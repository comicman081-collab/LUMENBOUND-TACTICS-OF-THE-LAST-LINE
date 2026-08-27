# R7 MVP Result Commit / Refresh Audit

Date: 2026-08-23 (Asia/Seoul)

Scope:

- `godot/autoload/app_state.gd`
- `godot/autoload/save_service.gd`
- `godot/screens/app_shell.gd`
- `godot/tests/r15_test_runner.gd`
- existing pending-reveal coverage in `godot/chapter_map/tests/map_test_runner.gd`

Shipping battle balance, stage data, reward data, and `BattleSimulation` were not changed.

## P0 finding and correction

The original result callback called `record_stage_clear()` before proving that the callback owned a live battle reward token. A tokenless or stale victory callback could therefore change `first_clear`, stars, chapter unlocks, and canonical reveal state even though reward claiming later failed.

The commit boundary is now claim-first:

1. `claim_pending_reward_once(stage_id)` validates and consumes the live transaction token.
2. Only a successful claim may call `record_stage_clear`, grant rewards/account EXP/relationship EXP, or queue the stage-clear story.
3. The map adapter rejects a victory when no live battle token exists. A merely prepared encounter is a recovery snapshot, not victory authority.
4. The complete committed profile is written once by the existing atomic `SaveService.save_game()` call before the result screen is routed.

This also removes the unsafe synthetic `stage_id:RECOVERED` clear-token fallback.

## Refresh policy verified

| Refresh boundary | Verified recovery |
|---|---|
| Prepared/contact snapshot, before battle entry is saved | Pending encounter is recovered to its authored return axial coordinate; hostile remains; inventory, reward, first-clear, and stamina remain unchanged. |
| Mid-battle runtime after entry | The last atomic pre-contact snapshot is loaded. Runtime token is discarded, so no result can be claimed from the abandoned simulation. |
| After result commit, before mandatory story | Reward/inventory, first clear, enemy removal, next-stage unlock, pending story, and unconsumed reveal presentation all survive load. |
| Duplicate result callback after load | Persistent profile is byte-semantically unchanged and reward output is empty. |
| Before map reveal presentation is consumed | The same pending reveal token survives load; canonical reveal refresh does not recreate it. |
| After reveal presentation is consumed | The consumed-token ledger survives load and the presentation cannot replay. |

## Automated evidence

`tools/powershell/RUN_R15_TESTS.ps1`

- Total: 47
- Pass: 47
- Fail: 0
- Added boundary assertions: 12 (`RESULT_TXN_01..05`, `RESULT_REFRESH_01..04`, `MID_BATTLE_REFRESH_01..03`)

`tools/powershell/RUN_MAP_TESTS.ps1`

- Total: 165
- Pass: 165
- Fail: 0
- Includes N09 pre-boss staging and six one-shot reveal/reload assertions.

All save-boundary fixtures use the isolated `user://r15_soak_sandbox/r15_result_refresh_audit` namespace and delete it after execution. They never read or overwrite the normal player save namespace.

