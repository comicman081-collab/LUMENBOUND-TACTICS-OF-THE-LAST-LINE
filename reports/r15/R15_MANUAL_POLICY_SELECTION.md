# R15 Manual Ultimate Policy Selection

## Scope and integrity

- Simulation: shipping `BattleSimulation`, fixed 30 Hz
- Profile: RECOMMENDED
- Party: `CHR001`, `CHR002`, `CHR003`, `CHR005`, `CHR008`
- Stages: `CH01-N07`, `CH01-N10`, `CH01-H01`, `CH01-H04`, `CH01-H05`
- Runs: 200 paired seeds per policy and stage (4,000 simulations total)
- Seed policy: every policy receives exactly the same seed for a given stage/run index
- Shipping StageDef, character, skill and battle data mutated: **no**
- Predeclared practical noninferiority margin: **-2.5 percentage points** versus AUTO

Raw reproducible evidence is in `R15_MANUAL_POLICY_PAIRED_PROBE.json`.

## Results

| Stage | AUTO | Current M3 | Health-gated AOE2 / 15 ticks | Health-gated AOE2 / 30 ticks |
|---|---:|---:|---:|---:|
| CH01-N07 | 180/200 (90.0%) | 179/200 (89.5%, -0.5pp) | 171/200 (85.5%, -4.5pp) | **176/200 (88.0%, -2.0pp)** |
| CH01-N10 | 174/200 (87.0%) | 183/200 (91.5%, +4.5pp) | 180/200 (90.0%, +3.0pp) | **187/200 (93.5%, +6.5pp)** |
| CH01-H01 | 133/200 (66.5%) | 180/200 (90.0%, +23.5pp) | 135/200 (67.5%, +1.0pp) | **133/200 (66.5%, +0.0pp)** |
| CH01-H04 | 105/200 (52.5%) | 156/200 (78.0%, +25.5pp) | 126/200 (63.0%, +10.5pp) | **126/200 (63.0%, +10.5pp)** |
| CH01-H05 | 94/200 (47.0%) | 76/200 (38.0%, -9.0pp) | 127/200 (63.5%, +16.5pp) | **120/200 (60.0%, +13.0pp)** |

Aggregate paired win-rate deltas versus AUTO:

- Current M3: mean +8.8pp, minimum -9.0pp, H05 38.0% (target FAIL)
- Health-gated AOE2 / 15 ticks: mean +5.3pp, minimum -4.5pp, H05 63.5% (all-stage noninferiority FAIL)
- **Health-gated AOE2 / 30 ticks: mean +5.6pp, minimum -2.0pp, H05 60.0% (all-stage noninferiority PASS)**

## Selected diagnostic candidate

**`HEALTH_GATED_AOE2_CADENCE30`** is the recommended policy candidate.

Rationale:

1. It is the only candidate whose worst paired stage delta remains inside the declared -2.5pp practical noninferiority margin.
2. It improves the five-stage mean win rate by 5.6pp versus AUTO.
3. It places H05 at 60.0%, inside the required 45–75% manual target.
4. The 30-tick cadence avoids the excessive defensive re-polling observed with the 15-tick manual policy while retaining deliberate target and gauge decisions.
5. The health gate spends a two-target AOE only when party health is stable or the lowest ally has sufficient shielding; boss/elite single-target decisions take priority.

This is a diagnostic recommendation only. The shipping battle policy and all shipping balance data remain unchanged in this task.
