-- Lights: the default view. One row per unit you care about (target, focus, your group when you
-- can heal, arena enemies), each with a colored light, its state (GOOD, MAX, OUT...) and the
-- live yards. The in/out reading comes straight from your reach spell (Auto Shot, Flash Heal...),
-- so it's as live as WoW 3.3.5 allows.
--
-- Each row also shows who it is: a short tag (T, F, P1, A1...), the name in class colors, a
-- stripe on the left (green = ally, red = enemy) and, for allies, a thin health line. Allies
-- you can't heal fade out, like on raid frames.
--
-- Rows are real unit buttons (SecureUnitButtonTemplate): hovering one makes it your
-- [@mouseover] unit, so mouseover macros and click-cast addons (Clique) work on them, and a left
-- click targets the unit. WoW forbids moving, showing or hiding such buttons in combat, so as
-- combat starts every row that could be needed gets a fixed slot (empty ones are invisible), and
-- the rows only re-sort again after combat.
--
-- Performance: the update loop only runs while at least one row is shown. With nothing to
-- watch it switches itself off, and events (target/focus/group/arena changes) switch it back on.
-- Rows only repaint while their distance is moving or their reading changed.

local _, ns = ...

-- 30 full checks per second, plus the melee/reach answer every frame so a zone change (and the
-- click) is never late. Higher than the usual 0.1-0.2s on purpose: this is a live PvP display.
local UPDATE_INTERVAL = 0.033
-- Map tracker size per row (see Tracker.lua). CPU cost scales with this number.
-- LIGHTER MODE: set this to 120 (and the bar's NewTracker(400) in Gauge.lua to 120) to roughly
-- halve RangeGauge's CPU use; the simulator shows only ~0.04 yd more error (0.65 -> 0.69 yd).
local PARTICLES = 250
local FLASH_DECAY = 3
local ROW_WIDTH = 230
local ROW_HEIGHT = 22
local ROW_GAP = 3
local OUT_OF_HEAL_ALPHA = 0.45 -- allies you can't heal: name faded like on raid frames

local UNITS = { "target", "focus", "party1", "party2", "party3", "party4",
  "arena1", "arena2", "arena3", "arena4", "arena5" }
local TAGS = { target = "T", focus = "F", party1 = "P1", party2 = "P2", party3 = "P3", party4 = "P4",
  arena1 = "A1", arena2 = "A2", arena3 = "A3", arena4 = "A4", arena5 = "A5" }
local PARTY = { party1 = true, party2 = true, party3 = true, party4 = true }

local frame = CreateFrame("Frame", "RangeGaugeLights", UIParent)
frame:SetWidth(ROW_WIDTH)
frame:SetHeight(ROW_HEIGHT)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")

local function StartDrag()
  if not RangeGaugeDB.locked and not InCombatLockdown() then frame:StartMoving() end
end
local function StopDrag()
  frame:StopMovingOrSizing()
  local point, _, relPoint, x, y = frame:GetPoint()
  RangeGaugeDB.lightsPoint = { point, relPoint, x, y }
end
frame:SetScript("OnDragStart", StartDrag)
frame:SetScript("OnDragStop", StopDrag)
ns.lights = frame

-- Shown while unlocked and nothing is targeted, so there's something to drag
local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("CENTER")
hint:SetText("Range lights - drag me")
local hintBg = frame:CreateTexture(nil, "BACKGROUND")
hintBg:SetAllPoints()
hintBg:SetTexture(0, 0, 0, 0.4)

local rows = {}

local function RowOnShow(row)
  if row.glow.breathing then row.glow.breathing:Play() end
end

local function RowOnEnter(row)
  GameTooltip_SetDefaultAnchor(GameTooltip, row)
  GameTooltip:SetUnit(row.token)
  GameTooltip:Show()
end

local function RowOnLeave()
  GameTooltip:Hide()
end

-- One row per unit token, created once at load (secure buttons can't be set up in combat)
local function CreateRow(token)
  local row = CreateFrame("Button", "RangeGaugeRow_" .. token, frame, "SecureUnitButtonTemplate")
  row.token = token
  row:SetAttribute("unit", token)
  row:SetAttribute("*type1", "target") -- left click targets; mouseover macros just need the hover
  row:RegisterForClicks("AnyUp")
  row:RegisterForDrag("LeftButton")
  row:SetScript("OnDragStart", StartDrag)
  row:SetScript("OnDragStop", StopDrag)
  row:SetScript("OnEnter", RowOnEnter)
  row:SetScript("OnLeave", RowOnLeave)
  ClickCastFrames = ClickCastFrames or {} -- Clique and other click-cast addons
  ClickCastFrames[row] = true
  row:SetWidth(ROW_WIDTH)
  row:SetHeight(ROW_HEIGHT)
  row:Hide()

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture(0, 0, 0, 0.55)

  -- Ally / enemy stripe on the left edge
  row.side = row:CreateTexture(nil, "BORDER")
  row.side:SetPoint("TOPLEFT")
  row.side:SetPoint("BOTTOMLEFT")
  row.side:SetWidth(2)
  row.side:SetTexture(1, 1, 1)

  -- Whole-row flash when the state changes
  row.flash = row:CreateTexture(nil, "BORDER")
  row.flash:SetAllPoints()
  row.flash:SetTexture(1, 1, 1)
  row.flash:SetBlendMode("ADD")
  row.flash:SetAlpha(0)
  row.flashAmount = 0

  row.light = row:CreateTexture(nil, "ARTWORK")
  row.light:SetWidth(ROW_HEIGHT - 8)
  row.light:SetHeight(ROW_HEIGHT - 8)
  row.light:SetPoint("LEFT", 6, 0)
  row.light:SetTexture(1, 1, 1)

  row.glow = row:CreateTexture(nil, "OVERLAY")
  row.glow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  row.glow:SetBlendMode("ADD")
  row.glow:SetWidth(40)
  row.glow:SetHeight(40)
  row.glow:SetPoint("CENTER", row.light, "CENTER")
  ns.Breathe(row.glow, 0.3, 0.6)

  -- Who it is: a short muted tag, then the name in class colors
  row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.tag:SetPoint("LEFT", row.light, "RIGHT", 6, 0)
  row.tag:SetWidth(16)
  row.tag:SetJustifyH("LEFT")

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.tag, "RIGHT", 2, 0)
  row.name:SetWidth(76)
  row.name:SetJustifyH("LEFT")
  row.name:SetShadowOffset(1, -1)

  -- Allies: thin health line along the bottom, green -> yellow -> red as health drops
  row.health = row:CreateTexture(nil, "ARTWORK")
  row.health:SetPoint("BOTTOMLEFT", 2, 0)
  row.health:SetHeight(2)
  row.health:SetTexture(1, 1, 1)
  row.health:Hide()

  row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.status:SetPoint("RIGHT", -6, 0)

  row.yards = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.yards:SetPoint("RIGHT", row.status, "LEFT", -6, 0)

  row:SetScript("OnShow", RowOnShow)

  row.tracker = ns.NewTracker(PARTICLES) -- smooth live yards for this row
  row.state = "unknown"
  row.dirty = true
  return row
end

-- A new reading (30 per second). fresh = a different unit in this row.
local function UpdateRow(row, unit, fresh)
  local lo, hi, zone, key, profile = ns.Measure(unit)
  -- Became an enemy or ally (a duel started, mind control...): different checks, start over
  if profile ~= row.profile then
    fresh = true
    row.zone = nil
    row.profile = profile
  end
  row.rawKey = key
  if row.tracker:Read(unit, lo, hi, zone, fresh, profile.reach) then row.dirty = true end

  -- Flash (and click for your target) when the unit steps into another zone
  if ns.ZoneChanged(row.zone, zone) then
    row.flashAmount = 1
    if unit == "target" then ns.PlayZoneSound(zone) end
  end
  row.zone = zone
end

-- Every frame: move the live distance along; repaint only if something changed
local function PaintRow(row, elapsed)
  local t = row.tracker
  if not t:Step(elapsed) and not row.dirty then return end
  row.dirty = false

  local p = row.profile
  row.state = ns.StateFor(t.zone, t.display, p.reach, p.style)
  local r, g, b = ns.StateColor(row.state, t.display, p.reach, p.style)
  row.light:SetVertexColor(r, g, b)
  row.glow:SetVertexColor(r, g, b)
  row.status:SetTextColor(r, g, b)
  if row.shownState ~= row.state then
    row.shownState = row.state
    row.status:SetText(ns.StateText(row.state, p.style))
  end
  ns.SetYardsText(row.yards, row, t)

  -- Allies you can't heal fade out (unknown counts as in range: no false alarm)
  local alpha = (p.style == "heal" and (t.zone == "out")) and OUT_OF_HEAL_ALPHA or 1
  if alpha ~= row.nameAlpha then
    row.nameAlpha = alpha
    row.name:SetAlpha(alpha)
    row.tag:SetAlpha(alpha)
  end
end

local function SetRowName(row, unit, name)
  local _, class = UnitClass(unit)
  local color = UnitIsPlayer(unit) and class and RAID_CLASS_COLORS[class]
  row.tag:SetText(TAGS[unit])
  row.name:SetText(name or "?")
  if color then
    row.name:SetTextColor(color.r, color.g, color.b)
  else
    row.name:SetTextColor(1, 1, 1)
  end
end

-- Stripe color: green = ally, red = enemy, yellow = neutral (attackable but not hostile)
local function UpdateSide(row, unit)
  local side
  if not UnitCanAttack("player", unit) then side = 1
  elseif UnitIsEnemy("player", unit) then side = 2
  else side = 3 end
  if side == row.sideKind then return end
  row.sideKind = side
  if side == 1 then
    row.side:SetVertexColor(0.3, 0.9, 0.45, 0.9)
  elseif side == 2 then
    row.side:SetVertexColor(0.95, 0.25, 0.2, 0.9)
  else
    row.side:SetVertexColor(0.95, 0.85, 0.25, 0.9)
  end
end

-- Health line for allies; only touches the texture when the shown percent changes
local function UpdateHealth(row, unit)
  if UnitCanAttack("player", unit) then
    if row.healthPct then row.health:Hide() row.healthPct = nil end
    return
  end
  local max = UnitHealthMax(unit)
  local pct = max > 0 and math.floor(100 * UnitHealth(unit) / max + 0.5) or 0
  if pct == row.healthPct then return end
  row.healthPct = pct
  local f = pct / 100
  row.health:SetWidth(math.max(1, (ROW_WIDTH - 4) * f))
  if f > 0.5 then
    row.health:SetVertexColor(2 * (1 - f) + 0.2, 0.9, 0.3, 0.85)
  else
    row.health:SetVertexColor(1, 1.8 * f, 0.2, 0.85)
  end
  row.health:Show()
end

-- Does this unit get a row?
local function Wanted(unit)
  if not UnitExists(unit) or UnitIsUnit(unit, "player") or UnitIsDead(unit) then return false end
  if unit == "focus" and UnitIsUnit("focus", "target") then return false end -- no duplicate row
  if PARTY[unit] then
    -- Your group: only when you can heal, and not twice (already your target or focus)
    if RangeGaugeDB.party == false or not ns.HasFriendlyProfile() then return false end
    if not UnitIsConnected(unit) then return false end
    if UnitIsUnit(unit, "target") or UnitIsUnit(unit, "focus") then return false end
  end
  return true
end

-- The row no longer shows a unit (it stays laid out until the next Layout)
local function ClearRow(row)
  row.unit, row.guid, row.zone, row.profile = nil, nil, nil, nil
  row.sideKind, row.healthPct, row.nameRaw = nil, nil, nil
  row.health:Hide()
  row.flashAmount = 0
  row.flash:SetAlpha(0)
end

for i, token in ipairs(UNITS) do rows[i] = CreateRow(token) end

-- Could this unit need a row during the coming fight? (target/focus always; group and arena
-- only when they're there.) Those get an invisible slot so they can appear in combat.
local function MayNeed(unit)
  if unit == "target" or unit == "focus" then return true end
  if PARTY[unit] then
    return UnitExists(unit) and RangeGaugeDB.party ~= false and ns.HasFriendlyProfile()
  end
  return select(2, IsInInstance()) == "arena"
end

-- Places the rows, top to bottom in UNITS order: showing rows first, then (forCombat) an
-- invisible slot for every other row that may be needed. Out of combat only.
local function Layout(forCombat)
  if InCombatLockdown() then return end
  local slot = 0
  for pass = 1, 2 do
    for _, row in ipairs(rows) do
      local place
      if pass == 1 then place = row.unit ~= nil else place = forCombat and not row.unit and MayNeed(row.token) end
      if place then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -slot * (ROW_HEIGHT + ROW_GAP))
        row:SetAlpha(row.unit and 1 or 0)
        row:Show()
        slot = slot + 1
      elseif pass == 2 and not row.unit and not (forCombat and MayNeed(row.token)) then
        row:Hide()
      end
    end
  end
  if slot > 0 then frame:SetHeight(slot * (ROW_HEIGHT + ROW_GAP) - ROW_GAP) end
  return slot
end

-- Reads every unit and updates the rows. Returns how many rows show a unit.
local function Check()
  local combat = InCombatLockdown()
  if not RangeGaugeDB or RangeGaugeDB.mode == "bar" then
    for _, row in ipairs(rows) do
      if row.unit then ClearRow(row) end
    end
    if not combat then frame:Hide() end
    return 0
  end

  local shown, changed = 0, false
  for _, row in ipairs(rows) do
    local unit = row.token
    if Wanted(unit) then
      shown = shown + 1
      if not row.unit then changed = true end
      -- A different person in this row: don't flash for the switch
      local guid = UnitGUID(unit)
      local fresh = row.unit ~= unit or row.guid ~= guid
      if fresh then
        row.zone = nil
        row.unit, row.guid = unit, guid
      end
      local name = UnitName(unit)
      if fresh or name ~= row.nameRaw then
        row.nameRaw = name
        SetRowName(row, unit, name)
      end
      UpdateSide(row, unit)
      UpdateHealth(row, unit)
      UpdateRow(row, unit, fresh)
      if combat and row:GetAlpha() < 1 then row:SetAlpha(1) end
    elseif row.unit then
      ClearRow(row)
      changed = true
      if combat then row:SetAlpha(0) end -- keeps its slot (and mouseover) until combat ends
    end
  end

  -- In combat the layout is frozen (see the top of this file)
  if combat then return shown end

  if changed or frame.needsLayout then
    frame.needsLayout = false
    Layout(false)
  end
  if shown > 0 then
    hint:Hide()
    hintBg:Hide()
    frame:Show()
  elseif not RangeGaugeDB.locked then
    hint:Show()
    hintBg:Show()
    frame:SetHeight(ROW_HEIGHT)
    frame:Show()
  else
    frame:Hide()
  end
  return shown
end

-- The update loop. Only attached while there's something to watch.
local driver = CreateFrame("Frame")
local since = 0
local running = false

local function OnUpdate(_, elapsed)
  for i = 1, #rows do
    local row = rows[i]
    if row.unit then
      -- Melee/reach answer changed since the last full check? Measure now: no late click.
      if ns.RawKey(row.unit) ~= row.rawKey then
        UpdateRow(row, row.unit, false)
      end
      if row.flashAmount > 0 then
        row.flashAmount = math.max(0, row.flashAmount - elapsed * FLASH_DECAY)
        row.flash:SetAlpha(row.flashAmount * 0.5)
      end
      PaintRow(row, elapsed)
    end
  end

  since = since + elapsed
  if since < UPDATE_INTERVAL then return end
  since = 0

  if Check() == 0 then
    -- Nothing to watch: switch off until an event wakes us
    driver:SetScript("OnUpdate", nil)
    running = false
  end
end

-- Check on the very next frame, and keep running while there's something to show
function ns.WakeLights()
  since = UPDATE_INTERVAL
  if not running then
    running = true
    driver:SetScript("OnUpdate", OnUpdate)
  end
end

local UNIT_SET = {}
for _, unit in ipairs(UNITS) do UNIT_SET[unit] = true end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_FOCUS_CHANGED")
events:RegisterEvent("ARENA_OPPONENT_UPDATE")
events:RegisterEvent("PARTY_MEMBERS_CHANGED")
events:RegisterEvent("RAID_ROSTER_UPDATE")
events:RegisterEvent("UNIT_HEALTH")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_REGEN_DISABLED" then
    -- Fires just before combat lockdown: last chance to give every possible row a slot
    if RangeGaugeDB.mode ~= "bar" and Layout(true) > 0 then
      hint:Hide()
      hintBg:Hide()
      frame:Show()
    end
    ns.WakeLights()
  elseif event == "PLAYER_REGEN_ENABLED" then
    frame.needsLayout = true -- drop the empty combat slots, re-sort
    ns.WakeLights()
  elseif event == "UNIT_HEALTH" then
    -- Only matters while switched off: a dead unit we watch came back to life
    if not running and UNIT_SET[unit] and Wanted(unit) then ns.WakeLights() end
  else
    ns.WakeLights()
  end
end)

-- The tracker of the row showing `unit` (for /rg live)
function ns.LightsTracker(unit)
  for i = 1, #rows do
    if rows[i].unit == unit then return rows[i].tracker end
  end
end

function ns.RestoreLights()
  if InCombatLockdown() then return end
  frame:ClearAllPoints()
  local p = RangeGaugeDB.lightsPoint
  if p then
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
  end
end
