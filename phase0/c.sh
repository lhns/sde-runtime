#!/bin/bash
# runs inside ubuntu:24.04 on the AVX-only host. Output = report.
TF=$'real %R user %U sys %S'
echo "== cpu"; grep -m1 'model name' /proc/cpuinfo; grep -m1 flags /proc/cpuinfo | tr ' ' '\n' | grep -E '^(avx|avx2|fma|bmi1|bmi2|f16c|movbe|abm|sse4_2)$' | tr '\n' ' '; echo
echo "== dr install"; mkdir -p /dr && curl -fsSL --retry 5 https://github.com/DynamoRIO/dynamorio/releases/download/release_11.3.0-1/DynamoRIO-Linux-11.3.0.tar.gz | tar -xz -C /dr
D=/dr/DynamoRIO-Linux-11.3.0/bin64/drrun; export HOME=/tmp
echo "== drrun version"; $D -version 2>&1 | head -2
echo "== drrun -- /bin/true"; $D -- /bin/true; echo rc=$?
echo "== drrun -- /bin/echo hi"; $D -- /bin/echo hi; echo rc=$?
head -c 40000000 <(cat /usr/lib/x86_64-linux-gnu/*.so* /usr/bin/* 2>/dev/null) > /big.bin; ls -l /big.bin
for i in 1 2 3; do echo "== v2 cpubench native $i"; ( TIMEFORMAT=$TF; time /b/cpubench_v2 >/tmp/o1 ); md5sum /tmp/o1; done
for i in 1 2 3; do echo "== v2 cpubench DR $i"; ( TIMEFORMAT=$TF; time $D -- /b/cpubench_v2 >/tmp/o2 ); md5sum /tmp/o2; done
for i in 1 2 3; do echo "== zstd -9 native $i"; ( TIMEFORMAT=$TF; time zstd -9 -T1 -c /big.bin | md5sum ); done
for i in 1 2 3; do echo "== zstd -9 DR $i"; ( TIMEFORMAT=$TF; time $D -- zstd -9 -T1 -c /big.bin | md5sum ); done
echo "== duckdb native select 42"; /b/duckdb -c 'select 42'; echo rc=$?
echo "== duckdb DR select 42"; $D -- /b/duckdb -c 'select 42'; echo rc=$?
echo "== duckdb -version DR"; $D -- /b/duckdb -version; echo rc=$?
echo "== duckdb DR sum squares"; $D -- /b/duckdb -c 'select sum(range*range) from range(30000000)'; echo rc=$?
echo "== sigill_pc native"; /b/sigill_pc; echo rc=$?
echo "== sigill_pc DR"; $D -- /b/sigill_pc; echo rc=$?
echo "== sigill_rt native"; /b/sigill_rt
echo "== sigill_rt DR"; $D -- /b/sigill_rt
