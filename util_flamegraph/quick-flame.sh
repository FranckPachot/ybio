# record perf samples during 1 minutes (run on the yugabyte server while the program is running)
sudo perf record --call-graph fp -F99 -e cpu-cycles -a sleep ${SLEEP:-60}
# get Brendan Gregg flamegraph tool
type git || sudo yum install -y git perl-open.noarch
git clone https://github.com/brendangregg/FlameGraph.git
# get my color map for YugabyteDB and PostgreSQL functions
wget -c https://raw.githubusercontent.com/FranckPachot/ybio/main/util_flamegraph/palette.map
# generate flamegraph on the recorded perf.data as perf.svg
sudo perf script -i perf.data | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl --colors green --width=1200 --hash --cp | tee perf.svg && chmod a+r perf.svg
# here is how to share it though internet:
echo $(curl -L --upload-file perf.svg http://transfer.sh/$(date +%Y%m%dT%H%M%S).svg)
# the url displayed can be opened publicly
