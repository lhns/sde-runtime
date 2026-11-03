#!/usr/bin/env bash
# Shared helpers for phase 0 jobs. Source, do not execute.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
P0=$ROOT/phase0
OUT=${OUT:-$ROOT/out}; mkdir -p "$OUT"
WK=$ROOT/work; mkdir -p "$WK"
SUM=$OUT/summary.md
DR_TAG=release_11.3.0-1; DR_VER=11.3.0
DR=$ROOT/dr/DynamoRIO-Linux-$DR_VER
DRRUN=$DR/bin64/drrun
DUCKDB_IMG='duckdb/duckdb:2.0.0@sha256:453caf4f1c445ee8363acaa6cd383751396d2eae0d02f362ada64d87267a4221'
export DRRUN OUT
sec() { printf '\n## %s\n\n' "$*" >> "$SUM"; echo "=== $*"; }
cpu_check() {
  gcc -O1 -o "$WK/cpuid" "$P0/src/cpuid.c" && "$WK/cpuid" | tee -a "$OUT/cpu.txt"
  { echo "Runner CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2)"; echo; echo '```'; cat "$OUT/cpu.txt"; echo '```'; } >> "$SUM"
  grep -q 'avx2=1' "$OUT/cpu.txt" || { echo "NO AVX2 on runner"; exit 1; }
}
dr_install() {
  if [ ! -x "$DRRUN" ]; then
    mkdir -p "$ROOT/dr"
    curl -fsSL --retry 5 -o "$ROOT/dr.tgz" "https://github.com/DynamoRIO/dynamorio/releases/download/$DR_TAG/DynamoRIO-Linux-$DR_VER.tar.gz" || exit 1
    tar -xzf "$ROOT/dr.tgz" -C "$ROOT/dr"
  fi
  gcc -shared -fPIC -O1 -DLINUX -DX86_64 -I"$DR/include" -o "$WK/libnull.so" "$P0/src/nullclient.c" || exit 1
  export NULLCLIENT=$WK/libnull.so
  { echo "DynamoRIO $DR_VER (tag $DR_TAG, stable release, Linux x86-64 tarball)"; "$DRRUN" -version 2>&1 | head -3; } | tee -a "$OUT/dr-version.txt"
  head -12 "$DR/License.txt" 2>/dev/null > "$OUT/license-head.txt"
}
duckdb_get() {
  [ -x "$WK/duckdb" ] && return
  docker pull -q "$DUCKDB_IMG" >/dev/null || return 1
  local c; c=$(docker create "$DUCKDB_IMG") && docker cp "$c:/duckdb" "$WK/duckdb" ; docker rm "$c" >/dev/null
  chmod +x "$WK/duckdb"; file "$WK/duckdb" | tee -a "$OUT/duckdb-file.txt"; ldd "$WK/duckdb" 2>&1 | tee -a "$OUT/duckdb-file.txt"
  "$WK/duckdb" -version | tee -a "$OUT/duckdb-file.txt"
}
