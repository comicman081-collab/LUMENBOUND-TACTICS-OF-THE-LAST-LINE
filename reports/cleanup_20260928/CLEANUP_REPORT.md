# 로컬 정리 (2026-09-28)

요청:
- "커밋하고 필요없는 것들을 다 지워라. 사운드관련 자산만 남기는데, 시나리오 음성의 경우에는 연결된 것만 남기고 폐기본은 삭제한다."
- "qa 관련 삭제 자산들도 한군데 이동시켜 모아놔라 내가 삭제하겠다"

## 1. 휴지통으로 보낸 것 (8,877개 파일, 5.4GB)

모든 파일의 경로·크기·SHA-256은 `retired_files.jsonl.gz`에 있다. 영구 삭제가 아니라 D: 휴지통으로 보냈다.

| 대상 | 파일 | 크기 |
|---|---|---|
| `quarantine/site_publish_20260920` (옛 배포 후보) | 220 | 1,572MB |
| `reports/` 아래 추적되지 않는 QA 캡처·로그 | 3,052 | 1,207MB |
| `quarantine/retained_archive_20260911` (옛 아트·LFS 빌드 복구 아카이브) | 3 | 843MB |
| `builds/web_growth_r13_release` (직전 빌드) | 3,593 | 810MB |
| `work/sites_20260920_sfx_hotfix`, `work/sites_20260920_minimal.zip` | 163 | 617MB |
| `work/voice_ja_20260927/{raw,probe,audition}`의 미선택 테이크 | 553 | 169MB |
| `quarantine/retired_builds_20260927` (r10·r11·r12 빌드) | 680 | 164MB |
| `quarantine/sites_sfx_hotfix*_20260920` | 89 | 84MB |
| `work/gameplay_qa_quarantine_20260907` (QA 녹화) | 2 | 39MB |
| `quarantine/voice_ja_r11_runtime_20260927` (옛 음성 런타임) | 502 | 14MB |
| 기타 빈 폴더와 작은 목록: `work/sites_*_index*`, `work/sites_upload_batches`, `work/pck_inspection`, `work/blender_profiles`, `quarantine/local_audit_20260910`, `quarantine/battle_signature_hd_r1_fail_20260904` | 20 | 1MB |

### 사운드

- 사운드 파일 320개(아카이브 안의 5개 포함)는 모두 보존본과 바이트 단위로 같았다. 새로 옮겨 둔 사운드는 없다.
  - 보존본 위치: `godot/assets/audio`, `data_source/audio_source`, `quarantine/asset_cleanup_20260904/audio_sources_retained`,
    `work/new_chat_recovery_20260926`, `work/sites_20260920`
- 남은 사운드는 쓰지 않는 곡을 포함해 그대로 있다.

### 시나리오 음성

- 연결된 음성만 남았다.
  - 런타임 2,857개: `godot/assets/audio/voice/ja`, `voice_manifest.json`의 모든 파일
  - 원본 2,857개: `work/voice_ja_20260927/selection.json`이 가리키는 테이크
  - 확인: 미선택 잔여 0, 누락 0
- 버린 음성 파일은 4,219개다.
  - 옛 빌드의 사이드카 사본 3,416개
  - r11 런타임 사본 502개
  - 미선택 테이크·오디션·프로브 553개
- 이 중 2,936개는 남긴 음성과 같은 사본이었다.

### 영상

- `intro.mp4` 사본 8개는 `work/video`의 원본과 같았다.
- 버린 영상은 QA 전투 녹화 2개와 배포 분할 조각 2개다. 조각의 원본 파일(`75d7de7f…`)은 `work/video/intro_1080p_50s_20260920`에 있다.
- `work/video`의 옛 인트로 영상(약 237MB)은 이번 요청 범위가 사운드라서 그대로 두었다.

### 남긴 것

- 빌드: 현재 빌드 `builds/web_tactics_r14_release` 하나만 남았다. 로컬 실행기는 이 빌드를 쓴다.
- Codex 작업물:
  - `work/sites_20260920`: `prepare_sites_minimal.py`의 원본
  - `work/sites_20260925_title_pop_v19.tar.gz`
  - `work/new_chat_recovery_20260926`
  - `work/quarantine`
- 원본: `quarantine/asset_cleanup_20260904`(사용자 원본 BGM 3.7GB), `work/down_pose_sd_20260911`, `data_source/art_source`
- 실행 중인 로컬 실행기가 열고 있는 로그 1개: `reports/local_launcher/21944-1790523523237.server.log`

## 2. QA 삭제 대상 모음 (사용자가 직접 삭제)

- 위치: `DELETE_CANDIDATES/qa_20260928/`. 이 폴더는 `.gitignore`에 있다.
- 2,434개 파일, 386MB. 삭제하지 않고 옮기기만 했다.
- 옮긴 파일의 원래 경로·크기·SHA-256은 `qa_gathered_files.jsonl.gz`에 있다.

| 원래 위치 | 파일 | 크기 | 내용 |
|---|---|---|---|
| `godot/.runtime_profile` | 82 | 185MB | Godot QA 격리 프로필, 실행 로그 |
| Claude 세션 임시 폴더 | 2,080 | 182MB | QA 로그, 캡처, 밸런스 보정 실행 결과, 임시 프로브 |
| `%APPDATA%\Godot\app_userdata\LUMENBOUND- TACTICS OF THE LAST LINE` | 38 | 12MB | 데스크톱 Godot 사용자 데이터: 헤드리스 테스트 저장, r15 샌드박스, 로그, 셰이더 캐시 |
| `%APPDATA%\Godot\app_userdata\LANTERNLINE DEV` | 12 | 1MB | 옛 개발명 사용자 데이터 |
| `godot/assets/placeholders_legacy` | 188 | 3.7MB | 옛 플레이스홀더. 내보내기에서 제외되고 참조되지 않는다 |
| `godot/assets/art/qa` | 13 | 1.6MB | QA 실루엣. 내보내기에서 제외되고 참조되지 않는다 |
| `tools/**/__pycache__` | 8 | 0.2MB | Python 캐시 |
| `.qa_logs` | 10 | 4KB | QA 서버 로그 |
| `godot/tools/tactical_balance_probe.*` | 3 | 4KB | 일회성 밸런스 프로브. git에서 제거했고 `3f17523`에 기록이 있다 |
| `godot/feature_profiles`, `work/video/intro_1080p_50s_20260910/tmp` | 0 | 0 | 빈 폴더 |

- 웹 빌드의 게임 저장은 브라우저에 있어서 영향이 없다.
- `app_userdata`는 데스크톱 Godot으로 실행할 때만 쓰인다.
- 옮긴 뒤 격리한 사용자 데이터로 회귀 테스트를 돌렸다. test_runner 308/308, 전술 규칙 81/81 통과.

## 정책

- `AGENTS.md`의 로컬 저장 규칙에 이번 요청을 반영했다.
  - 사운드는 모두 보존한다.
  - 시나리오 음성은 연결된 것만 보존한다.
  - `retained_archive_20260911`은 폐기했다.
- 배포·푸시는 하지 않았다.
