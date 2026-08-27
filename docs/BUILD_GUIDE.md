# Build Guide — Web / HTML only

요구 버전은 Godot 4.7.1 Stable Standard다. .NET/C# 에디터나 4.8 dev/4.7.2 RC는 스크립트가 중단한다. Windows Godot 실행 파일은 편집·헤드리스 테스트·Web 내보내기 도구일 뿐이며 네이티브 게임 산출물이 아니다.

```powershell
.\tools\powershell\VALIDATE_ALL.ps1
.\tools\powershell\RUN_HEADLESS_TESTS.ps1
.\tools\powershell\BUILD_WEB_DEVELOPMENT.ps1
.\tools\powershell\BUILD_WEB_RELEASE.ps1
.\tools\powershell\PACKAGE_HTML.ps1
.\tools\powershell\PACKAGE_SOURCE.ps1
.\tools\powershell\HASH_BUILDS.ps1
```

Web Development와 Web HTML Release는 스레드 및 GDExtension을 사용하지 않는다. Release는 PWA 파일을 포함한다. `builds/web_release/`를 HTTP 서버로 제공해야 하며 로컬 파일 URL로 직접 열지 않는다.

## 개발자 QA에서 HARD 일일 제한을 만났을 때

같은 날짜에 HARD 스테이지를 반복 검증해야 하면 `BUILD_WEB_DEVELOPMENT.ps1`로 만든
`builds/web_development/` 패키지를 사용한다. 개발 권한 빌드에서는 HARD 입장 횟수와
작전력을 차감하지 않으며 스테이지 상세에 `무제한 (DEV)`가 표시된다. 따라서 저장의
`hard_attempts` 값을 조작하거나 시스템 날짜를 바꿀 필요가 없다.

`Web HTML Release`에서는 이 우회가 존재하지 않는다. Release는 실제 날짜별 HARD
입장 횟수와 작전력 규칙을 그대로 적용한다. 개발 패키지의 QA 우회 코드는 Release
PCK에 포함되지 않으며, 배포 전에 반드시 Release 경로를 별도로 검증한다.

Windows EXE, Windows 앱 ZIP, APK, AAB, Electron, Tauri, NW.js, WebView 래퍼는 이 프로젝트의 빌드 대상이 아니다.
