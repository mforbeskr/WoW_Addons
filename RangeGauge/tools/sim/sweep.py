import sys, itertools, json
from world import run, SCENARIOS
import est_new
def score(mapflags=(True, False)):
    tot = dict(mae=0, p95=0, jumps=0, frozen=0); n = 0
    per = {}
    for sc in SCENARIOS:
        for mapok in mapflags:
            for s in (1, 2, 3):
                m = run(lambda w: est_new.Estimator(use_map=mapok), sc, mapok, s)
                for k in tot: tot[k] += m[k]
                key = sc + ("" if mapok else "-nomap")
                per.setdefault(key, [0,0])
                per[key][0] += m["mae"]/3; per[key][1] += m["jumps"]/3
                n += 1
    return {k: (v/n if k in ("mae","p95") else v/3) for k, v in tot.items()}, per
if __name__ == "__main__":
    grid = json.loads(sys.argv[1])
    keys = list(grid)
    for combo in itertools.product(*grid.values()):
        for k, v in zip(keys, combo): est_new.P[k] = v
        t, per = score()
        print(dict(zip(keys, combo)), " ".join(f"{k}={v:.2f}" for k, v in t.items()))
        if len(sys.argv) > 2:
            for k, v in per.items(): print(f"    {k:20} mae={v[0]:.2f} jumps={v[1]:.1f}")
