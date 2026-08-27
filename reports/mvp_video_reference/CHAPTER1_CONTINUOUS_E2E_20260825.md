# Chapter 1 Continuous Web E2E — 2026-08-25

## Scope

- Build: `builds/web_release` served at `http://127.0.0.2:8078`
- Browser: Codex in-app browser, temporary QA tab
- No deployment or cache/service-worker deletion performed
- Existing local save was used. It entered the run at the N05-cleared checkpoint; this is not a fresh N01 save.

## Observed flow

1. Title → Home → Chapter 1 SRPG map.
2. Existing checkpoint showed N05 cleared, N06 hostile, movement budget and exploration state restored.
3. N06 first attempt: route movement → existing real-time SD battle → defeat → no reward; hostile N06 remained on map.
4. Growth screen: recommended party growth applied using the existing Growth Service; no new ad-hoc calculation was used.
5. N06 retry: wait → route movement → real-time SD battle → victory (18.40 s, 5 survivors) → reward inventory diff and growth-impact panel → map return; N06 cleared and N07 revealed.
6. N07: movement-budget exhaustion was shown, wait restored movement, route continued → real-time battle → victory (13.47 s, 5 survivors) → map return; relay story `종탑형 중계기` played once.
7. N08: special encounter panel `단절된 중계선·토아` → wait/route → real-time battle → victory (14.13 s, 5 survivors) → reward/progression note and map return.
8. N09: multi-step long route with movement exhaustion and wait recovery → real-time battle → victory (24.57 s, 5 survivors) → map return; pre-boss story `공허기관 앞에서` played once.
9. N10: long route with multiple movement-budget waits → existing real-time battle → victory (33.67 s, 5 survivors) → reward panel → Chapter 1 outro `다음 등불` displayed and advanced back to the map.
10. HARD toggle became available after NORMAL completion. H01 route → real-time battle → victory (22.00 s, 4 survivors) → HARD2 route revealed.
11. H02 route → real-time battle → defeat (24.60 s, 0 survivors) → no reward; retry remains available. H03–H05 were not executed in this run.

## Regression observations

- N06 defeat preserved the hostile pawn and gave no reward.
- N06 retry gave one reward transaction; map clear/reveal occurred once.
- Movement exhaustion required `대기` before continuing and did not start battle prematurely.
- N07/N08/N09/N10 story and reward panels used localized text and actual inventory before→after values.
- Existing battle view displayed SD art, skill/ultimate VFX, projectiles, HP/shield HUD and battle audio playback.
- Browser console: 0 error, 0 warning in the captured 100-log window.
- Runtime soak samples remained present; latest observed sample reported `fps=95`, `orphan_node_count=0`, and verified playback counts with `playback_failed_counts={}`. These are bounded QA observations, not a 20-minute soak certification.

## Verdict

- **NORMAL N06→N10 checkpoint continuation:** OBSERVED PASS
- **HARD H01:** OBSERVED PASS
- **HARD H02:** OBSERVED DEFEAT / retry available
- **Fresh-save N01→N10 in this exact run:** UNVERIFIED (the save was already at N05-cleared)
- **H03–H05 continuous Release E2E:** UNVERIFIED
- **Physical mobile device QA:** UNVERIFIED
- **Deployment:** NOT PERFORMED

