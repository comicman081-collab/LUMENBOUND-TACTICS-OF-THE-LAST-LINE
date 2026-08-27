# MVP 이벤트 동료 조우 흐름 보완

## 범위

사용자가 제공한 세 로컬 참고 영상에서 추상화한 `맵의 사건 표식 → 짧은 사건 인지 → 기존 전투 → 결과에서 변화 전달 → 같은 맵 복귀` 문법을 현재 Chapter 1의 동료 조우 두 곳에 보완했다. 참고 영상의 캐릭터, 지형, UI, 전투 방식 또는 고유 문구는 사용하지 않았다.

## 실제 연결

| 조우 | 맵 표현 | 접촉 | 승리 결과 | 저장 상태 |
|---|---|---|---|---|
| `NODE_N04` / 베라 | 베라의 실제 SD MAP_IDLE 팩 + 청록 `!` 펄스 | 부대가 도착하면 자동 신호 카드 후 기존 실시간 전투 | 즉시 편성 가능 상태로 전환하고 결과에 동료 합류 표시 | event/recruitment 상태와 map transaction 저장 |
| `NODE_N08` / 토아 | 토아의 실제 SD MAP_IDLE 팩 + 청록 `!` 펄스 | 부대가 도착하면 자동 신호 카드 후 기존 실시간 전투 | 합류 신호 추적 상태를 표시, N09 클리어 후 실제 편성 해금 | pending/ready recruitment 상태 저장 |

두 조우 모두 선택만으로 전투를 시작하지 않는다. 경로 확인과 실제 부대 이동 후 접촉해야 하며, 접촉 뒤 별도 전투 확인 버튼도 없다.

## 변경 위치

- `godot/autoload/app_state.gd`
  - map encounter transaction에 presentation-only `special_event` payload를 함께 보관한다.
  - payload는 전투·보상·RNG·이동 판정 권한이 아니며, abandon/결과 처리 시 함께 제거된다.
- `godot/chapter_map/runtime/chapter_map_screen.gd`
  - event companion pawn은 hostile fallback 대신 해당 CharacterDef의 packaged SD MAP_IDLE atlas를 사용한다.
  - `!` marker와 ground ring이 소폭 pulse하여 지형 안에서도 사건 조우가 읽힌다.
- `godot/screens/app_shell.gd`
  - 접촉 후 1.25초의 자동 특별 신호 카드가 지나간 뒤 기존 BattleScene으로 전환한다. 카드에는 실제 동료 초상화, 이름과 현장 문구를 표시한다.
  - Reward/Growth 결과의 진행 변화 섹션이 즉시 합류와 이후 합류 추적을 구분하고, 실제 CharacterDef/localization 이름만 표시한다.
  - 동료 사건 승리 결과의 대표 일러스트는 더 이상 무관한 파티 리더가 아니라 실제 사건 동료의 portrait asset을 우선 사용한다. 일반 전투 결과는 기존 리더 portrait를 유지한다.
- `tools/generate_data.py`
  - 조우 및 결과 copy를 한국어/영어 localization key로 추가했다.

## 검증

2026-08-25에 다음을 실제 실행했다.

| 검증 | 결과 |
|---|---:|
| core Godot headless regression | 153 / 153 PASS |
| SRPG map + companion event regression | 225 / 225 PASS |
| R16 environment regression | 26 / 26 PASS |
| static audit | 67 / 67 PASS |
| Web Release local load and input | PASS — one in-app-browser tab loaded the rebuilt title, accepted title input, reached Home and Story, then closed cleanly |
| Companion event Development Web E2E | PASS — N04 immediate join and a fresh N08 → N09 deferred join run both used ordinary map selection, movement-pulse/contact, the existing realtime battle, result presentation and the authored post-N09 story trigger |
| Companion event Release Web E2E | PASS — a fresh Release sandbox progressed Prologue → N01 → N02 → N03 → N04 with ordinary movement pulses/waits, then completed the real N04 companion contact, recruitment, map return and refresh recovery |
| browser error/warn log | 0 / 0 on the current Release title/story, Release N04 E2E and Development N04 E2E |

현재 실제 Web 증거는 `reports/mvp_video_reference/WEB_TITLE_CURRENT_QA.png`와 `reports/r16_environment/38_RELEASE_STORY_TYPOGRAPHY_WEB.png`이다. 전자는 현 Release가 제목에서 Home으로 입력 전환되는 것을, 후자는 Story가 실제로 기동되는 것을 확인한 캡처다. Development N04 E2E 증거는 `01_N04_COMPANION_EVENT_MAP_WEB.png`, `02_N04_SPECIAL_CONTACT_BATTLE_WEB.png`, `03_N04_COMPANION_RECRUIT_RESULT_WEB.png`, `07_N04_DIRECT_MAP_RETURN_WEB.png`, `08_N04_COMPANION_RESULT_ART_WEB.png`다. Release new-save N04 E2E 증거는 `09_RELEASE_N04_COMPANION_SELECTED_WEB.png`, `10_RELEASE_N04_SPECIAL_SIGNAL_WEB.png`, `11_RELEASE_N04_RECRUIT_RESULT_WEB.png`, `12_RELEASE_N04_DIRECT_MAP_RETURN_WEB.png`, `13_RELEASE_N04_RELOAD_RESTORED_WEB.png`다. 이 묶음은 실제 베라 SD MapPawn/선택 패널, 특별 신호 카드, 베라 portrait와 합류·NEW 성장 결과, 직접 맵 복귀, 새로고침 후 같은 canonical 맵 상태를 각각 보인다. 과거에 나열된 N04 캡처 다섯 장은 현재 작업 트리에 존재하지 않아 증거로 사용하지 않는다.

동일한 Release sandbox를 N05→N09까지 계속 진행해 토아의 N08 특별 조우와 지연 합류도 확인했다. `14_RELEASE_N08_COMPANION_SELECTED_WEB.png`는 토아의 localized 특별 조우 패널과 실제 이동 경로를, `15_RELEASE_N08_TRACKING_RESULT_WEB.png`는 토아 portrait와 “제1장 NORMAL 9 이후에 다시 추적”이라는 결과 copy를 보인다. 이어진 실제 N09 승리에서 토아의 편성 합류 문구가 표시되는 것을 확인했다. 이 관찰에서 지연 합류 결과의 대표 portrait가 기존 파티 리더로 남는 결함을 발견했고 수정했다: 현재 `_result_feature_character`는 `newly_recruited_characters`를 special-event payload보다 먼저 해석한다. 새 core regression은 immediate `CHR006`과 deferred `CHR007` 양쪽 모두 실제 동료 asset을 선택하는지 검증한다.

수정 후 Development Web에서 fresh N08 → N09를 다시 끝까지 검증했다. `16_DEVELOPMENT_N08_COMPANION_SELECTED_POSTFIX_WEB.png`는 토아의 실제 사건 패널과 이동 확인을, `17_DEVELOPMENT_N08_TRACKING_RESULT_POSTFIX_WEB.png`는 N08 전투 보상 결과의 토아 portrait를, `18_DEVELOPMENT_N09_DEFERRED_RECRUIT_RESULT_ART_POSTFIX_WEB.png`는 N09 승리 결과에 무관한 파티 리더가 아닌 토아 portrait와 토아의 새 성장 후보가 나타나는 것을 보인다. N09의 실제 계속 동작은 작성된 boss-pre story로 전환되며, 이 전환 화면은 `19_DEVELOPMENT_N09_RETURN_POSTFIX_WEB.png`에 남겼다. 이 실행은 단일 임시 in-app-browser 탭에서 수행했고 console warning/error는 0/0이었으며 확인 직후 탭과 8078 서버를 닫았다. 최신 public Release를 N08부터 새로 진행하는 별도의 전체 시각 재확인은 아직 하지 않았으므로, Development 검증을 Release 검증으로 바꾸어 주장하지 않는다.

이번 보강에서 `EVENT_PAWN_RUNTIME_01..03`이 두 이벤트 노드 모두에 대해 실제 MapPawn 생성, 해당 동료 SD `MAP_IDLE` texture, grounded `!` marker를 각각 검증한다. Runtime texture metadata에는 immutable `source_id`를 함께 유지하므로, 동료 조우가 generic hostile/fallback art로 바뀌는 회귀도 검사한다. 이 검증은 Web 시각 E2E를 대체하지 않는다.

## 권한·결정론 경계

- `special_event`는 pending map encounter의 presentation data일 뿐이며 BattleSimulation input, enemy stat, RewardResolver table, map path, movement pulse, save schema version, combat RNG를 바꾸지 않는다.
- 전투 결과 mutation은 기존 pending battle token의 exactly-once 경계를 그대로 사용한다.
- event pawn이 제거되는 시점은 기존 stage clear/map clear authority이며, 실패 또는 포기 시 hostile/event pawn은 유지된다.
