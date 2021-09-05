drop table if exists ysql_metrics;
create table if not exists ysql_metrics (snaptime timestamp,hostname text,source text,metrics jsonb, primary key(hostname hash,snaptime asc));
drop function ysql_metrics;
create or replace function ysql_metrics() returns table(seconds bigint,hostname text,source text,name text,rows bigint,calls bigint,msecs float,row_per_sec bigint) as $func$
begin
perform pg_sleep(1);
copy ysql_metrics(snaptime,hostname,source,metrics) 
from program $copy$curl -s http://localhost:13000/metrics | jq -c '.[] | select (.type="server") | .metrics' | sed -e "s/^/`date +"%Y-%m-%d %H:%M:%S"`\t`hostname`\tYSQL server\t/" $copy$ with (rows_per_transaction 0);
return query with snaps as (
select v.snaptime,v.hostname,v.source,replace(m.name,'handler_latency_yb_ysqlserver_SQLProcessor_','') "name"
,m.rows-lag(m.rows) over w "rows",m.count-lag(m.count) over w "count",m.sum-lag(m.sum) over w "sum"
,extract(epoch from v.snaptime-lag(v.snaptime) over w) seconds, max(v.snaptime) over () last_snaptime
from ysql_metrics v, jsonb_to_recordset(v.metrics) as m("name" text,"count" bigint,"rows" bigint,"sum" bigint)
window w as (partition by v.hostname,v.source,m.name order by snaptime)
), last as (
select v.seconds::bigint,v.hostname,v.source,v.name,v.rows::bigint,v.count::bigint,v.sum/1000::float "sum/1e3"
,(v.rows/v.seconds)::bigint row_per_sec
from snaps v where v.snaptime=v.last_snaptime and v.count>0 
) select * from last v order by v.name;
end;
$func$ language plpgsql;

drop table if exists demo;
select * from ysql_metrics();
create table demo as select * from generate_series(1,10000) id;
select * from ysql_metrics();
update demo set id=id+10000 where id<=3000;
select * from ysql_metrics();
delete from demo where id >=5000;
select * from ysql_metrics();
select count(*) from demo;
select * from ysql_metrics();


