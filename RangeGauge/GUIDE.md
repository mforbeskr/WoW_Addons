# Range Gauge - How to use

Shows, live, whether your target (and focus, and arena enemies) is inside your
Auto Shot range.
Version 0.3 - made for Hunters (WoW 3.3.5a).
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
- The yards number is a live, smoothed estimate. The game only answers
  "in range or not" at certain distances, so the number glides between those
  points. It's a good guide, but the color of the light at the reach line is
  the exact part.

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
- Checked 20 times per second.

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
| `/rg debug`  | print every range check on your target (for fixing things)|
| `/rg live`   | print the bar's tracking for 10 seconds (for fixing things)|

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
- Your target is friendly. Auto Shot and most range checks only work on
  enemies. To test with a friend: duel them, then everything works. Training
  dummies also work.

**It doesn't seem to work on my other characters**
- Version 0.3 is set up for Hunters only. Other classes are planned.

**Something looks wrong**
- Target an enemy, type `/rg debug`, and screenshot the chat.
