# R14 Dynamic Exploration — Map Test Report

Date: 2026-08-19 (KST)  
Engine: Godot 4.7.1 Stable Standard / Compatibility Renderer

## Automated map simulation

Command:

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path godot res://chapter_map/tests/map_test_runner.tscn
```

Result: **97 / 97 PASS, 0 FAIL**.

The suite includes the existing Chapter 1 map, path, save, encounter, treasure, reward-growth, and battle-hash checks, plus the R14 patrol, awareness, wait, relay, event, intel, and exploration-completion checks.

## R14 coverage

- Deterministic LOOP, PING_PONG, and GUARD_AREA patrol paths.
- Save/reload of patrol coordinates and patrol indices.
- Offscreen pawn rendering policy with continuous lightweight logical simulation.
- Distance, elevation, and blocker-aware UNAWARE / SUSPICIOUS / ALERT awareness.
- Stable single encounter owner when two hostiles contact the party simultaneously.
- WAIT advances only map simulation; the party axial coordinate is unchanged.
- Relay activation, discovery expansion, active-relay fast travel, and no progression bypass.
- One-shot event resolution, saved choices, one-shot rewards, and stored intel.
- Detailed exploration completion without revealing undiscovered hidden totals.
- Existing BattleSimulation final-state and BattleEvent hashes remain unchanged.

## Regression

`tools/powershell/VALIDATE_ALL.ps1` after the R14 change:

- Static data audit: **60 / 60 PASS**
- Godot runtime: **92 / 92 PASS**
- Character EXP total: **905,520**
- Character credit total: **412,400**
- Weapon EXP total: **144,330**

No battle formula, growth curve, reward table, or stage count was changed by R14.
