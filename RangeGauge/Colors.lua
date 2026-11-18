-- Colors: the look shared by both views (lights and bar), so they always match.
-- Two styles, picked per unit by its profile (Checks.lua):
--
-- attack (enemies): bright inside your reach, dark outside, with a hard switch at the line:
--   red (melee) -> orange (near) -> green (good) -> teal (max) | dark purple (almost/out) -> royal blue (far)
-- heal (allies): like raid frames, calm while you can heal them and warm once you can't:
--   green (in range) -> gold (edge) | red-orange (out) -> dim wine (far)
--
-- Every function takes the unit's reach (yards) and style.

local _, ns = ...

ns.MELEE_YARDS = 5
local NEAR_YARDS = 5    -- first stretch outside melee: fades orange -> green
local MAX_YARDS = 7      -- last stretch inside your reach: fades to the edge color
local ALMOST_YARDS = 10  -- first stretch outside your reach
local FAR_YARDS = 50     -- this far or more = the far color

local MELEE = { 1, 0.15, 0.15 }
local NEAR = { 1, 0.5, 0.1 }
local GOOD = { 0.2, 1, 0.3 }
local MAX = { 0.2, 0.75, 0.8 }      -- teal: halfway between green and the dark purple outside
local OUT_NEAR = { 0.55, 0.22, 0.9 }
local OUT_FAR = { 0.08, 0.1, 0.55 } -- deep royal blue
local UNKNOWN = { 0.7, 0.7, 0.7 }

local HEAL_GOOD = { 0.3, 0.95, 0.5 }   -- soft green: you can heal them
local HEAL_EDGE = { 1, 0.8, 0.25 }     -- gold: still in range, but one step from losing them
local HEAL_OUT = { 1, 0.32, 0.18 }     -- red-orange: can't heal them
local HEAL_FAR = { 0.45, 0.2, 0.26 }   -- dim wine: far away

-- Labels for each state; "edge" is the near-max-range stretch
local TEXT = {
  attack = {
    melee = "MELEE", near = "NEAR", reach = "GOOD", edge = "MAX",
    almost = "ALMOST", out = "OUT", far = "FAR", unknown = "?",
  },
  heal = {
    melee = "IN RANGE", near = "IN RANGE", reach = "IN RANGE", edge = "EDGE",
    almost = "OUT", out = "OUT", far = "FAR", unknown = "?",
  },
}
ns.STATE_TEXT = TEXT.attack

function ns.StateText(state, style)
  return (TEXT[style] or TEXT.attack)[state]
end

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

-- Stop lists built once; only the yards that depend on the reach are refreshed per call
local insideStops = {
  { ns.MELEE_YARDS, NEAR },
  { ns.MELEE_YARDS + NEAR_YARDS, GOOD },
  { 0, GOOD },
  { 0, MAX },
}
local outsideStops = { { 0, OUT_NEAR }, { 0, OUT_FAR } }
local healInsideStops = { { 0, HEAL_GOOD }, { 0, HEAL_EDGE } }
local healOutsideStops = { { 0, HEAL_OUT }, { 0, HEAL_FAR } }

local function InsideColor(yards, reach, style)
  if style == "heal" then
    healInsideStops[1][1] = reach - MAX_YARDS
    healInsideStops[2][1] = reach
    return Gradient(healInsideStops, yards)
  end
  insideStops[3][1] = reach - MAX_YARDS
  insideStops[4][1] = reach
  return Gradient(insideStops, yards)
end

local function OutsideColor(yards, reach, style)
  local stops = style == "heal" and healOutsideStops or outsideStops
  stops[1][1] = reach
  stops[2][1] = math.max(FAR_YARDS, reach + ALMOST_YARDS + 4)
  return Gradient(stops, yards)
end

-- Color for a distance alone; used to paint the bar's scale
function ns.ScaleColor(yards, reach, style)
  if style ~= "heal" and yards < ns.MELEE_YARDS then return unpack(MELEE) end
  if yards < reach then return InsideColor(yards, reach, style) end
  return OutsideColor(yards, reach, style)
end

-- Picks the state from the zone (exact) and the band (rough yards)
-- The zone is exact; inside it, the live yards pick the label, so label and number always agree
function ns.StateFor(zone, yards, reach, style)
  if zone == "reach" then
    if yards >= reach - MAX_YARDS then return "edge" end
    if style ~= "heal" and yards <= ns.MELEE_YARDS + NEAR_YARDS then return "near" end
  elseif zone == "out" then
    if yards <= reach + ALMOST_YARDS then return "almost" end
    if yards >= FAR_YARDS then return "far" end
  end
  return zone
end

-- Color for a state at the live distance `yards`; the zone decides which fade to use,
-- so the color never contradicts the exact in/out reading
function ns.StateColor(state, yards, reach, style)
  if state == "unknown" then return unpack(UNKNOWN) end
  if state == "melee" then
    if style == "heal" then return unpack(HEAL_GOOD) end
    return unpack(MELEE)
  end
  if state == "reach" or state == "edge" or state == "near" then
    return InsideColor(math.min(yards, reach), reach, style)
  end
  return OutsideColor(math.max(yards, reach), reach, style)
end

-- Did the unit step into or out of a zone (melee / reach / out)? Unknown readings don't count.
function ns.ZoneChanged(old, new)
  return old ~= nil and old ~= new and old ~= "unknown" and new ~= "unknown"
end

-- Slow "breathing" glow run by the game's animation system, so it costs no Lua per frame.
-- Pulses the alpha between low and high, about once every 2 seconds.
function ns.Breathe(tex, low, high)
  tex:SetAlpha(low)
  if not tex.CreateAnimationGroup then return end -- no animations: just a steady glow
  local ag = tex:CreateAnimationGroup()
  local a = ag:CreateAnimation("Alpha")
  a:SetChange(high - low)
  a:SetDuration(1.05)
  a:SetSmoothing("IN_OUT")
  ag:SetLooping("BOUNCE")
  ag:Play()
  tex.breathing = ag
end

-- Sets "24 yd", "40+ yd" or "" on a font string, only when the shown value actually changes
-- (no new strings every frame). `cache` is any table owned by the caller.
function ns.SetYardsText(fs, cache, t)
  local key
  if t.zone == "melee" then
    key = -1
  elseif not t.hi then
    key = 1000 + t.lo
  else
    key = math.floor(t.display + 0.5)
  end
  if key == cache.yardsKey then return end
  cache.yardsKey = key
  if key == -1 then
    fs:SetText("")
  elseif key >= 1000 then
    fs:SetText(t.lo .. "+ yd")
  else
    fs:SetText(key .. " yd")
  end
end

-- The click both views play for your target (/rg sound turns it off)
function ns.PlayZoneSound(zone)
  if RangeGaugeDB.sound == false then return end
  PlaySound(zone == "out" and "igMainMenuOptionCheckBoxOff" or "igMainMenuOptionCheckBoxOn")
end
