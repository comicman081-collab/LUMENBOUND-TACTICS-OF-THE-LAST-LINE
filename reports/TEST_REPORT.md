# Test Report

Date: 2026-08-24 (Asia/Seoul)

## Superseding current local verification — 2026-08-25

The dated report below is retained as historical evidence. The latest local
source was re-run after the full-length local BGM repack and in-place Web
rebuild; the current measured suite is:

| Suite | Executed | Pass | Fail |
|---|---:|---:|---:|
| Static data/source/policy | 70 | 70 | 0 |
| Godot runtime | 165 | 165 | 0 |
| SRPG map | 249 | 249 | 0 |
| R15 content/result transaction | 49 | 49 | 0 |
| R16 environment FX | 26 | 26 | 0 |
| **Current aggregate** | **559** | **559** | **0** |

The in-place current Release PCK is `62,791,336` bytes, SHA-256
`148efe50fd4327b97de86b921cfe156b41626eb323ce9369c4191614053194e1`.
It booted in one temporary in-app-browser tab and a trusted title-button input
reached Home; the tab and local server were closed immediately afterward. This
verifies the rebuilt asset package boots after the audio change. It does not
claim human listening/mix approval or a new full gameplay E2E. Earlier direct
Release map and battle evidence remains historical; latest-Release
N01–N10/H01–H05 continuous browser completion remains **UNVERIFIED**.

### Full-length BGM repack — 2026-08-25

- Title BGM no longer has a 30-second excerpt cap; its packaged MP3 is the
  complete user-supplied stream (`4,097,476` bytes).
- Lobby, story, battle and boss BGM each retain their full approximately
  89.94-second composition at 14 kHz mono runtime delivery. The original Sound
  files remain unchanged.
- The existing two-player `1.8`-second BGM pre-end crossfade remains the loop
  transition mechanism. Core audio assertions covering full-length streams,
  loop end frames, crossfade, start gating and recovery all passed.
- `SYNC_LOCAL_AUDIO.ps1`, Development Web build, and Release Web build now use
  the local Python 3.14-capable audio builder before packaging, so future
  fixed-name R7 rebuilds cannot silently restore short excerpts.

### Current Release direct N10 regression — 2026-08-25

The current PCK was then exercised with direct in-app-browser pointer input,
not DOM/canvas synthetic clicks:

- Title → Home → Chapter Map completed.
- The visible `제1장 NORMAL 10 · 대형 조우` pawn was selected and its route
  confirmation was pressed.
- The party completed physical map movement and entered the existing real-time
  battle automatically; no second start button or duplicate battle was used.
- The run ended in `DEFEAT` at 21.97 seconds with zero rewards, as expected for
  a defeat. Returning through Home to Chapter Map left the N10 hostile pawn
  unresolved and visible.
- A browser refresh followed by Title → Home → Chapter Map restored the same
  unresolved N10 pawn and the party's pre-contact map position. Console
  errors/warnings were **0 / 0**.

This is a direct Release N10 contact/defeat/reload boundary result. It is not
a continuous N01–N10/H01–H05 certification, and no victory reward or unlock
claim is inferred from this defeat run.

### Isolated Development companion-event traversal — 2026-08-25

An isolated `127.0.0.2:8078` Development origin was used so the user-facing
Release save was not modified. The tested PCK was
`builds/web_development/index_dev_eeaca5f171403a7c.pck`
(`59,325,784` bytes, SHA-256
`9412e1c51b6208ec3b1a20e1df3e7e11308c59414d4d1ea6e47bed83ba081b5b`).
With the development-only stage-unlock helper enabled, a requested HARD route
was intentionally truncated by the first unresolved special encounter, which
is the required path-safety behavior.

- The squad consumed its current movement pulse and stopped before the
  unresolved contact; the map displayed the movement-exhausted notice.
- `대기` refilled the next pulse to `8/8` without moving the squad.
- Continuing the route reached the `! 단절된 중계선 · 토아` contact card,
  which displayed Toa's companion SD instead of a generic enemy pawn.
- Contact handed off to the unchanged real-time battle. The isolated
  development run won in 14.13 seconds; result inventory rows showed exact
  before/after quantities and the progression copy stated that Toa is tracked
  again after Chapter 1 NORMAL 9, proving deferred rather than immediate
  recruitment.
- Result → map → refresh kept the resolved event state without replaying the
  contact or duplicating its reward. Console errors/warnings were **0 / 0**.

This is a development fixture, not a Release HARD-completion certification.

현재 `R7` 고정 이름의 Godot 4.7.1 Compatibility Web MVP를 최종 재검증한 결과다. 이전 중간 집계는 재사용하지 않았다.

## 자동 회귀 테스트

| Suite | Executed | Pass | Fail | Evidence |
|---|---:|---:|---:|---|
| Static data/source/policy | 67 | 67 | 0 | `reports/static_validation.json` |
| Godot runtime | 149 | 149 | 0 | `godot/.runtime_profile/runs/13612-1787508748698/.../godot.log` |
| SRPG map | 200 | 200 | 0 | `godot/.runtime_profile/runs/19216-1787508759020/.../godot.log` |
| R15 content/result transaction | 47 | 47 | 0 | `godot/.runtime_profile/runs/8684-1787508766964/.../godot.log` |
| **Total** | **463** | **463** | **0** | 네 suite의 실제 최종 요약 합계 |

각 러너는 별도 skipped 합계를 출력하지 않으므로 skipped 수치는 주장하지 않는다.

주요 회귀 범위:

- 플레이어 8명, 적 11종, Chapter 1 NORMAL 10/HARD 5, 시나리오 9편의 데이터와 런타임 연결.
- 30 Hz 결정론적 전투, 동일 seed final/event hash, 1×/3× 결과 동등성, 일시정지, 보호막·상태이상·보스 페이즈·풀링.
- 장거리 axial hex 경로, 지형 차단, 카메라 지면 보정, 순찰·경계·릴레이·이벤트·보물·빠른 이동·전투 왕복·저장 복구.
- 보상/첫 클리어/결과 transaction의 정확히 1회 처리와 reload 중복 방지.
- 캐릭터 EXP `905,520`, 캐릭터 크레딧 `412,400`, 무기 EXP `144,330`, 스킬 `10/10/5`, B0-B5, T1-T6 회귀.
- `390×844` 세로 및 `915×412` 가로의 터치 크기·재배치 수학 검증.
- 사용자 소유 로컬 오디오 15개 해석, Web WAV loop endpoint, 시작 제한 및 circuit-breaker 회귀.

별도 `RUN_R15_PROGRESSION.ps1`도 PASS했다. 실제 `BattleSimulation` → reward commit → growth service → save/reload 경로로 fresh-save CH01-N01~N10을 각 10/10 완료했고, N03/N05/N07/N09/N10 scripted reload checkpoint도 PASS했다. 이는 서비스 기반 headless E2E이며 위 463개 assertion 합계에 중복 가산하지 않는다.

## 실제 인앱 브라우저 Release QA

실제 Release를 1280×720 인앱 브라우저에서 다음 범위로 조작했다.

- 타이틀 → 홈 → Chapter map: PASS.
- H02 선택 시 사용자용 현지화 문구와 지면에 붙은 경로/말 표시: PASS.
- H02 이동 → 실제 접촉 → 기존 5인 실시간 SD 전투 진입: PASS.
- 3× 전투, 19.07초 패배, 생존 0명: 실제 관찰.
- 결과 → 맵 복귀 시 전투 직전과 인접한 정확한 지면 좌표 복구: PASS.
- 패배한 H02 hostile 유지 및 보상/클리어 오적용 없음: PASS.
- reload 후 타이틀 → 홈 → 맵에서 동일 진행 상태 복구: PASS.
- 캡처된 console errors/warnings: **0 / 0**.

같은 현재 소스의 Development Web QA에서는 H01을 40.63초, 생존 5명으로 승리했고 보상 적용, H02 해금, 지면 복귀까지 실제 확인했다. 이는 Release H02 패배 경계와 함께 승리/패배 양쪽 왕복 증거로 사용하되, Chapter 1 전체 N01-N10/H01-H05를 최신 Release 바이트로 완주했다는 의미는 아니다.

## 성능·오디오 검증 경계

- 실제 Release 관찰 시간: 약 116초.
- 최신 RAF window: 평균 99.4 FPS, p50 10.0 ms, p95 10.1 ms, p99 10.1 ms, 100 ms 초과 long frame 0.
- 관찰된 맵 최대/대표 부하: draw calls 약 3,727, nodes 4,257, objects 7,068, orphan 0.
- 위 값은 짧은 기능 QA이며 브라우저당 20분 controlled soak가 아니다. 장시간 GPU·메모리 PASS는 **UNVERIFIED**다.
- Web에서 20초 WAV BGM의 `loop_end=441000`과 playback position 순환, lobby/battle stream, enemy attack/hit, player gun/hit/skill/ultimate event count, failures 0을 확인했다.
- 자동화로 실제 소리를 사람 귀로 평가하지 않았으므로 음질·음량·장면별 체감 믹스는 **UNVERIFIED**다.

## 미검증/제외

- 실물 모바일 기기의 터치·safe area·성능 QA: **UNVERIFIED**.
- 최신 Release로 Chapter 1 NORMAL 10 + HARD 5 전체 연속 플레이: **UNVERIFIED**.
- 프로덕션 아트 승인: `WAITING_USER_APPROVAL`.
- Windows EXE, APK, AAB: 생성하지 않음.
- 공개 배포/호스팅: 수행하지 않음.
