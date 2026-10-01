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

## 2026-09-11 — SD player defeat poses and enemy explosion-only presentation

- CHR001–CHR008에 전투용 SD 엎드림 원화 8종을 추가했다. 각 원화는 초록색
  마스터를 보존하고, 키잉한 512×512 RGBA 런타임 파생본과 머리 앵커 메타데이터를
  `godot/assets/runtime_web/combat_down_pose/`에 등록했다.
- `BattleView`는 실제 전투불능 플레이어에게 고정 SD 원화를 그리며, 기존 down 회전과
  afterimage를 건너뛴다. 적과 보스는 전용 비트맵을 읽지 않고 짧은 Canvas 폭발
  플래시·링·파편 연출만 표시한다. 라이브러리도 `CHR` ID만 허용한다.
- 잘못 생성된 풀 일러스트 후보와 적/보스 후보는
  `work/down_pose_sd_20260911/quarantine/`에 보존하고 런타임에서 제외했다.
- Godot 헤드리스 회귀 **297/297 PASS**, Web R7 Development/Release 빌드와
  HD 644 pages/BGM 5 tracks 사이드카 검증을 완료했다. 릴리스 PCK는
  `7ed7c66e99a53ad915b141b57f91bc54e3b8a9dfa76b189bfba864156caa86e2`다.
- 인트로 브라우저 검증은 1920×1080/50초, BGM 디코드, 일시정지·재개, 50초 ended를
  통과했다. 배포·업로드는 수행하지 않았다.

## 2026-09-11 — 검증본 연결 및 비사운드 자산 추가 정리

- 엑스포트 PCK의 `.import` 텍스처를 찾도록 SD 전투불능 로딩을 수정하고,
  마지막 적이 제거되어도 폭발이 끝난 뒤 결과 화면으로 넘어가도록 했다.
  CHR001–CHR008의 원화만 완료이며 CHR009–CHR044의 신규 SD 엎드림 원화는 미완료다.
- 회귀 301/301, 실제 전투 완료 3회 포함 검사 223/223, 고정 전투불능 렌더러
  16/16, 일반 릴리스 부팅·지도·음악 4/4 PASS. 현재 PCK는
  `0d481c47c34bc2c88904bf8a1523d7176320e3a5bfb034d3bba7c94b1374c893`이다.
- 이전 서버·중복 빌드·검사 프로필·캐시를 정리하고 실행기를
  `builds/web_verified_local_20260911_release/`로 연결했다.
  현재 URL은 `http://127.0.0.1:8770/play/0d481c47c34b/`이다.
- 작업 폴더 최초 96.66GiB → 1차 16.67GiB → 추가 정리 후 약 13.53GiB.
  추가 정리에서는 동일한 검사 PNG 283개와 옛 배포 준비 파일을 삭제했고,
  대형 기록 127개·보류 원화 기록 4,310개·LFS 빌드 17개는 해시가 일치하는
  복구 압축본으로 통합한 뒤 풀린 사본을 제거했다. Git 이력은 보존했다.
- 추가 정리 전 남아 있던 사운드 299개를 모두 보존했다. 별도 보호 대상 음악
  166개와 이전 인트로 포함 영상 12개의 해시가 일치한다. 최종 보존 검사
  27/27 PASS. 상세 삭제 목록·복구 경로·검증 범위는
  `reports/storage_cleanup_20260911/COMPLETION.md`에 기록했다.
- QA 도구는 종료 시 자체 브라우저 프로필을 정리한다. 다음 헤드리스 검사에서
  임포트 캐시가 없으면 에디터 임포트를 먼저 수행한다. 배포·업로드는 하지 않았다.

## 2026-09-24 — Claude 점검 및 권장 순서 개선 (1~5단계 + 결과·성장 화면)

- 1단계: 09-05 이후 미커밋 작업을 스냅샷 커밋(`12ac81d`)했다. `quarantine/`·QA 셰이더
  캐시는 `.gitignore`로 제외했고 QA 브라우저 프로필 약 505MB는 휴지통으로 옮겼다.
  런처를 오디오 schema v2 빌드로 연결하고 이전 빌드 서버를 교체하도록 했다.
  `Invoke-Checked`가 Windows PowerShell 5.1에서 Godot 경고 한 줄에 중단되던 문제와
  COMMON.ps1 한글 깨짐(BOM 없음)을 고쳤고, 데이터 변경을 따라가지 못한 테스트 3건을 갱신했다.
- 2단계: 스토리 아카이브는 본 장면만 열고 다시보기 모드(보상·플래그·영입·트리거·
  체크포인트 없음)로 재생한다. 편성 프리셋의 미합류 동료를 로드 시 자동 교체하고 전투
  전 검사한다. 편성 오류·에셋 로딩 실패 시 전투 토큰을 해제하고 입장 비용을 환불한다.
  읽을 수 없는/신버전 세이브는 쓰기 잠금 후 플레이어 선택 시 별도 파일로 보관한다.
  목록 전투 승리는 부대를 순간이동시키지 않는다. 잠긴 스테이지 순찰은 본래 칸에서 휴면한다.
  Release 전투·소탕은 매번 새 시드를 쓴다(개발 모드는 고정). 숨겨진 footer 메시지는 토스트로 보인다.
- 3단계: 전열이 적 쪽에 서도록 진형 좌표를 뒤집었고, HP·보호막·이름·상태 표시를 이펙트
  위 단계로 옮겨 화면 배율에 맞춰 키웠다. 10칸 전술 게이지와 한국어 HUD를 넣었고
  보호막 표시를 시전자별로 추적한다. 미니맵 범례 색·마커 크기·막힌 지형 표시를 고쳤다.
- 4단계: 적 대상 선택에 열 가중치(근접은 전열 위주), 광역 궁극기의 방어 궁극기 예약
  (부상·보스전 한정), 대상 확인 후 게이지 차감, 버프/디버프 레벨 비례 강도와 강화 허용,
  DEBUFF 일반 스킬 방어 감소, 보스 2초 예고기(기절 시 취소)·2페이즈 강화, 시간 종료 동시
  처치 승리, 적 공격 예고 링을 넣었다. 권장 레벨 파티 24시드 비교에서 N01~N20 승률·
  전투불능은 기존과 동등했다(보스전 전투불능 0.08→0.29명).
- 5단계(일부): 참조 없는 스크립트·씬 29개 삭제, 모바일 안정화 autoload의 매 프레임 JS
  호출을 0.25초 주기로 줄임, 결과 화면을 `screens/result_presentation.gd`로 분리했다.
  `app_shell.gd`·`chapter_map_screen.gd` 본격 분할은 소스 문자열 검사 테스트 의존이 커서 보류했다.
- 결과·성장 화면: 별 조건(승리/전원 생존/목표 시간)과 소탕 해금 안내, MVP·파티 기여도,
  `progression/growth_advisor.gd` 기반 "다음 성장 추천"(목표 작전 권장 레벨 대비 전투력,
  쓰러진 동료·전열 우선, 이유와 예상 상승치, 바로 적용)을 결과·성장 화면에 넣었다.
- 신규 테스트: `progression_integrity_runner`(22), `combat_tactics_runner`(26),
  `growth_advisor_runner`(15), 맵 휴면 순찰 검사 1건. 배포·업로드는 하지 않았다.
- 최종 로컬 실행본: `builds/web_claude_20260924_r2_release/`, PCK SHA-256
  `4f6779010c3c5e742d5b7ec5b5f9ef47babddc4f44a00b166a10798beb9a7c72`. 실행기는 이전 빌드
  서버(PID 16272)를 교체하고 `http://127.0.0.1:8770/play/4f6779010c3c/`를 연다.
  전체 러너 30종 + growth_advisor 15/15 통과(r15 54/54, map 358/358, core 301/301,
  조우 매트릭스 8309/8309). 좁은 창에서 프롤로그 대화창이 AUTO/SKIP을 덮던 문제도 고쳤다.
- 교체된 빌드는 기존 방식대로 `_audio/`·`intro.mp4`만 남기고 휴지통으로 옮겼다(복구 가능):
  `web_claude_step3_release`(PCK 6c4fab219e59…), `web_claude_step4_release`(1ae60665795f…),
  `web_claude_20260924_release`(00a05adab173…), `web_combat_motion_scout_final_20260913_release`
  (f79324fa25e0…). 09-20 Sites 빌드와 `web_development`는 그대로 두었다.

## 2026-09-24 — 연출 강화: 타이틀·스토리·전투 (Claude)

- 공용 셰이더 `godot/ui/shaders/`(live_portrait·drift_background·light_rays·motes·
  text_shine·fog_band)와 도우미 `ui/cinematic_fx.gd`를 추가했다. 일러스트는 발을 기준점으로
  호흡·흔들림·머리카락/옷자락 물결·림라이트가 들어간 Live2D풍 대기 동작을 한다.
- 타이틀: 드리프트 배경, 캐릭터 뒤 빛줄기, 안개·빛가루, 128px 금빛 로고(윤곽·그림자·광택),
  비스듬한 금색 시작 버튼과 맥동 글로우, 페이드 인, 타이틀 BGM 재생.
- 스토리: 화자는 선명하고 청자는 불투명하게 어둡게(기존 반투명 유령 표현 제거), 배경 드리프트·
  빛줄기·안개·빛가루·레터박스, 금테 글로우 대화창과 깜빡이는 진행 안내. 장 스토리는 대형 입식
  일러스트가 대화창 뒤로 걸치는 배치로 바꿨다.
- 버튼(전역): 주요 버튼은 비스듬한 평행사변형, 모든 버튼에 입체 그림자와 hover/focus 발광.
  선택 카드는 기울지 않는 `selected` 스타일로 발광한다.
- 전투: 모든 유닛에 발 고정 호흡·흔들림(보스는 부유), 팀 색 발밑 발광 링, 상단 HUD 바,
  AUTO 켜짐 발광, 궁극기 버튼(충전 중 흑백·비용 칩·준비 시 이중 광륜과 회전 불꽃),
  웨이브 배너, 치명타 금색+CRITICAL, 데미지 숫자 흩뿌리기, MISS 축소.
- 전투 로직: 적 역할 스킬(치유·강화·약화·범위·포격·방어)을 스킬 타이머에 연결했다. 1장(권장
  Lv20 이하)은 도입부 튜닝과 새 저장 E2E(`r15_fresh_progression_bootstrap`)를 지키기 위해 제외하고,
  2장부터 45% 위력으로 시작해 Lv40에서 100%가 된다. 보스 스테이지와 보스 생존 중에는 쓰지 않는다
  (보스 예고 패턴 가독성). 권장 레벨 24시드 비교: CH02-N02/N08/N16·CH03-N10·CH05-N10 모두 24/24로
  기존과 같고, 보스 스테이지는 기존 수치 그대로다.
- (정정) 위 CH02-N20 2/24 등은 돌파·무기·스킬 없이 레벨만 맞춘 측정이었다. 권장 성장 프로필로는
  1~4장 보스전이 23~24/24이며, 실제 문제는 5장 이후였다. 아래 캠페인 밸런스 항목 참고.
- 인트로를 빨리 넘기면 페이드 콜백이 해제된 노드를 받던 오류와 AUTO 버튼 메타 조회 오류를 고쳤다.
- 전체 회귀 31개 장면 통과(test_runner 301, r15 54, 전투 전술 34, 보스 흐름 153, 조우 매트릭스 8309 등).
- 최종 로컬 실행본: `builds/web_claude_20260924_r3_release/`, PCK SHA-256
  `051829122aeea08cb49001d99120531affba6471f5dd871b954fa0fcc49bf371`. 실행기는 r2 서버(PID 15432)를
  교체하고 `http://127.0.0.1:8770/play/051829122aee/`를 연다. 웹에서 타이틀 셰이더가 정상 표시된다.
- 교체된 `web_claude_20260924_r2_release`(PCK 4f6779010c3c…)는 `_audio/`·`intro.mp4`만 남기고
  휴지통으로 옮겼다(복구 가능). 배포·업로드는 하지 않았다.
- 결과 화면 헤더가 좁은 열의 자동 줄바꿈 때문에 화면 전체로 늘어나던 버그, 좁은 창 프롤로그
  SKIP 가림을 고쳤다. `tools/capture_cinematic_qa.tscn`으로 1920×1080 화면 캡처를 검증했다.

## 2026-09-24 — 캠페인 밸런스 재조정 5~20장 (Claude)

- 권장 성장 프로필(돌파·무기·스킬 포함) 측정 결과 1~4장은 정상, 5장 N20부터 보스전 0/24, 7장부터
  일반 작전까지 0/24였다. 레벨 상한 뒤 성장은 스킬뿐(최대 스킬 +8~20%)인데 생성기가 지역 적·보스
  기본 능력치 상승 위에 `post_cap_scale`(장당 +0.144)을 계속 곱해 20장 보스가 약 6.6배 강했다.
- `godot/tools/campaign_balance_calibrator.tscn`으로 431개 스테이지의 적 배율을 이분 탐색해
  `data_source/stage_balance_overrides.json`에 기록했다. `tools/generate_data.py`는 이제 3~20장에도
  덮어쓰기 값을 적용한다. 목표 승률: 일반 95→85%, N20 75%, 하드 70→55%, H05 40%. 일반 작전은
  쉬워지기만 하고 마지막 작전은 최대 ×1.25까지 어려워진다. 1장은 하드닝 값 유지(H05만 1.385→1.357).
- 기대 성장은 `GrowthAdvisor.expected_skill_levels`(5장부터 스킬 3→10, 궁극기 1→5) 하나로 정의해
  보정기·성장 화면·결과 화면·작전 상세가 같이 쓴다. 레벨 100 파티라도 스킬이 모자라면 준비도가
  100%가 되지 않고 "이 작전은 스킬 Lv.N 기준" 추천이 우선한다(테스트 ADVISOR_10~12).
- 분리된 검증 시드로 500개 스테이지 전부 승리 가능, 목표보다 25%p 넘게 낮은 곳 없음.
  상세·원자료는 `reports/campaign_balance_20260924/`에 있다.
- 남은 점: 4~6장 H05는 정예 마무리라 ×1.25 상한에서도 100%, 후반 보스전은 제한 시간 90% 이상 소요.
- 로컬 실행본: `builds/web_claude_20260924_r4_release/`, PCK SHA-256
  `6042f07fd55ad1aa94ad7d947231d1475de663e703271a71f50460a339da0e68`, 실행 주소
  `http://127.0.0.1:8770/play/6042f07fd55a/`. 교체된 r3(PCK 051829122aee…)은 `_audio/`·`intro.mp4`만
  남기고 휴지통으로 옮겼다. 전체 회귀 31개 장면 통과, 정적 감사 71/71. 배포·업로드는 하지 않았다.

## 2026-09-24 — 결과 화면 성장 제거·성장 메뉴 (Claude)

- 전투 결과 화면에서 파티 성장을 모두 뺐다: "파티 성장"/"권장 파티 성장" 버튼, "다음 성장 추천" 패널,
  "이번 보상으로 새롭게 가능한 성장" 목록. 결과는 별 조건·MVP·파티 기여도·보상·해금 안내만 보여준다.
  (맵 보물 획득 창의 새 성장 안내는 그대로 둔다.)
- 새 `godot/screens/growth_menu.gd`: "메뉴" 모달에 레벨업·스킬업 항목이 따로 있다. 각 항목은 지금 올릴
  수 있는 동료 수를 보여주고, 누르면 그 성장이 가능한 파티원으로 해당 탭의 성장 화면을 연다. 성장 화면
  제목은 현재 탭 이름을 따른다. 모바일 가로(915×412 등)에서는 패널과 터치 영역을 키운다.
- 메뉴 위치: 본부 상단(설정 옆), 전투맵 도구줄(파티 편성 옆, 좁은 화면에서도 표시), 릴레이 캠프(출발
  거점) 상세 패널의 "정비 메뉴 · 레벨업 / 스킬업". 지도에서 연 성장 화면의 뒤로는 지도로 돌아간다.
- 테스트: `growth_advisor_runner` RESULT_UI_04를 "결과에 성장 없음"으로 바꾸고 MENU_01~07을 추가했다.
  1920×1080·915×412 캡처로 본부·지도·캠프·메뉴·스킬업 화면을 확인했다(임시 캡처 도구는 휴지통).
- 전체 회귀 31개 장면 통과(growth_advisor 25, test_runner 301, r15 54, map 358, 조우 매트릭스 8309 등),
  정적 감사 71/71. `capture_mobile_progression_qa`는 폐지된 세로 레이아웃 노드를 찾아 원래부터 실패하는
  도구라 이번 변경분(결과에 성장 버튼 없음·결과 버튼 줄 표시)만 확인했다.
- 메뉴 버튼이 추가되어 좁은 가로 화면(약 700 CSS px 이하)에서 지도 도구줄이 두 줄로 넘어가던 것을 버튼 폭
  78→64, 간격 10→6으로 줄여 565×318~1280×720에서 한 줄로 유지했다.
- 로컬 실행본: `builds/web_claude_20260924_r6_release/`, PCK SHA-256
  `0c22b6faadc5e4d3690e38936ab660da6d661eb405d83fbb0032858de38863e1`, 실행 주소
  `http://127.0.0.1:8770/play/0c22b6faadc5/`(서버 PID 9412). 웹에서 본부 메뉴→레벨업 이동을 확인했다.
  교체된 r4(PCK 6042f07fd55a…)와 도구줄 수정 전 후보 r5(PCK a5a01149798d…)는 `_audio/`·`intro.mp4`만
  남기고 휴지통으로 옮겼다. 배포·업로드는 하지 않았다.
- 릴레이 작전(삼중 노선 릴레이) 화면 머리줄 오른쪽에도 같은 "메뉴"를 넣었다(테스트 MENU_08~09,
  1920×1080·915×412 캡처 확인).
- 로컬 실행본을 `builds/web_claude_20260924_r7_release/`로 교체했다. PCK SHA-256
  `6337424b2208f088f9d55e1679350694347af4b33e2a0c8cff8d6f1f0573b9a6`, 실행 주소
  `http://127.0.0.1:8770/play/6337424b2208/`(서버 PID 26968). 웹에서 릴레이 작전→메뉴→스킬업→뒤로(릴레이
  복귀)를 확인했다. 전체 회귀 31개 장면 통과. 교체된 r6(PCK 0c22b6faadc5…)은 `_audio/`·`intro.mp4`만 남기고
  휴지통으로 옮겼다.

## 2026-09-24 — 로컬 용량 정리 (Claude)

- 손실 없는 대상만 격리 후 휴지통으로 보냈다(파일 1,232개, 1.34GiB):
  - 09-20 개발 빌드 `builds/web_development`(`_audio/` 유지)
  - QA용 Godot 실행 프로필
  - 게임 자산과 SHA-256이 같은 작업·격리 폴더 사본
- 격리 뒤 1,232개 모두 격리 확인, 중복 1,152개의 남은 사본은 모두 해시 일치, r7 실행본 HTTP 200을 확인했다.
- 소리·영상, Sites 배포 입력물(Codex 담당), 복구 압축본은 남겼다.
  상세와 파일별 기록은 `reports/storage_cleanup_20260924/`.
- 2차(사용자 요청 "남은 작업 중간물, 교체되어 필요없는 원화들도 정리"): `work/`·`quarantine/`의 제작 중간물과
  교체 전 원화 4,503개·1.20GiB를 해시 기록 후 격리하고 휴지통으로 보냈다. 전투 동작 후보, 몹/동료 교체 전 원화와
  생성 중간물, 고밀도 작업본, 09-07 QA 후보 등이다. 게임이 출처로 가리키는 전투불능 원본 8장
  (`work/down_pose_sd_20260911/masters/`)과 모든 소리·영상은 남겼다. 격리 상태에서 정적 검사 71/71,
  헤드리스 회귀 31개 장면 통과, r7 실행본 HTTP 200을 확인했다.

## 2026-09-27 — 일본어 스토리 음성 (Claude)

- 사용자 요청: "시나리오를 일본어로 번역한 후 일본어로만 생성… 한국어 나레이션에 일본어 음성", 생성은 알리바바 개인 Token Plan
  싱가포르(`qwen-audio-3.0-tts-plus`)로. 화면 텍스트는 한국어 그대로, 대사·나레이션 335줄(같은 화자·같은 문장은 공유해
  파일 250개, 총 34분·15MB)에 일본어 음성을 붙였다. 주인공 선택지는 무음성. 구독 할당량만 썼고 과금 경로는 켜지 않았다.
- 번역·용어 읽기·캐스팅(성인 여성 목소리 25종)은 `data_source/voice/ja/`, 도구는 `tools/voice/voice_ja_pipeline.py`
  (`extract`→`jobs`→`run`→`qa`→`select`→`finalize`). 모든 줄을 faster-whisper medium으로 받아쓰기 대조했다. 자동 표시
  15줄과 경계선 줄을 검토해 오독·잡음 8줄(逆行, 灰白, 余剰, 浮標, 採掘環, 첫 음절 잡음, 클리핑 2)은 재생성본으로 바꿨고
  (더 깨끗한 재생성본을 고른 1줄 포함 총 9줄 교체), 나머지 표시 줄은 같은 발음의 다른 한자이거나 받아쓰기 쪽 편향
  (残光→残酷, 監査官→観察官)임을 짧은 대조 음성으로 확인했다.
  음성은 앞뒤 무음을 다듬고 -18 LUFS로 맞춘 OGG다. 줄별 원문·번역·해시는 `voice_lines_ja.json`.
- 게임: 줄을 넘기면 이전 음성이 끊기고, AUTO는 음성이 끝난 뒤 짧게 쉬고 넘어간다. 스토리 화면을 벗어나면 멈춘다.
  설정 `voice_volume`(마스터와 곱함). Web은 BGM·효과음과 같이 브라우저 오디오로 `_audio/voice/ja/` 사이드카를
  재생하고(시나리오 시작 때 해당 줄 미리 받기), 음성 OGG는 PCK에서 제외했다(PCK +36KB). 인게임 라이선스 화면과
  `docs/LICENSE_POLICY.md`에 제작 단계 TTS 사용과 실행 중 TTS 없음을 적었다.
- 검증: Godot 테스트 307/307(음성 6항목 추가), 헤드리스 회귀 31개 장면 통과, 정적 검사 71/71.
  후보 빌드 `builds/web_voice_ja_r11_release`(PCK SHA-256 `244e9c3178e1df9f3133a5bc85d8ce5363b3ad45c69a8e054ff6baf3239f70aa`)를
  브라우저에서 열어 프롤로그 4줄이 미리 받아지고 4/4 재생·실패 0인 것을 확인했다. 로컬 실행기를 r11로 바꿨다
  (`http://127.0.0.1:8770/play/244e9c3178e1/`). 직전 빌드 r10(Codex)은 그대로 두었다. 배포는 하지 않았다.

## 2026-09-27 — 캠페인 시나리오 전면 개편, 맵 이벤트·일본어 음성 확장 (Claude)

- 사용자 요청: "시나리오 전체 점검해서 제대로 멋지고 웅장한 시나리오가 될 수 있도록 수정하고 그에 따라 나레이션,
  동료 첫대면 이벤트(전투 등)와 영입 및 보스 대면과 함께 맵에서 갑작스러운 돌발 이벤트 등이 발생할 수 있도록".
- 이야기: 20장을 5막 한 줄기로 다시 썼다. 대정전의 밤 항해자가 한 첫 서명(최종 시간표 초안)과 종착 관제가 기다리는
  마지막 서명이 17장에서 드러나고, 스무 노선의 서명으로 새 시간표를 쓰는 20장에서 맞물린다. 시오의 마지막 무전(11장)과
  잔향(19장)이 소렌·마에루의 선을 잇는다. 장마다 INTRO·MID_A·MID_B·CAMP·PREBOSS·OUTRO·HARD_INTRO·HARD_OUTRO
  8장면, 프롤로그와 관계 이야기 2개를 더해 163장면이다. 원고 `data_source/story_script/*.json`, 형식
  `docs/STORY_SCRIPT_FORMAT.md`, 세계관 `docs/STORY_BIBLE.md`, 장면별 줄거리 `docs/STORY_OUTLINE.md`.
  컴파일러(`tools/story_script.py`)는 대사 어조로 표정을 바꾸고(`e`로 직접 지정), 엔딩 장면에서 쓰러진 보스는 마지막
  대사 뒤 퇴장시킨다.
- 맵: 동료 첫대면은 전투 전 대화 뒤 승리하면 합류한다. 1~19장 H03마다 떠도는 대원(CHR026–044) 한 명이 같은
  방식으로 합류한다(한 번 이기면 합류하는 조우는 "이 전투에서 승리하면 합류"로 표시). 특이 위협과 보스는 전투 전에
  말을 건다. 이동 중 돌발 사건 6종(매복·구조 요청·폭풍·보급품·잡담·잔향)이 장마다 한 번씩, N02 첫 클리어 뒤 2칸
  이상 이동에서 24% 확률(이후 2회 이동 쿨다운)로 일어나며 일부는 선택지를 준다.
- 음성: 스토리 1,905줄과 맵 대사 952줄, 모두 2,857줄에 일본어 음성을 붙였다(기존 335줄). 번역은 5개 그룹으로
  나눠 옮긴 뒤 읽기·1인칭·용어를 맞춰 병합했고, 새 화자 27명에게 목소리를 배정했다. 알리바바 Token Plan(싱가포르,
  `qwen-audio-3.0-tts-plus`) 구독 할당량만 썼고 생성 실패 0. faster-whisper medium으로 모든 줄을 받아써 대조했다
  (숫자·가나 표기 차이는 정규화, 히라가나로만 받아쓴 줄은 중립 문장 프롬프트로 한 번 더 받아씀). 걸린 줄은 최대
  네 번 다시 생성했고 오독 4줄은 가나 읽기로 고쳤다. 남은 표시 93줄은 동음이의어·반복 대사 축약 같은 받아쓰기 쪽
  차이였고, 클리핑 4줄은 5초에 샘플 1~12개라 들리지 않는다. 옛 런타임 음성 250개는 해시와 함께
  `quarantine/voice_ja_r11_runtime_20260927/`에 보관했고, 새 목록에 없는 59개만 런타임 폴더에서 휴지통으로 보냈다.
- 검증: Godot 테스트 308/308, r15 54/54, 맵 358/358, 스토리 연속성 946/946, 지역 197/197, 보스 흐름 153/153,
  스토리 UI 25/25 등 헤드리스 회귀 31개 장면 통과, 정적 검사 71/71. 1920×1080 화면 밖 렌더로 스토리·동료 조우·특이
  위협·보스·돌발 사건 창을 캡처해 확인했다(`reports/story_campaign_r12_20260927/qa/`).
- 빌드: `builds/web_story_r12_release`(PCK SHA-256 `437ceb54f1b226898ee5dd8f1d82d9ae876d27eab713be32fbf641b4363d5598`,
  음성 사이드카 2,857개). 브라우저에서 프롤로그 19줄이 미리 받아지고 재생 5/5·실패 0·60fps, 실제 저장 쓰기 0(샌드박스)을
  확인했다. 로컬 실행기를 r12로 바꿨다(`http://127.0.0.1:8770/play/437ceb54f1b2/`). 빌드는 r12(현재)와 r11(직전 검증본)만
  남기고 r10·텍스트 전용 r12·개발 QA 빌드는 해시 기록 뒤 휴지통으로 보냈다(`_audio/`·`intro.mp4`는
  `quarantine/retired_builds_20260927/`에 보존, 기록 `reports/story_campaign_r12_20260927/`).
- 배포·푸시는 하지 않았다.

## 2026-09-27 — 작은 가로 화면 스토리 창 수정, "권장 성장" 개편 (Claude)

- 사용자 요청: 작은 가로 화면에서 대사 창이 AUTO/SKIP 위로 커지는 문제 수정, "권장 눌러도 별로 권장까지 레벨, 스킬업이
  되지 않는다. 이것도 함께 개편해라".
- 스토리 창: 대사 글자 크기와 프롤로그 대사 판 높이에 화면 높이 비율(`story_fit_for_size`, 기준 높이 340/520 CSS px,
  최소 0.55)을 곱했다. 353×198에서 재현되던 겹침이 없어졌고 여섯 크기와 일반 장면에서 창이 화면 안에 들어간다.
- 원인: 권장 수준까지 필요한 경험치의 약 1%만 보상으로 들어왔고, 계정 레벨이 권장 레벨보다 40가량 낮아 캐릭터 레벨
  상한이 막혔으며, 스킬·돌파·무기 재료가 모자랐고, 무기 칩(100 EXP 단위)이 10 EXP 단위 티어 상한에 딱 맞지 않아
  무기 티어업이 불가능했다. 기존 버튼은 12단계까지만 실행했다.
- 권장 프로필(`GrowthAdvisor.recommended_profile`): 권장 레벨과 그 돌파, 스킬(1~4장 2/2/1, 이후 20장까지 최대),
  무기 레벨 min(60, 권장 레벨). 성장 화면 머리말·작전 상세·밸런스 보정기가 같은 프로필을 쓴다.
- 권장 성장(`GrowthPlanBuilder.preview_to_recommended` / `execute_to_recommended`): 한 번 누르면 파티 5명을 목표
  작전의 권장 프로필까지 올린다. 레벨은 가장 낮은 동료부터 한 단계씩(상한이면 돌파), 스킬은 한 단계씩 돌아가며,
  무기는 상한에서 티어업하고 목표에 닿는 가장 작은 칩을 쓴다. 권장 수준을 넘겨 쓰지 않는다. 미리보기는 같은 계획을
  프로필 사본에서 돌려 결과·소모·부족을 보여 주고, 실행 결과와 일치하는지 확인한다. 성장 화면 "권장 성장" 카드와
  메뉴(로비·지도·릴레이)의 "권장 성장" 항목에서 쓸 수 있다.
- 경제: 첫 클리어 보상에 성장 재료 묶음(`growth_first_clear`)을 더했다. 생성기(`tools/generate_data.py`)가 필수 루트를
  따라 다음 필수 작전의 권장 프로필 × 1.10 + 동료당 한 레벨 분 경험치까지 채우고, 선택 작전은 장별 증가분의 30%를
  준다. 훈련 노트는 그 레벨의 한 단계 비용보다 큰 권종을 쓰지 않고, 무기 칩은 M과 S(30%)로 준다. 첫 클리어 때 계정
  레벨을 권장 레벨 + 10까지 올린다. 무기 칩은 티어 상한에서 100 EXP 미만이 남는 경우만 허용한다. 새 게임 시작
  재료는 스킬 교본 T1 30, 훈련 노트 M 27(L 3장 대신 같은 경험치)로 바꿨다.
- 세이브 스키마 10: 이미 클리어한 작전의 성장 재료를 한 번 지급하고 계정 레벨을 올리며, 로비나 지도에 처음 들어갈 때
  한 번 알린다. 작전 상세와 지도 작전 정보에 첫 클리어 보상을 표시하고, 재료 획득처는 이미 클리어한 작전의 첫 클리어
  보상을 가리키지 않는다. 처음 뜨는 알림 토스트가 폭 0으로 줄바꿈을 계산해 글자가 화면 밖으로 밀리던 문제도 고쳤다.
- 검증: 새 `tests/growth_economy_runner`(필수 루트 249개 작전마다 한 번 눌러 5명 모두 권장 프로필 도달, 장 보스 직전에만
  눌러도 도달, v9 이관 지급량 일치), 성장 가이드 32/32, r15 성장 계획 15항목 등 헤드리스 회귀 32개 장면 통과(test_runner 308/308, r15 54/54, 성장 경제 9/9, 맵 358/358, 스토리 UI 25/25), 정적 검사 71/71. 1280×720·740×360
  화면 밖 렌더로 성장 카드·메뉴·결과 토스트를 캡처해 확인했다.
- 빌드: `builds/web_growth_r13_release`(PCK SHA-256 `ece5f217abc269e7ec59b1dc5de0538573727233d2f34aa564e84b7e6b02b6a5`).
  브라우저(QA 샌드박스 저장)에서 프롤로그 → 로비 → 1장 지도와 메뉴의 권장 성장(5명·10단계, 결과 토스트)을 확인했다.
  로컬 실행기를 r13으로 바꿨다(`http://127.0.0.1:8770/play/ece5f217abc2/`). 빌드는 r13(현재)과 r12(직전 검증본)만 남기고
  r11은 해시 기록 뒤 휴지통으로 보냈다(`_audio/`·`intro.mp4`는 `quarantine/retired_builds_20260927/`에 보존,
  기록·캡처 `reports/growth_r13_20260927/`)
- 배포·푸시는 하지 않았다.

## 2026-09-28 — 전술 전투 개편: 배치 + 대응 중심 (Claude)

- 사용자 요청: "전투씬이 뭔가 너무 단순하고, 그냥 육성만 되면 깨지는 수준이라 성취감이 없는데.... 뭔가 배치+전략 7 : 육성 3
  스타일의 전투로 바꿀 수 있겠냐?"
- 전장:
  - 3레인 × 6열 격자(`battle/model/battle_grid.gd`)로 바꿨다. 0~2열은 아군, 3~5열은 적 구역이다.
  - 사거리: 근접은 칸 걸음 수, 원거리는 열 차이로 센다.
  - 위치 보정: 엄폐, 수호 옆, 측후면 근접, 포격 후열 등. 규칙 전체는 `docs/COMBAT_SPEC.md`에 있다.
- 배치 단계:
  - 전투가 첫 틱 전에 멈춘 채 시작한다. "작전 배치" 창이 웨이브별 적 구성과 조언을 보여 준다.
  - 동료를 누르고 칸을 누르면 옮기거나 자리를 바꾼다. "기본 배치"로 되돌리고 "전투 개시"로 시작한다.
  - 배치는 편성·릴레이 분대별로 `profile.formations`에 저장된다.
- 전투 중 조작:
  - 동료를 누르면 시계가 멈추고 칸을 눌러 이동한다. 적을 누르면 집중 공격 대상이 된다.
  - 대상 지정 궁극기는 적을 눌러 발동하고, 같은 버튼을 다시 누르면 추천 대상에게 발동한다.
  - 배치 중이거나 동료를 고른 동안에는 궁극기 버튼이 아래 레인 칸 입력을 통과시킨다.
- 적 압박 (1장 일반 1~3 작전은 튜토리얼이라 제외):
  - 정예 강타: 정예가 9초마다 아군 구역에 1.8초 예고 공격(LANE/PLUS, 최대 HP 14%)을 한다.
  - 돌파: 돌진형은 막히지 않은 레인으로 돌파해 후열을 노린다.
  - 역할 스킬: 모든 전투에서 켜진다. 광역·포격형의 비율 피해를 올렸다.
  - 경고 문구("경고 · 정예 강타 N초")는 피해 숫자 위에 그린다.
- 성장 보정: 전투 시작 때 능력치를 권장 기준 × (실제/기준)^0.5, 레벨을 권장 + 차이 × 0.5로 보정한다.
  과성장은 도움이 되지만 배치와 대응을 대신하지 못한다.
- 밸런스:
  - `tools/campaign_balance_calibrator.gd`를 다시 썼다. 권장 프로필 파티가 `TacticalPolicy`(회피·집중·AUTO 궁극기)로,
    대응 배치와 기본 배치 중 나은 쪽을 써서 목표 승률에 맞춘다.
  - 500개 스테이지를 여유 없이 보정했다. 다른 시드 검증에서 목표보다 15%p 넘게 낮은 40개는 5~8% 완화했다.
  - 결과(16회 × 500): 전술 94% / 기본 배치(대응 없음) 48%, 장 마지막 작전 87% / 30%.
    1~6장은 10레벨 과성장으로 기본 배치 승률이 오른다. 7장부터는 권장 레벨이 이미 100이다.
  - 기록: `reports/tactics_r14_20260928/TACTICS_REPORT.md`
- 검증:
  - 헤드리스 회귀 32개 장면 통과: 전술 규칙 81/81, 조우 전투 146/146, test_runner 308/308, r15 54/54,
    성장 경제 9/9, 맵 358/358, 스토리 UI 25/25, 플레이어 피드백 23/23.
  - 정적 검사 71/71.
  - r15 신규 진행은 패배 시 다른 배치로 재도전(최대 3회)하도록 바꿨다. 1장 완주, 재도전 2회.
- 빌드: `builds/web_tactics_r14_release`(PCK SHA-256 `e7b886102fd5981e170572c12b279fb8c4d0e1e63b60e19d0e0d54f0da68239f`).
  - 브라우저(QA 샌드박스 저장)에서 배치 → 이동 → 돌파 → 승리 → 저장된 배치 재등장 → 기본 배치 복귀를 확인했다.
  - 로컬 실행기를 r14로 바꿨다(`http://127.0.0.1:8770/play/e7b886102fd5/`).
  - 빌드는 r14(현재)와 r13(직전 검증본)만 남겼다. r12는 해시 기록 뒤 휴지통으로 보냈다. 음원·영상은 원본과 같아서
    따로 복사하지 않았다. 기록: `reports/tactics_r14_20260928/retired_files.jsonl.gz`
- 배포·푸시는 하지 않았다.

## 2026-09-28 — 로컬 정리: 사운드와 연결된 음성만 남김 (Claude)

- 사용자 요청:
  - "커밋하고 필요없는 것들을 다 지워라. 사운드관련 자산만 남기는데, 시나리오 음성의 경우에는 연결된 것만 남기고 폐기본은 삭제한다."
  - "qa 관련 삭제 자산들도 한군데 이동시켜 모아놔라 내가 삭제하겠다"
- 휴지통으로 보낸 것 (8,877개 파일, 5.4GB, 모든 파일의 해시는 `reports/cleanup_20260928/retired_files.jsonl.gz`):
  - 직전 빌드 r13
  - 옛 빌드·배포 격리본, 음성 r11 런타임, `retained_archive_20260911`
  - 옛 배포 스테이징(`work/sites_*` 인덱스·업로드 묶음·SFX 핫픽스·minimal zip)
  - 미선택 음성 테이크·오디션·프로브, `reports/`의 추적되지 않는 QA 캡처·로그
- 사운드 320개와 `intro.mp4` 사본은 모두 보존본과 같아서 새로 옮긴 것이 없다.
- 시나리오 음성은 연결된 것만 남았다: 런타임 2,857개, `selection.json`이 가리키는 원본 테이크 2,857개.
- QA 삭제 대상 2,434개(386MB)는 삭제하지 않고 `DELETE_CANDIDATES/qa_20260928/`에 모았다. 사용자가 직접 지운다.
  - 프로젝트 안: `godot/.runtime_profile`, `.qa_logs`, `godot/assets/art/qa`, `godot/assets/placeholders_legacy`,
    `__pycache__`, 일회성 프로브 `godot/tools/tactical_balance_probe.*`
  - 프로젝트 밖: Godot `app_userdata`의 이 게임 테스트 데이터, Claude 세션 임시 파일
  - 목록: `reports/cleanup_20260928/qa_gathered_files.jsonl.gz`
- 확인: 옮긴 뒤 격리한 사용자 데이터로 test_runner 308/308, 전술 규칙 81/81 통과.
- 옛 git 커밋 데이터 ("너도 오래된 git 커밋 파일도 지워라"):
  - 9월 11일 gc가 남긴 cruft pack(3.56GB)을 휴지통으로 보냈다. 2026-09-05 R7 사전 빌드 배포 커밋 4개와 그 빌드 파일로,
    어디에서도 가리키지 않는 데이터였다.
  - 기록 재작성·강제 푸시는 하지 않았다. `git fsck --connectivity-only` 통과, `.git` 5.5GB → 2.1GB.
  - 기록: `reports/cleanup_20260928/git_cruft_pack_retired.txt.gz`
- `AGENTS.md`의 로컬 저장 규칙을 이번 요청으로 갱신했다. 기록: `reports/cleanup_20260928/CLEANUP_REPORT.md`
- 배포·푸시는 하지 않았다.

## 2026-09-30 — 전투·이벤트 연출 1단계 (Claude)

- 사용자 요청: "전투 규모: 5명 배치 전투를 유지하고 규모감만 so. 장식톤은 절충안으로 하고, 컷인은 "짧게"(첫사용만 길게)
  해서 1단계부터 진행해"
  - 방향 문서: `reports/visual_direction_20260930/VISUAL_DIRECTION.md`. 참고 영상 프레임은 로컬 비교용으로만 두고 올리지 않았다.
- 전투 규칙·밸런스·5명 배치는 그대로다. 모두 화면 연출 변경이다.
- 장식: 청록 신호 테마 + 금색 테두리·청록 발광선 금속 레일 프레임(절충안). 문양은 `godot/ui/ornament_draw.gd`에서 코드로 그린다.
- 전투(`battle/view/battle_view.gd`):
  - "작전 개시!" 시작 띠. 배치를 마친 뒤 0.9초 동안 띠가 먼저 보이고 첫 틱이 돈다(틱 순서는 같다).
  - 일반 승리 뒤 1.45초 "결착 / 작전 완료" 카드. 보스 승리는 기존 연출에 같은 카드를 쓴다.
  - 기술 명판: 아군 [역할] + 기술명(원형 표식 포함), 적 가시 말풍선. 최대 2개, 필살기·보스 우선.
  - 예고 장판: 바깥→안으로 차오름, 테두리 발광, 바닥 카운트다운, 착탄 섬광, 보스 광역 문양 고리.
    경고 명판은 "경고 · 기술명"만 쓰고 남은 초는 바닥 숫자로 옮겼다(r14 기록의 "경고 · 정예 강타 N초"에서 바뀜).
  - BOSS ENCOUNTER 전폭 적색 띠(전투 안, 지도 보스 접촉 카드 공통).
  - "N연속" 표시(아군 적중 3회부터, 2초 창, 표시 전용).
- 필살기 컷인:
  - 스탠딩 아트 + 캐릭터 색 집중선 + 기술명·이름 띠. 기본 "짧게"는 기존 2.10초 타임라인 그대로다.
  - 캐릭터마다 첫 사용만 길게: 1.05초 앞부분(배우·시뮬레이션 정지), 흰 섬광, 더 큰 띠와 보조 띠. 착탄이 그만큼 뒤로 밀린다.
  - 설정 "필살기 컷인: 짧게 (첫 사용만 길게) / 전체 / 끄기". 첫 사용 기록은 `profile.settings.battle_cutin_seen`.
- 스토리·이벤트·결과(`screens/app_shell.gd`, `ui/ornate_title_card.gd`, `ui/result_stamp.gd`, `ui/ornate_frame_overlay.gd`):
  - 장 도입 스토리를 처음 시작할 때 장 타이틀 카드(탭으로 넘김, 이어 보기에는 없음).
  - 동료·특수 적 이벤트 대화 전 EVENT 카드(1.1초).
  - 승리 결과에 "완수"/"승인" 도장, MVP 초상 문양 프레임.
- test_runner의 "skill cues remain circular" 검사에 맞춰 명판 앞에 원형 표식을 남겼다.
- 검증:
  - 새 테스트 `res://tests/battle_presentation_phase1_runner.tscn` 52/52.
  - 헤드리스 회귀 30개 장면 통과: test_runner 308/308, 전술 규칙 81/81, 조우 전투 146/146, r15 54/54, 맵 358/358,
    스토리 UI 25/25, 플레이어 피드백 23/23, 조우 매트릭스 8281/8281, 캠페인 스토리 946/946.
  - 정적 검사 71/71.
  - 캡처 도구 `res://tools/capture_presentation_phase1_qa.tscn`(창 필요)로 1600×900, 390×844 실제 셸 캡처.
    기록·캡처: `reports/visual_phase1_20260930/PHASE1_REPORT.md`
- 빌드: `builds/web_visual_r15_release`(PCK SHA-256 `a2ebffb1443a9a3b1b33c78ec426ba19c36c741809138b3ee4084d87678734c7`).
  - 로컬 실행기를 r15로 바꿨다(`http://127.0.0.1:8770/play/a2ebffb1443a/`). r14는 직전 검증본으로 남겼다.
  - 인앱 브라우저(QA 샌드박스 저장 `?qa=visual-r15`): 타이틀 → 설정의 "필살기 컷인" 항목 → 프롤로그(장 카드 없음) → 본부 →
    1장 타이틀 카드 → 스토리 첫 대사까지 확인했다. 그 뒤 지도 로딩은 브라우저 창이 숨겨져 캔버스 크기가 0이 되면서
    시간 초과로 멈췄다(WebGL "Attachment has zero size"). 전투 연출은 데스크톱 실제 셸 캡처로 확인했다.
- 배포·푸시는 하지 않았다. 규모감(다음 웨이브 실루엣, 무리 유닛)은 2단계다.

## 2026-09-30 — 지도 외형 2단계 + 전투 규모감 (Claude)

- 사용자 요청: "2단계 진행해"
  - 방향 문서 `reports/visual_direction_20260930/VISUAL_DIRECTION.md`의 2단계(A1 재질, A3 원경, A5 UI 정리, A6 표식,
    B1·B2 이동 동작, B4 조우 전환)와 1단계에서 넘긴 D7 규모감을 했다.
- 지도 규칙·이동력·시야·적 턴·전투 계산은 그대로다. 모두 화면 연출 변경이다.
- 지도(`chapter_map/runtime/chapter_map_screen.gd` 외):
  - A1: `terrain_surface.gdshader`를 다시 썼다. 상면 이끼·눈·모래 얼룩(바닥색 칸에만), 칸 가장자리 마모와 홈,
    절벽 지층 띠, 턱 밑 이끼 띠, 아래로 갈수록 어두워짐. 색은 생물군계 8종별 `RegionPalette.surface_look()`.
    계단식 높이 계산과 지형 데이터는 건드리지 않았다.
  - A3: 가장자리 틸트시프트 흐림과 위쪽 대기색(`map_atmosphere.gdshader`, 안개 오버레이 앞),
    물 셰이더에 섬 밖으로 갈수록 깊어지는 바다색과 해안 물빛.
  - A5: 데스크톱은 행동 버튼을 화면 아래 막대로 옮기고 부제를 숨겼다(세로·좁은 화면은 기존 상단 배치).
    안내 문구는 짧은 알림(토스트)으로, 상태 줄의 "탐험 N%"는 "탐사율" 원형 게이지로 옮겼다. 미니맵 접기 버튼.
  - A6: 보스 해골, 정예 별, 사건 "!", 보물 상자 표식이 칸 위에 떠서 맥박처럼 깜빡인다(`map_presentation_overlay.gd`).
  - B1: 한 칸 이동마다 포물선 도약(높이차가 있으면 더 높이), 착지 먼지.
  - B2: 경로를 빛나는 행진 점선 + 화살촉 + "N칸"(이번 턴에 못 가는 칸은 회색, "N칸 / M")으로, 이동 범위 테두리에
    도는 빛을 더했다. 기존 3D 경로 리본은 반투명 가이드로 낮췄다.
  - B4: 일반 조우는 카메라가 접촉 칸으로 밀고 들어간 뒤 속도선 와이프와 적 정보 패널(웨이브별 적 이름·수, 권장 Lv, 부대 평균 Lv)이
    옆에서 들어오고 전투 로딩으로 간다(1.35초, 패널이 뜬 뒤 탭하면 넘김). 보스는 기존 BOSS 띠, 이벤트·전환 줄이기 설정은 기존 경로.
- 전투 D7(`battle/view/battle_view.gd`):
  - 일반 등급 적은 3체 "무리"로 그린다. 표시 체력 2/3, 1/3 아래로 내려갈 때마다 한 체가 쓰러지며 빠진다.
    체력 바에 3등분 눈금과 "×N". 시뮬레이션 유닛·체력 계산은 그대로다.
  - 다음 웨이브를 적 구역 뒤에 붉은 테두리 실루엣과 "NEXT WAVE ×N"으로 대기시킨다(보스 등장·마지막 웨이브에는 없음).
- 검증:
  - 새 테스트 `res://tests/battle_presentation_phase2_runner.tscn` 19/19, `res://tests/map_presentation_phase2_runner.tscn` 32/32.
  - 헤드리스 회귀 32개 장면 통과: test_runner 308/308, 1단계 52/52, 맵 358/358, 전술 81/81, 조우 전투 146/146, r15 54/54,
    필드 탐색 342/342, 지역 로딩 197/197, 조우 매트릭스 8281/8281, 캠페인 스토리 946/946 외.
  - 정적 검사 71/71.
  - 캡처 도구 `res://tools/capture_presentation_phase2_qa.tscn`(창 필요, battle/map)로 1600×900, 390×844 실제 셸 캡처.
    호환 렌더러로도 지도 셰이더 컴파일과 모양을 확인했다. 기록·캡처: `reports/visual_phase2_20260930/PHASE2_REPORT.md`
- 빌드: `builds/web_visual_r16_release` (PCK SHA-256 `9e763b950e0256d793058915e3aab42e7b966cf4a9cda8ba7d5090e48d22917a`)를 후보로 만들고
  로컬 실행기(`tools/powershell/START_LOCAL_GAME.ps1`)를 r16으로 바꿨다. r15는 현재 검증본으로 남겼다.
  - r14는 해시(파일 3,593개)를 `reports/visual_phase2_20260930/r14_retirement_manifest.json`에 적고 휴지통으로 보냈다.
  - 인앱 브라우저에서 1장 지도까지 갔고, 모바일 가로 844×390에서 웹 지도(셰이더, 점선 경로, 표식, 게이지)를 확인했다.
    첫 지도 진입은 패널이 숨겨진 상태(프레임 제한)에서 무진행 12초 제한에 걸렸고 RETRY는 2.4초에 열렸다. 1단계의 r15와 같은 증상이다.
    보이는 브라우저에서 첫 진입 시간을 재는 일이 남았다.
- 하지 않은 것: 달리기 동작·좌우 뒤집기·발소리(B1), 원경 실루엣과 거리 안개(A3), 높이차 확대·바위 기둥(A1, 지형 데이터 변경),
  상단 재화·전력 표시(A5). 조우 패널 제목은 기존 스테이지 이름("제1장 NORMAL 1")을 그대로 쓴다.
- 배포·푸시는 하지 않았다.

## 2026-09-30 — 로딩 문제 수정 + 필드 연출 시스템 3단계 (Claude)

- 사용자 요청: "로딩 문제 해결하고 3단계 진행해라."
  - 방향 문서 `reports/visual_direction_20260930/VISUAL_DIRECTION.md`의 3단계(C3 필드 연출 시스템)를 했다.
  - 지도 규칙·전투 계산·보상·저장은 그대로다. 모두 화면 연출이다.
- 로딩(웹 첫 지도 진입 "TACTICAL MAP UNAVAILABLE"):
  - 원인 셋: 벽시계로 재는 12초 무진행 감시(그려지지 않는 동안에도 흐름), 프레임마다 고정 10ms 작업 조각,
    진행 표시가 6곳뿐이라 그 사이(세계 구성 타일 스캔이 호출마다 프레임 하나씩 씀)가 초당 2~4프레임에서 12초를 넘김.
  - `core/loading_clock.gd`(새 파일): 전달된 프레임당 최대 250ms만 센다. 작업 조각은 프레임 간격의 절반(20~250ms).
    맵 빌더, `StageAssetCache` 웜업, `app_shell`의 지도·전투 감시가 같이 쓴다.
  - `chapter_map_screen.gd` `_finish_web_build_slice`: 조각 예산 건너뛰기를 `map_ready`까지 전체에 적용하고,
    프레임을 넘긴 조각이 마지막 진행 지점을 다시 알려 무진행 시계를 되돌린다. 전체 45초 제한은 남는다.
  - 대기 셰이더를 부팅 웜업에 넣었다(`web_soak_probe.gd`).
  - 실제 브라우저(Chrome headless + CDP, 새 프로필) 첫 진입: r16 CPU ×16 TIMEOUT 45.1초 →
    r19 제한 없음 2.15초(r16 약 4.2초), CPU ×16 완료 36.9초, 프레임 2/초 완료 25.0초, 4/초 완료 13.4초.
    중간 r17은 2/초와 4/초에서, r18은 2/초와 4/초에서 여전히 TIMEOUT이라 세계 구성 구간까지 넓힌 것이 r19다.
    프레임 1/초는 구동기 클릭 타이밍이 맞지 않아 재지 못했다.
- 필드 연출(`godot/field/`, 새 폴더):
  - 스크립트 형식(`field_script.gd`): 명령 `say`(말풍선, 아군 청록·적 빨강·이벤트 금색), `move`, `face`, `jump`,
    `emote`(!, ?, 땀, 분노, 섬광), `camera`(focus/zoom/shake), `banner`, `sfx`, `wait`. `"with": true`는 앞 명령과 같이 시작.
    배역 `leader/ally/foe/boss/event/center`. 기존 쪽지(`pre_battle_dialogue`, `event_encounters`)를 장면으로 바꾸는 변환 포함.
  - 실행기 `field_scene.gd`(시간 구동, 탭·건너뛰기), 화면 `field_scene_overlay.gd`(타자 효과 말풍선, 감정 표시, 배너, 레터박스),
    호스트 어댑터 `field_stage.gd`(인터페이스) · `map_field_stage.gd` · `battle_field_stage.gd`.
  - 라이브러리 `data/field_scenes/field_scenes.json`: 장면 25개(보스 후일담 23 + 기본 1 + 데모 1), ko/en 문구.
  - 쓰는 곳: 지도 이벤트 접촉, 보스 대치(밀어붙임 zoom 1.35 / 1.45, 타격음), 보스 격파 후 결과 카드 전 짧은 후일담
    (보스 마지막 말 + 아군 답, 23개 보스 전투). 긴 대화와 감정 장면은 비주얼 노벨 화면 그대로.
    "전환 줄이기" 설정, 건너뛰기 진행 중, 적 폰 없음일 때는 기존 읽기 패널로 돌아가거나 후일담을 건너뛴다.
  - 호스트: `chapter_map_screen.gd`에 `field_*` 훅(폰·적 폰 위치·도약·좌우, 카메라 포커스·줌·흔들림), `battle_view.gd`에
    후일담 재생·대기와 유닛 위치·도약·카메라 훅, `app_shell.gd`에 `_play_field_contact`(이벤트·보스 접촉이 필드 장면을 먼저
    시도). `battle_view.field_aftermath_enabled` 기본 false(테스트·도구는 탭을 기다리지 않음), 호스트만 켠다.
  - 캡처로 찾아 고친 것: 한국어 단어 중간 줄바꿈, 지도 HUD 겹침(베일 색조, 이름표 숨김), 약한 밀어붙임.
- 검증:
  - 새 테스트 `res://tests/field_direction_runner.tscn` 115/115, `res://tests/loading_pacing_runner.tscn` 34/34.
  - 헤드리스 회귀 34개 장면 모두 통과(test_runner 308/308, 맵 358/358, 전술 81/81, r15 54/54, 필드 탐색 342/342, 지역 로딩 197/197,
    조우 매트릭스 8281/8281, 캠페인 스토리 946/946 외). 마지막 수정 뒤 맵·지역 로딩·필드·맵 2단계·로딩을 다시 돌렸다. 정적 검사 71/71.
  - 캡처 도구 `res://tools/capture_presentation_phase3_qa.tscn`(창 필요, `map event|boss` / `battle`)으로 1600×900, 390×844 실제 셸
    캡처. 기록·캡처: `reports/visual_phase3_20260930/PHASE3_REPORT.md`
- 빌드: `builds/web_visual_r19_release` (PCK SHA-256 `816f0b8260b5f27b816f3400e53d1796fa33f92a82ecb0d1a5a74904785abd39`)를 후보로
  만들고 로컬 실행기를 r19로 바꿨다. r15는 현재 검증본으로 남겼다.
  - r16·r17·r18과 r17·r18·r19 development 내보내기는 해시를 `reports/visual_phase3_20260930/*_retirement_manifest.json.gz`에
    적고 휴지통으로 보냈다. 일회용 Chrome 프로필 17개도 휴지통으로 보냈다.
- 하지 않은 것 / 못 한 것: 필드 장면은 웹 빌드에서 돌려 보지 못했다(창 있는 셸 캡처와 헤드리스 테스트로만 확인),
  프레임 1/초 첫 진입, 전투 진입의 느린 프레임 측정, 일반 전투 후일담, 장면 편집 도구.
- 배포·푸시는 하지 않았다.

## 2026-09-30 — 확장 4단계: 랜드마크·원근 카메라·전투 바닥·타격 효과 (Claude)

- 사용자 요청: "4단계 진행해."
  - 방향 문서 `reports/visual_direction_20260930/VISUAL_DIRECTION.md`의 4단계(A2, A4, D1, D6, D7)를 했다. D7은 2단계에서 끝났다.
  - 지도 규칙·전투 계산·난수·보상·저장은 그대로다. 모두 화면 연출이다.
- A2 랜드마크(`chapter_map/view/landmark_builder.gd`, 새 파일):
  - 코드로 만든 메시(새 에셋 파일·가져오기 없음). (종류, 지역 계열, 변형)마다 `ArrayMesh` 하나를 캐시하고, 꼭짓점 색에 빛을 구워 넣었다.
    창·불빛은 따로 빛나는 층, 깃발과 연기 덩어리는 움직이는 자식 노드다.
  - 작은 건물 7종(전진 기지, 바리케이드, 천막, 신호탑, 보급 상자, 폐허 아치, 신호 불꽃), 보스 건물 13종 원형에서 챕터별 20쌍.
    삼각형 예산 작은 것 420 이하(최대 308), 보스 1500 이하(최대 1400).
  - `chapter_map_screen.gd`: 시작 거점→전진 기지, 일반 적→바리케이드, 정예→천막, 보스→챕터 건물+받침, 중계소→신호탑, 보물→상자.
    웹은 예열된 지형 재질을 그대로 쓰고(셰이더 추가 없음), 건물 움직임은 한 프레임 걸러 갱신, 먼 건물은 갱신하지 않는다.
  - 웹 전용 나중 채우기: 진입 중에는 건물의 빈 뿌리(`create_root`)만 놓고, 메시 생성과 자식 노드(`populate`)는 지도가 열린 뒤
    프레임마다 최대 5ms씩 카메라에 가까운 것부터 채운다(`_drain_landmark_fill_queue`). 네이티브는 예전처럼 바로 채운다.
    보스 건물 크기 맞춤은 채울 때 한다(`fit_height`).
- A4 카메라(`chapter_map/view/map_camera_rig.gd`, 새 파일):
  - 약 48도 기울인 원근 카메라(렌즈 38도). 궤도 중심에서 화면 배율이 예전 직교와 같아 기존 화면 계산이 그대로 맞다.
    확대·축소는 카메라를 앞뒤로 움직인다. 선택은 광선 방식이라 그대로 정확하다.
  - 칸 초점 연출 4종(보물 1.00초, 중계소 1.25초, 사건 0.85초, 충격 0.60초): 밀고 들어가기, 살짝 돌기, 흔들기.
    이동 중, 필드 장면 중, "전환 줄이기"에서는 재생하지 않는다.
  - 설정 `map_camera_perspective`(기본 켜짐). 끄면 예전 직교 카메라. 설정 화면 스위치는 아직 없다.
- D1 전투 바닥(`battle/view/battle_region_floor.gd`, 새 파일): 지역 계열 8개, 바닥 문양 10개, 세 겹(먼 안개·입자, 격자 투영 바닥판과 문양, 앞 소품과 비네트).
  새 텍스처 없음.
- D6 타격감(`battle/view/combat_hit_feedback.gd`, 새 파일, `combat_weapon_effects.gd` 등 수정):
  - 피해 숫자 7형(일반·치명·약점·저항·빗나감·회복·보호막), 2프레임 흰색 번쩍임, 피해량 비례 흔들림 프리셋 4개(tap·thud·snap·quake)와 넉백.
  - 공격별 효과: 참격 잔상 궤적, 총구 화염과 예광탄, 폭발(불덩이·연기·그을음·파편), 마법 육망성, 보호막 고리, 치명·약점 덧표시.
- 검증:
  - 새 테스트 landmark_builder 1547/1547, landmark_map 46/46(웹 방식의 나중 채우기 포함), map_camera 72/72, battle_region_floor 105/105, hit_feedback 61/61.
  - 헤드리스 회귀 `tests/*.tscn` 37개 장면 모두 종료 코드 0·실패 0(조우 매트릭스 8281/8281, r15 54/54, 캠페인 스토리 946/946, test_runner 308/308),
    `chapter_map/tests` 지도 358/358·환경 효과 26/26, 정적 검사 71/71. 새 엔진 오류 없음
    (`field_direction_runner`의 헤드리스 글꼴 "p_size <= 0" 1건은 3단계부터 있던 것, 테스트 자체는 115/115).
    나중 채우기를 넣은 뒤 전체를 다시 돌렸다.
  - 캡처 도구 `res://tools/capture_presentation_phase4_qa.tscn`(창 필요)로 1600×900, 390×844 실제 셸 캡처.
    기록·캡처: `reports/visual_phase4_20260930/PHASE4_REPORT.md`
- 빌드: `builds/web_visual_r21_release` (PCK SHA-256 `504baf5218247f1cb6cd93c1002d3af85e70ae84de1a3962cb5cc9bf89074535`, 176,855,796바이트,
  r19보다 72,552바이트 큼)를 후보로 만들고 로컬 실행기를 r21로 바꿨다. r15는 검증본으로 남겼다. r20은 나중 채우기 전의 첫 후보였다.
  - 실제 Chrome(새 프로필): 지도 첫 진입(제한 없음)을 r19·r20·r21 번갈아 8번씩 쟀다. 기계 부하 때문에 같은 빌드도 2.3~3.0초로 흔들린다.
    평균 r19 2597ms, r20 2704ms, r21 2706ms(표준편차 약 250ms). 차이는 +4% 안팎으로 잡음보다 작아 늘었다/안 늘었다를 확실히 말할 수 없다.
    처음 4번의 r20 +175ms는 부하가 바뀐 뒤 사라졌다. 목표 5000ms 안.
  - CPU ×16: r19 57.6, 56.1, 64.5초 / r20 57.3, 72.6초 / r21 52.2초. 프레임 2/초: r19 25.0초(3단계), r20 25.0초, r21 25.1초.
    4/초: 13.4초(3단계), 13.7초, 13.6초. 모두 완료, TIMEOUT 없음. 데스크톱 60.3fps(가장 긴 프레임 20ms), 지도 진입 직후 3.5초에도 33ms 넘는 프레임 없음.
  - r20 빌드 직후 HD 이미지 한 장(`_hd/map_density/r1/CHR026/atlas.png`)의 한 바이트가 바뀌어 있어 로컬 실행기 검증이 잡았다
    (크기·수정 시각 동일, 빌드 직후 검증은 통과, 원본·PCK·오디오는 해시 정상). r20 릴리스 쪽 그 파일만 원본에서 다시 복사해 656쪽을 다시 검증했다.
    저장 장치나 메모리 문제의 징후일 수 있다. r21 빌드에서는 없었다.
  - r19 release, r20 release·development, r21 development 내보내기 4개는 경로·해시 목록을 `reports/visual_phase4_20260930/*_retirement_manifest.json.gz`에 적고 휴지통으로 보냈다(r15 검증본과 r21 후보만 남김). 일회용 Chrome 프로필 49개도 휴지통으로 보냈다.
- 하지 않은 것 / 못 한 것: 첫 진입 시간의 작은 차이(+4%)를 잡음에서 가려내는 측정, 충격·중계소·사건·보물 카메라 순간의 창 캡처(테스트만),
  보스 건물의 안개·적 스프라이트 가림 보정, 어려움 보스 전용 건물, 실제 휴대폰 브라우저 확인, 설정 화면의 카메라 스위치.
- 배포·푸시는 하지 않았다.

## 2026-10-01 — 로컬 용량 정리, 배포 요청 (Claude)

- 사용자 요청 1: "네가 배포해라." → 하지 못했다. 사이트는 ChatGPT Sites(`lanternline-r7.comicman081.chatgpt.site`, 현재 r10)이고,
  올리는 데 필요한 Sites 연결 호출(쓰기 자격 증명 발급, 버전 저장, 배포)은 Codex 쪽 도구뿐이다. Sites git 주소에는 저장된 로그인 정보가 없고,
  Codex 인증 파일은 쓰지 않았다. `.deploy/REQUEST`와 GitHub는 건드리지 않았다. 올릴 후보는 r21(`builds/web_visual_r21_release`,
  PCK SHA-256 `504baf52…4535`)이고 마지막 배포 단계는 Codex가 해야 한다.
- 사용자 요청 2: "필요없는것들 사운드, 인트로동영상 자산들 제외하고 지워라."
  - `Games` 폴더 146.6GB 중 이 프로젝트는 약 16.0GB다. 다른 게임 폴더는 건드리지 않았다.
  - QA 런타임 프로필 7개와 이전 단계 QA 캡처 73개(101개 파일, 216.8MB)를 경로·해시를 `reports/storage_cleanup_20261001/retired_files.jsonl.gz`에 적고 휴지통으로 보냈다.
    스크래치 폴더(C 드라이브)의 테스트 출력 약 600MB도 같다. 기록: `reports/storage_cleanup_20261001/COMPLETION.md`.
  - 사운드(3.9GB 격리 음원 마스터, 음성, 오디오 원본), 인트로 영상, r15·r21 빌드, Codex 작업물, 게임 자산은 남겼다.
- 배포·푸시는 하지 않았다.


## 2026-10-01 — r22: 지도 높이 표시 수정, 타이틀 라이브 2D, 전투 웹 프레임 (Claude)

- 요청: "r21로 배포했다. 개선·추가·버그 수정할 게 있는지 확인하고 r22로 업데이트", "고저차 맵에서 이동 가능 영역 노란 박스 높이가 안 맞는 것도 수정", 시안 영상(`title_live2d_preview.mp4`)을 보고 "타이틀 화면에 이런 수준의 라이브 2D 적용".
- 지도: 이동 범위·경로·격자를 월드 좌표 칸으로 두고 GPU가 지도 카메라로 투영한다(`world_cell_overlay.gd/.gdshader`).
  이전에는 CPU가 한 번 투영한 Control을 통째로 밀어서, 원근 카메라에서 고저차가 있는 칸 위로 미끄러졌다(격자는 최대 약 40px).
  투영 189건이 `Camera3D.unproject_position()`과 일치, 지도 테스트 358/358, 웹 캡처에서 칸마다 자기 윗면 높이에 붙는 것을 확인했다.
- 타이틀: 인물 일러스트를 픽셀 단위로 휘게 하는 셰이더 퍼핏(`ui/title_live2d.gd`, `title_puppet.gdshader`, 자산 `assets/title_live2d/`).
  머리카락·옷 흔들림, 랜턴 진자, 숨·눈 깜박임·시선, 심장박동, 입장 연출. 프레임 시간으로 품질 단계를 자동 조절하고 자산이 없으면 정지 타이틀로 돌아간다.
  웹 예열에 `타이틀 연출` 조각을 넣었다. 시안 영상: `reports/visual_r22_20261001/title_live2d_r22_preview.mp4`.
- 전투 웹 프레임: 프레임마다 GPU 버퍼를 만들던 도형 명령을 정적 메시·캐시 텍스처로 바꿨다(`battle_mesh_kit.gd`, `battle_soft_sprites.gd`, `battle_region_floor.gd`).
  같은 PC에서 r21 20~22fps → r22 41~42fps(CPU 4배 느림 5~6 → 10~11fps). 프레임당 폴리곤 명령 약 130개가 남았다.
- 버그 9건: 피해 숫자 접두어(측면·엄폐·직격) 한글 폴백, `▸`·`▾` 글리프 교체, 오른쪽 클릭·휠이 연출을 건너뜀, 보스 후일담이 탭을 못 받음,
  전투 뒤 지도 카메라 연출 잔재, 다음 웨이브 표식 글씨 하한, 유닛 이름 외곽선, MISS 숫자 정리, 랜드마크 연기 덩어리.
- 빌드: `builds/web_visual_r22_release`, PCK `r7_current_13455ea5e24b.pck` 177,065,872바이트(SHA-256 `13455ea5…7731`), r21보다 +210,076바이트.
  Sites 압축 해제 한도(268,435,456바이트)의 여유가 r21 배포 기준 854,016바이트뿐인데 처음 만든 r22는 +2,737,900바이트였다.
  그래서 코드가 참조하지 않는 옛 타이틀 이미지 2장(`title_cast_plate_r1.png`, `title_cast_plate_portrait_r1.png`, PCK 안 2,526,818바이트)을
  `quarantine/title_cast_plate_superseded_20261001/`로 옮기고(삭제 아님, 해시 기록) 다시 빌드했다. 새 여유는 약 0.64MB로 추정한다. 실제 값은 Codex 도구로 확인해야 한다.
- 검증: 헤드리스 40개 장면 전부 통과, 정적 71/71, 새 Chrome 프로필에서 부팅 → 타이틀 → 지도 → 전투 오류 없음.
- 인계(Codex): `godot/screens/command_presentation.gd`의 타이틀 연결 부분(`TitleLive2D` preload와 `live_cast` 분기)은 Codex의 미커밋 `title_backdrop` 재작성 안에 있어 커밋하지 않았다. Codex가 타이틀 변경과 같이 커밋해야 한다.
  `tools/powershell/START_LOCAL_GAME.ps1`은 이제 r22를 가리킨다. 자세한 내용: `reports/visual_r22_20261001/R22_REPORT.md`.
- 하지 않은 것 / 못 한 것: 실제 휴대폰 확인, NVIDIA+ANGLE 외 GPU 확인, 전투 폴리곤 명령 약 130개 정리.
- 배포·푸시는 하지 않았다.


## 2026-10-01 — r22 GitHub Pages 배포 (Claude)

- 요청: "깃허브에 루멘바운드 배포 주소 있으니 pages 찌꺼기 남겨서 용량 차지 않하게 하고 깃허브 액션 최소화해서 배포해", 이어서 "배포하고나서는 pages 에 찌꺼기 남기지 말고 다 지워라".
  이 요청에 한해 "배포는 하지 말아" 제한을 풀었다. 배포 주소: `https://comicman081-collab.github.io/LUMENBOUND-TACTICS-OF-THE-LAST-LINE/` (저장소 `comicman081-collab/LUMENBOUND-TACTICS-OF-THE-LAST-LINE`).
- 만든 것: `tools/web/stage_pages_release.py`. 검증된 r22 릴리스를 Pages 트리로 만든다(해시 이름 PCK/WASM, 오디오 사이드카, 검증된 인트로 `intro.mp4`, 하위 경로용 인트로 경로 보정,
  영어 로딩 문구, 정리한 LICENSES/README, 파일별 해시표가 든 VERSION.json). 선택 HD 페이지 `_hd/`는 제외했다(Sites r21과 같이 PCK 안 압축 텍스처로 대체).
  PCK 177,065,872바이트는 Git LFS 없이 49MB 이하 4조각으로 임시 브랜치 `deploy-payload`에 올렸다. 처음에는 LFS 무료 한도가 1GiB라 옛 기록(원격 약 1.14GB)으로 이미 넘었다고 판단했지만 낡은 기준이었다. 공식 문서(2026-10-02 확인)는 GitHub Free에 저장 10GiB·대역폭 10GiB를 주고 매월 다시 센다고 하며, 옛 기록은 그 약 10%다. 그래도 LFS를 쓰지 않은 이유는 PCK 버전마다 LFS 저장이 영구히 쌓이고(지우려면 저장소를 새로 만들거나 Support 요청) Actions 체크아웃마다 대역폭을 쓰기 때문이다.
- Actions는 1회만: 워크플로 변경을 `[skip actions]`로 main에 올리고(실행 0건 확인), `.deploy/REQUEST` 한 줄만 바꾼 커밋 하나로 실행을 시작했다(실행 36878970881, 47초, 성공).
  실행은 payload 브랜치를 받아 정확한 파일 집합, 모든 바이트의 해시, 서비스 워커·매니페스트·문구를 검증한 뒤에만 배포한다.
  올린 Pages 아티팩트는 `retention-days: 1`이고 배포 직후 실행이 스스로 지운다. 실행 뒤 아티팩트 0건, 캐시 0건. 새 워크플로는 main `da2d8ff`, 요청은 `b142237`.
- 검증: 배포본 파일 2,935개(VERSION.json·DEPLOY_SHA.txt 제외, 약 540MB 조회)를 VERSION.json·audio_sidecars.json의 크기·SHA-256과 전부 대조해 일치했다(`tools/web/verify_live_pages.py`, PCK `13455ea5…7731`).
  새 Chrome 프로필로 로딩 화면(영어 문구) → 타이틀 → 지도 → 전투(57fps)까지 오류 없이 지났고, 인트로 영상은 실제로 재생됐다(3.0초 → 8.7초, 오류 없음).
  콘솔·네트워크 문제는 선택 파일 `_hd/…/atlas.png`의 404 한 건뿐이며 압축 텍스처로 폴백한다(이때 엔진 gzip 오류 로그 한 줄이 같이 찍힌다).
- 정리: 임시 브랜치 `deploy-payload` 삭제(원격은 main과 기존 브랜치 두 개만 남음), 로컬 스테이징 사본·QA 프로필 약 1.7GB는 휴지통으로 보냈다. 이 브랜치는 푸시하지 않았다.
- 이 브랜치 변경: `.github/workflows/deploy-pages.yml`을 main의 새 워크플로와 맞추고 `tools/web/stage_pages_release.py`를 추가했다.
- 인계(Codex): (1) `godot/screens/app_shell.gd`의 인트로 경로가 절대 경로 `/intro.mp4`라서 하위 경로 호스트에서는 스테이저의 보정 코드가 필요하다. 소스에서 `./intro.mp4`로 바꾸면 보정이 필요 없다.
  (2) 배포본의 런타임 소스 커밋은 `2ed2b87`이지만 빌드에는 Codex의 당시 미커밋 타이틀·인트로 변경이 같이 들어 있다. `command_presentation.gd`는 아직 커밋되지 않았다.
  (3) 다음 배포는 payload 브랜치를 먼저 만든 뒤 REQUEST를 바꾸는 순서다(워크플로 머리말 참고). 브랜치가 없으면 실행이 체크아웃에서 멈춘다.
- 사용자가 직접 할 일: 이미 만들어진 실행 기록 1건 삭제(Actions → 실행 → ⋯ → Delete workflow run). Settings → Actions → General의 보관 기간 1일 설정은 사용자 승인 뒤 시도했지만 인앱 브라우저가 GitHub에 로그인돼 있지 않아 못 했다. 이 설정은 2026-10-01부터 실행 기록에도 적용되지만 새로 생기는 실행에만 적용된다. 옛 LFS 객체 약 1.14GB는 무료 허용량(10GiB)의 약 10%라 지울 필요가 없다.
