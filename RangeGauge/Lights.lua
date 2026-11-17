-- Lights: the default view. One row per unit you care about (target, focus, arena enemies),
-- each with a colored light, its state (GOOD, MAX, OUT...) and the live yards.
-- The in/out reading comes straight from Auto Shot, so it's as live as WoW 3.3.5 allows.

local _, ns = ...

local UPDATE_INTERVAL = 0.05 -- 20 checks per second
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

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.light, "RIGHT", 6, 0)
  row.name:SetWidth(84)
  row.name:SetJustifyH("LEFT")

  row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.status:SetPoint("RIGHT", -6, 0)

  row.yards = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.yards:SetPoint("RIGHT", row.status, "LEFT", -6, 0)

  row.tracker = ns.NewTracker() -- smooth live yards for this row
  row.state = "unknown"
  return row
end

-- A new reading (20 per second). fresh = a different unit in this row.
local function UpdateRow(row, unit, fresh)
  local lo, hi, zone = ns.Measure(unit)
  row.tracker:Read(lo, hi, zone, fresh)
  row.state = ns.StateFor(lo, hi, zone)

  -- Flash (and click for your target) when the unit steps into another zone
  if ns.ZoneChanged(row.zone, zone) then
    row.flashAmount = 1
    if unit == "target" then ns.PlayZoneSound(zone) end
  end
  row.zone = zone
end

-- Every frame: move the live distance along and repaint the row
local function PaintRow(row, elapsed)
  local t = row.tracker
  t:Step(elapsed)

  local r, g, b = ns.StateColor(row.state, t.display)
  row.light:SetVertexColor(r, g, b)
  row.glow:SetVertexColor(r, g, b)
  row.status:SetText(ns.STATE_TEXT[row.state])
  row.status:SetTextColor(r, g, b)

  if t.zone == "melee" then
    row.yards:SetText("")
  elseif not t.hi then
    row.yards:SetText(t.lo .. "+ yd")
  else
    row.yards:SetText(math.floor(t.display + 0.5) .. " yd")
  end
end

local function SetRowName(row, unit)
  local name = UnitName(unit) or "?"
  local _, class = UnitClass(unit)
  local color = UnitIsPlayer(unit) and class and RAID_CLASS_COLORS[class]
  row.name:SetText(TAGS[unit] .. name)
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

-- A separate driver keeps updating even while the lights frame is hidden
local driver = CreateFrame("Frame")
local since = 0
driver:SetScript("OnUpdate", function(_, elapsed)
  for _, row in ipairs(rows) do
    if row.flashAmount > 0 then
      row.flashAmount = math.max(0, row.flashAmount - elapsed * FLASH_DECAY)
      row.flash:SetAlpha(row.flashAmount * 0.5)
    end
    row.glow:SetAlpha(0.45 + 0.15 * math.sin(GetTime() * 3))
    if row:IsShown() and row.unit then PaintRow(row, elapsed) end
  end

  since = since + elapsed
  if since < UPDATE_INTERVAL then return end
  since = 0

  if not RangeGaugeDB or RangeGaugeDB.mode == "bar" then
    frame:Hide()
    return
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
      SetRowName(row, unit)
      UpdateRow(row, unit, fresh)
      row:Show()
    end
  end
  for i = shown + 1, #rows do
    rows[i]:Hide()
    rows[i].unit, rows[i].guid, rows[i].zone = nil, nil, nil
  end

  local unlocked = not RangeGaugeDB.locked
  if shown > 0 then
    hint:Hide()
    hintBg:Hide()
    frame:SetHeight(shown * (ROW_HEIGHT + ROW_GAP) - ROW_GAP)
    frame:Show()
  elseif unlocked then
    hint:Show()
    hintBg:Show()
    frame:SetHeight(ROW_HEIGHT)
    frame:Show()
  else
    frame:Hide()
  end
end)

function ns.RestoreLights()
  frame:ClearAllPoints()
  local p = RangeGaugeDB.lightsPoint
  if p then
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
  end
end
