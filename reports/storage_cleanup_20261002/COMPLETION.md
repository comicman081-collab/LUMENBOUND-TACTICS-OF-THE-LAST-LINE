# 로컬 용량 정리 2차 — 2026-10-02 (Claude)

사용자 요청: "너도 게임 수정하고 배포하느라 생긴 쓸게 없는 자료들 다 좀 지워라 용량 확보해야해". 이어서 r15 빌드에 대해 "r15 지워".

## 범위

내가 r22를 수정하고 배포하면서 만든 것 가운데, 다시 만들 수 있거나 결과가 보고서에 이미 적힌 것만 정리했다.
r15 검증본은 사용자가 지우라고 해서 정리했다. 사운드·인트로 영상·Codex 작업물·배포 근거는 건드리지 않았다.

## 정리한 것

경로·크기·SHA-256·이유를 이 폴더의 `*_retirement_manifest.json.gz`에 먼저 적고 Windows 휴지통으로 보냈다(영구 삭제 아님).

| 대상 | 파일 | 크기 | 기록 |
| --- | --- | --- | --- |
| D: `builds/web_visual_r15_release` (r15 검증본 Web 빌드, 사용자 지시 "r15 지워") | 3,593 | 849,215,380바이트 (약 0.85GB) | `r15_release_retirement_manifest.json.gz` |
| D: `builds/web_visual_r22_development` (r22 디버그 템플릿 내보내기, 개발자 모드 로그 `WEB_FRAME_GAP` 확인용) | 3,584 | 852,191,468바이트 (약 0.85GB) | `r22_development_retirement_manifest.json.gz` |
| D: `tools/web/__pycache__` (스크립트 실행이 만든 바이트코드 캐시, 자동으로 다시 생긴다) | 1 | 19,064바이트 | 같은 기록의 `other_files` |
| D: `reports/visual_phase4_20260930/screenshots` (끝난 4단계의 git 제외 QA 캡처, 결과는 `PHASE4_REPORT.md`에 있다) | 16 | 24,855,440바이트 (약 25MB) | `phase4_captures_retirement_manifest.json.gz` |
| C: 이 세션의 스크래치 폴더 51개 (QA용 Godot 사용자 폴더, 단계별 작업 폴더·캡처·로그, 참조 영상 프레임, 검토용 캡처) | — | 약 477MB | 작업용 임시 폴더라 별도 목록은 없다. QA 스크립트 몇 개만 남겼다 |

D:에서 정리한 합계는 약 1.73GB다. 휴지통에는 D:에 약 1.75GB, C:에 약 0.4GB가 쌓여 있다.
**디스크 공간은 휴지통을 비워야 확보된다.** 휴지통은 내가 비우지 않는다(사용자가 비운다).

### r15를 지우기 전에 확인한 것

- 사운드·인트로 영상은 보존 대상이라, r15 안의 오디오·영상 파일 2,917개(186,275,219바이트: BGM, SFX, `intro.mp4`)를 전부 해시로 보존 위치의 파일과 대조했다.
  바이트까지 같은 사본이 없는 파일은 0개다. BGM은 `godot/assets/audio/bgm`에 있고, 인트로 영상은
  `work/video/intro_1080p_50s_20260920/intro_1080p_50s_with_existing_bgm_compressed.mp4`와 같다. 기록에 파일마다 사본 위치를 적었다.
- `_hd` 페이지 656개(474,942,319바이트)는 전부 `godot/assets`의 파일과 r22 빌드의 `_hd` 페이지와 같다.
- 남지 않는 것은 r15 PCK(`r7_current_a2ebffb1443a.pck`, SHA-256 `a2ebffb1443a9a3b1b33c78ec426ba19c36c741809138b3ee4084d87678734c7`)와 wasm 같은 빌드 산출물뿐이다.
  소스는 git에 있고 `tools/powershell/BUILD_WEB_R7.ps1`로 다시 만들 수 있다.
- 이 경로를 쓰는 스크립트는 없다(`tools`와 루트 문서를 검색했다). 로컬 실행기 `START_LOCAL_GAME.ps1`은 이미 r22를 가리킨다.

### 다시 만들 때

r22 개발 내보내기가 다시 필요하면 새 태그로 `tools/powershell/BUILD_WEB_R7.ps1`을 돌린다. 같은 태그 `visual_r22`는 release 폴더가 있어 스크립트가 거부하고,
`-ReplaceExisting`을 쓰면 기존 release가 `work/build_output_quarantine`으로 옮겨져 용량이 오히려 는다.

## 남긴 것과 이유

- 빌드: `builds`에는 이제 r21과 r22 릴리스만 있다(각 약 0.82GB).
  r22(`web_visual_r22_release`)는 GitHub Pages 배포본의 원본이라 스테이저의 입력이다. r21은 Codex가 Sites에 올린 버전이고 Codex 도구(`compact_sites_voice.py`)가 이 경로를 쓴다.
- 사운드: `quarantine/asset_cleanup_20260904/audio_sources_retained`, `work/voice_ja_20260927`, `data_source/audio_source`, `godot/assets/audio`. 인트로 영상: `intro/`, `work/video`, `godot/assets/video`.
- Codex 작업물: `work/sites_20260920`(1.85GB), `work/sites_r21_20261001`(1.04GB), `reports/sites_r21_intro_fix_20261001`(0.27GB), `work/sites_20260925_title_pop_v19.tar.gz`, `work/new_chat_recovery_20260926`.
- `godot/.godot`(1.06GB): 임포트 캐시라 지우면 다음 테스트·내보내기 전에 전부 다시 임포트해야 하고, Codex가 같이 쓰고 있을 수 있다.
- `.git`(2.3GB): 건드리지 않았다. 느슨한 객체 1.08GiB를 팩으로 묶는 경우를 쓰기 없이 추정하니 1.06GiB라 줄어드는 양이 미미하다.
- `reports/visual_r22_20261001`의 캡처(5.8MB)와 타이틀 미리보기 영상(7MB): Codex 인계의 근거라 남겼다.
- C:의 Temp 루트에 있는 다른 프로그램의 Chrome 프로필 폴더(약 19GB): 내 세션이 만든 것이 아니라 건드리지 않았다.

## 결정이 필요한 것

1. r21 릴리스 0.82GB. Codex가 r22를 Sites에 올린 뒤에 지우는 편이 안전하다.
2. `godot/.godot` 1.06GB. Codex가 쓰지 않을 때 지우고 한 번 다시 임포트하면 된다.
3. Codex 작업 폴더 약 3.2GB. Codex에게 정리를 맡긴다.
