# R15 Final Report

Date: 2026-08-24 (Asia/Seoul)

## Superseding current verification — 2026-08-25

The dated sections below remain the contemporaneous R15 evidence.  The current
source was rerun after the full-length local BGM repack and fixed-name Web
rebuild:

- Runtime combat/map/VFX integration: players **8/8**, enemies **11/11**,
  static-card battle fallback **0**.  This is a runtime connection statement;
  the retained R15 character QA table correctly keeps CHR001 static
  illustration/portrait quality as **PARTIAL / pending art review**.
- Latest balance matrix: `R15_CH01_BALANCE_MATRIX.json`, **90 cells / 18,000
  shipping-BattleSimulation runs**.  Its current target audit is **13 PASS / 0
  FAIL / 0 UNVERIFIED**.
- Current regression: static **70/70**, Godot core/runtime **165/165**, SRPG
  map **249/249**, R15 **49/49**, R16 environment **26/26** — **559/559 PASS**.
- Current in-place Release PCK: `builds/web_release/index.pck`, `62,791,336`
  bytes, SHA-256
  `148efe50fd4327b97de86b921cfe156b41626eb323ce9369c4191614053194e1`.
- Fresh post-audio full browser traversal and the normal-Release H02→H05
  evidence remain **UNVERIFIED**.  They are not implied by these automated or
  headless checks.  No deployment or upload has been performed.

## CONTENT

- 플레이어 runtime combat pack: **8/8**.
- 적 runtime combat pack: **11/11** (일반 6 / 엘리트 3 / 보스 2).
- runtime static-card fallback: **0**.
- Chapter 1 stage data: NORMAL **10**, HARD **5**.
- Scenario data: **9**.
- 런타임 자산 연결은 검증됐지만 프로덕션 미술 승인은 별도다. `PRODUCTION_APPROVED = WAITING_USER_APPROVAL`.

## BALANCE

정본 `BattleSimulation`을 사용한 최신 매트릭스는 셀당 200 seeds, 총 18,000 runs다.

- N01 RECOMMENDED AUTO: 100.0%, 평균 17.07초.
- N05 RECOMMENDED AUTO: 88.5%, 평균 25.14초.
- N10 RECOMMENDED AUTO: 83.5%, 평균 47.43초.
- N10 SCRIPTED_MANUAL_ULTIMATE: 91.5%, 평균 49.43초.
- H01 RECOMMENDED AUTO: 77.5%, 평균 30.01초.
- H05 RECOMMENDED AUTO: 50.5%, 평균 69.72초.
- H05 SCRIPTED_MANUAL_ULTIMATE: 59.5%, 평균 73.60초.

목표 audit 13개 지점은 13 PASS / 0 FAIL이다. 상세 정본은 `reports/r15/R15_BALANCE_TARGET_EVALUATION.json`, 전체 표는 `R15_NORMAL_BALANCE.md`와 `R15_HARD_BALANCE.md`다.

## PROGRESSION

별도 근사 계산기가 아니라 실제 `BattleSimulation` → reward commit → `GrowthAffordabilityAnalyzer` 및 성장 서비스 → save/reload 경로로 fresh-save CH01-N01~N10을 각 10/10 완료했다. N03/N05/N07/N09/N10 scripted reload checkpoint도 PASS했다. 최종 대표 편성 상태는 다음과 같다.

| Character | Level | Breakthrough | Skills N/P/U | Weapon |
|---|---:|---:|---|---|
| CHR001 | 10 | B0 | 3/2/2 | Lv.8 T1 |
| CHR002 | 10 | B0 | 2/1/1 | Lv.8 T1 |
| CHR003 | 19 | B0 | 1/1/1 | Lv.8 T1 |
| CHR004 | 10 | B0 | 1/1/1 | Lv.9 T1 |
| CHR005 | 12 | B0 | 1/1/1 | Lv.8 T1 |

이는 headless 서비스 흐름 증거이며 최신 Release에서 N01→N10을 사람이 연속 플레이했다는 뜻은 아니다.

## EXPLORATION / BATTLE ROUNDTRIP

- Map, patrol, awareness, wait, relay, event, intel, visible/hidden treasure, optional progression 및 저장 관련 map assertions: **200/200 PASS**.
- 실제 Release 1280×720: H02 선택 → grounded path → 이동/contact → 기존 5인 실시간 전투 → 19.07초 패배 → 정확한 맵 위치 복귀 → hostile 유지 → reload 복구 PASS.
- 같은 현재 소스 Development Web: H01 40.63초 승리, 생존 5명, reward, H02 unlock, grounded return PASS.

## TESTS

| Suite | Pass | Fail |
|---|---:|---:|
| Static | 67 | 0 |
| Godot runtime | 149 | 0 |
| SRPG map | 200 | 0 |
| R15 | 47 | 0 |
| **Total** | **463** | **0** |

## WEB / PACKAGE

- Final HTML ZIP: 66,259,197 bytes, SHA-256 `82555D8EDAD76C17E731623A3F8F17DE6B062A6704F740463850A1987FB5A41D`.
- 실제 Release console errors/warnings: **0 / 0**.
- latest RAF window: 평균 99.4 FPS, p50/p95/p99 10.0/10.1/10.1 ms.
- 약 116초의 기능 QA이며 20분 controlled soak는 **UNVERIFIED**.
- 실물 모바일 QA는 **UNVERIFIED**; `390×844`, `915×412`는 headless layout metric 검증만 PASS.

## FINAL VERDICT

## CURRENT RELEASE CHECKPOINT (2026-08-25)

- 최신 Web Release에서 동일 `hard-release-cert-r15` 저장을 사용해 H02를
  실제로 선택하고, 33구간 경로를 여러 7/7 이동 pulse와 WAIT로 진행해
  H02 hex에 도달했다. 접촉 시 별도 재클릭 없이 기존 실시간 전투로
  진입했다.
- H02 결과는 20.83초 DEFEAT / 생존 0 / 보상 없음이었다. hostile pawn,
  패배 전 위치, reload 후 HARD 맵 상태가 유지됐다. 이 경로는 PASS다.
- H02 attempts는 authored daily limit인 3/3에 도달했다. 코드에는
  `Time.get_date_string_from_system()` 날짜 변경 시 카운터를 비우는
  reset 경로가 있으나 실제 날짜 경계 브라우저 확인은 아직 수행하지
  않았으므로 `HARD_ATTEMPT_RESET_ACTUAL_WEB = UNVERIFIED`다.
- 최신 직접 회귀 집계는 Static 70/70, Godot core 165/165, SRPG map
  234/234, R15 49/49, R16 26/26 = **544/544 PASS**다.
- H02 승리, H03, H04, H05, H05 이후 reload persistence는 여전히
  **UNVERIFIED**이며, 이를 승리로 추정하거나 개발자 권한으로 보완하지
  않는다.

## RELEASE MAP CAPACITY CHECKPOINT (2026-08-25 15:54)

- A separate `capacity-web-r15` Release sandbox loaded Title → Prologue →
  Chapter 1 map from the current PCK and visibly showed `이동 7/7`, the
  96-hex long-distance terrain, squad pawn, and encounter marker.
- GPT Web reviewed map entry, capacity HUD, long-map render, and pulse/WAIT as
  PASS. Direct browser proof that VT03/HT03 route modules individually add
  `+1/+1` remains **UNVERIFIED**. The H02 same-day `3/3` gate and all
  date-boundary/H02→H05/H05-reload evidence states are unchanged.

- SYSTEM / DATA / BALANCE REGRESSION: **PASS**.
- CURRENT-SCOPE WEB MAP↔BATTLE↔MAP / SAVE: **PASS**.
- LATEST RELEASE FULL NORMAL 10 + HARD 5 CONTINUOUS E2E: **UNVERIFIED**.
- CHAPTER 1 PRODUCTION ART APPROVAL: **WAITING_USER_APPROVAL**.
- PUBLIC DEPLOYMENT: **NOT PERFORMED**.

따라서 `CHAPTER 1 VERTICAL SLICE` 전체를 최종 프로덕션 PASS라고 확대하지 않는다. 현재 판정은 **기능 MVP 검증 범위 PASS / 전체 연속 E2E와 프로덕션 승인 대기**다.
