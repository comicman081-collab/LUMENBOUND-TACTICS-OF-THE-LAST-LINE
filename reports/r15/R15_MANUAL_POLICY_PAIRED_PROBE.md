# R15 Same-seed Manual Ultimate Policy Probe

Shipping `BattleSimulation`, StageDef, character and skill data were reused without mutation.
Every policy used the same 200 seeds per stage.

| Stage | Policy | Wins | Win rate | Mean time | Survivors | Delta vs AUTO |
|---|---:|---:|---:|---:|---:|---:|
| CH01-N07 | AUTO | 180/200 | 90.0% | 23.915s | 3.310 | +0.0pp |
| CH01-N07 | CURRENT_M3 | 179/200 | 89.5% | 26.706s | 3.220 | -0.5pp |
| CH01-N07 | HEALTH_GATED_AOE2 | 171/200 | 85.5% | 24.925s | 3.310 | -4.5pp |
| CH01-N07 | HEALTH_GATED_AOE2_CADENCE30 | 176/200 | 88.0% | 24.806s | 3.360 | -2.0pp |
| CH01-N10 | AUTO | 174/200 | 87.0% | 47.261s | 3.930 | +0.0pp |
| CH01-N10 | CURRENT_M3 | 183/200 | 91.5% | 51.508s | 4.225 | +4.5pp |
| CH01-N10 | HEALTH_GATED_AOE2 | 180/200 | 90.0% | 49.338s | 4.050 | +3.0pp |
| CH01-N10 | HEALTH_GATED_AOE2_CADENCE30 | 187/200 | 93.5% | 49.635s | 4.135 | +6.5pp |
| CH01-H01 | AUTO | 133/200 | 66.5% | 31.513s | 2.855 | +0.0pp |
| CH01-H01 | CURRENT_M3 | 180/200 | 90.0% | 33.398s | 3.920 | +23.5pp |
| CH01-H01 | HEALTH_GATED_AOE2 | 135/200 | 67.5% | 33.519s | 2.785 | +1.0pp |
| CH01-H01 | HEALTH_GATED_AOE2_CADENCE30 | 133/200 | 66.5% | 33.538s | 2.835 | +0.0pp |
| CH01-H04 | AUTO | 105/200 | 52.5% | 41.950s | 2.110 | +0.0pp |
| CH01-H04 | CURRENT_M3 | 156/200 | 78.0% | 48.851s | 3.365 | +25.5pp |
| CH01-H04 | HEALTH_GATED_AOE2 | 126/200 | 63.0% | 45.802s | 2.730 | +10.5pp |
| CH01-H04 | HEALTH_GATED_AOE2_CADENCE30 | 126/200 | 63.0% | 45.846s | 2.690 | +10.5pp |
| CH01-H05 | AUTO | 94/200 | 47.0% | 67.444s | 1.880 | +0.0pp |
| CH01-H05 | CURRENT_M3 | 76/200 | 38.0% | 72.101s | 1.565 | -9.0pp |
| CH01-H05 | HEALTH_GATED_AOE2 | 127/200 | 63.5% | 75.025s | 2.600 | +16.5pp |
| CH01-H05 | HEALTH_GATED_AOE2_CADENCE30 | 120/200 | 60.0% | 74.272s | 2.440 | +13.0pp |

## Policy verdicts

- **CURRENT_M3**: all-stage noninferior=false; mean delta=+8.8pp; minimum delta=-9.0pp; H05=38.0% (target 45–75%: false).
- **HEALTH_GATED_AOE2**: all-stage noninferior=false; mean delta=+5.3pp; minimum delta=-4.5pp; H05=63.5% (target 45–75%: true).
- **HEALTH_GATED_AOE2_CADENCE30**: all-stage noninferior=true; mean delta=+5.6pp; minimum delta=-2.0pp; H05=60.0% (target 45–75%: true).

The probe is diagnostic evidence only; it does not alter shipping policy or balance data.
