-- GearDump: /geardump opens a box with every wearable item you own, ready to Ctrl+A, Ctrl+C.
-- Open your bank first if you want bank items included.

local SLOTS = {
  "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot",
  "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot",
  "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}

-- Item types that aren't gear we care about
local SKIP = { [""] = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true,
  INVTYPE_TABARD = true, INVTYPE_BODY = true }

local bankOpen = false

local function Describe(link)
  local name, _, _, ilvl, _, _, _, _, equipLoc = GetItemInfo(link)
  if not name or SKIP[equipLoc] then return nil end
  local id, enchant = link:match("item:(%d+):(%-?%d+)")
  local line = string.format("%s | ilvl %d | id %s | %s", name, ilvl or 0, id, _G[equipLoc] or equipLoc)
  if enchant and enchant ~= "0" then
    line = line .. " | enchant " .. enchant
  end
  local gems = {}
  for i = 1, 4 do
    local gemName = GetItemGem(link, i)
    if gemName then table.insert(gems, gemName) end
  end
  if #gems > 0 then
    line = line .. " | gems: " .. table.concat(gems, ", ")
  end
  return line
end

local function DumpBags(out, first, last)
  for bag = first, last do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      local line = link and Describe(link)
      if line then table.insert(out, line) end
    end
  end
end

local function BuildText()
  local out = {}
  table.insert(out, string.format("%s - %s %s", UnitName("player"), UnitRace("player"), UnitClass("player")))
  table.insert(out, string.format("Hit %d | Expertise %d | AP %d",
    GetCombatRating(CR_HIT_MELEE), GetExpertise(), select(1, UnitAttackPower("player")) + select(2, UnitAttackPower("player"))))

  table.insert(out, "")
  table.insert(out, "== EQUIPPED ==")
  for _, slotName in ipairs(SLOTS) do
    local link = GetInventoryItemLink("player", GetInventorySlotInfo(slotName))
    local line = link and Describe(link)
    if line then table.insert(out, slotName .. ": " .. line) end
  end

  -- Sets saved in Blizzard's Equipment Manager (item names only; gems/enchants aren't stored)
  local numSets = GetNumEquipmentSets and GetNumEquipmentSets() or 0
  if numSets > 0 then
    table.insert(out, "")
    table.insert(out, "== EQUIPMENT MANAGER SETS ==")
    for i = 1, numSets do
      local setName = GetEquipmentSetInfo(i)
      local ids = setName and GetEquipmentSetItemIDs(setName)
      if ids then
        local names = {}
        for _, slotName in ipairs(SLOTS) do
          local id = ids[GetInventorySlotInfo(slotName)]
          if id and id > 0 then
            local itemName, _, _, ilvl = GetItemInfo(id)
            table.insert(names, string.format("%s (%s)", itemName or ("item " .. id), ilvl or "?"))
          end
        end
        table.insert(out, setName .. ": " .. table.concat(names, ", "))
      end
    end
  end

  table.insert(out, "")
  table.insert(out, "== BAGS ==")
  DumpBags(out, 0, NUM_BAG_SLOTS)

  table.insert(out, "")
  if bankOpen then
    table.insert(out, "== BANK ==")
    DumpBags(out, BANK_CONTAINER, BANK_CONTAINER)
    DumpBags(out, NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS)
  else
    table.insert(out, "(bank not included - open your bank and run /geardump again)")
  end

  return table.concat(out, "\n")
end

local function ShowText(text)
  if not GearDumpFrame then
    local f = CreateFrame("Frame", "GearDumpFrame", UIParent)
    f:SetWidth(640)
    f:SetHeight(420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -14)
    title:SetText("GearDump - Ctrl+A, Ctrl+C")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local sf = CreateFrame("ScrollFrame", "GearDumpScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 18, -34)
    sf:SetPoint("BOTTOMRIGHT", -36, 16)

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(580)
    eb:SetHeight(360)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)

    f.editBox = eb
    tinsert(UISpecialFrames, "GearDumpFrame") -- Escape closes it
  end
  GearDumpFrame.editBox:SetText(text)
  GearDumpFrame:Show()
  GearDumpFrame.editBox:SetFocus()
  GearDumpFrame.editBox:HighlightText()
end

local events = CreateFrame("Frame")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:SetScript("OnEvent", function(_, event)
  bankOpen = (event == "BANKFRAME_OPENED")
end)

SLASH_GEARDUMP1 = "/geardump"
SlashCmdList["GEARDUMP"] = function() ShowText(BuildText()) end
