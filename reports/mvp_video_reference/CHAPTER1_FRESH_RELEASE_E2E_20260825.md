# Chapter 1 Fresh Release / Development E2E — 2026-08-25

## Scope and evidence policy

- Project: `SD_STORY_RPG_GODOT`
- Runtime: Godot 4.7.1 Stable, Compatibility Renderer, Web
- Browser: Codex in-app browser, one temporary QA tab
- Release server: local HTTP only; no deployment, upload, or cache/service-worker deletion
- Development server: local HTTP only, used only for development-only HARD route coverage
- The Release and Development observations below are intentionally reported separately.

## Evidence integrity correction

The Development QA used the same `r15-save-sandbox-session=chapter1-20260825`
namespace as the preceding Release run. The developer screen granted account
level/material/weapon QA values and those values were persisted in that isolated
sandbox. Therefore:

- Release observations made **before** the Development build (fresh N01→N10,
  H01 victory, H02 defeat/retry/stamina gate) remain valid.
- Development H02→H05 victories remain valid as development-only route coverage.
- The later Release reload that showed account Lv100 and the post-development
  map context is **not** valid Release evidence and is excluded from all Release
  claims.
- No production save namespace was touched; this correction concerns only the
  deliberately isolated QA sandbox.

## Fresh Release N01→N10 observation

The temporary Release sandbox started from a fresh Chapter 1 progression and exercised the long-map loop in one run:

| Stage | Observed result | Notes |
|---|---|---|
| N01 | victory | route preview, movement budget, WAIT/patrol handling, existing real-time battle |
| N02 | victory | one battle result and map return |
| N03 | victory | existing SD battle and reward flow |
| N04 | special encounter victory | `구조 신호 · 베라`; companion event presentation and immediate recruit path observed |
| N05 | victory | normal progression continued |
| N06 | victory after retry | first defeat preserved hostile; growth service was used before retry |
| N07 | victory | `종합형 중계기` story observed once; reload checkpoint was exercised |
| N08 | first defeat, then victory | `단절된 중계선 · 토아`; delayed companion outcome and growth-impact panel observed |
| N09 | victory | NIGHT_RAIN presentation, WAIT/movement budget recovery, pre-boss story observed |
| N10 | completion/outro observed | battle returned to Chapter 1 outro (`다음 등불`) and the map/home progression advanced; a separate result-screen screenshot was not captured, so direct N10 result evidence remains PARTIAL |

### Release findings

- Map movement did not spend operation power; movement budget was restored through `대기` and did not start a battle by itself.
- Contact with the hostile pawn entered the existing real-time SD battle; no hex/turn combat was introduced.
- N06 defeat produced no reward and left the hostile encounter available.
- N08 special encounter displayed the companion identity and reward/growth presentation. Exact roster/save persistence for the companion was not separately captured in this run.
- Browser runtime logs observed during the run contained 0 error and 0 warning entries; this is not a 20-minute soak certification.

## Release HARD continuation

- H01: victory observed and H02 route revealed.
- H02: defeat observed (24.23 s, 0 survivors in the Release run); hostile remained and retry was offered.
- After the defeat, the legitimate Release save had only 3 operation-power points available and correctly disabled the H02 move action. H03–H05 could not be completed in that same Release save without changing gameplay authority, so they remain **UNVERIFIED in Release**.

This was an operation-power gate in the pre-development Release observation. The
subsequent Development run did not bypass the Release build; however, because it
shared the isolated sandbox namespace, its persisted debug grants invalidate any
later Release-save continuation claim. A new isolated clean Release sandbox is
required for H02→H05 certification.

## Development-only HARD continuation

For coverage of the already-authored H02–H05 route, a fresh Development Web build was run locally with the existing developer-only QA authority. No Release preset or save policy was weakened.

- H02: victory, 17.43 s, 5 survivors.
- H03: victory, 46.70 s, 5 survivors.
- H04: victory, 37.23 s, 4 survivors.
- H05: victory, 64.90 s, 4 survivors; result showed reward before→after inventory values and growth-candidate summary.
- H05 result→map return was observed.
- The post-development reload returned to title; Continue→Home→Chapter 1 map
  loaded the debug-mutated sandbox context. It is retained only as a
  Development persistence observation, not as Release save certification.

Development results are useful route coverage only. They do not replace the required same-save Release H01→H05 run.

## Automated regression rerun

- Static data audit: **70/70 PASS**.
- Core/Godot headless runner: **161/161 PASS**.
- SRPG map runner: **228/228 PASS**.
- R15 content runner: **49/49 PASS**.
- R16 environment runner: **26/26 PASS**.
- Measured aggregate: **534/534 PASS**.

The R16 runner additionally confirmed environment preset isolation, transition interpolation, quality tiers, and no unbounded FX-node growth across 100 transitions.

## Current verdict

- Fresh Release N01→N10 flow: **OBSERVED PASS (direct N10 Result captured in clean continuation)**.
- Release H01: **OBSERVED PASS**.
- Release H02: **OBSERVED DEFEAT / retry and operation-power gate**.
- Release H03→H05 same-save continuation: **UNVERIFIED**.
- Development H02→H05 route: **OBSERVED PASS (development-only coverage; shared sandbox later invalidated for Release claims)**.
- Physical mobile touch QA: **UNVERIFIED**.
- Controlled 20-minute browser soak: **UNVERIFIED**.
- Listening/mix QA: **UNVERIFIED**.
- Production art approval: **WAITING_USER_APPROVAL**.
- Deployment: **NOT PERFORMED**.

## Clean Release certification continuation — `hard-release-cert-r15`

This continuation used a new Release-only namespace with developer override off.
It is separate from the Development QA namespace and is valid Release evidence.

### Additional observed results

| Stage | Result | Evidence notes |
|---|---|---|
| N01→N05 | victory | clean Release progression; real-time SD battle and map return |
| N06 | defeat ×2 → legitimate growth UI → victory | no reward on defeat; hostile remained; growth was applied through the normal UI |
| N07 | victory | relay story triggered once |
| N08 | special encounter victory | companion event and reward/growth presentation |
| N09 | victory | pre-boss story and map return |
| N10 | victory, 46.03 s, 5 survivors | direct Result screen captured; outro `다음 등불` followed |
| H01 | defeat → legitimate growth UI → victory, 31.97 s, 1 survivor | H01 retry and reward commit observed |
| H02 | defeat, 24.90 s, 0 survivors | reward `0`, hostile retained, attempts changed to `1/3` |
| H02 retry gate | operation-power lock | after legitimate retries and entries, the H02 move/entry action was correctly disabled as `작전력 부족`; no authority bypass was used |

The data contract totals explain the gate: Chapter 1 NORMAL costs 72 stamina,
H01–H05 costs 62 stamina, and this run also consumed legitimate N06/H01/H02
attempts. The remaining Release stamina was below H02's 12-point entry cost.
The gate is therefore a normal economy/recovery behavior, not a code defect.

### Clean Release verdict update

- Fresh Release N01→N10 with direct N10 Result evidence: **PASS (observed)**.
- Release H01 defeat→growth→retry victory: **PASS (observed)**.
- Release H02 defeat, no reward, attempt persistence, hostile retention and stamina gate: **PASS (observed)**.
- Release H02 victory→H05 victory and H05 reload persistence: **UNVERIFIED**; the clean run exhausted its legitimate stamina before H02 retry.
- Development H02→H05 remains supporting route coverage only and is not substituted for Release evidence.
- No gameplay authority, save schema, reward formula, or battle code was changed to force this result.
- After closing the QA tab and reopening the same namespace later, Continue restored
  the legitimate save at account Lv21 with `작전력 9/124`; the Release H02 entry
  remains correctly gated until the normal recovery reaches its 12-point cost.
  The temporary tab and local HTTP server were closed again after this check.

### 2026-08-25 H02 physical-contact continuation

After ordinary recovery to `12/124`, the same namespace was continued in one
temporary Release tab. H02 showed a 33-hex route preview. The squad consumed
multiple authored 7/7 movement pulses, used WAIT between pulses, and reached
the H02 hex physically. Contact automatically entered the existing real-time
battle without a second start click. The result was `DEFEAT`, 20.83 seconds,
zero survivors, and no reward. The H02 hostile pawn remained; the pre-contact
map position was restored and survived browser reload → Continue → Home → HARD
map. The attempt counter reached `3/3`, so H02 victory and H03–H05 could not be
honestly attempted again on the same local date. `AppState` has a local-date
reset path, but the actual browser date-boundary reset remains **UNVERIFIED**.

## Map-capacity checkpoint (2026-08-25 15:54 KST)

An isolated current-Release sandbox loaded Title → Prologue → Chapter 1 map;
the real HUD showed `이동 7/7` and the long 96-hex terrain rendered with squad
pawn and encounter marker. The single temporary tab/server were closed after
inspection. GPT Web classified map entry, capacity HUD, long-map render, and
pulse/WAIT as PASS; module-specific `+1/+1` direct Web attribution and the
same-day H02→H05 evidence remain UNVERIFIED.
No save edit, clock change, developer override, deployment, upload, or cache
deletion was used.
