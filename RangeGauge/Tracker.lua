-- Tracker: turns yes/no range readings into a smooth, live distance for one unit.
--
-- Two estimators run side by side and are blended by how sure each one is:
--
-- 1. Band tracker (always). The checks give a band (e.g. 30-35 yd). The game also tells how
--    fast you and the target move (GetUnitSpeed), so the distance can't change faster than
--    your two speeds together: we keep the range of distances that are still possible, which
--    shrinks to a point every time a checkpoint is crossed. Two crossings give a direction and
--    speed; if nobody moves, the estimate stands still instead of drifting.
--
-- 2. Map tracker (when your map position is known, see Locator.lua). A cloud of guesses
--    ("particles") of where the target stands, each with its own heading. Every reading
--    removes the guesses that don't fit what the checks said from where you stood, so when
--    you move around a standing target, the cloud closes in on its real position and the
--    distance follows your own movement continuously, even inside a band.
--
-- The shown value follows the blended estimate exactly while it moves smoothly; only sudden
-- corrections (a checkpoint proving the guess wrong) are glided out over a moment.

local _, ns = ...

local FAR = 100             -- stands in for "beyond every check"
local MARGIN = 0.5          -- yd/s on top of the physical speed limit (latency, turning)
local ASSUME = 0.85         -- share of the speed assumed to be straight in/out on a first crossing
local DIR_FADE = 0.15       -- how fast a measured direction is forgotten (per second)
local STOP_FORGET = 0.25    -- nobody moved this long: forget which way they were going
local RECENT = 3            -- two crossings closer than this (seconds) give a measured speed
local CORRECTION_TIME = 0.25 -- seconds a correction takes to glide out
local BLIND_SPEED = 3       -- assumed target speed until the game has reported any unit's speed

-- Map tracker
local SIG_BAND = 0.45       -- how soft a band edge is (items aren't exact), yards
local SIG_REACH = 0.15      -- the reach line is exact
local TURN = 1.0            -- how fast a running target may change heading (rad per sqrt(s))
local KMAX = 6              -- unknown size of both units' hitboxes (ranges count from their edge)
local MOVE_DOUBT = 1.0      -- trust the map tracker less while the target runs
local TWO_PI = 2 * math.pi

local sqrt, cos, sin, log, exp, random = math.sqrt, math.cos, math.sin, math.log, math.exp, math.random
local max, min, abs = math.max, math.min, math.abs

ns.speedWorks = false       -- set once the game reports a speed for any unit other than you

local function Gauss()
  return sqrt(-2 * log(1 - random())) * cos(TWO_PI * random())
end

-- A critically damped spring (same formula as Unity's SmoothDamp)
local function SmoothDamp(current, target, velocity, smoothTime, dt)
  local omega = 2 / smoothTime
  local x = omega * dt
  local decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
  local change = current - target
  local temp = (velocity + omega * change) * dt
  return target + (change + temp) * decay, (velocity - omega * temp) * decay
end

local Tracker = {}
Tracker.__index = Tracker

-- particles: size of the map tracker's cloud (more = steadier, slower)
function ns.NewTracker(particles)
  local n = particles or 300
  return setmetatable({
    lo = 0, zone = "out", bLo = 0, bHi = FAR,
    a = 0, b = FAR, est1 = 0, frac = 0, still = 0,
    estimate = 0, speed = 0, display = 0, off = 0, offVel = 0,
    n = n, px = {}, py = {}, pk = {}, ph = {}, pw = {},
    qx = {}, qy = {}, qk = {}, qh = {}, -- spare arrays for resampling (no garbage)
    pfOn = false, mode = "band",
  }, Tracker)
end

function Tracker:Speeds()
  local sp = GetUnitSpeed("player") or 0
  local st = self.unit and GetUnitSpeed(self.unit) or 0
  if st > 0 then ns.speedWorks = true end
  if not ns.speedWorks then st = max(st, BLIND_SPEED) end
  return sp, st
end

-- Map tracker ------------------------------------------------------------------------------

function Tracker:PfInit(lo, hi, x0, y0)
  local px, py, pk, ph, pw, n = self.px, self.py, self.pk, self.ph, self.pw, self.n
  local top = min(hi, lo + 25)
  for i = 1, n do
    local s = lo + (top - lo) * random()
    local k = KMAX * random()
    local ang = TWO_PI * random()
    px[i] = x0 + (s + k) * cos(ang)
    py[i] = y0 + (s + k) * sin(ang)
    pk[i] = k
    ph[i] = TWO_PI * random()
    pw[i] = 1 / n
  end
  self.pfOn = true
  self.pfVersion = ns.mapVersion
end

function Tracker:PfResample()
  local px, py, pk, ph, pw, n = self.px, self.py, self.pk, self.ph, self.pw, self.n
  local qx, qy, qk, qh = self.qx, self.qy, self.qk, self.qh
  local step = 1 / n
  local u = random() * step
  local c, j = pw[1], 1
  for i = 1, n do
    while u > c and j < n do
      j = j + 1
      c = c + pw[j]
    end
    qx[i] = px[j] + 0.15 * Gauss()
    qy[i] = py[j] + 0.15 * Gauss()
    qk[i] = min(KMAX, max(0, pk[j] + 0.05 * Gauss()))
    qh[i] = ph[j] + 0.15 * Gauss()
    u = u + step
  end
  -- swap the arrays instead of copying
  self.px, self.qx = qx, px
  self.py, self.qy = qy, py
  self.pk, self.qk = qk, pk
  self.ph, self.qh = qh, ph
  for i = 1, n do pw[i] = step end
end

-- A new reading: guesses that don't fit the band (seen from where you stand) lose weight
function Tracker:PfUpdate(lo, hi, x0, y0)
  local px, py, pk, pw, n = self.px, self.py, self.pk, self.pw, self.n
  local R = ns.reachYards
  local sLo = lo == R and SIG_REACH or SIG_BAND
  local sHi = hi == R and SIG_REACH or SIG_BAND
  local total = 0
  for i = 1, n do
    local dx, dy = px[i] - x0, py[i] - y0
    local s = sqrt(dx * dx + dy * dy) - pk[i]
    if s < lo then
      local e = (lo - s) / sLo
      pw[i] = pw[i] * exp(-0.5 * e * e)
    elseif s > hi then
      local e = (s - hi) / sHi
      pw[i] = pw[i] * exp(-0.5 * e * e)
    end
    total = total + pw[i]
  end
  if total < 1e-30 then
    self:PfInit(lo, hi, x0, y0) -- nothing fits any more (blink, charge, teleport): start over
    return
  end
  local sumSq = 0
  for i = 1, n do
    local w = pw[i] / total
    pw[i] = w
    sumSq = sumSq + w * w
  end
  if 1 / sumSq < n / 2 then self:PfResample() end
end

function Tracker:PfMove(dt, st)
  if st < 0.05 then return end
  local px, py, ph, n = self.px, self.py, self.ph, self.n
  local turn = TURN * sqrt(dt)
  local stepLen = st * dt
  for i = 1, n do
    local h = ph[i] + turn * Gauss()
    ph[i] = h
    px[i] = px[i] + stepLen * cos(h)
    py[i] = py[i] + stepLen * sin(h)
  end
end

-- Weighted mean distance (from the edge of the hitboxes) and its spread
function Tracker:PfEstimate(x0, y0)
  local px, py, pk, pw, n = self.px, self.py, self.pk, self.pw, self.n
  local m, m2 = 0, 0
  for i = 1, n do
    local dx, dy = px[i] - x0, py[i] - y0
    local s = sqrt(dx * dx + dy * dy) - pk[i]
    m = m + pw[i] * s
    m2 = m2 + pw[i] * s * s
  end
  return m, max(0, m2 - m * m)
end

-- Readings ---------------------------------------------------------------------------------

-- Feed a new reading. hi = nil means beyond every check. fresh = a new unit: start over.
-- Returns true when the reading differs from the last one.
function Tracker:Read(unit, lo, hi, zone, fresh)
  local changed = fresh or lo ~= self.lo or hi ~= self.hi or zone ~= self.zone
  self.unit, self.lo, self.hi, self.zone = unit, lo, hi, zone
  local now = GetTime()

  -- The band in yards, tightened by the exact reach line
  local R = ns.reachYards
  local bLo, bHi = lo, hi or FAR
  if zone == "melee" then
    bLo = 0
  elseif zone == "reach" then
    bHi = min(bHi, R)
    bLo = min(bLo, bHi - 0.5)
  elseif zone == "out" then
    bLo = max(bLo, R)
    bHi = max(bHi, bLo + 0.5)
  end

  local sp, st = self:Speeds()
  local vm = sp + st

  if fresh then
    self.a, self.b = bLo, bHi
    self.est1 = bHi < FAR and (bLo + bHi) / 2 or bLo + 2.5
    self.frac, self.still, self.lastY, self.lastT = 0, 0, nil, nil
    self.off, self.offVel, self.prev = 0, 0, nil
    self.display = self.est1
    self.pfOn = false
  else
    -- Did it just cross a checkpoint? Then it's standing right on it.
    local pLo, pHi = self.bLo, self.bHi
    local c, d
    if bLo >= pHi then
      c, d = bLo, 1
    elseif bHi <= pLo then
      c, d = bHi, -1
    end
    if c then
      local slack = (vm + MARGIN) * min(0.1, now - (self.lastRead or now))
      if d > 0 then
        self.a, self.b = c, min(c + slack, bHi)
      else
        self.a, self.b = max(c - slack, bLo), c
      end
      self.est1 = c + d * slack * 0.5
      local recent = self.lastT and now - self.lastT < RECENT
      local v = recent and now > self.lastT and (c - self.lastY) / (now - self.lastT)
      if v and v * d > 0 then
        self.frac = vm > 0.05 and max(-1, min(1, v / max(vm, 0.5))) or 0 -- measured
      elseif recent then
        self.frac = 0 -- back and forth over the same checkpoint: hovering on it
      else
        self.frac = d * ASSUME -- first crossing: assume they keep going
      end
      self.lastY, self.lastT = c, now
    else
      self.a, self.b = max(self.a, bLo), min(self.b, bHi)
      if self.a > self.b then self.a, self.b = bLo, bHi end -- blink/charge: start over in the band
    end
    self.est1 = min(max(self.est1, self.a), self.b)
  end
  self.bLo, self.bHi = bLo, bHi
  self.lastRead = now

  -- Map tracker
  local x0, y0 = ns.PlayerYards()
  if x0 and zone ~= "unknown" then
    if not self.pfOn or self.pfVersion ~= ns.mapVersion then
      self:PfInit(bLo, bHi, x0, y0)
    else
      self:PfUpdate(bLo, bHi, x0, y0)
    end
  else
    self.pfOn = false
  end
  return changed
end

-- Advance by dt seconds; afterwards self.display is the distance to show.
-- Returns true when the shown value moved.
function Tracker:Step(dt)
  if dt <= 0 then return false end
  local sp, st = self:Speeds()
  local vm = sp + st

  -- Band tracker: what's still possible grows with the speeds, the guess moves along
  local grow = vm > 0.05 and (vm + MARGIN) * dt or 0
  self.a = max(self.a - grow, self.bLo)
  self.b = min(self.b + grow, self.bHi)
  if vm <= 0.05 then
    self.still = self.still + dt
    if self.still > STOP_FORGET then self.frac = 0 end
  else
    self.still = 0
  end
  self.frac = self.frac * max(0, 1 - dt * DIR_FADE)
  local g = self.est1 + self.frac * vm * dt
  if vm > 0.05 and self.frac == 0 then
    -- direction unknown: drift toward the middle of what's possible
    local mid = (self.a + self.b) / 2
    local lim = vm * dt * 0.5
    g = g + max(-lim, min(lim, mid - g))
  end
  local c = min(max(g, self.a), self.b)
  if c ~= g and self.frac ~= 0 and (c - g) * self.frac < 0 then
    self.frac = 0 -- ran into the edge of what's possible: they slowed down or turned
  end
  self.est1 = c
  self.speed = self.frac * vm
  local w = self.b - self.a
  local var1 = w * w / 12 + 0.05

  -- Map tracker, blended in by how sure it is
  local est = c
  self.mode = "band"
  if self.pfOn then
    local x0, y0 = ns.PlayerYards()
    if x0 and self.pfVersion == ns.mapVersion then
      self:PfMove(dt, st)
      local e2, var2 = self:PfEstimate(x0, y0)
      var2 = var2 * (1 + st * MOVE_DOUBT) + 0.02
      est = (c / var1 + e2 / var2) / (1 / var1 + 1 / var2)
      self.mode = var2 < var1 and "map" or "band+map"
    end
  end

  -- Never contradict the band or the exact reach line
  local lo, hi = self.bLo, self.bHi
  local R = ns.reachYards
  if self.zone == "reach" then
    hi = min(hi, R - 0.05)
  elseif self.zone == "out" then
    lo = max(lo, R + 0.05)
  end
  est = min(max(est, lo), hi)
  self.estimate = est

  -- Follow the estimate 1:1 while it moves at a possible speed; glide out sudden corrections
  local prev = self.prev or est
  local delta = est - prev
  local allowed = (vm + MARGIN) * dt
  if delta > allowed then
    self.off = self.off - (delta - allowed)
  elseif delta < -allowed then
    self.off = self.off - (delta + allowed)
  end
  self.prev = est
  self.off, self.offVel = SmoothDamp(self.off, 0, self.offVel, CORRECTION_TIME, dt)
  if abs(self.off) < 0.001 and abs(self.offVel) < 0.001 then self.off, self.offVel = 0, 0 end

  local old = self.display
  self.display = est + self.off
  return abs(self.display - old) > 0.001
end
