# Final R7 SRPG Map Visual QA Report

## Evidence reviewed

- Blender R1, R2, R3 and R4 camera renders.
- R4 tile library and full-map contact sheets.
- Actual Godot Web map before selection, route preview, post-battle reveal and
  844×390 responsive capture.
- Existing real-time battle and result captures reached from the map flow.

## Reference abstraction

The supplied still was used only to identify high-level visual grammar: an
elevated coastal hex island, readable forest density, bright selected-node
rings, a leader pawn and a right-side encounter panel. R4 uses the independent
Lanternline relay-forest palette, geometry, markers, characters and labels.

## Revision findings

- R1: rejected; disconnected kit-preview impression.
- R2: rejected; connected map but underlit and sparse.
- R3: rejected; readable lighting, insufficient forest/surface density.
- R4: current candidate; adds clustered trees, moss/glow accents, coastal foam,
  brighter unrevealed terrain and corrected imported component scale.

Actual Web QA found and fixed three integration defects before the R4B build:
near-black unrevealed terrain, oversized white foam cubes caused by discarded
Blender node scale, and the START label fully covering the squad pawn.

## Score

R4B: 83/100. Required threshold: 88.

No clipping, z-fighting, blocked-route traversal, map-bound escape, panel/button
overlap, mismatched return coordinate or copied-reference impression was found.
The score remains below target because the map-pawn lacks the contracted full
IDLE/WALK/ARRIVE/SELECT directional animation and the terrain/VFX transition
density is not yet at the premium bar. These are not concealed as PASS.

PRODUCTION_APPROVED: WAITING_USER_APPROVAL.

## Independent GPT Web review

On 2026-08-18, five actual Web screenshots plus the internal scorecard and this
report were submitted to ChatGPT Web for an evidence-only independent review.
The independent result was stricter than the internal review:

- Static visual quality: 63/100, FAIL.
- Hard failure: primitive test-map impression.
- Squad movement/grounding: UNVERIFIED without video.
- Map/battle transition motion: UNVERIFIED without video.
- Direct reference-copy risk: low, but project-specific map identity is weak.

This independent opinion does not replace executable QA, but it invalidates any
claim that the current still-image evidence meets the 88-point production-art
gate. The full result, remediation priorities, evidence list, and conversation
URL are recorded in `reports/r7_srpg_map/GPT_WEB_INDEPENDENT_VISUAL_REVIEW.md`.

CURRENT STATIC VISUAL VERDICT: FAIL.
PRODUCTION_APPROVED: WAITING_USER_APPROVAL.
