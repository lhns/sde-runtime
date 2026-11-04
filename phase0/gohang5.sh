#!/usr/bin/env bash
# gohang5.sh patched|thread_private|native: residual Go hang rate, snapshot of each hang.
source "$(dirname "$0")/lib.sh"
MODE=$1; N=${N:-1000}; T=${T:-20}; PAR=${PAR:-2}
sudo apt-get update -qq; sudo apt-get install -y -qq cmake g++ zlib1g-dev libsnappy-dev liblz4-dev libunwind-dev gdb >/dev/null
dr_install
case $MODE in
  patched) git clone -q --depth 1 -b fix-pending-signal-self-link https://github.com/lhns/dynamorio.git "$ROOT/drsrc"
    git -C "$ROOT/drsrc" submodule update -q --init --depth 1 --recommend-shallow
    cmake -S "$ROOT/drsrc" -B "$ROOT/drbuild" -DDEBUG=OFF -DBUILD_TESTS=OFF -DBUILD_DOCS=OFF -DBUILD_SAMPLES=OFF -DBUILD_CLIENTS=OFF >/dev/null 2>&1 || exit 1
    cmake --build "$ROOT/drbuild" -j4 >/dev/null 2>&1 || exit 1
    PRE="$ROOT/drbuild/bin64/drrun --";;
  thread_private) PRE="$DRRUN -thread_private --";;
  stock) PRE="$DRRUN --";;
  native) PRE="";;
esac
cd "$WK"; R=$OUT/gohang5-$MODE; mkdir -p "$R"
( cd "$P0/src/gomin" && CGO_ENABLED=0 go build -o "$WK/gomin" main.go ) || exit 1
_one() { local i=$1 p w=0; $PRE ./gomin spin >"$R/out.$i" 2>"$R/err.$i" & p=$!
  while kill -0 $p 2>/dev/null && [ $w -lt $((T*10)) ]; do sleep 0.1; w=$((w+1)); done
  if kill -0 $p 2>/dev/null; then
    echo "$i" >> "$R/hangs"; local f=$R/snap.$i
    { ps -L -o tid,stat,pcpu,comm -p $p; cat /proc/$p/maps | grep -E 'dynamorio|rwx|r-x' | head -40
      sudo timeout 60 gdb -batch -p $p -ex 'set pagination off' -ex 'info threads' -ex 'thread apply all info registers rip rax rdi rsi rdx' -ex 'thread apply all bt 14'; } > "$f" 2>&1
    kill -QUIT $p; sleep 2; kill -9 $p 2>/dev/null; cp "$R/err.$i" "$f.goquit"; cp "$R/out.$i" "$f.stdout"
  fi; wait $p 2>/dev/null; rc=$?; echo $rc >> "$R/rcs"; rm -f "$R/out.$i"; [ -f "$R/snap.$i" ] || rm -f "$R/err.$i"; }
export -f _one; export PRE T R
seq 1 $N | xargs -P $PAR -I{} bash -c '_one {}'
h=0; [ -f "$R/hangs" ] && h=$(wc -l < "$R/hangs")
{ echo "### gohang5 $MODE: hangs $h/$N (timeout ${T}s)"; sort "$R/rcs" | uniq -c; } | tee -a "$SUM"
