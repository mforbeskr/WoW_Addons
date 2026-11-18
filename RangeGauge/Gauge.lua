-- Gauge: the bar view (/rg bar). Same readings, colors, labels, click and live tracking as the
-- lights, drawn as a vertical scale: 0 yd at the bottom, a little past your reach at the top.
-- Also home to the addon's setup, events and /rg commands.

local _, ns = ...

local BAR_HEIGHT = 220
local BAR_WIDTH = 10
local SCALE_PAST_REACH = 10   -- yards shown above the reach line
local TICK_YARDS = 5          -- a small tick mark every 5 yards
local UPDATE_INTERVAL = 0.033 -- 30 full checks per second, same as the lights (on purpose)
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
reachLine:SetAlpha(0.6)
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
ns.Breathe(markerGlow, 0.3, 0.6)
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
local shownProfile -- the profile the scale is painted for (enemy or ally colors)

local function YardsToY(yards)
  return math.max(0, math.min(yards, scaleTop)) / scaleTop * BAR_HEIGHT
end

-- Paints the scale with the same colors as the lights, as 1-yard gradient slices,
-- and puts a tick every TICK_YARDS. Re-run when the reach changes (talents) or the target
-- switches between enemy and ally (attack range vs. heal range).
local function Layout(profile)
  profile = profile or shownProfile or ns.DefaultProfile()
  shownProfile = profile
  local reach, style = profile.reach, profile.style
  scaleTop = reach + SCALE_PAST_REACH

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
    local r1, g1, b1 = ns.ScaleColor(y0 + 0.01, reach, style)
    local r2, g2, b2 = ns.ScaleColor(y1 - 0.01, reach, style)
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

  reachLine:SetPoint("CENTER", bar, "BOTTOM", 0, YardsToY(reach))
  reachText:SetText(reach)
end

-- Measuring and the marker -----------------------------------------------------------

local tracker = ns.NewTracker(400) -- lighter mode: 120 (see PARTICLES in Lights.lua)
local state = "unknown"
local lastZone            -- to notice the target stepping into another zone
local lastKey             -- last melee/reach answer; checked every frame for an instant click
local flash = 0           -- 1 right after a change, fades to 0
local targetAlpha = 0     -- 1 = fading in, 0 = fading out
local fading = false      -- only touch the alpha while a fade is in progress
local dirty = true        -- the reading changed: repaint even if the marker didn't move
local textCache = {}      -- what the yards text currently shows
local sinceUpdate = 0

-- fresh = a new target: start fresh instead of treating it as movement
local function Measure(fresh)
  local lo, hi, zone, key, profile = ns.Measure("target")
  lastKey = key
  if profile ~= shownProfile then
    Layout(profile)
    fresh = true
  end
  if tracker:Read("target", lo, hi, zone, fresh, profile.reach) then dirty = true end
  if fresh then state = nil end

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
  if UnitExists("target") then
    -- Melee/reach answer changed? Measure right now, so the click is never late.
    if sinceUpdate >= UPDATE_INTERVAL or ns.RawKey("target") ~= lastKey then
      sinceUpdate = 0
      Measure()
    end
  end

  -- Fade in or out; fully faded out = hide (which also stops this OnUpdate)
  if fading then
    local alpha = Approach(self:GetAlpha(), targetAlpha, FADE_SPEED, elapsed)
    if targetAlpha == 0 and alpha < 0.02 then
      fading = false
      self:Hide()
      return
    elseif targetAlpha == 1 and alpha > 0.98 then
      fading = false
      alpha = 1
    end
    self:SetAlpha(alpha)
  end

  -- Reach line flash: brighter and a bit wider, then settles back
  if flash > 0 then
    flash = math.max(0, flash - elapsed * FLASH_DECAY)
    reachLine:SetAlpha(0.6 + 0.4 * flash)
    reachLine:SetWidth(BAR_WIDTH + 16 + 14 * flash)
  end

  -- Live distance (see Tracker.lua). Unchanged = nothing to do.
  if not tracker:Step(elapsed) and not dirty then return end
  dirty = false

  local yards = tracker.display
  if tracker.zone == "melee" then yards = math.min(yards, ns.MELEE_YARDS) end
  marker:SetPoint("CENTER", bar, "BOTTOM", 0, YardsToY(yards))

  local p = shownProfile
  local newState = ns.StateFor(tracker.zone, tracker.display, p.reach, p.style)
  if newState ~= state then
    state = newState
    statusText:SetText(ns.StateText(state, p.style))
  end
  local r, gr, b = ns.StateColor(state, tracker.display, p.reach, p.style)
  markerTex:SetVertexColor(r, gr, b)
  markerGlow:SetVertexColor(r, gr, b)
  statusText:SetTextColor(r, gr, b)
  ns.SetYardsText(yardsText, textCache, tracker)
end)

-- The glow's breathing animation; make sure it runs whenever the bar appears
g:SetScript("OnShow", function()
  if markerGlow.breathing then markerGlow.breathing:Play() end
end)

-- The bar is the optional view (/rg bar); the default view is the lights in Lights.lua
local function OnTargetChanged()
  if RangeGaugeDB.mode == "bar" and UnitExists("target") and not UnitIsUnit("target", "player") then
    if not g:IsShown() then g:SetAlpha(0) end
    targetAlpha = 1
    fading = true
    dirty = true
    g:Show()
    lastZone = nil
    Measure(true)
  else
    targetAlpha = 0
    fading = true
  end
end

-- Setup --------------------------------------------------------------------------------

local function ApplyLock()
  g:EnableMouse(not RangeGaugeDB.locked)
  ns.lights:EnableMouse(not RangeGaugeDB.locked)
  ns.WakeLights() -- show or hide the "drag me" box
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
    -- Talents changed: Hawk Eye / Shadow Reach / Holy Reach may have changed the reach
    ns.UpdateReach()
    Layout()
  end
end)

-- /rg live: prints your target's tracker twice per second for 10 seconds, to see what it's doing.
-- One frame, reused; hidden (and so idle) when not printing.
local liveTicker = CreateFrame("Frame")
liveTicker:Hide()
liveTicker:SetScript("OnUpdate", function(self, elapsed)
  self.since = self.since + elapsed
  if self.since < 0.5 then return end
  self.since = 0
  self.ticks = self.ticks + 1
  local t = RangeGaugeDB.mode == "bar" and tracker or ns.LightsTracker("target")
  if t and UnitExists("target") then
    ns.Print(string.format("band %s-%s %s | shown %.1f yd | %s | moving %.1f yd/s (you %.1f, target %.1f)",
      t.lo, t.hi or "?", t.zone, t.display, t.mode, t.speed,
      GetUnitSpeed("player") or 0, GetUnitSpeed("target") or 0))
  else
    ns.Print("no target.")
  end
  if self.ticks >= 20 then self:Hide() end
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
    ns.WakeLights()
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
    liveTicker.ticks, liveTicker.since = 0, 0
    liveTicker:Show()
  elseif msg == "verify" then
    ns.StartVerify(60)
  elseif msg == "party" then
    RangeGaugeDB.party = RangeGaugeDB.party == false
    ns.WakeLights()
    ns.Print(RangeGaugeDB.party and "showing your group's rows." or "group rows hidden.")
  elseif msg == "map" then
    ns.Print("map position: " .. ns.LocatorStatus())
  else
    ns.Print("/rg lock, /rg unlock, /rg reset, /rg lights, /rg bar, /rg mute, /rg unmute, " ..
      "/rg party, /rg debug, /rg live, /rg verify, /rg map")
  end
end
