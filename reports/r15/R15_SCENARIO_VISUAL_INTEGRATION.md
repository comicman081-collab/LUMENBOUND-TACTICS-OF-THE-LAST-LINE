# R15 Scenario Visual Integration Audit

## Result

- Scenario definitions: 9 / 9 compiled and executable
- Chapter progression triggers: 6 / 6 preserved and resolving
- Relationship archive bindings: Maeru → CHR001, Iri → CHR008
- Referenced portrait assets: 4 distinct runtime IDs, all resolved
- Referenced background/CG assets: 4 distinct runtime IDs, all resolved
- Missing Korean or English localization keys: 0

## Runtime mapping

| Scenario | Background / CG | Portrait | Expression-state progression |
| --- | --- | --- | --- |
| SCN_PROLOGUE | bg_lantern_tunnel_dev | portrait_chr001_dev | SERIOUS → BATTLE_FOCUS |
| SCN_CH01_INTRO | bg_lantern_tunnel_dev | portrait_chr001_dev | NEUTRAL → SERIOUS → BATTLE_FOCUS |
| SCN_CH01_MID_A | bg_ch01_glass_rail_story | portrait_chr002_dev | ALERT → RELIEVED |
| SCN_CH01_MID_B | bg_ch01_glass_rail_story | portrait_chr003_dev | SERIOUS → CONFIDENT |
| SCN_CH01_MID_C | bg_ch01_signal_cathedral_story | portrait_chr008_dev | SERIOUS → CONCERNED → BATTLE_FOCUS |
| SCN_CH01_PREBOSS | bg_ch01_signal_cathedral_story | portrait_chr001_dev | ALERT → SERIOUS → BATTLE_FOCUS |
| SCN_CH01_OUTRO | bg_lantern_tunnel_dev / cg_ch01_pilot_teamwork | portrait_chr001_dev | RELIEVED → SMILE |
| SCN_REL_MAERU | bg_lantern_tunnel_dev | portrait_chr001_dev | NEUTRAL → SAD → SMILE |
| SCN_REL_IRI | bg_lantern_tunnel_dev | portrait_chr008_dev | SMILE → SERIOUS → SMILE |

The previous SCN_REL_IRI error (portrait_chr001_dev and SPEAKER_MAERU) is removed from both source JSON and compiled game data.

## Localization

The nine title keys now have Korean and English titles. The 27 dialogue keys have Korean canonical text and non-placeholder English text. SPEAKER_ROAN, SPEAKER_NARIN and SPEAKER_IRI were added so displayed speaker identity matches the selected portrait.

## Verification

- `python tools/generate_data.py`: PASS; 8 characters, 24 skills, 11 enemies, 15 stages, 9 scenarios; growth regression totals unchanged.
- Godot `res://tools/data_compiler.gd`: PASS; source hashes and compiled JSON verified.
- `RUN_R15_TESTS.ps1`: 33 / 33 PASS, including the new nine-scenario visual contract and Iri identity assertions.
- `RUN_HEADLESS_TESTS.ps1`: 105 / 105 PASS, including ScenarioRunner validation, choice persistence, resume state, localization, and asset resolution.
- `validate_static.py`: scenario, localization, asset, content-policy and growth checks PASS. Overall run was 59 / 60 because the pre-existing repository-wide `no HTTP runtime code` rule currently detects the Web-soak HTTP instrumentation; this failure is outside the scenario changes.

## Remaining art limitation

The current R15 art set contains one production-candidate static portrait bitmap per character, not six facial-expression bitmaps. ScenarioRunner now executes and persists correct expression states, but the visible face remains the character's base static portrait until expression-specific art files are authored and registered. No expression variant is falsely reported as present.
