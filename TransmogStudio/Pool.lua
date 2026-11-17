-- Pool: every wearable item you own (equipped, bags and bank), grouped by slot.

local _, ns = ...

-- invType -> list of slot indexes it can go in (one-handers fit both hands)
local slotsByInvType = {}
for i, slot in ipairs(ns.SLOTS) do
  for _, invType in ipairs(slot.invTypes) do
    slotsByInvType[invType] = slotsByInvType[invType] or {}
    table.insert(slotsByInvType[invType], i)
  end
end

local function ItemID(link)
  return link and tonumber(link:match("item:(%d+)"))
end

-- Can this character wear the item? The tooltip shows red text for anything you can't use
-- (wrong armor type, wrong weapon type), which works for every class without a lookup table.
local scanTip = CreateFrame("GameTooltip", "TransmogStudioScanTip", nil, "GameTooltipTemplate")
local canWearCache = {}

local function CanWear(link)
  local id = ItemID(link)
  if canWearCache[id] ~= nil then return canWearCache[id] end
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:SetHyperlink(link)
  local ok = true
  for i = 2, scanTip:NumLines() do
    for _, side in ipairs({ "TextLeft", "TextRight" }) do
      local line = _G["TransmogStudioScanTip" .. side .. i]
      if line and line:IsShown() and line:GetText() then
        local r, g, b = line:GetTextColor()
        if r > 0.9 and g < 0.2 and b < 0.2 then ok = false end
      end
    end
  end
  scanTip:Hide()
  canWearCache[id] = ok
  return ok
end

-- The bank can only be read while it's open, so remember its contents per character
local bankOpen = false
local function ScanBank()
  if not bankOpen then return end
  local ids = {}
  local bags = { BANK_CONTAINER }
  for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do table.insert(bags, bag) end
  for _, bag in ipairs(bags) do
    for slot = 1, GetContainerNumSlots(bag) do
      local id = ItemID(GetContainerItemLink(bag, slot))
      if id then table.insert(ids, id) end
    end
  end
  ns.charDB.bank = ids
end

ns.On("BANKFRAME_OPENED", function() bankOpen = true; ScanBank() end)
ns.On("BANKFRAME_CLOSED", function() bankOpen = false end)
ns.On("PLAYERBANKSLOTS_CHANGED", ScanBank)
ns.On("BAG_UPDATE", ScanBank)

-- Returns pool[slotIndex] = { itemID, ... } and the total number of distinct items
function ns.BuildPool()
  local pool, seen, count = {}, {}, 0
  for i in ipairs(ns.SLOTS) do pool[i] = {} end

  local function Add(id)
    if not id or seen[id] then return end
    local name, link, _, _, _, _, _, _, invType = GetItemInfo(id)
    if not name or not slotsByInvType[invType] or not CanWear(link) then return end
    seen[id] = true
    count = count + 1
    for _, i in ipairs(slotsByInvType[invType]) do table.insert(pool[i], id) end
  end

  for invSlot = 1, 19 do Add(ItemID(GetInventoryItemLink("player", invSlot))) end
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bag) do Add(ItemID(GetContainerItemLink(bag, slot))) end
  end
  for _, id in ipairs(ns.charDB.bank) do Add(id) end

  return pool, count
end
