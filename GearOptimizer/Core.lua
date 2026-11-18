-- GearOptimizer: finds the gear you own (equipped, bags, bank) with the highest estimated DPS for
-- a scenario: Raid (one boss) or AOE (a pack). Calculated only when you press "Find": no
-- background work, no libraries.
--
-- Every candidate set is run through the DPS model (Model.lua), with:
--   * your talents and base stats, and typical ICC raid buffs
--   * your glyphs, read from their text (Stormstrike, Windfury, Lava Lash, Feral Spirit...)
--   * item stats and gems; an empty socket counts as gemmed with your best gem stat
--   * trinket and totem effects read from the tooltip; procs are valued from the hits, crits
--     and casts per second of that exact set, then the set is recalculated with the average buff
--   * set bonuses read from their text: damage increases, procs, flat stats
-- Effects or bonuses it can't read get a small estimate, marked "~".
-- The search starts from what you wear and keeps swapping in whatever raises the DPS, slot by
-- slot (rings, trinkets and weapons as pairs), then tries trading pieces for set bonuses.
-- Not counted: enchants and socket bonuses.

local _, ns = ...
local Model = ns.Model

ns.PREFIX = "|cff8fd16aGear Optimizer|r: "
function ns.Print(msg) print(ns.PREFIX .. msg) end

ns.SCENARIOS = { "RAID", "AOE" } -- the Find buttons, in order

local PROC_COOLDOWN = 45            -- typical internal cooldown of a 3.3 trinket proc (seconds)
local TRINKET_PROC_CHANCE = 10      -- % per event when a trinket's tooltip doesn't say
local STACK_SHARE = 0.8             -- stacking buffs: average share of full stacks over a fight
local UNKNOWN_TRINKET = 0.03        -- unreadable trinket effect: share of DPS at item level 264
local UNKNOWN_RELIC = 0.012         -- the same for a totem
local UNKNOWN_BONUS = { [2] = 0.02, [4] = 0.03 } -- unreadable set bonus: share of DPS
local GEM_OPTIONS = { { agi = 20 }, { sp = 23 }, { haste = 20 }, { crit = 20 }, { ap = 40 }, { hit = 20 } }
local MIN_GAIN = 0.002              -- a change must add at least 0.2% DPS, or it isn't suggested

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
local GEAR_KEYS = { "agi", "str", "int", "ap", "sp", "hit", "crit", "haste", "exp", "arp" }
local CRIT_METAS = { ["Relentless Earthsiege Diamond"] = true, ["Chaotic Skyflare Diamond"] = true,
  ["Chaotic Skyfire Diamond"] = true }

local statCache = {} -- per item link (gems are part of the link), for this session

-- Returns { agi = 20, hit = 15, dps = 120.5, empty = 1, critMeta = true, ... } or nil if not loaded
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
    local gemName, gemLink = GetItemGem(link, i)
    if gemLink then
      gems = gems + 1
      if CRIT_METAS[gemName] then st.critMeta = true end
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

-- Reading effect text ---------------------------------------------------------------------------
local STAT_WORDS = {
  { "attack power", "ap" }, { "spell power", "sp" }, { "haste rating", "haste" },
  { "critical strike rating", "crit" }, { "hit rating", "hit" }, { "armor penetration rating", "arp" },
  { "expertise rating", "exp" }, { "agility", "agi" }, { "strength", "str" }, { "intellect", "int" },
}

-- An effect that gives a stat for a while ("use:", procs, stacking buffs) -> a proc description
-- { stat, amount or pct, dur, cd, stacks, chance, use, trigger }, or nil
local function ParseProc(line)
  if line:find(" of [%a' ]+ by ") then return nil end -- "spell power of Lightning Bolt": one spell only
  for _, sw in ipairs(STAT_WORDS) do
    local word = sw[1]
    local pct = line:match("(%d+)%% " .. word) or line:match(word .. " by (%d+)%%")
    local amount = line:match(word .. " by (%d+)") or line:match("(%d+) " .. word)
    if pct or amount then
      local p = { stat = sw[2] }
      if pct then
        if sw[2] ~= "ap" then return nil end -- only "% attack power" can be turned into points
        p.pct = tonumber(pct) / 100
      else
        p.amount = tonumber(amount)
      end
      p.dur = tonumber(line:match("for (%d+) sec"))
      p.stacks = tonumber(line:match("up to (%d+) times"))
      local cdMin, cdSec = tonumber(line:match("(%d+) min cooldown")), tonumber(line:match("(%d+) sec cooldown"))
      p.cd = cdMin and cdMin * 60 or cdSec
      p.chance = tonumber(line:match("(%d+)%% chance"))
      p.use = line:find("^use:") ~= nil
      if line:find("maelstrom") then p.trigger = "maelstrom"
      elseif line:find("critical") then p.trigger = line:find("spell") and not line:find("melee") and "spellCrits" or "crits"
      elseif line:find("spell") and not line:find("melee") then p.trigger = "spellHits"
      elseif line:find("melee") then p.trigger = "meleeHits"
      else p.trigger = "hits" end
      if not p.use and not p.stacks and not p.dur then return nil end -- a permanent stat
      return p
    end
  end
end

-- A permanent stat line ("equip: improves hit rating by 20.") is already in GetItemStats
local function IsPlainStat(line)
  return line:find("^equip: [%a ]+ by %d+%.?$") and not line:find(" of ")
    and not line:find("chance") and not line:find(" when ") and not line:find("each time")
end

-- Ability names in glyph and set bonus text -> the model's breakdown entries
local ABILITIES = {
  { "stormstrike", "Stormstrike" }, { "lava lash", "Lava Lash" }, { "lightning bolt", "Lightning Bolt" },
  { "chain lightning", "Chain Lightning" }, { "earth shock", "Shocks" }, { "flame shock", "Shocks" },
  { "frost shock", "Shocks" }, { "shock", "Shocks" }, { "lightning shield", "Lightning Shield" },
  { "windfury", "Windfury" }, { "fire nova", "Fire Nova" }, { "magma totem", "Magma Totem" },
  { "searing totem", "Searing Totem" }, { "feral spirit", "Feral Spirit" }, { "flametongue", "Flametongue" },
}

-- Glyph or set bonus text -> model modifiers. Returns true if it understood something.
local function ParseMods(text, mods)
  local n = text:match("nature damage bonus from your stormstrike.- by an additional (%d+)%%")
  if n then mods.ssBonus = (mods.ssBonus or 0) + n / 100 return true end
  n = text:match("windfury weapon to trigger by (%d+)%%")
  if n then mods.wfChance = (mods.wfChance or 0) + n / 100 return true end
  if text:find("spirit wolves") or (text:find("feral spirit") and text:find("attack power")) then
    n = text:match("(%d+)%%")
    if n then mods.wolfAP = (mods.wolfAP or 0) + n / 100 return true end
  end
  if text:find("chain lightning") and text:find("additional target") then
    mods.clTargets = (mods.clTargets or 0) + (tonumber(text:match("(%d+) additional")) or 1)
    return true
  end
  n = text:match("cooldown of your fire nova.- by (%d+) sec")
  if n then mods.fireNovaCD = (mods.fireNovaCD or 0) + n return true end
  if text:find("flametongue") and text:find("spell critical") then
    n = text:match("by (%d+)%%")
    if n then mods.spellCrit = (mods.spellCrit or 0) + n return true end
  end
  if text:find("damage") then
    n = text:match("by an additional (%d+)%%") or text:match(" by (%d+)%%")
    if n then
      local found, seen = false, {}
      for _, a in ipairs(ABILITIES) do
        if text:find(a[1]) and not seen[a[2]] then
          seen[a[2]] = true
          mods.dmg[a[2]] = (mods.dmg[a[2]] or 1) * (1 + n / 100)
          found = true
        end
      end
      return found
    end
  end
  return false
end

-- One tooltip read per item link (cached): can you wear it, weapon speed, effects, set
local scanTip = CreateFrame("GameTooltip", "GearOptimizerScanTip", nil, "GameTooltipTemplate")
local tipCache = {}
local function ReadTooltip(link)
  local info = tipCache[link]
  if info then return info end
  info = { canWear = true, procs = {}, unknown = false, bonuses = {} }
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:SetHyperlink(link)
  for i = 2, scanTip:NumLines() do
    for _, side in ipairs({ "TextLeft", "TextRight" }) do
      local fs = _G["GearOptimizerScanTip" .. side .. i]
      local text = fs and fs:IsShown() and fs:GetText()
      if text then
        local r, g, b = fs:GetTextColor()
        if r > 0.9 and g < 0.2 and b < 0.2 then info.canWear = false end
        local speed = text:match("^Speed (%d+%.%d+)")
        if speed then info.speed = tonumber(speed) end
        if side == "TextLeft" then
          local lower = text:lower()
          local setName = text:match("^(.-) %(%d+/%d+%)$")
          local pieces, bonusText = lower:match("^%((%d)%) set: (.+)$")
          if setName and not info.setName then
            info.setName = setName
          elseif pieces then
            local bonus = { mods = { dmg = {} } }
            bonus.proc = ParseProc(bonusText)
            if not bonus.proc then
              local stat, amount
              for _, sw in ipairs(STAT_WORDS) do
                amount = bonusText:match(sw[1] .. " by (%d+)[^%%%d]") or bonusText:match("(%d+) " .. sw[1])
                if amount then stat = sw[2] break end
              end
              if stat then
                bonus.stat, bonus.amount = stat, tonumber(amount)
              elseif not ParseMods(bonusText, bonus.mods) then
                bonus.unknown = true
              end
            end
            info.bonuses[tonumber(pieces)] = bonus
          elseif lower:find("^use:") or lower:find("^equip:") or lower:find("^chance on hit:") then
            local p = ParseProc(lower)
            if p then
              table.insert(info.procs, p)
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

-- Glyphs: read their text once per Find -> model modifiers and the names it understood
local function ReadGlyphs()
  local mods, names = { dmg = {} }, {}
  if not GetNumGlyphSockets then return mods, names end
  for i = 1, GetNumGlyphSockets() do
    local enabled, _, spellID = GetGlyphSocketInfo(i)
    if enabled and spellID then
      scanTip:SetOwner(UIParent, "ANCHOR_NONE")
      scanTip:SetHyperlink("spell:" .. spellID)
      local parts = {}
      for l = 2, scanTip:NumLines() do
        local fs = _G["GearOptimizerScanTipTextLeft" .. l]
        if fs and fs:GetText() then table.insert(parts, fs:GetText():lower()) end
      end
      scanTip:Hide()
      if ParseMods(table.concat(parts, " "), mods) then
        local name = GetSpellInfo(spellID) or "?"
        table.insert(names, (name:gsub("^Glyph of ", "")))
      end
    end
  end
  return mods, names
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
local PAIRS = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }
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

-- Did this item's value need an estimate? (shown as "~")
function ns.Estimated(c)
  return c.tip.unknown and (c.equipLoc == "INVTYPE_TRINKET" or c.equipLoc == "INVTYPE_RELIC")
end

-- Evaluating a set ------------------------------------------------------------------------------
local function MergeMods(a, b)
  local m = { dmg = {} }
  for _, src in ipairs({ a, b }) do
    for k, v in pairs(src) do
      if k == "dmg" then
        for ability, mult in pairs(v) do m.dmg[ability] = (m.dmg[ability] or 1) * mult end
      else
        m[k] = (m[k] or 0) + v
      end
    end
  end
  return m
end

-- Average stat a proc gives over a fight, from the set's event rates
local function ProcAverage(p, ev, trinket)
  local amount = p.amount or p.pct
  if p.use then return amount * math.min(1, (p.dur or 15) / (p.cd or 120)) end
  if p.stacks then return amount * p.stacks * STACK_SHARE end
  local rate
  if p.trigger == "crits" then rate = ev.meleeCrits + ev.spellCrits
  elseif p.trigger == "spellCrits" then rate = ev.spellCrits
  elseif p.trigger == "maelstrom" then rate = ev.maelstrom
  elseif p.trigger == "spellHits" then rate = ev.spellHits
  elseif p.trigger == "meleeHits" then rate = ev.meleeHits
  else rate = ev.meleeHits + ev.spellHits end
  local per = rate * (p.chance or (trinket and TRINKET_PROC_CHANCE or 100)) / 100
  if per <= 0 then return 0 end
  local icd = p.cd or (trinket and PROC_COOLDOWN or 0)
  local uptime = icd > 0 and p.dur / (icd + 1 / per) or 1 - math.exp(-per * p.dur)
  return amount * math.min(1, uptime)
end

-- The set's DPS with everything applied. detail = true also returns breakdown, stats, bonuses.
local function Evaluate(set, ctx, detail)
  local g, procs, est = {}, {}, 0
  local setCount, setSample = {}, {}
  for slot, c in pairs(set) do
    local st = c.st
    for _, k in ipairs(GEAR_KEYS) do
      if st[k] then g[k] = (g[k] or 0) + st[k] end
    end
    if st.empty > 0 then
      for k, v in pairs(ctx.gem) do g[k] = (g[k] or 0) + v * st.empty end
    end
    if st.critMeta then g.critMeta = true end
    if slot == 16 and st.dps then g.mh = { dps = st.dps, speed = c.tip.speed } end
    if slot == 17 and st.dps then g.oh = { dps = st.dps, speed = c.tip.speed } end
    for _, p in ipairs(c.tip.procs) do
      table.insert(procs, { p = p, trinket = c.equipLoc == "INVTYPE_TRINKET" })
    end
    if c.tip.unknown then
      if c.equipLoc == "INVTYPE_TRINKET" then est = est + UNKNOWN_TRINKET * c.ilvl / 264
      elseif c.equipLoc == "INVTYPE_RELIC" then est = est + UNKNOWN_RELIC * c.ilvl / 264 end
    end
    local name = c.tip.setName
    if name then
      setCount[name] = (setCount[name] or 0) + 1
      setSample[name] = c
    end
  end
  if g.mh and set[16] and set[16].equipLoc == "INVTYPE_2HWEAPON" then g.oh = nil end

  -- Set bonuses that are active
  local bonusMods, bonusList = { dmg = {} }, {}
  for name, n in pairs(setCount) do
    local entry = { name = name, count = n, active = {}, estimated = false }
    for pieces, bonus in pairs(setSample[name].tip.bonuses) do
      if n >= pieces then
        table.insert(entry.active, pieces)
        if bonus.proc then
          table.insert(procs, { p = bonus.proc })
        elseif bonus.stat then
          g[bonus.stat] = (g[bonus.stat] or 0) + bonus.amount
        elseif bonus.unknown then
          est = est + (UNKNOWN_BONUS[pieces] or UNKNOWN_BONUS[4])
          entry.estimated = true
        else
          bonusMods = MergeMods(bonusMods, bonus.mods)
        end
      end
    end
    if #entry.active > 0 then
      table.sort(entry.active)
      table.insert(bonusList, entry)
    end
  end
  local mods = MergeMods(ctx.glyphMods, bonusMods)

  local dps, breakdown, ev, stats = Model.DPS(g, ctx.sc, ctx.T, ctx.base, mods)
  if #procs > 0 then
    -- Value procs from this set's attack rate, then recalculate with their average buff
    for _, pr in ipairs(procs) do
      local avg = ProcAverage(pr.p, ev, pr.trinket)
      if pr.p.pct then
        g.apPct = (g.apPct or 0) + avg
      else
        g[pr.p.stat] = (g[pr.p.stat] or 0) + avg
      end
    end
    dps, breakdown, ev, stats = Model.DPS(g, ctx.sc, ctx.T, ctx.base, mods)
  end
  dps = dps * (1 + est)
  if detail then return dps, breakdown, stats, bonusList, est > 0 end
  return dps
end

-- Searching -------------------------------------------------------------------------------------
local function Copy(set)
  local t = {}
  for k, v in pairs(set) do t[k] = v end
  return t
end

local function Used(set, c, except)
  for slot, other in pairs(set) do
    if slot ~= except and other == c then return true end
  end
  return false
end

-- Starting from `set`, keeps swapping in whatever raises the DPS until nothing does
local function Climb(set, cands, ctx)
  local best = Evaluate(set, ctx)
  local dual = CanDualWield and CanDualWield()
  local function Try(trial)
    local v = Evaluate(trial, ctx)
    if v > best + 0.01 then set, best = trial, v return true end
    return false
  end
  for _ = 1, 6 do
    local improved = false
    for _, slot in ipairs(SINGLE_SLOTS) do
      for _, c in ipairs(cands) do
        if c ~= set[slot] and Fits(c, slot) then
          local trial = Copy(set)
          trial[slot] = c
          if Try(trial) then improved = true end
        end
      end
    end
    -- Rings and trinkets: never the same item in both slots (unique-equipped)
    for slot, other in pairs(PAIRS) do
      for _, c in ipairs(cands) do
        local o = set[other]
        if c ~= set[slot] and Fits(c, slot) and c ~= o and not (o and o.id == c.id) then
          local trial = Copy(set)
          trial[slot] = c
          if Try(trial) then improved = true end
        end
      end
    end
    -- Weapons as a pair: every main hand with every off hand, and two-handers alone
    for _, mh in ipairs(cands) do
      if Fits(mh, 16) then
        if mh.equipLoc == "INVTYPE_2HWEAPON" then
          if mh ~= set[16] or set[17] then
            local trial = Copy(set)
            trial[16], trial[17] = mh, nil
            if Try(trial) then improved = true end
          end
        else
          for _, oh in ipairs(cands) do
            if oh ~= mh and Fits(oh, 17) and (dual or not oh.st.dps)
              and not (mh == set[16] and oh == set[17]) then
              local trial = Copy(set)
              trial[16], trial[17] = mh, oh
              if Try(trial) then improved = true end
            end
          end
        end
      end
    end
    if not improved then break end
  end
  return set, best
end

-- Tries trading pieces for set bonuses (2, 4, 5 pieces of one set, or 2 + 2 of two sets): the
-- climb alone can't find them, because one piece of a set is worth nothing extra
local function SetTrades(set, cands, ctx)
  local sets = {}
  for _, c in ipairs(cands) do
    local name = c.tip.setName
    if name and next(c.tip.bonuses) then
      for _, slot in ipairs(SLOTS_FOR[c.equipLoc]) do
        sets[name] = sets[name] or {}
        sets[name][slot] = sets[name][slot] or {}
        table.insert(sets[name][slot], c)
      end
    end
  end
  local base = Evaluate(set, ctx)
  -- The best piece of a set per slot, cheapest trade first
  local function Ordered(slots, used)
    local list = {}
    for slot, pieces in pairs(slots) do
      if not (used and used[slot]) then
        local bestC, bestV
        for _, c in ipairs(pieces) do
          local trial = Copy(set)
          trial[slot] = c
          local v = Evaluate(trial, ctx)
          if not bestV or v > bestV then bestC, bestV = c, v end
        end
        table.insert(list, { slot = slot, c = bestC, loss = base - bestV })
      end
    end
    table.sort(list, function(a, b) return a.loss < b.loss end)
    return list
  end
  local best, bestV = set, base
  local function Try(trial)
    local v = Evaluate(trial, ctx)
    if v > bestV then best, bestV = trial, v end
  end
  local names = {}
  for name, slots in pairs(sets) do
    local order = Ordered(slots)
    if #order >= 2 then
      table.insert(names, name)
      for _, k in ipairs({ 2, 4, 5 }) do
        if #order >= k then
          local trial = Copy(set)
          for i = 1, k do trial[order[i].slot] = order[i].c end
          Try(trial)
        end
      end
    end
  end
  for i = 1, #names do
    for j = i + 1, #names do
      local a = Ordered(sets[names[i]])
      local trial, used = Copy(set), {}
      for k = 1, 2 do trial[a[k].slot] = a[k].c; used[a[k].slot] = true end
      local b = Ordered(sets[names[j]], used)
      if #b >= 2 then
        for k = 1, 2 do trial[b[k].slot] = b[k].c end
        Try(trial)
      end
    end
  end
  return best
end

-- Slots that change together: a ring or trinket pair, both weapons, or a single slot
local GROUPS = { { 1 }, { 2 }, { 3 }, { 5 }, { 6 }, { 7 }, { 8 }, { 9 }, { 10 }, { 15 }, { 18 },
  { 11, 12 }, { 13, 14 }, { 16, 17 } }

local function GroupChanged(best, current, group)
  for _, slot in ipairs(group) do
    local a, b = best[slot], current[slot]
    if not (a == b or (a and b and a.link == b.link)) then return true end
  end
  return false
end

-- Drops changes that add less than MIN_GAIN (not worth a swap, a bank trip or new gems), then
-- returns how much each remaining change adds: gains[slot] = share of DPS
local function Prune(best, current, ctx)
  local bestV = Evaluate(best, ctx)
  local again = true
  while again do
    again = false
    for _, group in ipairs(GROUPS) do
      if GroupChanged(best, current, group) then
        local trial = Copy(best)
        for _, slot in ipairs(group) do trial[slot] = current[slot] end
        local v = Evaluate(trial, ctx)
        if bestV - v < MIN_GAIN * bestV then
          best, bestV, again = trial, v, true
        end
      end
    end
  end
  local gains = {}
  for _, group in ipairs(GROUPS) do
    if GroupChanged(best, current, group) then
      local trial = Copy(best)
      for _, slot in ipairs(group) do trial[slot] = current[slot] end
      local gain = (bestV - Evaluate(trial, ctx)) / bestV
      for _, slot in ipairs(group) do gains[slot] = gain end
    end
  end
  return best, gains
end

-- Context for one Find: scenario, talents, base stats, glyphs, best gem for empty sockets
local function Context(scenarioKey, current)
  local ctx = {
    sc = Model.SCENARIOS[scenarioKey], T = Model.ReadTalents(), base = Model.ReadBase(),
  }
  ctx.glyphMods, ctx.glyphs = ReadGlyphs()
  local bestGem, bestV
  for _, gem in ipairs(GEM_OPTIONS) do
    ctx.gem = gem
    local v = Evaluate({ [16] = current[16], [17] = current[17], x = { st = { empty = 3 }, tip = { procs = {}, bonuses = {} } } }, ctx)
    if not bestV or v > bestV then bestGem, bestV = gem, v end
  end
  ctx.gem = bestGem
  return ctx
end

local function CurrentFrom(cands)
  local current = {}
  for _, c in ipairs(cands) do
    if c.where == "equipped" then current[c.invSlot] = c end
  end
  return current
end

-- What you wear right now (cheap; shown when the window opens)
function ns.Current()
  return CurrentFrom((Candidates()))
end

local function ClassCheck()
  local _, class = UnitClass("player")
  if class ~= "SHAMAN" then return "only Enhancement Shaman is modelled so far." end
end

-- The best set for a scenario ("RAID" or "AOE")
function ns.Find(scenarioKey)
  local err = ClassCheck()
  if err then return nil, err end
  local cands, missing = Candidates()
  local current = CurrentFrom(cands)
  local ctx = Context(scenarioKey, current)

  local best = Climb(Copy(current), cands, ctx)
  best = SetTrades(best, cands, ctx)
  best = Climb(best, cands, ctx)
  local gains
  best, gains = Prune(best, current, ctx)

  local curDPS, _, curStats = Evaluate(current, ctx, true)
  local bestDPS, breakdown, stats, bonuses, estimated = Evaluate(best, ctx, true)

  -- Your saved Equipment Manager sets, same model (gems from your copies)
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
        table.insert(saved, { name = name, dps = Evaluate(set, ctx) })
      end
    end
  end

  return {
    scenario = ctx.sc, key = scenarioKey, missing = missing, current = current, best = best, gains = gains,
    curDPS = curDPS, bestDPS = bestDPS, curStats = curStats, stats = stats, breakdown = breakdown,
    bonuses = bonuses, estimated = estimated, glyphs = ctx.glyphs, saved = saved,
  }
end

-- /gopt model: the model's view of what you wear, to compare with Skada
function ns.ModelReport(scenarioKey)
  local err = ClassCheck()
  if err then ns.Print(err) return end
  local cands = Candidates()
  local current = CurrentFrom(cands)
  local ctx = Context(scenarioKey or "RAID", current)
  local dps, breakdown, s, bonuses = Evaluate(current, ctx, true)
  ns.Print(string.format("%s, what you wear: about %d DPS (raid-buffed estimate).", ctx.sc.name, dps))
  local list = {}
  for name, v in pairs(breakdown) do table.insert(list, { name = name, v = v }) end
  table.sort(list, function(a, b) return a.v > b.v end)
  for _, e in ipairs(list) do
    ns.Print(string.format("  %-18s %5.1f%%  %d", e.name, 100 * e.v / dps, e.v))
  end
  ns.Print(string.format("  AP %d  SP %d  melee crit %.1f%%  spell crit %.1f%%  hit %.1f%% / spell %.1f%%  expertise %d",
    s.ap, s.sp, 100 * s.meleeCrit, 100 * s.spellCrit, s.hitPct, s.spellHitPct, s.expertise))
  ns.Print("  glyphs counted: " .. (#ctx.glyphs > 0 and table.concat(ctx.glyphs, ", ") or "none"))
  for _, b in ipairs(bonuses) do
    ns.Print(string.format("  set: %s %d pc (%s)%s", b.name, b.count, table.concat(b.active, "+"),
      b.estimated and " ~" or ""))
  end
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
