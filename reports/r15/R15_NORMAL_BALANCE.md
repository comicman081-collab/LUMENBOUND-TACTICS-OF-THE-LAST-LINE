# R15 NORMAL Balance Matrix

| Stage | Recommended AUTO | Recommended Manual | Low AUTO | High AUTO | AUTO mean | Manual mean |
|---|---:|---:|---:|---:|---:|---:|
| CH01-N01 | 100.0% | 100.0% | 99.5% | 100.0% | 17.07s | 18.92s |
| CH01-N02 | 99.5% | 99.5% | 96.5% | 100.0% | 17.86s | 20.63s |
| CH01-N03 | 98.0% | 99.5% | 95.0% | 99.5% | 18.32s | 20.35s |
| CH01-N04 | 96.5% | 98.5% | 94.0% | 100.0% | 22.44s | 24.06s |
| CH01-N05 | 88.5% | 90.0% | 69.0% | 100.0% | 25.14s | 26.06s |
| CH01-N06 | 96.0% | 97.0% | 78.5% | 100.0% | 32.28s | 33.42s |
| CH01-N07 | 87.5% | 89.0% | 61.0% | 100.0% | 24.23s | 24.75s |
| CH01-N08 | 85.0% | 92.0% | 64.5% | 99.0% | 21.59s | 24.65s |
| CH01-N09 | 85.0% | 88.0% | 60.0% | 99.5% | 43.74s | 43.41s |
| CH01-N10 | 83.5% | 91.5% | 49.5% | 100.0% | 47.43s | 49.43s |

Source: `R15_CH01_BALANCE_MATRIX.json` (current rerun). Runs per cell: `200`. Total recorded runs: `18000`. Results are from the shipping deterministic `BattleSimulation`.
Scripted manual policy: `HEALTH_GATED_AOE2_CADENCE30` at `30` decision ticks.

## N10 before/after control
- Pre-tune: 79.0%, 48.10s.
- Current: 83.5%, 47.43s.
- CH01-N10's data multiplier was intentionally unchanged; the comparison guards the climax while intermediate-stage data is tuned.
