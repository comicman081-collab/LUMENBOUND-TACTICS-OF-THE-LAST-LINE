# R7 SRPG Chapter Map Test Report

## Automated results

- Static data audit: 60/60 PASS.
- Existing Godot runtime suite: 87/87 PASS.
- Existing Godot runtime suite re-run after the macro-map change: 87/87 PASS.
- New chapter-map suite: 57/57 PASS.
- Total executed for the macro-map revalidation: 144, PASS 144, FAIL 0, skipped 0.
- Godot: 4.7.1-stable official, Compatibility renderer.

The map suite covers axial/world round-trip, six neighbours, cube distance,
elevation, blocked deep water and cliffs, deterministic A* tie-breaking,
unreachable destinations, all 10 NORMAL and 5 HARD references, sequential
unlock rules, reveal rules, v1→v2→v3 save migration, macro-route reanchoring,
ten-plus-viewport route extent, deterministic seeded terrain generation,
unknown-node quarantine,
zero-cost traversal/fast travel, exactly-once battle entry, duplicate-result
prevention, victory/defeat placement, map↔battle IDs and reward/stamina safety.

## Frozen-system regression

- Battle final state hash: unchanged, PASS.
- Battle event hash: unchanged, PASS.
- Character EXP total: 905,520, PASS.
- Character credit total: 412,400, PASS.
- Weapon EXP total: 144,330, PASS.
- Skill arrays: 10/10/5, PASS.
- Chapter content count: NORMAL 10 / HARD 5, PASS.

## Actual Web flow

Codex In-app Browser on the R7 macro-map R11 Web Release completed:

title → home → Chapter 1 macro map → N01 route preview (9 hexes) → squad
movement along the highlighted route → existing real-time SD battle → map
return at axial coordinate (8, 1).

The current browser map screenshot demonstrated that only a local streamed
neighbourhood is visible at once; panning leaves the start location behind while
the authored route continues through the deterministic macro world. Existing
victory/reveal/reload evidence remains preserved in the prior R7 browser report.

No console error or warning was captured. The actual screenshots and hashes are
listed in `SCREENSHOT_MANIFEST.csv`.

## Not executed as PASS

- Chrome and Edge automation: UNVERIFIED because the ChatGPT browser extension
  and native host are not installed/configured in either browser profile.
- 20-minute R7 soak: UNVERIFIED. An actual 315.003-second in-app interval was
  executed; it is not relabelled as 20 minutes.
- Actual flow video: UNVERIFIED because the active browser control surface did
  not expose a recording API. Screenshot sequences are not reported as video.
