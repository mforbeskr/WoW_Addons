-- Tracker: turns stepwise range readings into a smooth, live distance for one unit.
-- The game only says which band the unit is in (e.g. 35-40 yd), but the moment the band
-- changes, the unit is standing right ON the checkpoint it crossed. Two crossings give a speed;
-- between crossings we keep moving at that speed, kept inside the current band, and the shown
-- value follows on a spring so corrections glide instead of jumping.

local _, ns = ...

local MAX_SPEED = 20       -- yards per second; caps the estimate after blinks and charges
local SPEED_MEMORY = 0.25  -- how fast an old speed is forgotten when no new crossing comes
local SMOOTH_TIME = 0.25   -- seconds the spring takes to settle; higher = calmer
local MELEE_YARDS = 5

-- A critically damped spring (same formula as Unity's SmoothDamp): accelerates and brakes
-- smoothly toward the target, never overshooting. Returns the new value and its velocity.
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

function ns.NewTracker()
  return setmetatable({ lo = 0, zone = "out", estimate = 0, speed = 0, display = 0, velocity = 0 }, Tracker)
end

-- Keeps a distance inside the current band (and on the right side of the exact reach line)
function Tracker:Clamp(yards)
  if self.zone == "melee" then return MELEE_YARDS / 2 end
  local lo, hi = self.lo, self.hi
  if self.zone == "reach" then
    hi = math.min(hi or math.huge, ns.reachYards - 0.5)
  elseif self.zone == "out" then
    lo = math.max(lo, ns.reachYards + 0.5)
  end
  if not hi then return math.max(lo, yards) end -- beyond every check: only a lower bound
  if hi < lo then return (lo + hi) / 2 end
  return math.max(lo, math.min(hi, yards))
end

-- Feed a new reading. fresh = a new unit: start in the middle of its band, no speed.
function Tracker:Read(lo, hi, zone, fresh)
  local oldLo, oldHi, oldZone = self.lo, self.hi, self.zone
  self.lo, self.hi, self.zone = lo, hi, zone

  if fresh then
    self.estimate = self:Clamp(hi and (lo + hi) / 2 or lo)
    self.display, self.velocity = self.estimate, 0
    self.speed, self.lastCross = 0, nil
    return
  end
  if lo == oldLo and hi == oldHi and zone == oldZone then return end

  -- Which checkpoint did the unit just cross?
  local crossed
  if oldHi and lo >= oldHi then
    crossed = lo -- moved out past it
  elseif hi and hi <= oldLo then
    crossed = hi -- moved in past it
  end
  if crossed then
    local now = GetTime()
    local last = self.lastCross
    if last and now - last.time < 3 then
      local speed = (crossed - last.yards) / (now - last.time)
      self.speed = math.max(-MAX_SPEED, math.min(MAX_SPEED, speed))
    else
      self.speed = 0
    end
    self.lastCross = { yards = crossed, time = now }
    self.estimate = crossed
  end
  self.estimate = self:Clamp(self.estimate)
end

-- Advance by dt seconds; afterwards self.display is the smooth distance to show
function Tracker:Step(dt)
  -- Hitting the edge of the band means the guess ran ahead of reality: stop and wait
  local guess = self.estimate + self.speed * dt
  self.estimate = self:Clamp(guess)
  if self.estimate ~= guess then self.speed = 0 end
  self.speed = self.speed * math.max(0, 1 - dt * SPEED_MEMORY)
  self.display, self.velocity = SmoothDamp(self.display, self.estimate, self.velocity, SMOOTH_TIME, dt)
end
