# Final Browser Soak Report — R6P4 Soak / R6P5 UI Delta

## Browser constraint

The user explicitly required the Codex in-app browser, so no external Chrome, Edge, or standalone Playwright surface was substituted. The final QA therefore covers one Codex in-app Chromium session.

## Actual functional flow

R6P4 was served through local HTTP and exercised through title → home → story → formation → slot 2 selection → stage select → structured stage detail → 1× battle → result → 3× battle → deterministic matching result → growth. Console errors and warnings were zero. R6P5 changes only acquisition-stage text compaction; its title, roster, and final growth screen were loaded through a separate in-app-browser Web session with zero console errors/warnings.

Responsive checks:

- 1280×720: PASS
- 844×390: PASS with aspect-preserving letterbox
- 390×844: PASS; native `LANTERNLINE / 가로 화면으로 돌려 주세요 / 최소 지원 크기 844 × 390` gate is readable

## Wall-clock probe

The R6P4 Web autoload probe sampled every 5 seconds and retained 240 samples.

- Final elapsed: 1,240.008 seconds
- Samples: 240
- Average FPS: 91.91
- Minimum FPS: 90.0
- Orphan nodes: 0
- Typical result-screen node/object count: 47 / 1,554
- Observed battle node/object count: 59 / 2,542
- Fatal console errors: 0
- Console warnings: 0
- WebGL context loss: 0 observed
- Crash/freeze/black frame: 0
- Scene transition failure: 0

Godot Web returns `0` for `Performance.MEMORY_STATIC`, so that value is explicitly recorded as unavailable rather than presented as a real heap measurement. As an external stability proxy, aggregate ChatGPT/in-app-browser host working set over the final measured interval changed from 7,902,699,520 to 7,863,095,296 bytes (−39,604,224), and private bytes changed from 7,378,231,296 to 7,356,456,960 (−21,774,336). This is a host aggregate, not per-tab memory, but it shows no unbounded growth during the closing interval. Engine object/node counts also returned to their stable result-screen baseline after each battle.

## Incremental final-build treatment

The full 20-minute run was performed on R6P4. R6P5 is an 80-byte PCK delta that only shortens acquisition-stage strings in `app_shell.gd`; it passed 87/87 runtime tests and direct in-app-browser growth-screen visual QA. No simulation, asset, VFX, pool, renderer, or save code changed between these builds. The soak verdict therefore uses R6P4 as the tested baseline plus R6P5 delta verification.

## Verdict

- Functional Web flow: PASS
- Responsive QA: PASS
- 20-minute in-app-browser soak: PASS
- Incremental R6P5 UI delta: PASS
- **BROWSER SOAK: PASS**

Current limitation: exact per-tab GPU/process-memory counters are not exposed by the in-app browser. This is documented and was not replaced with a fabricated value.
