# Final Balance Hardening Report

## Method

The matrix reused the actual 30 Hz `BattleSimulation`: five stages, five growth profiles, AUTO and scripted manual ultimate, 200 deterministic seeds per combination (10,000 runs). Balance changes were applied only through `data_source/stage_balance_overrides.json` and compiled into runtime data.

## Target-stage results

| Stage / profile | Control | Win rate | Mean clear | Target | Verdict |
|---|---:|---:|---:|---|---|
| CH01-N01 initial | AUTO | 100.0% | 20.838 s | 95–100%, 15–30 s | PASS |
| CH01-N05 recommended | AUTO | 95.0% | 26.766 s | 85–98%, 25–50 s | PASS |
| CH01-N10 recommended | AUTO | 86.0% | 51.858 s | 70–90%, 40–70 s | PASS |
| CH01-N10 recommended | MANUAL | 91.0% | 52.402 s | 85–98% | PASS |
| CH01-H01 recommended | AUTO | 64.0% | 34.868 s | 50–75% | PASS |
| CH01-H05 recommended | AUTO | 47.5% | 71.280 s | 25–55% | PASS |
| CH01-H05 recommended | MANUAL | 47.0% | 72.880 s | 45–75%, 60–88 s | PASS |

Final enemy factors: N01 3.5, N05 3.0, N10 1.57, H01 2.0, H05 1.385.

N10 changed from 100% / 26.886 s to 86% / 51.858 s for the recommended AUTO profile. The H05 final same-seed result is recorded in `reports/balance_hardening/factor_probe_h05_fine.json`; the older `after_matrix.json` and the H05 row in `after_matrix_final.json` are retained as iteration evidence, not the final H05 authority.

## Regression

- Baseline tests: 147/147 PASS (static 60, Godot runtime 87)
- Character EXP total: 905,520 unchanged
- Character credit total: 412,400 unchanged
- Weapon EXP total: 144,330 unchanged
- Skill caps, breakthroughs, weapon tiers, save schema, reward and deterministic contracts unchanged

**BALANCE HARDENING: PASS**
