# Test Report

Date: 2026-08-17

## Automated results

- Static data/source/policy: **60 PASS / 0 FAIL**.
- Godot 4.7.1 headless runtime: **87 PASS / 0 FAIL**.
- Combined assertions: **147 PASS / 0 FAIL**.

Coverage includes IDs/references/localization, 10/10/5 arrays, all curves and regressions, N10/H5 content, 560 active unit frames, 56 projectile frames, deterministic hashes, varied seeded RNG, shield/taunt/silence/stun/status rules, manual ultimate targeting, speed/pause equivalence, pooling, level/breakthrough/weapon limits, atomic multi-sweep, story resume, save backup/recovery/migration and duplicate-reward protection.

## Runtime and visual QA

- Source-project Compatibility render capture: **PASS**, 11 PNGs at 1920×1080.
- Final Web HTML Release in a real browser: **PASS** for title → home → story/choice → formation → stage/detail → live battle → pause → result → growth → save/reload recovery.
- Browser console errors/warnings: **0** in the final Release run.
- Visible persistence: character level/skill/weapon changes survived reload; title reported `SAVE: primary`.
- Godot root-certificate-store message: observed on Windows headless runs; nonfatal and unrelated to project-local save/log writes.

## Load test

- Kind: `HEADLESS_SIMULATED_LOAD_TEST`.
- Actual runtime model: 5 allies, 20 simultaneous enemies, 100 projectiles, 100 damage texts.
- Duration: 18,000 ticks / 600 simulation seconds.
- Pool recycling: PASS; retained event-log entries: 0.
- Static-memory delta: 68,024 bytes, under the 16,777,216-byte threshold.
- This is not an actual wall-clock ten-minute visual/browser soak; that item remains UNVERIFIED.

## Unverified / excluded

- Android APK/device QA: not built by current user instruction.
- Windows native executable QA: not targeted in the current HTML-only phase.
- Real audio playback: no production audio files available.

DEV cutout sprites/projectiles passed technical visual integration only and are not final production-art approval.
