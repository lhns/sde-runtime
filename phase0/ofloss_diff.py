#!/usr/bin/env python3
# Compare two SEM_DUMP logs case by case; print differing cases and a per-form tally.
import collections
import re
import sys


def load(path):
    cases, key = {}, None
    for line in open(path, errors="replace"):
        if line.startswith("case "):
            f = line.split()
            key = (f[1], f[2])
            cases[key] = f[3:7]
        elif line.startswith("  infl") and key:
            cases[key].append(line.strip())
            key = None
    return cases


def flags(case):
    m = re.search(r"fl=(\w+)", case[4]) if len(case) > 4 else None
    return int(m[1], 16) if m else None


a, b = load(sys.argv[1]), load(sys.argv[2])
tally, shown, xors = collections.Counter(), collections.Counter(), collections.Counter()
for key, case in a.items():
    if key not in b:
        tally[key[0] + " missing"] += 1
        continue
    if case == b[key]:
        continue
    tally[key[0] + " diff"] += 1
    fa, fb = flags(case), flags(b[key])
    if fa is not None and fb is not None:
        xors[hex(fa ^ fb)] += 1
    if shown[key[0]] < 4:
        shown[key[0]] += 1
        print(key[0], key[1])
        print("  A", *case)
        print("  B", *b[key])
print("cases", len(a), len(b))
for name, count in sorted(tally.items()):
    print(" ", name, count)
print("flag xor histogram", dict(xors))
