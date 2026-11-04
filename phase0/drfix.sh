#!/usr/bin/env bash
# drfix.sh base|patched release|debug: build DR from source, run its signal/thread tests,
# then the hang reproducers (release: base N=30, patched N=200; debug: N=30) and, for
# patched release, the -thread_private cost.
source "$(dirname "$0")/lib.sh"
SIDE=$1; BT=$2; S=$ROOT/drsrc; B=$ROOT/drbuild
FORK_BRANCH=fix-pending-signal-self-link
sudo apt-get update -qq; sudo apt-get install -y -qq cmake g++ zlib1g-dev libsnappy-dev liblz4-dev libunwind-dev time >/dev/null
if [ "$SIDE" = patched ]; then git clone -q --depth 1 -b $FORK_BRANCH https://github.com/lhns/dynamorio.git "$S"
else git clone -q --depth 1 -b $DR_TAG https://github.com/DynamoRIO/dynamorio.git "$S"; fi
git -C "$S" submodule update -q --init --depth 1 --recommend-shallow || exit 1
git -C "$S" log --oneline -1 | tee "$OUT/source.txt"
[ "$BT" = debug ] && DBG=ON || DBG=OFF
cmake -S "$S" -B "$B" -DDEBUG=$DBG -DBUILD_TESTS=ON -DBUILD_DOCS=OFF -DBUILD_SAMPLES=OFF >"$OUT/cmake.log" 2>&1 || { tail -30 "$OUT/cmake.log"; exit 1; }
cmake --build "$B" -j4 >"$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 1; }
( cd "$B" && timeout 2400 ctest -j2 --timeout 300 -R 'linux\.(signal|sigplain|thread)' -E 'decode-bad' ) > "$OUT/ctest.txt" 2>&1
grep -E 'Test +#[0-9]+:' "$OUT/ctest.txt" | sed -E 's/^.*Test +#[0-9]+: //; s/ \.+\**/ /; s/ +[0-9.]+ sec$//' | sort > "$OUT/ctest-results.txt"
tail -3 "$OUT/ctest.txt"
( cd "$B" && timeout 900 ctest --timeout 600 -R 'api\.ir' ) > "$OUT/ctest-ir.txt" 2>&1; tail -6 "$OUT/ctest-ir.txt"
if [ "$SIDE" = patched ] && [ "$BT" = release ]; then N=200; else N=30; fi
export N PROOF=1 DR_PATCHED=$B
bash "$P0/gohang4.sh"
[ "$SIDE" = patched ] && [ "$BT" = release ] && bash "$P0/cost.sh" "$B/bin64/drrun"
cat "$SUM"
