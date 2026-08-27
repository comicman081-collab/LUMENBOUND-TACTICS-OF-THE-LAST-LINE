# Web Release rebuild audit

Date: 2026-08-25 (Asia/Seoul)

This is a local, non-deployment rebuild after the treasure landmark localization
contract and runtime Web import repair were applied. The existing
runtime/gameplay authority was not changed.

This supersedes the prior artifact table below: after the repeatability guard in
`tools/powershell/COMMON.ps1`, the fixed-name Web Release was rebuilt twice with
the same inputs and produced the identical PCK hash. No deployment, upload,
service-worker/cache deletion, or public publication was performed.

## Artifact

Path: `builds/web_release/`

| file | bytes | SHA-256 |
|---|---:|---|
| `index.pck` | 59,320,264 | `4185e8a0c04c6205c258973abd821ff17f2f8e12b09650a5bd912d14587e0aaf` |
| `index.wasm` | 39,513,091 | `35116f68540ac41acf7d71ea457added91b5e960a9cca3e2acc72918eaf01277` |
| `index.js` | 279,815 | `68586d6daafc93c6e697b3fb258976874aa7459b8931165eb1dc3c9614cc42c` |
| `index.html` | 7,768 | `9cc566c932125acbbee38cf3d3f7cf2d626b787d5cb52382b58947bc68207f36` |

The rebuilt release also contains `index.service.worker.js` (5,689 bytes,
`eb3b6c96d094e715f67ab253d4ae97f14d466c5c27b3cd7bf5edf37eab855b6a`) and
`VERSION.json` (488 bytes,
`e22a1643d81c1a0cef4f4faf4200c2fa60d262fed4b35ebae35a8a8bb9fcee8d`).

The ENM005 runtime import fault was repaired by removing only its invalid
generated import metadata, re-running the Godot 4.7.1 editor importer, and
adding a static guard that rejects `valid=false` runtime Web import files.

`index.service.worker.js` uses the final artifact fingerprint, the
`LANTERNLINE-sw-cache-` namespace, `skipWaiting()`, `clients.claim()`, and a
network-first navigation fallback. The service worker was not deleted or
manipulated during this check.

## In-app browser technical check

Temporary URL: `http://127.0.0.2:8078/index.html?mvp-release-qa=20260825-fix2`

- Godot canvas present: 1
- Canvas internal size: 1600×900
- CSS viewport size: 1280×720
- Browser console errors: 0
- Browser console warnings: 0
- Runtime logs include Godot 4.7.1 Compatibility/WebGL 2 initialization.
- Temporary QA tab closed after the check.
- Temporary Python server on port 8078 stopped after the check.

CDP screenshots visibly verified the Release title, home, SRPG map, N05 stage
panel and route, N05 real-time battle with premium player/enemy art and skill
VFX, reward/growth result, mandatory story, and map return with N05 cleared and
N06 exposed. The map WAIT action restored the 8-hex movement budget before the
route action. Console errors/warnings during this run were 0/0.

This remains bounded Web evidence; it is not a claim that the full latest
Release N01–N10/H01–H05 continuous run has been completed.

The same temporary Release tab also collected the runtime log buffer after the
N05 victory and N06 movement-limit/defeat checks: 100 log records, 0 warnings,
0 errors, and 100 `R7_WEB_SOAK_SAMPLE` records. The latest sample reported
95 FPS, 3,367 draw calls, 4,090 nodes, 0 orphan nodes, and empty playback
failure counts; recorded event playback counts included battle BGM, story/lobby
BGM, player gun/hit/skill/ultimate, and enemy attack/hit events.

## Current boundaries

- No deployment, upload, or publishing action was performed.
- GPT Web review was not transmitted in this turn.
- No browser site data or service-worker cache was deleted.
