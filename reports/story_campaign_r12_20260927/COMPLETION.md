# 캠페인 개편 r12 — 빌드 정리 기록 (2026-09-27, Claude)

보관 규칙("현재 검증본 + 후보 하나만 남기고, 교체된 빌드는 `_audio/`와 `intro.mp4`를 남긴 채 해시를 기록")에 따라 정리했다.

| 빌드 | 파일 | 크기 | PCK SHA-256 | 처리 |
| --- | --- | --- | --- | --- |
| `web_story_r12_release` (텍스트 전용 후보) | 986 | 691MiB | `09ab14c25513132dfe1580ccc354dd2acb2a6ecff4197898238ce59f00bbc73a` | `_audio/`·`intro.mp4` 보존 후 휴지통 |
| `web_story_r12_devqa` (일회용 개발 QA) | 977 | 694MiB | `070e140fc2ba23321c8ce05f561d22642d81029bc218eb7a7e635145a304c715` | `_audio/`·`intro.mp4`는 위 보존본과 바이트 동일, 휴지통 |
| `web_title_pop_r10_release` (Codex r10) | 736 | 675MiB | `f8bc23d9f14ce920f754ee4e27c8a2c5b3cfcaf37c3a89fcc49c4dae543eeecf` | `_audio/`·`intro.mp4` 보존 후 휴지통 |

- 파일별 경로·크기·해시·이유·보존 사본: `retired_files.jsonl.gz`(2,699행).
- 보존 위치: `quarantine/retired_builds_20260927/<빌드>/`(r12 텍스트 전용 61MB, r10 46MB).
- 남은 빌드: `web_story_r12_release`(현재, PCK `437ceb54f1b226898ee5dd8f1d82d9ae876d27eab713be32fbf641b4363d5598`, 음성 2,857개),
  `web_voice_ja_r11_release`(직전 검증본, PCK `244e9c3178e1df9f3133a5bc85d8ce5363b3ad45c69a8e054ff6baf3239f70aa`).
- 옛 런타임 음성 250개(OGG·`.import`·매니페스트 501개)는 `quarantine/voice_ja_r11_runtime_20260927/`에
  `SHA256SUMS.txt`와 함께 보관했다. 새 목록에 없는 59개 OGG와 `.import`는 보관본과 해시가 같음을 확인한 뒤 런타임 폴더에서 휴지통으로 보냈다.
- 휴지통은 비우지 않았다(복구 가능). 디스크 공간은 휴지통을 비워야 확보된다.
- `qa/`: 1920×1080 화면 밖 렌더 캡처(스토리 장면, 동료·특이 위협·보스·돌발 사건 창, 보스 퇴장·돌발 사건 창 수정 후).
