# Gear Optimizer - how to

1. Visit your bank once per character so bank gear is included.
2. Type `/gopt`. Each row shows what you wear and the best item you own for that slot,
   with the score gain. Hover an item for its tooltip.
3. **Equip from bags** puts on the suggested bag items. Items marked `(bank)` you fetch
   yourself; `(swap)` means move one of your own items (e.g. weapon to the other hand).
4. Like it? Save it in Blizzard's Equipment Manager (character window).

- So far: Enhancement Shaman PvE. Weights are in `Core.lua` (`PROFILES`), easy to tweak.
- Hit and expertise count less once you're over the cap (shown under the score).
- Not counted: enchants, socket/set bonuses, Equip/Use effects. Trinkets and totem are kept.
- Your saved Equipment Manager sets are scored too, for comparison.
