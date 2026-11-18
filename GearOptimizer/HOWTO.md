# Gear Optimizer - how to

1. Visit your bank once per character so bank gear is included.
2. `/gopt`, then **Find best Raid build** (bosses) or **Find best AOE build** (dungeons, packs).
   Nothing is calculated until you press one.
3. Each row: what you wear > what to wear instead. Green rows change, the rest say "same".
   `(bank)` = in the bank, `(other slot)` = one of your own items moves (e.g. other hand).
4. **Equip all changes** does it in one click (with the bank open it fetches bank items too).
   Then **Save as "Opt Raid"** / **"Opt AOE"** for one-click swaps in the Equipment Manager.

How it decides: every combination is run through an Enhancement DPS model with your talents,
glyphs, base stats and ICC raid buffs. Trinket procs are valued from the hits/crits/casts of that
exact set, set bonuses are read from their text. `~` = estimated (an effect it can't read).

- `/gopt model` (or `/gopt model aoe`): the model's DPS breakdown per ability for what you wear.
  Compare the percentages with Skada after a boss to see where the model is off.
- Not counted: enchants, socket bonuses. Buffs and constants are in `Model.lua`.
