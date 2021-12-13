## create yb_metrics objects

```
\! wget -qc https://raw.githubusercontent.com/FranckPachot/ybio/main/util_metrics/yb_metrics_snap.sql
\i yb_metrics_snap.sql
```

## gather metrics snapshots

```
call yb_metrics_snap(); 
```

## gather metrics snapshots and show report

```
call yb_metrics_snap(); 
select * from yb_metrics_tablets_last where delta>0;
```

## show delta per server
```
select   format('%s %s %s',name,namespace_name,table_name) as name, host, sum(delta) delta 
from yb_metrics_tablets_last where name='rows_inserted' and delta>0 and value>0
group by name,id, namespace_name,table_name, host
\crosstabview name host delta
```
