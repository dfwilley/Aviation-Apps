"""Compare the native model output with the web app's numbers. Exit 1 on any mismatch."""
import json, sys
exp = json.load(open(sys.argv[1])); got = json.load(open(sys.argv[2]))
bad = 0; n = 0
def cmp(path, e, g):
    global bad, n
    for k, ev in e.items():
        if k in ("alt", "dT", "W", "pct", "mode", "cal", "fK", "fA", "own", "h", "p"):
            continue
        gv = got_v = g.get(k)
        n += 1
        if ev is None or gv is None:
            ok = ev is None and gv is None
        else:
            ok = abs(ev - gv) <= 1e-6 * max(1.0, abs(ev))
        if not ok:
            bad += 1; print(f"MISMATCH {path}.{k}: web {ev}  native {gv}")
for sec in ("solve", "finder", "table"):
    for i, (e, g) in enumerate(zip(exp[sec], got[sec])):
        cmp(f"{sec}[{i}]", e, g)
    if len(exp[sec]) != len(got[sec]):
        bad += 1; print(f"MISMATCH {sec} count")
cmp("planning", exp["planning"], got["planning"])
print(f"{n - bad} of {n} values match the web app")
sys.exit(1 if bad else 0)
