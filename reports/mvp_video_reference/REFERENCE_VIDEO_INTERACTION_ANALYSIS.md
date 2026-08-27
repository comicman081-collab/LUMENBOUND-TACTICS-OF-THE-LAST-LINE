# 참고 영상 기반 맵·이벤트 진행 문법 분석 — MVP 반영안

## 결론

세 영상에서 가져올 핵심은 특정 게임의 육각 지형, 캐릭터, 전투 UI가 아니라 다음 **진행 리듬**이다.

`월드맵에서 공간적 맥락 확인 → 조우 선택/이동/집중 → 짧은 이벤트 타이틀 → 전투 전 대화 → 전투 → 전투 후 대화 → 보상·성장 → 같은 맵의 변한 상태로 복귀`

현재 프로젝트의 결정론적 30 Hz 실시간 5인 SD 전투는 그대로 유지한다. 이번 참고를 반영할 대상은 **맵·이벤트 presentation layer와 그 사이의 상태 전환**뿐이다. 참고 영상의 턴제/육각 전투, 화면 배치, 캐릭터, 명칭, 색 구성, 지형 형상은 복제하지 않는다.

## 분석 범위와 재현성

- 원본 3개는 읽기 전용으로 분석했으며 수정하지 않았다.
- 로컬 도구만 사용했다: OpenCV 4.14.0과 `C:\Program Files\BlueStacks_nxt\ffmpeg.exe`.
- 1초/2초 간격 프레임, 장면 변화 후보(`scene > 0.18`)와 contact sheet를 생성했다.
- 내부 검토 프레임은 `work/reference_cache/mvp_videos/`에만 있다. 96개 파일, 36,202,717 bytes다.
- `.gitignore`가 `work/`를 제외하고, Godot Web export는 `res://`만 패키징하며, `PACKAGE_SOURCE.ps1`도 `work/`를 복사하지 않는다. 같은 이름의 contact sheet가 `work/reference_cache` 밖에 존재하지 않는 것도 확인했다.
- 이 문서와 CSV에는 프레임 자체를 포함하지 않는다.
- 타임라인 경계는 장면 검출과 1초 샘플을 합친 관찰치이며, 페이드 구간은 약 ±0.5초 오차가 있을 수 있다.

## 원본 메타데이터

| ID | 파일 | 크기 | 영상 스트림 | 컨테이너 길이 | 디코딩 영상 길이 | SHA-256 |
|---|---|---:|---|---:|---:|---|
| V1 | `2026_08_19 23_45.mp4` | 10,499,772 | 1280×600, 23.9885 FPS, 2,086 frames | 86.96s | 86.958s | `90D7F81B2B7765FADEE810154186C230EA3BFFC06C3A453C60A0C259A955A7D8` |
| V2 | `2026_08_21 06_47.mp4` | 28,614,196 | 1562×720, 24 FPS, 1,560 frames | 69.31s | 65.000s | `D09460017A5414D4227BB9644C4AAEB0AFD728F71186A5215E3841D6BF227471` |
| V3 | `2026_08_21 00_12.mp4` | 2,365,515 | 1920×888, 30 FPS, 520 frames | 17.33s | 17.333s | `CA448891FE16F3C9B03608603FAAFF6CD33CC195E5D3DCDD586655CCBB30597D` |

V2는 컨테이너가 69.31초라고 보고하지만 마지막 디코딩 영상 PTS는 64.958초다. 따라서 V2 시각 분석은 65.0초에서 끝냈고 남은 4.31초를 화면 증거로 간주하지 않았다.

## 영상별 진행 타임라인

### V1 — 일반 조우, 전투 후 해금, 보상과 지역 전환

| 구간 | 관찰 |
|---|---|
| 0.00–2.83s | 육각 월드맵에서 조우를 선택하고 상세 패널을 확인한다. |
| 2.83–5.50s | 선택 지점 집중 전환 뒤 짧은 이벤트 타이틀을 보여준다. |
| 5.50–18.08s | 전투 배경과 같은 공간에서 짧은 전투 전 대화를 진행한다. |
| 18.08–53.38s | 명시적 전투 시작 표시 후 전투가 진행된다. |
| 53.38–57.38s | 마지막 공격과 전투 종료가 정리되는 짧은 여유 구간이 있다. |
| 57.38–67.96s | 전투 결과와 연결된 후속 대화/구조 결과를 보여준다. |
| 67.96–69.83s | 신규 인물 획득을 별도 dossier로 강조한다. 현 프로젝트 MVP에는 새 캐릭터 획득이 필요하지 않다. |
| 69.83–74.33s | 승리 → 보상 → 개별 레벨업 순으로 결과를 잘게 나누어 읽힌다. |
| 74.33–81.79s | 같은 맵의 조우 지점으로 돌아가 갱신된 상태를 보여준다. |
| 81.79–86.96s | 새 지역 카드 후 별도 로컬 탐색 화면으로 들어간다. 현 프로젝트에서는 기존 맵 reveal/landmark로 축약할 수 있다. |

핵심 추상화는 전투 전후의 사건이 한 덩어리의 결과 팝업으로 압축되지 않고, `대화 → 승리 → 보상/성장 → 맵 변화`로 순차 전달된다는 점이다.

### V2 — 장거리 카메라 집중, 보스 소개, 보스 후일담

| 구간 | 관찰 |
|---|---|
| 0.00–4.67s | 넓은 맵을 보여준 후 이동 중이거나 수비 중인 보스 조우로 카메라가 접근한다. |
| 4.67–7.50s | 보스 pawn/랜드마크와 상세 패널을 크게 보여준 뒤 전환한다. |
| 7.50–10.00s | 최소 정보의 이벤트 타이틀 카드가 등장한다. |
| 10.00–26.88s | 보스와 파티가 대화하고 보스 정체를 별도 배너로 강조한다. |
| 26.88–31.88s | 전투 준비/시작 표식으로 이야기 화면에서 조작 화면으로 넘어간다. |
| 31.88–56.70s | 보스 전투가 진행된다. 48.42초의 큰 변화는 밝은 전투 효과이며 별도 화면 전환으로 보지 않았다. |
| 56.70–63.50s | 패배한 보스의 짧은 후일담 뒤 전장이 비워진다. |
| 63.50–65.00s | 간결한 결과/승인 요약으로 끝난다. |

핵심 추상화는 **보스 조우가 맵 단계부터 일반 조우보다 강하게 읽히고**, 전투 전에 정체를 소개하며, 전투 뒤 한 번 더 서사를 닫는다는 점이다.

### V3 — 보스 조우 진입부 확대 관찰

| 구간 | 관찰 |
|---|---|
| 0.00–4.30s | 보스 조우 선택, pawn/타일 이동, 상세 패널 갱신 순서를 보여준다. |
| 4.30–5.10s | 짧은 픽셀/암전 로딩 전환이 맵과 이벤트를 분리한다. |
| 5.10–7.00s | 이벤트 타이틀 카드가 표시된다. |
| 7.00–10.50s | 보스 단독 발화로 위협을 먼저 세운다. |
| 10.50–13.50s | 파티가 화면 반대편에 나타나 응답한다. |
| 13.50–17.33s | 보스 이름 배너가 표시되며 영상은 실제 전투 시작 전에 끝난다. |

V3는 `맵 상세 → 전환 → 제목 → 보스 단독 → 파티 등장 → 보스 배너`의 도입 순서를 가장 명확하게 보여준다.

## 공통 인터랙션 문법

1. **Overview before focus**: 먼저 지역과 위협의 공간적 관계를 보여준다.
2. **Selection before commitment**: 선택만으로 전투하지 않고 정보와 경로/도착을 거친다.
3. **Focused handoff**: 선택 지점 집중과 짧은 시각 전환으로 맵과 이벤트를 분리한다.
4. **Event punctuation**: 한두 초짜리 제목 카드가 플레이어의 주의를 재설정한다.
5. **Concise pre-battle story**: 전투 이유와 상대 정체를 짧게 전달한다.
6. **Explicit control handoff**: 언제부터 조작 가능한지 명확하다.
7. **Outcome story before inventory**: 필요하면 전투 결과 대화를 먼저 끝낸다.
8. **Readable reward/growth cadence**: 획득량, 보유량 변화, 새로 가능한 성장을 구분한다.
9. **Return to changed space**: 같은 맵 위치로 돌아가 적 제거, 경로 공개, 랜드마크 변화가 읽힌다.

## 현재 R14/R15와의 차이

| 기능 | 현재 상태 | 판단 |
|---|---|---|
| 장거리 맵, 카메라 focus, route preview | 구현 | 유지 |
| 실제 부대 이동 후 접촉 전투 | 구현 | 유지 |
| 순찰/경계/대기/relay/event/treasure | 구현 | 참고 영상보다 이미 풍부하므로 유지 |
| 일반/엘리트/보스 MapPawn 구별 | 구현 | 보스 집중 연출을 시각 QA로 강화 |
| 맵→전투 전환 | 구현 | 제목 카드와 story handoff를 포함한 전체 체인은 미검증 |
| 전투 전 localized scenario | ScenarioRunner와 데이터 존재 | 맵 조우와의 presentation 순서 표준화 필요 |
| 전장 위 speech-bubble choreography | 없음 | MVP에서는 만들지 않고 정적 스토리 화면으로 대체 |
| 기존 실시간 5인 SD 전투 | 구현 | 절대 변경 금지 |
| 전투 후 Reward/Growth Impact | 구현 | 유지 |
| 전투 후 시나리오 | N03/N05/N07/N09/N10 trigger 존재 | 결과→후속 story→map 순서와 exactly-once를 Web E2E로 검증 |
| 동일 위치 복귀/적 제거/route reveal | 구현 | 유지 |
| 보스 이름/위협 전용 intro banner | 부분 또는 미검증 | N10 MVP 시각 게이트 |
| 신규 캐릭터 dossier | 없음 | 이번 MVP 범위 밖 |
| 별도 실내 탐색 모드 | 없음 | 기존 ChapterMap reveal로 대체; 신규 엔진 금지 |

## MVP 분류

### MUST — 이번 MVP에 반영

1. 데이터 기반 presentation sequence를 정본화한다.
   - `MAP_FOCUS`
   - `EVENT_TITLE` (선택, 짧고 skip 가능)
   - `PRE_BATTLE_SCENARIO` (선택)
   - `BATTLE_READY`
   - 기존 `BATTLE`
   - 기존 `RESULT`
   - `POST_BATTLE_SCENARIO` (선택)
   - `MAP_RETURN_REVEAL`
2. N01 일반 조우와 N10 보스 조우에 위 전체 순서를 실제 Web 사용자 흐름으로 연결한다.
3. 이벤트 제목, scenario ID, boss intro, 복귀 reveal을 stage/encounter 데이터로 지정하고 코드에 고유명사를 박지 않는다.
4. 이벤트 카드/대화는 키보드·마우스·터치에서 진행/skip 가능해야 한다.
5. pending presentation 상태와 completion flag를 저장해 새로고침 후 중복 대화, 중복 전투, 중복 보상이 없게 한다.
6. N10은 `보스 맵 presence → pre-boss story → 독자 boss intro → 기존 phase battle → result → outro → map change`를 완주한다.
7. 전투 전후에도 동일 seed/input의 BattleSimulation final hash와 event hash를 유지한다.
8. 결과 화면의 RewardResolver 및 GrowthAffordabilityAnalyzer를 그대로 재사용한다.
9. 복귀 시 카메라가 전투 지점과 새로 공개된 경로/landmark를 짧게 보여준 후 사용자 제어를 돌려준다.

### SHOULD — MVP 통과 후 품질 강화

1. 일반 조우/엘리트/보스별 focus duration과 transition motif 차별화.
2. 마지막 타격 뒤 0.3–0.6초의 짧은 settle beat.
3. 정적 story 배경에서 보스 단독 → 파티 등장 순서의 portrait fade 연출.
4. major relay/새 지역 공개용 한두 초짜리 area-discovery card.
5. 이미 획득한 story/archive 항목을 결과에서 간결하게 별도 표기.
6. 작은 viewport에서 title/banner가 전투 HUD와 겹치지 않는 responsive variant.

### OUT OF SCOPE / 금지

1. 현재 실시간 전투를 참고 영상의 턴제 육각 전투로 교체.
2. 전투 화면에 이동 hex, 행동력, 전투 턴 시스템 추가.
3. 참고 영상의 캐릭터, 적, 지형, 차량, UI 프레임, 아이콘, 색 배치, 문구, 고유명칭 복제.
4. 참고 영상 프레임을 runtime/source/review package에 포함.
5. 신규 캐릭터 획득/dossier 시스템, 신규 성장축, 별도 실내 탐색 엔진.
6. 장시간 전장 내 speech-bubble 연출이나 상시 캐릭터 흔들기/가짜 Live2D.
7. presentation을 이유로 전투 수치, 보상표, 성장 총량을 변경.

## 권장 데이터 계약

새로운 거대 시스템보다 기존 stage/scenario/map 데이터에 다음과 같은 presentation block을 연결하는 방식이 MVP에 적합하다.

```json
{
  "encounter_id": "NODE_N10",
  "stage_id": "CH01-N10",
  "presentation": {
    "event_title_key": "...",
    "pre_scenario_id": "SCN_CH01_PREBOSS",
    "intro_style": "BOSS_SIGNAL",
    "battle_ready_style": "BOSS",
    "post_scenario_id": "SCN_CH01_OUTRO",
    "return_reveal_ids": ["..."],
    "skippable_if_read": true
  }
}
```

실제 field 이름은 기존 schema와 충돌하지 않도록 컴파일러에서 확정한다. 표시명은 localization key만 사용한다.

## MVP 검증 시나리오

### 일반 조우 N01

`맵 진입 → 적 선택 → 경로 preview → 부대 이동 → 접촉 → focus/title → 짧은 pre-event → 기존 실시간 전투 → 결과/보상/Growth Impact → 같은 hex 복귀 → 적 제거/다음 경로 reveal → 저장/새로고침 복구`

### 보스 조우 N10

`N09 이후 pre-boss trigger → 보스 MapPawn focus → event title → 보스/파티 정적 story → 독자 boss intro → 기존 실시간 phase battle → 결과 → outro → map 복귀/보스 제거/Chapter 상태 변화 → 중복 재생 없이 reload`

### 필수 판정

- 맵 선택만으로 전투 시작 0.
- 접촉당 presentation/battle transaction owner 정확히 1.
- 전투/보상/스토리 completion 중복 0.
- 뒤로가기/skip/새로고침 후 softlock 0.
- BattleSimulation final/event hash 변화 0.
- MapPawn, story portrait, boss banner, battle, result가 각각 실제 정본 asset ID를 사용.
- 1920×1080, 1280×720, 915×412, 844×390, 세로 모바일 안전 영역에서 제목/대화/계속 버튼 겹침 0.
- 실제 Web 캡처/영상은 전체 사용자 흐름에서 생성하고 editor/mockup으로 대체하지 않음.

## 최종 판정

참고 영상의 장점은 전투 방식 자체보다 **맵에서 사건을 선택한 뒤, 이야기와 전투와 결과를 한 호흡으로 연결하고, 다시 변한 맵으로 돌려보내는 연출 문법**이다. R14/R15는 이동, 접촉, 실시간 전투, 결과, 성장, 저장의 기능 토대가 이미 있으므로, MVP는 신규 전투나 신규 탐색 엔진이 아니라 이 토대 사이의 presentation sequence를 데이터화하고 N01/N10 Web E2E로 증명하는 방향이 가장 비용 대비 효과가 높다.
