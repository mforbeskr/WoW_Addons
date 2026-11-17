-- Lights: the default view. One row per unit you care about (target, focus, arena enemies),
-- each with a colored light, its state (GOOD, MAX, OUT...) and the live yards.
-- The in/out reading comes straight from Auto Shot, so it's as live as WoW 3.3.5 allows.
--
-- Performance: the update loop only runs while at least one row is shown. With nothing to
-- watch it switches itself off, and events (target/focus/arena changes) switch it back on.
-- Rows only repaint while their distance is moving or their reading changed.

local _, ns = ...

-- 30 full checks per second, plus the melee/reach answer every frame so a zone change (and the
-- click) is never late. Higher than the usual 0.1-0.2s on purpose: this is a live PvP display.
local UPDATE_INTERVAL = 0.033
local PARTICLES = 250 -- map tracker size per row (see Tracker.lua)
local FLASH_DECAY = 3
local ROW_WIDTH = 200
local ROW_HEIGHT = 22
local ROW_GAP = 3

local UNITS = { "target", "focus", "arena1", "arena2", "arena3", "arena4", "arena5" }
local TAGS = { target = "", focus = "F  ", arena1 = "A1 ", arena2 = "A2 ", arena3 = "A3 ", arena4 = "A4 ", arena5 = "A5 " }

local frame = CreateFrame("Frame", "RangeGaugeLights", UIParent)
frame:SetWidth(ROW_WIDTH)
frame:SetHeight(ROW_HEIGHT)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, relPoint, x, y = self:GetPoint()
  RangeGaugeDB.lightsPoint = { point, relPoint, x, y }
end)
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

local function CreateRow(index)
  local row = CreateFrame("Frame", nil, frame)
  row:SetWidth(ROW_WIDTH)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + ROW_GAP))

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture(0, 0, 0, 0.55)

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
  row.light:SetPoint("LEFT", 4, 0)
  row.light:SetTexture(1, 1, 1)

  row.glow = row:CreateTexture(nil, "OVERLAY")
  row.glow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  row.glow:SetBlendMode("ADD")
  row.glow:SetWidth(40)
  row.glow:SetHeight(40)
  row.glow:SetPoint("CENTER", row.light, "CENTER")
  ns.Breathe(row.glow, 0.3, 0.6)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.light, "RIGHT", 6, 0)
  row.name:SetWidth(84)
  row.name:SetJustifyH("LEFT")

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

-- A new reading (20 per second). fresh = a different unit in this row.
local function UpdateRow(row, unit, fresh)
  local lo, hi, zone, key = ns.Measure(unit)
  row.rawKey = key
  if row.tracker:Read(unit, lo, hi, zone, fresh) then row.dirty = true end

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

  row.state = ns.StateFor(t.zone, t.display)
  local r, g, b = ns.StateColor(row.state, t.display)
  row.light:SetVertexColor(r, g, b)
  row.glow:SetVertexColor(r, g, b)
  row.status:SetTextColor(r, g, b)
  if row.shownState ~= row.state then
    row.shownState = row.state
    row.status:SetText(ns.STATE_TEXT[row.state])
  end
  ns.SetYardsText(row.yards, row, t)
end

local function SetRowName(row, unit, name)
  local _, class = UnitClass(unit)
  local color = UnitIsPlayer(unit) and class and RAID_CLASS_COLORS[class]
  row.name:SetText(TAGS[unit] .. (name or "?"))
  if color then
    row.name:SetTextColor(color.r, color.g, color.b)
  else
    row.name:SetTextColor(1, 1, 1)
  end
end

-- Does this unit get a row?
local function Wanted(unit)
  if not UnitExists(unit) or UnitIsUnit(unit, "player") or UnitIsDead(unit) then return false end
  if unit == "focus" and UnitIsUnit("focus", "target") then return false end -- no duplicate row
  return true
end

local function HideRow(row)
  row:Hide()
  row.unit, row.guid, row.zone = nil, nil, nil
  row.flashAmount = 0
  row.flash:SetAlpha(0)
end

-- Reads every unit and lays out the rows. Returns how many rows are shown.
local function Check()
  if not RangeGaugeDB or RangeGaugeDB.mode == "bar" then
    frame:Hide()
    return 0
  end

  local shown = 0
  for _, unit in ipairs(UNITS) do
    if Wanted(unit) then
      shown = shown + 1
      local row = rows[shown] or CreateRow(shown)
      rows[shown] = row
      -- A different unit or person in this row: don't flash for the switch
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
      UpdateRow(row, unit, fresh)
      row:Show()
    end
  end
  for i = shown + 1, #rows do
    if rows[i].unit then HideRow(rows[i]) end
  end

  if shown > 0 then
    hint:Hide()
    hintBg:Hide()
    frame:SetHeight(shown * (ROW_HEIGHT + ROW_GAP) - ROW_GAP)
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
events:RegisterEvent("UNIT_HEALTH")
events:SetScript("OnEvent", function(_, event, unit)
  if event == "UNIT_HEALTH" then
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
  frame:ClearAllPoints()
  local p = RangeGaugeDB.lightsPoint
  if p then
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
  end
end
