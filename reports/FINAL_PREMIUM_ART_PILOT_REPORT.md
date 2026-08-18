# Final Premium Art Pilot Report — R6P2 Art / R6P5 Web

## Environment

- Project: `D:\AI 종합 폴더\Games\블아 like\SD_STORY_RPG_GODOT`
- Godot: 4.7.1 stable Standard (`a13da4feb`), Compatibility renderer, Web only
- Blender: 4.5.11 LTS, background CLI rendering
- Asset factory: `D:\AI 종합 폴더\Games\asset_share`, package 0.1.0 / generator 1.0.0
- Premium pipeline generator: `premium-pilot-1.1.1`; rig `billboard-deform-rig-1.1.0`
- Final art revision: R6P2; final Web/UI revision: R6P5

## Baseline and regression

The baseline HTML and Source ZIP remain preserved under `builds/baseline/`; old files were not overwritten. Final validation executed all 60 static and 87 Godot runtime tests: **147/147 PASS**. Growth totals remain character EXP 905,520, credits 412,400, and weapon EXP 144,330. The deterministic 1×/3× battle result and event-hash test remains PASS.

## Pilot delivered

- Player pilots: CHR001 and CHR008
- Enemy pilots: ENM001 normal, ENM007 elite, BOSS001 boss
- Three backgrounds, one event CG, 16 pilot icons
- Six VFX sets × 12 frames
- Five exact 80-frame SD runtime packs
- Authoritative R6P2 `.blend` sources, manifests, seeds, SHA-256 values, render commands, contact sheets, validator, incremental sync, and Web build scripts
- Actual runtime integration for portrait, icon, formation, combat SD, projectile, VFX, HP/shield, result, and growth screens

Technical validation processed 422 PNGs with zero failures. The 204 dark-matte heuristic warnings were manually cross-checked against the R6P2 contact sheets and actual R6P4/R6P5 Web rendering; no black-alpha-fringe hard failure was observed. Pilot runtime IDs produced **0 fallback calls**. Broader non-pilot fallback remains 2 player + 7 enemy entities by approval-gate design.

## R6 remediation outcome

- Illustration: **90.2/100 PASS**
- SD and animation: **88.6/100 PASS**
- Background: **89.3/100 PASS**
- VFX: **87.4/100 PASS**
- UI: **86.0/100 PASS**
- Overall bounded pilot: **88.3/100 PASS**
- Final hard failures: **0**

R6P2 replaced the rejected black-silhouette interpolation attempt with fully opaque authored state poses and subdivided planted-foot deformation. R6P4 removed raw JSON presentation, repaired formation-slot interaction, added premium art to home/result/growth, preserved the five-button battle HUD, and added a native readable portrait gate. R6P5 additionally collapsed long acquisition-stage lists to three examples plus a remaining-count suffix so the growth footer no longer overflows.

## Web and package

- R6P5 runtime folder: 18 files, 299,550,684 bytes
- R6P5 Web ZIP: `builds/review/LANTERNLINE_WEB_ART_PILOT_R6P5.zip`
- ZIP bytes: 268,919,133
- ZIP SHA-256: `9A0B03F50C9C4D1FBFB4053EEBC3BB839D230DCB6C0939F1B42D724094BC9999`
- Review ZIP: `builds/review/LANTERNLINE_PREMIUM_ART_PILOT_REVIEW_R6P5.zip`
- Review ZIP bytes: 48,892,417
- Review ZIP SHA-256: `AFF455BDBBA3EF4980F7C4D9741FC728834B5921D601BC7E4AF4A5222DE1B793`
- 300 MB budget: **PASS**

Actual Codex in-app-browser flow passed title → home → story → formation → stage detail → battle → result → growth. The formation slot-selection bug was directly retested, 390×844 shows the landscape gate, and console errors/warnings were zero. R6P5's growth overflow fix was directly rechecked in a new in-app-browser Web session.

## Final verdict

- SYSTEM FOUNDATION: PASS
- PREMIUM ART PILOT: PASS
- REFERENCE PARITY (bounded pilot): PASS
- BALANCE HARDENING: PASS
- BROWSER SOAK: see `FINAL_BROWSER_SOAK_REPORT.md`
- PRODUCTION APPROVAL: WAITING_USER_APPROVAL

No Windows native build, APK, AAB, external paid API, Krea2 asset, or new audio work was produced. Full 8-player/11-enemy production art remains gated on the user's review of this pilot.
