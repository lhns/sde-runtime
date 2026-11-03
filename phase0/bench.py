#!/usr/bin/env python3
"""bench.py NAME RUNS [--stdin F] [--timeout S] -- cmd...   |   bench.py --report"""
import os, sys, time, subprocess, hashlib, json, statistics, signal, tempfile, threading
OUT = os.environ.get("OUT", "out")
DRRUN = os.environ.get("DRRUN", "drrun")
NULLC = os.environ.get("NULLCLIENT", "")

def run1(cmd, stdin, timeout):
    fo, fe = tempfile.TemporaryFile(), tempfile.TemporaryFile()
    fi = open(stdin, "rb") if stdin else subprocess.DEVNULL
    t0 = time.time()
    p = subprocess.Popen(cmd, stdin=fi, stdout=fo, stderr=fe, start_new_session=True)
    tm = threading.Timer(timeout, lambda: os.killpg(p.pid, signal.SIGKILL)); tm.start()
    _, st, ru = os.wait4(p.pid, 0)
    wall = time.time() - t0; tm.cancel()
    try: os.killpg(p.pid, signal.SIGKILL)
    except Exception: pass
    fo.seek(0); fe.seek(0); o, e = fo.read(), fe.read()
    rc = os.waitstatus_to_exitcode(st); rc = 128 - rc if rc < 0 else rc
    return dict(wall=wall, user=ru.ru_utime, sys=ru.ru_stime, rss=ru.ru_maxrss / 1024, rc=rc,
                oh=hashlib.sha256(o).hexdigest()[:12], eh=hashlib.sha256(e).hexdigest()[:12],
                err=e[-300:].decode("utf8", "replace"))

def modes(cmd):
    m = {"native": cmd, "dr": [DRRUN, "--"] + cmd}
    if NULLC: m["drnull"] = [DRRUN, "-c", NULLC, "--"] + cmd
    return m

def main():
    name, n = sys.argv[1], int(sys.argv[2]); i = sys.argv.index("--"); cmd = sys.argv[i + 1:]
    stdin = timeout = None; timeout = 400
    a = sys.argv[3:i]
    if "--stdin" in a: stdin = a[a.index("--stdin") + 1]
    if "--timeout" in a: timeout = int(a[a.index("--timeout") + 1])
    ms = modes(cmd); rec = {"name": name, "cmd": " ".join(cmd), "modes": {}}
    def go(mode, c, cnt):
        runs = []
        for k in range(cnt):
            r = run1(c, stdin, timeout); runs.append(r)
            print(name, mode, k, {x: r[x] for x in ("wall", "rc", "oh")}, flush=True)
            if k == 0 and r["wall"] > 100 and cnt > 2: cnt = 2
            if k + 1 >= cnt: break
        rec["modes"][mode] = runs
    for mode, c in ms.items(): go(mode, c, n)
    nat = rec["modes"]["native"][0]
    d = rec["modes"]["dr"][0]
    if d["rc"] != nat["rc"] or d["oh"] != nat["oh"]:
        go("dr_notraces", [DRRUN, "-disable_traces", "--"] + cmd, min(n, 3))
    with open(os.path.join(OUT, "bench.jsonl"), "a") as f: f.write(json.dumps(rec) + "\n")

def report():
    rows = [json.loads(l) for l in open(os.path.join(OUT, "bench.jsonl"))]
    print("| case | mode | runs | wall med s | user s | sys s | RSS MB | rc | stdout=native | stderr=native | wall x native |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        nat = r["modes"]["native"]; nw = statistics.median(x["wall"] for x in nat)
        for mode, runs in r["modes"].items():
            med = lambda k: statistics.median(x[k] for x in runs)
            rcs = ",".join(sorted({str(x["rc"]) for x in runs}))
            so = "yes" if all(x["oh"] == nat[0]["oh"] for x in runs) else "NO"
            se = "yes" if all(x["eh"] == nat[0]["eh"] for x in runs) else "NO"
            print(f"| {r['name']} | {mode} | {len(runs)} | {med('wall'):.3f} | {med('user'):.3f} | {med('sys'):.3f} | {med('rss'):.0f} | {rcs} | {so} | {se} | {med('wall')/nw:.2f} |")
    print("\nStartup go/no-go (cases named startup-*): pass = DR wall < 1 s AND ratio < 2x native\n")
    print("| case | mode | wall s | ratio | <1 s | <2x |"); print("|---|---|---|---|---|---|")
    for r in rows:
        if not r["name"].startswith("startup-"): continue
        nw = statistics.median(x["wall"] for x in r["modes"]["native"])
        for mode, runs in r["modes"].items():
            if mode == "native": continue
            w = statistics.median(x["wall"] for x in runs)
            print(f"| {r['name']} | {mode} | {w:.3f} | {w/nw:.1f} | {'pass' if w<1 else 'FAIL'} | {'pass' if w/nw<2 else 'FAIL'} |")
    for r in rows:
        for mode, runs in r["modes"].items():
            if mode != "native" and any(x["err"].strip() for x in runs) :
                print(f"\nstderr tail {r['name']}/{mode}: `{runs[0]['err'].strip()[-200:]!r}`")

if __name__ == "__main__":
    report() if sys.argv[1] == "--report" else main()
