#!/usr/bin/env bash
# ofloss.sh: per-case diff of avxemu's instruction forms, native vs plain drrun (no client),
# with DR built from the fork branch.
source "$(dirname "$0")/lib.sh"
FORK_BRANCH=${FORK_BRANCH:-fix-pending-signal-self-link}
AVXEMU=8242e2ebfc11a0054fb428676e576e4f30f5cae6
sudo apt-get update -qq; sudo apt-get install -y -qq cmake g++ zlib1g-dev libsnappy-dev liblz4-dev libunwind-dev >/dev/null
grep -m1 'model name' /proc/cpuinfo | tee "$OUT/cpu.txt"
cd "$ROOT"
git clone -q --depth 1 -b $FORK_BRANCH https://github.com/lhns/dynamorio.git drsrc
git -C drsrc submodule update -q --init --depth 1 --recommend-shallow
git -C drsrc log --oneline -1 | tee "$OUT/source.txt"
cmake -S drsrc -B drbuild -DDEBUG=OFF -DBUILD_TESTS=OFF -DBUILD_DOCS=OFF -DBUILD_SAMPLES=OFF -DBUILD_CLIENTS=OFF >/dev/null 2>&1 || exit 1
cmake --build drbuild -j4 >/dev/null 2>&1 || exit 1
DRR=$ROOT/drbuild/bin64/drrun
git clone -q https://github.com/lhns/avxemu avxemu; git -C avxemu checkout -q $AVXEMU
curl -fsSL -o sem_adapter.c https://raw.githubusercontent.com/lhns/v3compat/scaffold/test/sem/sem_adapter.c
sed -i 's/printf("  gpr");/printf("  infl=%llx gpr", (unsigned long long)c.in.rflags);/' sem_adapter.c
S=avxemu
gcc -O2 -UNDEBUG -w -DSEM_MANIFEST='""' -DSEM_KNOWN='""' -I$S/test/spec -I$S/src -I$S/test -o "$WK/semhw" \
  sem_adapter.c $S/test/spec/sem_hw.S $S/test/spec/spec.c $S/test/spec/known.c $S/test/refdigest.c $S/test/cpu.c -ldl -lm || exit 1
run() { # label prefix...
  local l=$1; shift
  ( cd "$WK"; SEM_DUMP=1 timeout 1500 "$@" ./semhw "$ROOT/$S/test/spec/manifest.tsv" "$ROOT/$S/test/reference/semantics.ref" full ) > "$OUT/$l.txt" 2>&1
  echo "$l rc=$?" | tee -a "$OUT/rcs.txt"
}
run native env
run dr "$DRR" --
run dr_notraces "$DRR" -disable_traces --
python3 "$P0/ofloss_diff.py" "$OUT/native.txt" "$OUT/dr.txt" | tee "$OUT/diff-dr.txt"
python3 "$P0/ofloss_diff.py" "$OUT/native.txt" "$OUT/dr_notraces.txt" | tee "$OUT/diff-notraces.txt"
grep -hE 'MISMATCH|semantics on' "$OUT/native.txt" | head -20
grep -hE 'MISMATCH|semantics on' "$OUT/dr.txt" | head -40
gzip -f "$OUT/native.txt" "$OUT/dr.txt" "$OUT/dr_notraces.txt"
