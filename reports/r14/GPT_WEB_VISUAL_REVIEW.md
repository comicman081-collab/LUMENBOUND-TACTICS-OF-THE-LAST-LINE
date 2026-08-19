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

## External re-review 1 — current evidence

The first corrected Web evidence was sent to the same collaboration thread.
Its verdict was **78/100 — FAIL**: raw runtime IDs, the profile-card-like
leader token, and their ground contact were accepted, but the reviewer still
classified the terrain/shoreline as a commercial-visual hard failure.

The current unsent local correction deliberately addresses only those remaining
visual findings:

- Replaced visible per-cell hex-prism ground with one shared-vertex connected
  terrain surface. Axial cells remain the simulation source of truth, but their
  former render meshes are hidden except for selection/route feedback.
- Removed per-elevated-cell strata/platform clusters. Terrain height now reads
  through continuous slopes and sparse asymmetric rock outcrops.
- Added deterministic boundary-aware coast foam/reef placement, sparse coastal
  signal debris, and stronger low-cost tide bands; no new gameplay resources or
  map rules were introduced.
- Reduced the desktop stage detail from a full-height inspector to a contextual
  card. It appears only on selection and retains scroll access for longer data.

Current local evidence still requires a new GPT Web visual re-review. Therefore
the status remains **VISUAL PASS: NOT CLAIMED**.

## External re-review 2 — causeway and shore correction

The same GPT Web thread reviewed one actual 1280×720 R7 Web overview after the
connected shallow-water ribbon, route causeway, and encounter socket changes.
Only that single attachment was used as evidence.

- Terrain / shoreline commercial hard failure: **NO / CLEARED**
- Encounter-map-pawn floating hard failure: **NO / CLEARED**
- Terrain continuity: **PASS**
- Shoreline readability: **PASS**
- Signal road / infrastructure readability: **PASS**
- Technical hard failure: **NO**
- Visual score: **87/100 — FAIL against the 88 gate**

The external reviewer identified no remaining P0 from the supplied overview.
The one-point gap is P1 visual polish only: a broad deep-water field still
reads flatter than the connected coast. The reviewer recommended directional
water highlights, minor darkening away from shore, and two or three large reef
silhouettes rather than more small foam particles.

### Local R7 follow-up pending re-review

The current local R7 overwrite adds exactly that P1-only follow-up:

- broader directional current bands and a controlled deep-water falloff in the
  Web-compatible water shader;
- three large, non-traversable reef silhouettes with sparse foam at the outer
  water field;
- no gameplay, map data, reward, save, or combat-state changes.

The follow-up was rebuilt into `builds/web_r7_current_release` and inspected in
the local Web runtime. A subsequent external review is still required before
claiming the 88-point visual gate as passed.
