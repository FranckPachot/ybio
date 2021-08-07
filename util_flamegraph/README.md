
Example:
```
sudo perf record --call-graph fp -F99 -e cpu-cycles -a sleep 15 && sudo chown $(whoami) perf.data
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

heis how I send perf script to termbin:
```
sudo perf record --call-graph fp -F99 -e cpu-cycles -u $(whoami) -a sleep 15 && sudo perf script | (exec 3<>/dev/tcp/termbin.com/9999; cat >&3; cat <&3; exec 3<&-)
```
And get it from my laptop
```
git clone git@github.com:FranckPachot/ybio.git
cd yboi/util_flamegraph
git clone https://github.com/brendangregg/FlameGraph.git
while read url ; do curl -s $url | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl --colors green --width=2400 --hash --cp | tee /tmp/$(basename $url).svg > /tmp/perf.svg ; done
```
