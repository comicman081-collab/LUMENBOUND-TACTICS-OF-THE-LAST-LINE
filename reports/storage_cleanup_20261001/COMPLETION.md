# 로컬 용량 정리 — 2026-10-01 (Claude)

사용자 요청: "필요없는것들 사운드, 인트로동영상 자산들 제외하고 지워라".

## 범위

`D:\AI 종합 폴더\Games` 전체는 146.6GB이고, 이 작업 폴더(`블아 like\SD_STORY_RPG_GODOT`)는 약 16.0GB(전체의 11%)다.
나머지는 다른 게임 폴더다(After Signal 61.4GB, voice·image asset 21.2GB, Sable-circuit 18.1GB, TRIAD_RUN 6.8GB, 비쥬얼 노벨 6.5GB, asset_share 6.2GB, 꼼순이 5.4GB 등). 이번 정리는 건드리지 않았다.

## 정리한 것

경로·크기·SHA-256·이유를 `retired_files.jsonl.gz`에 먼저 적고 Windows 휴지통으로 보냈다(영구 삭제 아님).

| 대상 | 파일 | 크기 |
| --- | --- | --- |
| `godot/.runtime_profile/runs/*` (QA 실행이 남긴 Godot 런타임 프로필 7개, 필요하면 다시 만들어짐) | 28 | 약 166MB |
| 1~3단계·전술 r14 QA 캡처 PNG/JPG (`reports/visual_phase1..3_20260930`, `reports/tactics_r14_20260928`, git 제외 파일) | 73 | 약 51MB |

합계 101개 파일, 216.8MB. 스크래치 폴더(C 드라이브)의 테스트용 Godot 사용자 폴더·캡처 출력 약 600MB도 휴지통으로 보냈다.
디스크 공간은 휴지통을 비워야 확보된다.

## 남긴 것과 이유

- 사운드: `quarantine/asset_cleanup_20260904/audio_sources_retained`(BGM 최종 WAV 등 3.9GB), `work/voice_ja_20260927`(0.96GB), `data_source/audio_source`, `godot/assets/audio`.
- 인트로 영상: `intro/`(210MB), `work/video`(248MB), `godot/assets/video`.
- 빌드: 검증본 r15와 후보 r21 (각 약 0.8GB).
- Codex 작업물: `work/sites_20260920`(1.85GB), `work/sites_20260925_title_pop_v19.tar.gz`, `work/new_chat_recovery_20260926`, `work/quarantine`.
- 게임 자산: `godot/assets/art`, `generated_import`, `runtime_web`는 git에 없거나 빌드에 들어가는 유일한 사본이다. `data_source/art_source`는 원본 마스터다.
- `.git`(2.3GB): 닿지 않는 객체가 2개뿐이라 줄일 것이 없다.
- `godot/.godot`(1.0GB): 임포트 캐시라 지우면 다음 테스트·내보내기 전에 다시 임포트해야 한다.
