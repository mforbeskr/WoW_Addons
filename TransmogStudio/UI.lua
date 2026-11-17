-- UI: the studio window. A model of your character in the middle, the outfit's slots on the left
-- (click to lock a slot), and Dislike / Skip / Like at the bottom. "Favorites" browses liked outfits.

local _, ns = ...

local NEON = ns.NEON
local BAMBOO = "Interface\\AddOns\\BambooBags\\textures\\"
local INSET = 20
local SLOT_SIZE = 24
local SLOT_GAP = 3

local pool, poolCount
local outfit
local locked = {}
local mode = "suggest" -- or "favorites"
local favIndex = 1

local f = CreateFrame("Frame", "TransmogStudioFrame", UIParent)
f:Hide()
f:SetWidth(380)
f:SetHeight(470)
f:SetPoint("CENTER")
f:SetFrameStrata("HIGH")
f:SetClampedToScreen(true)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
tinsert(UISpecialFrames, "TransmogStudioFrame") -- Escape closes it

-- Same bamboo look as BambooBags when it's installed, Blizzard's dialog look otherwise
if IsAddOnLoaded("BambooBags") then
  f:SetBackdrop({
    bgFile = BAMBOO .. "linen", edgeFile = BAMBOO .. "bamboo",
    tile = true, tileSize = 128, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
  })
else
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
end

local function NeonButton(label, width, onClick)
  local b = CreateFrame("Button", nil, f)
  b:SetWidth(width)
  b:SetHeight(20)
  local glow = b:CreateTexture(nil, "BACKGROUND")
  glow:SetAllPoints()
  glow:SetTexture(NEON[1], NEON[2], NEON[3], 0.15)
  local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("CENTER")
  text:SetText(label)
  text:SetTextColor(unpack(NEON))
  b:SetScript("OnEnter", function() glow:SetTexture(NEON[1], NEON[2], NEON[3], 0.45); text:SetTextColor(1, 1, 1) end)
  b:SetScript("OnLeave", function() glow:SetTexture(NEON[1], NEON[2], NEON[3], 0.15); text:SetTextColor(unpack(NEON)) end)
  b:SetScript("OnClick", onClick)
  b.text = text
  return b
end

-- Header ---------------------------------------------------------------------

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", INSET, -(INSET - 4))
title:SetText("Transmog Studio")
title:SetTextColor(unpack(NEON))

local info = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
info:SetPoint("LEFT", title, "RIGHT", 8, 0)

local closeButton = NeonButton("x", 20, function() f:Hide() end)
closeButton:SetPoint("TOPRIGHT", -INSET + 4, -(INSET - 6))

local ShowFavorite, NewSuggestion, UpdateMode -- defined below

local modeButton = NeonButton("Favorites", 70, function()
  mode = mode == "suggest" and "favorites" or "suggest"
  UpdateMode()
end)
modeButton:SetPoint("RIGHT", closeButton, "LEFT", -4, 0)

-- Model ----------------------------------------------------------------------

local model = CreateFrame("DressUpModel", nil, f)
model:SetPoint("TOPLEFT", INSET + SLOT_SIZE + 12, -(INSET + 16))
model:SetPoint("BOTTOMRIGHT", -INSET, INSET + 44)
local modelBg = model:CreateTexture(nil, "BACKGROUND")
modelBg:SetAllPoints()
modelBg:SetTexture(0, 0, 0, 0.3)

-- Drag the model sideways to turn it
model:EnableMouse(true)
model:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
model:SetScript("OnUpdate", function(self)
  if not self.dragX then return end
  local x = GetCursorPosition()
  self.facing = (self.facing or 0) + (x - self.dragX) * 0.02
  self.dragX = x
  self:SetFacing(self.facing)
end)

-- Slot column ----------------------------------------------------------------

local message = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
message:SetPoint("BOTTOM", model, "BOTTOM", 0, -16)

local slotButtons = {}
local Render -- defined below

local row = 0
for i, slot in ipairs(ns.SLOTS) do
  if not slot.skip then
    local b = CreateFrame("Button", nil, f)
    b:SetWidth(SLOT_SIZE)
    b:SetHeight(SLOT_SIZE)
    b:SetPoint("TOPLEFT", INSET, -(INSET + 16 + row * (SLOT_SIZE + SLOT_GAP)))
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.lock = b:CreateTexture(nil, "OVERLAY")
    b.lock:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.lock:SetBlendMode("ADD")
    b.lock:SetVertexColor(unpack(NEON))
    b.lock:SetWidth(SLOT_SIZE * 1.8)
    b.lock:SetHeight(SLOT_SIZE * 1.8)
    b.lock:SetPoint("CENTER")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    b:SetScript("OnClick", function()
      if mode ~= "suggest" then return end
      locked[i] = not locked[i] or nil
      Render()
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local id = outfit and outfit[i] or 0
      if id ~= 0 then
        GameTooltip:SetHyperlink("item:" .. id)
      else
        GameTooltip:SetText(slot.key .. ": empty")
      end
      if mode == "suggest" then
        GameTooltip:AddLine(locked[i] and "Locked. Click to unlock." or "Click to lock this slot.", NEON[1], NEON[2], NEON[3])
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    slotButtons[i] = b
    row = row + 1
  end
end

-- Bottom buttons: Dislike / Skip / Like, or Prev / Remove / Next for favorites --

local leftButton = NeonButton("", 96, function()
  if mode == "suggest" then
    ns.Rate(outfit, false, locked)
    NewSuggestion("Disliked. Showing you less of that.")
  else
    favIndex = favIndex - 1
    ShowFavorite()
  end
end)
leftButton:SetPoint("BOTTOMLEFT", INSET, INSET - 4)

local rightButton = NeonButton("", 96, function()
  if mode == "suggest" then
    ns.Rate(outfit, true, locked)
    local name, inDressMe = ns.SaveFavorite(outfit)
    NewSuggestion("Saved as " .. name .. (inDressMe and " (also in DressMe after /reload)" or ""))
  else
    favIndex = favIndex + 1
    ShowFavorite()
  end
end)
rightButton:SetPoint("BOTTOMRIGHT", -INSET, INSET - 4)

local middleButton = NeonButton("", 96, function()
  if mode == "suggest" then
    NewSuggestion("")
  else
    table.remove(ns.db.favorites, favIndex)
    ShowFavorite()
  end
end)
middleButton:SetPoint("BOTTOM", 0, INSET - 4)

-- Rendering ------------------------------------------------------------------

function Render()
  model:Undress()
  for i, slot in ipairs(ns.SLOTS) do
    local id = outfit and outfit[i] or 0
    if id ~= 0 then model:TryOn("item:" .. id) end
    local b = slotButtons[i]
    if b then
      b.icon:SetTexture(id ~= 0 and select(10, GetItemInfo(id)) or slot.icon)
      if locked[i] and mode == "suggest" then b.lock:Show() else b.lock:Hide() end
    end
  end
end

function NewSuggestion(text)
  outfit = ns.Generate(pool, outfit, locked)
  message:SetText(text or "")
  Render()
end

function ShowFavorite()
  local favorites = ns.db.favorites
  if #favorites == 0 then
    message:SetText("No favorites yet. Like an outfit first.")
    outfit = nil
    info:SetText("")
    Render()
    return
  end
  -- Wrap around at both ends
  if favIndex < 1 then favIndex = #favorites end
  if favIndex > #favorites then favIndex = 1 end
  local fav = favorites[favIndex]
  outfit = {}
  for i, id in ipairs(fav.items) do outfit[i] = id end
  info:SetText(fav.name)
  message:SetText(favIndex .. " / " .. #favorites)
  Render()
end

function UpdateMode()
  if mode == "suggest" then
    modeButton.text:SetText("Favorites")
    leftButton.text:SetText("Dislike")
    middleButton.text:SetText("Skip")
    rightButton.text:SetText("Like")
    info:SetText("from " .. poolCount .. " items you own")
    NewSuggestion("")
  else
    modeButton.text:SetText("Suggest")
    leftButton.text:SetText("< Prev")
    middleButton.text:SetText("Remove")
    rightButton.text:SetText("Next >")
    ShowFavorite()
  end
end

f:SetScript("OnShow", function()
  pool, poolCount = ns.BuildPool()
  model:SetUnit("player")
  model.facing = 0
  model:SetFacing(0)
  UpdateMode()
end)

function ns.Toggle()
  if f:IsShown() then f:Hide() else f:Show() end
end
