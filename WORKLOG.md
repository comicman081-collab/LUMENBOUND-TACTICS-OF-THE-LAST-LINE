# Worklog

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
