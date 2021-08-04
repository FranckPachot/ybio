Example:
```
sudo perf record --call-graph fp -F99 -e cpu-cycles -a sleep 15 && sudo chown $(whoami) perf.data
perf script -i perf.data | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl --colors green --width=2400 --hash --cp | tee perf.svg 

```
