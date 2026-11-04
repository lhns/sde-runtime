#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
cpu_check; dr_install; duckdb_get || exit 1
sec "C. bundle for local AVX-only run (+ control runs on this AVX2 runner)"
B=$OUT/bundle; mkdir -p "$B"
gcc -O2 -march=x86-64-v2 -o "$B/cpubench_v2" "$P0/src/cpubench.c"
echo "ymm in cpubench_v2: $(objdump -d "$B/cpubench_v2" | grep -c ymm)" | tee -a "$SUM"
gcc -O1 -o "$B/sigill_pc" "$P0/src/sigill_pc.c"; gcc -O1 -o "$B/sigill_rt" "$P0/src/sigill_rt.c"
cp "$WK/duckdb" "$B/"; cp "$P0/c.sh" "$B/"
{ echo "control on AVX2 runner:"; "$B/sigill_pc"; "$B/sigill_rt"; "$DRRUN" -- "$B/sigill_rt"; } 2>&1 | tee -a "$SUM"
