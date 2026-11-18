-- UI: one small window. At the top a "Find best ... build" button per scenario (Raid, AOE).
-- Nothing is calculated until you press one. Then a row per slot: what you wear -> what to wear
-- instead. Changed rows are highlighted, unchanged ones say "same". Below: estimated DPS, the
-- stats it gives, the set bonuses and glyphs counted, your saved sets, and two buttons:
-- Equip all changes (one click) and Save as an Equipment Manager set.
-- Created once on first open; while shown, gear changes only refresh the "wearing" side.

local _, ns = ...

local ROW_H = 18
local COL_SLOT, COL_ITEM = 62, 196
local WIDTH = 12 + COL_SLOT + COL_ITEM + 22 + COL_ITEM + 12
local GOOD, MUTED, WARN = { 0.45, 0.85, 0.35 }, { 0.62, 0.6, 0.56 }, { 1, 0.75, 0.3 }

local f, rows, findButtons, header, capsText, bonusText, savedText, info
local equipButton, saveButton
local result, resultKey
local dirty = false

local function Color(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

local function ItemCell(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(COL_ITEM)
  b:SetHeight(ROW_H)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetWidth(ROW_H - 2)
  b.icon:SetHeight(ROW_H - 2)
  b.icon:SetPoint("LEFT")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
  b.text:SetPoint("RIGHT")
  b.text:SetJustifyH("LEFT")
  b:SetScript("OnEnter", function(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.link)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self)
    if self.link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link) end
  end)
  return b
end

local function SetCell(cell, c, tag)
  cell.link = c and c.link
  if c then
    cell.icon:SetTexture(GetItemIcon(c.link))
    cell.text:SetText(c.link .. (ns.Estimated(c) and " |cffaaaaaa~|r" or "") .. (tag or ""))
  else
    cell.icon:SetTexture(nil)
    cell.text:SetText("|cff808080-|r")
  end
end

local function SetCellText(cell, text)
  cell.link = nil
  cell.icon:SetTexture(nil)
  cell.text:SetText(text)
end

local function Button(label, width, onClick)
  local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  b:SetWidth(width)
  b:SetHeight(20)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function Same(a, b) return a == b or (a and b and a.link == b.link) end

-- Rows and summary for the current result (or just what you wear, before any Find)
local function Render()
  local current = ns.Current()
  for _, slot in ipairs(ns.SLOT_ORDER) do
    local row = rows[slot]
    SetCell(row.cur, current[slot])
    local best = result and result.best[slot]
    if not result then
      SetCellText(row.new, "")
      row.arrow:SetText("")
      row.mark:Hide()
    elseif Same(best, current[slot]) or not best then
      SetCellText(row.new, Color(MUTED) .. "same|r")
      row.arrow:SetText("")
      row.mark:Hide()
    else
      local tag = ""
      if best.where == "bank" then tag = " |cffffbf4d(bank)|r"
      elseif best.where == "equipped" then tag = " |cffffbf4d(other slot)|r" end
      if best.st.empty > 0 then tag = tag .. " |cffffbf4d(needs gems)|r" end
      local gain = result.gains[slot]
      if gain then tag = string.format(" %s+%.1f%%|r", Color(GOOD), 100 * gain) .. tag end
      SetCell(row.new, best, tag)
      row.arrow:SetText(Color(GOOD) .. ">|r")
      row.mark:Show()
    end
  end

  if not result then
    header:SetText("Press Find: it tries every combination of the gear you own.")
    capsText:SetText("")
    bonusText:SetText("")
    savedText:SetText("")
    equipButton:Hide()
    saveButton:Hide()
    return
  end

  local r, sc, st = result, result.scenario, result.stats
  local pct = r.curDPS > 0 and (r.bestDPS / r.curDPS - 1) * 100 or 0
  header:SetText(string.format("Best %s build (%s):  ~%d -> %d DPS  %s+%.1f%%|r", sc.name, sc.purpose,
    r.curDPS, r.bestDPS, Color(pct > 0.05 and GOOD or MUTED), pct))
  capsText:SetText(string.format("AP %d  SP %d  crit %.1f%% / spell %.1f%%  hit %.1f%% / spell %.1f%%  expertise %d",
    st.ap, st.sp, 100 * st.meleeCrit, 100 * st.spellCrit, st.hitPct, st.spellHitPct, st.expertise))

  if #r.bonuses > 0 then
    local parts = {}
    for _, b in ipairs(r.bonuses) do
      table.insert(parts, string.format("%s %d pc (%s)%s", b.name, b.count, table.concat(b.active, "+"),
        b.estimated and " |cffaaaaaa~|r" or ""))
    end
    bonusText:SetText("Set bonuses: " .. table.concat(parts, ",  "))
  else
    bonusText:SetText("Set bonuses: none in this build")
  end
  bonusText:SetText(bonusText:GetText() .. "\nGlyphs counted: "
    .. (#r.glyphs > 0 and table.concat(r.glyphs, ", ") or "none that change damage"))

  if #r.saved > 0 then
    local parts = {}
    for _, s in ipairs(r.saved) do table.insert(parts, string.format("%s %d", s.name, s.dps)) end
    savedText:SetText("Your saved sets, est. DPS: " .. table.concat(parts, "   "))
  else
    savedText:SetText("Your saved sets: none yet")
  end

  equipButton:Show()
  saveButton:Show()
  saveButton:SetText("Save as \"Opt " .. sc.name .. "\"")
  if ns.Wearing(r) then
    equipButton:Disable()
    saveButton:Enable()
  else
    equipButton:Enable()
    saveButton:Disable()
  end
end

local function UpdateNotes()
  local notes = {
    "Estimated DPS with ICC raid buffs; your talents, glyphs, procs and set bonuses included.",
    "~ = estimated (an effect or set bonus it can't read). Not counted: enchants, socket bonuses.",
    "Only changes worth at least 0.2% DPS are shown; +x% = what that change adds.",
  }
  if result and result.missing > 0 then
    table.insert(notes, 1, Color(WARN) .. result.missing .. " item(s) not loaded yet - press Find again in a moment.|r")
  end
  if #GearOptimizerCharDB.bank == 0 then table.insert(notes, "Visit your bank once so bank items are included.") end
  info:SetText(table.concat(notes, "\n"))
end

local function LayoutFindButtons()
  for i, btn in ipairs(findButtons) do
    local key = ns.SCENARIOS[i]
    btn.key = key
    btn:SetText("Find best " .. ns.Model.SCENARIOS[key].name .. " build")
    if key == resultKey then btn:LockHighlight() else btn:UnlockHighlight() end
  end
end

local function Build()
  f = CreateFrame("Frame", "GearOptimizerFrame", UIParent)
  f:SetWidth(WIDTH)
  f:SetFrameStrata("HIGH")
  f:SetPoint("CENTER")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  f:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
  f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  tinsert(UISpecialFrames, "GearOptimizerFrame") -- Escape closes it

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -11)
  title:SetText("Gear Optimizer")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  -- One Find button per scenario; calculating happens only here
  findButtons = {}
  for i = 1, 2 do
    local btn = Button("Find", 170, nil)
    btn:SetScript("OnClick", function(self)
      local r, err = ns.Find(self.key)
      if not r then ns.Print(err) return end
      result, resultKey = r, self.key
      LayoutFindButtons()
      Render()
      UpdateNotes()
    end)
    btn:SetPoint("TOPLEFT", 12 + (i - 1) * 176, -34)
    findButtons[i] = btn
  end

  header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  header:SetPoint("TOPLEFT", 12, -64)

  local top = -84
  local head = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  head:SetPoint("TOPLEFT", 12 + COL_SLOT, top)
  head:SetText("Wearing")
  local head2 = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  head2:SetPoint("TOPLEFT", 12 + COL_SLOT + COL_ITEM + 22, top)
  head2:SetText("Wear instead")

  rows = {}
  local y = top - 14
  for _, slot in ipairs(ns.SLOT_ORDER) do
    local r = {}
    r.mark = f:CreateTexture(nil, "BACKGROUND") -- soft green behind changed rows
    r.mark:SetTexture(0.3, 0.8, 0.25, 0.12)
    r.mark:SetPoint("TOPLEFT", 6, y)
    r.mark:SetPoint("TOPRIGHT", -6, y)
    r.mark:SetHeight(ROW_H)
    r.mark:Hide()
    r.slot = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.slot:SetPoint("TOPLEFT", 12, y - 3)
    r.slot:SetText(ns.SLOT_NAMES[slot])
    r.cur = ItemCell(f)
    r.cur:SetPoint("TOPLEFT", 12 + COL_SLOT, y)
    r.arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.arrow:SetPoint("LEFT", r.cur, "RIGHT", 6, 0)
    r.new = ItemCell(f)
    r.new:SetPoint("LEFT", r.cur, "RIGHT", 22, 0)
    rows[slot] = r
    y = y - ROW_H
  end

  capsText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  capsText:SetPoint("TOPLEFT", 12, y - 8)
  bonusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bonusText:SetPoint("TOPLEFT", capsText, "BOTTOMLEFT", 0, -4)
  bonusText:SetWidth(WIDTH - 24)
  bonusText:SetJustifyH("LEFT")
  savedText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  savedText:SetPoint("TOPLEFT", bonusText, "BOTTOMLEFT", 0, -4)
  savedText:SetWidth(WIDTH - 24)
  savedText:SetJustifyH("LEFT")
  info = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  info:SetPoint("TOPLEFT", savedText, "BOTTOMLEFT", 0, -6)
  info:SetWidth(WIDTH - 24)
  info:SetJustifyH("LEFT")

  equipButton = Button("Equip all changes", 150, function()
    if result then ns.EquipAll(result) end
  end)
  equipButton:SetPoint("BOTTOMLEFT", 12, 10)
  saveButton = Button("Save", 160, function()
    if result then ns.SaveSet("Opt " .. result.scenario.name) end
  end)
  saveButton:SetPoint("LEFT", equipButton, "RIGHT", 6, 0)
  f:SetHeight(-y + 150)

  -- While shown: gear changes refresh the "wearing" side (no new search)
  f:RegisterEvent("UNIT_INVENTORY_CHANGED")
  f:RegisterEvent("BAG_UPDATE")
  f:SetScript("OnEvent", function(_, event, unit)
    if event ~= "UNIT_INVENTORY_CHANGED" or unit == "player" then dirty = true end
  end)
  f:SetScript("OnUpdate", function()
    if dirty and not InCombatLockdown() then
      dirty = false
      Render()
    end
  end)
end

function ns.Toggle()
  if not f then Build() end
  if f:IsShown() then
    f:Hide()
    return
  end
  f:Show()
  LayoutFindButtons()
  Render()
  UpdateNotes()
end

SLASH_GEAROPTIMIZER1 = "/gopt"
SLASH_GEAROPTIMIZER2 = "/gearopt"
SlashCmdList.GEAROPTIMIZER = function(msg)
  local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "model" then
    ns.ModelReport(arg == "aoe" and "AOE" or "RAID")
  else
    ns.Toggle()
  end
end
