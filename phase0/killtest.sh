#!/bin/bash
# killtest.sh native|dr DRRUN DUCKDB drrun|app
mode=$1; DRRUN=$2; DD=$3; tgt=$4
Q="select sum(range*range) from range(5000000000)"
if [ "$mode" = native ]; then "$DD" -c "$Q" >/dev/null 2>&1 & else "$DRRUN" -- "$DD" -c "$Q" >/dev/null 2>&1 & fi
pid=$!; sleep 5
tp=$pid
if [ "$tgt" = app ]; then for p in /proc/[0-9]*; do [ "$(cat $p/comm 2>/dev/null)" = duckdb ] && tp=${p#/proc/}; done; fi
echo "alive_before=$(kill -0 $pid 2>/dev/null && echo 1 || echo 0) target=$tgt same_as_spawned=$([ $tp = $pid ] && echo 1 || echo 0)"
kill -TERM $tp; wait $pid; echo "rc=$?"
sleep 1; n=0; for p in /proc/[0-9]*; do [ "$(cat $p/comm 2>/dev/null)" = duckdb ] && n=$((n+1)); done; echo "leftover_duckdb=$n"
