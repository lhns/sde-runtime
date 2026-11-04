#!/usr/bin/env python3
"""classify.py static FILE(objdump -d --no-show-raw-insn text) | classify.py dynamic FILE(opcode_mix output)
Prints percent of instructions per class. static: operand widths known; dynamic: mnemonic only."""
import re, sys, collections

FMA = re.compile(r"^v(f|fn)m(add|sub|addsub|subadd)\d{3}[ps][sd]$")
GATHER = re.compile(r"^v(p)?gather")
F16C = {"vcvtph2ps", "vcvtps2ph"}
BMI1 = {"andn", "blsi", "blsmsk", "blsr", "bextr"}
BMI2 = {"bzhi", "pdep", "pext", "mulx", "rorx", "sarx", "shlx", "shrx"}
# integer ops that exist only as AVX2 regardless of width
AVX2_ONLY = re.compile(r"^(vpbroadcast[bwdq]|vbroadcasti128|vperm2i128|vpermd|vpermq|vpermps|vpermpd|vinserti128|vextracti128|vpblendd|vpmaskmov[dq]|vpsllv[dq]|vpsrlv[dq]|vpsravd)$")
# vp* mnemonics that are AVX1 even with ymm (none integer) or not integer-vector ops
NOT_INT = {"vptest", "vpermilps", "vpermilpd", "vpcmpestri", "vpcmpestrm", "vpcmpistri", "vpcmpistrm", "vpextrb", "vpextrw", "vpextrd", "vpextrq", "vpinsrb", "vpinsrw", "vpinsrd", "vpinsrq"}

def cls(m, ymm):
    if FMA.match(m): return "FMA"
    if GATHER.match(m): return "gather"
    if m in F16C: return "F16C"
    if m == "tzcnt": return "TZCNT"
    if m == "lzcnt": return "LZCNT"
    if m == "movbe": return "MOVBE"
    if m in BMI1: return "BMI1(excl tzcnt)"
    if m in BMI2: return "BMI2"
    if AVX2_ONLY.match(m): return "AVX2 int"
    if m.startswith("vp") and m not in NOT_INT and ymm is True: return "AVX2 int"
    if m.startswith("vp") and m not in NOT_INT and ymm is None: return "VEX vp* (AVX1 if xmm, AVX2 if ymm)"
    if m.startswith("v"): return "AVX1 VEX (other)"
    return "legacy/other"

def main():
    mode, path = sys.argv[1], sys.argv[2]
    c = collections.Counter(); tot = 0; vex = 0
    if mode == "static":
        for l in open(path, errors="replace"):
            p = l.split("\t")
            if len(p) < 2: continue
            ins = p[-1].strip()
            if not ins or ins.startswith("("): continue
            w = ins.replace("lock ", "").replace("rep ", "").replace("repz ", "").replace("repnz ", "").replace("notrack ", "").replace("bnd ", "").split()
            if not w: continue
            m = w[0]; tot += 1
            k = cls(m, "ymm" in ins)
            c[k] += 1
            if m.startswith("v") and k != "legacy/other": vex += 1
    else:
        for l in open(path, errors="replace"):
            mm = re.match(r"^\s*(\d+)\s*:\s*([a-z0-9_]+)\s*$", l)
            if not mm: continue
            n, m = int(mm.group(1)), mm.group(2); tot += n
            k = cls(m, None); c[k] += n
            if m.startswith("v") and k != "legacy/other": vex += n
    print(f"total instructions: {tot}")
    if tot == 0: return
    print("| class | count | % |"); print("|---|---|---|")
    for k, v in c.most_common(): print(f"| {k} | {v} | {100*v/tot:.4f} |")
    print(f"| all VEX/EVEX (v* mnemonics) | {vex} | {100*vex/tot:.4f} |")

main()
