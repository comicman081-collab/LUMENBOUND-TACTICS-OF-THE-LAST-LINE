# Long-range SRPG MVP completion audit — 2026-08-25

This audit separates implemented authority from actual runtime evidence.  A
passing unit test is not presented as a visual Web pass, and a Development
fixture is not presented as a normal Release progression proof.

| Objective requirement | Current implementation evidence | Verification evidence | Status |
|---|---|---|---|
| Three supplied reference videos analysed locally | `REFERENCE_VIDEO_METADATA.csv`, `REFERENCE_INTERACTION_ANALYSIS.md`, `MVP_REFERENCE_IMPLEMENTATION.md` | Local video metadata/hash and extracted interaction notes | PASS |
| Independent long Chapter 1 SRPG exploration map | `data_source/chapter_maps/CH01_MAP.json`, `chapter_map/` runtime and 96-hex macro world | 249 map assertions, including terrain, route, camera and streaming contracts | PASS |
| Movement limit per map pulse | `map_simulation.gd`, `chapter_map_progress.gd`, `CH01_MAP.json` movement config | `PULSE_01` through `PULSE_04`; direct historical Release 5/7 → WAIT → 7/7 observation | PASS |
| Level and item movement expansion | Account milestones and optional `EXPEDITION_ROUTE_MODULE_A/B` rewards in map data | `PULSE_REWARD_01` through `PULSE_REWARD_06`; historic direct Release A-module claim/reload observation | PASS |
| Visible and hidden side exploration | Treasure, relay, event and patrol definitions in `CH01_MAP.json` | Treasure/reveal/exact-once/save map tests and R15 transaction tests | PASS |
| Event enemy has a grounded `!` marker | Special encounter definitions for Vera/Toa and companion pawn rendering | `EVENT_PAWN_01` through `EVENT_PAWN_RUNTIME_03`; Development physical-contact evidence | PASS |
| Event contact produces a special event before ordinary realtime combat | `map_simulation.gd`, `chapter_map_screen.gd`, localized event contact card | event transaction tests; historical N04/N08 physical-contact evidence | PASS |
| Immediate companion recruitment | Vera / `CHR006` outcome is `IMMEDIATE_JOIN` | `EVENT_PAWN_03/04`, R15 full-route transaction coverage | PASS |
| Deferred companion recruitment | Toa / `CHR007` outcome resolves only after its authored later stage | `EVENT_PAWN_05/06`, R15 full-route transaction coverage | PASS |
| Companion SD, rather than generic hostile, on companion event map node | Character `MAP_IDLE` asset resolution path is used by special pawn creation | `EVENT_PAWN_RUNTIME_01/02/03` for N04 and N08 | PASS |
| Existing realtime five-unit battle is preserved | Existing `BattleSimulation` and view remain the sole combat authority | core deterministic, map battle-roundtrip and R15 stage tests | PASS |
| Reward → growth → map return → save recovery | shared result/reward transactions, growth plan builder and atomic saves | fresh N01→N10 progression simulation and 49 R15 tests | PASS |
| Chapter 1 normal/hard balance targets | `R15_CH01_BALANCE_MATRIX.json` from the shipping `BattleSimulation` | 90 cells × 200 seeds = 18,000 runs; target audit 13 PASS / 0 FAIL / 0 UNVERIFIED | PASS |
| Godot 4.7.1 Web build logic regression | fixed R7 Web build scripts and current in-place PCK | static 70/70, core 165/165, map 249/249, R15 49/49, R16 26/26 | PASS (logic) |
| Current PCK N01 browser loop after latest BGM repack | fixed-name `builds/web_release/index.pck` | Isolated Web save: title → home → Chapter 1 intro → map → N01 route preview → two movement pulses with WAIT → physical contact → realtime battle → victory/reward → map return → browser refresh/recovery | PASS (N01 E2E) |
| Current PCK full browser flow after latest BGM repack | fixed-name `builds/web_release/index.pck` | N01 E2E is current and verified; an entire N01→N10 + HARD browser completion has not been repeated in this audit | UNVERIFIED |
| Current PCK physical Release HARD H02→H05 sequence and H05 reload | Gameplay rules and Dev route coverage are implemented | Normal Release evidence remains stamina-gated; Development evidence is supporting only | UNVERIFIED |
| GPT Web event-design review | Existing review history in `GPT_WEB_REVIEW_RESPONSE_20260825.md`; latest request updated in `GPT_WEB_REVIEW_REQUEST.md` | A fresh message is prepared but not sent in this turn because message sending requires action-time confirmation | READY FOR REVIEW |
| Deployment/upload | No deployment script has been invoked | Working tree and reports retain local artifact paths only | NOT PERFORMED (intentional) |

## Current local verification aggregate

| Suite | Executed | Pass | Fail |
|---|---:|---:|---:|
| Static | 70 | 70 | 0 |
| Godot core/runtime | 165 | 165 | 0 |
| SRPG map | 249 | 249 | 0 |
| R15 content/results | 49 | 49 | 0 |
| R16 presentation | 26 | 26 | 0 |
| **Total** | **559** | **559** | **0** |

## Current Godot Compatibility visual capture

`CAPTURE_VISUAL_QA.ps1` was rerun on Godot 4.7.1 Compatibility and completed
with exit code 0 after writing 12 fresh 1920×1080 PNGs (`title`, `home`,
`story`, `formation`, character/growth, chapter map, selected encounter,
battle, pause and result) to `reports/screenshots/`.  The manifest records
`gl_compatibility` and 11,643,573 total PNG bytes.  Visual inspection included
the long map and the five-party battle presentation.

The editor-side capture process emitted one CanvasItem RID and two ObjectDB
leak warnings during engine teardown.  Those warnings are captured as a
non-blocking **tooling limitation**; this result is a Godot rendered-frame
check, not Web browser QA and not a claim of zero renderer warnings.

## Browser-control note

On this audit date the in-app Browser could create and close a single temporary
tab, but its returned tab binding referenced an already-closed internal ID when
asked to navigate.  The temporary tab and local HTTP server were closed after
each attempt.  This is recorded as a tooling limitation, not as a release
runtime pass or failure.

## Current isolated Web E2E — 2026-08-25

The current fixed-name R7 Web Release was served locally only on port 8078
and exercised in one in-app Browser tab with the opt-in, isolated
`r15-save-sandbox` namespace.  The verification intentionally did not read or
modify the production save namespace.

Observed flow: title → home → Chapter 1 intro → 96-hex map.  The first
encounter route exhausted the 7/7 movement pulse before contact; `WAIT`
refilled the pulse without changing the party position.  A second confirmed
movement entered the ordinary realtime five-unit SD battle.  N01 ended in
victory at 15.47 seconds with five survivors; the result showed per-item
inventory deltas and returned to the map with N02 unlocked.  After a full
browser refresh and normal title/home re-entry, the isolated save restored N01
clear, N02 as the next encounter, 4% exploration, the party location, and the
remaining 6/7 movement state.

The Web console recorded zero errors and zero warnings for this run.  After a
trusted click, the local lobby BGM was confirmed as a verified streaming
playback (89.94-second local WAV, loop configured, no failed starts).  The tab
and its exact local server process were closed after the check; port 8078 was
then verified closed.

No deployment, upload, production-art approval, mobile-device QA, or human
audio mix approval is claimed by this audit.
