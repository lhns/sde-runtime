#!/usr/bin/env bash
# gohang6.sh MODE: hang rate of a self-built DR with lock owners and stacks at each hang.
# MODE: side(patched|base|native)/drflag(-|flag)/gomin arg/GODEBUG(-|value)/binary suffix(-|_v3)
source "$(dirname "$0")/lib.sh"
IFS=/ read -r SIDE FLAG ARG GD SUF <<< "$1"
N=${N:-1000}; T=${T:-20}; PAR=${PAR:-2}; LABEL=$(echo "$1" | tr '/' '.')
FORK_BRANCH=${FORK_BRANCH:-fix-pending-signal-self-link}
sudo apt-get update -qq; sudo apt-get install -y -qq cmake g++ zlib1g-dev libsnappy-dev liblz4-dev libunwind-dev gdb >/dev/null
cd "$ROOT"; PRE=""
if [ "$SIDE" != native ]; then
  if [ "$SIDE" = patched ]; then git clone -q --depth 1 -b $FORK_BRANCH https://github.com/lhns/dynamorio.git drsrc
  else git clone -q --depth 1 -b $DR_TAG https://github.com/DynamoRIO/dynamorio.git drsrc; fi
  git -C drsrc submodule update -q --init --depth 1 --recommend-shallow
  git -C drsrc log --oneline -1 | tee -a "$OUT/source.txt"
  cmake -S drsrc -B drbuild -DDEBUG=OFF -DBUILD_TESTS=OFF -DBUILD_DOCS=OFF -DBUILD_SAMPLES=OFF -DBUILD_CLIENTS=OFF >/dev/null 2>&1 || exit 1
  cmake --build drbuild -j4 >/dev/null 2>&1 || exit 1
  [ "$FLAG" = - ] && PRE="$ROOT/drbuild/bin64/drrun --" || PRE="$ROOT/drbuild/bin64/drrun $FLAG --"
fi
[ "$GD" = - ] || export GODEBUG=$GD
cd "$WK"; R=$OUT/$LABEL; mkdir -p "$R"
( cd "$P0/src/gomin" && CGO_ENABLED=0 go build -o "$WK/gomin" main.go && CGO_ENABLED=0 GOAMD64=v3 go build -o "$WK/gomin_v3" main.go ) || exit 1
gcc -O1 -pthread -o "$WK/exitrace" "$P0/src/exitrace/exitrace.c" || exit 1
case $SUF in -) BIN=./gomin;; exitrace) BIN=./exitrace; ARG="";; *) BIN=./gomin$SUF;; esac
snap() { local p=$1 f=$2 t live
  { ps -L -o tid,stat,pcpu,comm -p $p
    for t in /proc/$p/task/*; do echo "## $(basename $t) $(cut -d' ' -f3,14,15 $t/stat)"; sudo cat $t/syscall; sudo cat $t/stack | head -12; done
    for live in $(ps -L -o tid=,stat= -p $p | awk '$2!~/^Z/{print $1}'); do echo "#### gdb tid $live"
      sudo timeout 60 gdb -batch -p $live -ex 'set pagination off' -ex 'print change_linking_lock' -ex 'print all_threads_synch_lock' -ex 'print uninit_thread_count' -ex 'print dynamo_exited' -ex 'info registers rip rsp' -ex 'x/6i $pc' -ex 'bt 24' 2>&1 | grep -v '^warning\|^\[\|^$'; done; } > "$f" 2>&1; }
_one() { local i=$1 p w=0 rc; $PRE $BIN $ARG >"$R/out.$i" 2>"$R/err.$i" & p=$!
  while kill -0 $p 2>/dev/null && [ $w -lt $((T*10)) ]; do sleep 0.1; w=$((w+1)); done
  if kill -0 $p 2>/dev/null; then
    echo "$i" >> "$R/hangs"; local f=$R/snap.$i
    snap $p "$f"; cp "$R/err.$i" "$f.err0"
    kill -QUIT $p; sleep 2; kill -9 $p 2>/dev/null; cp "$R/err.$i" "$f.err1"; cp "$R/out.$i" "$f.stdout"
  fi; wait $p 2>/dev/null; rc=$?; echo $rc >> "$R/rcs"; [ -f "$R/snap.$i" ] && echo "$rc" > "$R/snap.$i.rc"; rm -f "$R/out.$i" "$R/err.$i"; }
export -f _one snap; export PRE T R BIN ARG
seq 1 $N | xargs -P $PAR -I{} bash -c '_one {}'
h=0; [ -f "$R/hangs" ] && h=$(wc -l < "$R/hangs")
{ echo "### $LABEL: hangs $h/$N (timeout ${T}s)"; sort "$R/rcs" | uniq -c; } | tee -a "$SUM"
