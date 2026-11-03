#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
cpu_check; dr_install; duckdb_get || exit 1
sec "D. instruction density (duckdb 2.0.0)"
cd "$WK"
size "$WK/duckdb" | tee -a "$OUT/d.txt"
objdump -d -j .text --no-show-raw-insn "$WK/duckdb" > text.dis 2>"$OUT/objdump.err"
{ echo "#### static, objdump of .text (all instructions, not execution-weighted; ymm operand => AVX2 int for vp*)"; python3 "$P0/classify.py" static text.dis; } | tee -a "$SUM"
# dynamic: DR opcode_mix via drcachesim
Q_FULL="select sum(range*range) from range(3000000)"
for q in "select 42" "$Q_FULL"; do
  n=$(echo "$q" | md5sum | cut -c1-6)
  echo "--- opcode_mix: $q"
  ( time timeout 2400 "$DRRUN" -t drcachesim -simulator_type opcode_mix -- "$WK/duckdb" -c "$q" ) > "opmix-$n.txt" 2>&1
  tail -5 "opmix-$n.txt"
  if ! grep -qE '^\s*[0-9]+\s*:\s*[a-z]' "opmix-$n.txt"; then
    echo "online failed or unparsable; trying offline"
    rm -rf drmem.*; ( time timeout 2400 "$DRRUN" -t drcachesim -offline -outdir "$WK/tr-$n" -- "$WK/duckdb" -c "$q" ) > "offline-$n.txt" 2>&1; tail -3 "offline-$n.txt"
    ( time timeout 2400 "$DRRUN" -t drcachesim -indir "$WK"/tr-$n/drmemtrace.* -simulator_type opcode_mix ) > "opmix-$n.txt" 2>&1; tail -5 "opmix-$n.txt"
  fi
  cp "opmix-$n.txt" "$OUT/opmix-$n.txt"
  { echo "#### dynamic (DR opcode_mix, mnemonic-only classification), query: \`$q\`"; python3 "$P0/classify.py" dynamic "opmix-$n.txt"; } | tee -a "$SUM"
done
