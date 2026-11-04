#!/usr/bin/env bash
# gohang.sh matrix|min|oldgo|evidence|confirm  -- Go-under-DynamoRIO hang hunt
source "$(dirname "$0")/lib.sh"
MODE=$1; N=${N:-20}; T=${T:-60}; PAR=${PAR:-2}
dr_install
sudo apt-get install -y -qq gdb >/dev/null 2>&1
cd "$WK"; R=$OUT/gohang; mkdir -p "$R"; TSV=$R/table.tsv; : > "$TSV"
go version | tee -a "$R/goversion.txt"
( cd $P0/src/go && CGO_ENABLED=0 go build -o "$WK/go_static" main.go && CGO_ENABLED=0 GOAMD64=v3 go build -o "$WK/go_v3" main.go )
( cd $P0/src/gomin && CGO_ENABLED=0 go build -o "$WK/gomin" main.go; cat > "$WK/hello.go" <<'EOG'
package main

func main() { println("hello") }
EOG
cd "$WK" && CGO_ENABLED=0 go build -o "$WK/gohello" hello.go )
# one_run LABEL IDX env-assignments... -- drrun-args... -- cmd...  (prints rc)
runs() { # label "ENV=.. ENV2=.." "drflags" cmd...
  local label=$1 envs=$2 drf=$3; shift 3
  local d=$R/$label; mkdir -p "$d"
  seq 1 $N | xargs -P $PAR -I{} bash -c '_one "$@"' _ {} "$d" "$envs" "$drf" "$@" >/dev/null
  local h; h=$(grep -c '^124$' "$d"/rc.* 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
  local o; o=$(cat "$d"/rc.* | grep -vc '^\(0\|124\)$')
  printf '%s\t%s/%s\t%s\n' "$label" "$h" "$N" "other_nonzero=$o" | tee -a "$TSV"
}
_one() { local i=$1 d=$2 envs=$3 drf=$4; shift 4
  env $envs timeout $T $DRRUN $drf -- "$@" >/dev/null 2>"$d/err.$i"; echo $? > "$d/rc.$i"; }
export -f _one; export T DRRUN
NATIVE_CHECK() { for b in go_static go_v3 gomin; do ( time ./$b >/dev/null ) 2>&1 | grep real; done; }
case $MODE in
matrix)
  for b in go_static go_v3; do
    runs "$b.default" "A=1" "" ./$b
    runs "$b.asyncoff" "GODEBUG=asyncpreemptoff=1" "" ./$b
    runs "$b.asyncoff_p1" "GODEBUG=asyncpreemptoff=1 GOMAXPROCS=1" "" ./$b
    runs "$b.p1" "GOMAXPROCS=1" "" ./$b
    runs "$b.nodisabletraces" "A=1" "-disable_traces" ./$b
  done ;;
min)
  runs hello "A=1" "" ./gohello
  for m in hello goroutines gc spin signal http; do runs "gomin.$m" "A=1" "" ./gomin $m; done ;;
oldgo)
  for v in 1.22.12 1.20.14; do
    go install golang.org/dl/go$v@latest >/dev/null 2>&1 && "$HOME/go/bin/go$v" download >/dev/null 2>&1 || continue
    ( cd $P0/src/go && CGO_ENABLED=0 "$HOME/go/bin/go$v" build -o "$WK/go_$v" main.go )
    runs "go$v.default" "A=1" "" ./go_$v
    runs "go$v.asyncoff" "GODEBUG=asyncpreemptoff=1" "" ./go_$v
  done ;;
esac
{ echo "### gohang $MODE (N=$N, timeout ${T}s, par=$PAR)"; echo; echo '| case | hangs (rc124) | note |'; echo '|---|---|---|'; awk -F'\t' '{printf "| %s | %s | %s |\n",$1,$2,$3}' "$TSV"; } >> "$SUM"
cat "$SUM"
