# Scenario Format

시나리오는 `id`, `title_key`, `chapter_id`, `commands[]` JSON이다. 모든 표시 텍스트는 localization key다. 명령 ID는 jump target이 될 수 있다.

지원 명령: set_background, set_cg, show_portrait, hide_portrait, set_expression, dialogue, narration, choice, set_flag, check_flag, jump, play_bgm, stop_bgm, play_sfx, play_voice, fade_in, fade_out, wait, start_battle, grant_reward, end_scenario.

Runner는 대사 index, 배경/CG/portrait 상태를 `last_scenario_position`에 저장한다. 읽은 command index만 일반 스킵할 수 있고 전체 스킵은 개발 옵션과 분리한다. voice_path가 없으면 텍스트 진행을 막지 않는다.

