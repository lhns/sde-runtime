#!/usr/bin/env bash
# b.sh direct|docker|dockernp
source "$(dirname "$0")/lib.sh"
MODE=$1
cpu_check; dr_install
RES=$OUT/res-$MODE; mkdir -p "$RES"; ROWS=$RES/rows.tsv; : > "$ROWS"
cd "$WK"
IMG=ubuntu:24.04
SRC=$P0/src
# --- builds
gcc -O2 -mavx2 -static -o avx2_glibc_static $SRC/avx2.c
gcc -O2 -mavx2 -static-pie -fPIE -o avx2_static_pie $SRC/avx2.c
gcc -O2 -mavx2 -o avx2_dyn $SRC/avx2.c
docker run --rm -v "$ROOT:$ROOT" -w "$WK" alpine sh -c "apk add -q gcc musl-dev && gcc -O2 -mavx2 -static -o avx2_musl $SRC/avx2.c" || echo "musl build failed"
for t in child forker execer exeinfo suid sig smc; do gcc -O1 -o ${t}_dyn $SRC/$t.c; gcc -O1 -static -o ${t}_static $SRC/$t.c; done
gcc -O1 -o rseq_dyn $SRC/rseq.c
gcc -O1 -shared -fPIC -mlzcnt -mbmi -mbmi2 -mavx2 -o libl.so $SRC/libl.c; gcc -O1 -o dl_dyn $SRC/dl.c -ldl
g++ -O1 -static-libstdc++ -pthread -o cpp_dyn $SRC/cpp.cpp
( cd $SRC/go && CGO_ENABLED=0 go build -o "$WK/go_static" main.go && CGO_ENABLED=0 GOAMD64=v3 go build -o "$WK/go_v3" main.go )
cp $P0/chain.sh .; chmod +x chain.sh
cp suid_dyn suid_child; sudo chown root:root suid_child; sudo chmod 4755 suid_child
file avx2_glibc_static avx2_static_pie avx2_musl go_static go_v3 | tee -a "$OUT/file-static.txt"
# --- runner wrapper
DROPTS=()
if [ "$MODE" = direct ]; then W=(); else
  SEC=()
  if [ "$MODE" = dockernp ]; then
    curl -fsSL https://raw.githubusercontent.com/moby/profiles/main/seccomp/default.json -o default.json || curl -fsSL https://raw.githubusercontent.com/moby/moby/master/profiles/seccomp/default.json -o default.json
    python3 -c '
import json
p=json.load(open("default.json"))
for s in p["syscalls"]: s["names"]=[n for n in s["names"] if n!="ptrace"]
json.dump(p,open("noptrace.json","w"))'
    SEC=(--security-opt "seccomp=$WK/noptrace.json")
  fi
  mkdir -p home
  W=(docker run --rm "${SEC[@]}" -v "$ROOT:$ROOT" -w "$WK" -e HOME="$WK/home" --user "$(id -u):$(id -g)" $IMG)
fi
row() { printf '%s\t%s\t%s\t%s\n' "$MODE" "$1" "$2" "$3" >> "$ROWS"; }
one() { tr '\n' ' ' | cut -c1-${1:-260}; }
# run_case NAME FLAGS cmd...   FLAGS: follow (all DRINFO maps_dr>0 under DR) | info (report only) | -
run_case() {
  local name=$1 flags=$2; shift 2; local d=$RES/$name; mkdir -p "$d"
  timeout 120 "${W[@]}" "$@" >$d/n.out 2>$d/n.err; local nrc=$?
  local ld=$WK/logs/$MODE-$name; mkdir -p "$ld"
  timeout 300 "${W[@]}" $DRRUN "${DROPTS[@]}" -logdir "$ld" -- "$@" >$d/d.out 2>$d/d.err; local drc=$?
  grep -v DRINFO $d/n.out > $d/n.cmp; grep -v DRINFO $d/d.out > $d/d.cmp
  local maps; maps=$(grep -o 'maps_dr=[-0-9]*' $d/d.out | cut -d= -f2 | tr '\n' ',')
  local nlogs; nlogs=$(find "$ld" -mindepth 1 2>/dev/null | wc -l)
  local ok=1
  [ $nrc = $drc ] || ok=0
  cmp -s $d/n.cmp $d/d.cmp || ok=0
  if [[ $flags == follow ]]; then [ -n "$maps" ] || ok=0; for m in ${maps//,/ }; do [ "$m" -gt 0 ] || ok=0; done; fi
  local v; if [[ $flags == info ]]; then v=INFO; elif [ $ok = 1 ]; then v=PASS; else v=FAIL; fi
  row "$name" "$v" "rc native=$nrc dr=$drc; dr_maps=[${maps}]; logdir_files=$nlogs; out_diff=$(diff $d/n.cmp $d/d.cmp | head -4 | one 120); dr_stderr=$(head -c 200 $d/d.err | one 160); dr_out=$(head -c 150 $d/d.out | one 130)"
}
for t in avx2_glibc_static avx2_static_pie avx2_musl avx2_dyn; do run_case "b1-3_$t" follow ./$t; done
run_case b4_go_static follow ./go_static
run_case b4_go_goamd64v3 follow ./go_v3
run_case b5_sh_script follow sh ./chain.sh
run_case b5_forker_dyn follow ./forker_dyn ./child_dyn ./child_static
run_case b5_forker_static follow ./forker_static ./child_dyn ./child_static
run_case b5_exec_dyn_to_static follow ./execer_dyn ./child_static
run_case b5_exec_static_to_dyn follow ./execer_static ./child_dyn
run_case b6_exe_dyn - ./exeinfo_dyn
run_case b6_exe_static - ./exeinfo_static
run_case b7_setuid_via_forker info ./forker_dyn ./suid_child
run_case b7_setuid_direct info ./suid_child
for k in dyn static; do run_case b8_segv_$k - ./sig_$k segv; run_case b8_altstack_$k - ./sig_$k altstack; done
run_case b8_sigterm_exit143 - ./sig_dyn term
run_case b9_cpp_exc_pthread_cancel - ./cpp_dyn
run_case b10_dlopen_lzcnt_bmi2 follow ./dl_dyn
run_case b11_rseq - ./rseq_dyn
run_case b12_smc_dyn - ./smc_dyn
run_case b12_smc_static - ./smc_static
# kill -TERM mid-query
if duckdb_get; then for v in "native app" "dr drrun" "dr app"; do set -- $v
  o=$("${W[@]}" bash $P0/killtest.sh $1 $DRRUN $WK/duckdb $2 2>&1 | one 300)
  vd=INFO; [[ $o == *"rc=143"* && $o == *"leftover_duckdb=0"* ]] && vd=PASS
  row "b8_kill_term_duckdb_$1_$2" $vd "$o"
done; fi
# b13 injection variants on static targets
for t in avx2_glibc_static avx2_static_pie avx2_musl go_static; do
  for o in "" "-early" "-late" "-ops -no_early_inject"; do
    d=$RES/inj; mkdir -p $d; ld=$WK/logs/$MODE-inj-$t; mkdir -p $ld
    timeout 120 "${W[@]}" $DRRUN $o -logdir $ld -- ./$t >$d/o 2>$d/e; rc=$?
    row "b13_${t}_[${o:-default}]" INFO "rc=$rc dr_maps=$(grep -o 'maps_dr=[-0-9]*' $d/o) out=$(head -c 120 $d/o | one 100) err=$(head -c 220 $d/e | one 200)"
  done
done
if [ "$MODE" = direct ]; then
  $DRRUN -help > "$OUT/drrun-help.txt" 2>&1; ls "$DR" "$DR/docs" > "$OUT/dr-ls.txt" 2>&1
  grep -rhoiE '.{0,140}(statically[ -]linked|static executable|static binar|no_early_inject|early injection|late injection).{0,200}' "$DR/docs" 2>/dev/null | sed 's/<[^>]*>//g' | sort -u | head -40 > "$OUT/docs-static.txt"
  ( cd "$WK" && find logs -maxdepth 2 | head -80 ) > "$OUT/dr-logs-listing.txt"
fi
{ echo "### B ($MODE)"; echo; echo "| case | verdict | evidence |"; echo "|---|---|---|"; awk -F'\t' '{gsub(/\|/,"/",$4); printf "| %s | %s | %s |\n",$2,$3,$4}' "$ROWS"; } | tee -a "$SUM"
