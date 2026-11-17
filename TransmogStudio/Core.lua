-- Transmog Studio: suggests outfits from gear you own and learns from your likes and dislikes.
-- Core: shared namespace, slot definitions, saved data and a small event dispatcher.
-- Every file gets the same private table `ns` from the client, so files can share code
-- without polluting the global namespace.

local addonName, ns = ...

-- Slots in DressMe's saved-look order, so liked outfits can also be saved into DressMe.
-- `optional` = chance the slot is left empty in a suggestion; `skip` slots are never filled.
local PAPERDOLL = "Interface\\PaperDoll\\UI-PaperDoll-Slot-"
ns.SLOTS = {
  { key = "Head", icon = PAPERDOLL .. "Head", optional = 0.25, invTypes = { "INVTYPE_HEAD" } },
  { key = "Shoulder", icon = PAPERDOLL .. "Shoulder", invTypes = { "INVTYPE_SHOULDER" } },
  { key = "Back", icon = PAPERDOLL .. "Chest", optional = 0.2, invTypes = { "INVTYPE_CLOAK" } },
  { key = "Chest", icon = PAPERDOLL .. "Chest", invTypes = { "INVTYPE_CHEST", "INVTYPE_ROBE" } },
  { key = "Shirt", icon = PAPERDOLL .. "Shirt", optional = 0.5, invTypes = { "INVTYPE_BODY" } },
  { key = "Tabard", icon = PAPERDOLL .. "Tabard", optional = 0.7, invTypes = { "INVTYPE_TABARD" } },
  { key = "Wrist", icon = PAPERDOLL .. "Wrists", invTypes = { "INVTYPE_WRIST" } },
  { key = "Hands", icon = PAPERDOLL .. "Hands", invTypes = { "INVTYPE_HAND" } },
  { key = "Waist", icon = PAPERDOLL .. "Waist", invTypes = { "INVTYPE_WAIST" } },
  { key = "Legs", icon = PAPERDOLL .. "Legs", invTypes = { "INVTYPE_LEGS" } },
  { key = "Feet", icon = PAPERDOLL .. "Feet", invTypes = { "INVTYPE_FEET" } },
  { key = "Main Hand", icon = PAPERDOLL .. "MainHand",
    invTypes = { "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_2HWEAPON" } },
  { key = "Off-hand", icon = PAPERDOLL .. "SecondaryHand",
    invTypes = { "INVTYPE_WEAPON", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" } },
  -- Relics and most ranged items don't show on the character, so they're left out of suggestions
  { key = "Ranged", icon = PAPERDOLL .. "Ranged", skip = true,
    invTypes = { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN" } },
}
ns.MAIN_HAND, ns.OFF_HAND = 12, 13

ns.NEON = { 0.78, 0.35, 1 }

function ns.Print(msg)
  print("|cffc77dffTransmog Studio|r: " .. msg)
end

-- Event dispatcher: ns.On("EVENT", fn) lets every file listen without its own frame
local listeners = {}
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(listeners[event]) do fn(...) end
end)

function ns.On(event, fn)
  if not listeners[event] then
    listeners[event] = {}
    events:RegisterEvent(event)
  end
  table.insert(listeners[event], fn)
end

ns.On("ADDON_LOADED", function(name)
  if name ~= addonName then return end
  -- Taste and favorites are account-wide; bank contents are per character
  TransmogStudioDB = TransmogStudioDB or {}
  TransmogStudioDB.weights = TransmogStudioDB.weights or {}
  TransmogStudioDB.favorites = TransmogStudioDB.favorites or {}
  TransmogStudioCharDB = TransmogStudioCharDB or {}
  TransmogStudioCharDB.bank = TransmogStudioCharDB.bank or {}
  ns.db = TransmogStudioDB
  ns.charDB = TransmogStudioCharDB
end)

SLASH_TRANSMOGSTUDIO1 = "/ts"
SlashCmdList["TRANSMOGSTUDIO"] = function(msg)
  if msg == "forget" then
    ns.db.weights = {}
    ns.Print("forgot everything it learned about your taste.")
  else
    ns.Toggle()
  end
end
