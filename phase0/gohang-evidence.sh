#!/usr/bin/env bash
# gohang-evidence.sh: run Go under DR until one hangs, snapshot it, then kill. VARIANT=release|debug
source "$(dirname "$0")/lib.sh"
V=${VARIANT:-release}
dr_install
sudo apt-get install -y -qq gdb strace >/dev/null 2>&1
cd "$WK"; E=$OUT/evidence-$V; mkdir -p "$E"
( cd $P0/src/gomin && CGO_ENABLED=0 go build -o "$WK/gomin" main.go )
ls "$DR/lib64" | tee "$E/lib64-ls.txt"; ls "$DR/lib64/debug" 2>&1 | tee -a "$E/lib64-ls.txt"
FL=""; [ "$V" = debug ] && FL="-debug"
snap() { # pid label
  local p=$1 f=$E/snap-$2.txt
  { echo "## status"; cat /proc/$p/status; echo "## ps threads"; ps -L -o pid,tid,stat,pcpu,wchan:30,comm -p $p
    for t in /proc/$p/task/*; do echo "## task $(basename $t) $(cat $t/comm)"; echo "stat: $(cut -d' ' -f3,14,15 $t/stat)"; echo "wchan: $(cat $t/wchan)"; echo "syscall: $(sudo cat $t/syscall)"; echo "stack:"; sudo cat $t/stack; done
    echo "## maps (dynamorio + stacks)"; grep -E 'dynamorio|stack|vdso' /proc/$p/maps
    echo "## per-thread signal state"; for t in /proc/$p/task/*; do echo "$(basename $t) $(grep -E '^(SigPnd|SigBlk)' $t/status | tr '
	' '  ')"; done
    echo "## sigmask/pending"; grep -E 'Sig|Shd' /proc/$p/status; } > "$f" 2>&1
}
for a in $(seq 1 40); do
  $DRRUN $FL -- ./gomin spin >"$E/out.$a" 2>"$E/err.$a" & dp=$!
  sleep 25
  if kill -0 $dp 2>/dev/null; then
    echo "HANG on attempt $a (variant $V)"; echo "attempt $a" > "$E/hung"
    pids=$(pgrep -f '^\./gomin|gomin$' | tr '\n' ' '); echo "pids: $pids $dp" | tee "$E/pids.txt"
    for p in $pids; do snap $p t0-$p; done
    sleep 5; for p in $pids; do snap $p t5-$p; done   # CPU delta: compare utime/stime in stat lines
    for p in $pids; do sudo timeout 120 gdb -batch -p $p -ex 'set pagination off' -ex 'info threads' -ex 'thread apply all bt 25' -ex 'info registers rip rsp' -ex 'thread apply all x/12i $pc' > "$E/gdb-$p.txt" 2>&1; done
    for p in $pids; do sudo timeout 8 strace -f -tt -e trace=tgkill,tkill,rt_sigreturn,rt_sigaction,rt_sigprocmask,futex -p $p > "$E/strace-$p.txt" 2>&1; done
    for p in $pids; do kill -QUIT $p 2>/dev/null; done; sleep 3   # Go goroutine dump, if the runtime can still run
    cp "$E/err.$a" "$E/err-after-sigquit.txt"; cp "$E/out.$a" "$E/out-hung.txt"
    pkill -9 -f gomin; break
  fi
  wait $dp
done
ls "$WK"/../dr/DynamoRIO-Linux-*/logs 2>/dev/null | head
{ echo "### evidence ($V)"; ls "$E"; cat "$E/hung" 2>/dev/null || echo "no hang in 40 attempts"; } >> "$SUM"; cat "$SUM"
