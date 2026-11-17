import sys
from world import run, SCENARIOS
import est_old

EST = {
    "old": lambda w: est_old.OldTracker(),
    "old_fixedlabels": lambda w: est_old.OldTracker(est_old.LABELS_FIXED, set(range(14))),
}
try:
    import est_new
    EST["new_1d"] = lambda w: est_new.Estimator(use_map=False)
    EST["new"] = lambda w: est_new.Estimator(use_map=True)
except ImportError as e:
    print("no est_new:", e)

names = sys.argv[1:] or list(EST)
seeds = [1, 2, 3]
print(f"{'estimator':16} {'scenario':13} {'map':4} {'mae':>5} {'p95':>5} {'jumps':>5} {'frozen':>6}")
for en in names:
    tot = dict(mae=0, p95=0, jumps=0, frozen=0)
    cnt = 0
    for sc in SCENARIOS:
        for mapok in (True, False):
            agg = dict(mae=0, p95=0, jumps=0, frozen=0)
            for s in seeds:
                m = run(EST[en], sc, mapok, s)
                for k in agg:
                    agg[k] += m[k] / len(seeds)
            for k in tot:
                tot[k] += agg[k]
            cnt += 1
            print(f"{en:16} {sc:13} {'y' if mapok else 'n':4} {agg['mae']:5.2f} {agg['p95']:5.2f} {agg['jumps']:5.1f} {agg['frozen']:6.2f}")
    print(f"{en:16} {'TOTAL':13} {'':4} {tot['mae']/cnt:5.2f} {tot['p95']/cnt:5.2f} {tot['jumps']:5.1f} {tot['frozen']:6.2f}")
    print()
