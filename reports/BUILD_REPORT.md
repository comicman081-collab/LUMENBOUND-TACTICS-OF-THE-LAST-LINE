# Build Report

Date: 2026-08-24 (Asia/Seoul)

## Superseding current local Web rebuild — 2026-08-25

The historical package values below are preserved. The latest in-place local
Web Release directory, rebuilt after full-length local BGM synchronization, is:

- `builds/web_release/index.pck` — 62,791,336 bytes — SHA-256
  `148efe50fd4327b97de86b921cfe156b41626eb323ce9369c4191614053194e1`
- `index.wasm` — 39,513,091 bytes — SHA-256
  `35116f68540ac41acf7d71ea457added91b5e960a9cca3e2acc72918eaf01277`
- `index.js` — 279,815 bytes — SHA-256
  `68586d6daafc93c6e697b3fb258976874aa7459b8931165eb1dc3c9614cc42c`
- `index.html` — 7,768 bytes — SHA-256
  `9cc566c932125acbbee38cf3d3f7cf2d626b787d5cb52382b58947bc68207f36`

The current source automated aggregate is 559/559 PASS (70 static + 165 runtime +
249 map + 49 R15 + 26 R16). One temporary in-app-browser tab booted the
rebuilt Release and trusted title input reached Home; that tab and its local
HTTP server were closed after the check. Existing earlier screenshots remain
historical evidence. This is bounded evidence, not a claim of full
N01–N10/H01–H05 completion or a human audio-mix approval. No deployment or
upload was performed.

## 고정 이름 Web / HTML Release

현재 정본 패키징 재실행 결과(고정 파일명을 in-place 갱신):

- `builds/SD_STORY_RPG_HTML.zip` — **68,785,321 bytes** — SHA-256
  `B615EC71154A6A9B5EEA9E23EDBFFEDCB6C328C009EF3AE386DF0F69F2717C93`.
- `builds/SD_STORY_RPG_SOURCE.zip` — **756,339,369 bytes** — SHA-256
  `CFD9D4003EE4E634BB2471EFEFBACD591B0019D8759B0BCD08AAB564B5E1C722`.
- `tools/powershell/PACKAGE_HTML.ps1` now accepts both standard raw Godot
  WebAssembly and the optional deterministic gzip limited-host variant; the
  current package uses standard raw WebAssembly.

Status: **BUILT / PACKAGE INTEGRITY PASS / ACTUAL RELEASE FUNCTIONAL QA PASS (검증 범위 한정)**

- Project: `D:\AI 종합 폴더\Games\블아 like\SD_STORY_RPG_GODOT`
- Engine: Godot `4.7.1-stable (official)` Standard / GDScript.
- Renderer: Compatibility.
- Target: Web HTML Release only.
- Revision/build ID: `R7` / `LANTERNLINE_R7_WEB_MVP`.
- HTML/PWA 표시 이름: `LANTERNLINE`.
- Orientation: landscape + portrait.
- Release directory: `D:\AI 종합 폴더\Games\블아 like\SD_STORY_RPG_GODOT\builds\web_release`.
- Runtime PCK (current): **62,791,336 bytes**, SHA-256
  `148efe50fd4327b97de86b921cfe156b41626eb323ce9369c4191614053194e1`.

`VERSION.json`은 위 PCK 해시, `revision: R7`, `production_approved: false`를 기록한다. 패키지 이름은 버전을 계속 늘리지 않고 고정 이름을 덮어쓰는 정책을 유지했다.

## Historical package table (dated report)

| Package | Bytes | Entries | SHA-256 |
|---|---:|---:|---|
| `builds/SD_STORY_RPG_HTML.zip` | 66,259,197 | 18 | `82555D8EDAD76C17E731623A3F8F17DE6B062A6704F740463850A1987FB5A41D` |
| `builds/SD_STORY_RPG_SOURCE.zip` | 732,472,301 | 4,805 | `D23B22EF576DFB2030912FAE51DCEBD10305B697CB5706BE2F89450665B73017` |

Source 패키지는 staging 중 70개 텍스트 파일에서 개인 경로 177건을 제거한 뒤 생성했다. HTML ZIP에는 실행용 18개 항목만 포함되며 소스 Blender, authoring Python, reference, contact sheet 및 렌더 intermediate는 런타임 패키지 대상이 아니다. Source ZIP 안에 포함된 이 보고서의 사본은 자기참조 해시를 피하기 위해 외부 원장 `builds/SHA256SUMS.txt`를 가리키며, 작업공간의 이 보고서와 외부 원장에는 최종 아카이브 값이 기록되어 있다.

## Historical Release browser evidence (prior checkpoint)

최종 Release를 1280×720 인앱 브라우저의 로컬 HTTP origin에서 실제 실행했다.

- 타이틀, 홈, Chapter map 진입: PASS.
- H02 현지화 선택 패널 및 지면에 붙은 경로/말: PASS.
- 이동·접촉으로 기존 5인 실시간 전투 진입, 3× 실행: PASS.
- 19.07초 패배 후 결과 → 맵 복귀, 정확한 인접 지면 위치와 H02 hostile 유지: PASS.
- reload 후 타이틀 → 홈 → 맵 진행 복구: PASS.
- captured console errors/warnings: **0 / 0**.

같은 현재 소스의 Development Web에서는 H01 40.63초 승리, 생존 5명, 보상, H02 해금과 지면 복귀를 확인했다. 최신 Release에서 NORMAL 10 + HARD 5 전체를 한 번에 완주하지는 않았으므로 이를 전체 Chapter 1 E2E PASS로 확대하지 않는다.

- Latest Release full NORMAL 10 + HARD 5 continuous E2E: **UNVERIFIED**.

## 제외 및 배포 상태

- Windows EXE: **NOT CREATED**.
- Android APK/AAB: **NOT CREATED**.
- Electron/Tauri/NW.js wrapper: **NOT CREATED**.
- Public deployment/hosting: **NOT PERFORMED**. 사용자 명시 승인 전에는 배포하지 않는다.
