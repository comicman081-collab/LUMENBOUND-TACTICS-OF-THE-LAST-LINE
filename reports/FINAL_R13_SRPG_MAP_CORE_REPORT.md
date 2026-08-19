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
- Total bytes: `42,009,389`
- PCK: `r7_current_aab97113dc33.pck`, `31,480,784` bytes
- PCK SHA-256: `AAB97113DC3308072C37E2F1D424CDB4D6E91262A3C8FAD31B8BBCB605896436`
- This artifact replaces the same fixed R7 output directory; no versioned release directory or public deployment was created.

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
- `reports/r13/screenshots/R13_FINAL_HINT_ENVIRONMENTAL.png`
- `reports/r13/screenshots/R13_FINAL_REWARD_CLARITY.png`

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
| External GPT-web visual re-review | PASS — in-app ChatGPT review, 2026-08-19 |

## In-app GPT-web visual re-review

The user explicitly authorized the in-app ChatGPT exchange and requested it be sent. The reviewer received the actual Web captures rather than editor renders.

- `HIDDEN TREASURE VISUAL / EXPLORATION UX`: **PASS**. The reviewer confirmed that the HINT screen exposes no exact ring, chest, selection state, or automatic route; the environmental crystal/prop cue remains the only clue before the close-range reveal.
- `REWARD / GROWTH HUMAN READABILITY`: **PASS**. The reviewer confirmed the high-contrast two-column reward cards, pre/post inventory values, separate NEW-0 state, and separate current-growth summary have a clear visual hierarchy.
- Non-blocking P1 follow-up: add a very subtle 1–2 second brightness pulse or light particle to the hinted environmental prop. Do not restore an exact location marker.

No public deployment, git push, release upload, or hosted publication was performed.
