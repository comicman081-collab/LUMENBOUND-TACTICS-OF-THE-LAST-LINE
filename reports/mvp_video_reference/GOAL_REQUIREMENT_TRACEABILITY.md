# Long-map event-companion MVP — requirement traceability

Date: 2026-08-25 (Asia/Seoul)

This is a completion-oriented evidence map for the active MVP objective. It
does not treat an automated assertion as a substitute for a broader browser
claim and does not mark the MVP complete while any listed evidence is pending.

| Requirement | Current implementation authority | Direct verification | Current status |
|---|---|---|---|
| Analyze all three supplied reference videos locally | `REFERENCE_VIDEO_METADATA.csv` records source path, dimensions, decoded duration, frame rate and SHA-256 for V1–V3. `REFERENCE_VIDEO_INTERACTION_ANALYSIS.md` records only abstract interaction lessons. | The three original files were rehashed; no source video/keyframe was copied into Godot, Web output or review package. | COMPLETE / LOCAL-ONLY |
| Independent long Chapter 1 SRPG exploration map | `data_source/chapter_maps/CH01_MAP.json`, `macro_world_generator.gd`, `chapter_map_screen.gd`. | Map tests `MACRO_SORT_01..04`, macro span, route-surface and camera-ground coverage assertions; map report evidence. | IMPLEMENTED / TESTED |
| Turn-like movement limit that grows from account progress and owned items | `map_exploration_service.gd::movement_capacity`, stored `movement_points`, `movement_points_max`, `exploration_pulse`; route-module data from map definition. | `PULSE_01..04`, `PULSE_REWARD_01..06`, and `PULSE_UI_01`; actual Release detail now exposes base / account-level / owned-module sources. | IMPLEMENTED / TESTED + PARTIAL RELEASE E2E |
| Physical squad travel before encounter | `chapter_map_screen.gd::_move_along`, `AppState.prepare_map_encounter`. | Contact/return transaction tests and current Release N01, N04, H01/H02 evidence. | IMPLEMENTED / TESTED + RELEASE E2E |
| Existing five-person realtime SD battle stays the battle authority | `BattleSimulation`, `BattleView`, map-to-battle adapter. | Map runner proves final state/event hashes unchanged by traversal; R15/core battle tests. | IMPLEMENTED / TESTED |
| Event targets visibly use `!` instead of generic hostile notation | Chapter map `event_encounters` requires `marker: BANG`; map screen renders `! 특별 조우`; event pawns have a raised, pulsing marker. | Loader validation plus `EVENT_PAWN_01`, `EVENT_PAWN_RUNTIME_01..03`; N04/N08 browser captures. | IMPLEMENTED / TESTED + RELEASE E2E (N04) |
| Event target contact presents a special event, then enters ordinary realtime battle | `AppState.pending_map_special_event`, `CompanionEventContactCard`, presentation-only 1.85 second hold; `entry_type: EVENT_CONTACT`. | `EVENT_PAWN_02A..09`; browser N04 special-signal capture. | IMPLEMENTED / TESTED + RELEASE E2E (N04) |
| Event target is rendered as its eventual companion SD, not a generic monster | Event data immutable `character_id`; map screen resolves that character's `MAP_IDLE` pack. | `EVENT_PAWN_RUNTIME_02` checks texture/source identity for N04/CHR006 and N08/CHR007. | IMPLEMENTED / TESTED |
| Some event companions recruit immediately on victory | `EVENT_RESCUE_VERA` at NODE_N04: `IMMEDIATE_ON_VICTORY`. | `resolve_event_encounter_victory`; `EVENT_PAWN_03..04`; Release result/map-return/reload evidence. | IMPLEMENTED / RELEASE E2E |
| Some event companions recruit later | `EVENT_RELAY_TOA` at NODE_N08: `AFTER_STAGE_CLEAR`, recruiting after N09. | `EVENT_PAWN_05..06`, source/result-art checks; Development N08/N09 E2E captures. | IMPLEMENTED / TESTED + DEVELOPMENT E2E |
| Contact screen explains immediate vs later recruitment before battle | Event JSON `contact_outcome_key`; `AppState` copies the immutable field into pending presentation; contact card displays **조우 결과**. | `EVENT_PAWN_02B`, `EVENT_PAWN_09`; current localization audit. | IMPLEMENTED / TESTED |
| Map, event, recruitment and party state survive reload without duplicate rewards | Map progress stores map coordinates, encounter/recruit states and pending transactions; `SaveService` uses atomic primary/backup write. | Map result/refresh tests, N04 release refresh and H02 defeat-refresh E2E. | IMPLEMENTED / TESTED + PARTIAL RELEASE E2E |
| Mid-story dialogue and open choices survive a Web tab close/reopen | `ScenarioState.snapshot()` now retains `current_line` and `waiting_for_choice`; `AppShell` atomically persists every interactive story checkpoint. | Core checks validate dialogue/choice checkpoint wiring; after LANTERNLINE-only hand-off, actual Release Web Title→Home→Main Story reached the open choice, tab reload returned to Title, re-entering Main Story restored the same open choice, and selecting it returned Home. | IMPLEMENTED / HEADLESS-TESTED / ACTUAL-WEB-PASS |
| Web Compatibility / Godot 4.7.1 only | `project.godot`, PowerShell engine guard, Web export script. | Static engine/renderer/cache-policy check 70/70; in-place Web export. | IMPLEMENTED / TESTED |
| In-app browser visual QA without accumulating tabs | One temporary QA tab per check; local port 8078 starts hidden and is stopped after each session. | Latest title/story desktop and 390×844 portrait QA had 0 console warnings/errors; tab and port were closed after each check. | IMPLEMENTED / CURRENT QA POLICY |
| GPT Web collaboration on event design | `GPT_WEB_REVIEW_REQUEST.md` plus the existing ChatGPT Web session review record. | Event/recruitment design and the latest E2E evidence were transmitted through the existing in-app ChatGPT session; response is recorded in `GPT_WEB_REVIEW_RESPONSE_20260825.md`. | COMPLETE / FOLLOW-UP EVIDENCE REVIEWED |
| Deployment | No upload/publish/package release action is authorized. | Local `builds/web_release/` is a test artifact only. | NOT PERFORMED BY DESIGN |

## Current regression evidence

Latest direct suites after story hierarchy, choice-resume persistence and legacy-import recovery:

- static source/data: **70 / 70 PASS**
- Godot core/runtime: **165 / 165 PASS**
- SRPG map: **249 / 249 PASS**
- R15 content/progression: **49 / 49 PASS**
- R16 environment presentation: **26 / 26 PASS**
- combined source assertions: **559 PASS / 0 FAIL**

## Remaining evidence boundary

The core MVP mechanics above are implemented and continuously tested. The
following claims remain deliberately bounded rather than inflated:

1. The current Release has a fresh-save **NORMAL N01→N10** functional run and
   Release H01/H02 handling. The separate N10 Result-screen presentation is
   only PARTIAL, and no uninterrupted latest-Release **H02→H05** completion
   claim exists because the same save correctly reached the operation-power gate.
   Development-only H02→H05 coverage is recorded as supporting evidence, not a
   Release substitute.
2. The LANTERNLINE-only hand-off worker has been executed and the same-origin
   Release Title→Home reload plus the mid-story open-choice close/reopen flow
   passed in the temporary Web tab. This does not certify the broader
   N01→N10/H01→H05 continuous run.
3. A 20-minute controlled browser soak, physical mobile touch QA, listening/mix
   QA, and user production-art approval remain outside the current evidence.

The rebuilt local Web output now rotates its cache from the final PCK/WASM/JS/
HTML bytes and uses network-first navigation with an offline fallback. The
one-time LANTERNLINE-only hand-off was executed without touching save data or
other origins, followed by an actual mid-story open-choice close/reopen check.

Neither remaining boundary changes gameplay authority or Release behavior.
The broader continuous-run, soak, device-QA and approval gates remain open, so
this traceability file is not a declaration of MVP completion.

## 2026-08-25 current full-length audio delivery

The latest fixed-name Release PCK is
`builds/web_release/index.pck` (**62,791,336 bytes**; SHA-256
`148efe50fd4327b97de86b921cfe156b41626eb323ce9369c4191614053194e1`).
The source audio folder was preserved. The runtime title track no longer uses a
30-second excerpt, and the lobby/story/battle/boss streams use their complete
approximately 89.94-second source compositions with the existing two-player
1.8-second crossfade. Static/core/map/R15/R16 were rerun at **70/165/249/49/26
PASS**. One temporary current-Release tab reached Title → Home; it was closed
with its local server immediately afterward. This is a technical boot and
playback-path checkpoint, not a human audio listening/mix verdict.

## 2026-08-25 latest Release H02 checkpoint

The same Release namespace reached H02 after natural recovery and completed a
real multi-pulse route with WAIT, physical contact, automatic handoff to the
unchanged real-time battle, defeat, reward-zero handling, hostile retention,
exact pre-contact return, and reload recovery. The authored daily attempt gate
reached `3/3`. `AppState` statically contains a local-date reset path, but the
actual browser date-boundary reset remains **UNVERIFIED**. H02 victory, H03–H05,
and H05 reload therefore remain **UNVERIFIED**; Development route coverage is
not substituted. GPT Web reviewed this exact split and found no known P0 defect.

## 2026-08-25 latest Release map-capacity checkpoint

An isolated `capacity-web-r15` Release sandbox used the same current PCK and
entered Title → Prologue → Chapter 1 map in one temporary tab. The real map HUD
showed `이동 7/7`; the 96-hex long-distance terrain, squad pawn, and encounter
markers rendered. The temporary tab and local server were closed immediately.
GPT Web classified map entry, movement-capacity HUD, long-map rendering, and the
existing pulse-limit/WAIT behavior as **PASS**. This does not prove the direct
browser `EXPEDITION_ROUTE_MODULE_A/B` `+1/+1` attribution, which remains
**UNVERIFIED**. It also does not change the same-day H02 `3/3` boundary or the
H02 victory/H03–H05/H05-reload **UNVERIFIED** status.

## 2026-08-25 GPT Web event evidence boundary

The existing GPT Web session reviewed the N04/N08 event evidence and agreed
that the active MVP requirements are implemented without a new P0 defect:
N04's companion-pawn → `!` → contact card → unchanged realtime battle →
immediate recruit → map/profile return → reload chain is actual-Web PASS;
N08's authored companion identity, deferred timing and tracking presentation
are contract/Development-Web PASS. A separately isolated public-Release proof
of the N09 final roster insertion and a direct browser before/after duplicate
trigger observation remain **UNVERIFIED** rather than being inferred from the
headless assertions. This is independent of the separate H02→H05 daily-attempt
gate.

## 2026-08-25 LANTERNLINE-only cache hand-off checkpoint

The Development hand-off worker ran on the fixed local origin and requested
the worker successfully. It deletes only cache keys prefixed
`LANTERNLINE-sw-cache-` and unregisters itself. After closing that temporary
tab, the same-origin Release loaded Title→Home with the expected JS/WASM/PCK,
worker and audio worklet requests and no missing request. This closes the stale
worker prerequisite for the next story-choice check; it does not itself prove
mid-story close/reopen persistence.

## 2026-08-25 developer QA quota guard

The development-authorized build now presents HARD entries as `무제한 (DEV)`
and leaves both `hard_attempts` and stamina unchanged during QA entry. The
normal Release path still enforces and records the daily quota. Core acceptance
checks cover the exhausted `3/3` developer case; direct Release authority
execution remains intentionally separate from this DEV-only evidence.

## 2026-08-25 Release movement-source readability checkpoint

The local public Release PCK
`5609fbd93dc7df850514a09835891904344eb7ba29b59aacd23997bd12872df4`
was rebuilt in place and inspected in one temporary in-app-browser tab. At the
actual Chapter 1 NORMAL 4 detail panel, the player-facing movement copy showed
`이번 펄스 7/7 구간` followed by `기본 5 · 계정 Lv.21 +2 · 노선 모듈 +0`.
The map still rendered the long world, grounded squad pawn and existing
encounter markers; console error/warning count was 0. This is presentation
only and does not alter movement authority. The temporary tab and HTTP server
were closed immediately after the check. Direct browser before/after evidence
for claiming module α/β remains separately UNVERIFIED.

## 2026-08-25 Release route-module α actual-Web checkpoint

One ordinary local Release run at the existing NORMAL 4 map checkpoint selected
the visible side-branch supply cache and travelled there through the normal map
movement flow. The shared treasure result screen recorded `노선 확장 모듈 α +1`
and inventory `0 → 1`. Returning to the map immediately changed the player HUD
from the prior `7/7` capacity to `5/8` (two ordinary movement points had been
spent en route); the detail breakdown displayed `기본 5 · 계정 Lv.21 +2 · 노선
모듈 +1`. A browser reload restored the same `5/8` and `+1` breakdown. Browser
console errors/warnings were 0. The run used no developer authority, direct
save editing, or clock change. The temporary tab and local HTTP server were
closed afterwards.

This upgrades the actual-Web evidence for the visible module α delta and its
save restore. The hidden module β counterpart, a full `9/9` wait/refill
observation, and the independent HARD continuous-route evidence remain
UNVERIFIED.

## 2026-08-25 NORMAL corridor-continuity regression

The map regression now separately validates every normal clear-to-next-encounter
corridor (`N01→N02` through `N09→N10`) from the exact post-clear reveal state.
Each route starts at the just-cleared node, ends at the newly unlocked node,
uses only traversable hexes, and requires at least one physical step. This
prevents a future fog/reveal change from exposing a visible next-operation
marker with no selectable travel route. The direct SRPG runner passed
**244/244**, and the accompanying static/core/R15/R16 suites passed
**70/70**, **165/165**, **49/49**, and **26/26** respectively: **554/554 PASS,
0 FAIL**. This is an automated continuity guard; it does not inflate the
separate actual-Web evidence boundaries recorded above.

## 2026-08-25 Development event/render smoke

The current in-place Development Web build was opened in one isolated
in-app-browser tab. The N04 developer-only staging fixture produced the
authored special-contact card, entered the unchanged battle path, displayed
the immediate companion result with the companion portrait, and returned to
the Chapter map. This fixture is evidence that the current rendered build
still connects the special-event presentation to the normal map/battle/result
flow; it is not substituted for the existing public-Release N04 proof.

During the same check, streamed terrain residency was reduced from a radius of
20 to **16** hexes. The stream continues to follow the camera and squad, so
no map topology, reveal, pathfinding, stage authority, or saved coordinate
changed. On the actual returned map view, the visible terrain was continuous;
the Web probe reported **47 draw calls**, **93 nodes**, and **100 FPS** in two
successive five-second samples, with **0** browser warnings/errors. The
temporary browser tab and local HTTP server were closed after the check.

## 2026-08-25 Release rebuild and long-map stream smoke

The local public Release was rebuilt **in place** after the map stream-radius
presentation adjustment. The current `builds/web_release/index.pck` is
`59,321,768` bytes with SHA-256
`868a12a7713fda0e0ef282cc1a27cadca420b2179c69f06adbb4e142930f7e3c`.
One temporary in-app-browser tab then loaded that exact local Release and
executed Title → Home → Chapter 1 map. The full long-map terrain, grounded
squad pawn, main-route markers, route minimap, and interaction controls were
visible; no browser console warning or error was recorded. HTTP successfully
served the HTML, JS, PCK, WASM, worker, and related boot resources. The tab
and local HTTP server were closed immediately afterward. This was a local
verification only: no deployment, upload, or external publication occurred.

## 2026-08-25 N10 independent event-title and boss-introduction checkpoint

`CH01-N10` now owns a data-authored `presentation` block in
`data_source/chapter_maps/CH01_MAP.json`.  Its transition style, event title,
boss name, and subtitle are all localization keys; the runtime does not embed
reference-video text, art, layouts, or identifiers.  `AppState` carries this
inert presentation payload only inside the existing one-shot contact
transaction, while `app_shell.gd` renders it as an original amber signal-readout
card for 1.45 seconds before the unchanged battle handoff.

Actual Development Web verification selected the N10 boss pawn, executed the
normal physical route move, and observed the localized title `심층 신호 차단`,
threat caption, boss identity, and subtitle immediately before the existing
real-time battle result flow.  Browser console warnings/errors were `0`.  The
development-only fixture did not alter Release authority, rewards, combat data,
or save rules.  The temporary tab and server were closed after the check.

The local public Release PCK was then rebuilt in place:
`builds/web_release/index.pck`, `59,325,720` bytes, SHA-256
`e5659c49d0104aa2174e445b8bf5d38d0f843ea91b176cebce3e03215c7771bc1`.
Title → Home → Chapter 1 map smoke for that exact Release artifact produced
zero browser warnings/errors.  A direct uninterrupted public-Release N10
contact recording remains **UNVERIFIED**; this checkpoint does not claim it.

The explicit reload policy remains unchanged: a browser refresh during an
unstarted contact clears its presentation transaction, restores the squad to
the pre-contact hex, retains the hostile, and starts neither battle nor reward.
This prevents duplicate boss cards, battle entry, or rewards.

## 2026-08-25 current-Release boot boundary

The exact current Release PCK above was served once on local-only
`127.0.0.1:8078` and opened in one temporary in-app-browser tab.  `index.html`,
`index.pck`, `index.wasm`, and the worker all returned successfully; the
rendered Korean title screen and Compatibility/WebGL 2.0 initialization were
visible.  Browser logs contained no warning or error entries.

The available canvas automation surface did not deliver a trusted Godot button
activation during this particular probe.  Consequently this is recorded only
as a current-artifact boot/render check, **not** as a Title→Home or gameplay
E2E result.  The tab and local HTTP server were closed immediately afterward;
no browser save, service-worker cache, deployment, or upload was changed.

## 2026-08-25 N10 physical-contact regression hardening

`BOSS_PRESENTATION_03..05` now reproduce the canonical N09→N10 revealed route
instead of preparing an abstract N10 transaction.  The test walks the
deterministic physical route to the boss hex, confirms one localized
presentation payload and one battle token, rejects a second entry attempt, and
then reloads the active transaction.  Recovery returns the squad to the exact
adjacent pre-contact hex and clears all pending presentation/token state.

The current direct suite is Static **70/70**, Core **165/165**, SRPG map
**249/249**, R15 **49/49**, and R16 **26/26**: **559/559 PASS, 0 FAIL**.
This strengthens the automated map-contact authority path; it does not replace
the separately recorded direct Release visual E2E boundary.

## 2026-08-25 current Release N10 direct execution checkpoint

Direct pointer input, rather than DOM/canvas synthetic input, reached the
current Release path `TITLE → HOME → MAP → N10 → physical contact → existing
battle`. The observed defeat awarded no reward, retained the unresolved boss
pawn, and restored the unresolved encounter/map position after browser
refresh. Captured Release console errors/warnings: `0 / 0`.

The scope is deliberately limited to N10 contact/defeat/reload; it is not a
continuous Chapter completion claim.

## 2026-08-25 isolated movement-pulse and deferred-companion checkpoint

The current Development Web build was served on an isolated local origin so
the user-facing Release save remained untouched. A route toward HARD 2 was
truncated at the first unresolved authored special encounter, confirming that
the map does not route a squad through an unresolved event. The squad consumed
its pulse, stopped, and then `대기` refilled the next pulse to `8/8` without
changing its position.

The continued physical route reached `! 단절된 중계선 · 토아`. Its contact card
used Toa's companion SD art, not a generic hostile asset, then handed off to
the existing real-time battle. The Development victory result preserved the
one-shot reward diff and explicitly recorded the deferred recruitment condition
after NORMAL 9. Result return plus browser refresh retained the resolved event
and did not replay or duplicate it; console errors/warnings were `0 / 0`.
