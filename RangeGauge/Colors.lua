-- Colors: the look shared by both views (lights and bar), so they always match.
-- Inside your reach the colors are bright, outside they're dark, with a hard switch at the line:
--   red (melee) -> orange (near) -> green (good) -> teal (max) | dark purple (almost/out) -> royal blue (far)

local _, ns = ...

ns.MELEE_YARDS = 5
local NEAR_YARDS = 5    -- first stretch outside melee: fades orange -> green
local MAX_YARDS = 7      -- last stretch inside your reach: fades green -> teal
local ALMOST_YARDS = 10  -- first stretch outside your reach
local FAR_YARDS = 50     -- this far or more = deep blue, nothing to worry about yet

local MELEE = { 1, 0.15, 0.15 }
local NEAR = { 1, 0.5, 0.1 }
local GOOD = { 0.2, 1, 0.3 }
local MAX = { 0.2, 0.75, 0.8 }      -- teal: halfway between green and the dark purple outside
local OUT_NEAR = { 0.55, 0.22, 0.9 }
local OUT_FAR = { 0.08, 0.1, 0.55 } -- deep royal blue
local UNKNOWN = { 0.7, 0.7, 0.7 }

-- Labels for each state; "edge" is the near-max-range stretch
ns.STATE_TEXT = {
  melee = "MELEE", near = "NEAR", reach = "GOOD", edge = "MAX",
  almost = "ALMOST", out = "OUT", far = "FAR", unknown = "?",
}

-- Color at `yards` along a list of { yards, color } stops, sorted from near to far
local function Gradient(stops, yards)
  if yards <= stops[1][1] then return unpack(stops[1][2]) end
  for i = 2, #stops do
    local a, b = stops[i - 1], stops[i]
    if yards <= b[1] then
      local f = (yards - a[1]) / (b[1] - a[1])
      return a[2][1] + (b[2][1] - a[2][1]) * f,
        a[2][2] + (b[2][2] - a[2][2]) * f,
        a[2][3] + (b[2][3] - a[2][3]) * f
    end
  end
  return unpack(stops[#stops][2])
end

local function InsideColor(yards)
  return Gradient({
    { ns.MELEE_YARDS, NEAR },
    { ns.MELEE_YARDS + NEAR_YARDS, GOOD },
    { ns.reachYards - MAX_YARDS, GOOD },
    { ns.reachYards, MAX },
  }, yards)
end

local function OutsideColor(yards)
  return Gradient({
    { ns.reachYards, OUT_NEAR },
    { math.max(FAR_YARDS, ns.reachYards + ALMOST_YARDS + 4), OUT_FAR },
  }, yards)
end

-- Color for a distance alone; used to paint the bar's scale
function ns.ScaleColor(yards)
  if yards < ns.MELEE_YARDS then return unpack(MELEE) end
  if yards < ns.reachYards then return InsideColor(yards) end
  return OutsideColor(yards)
end

-- Picks the state from the zone (exact) and the band (rough yards)
function ns.StateFor(lo, hi, zone)
  if zone == "reach" and lo >= ns.reachYards - MAX_YARDS then return "edge" end
  if zone == "reach" and hi and hi <= ns.MELEE_YARDS + NEAR_YARDS then return "near" end
  if zone == "out" and hi and hi <= ns.reachYards + ALMOST_YARDS then return "almost" end
  if zone == "out" and lo >= FAR_YARDS then return "far" end
  return zone
end

-- Color for a state at the live distance `yards`; the zone decides which fade to use,
-- so the color never contradicts the exact in/out reading
function ns.StateColor(state, yards)
  if state == "melee" then return unpack(MELEE) end
  if state == "unknown" then return unpack(UNKNOWN) end
  if state == "reach" or state == "edge" or state == "near" then
    return InsideColor(math.min(yards, ns.reachYards))
  end
  return OutsideColor(math.max(yards, ns.reachYards))
end

-- Did the unit step into or out of a zone (melee / reach / out)? Unknown readings don't count.
function ns.ZoneChanged(old, new)
  return old ~= nil and old ~= new and old ~= "unknown" and new ~= "unknown"
end

-- The click both views play for your target (/rg sound turns it off)
function ns.PlayZoneSound(zone)
  if RangeGaugeDB.sound == false then return end
  PlaySound(zone == "out" and "igMainMenuOptionCheckBoxOff" or "igMainMenuOptionCheckBoxOn")
end
