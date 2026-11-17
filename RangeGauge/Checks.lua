-- Checks: the game can't tell us an exact distance, only "is the unit in range of X? yes/no".
-- We ask many such questions with known ranges and narrow the answer down to a band, e.g. 28-35 yd.
--
-- The band is chosen so that as few answers as possible disagree with it, instead of trusting
-- every answer blindly: one wrong or flickering check can't throw the band around.

local _, ns = ...

-- Items usable on enemies, with known ranges (the lists LibRangeCheck-2.0 uses for 3.3.5).
-- You don't need to own them, but the game only answers for items it has seen, so they're
-- fetched at login (and again until they all arrive). Several per range = backups.
-- /rg verify shows in game whether each one really answers at its range.
local ITEM_CHECKS = {
  { yards = 5, item = 37727 },  -- Ruby Acorn
  { yards = 8, item = 34368 },  -- Attuned Crystal Cores
  { yards = 10, item = 32321 }, -- Sparrowhawk Net
  { yards = 15, item = 33069 }, -- Sturdy Rope
  { yards = 20, item = 10645 }, -- Gnomish Death Ray
  { yards = 25, item = 24268 }, -- Netherweave Net
  { yards = 25, item = 41509 }, -- Frostweave Net
  { yards = 30, item = 835 },   -- Large Rope Net
  { yards = 30, item = 34191 }, -- Handful of Snowflakes
  { yards = 35, item = 24269 }, -- Heavy Netherweave Net
  { yards = 35, item = 18904 }, -- Zorbin's Ultra-Shrinker
  { yards = 40, item = 28767 }, -- The Decapitator
  { yards = 45, item = 23836 }, -- Goblin Rocket Launcher (was wrongly listed as 50 before)
  { yards = 60, item = 32825 }, -- Soul Cannon
  { yards = 80, item = 35278 }, -- Reinforced Net
}

-- Built-in distance tests (3 = duel, 2 = trade, 4 = follow). Their real reach depends on the
-- player's race (model size); these are LibRangeCheck's measured values.
local INTERACT_YARDS = {
  default = { [3] = 8, [2] = 9, [4] = 28 },
  Tauren = { [3] = 6, [2] = 7, [4] = 25 },
  Scourge = { [3] = 7, [2] = 8, [4] = 27 },
}

-- Per-class setup. reachSpell decides the reach line; meleeSpell detects melee range.
-- Other classes can be added here later.
local CLASSES = {
  HUNTER = {
    reachSpell = 75,    -- Auto Shot
    baseReach = 35,
    meleeSpell = 2974,  -- Wing Clip
    spells = {
      { yards = 15, spell = 19503 }, -- Scatter Shot (Marksmanship talent; ignored if not learned)
    },
  },
}

local MELEE_YARDS = 5
local TOO_CLOSE_YARDS = 10 -- reach check says "no" but the band is this close: too close to shoot
local REACH_WEIGHT = 3     -- the reach check is exact, so it outvotes a single wrong item

local config = {} -- filled in by InitChecks at login
local sorted = {} -- every check, nearest range first: { yards, label, weight, test, r }
local reachCheck
local reachName, meleeName -- spell names, looked up once at login
ns.reachYards = MELEE_YARDS

-- IsSpellInRange / IsItemInRange return 1, 0 or nil (nil = can't tell for this unit)
local function ToBool(result)
  if result == 1 then return true elseif result == 0 then return false end
end

-- Hawk Eye adds 2 yards per rank to ranged attacks
local function HawkEyeRank()
  for tab = 1, GetNumTalentTabs() do
    for i = 1, GetNumTalents(tab) do
      local name, _, _, _, rank = GetTalentInfo(tab, i)
      if name == "Hawk Eye" then return rank end
    end
  end
  return 0
end

local function ByYards(a, b)
  if a.yards ~= b.yards then return a.yards < b.yards end
  return a.weight > b.weight
end

function ns.UpdateReach()
  if config and config.baseReach then
    ns.reachYards = config.baseReach + 2 * HawkEyeRank()
  else
    ns.reachYards = MELEE_YARDS
  end
  if reachCheck then
    reachCheck.yards = ns.reachYards
    table.sort(sorted, ByYards)
  end
end

-- Item data: ask the server for items the client hasn't seen, and keep asking until all arrive
local primeTip = CreateFrame("GameTooltip", "RangeGaugePrimeTip", nil, "GameTooltipTemplate")
local primer = CreateFrame("Frame")
primer:Hide()
primer.since, primer.tries = 0, 0

local function PrimeMissing()
  local missing = 0
  for _, c in ipairs(ITEM_CHECKS) do
    if not GetItemInfo(c.item) then
      missing = missing + 1
      primeTip:SetOwner(UIParent, "ANCHOR_NONE")
      primeTip:SetHyperlink("item:" .. c.item)
      primeTip:Hide()
    end
  end
  return missing
end

primer:SetScript("OnUpdate", function(self, elapsed)
  self.since = self.since + elapsed
  if self.since < 2 then return end
  self.since = 0
  self.tries = self.tries + 1
  if PrimeMissing() == 0 or self.tries >= 30 then self:Hide() end
end)

local function AddCheck(yards, label, weight, test)
  local c = { yards = yards, label = label, weight = weight, test = test }
  table.insert(sorted, c)
  return c
end

function ns.InitChecks()
  config = CLASSES[select(2, UnitClass("player"))] or {}
  wipe(sorted)
  reachCheck = nil
  reachName = config.reachSpell and GetSpellInfo(config.reachSpell)
  meleeName = config.meleeSpell and GetSpellInfo(config.meleeSpell)

  if reachName then
    reachCheck = AddCheck(ns.reachYards, reachName .. " (reach)", REACH_WEIGHT, function(unit)
      return ToBool(IsSpellInRange(reachName, unit))
    end)
  end

  local _, race = UnitRace("player")
  local interact = INTERACT_YARDS[race] or INTERACT_YARDS.default
  for index, yards in pairs(interact) do
    AddCheck(yards, "interact " .. index, 1, function(unit)
      return CheckInteractDistance(unit, index) and true or false
    end)
  end

  for _, s in ipairs(config.spells or {}) do
    local name = GetSpellInfo(s.spell)
    if name then
      AddCheck(s.yards, name, 1, function(unit)
        return ToBool(IsSpellInRange(name, unit))
      end)
    end
  end

  for _, it in ipairs(ITEM_CHECKS) do
    local id = it.item
    AddCheck(it.yards, "item " .. id, 1, function(unit)
      return ToBool(IsItemInRange(id, unit))
    end)
  end

  if PrimeMissing() > 0 then
    primer.since, primer.tries = 0, 0
    primer:Show()
  end

  ns.UpdateReach() -- also sorts
end

-- /rg verify statistics: how often each check disagreed with the chosen band
local verify = { on = false }

-- The cheap part, run every frame: has the melee or reach answer changed?
-- 3 = melee, 1 = in reach, 0 = out of reach, -1 = can't tell.
function ns.RawKey(unit)
  if meleeName and IsSpellInRange(meleeName, unit) == 1 then return 3 end
  local r = reachName and IsSpellInRange(reachName, unit)
  if r == 1 then return 1 elseif r == 0 then return 0 end
  return -1
end

-- Returns lo, hi, zone, key: the unit is farther than lo yards and within hi yards
-- (hi = nil means farther than anything we can test). zone is "melee", "reach", "out",
-- or "unknown" when we can't tell which side of the reach line. key is RawKey's value.
function ns.Measure(unit)
  if meleeName and IsSpellInRange(meleeName, unit) == 1 then
    return 0, MELEE_YARDS, "melee", 3
  end

  -- Ask everything. falsesAfter = weight of "no" answers (all of them start on the near side).
  local n = #sorted
  local falsesAfter = 0
  for i = 1, n do
    local c = sorted[i]
    local r = c.test(unit)
    c.r = r
    if r == false then falsesAfter = falsesAfter + c.weight end
  end

  -- Try every split point: checks 1..j should say "no" (unit is farther), j+1..n "yes".
  -- Keep the split(s) with the fewest disagreeing answers; ties widen the band.
  local truesBefore = 0
  local best, j0, j1
  for j = 0, n do
    local cost = truesBefore + falsesAfter
    if not best or cost < best then
      best, j0, j1 = cost, j, j
    elseif cost == best then
      j1 = j
    end
    if j < n then
      local c = sorted[j + 1]
      if c.r == true then
        truesBefore = truesBefore + c.weight
      elseif c.r == false then
        falsesAfter = falsesAfter - c.weight
      end
    end
  end

  local lo, hi = 0, nil
  for i = j0, 1, -1 do
    if sorted[i].r ~= nil then lo = sorted[i].yards break end
  end
  for i = j1 + 1, n do
    if sorted[i].r ~= nil then hi = sorted[i].yards break end
  end

  local inReach = reachCheck and reachCheck.r
  local R = ns.reachYards
  local zone, key
  if inReach == true then
    zone, key = "reach", 1
    if not hi or hi > R then hi = R end
    if lo >= hi then lo = math.max(0, hi - 2) end
  elseif inReach == false then
    key = 0
    if hi and hi <= TOO_CLOSE_YARDS then
      zone = "melee" -- inside Auto Shot's minimum range: too close to shoot
    else
      zone = "out"
      if lo < R then lo = R end
      if hi and hi <= lo then hi = lo + 5 end
    end
  else
    key = -1
    if hi and hi <= R then
      zone = "reach"
    elseif lo >= R then
      zone = "out"
    else
      zone = "unknown"
    end
  end

  if verify.on and unit == "target" then
    verify.readings = verify.readings + 1
    for i = 1, n do
      local c = sorted[i]
      local s = verify.stats[c]
      if not s then
        s = { answered = 0, unknown = 0, wrong = 0 }
        verify.stats[c] = s
      end
      if c.r == nil then
        s.unknown = s.unknown + 1
      else
        s.answered = s.answered + 1
        if (c.r == true and c.yards < lo) or (c.r == false and hi and c.yards > hi) then
          s.wrong = s.wrong + 1
        end
      end
    end
  end

  return lo, hi, zone, key
end

-- /rg verify: collect for `seconds` while you move around your target, then report which
-- checks never answer or disagree with the others (= their range in the list is wrong)
local verifier = CreateFrame("Frame")
verifier:Hide()
verifier:SetScript("OnUpdate", function(self)
  if GetTime() < verify.stop then return end
  self:Hide()
  verify.on = false
  ns.Print(string.format("verify done: %d readings.", verify.readings))
  for _, c in ipairs(sorted) do
    local s = verify.stats[c]
    if s then
      local status
      if s.answered == 0 then
        status = "|cffff5555never answers|r"
      elseif s.wrong / s.answered > 0.03 then
        status = string.format("|cffffaa33disagrees %d%% - range may be wrong|r", math.floor(100 * s.wrong / s.answered + 0.5))
      else
        status = string.format("|cff55ff55ok|r (%d%% off)", math.floor(100 * s.wrong / s.answered + 0.5))
      end
      ns.Print(string.format("%2d yd  %-28s %s", c.yards, c.label, status))
    end
  end
  ns.Print("target speed reported by the game: " .. (ns.speedWorks and "|cff55ff55yes|r" or "|cffff5555not seen yet|r"))
  ns.Print("map position: " .. ns.LocatorStatus())
end)

function ns.StartVerify(seconds)
  verify.on, verify.readings, verify.stats = true, 0, {}
  verify.stop = GetTime() + seconds
  verifier:Show()
  ns.Print(string.format("verifying for %d s: target an enemy (a training dummy is fine) and walk " ..
    "slowly from melee range out to 60+ yards and back.", seconds))
end

-- /rg debug: print what every check says about the current target
function ns.Debug(unit)
  if not UnitExists(unit) then ns.Print("target something first.") return end
  local lo, hi, zone = ns.Measure(unit)
  for _, c in ipairs(sorted) do
    ns.Print(string.format("%2d yd  %-28s %s", c.yards, c.label, c.r == nil and "unknown" or tostring(c.r)))
  end
  ns.Print(string.format("=> %s-%s yd, %s (reach %d yd)", lo, hi or "?", zone, ns.reachYards))
end
