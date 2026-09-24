# 로컬 용량 정리 — 2026-09-24 (Claude)

사용자 요청 "로컬에서 필요 없는 자산들 격리해서 지운 후"에 따라, 내용 손실이 없는 대상만 정리했다.
작업 폴더(`.git` 포함) 약 28GiB → 26GiB, 파일 1,232개·1.34GiB.

## 방법

1. `.git`과 Godot 임포트 캐시를 뺀 프로젝트 전체 26,921개 파일의 SHA-256 목록을 만들었다.
2. 아래 기준에 맞는 파일만 골라 경로·크기·해시·이유·남은 사본을 `retired_files.jsonl.gz`에 먼저 기록했다.
3. 대상을 `quarantine/local_cleanup_20260924/`로 격리한 뒤 검증했다.
   - 1,232개 모두 격리됨, 크기 일치.
   - 중복 1,152개의 남은 사본이 모두 존재하고 해시 일치.
   - 현재 실행본 r7이 HTTP 200으로 제공됨.
4. 격리 폴더를 Windows 휴지통으로 보냈다(복구 가능, 영구 삭제 아님). 디스크 공간은 휴지통을 비워야 확보된다.

## 정리한 것

| 대상 | 파일 | 크기 | 이유 |
| --- | --- | --- | --- |
| `builds/web_development` (09-20 개발 빌드) | 668 | 722MiB | 오래된 빌드. `BUILD_WEB_DEVELOPMENT.ps1`이 다시 만든다. `_audio/`는 남김 |
| `godot/.runtime_profile/runs` | 75 | 340MiB | QA용 Godot 사용자 데이터(일회용) |
| `work/enemy_replacement_20260911` | 156 | 154MiB | 게임 자산과 바이트 단위로 같은 사본 |
| `work/existing_roster_spritegen_20260911` | 65 | 74MiB | 동일 사본 |
| `work/enclosed_matte_repair` | 174 | 35MiB | 동일 사본 |
| `work/combat_motion_20260913`, `quarantine/combat_motion_20260913` | 69 | 45MiB | 동일 사본 |
| 기타 work·quarantine 소량 | 25 | 3MiB | 동일 사본 |

## 남긴 것과 이유

- **소리·영상 파일 전부**(AGENTS.md 보존 규칙): 교체된 빌드의 `_audio/`·`intro.mp4`, `intro/`,
  `data_source/audio_source/`, 음악 보존 묶음 `quarantine/asset_cleanup_20260904/`.
- **Sites 배포 관련**: `builds/web_sites_20260920_release`, `work/sites_20260920*`(체크아웃·압축본),
  `quarantine/site_publish_20260920`, `quarantine/sites_sfx_hotfix*`. 배포는 Codex가 맡으므로 입력물을 건드리지 않았다.
- **복구 압축본** `quarantine/retained_archive_20260911/`, 실패 자산 검토 기록
  `quarantine/battle_signature_hd_r1_fail_20260904/`, Git 이력, 보고서·스크린샷.
- 다른 곳에 사본이 없는 작업 중간물·교체된 원화는 1차에서 남겼고, 사용자 요청에 따라 아래 2차에서 정리했다.
- 정리 도중 생긴 새 QA 실행 프로필(`runs/34920-…`)은 다른 작업이 쓰는 중일 수 있어 두었다.

## 2차 — 작업 중간물·교체된 원화

사용자 요청 "남은 작업 중간물, 교체되어 필요없는 원화들도 정리해라"에 따라 `work/`·`quarantine/`의 제작 중간물과
교체 전 원화를 정리했다. 파일 4,503개·1.20GiB. 작업 폴더(`.git` 포함) 약 26.2GiB → 25.0GiB.
이제 `work/`·`quarantine/`에 남은 큰 항목은 음악 보존 묶음(3.7GiB), Sites 배포 입력물(약 7GiB), 복구 압축본(0.8GiB), 영상(0.2GiB)이다.

1. 게임(`godot/`)·빌드·검사 스크립트가 이 폴더들을 읽지 않는지 확인했다. 게임 데이터의 `work/` 경로는 출처 기록뿐이다.
   실제로 있는 파일을 가리키는 것은 현재 SD 전투불능 원화의 원본 8장
   `work/down_pose_sd_20260911/masters/CHR001~008_down_pose_sd_green.png`뿐이어서 그것은 남겼다.
2. 소리·영상 확장자와 1차의 보존 대상은 모두 제외했다.
3. 파일별 경로·크기·SHA-256을 `retired_art_intermediates.jsonl.gz`에 먼저 기록했다. 각 폴더의 manifest·출처·보존 기록 JSON(2MB 이하 385개)은
   `retired_art_records.tar.gz`에 따로 남겼다.
4. `quarantine/local_cleanup_20260924_art/`로 격리한 뒤 4,503개 모두 크기·해시가 일치함을 확인했다.
   정적 검사 71/71과 헤드리스 회귀 31개 장면이 통과한 뒤 휴지통으로 보냈다(복구 가능).

| 대상 | 파일 | 크기 | 내용 |
| --- | --- | --- | --- |
| `work/combat_motion_20260913` | 1,273 | 415MiB | 전투 동작 자세 생성 중간물·후보·로그 |
| `quarantine/combat_motion_20260913` | 511 | 168MiB | 탈락한 전투 동작 후보 |
| `work/enemy_replacement_20260911` | 400 | 167MiB | 몹/보스 교체 생성 중간물 |
| `quarantine/enemy_placeholders_20260911` | 679 | 137MiB | 교체 전 적 임시 그림 |
| `quarantine/existing_roster_pre_spritegen_20260911` | 278 | 113MiB | Sprite Gen 교체 전 동료 원화 |
| `work/existing_roster_spritegen_20260911` | 160 | 80MiB | 동료 Sprite Gen 생성 중간물 |
| `work/full_density` | 331 | 66MiB | 고밀도 이미지 작업본(게임용은 `godot/`에 있음) |
| `work/gameplay_qa_quarantine_20260907` | 749 | 46MiB | 09-07 QA 후보·이전 판정 기록(`.webm` 2개는 남김) |
| `quarantine/down_pose_local_20260911`, `work/down_pose_sd_20260911`(원본 8장 제외) | 80 | 23MiB | 전투불능 자세 이전 후보 |
| 기타 12곳 | 42 | 10MiB | 동료 초록 배경 키 작업, 참조 캐시, 지도 작업 `.blend`, 본부 일러스트 생성 기록, 09-11 교체 빌드 기록, UI 후보 등 |

남긴 것: 위 원본 8장, 모든 소리·영상(`work/video/`, QA `.webm` 포함), Sites 배포 입력물, 복구 압축본
`quarantine/retained_archive_20260911/`, 음악 보존 묶음, 실패 자산 검토 기록.
