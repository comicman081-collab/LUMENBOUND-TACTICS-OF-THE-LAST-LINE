# R7 SRPG Chapter Map Implementation Report

PROJECT_ROOT: `D:\AI 종합 폴더\Games\블아 like\SD_STORY_RPG_GODOT`

GODOT_VERSION: 4.7.1 Stable Standard

TARGET: Web/HTML only, Compatibility renderer

## Current R7 output

- Fixed output: `builds/web_r7_current_release`.
- Fixed build ID: `LANTERNLINE_R7_CURRENT_WEB`.
- PCK: `r7_current_72afe8d01baf.pck`.
- PCK SHA-256: `72AFE8D01BAF6A5FD692742D5F334CDF22B1B15621461FB3EF47D6A98F3E37E3`.
- No incrementing R-number output directory was created.

## Chapter map

- Map ID: `CH01_MAP`.
- Hex coordinates: deterministic axial q/r with cube-distance conversion.
- Pathfinding: deterministic A* with q-then-r tie-break.
- NORMAL battle nodes: 10.
- HARD battle nodes: 5.
- Long macro route: over ten local-view lengths; the in-map route minimap
  provides full-route context while the 3D view remains a local traversal view.
- Traversal stamina cost: 0. Battle-entry stamina transaction: exactly once.
- Fast travel: clear/revealed/allowed nodes only; no reward or stamina.
- Existing real-time BattleSimulation/BattleView remains separate from the map.
- Movement presentation is real pawn-coordinate interpolation along the A* path,
  with per-step trail markers, WALK/ARRIVE motion states, and bounded camera
  follow. Selection no longer snaps the camera to the destination before travel.
- Seeded terrain now uses elevation tiers 0–3, visible low-poly hex land caps,
  cliff/strata dressing, forest clusters, ruins, signal rails and coastline.
  The original Blender map-kit source remains preserved and unmodified.
- Node controls are now scaled from the live SubViewport size, so their screen
  positions align with their corresponding 3D encounter/pawn locations.
- Actual R7 browser replay: N03 route preview/movement → real-time battle at
  3× → victory result → exact Chapter Map return → N04 revealed.
- Current output focused check: N04 → N05 route preview and mid-route pawn
  movement were visibly observed in the in-app browser.

## Battle presentation correction

- NORMAL SKILL and ULTIMATE events were already present in `BattleSimulation`;
  this pass fixes their visibility in `BattleView`.
- Each event now receives a readable `SKILL`/`ULT` callout and event-driven
  animation. CHR001/CHR008 retain authored pilot VFX; other characters render a
  clearly marked runtime fallback with core, ring, spokes and impact layers
  until their authored PNG packs are supplied.
- Presentation playback is capped independently of the simulation at 3× so an
  event is not reduced to a single visual frame. Deterministic battle logic and
  30 Hz tick rate are unchanged.
- The normal Chapter 1 two-enemy area-ultimate AUTO threshold is two targets,
  allowing a gauge-ready area ULT to appear in early gameplay.
- VFX presentation now has explicit cast, travel and impact phases: normal and
  ultimate shots leave role-coloured trails, then resolve into a delayed
  shock-disk/starburst at the target. Healing and shielding get distinct cross
  and hex-barrier visuals. These are BattleView-only additions; no battle event,
  RNG, damage formula or deterministic state calculation changed.

## Responsive layout correction

- `ChapterMapScreen` now takes bounds from AppShell's content container instead
  of anchoring itself across the full viewport.
- Portrait hides the verbose legend and uses the route minimap without overlapping
  the stage detail bottom sheet.
- Orientation probing refreshes shell typography/safe-area metrics even on Web
  engines that omit a Godot window-size signal.
- Chapter-map UI reconstructs from stable saved map state after orientation
  changes; battle presentation remains separately protected from this behavior.

## Regression evidence

- Foundation/headless tests: **87 planned, 87 executed, 87 pass, 0 fail**.
- R7 map tests: **57 planned, 57 executed, 57 pass, 0 fail**.
- Combined actual execution: **144 pass, 0 fail**.
- Map traversal final-state and event-hash regression: PASS by automated test.
- Character-growth, weapon-growth, reward, pity and 10/10/5 regressions: PASS
  by automated test.

## Excluded

- AUDIO: OUT OF SCOPE; existing hooks remain disabled safely.
- WINDOWS EXE: NOT CREATED.
- APK/AAB: NOT CREATED.

## Current verdict

- SYSTEM REGRESSION: PASS.
- SRPG MAP FUNCTION: PASS by automated tests and focused in-app map QA.
- PORTRAIT/LANDSCAPE MAP LAYOUT: PASS for tested 390×844 and 1280×720 live rotation.
- BATTLE PRESERVATION: PASS by deterministic regression test.
- SAVE MIGRATION: PASS by automated map tests.
- MAP VISUAL QUALITY: still an R7 art candidate; no production-art PASS is claimed.
- FULL CROSS-BROWSER SOAK: UNVERIFIED.
- PRODUCTION APPROVAL: WAITING_USER_APPROVAL.
