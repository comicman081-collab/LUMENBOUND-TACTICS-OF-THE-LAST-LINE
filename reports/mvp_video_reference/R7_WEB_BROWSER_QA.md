# R7 Web Browser QA

Date: 2026-08-24 (Asia/Seoul)

## 검증 빌드

- Web ZIP: `D:\AI 종합 폴더\Games\블아 like\SD_STORY_RPG_GODOT\builds\SD_STORY_RPG_HTML.zip`
- ZIP bytes: **66,259,197**
- ZIP SHA-256: `82555D8EDAD76C17E731623A3F8F17DE6B062A6704F740463850A1987FB5A41D`
- ZIP members: **18**
- Runtime PCK bytes: **56,607,840**
- Runtime PCK SHA-256: `E06F8F13E16FFF9F0690331C0FE95A191E4CDE32B2EA28CE18AFFEAA5B70C84A`
- Build/revision: `LANTERNLINE_R7_WEB_MVP` / `R7`
- Browser: Codex in-app browser, local HTTP origin, 1280×720.
- Public deployment: **NOT PERFORMED**.

## 실제 Release 사용자 흐름

최종 Release에서 다음을 실제 조작했다.

1. 타이틀 → 홈 → Chapter map 진입.
2. H02 hostile을 선택하고 사용자용 현지화 encounter 정보와 지면 위 경로를 확인.
3. 이동을 확정해 부대 말이 실제 경로를 이동.
4. hostile 접촉 시 별도 stage-card 우회 없이 기존 5인 실시간 SD 전투 진입.
5. 3× 전투에서 19.07초 패배, 생존자 0명 확인.
6. 결과 화면에서 맵으로 복귀.
7. 부대가 전투 직전과 인접한 정확한 지면 좌표로 복구되고 H02 hostile이 유지됨을 확인.
8. reload 후 타이틀 → 홈 → 맵으로 재진입해 동일 상태 복구 확인.

| Check | Result |
|---|---|
| Godot Web boot / title / home | PASS |
| Chapter map 진입 | PASS |
| H02 현지화 선택 및 grounded route | PASS |
| 실제 이동 후 접촉 전투 | PASS |
| 기존 5인 실시간 SD 전투·3× | PASS |
| 패배 시 hostile 유지·정확한 위치 복귀 | PASS |
| reload 진행 상태 복구 | PASS |
| Captured console errors | 0 |
| Captured console warnings | 0 |

같은 현재 소스의 Development Web QA에서는 H01을 40.63초, 생존 5명으로 승리하고 보상, H02 해금 및 grounded map return을 확인했다. Release 패배 흐름과 함께 승리·패배 양쪽 상태 전환의 실제 증거다.

## 자동 회귀와 검증 경계

- Static: 67/67 PASS.
- Godot runtime: 149/149 PASS.
- SRPG map: 200/200 PASS.
- R15: 47/47 PASS.
- Total: **463/463 PASS**, FAIL 0.

최신 Release에서 Chapter 1의 NORMAL N01-N10과 HARD H01-H05를 한 세션으로 모두 완주하지 않았다. 따라서 위 실제 H01/H02 범위를 전체 Chapter E2E PASS로 확대하지 않는다.

## 반응형·모바일

| Viewport | Evidence | Result |
|---|---|---|
| `1280×720` | 실제 인앱 Release 조작 | PASS (위 범위) |
| `390×844` | touch target, portrait reflow, bottom action/layout의 결정론적 headless metric | PASS (자동 검증) |
| `915×412` | compact landscape touch/layout의 결정론적 headless metric | PASS (자동 검증) |

실물 휴대전화 터치, 상·하단 시스템 바, safe area, 발열 및 장시간 성능은 실행하지 않았으므로 **UNVERIFIED**다.

## 런타임 이미지·오디오

- 맵과 전투에서 연결된 부대/적 이미지, 실제 5인 전투, projectile/VFX가 표시됐다.
- Web runtime에서 20초 WAV BGM의 `loop_end=441000`과 playback position 순환을 확인했다.
- lobby/battle stream이 활성화됐고 enemy attack/hit, player gun/hit/skill/ultimate event count가 기록됐으며 audio failures는 0이었다.
- 자동화가 사람의 청각 평가를 대신하지 않으므로 음질·볼륨·장면별 체감 믹스는 **UNVERIFIED**다.
- 런타임 연결은 프로덕션 미술 승인과 다르다. `PRODUCTION_APPROVED = WAITING_USER_APPROVAL`이다.

## RAF·부하 관찰

- 실제 Release 관찰 시간: 약 116초.
- 최신 RAF window: 평균 99.4 FPS.
- frame time: p50 10.0 ms / p95 10.1 ms / p99 10.1 ms.
- 100 ms 초과 long frame: 0.
- map draw calls 약 3,727, nodes 4,257, objects 7,068, orphan 0.
- console errors/warnings: 0 / 0.

이는 짧은 기능 QA다. 브라우저당 20분 controlled foreground GPU·메모리 soak가 아니므로 장시간 Web 성능 PASS는 **UNVERIFIED**이며, draw-call/node 최적화 여지도 남아 있다.

## 판정

- 최종 Release 실제 H02 접촉 전투·패배·맵 복귀·reload: **PASS**.
- 동일 현재 소스 Development H01 승리·보상·H02 해금: **PASS**.
- 자동 회귀: **463/463 PASS**.
- 최종 Release Chapter 1 전체 연속 E2E: **UNVERIFIED**.
- controlled 20분 Web soak: **UNVERIFIED**.
- physical mobile QA: **UNVERIFIED**.
- audible perceptual audio QA: **UNVERIFIED**.
- production art approval: **WAITING_USER_APPROVAL**.
- deployment: **NOT PERFORMED**.

표시된 실제 범위를 넘어 전체 제품 PASS를 주장하지 않는다.
