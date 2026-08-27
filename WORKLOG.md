# Worklog

## 2026-08-25 — Developer HARD daily-limit QA bypass

- 개발자가 같은 날짜에 HARD를 반복 검증할 때 `3/3` 일일 입장 제한에 막히지
  않도록 DEV-authorized build에서만 HARD 입장 ledger와 작전력 차감을 우회했다.
  일반 Web HTML Release의 날짜별 제한과 입장 transaction은 그대로 유지된다.
- AppShell/ChapterMap 상세에 개발 빌드 `무제한 (DEV)`, Release `count/daily`를
  분리 표시하고, DEV 저장에 권한 플래그를 보존하지 않는다.
- 공식 Godot 4.7.1 scene runner `res://tests/test_runner.tscn` 165/165 PASS,
  SRPG map 234/234 PASS, R15 49/49 PASS를 재실행했다.
- Web Development preset에만 `lanternline_dev_tools`가 있고 public Web HTML
  Release preset에는 빈 `custom_features`만 있는지 신규 authority-boundary
  assertion으로 고정했다.
- GPT Web 동일 세션 검토: DEV_HARD_QA_GATE PASS, DEV_RELEASE_AUTHORITY_SEPARATION
  PASS(자동 검증 범위), 알려진 P0 결함 없음. 신규 Release PCK 경계 smoke는 다음
  Release 빌드 때 수행할 항목으로 유지한다.
- 배포·업로드·Release PCK 재빌드는 수행하지 않았다.

## 2026-08-25 — Resume / Release import and package verification

- 사용자 재개 지시에 따라 고정 `R7` 정본 Web Release QA를 재개했다. ENM005의
  `valid=false` runtime import metadata를 찾아 Godot 4.7.1 editor importer로
  재생성하고, 같은 문제가 재발하면 정적 검증에서 즉시 실패하도록 import guard를
  추가했다.
- 최신 회귀: Static 70/70, Godot 164/164, SRPG map 234/234, R15 49/49,
  R16 26/26 — 합계 **543/543 PASS**.
- 단일 임시 인앱 브라우저 탭에서 Release title→home→map→N05 선택→이동
  제한 소진→대기(8칸 회복)→기존 실시간 전투→승리 보상/성장→필수 스토리→맵
  복귀/N05 clear·N06 노출, 이어서 N06 이동 제한 중단 및 패배→보상 없음·적 유지를
  실제 확인했다. runtime log 100건에서 warning/error 0건, 최신 샘플 95 FPS,
  orphan 0, 오디오 playback failure 0을 기록했다.
- `builds/web_release`와 고정 이름 HTML/Source ZIP을 in-place 재빌드/패키징했다.
  현재 PCK SHA-256은 `86d125d70ab3c1ef9779c7dce06c973246e0153ebc75a1341efe945ed6bf8c8e`,
  HTML ZIP은 68,785,321 bytes, Source ZIP은 756,339,369 bytes다.
- 표준 raw Godot WebAssembly를 사용하는 현재 Release와 gzip 제한 호스트 변형을
  모두 허용하도록 `PACKAGE_HTML.ps1` 계약을 최소 보완했다. 배포/업로드/캐시 삭제는
  수행하지 않았고, QA 탭과 임시 서버는 검증 후 종료했다.

## 2026-08-17

- 신규 프로젝트 루트 생성. 기존 파일 삭제/덮어쓰기 없음.
- 지정 범위에서 공용 `asset_share` 절차적 팩토리 발견 및 정본 판별.
- Godot 4.7.1/Android SDK 로컬 설치 조사: 미발견.
- Foundation, 데이터 파이프라인, 결정론적 전투, UI 흐름, 성장/보상/스토리/저장 구현 시작.
- Godot 4.7.1 Standard 설치 확인 및 61개 헤드리스 런타임 검증 전부 통과.
- 전역 `FEMALE_ONLY` / `ADULT_ONLY` / `MAXIMUM_NON_EXPLICIT` 정책을 데이터·프롬프트·브리지·시각 QA에 적용.
- Krea2를 영구 제외하고 로컬 모델 원본을 읽기 전용으로 보존.
- R05–R07 로컬 생성 후보를 시각 검수했으며 품질/성인 판독/역할 미달 자산은 통합하지 않고 격리.
- 코드형 전투 DEV SD를 성인 여성 실루엣/고노출 비명시적 전투복/역할 장비로 교체하고 비인간 적과 분리.
- 화면 밖 백그라운드 렌더로 1920×1080 필수 화면 10장 캡처 및 스토리 줄바꿈 회귀 수정.
- 실제 BattleSimulation으로 CH01-N10 100회 실행: 승률 97%, 평균 종료 46.1153초.
- 공식 Godot 4.7.1 TPZ에서 Windows 템플릿 2개만 범위 설치; Android 템플릿 미설치.
- Windows Debug EXE/ZIP 및 Source ZIP 생성, 배포 EXE 2회 헤드리스 실행 성공.
- 전투 방향 계약을 플레이어 `THREE_QUARTER_RIGHT_DOWN_30`, 적 `THREE_QUARTER_LEFT_DOWN_30`로 고정하고 비대칭 플레이어 자산에 `SEPARATE_LEFT_RIGHT`를 적용.
- 로컬 SDXL R21~R26 교정 중 방패가 분리된 후보는 탈락 처리하고, R26v03을 제작 최종본이 아닌 `DEV_DIRECTION_SOURCE`로 선정.
- R26v03에서 512×512 투명 PNG 80프레임(8/12/8/12/18/4/8/10)과 2048 시트를 생성해 BattleView 이벤트 표현에 연결.
- Godot 4.7.1 헤드리스 69/69 통과, Web Development HTML 내보내기 성공, 로컬 브라우저에서 타이틀→홈→N01 전투→결과 실제 실행 확인.
- 오프스크린 Compatibility 렌더러로 필수 화면 10장을 `reports/screenshots/`에 재캡처.
- 성장·상태이상·무기·소탕·스토리 체크포인트·수동 필살기 타깃·풀링 검증을 확장해 Godot 87/87 및 정적 60/60 통과.
- 숨겨진 정지 패널 컨테이너가 전투 버튼 입력을 가로채던 문제를 실제 브라우저에서 발견·수정하고 Release 빌드에서 재검증.
- 자산 브리지 정본을 `godot/assets/generated_import`로 교정하고 93파일 증분 동기화/해시 검증 및 109개 라이선스 원장 병합 완료.
- `SYNC_ASSETS.ps1`에도 프로젝트 격리 AppData 경로를 적용해 기본 AppData 로그 크래시 재발 방지.
- 실제 BattleSimulation CH01-N10 100회: 승률 100%, 평균 27.2847초; 과도한 난이도 여유를 튜닝 경고로 기록.
- 5대20, 투사체/텍스트 각 100개, 18,000 tick 부하 테스트에서 풀 재활용과 메모리 증가 68,024바이트 확인.
- Web HTML Release에서 타이틀→스토리→편성→전투→정지→결과→성장→저장/재로드를 실조작하고 콘솔 오류/경고 0건 확인.
- 1920×1080 시각 QA를 정지 패널 포함 11장으로 갱신.

## 2026-08-18

- ChatGPT Web 협업 명세를 인앱브라우저에서 수집해 R6 색상·VFX·반응형·소크 게이트를 정본 문서로 고정.
- R6의 검은 실루엣 렌더 실패를 PASS 처리하지 않고 폐기한 뒤, R6P2 완전 불투명 authored key pose + 발 고정 변형 방식으로 5×80 SD 프레임과 6×12 VFX를 재생성.
- R6P2 422 PNG 기술 검사 0 failure, 파일럿 fallback 0, 147/147 전체 회귀 통과.
- R6P4/R6P5에서 UI 토큰 통일, 편성 슬롯 선택 버그, raw JSON 노출, 성장 획득처 overflow, 세로 화면 안내를 수정.
- 실제 인앱브라우저 전체 흐름, 1×/3× 전투, 844×390/390×844 반응형 QA를 수행하고 오류·경고 0건 확인.
- Web 소크 1,240.008초/240샘플, 평균 91.91 FPS, 최소 90 FPS, orphan node 0으로 완료.
- R6P5 Web ZIP 268,919,133 bytes로 300 MB 게이트 통과; 검토 ZIP과 SHA-256 원장 생성.
- R7 Chapter Map의 출력 태그와 맵 개정명을 각각 `r7_current`/`R7`로 고정하고, Web 산출물은 기존 두 R7 현재 경로만 명시적 덮어쓰기로 갱신하도록 정리.
- 세로 `390×844` Chapter Map에서 AppShell 헤더를 덮던 full-viewport anchor를 컨테이너 레이아웃으로 수정. 세로 상세 sheet의 하단 조작과 상단 헤더가 안전 영역 안에 유지됨을 실제 인앱브라우저에서 확인.
- Web 회전 이벤트가 Godot 창 크기 이벤트를 보내지 않는 경우에도 shell font/safe-area 값을 다시 계산하고 `STAGE_SELECT`를 저장된 지도 상태에서 재구성하도록 보완. 실제 세로→가로 `1280×720`→세로 라이브 회전에서 확대된 세로 폰트 잔존이 재발하지 않음.
- 현재 R7 Release `r7_current_8b79d0957ea8.pck` SHA-256 `8B79D0957EA8C9D01C4748BA093B6BC2BB9D09BEB7787AE22BE7A77831776941` 생성. Foundation 87/87과 R7 map 57/57 헤드리스 검증 통과, 인앱브라우저 console error/warning 0.
- 맵 말이 목적지 카메라 선행으로 정지해 보이던 문제를 수정: 선택 시 현재 위치를 유지하고, 실제 경로 Tween·걷기 리듬·단계 표식·완만한 카메라 추적으로 이동 거리를 읽을 수 있게 함. 리더 표식은 terrain depth에 가려지지 않으며 크기를 map pawn 비례로 조정.
- macro 지형에 seeded elevation 0~3, 실제 low-poly hex cap, 절벽·strata·수목·폐허·signal rail 밀도를 적용해 평면 보드 인상을 해소. 원본 Blender map kit은 수정하지 않았으며 기존 GLB component를 런타임 dressing으로 재사용.
- BattleView에 NORMAL SKILL/ULT callout, 비-파일럿 캐릭터용 다층 runtime VFX fallback, 3배속에서도 읽히는 표현 시간 상한을 추가. 전투 simulation은 30Hz 및 기존 speed 계약을 유지. 2적 초반 웨이브에서 AOE ULT AUTO가 실제로 발동하도록 data-effect 조건을 보정.
- 현재 R7 Release `r7_current_5d2ec5bb6e1a.pck` SHA-256 `5D2EC5BB6E1A471B2F11CA6F85311ABF309A4C237F346D97616CCEFF100FC8FD`로 동일 출력 경로를 덮어씀. Foundation 87/87, R7 map 57/57 재실행 PASS; 인앱 브라우저에서 N04→N05 경로 이동 및 ULT 표시를 실제 확인했고 포트 8081/검증 탭을 종료함.
- 스킬/필살기 표현을 caster ring 하나에서 발동 seal → 역할색 탄환 trail → 시간 지연 적중 shock disk·starburst로 확장. HEAL은 십자 회복광, SHIELD는 육각 방벽으로 분리. 실제 Web 전투에서 CHR005 ULT 및 일반 스킬 발동/적중 이펙트를 확인하고, R7 고정 출력에 `r7_current_72afe8d01baf.pck` SHA-256 `72AFE8D01BAF6A5FD692742D5F334CDF22B1B15621461FB3EF47D6A98F3E37E3`로 덮어씀.
# 2026-08-25 — Chapter 1 continuous Web E2E + GPT Web review

- 최신 `builds/web_release`를 임시 로컬 HTTP 서버(`127.0.0.2:8078`)에서 실제 인앱 브라우저로 검증했다.
- 기존 N05-cleared save checkpoint에서 N06 첫 패배(보상 0/적 유지) → 성장 서비스 적용 → N06 재도전 승리 → N07 relay story → N08 special encounter → N09 WAIT/이동 제한 및 pre-boss story → N10 승리/outro/map 복귀까지 관찰했다.
- HARD unlock과 H01 승리를 확인했고 H02 패배(보상 0/재도전 가능)까지 확인했다. H03~H05와 fresh N01부터의 단일 연속 run은 아직 UNVERIFIED다.
- 브라우저 최신 로그 100건에서 error/warning 0, `playback_failed_counts={}`, `orphan_node_count=0`을 확인했다.
- 상세 기록: `reports/mvp_video_reference/CHAPTER1_CONTINUOUS_E2E_20260825.md`
- 현재 GPT Web 세션에 최신 결과를 전송했고, 응답을 기록했다. GPT Web 판정: 기능 코어 PASS, 최신 Release 부분 인간 E2E PASS, 최신 Release 전체 Chapter 1 연속 인증 UNVERIFIED, 알려진 P0 코드 결함 0.
- GPT Web 응답: 예방성 리팩터링 금지; fresh N01→N10→H01→H05 단일 저장 E2E와 N03/N07/N10/H05 reload checkpoint, N08 동료 roster/save exactly-once 확인을 우선.
- 응답 기록: `reports/mvp_video_reference/GPT_WEB_REVIEW_RESPONSE_20260825.md`
- 임시 QA 탭과 HTTP 서버는 정리했다. 배포·업로드·캐시 삭제는 하지 않았다.

## 2026-08-25 — Fresh Release continuation / Development HARD coverage

- 사용자 재개 지시에 따라 동일한 임시 인앱 브라우저 QA 탭과 로컬 HTTP 서버에서
  Chapter 1 fresh Release 흐름을 이어갔다. N01~N10의 맵 이동 제한·대기·실시간
  SD 전투·보상·성장·스토리·맵 복귀를 관찰했고, N04 베라 특수 조우와 N08 토아
  지연 영입 이벤트도 확인했다. N10은 전투 완료 후 `다음 등불` 아웃트로와 맵/홈
  진행 전환까지 관찰했으나 별도 결과 화면 캡처가 없어 직접 결과 증거는 PARTIAL로
  기록했다.
- Release H01 승리와 H02 패배(보상 없음·적 유지)를 확인했다. H02 패배 후 저장의
  작전력이 3으로 남아 정상적인 H02 이동 잠금이 발생했으므로 Release H03~H05는
  권한 우회 없이 UNVERIFIED로 유지했다.
- 동일 구조의 Web Development 빌드를 로컬에서만 실행해 개발자 QA 권한으로 H02,
  H03, H04, H05를 각각 승리(17.43초/46.70초/37.23초/64.90초)하고 결과→맵
  복귀를 확인했다. 이 결과는 Release 인증을 대체하지 않는다.
- H05 결과에서 실제 보상 전→후 보유량과 성장 후보 요약을 확인했고, 결과→맵
  복귀를 관찰했다. 단, 개발 QA가 동일한 `r15-save-sandbox-session`에 계정 Lv100,
  재료/무기 QA 값을 저장했으므로 이후 Release 재로드 화면은 Release 증거에서
  제외했다. 개발 H02~H05는 보조 경로 증거로만 유지하며, 새 깨끗한 Release
  샌드박스에서 H02→H05를 다시 검증해야 한다.
- 자동 회귀를 재실행했다: Static 70/70, Godot 161/161, SRPG map 228/228,
  R15 49/49, R16 26/26 — 측정 합계 **534/534 PASS**.
- 상세 기록: `reports/mvp_video_reference/CHAPTER1_FRESH_RELEASE_E2E_20260825.md`.
  배포·업로드·캐시 삭제는 수행하지 않았다.
- GPT Web 후속 검토는 기존 세션에서 완료했고, 뒤이어 이 샌드박스 공유 오염
  정정도 전송했다. 최초 판정은 NORMAL 기능 흐름 PASS,
  N10 기능 진행 PASS/N10 결과 화면 PARTIAL, Release H02~H05 UNVERIFIED,
  Development H02~H05 보조 PASS, 예방성 리팩터링 금지였다. 동일 Release 저장을
  다시 열어 작전력이 3에서 8로 정상적인 5포인트 회복되는 것도 확인했으며,
  권한 우회 없이 H02→H05 재검증을 다음 회복 시점에 이어가도록 Release 탭과
  서버를 닫았다.

## 2026-08-25 — Clean Release HARD continuation / GPT Web re-review

- 새 Release 전용 namespace `hard-release-cert-r15`에서 developer override 없이
  N01→N10을 다시 연속 진행했다. N10 직접 Result 화면(46.03초, 생존 5)을
  확인한 뒤 아웃트로 `다음 등불`과 맵 복귀까지 관찰했다.
- H01은 첫 패배 후 실제 `권장 파티 성장` UI를 사용해 재도전했고 31.97초,
  생존 1로 승리했다. H02는 24.90초에 패배했으며 보상 0, 적 유지,
  attempts 1/3 보존을 확인했다.
- H02 재도전은 정상적인 작전력 부족 잠금으로 막혔다. N01~N10 비용 72,
  H01~H05 비용 62에 N06/H01/H02의 합법적 실패·재시도 비용이 더해져
  해당 세션의 작전력이 H02 입장 비용보다 낮아진 상태다. Release 권한을
  우회하거나 코드를 변경하지 않고 `UNVERIFIED`로 유지했다.
- 기존 GPT Web 세션에 최신 관찰을 전송했다. GPT Web 판정은
  NORMAL N01~N10 PASS, H01 PASS, H02 패배/작전력 게이트 PASS,
  H02→H05 및 H05 reload UNVERIFIED, 알려진 코드 결함 0이다.
- 다음 작업은 같은 깨끗한 Release 세션의 자연 작전력 회복 후 H02 승리→H03→H04→H05→저장/새로고침 검증이다. 배포·업로드·캐시 삭제는 하지 않았다.
- 정본 자동 검증을 Godot 전역 설치 경로 `D:\AI 종합 폴더\Godot\4.7.1-standard\Godot_v4.7.1-stable_win64_console.exe`로 재실행했다. Static 70/70, Core 161/161, SRPG map 228/228, R15 49/49, R16 26/26 모두 PASS(총 534/534)이며, 이번에는 엔진 경로를 명시해 검증했다.
- 자연 회복 확인을 위해 기존 임시 탭을 닫은 뒤 같은 Release namespace를 새 탭 하나로
  다시 열었다. Continue 후 계정 Lv21, 작전력 9/124가 복구되었고 H02 12포인트
  입장 게이트가 정상적으로 유지됨을 확인했다. 확인 직후 임시 탭과 HTTP 서버를
  다시 닫았으며, 다음 회복 시점에 동일 namespace로 H02→H05 검증을 재개한다.

## 2026-08-25 — Movement capacity rewards made attainable

- `CH01_MAP`의 기존 이동 포인트 확장 계약(`EXPEDITION_ROUTE_MODULE_A/B`)이
  코드·저장·계정 milestone에는 있었지만 일반 플레이 보상에 연결되지 않았던
  gap을 확인했다. 신규 성장축을 만들지 않고, 기존 샛길 보물 보상에만 연결했다.
- Visible side treasure `CH01_VT03` now grants module A; revealed Hidden side
  treasure `CH01_HT03` now grants module B. 두 보물 모두 기존
  `RewardService`/`claim_treasure` exact-once 경로를 사용한다.
- `tools/generate_data.py`로 Godot compiled map을 재생성했고, 실제 보물 claim과
  인벤토리 반영을 검증하는 `PULSE_REWARD_01/02` 회귀를 추가했다.
- 재검증 결과: Static 70/70, Core 161/161, SRPG map **234/234**, R15 49/49,
  R16 26/26 — 현재 자동 합계 **540/540 PASS**. `git diff --check`는 기존
  CRLF/LF 변환 경고만 출력했고 whitespace 오류는 없었다.
- 이번 변경은 map topology, BattleSimulation, reward formula, save schema,
  stamina와 전투 결과를 변경하지 않는다. 배포/업로드/캐시 삭제는 하지 않았다.
- 변경된 compiled map을 포함하도록 고정 경로 `builds/web_release`를 로컬에서
  재빌드했다. `index.pck`는 59,319,720 bytes,
  SHA-256 `6396679DE53BBBCD67449A9C0A51CF4247BC9475E46C9DEF5CC1495B42613744`이며,
  이는 로컬 검증 산출물일 뿐 공개 배포가 아니다.
- 재빌드한 Release를 단 하나의 임시 인앱브라우저 탭에서 열어 실제 타이틀과 홈
  화면을 확인했다. 확인 직후 해당 탭과 `127.0.0.2:8078` 서버를 닫았고, 기존
  GPT Web 세션 탭 하나만 남겼다. 이 짧은 확인은 모듈 획득의 시각적 Web 증거를
  대체하지 않으며, 그 항목은 GPT Web 권고대로 `UNVERIFIED`로 유지한다.

## 2026-08-25 — Resume verification / repeatability guard

- 사용자 재개 후 Godot 4.7.1 headless core, SRPG map, R15, R16와 static
  검증을 재실행했다. 결과는 Static 70/70, Core 161/161, SRPG map 234/234,
  R15 49/49, R16 26/26 — **540/540 PASS**다.
- 반복 실행에서 환경변수 없이도 `Find-Godot471`가 실제 사용자 승인 설치
  경로를 찾도록 `tools/powershell/COMMON.ps1`에 ASCII wildcard 기반 탐색을
  추가했다. 설치 파일 버전은 `4.7.1.stable.official.a13da4feb`로 확인했다.
- 최신 540/540 및 PCK 바이트 정보를 기존 GPT Web 세션에 전송했다. GPT Web
  재판정은 이벤트/동료 영입/이동 모듈 보상/정확성 계약 PASS, 새 P0 0,
  `PRODUCTION_APPROVED = WAITING_USER_APPROVAL`이다.
- 실제 최신 Web에서 모듈 획득 전후 이동 cap 시각 증거와 자연 작전력 회복 후
  Release H02→H05→H05 reload는 계속 `UNVERIFIED`다. 배포·업로드·캐시 삭제는
  하지 않았고, 임시 인앱 브라우저 탭은 열지 않은 상태로 GPT Web 세션 1개만
  유지했다.
- 동일한 `hard-release-cert-r15` Release sandbox를 임시 탭 하나에서 다시
  확인했다. 복귀 시 작전력 14/124로 H02 선택·접촉까지는 가능했지만 H02는
  20.83초 패배(생존 0)했고, 권장 파티 성장 화면은 실제 보유 재료 부족으로
  추가 적용이 없었다. 결과→맵 복귀 후 H02 attempts 2/3, 작전력 부족 잠금이
  정상 표시되어 재도전 우회 없이 탭과 `127.0.0.2:8078` 서버를 즉시 닫았다.

## 2026-08-25 — Fixed-name Web rebuild repeatability / resume checkpoint

- `tools/powershell/COMMON.ps1`의 Godot 4.7.1 설치 검색 보강 후, 환경변수
  없이 동일 입력으로 고정 경로 `builds/web_release`를 연속 2회 재빌드했다.
  두 실행 모두 종료 코드 0과 `R7_WEB_RAF_PROBE=PASS`였고 `index.pck`는
  두 번 모두 59,320,264 bytes / SHA-256
  `4185e8a0c04c6205c258973abd821ff17f2f8e12b09650a5bd912d14587e0aaf`였다.
  `index.html`은 7,768 bytes / SHA-256
  `9cc566c932125acbbee38cf3d3f7cf2d626b787d5cb52382b58947bc68207f36`로
  갱신되었다.
- 현재 자동 검증은 Static 70/70, Core 161/161, SRPG map 234/234,
  R15 49/49, R16 26/26으로 **540/540 PASS**를 유지한다. 이는 로컬
  산출물 검증이며 배포·업로드·서비스 워커/캐시 삭제는 하지 않았다.
- 최신 Release의 짧은 UI 확인은 타이틀→홈→맵 H02 선택/패배와 정상적인
  작전력 게이트까지만 재확인했다. 자연 회복을 기다리지 않고 권한을
  우회하지 않았으므로 Release H02→H05 및 reload는 계속 UNVERIFIED다.

## 2026-08-25 — Resume verification checkpoint

- 문서 갱신 후 정본 자동검증을 다시 실행했다. Static 70/70, Core 161/161,
  SRPG map 234/234, R15 49/49, R16 environment 26/26으로 총 **540/540
  PASS**를 재확인했다. R16 preset/transition/authority isolation/leak
  검증도 26/26 PASS다.
- 최신 고정 이름 Web Release를 한 개의 임시 인앱 브라우저 탭에서 로드해
  타이틀 화면을 시각 확인했다. 확인 후 임시 탭과 `127.0.0.2:8078`
  서버를 즉시 닫았고, GPT Web 세션 탭 1개만 유지했다. 이 확인은 최신
  PCK의 타이틀 로드 증거이며 전체 Chapter E2E를 의미하지 않는다.
- GPT Web 최신 응답은 PCK 2회 동일 해시 재현성, 540/540, H02 정상
  패배·작전력 게이트를 PASS로 판정했고, 새 P0 결함은 없다고 확인했다.
  자연 회복 후 Release H02→H05→H05 reload와 VT03/HT03 이동 cap 실브라우저
  증거는 계속 UNVERIFIED로 유지한다. 배포·업로드·캐시 삭제는 하지 않았다.

## 2026-08-25 — Release map movement / reward evidence checkpoint

- 동일 `hard-release-cert-r15` Release 샌드박스를 임시 탭 하나에서 재개했다.
  Continue 후 계정 Lv21, 작전력 5/124, 맵 이동 5/7을 확인했다.
- 공개된 보물 샛길을 실제 선택하고 이동했다. 5칸 이동 후 Release 화면에
  `이동 범위를 소진했습니다. 대기 후 경로를 계속 이동할 수 있습니다.`가
  표시되었고, `대기`를 누르자 `이동 7/7 복구`가 표시되었다. 남은 경로를
  이어 이동한 뒤 실제 탐색 보상 화면에서 `훈련 노트 L +1`, 기존→최종
  보유량, 이번 보상으로 가능한 성장 후보를 확인했다.
- 이 실행은 이동 제한/대기/보상 UI의 실제 최신 Web 증거이며, 선택한 보물은
  이동 모듈 보물(VT03/HT03)이 아니므로 모듈 전후 `+1/+1` 증거를 대체하지
  않는다. H02→H05는 작전력 5로 입장할 수 없어 시도하지 않았다.
- 확인 후 임시 탭과 `127.0.0.2:8078` 서버를 닫고 GPT Web 세션 탭 1개만
  유지했다. 서버 로그에서 최신 Release의 `index.pck` 요청 200을 확인했다.
  배포·업로드·캐시 삭제는 하지 않았다.

## 2026-08-25 — Release stamina recovery checkpoint (14:17 KST)

- 동일한 `hard-release-cert-r15` Release namespace를 임시 인앱 브라우저
  탭 하나에서 다시 열어 저장 복구를 확인했다. 타이틀→홈까지 정상 진입했고,
  계정 Lv21 및 작전력 `8/124`가 표시되었다. 개발자 오버라이드는 사용하지
  않았다.
- H02 비용 12에는 아직 도달하지 않아 전투를 시작하지 않았으며, 이 확인은
  자연 회복·저장 복구 증거만 추가한다. 임시 탭과 `127.0.0.2:8078` 서버는
  확인 직후 닫았다. GPT Web 탭 1개만 유지했으며 배포·업로드·캐시 삭제는
  수행하지 않았다.

## 2026-08-25 — Regression rerun after resume

- 작업 재개 후 정본 회귀를 다시 실행했다. Static 70/70, Godot core 161/161,
  SRPG/R14 map 234/234, R15 49/49가 모두 PASS했다. R16 전용 26개도 직전
  실행에서 PASS한 상태이며, 이 재실행은 전투·성장·맵 권한을 변경하지 않는다.

## 2026-08-25 — Release navigation audit (14:40 KST)

- 자연 회복으로 작전력 `12/124`가 된 동일 Release namespace를 열어 H02
  경로를 확인했다. H02 입장 횟수 `2/3`와 작전력 12 비용은 정상 표시됐다.
- 맵의 이전 클리어 노드로 재배치하려고 선택 패널을 닫는 과정에서 결과 패널의
  `기존 실시간 전투 재도전` 버튼을 잘못 눌러 합법적인 N08 반복 전투가 한 번
  실행됐다. 전투는 15.47초에 5명 생존으로 승리했고 보상은 정상 1회 처리됐다.
  홈 복귀 후 작전력은 데이터 비용대로 `5/124`가 되었고 H02 상태·시도 횟수는
  변경되지 않았다. 이는 코드 결함이 아니라 QA 입력 실수이며, H02→H05
  Release 증거는 다시 자연 회복 후 이어간다.
- 확인 직후 임시 탭과 서버를 닫고 GPT Web 탭 1개만 유지했다. 배포·업로드·
  캐시 삭제는 수행하지 않았다.

## 2026-08-25 — 작업 재개 / GPT Web 재검토 (14:53 KST)

- 기존 GPT Web 세션 탭 하나에 현재 재개 상태를 다시 전달했다. GPT Web은
  자동검증 540/540, 실제 Release 이동력 `5/7 → WAIT → 7/7`, 경로 재개,
  보상 전후 보유량 UI, H02 접근·패배·맵 복귀·작전력 게이트를 PASS로
  재확인했다.
- 결과 패널을 닫는 과정에서 발생한 N08 반복전투 1회는 입력 실수이며 코드
  결함이 아니라는 판정이다. 최종 인증 전 N08 보상/first-clear/1회성
  보상 중복이 없는지 한 번만 경계 확인한다.
- VT03/HT03 실제 브라우저 이동력 cap `+1/+1`, Release H02→H05 연속
  클리어, H05 이후 새로고침 복구는 자연 작전력 회복 전까지
  **UNVERIFIED**로 유지한다. 현재 Release 저장을 덮어쓰거나 개발자
  오버라이드를 쓰지 않는다.
- GPT Web 권고 순서는 동일 저장 보존 → 자연 회복 → H02 → H03 → H04 →
  H05 실제 접촉/전투/보상/해금 → H05 이후 새로고침 복구다. 수정·배포·
  업로드·캐시 삭제는 권고되지 않았으며 수행하지 않았다.
- N08 경계 확인을 포함해 R15 49/49와 SRPG map 234/234를 재실행해 PASS했다.
  현재 집계는 기존 540/540 PASS를 유지한다.
- 같은 GPT Web 세션에 이 재검증을 다시 전달했고, GPT Web은 순서를 그대로
  유지하되 수정 없이 자연 회복 후 H02→H05→H05 새로고침 복구를 진행하라고
  재확인했다. 현재 남은 항목은 실제 Release 증거뿐이다.
- 동일 저장을 임의로 보충하지 않기 위해 `reports/r15/RELEASE_HARD_RECOVERY_PLAN.md`
  에 H02~H05의 실제 비용과 자연 회복 순서를 기록했다. 이 문서는 QA 실행
  계획이며 게임 데이터나 저장 권한을 변경하지 않는다.

## 2026-08-25 — Release recovery checkpoint (15:09 KST)

- 동일 `hard-release-cert-r15` Release sandbox를 한 개의 임시 탭으로
  재개했다. 타이틀→Continue→Home이 정상이며 계정 Lv21, 작전력 `9/124`,
  크레딧 97,900이 표시됐다. 자연 회복이 실제로 반영되고 있다.
- H02 비용 12에는 아직 3점이 부족해 전투를 시작하지 않았다. 확인 직후
  임시 탭과 `127.0.0.2:8078` 서버를 닫고 GPT Web 세션 탭 1개만 남겼다.
  개발자 오버라이드·저장 초기화·배포·업로드·캐시 삭제는 없었다.
- 이 회복 체크포인트와 다음 H02→H05 순서를 같은 GPT Web 세션에 전달했고,
  GPT Web은 정상 회복 증거로 기록하되 H02 비용 충족 전 전투를 시작하지
  말라고 재확인했다. H02→H05는 계속 UNVERIFIED다.

## 2026-08-25 — Regression recheck before HARD continuation (15:13 KST)

- 정본 변경 없이 Static 70/70, Godot core 161/161, R16 environment 26/26을
  재실행해 모두 PASS했다. 이전 R15 49/49 및 SRPG map 234/234와 합산한
  현재 집계는 **540/540 PASS**다.
- 이 실행은 실제 Release 저장·작전력·전투 진행을 변경하지 않았다.

## 2026-08-25 — Release natural recovery checkpoint (15:20 KST)

- 동일 `hard-release-cert-r15` Release sandbox를 한 개의 임시 탭으로
  확인했다. 타이틀→Continue→Home이 정상이며 계정 Lv21, 작전력 `10/124`,
  크레딧 97,900이 표시됐다. 이전 `9/124`에서 시스템 시간 기반 자연 회복
  1점이 반영됐다.
- H02 비용 12에는 아직 2점이 부족해 전투를 시작하지 않았다. 확인 직후
  임시 탭과 `127.0.0.2:8078` 서버를 닫고 GPT Web 세션 탭 1개만 남겼다.
  개발자 오버라이드·저장 초기화·시스템 시간 변경·배포·업로드·캐시 삭제는
  없었다. H02→H05 Release 증거는 계속 **UNVERIFIED**다.

## 2026-08-25 — Release H02 physical-contact defeat and reload (15:30–15:38 KST)

- 자연 회복으로 동일 `hard-release-cert-r15` 저장의 작전력이 `12/124`가
  된 뒤, 임시 탭 1개에서 HARD 맵을 열고 H02를 선택했다. 상세 패널에서
  예상 이동 33구간과 이번 펄스 7구간을 확인했다.
- 경로 이동을 확정하고 실제 부대를 여러 pulse에 걸쳐 이동시켰다. 각
  pulse에서 7/7 이동력을 소진한 뒤 WAIT로 다음 pulse를 열었고, H02 hex에
  실제 도달하자 별도 전투 재클릭 없이 Chapter 1 HARD 2 전환 및 기존
  실시간 전투가 시작됐다.
- 전투 결과는 `DEFEAT`, 20.83초, 생존 0, 보상 없음이었다. 맵 복귀 후 H02
  hostile pawn이 유지되고 패배 전 위치로 돌아왔다.
- 브라우저 reload → Continue → Home → HARD 맵에서 H02 hostile pawn과
  복귀 위치가 유지되는 것을 확인했다. H02 시도 수는 `3/3`이 되었고,
  동일 날짜에는 authored daily-attempt 정책상 재진입할 수 없다.
- 임시 탭과 `127.0.0.2:8078` 서버는 즉시 닫았다. 코드/데이터/저장 편집,
  시스템 시각 변경, 개발자 오버라이드, 배포/업로드/캐시 삭제는 없었다.
- GPT Web은 `540/540 PASS`, H02 물리 이동/접촉/기존 전투/패배/보상 없음/
  적 유지/새로고침 복구를 모두 PASS로 검토했다. 날짜 경계 후 실제 attempt
  reset은 **UNVERIFIED**로 유지하라는 판정이다.

## 2026-08-25 — GPT Web attempt-reset review (15:44 KST)

- `AppState.reset_hard_attempts_if_needed()`의 날짜 비교·카운터 초기화
  경로와 HARD `daily_attempts = 3` 데이터 계약을 정적으로 재확인했다.
- GPT Web 판정: 일일 제한 계약 PASS, 같은 날짜 3/3 차단 PASS, 날짜 경계
  reset 코드 경로 PASS(정적), 실제 날짜 경계 reset은 **UNVERIFIED**.
  H02 승리/H03~H05/H05 reload도 계속 **UNVERIFIED**이며 알려진 P0 결함은
  없음.
- 자연 날짜 경계 후 같은 저장을 `3/3 → reset → H02 승리 → H03 → H04 →
  H05 → reload` 순서로 이어가라는 검토 결과를 기록했다. 시스템 시간 변경,
  저장 편집, 개발자 권한 사용은 하지 않는다.

## 2026-08-25 — Release map-capacity checkpoint and GPT Web review (15:54 KST)

- 별도 `capacity-web-r15` Release sandbox를 한 개의 임시 탭에서 새로 열어
  타이틀 → 프롤로그 → Chapter 1 맵까지 실제로 진입했다. 동일 Web PCK
  (`4185e8a0c04c6205c258973abd821ff17f2f8e12b09650a5bd912d14587e0aaf`)에서
  맵 HUD의 `이동 7/7`, 96hex 장거리 지형, 부대 말, 조우 표식이 실제로
  렌더링됐다.
- 확인 후 임시 탭과 `127.0.0.2:8078` 서버를 닫고 GPT Web 세션 탭 1개만
  남겼다. 저장·시계·개발자 권한·코드·배포·업로드·캐시 삭제는 변경하지
  않았다.
- GPT Web은 이 증거를 `ACTUAL_WEB_MAP_ENTRY: PASS`,
  `ACTUAL_WEB_MOVEMENT_CAP_HUD: PASS`, `ACTUAL_WEB_LONG_MAP_RENDER: PASS`,
  `ACTUAL_WEB_PULSE_LIMIT/WAIT: PASS`로 검토했다. 다만 VT03/HT03 route
  module이 cap을 실제 브라우저에서 `+1/+1` 했다는 직접 증거는 계속
  **UNVERIFIED**이며, H02 victory/H03–H05/H05 reload도 날짜 경계 전까지
  **UNVERIFIED**다.

## 2026-08-25 — R16 environment regression rerun (16:12 KST)

- Godot 4.7.1 Stable 명시 실행 파일로 `environment_fx_test_runner.tscn`을
  재실행했다. R16 환경 프리셋·보간·권한 격리·품질 tier·100회 전환 누수·
  portrait 개발 패널 검사가 `26/26 PASS`였다.
- 직전 전체 회귀 실행 결과와 합산하면 Static `70/70`, Godot runtime
  `161/161`, SRPG map `234/234`, R15 `49/49`, R16 `26/26`으로
  `540/540 PASS`다. R16 래퍼의 PATH 오류는 테스트 실패가 아니라
  `godot` 별칭 미해결이었으며, 명시 경로 재실행으로 교정했다.
- 이번 확인에서도 H02 동일 날짜 `3/3` 제한, H02 승리 및 H03~H05/H05
  reload는 날짜 경계 전 실제 Release 증거가 없어 **UNVERIFIED**로
  유지한다. 배포·업로드·캐시 삭제·시계/저장 편집은 하지 않았다.

## 2026-08-25 — GPT Web event/companion evidence review (16:19 KST)

- 최신 N04/N08 증거와 `PULSE_01..06`, `EVENT_PAWN_*`,
  `EVENT_PAWN_RUNTIME_*` 결과를 기존 GPT Web 세션에 전달했다.
- GPT Web은 N04의 `동료 SD MapPawn + ! → 특별 접촉 카드 → 기존 실시간
  전투 → 즉시 영입 → 프로필/맵 복귀 → reload` 체인을 실제 Web **PASS**로
  분류했다. N08의 동료 identity·지연 영입 계약·tracking presentation도
  **PASS**로 분류했으며, N09 최종 roster 삽입을 별도 Release 캡처로
  고립해 증명한 것은 **UNVERIFIED**로 남겼다.
- 이동 제한/WAIT는 자동·실제 Web 모두 PASS, 이동력 증가의 데이터/서비스
  계산은 PASS이나 VT03/HT03 각각의 브라우저 +1/+1 귀속은 UNVERIFIED로
  유지했다. HARD H02→H05와 섞지 않았고 PRODUCTION_APPROVED는
  `WAITING_USER_APPROVAL`이다.

## 2026-08-25 — SRPG map/event runner recheck (16:17 KST)

- `tools/powershell/RUN_MAP_TESTS.ps1`를 Godot 4.7.1 Stable 탐색 결과의
  명시 실행 파일로 재실행했다. 최신 정본에서 SRPG map/event suite는
  `MAP_TEST_SUMMARY total=234 pass=234 fail=0`였다.
- 이번 출력에는 `PULSE_01..04`, `PULSE_REWARD_01..06`,
  `EVENT_PAWN_01..10`, `EVENT_PAWN_RUNTIME_01..03`(N04/N08 각각),
  전투 hash·final state 불변, 보상/영입 exactly-once와 reload 관련 검사가
  모두 포함됐다.
- GPT Web 세션은 이 결과와 실제 N04/N08 캡처를 별도 검토했고, N04
  즉시영입 체인은 Actual-Web PASS, N08 지연영입 계약/추적은
  PASS로 분류했다. N09 최종 roster 삽입의 별도 Release 캡처와 실제
  브라우저 중복 트리거 전후 관찰은 보수적으로 **UNVERIFIED**로 유지한다.

## 2026-08-25 — Development Web event fixture re-entry (16:23–16:27 KST)

- `builds/web_development`를 고정 포트 `127.0.0.2:8078`에서 한 번만
  열고, 기존 GPT Web 탭과 분리된 임시 Development 탭에서 타이틀 → 홈 →
  Chapter 1 SRPG map을 실제로 재진입했다.
- 개발자 전용 `N08 지연 합류 QA` fixture를 통해 맵 화면과 장거리 지형,
  부대 말·조우 표식·이동 HUD를 다시 확인했다. 이 fixture는 Release에
  존재하지 않으며 Release 증거로 승격하지 않았다.
- 임시 탭은 닫았고 Python 서버는 `Ctrl+C`로 종료했다. 최종 브라우저
  탭 목록에는 GPT Web 세션 1개만 남았다. 코드·저장·시계·배포는 변경하지
  않았다.

## 2026-08-25 — Developer HARD attempt-limit guard

- 개발자 권한 빌드에서는 HARD 일일 입장 제한과 작전력 부족으로 QA가
  막히지 않도록 기존 `AppState.can_enter_stage_count()` 우회를 유지하고,
  실제 입장 시 `hard_attempts` 원장을 증가시키지 않도록 정리했다.
- 개발자 화면과 SRPG 상세 패널에는 HARD 입장 횟수를 `무제한 (DEV)`로
  표시한다. 일반 Release는 기존 `사용 횟수/일일 한도`와 차감 규칙을
  그대로 유지한다.
- Godot 4.7.1 headless 재검증: core `164/164 PASS`, map/event
  `234/234 PASS`. 배포·업로드는 수행하지 않았다.

## 2026-08-25 — GPT Web developer-limit review

- 기존 GPT Web 세션 탭에 개발자 HARD 제한 변경을 전송했다. GPT Web은
  `DEV HARD DAILY-LIMIT BYPASS DESIGN = PASS`, `KNOWN P0 DEFECT = NONE`으로
  검토했으며, Release 권한 경계의 실제 전용 실행 증거는 별도로 남겨야 한다고
  구분했다.
- acceptance checks를 core runner에 추가해 `developer=true`에서 3/3 상태도
  입장 가능, HARD 원장·작전력 불변, UI `무제한 (DEV)` 표시를 검증했다.
  최신 정적 70/70, core `164/164`, map/event `234/234`가 PASS다.
- DEV 저장은 Release 인증/production 저장 증거로 사용하지 않는다. 최종
  `PRODUCTION_APPROVED`는 계속 `WAITING_USER_APPROVAL`이며 배포는 하지 않았다.
- 로컬 Development Web도 새 소스로 재빌드했다. runtime set은
  `index_dev_2fb8ffb706868c01`이며, 이는 배포가 아닌 다음 QA용 고정 로컬
  산출물이다. 임시 HTTP 서버와 브라우저 탭은 사용 후 종료한다.

## 2026-08-25 — LANTERNLINE-only cache handoff and Release reload (16:50–16:51 KST)

- 같은 `127.0.0.2:8078` origin에서 Development hand-off worker를 한 번
  실행했다. 서버 로그로 `index.service.worker.js` 200 응답을 확인했고,
  worker 계약은 `LANTERNLINE-sw-cache-*`만 삭제한 뒤 자기 등록을 해제한다.
- hand-off 직후 임시 탭을 닫고 동일 origin에서 기존 `builds/web_release`
  Release를 새로 열었다. Title → Home 캔버스가 로드됐고 서버 요청은
  index.js/WASM/PCK/worker/worklet 모두 200/304였으며 404가 없었다.
- 임시 Release 탭과 서버를 종료했고, 최종 탭은 GPT Web 세션 1개만 남겼다.
  사용자 save payload, 다른 origin 캐시, 배포 산출물은 변경하지 않았다.

## 2026-08-25 — Actual Web open-choice reload checkpoint (16:54–16:56 KST)

- LANTERNLINE-only hand-off 이후 동일 Release Web에서 Title → Home → Main
  Story로 진입해 프롤로그 선택지를 실제로 띄웠다.
- 선택지를 고르지 않은 채 같은 탭을 reload한 뒤 Title → Home → Main Story로
  재진입했을 때 동일한 열린 선택지가 복구됐다. 첫 선택을 확정하자 중복
  없이 Home으로 돌아왔다.
- 서버 로그에서 runtime JS/WASM/PCK/worker 요청 404가 없었고, 임시 탭과
  서버는 즉시 종료했다. 이 증거는 스토리 체크포인트에 한정하며 H02→H05
  연속 Release E2E를 대신하지 않는다.
- GPT Web은 `MID_STORY_OPEN_CHOICE_ACTUAL_WEB = PASS`,
  `OPEN_CHOICE_RELOAD_RESTORE = PASS`, `OPEN_CHOICE_FIRST_COMMIT = PASS`,
  `OBSERVED_DUPLICATE_COMMIT = 0`으로 검토했다. 전체 스토리 체크포인트
  매트릭스와 H02→H05 연속 Release는 별도 UNVERIFIED로 유지한다.

## 2026-08-25 — Developer HARD quota actual Web checkpoint (17:12 KST)

- Development Web의 단일 임시 QA 탭에서 isolated `r15-save-sandbox`로
  Debug QA를 실행했다. 실제 Chapter 1 위험 작전 상세 패널에
  `입장 횟수 무제한 (DEV)`, 맵 HUD에 `이동 9/9`가 표시되는 것을 확인했다.
- 증거 캡처: `reports/mvp_video_reference/screenshots/DEV_HARD_QUOTA_WEB_EVIDENCE_20260825.png`.
- GPT Web 판정: `DEV_HARD_UNLIMITED_QA = PASS`,
  `DEV_HARD_UI_ACTUAL_WEB = PASS`, `DEV_LEDGER_ISOLATION = PASS`,
  `DEV_STAMINA_ISOLATION = PASS`, `EXPORT_PRESET_AUTHORITY_BOUNDARY = PASS`,
  `KNOWN_P0_DEFECT = NONE`.
- 공식 scene runner는 `165/165 PASS`이며 public Release preset은
  `lanternline_dev_tools`가 비어 있다. 새 Release PCK artifact-level smoke는
  아직 실행하지 않아 UNVERIFIED로 유지한다. 임시 탭과 8078 서버는 캡처 후
  닫았고 배포/업로드는 하지 않았다.

## 2026-08-25 — Release artifact authority smoke

- public Web HTML Release를 현재 소스로 재빌드하고 동일한 in-app-browser
  세션에서 Title → Home → Chapter 1 intro → SRPG map을 실제 확인했다.
  `builds/web_release/index.pck` SHA-256은
  `46acae74776ae18c05791c8878fca5ee26d323123e5628dc75006d48112e114c`이며,
  Release HUD는 `이동 7/7`을 표시했다.
- Release 화면에는 developer tools와 `무제한 (DEV)`가 없었고, 브라우저
  콘솔 error/warning은 0개였다. 캡처는
  `reports/mvp_video_reference/screenshots/RELEASE_ARTIFACT_MAP_BOUNDARY_20260825.png`.
- GPT Web 판정은 `RELEASE_ARTIFACT_AUTHORITY_SMOKE = PARTIAL PASS`, `P0 = NONE`.
  동일 PCK에서 exhausted HARD `3/3` 차단·원장/작전력 불변·DEV 라벨 부재를
  직접 확인하는 Release-cert P1은 아직 UNVERIFIED다.
- 임시 Release 서버는 종료했고 배포·업로드하지 않았다. GPT Web 세션만
  유지한다.

## 2026-08-25 — Post-smoke regression confirmation

- 현재 소스에서 재실행한 정적 검증은 **70/70 PASS**다.
- Godot 4.7.1 공식 scene runner는 **165/165 PASS**, SRPG map/event는
  **234/234 PASS**, R15는 **49/49 PASS**, R16 environment는 **26/26 PASS**다.
- 합계는 **544/544 PASS, 0 FAIL**이다. `git diff --check`도 exit 0이며,
  LF/CRLF 경고만 출력됐다.
- 로컬 Release QA 서버 8078/8079는 종료됐다. GPT Web 세션은 유지했으며
  별도 Release 탭은 닫았다. 브라우저 정책상 이전 접속 실패 화면 탭의
  `data:` URL은 자동 close가 거부되어 stale tab 1개가 목록에 남아 있다;
  새 QA 탭을 추가로 열지는 않았다.

## 2026-08-25 — Same-PCK Release quota-edge review

- 동일 PCK `46acae74776ae18c05791c8878fca5ee26d323123e5628dc75006d48112e114c`
  기준 Release smoke를 GPT Web에 재검토 요청했다.
- 현재 ordinary same-origin save는 NORMAL N04라 HARD route/H02가 정상적으로
  잠겨 있다. 이 때문에 `3/3` 소진 panel을 보려는 목적으로 save 편집,
  시계 변경, Development authority 사용을 하지 않았다.
- GPT Web 판정: **PASS WITH ONE UNVERIFIED RUNTIME EDGE**, P0 없음. 남은 P1은
  같은 PCK의 exhausted HARD `3/3` 차단 및 원장/작전력 불변 실증이다.
- 성공한 임시 Release QA 탭과 8078 서버는 이미 닫혀 있다. 배포·업로드는
  수행하지 않았다.

## 2026-08-25 — Movement-capacity source readability

- 맵 상세의 이동 안내가 이제 `기본 · 계정 레벨 보너스 · 보유 노선 모듈 보너스`
  를 함께 표시한다. 계산 authority는 기존 `movement_capacity()`와 map JSON의
  `account_level_milestones`/`mobility_items`를 읽기만 하며 변경하지 않는다.
- 새 map regression `PULSE_UI_01`이 이 player-facing source breakdown을
  유지하도록 추가됐고, map suite는 **235/235 PASS**다.
- 현재 Release PCK SHA-256:
  `5609fbd93dc7df850514a09835891904344eb7ba29b59aacd23997bd12872df4`
  (59,321,496 bytes). 실제 Release N04 detail에서 `이동 7/7`,
  `기본 5 · 계정 Lv.21 +2 · 노선 모듈 +0`과 console error/warning 0을
  확인했다. 임시 tab/8078 server는 즉시 종료했고 배포·업로드는 하지 않았다.

## 2026-08-25 — Preserved quota-sandbox lookup

- GPT Web의 우선순위에 따라 `hard-release-cert-r15` 격리 namespace를 current
  public Release PCK로 한 번만 열었다. 실제 상태는 HARD 3/3 저장이 아니라
  새 Chapter 1 N01/HARD 잠금 상태였다.
- save 편집·시계 변경·DEV 권한을 사용하지 않았고, 따라서 same-PCK HARD 3/3
  gate는 계속 **UNVERIFIED**다. 성공/실패로 부풀리지 않았다.
- 해당 temporary browser tab과 8078 HTTP server는 즉시 종료했다. 배포·업로드
  는 수행하지 않았다.

## 2026-08-25 — Full post-capacity regression

- 정적 검사 **70/70**, Godot core/runtime **165/165**, SRPG map **235/235**,
  R15 content/progression **49/49**, R16 environment **26/26**을 재실행했다.
- 현 시점 합계는 **545/545 PASS, 0 FAIL**이다. 이 수치는 continuous Release
  H02→H05 또는 real-device QA를 대신하지 않으며, 해당 증거는 계속
  UNVERIFIED로 유지한다.

## 2026-08-25 — Release route-module α actual-Web check

- ordinary Release N04 map에서 visible side cache를 물리 이동으로 획득했다.
  공용 보상 화면은 `노선 확장 모듈 α +1`, inventory `0 → 1`을 실제로 표시했다.
- 이동 maximum은 즉시 7에서 8로 증가했고, 이동 후 map HUD/detail에는 `5/8` 및
  `기본 5 · 계정 Lv.21 +2 · 노선 모듈 +1`이 나타났다.
- browser reload 뒤에도 동일한 `5/8`/`+1` 상태가 복구됐고 console error/warning은
  0이었다. DEV authority, save edit, clock change는 사용하지 않았다.
- module β / 9/9 WAIT refill / HARD continuous evidence는 여전히 UNVERIFIED.
  temporary QA tab과 8078 server는 즉시 종료했고 배포·업로드는 하지 않았다.

## 2026-08-25 — Full-length local BGM repack and fixed-name Web rebuild

- 사용자 제공 `Sound` 원본은 수정하지 않고, 런타임 복사본만 다시 생성했다.
  타이틀 BGM의 30초 excerpt 제한을 제거했고, title MP3는 원본 전체
  `4,097,476` bytes로 반영됐다. lobby/story/battle/boss BGM은 각각 약
  89.94초 전곡을 유지한다.
- 기존 `AudioService`의 1.8초 two-player pre-end crossfade를 보존했다.
  이 변경은 전투·맵·저장 authority를 변경하지 않는다.
- `SYNC_LOCAL_AUDIO.ps1` 및 두 Web build 스크립트가 Python 3.14-capable
  로컬 audio packer를 먼저 실행하도록 고정했다. WAVE_FORMAT_EXTENSIBLE
  입력을 Python 3.11로 읽다가 실패하던 재현성 문제를 제거했다.
- 정적 70/70, Godot runtime 165/165, SRPG map 249/249, R15 49/49, R16
  26/26, 합계 **559/559 PASS**를 다시 실행했다.
- 고정 R7 Release `builds/web_release/index.pck`를 in-place로 덮어썼다:
  `62,791,336` bytes, SHA-256
  `148efe50fd4327b97de86b921cfe156b41626eb323ce9369c4191614053194e1`.
  한 개의 임시 in-app browser tab에서 Title → Home 부팅을 확인한 뒤 탭과
  8078 서버를 종료했다. 배포·업로드는 수행하지 않았다.

## 2026-08-25 — Complete Chapter 1 balance rerun and observable checkpoints

- 중단된 balance runner의 checkpoint를 재개하여 Chapter 1 NORMAL/HARD의
  LOW/RECOMMENDED/HIGH × AUTO/SCRIPTED_MANUAL matrix **90 cells / 18,000
  BattleSimulation runs**를 실제 완료했다. 현재 matrix target audit은
  **13 PASS / 0 FAIL / 0 UNVERIFIED**다.
- `RUN_R15_BALANCE.ps1`은 이제 각 checkpointed cell의 Godot 출력을 실시간으로
  내보내면서도 exit code와 script-error 검증을 유지한다. 1-cell smoke를
  통과해 장기 검증이 무응답으로 보이는 문제를 줄였다.
- 그 후 static 70/70, core 165/165, map 249/249, R15 49/49, R16 26/26,
  합계 **559/559 PASS**와 fresh-save N01→N10 reward/growth/save simulation을
  재실행했다. Web upload/deployment는 수행하지 않았다.
