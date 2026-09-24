# SD 전투불능 원화 검증

- 대상: 플레이어 캐릭터 CHR001–CHR008, 8종
- 형식: 고정 512×512 논리 캔버스의 SD 전투용 엎드림 원화
- 적/보스: 전투불능 비트맵을 런타임에서 읽지 않고 Canvas 폭발 연출만 표시
- 런타임 폴더: `godot/assets/runtime_web/combat_down_pose/`
- 시각 검수: `work/down_pose_sd_20260911/candidates/sd_down_pose_player_only_contact_sheet.png`
- 헤드리스 회귀: 후속 수정 포함 301/301 PASS
- 현재 Web 릴리스: `builds/web_verified_local_20260911_release/`
- 현재 로컬 확인 주소: http://127.0.0.1:8770/play/0d481c47c34b/
- 이전 `7ed7c66e99a5` 검사 빌드는 후속 검증 완료 후 제거했다.
- 인트로 브라우저 검증: 1920×1080, 50초, BGM 디코드, 일시정지/재개, 50초 ended PASS
- 사이드카 검증: HD 644 pages, BGM 5 tracks

실수로 생성된 풀 일러스트 후보와 적/보스 후보는 `work/down_pose_sd_20260911/quarantine/`에 보존했고 런타임 포인터에서 제외했다.

후속 검증: 실제 맵 접촉→전투 진입 후 고정된 렌더러 검사에서 8명 원화와 적 폭발/소멸 16/16 PASS. 자연 전투에서 8명 모두가 쓰러지는 장면을 재현했다는 의미는 아니다. 실제 전투 완료 3회 검사는 223/223 PASS, 일반 릴리스 부팅·지도·음악 검사는 4/4 PASS다. 상세 기록은 `reports/storage_cleanup_20260911/`에 있다.

범위 제한: 전체 44명 기준 CHR009–CHR044의 신규 SD 엎드림 원화 36종은 미완료다. 이 보고서는 모든 캐릭터의 제작 완료를 선언하지 않는다.
