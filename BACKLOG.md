# WoW Backlog

Addon ideas and to-dos for WoW 3.3.5a (Warmane).

- **Game:** `C:\Games\World of Warcraft 3.3.5a`
- **Our addons:** `...\Interface\AddOns\` (GearDump, BambooBags)
- **Workflow:** edit Lua in the IDE -> `/reload` in game. New textures or new addon
  folders need a full game restart.

> **Status 2026-11-17:** v0.1 built early! `AddOns\RangeGauge` (`/rg`). Hunter only:
> reach line = Auto Shot (+Hawk Eye), melee = Wing Clip, interact + item checks in
> between. Next: verify item ranges with `/rg debug`, add other classes, focus/arena
> bars, sounds, bamboo look.

---

## Big project: Range indicator addon ("range gauge")

For me + friend. Hunter PvP first, but built to work for any class.
Start fresh another day.

### Goal

Always see how far your target is compared to your auto-attack reach, so you know
when you can hit, when someone is about to come in or slip out, and when to back off.

### Design

- You target someone; the addon keeps asking the game for the range.
- Display: a thin **vertical** bar. A marker moves up/down the bar with the target's distance.
- A thin **horizontal** line across the bar = "within auto-attack reach".
  - Hunter: Auto Shot max range, 35 yd, or 41 with Hawk Eye.
  - Melee classes: melee range.
  - Casters: could use the main spell's range.
- Below the line = in range (green).
- Just above the line = approach zone, "almost in range" (yellow): you see someone
  coming in or slipping out before it happens.
- The bar only shows a short stretch past the line (e.g. +10 yd). Anything farther
  just pins the marker at the top as "out of range" (grey). No huge scale.

```
out of range  ┬  (marker pinned here when far away)
              │   yellow: approaching (line + 10 yd)
───────────── ┼  <- auto-attack reach line
              │   green: in range
              ▼
0 yd (on top of you)
```

### How it works

- The game can't give an exact distance. Instead we ask "is the unit in range of X?
  yes/no" for spells and items with known ranges (`IsSpellInRange`, `IsItemInRange`,
  `CheckInteractDistance`), then combine the answers into a min-max band, e.g.
  "30-35 yd". That's how LibRangeCheck works.
- The marker therefore moves in steps between known checkpoints. Animate between
  steps so it still feels smooth. The reach line itself is exact.
- Each class gets its own list of checkpoints (hunter first, then add classes one by one).

### Update rate

- About 10 checks per second (every 0.1 s), via a throttled OnUpdate.
- Why 10: other players' positions only arrive from the server every so often, so
  faster adds little. Blizzard's own out-of-range button coloring checks 5x per
  second. A range check is very cheap, so FPS isn't affected.
- Target changes react instantly via the `PLAYER_TARGET_CHANGED` event.
- Keep the rate as one constant at the top (`UPDATE_INTERVAL = 0.1`); try 5/10/20
  on build day.

### Limits

- No drawing circles on the ground in the 3D world (no API for it in 3.3.5).
- Information only: no automation. One key press = one action.

### Later options

- The same bar for focus and arena1-5 (enemy healer distance matters in arena).
- Sound or flash when the target crosses the line, or when an enemy melee closes in.
- Lock / move / resize the bar.
- Match the BambooBags look (bamboo + purple neon).
- Related range ideas that could live in the same addon later:
  - Range radar like DBM's: round window with group dots and 8/10/30 yd rings.
  - Totem range (shaman): show which group members are outside my totems' range.

### Build day steps

1. Check the exact ranges of hunter spells in 3.3.5 (they changed between patches)
   and pick which spells/items to test for each range band.
2. Range check loop + print the band in chat (prove the data works).
3. The vertical bar, marker and reach line.
4. Colors, approach zone, out-of-range pin.
5. Saved settings, then the later options.

### Learning topics

Unit API, combining many yes/no checks into a band, OnUpdate throttling, events,
smooth animation, saved settings, a movable/lockable display.

---

## Transmog Studio (v0.1 built 2026-11-17, `/ts`)

Suggests outfits from gear you own (equipped, bags, bank), learns from Like/Dislike,
keeps a Favorites list, and also saves liked looks into DressMe.

Next ideas:

- Color tags: one click to tag an item red/blue/green..., then "only blue" or
  matching-color sets.
- Smarter learning: remember which items look good TOGETHER, not just each item alone.
- Pool filter: only the Outfits section from BambooBags, or include gear.
- Rename favorites; zoom the model with the mouse wheel.

---

## Smaller ideas

- Maelstrom Weapon tracker (enhancement): glow or sound at 5 stacks. Uses `UNIT_AURA`.
- BambooBags: button to buy bank bag slots (the Blizzard bank screen is hidden now).
- BambooBags: optionally sell more than greys (old food, etc.), never touching Outfits.

---

## To-do

- [ ] Set up IntelliJ on StudyUser: open the addon folder, install the EmmyLua plugin,
  and add WoW 3.3.5 API autocomplete.
- [ ] Make a new WoW shortcut (old shortcuts may still point to the USB stick).
- [ ] Delete the old WoW copy on the USB stick (`D:\Magnus\...`) once the SSD copy has
  run fine for a while.
