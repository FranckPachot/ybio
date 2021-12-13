
/*
   raw metrics are stored in yb_metrics_json
   with one row per snap / server
*/


drop table if exists yb_metrics_json cascade;

create table yb_metrics_json(
 snap_time timestamp, host text, metrics jsonb
 , primary key(host hash, snap_time desc)
);

/*
   yb_metrics_snap() read metrics from
   all servers to store them as json
*/

create or replace procedure yb_metrics_snap()
language plpgsql as $yb_metrics$
declare
 _server record;
 _copy text;
 _time timestamp:=now();
 r refcursor;
begin
    perform pg_sleep(1);
    for _server in (select * from yb_servers()) loop
     _copy:=format($copy$ copy yb_metrics_json(metrics,host,snap_time) from program $program$
         exec 5<>/dev/tcp/%s/9000
         echo -e "GET /metrics HTTP/1.1\n">&5
         awk '/[[]/{d=1}d>0{printf $0}END{print "\t%s\t%s"}' <&5
     $program$ with (rows_per_transaction 0) 
     $copy$,_server.host,_server.host,_time);
     --raise info '%',_copy;
     execute _copy;
    end loop;
end;
$yb_metrics$;
;

/*
   yb_metrics_tablets_last is a view to display
   the delta values from the last two snaps
*/

create or replace view yb_metrics_tablets_last as
with
last_metrics as(
 select * from  (
  select host,snap_time,metrics
  ,dense_rank() over snap_window as snap
  from yb_metrics_json
  window snap_window as (order by snap_time desc)
 ) json_metrics
 where snap<=2 --> the last two snapshots only
),
tserver_metrics as (
select host,snap,snap_time
 ,m->>'id' as id
 ,m->>'type' as type
 ,m->'attributes'->>'namespace_name' as namespace_name
 ,m->'attributes'->>'table_name' as table_name
 ,m->>'metrics' as metrics
 from last_metrics,jsonb_array_elements(metrics) m
),
tablet_metrics as (
 select 
 host, snap,snap_time,id,type,namespace_name,table_name
 ,m->>'name' as name
 ,m->>'value' as value
 from tserver_metrics,jsonb_array_elements(metrics::jsonb) m
 where type='tablet'
),
metrics_delta as (
select 
 snap,snap_time,host,id,namespace_name,table_name,name,value::float as value
 ,value::float-lead(value::float) over snap_window as delta
 ,extract(epoch from snap_time-lead(snap_time) over snap_window) as seconds
from tablet_metrics
--where name like '%inserted%' 
window snap_window as (partition by host,type,id,namespace_name,table_name,name order by snap_time desc)
)
select snap_time,host,namespace_name,table_name,id,name,value,delta,seconds::int
 ,sum(value) over tablew /count(*) over tabletw as value_table
 ,sum(delta) over tablew /count(*) over tabletw as delta_table
 ,round(value/seconds) "/s" from metrics_delta 
where seconds>0 and value>0 and (namespace_name,table_name) not in (('yugabyte','yb_metrics_json'),('system','metrics'))
window tabletw as (partition by id,namespace_name,table_name),tablew as (partition by namespace_name,table_name)
order by snap_time desc,value;

/*
   yb_metrics_tablets_last is a view to display
   the delta values from the last two snaps
*/

call yb_metrics_snap(); 
call yb_metrics_snap(); 

call yb_metrics_snap(); select * from yb_metrics_tablets_last where delta>0;


