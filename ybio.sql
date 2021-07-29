/* 
 * This work is porting PGIO (https://github.com/therealkevinc/pgio) 
 * to be run from PL/pgSQL only. The idea follows Kevin Closson SLOB method
 *  (https://kevinclosson.net/slob/) where we focus on the component we want
 * to benchmark. For example, if we want to measure the read path down to disk
 * (PGIO - Physical IO) we will run a workload that will get random rows on a
 * working set that is larger than the available memory. And avoid any other
 * work (network calls, query parsing, reading through a large document,...
 * 
 * We have two procedures create there:
 *  - setup() will create tables of the required size
 *  - runit() will run the benchmark for the specified time
 * and one table:
 *  - benchruns will store the runs results
 */

--\set ON_ERROR_STOP on

drop procedure if exists setup;

--\df setup;

/*
 * SETUP
 * As we may want that each session reads its own table, or the same table (if what
 * we want to test is concurrent access) we have a table name prefix and a number. The
 * default will create bench0001. We insert in several batches to fill a total number
 * of rows. Rows have a "mykey" int column, indexed, which is the one we will query.
 * The "scratch" column is random to be sure to scatter rows within the table. The 
 * "filler" just adds some bytes to it.
 */

create or replace procedure setup(
   -- table name is built from prefix + number
   tab_prefix text default 'bench',
   tab_num int default 1,
   -- number of table rows to insert
   tab_rows bigint default 1e6,
   -- rows are inserted by batch (0 will default thousand rows batches)
   batches bigint default 0,
   -- split into tablets (0 means the default)
   tablets int default 0,
   -- filler characters (not very useful here)
   filler int default 1,
   -- drops the table to recreate it
   recreate boolean default true
) language plpgsql as
$setup$
begin
  -- by default we do batches of 1000 rows but only one batch if the number of rows is smaller
  if batches = 0 then batches:=ceil(tab_rows/1000); end if;
  -- there's a flag to drop the existing tables	
  if recreate then execute format('drop table if exists %I',tab_prefix||to_char(tab_num,'fm0000')); end if;
  -- create the table
  execute format('create table if not exists %I (mykey bigint, scratch bigint, filler char(%s)) %s',tab_prefix||to_char(tab_num,'fm0000'),filler,case tablets when 0 then '' else format('split into %s tablets',tablets)end);
  -- index the table on mykey (could be done afterwards but I like homogenous work)
  execute format('create index if not exists %I_asc_mykey on %I(mykey asc)',tab_prefix||to_char(tab_num,'fm0000'),tab_prefix||to_char(tab_num,'fm0000'));
  -- insert rows in several passes
  raise notice 'Inserting % rows in % batches of %',tab_rows,batches,ceil(tab_rows/batches);
  for i in 1..batches loop
    -- generate numbers and shuffle them with the random scratch
    execute format('insert into %I 
     select generate_series::bigint*%s+%s mykey, (random()*%s)::bigint as scratch , lpad(%L,%s,md5(random()::text)) filler 
     from generate_series(1,%s) order by scratch'
    ,tab_prefix||to_char(tab_num,'fm0000'),batches,i,tab_rows,'',filler,ceil(tab_rows/batches));
    -- output a message for each loop
    raise notice 'Table % Progress: % % (% rows)',tab_prefix||to_char(tab_num,'fm0000'),to_char((100*(i::float)/batches),'999.99'),'%',i*tab_rows/batches;
    -- intermediate commit for each batch
    commit;
    end loop;
END; $setup$;

/* the results of the runs will be stored in a "benchruns" table 
 * where the most interesting will be:
 *  num_rows/extract(epoch from end_time-start_time)
 * the number or rows read per second
 */

drop table if exists benchruns;

create table benchruns(job_id serial,start_time timestamp, end_time timestamp
,num_batches int, num_rows bigint, pct_update int, max_scratch bigint
, prepared boolean, index_only boolean, tab_rows int, batch_size int
,table_name text, table_rows bigint, table_scratch bigint
, primary key(job_id));

/*
 * RUNIT
 *  This will be called by one session, specifying the table it works on, with "tab_num"
 * and the number of rows: it will read at random some rows between 1 and "tab_rows"
 * (so "tab_rows" must be equal or lower than the one used to create the table)
 *  In order to focus on reading rows, we range scan an index on "mykey" where we know
 * that rows are scattered in all table, to get "batch_size" rows for each execution of
 * the select. A large "batch_size" avoids to spend time on other layers than read rows.
 */

drop procedure if exists runit;

create or replace procedure runit(
   -- table name is built from prefix + number
   tab_prefix text default 'bench',
   tab_num int default 1,
   -- random reads will be done on [1..table_rows] id (must have enough rows in the table)
   tab_rows   bigint default 1e6,
   -- each execute will read batch_size random rows in the range scan
   batch_size bigint default 1e4,
   -- the job stops after run_duration
   run_duration interval default interval '1 minute',
   -- precent of updates
   pct_update int default 0,
   -- prepared statements by default (see https://dev.to/aws-heroes/postgresql-prepared-statements-in-pl-pgsql-jl3)
   prepared boolean default true,
   -- doesn't read more columns than the index one if index_only
   index_only boolean default false,
   -- starts by counting the rows (and verifies tab_rows)
   initial_count boolean default false   
) language plpgsql as
$runit$ <<this>>
declare
 clock_start timestamp;
 clock_end timestamp;
 job_id int:=null;
 num_rows float:=0;
 num_updated float:=0;
 num_batches int:=0;
 out_count int;
 out_scratch bigint;
 max_scratch bigint:=0;
 sql_select text;
 sql_update text;
 first_key int;
begin
  -- the batch size cannot be larger than the number or rows (num_rows should be a multiple actually)
  if batch_size > tab_rows then batch_size:=tab_rows; end if;
  -- we can try an index_only access path if we want to range scan the index only
  if index_only then
   sql_select:='select count(*),max(mykey) from %I where mykey between $1 and $2';
   sql_update:='with u as (update %I set mykey=mykey where mykey between $1 and $2 returning 1,mykey) select count(*),max(mykey) from u';
  else
   sql_select:='select count(*),max(scratch)  from %I where mykey between $1 and $2';
   sql_update:='with u as (update %I set scratch=scratch+1 where mykey between $1 and $2 returning 1,scratch) select count(*),max(scratch) from u';
  end if;
  -- start: count rows in the table (if flag for this - can take time)
  if initial_count then
   execute format('select count(*),max(scratch) from "%I"',tab_prefix||to_char(tab_num,'fm0000')) into strict out_count,out_scratch;
   if out_rows < tab_rows then raise exception 'Cannot read % rows from a % rows table',tab_rows,out_rows; end if;
  end if;
  -- insert info about this run
  insert into benchruns(start_time, prepared,index_only,tab_rows,pct_update,batch_size,table_name,table_rows,table_scratch) 
     values (clock_timestamp(),runit.prepared,runit.index_only,runit.tab_rows,runit.pct_update,runit.batch_size,tab_prefix||to_char(tab_num,'fm0000'),out_count,out_scratch) 
     returning benchruns.job_id into this.job_id;
    commit;
    if prepared then
     --deallocate all;
     execute 'prepare myselect(integer,integer) as '||format(sql_select,tab_prefix||to_char(tab_num,'fm0000'));
     execute 'prepare myupdate(integer,integer) as '||format(sql_update,tab_prefix||to_char(tab_num,'fm0000'));
    end if; 
    clock_start= clock_timestamp();
    clock_end := clock_start + run_duration ;   
  loop
   first_key:=trunc(random()*((tab_rows-batch_size)-1)+1);
   if (pct_update=100) or (100*(num_updated+0.5*batch_size)/(num_rows+batch_size)<pct_update) then
    -- UPDATE:
    if prepared then
     execute format('execute myupdate(%s,%s)',first_key,first_key+batch_size-1) into strict out_count,out_scratch;
    else
     execute format(sql_update,tab_prefix||to_char(tab_num,'fm0000')) into out_count,out_scratch using first_key,first_key+batch_size-1;
    end if;
    num_updated:=num_updated+out_count;
   else
    -- SELECT:
    if prepared then
     execute format('execute myselect(%s,%s)',first_key,first_key+batch_size-1) into strict out_count,out_scratch;
    else
     execute format(sql_select,tab_prefix||to_char(tab_num,'fm0000')) into out_count,out_scratch using first_key,first_key+batch_size-1;
    end if;
   end if;
   num_batches=num_batches+1;
   num_rows=num_rows+out_count;
   if out_scratch>max_scratch then max_scratch=out_scratch; end if;
   exit when clock_timestamp() >= clock_end;
   raise notice '% rows/s on %, job: % batch#: %, total: % rows read, % % updated, last: % rows between  % and %'
    ,to_char(round(num_rows/extract(epoch from clock_timestamp()-clock_start)),'9999999') -- RIOPS from start
    ,tab_prefix||to_char(tab_num,'fm0000') -- table name
    ,to_char(job_id,'99999') -- job number
    ,to_char(num_batches,'9999') -- number of iterations from start
    ,to_char(num_rows,'99999999999') -- total number of rows read
    ,to_char(100*num_updated/num_rows,'999D9'),'%' -- percentage updated
    ,(out_count) -- number of rows read
    ,(first_key+batch_size-1) -- the between range end
    ,(first_key) -- the between range start
   ;
  end loop;
    if prepared then
     deallocate myselect;
     deallocate myupdate;
    end if;
    update benchruns 
   set start_time=this.clock_start
     , end_time=clock_timestamp()
     , num_rows=this.num_rows
     , num_batches=this.num_batches
     , max_scratch=this.max_scratch
     where benchruns.job_id=this.job_id;
   commit; 
END; $runit$;
