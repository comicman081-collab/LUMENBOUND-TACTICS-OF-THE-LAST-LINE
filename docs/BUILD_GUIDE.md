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

Windows EXE, Windows 앱 ZIP, APK, AAB, Electron, Tauri, NW.js, WebView 래퍼는 이 프로젝트의 빌드 대상이 아니다.
