#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
cpu_check; dr_install
sec "A. non-duckdb programs"
B="python3 $P0/bench.py"; cd "$WK"
gcc -O2 -o cpubench "$P0/src/cpubench.c"; objdump -d cpubench | grep -c ymm > "$OUT/cpubench-ymm.txt"
$B cpubench-c 5 --timeout 900 -- ./cpubench
head -c 80000000 <(tar cf - /usr/lib /usr/share /opt 2>/dev/null) > big.bin; ls -l big.bin
sudo apt-get install -y -qq zstd >/dev/null; zstd --version
$B zstd-compress-9 5 --timeout 600 -- zstd -9 -T1 -c big.bin
node --version; java -version 2>&1 | head -1
$B startup-node-e0 5 -- node -e 0
$B node-bench 5 --timeout 900 -- node -e 'function f(n){return n<2?n:f(n-1)+f(n-2)};let a=[];for(let i=0;i<2e6;i++)a.push((i*2654435761)%1000003);a.sort((x,y)=>x-y);let m=new Map();for(let i=0;i<1e6;i++)m.set(i%50021,(m.get(i%50021)||0)+i);console.log(f(35),a[0],a[a.length-1],m.size,JSON.stringify(a.slice(0,1000)).length)'
javac -d . "$P0/src/Bench.java"
$B startup-java-version 5 -- java -version
$B java-bench 5 --timeout 900 -- java -cp . Bench
python3 $P0/bench.py --report | tee -a "$SUM"
