# R16 Web Visual Matrix — interim evidence

## Scope

This record covers the actual local Web/HTML visual captures made after the R16 environment presentation pass. It is evidence for the presentation layer and the listed actual traversal flows; it does not overstate the still-open Release H02 defeat/refresh scenario.

## Development visual matrix

All six presets were captured from the same Web Development runtime at 1280×720. The captures show the player/map terrain, selectable route markers, elevation, and environment treatment together.

| Preset | Evidence | Observed result |
| --- | --- | --- |
| CLEAR_DAY | `01_CLEAR_DAY_WEB.png` | Baseline terrain color and readable interaction markers. |
| MIST_DAY | `02_MIST_DAY_WEB.png` | Cool, depth-separated mist while party and route remain legible. |
| DUSK | `03_DUSK_WEB.png` | Warm grade without a full-screen orange overlay. |
| NIGHT | `04_NIGHT_WEB.png` | Cool low-light grade with terrain elevation still visible. |
| NIGHT_RAIN | `05_NIGHT_RAIN_WEB.png` | Multi-depth rain is visible; party and markers remain readable. |
| STORM | `06_STORM_WEB.png` | Stronger darkness, fog, and rain than NIGHT_RAIN without obscuring the route. |

## Release smoke evidence

| Flow | Evidence | Observed result |
| --- | --- | --- |
| Release normal route | `01_RELEASE_MIST_DAY_NORMAL_ROUTE.png` | Current saved route loaded in MIST_DAY without Web fatal/error output. |
| Release map | `02_RELEASE_MIST_DAY_MAP.png` | Canonical map rendered with map state intact. |
| Cache-clean release title | `08_RELEASE_CACHE_CLEAN_TITLE.png` | Fresh release launch after the development cache hand-off. |
| Cache-clean release map | `10_RELEASE_CACHE_CLEAN_MAP.png` | Title → Home → Chapter map flow completed after cache hand-off. |

## Local cache hand-off verification

Development and Release are intentionally served on the same local origin during QA. The development export now contains a narrowly scoped service-worker hand-off file:

- File: `builds/web_development/index.service.worker.js`
- Scope: removes only cache keys that start with `LANTERNLINE-sw-cache-`, then unregisters itself.
- It does not access save payloads, browser storage, or non-LANTERNLINE cache names.

Actual local server evidence after loading the Development build at `127.0.0.1:8078`:

```text
GET /index.service.worker.js HTTP/1.1 200
```

The development browser console had 10 ordinary Godot log entries and zero entries matching error, warning, 404, service-worker failure, or worker failure. The capture is `07_DEVELOPMENT_CACHE_HANDOFF.png`. The temporary browser tab and local server were closed after verification.

The subsequent cache-clean Release smoke run completed Title → Home → Chapter Map. Its console had 13 `log` entries and zero `warning` or `error` entries. The WebGL 2.0 Compatibility startup line was informational, not an error. Its temporary tab and local server were also closed after the capture.

## Open verification work

- Fresh Release H02 map → battle → defeat → return → refresh E2E after the cache hand-off change.
- Final R16 acceptance may be marked PASS only after that exact Release H02 scenario is captured. The current Release sandbox starts at N01 and exposes no user-facing QA shortcut to H02, so this has not been substituted with a development-only unlock.

## Automated regression rerun

Executed after the story typography and local Web cache-handoff changes:

| Runner | Actual result |
| --- | --- |
| Core headless runner | 151 / 151 PASS |
| SRPG map runner | 219 / 219 PASS |
| R15 content runner | 47 / 47 PASS |
| R16 environment runner | 26 / 26 PASS |
| **Current executed total** | **443 / 443 PASS** |

The older R16 prompt listed a 463-test historical aggregate. The current repository runners execute 443 checks; this record uses the measured runner totals rather than reproducing that stale aggregate.

## Story typography follow-up

The shared Button theme and the resize/orientation reflow now use 16px base button type. Story navigation controls explicitly use 14px desktop / 13px portrait type while preserving their existing touch-target dimensions. Narrative RichText uses 32px desktop / 29px portrait. The corrected Development Web story screen is captured in `11_STORY_TYPOGRAPHY_WEB.png`; its console had five normal `log` entries and zero warnings/errors. The temporary tab and local server were closed after the check.

The local Web Release was rebuilt after this correction. The generated `index.pck` SHA-256 is `37cd22dbe12660f6c68d8c1f874f70b66e3e1f211a69ca05abbec97d00e31d0d`. This was a local build refresh only; no external deployment or publication was performed.

The rebuilt public Release was then loaded locally with an isolated Web-save session. `37_RELEASE_TITLE_POSTFIX_WEB.png` confirms the public title and clean console; `38_RELEASE_STORY_TYPOGRAPHY_WEB.png` confirms the production story layout with the larger narrative line and smaller controls. The Release console had zero warnings/errors. Its temporary tab and local server were closed after the check.

## Development H01 actual round-trip follow-up

The development-only full-map QA capability was corrected so it reveals only the view/navigation allowance needed by the existing debug stage-unlock option; it does not alter persisted fog, rewards, battles, or save state. A real H01 flow then completed:

```text
Hard route → H01 selected → real squad path motion → hostile contact
→ existing 5-unit realtime SD battle → VICTORY → reward/growth result
→ Chapter Map return → H02 next encounter revealed
```

Evidence: `31_DEVELOPMENT_H01_HARD_ROUTE_WEB.png`, `32_DEVELOPMENT_H01_PATH_WEB.png`, `34_DEVELOPMENT_H01_PULSE_WEB.png`, `35_DEVELOPMENT_H01_RESULT_WEB.png`, and `36_DEVELOPMENT_H01_RETURN_WEB.png`. The battle and post-return console contained zero warning/error entries.

## Portrait FX tuning-panel follow-up

The development-only tuning sheet was rechecked at an actual `390×844` portrait Web viewport. Its layout now derives height from the map region rather than treating a CSS-pixel cap as a Godot logical-canvas cap. The sheet keeps the map's header and bottom area unobstructed, exposes all controls through vertical scrolling, and retains the reset control at the end of the scroll content. Evidence: `23_PORTRAIT_FX_PANEL_FINAL_WEB.png`. This followed an R16 headless rerun: `26 / 26 PASS`.

## Actual Web performance samples

The existing in-page RAF probe was enabled only in the local Development export. Each result below aggregates the final twelve five-second probe windows after the selected preset had settled: a measured 60-second interval on the actual map, with the FX panel open. Browser automation used one temporary tab that was closed afterward.

| Preset | Measured interval | Avg FPS | p50 / p95 / p99 | Frames >100 ms | JS heap delta |
| --- | ---: | ---: | ---: | ---: | ---: |
| CLEAR_DAY | 60.01 s | 99.40 | 10.0 / 20.0 / 20.1 ms | 0 | -580,786 B |
| NIGHT_RAIN | 60.00 s | 99.98 | 10.0 / 10.1 / 10.1 ms | 0 | -291,261 B |
| STORM | 60.00 s | 99.97 | 10.0 / 10.1 / 10.1 ms | 0 | -1,451,598 B |

No Web console `warning` or `error` entries were observed during the timed pass. The timed visual evidence is `16_NIGHT_RAIN_TIMED_WEB.png` and `17_STORM_TIMED_WEB.png`; `12_R16_PERF_MAP_DEV.png` and `13_R16_FX_PANEL_DEV.png` record the map and development-only panel state used for the test.
