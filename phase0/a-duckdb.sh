#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
cpu_check; dr_install; duckdb_get || exit 1
sec "A. duckdb 2.0.0"
D=$WK/duckdb; B="python3 $P0/bench.py"
$B startup-duckdb-version 5 -- $D -version
$B startup-duckdb-select42 5 -- $D -c "select 42"
$B duckdb-sum-squares 5 -- $D -c "select sum(range*range) from range(30000000)"
$B duckdb-varied 5 --timeout 900 --stdin "$P0/varied.sql" -- $D :memory:
python3 $P0/bench.py --report | tee -a "$SUM"
