# SD 원화 교체·새 게임·피해 숫자·정리 완료 — 2026-09-11

현재 게임: http://127.0.0.1:8770/play/ff8741b54bbc/

원화 73종: http://127.0.0.1:8770/art-gallery

실행기: 프로젝트 루트의 `START_LOCAL_GAME.cmd`. 현재 유지하는 실행본은 `builds/web_roster21_damage_restart_20260911_release/`이며, 로컬 서버 PID는 검사 시점 20292였다. PCK SHA-256: `ff8741b54bbc2876cab53722c428af841e5a6f98ebbc1146740f7d82ee5d146c`. 외부 배포나 GitHub Actions는 실행하지 않았다.

## 반영 사항

- 선행 배치의 누락 몹 32종·보스 20종에 이어 기존 캐릭터 CHR001–CHR008, 몹 ENM001–ENM010, 보스 BOSS001–BOSS003을 Sprite Gen의 Codex GPT 경로로 제작·교체했다. 최종 범위는 기존 캐릭터 8명과 몹·보스 65종이다.
- 기존 캐릭터의 SD 비율, 머리·눈·무기·의상·역할을 정본과 대조했다. 8명 모두 COSTUME_CONTINUITY_PASS. 녹색 부품이 있는 ENM004·BOSS003은 설치된 Sprite Gen의 색상 분리 처리로 잘못 지워진 몸체를 수정한 후 검수했다.
- 초록 배경 마스터·원본 응답·투명 파생본을 보존했다. 승인 원본은 `data_source/art_source/enemy_replacements_20260911/`와 `data_source/art_source/roster_replacements_20260911/`에 있다. 전투 256px 고밀도 팩과 지도 192px 팩에 같은 정체성과 원본 해시를 연결했다.
- 과거 캐릭터 그림이 새 원화를 덮던 별도 시그니처 경로를 제거하고, 바닥 접점을 18,528프레임에서 다시 계산했다. 기존 전투 타이밍과 원화 기반의 결정적 표시 동작을 유지한다. 이번 교체는 새 동작을 프레임별로 다시 그린 애니메이션 제작 완료를 뜻하지 않는다.
- 캐릭터 8명의 기존 엎어진 SD 그림을 새 의상 정체성과 비교해 유지했다. 몹·보스는 폭발 후 완전히 사라진다. CHR009–CHR044의 신규 전투불능 그림은 이번 기존 8명 교체 범위에 포함되지 않았으며 미완료 상태다.
- 타이틀에 **새 게임**을 추가했다. 실제 진행 초기화 전 게임 안에서 확인하며, 취소하면 기록을 유지한다. 확정 시 성장·첫 클리어·이야기 진행을 새로 시작하고 프롤로그로 진입한다. 기존 원자적 저장/백업 경로를 사용하며 저장 실패 시 메모리 상태를 복구한다.
- 받는 피해와 주는 피해 모두 대상의 머리 위에 표시한다. 화면 크기에 따라 일반 숫자는 실제 21–34px로 읽히고, 치명타는 1.38배 크기와 추가 팝 확대를 사용한다. 연속 피해 겹침 완화, 천 단위 구분, 테두리와 그림자를 적용했다.
- 숫자는 둥근 Nunito Black 기반의 `Lantern Rounded Black`으로 변경했다. 원본 가변 글꼴과 SIL OFL 라이선스, 파생 글꼴의 이름·해시는 `godot/assets/fonts/`에 보존했다. 공식 출처: https://github.com/google/fonts/tree/main/ofl/nunito

## 최종 검증

| 검사 | 결과 | 기록 |
| --- | --- | --- |
| 기존 원화 21종 기술·시각 검사 | 21/21 PASS | `candidate_technical_review.json`, `visual_review.json` |
| 21종 설치 팩·원본·동작·메모리 | 3,112 PASS | `installed_runtime_verification.json` |
| 앞서 교체한 52종 재검사 | 7,281 PASS | `../enemy_replacement_20260911/installed_runtime_verification.json` |
| 실제 Godot 전투 라이브러리·자산 캐시 | 351/351 PASS | `godot_asset_verification.json` |
| 새 게임·저장 실패 복구·숫자 글꼴 | 11/11 PASS | `restart_tests.json` |
| 기존 헤드리스 회귀 검사 | 301/301 PASS | `regression.log` |
| 640×360·1280×720 새 게임·피해·기존 보스 | 274/274 PASS | `browser_v2/acceptance.json` |
| 실제 지도 접촉 진입 후 SD 전투불능·적 소멸 | 16/16 PASS | `defeat_browser/acceptance.json` |
| CH02·CH08·CH20 전투·후반 보스 | 228/228 PASS | `late_encounter_browser/acceptance.json` |
| 일반 릴리스 타이틀→지도·BGM·오류 로그 | 4/4 PASS | `release_boot/acceptance.json` |
| 정리 후 실행본·음악·영상·Git·복구 자료 | 27/27 PASS | `verification_after_cleanup.json` |
| 원화 열람·PNG 원본 및 미리보기 URL | 73종, 146개 정상 | `delivery_verification.json` |

최신 브라우저 검사 합계는 **522/522 PASS**. 원화·치명타·전투불능·후반 보스의 고정 렌더러 장면을 직접 시각 검수했다. 고정 장면 검사는 자연 전투 중 모든 캐릭터의 사망이나 앞선 보스 웨이브 승리를 재현했다는 뜻은 아니다. 500개 작성된 조우에서 가장 큰 5인 파티의 최대 자산 임대량은 **119,549,952바이트(114.01MiB)**로 144MiB 예산 안에 있다.

## 저장 공간

이번 추가 정리에서 12,321개 중복 파일 **4,325,669,128바이트(4.33GB)**를 제거했다. 삭제 전 경로·크기·SHA-256을 `retirement_manifest.json`에 기록하고 다시 대조했다. 정리 대상은 교체된 빌드 4개, 재생성 가능한 Godot 임포트 캐시, 격리 QA 프로필, 설치 완료된 팩의 중복 스테이징이었다.

정리 후 `SD_STORY_RPG_GODOT`은 약 **15.74GB(14.66GiB)**, 상위 `블아 like` 작업 폴더 전체는 약 **15.75GB(14.67GiB)**다. 측정값은 `delivery_verification.json`에 기록했다. 새 Godot 편집/빌드 시 임포트 캐시는 다시 만들어진다.

모든 기존 음원, 미사용 BGM·타이틀·엔딩 곡, 이전 인트로 영상과 복구 압축본은 유지했다. 구 빌드 폴더에는 보호 대상 음원 5개씩만 남아 있으며 실행 가능한 중복 빌드는 없다. Git 참조와 객체, 승인 원화, 원본 녹색 마스터, 검수 보류 자료와 이전 팩의 격리 자료도 보존했다. 이번 정리는 원화 원본이나 실패 후보를 무조건 폐기하는 작업이 아니다.

기존 UI·인트로·지도 수정의 상세 과거 검증은 `../storage_cleanup_20260911/COMPLETION.md` 및 `../player_feedback_20260911/`에 보존되어 있다. 과거 보고서의 실행 주소와 빌드 경로는 당시 기록이며 현재 실행본은 이 문서 상단 주소다.
