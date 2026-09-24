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
- **다른 곳에 사본이 없는 작업 중간물·교체된 원화**(원화 보존 규칙):
  - `work/combat_motion_20260913` 415MiB
  - `work/enemy_replacement_20260911` 167MiB
  - `quarantine/combat_motion_20260913` 168MiB
  - `quarantine/enemy_placeholders_20260911` 137MiB
  - `quarantine/existing_roster_pre_spritegen_20260911` 113MiB 등

  필요 없다고 확인되면 같은 방식으로 추가 정리할 수 있다.
- 정리 도중 생긴 새 QA 실행 프로필(`runs/34920-…`)은 다른 작업이 쓰는 중일 수 있어 두었다.
