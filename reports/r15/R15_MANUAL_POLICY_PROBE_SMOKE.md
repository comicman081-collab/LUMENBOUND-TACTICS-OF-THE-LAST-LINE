# R15 Same-seed Manual Ultimate Policy Probe

Shipping `BattleSimulation`, StageDef, character and skill data were reused without mutation.
Every policy used the same 1 seeds per stage.

| Stage | Policy | Wins | Win rate | Mean time | Survivors | Delta vs AUTO |
|---|---:|---:|---:|---:|---:|---:|
| CH01-N07 | AUTO | 1/1 | 100.0% | 20.833s | 4.000 | +0.0pp |
| CH01-N07 | CURRENT_M3 | 1/1 | 100.0% | 26.267s | 3.000 | +0.0pp |
| CH01-N07 | HEALTH_GATED_AOE2 | 1/1 | 100.0% | 23.267s | 4.000 | +0.0pp |
| CH01-N07 | HEALTH_GATED_AOE2_CADENCE30 | 1/1 | 100.0% | 21.967s | 4.000 | +0.0pp |
| CH01-N10 | AUTO | 1/1 | 100.0% | 49.267s | 2.000 | +0.0pp |
| CH01-N10 | CURRENT_M3 | 0/1 | 0.0% | 53.100s | 0.000 | -100.0pp |
| CH01-N10 | HEALTH_GATED_AOE2 | 1/1 | 100.0% | 46.667s | 5.000 | +0.0pp |
| CH01-N10 | HEALTH_GATED_AOE2_CADENCE30 | 1/1 | 100.0% | 50.067s | 4.000 | +0.0pp |
| CH01-H01 | AUTO | 1/1 | 100.0% | 29.767s | 5.000 | +0.0pp |
| CH01-H01 | CURRENT_M3 | 0/1 | 0.0% | 44.567s | 0.000 | -100.0pp |
| CH01-H01 | HEALTH_GATED_AOE2 | 0/1 | 0.0% | 36.567s | 0.000 | -100.0pp |
| CH01-H01 | HEALTH_GATED_AOE2_CADENCE30 | 1/1 | 100.0% | 33.933s | 5.000 | +0.0pp |
| CH01-H04 | AUTO | 1/1 | 100.0% | 39.467s | 5.000 | +0.0pp |
| CH01-H04 | CURRENT_M3 | 0/1 | 0.0% | 38.467s | 0.000 | -100.0pp |
| CH01-H04 | HEALTH_GATED_AOE2 | 1/1 | 100.0% | 73.467s | 2.000 | +0.0pp |
| CH01-H04 | HEALTH_GATED_AOE2_CADENCE30 | 1/1 | 100.0% | 74.267s | 2.000 | +0.0pp |
| CH01-H05 | AUTO | 0/1 | 0.0% | 67.367s | 0.000 | +0.0pp |
| CH01-H05 | CURRENT_M3 | 1/1 | 100.0% | 76.833s | 5.000 | +100.0pp |
| CH01-H05 | HEALTH_GATED_AOE2 | 1/1 | 100.0% | 77.867s | 5.000 | +100.0pp |
| CH01-H05 | HEALTH_GATED_AOE2_CADENCE30 | 0/1 | 0.0% | 70.000s | 0.000 | +0.0pp |

## Policy verdicts

- **CURRENT_M3**: all-stage noninferior=false; mean delta=-40.0pp; minimum delta=-100.0pp; H05=100.0% (target 45–75%: false).
- **HEALTH_GATED_AOE2**: all-stage noninferior=false; mean delta=+0.0pp; minimum delta=-100.0pp; H05=100.0% (target 45–75%: false).
- **HEALTH_GATED_AOE2_CADENCE30**: all-stage noninferior=true; mean delta=+0.0pp; minimum delta=+0.0pp; H05=0.0% (target 45–75%: false).

The probe is diagnostic evidence only; it does not alter shipping policy or balance data.
