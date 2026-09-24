# LUMENBOUND: TACTICS OF THE LAST LINE

프로젝트 전역 불변 조건: 모든 인간 및 인간형 캐릭터는 명확한 성인 여성이고 남성 캐릭터 생성은 금지한다. 일러스트·SD·인게임 의상은 친밀 신체 부위를 가리는 `MAXIMUM_NON_EXPLICIT` 노출도를 공통 목표로 한다. 정본은 `docs/PROJECT_CONTENT_POLICY.md`와 `tools/policy/project_content_policy.json`이다.

Godot 4.7.1 Standard/GDScript/Compatibility renderer로 제작된 Web/HTML 전용 SD 스토리 수집형 RPG 버티컬 슬라이스입니다. Windows의 Godot 실행 파일은 편집, 헤드리스 테스트, Web 내보내기에만 사용하며 네이티브 Windows 게임과 Android 앱은 만들지 않습니다.

실행 흐름은 `타이틀 → 홈 → 스토리 → 편성 → 스테이지 → 전투 → 결과 → 성장 → 저장/복구`입니다. 현재 작업본에는 캐릭터 일러스트, 전투 애니메이션, 지형 및 UI 에셋이 연결되어 있습니다. 기술 검증과 최종 미술 승인은 별도로 관리합니다.

## 실행

2026-09-24 성장 메뉴: 전투 결과 화면에서 파티 성장(성장 추천·성장 버튼·새로 가능한 성장 목록)을 뺐습니다. 성장은 본부(랜턴라인 본부) 상단, 전투맵 도구줄, 릴레이 캠프(출발 거점) 상세의 ‘메뉴’에서 합니다. 메뉴에는 레벨업과 스킬업이 따로 있고, 각 항목은 지금 올릴 수 있는 동료 수를 보여주며 해당 탭의 성장 화면을 엽니다.

2026-09-24 캠페인 밸런스: 레벨 상한 이후 적 배율이 계속 올라 5~20장이 사실상 클리어 불가였던 문제를 431개 스테이지 보정으로 고쳤습니다. 5장부터는 스킬 레벨이 성장 기준이며 작전 상세·성장 화면에 권장 스킬 레벨이 표시됩니다. 방법과 검증은 `reports/campaign_balance_20260924/CAMPAIGN_BALANCE_REPORT.md`에 있습니다.

2026-09-24 점검·개선: 스토리 아카이브 보상 반복·미합류 동료 출전·전투 로딩 실패 후 진행 정지·읽을 수 없는 세이브 덮어쓰기·목록 전투의 맵 불일치·고정 드롭 시드를 고쳤습니다. 전열이 적 쪽에 서도록 진형을 바로잡고, 적은 열 가중치로 대상을 고르며, 보스 공격은 2초 전에 예고됩니다. 전투 HUD에 10칸 전술 게이지와 적 공격 예고를 넣었습니다. 결과 화면은 별 조건·MVP·파티 기여도·보상을 보여주고, 성장 화면은 목표 작전 대비 파티 준비도, 이유와 예상 상승치가 붙은 추천, 권장 레벨 버튼을 제공합니다. 기록은 `WORKLOG.md` 2026-09-24 항목에 있습니다.

2026-09-13 전투 동작 개선: 기존 동료 8명의 기본 공격·일반 스킬·궁극기, 기존 적/보스 4종의 기본 공격·일반 스킬에 32동작 / 192개의 새 SD 자세를 연결했습니다. 무기별 발사·궤적·충돌 표현과 타격 시점, 근접 전진 후 복귀를 적용했습니다. 정찰 1-1 처치가 같은 스테이지를 쓰는 1-2의 그림·선택·전투 진입까지 막던 화면 판정을 개별 몹 기준으로 수정했습니다. 두 처치 순서와 실제 전투·재접속을 검증했습니다. 범위와 검증·보존 기록은 `reports/combat_motion_20260913/COMPLETION.md`에 있습니다.

로컬 플레이는 프로젝트 폴더의 `START_LOCAL_GAME.cmd`를 더블클릭하면 됩니다. 서버가 꺼져 있으면 다시 켜고 브라우저를 엽니다. 실행 창을 닫아도 서버는 유지되며, PC 재부팅 뒤에는 같은 파일을 다시 실행하면 됩니다. 같은 빌드의 서버가 있으면 재사용하고, 이전 빌드의 실행기 서버가 남아 있으면 새 빌드로 교체합니다. 인트로 영상만 볼 때는 `PLAY_INTRO.cmd`를 사용합니다.

현재 실행 주소: `http://127.0.0.1:8770/` (최신 로컬 검증본으로 연결) · 영상 재생 주소: `http://127.0.0.1:8770/intro-preview`. 실행기는 게임 PCK 해시로 구분한 주소를 열어 이전 브라우저 캐시와 현재 빌드가 섞이지 않게 합니다. 저장 기록과 IndexedDB를 지우지 않습니다. 파일 경로를 브라우저에서 직접 여는 대신 이 주소를 사용합니다. 실행기 검증 기록은 `reports/player_feedback_20260911/r4_launcher_verified.json`에 있습니다.

최신 로컬 실행본은 `builds/web_claude_20260924_r4_release/`입니다. 일반 1-20 승리 결과의 ‘제2장으로’ 버튼은 1장 후일담, 2장 도입부, 2장 지도로 이어집니다. 다른 장의 일반 마지막 작전에도 같은 진행 규칙을 적용했으며, 위험 작전은 별도로 남습니다. 이전 버전에서 일반 마지막 작전을 이미 클리어한 저장본의 미개방 지역도 보상을 중복 지급하지 않고 복구합니다. 보스전에는 3.8초의 배경 전환·하강·착지·자막을 추가했고, 보스 사망 후에는 전장 배경을 유지한 채 결과 화면으로 전환합니다. 상세 기록은 `reports/chapter_boss_flow_20260912/COMPLETION.md`에 있습니다. 기존 조우 진입 복구, Sprite Gen 캐릭터 8명·몹/보스 65종, 새 게임, 피해 숫자, SD 전투불능과 적 폭발은 유지합니다. 원화 열람은 `http://127.0.0.1:8770/art-gallery`입니다. 과거 보고서의 빌드 경로는 당시 기록이며 교체된 빌드에는 보존 대상 음원만 남겨두었습니다.

전투 동작·정찰몹 수정 후 중복 출력 8.72GB를 정리했습니다. 프로젝트 전체는 약 16.99GB이며, 이 중 Git 이력이 4.69GB, 실제 작업 파일이 12.29GB입니다. 새 SD 원본, 음악과 이전 인트로는 보존했습니다. 검수 보류 원화와 과거 Git LFS 빌드의 복구 압축본은 `quarantine/retained_archive_20260911/`에 있습니다. 과거 LFS 버전을 체크아웃하기 전에 필요한 객체를 `python -B tools/qa/restore_legacy_storage.py lfs`로 복구할 수 있습니다. 상세 복구 방법은 해당 폴더의 `README.md`를 참조하세요. CHR009–CHR044의 신규 SD 전투불능 원화는 이번 기존 8명 교체 범위에 포함되지 않았으며 아직 완료되지 않았습니다.

Godot 4.7.1 Stable Standard가 설치된 Windows 11에서 HTML 빌드:

```powershell
.\tools\powershell\RUN_HEADLESS_TESTS.ps1
.\tools\powershell\SIMULATE_BATTLES.ps1 -Runs 100
.\tools\powershell\BUILD_WEB_DEVELOPMENT.ps1
.\tools\powershell\RUN_LOCAL_WEB.ps1
.\tools\powershell\BUILD_WEB_RELEASE.ps1
.\tools\powershell\PACKAGE_HTML.ps1
.\tools\powershell\PACKAGE_SOURCE.ps1
.\tools\powershell\HASH_BUILDS.ps1
```

로컬 설치된 고정 엔진은 `D:\AI 종합 폴더\Godot\4.7.1-standard`에서 탐색됩니다. 데이터 정본은 `data_source/`, 런타임 컴파일 결과는 `godot/data/compiled/`에 있습니다. 현재 실행 결과물은 `builds/web_claude_20260924_r4_release/`입니다. Web 서버를 통해 실행해야 하며 `index.html`을 파일로 직접 여는 방식은 지원하지 않습니다.

인트로 교체까지 포함한 현재 빌드는 다음 명령으로 실행합니다.

```powershell
.\tools\powershell\START_LOCAL_GAME.ps1
```

Web 빌드에는 부팅 파일과 함께 `_hd/` 및 `density_sidecars.json`을 포함해야 합니다. 실행·패키징 전에 별도 고해상도 이미지의 누락과 해시 불일치를 검사합니다. 브라우저 저장은 체크섬을 포함한 동기식 복구 저널과 기존 파일/백업을 함께 사용하여 저장 완료 직후 새로고침해도 확정한 진행을 복구합니다. 검사 결과는 `reports/local_audit_20260910/`에 기록합니다.

현재 인트로는 `intro/1.mp4`부터 `5.mp4`까지 번호 순으로 연결한 1920×1080, 24fps, 50초 영상입니다. 장면 사이에는 7프레임(약 0.292초) 디졸브를 적용하고, 첫 네 클립을 240→247프레임으로 늘려 전체 길이를 유지합니다. 새 원본들의 음성·BGM은 사용하지 않으며, 교체 전 인트로의 음악만 패킷 복사로 유지합니다. 게임용 파일은 `godot/assets/video/lumenbound_intro_full.ogv`, 제작 도구는 `tools/video/build_intro_1080p.py`, 원본 보존·추적 정보는 `data_source/video/intro_20260910/`, 검증 결과는 `reports/intro_replace_20260910/`에 있습니다.
