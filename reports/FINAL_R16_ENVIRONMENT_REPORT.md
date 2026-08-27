# R16 Environment / Weather / Shader Production Polish — Current Report

## Superseding local verification note — 2026-08-25

The original R16 block below is retained for its evidence history. After the
treasure-localization and runtime-import repair, the current regression aggregate is 544/544
PASS (70 static, 164 core, 234 map, 49 R15, 26 R16). This is the current source
aggregate; the existing Release PCK was not rebuilt for the developer-only QA
guard. The latest Web directory
loads in the in-app browser with a canvas and 0 console errors/warnings. This
does not erase the visual-capture limitation or certify the full latest-Release
H02/H03–H05 browser route; those remain explicitly UNVERIFIED.

## R16 STATUS: BLOCK

`BLOCK` means the remaining explicit Release H02 defeat → map return → browser refresh E2E has not yet been evidenced. It does **not** indicate a failed regression, shader, or visual test.

## Changed files

- `godot/chapter_map/presentation/environment_fx_controller.gd` — presentation-only environment preset, transition, quality-tier and development tuning control.
- `godot/chapter_map/shaders/environment_grade.gdshader` — canvas-compatible grade and vignette.
- `godot/chapter_map/shaders/environment_fog.gdshader` — depth-banded drifting atmosphere.
- `godot/chapter_map/shaders/environment_rain.gdshader` — bounded multi-depth rain.
- `godot/chapter_map/shaders/water_environment.gdshader` — WebGL2-compatible water movement and rain response.
- `godot/chapter_map/runtime/chapter_map_screen.gd` — transient environment binding, responsive map presentation, and a Development-only debug navigation allowance that does not mutate canonical map progress.
- `godot/screens/app_shell.gd` — story hierarchy: larger, more generously spaced narrative body and deliberately smaller secondary navigation type without changing touch targets.

## Environment presets

`CLEAR_DAY`, `MIST_DAY`, `DUSK`, `NIGHT`, `NIGHT_RAIN`, and `STORM` are implemented through one controller without a map-scene reload. Their parameters are presentation-only and are not serialized into the save schema.

## Shaders / Compatibility

All four R16 shaders are included in the Godot 4.7.1 Compatibility Web export. The R16 runner confirmed valid ranges, interpolation, quality tiers, no authoritative state dependency, and no unbounded FX-node growth over 100 transitions.

## Automated tests

| Suite | Actual result |
| --- | ---: |
| Static data audit | 70 / 70 PASS |
| Core Godot runner | 164 / 164 PASS |
| SRPG map runner | 234 / 234 PASS |
| R15 content runner | 49 / 49 PASS |
| R16 environment runner | 26 / 26 PASS |
| **Executed aggregate** | **544 / 544 PASS** |

The aggregate is the measured current runner sum; it intentionally does not copy an older prompt's historical total.

## Authority isolation

- Gameplay state delta: `0` in R16 isolation runner.
- Battle RNG delta: `0`.
- Save-schema delta: `0`.
- The environment controller has no AppState, SaveService, reward, pathfinding, combat, or RNG dependency.

## Actual Web evidence

- Six-preset visual matrix: `reports/r16_environment/01_CLEAR_DAY_WEB.png` through `06_STORM_WEB.png`.
- Development H01 movement, actual existing realtime battle, victory and H02 map reveal: `31_DEVELOPMENT_H01_HARD_ROUTE_WEB.png` through `36_DEVELOPMENT_H01_RETURN_WEB.png`.
- Public Release story typography: `37_RELEASE_TITLE_POSTFIX_WEB.png`, `38_RELEASE_STORY_TYPOGRAPHY_WEB.png`.
- The current Release was rebuilt in place. One temporary in-app-browser tab verified Title → Home → Story in desktop layout and a second sequential temporary tab verified the same flow at `390×844` portrait; both were closed immediately after capture: `WEB_TITLE_CURRENT_QA.png`, `38_RELEASE_STORY_TYPOGRAPHY_WEB.png`, `39_RELEASE_STORY_TYPOGRAPHY_PORTRAIT_WEB.png`.
- The subsequent type-hierarchy pass was checked in the current rebuilt Release at desktop Web size: `40_RELEASE_STORY_TYPOGRAPHY_HIERARCHY_WEB.png`. It shows the narrative body at `38px`, with a `6px` line separation, while story-control text remains `12.5px`; their 58-logical-pixel touch targets were retained. Console warnings/errors: `0 / 0`.
- All listed local browser checks reported zero console warnings/errors. Each used one temporary in-app-browser tab and the server/tab were closed afterward.

## Performance

Measured Development map samples (actual 60-second intervals):

| Preset | Avg FPS | p50 / p95 / p99 | >100 ms frames |
| --- | ---: | ---: | ---: |
| CLEAR_DAY | 99.40 | 10.0 / 20.0 / 20.1 ms | 0 |
| NIGHT_RAIN | 99.98 | 10.0 / 10.1 / 10.1 ms | 0 |
| STORM | 99.97 | 10.0 / 10.1 / 10.1 ms | 0 |

WebGL context loss: `0`. Browser console shader/WebGL errors: `0` in the recorded runs.

## Web release

- Path: `builds/web_release/`
- Historical R16 snapshot PCK SHA-256: `60c037255dede0d87387928e22f753f3724d83544b0b0b7cccad774a28a89363`.
- Current in-place R7 Release PCK SHA-256: `4185e8a0c04c6205c258973abd821ff17f2f8e12b09650a5bd912d14587e0aaf` (59,320,264 bytes).
- Engine: Godot 4.7.1 Stable / Compatibility / Web HTML Release.
- Deployment/publication: **not performed**.

## Known limitation / next required evidence

The actual public Release H02 selection → movement under active environment effect → existing battle → defeat → exact map-position return → browser refresh recovery remains unverified. The isolated Release session starts at N01, and no development-only unlock is present in Release; this report keeps the R16 overall verdict blocked until a legitimate H02-ready Release QA state can be used.

## FINAL

**BLOCK — continue with the exact outstanding Release H02 E2E.**

## Current continuation note — 2026-08-25

The outstanding Release evidence was advanced in a new clean namespace
`hard-release-cert-r15` with developer override disabled. N01→N10, direct N10
Result, H01 defeat→legitimate growth→retry victory, and H02 defeat/reward-zero/
hostile-retention/attempt-persistence were observed. H02 retry then correctly
showed the normal `작전력 부족` entry gate. GPT Web reviewed this latest evidence
in the existing session and found no code defect; H02→H05 and H05 reload remain
**UNVERIFIED** until natural stamina recovery permits the same Release save to
continue. Deployment remains not performed.

The resumed bounded check also re-ran R15 `49/49` and map `234/234`, including
the N08 repeat-reward boundary. GPT Web confirmed the same order remains valid:
preserve the save, wait for ordinary recovery, then H02→H03→H04→H05 and H05
reload persistence. No developer override, save reset, deployment, upload, or
cache deletion was used.

The 2026-08-25 continuation reached H02 at `12/124` through actual multi-pulse
movement and WAIT, entered the unchanged real-time battle on physical contact,
and recorded a 20.83s defeat with no reward. H02 hostile retention, exact
pre-contact return, and reload → Continue → Home → HARD map restoration were
verified. The authored H02 attempt cap is now `3/3`; the date-change reset path
is present in `AppState`, but a real date-boundary browser check is still
**UNVERIFIED**, as are H02 victory, H03–H05, and H05 reload persistence.

The subsequent isolated Release `capacity-web-r15` check loaded Title →
Prologue → Chapter 1 map on the same PCK and showed `이동 7/7`, the 96-hex
long-distance terrain, squad pawn, and encounter marker. GPT Web classified
map entry, movement-capacity HUD, long-map rendering, and pulse/WAIT as PASS.
Direct browser attribution of VT03/HT03 route-module `+1/+1` remains
**UNVERIFIED**; no code or save authority was changed.
