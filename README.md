# Project LANTERNLINE (DEV)

프로젝트 전역 불변 조건: 모든 인간 및 인간형 캐릭터는 명확한 성인 여성이고 남성 캐릭터 생성은 금지한다. 일러스트·SD·인게임 의상은 친밀 신체 부위를 가리는 `MAXIMUM_NON_EXPLICIT` 노출도를 공통 목표로 한다. 정본은 `docs/PROJECT_CONTENT_POLICY.md`와 `tools/policy/project_content_policy.json`이다.

Godot 4.7.1 Standard/GDScript/Compatibility renderer로 제작된 Web/HTML 전용 SD 스토리 수집형 RPG 버티컬 슬라이스입니다. Windows의 Godot 실행 파일은 편집, 헤드리스 테스트, Web 내보내기에만 사용하며 네이티브 Windows 게임과 Android 앱은 만들지 않습니다.

실행 흐름은 `타이틀 → 홈 → 스토리 → 편성 → 스테이지 → 전투 → 결과 → 성장 → 저장/복구`입니다. 현재 모든 캐릭터·배경·UI 그래픽은 독립 IP의 코드 기반 `DEV_PLACEHOLDER`이며 최종 제작 에셋이 아닙니다.

## 실행

Godot 4.7.1 Stable Standard가 설치된 Windows 11에서 HTML 빌드:

```powershell
.\tools\powershell\RUN_HEADLESS_TESTS.ps1
.\tools\powershell\SIMULATE_BATTLES.ps1 -Runs 100
.\tools\powershell\BUILD_WEB_DEVELOPMENT.ps1
.\tools\powershell\BUILD_WEB_RELEASE.ps1
.\tools\powershell\PACKAGE_HTML.ps1
.\tools\powershell\PACKAGE_SOURCE.ps1
.\tools\powershell\HASH_BUILDS.ps1
```

로컬 설치된 고정 엔진은 `D:\AI 종합 폴더\Godot\4.7.1-standard`에서 탐색됩니다. 데이터 정본은 `data_source/`, 런타임 컴파일 결과는 `godot/data/compiled/`에 있습니다. 결과물 정본은 `builds/web_release/` 및 `builds/SD_STORY_RPG_HTML.zip`입니다. Web 서버를 통해 실행해야 하며 `index.html`을 파일로 직접 여는 방식은 지원하지 않습니다.
