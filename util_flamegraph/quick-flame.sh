sudo bash -c '
type perf || yum install -y perf wget
# record perf samples during 1 minutes (run on the yugabyte server while the program is running)
echo "Capturing for ${SLEEP:=60} seconds from $(date) ... "
perf record --call-graph fp -F99 -e cpu-cycles -a sleep ${SLEEP}
echo "... to $(date)"
# get Brendan Gregg flamegraph tool
type git || yum install -y git perl-open.noarch
git clone https://github.com/brendangregg/FlameGraph.git
# get my color map for YugabyteDB and PostgreSQL functions
wget -qc https://raw.githubusercontent.com/FranckPachot/ybio/main/util_flamegraph/palette.map
# generate flamegraph on the recorded perf.data as perf.svg
perf script -i perf.data | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl --colors green --width=1200 --hash --cp | tee perf.svg > /dev/null && chmod a+r perf.svg
# here is how to share it though internet:
echo $(curl -L --upload-file perf.svg http://transfer.sh/$(date +%Y%m%dT%H%M%S).svg)
# the url displayed can be opened publicly
'
