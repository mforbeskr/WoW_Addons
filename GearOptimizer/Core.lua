-- GearOptimizer: picks the best gear you own (equipped, bags, bank) for a purpose.
-- v0.1 knows one purpose: Enhancement Shaman PvE. Everything runs only when you open the
-- window or press Optimize: no background work, no libraries.
--
-- How an item is scored: its stats (GetItemStats) and the stats of the gems in it, times the
-- profile's weights (attack-power equivalents), plus weapon DPS for the hand it goes in, plus a
-- fixed value for each empty socket (you'd gem it). Hit and expertise are worth less once the
-- set reaches their cap, so the optimizer searches for the set that is best with the caps
-- applied, not just the one with the most raw points.
-- Not counted: enchants, socket bonuses, set bonuses, and "Equip:/Use:" effects. Trinkets and
-- the totem are mostly effects, so those slots keep what you wear.

local _, ns = ...

ns.PREFIX = "|cff8fd16aGear Optimizer|r: "
function ns.Print(msg) print(ns.PREFIX .. msg) end

-- Profiles ------------------------------------------------------------------------------------
-- Weights are attack-power equivalents: approximate 3.3.5 Enhancement values. Tweak to taste.
ns.PROFILES = {
  SHAMAN_ENH = {
    name = "Enhancement Shaman - PvE",
    class = "SHAMAN",
    weights = {
      agi = 1.6, str = 1.0, int = 1.1, ap = 1.0, sp = 0.9,   -- int: Mental Dexterity gives AP
      hit = 1.6, exp = 1.5, haste = 1.3, crit = 1.2, arp = 0.5, mp5 = 0.2,
    },
    afterCap = { hit = 0.5, exp = 0 }, -- past the cap: hit still helps white hits a little
    mainHandDps = 7,                   -- per point of weapon DPS
    offHandDps = 5,
    socketValue = 34,                  -- an empty socket: you'd put about 20 agility in it
    hitCap = 446,                      -- rating from gear: 17% spell hit (shocks, Lightning Bolt)
    hitCapRace = { Draenei = -26 },    -- Heroic Presence gives 1%
    expertiseCap = 26,                 -- dodge cap in expertise points
    expertiseTalent = "Unleashed Rage", expertisePerRank = 3,
    keepSlots = { [13] = true, [14] = true, [18] = true }, -- trinkets, totem: effects can't be scored
  },
}

local EXPERTISE_PER_POINT = 8.19745 -- expertise rating per point at level 80

-- Stats ---------------------------------------------------------------------------------------
local KEY = {
  ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_INTELLECT_SHORT = "int",
  ITEM_MOD_SPIRIT_SHORT = "spi", ITEM_MOD_STAMINA_SHORT = "sta",
  ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "ap",
  ITEM_MOD_SPELL_POWER_SHORT = "sp",
  ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "hit",
  ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "crit",
  ITEM_MOD_HASTE_RATING_SHORT = "haste", ITEM_MOD_HASTE_MELEE_RATING_SHORT = "haste",
  ITEM_MOD_HASTE_SPELL_RATING_SHORT = "haste",
  ITEM_MOD_EXPERTISE_RATING_SHORT = "exp", ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "arp",
  ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_RESILIENCE_RATING_SHORT = "res",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
  EMPTY_SOCKET_RED = "socket", EMPTY_SOCKET_YELLOW = "socket", EMPTY_SOCKET_BLUE = "socket",
  EMPTY_SOCKET_PRISMATIC = "socket", EMPTY_SOCKET_META = "socket",
}

local statCache = {} -- per item link (gems are part of the link), for this session

-- Returns { agi = 20, hit = 15, dps = 120.5, empty = 1, ... } or nil if the item isn't loaded
local function Stats(link)
  local st = statCache[link]
  if st then return st end
  local raw = GetItemStats(link)
  if not raw then return nil end
  st = {}
  local sockets, gems = 0, 0
  for key, amount in pairs(raw) do
    local stat = KEY[key]
    if stat == "socket" then
      sockets = sockets + amount
    elseif stat then
      st[stat] = (st[stat] or 0) + amount
    end
  end
  for i = 1, 4 do
    local _, gemLink = GetItemGem(link, i)
    if gemLink then
      gems = gems + 1
      local g = GetItemStats(gemLink)
      if g then
        for key, amount in pairs(g) do
          local stat = KEY[key]
          if stat and stat ~= "socket" and stat ~= "dps" then st[stat] = (st[stat] or 0) + amount end
        end
      end
    end
  end
  st.empty = math.max(0, sockets - gems)
  statCache[link] = st
  return st
end

-- Can this character wear it? The tooltip shows red text for anything you can't use (armor or
-- weapon type, level, class), which works for every class without a lookup table.
local scanTip = CreateFrame("GameTooltip", "GearOptimizerScanTip", nil, "GameTooltipTemplate")
local wearCache = {}
local function CanWear(link)
  local id = tonumber(link:match("item:(%d+)"))
  if wearCache[id] ~= nil then return wearCache[id] end
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:SetHyperlink(link)
  local ok = true
  for i = 2, scanTip:NumLines() do
    for _, side in ipairs({ "TextLeft", "TextRight" }) do
      local line = _G["GearOptimizerScanTip" .. side .. i]
      if line and line:IsShown() and line:GetText() then
        local r, g, b = line:GetTextColor()
        if r > 0.9 and g < 0.2 and b < 0.2 then ok = false end
      end
    end
  end
  scanTip:Hide()
  wearCache[id] = ok
  return ok
end

-- Slots ---------------------------------------------------------------------------------------
-- Which inventory slots an item type can go in (one-handers fit both hands)
local SLOTS_FOR = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
  INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_HOLDABLE = { 17 }, INVTYPE_RELIC = { 18 }, INVTYPE_RANGED = { 18 },
  INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}
local SINGLE_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 15 }
ns.SLOT_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
ns.SLOT_NAMES = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [15] = "Back", [5] = "Chest", [9] = "Wrist",
  [10] = "Hands", [6] = "Waist", [7] = "Legs", [8] = "Feet", [11] = "Ring", [12] = "Ring",
  [13] = "Trinket", [14] = "Trinket", [16] = "Main hand", [17] = "Off hand", [18] = "Relic",
}

local function Fits(c, slot)
  for _, s in ipairs(SLOTS_FOR[c.equipLoc]) do
    if s == slot then return true end
  end
  return false
end

-- Bank memory ---------------------------------------------------------------------------------
-- The bank can only be read while it's open, so its gear links are remembered per character.
-- Bank events come in bursts; a change queues one scan a moment later.
local bankOpen = false
local function ScanBank()
  if not bankOpen then return end
  local links = {}
  local bags = { BANK_CONTAINER }
  for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do table.insert(bags, bag) end
  for _, bag in ipairs(bags) do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      local equipLoc = link and select(9, GetItemInfo(link))
      if equipLoc and SLOTS_FOR[equipLoc] then table.insert(links, link) end
    end
  end
  GearOptimizerCharDB.bank = links
end

local scanner = CreateFrame("Frame")
scanner:Hide()
scanner:SetScript("OnUpdate", function(self, elapsed)
  self.wait = self.wait - elapsed
  if self.wait > 0 then return end
  self:Hide()
  ScanBank()
end)
local function QueueScan()
  if not bankOpen or scanner:IsShown() then return end
  scanner.wait = 0.2
  scanner:Show()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
events:RegisterEvent("BAG_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == "GearOptimizer" then
      GearOptimizerCharDB = GearOptimizerCharDB or {}
      GearOptimizerCharDB.bank = GearOptimizerCharDB.bank or {}
    end
  elseif event == "BANKFRAME_OPENED" then
    bankOpen = true
    ScanBank()
  elseif event == "BANKFRAME_CLOSED" then
    if scanner:IsShown() then scanner:Hide() ScanBank() end
    bankOpen = false
  elseif event == "PLAYERBANKSLOTS_CHANGED" then
    QueueScan()
  elseif event == "BAG_UPDATE" and (arg1 == BANK_CONTAINER or (arg1 and arg1 > NUM_BAG_SLOTS)) then
    QueueScan()
  end
end)

-- Candidates ----------------------------------------------------------------------------------
-- Every wearable item you own, once per copy: { link, id, equipLoc, st, where, invSlot }
local function Candidates()
  local list, missing = {}, 0
  local function Add(link, where, invSlot)
    if not link then return end
    local name, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    if not name then missing = missing + 1 return end
    if not SLOTS_FOR[equipLoc] or not CanWear(link) then return end
    local st = Stats(link)
    if not st then missing = missing + 1 return end
    table.insert(list, { link = link, id = tonumber(link:match("item:(%d+)")), equipLoc = equipLoc,
      st = st, where = where, invSlot = invSlot })
  end
  for invSlot = 1, 18 do Add(GetInventoryItemLink("player", invSlot), "equipped", invSlot) end
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bag) do Add(GetContainerItemLink(bag, slot), "bags") end
  end
  for _, link in ipairs(GearOptimizerCharDB.bank) do Add(link, "bank") end
  return list, missing
end

-- Scoring -------------------------------------------------------------------------------------
-- Value of one item in one slot, with hit and expertise at the given weights
local function Value(c, slot, prof, w)
  local st, v = c.st, 0
  for stat, amount in pairs(st) do
    local k = w[stat]
    if k then v = v + amount * k end
  end
  v = v + st.empty * prof.socketValue
  if st.dps then v = v + st.dps * (slot == 17 and prof.offHandDps or prof.mainHandDps) end
  if c.where == "equipped" then v = v + 0.01 end -- on a tie, keep what you wear
  return v
end

-- A whole set's value with the caps applied: hit/expertise past the cap count at afterCap
function ns.SetValue(set, prof, caps)
  local w = {}
  for k, v in pairs(prof.weights) do w[k] = v end
  w.hit, w.exp = 0, 0
  local total, hit, exp = 0, 0, 0
  for slot, c in pairs(set) do
    total = total + Value(c, slot, prof, w)
    hit = hit + (c.st.hit or 0)
    exp = exp + (c.st.exp or 0)
  end
  local function Capped(amount, cap, full, after)
    return math.min(amount, cap) * full + math.max(0, amount - cap) * after
  end
  total = total + Capped(hit, caps.hit, prof.weights.hit, prof.afterCap.hit)
  total = total + Capped(exp, caps.exp, prof.weights.exp, prof.afterCap.exp)
  return total, hit, exp
end

-- The best set for weights w (hit/expertise at a fixed price)
local function Pick(cands, prof, w, current)
  local set = {}
  for _, slot in ipairs(SINGLE_SLOTS) do
    local best, bestV
    for _, c in ipairs(cands) do
      if Fits(c, slot) then
        local v = Value(c, slot, prof, w)
        if not bestV or v > bestV then best, bestV = c, v end
      end
    end
    set[slot] = best
  end

  -- Rings: the two best, never the same item twice (unique-equipped). Keep their current slots.
  local r1, r2, v1, v2
  for _, c in ipairs(cands) do
    if c.equipLoc == "INVTYPE_FINGER" then
      local v = Value(c, 11, prof, w)
      if not v1 or v > v1 then
        if r1 and r1.id ~= c.id then r2, v2 = r1, v1 end
        r1, v1 = c, v
      elseif c.id ~= r1.id and (not v2 or v > v2) then
        r2, v2 = c, v
      end
    end
  end
  if (r1 and r1.invSlot == 12) or (r2 and r2.invSlot == 11) then r1, r2 = r2, r1 end
  set[11], set[12] = r1, r2

  -- Slots whose items are mostly effects: keep what you wear
  for slot in pairs(prof.keepSlots) do set[slot] = current[slot] end

  -- Weapons: a two-hander alone, or the best main hand + off hand pair
  local best, bestV
  local dual = CanDualWield and CanDualWield()
  for _, mh in ipairs(cands) do
    if Fits(mh, 16) then
      local vm = Value(mh, 16, prof, w)
      if mh.equipLoc == "INVTYPE_2HWEAPON" then
        if not bestV or vm > bestV then best, bestV = { mh }, vm end
      else
        for _, oh in ipairs(cands) do
          if oh ~= mh and Fits(oh, 17) and (dual or oh.equipLoc == "INVTYPE_SHIELD" or oh.equipLoc == "INVTYPE_HOLDABLE") then
            local v = vm + Value(oh, 17, prof, w)
            if not bestV or v > bestV then best, bestV = { mh, oh }, v end
          end
        end
        if not bestV or vm > bestV then best, bestV = { mh }, vm end -- main hand alone
      end
    end
  end
  if best then set[16], set[17] = best[1], best[2] end
  return set
end

local function Caps(prof)
  local _, race = UnitRace("player")
  local hit = prof.hitCap + ((prof.hitCapRace or {})[race] or 0)
  local expPoints = prof.expertiseCap
  if prof.expertiseTalent then
    for tab = 1, GetNumTalentTabs() do
      for i = 1, GetNumTalents(tab) do
        local name, _, _, _, rank = GetTalentInfo(tab, i)
        if name == prof.expertiseTalent then expPoints = expPoints - rank * prof.expertisePerRank end
      end
    end
  end
  return { hit = hit, exp = math.max(0, math.floor(expPoints * EXPERTISE_PER_POINT + 0.5)) }
end

-- Which profile fits this character (v0.1: Enhancement Shaman only)
function ns.Profile()
  local _, class = UnitClass("player")
  if class ~= "SHAMAN" then return nil, "only Enhancement Shaman is set up so far." end
  local note
  local _, _, enh = GetTalentTabInfo(2)
  for tab = 1, GetNumTalentTabs() do
    local _, _, points = GetTalentTabInfo(tab)
    if tab ~= 2 and points > (enh or 0) then note = "your talents aren't Enhancement; scoring as Enhancement anyway." end
  end
  return ns.PROFILES.SHAMAN_ENH, note
end

-- The whole run: returns everything the window shows
function ns.Run()
  local prof, note = ns.Profile()
  if not prof then return nil, note end
  local cands, missing = Candidates()
  local caps = Caps(prof)

  local current = {}
  for _, c in ipairs(cands) do
    if c.where == "equipped" then current[c.invSlot] = c end
  end

  -- Search the hit/expertise price: full price if the set stays under the cap, lower if the
  -- best set goes over. Keep whichever set is best with the caps applied.
  local w = {}
  for k, v in pairs(prof.weights) do w[k] = v end
  local hitLo, hitHi = prof.afterCap.hit, prof.weights.hit
  local expLo, expHi = prof.afterCap.exp, prof.weights.exp
  local bestSet, bestValue
  for _ = 1, 10 do
    local set = Pick(cands, prof, w, current)
    local value, hit, exp = ns.SetValue(set, prof, caps)
    if not bestValue or value > bestValue then bestSet, bestValue = set, value end
    if hit > caps.hit then hitHi = w.hit else hitLo = w.hit end
    if exp > caps.exp then expHi = w.exp else expLo = w.exp end
    if hit <= caps.hit and exp <= caps.exp and w.hit == prof.weights.hit and w.exp == prof.weights.exp then break end
    w.hit, w.exp = (hitLo + hitHi) / 2, (expLo + expHi) / 2
  end

  local curValue, curHit, curExp = ns.SetValue(current, prof, caps)
  local _, bestHit, bestExp = ns.SetValue(bestSet, prof, caps)

  -- Your saved Equipment Manager sets, scored the same way (gems from your copies when found)
  local sets = {}
  if GetNumEquipmentSets then
    for i = 1, GetNumEquipmentSets() do
      local name = GetEquipmentSetInfo(i)
      local ids = name and GetEquipmentSetItemIDs(name)
      if ids then
        local set = {}
        for slot, id in pairs(ids) do
          if id and id > 0 and slot >= 1 and slot <= 18 then
            for _, c in ipairs(cands) do
              if c.id == id then set[slot] = c break end
            end
          end
        end
        table.insert(sets, { name = name, value = ns.SetValue(set, prof, caps) })
      end
    end
  end

  return {
    profile = prof, note = note, missing = missing, caps = caps,
    current = current, best = bestSet,
    curValue = curValue, bestValue = bestValue,
    curHit = curHit, curExp = curExp, bestHit = bestHit, bestExp = bestExp,
    sets = sets,
  }
end

-- Equips the suggested items that are in your bags. Items in the bank or moves between your
-- own slots (e.g. a weapon to the other hand) are left for you; returns how many were equipped.
function ns.EquipFromBags(result)
  if InCombatLockdown() or UnitAffectingCombat("player") then
    ns.Print("can't change gear in combat.")
    return 0
  end
  local n = 0
  for _, slot in ipairs(ns.SLOT_ORDER) do
    local c = result.best[slot]
    if c and c.where == "bags" and c ~= result.current[slot] then
      EquipItemByName(c.link, slot)
      n = n + 1
    end
  end
  return n
end
