# candidate34 로컬 전투·모바일 검수

상태: 로컬 후보 검수 완료, 배포/승격 보류. GitHub Actions, push, commit,
공개 배포, 자산 삭제를 실행하지 않았다. 물리 Android/iOS 검수와 업로드 참고
영상 수준의 신규 관절 애니메이션 제작은 이 결과에 포함하지 않는다.

## 이번 구현

- 총기 역할의 기본 공격·일반 스킬·필살기를 전진 찌르기 대신 조준,
  브레이싱, 반동 중심의 역할 동작으로 분리했다.
- 공격 트랙을 끊지 않는 방향성 피격 반응과 일반 타격용 최대 55 ms의
  actor-only hitstop을 추가했다. 전투 시뮬레이션 시간은 멈추지 않는다.
- 근접 타격 구간에만 최대 두 개의 제한된 잔상을 표시한다.
- 발사체가 정적인 몸 중심이 아니라 역할·액션·방향별 무기 앵커에서
  시작하도록 변경했다.
- additive pose를 모두 합성한 뒤 최종 발 접지 보정을 적용한다.
- 전 구간 검사 도중 발견한 브라우저 터치 레이스를 게임 결함과 분리하기
  위해, 검수 도구가 `다음 조우` 입력 후 실제 이동 버튼을 기다리고 최대
  세 번 재터치하도록 보강했다.

## 통과한 검증

- Godot 일반 회귀: 290/290 PASS. GPT 웹 검토 권고에 따라 다중 피격도
  hitstop이 55 ms를 넘지 않는 조건과 알 수 없는 역할의 발사체가 화면
  원점이 아닌 결정적 actor-local 앵커를 쓰는 조건을 추가 고정했다.
- Godot 맵 회귀: 354/354 PASS.
- 단독 고해상도 자산 디코딩: 캐릭터·몹 109, 효과 436, 맵 캐릭터 109,
  failures=[] PASS.
- 실제 N20 전투 녹화: 기본 공격·일반 스킬·필살기, 양 진영 동작 진행,
  전 샘플 발 접지, 런타임/셰이더 오류 0 — 5/5 PASS.
- N20 종단 경로: 360x640, 390x844, 1280x720에서 접지와 얼굴 원형
  필살기 UI 5개 완전 노출, 보상 하단 드래그, N20→H01, suspend/resume —
  231/231 PASS.
- 홈/맵 튜토리얼과 N06/N08/N13 설명창의 세로·가로 회전, 3페이지,
  터치 스크롤, 실제 전투 진입 — 346/346 PASS.
- N01/N05/N10/N20 맵 갤러리: 연속 배경, 192 px 맵 캐릭터, 강·얕은물
  실제 더블터치 차단 — 19/19 PASS.
- N01~N20 실제 브라우저 전투 20개 스테이지/45개 웨이브를 각각
  전투→보상 하단 터치 스크롤→다음 스테이지로 순회했다. N01~N08,
  N09~N15, N16~N20의 최종 성공 실행 결과를 합치면 20/20 PASS이며
  모든 실행은 격리 QA 저장소만 사용했다.
- 각 실전 웨이브에서 109개 캐릭터·몹의 256 px 8동작과 436개 전용
  발사체/일반 스킬/필살기 FX 연결을 검사했고 로딩 실패는 0이었다.

## 실패 증거 보존

- `20260907_motion34_audit`: QA URL에 저장 격리 키가 빠진 실행.
- `20260907_route34_matrix`: N09에서 이동 버튼 생성 전 조기 판정.
- `20260907_route34_matrix_n09_n20`: N16에서 브라우저 입력 억제 프레임과
  단일 터치가 겹친 실행.
- `20260907_candidate34_density_native.log`: 프로젝트 오토로드를 올리지
  않은 잘못된 `--script` 진입 방식.
- `20260907_candidate34_density_native_pass.log`: 지원되지 않는 사용자 경로
  인수가 테스트 씬 대신 일반 메인 씬을 실행한 호출. 해당 프로세스만
  종료했고 파일은 보존했다.

위 실패 폴더와 로그는 삭제하지 않았다. 대응 검증은 별도 `*_pass` 또는
분할 성공 실행에 기록했다.

## 실행물과 주요 증거

- 로컬 개발 후보: `builds/web_gameplay_qa_20260907_candidate34_development`
- 로컬 릴리스 후보: `builds/web_gameplay_qa_20260907_candidate34_release`
- 실제 전투 녹화: `reports/gameplay_qa/20260907_motion34_audit_pass/actual_combat.webm`
- N20 종단: `reports/gameplay_qa/20260907_final34_audit/acceptance.json`
- 설명창: `reports/gameplay_qa/20260907_briefing34_audit/acceptance.json`
- 맵 화면: `reports/gameplay_qa/20260907_map34_gallery/acceptance.json`
- 전 구간 성공 조각: `20260907_route34_matrix`,
  `20260907_route34_matrix_n09_n20`, `20260907_route34_matrix_n16_n20`의
  각 `acceptance.json`과 `route_progress.json`.
- 최종 일반 회귀: `reports/gameplay_qa/20260907_motion34_native_final.log`
- 최종 맵 회귀: `reports/gameplay_qa/20260907_motion34_map_native.log`
- 최종 자산 디코딩: `reports/gameplay_qa/20260907_candidate34_density_native_scene_pass.log`

## GPT 웹 Pro 검토

- 기존 `전투 연출 설계 검토` 대화에 구현·검증·한계를 전달하고 응답
  완료까지 기다렸다. 판정은 `APPROVED`, LOCAL QA 전에 반드시 수정할
  항목과 현재 로컬 승인을 막는 근거는 없었다.
- 설명창 전용 fixture를 처음 요약할 때 N05로 잘못 적은 부분을 N06으로
  정정해 다시 확인했다. 정정 후에도 APPROVED가 유지됐다. 정확한 범위는
  N06/N08/N13 설명창 전용 검증, N05 전투→보상→N06 연결 별도 PASS다.
- 검토는 제공한 결과 구조에 대한 검토이며 웹 대화가 로컬 녹화·리포트
  파일을 직접 연 독립 픽셀 검수는 아니다.

## 남은 외부/물리 게이트

- 현재 환경에 ADB가 없어 실제 Android/iOS 발열·메모리·터치 검증은 못 했다.
- 이번 배치는 기존 고해상도 SD 원본의 역할 동작을 코드로 개선한 것이며,
  신규 스켈레탈/프레임 애니메이션으로 참고 영상과 상용급 동등성을 달성한
  것으로 판정하지 않는다.
- 전체 상용 미술 품질 승인, 공개 배포, 실패 자산 폐기는 별도 게이트다.
