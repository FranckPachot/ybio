export PGHOST PGUSER PGPASSWORD PGDATABASE PGPORT

# create setup() and runit() procedures, and the benchruns table:
psql -e < ybio.sql
# create two tables:
for i in {1..4} ; do psql <<<"call setup(tab_prefix=>'bench',tab_num=>${i},tab_rows=>1e7::int,batch_size=>100000);" & done ; wait
#
for i in {1..4} ; do psql <<<"call runit(tab_prefix=>'bench',tab_num=>${i},tab_rows=>1e7::int,batch_size=>1000,run_duration=>interval '1 hour',pct_update=>10);" & done ; wait

# for YugabyteDB you can look at http://${PGHOST}:7000/tablet-servers to watch Read/Write ops/sec

# check results:
psql <<'SQL'
select end_time-start_time duration,round(num_rows/extract(epoch from end_time-start_time)) riops
,round(100*max_scratch::float/table_scratch) as pct_scratch
, case when num_rows > table_rows then lpad(to_char(num_rows::float/table_rows,'xfmB9990D9'),6) 
  else lpad(to_char(100*num_rows/table_rows,'fmB999 %'),6) end coverage
,* from benchruns order by job_id desc nulls last limit 10;
SQL
