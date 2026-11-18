# WoW_Addons

Addons for WoW 3.3.5a (Warmane, Interface 30300, Lua 5.1 / WotLK API only).

## Setup
- Each addon folder is junctioned into
  `C:\Games\World of Warcraft 3.3.5a\Interface\AddOns\`.
  Save + `/reload` picks up Lua/XML edits; new files or .toc edits need a client restart.
- Windows users StudyUser (edits) and MForb (read-only, also plays).

## Performance rules (all addons)
Addons must run well on weak PCs:
- No per-frame OnUpdate work beyond a cheap dirty-flag check. Prefer events;
  throttle timers to 0.1-0.2s.
- Coalesce event bursts into one refresh.
- Create frames/textures once and reuse them.
- No work while hidden.
- Avoid creating garbage (tables, closures, string concat) in hot paths.
- Smallest textures that look right (32-64px, power of two).
- No libraries like Ace3 unless clearly needed.
- Keep SavedVariables small.
- Exception: RangeGauge is tuned for max quality, not min cost (owner's call): 30 full
  checks/s + melee/reach answer every frame, and a particle filter per shown unit.
  It must still stop when idle (no units shown).

## Addons
- **BambooBags** (window title "Bags") - bag/bank replacement. Dark translucent grain panel
  (`textures/grain.tga`, made by the PowerShell script in `tools/`; `/bb alpha 0.2-1`), crisp 1px
  bevel edges, drop shadow, raised buttons, sunken search. The old bamboo/linen textures stay for
  TransmogStudio. Footer shows the currencies ticked "Show on Backpack" (emblems, honor). Sections: Gear (ilvl 200+),
  Outfits (cosmetics/transmog), General. Search, sort, ilvl text, quality borders,
  free-slot counter, sell-grey-junk button at vendors (skips items moved to Outfits),
  bank bag slot row + buy-slot button in the bank window, Alt+click moves items
  between sections, movable windows with saved positions.
- **GearDump** - exports equipped/bag/bank items (ilvl, ID, enchants, gems) as text.
- **RangeGauge** (`/rg`) - live range to target/focus/arena1-5 vs. your Auto Shot reach
  (Hunter only so far; +Hawk Eye). Range lights (default) or vertical bar (`/rg bar`),
  color zones MELEE/NEAR/GOOD/MAX | ALMOST/OUT/FAR, flash + click on zone change.
  Distance: robust band from yes/no spell/item/interact checks (`Checks.lua`); `Tracker.lua`
  blends a speed-bounded band tracker (GetUnitSpeed) with a map particle filter (your map
  position, `Locator.lua`, map size self-calibrated from run speed, saved per map).
  `/rg verify` checks item ranges in game. Python simulator for tuning: `RangeGauge/tools/sim/`
  (`python bench.py`; mirrors the Lua, keep both in sync). User guide: `RangeGauge/GUIDE.md`.
- **TransmogStudio** (`/ts`) - suggests outfits from gear you own (equipped, bags, bank
  remembered per character), shown on a model; Like/Dislike reweights items
  (`Generator.lua`), click a slot to lock it, Favorites list, liked looks also saved into
  DressMe. Uses BambooBags' bamboo textures when that's loaded. `/ts forget` resets learning.

Ideas and to-dos: `BACKLOG.md`.

## Open work
- In-game test: 10px dark border, Outfits section, sell junk, bank bag slots + buy slot, bank+bag interactions.
- Maybe: extra auto-sell categories (never touch Outfits).
