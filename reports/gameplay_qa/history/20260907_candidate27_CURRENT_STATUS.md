# 최신 로컬 검수 — candidate 27

배포·GitHub Actions·push·파일 삭제 없음. 전체 상용 아트 승인과 구분한 로컬 검수 기록이다.

## 이번 흰 잔여물 수정

- 로안(CHR002) 팔 안쪽과 에다(CHR004) 헤어 내부의 불투명 흰 영역을 제거했다.
- 각 80개 동작 프레임의 투명 영역이 실제 256px 아틀라스와 오차 없이 일치한다.
- 필살기용 384px 프레임도 녹색 마스터·RGBA·해시를 개별 보존했다.
- 기존 의상·무기·얼굴·게임 수치는 변경하지 않았다. 잘못된 자산은 격리했으며 삭제하지 않았다.

## 함께 반영·검수한 범위

- 109개 캐릭터·몹의 모든 동작 256px, 선택된 주요 동작 384px.
- 109개 발사체 192px, 기본·일반 스킬 192px, 필살기 256px. 기존 원본/프로시저를 사용했으며 저해상도 썸네일 확대가 아니다.
- 109개 맵 캐릭터의 대기·이동·도착 동작 192px. 화면상 크기와 발 접점은 유지한다.
- 고해상도 PNG는 첫 실행 PCK에 넣지 않고 필요한 장면에서만 해시 검증 후 읽는다. 동시 요청은 최대 3개, 디코딩/업로드는 프레임당 1개다.
- 파일 크기 비교 오류로 HD가 거절되던 문제와, 실제 다운로드 중인데 로딩 감시가 중단시키던 오류를 고쳤다.
- 맵 개체별 프레임 선택을 분리해 한 몹의 이동 동작이 다른 몹의 텍스처 상태를 바꾸지 않게 했다.
- N13 모바일 설명창 전체 페이지·회전·터치·전투·N14 연결, N01/N05 보상·성장·장비·대사, N20 보스 3웨이브·H01 연결·회전·브라우저 복귀를 검수했다.
- 맵 배경·오브젝트·192px 캐릭터, 강 터치 통과 차단, 가로/세로 가시성 검수 통과.

## 결과

- map26_gallery: 19/19 PASS
- briefing26_audit: 134/134 PASS
- progression26_audit: 164/164 PASS
- final26_audit: 223/223 PASS
- final27_audit: 223/223 PASS
- 일반 회귀 277/277, 맵 회귀 354/354.
- 전체 자산 로딩: 전투 109, 발사체·이펙트 436, 맵 109 — 실패 0.
- 새 프로필 20스테이지 서비스 체인: 막힘 0, 저장/재로드 불일치 0. 실제 전 스테이지 수동 플레이와는 구분한다.
- 최신 N20 전투/진입 구간: 최대 140.0ms, 1초 이상 지연 0회, 완전한 측정 창의 최악 p95 40.0ms. 물리적 휴대전화 60fps 인증은 아니다.

## 남아 있는 한계

첫 Web 그래픽 준비는 여전히 길다. 최신 실행 로그: WEB_RENDER_WARMUP_COMPLETE 20898.50ms / STAGE_ENTRY_PRELOAD_COMPLETE map=CH01_MAP elapsed_ms=6541 target_ms=5000 within_target=false cache_hit=false gpu_textures=40 / STAGE_ENTRY_PRELOAD_COMPLETE map=CH01_MAP elapsed_ms=1864 target_ms=5000 within_target=true cache_hit=true gpu_textures=0.
해상도와 연결 개선이 업로드 영상 수준의 관절 애니메이션/상용 아트 완성을 뜻하지 않는다. 실제 Android/iOS, 음원 청취, 외부 ChatGPT 리뷰는 이번 배치에서 수행하지 않았다. 따라서 격리본 삭제·공개 배포·전체 상용 품질 PASS는 승인하지 않았다.

실행본: builds/web_gameplay_qa_20260907_candidate27/development
상세 해시·측정·검수 경계: 20260907_VERIFICATION_MANIFEST.json
이전 candidate 20 기록: history/20260907_candidate20_status.md
