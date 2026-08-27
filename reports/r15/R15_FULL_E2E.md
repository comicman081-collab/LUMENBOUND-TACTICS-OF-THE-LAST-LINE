# R15 Full E2E Status

Date: 2026-08-24 (Asia/Seoul)

## 실제 최신 Release 실행 범위

1280×720 인앱 브라우저에서 다음을 실제 수행했다.

`TITLE → HOME → CHAPTER MAP → H02 선택 → 경로 이동 → hostile 접촉 → 기존 5인 실시간 SD 전투(3×) → 19.07초 패배/생존 0 → RESULT → MAP 복귀 → H02 hostile 유지 → reload → TITLE → HOME → 동일 MAP 상태 복구`

결과:

- 접촉 전 전투 시작 0, 접촉 시 전투 1회: PASS.
- 패배 보상/클리어 오적용 0: PASS.
- 전투 직전과 인접한 정확한 grounded party 위치 복구: PASS.
- hostile H02 유지: PASS.
- reload 진행 상태 복구: PASS.
- console errors/warnings: 0 / 0.

같은 현재 소스의 Development Web에서는 H01을 40.63초, 생존 5명으로 승리했고 reward → H02 unlock → grounded map return까지 확인했다.

## 자동 E2E 성격의 검증

- 실제 `BattleSimulation` → reward commit → growth service → save/reload 경로의 fresh-save CH01-N01~N10: 각 10/10 PASS.
- N03/N05/N07/N09/N10 scripted reload checkpoint: PASS.
- NORMAL/HARD 전투 매트릭스: 18,000 actual `BattleSimulation` runs.
- 전체 회귀: 463/463 PASS.

## 남은 전체 흐름 게이트

최신 Release 바이트에서 신규 save로 story를 포함해 N01→N10을 연속 완주한 뒤 HARD H01→H05까지 연속 완주하는 수동 브라우저 세션은 수행하지 않았다. 따라서 다음 총괄 판정은 **UNVERIFIED**다.

`NEW SAVE → STORY → NORMAL N01-N10 → BOSS/OUTRO → HARD H01-H05 → SWEEP/DAILY ATTEMPT → SAVE/RELOAD`

실물 모바일 터치/device 실행과 20분 controlled browser soak도 **UNVERIFIED**다. 공개 배포는 수행하지 않았다.

## 2026-08-25 Release continuation checkpoint

The same `hard-release-cert-r15` namespace was continued after ordinary
operation-power recovery to 12/124. H02 was physically approached over a
33-hex preview using repeated 7/7 movement pulses and WAIT. Contact entered the
existing real-time battle automatically. The 20.83s defeat produced no reward;
the hostile H02 pawn and exact pre-contact position were restored and survived
reload → Continue → Home → HARD map. H02 attempts reached the authored 3/3
daily limit. The date-change reset path exists in `AppState`, but real browser
verification across the date boundary is **UNVERIFIED**. H02 victory, H03,
H04, H05, and H05 reload remain **UNVERIFIED**.

The current direct test aggregate is Static 70/70, Godot core 165/165, SRPG
map 234/234, R15 49/49, and R16 26/26: **544/544 PASS**. No code/data/save
edit, developer override, system-clock change, deployment, upload, or cache
deletion was used.
