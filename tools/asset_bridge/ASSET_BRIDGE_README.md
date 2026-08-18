# Local Asset Bridge

이 브리지는 발견된 로컬 TypeScript/Three.js 공용 자산 팩토리의 원본을 수정하지 않습니다. manifest 필수 필드, export 경로, manifest SHA-256, PNG IHDR(폭·높이·알파 형식)을 검사한 뒤 최신 버전의 PNG/atlas만 증분 복사합니다. 동일 SHA-256은 다시 복사하지 않습니다.

정본 출력은 `godot/assets/generated_import/`이며 `import_manifest.json`, `licenses.json`, `attribution.md`를 이 경로에 생성합니다. 라이선스 원장은 팩토리 파일뿐 아니라 프로젝트 생성 전투 팩과 번들 폰트 기록을 병합합니다. Godot 검증 단계는 프로젝트 내부 `.runtime_profile`을 사용하므로 기본 AppData 로그 경로에 의존하지 않습니다.

```powershell
$env:SD_RPG_ASSET_FACTORY_ROOT='D:\AI 종합 폴더\Games\asset_share'
..\powershell\SYNC_ASSETS.ps1
```

Three.js 렌더와 spritesheet는 모두 `DEV_PLACEHOLDER`입니다. 기존 walk sheet만으로 최종 8종 SD 애니메이션 계약을 충족한다고 간주하지 않습니다. `licenses.json`의 `MANIFEST_NOT_DECLARED` 항목은 상업 배포 전 권리 확인이 필요합니다.
