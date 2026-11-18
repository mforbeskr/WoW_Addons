-- UI: one small window. A row per slot: what you wear -> what the optimizer suggests, with the
-- gain. Below: total score, hit/expertise against their caps, your saved Equipment Manager sets
-- scored the same way, and buttons to optimize again and to equip the suggestions from your bags.
-- Created once on first open; refreshes only while shown (gear changes set a dirty flag).

local _, ns = ...

local WIDTH, ROW_H = 520, 18
local COL_SLOT, COL_ITEM = 66, 196
local GOOD, MUTED, WARN = { 0.45, 0.85, 0.35 }, { 0.62, 0.6, 0.56 }, { 1, 0.75, 0.3 }

local f, rows, info, capsText, setsText, scoreText, result
local dirty = false

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
    cell.text:SetText(c.link .. (tag or ""))
  else
    cell.icon:SetTexture(nil)
    cell.text:SetText("|cff808080-|r")
  end
end

local function Button(label, width, onClick)
  local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  b:SetWidth(width)
  b:SetHeight(20)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
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
  f:SetBackdropColor(0.06, 0.06, 0.06, 0.88)
  f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  tinsert(UISpecialFrames, "GearOptimizerFrame") -- Escape closes it

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  f.title = title
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  local head = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  head:SetPoint("TOPLEFT", 12 + COL_SLOT, -30)
  head:SetText("Wearing")
  local head2 = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  head2:SetPoint("TOPLEFT", 12 + COL_SLOT + COL_ITEM + 18, -30)
  head2:SetText("Best you own")

  rows = {}
  local y = -44
  for i, slot in ipairs(ns.SLOT_ORDER) do
    local r = {}
    r.slot = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.slot:SetPoint("TOPLEFT", 12, y - 3)
    r.slot:SetText(ns.SLOT_NAMES[slot])
    r.cur = ItemCell(f)
    r.cur:SetPoint("TOPLEFT", 12 + COL_SLOT, y)
    r.arrow = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.arrow:SetPoint("LEFT", r.cur, "RIGHT", 4, 0)
    r.best = ItemCell(f)
    r.best:SetPoint("LEFT", r.cur, "RIGHT", 18, 0)
    r.gain = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.gain:SetPoint("TOPRIGHT", -12, y - 3)
    rows[slot] = r
    y = y - ROW_H
  end

  scoreText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  scoreText:SetPoint("TOPLEFT", 12, y - 8)
  capsText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  capsText:SetPoint("TOPLEFT", scoreText, "BOTTOMLEFT", 0, -4)
  setsText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  setsText:SetPoint("TOPLEFT", capsText, "BOTTOMLEFT", 0, -4)
  setsText:SetWidth(WIDTH - 24)
  setsText:SetJustifyH("LEFT")
  info = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  info:SetPoint("TOPLEFT", setsText, "BOTTOMLEFT", 0, -4)
  info:SetWidth(WIDTH - 24)
  info:SetJustifyH("LEFT")

  local optimize = Button("Optimize", 90, function() ns.Refresh() end)
  optimize:SetPoint("BOTTOMRIGHT", -12, 10)
  local equip = Button("Equip from bags", 120, function()
    if not result then return end
    local n = ns.EquipFromBags(result)
    if n > 0 then ns.Print("equipped " .. n .. " item" .. (n == 1 and "" or "s") .. ". Save it in the Equipment Manager if you like it.") end
  end)
  equip:SetPoint("RIGHT", optimize, "LEFT", -6, 0)
  f:SetHeight(-y + 128)

  -- Re-score when your gear or bags change, once, while the window is open
  f:RegisterEvent("UNIT_INVENTORY_CHANGED")
  f:RegisterEvent("BAG_UPDATE")
  f:RegisterEvent("EQUIPMENT_SETS_CHANGED")
  f:SetScript("OnEvent", function(_, event, unit)
    if event ~= "UNIT_INVENTORY_CHANGED" or unit == "player" then dirty = true end
  end)
  f:SetScript("OnUpdate", function()
    if dirty and not InCombatLockdown() then
      dirty = false
      ns.Refresh()
    end
  end)
end

local function Color(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

function ns.Refresh()
  local r, err = ns.Run()
  result = r
  if not r then
    f.title:SetText("Gear Optimizer")
    scoreText:SetText(err or "")
    return
  end
  f.title:SetText("Gear Optimizer - " .. r.profile.name)

  for _, slot in ipairs(ns.SLOT_ORDER) do
    local row, cur, best = rows[slot], r.current[slot], r.best[slot]
    SetCell(row.cur, cur)
    local tag
    if best and best.where == "bank" then tag = " |cffffbf4d(bank)|r"
    elseif best and best.where == "equipped" and best ~= cur then tag = " |cffffbf4d(swap)|r" end
    local changed = best ~= cur and not (best and cur and best.link == cur.link)
    if r.profile.keepSlots[slot] then
      SetCell(row.best, nil)
      row.best.text:SetText(Color(MUTED) .. "kept (effects can't be scored)|r")
      row.arrow:SetText("")
      row.gain:SetText("")
    elseif changed then
      SetCell(row.best, best, tag)
      row.arrow:SetText(">")
      local single = {}
      single[slot] = best
      local before = {}
      before[slot] = cur
      local gain = ns.SetValue(single, r.profile, { hit = 1e9, exp = 1e9 }) - ns.SetValue(before, r.profile, { hit = 1e9, exp = 1e9 })
      row.gain:SetText((gain >= 0 and Color(GOOD) .. "+" or Color(WARN)) .. string.format("%d", gain) .. "|r")
    else
      SetCell(row.best, nil)
      row.best.text:SetText(Color(MUTED) .. "already best|r")
      row.arrow:SetText("")
      row.gain:SetText("")
    end
  end

  local pct = r.curValue > 0 and (r.bestValue / r.curValue - 1) * 100 or 0
  scoreText:SetText(string.format("Score: wearing %d   best %d   %s(+%.1f%%)|r",
    r.curValue, r.bestValue, Color(pct > 0.05 and GOOD or MUTED), pct))
  capsText:SetText(string.format("Hit %d -> %d of %d    Expertise %d -> %d of %d    (rating from gear and gems)",
    r.curHit, r.bestHit, r.caps.hit, r.curExp, r.bestExp, r.caps.exp))

  if #r.sets > 0 then
    local parts = {}
    for _, s in ipairs(r.sets) do table.insert(parts, string.format("%s %d", s.name, s.value)) end
    setsText:SetText("Your saved sets: " .. table.concat(parts, "   "))
  else
    setsText:SetText("Your saved sets: none yet")
  end

  local notes = { "Not counted: enchants, socket and set bonuses, Equip/Use effects. Empty sockets count as gemmed." }
  if r.note then table.insert(notes, 1, Color(WARN) .. r.note .. "|r") end
  if r.missing > 0 then
    table.insert(notes, 1, Color(WARN) .. r.missing .. " item(s) not loaded yet - press Optimize again in a moment.|r")
  end
  if #GearOptimizerCharDB.bank == 0 then table.insert(notes, "Visit your bank once so bank items are included.") end
  info:SetText(table.concat(notes, "\n"))
end

function ns.Toggle()
  if not f then Build() end
  if f:IsShown() then
    f:Hide()
  else
    f:Show()
    ns.Refresh()
  end
end

SLASH_GEAROPTIMIZER1 = "/gopt"
SLASH_GEAROPTIMIZER2 = "/gearopt"
SlashCmdList.GEAROPTIMIZER = function() ns.Toggle() end
