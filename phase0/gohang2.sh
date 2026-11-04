#!/usr/bin/env bash
# gohang2.sh spin: spin-only variants. Native control first.
source "$(dirname "$0")/lib.sh"
N=${N:-20}; T=${T:-30}; PAR=${PAR:-2}
dr_install
cd "$WK"; R=$OUT/gohang2; mkdir -p "$R"; TSV=$R/table.tsv; : > "$TSV"
go version | tee "$R/goversion.txt"
( cd $P0/src/gomin && CGO_ENABLED=0 go build -o "$WK/gomin" main.go && CGO_ENABLED=0 GOAMD64=v3 go build -o "$WK/gomin_v3" main.go )
_one() { local i=$1 d=$2 envs=$3 drf=$4; shift 4
  if [ -n "${NATIVE:-}" ]; then env $envs timeout $T "$@" >/dev/null 2>"$d/err.$i"; else env $envs timeout $T $DRRUN $drf -- "$@" >/dev/null 2>"$d/err.$i"; fi; echo $? > "$d/rc.$i"; }
export -f _one; export T DRRUN
runs() { local label=$1 envs=$2 drf=$3; shift 3
  local d=$R/$label; mkdir -p "$d"
  seq 1 $N | xargs -P $PAR -I{} bash -c '_one "$@"' _ {} "$d" "$envs" "$drf" "$@" >/dev/null
  local h; h=$(cat "$d"/rc.* | grep -c '^124$'); local o; o=$(cat "$d"/rc.* | grep -vc '^\(0\|124\)$')
  printf '%s\t%s/%s\tother_nonzero=%s\t%s\n' "$label" "$h" "$N" "$o" "$(cat $d/err.* | grep -v '^$' | sort | uniq -c | sort -rn | head -2 | tr '\n' ' ' | cut -c1-160)" | tee -a "$TSV"
}
NATIVE=1 runs native.spin "A=1" "" ./gomin spin
NATIVE=1 runs native.spin.asyncoff "GODEBUG=asyncpreemptoff=1" "" ./gomin spin
NATIVE=1 runs native.spincoop.asyncoff "GODEBUG=asyncpreemptoff=1" "" ./gomin spincoop
runs dr.spin.default "A=1" "" ./gomin spin
runs dr.spincoop.default "A=1" "" ./gomin spincoop
runs dr.spincoop.asyncoff "GODEBUG=asyncpreemptoff=1" "" ./gomin spincoop
runs dr.spin.v3 "A=1" "" ./gomin_v3 spin
runs dr.spin.p1 "GOMAXPROCS=1" "" ./gomin spin
runs dr.spin.disable_traces "A=1" "-disable_traces" ./gomin spin
runs dr.spin.thread_private "A=1" "-thread_private" ./gomin spin
runs dr.spin.no_shared_bbs "A=1" "-thread_private -no_shared_bbs -no_shared_traces" ./gomin spin
runs dr.spin.bb1 "A=1" "-max_bb_instrs 1" ./gomin spin
runs dr.spin.no_indcall2direct "A=1" "-indcall2direct" ./gomin spin
runs dr.spin.late "A=1" "-no_early_inject" ./gomin spin
runs dr.spin.sigmask "A=1" "-no_inline_ignored_syscalls" ./gomin spin
{ echo "### gohang2 (N=$N, timeout ${T}s)"; echo; echo '| case | hangs (rc124) | other | top stderr |'; echo '|---|---|---|---|'; awk -F'\t' '{printf "| %s | %s | %s | %s |\n",$1,$2,$3,$4}' "$TSV"; } >> "$SUM"; cat "$SUM"
