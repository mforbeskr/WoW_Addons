-- BambooBags: your bags and bank in two bamboo-framed, translucent hemp-cloth windows, split into Gear / Outfits / General.
-- Sorting is "virtual": items are shown in sorted order but never moved, so it's instant and safe.
-- Alt+Left-click an item to move it to another section; the choice is remembered per item.

local TEX = "Interface\\AddOns\\BambooBags\\textures\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local PREFIX = "|cffe6c35cBags|r: "
local ACCENT = { 0.9, 0.76, 0.42 }   -- muted gold for section labels, hover and focus
local TEXT = { 0.86, 0.86, 0.88 }
local MUTED = { 0.6, 0.6, 0.63 }
local BLACK = { 0, 0, 0, 0.95 }
local COLUMNS = 14
local SCALE = 0.6          -- Blizzard item buttons are 37px; this makes them ~22px
local SIZE = 37 * SCALE
local GAP = 3
local INSET = 15           -- frame edge to content
local BAMBOO_EDGE = 10     -- bamboo border thickness (32px texture shown at 10px)
local HEADER = 26
local SECTION_TITLE = 14
local SECTION_GAP = 6
local FOOTER = 18
local SELL_ROW = 24        -- extra footer row for the Sell junk button while a vendor is open
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local DEFAULT_GEAR_LEVEL = 200
local DEFAULT_ALPHA = 0.82 -- background opacity; items and text stay fully opaque

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

-- Drawing helpers --------------------------------------------------------------
-- Edges are 1-screen-pixel lines so they stay crisp at any UI scale. Each line registers a small
-- layout job that reruns only when the pixel size changes (UI scale or resolution change).

local px = 1
local pixelJobs = {}
local function PixelJob(fn)
  table.insert(pixelJobs, fn)
  fn(px)
end

local function UpdatePixelSize()
  local h = tonumber((GetCVar("gxResolution") or ""):match("%d+x(%d+)"))
  local scale = UIParent:GetEffectiveScale()
  local new = (h and h > 0 and scale > 0) and (768 / h / scale) or 1
  if new == px then return end
  px = new
  for _, fn in ipairs(pixelJobs) do fn(px) end
end

local function Solid(parent, layer, c)
  local t = parent:CreateTexture(nil, layer)
  t:SetTexture(WHITE)
  t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  return t
end

-- A 1px line along one side of `parent`, `inset` pixels in from its edge
local function EdgeLine(parent, layer, side, inset, c)
  local t = Solid(parent, layer, c)
  PixelJob(function(p)
    local n = inset * p
    t:ClearAllPoints()
    if side == "TOP" then
      t:SetPoint("TOPLEFT", n, -n); t:SetPoint("TOPRIGHT", -n, -n); t:SetHeight(p)
    elseif side == "BOTTOM" then
      t:SetPoint("BOTTOMLEFT", n, n); t:SetPoint("BOTTOMRIGHT", -n, n); t:SetHeight(p)
    elseif side == "LEFT" then
      t:SetPoint("TOPLEFT", n, -n - p); t:SetPoint("BOTTOMLEFT", n, n + p); t:SetWidth(p)
    else
      t:SetPoint("TOPRIGHT", -n, -n - p); t:SetPoint("BOTTOMRIGHT", -n, n + p); t:SetWidth(p)
    end
  end)
  return t
end

-- Four edge lines; top/left get `lit`, bottom/right `shade` (raised or sunken look)
local function Ring(parent, layer, inset, lit, shade)
  return {
    top = EdgeLine(parent, layer, "TOP", inset, lit),
    left = EdgeLine(parent, layer, "LEFT", inset, lit),
    bottom = EdgeLine(parent, layer, "BOTTOM", inset, shade),
    right = EdgeLine(parent, layer, "RIGHT", inset, shade),
  }
end

local function SetRingColor(ring, lit, shade)
  ring.top:SetVertexColor(unpack(lit)); ring.left:SetVertexColor(unpack(lit))
  ring.bottom:SetVertexColor(unpack(shade)); ring.right:SetVertexColor(unpack(shade))
end

-- Soft shadow around a frame, cut from the radial glow texture (corners = its quarters,
-- sides = a thin slice through its middle). Lifts the window off the game world.
local SHADOW_PIECES = {
  -- point, relPoint, point2, relPoint2, texcoords
  { "BOTTOMRIGHT", "TOPLEFT", nil, nil, 0, .5, 0, .5 },
  { "BOTTOMLEFT", "TOPRIGHT", nil, nil, .5, 1, 0, .5 },
  { "TOPRIGHT", "BOTTOMLEFT", nil, nil, 0, .5, .5, 1 },
  { "TOPLEFT", "BOTTOMRIGHT", nil, nil, .5, 1, .5, 1 },
  { "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", .49, .51, 0, .5 },     -- top
  { "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT", .49, .51, .5, 1 },     -- bottom
  { "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", 0, .5, .49, .51 },     -- left
  { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", .5, 1, .49, .51 },     -- right
}
local function DropShadow(f, s, alpha)
  for i, p in ipairs(SHADOW_PIECES) do
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(TEX .. "glow")
    t:SetVertexColor(0, 0, 0, alpha)
    t:SetTexCoord(p[5], p[6], p[7], p[8])
    t:SetPoint(p[1], f, p[2])
    if p[3] then t:SetPoint(p[3], f, p[4]) end
    if i <= 4 or i >= 7 then t:SetWidth(s) end
    if i <= 6 then t:SetHeight(s) end
  end
end

-- Etched divider: a dark line with a faint light line under it. Returns the dark line to anchor.
local function Groove(parent)
  local dark = Solid(parent, "ARTWORK", { 0, 0, 0, 0.6 })
  local light = Solid(parent, "ARTWORK", { 1, 1, 1, 0.07 })
  light:SetPoint("TOPLEFT", dark, "BOTTOMLEFT")
  light:SetPoint("TOPRIGHT", dark, "BOTTOMRIGHT")
  PixelJob(function(p) dark:SetHeight(p); light:SetHeight(p) end)
  return dark
end

-- Covers the frame (inside the bamboo border) with 128px weave tiles, cropping the last row/column.
-- Tiles are created once and reused; only runs when the window is laid out.
local TILE = 128
local TILE_INSET = 3 -- the bamboo stalks start a few pixels in from the frame edge
local function TileBackground(f, w, h)
  w, h = w - TILE_INSET * 2, h - TILE_INSET * 2
  local cols, rows = math.ceil(w / TILE), math.ceil(h / TILE)
  local alpha = BambooBagsDB.alpha or DEFAULT_ALPHA
  local n = 0
  for r = 1, rows do
    local th = math.min(TILE, h - (r - 1) * TILE)
    for c = 1, cols do
      local tw = math.min(TILE, w - (c - 1) * TILE)
      n = n + 1
      local t = f.tiles[n]
      if not t then
        t = f:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(TEX .. "weave")
        f.tiles[n] = t
      end
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", TILE_INSET + (c - 1) * TILE, -(TILE_INSET + (r - 1) * TILE))
      t:SetWidth(tw)
      t:SetHeight(th)
      t:SetTexCoord(0, tw / TILE, 0, th / TILE)
      t:SetAlpha(alpha)
      t:Show()
    end
  end
  for i = n + 1, #f.tiles do f.tiles[i]:Hide() end
end

-- Lays out a stitch line of the given width from 64px pieces (the client won't repeat a
-- texture); pieces are created once and reused. Tinted to the gold accent and kept faint.
local STITCH_ALPHA = 0.5
local function SetStitchWidth(line, w)
  line:SetWidth(w)
  local n = math.ceil(w / 64)
  for i = 1, math.max(n, #line.segs) do
    local seg = line.segs[i]
    if i <= n then
      if not seg then
        seg = line:CreateTexture(nil, "ARTWORK")
        seg:SetTexture(TEX .. "stitch")
        seg:SetVertexColor(1, 0.95, 0.85, STITCH_ALPHA)
        seg:SetHeight(8)
        seg:SetPoint("LEFT", (i - 1) * 64, 0)
        line.segs[i] = seg
      end
      local segW = math.min(64, w - (i - 1) * 64)
      seg:SetWidth(segW)
      seg:SetTexCoord(0, segW / 64, 0, 1)
      seg:Show()
    elseif seg then
      seg:Hide()
    end
  end
end

-- Raised button: dark vertical gradient, black outline and a lit top edge. Lighter with a gold
-- edge on hover, pressed in (darker, text nudged down) while held.
local function StyledButton(parent, label, width, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(width)
  b:SetHeight(18)
  local bg = Solid(b, "BACKGROUND", TEXT)
  bg:SetAllPoints()
  local outline = Ring(b, "BORDER", 0, BLACK, BLACK)
  local rim = EdgeLine(b, "ARTWORK", "TOP", 1, { 1, 1, 1, 0.13 })
  local hoverEdge = { ACCENT[1], ACCENT[2], ACCENT[3], 0.6 }
  local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetText(label)

  local hover, down
  local function Paint()
    local top, bottom = 0.2, 0.1
    if down then top, bottom = 0.09, 0.13
    elseif hover then top, bottom = 0.3, 0.16 end
    bg:SetGradientAlpha("VERTICAL", bottom, bottom, bottom + 0.01, 0.92, top, top, top + 0.015, 0.92)
    rim:SetAlpha(down and 0 or 1)
    local edge = hover and hoverEdge or BLACK
    SetRingColor(outline, edge, edge)
    if hover then text:SetTextColor(1, 1, 1) else text:SetTextColor(unpack(TEXT)) end
    text:ClearAllPoints()
    text:SetPoint("CENTER", down and 1 or 0, down and -1 or 0)
  end
  Paint()
  b:SetScript("OnEnter", function() hover = true; Paint() end)
  b:SetScript("OnLeave", function() hover = false; down = false; Paint() end)
  b:SetScript("OnMouseDown", function() down = true; Paint() end)
  b:SetScript("OnMouseUp", function() down = false; Paint() end)
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
  if not b.slotOrder or b.quality == 0 then return "general" end
  if b.equipLoc == "INVTYPE_BODY" or b.equipLoc == "INVTYPE_TABARD" then return "rp" end
  return b.itemLevel >= BambooBagsDB.gearLevel and "gear" or "rp"
end

local function OnItemClick(self, button)
  if button ~= "LeftButton" or not IsAltKeyDown() or not self.itemID then return end
  local target = NEXT_SECTION[SectionOf(self)]
  BambooBagsDB.sections[self.itemID] = target
  print(PREFIX .. (GetContainerItemLink(self:GetParent():GetID(), self:GetID()) or "Item")
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
    b.icon:SetVertexColor(0.5, 0.5, 0.53)
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

-- opts: title, bags (list of bag ids), pointKey (saved position), defaultPoint, showMoney, extraButtons,
--       footer (extra pixels at the bottom for window-specific controls)
local function NewWindow(frameName, opts)
  local w = setmetatable({
    name = frameName, bags = opts.bags, pointKey = opts.pointKey, defaultPoint = opts.defaultPoint,
    holders = {}, buttons = {}, allButtons = {}, sectionTitles = {}, stamp = 0, dirty = true,
    footer = FOOTER + (opts.footer or 0),
  }, Window)

  local f = CreateFrame("Frame", frameName, UIParent)
  w.frame = f
  f:Hide()
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  tinsert(UISpecialFrames, frameName) -- Escape closes it

  -- Look: a solid bamboo frame (lashed corners) around translucent dark hemp cloth (tiles laid
  -- out by TileBackground; backdrop tiling smears), light from above, soft drop shadow.
  f:SetBackdrop({
    edgeFile = TEX .. "bamboo", edgeSize = BAMBOO_EDGE,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  f:SetBackdropBorderColor(1, 1, 1, 1)
  f.tiles = {}
  DropShadow(f, 12, 0.55)
  local shade = Solid(f, "BORDER", TEXT)
  shade:SetPoint("TOPLEFT", 3, -3)
  shade:SetPoint("BOTTOMRIGHT", -3, 3)
  shade:SetGradientAlpha("VERTICAL", 0, 0, 0, 0.25, 1, 1, 1, 0.045)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", INSET, -(INSET - 3))
  title:SetText(opts.title)
  title:SetTextColor(0.95, 0.95, 0.95)
  title:SetShadowOffset(1, -1)

  local headerLine = Groove(f)
  headerLine:SetPoint("TOPLEFT", INSET - 3, -(INSET + HEADER - 9))
  headerLine:SetPoint("TOPRIGHT", -(INSET - 3), -(INSET + HEADER - 9))
  w.footerLine = Groove(f)

  -- Header buttons are laid out right to left
  local last
  local function AddHeaderButton(label, width, onClick)
    local b = StyledButton(f, label, width, onClick)
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

  -- Search field: sunken (dark top/left edge, faint light bottom/right, inner shadow at the top)
  local search = CreateFrame("EditBox", frameName .. "Search", f)
  w.search = search
  search:SetAutoFocus(false)
  search:SetFontObject(GameFontHighlightSmall)
  search:SetTextInsets(6, 6, 0, 0)
  search:SetWidth(104)
  search:SetHeight(18)
  search:SetPoint("RIGHT", last, "LEFT", -8, 0)
  local searchBg = Solid(search, "BACKGROUND", { 0, 0, 0, 0.45 })
  searchBg:SetAllPoints()
  local innerShadow = Solid(search, "BORDER", BLACK)
  innerShadow:SetPoint("TOPLEFT")
  innerShadow:SetPoint("TOPRIGHT")
  innerShadow:SetHeight(5)
  innerShadow:SetGradientAlpha("VERTICAL", 0, 0, 0, 0, 0, 0, 0, 0.4)
  local SUNKEN_LIT, SUNKEN_SHADE = { 0, 0, 0, 0.9 }, { 1, 1, 1, 0.12 }
  local FOCUS = { ACCENT[1], ACCENT[2], ACCENT[3], 0.7 }
  local searchEdge = Ring(search, "ARTWORK", 0, SUNKEN_LIT, SUNKEN_SHADE)
  local placeholder = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  placeholder:SetPoint("LEFT", 6, 0)
  placeholder:SetText("Search")
  search:SetScript("OnEditFocusGained", function()
    placeholder:Hide()
    SetRingColor(searchEdge, FOCUS, FOCUS)
  end)
  search:SetScript("OnEditFocusLost", function(self)
    if self:GetText() == "" then placeholder:Show() end
    SetRingColor(searchEdge, SUNKEN_LIT, SUNKEN_SHADE)
  end)
  search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  search:SetScript("OnTextChanged", function() w:ApplySearch() end)

  -- Section titles, each followed by a quiet embroidered running stitch in the same gold
  for _, s in ipairs(SECTIONS) do
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetText(s.label)
    t:SetTextColor(unpack(ACCENT))
    local line = CreateFrame("Frame", nil, f)
    line.segs = {}
    line:SetHeight(8)
    line:SetPoint("LEFT", t, "RIGHT", 6, 0)
    w.sectionTitles[s.key] = { title = t, line = line }
  end

  w.freeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  w.freeText:SetPoint("BOTTOMLEFT", INSET, INSET - 4)
  w.freeText:SetTextColor(unpack(MUTED))
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
        local lineW = width - INSET * 2 - st.title:GetStringWidth() - 6
        SetStitchWidth(st.line, lineW)
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

  local footer = self.footer + (self.extraFooter or 0)
  local height = y - SECTION_GAP + footer + INSET
  f:SetHeight(height)
  TileBackground(f, width, height)
  self.footerLine:ClearAllPoints()
  self.footerLine:SetPoint("BOTTOMLEFT", INSET - 3, INSET + footer - 3)
  self.footerLine:SetPoint("BOTTOMRIGHT", -(INSET - 3), INSET + footer - 3)

  self.sortButton.text:SetText(BambooBagsDB.sorted and "Sections" or "Bag order")
  self.freeText:SetText(string.format("Free %d/%d", #empties, #all))
  self:UpdateMoney()
  self:ApplySearch()
  if self.onRefresh then self.onRefresh() end
end

-- The two windows ------------------------------------------------------------

local backpackBags = {}
for bag = 0, NUM_BAG_SLOTS do table.insert(backpackBags, bag) end

local bankBags = { BANK_CONTAINER }
for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do table.insert(bankBags, bag) end

bagsWindow = NewWindow("BambooBagsFrame", {
  title = "Bags",
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
  title = "Bank",
  bags = bankBags,
  pointKey = "bankPoint",
  defaultPoint = { "TOPLEFT", "TOPLEFT", 40, -110 },
  footer = SIZE + 6, -- room for the bank bag slot row
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

-- Sell junk: a footer button that only shows while a vendor is open.
-- Only grey items, and never one you've put in Outfits with Alt+click.
local function JunkAt(bag, slot)
  local link = GetContainerItemLink(bag, slot)
  if not link then return end
  local _, _, quality, _, _, _, _, _, _, _, price = GetItemInfo(link)
  if quality ~= 0 then return end
  local itemID = tonumber(link:match("item:(%d+)"))
  if BambooBagsDB.sections[itemID] == "rp" then return end
  return price or 0
end

local function CountJunk()
  local count = 0
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bag) do
      if JunkAt(bag, slot) then count = count + 1 end
    end
  end
  return count
end

local function SellJunk()
  if not MerchantFrame:IsShown() then return end
  local sold, copper = 0, 0
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bag) do
      local price = JunkAt(bag, slot)
      local _, itemCount, locked = GetContainerItemInfo(bag, slot)
      if price and not locked then
        UseContainerItem(bag, slot) -- with a vendor open, this sells the item
        sold = sold + 1
        copper = copper + price * (itemCount or 1)
      end
    end
  end
  if sold > 0 then
    local earned = copper > 0 and GetCoinTextureString and (" for " .. GetCoinTextureString(copper)) or ""
    print(PREFIX .. "sold " .. sold .. " junk item" .. (sold == 1 and "" or "s") .. earned .. ".")
  else
    print(PREFIX .. "no junk to sell.")
  end
end

local sellButton = StyledButton(bagsWindow.frame, "Sell junk", 110, SellJunk)
sellButton:SetPoint("BOTTOM", 0, INSET + FOOTER)
sellButton:Hide()

-- Tracked currencies (the ones ticked "Show on Backpack" in the Currency tab, e.g. emblems and
-- honor) in the footer, like the default backpack. Hover for the tooltip, click opens the tab.
local tokenButtons = {}
for i = 1, MAX_WATCHED_TOKENS or 3 do
  local b = CreateFrame("Button", nil, bagsWindow.frame)
  b:SetID(i)
  b:SetHeight(14)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetWidth(13)
  b.icon:SetHeight(13)
  b.icon:SetPoint("RIGHT")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("RIGHT", b.icon, "LEFT", -2, 0)
  if i == 1 then
    b:SetPoint("LEFT", bagsWindow.freeText, "RIGHT", 12, 0)
  else
    b:SetPoint("LEFT", tokenButtons[i - 1], "RIGHT", 9, 0)
  end
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if GameTooltip.SetBackpackToken then
      GameTooltip:SetBackpackToken(self:GetID())
    else
      GameTooltip:SetText((GetBackpackCurrencyInfo(self:GetID())))
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function() ToggleCharacter("TokenFrame") end)
  b:Hide()
  tokenButtons[i] = b
end

local function UpdateTokens()
  if not GetBackpackCurrencyInfo then return end
  for i, b in ipairs(tokenButtons) do
    local name, count, extraType, icon = GetBackpackCurrencyInfo(i)
    if name then
      b.icon:SetTexCoord(0, 1, 0, 1)
      if extraType == 1 then
        b.icon:SetTexture("Interface\\PVPFrame\\PVP-ArenaPoints-Icon")
      elseif extraType == 2 then
        b.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. (UnitFactionGroup("player") or "Alliance"))
        b.icon:SetTexCoord(0.03125, 0.59375, 0.03125, 0.59375)
      else
        b.icon:SetTexture(icon)
      end
      b.text:SetText(count)
      b:SetWidth(b.text:GetStringWidth() + 15)
      b:Show()
    else
      b:Hide()
    end
  end
end
bagsWindow.onRefresh = UpdateTokens

-- Ticking "Show on Backpack" calls this; the Currency UI loads on demand, so hook when it exists
local tokenHooked
local function HookTokenUpdates()
  if tokenHooked or not BackpackTokenFrame_Update then return end
  tokenHooked = true
  hooksecurefunc("BackpackTokenFrame_Update", function()
    if bagsWindow.frame:IsShown() then UpdateTokens() end
  end)
end
HookTokenUpdates()

local function UpdateSellButton()
  if not sellButton:IsShown() then return end
  local count = CountJunk()
  sellButton.text:SetText(count > 0 and ("Sell junk (" .. count .. ")") or "No junk")
end

-- Bank bag slots: Blizzard's bank frame is hidden, so the bank window gets its own row of
-- bag slots (click or drag a bag onto one) and a button to buy the next slot.
local function MoneyString(copper)
  return GetCoinTextureString and GetCoinTextureString(copper)
    or string.format("%dg %ds %dc", copper / 10000, (copper / 100) % 100, copper % 100)
end

StaticPopupDialogs.BAMBOOBAGS_BUY_BANK_SLOT = {
  text = "Buy a new bank bag slot for %s?",
  button1 = YES,
  button2 = NO,
  OnAccept = function() PurchaseSlot() end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

local bankSlots = {}
for i = 1, NUM_BANKBAGSLOTS do
  local invSlot = BankButtonIDToInvSlotID(i, 1)
  local b = CreateFrame("Button", nil, bankWindow.frame)
  b:SetWidth(SIZE)
  b:SetHeight(SIZE)
  b:SetPoint("BOTTOMLEFT", bankWindow.frame, "BOTTOMLEFT", INSET + (i - 1) * (SIZE + GAP), INSET + FOOTER - 2)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  Ring(b, "OVERLAY", 0, BLACK, BLACK)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:RegisterForDrag("LeftButton")

  local function PickupOrPlace()
    if i > GetNumBankSlots() then return end
    if CursorHasItem() then PutItemInBag(invSlot) else PickupBagFromSlot(invSlot) end
  end
  b:SetScript("OnClick", PickupOrPlace)
  b:SetScript("OnDragStart", PickupOrPlace)
  b:SetScript("OnReceiveDrag", PickupOrPlace)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if i > GetNumBankSlots() then
      GameTooltip:SetText("Bank bag slot (not bought yet)")
    elseif not GameTooltip:SetInventoryItem("player", invSlot) then
      GameTooltip:SetText("Empty bank bag slot")
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  bankSlots[i] = { button = b, invSlot = invSlot }
end

local buySlotButton = StyledButton(bankWindow.frame, "Buy slot", 120, function()
  local owned, full = GetNumBankSlots()
  if full then return end
  local cost = GetBankSlotCost(owned)
  if GetMoney() < cost then
    print(PREFIX .. "the next bank slot costs " .. MoneyString(cost) .. ", you can't afford it yet.")
    return
  end
  StaticPopup_Show("BAMBOOBAGS_BUY_BANK_SLOT", MoneyString(cost))
end)
buySlotButton:SetPoint("LEFT", bankSlots[NUM_BANKBAGSLOTS].button, "RIGHT", 8, 0)

bankWindow.onRefresh = function()
  local owned, full = GetNumBankSlots()
  for i, s in ipairs(bankSlots) do
    local texture = GetInventoryItemTexture("player", s.invSlot)
    s.button.icon:SetTexture(texture or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
    if i > owned then
      s.button.icon:SetVertexColor(1, 0.25, 0.25)
    else
      s.button.icon:SetVertexColor(1, 1, 1)
    end
  end
  if full then
    buySlotButton:Hide()
  else
    buySlotButton.text:SetText("Buy slot  " .. MoneyString(GetBankSlotCost(owned)))
    buySlotButton:Show()
  end
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
events:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
events:RegisterEvent("HONOR_CURRENCY_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == "BambooBags" then
      BambooBagsDB = BambooBagsDB or {}
      if BambooBagsDB.sorted == nil then BambooBagsDB.sorted = true end
      BambooBagsDB.sections = BambooBagsDB.sections or {}
      BambooBagsDB.gearLevel = BambooBagsDB.gearLevel or DEFAULT_GEAR_LEVEL
      for _, w in ipairs(windows) do w:RestorePosition() end
    elseif arg1 == "Blizzard_TokenUI" then
      HookTokenUpdates()
    end
  elseif event == "PLAYER_ENTERING_WORLD" or event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    UpdatePixelSize()
  elseif event == "CURRENCY_DISPLAY_UPDATE" or event == "HONOR_CURRENCY_UPDATE" then
    if bagsWindow.frame:IsShown() then UpdateTokens() end
  elseif event == "BANKFRAME_OPENED" then
    bankWindow.frame:Show()
    bagsWindow.frame:Show()
  elseif event == "BANKFRAME_CLOSED" then
    bankWindow.frame:Hide()
  elseif event == "MERCHANT_SHOW" then
    sellButton:Show()
    UpdateSellButton()
    bagsWindow.extraFooter = SELL_ROW
    bagsWindow.dirty = true
    bagsWindow.frame:Show()
  elseif event == "MERCHANT_CLOSED" then
    sellButton:Hide()
    bagsWindow.extraFooter = nil
    bagsWindow.dirty = true
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
    print(PREFIX .. "gear at item level " .. arg .. "+ goes in Gear.")
    RefreshAll()
  elseif cmd == "alpha" and tonumber(arg) then
    BambooBagsDB.alpha = math.max(0.2, math.min(1, tonumber(arg)))
    print(PREFIX .. "background opacity " .. BambooBagsDB.alpha .. ".")
    RefreshAll()
  elseif cmd == "resetsections" then
    BambooBagsDB.sections = {}
    print(PREFIX .. "all Alt+click section choices cleared.")
    RefreshAll()
  else
    Toggle()
  end
end
