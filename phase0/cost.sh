#!/usr/bin/env bash
# cost.sh <patched drrun>: wall time and max RSS, median of 10, ~100 threads, per DR mode.
source "$(dirname "$0")/lib.sh"
PD=$1
dr_install >/dev/null
cd "$WK"; duckdb_get >/dev/null || exit 1
[ -x gomin ] || ( cd "$P0/src/gomin" && CGO_ENABLED=0 go build -o "$WK/gomin" main.go )
R=$OUT/cost.tsv; printf 'workload\tmode\tmedian_s\tmedian_rss_mb\n' > "$R"
one() { local w=$1 m=$2; shift 2; local pre=()
  case $m in native) ;; stock) pre=("$DRRUN" --);; thread_private) pre=("$DRRUN" -thread_private --);; patched) pre=("$PD" --);; esac
  for i in $(seq 1 10); do /usr/bin/time -f '%e %M' -a -o t.$$ timeout -s KILL 300 "${pre[@]}" "$@" >/dev/null 2>&1; done
  local s rss; s=$(cut -d' ' -f1 t.$$ | sort -n | sed -n 5p); rss=$(cut -d' ' -f2 t.$$ | sort -n | sed -n 5p); rm -f t.$$
  printf '%s\t%s\t%s\t%s\n' "$w" "$m" "$s" "$((rss/1024))" | tee -a "$R"; }
for m in native stock thread_private patched; do
  one go.threads100 $m ./gomin threads
  one duckdb.select1 $m ./duckdb -c "select 1"
  one duckdb.threads100 $m ./duckdb -c "set threads=100; select sum(i) from range(300000000) t(i)"
done
{ echo "### cost"; echo; cat "$R"; } >> "$SUM"
