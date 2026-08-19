# R13 SRPG Map Core Report

## Scope completed

- Unclear Chapter 1 encounters render concrete enemy MapPawns from the existing stage/enemy IDs. NORMAL, ELITE, and BOSS use distinct threat treatment.
- Selecting an encounter previews a deterministic route; a route ends at the first unresolved hostile.
- The squad must reach the enemy before the existing real-time battle begins. Selecting an enemy alone does not start combat.
- Victory removes the hostile pawn, marks the relay/clear state, unlocks only the next valid route, and returns to the same map. Defeat/abandon preserves the hostile and restores the pre-contact map position.
- Visible treasure and fixed-seed hidden treasure are placed on optional side branches. Hidden treasure progresses `UNDISCOVERED → HINTED → REVEALED → CLAIMED` through proximity.
- Encounter and treasure rewards share `RewardResolver`; the result screen now shows each item’s delta and pre/post inventory quantity.
- `GrowthAffordabilityAnalyzer` computes false-to-true level, breakthrough, skill, weapon-level, and weapon-tier opportunities without double-counting shared materials.
- Map save data now keeps party axial position, encounter state, treasure state, reveal state, pending encounter, and camera anchor; v3 saves migrate into the v4 map schema.
- Result navigation keeps its action rail visible at the bottom of the landscape viewport.
- Full Korean font packaging and Korean localization are present in the Web build.

## Local Web artifact — not deployed

- Directory: `builds/web_r7_current_release`
- Build files: 18
- Total bytes: `42,008,285`
- PCK: `r7_current_a7f7ca803ea6.pck`, `31,479,680` bytes
- PCK SHA-256: `A7F7CA803EA65E82BB3D2A731656B261C34209E1385D9E12346BC28DA5568FED`
- WASM SHA-256: `52E161B049AF1696730D31DE0846B3B34CBE79275A65EA9B279B4C62CA299331`

## Actual in-app browser evidence

The following are real Web screenshots, not editor renders:

- `reports/r13/screenshots/01_MAP_ENEMY_VISIBLE.png`
- `reports/r13/screenshots/02_ENCOUNTER_SELECTED.png`
- `reports/r13/screenshots/04_PARTY_APPROACH.png`
- `reports/r13/screenshots/06_EXISTING_REALTIME_BATTLE.png`
- `reports/r13/screenshots/07_REWARD_ITEMS.png`
- `reports/r13/screenshots/09_MAP_AFTER_CLEAR.png`
- `reports/r13/screenshots/10_VISIBLE_TREASURE.png`
- `reports/r13/screenshots/11_HIDDEN_TREASURE_HINT.png`
- `reports/r13/screenshots/12_HIDDEN_TREASURE_REVEALED.png`
- `reports/r13/screenshots/13_TREASURE_REWARD.png`
- `reports/r13/screenshots/14_RELOAD_RESTORED.png`

The final browser run had `0` captured console errors and `0` captured console warnings.

## Verification status

| Area | Result |
|---|---|
| R13 map tests | PASS — 73/73 |
| Existing static tests | PASS — 60/60 |
| Existing Godot runtime tests | PASS — 92/92 |
| In-app Web N01 end-to-end | PASS |
| Exact-once reward / save recovery | PASS |
| Deployment / publishing | NOT PERFORMED |
| External GPT-web review message | NOT SENT — requires confirmation immediately before external transmission |

No public deployment, git push, release upload, or external message was performed in this R13 validation pass.
