# change the following to your database. This will drop and create tables starting with 'bench':
export PGHOST=yb1.pachot.net PGPORT=5433 PGUSER=franck PGDATABASE=yugabyte PGPASSWORD=PleaseDontBreakMyDB
# create setup() and runit() procedures, and the benchruns table:
psql -e ybio.sql
# create two tables:
for i in {1..2} ; do psql <<<"call setup(tab_prefix=>'bench',tab_num=>${i},tab_rows=>1e6::int);" ; done ; wait
#
for i in {1..2} ; do psql <<<"call runit(tab_prefix=>'bench',tab_num=>${i},tab_rows=>1e6::int,run_duration=>interval '1 minutes',pct_update=>5);" ; done ; wait
# you can look at http://${PGHOST}:7000/tablet-servers to watch Read/Write ops/sec
