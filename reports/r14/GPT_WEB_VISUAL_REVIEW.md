# GPT Web Visual Review — R14 Initial Gate

Review destination: existing GPT Web collaboration conversation (`게임 시스템 구축 계획`)

Review scope: actual local Web screenshots from the R14 SRPG map flow. The
review was asked to separate functional-system evidence from visual approval.

## Initial external result

- System / interaction structure: **PASS**
- Visual UX gate: **FAIL** (review score: 71/100)
- Technical hard failure: no
- Commercial visual hard failure: yes, due to player-facing runtime IDs.

The reviewer confirmed the visible enemy → route → squad approach → contact →
existing real-time battle → result → map return flow, as well as the initial
Wait affordance. Relay, event, fast-travel, intel, and an actual Wait motion
result were not evidenced in the initial screenshot set and remain explicitly
unverified by that review.

## Required P0 corrections

1. Remove internal IDs from player-facing rewards, battle results, growth,
   inventory, party summaries, and related labels.
2. Replace the procedural field of isolated hex slabs / near-black cliff walls
   with connected terrain formations, varied strata, and visible authored
   terrain relief.
3. Replace the large profile-card-like player token with a map-scale SD pawn
   that shares the hostile pawn visual language.
4. Make Wait causal in the release view: visible patrol step, short after-signal,
   and completion feedback.

## R7 overwrite corrective pass

The corrective pass is intentionally being written to the existing R7 runtime
and port, not to a parallel numbered release.

- `app_shell.gd`: runtime item/character/enemy/weapon IDs are resolved through
  localized display names; party summary and stage fallback UI now do the same.
- `chapter_map_screen.gd`: leader uses the combat SD idle atlas at map-pawn
  scale rather than the profile icon; Wait now announces affected patrols and
  animates an after-signal between patrol positions.
- `tools/blender/build_ch01_terrain_relief.py`: project-owned Blender 4.5.11
  headless source and GLB output for broad forest / ruin / coast relief and
  rock ridges; `asset_share` source is untouched.
- connected-relief placement, lower individual cell wall height, and
  compatibility fill lighting are being checked in the rebuilt Web runtime.
- `chapter_route_minimap.gd`: release minimap labels are Korean.

## Verification status

After the corrective Web capture is ready, this exact GPT conversation must be
sent the revised screenshots and asked for a fresh visual gate. Until that
review returns, **VISUAL PASS is not claimed**.

