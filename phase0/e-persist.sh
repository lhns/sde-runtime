#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
cpu_check; dr_install; duckdb_get || exit 1
sec "E. persistent code cache"
cd "$WK"
{
echo "--- docs lines mentioning persist"
grep -rhoiE '.{0,200}persist.{0,300}' "$DR/docs" 2>/dev/null | sed 's/<[^>]*>//g' | sort -u | head -60
echo "--- drrun -help persist"
"$DRRUN" -help 2>&1 | grep -i persist
echo "--- options docs (drrun -helpall)"
"$DRRUN" -helpall 2>&1 | grep -i -B1 -A3 persist | head -60
} > "$OUT/persist-docs.txt" 2>&1
head -60 "$OUT/persist-docs.txt"
mkdir -p "$WK/pcache"; T() { local s=$(date +%s.%N); "$@" >"$WK/pout" 2>"$WK/perr"; local rc=$?; echo "rc=$rc wall=$(echo "$(date +%s.%N) - $s" | bc) out=$(head -c 80 "$WK/pout" | tr '\n' ' ') err=$(head -c 300 "$WK/perr" | tr '\n' ' ')"; }
{
echo "--- baseline no persist"; for i in 1 2 3; do T "$DRRUN" -- ./duckdb -c "select 42"; done
for ops in "-persist" "-persist -persist_dir $WK/pcache" "-persist_dir $WK/pcache -use_persisted"; do
  echo "--- -ops '$ops' (cold then warm)"; rm -rf "$WK/pcache"/*
  for i in 1 2 3; do T "$DRRUN" -ops "$ops" -- ./duckdb -c "select 42"; done
  ls -la "$WK/pcache" | head
done
echo "--- persistence tool (drcachesim/persist options present in this release?)"; ls "$DR/tools" "$DR/bin64" | head -50
} 2>&1 | tee "$OUT/persist-run.txt" | tee -a "$SUM"
