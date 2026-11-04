#!/usr/bin/env bash
# flagrepro.sh: flag and result corruption reproducer: native, then stock DR with option variants.
source "$(dirname "$0")/lib.sh"
dr_install
grep -m1 "model name" /proc/cpuinfo | tee -a "$SUM"
gcc -O1 -o "$WK/flagrepro" "$P0/src/flagrepro/flagrepro.c" || exit 1
cd "$WK"
for v in "native" "dr" "dr -ro2sandbox_threshold 0" "dr -disable_traces"; do
  echo "### $v" | tee -a "$SUM"
  if [ "$v" = native ]; then ./flagrepro 2>&1 | tee -a "$SUM"; else "$DRRUN" ${v#dr} -- ./flagrepro 2>&1 | tee -a "$SUM"; fi
done
