-- Checks: the game can't tell us an exact distance, only "is the unit in range of X? yes/no".
-- We ask many such questions with known ranges and narrow the answer down to a band, e.g. 28-35 yd.

local _, ns = ...

-- Items usable on enemies, with known ranges (the same idea LibRangeCheck uses). You don't need
-- to own them, but the game only answers for items it has seen, so they're primed at login.
-- Ranges to double-check in game with /rg debug.
local ITEM_CHECKS = {
  { yards = 8, item = 34368 },  -- Attuned Crystal Cores
  { yards = 10, item = 32321 }, -- Sparrowhawk Net
  { yards = 15, item = 33069 }, -- Sturdy Rope
  { yards = 20, item = 10645 }, -- Gnomish Death Ray
  { yards = 25, item = 24268 }, -- Netherweave Net
  { yards = 30, item = 835 },   -- Large Rope Net
  { yards = 40, item = 28767 }, -- The Decapitator
  { yards = 45, item = 32698 }, -- Wrangling Rope
  { yards = 50, item = 23836 }, -- Goblin Rocket Launcher
}

-- Built-in distance tests: 3 = duel (~10 yd), 2 = trade (~11 yd), 4 = follow (~28 yd)
local INTERACT_CHECKS = {
  { yards = 10, index = 3 },
  { yards = 11, index = 2 },
  { yards = 28, index = 4 },
}

-- Per-class setup. reachSpell decides the reach line; meleeSpell detects melee range.
-- Other classes can be added here later.
local CLASSES = {
  HUNTER = {
    reachSpell = 75,    -- Auto Shot
    baseReach = 35,
    meleeSpell = 2974,  -- Wing Clip
    spells = {
      { yards = 15, spell = 19503 }, -- Scatter Shot (Marksmanship talent)
    },
  },
}

local MELEE_YARDS = 5

local config = {} -- filled in by InitChecks at login
local checks = {}
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

function ns.UpdateReach()
  if config and config.baseReach then
    ns.reachYards = config.baseReach + 2 * HawkEyeRank()
  else
    ns.reachYards = MELEE_YARDS
  end
end

-- Hidden tooltip used to make the client fetch item data it hasn't seen yet
local primeTip = CreateFrame("GameTooltip", "RangeGaugePrimeTip", nil, "GameTooltipTemplate")

function ns.InitChecks()
  config = CLASSES[select(2, UnitClass("player"))] or {}
  wipe(checks)

  for _, c in ipairs(INTERACT_CHECKS) do
    table.insert(checks, { yards = c.yards, label = "interact " .. c.index, test = function(unit)
      return CheckInteractDistance(unit, c.index) and true or false
    end })
  end

  for _, c in ipairs(config.spells or {}) do
    local name = GetSpellInfo(c.spell)
    table.insert(checks, { yards = c.yards, label = name, test = function(unit)
      return ToBool(IsSpellInRange(name, unit))
    end })
  end

  for _, c in ipairs(ITEM_CHECKS) do
    if not GetItemInfo(c.item) then
      primeTip:SetOwner(UIParent, "ANCHOR_NONE")
      primeTip:SetHyperlink("item:" .. c.item)
      primeTip:Hide()
    end
    table.insert(checks, { yards = c.yards, label = "item " .. c.item, test = function(unit)
      return ToBool(IsItemInRange(c.item, unit))
    end })
  end

  ns.UpdateReach()
end

-- Returns lo, hi, zone: the unit is farther than lo yards and within hi yards
-- (hi = nil means farther than anything we can test).
-- zone is "melee", "reach", "out", or "unknown" when we can't tell which side of the reach line.
function ns.Measure(unit)
  local meleeName = config.meleeSpell and GetSpellInfo(config.meleeSpell)
  if meleeName and IsSpellInRange(meleeName, unit) == 1 then
    return 0, MELEE_YARDS, "melee"
  end

  local lo, hi = 0, nil
  local function Record(yards, inRange)
    if inRange == true then
      if not hi or yards < hi then hi = yards end
    elseif inRange == false then
      if yards > lo then lo = yards end
    end
  end

  local inReach
  local reachName = config.reachSpell and GetSpellInfo(config.reachSpell)
  if reachName then
    inReach = ToBool(IsSpellInRange(reachName, unit))
    Record(ns.reachYards, inReach)
  end

  for _, c in ipairs(checks) do
    Record(c.yards, c.test(unit))
  end

  -- Item ranges aren't perfectly exact; never report a band that's upside down
  if hi and lo >= hi then lo = math.max(0, hi - 1) end

  -- Auto Shot can't be used on friendly targets, so then the reach check answers nothing.
  -- Only decide the side of the line when the band is clearly on one side of it.
  local zone
  if inReach == true then
    zone = "reach"
  elseif inReach == false then
    zone = "out"
  elseif hi and hi <= ns.reachYards then
    zone = "reach"
  elseif lo >= ns.reachYards then
    zone = "out"
  else
    zone = "unknown"
  end
  return lo, hi, zone
end

-- /rg debug: print what every check says about the current target
function ns.Debug(unit)
  if not UnitExists(unit) then ns.Print("target something first.") return end
  for _, c in ipairs(checks) do
    local r = c.test(unit)
    ns.Print(string.format("%2d yd  %-26s %s", c.yards, c.label, r == nil and "unknown" or tostring(r)))
  end
  local lo, hi, zone = ns.Measure(unit)
  ns.Print(string.format("=> %s-%s yd, %s (reach %d yd)", lo, hi or "?", zone, ns.reachYards))
end
