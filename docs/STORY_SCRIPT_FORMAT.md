# 스토리 원고 형식 (`data_source/story_script/*.json`)

`tools/generate_data.py`가 이 원고를 시나리오 JSON, 스토리 트리거, 지도 조우 대사, 돌발 사건, 현지화 키(ko/en)로
컴파일한다. 원고 하나가 한 장(chapter)이다. 파일은 UTF-8, 들여쓰기 2칸 JSON이다.

## 최상위

```json
{
  "chapter_id": "CH03",
  "scenes": [ ... ],
  "popups": { ... },
  "incidents": [ ... ]
}
```

## 대사 한 줄

```json
{"s": "CHR007", "ko": "한국어 화면 대사", "en": "English line"}
```

- `s` 화자 코드
  - `N` 나레이션(길잡이)
  - `CHR001`~`CHR044` 캐릭터
  - `CONTROL` 종착 관제(안내 방송)
  - `BOSS` 이 장의 일반 보스, `HBOSS` 이 장의 심층(위험 경로) 보스
  - `ENEMY` 특이 위협 조우의 적(팝업 `ANOMALY_*` 안에서만)
  - `SIO` 시오(마에루가 잃은 동료, 잔향·기록으로만 등장)
  - `SURVIVOR` 이름 없는 생존자(성인 여성)
  - `ECHO` 사람 목소리를 흉내 내는 잔향체
  - `EAST_KING` 동부선 노선왕, `WEST_KING` 서부선 노선왕 (16장 전용)
- `e`(선택): 그 줄에서 화자의 표정 상태. `NEUTRAL` `SMILE` `SAD` `ALERT` `SERIOUS` `RESOLVED` `CONCERNED`
  `BATTLE_FOCUS` `RELIEVED` 중 하나. 생략하면 컴파일러가 말투로 정한다(`……`로 시작 → `SERIOUS`, 느낌표 → `ALERT`,
  보스 직전 장면의 느낌표 → `BATTLE_FOCUS`, 물음표 → `CONCERNED`, 사과·상실 → `SAD`, 웃음·감사 → `SMILE`).
- 화면에 한 번에 보이는 한국어는 70자 안팎까지. 길면 두 줄로 나눈다.
- 말줄임표는 `……`(두 개)로 통일한다. 영어는 `…`.

## 장면 (`scenes[]`)

```json
{
  "id": "INTRO",
  "trigger": "MAP_ENTER",
  "title_ko": "장면 제목", "title_en": "Scene title",
  "background": "tunnel",
  "cast": {"LEFT": "CHR001", "CENTER": "CHR003", "RIGHT": "CHR002"},
  "lines": [ 대사, 대사, {"cast": {"RIGHT": "CHR007"}}, {"choice": [...]}, ... ]
}
```

- `id`: `INTRO` `MID_A` `MID_B` `CAMP` `PREBOSS` `OUTRO` `HARD_INTRO` `HARD_OUTRO` (시나리오 ID는 `SCN_<장>_<id>`)
- `trigger`: `MAP_ENTER` 또는 클리어 작전 코드(`N04`, `N19`, `H01`…). 장면 순서표는 `docs/STORY_OUTLINE.md` 머리말 참고.
- `background`: `tunnel`(등불 터널·기지) · `rail`(유리 선로·야외 노선) · `cathedral`(신호 성당·거대 시설 내부) 중 하나.
- `cg`(선택): 장면 전체에 까는 CG 에셋 ID(예: 1장 OUTRO의 `cg_ch01_pilot_teamwork`). 없으면 배경을 쓴다.
- `cast`(선택): 첫 무대의 초상화 슬롯(`LEFT`/`CENTER`/`RIGHT`, 최대 3명). 값은 캐릭터 코드, `BOSS`, `HBOSS`, 또는 `null`.
  대사 중 `{"cast": {...}}`로 바꿀 수 있다. **생략해도 된다** — 컴파일러가 말하는 인물이 무대에 없으면 가장 오래 말하지 않은
  슬롯에 자동으로 세운다. 나레이션·관제·생존자·잔향은 초상화가 없다.
- 선택지(주인공의 응답, 음성 없음):

```json
{"choice": [
  {"ko": "선택지 문구", "en": "Choice label", "flag": "CH07_HOLD_MAERU", "reply": [대사, ...]},
  {"ko": "선택지 문구", "en": "Choice label", "reply": [대사, ...]}
]}
```

  `reply`는 그 선택 직후 1~3줄. 이후 대사는 두 선택이 공유한다.

## 지도 조우 팝업 (`popups`)

전투 직전 지도 위에서 뜨는 대화창. 한 쪽이 한 줄이며 음성이 나온다. 화자는 캐릭터 코드/`BOSS`/`HBOSS`/`ENEMY`.

| 키 | 시점 | 줄 수 |
|---|---|---|
| `RECRUIT` | 합류 동료 접촉 노드 전투 직전(첫대면) | 6–10 |
| `WANDERER` | H03 떠돌이 대원 첫대면(20장 없음) | 6–10 |
| `BOSS` | N20 보스 노드 전투 직전 | 3–5 |
| `HARD_BOSS` | H05 심층 보스 전투 직전 | 3–5 |
| `ANOMALY_1` `ANOMALY_2` `ANOMALY_3` | N06·N13·H02 특이 위협 조우(합류 작전이 N13인 장은 둘째가 N15) | 3–4 |

## 돌발 사건 (`incidents[]`)

지도 이동 중 불시에 일어난다. 장마다 6개, 종류마다 1개.

```json
{"kind": "ECHO", "title_ko": "제목", "title_en": "Title",
 "lines": [대사 2~3줄],
 "choices": [{"outcome": "LISTEN", "ko": "끝까지 들어 본다", "en": "Listen to the end"},
             {"outcome": "IGNORE", "ko": "지나간다", "en": "Move on"}]}
```

| kind | 상황 | choices(outcome 고정) |
|---|---|---|
| `AMBUSH` | 잔향체 기습 | `FIGHT`(짧은 교전으로 자동 정리 → 크레딧·훈련 기록 S) · `EVADE`(우회 → 보상 없음) |
| `DISTRESS` | 조난 신호·생존자 | `RESCUE`(구조 → 크레딧·훈련 기록 M) · `RECORD`(좌표 기록 → 반경 4칸 시야 공개) |
| `STORM` | 잔광 폭풍 | `SHELTER`(대피 → 훈련 기록 S) · `PUSH`(돌파 → 반경 3칸 시야 공개) |
| `CACHE` | 보급 흔적 | `TAKE`(회수 → 크레딧·무기 칩 S) 한 개 |
| `BANTER` | 동료끼리의 짧은 대화 | `CONTINUE`(계속 간다 → 훈련 기록 S) 한 개 |
| `ECHO` | 대정전 이전의 목소리·기록 | `LISTEN`(듣는다 → 훈련 기록 M) · `IGNORE`(지나간다) |

발생 규칙(`godot/chapter_map/model/map_exploration_service.gd`):
- 그 장의 N02를 처음 클리어한 뒤부터 일어난다.
- 조건: 전투·보물 없는 칸으로 2칸 이상 이동. 확률 24%, 발생 후 2회 이동은 쉰다.
- 같은 사건은 장마다 한 번만 일어난다. 보상 크레딧은 장 단계(1~4)에 비례한다.
- 사건이 끝나면 평소처럼 적 턴이 이어진다. 보상이 있으면 보물처럼 보상 창을 거친다.

첫 줄은 보통 나레이션(`N`)으로 상황을 보여 주고, 이어서 동료 1~2명이 반응한다.
