#!/usr/bin/env bash
# exitrace.sh native|stock|fork: capped clone-at-exit race N times, then one uncapped run in a
# cgroup (so the runner survives) sampling threads and memory, to show what the cap prevents.
source "$(dirname "$0")/lib.sh"
SIDE=$1; CAP=${CAP:-256}; N=${N:-300}; T=${T:-60}; PAR=${PAR:-2}
FORK_BRANCH=${FORK_BRANCH:-fix-pending-signal-self-link}
PRE=""; cd "$ROOT"
if [ "$SIDE" = fork ]; then
  sudo apt-get update -qq; sudo apt-get install -y -qq cmake g++ zlib1g-dev libsnappy-dev liblz4-dev libunwind-dev >/dev/null
  git clone -q --depth 1 -b $FORK_BRANCH https://github.com/lhns/dynamorio.git drsrc
  git -C drsrc submodule update -q --init --depth 1 --recommend-shallow
  git -C drsrc log --oneline -1 | tee "$OUT/source.txt"
  cmake -S drsrc -B drbuild -DDEBUG=OFF -DBUILD_TESTS=OFF -DBUILD_DOCS=OFF -DBUILD_SAMPLES=OFF -DBUILD_CLIENTS=OFF >/dev/null 2>&1 || exit 1
  cmake --build drbuild -j4 >/dev/null 2>&1 || exit 1
  PRE="$ROOT/drbuild/bin64/drrun --"
elif [ "$SIDE" = stock ]; then
  dr_install; PRE="$DRRUN --"
fi
gcc -O1 -pthread -o "$WK/exitrace" "$P0/src/exitrace/exitrace.c" || exit 1
R=$OUT/$SIDE; mkdir -p "$R"; cd "$WK"
_one() { local i=$1 p w=0 peak=0 t rc
  $PRE ./exitrace $CAP >"$R/out.$i" 2>"$R/err.$i" & p=$!
  while kill -0 $p 2>/dev/null && [ $w -lt $((T*10)) ]; do
    t=$(ls /proc/$p/task 2>/dev/null | wc -l); [ "$t" -gt "$peak" ] && peak=$t; sleep 0.1; w=$((w+1)); done
  if kill -0 $p 2>/dev/null; then echo "$i threads=$(ls /proc/$p/task | wc -l)" >> "$R/hangs"
    { ls /proc/$p/task | wc -l; sudo cat /proc/$p/task/*/syscall | cut -d' ' -f1 | sort | uniq -c; sudo cat /proc/$p/task/*/stack | sort | uniq -c | sort -rn | head -20; } > "$R/snap.$i" 2>&1
    kill -9 $p; fi
  wait $p 2>/dev/null; rc=$?; echo "$rc" >> "$R/rcs"; echo "$w $peak $(cat "$R/out.$i")" >> "$R/runs"
  [ $rc = 0 ] && rm -f "$R/err.$i"; rm -f "$R/out.$i"; }
export -f _one; export PRE T R CAP
seq 1 "$N" | xargs -P "$PAR" -I{} bash -c '_one {}'
h=0; [ -f "$R/hangs" ] && h=$(wc -l < "$R/hangs")
{ echo "### exitrace $SIDE cap=$CAP: hangs $h/$N (timeout ${T}s)"; sort "$R/rcs" | uniq -c
  sort -n "$R/runs" | awk 'NR==1{print "fastest (0.1s ticks, peak threads, out):",$0} {l=$0} END{print "slowest:",l}'; } | tee -a "$SUM"
# Uncapped once, in a cgroup so memory or task exhaustion cannot starve the runner.
sudo systemd-run --scope -q -p MemoryMax=8G -p TasksMax=20000 -p MemorySwapMax=0 --uid="$(id -u)" --gid="$(id -g)" -- \
  timeout -k 5 90 $PRE ./exitrace 0 >"$R/uncapped.out" 2>"$R/uncapped.err" & up=$!
for s in $(seq 1 95); do sleep 1
  p=$(pgrep -n -f '[.]/exitrace 0'); [ -n "$p" ] || continue
  echo "$s threads=$(ls /proc/$p/task 2>/dev/null | wc -l) maps=$(sudo wc -l < /proc/$p/maps) rssKB=$(awk '/VmRSS/{print $2}' /proc/$p/status 2>/dev/null) vmKB=$(awk '/VmSize/{print $2}' /proc/$p/status 2>/dev/null) availKB=$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
  kill -0 $up 2>/dev/null || break
  [ $s = 30 ] && { sysctl vm.max_map_count; sudo cat /proc/$p/task/*/syscall | cut -d' ' -f1 | sort | uniq -c | sort -rn | head -8; sudo cat /proc/$p/task/*/stack | sort | uniq -c | sort -rn | head -12; } > "$R/uncapped.hang" 2>&1
done > "$R/uncapped.samples"
wait $up; echo "uncapped rc=$?" | tee -a "$SUM"
awk 'NR%10==1' "$R/uncapped.samples" | tee -a "$SUM"; tail -3 "$R/uncapped.samples" | tee -a "$SUM"; tail -5 "$R/uncapped.err" | cut -c1-300 | tee -a "$SUM"; cat "$R/uncapped.out" | tee -a "$SUM"
cat "$R/uncapped.hang" | cut -c1-120 | tee -a "$SUM"; sudo dmesg | grep -iE 'oom|killed|map_count' | tail -5 | cut -c1-200 | tee -a "$SUM"
