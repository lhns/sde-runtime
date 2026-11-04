#!/usr/bin/env bash
# gohang4.sh: C reproducer (sigspin) and a really-1-P Go run. DR_PATCHED=<dir> tests a built DR.
source "$(dirname "$0")/lib.sh"
N=${N:-30}; T=${T:-60}; PAR=${PAR:-2}; ROUNDS=${ROUNDS:-200}
dr_install
[ -n "${DR_PATCHED:-}" ] && { DR=$DR_PATCHED; DRRUN=$DR/bin64/drrun; export DRRUN; }
cd "$WK"; R=$OUT/gohang4; mkdir -p "$R"; TSV=$R/table.tsv; : > "$TSV"
gcc -O1 -pthread -o sigspin "$P0/src/sigspin/sigspin.c" || exit 1
( cd "$P0/src/gomin" && CGO_ENABLED=0 go build -o "$WK/gomin" main.go && CGO_ENABLED=0 GOAMD64=v3 go build -o "$WK/gomin_v3" main.go ) || exit 1
_one() { local i=$1 d=$2 drf=$3 rc s; shift 3; s=$(date +%s.%N)
  if [ "$drf" = native ]; then timeout -s KILL $T "$@" >"$d/out.$i" 2>&1; rc=$?; else timeout -s KILL $T $DRRUN $drf -- "$@" >"$d/out.$i" 2>&1; rc=$?; fi
  echo "$rc $(echo "$(date +%s.%N) - $s" | bc)" > "$d/rc.$i"; }
export -f _one; export T DRRUN
runs() { local label=$1 drf=$2; shift 2
  local d=$R/$label; mkdir -p "$d"
  seq 1 $N | xargs -P $PAR -I{} bash -c '_one "$@"' _ {} "$d" "$drf" "$@" >/dev/null
  local h o a; h=$(cat "$d"/rc.* | awk '$1==3||$1==137' | wc -l); o=$(cat "$d"/rc.* | awk '$1!=0&&$1!=3&&$1!=137' | wc -l); a=$(cat "$d"/rc.* | awk '$1==0{s+=$2;n++} END{if(n)printf "%.3f",s/n}')
  printf '%s\t%s/%s\tother=%s\tavg_ok_s=%s\n' "$label" "$h" "$N" "$o" "$a" | tee -a "$TSV"; }
if [ -n "${PROOF:-}" ]; then
  runs c.default.n8 "" ./sigspin 8 $ROUNDS
  runs c.default.n2 "" ./sigspin 2 $ROUNDS
  runs c.disable_traces.n8 "-disable_traces" ./sigspin 8 $ROUNDS
  runs go.spin.default "" ./gomin spin
  runs go.spin_v3.default "" ./gomin_v3 spin
elif [ -z "${LOGONLY:-}" ]; then
  runs c.native.n1 native ./sigspin 1 $ROUNDS
  runs c.native.n8 native ./sigspin 8 $ROUNDS
  runs c.default.n1 "" ./sigspin 1 $ROUNDS
  runs c.default.n2 "" ./sigspin 2 $ROUNDS
  runs c.default.n8 "" ./sigspin 8 $ROUNDS
  runs c.thread_private.n8 "-thread_private" ./sigspin 8 $ROUNDS
  runs c.disable_traces.n8 "-disable_traces" ./sigspin 8 $ROUNDS
  runs go.spin1.default "" ./gomin spin1
  runs go.spin.default "" ./gomin spin
fi
{ echo "### gohang4 (N=$N, rounds=$ROUNDS)"; echo; echo '| case | hangs | other |'; echo '|---|---|---|'; awk -F'\t' '{printf "| %s | %s | %s |\n",$1,$2,$3}' "$TSV"; } >> "$SUM"
[ -n "${PROOF:-}" ] && { cat "$SUM"; exit 0; }
# Debug build with LOG_ASYNCH: the hung thread's last words name the mechanism.
E=$OUT/gohang4-log; mkdir -p "$E"; LD=$WK/drlogs
for a in $(seq 1 100); do
  rm -rf "$LD"; mkdir -p "$LD"
  timeout -s KILL 120 $DRRUN -debug -loglevel 3 -logmask 0x10 -logdir "$LD" -- ./sigspin 8 $ROUNDS 20 > "$E/out.txt" 2>&1; rc=$?
  [ $rc = 3 ] || continue
  echo "HANG on debug attempt $a" | tee -a "$SUM"; cat "$E/out.txt" | tee -a "$SUM"
  find "$LD" -name 'log.*' | tee "$E/logs.txt"
  for t in $(grep -o 'tid=[0-9]*' "$E/out.txt" | cut -d= -f2); do
    f=$(find "$LD" -name "log.*.$t.html" | head -1); echo "### hung tid $t: $f" >> "$E/hung.txt"; grep -a -n 'interrupted F\|delaying until\|record_pending\|receive_pending' "$f" | tail -n 12 >> "$E/hung.txt"
    id=$(grep -a 'for interrupted F' "$f" | tail -1 | sed 's/.*interrupted F//'); echo "last interrupted F=$id" >> "$E/hung.txt"
    grep -a -c "re-linking outgoing for interrupted F$id\$" $(find "$LD" -name 'log.*.html') >> "$E/hung.txt"
    for o in $(find "$LD" -name 'log.*.html'); do [ "$o" = "$f" ] || { echo "--- $o"; grep -a -n "interrupted F$id\$" "$o" | tail -n 3; }; done >> "$E/hung.txt"
  done
  break
done
cat "$SUM"
