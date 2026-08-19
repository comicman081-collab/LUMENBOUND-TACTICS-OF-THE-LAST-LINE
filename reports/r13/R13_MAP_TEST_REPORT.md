# R13 SRPG Map Core — Test Report

Tested on 2026-08-19 with Godot `4.7.1.stable.official.a13da4feb`.

| Suite | Executed | Pass | Fail |
|---|---:|---:|---:|
| R13 map model/runtime | 73 | 73 | 0 |
| Existing static data audit | 60 | 60 | 0 |
| Existing Godot runtime regression | 92 | 92 | 0 |

The map suite covers the R13 additions: concrete enemy-pawn eligibility, first-unresolved-enemy path truncation, arrival-only encounter start, victory/defeat state changes, exactly-once rewards, deterministic visible/hidden treasure placement and transitions, shared reward resolution, affordability deltas, save restoration, stamina transactions, and battle/growth regressions.

## Determinism and regression

- Map traversal does not change BattleEvent hashes or battle final-state hashes.
- Character EXP total remains `905,520`; character credit total remains `412,400`; weapon EXP total remains `144,330`.
- Skill data remains `10/10/5`.
- Existing battle test covers explicit manual-ultimate target damage, status controls, 1x/3x simulation equivalence, and pooled projectile/text reuse.

## Browser verification (in-app browser)

Fresh local Web run at the fixed test port `8078` completed this sequence without console errors or warnings:

`title → home → Chapter 1 map → N01 enemy select → route preview → squad movement → contact-only real-time battle → victory reward → map return → visible treasure → hidden-treasure hint → reveal/claim → reload → saved map state`.

This is local verification only. No deployment or publication was performed.

## R13 visual re-review

The user-authorized in-app ChatGPT re-review accepted the revised HINT visual and revised reward/growth screen as **PASS**. See `reports/r13/GPT_WEB_REVIEW_R13.md` for the supplied real-Web evidence and exact verdicts.
