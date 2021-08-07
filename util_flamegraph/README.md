
Example:
```
sudo perf record --call-graph fp -F99 -e cpu-cycles -u $(whoami) -a sleep 15 && sudo chown $(whoami) perf.data
perf script -i perf.data | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl --colors green --width=2400 --hash --cp | tee perf.svg 

```
with ybio
```
psql -h localhost -p 5433 -U yugabyte yugabyte < ../ybio.sql
psql -h localhost -p 5433 -U yugabyte yugabyte <<< "call setup()" & sleep 10
sudo perf record --call-graph fp -F10 -e cpu-cycles -a sleep 120 && sudo chown $(whoami) perf.data
perf script -i perf.data | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl --colors green --width=1200 --hash --cp | tee perf.svg 
wait
psql -h localhost -p 5433 -U yugabyte yugabyte <<< "call runit(run_duration=>interval'3 minutes',batch_size=>100000)" & sleep 10
sudo perf record --call-graph fp -F10 -e cpu-cycles -a sleep 120 && sudo chown $(whoami) perf.data
perf script -i perf.data | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl --colors green --width=1200 --hash --cp | tee perf.svg 
wait
psql -h localhost -p 5433 -U yugabyte yugabyte <<< "call runit(run_duration=>interval'3 minutes',batch_size=>10)" & sleep 10
sudo perf record --call-graph fp -F10 -e cpu-cycles -a sleep 120 && sudo chown $(whoami) perf.data
perf script -i perf.data | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl --colors green --width=1200 --hash --cp | tee perf.svg 
wait
psql -h localhost -p 5433 -U yugabyte yugabyte <<< "call runit(run_duration=>interval'3 minutes',pct_update=>100)" & sleep 10
sudo perf record --call-graph fp -F10 -e cpu-cycles -a sleep 120 && sudo chown $(whoami) perf.data
perf script -i perf.data | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl --colors green --width=1200 --hash --cp | tee perf.svg 

```
