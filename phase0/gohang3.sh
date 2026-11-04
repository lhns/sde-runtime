#!/usr/bin/env bash
# gohang3.sh direct|docker : confirm -thread_private / -no_early_inject, 100 runs each
source "$(dirname "$0")/lib.sh"
MODE=$1; N=${N:-100}; T=${T:-30}; PAR=${PAR:-2}
dr_install
cd "$WK"; R=$OUT/gohang3-$MODE; mkdir -p "$R"; TSV=$R/table.tsv; : > "$TSV"
( cd $P0/src/go && CGO_ENABLED=0 go build -o "$WK/go_static" main.go && CGO_ENABLED=0 GOAMD64=v3 go build -o "$WK/go_v3" main.go )
mkdir -p home
if [ "$MODE" = docker ]; then export W="docker run --rm -v $ROOT:$ROOT -w $WK -e HOME=$WK/home --user $(id -u):$(id -g) ubuntu:24.04"; else export W=""; fi
_one() { local i=$1 d=$2 drf=$3; shift 3; local s=$(date +%s.%N)
  timeout -s KILL $T $W $DRRUN $drf -- "$@" >/dev/null 2>"$d/err.$i"; local rc=$?; echo "$rc $(echo "$(date +%s.%N) - $s" | bc)" > "$d/rc.$i"
  [ $rc = 137 ] && [ "$MODE" = docker ] && docker ps -q | xargs -r docker kill >/dev/null 2>&1; true; }
export -f _one; export T DRRUN MODE
runs() { local label=$1 drf=$2; shift 2
  local d=$R/$label; mkdir -p "$d"
  seq 1 $N | xargs -P $PAR -I{} bash -c '_one "$@"' _ {} "$d" "$drf" "$@" >/dev/null
  local h o avg
  h=$(cat "$d"/rc.* | awk '$1==124||$1==137' | wc -l); o=$(cat "$d"/rc.* | awk '$1!=0&&$1!=124&&$1!=137' | wc -l)
  avg=$(cat "$d"/rc.* | awk '$1==0{s+=$2;n++} END{if(n)printf "%.2f",s/n}')
  printf '%s\t%s/%s\tother_nonzero=%s\tavg_ok_s=%s\n' "$label" "$h" "$N" "$o" "$avg" | tee -a "$TSV"; }
for b in go_static go_v3; do
  runs $b.default "" ./$b
  runs $b.thread_private "-thread_private" ./$b
  runs $b.no_early_inject "-no_early_inject" ./$b
done
{ echo "### gohang3 $MODE (N=$N, timeout ${T}s)"; echo; echo '| case | hangs | other | avg ok s |'; echo '|---|---|---|---|'; awk -F'\t' '{printf "| %s | %s | %s | %s |\n",$1,$2,$3,$4}' "$TSV"; } >> "$SUM"; cat "$SUM"
