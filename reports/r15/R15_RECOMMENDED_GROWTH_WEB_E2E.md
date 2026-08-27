# R15 Recommended Growth — Actual Web E2E

## Scope

- Runtime: Godot 4.7.1 Stable Web build on the local HTTP server.
- URL session: `r15-save-sandbox=1&r15-save-sandbox-session=growth-e2e-r15`.
- This session uses `user://r15_soak_sandbox/growth-e2e-r15/` only. It did not read, write, reset, or back up the production save namespace.
- Progression input: the player-facing **권장 파티 성장** action only; its actions route through the normal character, breakthrough, skill, and weapon services.

## Actual NORMAL Route

| Stage | Actual result | Clear time | Survivors | Growth action batches after result |
| --- | --- | ---: | ---: | --- |
| CH01-N01 | Victory | 15.47 s | 5 | 12 + 12 + 7; planner then reported no further legal recommendation |
| CH01-N02 | Victory | Observed in Web; result returned to map | 5 | No new batch required |
| CH01-N03 | Victory | 12.23 s | 5 | No new batch required |
| CH01-N04 | Victory | 17.17 s | 5 | No new batch required |
| CH01-N05 | Victory | 17.43 s | 5 | No new batch required |
| CH01-N06 | Victory | 24.60 s | 4 | 8 actual service actions; planner then reported no further legal recommendation |
| CH01-N07 | Victory | 16.67 s | 5 | No new batch required |
| CH01-N08 | Victory | 16.17 s | 4 | No new batch required |
| CH01-N09 | Victory | 29.50 s | 4 | 2 actual service actions; planner then reported no further legal recommendation |
| CH01-N10 | Victory | 37.07 s | 5 | No new batch required; Chapter outro entered |

N06 is the regression gate for the prior one-character-growth failure. It completed through the visible recommendation path without changing combat data.

## Actual Save / Reload Checkpoints

- **N03:** saved from formation, reloaded the browser, then returned through title and home to the chapter map. Account level, stamina, credits, cleared N03, next N04, and party map location were visibly restored.
- **N07:** repeated the same save/reload path. Account level 21, stamina 75, credits 72,373, cleared N07, and next N08 were visibly restored.
- **N10:** saved after Chapter outro, reopened the same isolated session, returned through title/home, and reopened the chapter map. Runtime map probe reported `node_count=1926`, `draw_calls=2142`, confirming map restoration. The in-app browser had a background screenshot-capture limitation at this final checkpoint, so a visual HARD-route screenshot is not claimed here.

## Web Safety Audit

Latest sandbox audit from the actual session:

```json
{
  "sandbox_active": true,
  "sandbox_session": "growth-e2e-r15",
  "sandbox_path_resolve_count": 1,
  "production_path_resolve_count": 0,
  "production_read_attempt_count": 0,
  "production_write_attempt_count": 0,
  "production_backup_attempt_count": 0,
  "production_reset_attempt_count": 0
}
```

- Browser console errors: 0 observed.
- Browser console warnings: 0 observed.
- The completed local Web tab was closed after this QA pass; the GPT review tab remains the only in-app browser tab.

## Regression Commands Re-run After the E2E

- `RUN_HEADLESS_TESTS.ps1`: **97 / 97 PASS**
- `RUN_R15_TESTS.ps1`: **31 / 31 PASS**
- `RUN_MAP_TESTS.ps1`: **137 / 137 PASS**
- `RUN_R15_PROGRESSION.ps1`: fresh service-based CH01-N01 through CH01-N10 PASS, including scripted reload checkpoints.

## A — Recommended-Growth Batch Hardening

The batch now builds its bounded (maximum 12) sequence against an isolated profile copy through the same CharacterProgression, BreakthroughService, SkillUpgradeService, and WeaponUpgradeService APIs used by the actual transaction. It then executes that exact sequence against the live profile and reports planned / successful / rejected action counts plus inventory and credit deltas.

The additional regression coverage is intentionally service-based rather than a parallel profile mutator:

- preview action sequence equals the actual service execution sequence;
- preview and execution material / credit deltas match;
- zero legal actions make zero service transactions and leave profile state unchanged;
- a rejected action stops the batch immediately, reports the successful prefix exactly, and does not execute a later action;
- preview leaves the live profile untouched and is deterministic from a fixed snapshot;
- active party balancing avoids leaving a member at Lv.1 while another runs ahead;
- batch → SaveService → LoadService preserves level, EXP, breakthrough, inventory, and credit exactly.

`GROWTH_PLAN_10` through `GROWTH_PLAN_15`: **6 / 6 PASS**.

This test pass includes the prior `GROWTH_PLAN_01` through `GROWTH_PLAN_09` checks; no existing assertion was removed or weakened.

## Result

`RECOMMENDED_GROWTH_WEB_E2E_NORMAL: PASS`

This result certifies the fresh NORMAL-route progression UX only. It does not certify the outstanding static-art completion gaps, the HARD H01–H05 actual Web route, or a final production release.
