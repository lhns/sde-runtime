#!/usr/bin/env bash
# flagrepro.sh: flag and result corruption reproducer on native, stock DR and the fork; then an
# indirect-branch benchmark of what restoring flags on every entry costs.
source "$(dirname "$0")/lib.sh"
FORK_BRANCH=${FORK_BRANCH:-fix-pending-signal-self-link}
sudo apt-get update -qq; sudo apt-get install -y -qq cmake g++ zlib1g-dev libsnappy-dev liblz4-dev libunwind-dev >/dev/null
dr_install
grep -m1 "model name" /proc/cpuinfo | tee -a "$SUM"
cd "$ROOT"
git clone -q --depth 1 -b $FORK_BRANCH https://github.com/lhns/dynamorio.git drsrc
git -C drsrc submodule update -q --init --depth 1 --recommend-shallow
git -C drsrc log --oneline -1 | tee -a "$SUM"
for bt in OFF ON; do
  cmake -S drsrc -B drbuild$bt -DDEBUG=$bt -DBUILD_TESTS=OFF -DBUILD_DOCS=OFF -DBUILD_SAMPLES=OFF -DBUILD_CLIENTS=OFF >/dev/null 2>&1 || exit 1
  cmake --build drbuild$bt -j4 >/dev/null 2>&1 || exit 1
done
gcc -O1 -o "$WK/flagrepro" "$P0/src/flagrepro/flagrepro.c" || exit 1
gcc -O1 -o "$WK/ibbench" "$P0/src/flagrepro/ibbench.c" || exit 1
cd "$WK"
sec native; ./flagrepro 2>&1 | tee -a "$SUM"
sec stock; "$DRRUN" -- ./flagrepro 2>&1 | tee -a "$SUM"
sec fork release; "$ROOT/drbuildOFF/bin64/drrun" -- ./flagrepro 2>&1 | tee -a "$SUM"
sec fork debug; "$ROOT/drbuildON/bin64/drrun" -- ./flagrepro 2>&1 | tee -a "$SUM"
sec fork -disable_traces; "$ROOT/drbuildOFF/bin64/drrun" -disable_traces -- ./flagrepro 2>&1 | tee -a "$SUM"
sec ibbench seconds
for i in 1 2 3; do
  for v in "native" "stock $DRRUN --" "fork $ROOT/drbuildOFF/bin64/drrun --"; do
    set -- $v; n=$1; shift; s=$(date +%s.%N); "$@" ./ibbench >/dev/null; echo "$n $(echo "$(date +%s.%N) - $s" | bc)" | tee -a "$SUM"
  done
done
