# Known Limitations

Date: 2026-08-24 (Asia/Seoul)

## Current verification note — 2026-08-25

The latest source run is 559/559 automated assertions PASS (70 static, 165
core, 249 map, 49 R15, 26 R16). The current local Release PCK is
`148efe50fd4327b97de86b921cfe156b41626eb323ce9369c4191614053194e1`
(62,791,336 bytes). Its technical in-app boot reached Title → Home in one
temporary tab after the full-length BGM repack. This does not remove the
limitations below.

현재 증거로 확인되는 제한만 기록한다.

1. 현재 Release에서는 직접 pointer 입력으로 N10 선택 → 물리 이동 → 기존 전투 → 패배 → 미클리어 boss 유지 → refresh 복구의 경계가 확인됐다. 그러나 현재 바이트에서 H02 및 Chapter 1 NORMAL 10 + HARD 5 전체를 연속 완주하지 않았으므로 해당 전체 E2E는 **UNVERIFIED**다.
2. 실제 Release QA는 약 116초였다. 최신 RAF window는 평균 99.4 FPS, p50/p95/p99 10.0/10.1/10.1 ms였지만 브라우저당 20분 controlled GPU·메모리 soak가 아니므로 장시간 성능 PASS는 **UNVERIFIED**다.
3. 맵에서 약 3,727 draw calls, 4,257 nodes, 7,068 objects가 관찰됐다(orphan 0). 현재 짧은 QA는 원활했으나 draw-call/node 최적화 여지가 남아 있다.
4. 현재 모바일 증거는 `390×844`와 `915×412` layout/touch metric의 결정론적 headless 검증이다. 실물 휴대전화의 터치, 상·하단 시스템 UI, safe area, 발열 및 성능 QA는 **UNVERIFIED**다.
5. 최신 패키지의 별도 설치 Edge/Chrome/Firefox 교차 브라우저 실행은 이번 최종 증거에 포함되지 않는다. 인앱 브라우저 결과를 cross-browser 인증으로 확대하지 않는다.
6. Web에서 lobby/battle BGM loop와 공격·피격·스킬·필살기 이벤트 연결, failures 0은 확인했다. 사람이 직접 들은 음질·볼륨·장면별 믹스 평가는 **UNVERIFIED**다.
7. 런타임 자산 연결 검증과 프로덕션 미술 승인은 별개다. `PRODUCTION_APPROVED`는 사용자 검토 전까지 `WAITING_USER_APPROVAL`이다.
8. 오프라인 save checksum, 로컬 날짜 HARD 제한, 브라우저 로컬 저장은 서버 권위 변조 방지나 클라우드 복구가 아니다.
9. Windows EXE 및 Android APK/AAB를 생성하지 않았고 native/device QA도 수행하지 않았다.
10. 공개 배포·호스팅은 수행하지 않았다. 사용자의 명시적인 배포 승인 전까지 로컬 산출물로만 유지한다.
