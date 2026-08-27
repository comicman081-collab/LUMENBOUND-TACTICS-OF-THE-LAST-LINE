# Current MVP Requirement Audit

Date: 2026-08-25 (Asia/Seoul)

This is a current-state evidence audit for the long-map/event-companion MVP. It does not convert partial browser runs into a claim that the entire Chapter 1/HARD route was completed in one sitting.

**Evidence integrity correction (2026-08-25):** the Development H02→H05 QA
temporarily shared the isolated Release sandbox namespace and persisted debug
grants. Those Development results remain route coverage only; the later
account-Lv100 Release reload is excluded. A clean Release namespace is required
for the remaining H02→H05 certification.

| Objective requirement | Current authority / evidence | Verdict |
|---|---|---|
| Independent long 2.5D Chapter 1 SRPG exploration map | `CH01_MAP.json`, deterministic macro-world assertions, map runner `MACRO_SORT_*`, route span assertion | IMPLEMENTED / TESTED |
| Map turn-like bounded movement and growth/item extension | `MapExplorationService`, account milestone and owned-route-module capacity; `PULSE_01..04`, side-treasure `PULSE_REWARD_01/02`, and local Release module α claim/reload observation | IMPLEMENTED / TESTED; module α direct Web delta verified, hidden module β remains UNVERIFIED |
| Physical squad movement before battle | `ChapterMapScreen._move_along()` + contact transaction; map runner movement/contact assertions | IMPLEMENTED / TESTED |
| Existing realtime 5-person battle remains unchanged | same BattleSimulation final/event hash before/after map traversal; `map traversal does not change*` assertions | IMPLEMENTED / TESTED |
| Event enemies visibly carry `!` | authored companion event `MAP_IDLE` pawn + grounded pulsing marker; `EVENT_PAWN_RUNTIME_01..03` for N04/N08 | IMPLEMENTED / TESTED |
| Event encounter on physical contact | automatic special-signal presentation followed by ordinary BattleScene; `EVENT_PAWN_02A..09` and Release N04 captures | IMPLEMENTED / TESTED + RELEASE E2E (N04) |
| Immediate companion recruitment | NODE_N04 / CHR006; Release result/map-return/reload captures `09..13_RELEASE_N04_*` | IMPLEMENTED / RELEASE E2E |
| Deferred companion recruitment | NODE_N08 / CHR007 tracking, then N09 recruitment; corrected result-art regression plus Development captures `16..19_DEVELOPMENT_*_POSTFIX_WEB` | IMPLEMENTED / DEVELOPMENT E2E |
| Immediate vs deferred outcome is clear before battle | Each immutable event encounter carries a localized `contact_outcome_key`; the contact card shows `조우 결과` without changing the battle or reward transaction | IMPLEMENTED / TESTED |
| No generic hostile art for companion encounter | character-specific `MAP_IDLE` atlas source IDs, not hostile fallback; `EVENT_PAWN_RUNTIME_02` | IMPLEMENTED / TESTED |
| Reward/clear happens exactly once | processed battle/reward tokens, map runner reward/clear/reload assertions | IMPLEMENTED / TESTED |
| Save/reload restores map/encounter/treasure/party state | map save/migration/reload assertions; Release N04 refresh capture | IMPLEMENTED / TESTED + RELEASE E2E (N04) |
| Video-derived boss progression | N09 pre-boss story → N10 route/contact/result Release captures `103..107_RELEASE_N10_*`; `PREBOSS_STAGING_01..11` | IMPLEMENTED / PARTIAL RELEASE E2E |
| Independent N10 event title / boss threat card | `CH01_MAP.json` authored presentation keys, `AppState` inert transaction payload, `BossEncounterTitleCard`, `BOSS_PRESENTATION_01..04` | IMPLEMENTED / TESTED + DEVELOPMENT WEB VISUAL; direct uninterrupted Release N10 card remains UNVERIFIED |
| Chapter outro runtime CG | `cg_ch01_pilot_teamwork` is generated as a 1280×720 Web-only runtime derivative; Release capture `reports/r16_environment/112_RELEASE_CH01_OUTRO_CG_RUNTIME_WEB.png` | IMPLEMENTED / RELEASE VISUAL QA |
| HARD-route movement, victory, defeat, and reload | Current Release H01 physical contact victory → H02 unlock; H02 pulse exhaustion → wait → physical contact defeat → exact map return → refresh | IMPLEMENTED / RELEASE E2E (H01/H02) |
| Fresh Release new-save NORMAL route | One isolated Release session completed N01→N10 with physical movement, pulse waits, patrol replans, story, recruitment, growth and N10 boss victory | RELEASE E2E PASS |
| Fresh Release HARD route | The same saved session restored the HARD gate; H01 won and H02 defeat/retry/stamina gating were observed. H03→H05 remain unverified in Release because the saved operation power was insufficient. Development-only H02→H05 coverage is recorded separately. | PARTIAL RELEASE E2E |
| GPT Web event-design review | The event/recruitment design and latest E2E evidence were sent through the existing ChatGPT Web session; response is recorded in `GPT_WEB_REVIEW_RESPONSE_20260825.md`. | COMPLETE / FOLLOW-UP REVIEW |

## Current test evidence

Latest direct reruns after the companion-result and outro-CG corrections:

- Core runner: **165 / 165 PASS**
- SRPG map runner: **249 / 249 PASS**
- R15 content runner: **49 / 49 PASS**
- R16 environment runner: **26 / 26 PASS**
- Static source/runtime-package audit: **70 / 70 PASS**
- Fresh service E2E: **CH01-N01 → N10 PASS**, including normal reward,
  growth, atomic save, and scripted reload checkpoints at N03/N05/N07/N09/N10.

The combined direct suite total is now **559 PASS / 0 FAIL**.  The additional
core coverage includes an actual atomic save/load of the persisted
intermediate-story checkpoint, an open-choice restore state, and the shell
wiring that makes the browser persist each interactive boundary. The actual
browser tab-close/reopen counterpart is pending only a confirmation to clear
the obsolete, LANTERNLINE-only PWA cache; no game save data has been deleted
or modified for that recheck.

## 2026-08-25 Full Chapter transaction and reload regression

`R15_FULL_ROUTE_01` executes the complete canonical operation sequence
`N01…N10 → H01…H05` through the same normal-player map encounter,
battle-entry, result, reward, node-clear, companion-recruitment, and unlock
services used by the runtime. Developer authority stays off and the fixture
grants no growth materials. It proves each result commits exactly once and a
duplicate stale result is a persistent no-op; it does not impersonate physical
browser movement or rendered realtime battle.

`R15_FULL_ROUTE_02` saves the fully completed route to an isolated test save,
reloads it, and verifies all fifteen cleared encounter nodes and no pending
encounter transaction remain. Both passed.

## 2026-08-25 Contact-outcome clarity and source recheck

The three read-only reference-video source files were rehashed locally. Their
SHA-256 values exactly match `REFERENCE_VIDEO_METADATA.csv`; no video was
copied into the Godot project, source package, or Web output.

The two existing companion-event contracts now include an immutable,
localized presentation field rather than relying on result-screen copy alone:

- `EVENT_RESCUE_VERA`: **승리 시 즉시 편성에 합류**
- `EVENT_RELAY_TOA`: **승리 후 신호 동행 · NORMAL 9 완료 뒤 편성 합류**

`contact_outcome_key` is copied into the pending map-contact presentation
payload and displayed on the one-time contact card. It is not read by
BattleSimulation, RewardResolver, movement, map unlock, or save migration.
`EVENT_PAWN_02B` now asserts the payload copy, while `EVENT_PAWN_09` asserts
the card's clear outcome wiring. All current source, core, map, R15, and R16
test suites pass after this change.

## 2026-08-25 Contact-card readability verification

The development-only N04 fixture was used to execute the ordinary one-hex
physical contact path and inspect the real transition card. It rendered the
companion portrait, localized event name/body, and the new `조우 결과` row
before entering the unchanged realtime battle. The original 1.25-second
special-contact hold was too short once real browser input latency was
included, so the presentation-only hold is now **1.85 seconds** for special
contacts (the reduced-transition accessibility option remains 0.18 seconds).
No battle, reward, map unlock, path, RNG, or save transaction timing changed.

This source change was followed by direct reruns: Static **68/68**, core
**156/156**, SRPG map **226/226**, R15 **47/47**, and R16 **26/26**; total
**523 PASS / 0 FAIL**. The current in-place, non-deployed Release PCK is
`builds/web_release/index.pck` (**58,811,204 bytes**;
SHA-256 `a8a1d9f3d22567e29bb23285a8427956787f1a05140a6534349366a611b99362`).
The latest public-Release local smoke reopened title → home → map successfully.
The exact companion-card visual inspection is a development-fixture check;
it is not presented as a fresh full Release N04 E2E claim.

## Next highest-value work

Extend the isolated Release HARD-session evidence from H02 through H05 with both AUTO and deliberate manual-ultimate attempts where appropriate. This must not use development unlocks or mutate Release authority.

## 2026-08-25 Stable-URL service-worker update policy

The in-place, non-deployed Web export was rebuilt after the story hierarchy and
mid-story atomic checkpoint changes. Its current runtime PCK is
`builds/web_release/index.pck` (**58,811,748 bytes**; SHA-256
`b758424aaa05b9fcbf99c324b008f069c94aa9290d3f671fc02d12c70296d041`).

The build script now fingerprints the final `index.pck`, `index.wasm`,
`index.js`, and `index.html` as the service-worker cache version
`r7_3f5f08c69dfa096d`. It makes navigation network-first while retaining a
cached offline fallback, and a fetched worker immediately activates and claims
the open client. This preserves the fixed public URL and avoids future release
updates being indefinitely masked by a complete old cache. HTTP verification
confirmed the emitted worker contains this policy. The temporary in-app tab
was closed and its port-8078 server was stopped. Its automation surface
reported its own Canvas fallback, so this is a packaging/HTTP check, not a
replacement for the pending real browser visual recheck.

## 2026-08-25 Runtime CG packaging correction

The original CG file was valid locally but intentionally excluded from the Web
PCK as authoring-size art. The browser therefore used the authored story
background fallback. The Web bridge now creates only
`res://assets/runtime_web/story/cg_ch01_pilot_teamwork_1280x720.png` from that
preserved original, records its SHA-256 in the runtime asset manifest, and
maps the immutable CG asset ID to that packaged derivative. The Release PCK
was rebuilt in place (`59,312,296` bytes;
`0291b0c0fad1968df4da99d7110e61e1fc340ddf84efdf750edb0f76fe3064ca`).

The actual Release outro was reopened from the prior saved flow in one
temporary in-app-browser tab. It displayed the authored team CG, not an empty
band or background fallback; browser warning/error log was `0/0`. The tab and
temporary port-8078 server were closed immediately after capture.

## 2026-08-25 Current Release HARD-route evidence

The existing isolated `growth-e2e-r15` browser save was reopened on the same
`localhost.` origin used to create it; the alternate `127.0.0.1` origin was
observed to have separate browser storage and was not used as evidence. The
HARD route was visibly unlocked after the completed NORMAL route.

1. H01 was selected, the party physically moved to its pawn, and the unchanged
   realtime five-character battle ended in victory at `25.80s` with four
   survivors. Rewards displayed prior and final inventory quantities, and H02
   became the next HARD operation. Capture:
   `reports/mvp_video_reference/114_RELEASE_H01_VICTORY_CURRENT_WEB.png`.
2. H02 selection caused the authored movement-pulse cap to stop the party at
   `0/7`. The user-facing **대기** action restored `7/7`; a second route action
   physically reached the H02 pawn and entered the existing realtime battle.
3. H02 ended in defeat at `19.83s`, with no reward. Map return left the hostile
   H02 pawn and the party at its pre-contact map location. Captures:
   `115_RELEASE_H02_DEFEAT_CURRENT_WEB.png` and
   `116_RELEASE_H02_DEFEAT_RETURN_CURRENT_WEB.png`.
4. A browser refresh of the same isolated session restored the same HARD map,
   party position, still-hostile H02 pawn, and `next operation: HARD 2` state.
   Capture: `117_RELEASE_H02_DEFEAT_RELOAD_CURRENT_WEB.png`.

Browser console warning/error log was `0/0`. This confirms both victory and
defeat round-trip behavior on the current Release, but does not upgrade the
uninterrupted H01→H05 completion claim above from `UNVERIFIED`.

## 2026-08-25 Fresh-save route, typography, and audio check

An isolated Web save session was created with the runtime's existing test-save
isolation query. It began at the canonical Chapter 1 starting state (account
Lv.20, initial currency and stamina) rather than reusing a progressed browser
profile. The title's first trusted pointer action started the actual lobby BGM
stream: `audio_enabled=true`, `web_unlocked=true`, `music_playing=true`,
`AudioStreamWAV`, with a measured source length of `89.9356s` and one verified
`audio_bgm_lobby` playback. This is runtime evidence only; it does not alter a
player's saved audio setting.

Story presentation was also rechecked at the mobile-portrait layout. Narrative
copy now uses the larger story scale (36 portrait / 42 landscape logical px),
while compact story controls use 10.5 portrait / 11.5 landscape logical px and
retain their 56px physical touch targets. Reflow rebuilds only the visual story
presentation and preserves the active dialogue/choice state without advancing
the scenario or writing a new checkpoint.

The map runner now includes `FRESH_ROUTE_01`: a newly created Chapter 1 map
state must reveal and pathfind a physical route from the start hex to N01, with
at least one executable movement step under the current movement-pulse budget.
It passed in the direct 228/228 SRPG map rerun above.

The same isolated Web session then ran the player-facing N01 route: chapter
intro → map → **다음 조우 · 일반 1** → route preview → movement-pulse
exhaustion → **대기** refill → patrol-aware reselect → physical contact → the
unchanged five-member realtime battle. The battle displayed the individual SD
party and hostile art, projectile/VFX activity, tactical gauge, AUTO and
ultimate buttons. Browser console error/warning collection returned **0/0**.
The temporary in-app-browser tab and port-8078 server were closed immediately
after this check. This is a current Release Web N01 entry proof; it remains
separate from the HARD-route completion evidence.

## 2026-08-25 Fresh Release NORMAL completion and HARD follow-up

The same isolated Web save (`mvp_route_20260825`) was then driven as a real
player flow, not through a developer-unlock fixture. It completed all of the
following in one continuous Release browser session:

1. Prologue and Chapter 1 introduction, then **N01 through N10** in order.
2. Every route used real map selection and physical squad travel. When a
   seven-step pulse ended, the visible **대기** action refilled movement before
   a subsequent route selection. Patrol path changes required a fresh route
   preview instead of silently teleporting the squad.
3. N04 showed the authored `구조 신호 · 베라` companion presentation rather
   than a generic hostile pawn; contact entered the unchanged realtime battle,
   and its victory result carried the companion art and growth impact.
4. N08 similarly used the authored `단절된 중계선 · 토아` contact. N09's
   victory result carried the later companion's art/growth impact, proving the
   deferred recruitment path in the same release session.
5. The result screen was used to apply the actual bounded, shared-material
   **권장 파티 성장** service. It raised the party and skills only while its
   normal material/currency checks allowed it; there was no developer grant.
6. N10 displayed its pre-boss story, storm presentation, boss-route contact,
   realtime battle and **VICTORY** at `46.03s`, followed by the authored
   chapter-outro CG. The chapter map then exposed `HARD 1`.

After a browser reload of that same isolated save, the NORMAL clears, party
position and HARD availability were retained. Selecting **위험 작전** exposed
H01. An initial H01 AUTO attempt failed with no rewards; after all currently
legal recommended growth batches were consumed, a second H01 AUTO attempt
won at `26.70s` and exposed H02. An H02 AUTO attempt subsequently lost at
`20.83s`, with no rewards. This accurately demonstrates defeat/no-reward and
retry behavior, but does not claim H03–H05 completion or an all-HARD AUTO
win rate.

This complete browser session had console error/warning collection of
**0/0**. The one temporary test tab and the port-8078 local server were closed
when the check ended. No deployment was performed.

## HARD AUTO outcome classification

The single fresh-save H02 AUTO defeat above is intentionally not used as a
balance verdict. The completed, shipping-data `R15_SELECTED_MANUAL_POLICY_FULL_MATRIX.md`
matrix ran 200 deterministic seeds for each stage/profile/control cell. At the
recommended profile it reports H02 AUTO `120/200 (60.0%)` and the selected
manual-ultimate policy `165/200 (82.5%)`; H05 reports AUTO `101/200 (50.5%)`
and manual `119/200 (59.5%)`. Both are within the published HARD target bands,
and the selected manual policy's evaluator result is `13 PASS / 0 FAIL / 0
UNVERIFIED`. The browser result is therefore retained as real defeat/retry
evidence, while the deterministic matrix remains the balance authority.

One follow-up Release attempt reopened the same save, physically routed to H02
again, and confirmed the unchanged contact-to-battle hand-off and browser
console `0 errors / 0 warnings`. At this save's organic post-N10 growth level,
the 3x battle resolved in defeat before a stable, player-meaningful manual
ultimate timing window could be exercised. It is therefore logged only as
additional below-recommended-party defeat evidence; it is not presented as a
manual-policy test. The temporary tab and its port-8078 server were closed.

## 2026-08-25 Story typography hierarchy and combat-import recovery

Story reading was given explicit visual priority without reducing touch areas:

- Narrative text: **36 logical px in portrait / 42 logical px in landscape**.
- Story navigation controls: **10.5 logical px in portrait / 11.5 logical px
  in landscape**, while retaining their existing at-least-56 logical-pixel
  touch target.

The current in-place Web Release was opened locally in one temporary
in-app-browser tab and inspected at the real story screen. Korean narrative
copy is visibly primary and its compact navigation controls remain readable.
The tab was then closed; port 8078 was stopped. The captured browser console
contained **0 warnings / 0 errors**.

During this validation, `BattleSpriteLibrary` was also made resilient to the
two legacy source PNG import descriptors marked `valid=false`: it decodes that
local PNG bytes only when the source descriptor explicitly requires recovery,
then falls back to Godot's ordinary imported texture path for packaged Web
assets. This does not replace any asset and does not alter the battle model.
The previous headless resource-load warning no longer occurs in the R15
runtime pack test.

Direct regression after both changes: static **68/68**, core **157/157**
(including the typography regression), SRPG map **226/226**, R15 **47/47**,
R16 **26/26** — **524 PASS / 0 FAIL**.
The current non-deployed local Release PCK is
`builds/web_release/index.pck` (**58,811,540 bytes**;
SHA-256 `3676de236c2a65363ae59417002d606fa97b30c8beb14e8860460cc7a568611a`).

The same packaged Release was then checked at the real **390×844 portrait**
viewport. Narrative copy remained the dominant reading layer; the five story
controls wrapped into a two-column layout without overlap, and the control
targets stayed large despite their reduced font. The local browser logged
**0 warnings / 0 errors**. That single temporary QA tab was closed, the
viewport override was reset, and port 8078 was released.

## 2026-08-25 Isolated H02 retry

The same opt-in `growth-e2e-r15` Web save was reopened at account Lv.21 with
no developer grants, its HARD 2 pawn was selected, and the squad again moved
through the normal confirmation/contact transition. AUTO ended in **DEFEAT**
at `19.83s`, with no reward and no artificial promotion of the H03 route. The
run confirms that the defeated encounter is repeatable through its normal map
contact, but is deliberately not used as an H02 balance verdict or as an
H03–H05 completion claim. The one temporary in-app-browser QA tab and the
port-8078 local server were closed afterward.

## 2026-08-25 Release map-capacity checkpoint

An isolated `capacity-web-r15` Release sandbox loaded Title → Prologue →
Chapter 1 map on the current PCK. The actual Web HUD showed `이동 7/7`, while
the 96-hex long-distance terrain, squad pawn, and encounter marker rendered.
GPT Web reviewed map entry, movement-capacity HUD, long-map rendering, and the
existing pulse/WAIT behavior as PASS. Direct browser evidence that VT03/HT03
route modules individually add `+1/+1` remains UNVERIFIED; no code, save,
clock, developer authority, deployment, upload, or cache deletion was used.

## 2026-08-25 Developer HARD daily-limit QA

The Development Web build was opened in the existing single temporary QA tab
using an isolated `r15-save-sandbox` session. After the developer QA action,
the real map HUD showed `이동 9/9`; the HARD encounter detail showed
`입장 횟수 무제한 (DEV)` and retained its normal route/entry presentation.
This is direct Development-build evidence, saved at
`reports/mvp_video_reference/screenshots/DEV_HARD_QUOTA_WEB_EVIDENCE_20260825.png`.

The corresponding automated authority checks are **165/165 PASS** for the
core scene runner: an exhausted HARD ledger remains blocked in ordinary mode,
while DEV mode permits entry without incrementing `hard_attempts` or consuming
stamina. The public Web Release export preset has no
`lanternline_dev_tools` custom feature; the DEV-only bypass is therefore not
available through the public Release authority path. The temporary QA tab and
port 8078 were closed after capture. No deployment or upload was performed.

## 2026-08-25 Release artifact boundary smoke

The rebuilt public Web Release (`builds/web_release/index.pck`, SHA-256
`46acae74776ae18c05791c8878fca5ee26d323123e5628dc75006d48112e114c`) was
opened in the existing in-app-browser session and reached Title → Home →
Chapter 1 intro → map. The live Release HUD showed `이동 7/7`; developer tools
and `무제한 (DEV)` were absent; browser console errors/warnings were 0.
Screenshot: `reports/mvp_video_reference/screenshots/RELEASE_ARTIFACT_MAP_BOUNDARY_20260825.png`.

GPT Web classified this as **PARTIAL PASS** with **P0 none**. The only open
Release-certification P1 is the exact exhausted-HARD artifact smoke (`3/3`
blocked, no ledger/stamina mutation, no DEV label), still **UNVERIFIED**.
No deployment or upload was performed.

## 2026-08-25 — Same-PCK quota edge follow-up

GPT Web re-reviewed the current Release evidence after confirming that the
same-origin ordinary save is still at NORMAL N04 and therefore has the HARD
route legitimately locked. The test intentionally did not edit the save,
change the device clock, or apply Development authority just to produce a
`3/3` ledger. The result is **PASS WITH ONE UNVERIFIED RUNTIME EDGE**:

- verified: actual Release boot-to-map route, `이동 7/7`, no DEV UI, no
  `무제한 (DEV)`, browser error/warning 0;
- retained P1: exact current-PCK exhausted HARD `3/3` block and ledger/stamina
  no-mutation observation;
- P0: none; deployment/upload: none.

This preserves evidence integrity: a locked HARD route is not treated as a
quota pass, and no privileged mutation is presented as a public-Release test.

## 2026-08-25 — Preserved quota-sandbox lookup

Following the reviewer priority, the current public Release PCK was opened
once using the existing isolated `hard-release-cert-r15` sandbox name. The
loaded sandbox was a legitimate fresh Chapter 1 state (NORMAL N01, HARD route
locked), not the prior exhausted `3/3` state. No save content, system clock,
or Development authority was changed to manufacture that condition. This
lookup therefore adds no quota PASS claim and leaves the exact `3/3` runtime
gate **UNVERIFIED**. The one temporary tab and its local HTTP server were
closed immediately; deployment/upload remained untouched.
