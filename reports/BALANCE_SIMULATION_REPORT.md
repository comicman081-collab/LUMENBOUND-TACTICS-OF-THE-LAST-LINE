# Balance Simulation Report

Date: 2026-08-17

Status: **EXECUTED — runtime `BattleSimulation` reused**

Godot 4.7.1 headless executed 100 seeded CH01-N10 boss runs (`700000`–`700099`) with the actual fixed-30-Hz combat model and a level-10 default party. No separate approximation was used.

| Metric | Result |
|---|---:|
| Runs | 100 |
| Win rate | 100% |
| Mean clear time | 27.2847 s |
| Median / P90 / Min / Max | 27.2 / 29.0 / 24.6 / 31.1 s |
| Time variance | 1.8411 |
| Mean survivors | 4.98 |
| Mean ultimate uses | 4.00 |

Average damage per run:

| Character | Damage |
|---|---:|
| CHR001 | 2,513.64 |
| CHR002 | 4,391.67 |
| CHR003 | 4,622.13 |
| CHR004 | 4,070.64 |
| CHR005 | 3,601.25 |

Ultimate selection was CHR001 336 and CHR002 64 uses across 100 runs after the shield-AUTO monopoly rule was tightened. Healing was zero because this preset does not contain CHR008 Medic. The 100% recommended-level win rate is a tuning warning: CH01-N10 requires enemy/output hardening before a content-balance sign-off.

Machine-readable per-seed results and death causes: `reports/balance_simulation.json`.
