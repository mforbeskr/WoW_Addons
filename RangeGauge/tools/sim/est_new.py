"""New estimator prototype: robust band + speed-bounded 1D tracker + 2D particle filter."""
import math, random
from world import REACH, TICK

LABELS = [8, 8, 9, 10, 15, 15, 20, 25, 28, 30, 40, 45, 60, 80]
FAR = 100

P = dict(
    margin=0.5,       # extra yd/s on the physical speed bound (latency, turning)
    assume=0.85,      # fraction of combined speed assumed radial on a first crossing
    frac_mem=0.15,    # how fast a remembered direction fades (per s)
    st_fast=0.08,     # display spring when the estimate is sure
    st_slow=0.22,     # display spring when unsure
    N=300,
    sig_band=0.45,
    sig_reach=0.15,
    turn=1.0,         # target heading change (rad/sqrt(s)) in the particle filter
    kmax=6.0,
    pf_trust=1.0,
    pf_move=1.0,
    speed_works=True,
    blind_speed=7.0,
    stop_forget=0.25,
    drift=True,
    offset_display=True,
    st_corr=0.25,
)


def smooth_damp(cur, target, vel, st, dt):
    omega = 2 / st
    x = omega * dt
    decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
    change = cur - target
    temp = (vel + omega * change) * dt
    return target + (change + temp) * decay, (vel - omega * temp) * decay


def robust_band(res, inreach):
    """Split the sorted checks where the fewest answers disagree; reach counts triple."""
    items = sorted([(LABELS[i], r, 1) for i, (_, r) in enumerate(res) if r is not None] + [(REACH, inreach, 3)])
    n = len(items)
    # cost[j]: checks [0, j) should be False, [j, n) True
    falses_after = sum(w for _, r, w in items if not r)
    trues_before = 0
    best, bj = None, []
    for j in range(n + 1):
        c = trues_before + falses_after
        if best is None or c < best:
            best, bj = c, [j]
        elif c == best:
            bj.append(j)
        if j < n:
            y, r, w = items[j]
            if r:
                trues_before += w
            else:
                falses_after -= w
    j0, j1 = bj[0], bj[-1]
    lo = items[j0 - 1][0] if j0 > 0 else 0
    hi = items[j1][0] if j1 < n else None
    return lo, hi


class Tracker1D:
    def __init__(self):
        self.a = self.b = self.est = 0.0
        self.frac = 0.0
        self.still = 0.0
        self.lo, self.hi = 0, FAR
        self.last = None  # (yards, time, dir)

    def reset(self, lo, hi):
        self.lo, self.hi = lo, hi
        self.a, self.b = lo, hi
        self.est = (lo + hi) / 2 if hi < FAR else lo + 2.5
        self.frac = 0.0
        self.last = None

    def read(self, lo, hi, now, vm):
        plo, phi = self.lo, self.hi
        self.lo, self.hi = lo, hi
        c = d = None
        if lo >= phi:
            c, d = lo, 1
        elif hi <= plo:
            c, d = hi, -1
        if c is not None:
            slack = (vm + P["margin"]) * TICK
            if d > 0:
                self.a, self.b = c, min(c + slack, hi)
            else:
                self.a, self.b = max(c - slack, lo), c
            self.est = c + d * slack * 0.5
            last = self.last
            recent = last and now - last[1] < 3
            v = (c - last[0]) / (now - last[1]) if recent and now > last[1] else None
            if v is not None and v * d > 0:
                self.frac = max(-1.0, min(1.0, v / max(vm, 0.5))) if vm > 0.05 else 0.0
            elif recent:
                self.frac = 0.0  # hovering on the checkpoint / turned around
            else:
                self.frac = d * P["assume"]
            self.last = (c, now, d)
        else:
            self.a, self.b = max(self.a, lo), min(self.b, hi)
            if self.a > self.b:  # teleport / charge / bad speed: start over in the band
                self.a, self.b = lo, hi
        self.est = min(max(self.est, self.a), self.b)

    def step(self, dt, vm):
        grow = (vm + P["margin"]) * dt if vm > 0.05 else 0.0
        self.a = max(self.a - grow, self.lo)
        self.b = min(self.b + grow, self.hi)
        if vm <= 0.05:
            self.still += dt
            if self.still > P["stop_forget"]:
                self.frac = 0.0
        else:
            self.still = 0.0
        self.frac *= max(0.0, 1 - dt * P["frac_mem"])
        g = self.est + self.frac * vm * dt
        if P["drift"] and vm > 0.05 and self.frac == 0:
            # direction unknown: drift toward the middle of what's possible
            mid = (self.a + self.b) / 2
            g += max(-vm * dt * 0.5, min(vm * dt * 0.5, mid - g))
        c = min(max(g, self.a), self.b)
        if c != g and self.frac != 0 and (c - g) * self.frac < 0:
            self.frac = 0.0  # ran into what's possible: they slowed or turned
        self.est = c
        w = self.b - self.a
        return self.est, w * w / 12 + 0.05


class Particles:
    def __init__(self, rng):
        self.rng = rng
        self.on = False

    def init(self, lo, hi, Ppos):
        r = self.rng
        n = P["N"]
        top = min(hi, lo + 25)
        self.x, self.y, self.k, self.h, self.w = [], [], [], [], []
        for _ in range(n):
            s = r.uniform(lo, top)
            k = r.uniform(0, P["kmax"])
            a = r.uniform(0, 2 * math.pi)
            self.x.append(Ppos[0] + (s + k) * math.cos(a))
            self.y.append(Ppos[1] + (s + k) * math.sin(a))
            self.k.append(k)
            self.h.append(r.uniform(0, 2 * math.pi))
            self.w.append(1 / n)
        self.on = True

    def move(self, dt, st):
        if st < 0.05:
            return
        r = self.rng
        sd = P["turn"] * math.sqrt(dt)
        x, y, h = self.x, self.y, self.h
        for i in range(len(x)):
            hi = h[i] + r.gauss(0, sd)
            h[i] = hi
            x[i] += st * dt * math.cos(hi)
            y[i] += st * dt * math.sin(hi)

    def update(self, lo, hi, zone, Ppos):
        px, py = Ppos
        x, y, k, w = self.x, self.y, self.k, self.w
        sb, sr = P["sig_band"], P["sig_reach"]
        slo = sr if lo == REACH else sb
        shi = sr if hi == REACH else sb
        tot = 0.0
        for i in range(len(x)):
            s = math.hypot(x[i] - px, y[i] - py) - k[i]
            if s < lo:
                e = (lo - s) / slo
                w[i] *= math.exp(-0.5 * e * e)
            elif s > hi:
                e = (s - hi) / shi
                w[i] *= math.exp(-0.5 * e * e)
            tot += w[i]
        if tot < 1e-30:
            self.init(lo, hi, Ppos)
            return
        ess_inv = 0.0
        for i in range(len(w)):
            w[i] /= tot
            ess_inv += w[i] * w[i]
        if 1 / ess_inv < len(w) / 2:
            self.resample()

    def resample(self):
        r = self.rng
        n = len(self.w)
        step = 1 / n
        u = r.uniform(0, step)
        c = self.w[0]
        j = 0
        nx, ny, nk, nh = [], [], [], []
        for i in range(n):
            while u > c and j < n - 1:
                j += 1
                c += self.w[j]
            nx.append(self.x[j] + r.gauss(0, 0.15))
            ny.append(self.y[j] + r.gauss(0, 0.15))
            nk.append(min(P["kmax"], max(0, self.k[j] + r.gauss(0, 0.05))))
            nh.append(self.h[j] + r.gauss(0, 0.15))
            u += step
        self.x, self.y, self.k, self.h = nx, ny, nk, nh
        self.w = [step] * n

    def estimate(self, Ppos):
        px, py = Ppos
        m = v = 0.0
        ss = []
        for i in range(len(self.x)):
            s = math.hypot(self.x[i] - px, self.y[i] - py) - self.k[i]
            ss.append(s)
            m += self.w[i] * s
        for i, s in enumerate(ss):
            v += self.w[i] * (s - m) ** 2
        return m, v


class Estimator:
    def __init__(self, use_map=True, seed=7):
        self.use_map = use_map
        self.t1 = Tracker1D()
        self.pf = Particles(random.Random(seed))
        self.display = self.dvel = 0.0
        self.lo, self.hi, self.zone = 0, FAR, "out"
        self.sure = 0.0
        self.prev = None
        self.off = self.offv = 0.0
        self.untrusted_until = -1

    def tick(self, w, fresh):
        melee, inreach, res = w.read_checks()
        lo, hi = robust_band(res, inreach)
        hi = FAR if hi is None else hi
        if melee:
            lo, hi, zone = 0, 5, "melee"
        elif inreach:
            zone = "reach"
            hi = min(hi, REACH)
            lo = min(lo, hi - 0.5)
        else:
            zone = "out"
            lo = max(lo, REACH)
            hi = max(hi, lo + 0.5)
        self.lo, self.hi, self.zone = lo, hi, zone
        sp, st = self.speeds(w)
        if fresh:
            self.t1.reset(lo, hi)
            self.display = self.t1.est
            self.prev = None
            self.off = self.offv = 0.0
            self.pf.on = False
        else:
            self.t1.read(lo, hi, w.t, sp + st)
        Ppos = w.player_pos() if self.use_map else None
        if Ppos is not None:
            if not self.pf.on:
                self.pf.init(lo, hi, Ppos)
            else:
                self.pf.update(lo, hi, zone, Ppos)
        else:
            self.pf.on = False

    def speeds(self, w):
        sp, st = w.speeds()
        if st > 0:
            P["speed_works"] = True
        if not P["speed_works"]:
            st = P["blind_speed"]  # target speed unknown: assume it may run
        return sp, st

    def frame(self, w, dt):
        sp, st = self.speeds(w)
        e1, v1 = self.t1.step(dt, sp + st)
        est, var = e1, v1
        Ppos = w.player_pos() if self.use_map else None
        if Ppos is not None and self.pf.on:
            self.pf.move(dt, st)
            e2, v2 = self.pf.estimate(Ppos)
            v2 = v2 * P["pf_trust"] * (1 + st * P["pf_move"]) + 0.02
            est = (e1 / v1 + e2 / v2) / (1 / v1 + 1 / v2)
            var = 1 / (1 / v1 + 1 / v2)
        lo, hi = self.lo, self.hi
        if self.zone == "reach":
            hi = min(hi, REACH - 0.05)
        elif self.zone == "out":
            lo = max(lo, REACH + 0.05)
        est = min(max(est, lo), hi)
        if P["offset_display"]:
            if self.prev is None:
                self.prev = est
            delta = est - self.prev
            allowed = (sp + st + P["margin"]) * dt
            if abs(delta) > allowed:
                ex = delta - math.copysign(allowed, delta)
                self.off -= ex
            self.prev = est
            self.off, self.offv = smooth_damp(self.off, 0.0, self.offv, P["st_corr"], dt)
            self.display = est + self.off
            return self.display
        sd = math.sqrt(var)
        st_ = P["st_fast"] if sd < 0.6 else P["st_slow"] if sd > 1.5 else P["st_fast"] + (sd - 0.6) / 0.9 * (P["st_slow"] - P["st_fast"])
        self.display, self.dvel = smooth_damp(self.display, est, self.dvel, st_, dt)
        return self.display
