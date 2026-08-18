# Data Audit

Status: **PASS — 60/60 static data/source/policy checks**

- Result: `reports/static_validation.json`
- Player characters: 8 (GUARDIAN 1, VANGUARD 1, ASSAULT 2, ARTILLERY 1, SPECIALIST 2, MEDIC 1)
- Skills: 24; every character has exactly NORMAL 10 / PASSIVE 10 / ULTIMATE 5 values.
- Common weapons: 12; character-exclusive weapon records: 0.
- Enemies: normal 6, elite 3, boss 2; boss phases and patterns are data-defined.
- Chapter 1: NORMAL 10, HARD 5; N10/H5 boss flags and at least one reward per stage verified.
- Scenarios: prologue/main 7 plus personal 2, total 9; commands, jumps and KO/EN localization references resolve.

## Curves and regressions

- Character curve: 100 rows; 1→100 EXP 905,520; credits 412,400.
- Account curve: 100 rows.
- Weapon curve: 60 rows; 1→60 EXP 144,330.
- Negative growth costs: 0; positive stat reversals: 0.
- B0–B5 and T1–T6 caps: PASS.
- Affinity matrix: exact externalized 3×3 values PASS.
- All breakthrough, skill and weapon materials are available from repeatable Chapter 1 rewards.

## Asset and policy data

- Canonical bridge manifest: `godot/assets/generated_import/import_manifest.json`.
- Factory files: 93 resolved and SHA-256 matched; second sync copied 0 and reused 93.
- License ledger: 109 records (93 factory outputs, 15 preserved/generated combat bundles, 1 font), all with SHA-256.
- Human/humanoid playable policy: FEMALE, ADULT, maximum non-explicit attire; enemies are genderless nonhuman.
- Krea2 is excluded; selected local production models are build-time only.

The static audit is separate from the 87-assertion Godot runtime suite.
