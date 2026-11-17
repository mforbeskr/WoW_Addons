"""Simulated world for RangeGauge: player/target movement, WoW-style yes/no range checks,
and metrics on how well an estimator's displayed yards follow the truth."""
import math, random

DT = 1 / 60
TICK = 0.05
K_REACH = 3.0  # center distance - spell distance (combat reach of both units)
REACH = 35

# (yards, bias, kind). bias = how far off the real threshold is from the label (spell-yards).
CHECKS = [
    (8, 0.0, "item"), (8, 0.3, "interact"), (9, -0.3, "interact"), (10, 0.0, "item"),
    (15, 0.0, "item"), (15, 0.0, "spell"), (20, 0.0, "item"), (25, 0.0, "item"),
    (28, 0.4, "interact"), (30, 0.0, "item"), (40, 0.0, "item"), (45, 0.0, "item"),
    (60, 0.0, "item"), (80, 0.0, "item"),
]


class Path:
    """Piecewise motion: list of (duration, vx, vy) segments starting at pos."""
    def __init__(self, pos, segs):
        self.pos0 = pos
        self.segs = segs

    def total(self):
        return sum(s[0] for s in self.segs)


def follow(start, segs_fn):
    return start, segs_fn


class World:
    def __init__(self, player_fn, target_fn, duration, mapok=True, seed=1, flaky=None):
        self.rng = random.Random(seed)
        self.pf, self.tf = player_fn, target_fn
        self.duration = duration
        self.mapok = mapok
        self.t = 0.0
        self.P = (0.0, 0.0)
        self.T = (0.0, 0.0)
        self.pv = (0.0, 0.0)
        self.tv = (0.0, 0.0)
        self.flaky = flaky  # index of a check that answers randomly near its edge

    def step(self):
        self.t += DT
        self.pv = self.pf(self, self.t)
        self.tv = self.tf(self, self.t)
        self.P = (self.P[0] + self.pv[0] * DT, self.P[1] + self.pv[1] * DT)
        self.T = (self.T[0] + self.tv[0] * DT, self.T[1] + self.tv[1] * DT)

    def spell_dist(self):
        return math.hypot(self.P[0] - self.T[0], self.P[1] - self.T[1]) - K_REACH

    # --- the API the estimators may use ---
    def speeds(self):
        return math.hypot(*self.pv), math.hypot(*self.tv)

    def player_pos(self):
        return self.P if self.mapok else None

    def read_checks(self):
        """Returns melee(bool), inReach(bool), list of (yards, result)."""
        s = self.spell_dist()
        out = []
        for i, (y, bias, kind) in enumerate(CHECKS):
            jitter = self.rng.gauss(0, 0.05)
            if self.flaky == i and abs(s - y) < 3:
                r = self.rng.random() < 0.5
            else:
                r = s <= y + bias + jitter
            out.append((y, r))
        return s <= 5, s <= REACH, out


# ---------------------------------------------------------------- scenarios

def seg_motion(segs):
    """segs: list of (duration, fn(world)->velocity)."""
    bounds = []
    acc = 0
    for d, f in segs:
        bounds.append((acc, acc + d, f))
        acc += d

    def fn(w, t):
        for a, b, f in bounds:
            if a <= t < b:
                return f(w)
        return (0.0, 0.0)
    return fn, acc


def radial(speed):
    """Player moves straight away (+) / toward (-) the target."""
    def f(w):
        dx, dy = w.P[0] - w.T[0], w.P[1] - w.T[1]
        d = math.hypot(dx, dy) or 1
        return (dx / d * speed, dy / d * speed)
    return f


def target_radial(speed):
    def f(w):
        dx, dy = w.T[0] - w.P[0], w.T[1] - w.P[1]
        d = math.hypot(dx, dy) or 1
        return (dx / d * speed, dy / d * speed)
    return f


def tangent(speed, mix=0.0):
    def f(w):
        dx, dy = w.P[0] - w.T[0], w.P[1] - w.T[1]
        d = math.hypot(dx, dy) or 1
        tx, ty = -dy / d, dx / d
        return ((tx + dx / d * mix) * speed, (ty + dy / d * mix) * speed)
    return f


def still(w):
    return (0.0, 0.0)


def const(vx, vy):
    return lambda w: (vx, vy)


def scenario(name, mapok=True, seed=1):
    rng = random.Random(seed)
    if name == "dummy_walk":
        pf, dur = seg_motion([
            (1, still), (4.3, radial(7)), (2, still), (3.5, radial(-7)), (1, still),
            (3.5, radial(4.5)), (1.5, still), (0.4, radial(-7)), (0.6, still), (0.4, radial(7)),
            (0.5, still), (0.3, radial(-7)), (2, still), (2.5, radial(-7)), (1, still),
        ])
        w = World(pf, lambda w, t: (0.0, 0.0), dur, mapok, seed)
        w.P = (20 + K_REACH, 0.0)
        return w
    if name == "dummy_strafe":
        pf, dur = seg_motion([
            (1, still), (3, tangent(7, 0.3)), (2, tangent(7, -0.4)), (1, still), (3, tangent(-7, 0.5)),
            (2, radial(7)), (3, tangent(7, -0.2)), (1.5, still), (3, tangent(-7, -0.5)), (2, tangent(7, 0.6)),
        ])
        w = World(pf, lambda w, t: (0.0, 0.0), dur, mapok, seed)
        w.P = (25 + K_REACH, 0.0)
        return w
    if name == "hover":
        def pf(w, t):
            if t < 1:
                return (0.0, 0.0)
            ph = math.sin((t - 1) * math.pi)  # 2 s period
            return radial(2.5 * ph)(w)
        w = World(pf, lambda w, t: (0.0, 0.0), 20, mapok, seed)
        w.P = (34.2 + K_REACH, 0.0)
        return w
    if name == "chase":
        tf, dur = seg_motion([
            (1, still), (6.5, target_radial(-7)), (1, still), (6, target_radial(7)), (1, still),
            (3, target_radial(-7)), (2, tangent(7)),
        ])
        w = World(lambda w, t: (0.0, 0.0), tf, dur, mapok, seed)
        w.T = (50 + K_REACH, 0.0)
        return w
    if name == "pvp_random":
        def make_rand(r):
            segs = []
            for _ in range(40):
                d = r.uniform(0.4, 2.0)
                sp = r.choice([0, 4.5, 7, 7, 7])
                a = r.uniform(0, 2 * math.pi)
                segs.append((d, (sp * math.cos(a), sp * math.sin(a))))
            return segs

        def bounded(segs, who):
            bounds, acc = [], 0
            for d, v in segs:
                bounds.append((acc, acc + d, v))
                acc += d

            def fn(w, t):
                for a, b, v in bounds:
                    if a <= t < b:
                        # keep the two within ~60 yd: steer back toward the other one when far
                        me = w.P if who == "p" else w.T
                        other = w.T if who == "p" else w.P
                        dx, dy = other[0] - me[0], other[1] - me[1]
                        dd = math.hypot(dx, dy)
                        if dd > 55 and (v[0] * dx + v[1] * dy) < 0:
                            return (-v[0], -v[1])
                        return v
                return (0.0, 0.0)
            return fn, acc
        pf, d1 = bounded(make_rand(rng), "p")
        tf, d2 = bounded(make_rand(rng), "t")
        w = World(pf, tf, min(d1, d2, 50), mapok, seed)
        w.T = (30 + K_REACH, 0.0)
        return w
    raise ValueError(name)


SCENARIOS = ["dummy_walk", "dummy_strafe", "hover", "chase", "pvp_random"]


def run(make_estimator, name, mapok=True, seed=1, flaky=None, trace=False):
    w = scenario(name, mapok, seed)
    w.flaky = flaky
    est = make_estimator(w)
    since = TICK
    rows = []
    first = True
    while w.t < w.duration:
        w.step()
        since += DT
        if since >= TICK:
            since -= TICK
            est.tick(w, first)
            first = False
        disp = est.frame(w, DT)
        rows.append((w.t, w.spell_dist(), disp, sum(w.speeds())))
    return metrics(rows, trace)


def metrics(rows, trace=False):
    rows = [r for r in rows if r[0] > 1.0]
    errs = [abs(d - s) for _, s, d, _ in rows]
    n = len(errs)
    mae = sum(errs) / n
    p95 = sorted(errs)[int(n * 0.95)]
    # jumps: display moves more than physics allows + 1 yd within 0.3 s
    W = int(0.3 / DT)
    jumps, i = 0, 0
    while i + W < len(rows):
        dd = abs(rows[i + W][2] - rows[i][2])
        vmax = max(r[3] for r in rows[i:i + W + 1])
        if dd > vmax * 0.3 + 1.0:
            jumps += 1
            i += W
        else:
            i += 1
    # freeze: truth moves > 1.5 yd in 0.5 s but display < 0.3 yd
    W2 = int(0.5 / DT)
    frozen = 0
    for i in range(0, len(rows) - W2, 5):
        if abs(rows[i + W2][1] - rows[i][1]) > 1.5 and abs(rows[i + W2][2] - rows[i][2]) < 0.3:
            frozen += 1
    frozen_s = frozen * 5 * DT
    out = dict(mae=mae, p95=p95, jumps=jumps, frozen=frozen_s)
    if trace:
        out["rows"] = rows
    return out
