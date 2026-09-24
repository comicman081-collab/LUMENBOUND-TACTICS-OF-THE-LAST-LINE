# 캐릭터 성장 UI — Ponytail FULL 독립 코드 검토

검토일: 2026-09-08

판정: **PASS — 아래에 명시한 구현·권한·비용·코드 검증 범위.** 실제 브라우저의 모든 해상도 레이아웃, 실기기, 공개 Release 실행과 전체 게임 품질 승인을 포함하지 않는다. 해당 브라우저 검증은 메인 작업에서 계속 진행 중이다.

## 추적한 실행 경로

- 보상 화면의 성장 후보 / 캐릭터 목록 → SceneRouter GROWTH·CHARACTER_DETAIL → AppShell `_show_growth` → 레벨업·스킬업·장비·돌파 카드.
- 훈련 노트 선택 → CharacterProgression.preview → 순수 final_stats 현재/목표 상태 계산 → 실제 use_material → 공통 성장 결과 표시 → SaveService.save_game.
- 스킬 카드 → SkillUpgradeService comparison / next_cost / supports_upgrade → upgrade → AppState.pay → 실제 레벨 증가 → 저장과 카드 재구성.
- 추천 성장 → GrowthPlanBuilder의 실제 서비스 기반 복사 프로필 미리보기 → 최대 12단계 실행 → 정확한 전체 비용·실제 적용 결과 → 성공분 저장. 부분 실패도 이미 적용한 변경을 저장한다.
- 저장 실패 → 화면 내 미저장 표시 → 추가 소비 버튼 비활성화 → 별도 저장 재시도. 재시도는 성장 서비스를 다시 호출하지 않는다.
- 전투 효과의 의미를 BattleSimulation, SkillRuntime, DamageResolver, HealingResolver, StatusEffectRuntime와 대조했다.

## 발견한 원인과 반영 확인

1. 비용·보유량 설명이 실행 버튼과 떨어져 있었고 모바일은 무기·L 노트 중심이었다. 현재 목적별 4탭과 카드 안의 필요/보유/부족·실행 후 변화로 분리했다. 선택 탭과 노트는 다시 그려도 유지한다.
2. 개별 성장의 성공·실패가 숨긴 footer에만 표시되고 즉시 저장되지 않았다. 현재 성장 화면 안에 결과와 저장 상태를 표시하고 즉시 저장한다.
3. 잠긴 캐릭터 보호가 UI 조기 반환에만 의존했다. 레벨·스킬·돌파 서비스에서 unknown/locked 요청을 차감 전에 거부한다.
4. 고정 버프·디버프 궁극기 8종은 데이터 계수가 실제 전투 효과에 사용되지 않았다. 효과 고정이라고 표시하고 추가 구매·추천·보상 후 성장 후보를 같은 판단으로 제외한다. 기존 스킬 레벨·데이터·전투 수치는 그대로 유지한다.
5. 스킬의 소수 계수만 표시하던 문제를 실제 전투 단위로 수정했다. 공격력 대비 계수, 회복력 대비 회복/보호막, 패시브 능력치 증가율, 전체/단일 대상, 감속·도발의 지속시간을 구분한다. AOE .62/.82, 전체 회복 .72, 도발 보호막 .8 보정도 대조했다.
6. 재료가 있어도 티어 상한 레벨 미달인 무기 티어업이 활성화되던 문제는 설명과 비활성 조건으로 보완했다. 장비 선택은 보유한 호환 장비만 제공한다.
7. 획득처는 입장 가능한 스테이지를 우선 사용하고 없을 때 성장 화면 안에 이유를 표시한다. 내부 영문 슬롯 이름은 사용자용 한국어 이름으로 바뀌었다.

## 실제 검증

- `growth_service_authority_runner`: **56/56 PASS**. 고정 8종 각각의 무차감·기존 레벨 보존·추천 제외·보상 후보 제외, unknown/locked 차단, 순수 능력치 미리보기, 정상 스킬의 정확한 비용과 상한 보호.
  - 로그: `reports/gameplay_qa/20260908_growth_service_authority.log`
- 최종 소스 일반 회귀 `test_runner`: **293/293 PASS**, 스크립트 오류 0.
  - 로그: `reports/gameplay_qa/20260908_growth_full_general.log`
- 이전 화면의 변수명을 찾던 성장 관련 검사 세 곳은 실제 생성한 4탭 컨트롤, 주 행동 연결, TouchProgressionScroll, 스킬별 실제 아이콘 텍스처 대조로 바꿨다. 픽셀 배치 검증을 이 코드 검사로 대신하지 않는다.
- 변경 소유 파일 `git diff --check` 통과. 일반 테스트 로그의 기존 자산 경고는 전체 런타임 경고 0 주장과 구분한다.

## 검토 경계

브라우저의 실제 포인터 조작, 카드 전체 가시성, 회전/320px 폭/가로 화면, 저장 후 브라우저 재시작 복원은 메인 브라우저 검증 결과를 별도로 요구한다. 본 검토는 그 결과를 미리 PASS로 처리하지 않는다. 저장 장치 강제 실패 주입과 실물 휴대전화 검사는 수행하지 않았다.

새 서비스 계층·설정·의존성이나 전투 밸런스 변경을 도입하지 않았다. 기존 성장 서비스, 저장 서비스, 실제 데이터, 공유 비용 표기를 재사용했다. 위 범위에서 추가 출시 차단 수준 코드 결함은 발견하지 못했다.

## WDE 외관 변경 추가 검토

추가 판정: **PASS — 성장 UI 외관 변경의 코드·컨트롤 생성 검증 범위.** 메인 작업에서 읽은 WDE ON / STANDARD 설계 기록 `20260908_GROWTH_WDE_DESIGN_READ.md` 및 변경 구현을 대조했다.

- `GrowthMaterialChoices` 이름은 현재 재료의 선택 표현 범위 식별에 사용한다. GridContainer 가용 너비 확장과 가로·세로 간격은 기존 반응형 배율을 사용한다.
- 민트 테두리/문자색은 GrowthTabs, GrowthPartySelector, GrowthMaterialChoices의 선택된 비활성 버튼에만 적용된다. 재료 부족·성장 상한 때문에 실행할 수 없는 강화 버튼에 선택 스타일이 번지지 않는다. 버튼 권한·클릭 연결은 그대로다.
- 패널 안쪽 여백 10, 그리드 간격 6, 스킬 아이콘 폭 32는 같은 `_responsive_control_scale()`로 변환한다. 캐릭터 정보 초상화의 실제 자산·계수·비용·저장 흐름을 바꾸지 않는다.
- 추가 변경 후 일반 회귀 **293/293 PASS**, 스크립트 오류 0. 실제 성장 컨트롤 생성과 스킬 아이콘 대조 검사도 포함한다.
  - 로그: `reports/gameplay_qa/20260908_growth_wde_general.log`
- 이 검토에서 추가 중요 코드 결함은 발견하지 못했다. 브라우저 growth58 전체 레이아웃 결과와 실기기 검사는 별도이며, 본 코드 PASS를 해당 화면 검증 PASS로 해석하지 않는다.

## 최종 가로 전용 정책 추가 검토

사용자의 후속 지시가 이전 세로 UI 계획을 대체했다. 현재 검토 기준은 **가로 화면만 제공**하는 정책이다. 이전 항목의 세로 레이아웃 검증 계획과 초기 WDE 브라우저 대기 상태는 이 절의 최신 확인 범위로 대체한다.

추가 판정: **PASS — 가로 정책 변경의 코드 추적 및 아래 기존 실행 증거를 확인한 범위.** UI 코드 수정 없이 읽기 전용으로 검토했다.

- Web의 `godot/web/landscape.html`은 원래 주소의 쿼리·경로를 유지한 동일 출처 iframe 한 개를 만든다. 내부 프레임 표식으로 중첩 생성을 막으며, 실제 엔진 시작은 내부 프레임에서만 진행한다.
- 호스트 창의 긴 변을 iframe 너비로 사용한다. 세로 기기에서는 iframe 전체를 90도 회전하고, 가로 기기로 돌아오면 표시 회전만 제거한다. resize 콜백은 프레임 URL을 바꾸거나 엔진을 다시 시작하지 않는다.
- 실제 입력은 CSS로 회전한 iframe 경계에서 브라우저가 변환한다. 게임 안에 두 번째 좌표 보정이나 합성 입력 경로를 추가하지 않는다. QA 도구의 좌표 변환은 CDP에 실제 물리 클릭/터치 위치를 보내기 위한 테스트 코드다.
- 프로젝트 aspect `expand` 및 GameUI의 가로 레이아웃 크기 계산을 대조했다. compact 제목 26/부제 13, 이야기 인물/대화의 가로 병렬 배치와 본문 20은 표현 변경이며, 성장 권한·비용·저장 및 시나리오 진행 규칙은 유지한다.
- 회전으로 화면 배치가 바뀌어도 기존 이야기 ScenarioRunner와 맵 인스턴스를 보존하는 경로를 확인했다.

확인한 실제 실행 증거:

1. `20260908_growth64_landscape/acceptance.json`: **21/21 PASS**. 실제 성장 버튼 터치, 선택 노트 1개 소비, 스킬 1레벨 증가, 저장 표시, 브라우저 리로드 후 성장·지불 재화 보존, 부족·상한·고정 효과, 640×360 / 915×412 / 1280×720 읽기 영역, 격리 저장, 런타임 오류 검사를 포함한다.
2. `20260908_landscape63_browser/acceptance.json`: **14/14 PASS**. 세로 기기에서 옆으로 표시되는 가로 iframe, 실제 회전된 성장 탭 터치, 이야기 다음 버튼 진행, 기기 방향 변경 후 선택 탭·시나리오 보존, 맵·격자 가시성 및 회전 후 동일 맵 인스턴스·위치를 확인한다.
3. 위 14개 검사와 `landscape_only_audit.mjs`를 대조했다. **맵 이동 타일을 실제 터치해 이동시키는 검사는 이 실행에 없다.** 맵 표시/회전 보존 검사를 맵 이동 터치 검증으로 확대하지 않는다.
4. 최신 제공된 네이티브 회귀 로그 `20260908_field64_general_final.log`의 **293/293 PASS**를 읽어 확인했다. 이번 읽기 전용 추가 검토에서 같은 회귀를 중복 실행하지 않았다.

가로 변경에서 추가 중요 코드 결함은 발견하지 못했다. 실제 iOS/Android 기기, OS 방향 잠금, 설치형 PWA의 오프라인/전체화면 동작, 모든 브라우저 엔진, 세로 호스트에서의 맵 이동·전투 터치까지 승인하는 결과는 아니다. 스크린샷을 제시할 경우 사용자 지시에 따라 가로 캡처만 사용한다.

## 검토 시점 파일 SHA-256

- `godot/screens/app_shell.gd`: `93a20aded0655353c3dfe2ea8adb3d88be193e33816306c44855f4ed4aca62ca`
- `godot/progression/character_progression.gd`: `4e156d06aef7f011b6d394f4334dc2bbf7aa20397bacefea644a98c056b6cc6a`
- `godot/progression/skill_upgrade_service.gd`: `2d4bfad197abacc6484e8cb36383c0f714644f6dde9e271e692d704bb1499352`
- `godot/progression/breakthrough_service.gd`: `2f1218271198f0d39fcc1edf9f0b7252edfe9e0558491b9a49c2adb1b6a747c9`
- `godot/progression/growth_affordability_analyzer.gd`: `ab3d695237b5dcdd12864eedf41debe35241036dc08bb54d9a8a490c5c25ab3a`
- `godot/progression/growth_plan_builder.gd`: `7c69a39e98eac3b3afa9c1f5f0863a5c7c50688754222e1a8328e76c735fd9c3`
- `godot/tests/test_runner.gd`: `7d419fbb50a3bafebf34bf0e3823cd99b9dd72809276e2561b34b7e0ff6e6a03`
- `godot/tests/growth_service_authority_runner.gd`: `0ba1022562f3000092f0f6b5c0011c64f93aeea4c27971f0d20546f59e138cca`
- `godot/web/landscape.html`: `5d577f3d296ab17e213fba6ed28d15f69a642b9c73aa65c7e438fc4739f2c672`
- `godot/project.godot`: `2e075b3065568508f2e2dcc3718cb7a788d80900182d65a899766b1fab91c1cf`
- `godot/export_presets.cfg`: `e9e6448b2e2a0187a5a94ab16169ec806b0041319e99c647ff1a97fe8718c8b6`
- `godot/ui/game_ui_tokens.gd`: `47d88e3f57139f2d30d2955268a0ddf0b2361f46a5f11e276365b49f06de2743`
