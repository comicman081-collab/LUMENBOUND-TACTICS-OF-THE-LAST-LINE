# R15 Selected Manual Policy — Full Matrix Completion

## Integrity

- Policy: `HEALTH_GATED_AOE2_CADENCE30`
- Manual decision cadence: 30 simulation ticks
- Simulation: shipping deterministic `BattleSimulation`, fixed 30 Hz
- Shipping StageDef, character, skill and combat data changes: **0**
- Stages: 15 (`N01`–`N10`, `H01`–`H05`)
- Profiles: 3 (`LOW`, `RECOMMENDED`, `HIGH`)
- Controls: 2 (`AUTO`, `SCRIPTED_MANUAL_ULTIMATE`)
- Cells: 90
- Runs per cell: 200
- Total simulations: 18,000
- AUTO/MANUAL same-seed pairs: 45/45
- Cells with incorrect run count: 0
- Runtime: 808.862 seconds
- Matrix SHA-256: `CA0F1B9C8B1CAFA7EDC5CCB6E3A1E6FCC8F4A791F71AF462AA7D014A63EE8AC1`

Raw matrix: `R15_CH01_BALANCE_MATRIX_HEALTH_GATED_AOE2_CADENCE30.json`.

## Recommended-profile results

| Stage | AUTO wins | Manual wins | Manual delta | AUTO mean | Manual mean |
|---|---:|---:|---:|---:|---:|
| N01 | 200/200 (100.0%) | 200/200 (100.0%) | +0.0pp | 17.073s | 18.920s |
| N02 | 199/200 (99.5%) | 199/200 (99.5%) | +0.0pp | 17.859s | 20.630s |
| N03 | 196/200 (98.0%) | 199/200 (99.5%) | +1.5pp | 18.319s | 20.351s |
| N04 | 193/200 (96.5%) | 197/200 (98.5%) | +2.0pp | 22.444s | 24.057s |
| N05 | 177/200 (88.5%) | 180/200 (90.0%) | +1.5pp | 25.140s | 26.062s |
| N06 | 192/200 (96.0%) | 194/200 (97.0%) | +1.0pp | 32.284s | 33.419s |
| N07 | 175/200 (87.5%) | 178/200 (89.0%) | +1.5pp | 24.226s | 24.751s |
| N08 | 170/200 (85.0%) | 184/200 (92.0%) | +7.0pp | 21.589s | 24.647s |
| N09 | 170/200 (85.0%) | 176/200 (88.0%) | +3.0pp | 43.742s | 43.410s |
| N10 | 167/200 (83.5%) | 183/200 (91.5%) | +8.0pp | 47.434s | 49.426s |
| H01 | 155/200 (77.5%) | 152/200 (76.0%) | -1.5pp | 30.014s | 31.846s |
| H02 | 120/200 (60.0%) | 165/200 (82.5%) | +22.5pp | 26.581s | 30.479s |
| H03 | 122/200 (61.0%) | 140/200 (70.0%) | +9.0pp | 57.981s | 60.376s |
| H04 | 119/200 (59.5%) | 132/200 (66.0%) | +6.5pp | 42.589s | 46.084s |
| H05 | 101/200 (50.5%) | 119/200 (59.5%) | +9.0pp | 69.715s | 73.600s |

Across the 15 recommended-profile stages, manual is better in 12, equal in 2 and lower in 1. The mean stage delta is +4.733pp; the minimum is -1.5pp at H01, inside the probe's -2.5pp practical noninferiority margin. H05 manual is 59.5%, inside the required 45–75% range.

## Evaluator and regression

- Balance target evaluator: 13 PASS / 0 FAIL / 0 UNVERIFIED
- R15 content/runtime tests after harness integration: 35 PASS / 0 FAIL
- Updated generated reports: `R15_NORMAL_BALANCE.md`, `R15_HARD_BALANCE.md`
- Updated audit: `R15_BALANCE_TARGET_AUDIT_HEALTH_GATED_AOE2_CADENCE30.json`

The previous `R15_CH01_BALANCE_MATRIX.json` and its reports were preserved as historical evidence.
