-- Checks: the game can't tell us an exact distance, only "is the unit in range of X? yes/no".
-- We ask many such questions with known ranges and narrow the answer down to a band, e.g. 28-35 yd.
--
-- The band is chosen so that as few answers as possible disagree with it, instead of trusting
-- every answer blindly: one wrong or flickering check can't throw the band around.
--
-- There are two sets of checks ("profiles"): one for enemies (your attack range) and one for
-- allies (your heal range), because spells and items only answer for the side they work on.

local _, ns = ...

-- Items with known ranges (the lists LibRangeCheck-2.0 uses for 3.3.5). You don't need to own
-- them, but the game only answers for items it has seen, so they're fetched at login (and again
-- until they all arrive). Several per range = backups.
-- /rg verify shows in game whether each one really answers at its range.
local HOSTILE_ITEMS = {
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

-- Items usable on allies
local FRIENDLY_ITEMS = {
  { yards = 5, item = 37727 },  -- Ruby Acorn
  { yards = 8, item = 34368 },  -- Attuned Crystal Cores
  { yards = 10, item = 32321 }, -- Sparrowhawk Net
  { yards = 15, item = 34721 }, -- Frostweave Bandage
  { yards = 15, item = 21990 }, -- Netherweave Bandage
  { yards = 20, item = 21519 }, -- Mistletoe
  { yards = 25, item = 31463 }, -- Zezzak's Shard
  { yards = 30, item = 1180 },  -- Scroll of Stamina
  { yards = 30, item = 34191 }, -- Handful of Snowflakes
  { yards = 35, item = 18904 }, -- Zorbin's Ultra-Shrinker
  { yards = 40, item = 34471 }, -- Vial of the Sunwell
  { yards = 45, item = 32698 }, -- Wrangling Rope
  { yards = 60, item = 32825 }, -- Soul Cannon
  { yards = 80, item = 35278 }, -- Reinforced Net
}

-- Built-in distance tests (3 = duel, 2 = trade, 4 = follow). Their real reach depends on the
-- player's race (model size); these are LibRangeCheck's measured values. Work on both sides.
local INTERACT_YARDS = {
  default = { [3] = 8, [2] = 9, [4] = 28 },
  Tauren = { [3] = 6, [2] = 7, [4] = 25 },
  Scourge = { [3] = 7, [2] = 8, [4] = 27 },
}

-- Per-class setup, one block per side. reach = the spell that decides the reach line (exact);
-- melee = a melee-range spell; spells = extra checkpoints. A talent adds perRank yards per rank.
-- style picks the colors and labels (Colors.lua). Other classes can be added here later.
local CLASSES = {
  HUNTER = {
    hostile = {
      reach = { spell = 75, yards = 35, talent = "Hawk Eye", perRank = 2 },  -- Auto Shot
      melee = 2974,     -- Wing Clip
      deadZone = true,  -- Auto Shot has a minimum range
      spells = {
        { spell = 19503, yards = 15 }, -- Scatter Shot (Marksmanship talent; ignored if not learned)
      },
    },
  },
  PRIEST = {
    hostile = {
      reach = { spell = 589, yards = 30, talent = "Shadow Reach", perRank = 3 }, -- Shadow Word: Pain
      spells = {
        { spell = 585, yards = 30, talent = "Holy Reach", perRank = 3 },    -- Smite
        { spell = 15407, yards = 20, talent = "Shadow Reach", perRank = 2 }, -- Mind Flay (talent)
      },
    },
    friendly = {
      style = "heal",
      reach = { spell = 2061, yards = 40 }, -- Flash Heal (same 40 yd as Renew, Shield, Greater Heal)
      spells = {
        { spell = 1243, yards = 30 }, -- Power Word: Fortitude
        { spell = 527, yards = 30 },  -- Dispel Magic
      },
    },
  },
}

local MELEE_YARDS = 5
local NOT_VISIBLE_YARDS = 100 -- the client stops showing units about this far away
local TOO_CLOSE_YARDS = 10 -- reach check says "no" but the band is this close: too close to shoot
local REACH_WEIGHT = 3     -- the reach check is exact, so it outvotes a single wrong item

local hostile, friendly    -- the two profiles, built by InitChecks at login
ns.reachYards = MELEE_YARDS -- reach against enemies (kept for older callers)

-- IsSpellInRange / IsItemInRange return 1, 0 or nil (nil = can't tell for this unit)
local function ToBool(result)
  if result == 1 then return true elseif result == 0 then return false end
end

local function TalentRank(talent)
  if not talent then return 0 end
  for tab = 1, GetNumTalentTabs() do
    for i = 1, GetNumTalents(tab) do
      local name, _, _, _, rank = GetTalentInfo(tab, i)
      if name == talent then return rank end
    end
  end
  return 0
end

local function ByYards(a, b)
  if a.yards ~= b.yards then return a.yards < b.yards end
  return a.weight > b.weight
end

-- Talent-dependent ranges (Hawk Eye, Shadow Reach, Holy Reach)
local function UpdateProfileReach(p)
  for _, c in ipairs(p.sorted) do
    if c.talent then c.yards = c.baseYards + c.perRank * TalentRank(c.talent) end
  end
  p.reach = p.reachCheck and p.reachCheck.yards or MELEE_YARDS
  table.sort(p.sorted, ByYards)
end

function ns.UpdateReach()
  if hostile then UpdateProfileReach(hostile) end
  if friendly then UpdateProfileReach(friendly) end
  ns.reachYards = hostile and hostile.reach or MELEE_YARDS
end

-- Item data: ask the server for items the client hasn't seen, and keep asking until all arrive
local primeTip = CreateFrame("GameTooltip", "RangeGaugePrimeTip", nil, "GameTooltipTemplate")
local primer = CreateFrame("Frame")
primer:Hide()
primer.since, primer.tries = 0, 0

local function PrimeList(list)
  local missing = 0
  for _, c in ipairs(list) do
    if not GetItemInfo(c.item) then
      missing = missing + 1
      primeTip:SetOwner(UIParent, "ANCHOR_NONE")
      primeTip:SetHyperlink("item:" .. c.item)
      primeTip:Hide()
    end
  end
  return missing
end

local function PrimeMissing()
  return PrimeList(HOSTILE_ITEMS) + (friendly and PrimeList(FRIENDLY_ITEMS) or 0)
end

primer:SetScript("OnUpdate", function(self, elapsed)
  self.since = self.since + elapsed
  if self.since < 2 then return end
  self.since = 0
  self.tries = self.tries + 1
  if PrimeMissing() == 0 or self.tries >= 30 then self:Hide() end
end)

local function AddCheck(p, yards, label, weight, test)
  local c = { yards = yards, baseYards = yards, label = label, weight = weight, test = test }
  table.insert(p.sorted, c)
  return c
end

local function AddSpellCheck(p, s, weight, suffix)
  local name = GetSpellInfo(s.spell)
  if not name then return end
  local c = AddCheck(p, s.yards, name .. (suffix or ""), weight, function(unit)
    return ToBool(IsSpellInRange(name, unit))
  end)
  c.talent, c.perRank, c.spellName = s.talent, s.perRank or 0, name
  return c
end

local function BuildProfile(cfg, items, side)
  local p = { side = side, style = cfg.style or "attack", deadZone = cfg.deadZone, sorted = {} }
  p.meleeName = cfg.melee and GetSpellInfo(cfg.melee)
  if cfg.reach then
    p.reachCheck = AddSpellCheck(p, cfg.reach, REACH_WEIGHT, " (reach)")
    p.reachName = p.reachCheck and p.reachCheck.spellName
  end

  local _, race = UnitRace("player")
  local interact = INTERACT_YARDS[race] or INTERACT_YARDS.default
  for index, yards in pairs(interact) do
    AddCheck(p, yards, "interact " .. index, 1, function(unit)
      return CheckInteractDistance(unit, index) and true or false
    end)
  end

  for _, s in ipairs(cfg.spells or {}) do AddSpellCheck(p, s, 1) end

  for _, it in ipairs(items) do
    local id = it.item
    AddCheck(p, it.yards, "item " .. id, 1, function(unit)
      return ToBool(IsItemInRange(id, unit))
    end)
  end

  UpdateProfileReach(p) -- also sorts
  return p
end

function ns.InitChecks()
  local cfg = CLASSES[select(2, UnitClass("player"))] or {}
  hostile = BuildProfile(cfg.hostile or {}, HOSTILE_ITEMS, "hostile")
  -- Classes without an ally setup measure allies with the enemy checks, as before
  friendly = cfg.friendly and BuildProfile(cfg.friendly, FRIENDLY_ITEMS, "friendly") or nil
  ns.reachYards = hostile.reach

  if PrimeMissing() > 0 then
    primer.since, primer.tries = 0, 0
    primer:Show()
  end
end

-- Does this class have an ally (healing) setup?
function ns.HasFriendlyProfile()
  return friendly ~= nil
end

-- The profile used for `unit`: allies use your heal checks (when your class has them)
function ns.ProfileFor(unit)
  if friendly and not UnitCanAttack("player", unit) then return friendly end
  return hostile
end

function ns.DefaultProfile()
  return hostile
end

-- /rg verify statistics: how often each check disagreed with the chosen band
local verify = { on = false }

-- The cheap part, run every frame: has the melee or reach answer changed?
-- 3 = melee, 1 = in reach, 0 = out of reach, -1 = can't tell.
function ns.RawKey(unit)
  local p = ns.ProfileFor(unit)
  if p.meleeName and IsSpellInRange(p.meleeName, unit) == 1 then return 3 end
  local r = p.reachName and IsSpellInRange(p.reachName, unit)
  if r == 1 then return 1 elseif r == 0 then return 0 end
  return -1
end

-- Returns lo, hi, zone, key, profile: the unit is farther than lo yards and within hi yards
-- (hi = nil means farther than anything we can test). zone is "melee", "reach", "out",
-- or "unknown" when we can't tell which side of the reach line. key is RawKey's value.
-- profile says which checks were used (its reach and style go to the tracker and colors).
function ns.Measure(unit)
  local p = ns.ProfileFor(unit)
  if p.meleeName and IsSpellInRange(p.meleeName, unit) == 1 then
    return 0, MELEE_YARDS, "melee", 3, p
  end
  -- Too far for the client to even show (e.g. a party member in another zone)
  if not UnitIsVisible(unit) then
    return NOT_VISIBLE_YARDS, nil, "out", 0, p
  end

  -- Ask everything. falsesAfter = weight of "no" answers (all of them start on the near side).
  local sorted = p.sorted
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

  local inReach = p.reachCheck and p.reachCheck.r
  local R = p.reach
  local zone, key
  if inReach == true then
    zone, key = "reach", 1
    if not hi or hi > R then hi = R end
    if lo >= hi then lo = math.max(0, hi - 2) end
  elseif inReach == false then
    key = 0
    if p.deadZone and hi and hi <= TOO_CLOSE_YARDS then
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

  return lo, hi, zone, key, p
end

-- /rg verify: collect for `seconds` while you move around your target, then report which
-- checks never answer or disagree with the others (= their range in the list is wrong)
local function ReportProfile(p, title)
  local any
  for _, c in ipairs(p.sorted) do
    local s = verify.stats[c]
    if s then
      if not any then ns.Print(title) any = true end
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
end

local verifier = CreateFrame("Frame")
verifier:Hide()
verifier:SetScript("OnUpdate", function(self)
  if GetTime() < verify.stop then return end
  self:Hide()
  verify.on = false
  ns.Print(string.format("verify done: %d readings.", verify.readings))
  ReportProfile(hostile, "enemy checks:")
  if friendly then ReportProfile(friendly, "ally checks:") end
  ns.Print("target speed reported by the game: " .. (ns.speedWorks and "|cff55ff55yes|r" or "|cffff5555not seen yet|r"))
  ns.Print("map position: " .. ns.LocatorStatus())
end)

function ns.StartVerify(seconds)
  verify.on, verify.readings, verify.stats = true, 0, {}
  verify.stop = GetTime() + seconds
  verifier:Show()
  ns.Print(string.format("verifying for %d s: target an enemy (a training dummy is fine) or an ally " ..
    "and walk slowly from melee range out to 60+ yards and back.", seconds))
end

-- /rg debug: print what every check says about the current target
function ns.Debug(unit)
  if not UnitExists(unit) then ns.Print("target something first.") return end
  local lo, hi, zone, _, p = ns.Measure(unit)
  for _, c in ipairs(p.sorted) do
    ns.Print(string.format("%2d yd  %-28s %s", c.yards, c.label, c.r == nil and "unknown" or tostring(c.r)))
  end
  ns.Print(string.format("=> %s-%s yd, %s (%s checks, reach %d yd)", lo, hi or "?", zone, p.side, p.reach))
end
