# Range Gauge - How to use

Shows, live, whether your target (and focus, and arena enemies) is inside your
Auto Shot range - or, on a Priest, whether your allies are inside your heal range.
Version 0.5 - Hunters and Priests (WoW 3.3.5a). Priests: see section 4b.
Two views of the same thing: range lights (default) and a range bar.

## 1. Install

1. Close WoW completely.
2. Put the `RangeGauge` folder in: `World of Warcraft 3.3.5a\Interface\AddOns\`
3. Start WoW. On the character select screen, click "AddOns" (bottom left) and
   make sure "Range Gauge" is ticked. If it says "out of date", tick
   "Load out of date AddOns".

## 2. First time setup (once)

1. Log in on your Hunter.
2. Below the middle of your screen you'll see a dark box saying
   "Range lights - drag me".
3. Drag it with the left mouse button to where you want it.
4. Type `/rg lock` so you can't move it by accident.

## 3. The colors explained (same in both views)

The one rule to remember:

> **BRIGHT = you can shoot  ·  DARK = you can't**

The line between them is your Auto Shot range (35 yards, or 41 with all 3
points in Hawk Eye). It's the exact, instant part of the addon: it comes from
the game's own Auto Shot range check, the same one that turns your action bar red.

The steps, from on top of you to far away (yards for a 35 yd reach):

| Yards  | Color       | Label  | What it means                     |
|--------|-------------|--------|-----------------------------------|
| 0 - 5  | red         | MELEE  | melee range - too close to shoot  |
| 5 - 10 | orange      | NEAR   | can shoot, but they're closing in |
| 10 - 28| green       | GOOD   | comfortable shooting range        |
| 28 - 35| teal        | MAX    | still in range, but near your max |
| **35** | —           | —      | **reach line: the hard switch from bright to dark** |
| 35 - 45| dark purple | ALMOST | just out of range                 |
| 45 - 50| purple      | OUT    | out of range                      |
| 50 +   | royal blue  | FAR    | far away, nothing to worry about  |
| —      | grey        | ?      | can't tell (usually a friendly target) |

How the colors move:

- **Inside** your range the light fades smoothly with the distance:
  red -> orange -> green -> teal.
  So the warnings (orange when they get close, teal when they drift toward
  your max range) come while you can still shoot.
- **At the line** there is no fade on purpose: teal jumps straight to dark
  purple the moment they step out, so in vs. out is never in doubt.
- **Outside** your range it keeps fading darker as they get farther:
  dark purple -> royal blue.
- The colors fade, the labels change in steps. A light that's somewhere between
  green and teal is simply somewhere between GOOD and MAX.

What else moves:

- A soft glow behind the light slowly "breathes" so it looks alive.
- Flash + click: when your target steps into another zone (melee, in range or
  out of range), the light flashes and you hear a soft click. Clicking "on" =
  they came in, "off" = they left. Turn the click off with `/rg mute` (and back
  on with `/rg unmute`).
- The yards number is a live estimate. The game only answers "in range or
  not" at certain distances, so between those points the addon works it out
  from how fast you and your target move, and (outside arenas) from where you
  stand on the map. The color of the light at the reach line is always the
  exact part.
- The labels (GOOD, MAX, ALMOST...) follow the yards number, so they always
  agree with it.

### How the yards get better as you move

- **Standing target** (casters, healers, training dummies): every time you
  move, the addon narrows down where the target stands. After a few steps
  the number follows you smoothly and closely, even between checkpoints.
- **Moving target**: the game tells how fast it runs, not which way, so the
  number is a bit rougher. It never runs off while nobody moves.
- The first time you're in a zone, the addon has to learn the map's size:
  just run around for a few seconds. It remembers each zone after that.
  `/rg map` shows whether it's ready.
- In arenas the map gives no position, so the number comes from the
  checkpoints and speeds only.

## 4. The lights (the default view)

One row per enemy you care about:

```
[●] Enemyname          24 yd  GOOD         <- your target
[●] F  Healername      40+    OUT          <- your focus
[●] A1 Rogue                  MELEE        <- arena enemies 1-5
```

- Names are in class colors. "F" = focus, "A1"-"A5" = arena enemies.
- Your focus only gets its own row when it's not also your target.
- Arena rows only appear in arena.
- Checked 30 times per second; the in/out-of-range part every frame, so the
  click comes the instant they cross.

## 4b. Priests: healing range on allies

On a Priest the addon measures each unit with the right spells for it:

- **Allies** (friendly target, focus, your party): your heal range. The exact
  in/out line is Flash Heal's 40 yards (the same range as Renew, Power Word:
  Shield and Greater Heal). Power Word: Fortitude and Dispel Magic (30 yd) and
  friendly-usable items fill in the yards below that.
- **Enemies**: Shadow Word: Pain's range (30 yd, +3 per point in Shadow
  Reach), with Smite (+Holy Reach) and Mind Flay as extra checkpoints.

Allies get a healer color scheme, like raid frames:

| Color      | Label    | What it means                              |
|------------|----------|--------------------------------------------|
| soft green | IN RANGE | you can heal them                          |
| gold       | EDGE     | last 7 yards of your range - about to lose them |
| red-orange | OUT      | out of heal range                          |
| dim wine   | FAR      | far away (50+ yd, or out of sight: "100+ yd") |

```
|[●] T  Tankname       31 yd  IN RANGE    <- green stripe = ally
|[●] P1 Magename       38 yd  EDGE
|[●] P2 Roguename      44 yd  OUT          <- name faded: you can't heal them
|[●] F  Enemyname      24 yd  GOOD        <- red stripe = enemy
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ thin line under an ally = their health
```

- Your group (party1-4, also your subgroup in a raid and your team in arena)
  gets a row each, after your target and focus. Nobody gets two rows.
  `/rg party` hides or shows the group rows.
- Tags: T = target, F = focus, P1-P4 = party, A1-A5 = arena enemies.
- The stripe on the left: green = ally, red = enemy, yellow = neutral.
- Allies you can't heal fade out, so a glance shows who you'd lose.
- The click and flash work the same: "on" = they came into heal range,
  "off" = they left it.

## 5. The bar (optional second view)

Type `/rg bar` to switch to a vertical bar with a moving marker, and
`/rg lights` to switch back. The bar shows only your target.
Same colors, labels, yards, flash and click as the lights.

```
   far                          marker sits at the top when far away
   ░░ dark purple ░░            out of range
35 ─────────────── -           your Auto Shot range (the reach line)
   ▓▓ teal ▓▓        -          MAX
   ▓▓ green ▓▓       -          GOOD
   ▓▓ orange ▓▓      -          NEAR
   ▒▒ red ▒▒                    MELEE
```

- The bar itself is painted with the color steps, so you can see where each
  zone starts.
- The small marks on the right are every 5 yards.
- Next to the marker: the live yards and the label, e.g. "24 yd GOOD".
- The reach line flashes when your target crosses it.

## 6. Commands

| Command      | What it does                                              |
|--------------|-----------------------------------------------------------|
| `/rg`        | show the list of commands                                 |
| `/rg lock`   | lock the display in place                                 |
| `/rg unlock` | unlock it so you can drag it again                        |
| `/rg reset`  | move it back to its starting spot                         |
| `/rg lights` | show the range lights (default)                           |
| `/rg bar`    | show the vertical range bar instead                       |
| `/rg mute`   | turn the click off                                        |
| `/rg unmute` | turn the click back on                                    |
| `/rg sound`  | switch the click on/off (same as above, one command)      |
| `/rg party`  | hide/show your group's rows (Priests)                     |
| `/rg debug`  | print every range check on your target (for fixing things)|
| `/rg live`   | print your target's tracking for 10 seconds (for fixing things)|
| `/rg verify` | 60 s check that every range checkpoint answers at its distance |
| `/rg map`    | show whether your map position is ready                   |

## 7. Everyday use

Move the display later:

1. `/rg unlock`
2. Drag it. (With no target, drag the "drag me" box.)
3. `/rg lock`

Can't find it: `/rg reset`

## 8. Troubleshooting

**Nothing shows up**
- Do you have a target? The lights hide when you have none (unless unlocked,
  then you see the "drag me" box).
- Is "Range Gauge" ticked in the AddOns list on character select?
- Did you restart WoW fully after installing or updating? (`/reload` is not
  enough when the addon gets new files.)

**The light is grey with "?"**
- On a Hunter: your target is friendly. Auto Shot and most range checks only
  work on enemies. To test with a friend: duel them, then everything works.
  Training dummies also work. (Priests measure allies with their heals.)

**It doesn't seem to work on my other characters**
- Version 0.5 is set up for Hunters and Priests. Other classes are planned.

**Something looks wrong**
- Target an enemy, type `/rg debug`, and screenshot the chat.

**The number jumps at one particular distance**
- Target a training dummy, type `/rg verify`, and walk slowly from melee
  range out to 60+ yards and back within the minute. It lists any checkpoint
  that never answers or answers at the wrong distance. Screenshot the result.
