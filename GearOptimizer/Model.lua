-- Model: an estimated-DPS calculator for Enhancement Shamans (3.3.5, level 80), so gear is judged
-- by what it does to your damage instead of fixed stat weights.
--
-- In: the gear stats of one candidate set (plus weapon speeds, meta gem, proc averages) and the
-- modifiers from glyphs and set bonuses (read from their text by Core.lua). It adds your base
-- stats (race/class), your talents (read by name), and the buffs of the chosen scenario, then
-- works out hit/crit/haste/AP/SP and the damage per second of each ability.
-- Out: total DPS, a breakdown per ability, and event rates (hits, crits, casts per second) so
-- trinket procs can be valued from your real attack rate.
--
-- It is a closed-form average, not a combat log simulation: rotations and procs are averaged.
-- Numbers are approximate 3.3.5 values; /gopt model prints the breakdown to compare with Skada.

local _, ns = ...
local M = {}
ns.Model = M

-- Ratings at level 80
local CRIT_PER_PCT = 45.91
local MELEE_HIT_PER_PCT = 32.79
local SPELL_HIT_PER_PCT = 26.23
local MELEE_HASTE_PER_PCT = 25.22   -- shamans get 30% more melee haste from rating
local SPELL_HASTE_PER_PCT = 32.79
local EXPERTISE_PER_POINT = 8.19745
local ARP_PER_PCT = 13.99
local AGI_PER_CRIT = 83.33          -- agility per 1% melee crit (shaman)
local INT_PER_SPELL_CRIT = 166.67   -- intellect per 1% spell crit (shaman)
local BASE_MELEE_CRIT = 2.92
local BASE_SPELL_CRIT = 2.2

-- Boss (level 83)
local BOSS_ARMOR = 10643
local ARMOR_K = 15232.5             -- armor constant for a level 80 attacker
local BOSS_DODGE = 6.5
local MELEE_MISS = 8                -- specials; dual-wield white hits miss 19% more
local DW_EXTRA_MISS = 19
local SPELL_MISS = 17
local GLANCE_CHANCE, GLANCE_DAMAGE = 24, 0.75
local CRIT_SUPPRESSION = 4.8        -- melee crit lost against a boss

-- Buffs and debuffs of a typical 25-player ICC raid (what the scenarios assume). Edit to taste.
M.RAID_BUFFS = {
  stats = 52, kings = 0.10,           -- Mark of the Wild, Blessing of Kings
  ap = 688, apPct = 0.10,             -- Blessing of Might / Battle Shout, Unleashed Rage / Trueshot
  flaskAP = 180, foodAP = 80,         -- Flask of Endless Rage, Fish Feast
  sp = 280,                           -- Totem of Wrath / Demonic Pact
  meleeCrit = 5, spellCrit = 5,       -- Leader of the Pack, Moonkin Aura / Elemental Oath
  targetCrit = 3,                     -- Heart of the Crusader / Totem of Wrath: +3% to be crit
  spellCritDebuff = 5,                -- Improved Scorch / Winter's Chill
  meleeHaste = 0.20,                  -- Windfury Totem / Improved Icy Talons
  spellHaste = 0.05,                  -- Wrath of Air
  allHaste = 0.03,                    -- Swift Retribution / Improved Moonkin
  spellHit = 3,                       -- Misery / Improved Faerie Fire
  armorCut = 0.24,                    -- Sunder Armor + Faerie Fire
  physDamage = 0.04, spellDamage = 0.13, allDamage = 0.03,
  bloodlust = 40 / 300,               -- share of a fight under Bloodlust (+30% haste)
}

-- Scenarios: Raid = one boss; AOE = a pack of `targets` (melee and single-target spells still
-- hit only one of them)
M.SCENARIOS = {
  RAID = { name = "Raid", purpose = "single target", targets = 1 },
  AOE = { name = "AOE", purpose = "packs", targets = 4 },
}

local TALENTS = {
  "Ancestral Knowledge", "Thundering Strikes", "Enhancing Totems", "Flurry", "Elemental Weapons",
  "Weapon Mastery", "Dual Wield Specialization", "Unleashed Rage", "Mental Dexterity",
  "Mental Quickness", "Static Shock", "Maelstrom Weapon", "Improved Stormstrike", "Lava Lash",
  "Stormstrike", "Feral Spirit", "Improved Fire Nova", "Elemental Precision", "Concussion",
  "Call of Thunder", "Shamanistic Focus", "Improved Shields", "Elemental Devastation",
}

-- Talent ranks by name (read once per Find)
function M.ReadTalents()
  local want, t = {}, {}
  for _, name in ipairs(TALENTS) do want[name] = true; t[name] = 0 end
  for tab = 1, GetNumTalentTabs() do
    for i = 1, GetNumTalents(tab) do
      local name, _, _, _, rank = GetTalentInfo(tab, i)
      if want[name] then t[name] = rank end
    end
  end
  return t
end

-- Base stats from race and class (no gear, no buffs)
function M.ReadBase()
  local b = {}
  b.str = UnitStat("player", 1)
  b.agi = UnitStat("player", 2)
  b.int = UnitStat("player", 4)
  local _, race = UnitRace("player")
  b.draenei = race == "Draenei"
  return b
end

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

-- g: gear stats of a set (agi, str, int, ap, sp, hit, crit, haste, exp, arp, apPct; mh/oh =
-- { dps, speed }; critMeta = true for a +3% crit damage meta gem).
-- mods: from glyphs and set bonuses: dmg[ability] = multiplier, ssBonus, wfChance, wolfAP,
-- clTargets, fireNovaCD, spellCrit (all additive extras). Returns dps, breakdown, events, stats.
local NO_MODS = { dmg = {} }
function M.DPS(g, sc, T, base, mods)
  mods = mods or NO_MODS
  local B = M.RAID_BUFFS
  g.mh = g.mh or { dps = 0, speed = 2.0 } -- no main-hand weapon: fists
  local breakdown = {}

  -- Attributes
  local statMult = 1 + B.kings
  local agi = (base.agi + (g.agi or 0) + B.stats) * statMult
  local str = (base.str + (g.str or 0) + B.stats) * statMult
  local int = (base.int + (g.int or 0) + B.stats) * statMult * (1 + 0.02 * T["Ancestral Knowledge"])
  local apPct = math.max(B.apPct, T["Unleashed Rage"] > 0 and 0.10 or 0)
  local ap = (140 + agi + str + (g.ap or 0) + B.ap + B.flaskAP + B.foodAP
    + int * T["Mental Dexterity"] / 3) * (1 + apPct) * (1 + (g.apPct or 0))
  local sp = (g.sp or 0) + B.sp + ap * 0.1 * T["Mental Quickness"]

  -- Hit, expertise, crit
  local dual = g.oh and g.oh.dps and g.oh.dps > 0
  local hitPct = (g.hit or 0) / MELEE_HIT_PER_PCT + (base.draenei and 1 or 0)
    + (dual and 2 * T["Dual Wield Specialization"] or 0)
  local specialMiss = clamp(MELEE_MISS - hitPct, 0, 100)
  local whiteMiss = clamp(MELEE_MISS + (dual and DW_EXTRA_MISS or 0) - hitPct, 0, 100)
  local expertise = (g.exp or 0) / EXPERTISE_PER_POINT + 3 * T["Unleashed Rage"]
  local dodge = clamp(BOSS_DODGE - expertise * 0.25, 0, 100)
  local spellHitPct = (g.hit or 0) / SPELL_HIT_PER_PCT + (base.draenei and 1 or 0)
    + T["Elemental Precision"] + B.spellHit
  local spellMiss = clamp(SPELL_MISS - spellHitPct, 1, 100) / 100

  local meleeCrit = BASE_MELEE_CRIT + agi / AGI_PER_CRIT + (g.crit or 0) / CRIT_PER_PCT + B.meleeCrit
    + B.targetCrit + T["Thundering Strikes"] - CRIT_SUPPRESSION
  local spellCrit = BASE_SPELL_CRIT + int / INT_PER_SPELL_CRIT + (g.crit or 0) / CRIT_PER_PCT
    + B.spellCrit + B.targetCrit + B.spellCritDebuff + T["Thundering Strikes"] + (mods.spellCrit or 0)
  meleeCrit, spellCrit = clamp(meleeCrit, 0, 100) / 100, clamp(spellCrit, 0, 100) / 100
  local meleeCritMult = 2 * (g.critMeta and 1.03 or 1)
  local spellCritMult = 1.5 * (g.critMeta and 1.03 or 1)

  -- Haste (Bloodlust averaged over the fight); Flurry from melee crits
  local lust = 1 + 0.3 * B.bloodlust
  local flurryUptime = 1 - (1 - meleeCrit) ^ 3
  local flurry = 1 + 0.06 * T["Flurry"] * flurryUptime
  local meleeHaste = (1 + (g.haste or 0) / MELEE_HASTE_PER_PCT / 100) * (1 + B.meleeHaste)
    * (1 + B.allHaste) * lust * flurry
  local spellHaste = (1 + (g.haste or 0) / SPELL_HASTE_PER_PCT / 100) * (1 + B.spellHaste)
    * (1 + B.allHaste) * lust

  -- Damage multipliers
  local armor = BOSS_ARMOR * (1 - B.armorCut) * (1 - clamp((g.arp or 0) / ARP_PER_PCT, 0, 100) / 100)
  local armorMult = 1 - armor / (armor + ARMOR_K)
  local weaponMastery = 1 + ({ 0, 0.03, 0.07, 0.10 })[T["Weapon Mastery"] + 1]
  local physMult = armorMult * weaponMastery * (1 + B.physDamage) * (1 + B.allDamage)
  local fireMult = weaponMastery * (1 + B.spellDamage) * (1 + B.allDamage) -- Lava Lash: weapon, fire
  local spellMult = (1 + B.spellDamage) * (1 + B.allDamage)
  local ssBonus = T["Stormstrike"] > 0 and (1 + 0.2 + (mods.ssBonus or 0)) or 1

  -- Average outcome of one attack
  local yellowLand = (1 - specialMiss / 100) * (1 - dodge / 100)
  local yellowAvg = yellowLand * (1 + meleeCrit * (meleeCritMult - 1))
  local whiteCrit = clamp(meleeCrit * 100, 0, 100 - whiteMiss - dodge - GLANCE_CHANCE) / 100
  local whiteLand = 1 - whiteMiss / 100 - dodge / 100
  local whiteAvg = GLANCE_CHANCE / 100 * GLANCE_DAMAGE + whiteCrit * meleeCritMult
    + (whiteLand - GLANCE_CHANCE / 100 - whiteCrit)
  local spellAvg = (1 - spellMiss) * (1 + spellCrit * (spellCritMult - 1))

  local events = { meleeHits = 0, meleeCrits = 0, spellHits = 0, spellCrits = 0, maelstrom = 0 }
  local total = 0
  local function Add(name, dps)
    dps = dps * (mods.dmg[name] or 1)
    breakdown[name] = (breakdown[name] or 0) + dps
    total = total + dps
  end

  -- White hits
  local hands = { { w = g.mh, mult = 1, name = "Melee" } }
  if dual then table.insert(hands, { w = g.oh, mult = 0.5, name = "Melee" }) end
  local mhSwings, ohSwings = 0, 0
  for i, h in ipairs(hands) do
    local speed = h.w.speed or 2.6
    local swings = meleeHaste / speed
    local dmg = (h.w.dps * speed + ap / 14 * speed) * h.mult
    Add("Melee", swings * dmg * whiteAvg * physMult)
    events.meleeHits = events.meleeHits + swings * whiteLand
    events.meleeCrits = events.meleeCrits + swings * whiteCrit
    if i == 1 then mhSwings = swings * whiteLand else ohSwings = swings * whiteLand end
  end

  -- Windfury Weapon (main hand): 20% per landed hit, 3 s cooldown; two attacks with +1250 AP
  if g.mh then
    local speed = g.mh.speed or 2.6
    local tries = (mhSwings + 1 / 8) * (0.2 + (mods.wfChance or 0)) -- swings plus Stormstrike's main hand
    local procs = tries / (1 + tries * 3)
    local dmg = (g.mh.dps * speed + (ap + 1250) / 14 * speed) * (1 + 0.1333 * T["Elemental Weapons"])
    Add("Windfury", procs * 2 * dmg * yellowAvg * physMult)
    events.meleeHits = events.meleeHits + procs * 2 * yellowLand
    events.meleeCrits = events.meleeCrits + procs * 2 * yellowLand * meleeCrit
  end

  -- Stormstrike (8 s): both weapons, normalized to 2.4 speed
  if T["Stormstrike"] > 0 and g.mh then
    local dmg = g.mh.dps * (g.mh.speed or 2.6) + ap / 14 * 2.4
    if dual then dmg = dmg + 0.5 * (g.oh.dps * (g.oh.speed or 2.6) + ap / 14 * 2.4) end
    Add("Stormstrike", dmg / 8 * yellowAvg * physMult)
    events.meleeHits = events.meleeHits + (dual and 2 or 1) / 8 * yellowLand
  end

  -- Lava Lash (6 s): off-hand weapon damage, +25% with Flametongue on it, fire
  if T["Lava Lash"] > 0 and dual then
    local dmg = (g.oh.dps * (g.oh.speed or 2.6) + ap / 14 * (g.oh.speed or 2.6)) * 1.25
    Add("Lava Lash", dmg / 6 * yellowAvg * fireMult)
  end

  -- Flametongue Weapon (off hand): fire damage per landed off-hand hit
  if dual then
    local speed = g.oh.speed or 2.6
    local dmg = (40 * speed + 0.1 * sp * speed / 2.6) * (1 + 0.1333 * T["Elemental Weapons"])
    local hits = ohSwings + 1 / 6 -- plus Lava Lash
    Add("Flametongue", hits * dmg * spellAvg * spellMult)
    events.spellHits = events.spellHits + hits
  end

  -- Static Shock: 2% per rank per landed melee hit to discharge a Lightning Shield orb
  if T["Static Shock"] > 0 then
    local orb = (380 + 0.33 * sp) * (1 + 0.05 * T["Improved Shields"])
    Add("Lightning Shield", events.meleeHits * 0.02 * T["Static Shock"] * orb * (1 - spellMiss) * spellMult)
  end

  -- Shocks (6 s): Flame Shock kept up, Earth Shock in between; Stormstrike's +20% nature
  local concussion = 1 + 0.01 * T["Concussion"]
  local fsHit = (505 + 0.2142 * sp) * spellAvg + (834 + 0.6 * sp) * (1 - spellMiss) * (1 + spellCrit * 0.5)
  local es = (854 + 0.386 * sp) * spellAvg * ssBonus
  Add("Shocks", (fsHit + 2 * es) / 18 * spellMult * concussion)
  events.spellHits = events.spellHits + 1 / 6

  -- Maelstrom Weapon: 2 PPM per rank from landed melee hits; at 5 stacks an instant Lightning
  -- Bolt (Chain Lightning in AOE: 3 targets, 30% less per jump)
  if T["Maelstrom Weapon"] > 0 then
    local mhSpeed = g.mh and g.mh.speed or 2.6
    local ohSpeed = dual and g.oh.speed or 2.6
    local ppm = 2 * T["Maelstrom Weapon"]
    local stacks = ppm / 60 * (mhSwings * mhSpeed + ohSwings * ohSpeed + (events.meleeHits - mhSwings - ohSwings) * mhSpeed)
    local casts = stacks / 5
    local lbCrit = spellAvg + (1 - spellMiss) * 0.05 * T["Call of Thunder"] * (spellCritMult - 1)
    if sc.targets > 1 then
      local jumps = { 1, 0.7, 0.49, 0.343, 0.24 }
      local hits = 0
      for i = 1, math.min(sc.targets, 3 + (mods.clTargets or 0)) do hits = hits + jumps[i] end
      local cl = (1042 + 0.5714 * sp) * lbCrit * hits * spellMult * concussion
      Add("Chain Lightning", casts * cl)
    else
      local lb = (769 + 0.7143 * sp) * lbCrit * ssBonus * spellMult * concussion
      Add("Lightning Bolt", casts * lb)
    end
    events.spellHits = events.spellHits + casts
    events.maelstrom = casts
  end

  -- Fire totem: Searing on one target, Magma on a pack (every 2 s to all)
  local totems = 1 + 0.05 * T["Enhancing Totems"]
  if sc.targets > 1 then
    Add("Magma Totem", (371 + 0.1 * sp) / 2 * sc.targets * spellAvg * spellMult * totems)
  else
    Add("Searing Totem", (105 + 0.1667 * sp) / 2.2 * spellAvg * spellMult * totems)
  end

  -- Fire Nova (packs): 10 s, less with Improved Fire Nova
  if sc.targets > 1 then
    local cd = 10 - 2 * T["Improved Fire Nova"] - (mods.fireNovaCD or 0)
    Add("Fire Nova", (945 + 0.2142 * sp) / cd * sc.targets * spellAvg * spellMult)
  end

  -- Feral Spirit: two wolves for 45 s every 3 min, scaling with 30% of your AP
  if T["Feral Spirit"] > 0 then
    Add("Feral Spirit", 45 / 180 * 2 * (220 + (0.3 + (mods.wolfAP or 0)) * ap / 14 * 1.5) * whiteAvg * armorMult)
  end

  events.spellCrits = events.spellHits * spellCrit
  local stats = { ap = ap, sp = sp, meleeCrit = meleeCrit, spellCrit = spellCrit, hitPct = hitPct,
    spellHitPct = spellHitPct, expertise = expertise, meleeHaste = meleeHaste, spellHaste = spellHaste }
  return total, breakdown, events, stats
end
