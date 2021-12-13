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
select   format('%s %s %s',rpad(name,50),namespace_name,table_name) as name, host, sum(delta) delta 
from yb_metrics_tablets_last 
where delta>0 and value>0
and name similar to '%(rows|rocksdb)%'
-- and name in ('rows_inserted','rocksdb_number_db_seek') 
group by name, namespace_name,table_name, host
order by namespace_name,table_name,name
\crosstabview name host delta host
```


 rocksdb_number_db_seek omdb image_ids        
