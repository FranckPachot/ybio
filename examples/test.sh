export PGPASSWORD PGHOST PGPORT PGUSER PGDATABASE
ssh $PGHOST 2>/dev/null <<'SSH'
 df -Th /home/opc
 free -wh
SSH

psql -e < ybio.sql
psql -e <<< "call setup(tab_prefix=>'bench',tab_num=>1,tab_rows=>10000000);"

for u in 0 5 10 15 20
do
for b in 1 10 25 50 75 100 250 500 750 1000 2500 5000 7500 10000 25000 50000 75000 100000 250000 500000 750000 1000000
do
psql <<<"call runit(tab_prefix=>'bench',tab_num=>1,tab_rows=>1000000,run_duration=>interval '10 minutes',batch_size=>${b},pct_update=>${u});"
done
done
