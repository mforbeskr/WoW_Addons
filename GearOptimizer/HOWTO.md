# Gear Optimizer - how to

1. Visit your bank once per character so bank gear is included.
2. `/gopt`, pick your build at the top (remembered per character): **On-hit** or **Spellhance**.
3. Press **Find best Raid build** (bosses) or, on Spellhance, **Find best AOE build**
   (dungeons, trash packs). Nothing is calculated until you press one.
4. Each row: what you wear > what to wear instead. Green rows change, the rest say "same".
   `(bank)` = in the bank, `(other slot)` = one of your own items moves (e.g. other hand).
5. **Equip all changes** does it in one click (with the bank open it fetches bank items too).
   Then **Save as "Opt Raid"** / **"Opt AOE"** for one-click swaps in the Equipment Manager.

- Counts stats, gems, weapon DPS, trinket and totem effects, and tier set bonuses.
  `~` = estimated (an effect or bonus it can't read).
- Hit and expertise count less past their cap; the caps follow your talents and race.
- Not counted: enchants, socket bonuses. Weights per build are in `Core.lua` (`PROFILES`).
