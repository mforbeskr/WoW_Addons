# RangeGauge simulator

Python model of the range tracker, used to tune it without the game.

- `world.py` - simulated player/target movement and WoW-style yes/no range checks.
- `est_new.py` - prototype of the current tracker (`Checks.lua` band + `Tracker.lua`).
  **Keep it in sync with the Lua** when changing the tracker.
- `est_old.py` - the pre-0.4 tracker, as a baseline.
- `python bench.py` - error, jumps and frozen time per scenario, with/without map position.
- `python sweep.py '{"turn":[0.5,1,2]}' v` - try parameter values (see `P` in est_new.py).
- `python luacheck.py ..\..` - crude block/bracket balance check of the addon's Lua files.
