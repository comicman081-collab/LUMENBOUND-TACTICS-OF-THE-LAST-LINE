# r13 — 작은 가로 화면 스토리 창, 권장 성장 개편 (2026-09-27, Claude)

## 빌드

- 현재: `builds/web_growth_r13_release`
  - PCK SHA-256 `ece5f217abc269e7ec59b1dc5de0538573727233d2f34aa564e84b7e6b02b6a5`
  - 로컬 실행기: `http://127.0.0.1:8770/play/ece5f217abc2/`
- 직전 검증본으로 `builds/web_story_r12_release`를 남겼다.
- 정리한 빌드: `builds/web_voice_ja_r11_release`를 휴지통으로 보냈다(986개 파일).
  - 모든 파일의 해시는 `retired_files.jsonl.gz`에 있다.
  - `_audio/` 309개와 `intro.mp4`는 해시를 확인한 사본을 `quarantine/retired_builds_20260927/web_voice_ja_r11_release/`에 두었다.

## 검증

- **헤드리스 회귀 32개 장면 통과.** 이번에 `tests/growth_economy_runner`를 추가했다.
  - test_runner 308/308
  - r15 54/54
  - 성장 가이드 32/32
  - 성장 경제 9/9
  - 맵 358/358
  - 스토리 UI 25/25
- **정적 검사** 71/71.
- **성장 경제:** 새 게임에서 필수 루트 249개 작전을 차례로 진행하며, 작전마다 권장 성장을 한 번 눌렀다. 모든 작전에서 파티 5명이 레벨·돌파·스킬·무기 모두 권장 프로필에 닿았다. 장 보스 직전에만 눌러도 닿는다.
- **브라우저(QA 샌드박스 저장):**
  - 프롤로그 → 로비 → 1장 지도 흐름을 확인했다.
  - 메뉴의 "권장 성장"이 5명·10단계를 적용했다(크레딧 60,000 → 55,000).
  - 결과 토스트가 정상으로 표시됐다.

## 캡처 (`qa/`)

- `*_growth_before.png` / `*_growth_after.png`: 성장 화면의 권장 성장 카드. 적용 전에는 계획·소모가, 적용 후에는 도달 상태가 보인다.
- `*_menu_before.png` / `*_menu_after.png`: 메뉴 항목과 결과 메시지.
- `story_small/`: 작은 가로 화면 여섯 크기의 스토리 창.
  - `before_fix_*`는 수정 전 353×198에서 AUTO/SKIP과 겹치던 모습이다.
