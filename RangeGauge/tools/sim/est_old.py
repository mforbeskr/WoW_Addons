"""Port of the current Lua tracker (Checks.lua Measure + Tracker.lua) for a baseline."""
import math
from world import REACH

# Labels the current addon uses, by CHECKS index (world.py order).
# Current addon: duel=10, trade=11 (real ~8/9), GRL labelled 50 (real 45, if LibRangeCheck is right).
LABELS_CURRENT = [8, 10, 11, 10, 15, 15, 20, 25, 28, 30, 40, 50, 60, 80]
LABELS_FIXED = [8, 8, 9, 10, 15, 15, 20, 25, 28, 30, 40, 45, 60, 80]
USE_CURRENT = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}  # current addon has no 60/80 checks


def smooth_damp(cur, target, vel, st, dt):
    omega = 2 / st
    x = omega * dt
    decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
    change = cur - target
    temp = (vel + omega * change) * dt
    return target + (change + temp) * decay, (vel - omega * temp) * decay


def measure_old(w, labels, use):
    melee, inreach, res = w.read_checks()
    if melee:
        return 0, 5, "melee"
    lo, hi = 0, None

    def rec(y, r):
        nonlocal lo, hi
        if r:
            if hi is None or y < hi:
                hi = y
        else:
            if y > lo:
                lo = y
    rec(REACH, inreach)
    for i, (_, r) in enumerate(res):
        if i in use:
            rec(labels[i], r)
    if hi is not None and lo >= hi:
        lo = max(0, hi - 1)
    zone = "reach" if inreach else "out"
    return lo, hi, zone


class OldTracker:
    MAX_SPEED, SPEED_MEMORY, SMOOTH, ASSUMED, MIN_SPEED = 20, 0.25, 0.25, 7, 0.05

    def __init__(self, labels=LABELS_CURRENT, use=USE_CURRENT):
        self.labels, self.use = labels, use
        self.lo, self.hi, self.zone = 0, None, "out"
        self.estimate = self.speed = self.display = self.velocity = 0
        self.lastY = self.lastT = self.limit = None

    def clamp(self, y):
        if self.zone == "melee":
            return 2.5
        lo, hi = self.lo, self.hi
        if self.zone == "reach":
            hi = min(hi if hi is not None else 1e9, REACH - 0.5)
        elif self.zone == "out":
            lo = max(lo, REACH + 0.5)
        if hi is None or hi >= 1e9:
            return max(lo, y)
        if hi < lo:
            return (lo + hi) / 2
        return max(lo, min(hi, y))

    def tick(self, w, fresh):
        lo, hi, zone = measure_old(w, self.labels, self.use)
        olo, ohi, oz = self.lo, self.hi, self.zone
        self.lo, self.hi, self.zone = lo, hi, zone
        if fresh:
            self.estimate = self.clamp((lo + hi) / 2 if hi is not None else lo)
            self.display, self.velocity = self.estimate, 0
            self.speed, self.lastY, self.lastT, self.limit = 0, None, None, None
            return
        if lo == olo and hi == ohi and zone == oz:
            return
        crossed = None
        if ohi is not None and lo >= ohi:
            crossed = lo
        elif hi is not None and hi <= olo:
            crossed = hi
        if crossed is not None:
            now = w.t
            d = 1 if crossed == lo else -1
            sp = None
            recent = self.lastT is not None and now - self.lastT < 3
            if recent and now > self.lastT:
                sp = (crossed - self.lastY) / (now - self.lastT)
            if sp is not None and sp * d > 0:
                self.speed = max(-20, min(20, sp))
                self.limit = None
            elif recent:
                self.speed, self.limit = 0, None
            else:
                self.speed = d * self.ASSUMED
                self.limit = (lo + hi) / 2 if hi is not None else lo + 2.5
            self.lastY, self.lastT = crossed, now
            self.estimate = crossed
        self.estimate = self.clamp(self.estimate)

    def frame(self, w, dt):
        guess = self.estimate + self.speed * dt
        if self.limit is not None and ((self.speed > 0 and guess >= self.limit) or (self.speed < 0 and guess <= self.limit)):
            guess, self.speed, self.limit = self.limit, 0, None
        self.estimate = self.clamp(guess)
        if self.estimate != guess:
            self.speed = 0
        self.speed *= max(0, 1 - dt * self.SPEED_MEMORY)
        if abs(self.speed) < self.MIN_SPEED:
            self.speed = 0
        self.display, self.velocity = smooth_damp(self.display, self.estimate, self.velocity, self.SMOOTH, dt)
        if self.zone == "melee":
            return 2.5
        return self.display
