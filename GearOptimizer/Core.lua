-- GearOptimizer: finds the best gear you own (equipped, bags, bank) for one job, on request.
-- Shaman builds so far: On-hit (a Raid set) and Spellhance (a Raid set for bosses and an AOE set
-- for dungeons and trash packs). Nothing runs until you press "Find best ... build": no
-- background work, no libraries.
--
-- How an item is scored, in the job's own points:
--   * its stats (GetItemStats) and the stats of its gems, times the job's weights
--   * weapon DPS for the hand it goes in; an empty socket counts as gemmed
--   * Equip/Use effects read from the tooltip (trinkets, totems): "Use:" counts by duration over
--     cooldown, procs by a typical uptime, stacking buffs at a typical stack count
--   * effects it can't read get an estimate from item level, marked "~"
-- Set bonuses: for every tier set you own pieces of, it tries the 2- and 4-piece combinations
-- (and two 2-pieces) and keeps them only when they beat the best single pieces. Bonuses with a
-- stat are read; the rest get an estimated value, marked "~".
-- Hit and expertise are worth less once the set reaches their cap; the caps follow talents.
-- Not counted: enchants and socket bonuses (you'd move/redo those anyway).

local _, ns = ...

ns.PREFIX = "|cff8fd16aGear Optimizer|r: "
function ns.Print(msg) print(ns.PREFIX .. msg) end

-- Profiles ------------------------------------------------------------------------------------
-- One profile = one job. Weights are relative values per point of each stat, built from your
-- stat priorities; scores only compare within one profile. Tweak to taste.
--   hitType       which hit cap matters: "spell" 17% (shocks, spells), "melee" 8% (specials)
--   effectValue   estimate for a trinket effect it can't read, at item level 245
--   relicValue    the same for a totem
--   setBonus      estimate per set bonus it can't read, by pieces
ns.PROFILES = {
  -- On-hit: attack power > haste > crit > armor penetration
  ONHIT_RAID = {
    name = "Raid", purpose = "single target",
    weights = {
      ap = 1.0, str = 1.0, agi = 1.35, int = 0.9, -- agility: 1 AP plus crit; int: Mental Dexterity
      haste = 0.9, crit = 0.75, arp = 0.6, hit = 1.2, exp = 1.0, sp = 0.3, mp5 = 0.1,
    },
    afterCap = { hit = 0.45, exp = 0 },
    mainHandDps = 7, offHandDps = 5, socketValue = 27,
    hitType = "melee", expertiseCap = 26,
    effectValue = 220, relicValue = 90, setBonus = { [2] = 120, [4] = 180 },
  },
  -- Spellhance raid (bosses): haste > spell power = attack power > crit
  SPELL_RAID = {
    name = "Raid", purpose = "single target",
    weights = {
      haste = 1.3, sp = 1.0, ap = 1.0, crit = 0.8, agi = 1.2, str = 0.9, int = 1.0,
      hit = 1.4, exp = 0.3, arp = 0.1, mp5 = 0.3,
    },
    afterCap = { hit = 0.2, exp = 0 },
    mainHandDps = 4, offHandDps = 3, socketValue = 26,
    hitType = "spell", expertiseCap = 26,
    effectValue = 200, relicValue = 80, setBonus = { [2] = 100, [4] = 150 },
  },
  -- Spellhance AOE (dungeons, raid trash packs): spell power > crit > haste
  SPELL_AOE = {
    name = "AOE", purpose = "packs",
    weights = {
      sp = 1.0, crit = 0.85, haste = 0.75, ap = 0.45, agi = 0.7, str = 0.4, int = 0.8,
      hit = 1.1, exp = 0, arp = 0, mp5 = 0.3,
    },
    afterCap = { hit = 0.15, exp = 0 },
    mainHandDps = 2, offHandDps = 1.5, socketValue = 23,
    hitType = "spell", expertiseCap = 26,
    effectValue = 170, relicValue = 70, setBonus = { [2] = 60, [4] = 80 },
  },
}

-- A build is the job(s) one character wants: one "Find" button each
ns.BUILDS = {
  { key = "onhit", label = "On-hit", profiles = { "ONHIT_RAID" } },
  { key = "spell", label = "Spellhance", profiles = { "SPELL_RAID", "SPELL_AOE" } },
}

local EXPERTISE_PER_POINT = 8.19745 -- expertise rating per point at level 80
local MELEE_HIT_PER_PCT = 32.79     -- melee hit rating per 1% at level 80
local SPELL_HIT_PER_PCT = 26.23     -- spell hit rating per 1% at level 80
local PROC_COOLDOWN = 45            -- typical internal cooldown of a 3.3 trinket proc (seconds)
local STACK_SHARE = 0.8             -- stacking buffs: average share of full stacks over a fight
local USE_UNKNOWN_SHARE = 0.15      -- a "Use:" buff without a readable cooldown

-- Item stats ----------------------------------------------------------------------------------
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

-- Stat names as they appear in tooltip effect text (lowercase)
local STAT_WORDS = {
  { "attack power", "ap" }, { "spell power", "sp" }, { "haste rating", "haste" },
  { "critical strike rating", "crit" }, { "hit rating", "hit" }, { "armor penetration rating", "arp" },
  { "expertise rating", "exp" }, { "agility", "agi" }, { "strength", "str" }, { "intellect", "int" },
}

-- One effect line ("use: ...", "equip: ...") -> stat, average amount over a fight.
-- plain = true also accepts a permanent stat (for set bonuses; item stats come from the API).
local function ParseEffect(line, plain)
  if line:find(" of [%a' ]+ by ") then return nil end -- "spell power of Lightning Bolt": one spell only
  for _, sw in ipairs(STAT_WORDS) do
    local amount = line:match(sw[1] .. " by (%d+)") or line:match("(%d+) " .. sw[1])
    if line:find(sw[1] .. " by %d+%%") or line:find("%d+%% " .. sw[1]) then
      return nil -- a percentage ("20% more attack power"): can't be turned into points here
    end
    if amount then
      amount = tonumber(amount)
      local dur = tonumber(line:match("for (%d+) sec"))
      local stacks = tonumber(line:match("up to (%d+) times"))
      local cdMin, cdSec = tonumber(line:match("(%d+) min cooldown")), tonumber(line:match("(%d+) sec cooldown"))
      local cd = cdMin and cdMin * 60 or cdSec
      if line:find("^use:") then
        return sw[2], (dur and cd) and amount * math.min(1, dur / cd) or amount * USE_UNKNOWN_SHARE
      elseif stacks then
        return sw[2], amount * stacks * STACK_SHARE
      elseif dur then
        return sw[2], amount * dur / (dur + PROC_COOLDOWN)
      elseif plain then
        return sw[2], amount
      end
      return nil
    end
  end
end

-- A permanent stat line ("equip: improves hit rating by 20.") is already in GetItemStats
local function IsPlainStat(line)
  return line:find("^equip: [%a ]+ by %d+%.?$") and not line:find(" of ")
    and not line:find("chance") and not line:find(" when ") and not line:find("each time")
end

-- One tooltip read per item link (cached for the session): can you wear it, its effects, its set
local scanTip = CreateFrame("GameTooltip", "GearOptimizerScanTip", nil, "GameTooltipTemplate")
local tipCache = {}
local function ReadTooltip(link)
  local info = tipCache[link]
  if info then return info end
  info = { canWear = true, fx = {}, unknown = false, bonuses = {} }
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:SetHyperlink(link)
  for i = 2, scanTip:NumLines() do
    for _, side in ipairs({ "TextLeft", "TextRight" }) do
      local fs = _G["GearOptimizerScanTip" .. side .. i]
      local text = fs and fs:IsShown() and fs:GetText()
      if text then
        local r, g, b = fs:GetTextColor()
        if r > 0.9 and g < 0.2 and b < 0.2 then info.canWear = false end
        if side == "TextLeft" then
          local lower = text:lower()
          local setName = text:match("^(.-) %(%d+/%d+%)$")
          local pieces, bonusText = lower:match("^%((%d)%) set: (.+)$")
          if setName and not info.setName then
            info.setName = setName
          elseif pieces then
            local stat, amount = ParseEffect(bonusText, true)
            info.bonuses[tonumber(pieces)] = stat and { stat = stat, amount = amount } or { unknown = true }
          elseif lower:find("^use:") or lower:find("^equip:") or lower:find("^chance on hit:") then
            local stat, amount = ParseEffect(lower)
            if stat then
              info.fx[stat] = (info.fx[stat] or 0) + amount
            elseif not IsPlainStat(lower) then
              info.unknown = true
            end
          end
        end
      end
    end
  end
  scanTip:Hide()
  tipCache[link] = info
  return info
end

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
local SINGLE_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 15, 18 }
ns.SLOT_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
ns.SLOT_NAMES = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [15] = "Back", [5] = "Chest", [9] = "Wrist",
  [10] = "Hands", [6] = "Waist", [7] = "Legs", [8] = "Feet", [11] = "Ring", [12] = "Ring",
  [13] = "Trinket", [14] = "Trinket", [16] = "Main hand", [17] = "Off hand", [18] = "Totem",
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
local BANK_BAGS = { BANK_CONTAINER }
for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do table.insert(BANK_BAGS, bag) end

local function ScanBank()
  if not bankOpen then return end
  local links = {}
  for _, bag in ipairs(BANK_BAGS) do
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
-- Every wearable item you own, once per copy: { link, id, equipLoc, ilvl, st, tip, where, invSlot }
local function Candidates()
  local list, missing = {}, 0
  local function Add(link, where, invSlot)
    if not link then return end
    local name, _, _, ilvl, _, _, _, _, equipLoc = GetItemInfo(link)
    if not name then missing = missing + 1 return end
    if not SLOTS_FOR[equipLoc] then return end
    local tip = ReadTooltip(link)
    if not tip.canWear then return end
    local st = Stats(link)
    if not st then missing = missing + 1 return end
    table.insert(list, { link = link, id = tonumber(link:match("item:(%d+)")), equipLoc = equipLoc,
      ilvl = ilvl or 0, st = st, tip = tip, where = where, invSlot = invSlot })
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
  for stat, amount in pairs(c.tip.fx) do
    local k = prof.weights[stat]
    if k then v = v + amount * k end
  end
  if c.tip.unknown then
    if c.equipLoc == "INVTYPE_TRINKET" then
      v = v + prof.effectValue * c.ilvl / 245
    elseif c.equipLoc == "INVTYPE_RELIC" then
      v = v + prof.relicValue * c.ilvl / 245
    end
  end
  v = v + st.empty * prof.socketValue
  if st.dps then v = v + st.dps * (slot == 17 and prof.offHandDps or prof.mainHandDps) end
  if c.where == "equipped" then v = v + 0.01 end -- on a tie, keep what you wear
  return v
end

-- Did this item's value need an estimate? (shown as "~")
function ns.Estimated(c)
  return c.tip.unknown and (c.equipLoc == "INVTYPE_TRINKET" or c.equipLoc == "INVTYPE_RELIC")
end

-- Set bonuses active in a set: { { name, count, value, estimated, active = { 2, 4 } } ... }
local function Bonuses(set, prof)
  local count, sample = {}, {}
  for _, c in pairs(set) do
    local name = c.tip.setName
    if name then
      count[name] = (count[name] or 0) + 1
      sample[name] = sample[name] or c
    end
  end
  local list, total = {}, 0
  for name, n in pairs(count) do
    local entry = { name = name, count = n, value = 0, estimated = false, active = {} }
    for pieces, bonus in pairs(sample[name].tip.bonuses) do
      if n >= pieces then
        table.insert(entry.active, pieces)
        if bonus.unknown then
          entry.value = entry.value + (prof.setBonus[pieces] or prof.setBonus[4] or 0)
          entry.estimated = true
        else
          entry.value = entry.value + bonus.amount * (prof.weights[bonus.stat] or 0)
        end
      end
    end
    if #entry.active > 0 then
      table.sort(entry.active)
      total = total + entry.value
      table.insert(list, entry)
    end
  end
  return total, list
end

-- A whole set's value: items, set bonuses, and hit/expertise with the caps applied
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
  total = total + Bonuses(set, prof)
  return total, hit, exp
end

-- Best two of a paired slot (rings, trinkets), never the same item twice (unique-equipped).
-- Keeps them in the slots they're already in.
local function PickPair(cands, equipLoc, slotA, slotB, prof, w)
  local a, b, va, vb
  for _, c in ipairs(cands) do
    if c.equipLoc == equipLoc then
      local v = Value(c, slotA, prof, w)
      if not va or v > va then
        if a and a.id ~= c.id then b, vb = a, va end
        a, va = c, v
      elseif c.id ~= a.id and (not vb or v > vb) then
        b, vb = c, v
      end
    end
  end
  if (a and a.invSlot == slotB) or (b and b.invSlot == slotA) then a, b = b, a end
  return a, b
end

-- The best set for weights w (hit/expertise at a fixed price), set bonuses not yet considered
local function Pick(cands, prof, w)
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
  set[11], set[12] = PickPair(cands, "INVTYPE_FINGER", 11, 12, prof, w)
  set[13], set[14] = PickPair(cands, "INVTYPE_TRINKET", 13, 14, prof, w)

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

-- Tries trading single-slot picks for tier pieces to reach 2- and 4-piece bonuses (one set, or
-- two sets at 2 pieces), and keeps the trade only if the whole set comes out ahead.
local function WithSetBonuses(base, cands, prof, caps)
  local w = prof.weights
  -- For every set: the best piece of it per slot
  local sets = {}
  for _, c in ipairs(cands) do
    local name = c.tip.setName
    if name and next(c.tip.bonuses) then
      for _, slot in ipairs(SLOTS_FOR[c.equipLoc]) do
        sets[name] = sets[name] or {}
        local cur = sets[name][slot]
        if not cur or Value(c, slot, prof, w) > Value(cur, slot, prof, w) then sets[name][slot] = c end
      end
    end
  end

  local function Copy(set)
    local t = {}
    for k, v in pairs(set) do t[k] = v end
    return t
  end
  -- Slots of a set, cheapest trade first
  local function Ordered(pieces, used)
    local list = {}
    for slot, c in pairs(pieces) do
      if not used or not used[slot] then
        local loss = (base[slot] and Value(base[slot], slot, prof, w) or 0) - Value(c, slot, prof, w)
        table.insert(list, { slot = slot, c = c, loss = loss })
      end
    end
    table.sort(list, function(a, b) return a.loss < b.loss end)
    return list
  end

  local best, bestValue = base, ns.SetValue(base, prof, caps)
  local function Try(set)
    local v = ns.SetValue(set, prof, caps)
    if v > bestValue then best, bestValue = set, v end
  end

  local names = {}
  for name, pieces in pairs(sets) do
    local order = Ordered(pieces)
    if #order >= 2 then
      table.insert(names, name)
      for _, k in ipairs({ 2, 4, 5 }) do
        if #order >= k then
          local trial = Copy(base)
          for i = 1, k do trial[order[i].slot] = order[i].c end
          Try(trial)
        end
      end
    end
  end
  -- Two different sets at 2 pieces each
  for i = 1, #names do
    for j = i + 1, #names do
      local trial, used = Copy(base), {}
      local a = Ordered(sets[names[i]])
      for k = 1, 2 do trial[a[k].slot] = a[k].c; used[a[k].slot] = true end
      local b = Ordered(sets[names[j]], used)
      if #b >= 2 then
        for k = 1, 2 do trial[b[k].slot] = b[k].c end
        Try(trial)
      end
    end
  end
  return best, bestValue
end

-- Talents and race --------------------------------------------------------------------------
local function TalentRank(talent)
  for tab = 1, GetNumTalentTabs() do
    for i = 1, GetNumTalents(tab) do
      local name, _, _, _, rank = GetTalentInfo(tab, i)
      if name == talent then return rank end
    end
  end
  return 0
end

-- Gear rating needed to reach the caps, after talents and race
local function Caps(prof)
  local _, race = UnitRace("player")
  local draenei = race == "Draenei" and 1 or 0 -- Heroic Presence: +1% hit
  local hit
  if prof.hitType == "spell" then
    hit = (17 - draenei - TalentRank("Elemental Precision")) * SPELL_HIT_PER_PCT
  else
    hit = (8 - draenei - 2 * TalentRank("Dual Wield Specialization")) * MELEE_HIT_PER_PCT
  end
  local expPoints = prof.expertiseCap - 3 * TalentRank("Unleashed Rage")
  return {
    hit = math.max(0, math.floor(hit + 0.5)),
    exp = math.max(0, math.floor(expPoints * EXPERTISE_PER_POINT + 0.5)),
  }
end

-- The build for this character: the one you picked last time, or a guess from talents
-- (several points in Elemental = Spellhance, otherwise On-hit)
function ns.Build()
  local _, class = UnitClass("player")
  if class ~= "SHAMAN" then return nil, "only Shaman builds are set up so far." end
  local key = GearOptimizerCharDB.build
  if not key then
    local _, _, elemental = GetTalentTabInfo(1)
    key = (elemental or 0) >= 10 and "spell" or "onhit"
  end
  for _, b in ipairs(ns.BUILDS) do
    if b.key == key then return b end
  end
  return ns.BUILDS[1]
end

function ns.SetBuild(key)
  GearOptimizerCharDB.build = key
end

-- Finding ---------------------------------------------------------------------------------------
-- What you wear right now, from your gear only (cheap; shown when the window opens)
function ns.Current()
  local cands = Candidates()
  local current = {}
  for _, c in ipairs(cands) do
    if c.where == "equipped" then current[c.invSlot] = c end
  end
  return current
end

-- The best set for one job. Searches the hit/expertise price (full while under the caps, lower
-- when over), then tries set bonuses, and keeps whatever is best with everything applied.
function ns.Find(profileKey)
  local prof = ns.PROFILES[profileKey]
  local cands, missing = Candidates()
  local caps = Caps(prof)
  local current = {}
  for _, c in ipairs(cands) do
    if c.where == "equipped" then current[c.invSlot] = c end
  end

  local w = {}
  for k, v in pairs(prof.weights) do w[k] = v end
  local hitLo, hitHi = prof.afterCap.hit, prof.weights.hit
  local expLo, expHi = prof.afterCap.exp, prof.weights.exp
  local bestSet, bestValue
  for _ = 1, 10 do
    local set = Pick(cands, prof, w)
    local value, hit, exp = ns.SetValue(set, prof, caps)
    if not bestValue or value > bestValue then bestSet, bestValue = set, value end
    if hit > caps.hit then hitHi = w.hit else hitLo = w.hit end
    if exp > caps.exp then expHi = w.exp else expLo = w.exp end
    if hit <= caps.hit and exp <= caps.exp and w.hit == prof.weights.hit and w.exp == prof.weights.exp then break end
    w.hit, w.exp = (hitLo + hitHi) / 2, (expLo + expHi) / 2
  end
  bestSet, bestValue = WithSetBonuses(bestSet, cands, prof, caps)

  local curValue, curHit, curExp = ns.SetValue(current, prof, caps)
  local _, bestHit, bestExp = ns.SetValue(bestSet, prof, caps)
  local _, bonusList = Bonuses(bestSet, prof)

  -- Your saved Equipment Manager sets, scored the same way (gems from your copies)
  local saved = {}
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
        table.insert(saved, { name = name, value = ns.SetValue(set, prof, caps) })
      end
    end
  end

  return {
    profile = prof, caps = caps, missing = missing, current = current, best = bestSet,
    curValue = curValue, bestValue = bestValue, curHit = curHit, curExp = curExp,
    bestHit = bestHit, bestExp = bestExp, bonuses = bonusList, saved = saved,
  }
end

-- Equipping -------------------------------------------------------------------------------------
local function Same(a, b) return a == b or (a and b and a.link == b.link) end

-- Is everything in this result already on you? (Then it can be saved as an Equipment Manager set.)
function ns.Wearing(r)
  local now = ns.Current()
  for _, slot in ipairs(ns.SLOT_ORDER) do
    if r.best[slot] and not Same(r.best[slot], now[slot]) then return false end
  end
  return true
end

-- Second step of EquipAll, a moment later (after bank items reached your bags)
local equipper = CreateFrame("Frame")
equipper:Hide()
equipper:SetScript("OnUpdate", function(self, elapsed)
  self.wait = self.wait - elapsed
  if self.wait > 0 then return end
  self:Hide()
  local now = ns.Current()
  for _, slot in ipairs(ns.SLOT_ORDER) do
    local c = self.result.best[slot]
    if c and not Same(c, now[slot]) and c.where ~= "equipped" then EquipItemByName(c.link, slot) end
  end
  ns.Print("done. Check the window, then Save the set for one-click swaps.")
end)

-- One click: moves your own items between slots (rings, weapon hands), takes needed items out
-- of the bank if it's open, then puts everything on. Returns false if it can't right now.
function ns.EquipAll(r)
  if InCombatLockdown() or UnitAffectingCombat("player") then
    ns.Print("can't change gear in combat.")
    return false
  end
  ClearCursor()
  -- 1) Your own items that move to another slot. A swap moves both items, so skip its partner.
  local done = {}
  for _, slot in ipairs(ns.SLOT_ORDER) do
    local c = r.best[slot]
    if c and c.where == "equipped" and c.invSlot ~= slot and not done[slot] then
      PickupInventoryItem(c.invSlot)
      EquipCursorItem(slot)
      if CursorHasItem() then ClearCursor() end
      if Same(r.best[c.invSlot], r.current[slot]) then done[c.invSlot] = true end
      done[slot] = true
    end
  end
  -- 2) Items in the bank: into your bags (only while the bank is open)
  local fromBank, leftInBank = 0, 0
  for _, slot in ipairs(ns.SLOT_ORDER) do
    local c = r.best[slot]
    if c and c.where == "bank" then
      local found
      if bankOpen then
        for _, bag in ipairs(BANK_BAGS) do
          for s = 1, GetContainerNumSlots(bag) do
            if not found and GetContainerItemLink(bag, s) == c.link then
              UseContainerItem(bag, s) -- with the bank open, this moves it to your bags
              found = true
            end
          end
        end
      end
      if found then fromBank = fromBank + 1 else leftInBank = leftInBank + 1 end
    end
  end
  if leftInBank > 0 then
    ns.Print(leftInBank .. " item(s) are in the bank: open it and press Equip again to include them.")
  end
  -- 3) A moment later (bank moves take a server round trip), put everything on
  equipper.result = r
  equipper.wait = fromBank > 0 and 0.8 or 0.1
  equipper:Show()
  return true
end

-- Saves what you wear as an Equipment Manager set, e.g. "Opt Raid", replacing an older one
function ns.SaveSet(name)
  if InCombatLockdown() then
    ns.Print("can't save sets in combat.")
    return
  end
  local ok = pcall(SaveEquipmentSet, name, 1)
  if ok then
    ns.Print("saved your gear as the Equipment Manager set \"" .. name .. "\".")
  else
    ns.Print("couldn't save the set; save it yourself in the Equipment Manager as \"" .. name .. "\".")
  end
end
