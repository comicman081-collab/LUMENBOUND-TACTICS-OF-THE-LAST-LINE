# R7 SRPG Map Browser Report

## Actual in-app browser verification — 2026-08-18

- Target: fixed Web Release output `builds/web_r7_current_release`.
- Local test URL: `http://127.0.0.1:8081/index.html?build=r7_current`.
- The test server used only fixed port **8081** and was stopped after QA.
- Build ID: `LANTERNLINE_R7_CURRENT_WEB`.
- Runtime PCK: `r7_current_72afe8d01baf.pck`.

## Responsive map flow

- Portrait `390×844`: title → home → Chapter 1 map completed.
- Portrait map header, back action, navigation rail, map viewport, stage detail
  sheet, sweep actions and cancel action remained inside the visible/safe area.
- Live portrait → landscape `1280×720` rotation rebuilt the chapter-map shell
  from stable map state and removed portrait-only font scaling.
- Live landscape → portrait rotation restored the compact map and stage detail
  sheet without a reload.
- Header overlap that previously covered the chapter map on portrait devices is
  fixed in the current R7 output.
- Landscape `1280×720`: N03 route preview → route-following squad movement →
  existing real-time SD battle at 3× → victory result → Chapter Map return was
  completed. The squad returned to the encounter node and the next encounter
  advanced to N04.
- Current build visual check: N04→N05 was selected, the cyan route preview was
  visible, and the representative squad pawn was observed at an intermediate
  path location before arrival. The live SubViewport node-label alignment was
  also rechecked after the responsive-scale correction.
- Battle visual check: a gauge-ready CHR005 area `ULT` was observed in the real
  battle scene with the event callout, character pose and impact VFX present.
- Expanded VFX check: real battle displayed the ultimate cast seal and diamond,
  role-coloured projectile trail, target shock-disk/starburst, and a later
  normal-skill glyph plus impact effect. The current visual run completed
  without a fatal interruption; the in-app tab and fixed 8081 server were then
  closed.

## Runtime diagnostics

- Earlier full-flow in-app browser console errors/warnings: 0.
- Current focused visual pass: no fatal visual/runtime interruption observed.
- Local HTTP requests resolved the current hash-addressed PCK and WASM files.
- Browser tab closed after testing; temporary viewport override reset; port 8081
  confirmed closed after testing.

## Scope and verdict

- In-app responsive functional QA: **PASS** for the tested map title/detail
  flow and live orientation rotation.
- One complete map→battle→map browser round-trip was re-run after this layout
  correction. Multi-round-trip soak remains **UNVERIFIED**; deterministic map
  round-trip coverage is also present in the 57 automated map tests.
- Chrome, Edge and Firefox were not used in this pass because the user required
  in-app-browser QA; they are **UNVERIFIED**, not PASS.
