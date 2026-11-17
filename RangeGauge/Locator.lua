-- Locator: your own position in yards, from the map. Used by the trackers to work out where a
-- standing target is (each checkpoint crossing pins it on a circle around where you were).
--
-- Map coordinates go 0-1 across the zone map, so we need the map's size in yards. Instead of a
-- table of zone sizes we learn it: while you run, the game tells your speed (yards/s) and the
-- map tells how far you moved (map units), and speed * time / distance = yards per map unit.
-- Learned sizes are saved per map, so each zone only needs learning once.

local _, ns = ...

local ASPECT = 1.5          -- every zone map is 3:2, so a y map unit is 2/3 of an x map unit
local SAMPLE_TIME = 0.2     -- seconds between calibration samples
local MAX_SAMPLES = 31
local MIN_SAMPLES = 7
local MAX_SPREAD = 0.08     -- samples must agree within this (relative) before we use them

ns.mapVersion = 0           -- bumps when the map changes: trackers start their map work over

local mapKey                -- which map the coordinates belong to
local scale                 -- yards per x map unit on that map (nil = not known yet)
local samples = {}          -- recent calibration samples for this map
local sorted = {}

local function Median()
  local n = #samples
  for i = 1, n do sorted[i] = samples[i] end
  for i = n + 1, #sorted do sorted[i] = nil end
  table.sort(sorted)
  local mid = sorted[math.floor((n + 1) / 2)]
  local q1, q3 = sorted[math.floor(n / 4) + 1], sorted[math.floor(3 * n / 4)]
  return mid, (q3 - q1) / mid
end

local function UpdateKey()
  local file = GetMapInfo()
  local level = GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or 0
  local key = file and (file .. "#" .. level) or nil
  if key ~= mapKey then
    mapKey = key
    wipe(samples)
    scale = nil
    ns.mapVersion = ns.mapVersion + 1
  end
  -- A size learned in an earlier session (saved variables may load after the first map event)
  if not scale and key and RangeGaugeDB and RangeGaugeDB.scales then
    scale = RangeGaugeDB.scales[key]
  end
end

-- Keep the map on the zone you're in (unless you're looking at the world map yourself)
local function ToCurrentZone()
  if not (WorldMapFrame and WorldMapFrame:IsShown()) then
    SetMapToCurrentZone()
  end
  UpdateKey()
end

-- Your position in yards on the current map, or nil if the map can't tell (some instances,
-- or the map size isn't learned yet)
function ns.PlayerYards()
  if not scale then return nil end
  local x, y = GetPlayerMapPosition("player")
  if not x or (x == 0 and y == 0) then return nil end
  return x * scale, y * scale / ASPECT
end

function ns.LocatorStatus()
  local x, y = GetPlayerMapPosition("player")
  if not x or (x == 0 and y == 0) then
    return "|cffff5555not available here|r (range from checks only)"
  end
  if scale then
    return string.format("|cff55ff55ready|r (map %s, %.0f yd wide)", mapKey or "?", scale)
  end
  return string.format("|cffffaa33learning|r (%d/%d samples - just run around a bit)", #samples, MIN_SAMPLES)
end

-- Calibration: a few times per second, compare your speed with how far the map says you moved
local f = CreateFrame("Frame")
local since, lastX, lastY, lastSpeed, lastTime = 0
f:SetScript("OnUpdate", function(_, elapsed)
  since = since + elapsed
  if since < SAMPLE_TIME then return end
  since = 0

  local now = GetTime()
  local x, y = GetPlayerMapPosition("player")
  local speed = GetUnitSpeed("player")
  local ok = x and (x ~= 0 or y ~= 0) and mapKey
    and not UnitOnTaxi("player") and not (IsFalling and IsFalling())
    and not UnitInVehicle("player")
  if ok and lastX and speed > 0 and speed == lastSpeed then
    local dx, dy = x - lastX, (y - lastY) / ASPECT
    local d = math.sqrt(dx * dx + dy * dy)
    local dt = now - lastTime
    if d > 0 and dt > 0.1 and dt < 0.4 then
      if #samples >= MAX_SAMPLES then table.remove(samples, 1) end
      samples[#samples + 1] = speed * dt / d
      if #samples >= MIN_SAMPLES then
        local mid, spread = Median()
        if spread < MAX_SPREAD then
          if not scale or math.abs(mid - scale) / scale > 0.002 then
            if scale and math.abs(mid - scale) / scale > 0.05 then
              ns.mapVersion = ns.mapVersion + 1 -- big change: old map work is off, start over
            end
            scale = mid
            if RangeGaugeDB then
              RangeGaugeDB.scales = RangeGaugeDB.scales or {}
              RangeGaugeDB.scales[mapKey] = math.floor(mid * 10 + 0.5) / 10
            end
          end
        end
      end
    end
  end
  if ok then
    lastX, lastY, lastSpeed, lastTime = x, y, speed, now
  else
    lastX = nil
  end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
events:RegisterEvent("WORLD_MAP_UPDATE")
events:SetScript("OnEvent", function(_, event)
  if event == "WORLD_MAP_UPDATE" then
    UpdateKey()
  else
    ToCurrentZone()
  end
end)

if WorldMapFrame then
  WorldMapFrame:HookScript("OnHide", ToCurrentZone)
end
