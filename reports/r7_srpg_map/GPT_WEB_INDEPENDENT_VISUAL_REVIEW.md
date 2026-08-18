# GPT Web Independent Visual Review

- Review timestamp: 2026-08-18T15:58:08+09:00
- Destination: ChatGPT Web, signed-in user account
- Conversation: https://chatgpt.com/c/6a840193-1fb0-83e8-997f-7e5c17fdc722
- Evidence transmitted: five actual in-app Web screenshots, `MAP_VISUAL_SCORECARD.csv`, and `FINAL_R7_SRPG_MAP_VISUAL_QA_REPORT.md`
- Scope: independent visual critique only; this is not an authoritative test runner or production approval.

## Evidence set

1. `screenshots/01_ch01_map_full.png`
2. `screenshots/04_route_preview.png`
3. `screenshots/08_existing_battle.png`
4. `screenshots/10_return_to_map.png`
5. `screenshots/15_mobile_844x390.png`

## Independent verdict returned by GPT Web

- STATIC VISUAL QUALITY: **FAIL — 63/100**
- SQUAD PAWN MOVEMENT/GROUNDING: **UNVERIFIED**
- MAP <-> BATTLE TRANSITION MOTION: **UNVERIFIED**
- HARD FAILURE: **YES — primitive test-map impression**
- 88-point visual gate: **FAIL**
- PRODUCTION VISUAL APPROVAL: **FAIL**
- FUNCTIONAL QA: the reported 200/200 automated pass does not add points to visual QA.

## Independent score

| Category | Max | GPT Web | Verdict |
|---|---:|---:|---|
| Overall composition and terrain flow | 15 | 12 | FAIL |
| Hex terrain and elevation finish | 15 | 8 | FAIL |
| Terrain and node readability | 15 | 11 | FAIL |
| Squad pawn movement and grounding | 15 | 8* | UNVERIFIED |
| Camera and selection feedback | 10 | 7 | FAIL |
| Stage panel integration | 10 | 7 | FAIL |
| Map/battle transition | 10 | 4* | UNVERIFIED |
| Originality and project style | 10 | 6 | FAIL |
| Total | 100 | 63 | FAIL |

`*` A numeric estimate for the visible static portion only. It must not be treated as a motion PASS.

## Main findings

- The island silhouette and main progression axis read clearly, but repeated extruded hexes, simple sphere/block props, weak cliffs/coast/forest-floor differentiation, and limited elevation language make the scene look like a functional tactical-map prototype.
- The route preview is too weak. The selected ring, route ribbon/arrow, and reachable/unreachable contrast do not clearly communicate the planned move without relying on panel text.
- The stage panel avoids physical overlap but reads closer to a development inspector than a finished encounter UI because of dense small text, scrollbar emphasis, and weak integration with the game world's visual language.
- The existing real-time battle has substantially higher visual density and finish than the map. This creates a strong style and production-stage mismatch.
- The post-battle still shows progress-state change, but exact pawn-position restoration and movement-state preservation cannot be proved from still images.
- The 844x390 layout fits without obvious overlap, but is not sufficiently readable. It appears to be a scaled-down desktop composition rather than a purpose-built mobile landscape layout.
- No direct copying of the supplied commercial reference was identified. Copying risk was rated low, but the map's generic low-poly hex language was also judged insufficiently distinctive.

## Highest-impact remediation requested

1. **P0 — Rebuild hexes as terrain:** add authored cliff lips, rock sides, forest floor/root forms, coastal edges, shallow-water/foam forms, ruins, and meaningful 2–3-level elevation silhouettes. This is the primary action for removing the hard failure.
2. **P0 — Integrate nodes and routes into the world:** use strong selected plinth/ring, route ribbon, directional arrows, unreachable desaturation, and screen-space label collision/offset so labels do not compete with the pawn.
3. **P1 — Prove pawn contact and full motion with video:** show anchor/height snapping, directional walk, arrival settle, selection reaction, direction changes, elevation traversal, battle entry, and return.
4. **P1 — Connect map and battle art language:** bring the battle's teal crystalline/industrial and amber relay motifs into map geometry, landmarks, and transition VFX.
5. **P1 — Build a separate mobile landscape composition:** use a collapsible bottom sheet/slide-over, preserve map area, and enforce readable node labels and action buttons instead of globally shrinking desktop UI.

## Reconciliation with the internal score

GPT Web judged the internal 83/100 score to be generous based on the submitted in-game screenshots. The largest disagreements were terrain finish (12 -> 8), node readability (14 -> 11), stage panel integration (9 -> 7), and originality/style consistency (8 -> 6). Movement and transition scores were rejected as verified evidence because no video was supplied.

The project verdict therefore remains:

- Functional/runtime evidence: **PASS (200/200 reported and locally verified before this review)**
- Static map visual gate: **FAIL**
- Motion/transition visual gate: **UNVERIFIED**
- Production approval: **WAITING_USER_APPROVAL / NOT GRANTED**

