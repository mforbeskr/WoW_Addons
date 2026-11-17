-- BambooBags: your bags and bank in bamboo-framed windows, split into Gear / Outfits / General.
-- Sorting is "virtual": items are shown in sorted order but never moved, so it's instant and safe.
-- Alt+Left-click an item to move it to another section; the choice is remembered per item.

local TEX = "Interface\\AddOns\\BambooBags\\textures\\"
local NEON = { 0.78, 0.35, 1 }
local TWINE = { 0.62, 0.52, 0.36 }
local COLUMNS = 14
local SCALE = 0.6          -- Blizzard item buttons are 37px; this makes them ~22px
local SIZE = 37 * SCALE
local GAP = 3
local EDGE = 16            -- bamboo border thickness
local INSET = 20           -- frame edge to content
local HEADER = 26
local SECTION_TITLE = 14
local SECTION_GAP = 6
local FOOTER = 18
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local DEFAULT_GEAR_LEVEL = 200

local SECTIONS = {
  { key = "gear", label = "Gear" },
  { key = "rp", label = "Outfits" },
  { key = "general", label = "General" },
}
local NEXT_SECTION = { gear = "rp", rp = "general", general = "gear" }
local SECTION_LABEL = { gear = "Gear", rp = "Outfits", general = "General" }

-- Paper doll order, so gear lines up head to toe
local SLOT_ORDER = {
  INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CLOAK = 4,
  INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WRIST = 6, INVTYPE_HAND = 7,
  INVTYPE_WAIST = 8, INVTYPE_LEGS = 9, INVTYPE_FEET = 10, INVTYPE_FINGER = 11,
  INVTYPE_TRINKET = 12, INVTYPE_2HWEAPON = 13, INVTYPE_WEAPON = 13, INVTYPE_WEAPONMAINHAND = 13,
  INVTYPE_WEAPONOFFHAND = 14, INVTYPE_SHIELD = 14, INVTYPE_HOLDABLE = 14,
  INVTYPE_RANGED = 15, INVTYPE_RANGEDRIGHT = 15, INVTYPE_THROWN = 15, INVTYPE_RELIC = 15,
  INVTYPE_BODY = 16, INVTYPE_TABARD = 17,
}

-- Auction item class order: Weapon, Armor, Container, Consumable, Glyph, Trade Goods,
-- Projectile, Quiver, Recipe, Gem, Miscellaneous, Quest. Lower rank sorts first.
local RANK_BY_CLASS_INDEX = { 1, 1, 7, 3, 6, 4, 8, 8, 5, 2, 9, 10 }
local JUNK_RANK = 99

local windows = {}
local bagsWindow, bankWindow

local function RefreshAll()
  for _, w in ipairs(windows) do
    if w.frame:IsShown() then w:Refresh() end
  end
end

-- Shared helpers -------------------------------------------------------------

local function Glow(parent, alpha)
  local t = parent:CreateTexture(nil, "BACKGROUND")
  t:SetTexture(TEX .. "glow")
  t:SetBlendMode("ADD")
  t:SetVertexColor(unpack(NEON))
  t:SetAlpha(alpha)
  return t
end

local function NeonButton(parent, label, width, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(width)
  b:SetHeight(18)
  local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("CENTER")
  text:SetText(label)
  text:SetTextColor(unpack(NEON))
  local glow = Glow(b, 0.15)
  glow:SetAllPoints()
  b:SetScript("OnEnter", function() glow:SetAlpha(0.6); text:SetTextColor(1, 1, 1) end)
  b:SetScript("OnLeave", function() glow:SetAlpha(0.15); text:SetTextColor(unpack(NEON)) end)
  b:SetScript("OnClick", onClick)
  b.text = text
  return b
end

local classRank
local function RankOf(itemType, quality)
  if quality == 0 then return JUNK_RANK end
  if not classRank then
    classRank = {}
    for i, class in ipairs({ GetAuctionItemClasses() }) do
      classRank[class] = RANK_BY_CLASS_INDEX[i]
    end
  end
  return classRank[itemType] or 9
end

local function SectionOf(b)
  local override = BambooBagsDB.sections[b.itemID]
  if override then return override end
  if not b.slotOrder then return "general" end
  if b.equipLoc == "INVTYPE_BODY" or b.equipLoc == "INVTYPE_TABARD" then return "rp" end
  return b.itemLevel >= BambooBagsDB.gearLevel and "gear" or "rp"
end

local function OnItemClick(self, button)
  if button ~= "LeftButton" or not IsAltKeyDown() or not self.itemID then return end
  local target = NEXT_SECTION[SectionOf(self)]
  BambooBagsDB.sections[self.itemID] = target
  print("|cffc77dffBambooBags|r: " .. (GetContainerItemLink(self:GetParent():GetID(), self:GetID()) or "Item")
    .. " -> " .. SECTION_LABEL[target])
  RefreshAll()
end

local function UpdateButton(b, bag, slot)
  local texture, count, locked = GetContainerItemInfo(bag, slot)
  local link = GetContainerItemLink(bag, slot)

  b.hasItem = link and true or nil
  b.itemID = nil
  b.border:Hide()
  b.levelText:SetText("")

  if not link then
    SetItemButtonTexture(b, EMPTY_SLOT)
    SetItemButtonCount(b, 0)
    b.icon:SetVertexColor(0.85, 0.78, 0.65)
    b.searchText = nil
    return
  end

  SetItemButtonTexture(b, texture)
  SetItemButtonCount(b, count)
  SetItemButtonDesaturated(b, locked)
  if b.cooldown then ContainerFrame_UpdateCooldown(bag, b) end

  local name, _, quality, ilvl, _, itemType, subType, _, equipLoc = GetItemInfo(link)
  quality = quality or 1
  b.itemID = tonumber(link:match("item:(%d+)"))
  b.itemName = name and name:lower() or ""
  b.quality = quality
  b.itemLevel = ilvl or 0
  b.equipLoc = equipLoc
  b.slotOrder = SLOT_ORDER[equipLoc]
  b.rank = RankOf(itemType, quality)
  b.searchText = table.concat({ b.itemName, (itemType or ""):lower(), (subType or ""):lower() }, " ")

  local color = ITEM_QUALITY_COLORS[quality]
  if quality >= 2 and color then
    b.border:SetVertexColor(color.r, color.g, color.b)
    b.border:Show()
  end
  if b.slotOrder and (ilvl or 0) > 1 and color then
    b.levelText:SetText(ilvl)
    b.levelText:SetTextColor(color.r, color.g, color.b)
  end
end

local function CompareGear(a, b)
  local sa, sb = a.slotOrder or 99, b.slotOrder or 99
  if sa ~= sb then return sa < sb end
  if a.itemLevel ~= b.itemLevel then return a.itemLevel > b.itemLevel end
  if a.itemName ~= b.itemName then return a.itemName < b.itemName end
  return a.order < b.order
end

local function CompareGeneral(a, b)
  if a.rank ~= b.rank then return a.rank < b.rank end
  if a.quality ~= b.quality then return a.quality > b.quality end
  if a.itemName ~= b.itemName then return a.itemName < b.itemName end
  return a.order < b.order
end

-- Window ---------------------------------------------------------------------

local Window = {}
Window.__index = Window

-- opts: title, bags (list of bag ids), pointKey (saved position), defaultPoint, showMoney, extraButtons
local function NewWindow(frameName, opts)
  local w = setmetatable({
    name = frameName, bags = opts.bags, pointKey = opts.pointKey, defaultPoint = opts.defaultPoint,
    holders = {}, buttons = {}, allButtons = {}, sectionTitles = {}, stamp = 0, dirty = true,
  }, Window)

  local f = CreateFrame("Frame", frameName, UIParent)
  w.frame = f
  f:Hide()
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetBackdrop({
    bgFile = TEX .. "linen", edgeFile = TEX .. "bamboo",
    tile = true, tileSize = 128, edgeSize = EDGE,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
  })
  tinsert(UISpecialFrames, frameName) -- Escape closes it

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", INSET, -(INSET - 4))
  title:SetText(opts.title)
  title:SetTextColor(unpack(NEON))
  local titleGlow = Glow(f, 0.35)
  titleGlow:SetPoint("TOPLEFT", title, "TOPLEFT", -14, 10)
  titleGlow:SetPoint("BOTTOMRIGHT", title, "BOTTOMRIGHT", 14, -10)

  -- Header buttons are laid out right to left
  local last
  local function AddHeaderButton(label, width, onClick)
    local b = NeonButton(f, label, width, onClick)
    if last then
      b:SetPoint("RIGHT", last, "LEFT", -2, 0)
    else
      b:SetPoint("TOPRIGHT", -INSET + 4, -(INSET - 6))
    end
    last = b
    return b
  end
  AddHeaderButton("x", 18, function() f:Hide() end)
  for _, extra in ipairs(opts.extraButtons or {}) do
    AddHeaderButton(extra[1], extra[2], extra[3])
  end
  w.sortButton = AddHeaderButton("Sections", 62, function()
    BambooBagsDB.sorted = not BambooBagsDB.sorted
    RefreshAll()
  end)

  local search = CreateFrame("EditBox", frameName .. "Search", f, "InputBoxTemplate")
  w.search = search
  search:SetAutoFocus(false)
  search:SetWidth(90)
  search:SetHeight(18)
  search:SetPoint("RIGHT", last, "LEFT", -8, 0)
  local placeholder = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  placeholder:SetPoint("LEFT", 2, 0)
  placeholder:SetText("Search...")
  search:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
  search:SetScript("OnEditFocusLost", function(self)
    if self:GetText() == "" then placeholder:Show() end
  end)
  search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  search:SetScript("OnTextChanged", function() w:ApplySearch() end)

  -- Section titles, each followed by a thin twine line
  for _, s in ipairs(SECTIONS) do
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetText(s.label)
    t:SetTextColor(unpack(NEON))
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetTexture(TWINE[1], TWINE[2], TWINE[3], 0.7)
    line:SetHeight(1)
    line:SetPoint("LEFT", t, "RIGHT", 6, 0)
    w.sectionTitles[s.key] = { title = t, line = line }
  end

  w.freeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  w.freeText:SetPoint("BOTTOMLEFT", INSET, INSET - 4)
  if opts.showMoney then
    w.moneyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.moneyText:SetPoint("BOTTOMRIGHT", -INSET, INSET - 4)
  end

  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    BambooBagsDB[w.pointKey] = { point, relPoint, x, y }
  end)
  f:SetScript("OnShow", function()
    w.dirty = true
    PlaySound("igBackPackOpen")
    if w.onShow then w.onShow() end
  end)
  f:SetScript("OnHide", function()
    search:ClearFocus()
    PlaySound("igBackPackClose")
    if w.onHide then w.onHide() end
  end)
  -- OnUpdate only runs while the window is shown, so hidden windows cost nothing
  f:SetScript("OnUpdate", function()
    if w.dirty then
      w.dirty = false
      w:Refresh()
    end
  end)

  table.insert(windows, w)
  return w
end

function Window:RestorePosition()
  local f = self.frame
  f:ClearAllPoints()
  local p = BambooBagsDB[self.pointKey] or self.defaultPoint
  f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

function Window:UpdateMoney()
  if not self.moneyText then return end
  local copper = GetMoney()
  if GetCoinTextureString then
    self.moneyText:SetText(GetCoinTextureString(copper))
  else
    self.moneyText:SetText(string.format("%dg %ds %dc", copper / 10000, (copper / 100) % 100, copper % 100))
  end
end

-- Blizzard's item button templates read the bag id from the parent's ID and the slot from their own,
-- so each bag gets an invisible holder frame. Buttons can still be positioned anywhere.
function Window:GetButton(bag, slot)
  if not self.holders[bag] then
    self.holders[bag] = CreateFrame("Frame", self.name .. "Bag" .. bag, self.frame)
    self.holders[bag]:SetID(bag)
    self.buttons[bag] = {}
  end
  local b = self.buttons[bag][slot]
  if b then return b end

  -- The bank's main 28 slots aren't a real bag and need Blizzard's bank button template
  local template = bag == BANK_CONTAINER and "BankItemButtonGenericTemplate" or "ContainerFrameItemButtonTemplate"
  local name = self.name .. "Item" .. bag .. "_" .. slot
  b = CreateFrame("Button", name, self.holders[bag], template)
  b:SetID(slot)
  b:SetScale(SCALE)
  b.icon = _G[name .. "IconTexture"]
  b.cooldown = _G[name .. "Cooldown"]
  b:GetHighlightTexture():SetVertexColor(unpack(NEON))
  b:HookScript("OnClick", OnItemClick)

  -- Text is drawn at button scale, so use bigger fonts to stay readable
  local font = NumberFontNormal:GetFont()
  _G[name .. "Count"]:SetFont(font, 16, "OUTLINE")

  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.border:SetBlendMode("ADD")
  b.border:SetWidth(67)
  b.border:SetHeight(67)
  b.border:SetPoint("CENTER")

  b.levelText = b:CreateFontString(nil, "OVERLAY")
  b.levelText:SetFont(font, 15, "OUTLINE")
  b.levelText:SetPoint("TOPLEFT", 1, -1)

  local quest = _G[name .. "IconQuestTexture"]
  if quest then quest:Hide() end

  self.buttons[bag][slot] = b
  table.insert(self.allButtons, b)
  return b
end

function Window:ApplySearch()
  local query = self.search:GetText():lower()
  for _, b in ipairs(self.allButtons) do
    local match = query == "" or (b.searchText and b.searchText:find(query, 1, true))
    b:SetAlpha(match and 1 or 0.2)
  end
end

-- Lays out buttons in a grid starting at `top` (pixels from the frame's top); returns the grid's bottom
function Window:PlaceGrid(list, top)
  for i, b in ipairs(list) do
    local col = (i - 1) % COLUMNS
    local row = math.floor((i - 1) / COLUMNS)
    b:ClearAllPoints()
    -- Offsets are in the button's own (scaled) coordinates
    b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (INSET + col * (SIZE + GAP)) / SCALE, -(top + row * (SIZE + GAP)) / SCALE)
    b:Show()
  end
  return top + math.ceil(#list / COLUMNS) * (SIZE + GAP) - GAP
end

function Window:Refresh()
  self.stamp = self.stamp + 1
  local all, empties = {}, {}
  local lists = { gear = {}, rp = {}, general = {} }

  for _, bag in ipairs(self.bags) do
    for slot = 1, GetContainerNumSlots(bag) do
      local b = self:GetButton(bag, slot)
      b.stamp = self.stamp
      b.order = #all
      UpdateButton(b, bag, slot)
      table.insert(all, b)
      if b.hasItem then
        table.insert(lists[SectionOf(b)], b)
      else
        table.insert(empties, b)
      end
    end
  end

  -- Hide buttons for slots that disappeared (a bag was removed)
  for _, b in ipairs(self.allButtons) do
    if b.stamp ~= self.stamp then b:Hide() end
  end

  local f = self.frame
  local width = INSET * 2 + COLUMNS * SIZE + (COLUMNS - 1) * GAP
  f:SetWidth(width)
  local y = INSET + HEADER

  if BambooBagsDB.sorted then
    table.sort(lists.gear, CompareGear)
    table.sort(lists.rp, CompareGear)
    table.sort(lists.general, CompareGeneral)
    for _, b in ipairs(empties) do table.insert(lists.general, b) end

    for _, s in ipairs(SECTIONS) do
      local list = lists[s.key]
      local st = self.sectionTitles[s.key]
      if #list > 0 then
        st.title:ClearAllPoints()
        st.title:SetPoint("TOPLEFT", f, "TOPLEFT", INSET, -y)
        st.title:Show()
        st.line:SetWidth(width - INSET * 2 - st.title:GetStringWidth() - 6)
        st.line:Show()
        y = self:PlaceGrid(list, y + SECTION_TITLE) + SECTION_GAP
      else
        st.title:Hide()
        st.line:Hide()
      end
    end
  else
    for _, st in pairs(self.sectionTitles) do
      st.title:Hide()
      st.line:Hide()
    end
    y = self:PlaceGrid(all, y) + SECTION_GAP
  end

  f:SetHeight(y - SECTION_GAP + FOOTER + INSET)

  self.sortButton.text:SetText(BambooBagsDB.sorted and "Sections" or "Bag order")
  self.freeText:SetText(string.format("Free  %d / %d", #empties, #all))
  self:UpdateMoney()
  self:ApplySearch()
end

-- The two windows ------------------------------------------------------------

local backpackBags = {}
for bag = 0, NUM_BAG_SLOTS do table.insert(backpackBags, bag) end

local bankBags = { BANK_CONTAINER }
for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do table.insert(bankBags, bag) end

bagsWindow = NewWindow("BambooBagsFrame", {
  title = "Bamboo Bags",
  bags = backpackBags,
  pointKey = "point",
  defaultPoint = { "BOTTOMRIGHT", "BOTTOMRIGHT", -80, 120 },
  showMoney = true,
  extraButtons = {
    { "Dump", 40, function()
      if SlashCmdList.GEARDUMP then
        bagsWindow.frame:Hide()
        SlashCmdList.GEARDUMP("")
      else
        print("BambooBags: GearDump isn't loaded.")
      end
    end },
  },
})

bankWindow = NewWindow("BambooBankFrame", {
  title = "Bamboo Bank",
  bags = bankBags,
  pointKey = "bankPoint",
  defaultPoint = { "TOPLEFT", "TOPLEFT", 40, -110 },
})

-- Light up the backpack and bag bar buttons while the bags are open, like the default UI does
local function SetBagBarLit(lit)
  local checked = lit and 1 or nil
  MainMenuBarBackpackButton:SetChecked(checked)
  for i = 0, NUM_BAG_SLOTS - 1 do
    local slotButton = _G["CharacterBag" .. i .. "Slot"]
    if slotButton then slotButton:SetChecked(checked) end
  end
end
bagsWindow.onShow = function() SetBagBarLit(true) end
bagsWindow.onHide = function() SetBagBarLit(false) end

-- Sell junk: a footer button that only shows while a vendor is open
local function CountJunk()
  local count = 0
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      if link and select(3, GetItemInfo(link)) == 0 then count = count + 1 end
    end
  end
  return count
end

local function SellJunk()
  if not MerchantFrame:IsShown() then return end
  local sold, copper = 0, 0
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      local _, itemCount, locked = GetContainerItemInfo(bag, slot)
      if link and not locked then
        local _, _, quality, _, _, _, _, _, _, _, price = GetItemInfo(link)
        if quality == 0 then
          UseContainerItem(bag, slot) -- with a vendor open, this sells the item
          sold = sold + 1
          copper = copper + (price or 0) * (itemCount or 1)
        end
      end
    end
  end
  if sold > 0 then
    local earned = copper > 0 and GetCoinTextureString and (" for " .. GetCoinTextureString(copper)) or ""
    print("|cffc77dffBambooBags|r: sold " .. sold .. " junk item" .. (sold == 1 and "" or "s") .. earned .. ".")
  else
    print("|cffc77dffBambooBags|r: no junk to sell.")
  end
end

local sellButton = NeonButton(bagsWindow.frame, "Sell junk", 96, SellJunk)
sellButton:SetPoint("BOTTOM", 0, INSET - 7)
sellButton:Hide()

local function UpdateSellButton()
  if not sellButton:IsShown() then return end
  local count = CountJunk()
  sellButton.text:SetText(count > 0 and ("Sell junk (" .. count .. ")") or "No junk")
end

-- Closing our bank window ends the bank visit, just like closing Blizzard's
bankWindow.onHide = function() CloseBankFrame() end

-- Blizzard's bank frame must never show; we open and close ours from the bank events instead.
-- (Hiding BankFrame itself would end the bank visit, so we silence its events.)
BankFrame:UnregisterAllEvents()

-- Events ---------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == "BambooBags" then
      BambooBagsDB = BambooBagsDB or {}
      if BambooBagsDB.sorted == nil then BambooBagsDB.sorted = true end
      BambooBagsDB.sections = BambooBagsDB.sections or {}
      BambooBagsDB.gearLevel = BambooBagsDB.gearLevel or DEFAULT_GEAR_LEVEL
      for _, w in ipairs(windows) do w:RestorePosition() end
    end
  elseif event == "BANKFRAME_OPENED" then
    bankWindow.frame:Show()
    bagsWindow.frame:Show()
  elseif event == "BANKFRAME_CLOSED" then
    bankWindow.frame:Hide()
  elseif event == "MERCHANT_SHOW" then
    sellButton:Show()
    UpdateSellButton()
    bagsWindow.frame:Show()
  elseif event == "MERCHANT_CLOSED" then
    sellButton:Hide()
  elseif event == "PLAYER_MONEY" then
    bagsWindow:UpdateMoney()
  else
    for _, w in ipairs(windows) do w.dirty = true end
    UpdateSellButton()
  end
end)

-- Take over the bag keybinds and the backpack/bag bar buttons -----------------

local function Toggle()
  local f = bagsWindow.frame
  if f:IsShown() then f:Hide() else f:Show() end
end

local function IsBackpackBag(id)
  return id and id >= 0 and id <= NUM_BAG_SLOTS
end

local origToggleBag, origOpenBag, origCloseBag = ToggleBag, OpenBag, CloseBag

ToggleBackpack = Toggle
OpenBackpack = function() bagsWindow.frame:Show() end
CloseBackpack = function() bagsWindow.frame:Hide() end
CloseAllBags = function() bagsWindow.frame:Hide() end
OpenAllBags = function(forceOpen)
  if forceOpen then bagsWindow.frame:Show() else Toggle() end
end
ToggleBag = function(id)
  if IsBackpackBag(id) then Toggle() else origToggleBag(id) end
end
OpenBag = function(id)
  if IsBackpackBag(id) then bagsWindow.frame:Show() else origOpenBag(id) end
end
CloseBag = function(id)
  if IsBackpackBag(id) then bagsWindow.frame:Hide() else origCloseBag(id) end
end

SLASH_BAMBOOBAGS1 = "/bb"
SlashCmdList["BAMBOOBAGS"] = function(msg)
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  if cmd == "reset" then
    BambooBagsDB.point = nil
    BambooBagsDB.bankPoint = nil
    for _, w in ipairs(windows) do w:RestorePosition() end
  elseif cmd == "gearlevel" and tonumber(arg) then
    BambooBagsDB.gearLevel = tonumber(arg)
    print("|cffc77dffBambooBags|r: gear at item level " .. arg .. "+ goes in Gear.")
    RefreshAll()
  elseif cmd == "resetsections" then
    BambooBagsDB.sections = {}
    print("|cffc77dffBambooBags|r: all Alt+click section choices cleared.")
    RefreshAll()
  else
    Toggle()
  end
end
