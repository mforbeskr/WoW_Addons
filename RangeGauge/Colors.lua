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

-- Stop lists built once; only the yards that depend on your reach are refreshed per call
local insideStops = {
  { ns.MELEE_YARDS, NEAR },
  { ns.MELEE_YARDS + NEAR_YARDS, GOOD },
  { 0, GOOD },
  { 0, MAX },
}
local outsideStops = {
  { 0, OUT_NEAR },
  { 0, OUT_FAR },
}

local function InsideColor(yards)
  insideStops[3][1] = ns.reachYards - MAX_YARDS
  insideStops[4][1] = ns.reachYards
  return Gradient(insideStops, yards)
end

local function OutsideColor(yards)
  outsideStops[1][1] = ns.reachYards
  outsideStops[2][1] = math.max(FAR_YARDS, ns.reachYards + ALMOST_YARDS + 4)
  return Gradient(outsideStops, yards)
end

-- Color for a distance alone; used to paint the bar's scale
function ns.ScaleColor(yards)
  if yards < ns.MELEE_YARDS then return unpack(MELEE) end
  if yards < ns.reachYards then return InsideColor(yards) end
  return OutsideColor(yards)
end

-- Picks the state from the zone (exact) and the band (rough yards)
-- The zone is exact; inside it, the live yards pick the label, so label and number always agree
function ns.StateFor(zone, yards)
  if zone == "reach" then
    if yards >= ns.reachYards - MAX_YARDS then return "edge" end
    if yards <= ns.MELEE_YARDS + NEAR_YARDS then return "near" end
  elseif zone == "out" then
    if yards <= ns.reachYards + ALMOST_YARDS then return "almost" end
    if yards >= FAR_YARDS then return "far" end
  end
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
