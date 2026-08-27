# R15 H05 Paired Ultimate Policy Probe

## Scope

- Godot: `4.7.1.stable.official.a13da4feb`
- Simulation: shipping `BattleSimulation`, fixed 30 Hz
- Stage: `CH01-H05`, unmodified shipping `StageDef`
- Party: `CHR001`, `CHR002`, `CHR003`, `CHR005`, `CHR008`
- Profile: `RECOMMENDED` (`level=20`, skills `2/2/1`, weapon level `20`)
- Paired seeds: `5,150,000` through `5,150,199` (200 seeds per policy)
- Total simulations: 600
- Shipping balance-data changes: none

The previous full R15 matrix assigned different seed ranges to AUTO and scripted-manual cells. This probe gives all three policies the exact same 200 seeds, so outcome differences can be interpreted pairwise.

## Policy results

| Policy | Wins | Win rate | Mean time | p10 / p50 / p90 | Mean survivors | Timeout | Ultimate uses total / mean |
|---|---:|---:|---:|---:|---:|---:|---:|
| AUTO | 82 / 200 | 41.0% | 67.662s | 45.367 / 72.667 / 78.833s | 1.540 | 0.5% | 2,045 / 10.225 |
| Manual, AOE at 2+ enemies | 70 / 200 | 35.0% | 66.851s | 45.333 / 71.367 / 78.033s | 1.350 | 1.0% | 2,041 / 10.205 |
| Manual, AOE at 3+ enemies | 123 / 200 | 61.5% | 76.241s | 68.233 / 77.933 / 83.500s | 2.535 | 0.0% | 2,007 / 10.035 |

Ultimate-use totals by character:

| Policy | CHR001 | CHR002 | CHR003 | CHR005 | CHR008 |
|---|---:|---:|---:|---:|---:|
| AUTO | 958 | 218 | 11 | 848 | 10 |
| Manual, AOE ≥2 | 872 | 213 | 14 | 926 | 16 |
| Manual, AOE ≥3 | 1,776 | 218 | 5 | 0 | 8 |

The AOE≥3 rule preserves tactical gauge for CHR001's defensive ultimate instead of spending it on CHR005's two-target AOE. It raises survival and win rate, but also lengthens successful combat because it sacrifices damage tempo for protection.

## Paired outcomes

| Comparison | Both win | Left only | Right only | Both lose | Right-minus-left wins | Win-rate delta | Paired mean time delta | Both-win time delta |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| AUTO → Manual AOE≥2 | 45 | 37 | 25 | 93 | -12 | -6.0pp | -0.812s | -0.202s |
| AUTO → Manual AOE≥3 | 50 | 32 | 73 | 45 | +41 | +20.5pp | +8.579s | +4.319s |
| Manual AOE≥2 → AOE≥3 | 46 | 24 | 77 | 53 | +53 | +26.5pp | +9.391s | +4.676s |

For diagnostic context, an exact two-sided paired-discordance test gives `p=0.1619` for AUTO versus AOE≥2, `p=0.0000781` for AUTO versus AOE≥3, and `p=0.000000118` for AOE≥2 versus AOE≥3. The AOE≥2 result does not establish a reliable manual disadvantage at 200 paired seeds; AOE≥3 does establish a large policy effect in this scenario.

## Verdict

- H05 AUTO remains inside its 25–55% target at 41.0%.
- The current scripted-manual AOE≥2 policy is below the desired 45–75% H05 manual range at 35.0%.
- The AOE≥3 diagnostic policy reaches 61.5%, inside the desired range, with zero stage-data changes.
- This supports changing the scripted-manual decision policy (or adding an equivalent tactical gauge reservation rule), not changing H05 enemy scalars blindly.
- No shipping policy or balance data was changed by this probe. Adoption remains a separate implementation decision and must be followed by the full R15 matrix/regression run.

## Reproduction

```powershell
& .\tools\powershell\RUN_R15_H05_PAIRED_PROBE.ps1 -Runs 200
```

Machine-readable result:

- `reports/r15/R15_H05_PAIRED_ULTIMATE_POLICY_PROBE.json`
- SHA-256: `96CEC46BFD08C39698A56C3FE0ECC0110FE735BDB64373910B4D88C27BC507C0`
