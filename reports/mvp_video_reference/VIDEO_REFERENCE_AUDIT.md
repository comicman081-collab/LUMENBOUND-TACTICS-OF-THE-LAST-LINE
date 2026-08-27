# 세 참고 영상 기반 MVP 진행 문법 감사

## 판정

세 영상에서 현재 프로젝트에 반영할 가치가 있는 것은 특정 게임의 캐릭터, 지형, UI 또는 전투 규칙이 아니라 다음 진행 문법이다.

`넓은 맵에서 공간적 맥락 확인 → 조우 선택과 집중 → 짧은 사건 표제 → 전투 전 대화 → 전투 → 결과/후속 이야기 → 보상·성장 → 같은 위치의 변화한 맵으로 복귀`

현재 R7/R15는 맵 이동, 실제 접촉 전투, 결과 커밋, 보상·성장, 맵 복귀라는 기능 뼈대가 이미 이 문법과 대체로 일치한다. MVP에서 새 전투 시스템을 만들 필요는 없다. 남은 우선 과제는 **사건 표제와 보스 집중 연출을 데이터 기반으로 정돈하고 N10 전체 체인을 실제 Web에서 증명하는 것**이다.

## 분석 범위

- 원본은 읽기 전용으로만 확인했다. 런타임 및 원본 영상은 수정하지 않았다.
- 로컬 `ffmpeg` 디코더만 사용했으며 외부 API, 외부 모델, GPT Web을 사용하지 않았다.
- 검토용 추출 프레임은 `C:\Users\AAA\AppData\Local\Temp\r15_video_reference_audit\`에만 생성했다. 프로젝트·Web·Source 패키지에는 포함하지 않았다.
- 영상의 고유 캐릭터, 문구, 색 배치, 지형 형상, UI 프레임은 구현 대상으로 취급하지 않는다.

| ID | 원본 | 길이 / 영상 | SHA-256 |
|---|---|---|---|
| V1 | `2026_08_19 23_45.mp4` | 86.96초, 1280×600, 약 23.99 FPS | `90D7F81B2B7765FADEE810154186C230EA3BFFC06C3A453C60A0C259A955A7D8` |
| V2 | `2026_08_21 06_47.mp4` | 컨테이너 69.33초, 1562×720, 24 FPS | `D09460017A5414D4227BB9644C4AAEB0AFD728F71186A5215E3841D6BF227471` |
| V3 | `2026_08_21 00_12.mp4` | 17.33초, 1920×888, 30 FPS | `CA448891FE16F3C9B03608603FAAFF6CD33CC195E5D3DCDD586655CCBB30597D` |

V2의 화면 스트림은 약 65초까지만 디코딩되므로 이후 컨테이너 여유 구간은 시각 증거로 사용하지 않았다.

## 객관적 관찰

### V1 — 일반 조우와 전투 후 진행

- 0–3초: 육각 월드맵에서 조우를 선택하고 문맥 패널을 확인한다.
- 약 3–6초: 맵과 전투 사이에 짧은 집중 전환과 사건 표제가 있다.
- 약 6–18초: 전투 이유를 짧은 대화로 전달한다.
- 약 18–57초: 맵과 분리된 전투가 진행된다.
- 약 57–74초: 후속 대화, 승리/보상, 개별 성장 결과를 순차적으로 보여준다.
- 약 74초 이후: 같은 맵 위치로 돌아가 갱신된 진행 상태와 다음 지역을 보여준다.

추상적 교훈은 결과를 한 개의 긴 표로 압축하지 않고 `결과 의미 → 획득 → 성장 영향 → 맵 변화`로 나누어 읽히게 한다는 점이다.

### V2 — 보스 접근과 결말

- 0–8초: 넓은 지형을 먼저 보여주고 보스 pawn/랜드마크와 상세 정보로 카메라가 집중한다.
- 약 8–10초: 최소 정보의 사건 표제가 맵과 대화를 구분한다.
- 약 10–32초: 보스 단독 소개, 파티 응답, 전투 준비 표시가 순차적으로 나타난다.
- 약 32–57초: 보스 전투가 진행된다.
- 약 57–65초: 패배한 보스의 짧은 후일담과 결과 요약으로 사건을 닫는다.

추상적 교훈은 보스가 전투 화면에서만 큰 HP로 구분되는 것이 아니라 **맵 실루엣, 카메라 집중, 짧은 소개, 전투 후 닫힘**까지 하나의 체인을 가진다는 점이다.

### V3 — 보스 진입부의 압축된 예

- 0–4초: 보스 조우 선택, pawn/타일 집중, 상세 패널 갱신이 보인다.
- 약 4–7초: 짧은 암전/전환 뒤 사건 표제가 나타난다.
- 약 7–14초: 보스 단독 발화 후 파티가 반대편에서 응답한다.
- 약 14–17초: 보스 정체 배너로 소개를 마치며 실제 전투 직전에 영상이 끝난다.

V3는 `선택 → 집중 → 제목 → 상대 소개 → 파티 응답 → 전투 제어권`의 도입 순서를 가장 짧게 보여준다.

## 현재 구현과의 비교

| 진행 요소 | 현재 정본 근거 | 판정 |
|---|---|---|
| 장거리 2.5D 육각 맵과 경로 preview | `godot/chapter_map/runtime/chapter_map_screen.gd` | 구현됨. 유지. |
| 선택만으로 전투하지 않고 실제 접촉 후 진입 | `_resolve_arrival()`이 live enemy 좌표를 확인한 뒤 `_start_patrol_contact()`를 호출 | 구현됨. 영상보다 전략 요소가 풍부함. |
| 순찰·대기·위험 경로·relay·event·treasure | `MapSimulation`, `MapExplorationService`, R14 map tests | 구현됨. 새 시스템 추가 불필요. |
| 전투 결과 정확히 한 번 커밋 | `app_shell.gd::_battle_finished()`의 `claim_pending_reward_once()` 경계 | 구현됨. presentation 작업에서 절대 약화 금지. |
| 결과→후속 이야기→맵 복귀 | STAGE_CLEAR trigger, `pending_story_triggers`, `pending_reveal`/`reveal_consumed` | 기능 구조 구현. N03/N05/N07/N09/N10에 연결됨. |
| N09 후 프리보스 staging, N10 실제 접촉 | map regression의 `PREBOSS_STAGING_*` 계약 | 구현 및 자동검사 존재. 실제 최신 Web 완주는 별도 증거 필요. |
| 보스 PHASE_2/ENRAGE 시각 알림 | runtime test의 상태 이벤트별 one-shot banner 계약 | 자동검사 존재. 1×/3× 실제 판독성은 Web 시각 QA 대상. |
| 정적 시나리오 | 9개 scenario, static background/portrait, checkpoint/save | 구현됨. 영상의 전장 speech bubble은 복제하지 않고 기존 VN 화면을 사용. |
| 사건 표제/시나리오 제목 | Release story header resolves `ScenarioDef.title_key`; core regression explicitly rejects raw `SCN_*` display in Release | **해결됨.** 실제 Release capture `reports/r16_environment/103_RELEASE_N10_MAP_READY_WEB.png`도 localized `공허기관 앞에서`만 표시한다. |
| encounter별 presentation 데이터 | Chapter intro, N03/N05/N07/N09/N10 stage-clear story triggers and the N04/N08 authored companion-contact payloads | **구현됨.** 모든 일반 조우에 강제 장면을 추가하지 않고, 사건 조우와 보스 접근에만 제목/정적 story를 배치한다. |
| 보스 전용 맵→스토리 intro banner | N09 clear queues the localized pre-boss scenario; `PREBOSS_STAGING_01..11` prevent it from synthesizing an N10 battle transaction | **실제 Release 증거 있음.** `103_RELEASE_N10_MAP_READY_WEB.png` → `104_RELEASE_N10_ROUTE_WEB.png` → `106_RELEASE_N10_CONTACT_WEB.png` → `107_RELEASE_N10_BOSS_RESULT_WEB.png`. |

## MVP 권고

### P0 — 현재 반영·검증된 항목

1. Story 화면 헤더는 내부 `scenario_id`를 숨기고 `ScenarioDef.title_key`의 로컬라이즈된 실제 제목만 Release에 표시한다.
2. N01과 N10의 다음 presentation sequence는 기존 권한을 유지한 채 연결했다.
   - `MAP_FOCUS`
   - 짧고 건너뛸 수 있는 `EVENT_TITLE`
   - 선택적 `PRE_BATTLE_SCENARIO`
   - `BATTLE_READY`
   - 기존 실시간 `BATTLE`
   - 기존 `RESULT`
   - 선택적 `POST_BATTLE_SCENARIO`
   - 기존 `MAP_RETURN_REVEAL`
3. N10은 `pre-boss story → N09 staging → N10 route/path → 실제 접촉 → 기존 phase battle → result`까지 현재 Release capture로 확인했다. N10 결과 이후의 map-return/Chapter outro 연속 세션은 최신 evidence bundle에서 분리되어 있어, 단일 무중단 새-save 완주 증거로 과장하지 않는다.
4. presentation은 `pending_encounter.token`, `processed_reward_tokens`, `processed_battle_tokens`, `pending_reveal`을 읽기만 하거나 one-shot으로 소비해야 한다. 보상·별·first clear·적 제거를 재수행하면 안 된다. 이 경계는 map/runtime regression으로 검사한다.
5. N01의 Release map-return/reload capture와 N10의 Release pre-boss/contact/result capture가 존재한다. 그러나 한 세션에서 N01부터 N10과 HARD 전체를 연속 완주한 브라우저 증거는 여전히 별도 전체 E2E 게이트다.

### P1 — MVP 이후 품질 강화

- 일반/엘리트/보스별 focus 시간과 색/모티프를 독립 IP 범위에서 차별화한다.
- 마지막 타격 뒤 0.3–0.6초 settle beat를 두되 BattleSimulation 결과에는 관여하지 않게 한다.
- 보스 단독 초상 → 파티 초상 순서의 정적인 portrait fade를 사용한다.
- 실제 신규 route/landmark가 있을 때만 짧은 지역 공개 카드를 한 번 표시한다.
- 915×412, 844×390 및 세로 모바일에서 title/banner/계속 버튼의 안전 영역을 별도 QA한다.

### 하지 말아야 할 것

- 현재 30 Hz 실시간 5인 SD 전투를 영상의 전투 방식으로 교체하지 않는다.
- 전투 화면에 육각 이동, 행동력, 턴제 명령을 추가하지 않는다.
- 전장 speech bubble 시스템을 새로 만들지 않는다. 현재 정적 VN 계약으로 충분하다.
- 영상의 캐릭터, 적, 육각 지형, 차량, UI, 색 배치, 문구, 고유명칭을 복제하지 않는다.
- 신규 캐릭터 획득 dossier, 별도 로컬 탐색 엔진, 신규 성장축을 이번 MVP에 추가하지 않는다.
- event title이나 map reveal이 canonical 보상/진행을 다시 처리하게 만들지 않는다.

## 최종 수락 시나리오

### N01

`맵 → 적 선택 → 경로 preview → 실제 이동/접촉 → 짧은 localized title 또는 chapter intro handoff → 기존 실시간 전투 → 결과/보유량 변화/Growth Impact → 맵 복귀 → 적 제거/N02 공개 → 저장/새로고침 복구`

### N10

`N09 결과 커밋 → 프리보스 story → N09 인접 staging 복귀 → 보스 MapPawn 실제 접촉 → 보스 focus/title → 기존 phase battle → 결과 → outro → 맵 복귀/보스 제거/Chapter 변화 → 저장/새로고침 후 중복 0`

필수 판정은 BattleSimulation final/event hash 변화 0, reward exactly once, story/reveal exactly once, 실제 Web fatal console error 0이다. 자동검사는 구조 증거이며, 새-save N01→N10→H05의 단일 연속 Web 세션은 실제 실행 증거가 생기기 전까지 `UNVERIFIED`로 남긴다.

## 결론

참고 영상의 핵심은 전투 방식이 아니라 **사건을 한 호흡으로 묶는 연출 순서**다. 현재 프로젝트는 기능 토대가 충분하므로, 가장 비용 대비 효과가 높은 다음 단계는 신규 시스템 양산이 아니라 localized 사건 제목, N10 보스 집중 연출, 결과 이후 변화한 맵의 one-shot presentation을 정돈하고 실제 Web E2E로 증명하는 것이다.
