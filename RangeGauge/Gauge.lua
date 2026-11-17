-- Gauge: the bar view (/rg bar). Same readings, colors, labels, click and live tracking as the
-- lights, drawn as a vertical scale: 0 yd at the bottom, a little past your reach at the top.
-- Also home to the addon's setup, events and /rg commands.

local _, ns = ...

local BAR_HEIGHT = 220
local BAR_WIDTH = 10
local SCALE_PAST_REACH = 10   -- yards shown above the reach line
local TICK_YARDS = 5          -- a small tick mark every 5 yards
local UPDATE_INTERVAL = 0.05  -- 20 checks per second, same as the lights
local FADE_SPEED = 6          -- how fast the bar fades in and out
local FLASH_DECAY = 2.5       -- how fast the reach line flash dies down

function ns.Print(msg)
  print("|cffc77dffRange Gauge|r: " .. msg)
end

local g = CreateFrame("Frame", "RangeGaugeFrame", UIParent)
g:Hide()
g:SetWidth(110)
g:SetHeight(BAR_HEIGHT + 24)
g:SetClampedToScreen(true)
g:SetMovable(true)
g:RegisterForDrag("LeftButton")
g:SetScript("OnDragStart", g.StartMoving)
g:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, relPoint, x, y = self:GetPoint()
  RangeGaugeDB.point = { point, relPoint, x, y }
end)

local bar = CreateFrame("Frame", nil, g)
bar:SetWidth(BAR_WIDTH)
bar:SetHeight(BAR_HEIGHT)
bar:SetPoint("BOTTOMLEFT", 22, 4)

local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetPoint("TOPLEFT", -2, 2)
bg:SetPoint("BOTTOMRIGHT", 2, -2)
bg:SetTexture(0, 0, 0, 0.6)

local reachLine = bar:CreateTexture(nil, "OVERLAY")
reachLine:SetTexture(1, 1, 1, 0.9)
reachLine:SetWidth(BAR_WIDTH + 16)
reachLine:SetHeight(2)
local reachText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
reachText:SetPoint("RIGHT", reachLine, "LEFT", -2, 0)

local farText = g:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
farText:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -12, 5)
farText:SetText("far")

local marker = CreateFrame("Frame", nil, bar)
marker:SetWidth(BAR_WIDTH + 12)
marker:SetHeight(4)
local markerGlow = marker:CreateTexture(nil, "ARTWORK")
markerGlow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
markerGlow:SetBlendMode("ADD")
markerGlow:SetWidth(BAR_WIDTH + 44)
markerGlow:SetHeight(26)
markerGlow:SetPoint("CENTER")
local markerTex = marker:CreateTexture(nil, "OVERLAY")
markerTex:SetAllPoints()
markerTex:SetTexture(1, 1, 1)
local yardsText = marker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
yardsText:SetPoint("LEFT", marker, "RIGHT", 4, 0)
local statusText = marker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusText:SetPoint("LEFT", yardsText, "RIGHT", 4, 0)

-- Scale --------------------------------------------------------------------------

local scaleTop = 45
local slices, ticks = {}, {}

local function YardsToY(yards)
  return math.max(0, math.min(yards, scaleTop)) / scaleTop * BAR_HEIGHT
end

-- Paints the scale with the same colors as the lights, as 1-yard gradient slices,
-- and puts a tick every TICK_YARDS. Re-run when the reach changes (Hawk Eye).
local function Layout()
  scaleTop = ns.reachYards + SCALE_PAST_REACH

  local count = math.ceil(scaleTop)
  for i = 1, count do
    local s = slices[i]
    if not s then
      s = bar:CreateTexture(nil, "ARTWORK")
      s:SetTexture(1, 1, 1)
      s:SetWidth(BAR_WIDTH)
      slices[i] = s
    end
    local y0, y1 = i - 1, math.min(i, scaleTop)
    -- Colors just inside each end, so the hard switches (melee, reach) stay sharp
    local r1, g1, b1 = ns.ScaleColor(y0 + 0.01)
    local r2, g2, b2 = ns.ScaleColor(y1 - 0.01)
    s:SetGradientAlpha("VERTICAL", r1, g1, b1, 0.45, r2, g2, b2, 0.45)
    s:SetHeight(math.max(YardsToY(y1) - YardsToY(y0), 0.01))
    s:SetPoint("BOTTOM", bar, "BOTTOM", 0, YardsToY(y0))
    s:Show()
  end
  for i = count + 1, #slices do slices[i]:Hide() end

  local tickCount = math.floor(scaleTop / TICK_YARDS)
  for i = 1, tickCount do
    local t = ticks[i]
    if not t then
      t = bar:CreateTexture(nil, "OVERLAY")
      t:SetTexture(1, 1, 1, 0.35)
      t:SetWidth(4)
      t:SetHeight(1)
      ticks[i] = t
    end
    t:SetPoint("CENTER", bar, "BOTTOMRIGHT", 3, YardsToY(i * TICK_YARDS))
    t:Show()
  end
  for i = tickCount + 1, #ticks do ticks[i]:Hide() end

  reachLine:SetPoint("CENTER", bar, "BOTTOM", 0, YardsToY(ns.reachYards))
  reachText:SetText(ns.reachYards)
end

-- Measuring and the marker -----------------------------------------------------------

local tracker = ns.NewTracker()
local state = "unknown"
local lastZone            -- to notice the target stepping into another zone
local flash = 0           -- 1 right after a change, fades to 0
local targetAlpha = 0     -- 1 = fading in, 0 = fading out
local sinceUpdate = 0

-- fresh = a new target: start fresh instead of treating it as movement
local function Measure(fresh)
  local lo, hi, zone = ns.Measure("target")
  tracker:Read(lo, hi, zone, fresh)
  state = ns.StateFor(lo, hi, zone)

  if not fresh and ns.ZoneChanged(lastZone, zone) then
    flash = 1
    ns.PlayZoneSound(zone)
  end
  lastZone = zone
end

-- Moves `value` a step toward `goal`; `speed` is roughly "how many times per second"
local function Approach(value, goal, speed, elapsed)
  return value + (goal - value) * math.min(1, elapsed * speed)
end

g:SetScript("OnUpdate", function(self, elapsed)
  sinceUpdate = sinceUpdate + elapsed
  if sinceUpdate >= UPDATE_INTERVAL and UnitExists("target") then
    sinceUpdate = 0
    Measure()
  end

  -- Live distance, glided on a spring (see Tracker.lua)
  tracker:Step(elapsed)
  local yards = tracker.zone == "melee" and ns.MELEE_YARDS / 2 or tracker.display
  marker:SetPoint("CENTER", bar, "BOTTOM", 0, YardsToY(yards))

  local r, gr, b = ns.StateColor(state, tracker.display)
  markerTex:SetVertexColor(r, gr, b)
  markerGlow:SetVertexColor(r, gr, b)
  statusText:SetText(ns.STATE_TEXT[state])
  statusText:SetTextColor(r, gr, b)
  if tracker.zone == "melee" then
    yardsText:SetText("")
  elseif not tracker.hi then
    yardsText:SetText(tracker.lo .. "+ yd")
  else
    yardsText:SetText(math.floor(tracker.display + 0.5) .. " yd")
  end

  -- Slow breathing glow, a little brighter during a flash
  markerGlow:SetAlpha(0.45 + 0.15 * math.sin(GetTime() * 3) + 0.4 * flash)

  -- Reach line flash: brighter and a bit wider, then settles back
  flash = math.max(0, flash - elapsed * FLASH_DECAY)
  reachLine:SetAlpha(0.6 + 0.4 * flash)
  reachLine:SetWidth(BAR_WIDTH + 16 + 14 * flash)

  -- Fade in or out; fully faded out = hide (which also stops this OnUpdate)
  local alpha = Approach(self:GetAlpha(), targetAlpha, FADE_SPEED, elapsed)
  if targetAlpha == 0 and alpha < 0.02 then
    self:Hide()
  else
    self:SetAlpha(alpha)
  end
end)

-- The bar is the optional view (/rg bar); the default view is the lights in Lights.lua
local function OnTargetChanged()
  if RangeGaugeDB.mode == "bar" and UnitExists("target") and not UnitIsUnit("target", "player") then
    if not g:IsShown() then g:SetAlpha(0) end
    targetAlpha = 1
    g:Show()
    lastZone = nil
    Measure(true)
  else
    targetAlpha = 0
  end
end

-- Setup --------------------------------------------------------------------------------

local function ApplyLock()
  g:EnableMouse(not RangeGaugeDB.locked)
  ns.lights:EnableMouse(not RangeGaugeDB.locked)
end

local function RestorePosition()
  g:ClearAllPoints()
  local p = RangeGaugeDB.point
  if p then
    g:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    g:SetPoint("CENTER", UIParent, "CENTER", 220, 0)
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("CHARACTER_POINTS_CHANGED")
events:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == "RangeGauge" then
      RangeGaugeDB = RangeGaugeDB or {}
      RestorePosition()
      ns.RestoreLights()
      ApplyLock()
    end
  elseif event == "PLAYER_LOGIN" then
    ns.InitChecks()
    Layout()
    if not RangeGaugeDB.locked then
      ns.Print("drag the range display where you want it, then type /rg lock.")
    end
  elseif event == "PLAYER_TARGET_CHANGED" then
    OnTargetChanged()
  else
    -- Talents changed: Hawk Eye may have changed the reach
    ns.UpdateReach()
    Layout()
  end
end)

SLASH_RANGEGAUGE1 = "/rg"
SlashCmdList["RANGEGAUGE"] = function(msg)
  if msg == "lock" then
    RangeGaugeDB.locked = true
    ApplyLock()
    ns.Print("locked.")
  elseif msg == "unlock" then
    RangeGaugeDB.locked = false
    ApplyLock()
    ns.Print("unlocked, drag to move.")
  elseif msg == "reset" then
    RangeGaugeDB.point = nil
    RangeGaugeDB.lightsPoint = nil
    RestorePosition()
    ns.RestoreLights()
  elseif msg == "bar" or msg == "lights" then
    RangeGaugeDB.mode = msg
    OnTargetChanged()
    ns.Print(msg == "bar" and "showing the range bar." or "showing the range lights.")
  elseif msg == "sound" or msg == "mute" or msg == "unmute" then
    if msg == "mute" then
      RangeGaugeDB.sound = false
    elseif msg == "unmute" then
      RangeGaugeDB.sound = true
    else
      RangeGaugeDB.sound = RangeGaugeDB.sound == false -- toggle
    end
    ns.Print(RangeGaugeDB.sound and "sound on." or "sound off.")
  elseif msg == "debug" then
    ns.Debug("target")
  elseif msg == "live" then
    -- Prints the bar's tracker twice per second for 10 seconds, to see what it's doing
    local ticks = 0
    local ticker = CreateFrame("Frame")
    local since = 0
    ticker:SetScript("OnUpdate", function(self, elapsed)
      since = since + elapsed
      if since < 0.5 then return end
      since = 0
      ticks = ticks + 1
      ns.Print(string.format("band %s-%s %s | estimate %.1f yd | speed %.1f yd/s",
        tracker.lo, tracker.hi or "?", tracker.zone, tracker.estimate, tracker.speed))
      if ticks >= 20 then self:SetScript("OnUpdate", nil) end
    end)
  else
    ns.Print("/rg lock, /rg unlock, /rg reset, /rg lights, /rg bar, /rg mute, /rg unmute, /rg debug, /rg live")
  end
end
