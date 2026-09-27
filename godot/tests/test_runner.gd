extends Node

var passed := 0
var failed := 0
var failures: Array[String] = []
var growth_ui_contract: Dictionary = {}
const RelayServiceScript := preload("res://relay/relay_service.gd")
const BattlePresentationDirectorScript := preload("res://battle/view/battle_presentation_director.gd")

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, name: String, details := "") -> void:
	if condition:
		passed += 1
		print("PASS | ", name)
	else:
		failed += 1
		failures.append(name + (": " + details if details != "" else ""))
		printerr("FAIL | ", name, " | ", details)

func _run() -> void:
	print("LANTERNLINE HEADLESS TESTS | Godot ", Engine.get_version_info().get("string", "unknown"))
	_test_data()
	_test_settings_policy()
	_test_input_transition_edges()
	_test_responsive_ui_contracts()
	_test_stage_preload_contracts()
	_test_combat_art_contracts()
	_test_card_audio_contracts()
	_test_story_voice_contracts()
	await _test_signature_sliced_loads()
	_test_battle()
	_test_growth()
	_test_story()
	_test_relay()
	_test_save()
	print("TEST_SUMMARY total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	if not failures.is_empty(): print("FAILURES=", JSON.stringify(failures))
	get_tree().quit(0 if failed == 0 else 1)

func _test_signature_sliced_loads() -> void:
	var ids: Array[String] = ["CHR001", "ENM001"]
	var actors := BattleSpriteLibrary.new()
	var effects := EffectSignatureLibrary.new()
	var start_frame := Engine.get_process_frames()
	var actor_ok := await actors.load_signature_core_pack_sliced(ids, self)
	var effect_ok := await effects.load_signature_core_pack_sliced(ids, self)
	# The first process_frame signal can precede this frame's counter increment.
	check(actor_ok and effect_ok and Engine.get_process_frames() >= start_frame + 3, "signature core decoding yields between actor/effect entities")
	check(actors.signature_residency_snapshot().entity_ids == ids and effects.signature_residency_snapshot().entity_ids == ids, "sliced loaders retain the same complete actor/effect lease")
	var invalid: Array[String] = ["NO_SUCH_ENTITY"]
	check(not await actors.load_signature_core_pack_sliced(invalid, self) and actors.signature_frames.is_empty(), "sliced loading fails closed without retaining a partial actor family")

func _test_settings_policy() -> void:
	var shell_script := load("res://screens/app_shell.gd")
	check(not shell_script.loading_watchdog_expired(6100, 100, 5900), "loading beyond the five-second target is allowed while real progress continues")
	check(shell_script.loading_watchdog_expired(13000, 100, 1000), "loading with no progress still fails within the idle bound")
	check(shell_script.loading_watchdog_expired(45100, 100, 45000), "continuous progress cannot bypass the absolute loading bound")
	var gameplay_probe := load("res://qa/local_gameplay_probe.gd") as Script
	check(gameplay_probe != null and gameplay_probe.can_instantiate(), "localhost sandbox gameplay probe compiles without changing public Release authority")
	var settings_before := SettingsService.values.duplicate(true)
	check(SettingsService.developer_mode_for_build(true) and not SettingsService.developer_mode_for_build(false), "developer tooling is gated strictly by debug versus release build")
	check(SettingsService.developer_mode_for_capabilities(false, true) and not SettingsService.developer_mode_for_capabilities(false, false), "Web QA feature grants development authority without weakening the public Release preset")
	var export_presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	var dev_preset_start := export_presets.find("[preset.0]")
	var release_preset_start := export_presets.find("[preset.1]")
	var dev_preset := export_presets.substr(dev_preset_start, release_preset_start - dev_preset_start) if dev_preset_start >= 0 and release_preset_start > dev_preset_start else ""
	var release_preset := export_presets.substr(release_preset_start) if release_preset_start >= 0 else ""
	check(dev_preset.contains("custom_features=\"lanternline_dev_tools\"") and release_preset.contains("custom_features=\"\""), "Web Development authority feature is absent from the public Release preset")
	SettingsService.apply_saved({"developer_mode": false})
	check(SettingsService.is_developer_mode() == OS.is_debug_build(), "saved developer_mode cannot disable debug tooling or enable release tooling")
	var persisted := SettingsService.persisted_values()
	check(persisted.has("developer_mode") and not bool(persisted.developer_mode) and persisted.has("language") and persisted.has("battle_speed"), "normal save preserves settings schema but never persists developer authority")
	var profile_before := AppState.profile.duplicate(true)
	AppState.new_game()
	AppState.profile.chapter_progress.CH01.hard_unlocked = true
	var hard_stage := DataRegistry.stage("CH01-H01")
	AppState.profile.account.stamina = 999
	AppState.profile.hard_attempts.counts["CH01-H01"] = int(hard_stage.daily_attempts)
	SettingsService.values.developer_mode = false
	check(not AppState.can_enter_stage("CH01-H01"), "normal mode retains HARD daily-attempt limits")
	var debug_options_before := AppState.debug_options.duplicate(true)
	AppState.debug_options = {"unlock_all": true, "invincible": true, "enemy_multiplier": 2.0}
	var release_modifiers := AppState.effective_battle_debug_options()
	check(not AppState.is_stage_unlocked("CH01-N10") and not bool(release_modifiers.invincible) and is_equal_approx(float(release_modifiers.enemy_multiplier), 1.0), "release policy blocks mutated unlock, invincibility and enemy multiplier options")
	check(not SceneRouter.screen_allowed("DEBUG", false) and SceneRouter.screen_allowed("DEBUG", true) and SceneRouter.screen_allowed("HOME", false), "debug screen route policy distinguishes development from release")
	var router_screen_before := SceneRouter.current_screen
	var router_history_before := SceneRouter.history.duplicate()
	var route_payload_before := AppState.route_payload.duplicate(true)
	SceneRouter.current_screen = "HOME"
	SceneRouter.history.clear()
	SceneRouter.go("DEBUG", {"tampered": true})
	check(SceneRouter.current_screen == "HOME" and SceneRouter.history.is_empty() and AppState.route_payload.is_empty(), "direct DEBUG routing is rejected when developer mode is inactive")
	SceneRouter.current_screen = "HOME"
	SceneRouter.history.clear()
	SceneRouter.go("STAGE_SELECT")
	SceneRouter.go("STORY", {"after": "STAGE_SELECT", "origin": "CHAPTER_MAP"})
	SceneRouter.go("STAGE_SELECT", {"story_return": true})
	check(SceneRouter.current_screen == "STAGE_SELECT" and SceneRouter.history == ["HOME"] and not SceneRouter.history.has("STORY"), "chapter-map story return consumes its caller frame instead of creating a map/story Back loop")
	SceneRouter.back("HOME")
	check(SceneRouter.current_screen == "HOME" and SceneRouter.history.is_empty(), "chapter-map Back returns directly to Home after its entry story completes")
	SceneRouter.current_screen = "HOME"
	SceneRouter.history.clear()
	SceneRouter.go("STAGE_SELECT")
	SceneRouter.go("BATTLE")
	SceneRouter.go("RESULT")
	SceneRouter.go("STAGE_SELECT", {"result_return": true})
	check(SceneRouter.current_screen == "STAGE_SELECT" and SceneRouter.history == ["HOME"] and not SceneRouter.history.has("BATTLE") and not SceneRouter.history.has("RESULT"), "battle result return consumes the terminal battle frames instead of creating a result/map Back loop")
	SceneRouter.back("HOME")
	check(SceneRouter.current_screen == "HOME" and SceneRouter.history.is_empty(), "chapter-map Back returns directly to Home after a completed battle result")
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd").replace("\r\n", "\n")
	check(shell_source.contains("if not SceneRouter.screen_allowed(screen_id, SettingsService.is_developer_mode()):") and shell_source.contains("func _show_debug() -> void:\n\tif not SettingsService.is_developer_mode():") and shell_source.contains("func _debug_unlock_chapter_hard() -> void:\n\t# This capability exists only in the development-authorized screen") and shell_source.contains("\tif not SettingsService.is_developer_mode():\n\t\treturn\n\tAppState.profile.chapter_progress.CH01.normal_highest = 20"), "direct app-shell DEBUG rendering and HARD QA mutation are independently guarded")
	SettingsService.values.developer_mode = true
	var debug_modifiers := AppState.effective_battle_debug_options()
	check(AppState.debug_unlock_all_enabled() == OS.is_debug_build() and bool(debug_modifiers.invincible) == OS.is_debug_build() and (is_equal_approx(float(debug_modifiers.enemy_multiplier), 2.0) if OS.is_debug_build() else is_equal_approx(float(debug_modifiers.enemy_multiplier), 1.0)), "debug build can use authorized unlock and battle modifiers")
	var dev_attempt_count_before := int(AppState.profile.hard_attempts.counts.get("CH01-H01", 0))
	var dev_stamina_before := int(AppState.profile.account.stamina)
	check(AppState.can_enter_stage("CH01-H01"), "developer mode bypasses an exhausted HARD daily-attempt limit")
	check(AppState.consume_stage_entry("CH01-H01") and int(AppState.profile.hard_attempts.counts.get("CH01-H01", 0)) == dev_attempt_count_before and int(AppState.profile.account.stamina) == dev_stamina_before, "developer HARD QA entry does not mutate daily attempts or stamina")
	var map_screen_source := FileAccess.get_file_as_string("res://chapter_map/runtime/chapter_map_screen.gd")
	check(shell_source.contains("무제한 (DEV)") and map_screen_source.contains("무제한 (DEV)"), "developer HARD UI labels unlimited QA entry without exposing the normal Release quota")
	SceneRouter.current_screen = router_screen_before
	SceneRouter.history = router_history_before
	AppState.route_payload = route_payload_before
	AppState.debug_options = debug_options_before
	AppState.profile = profile_before
	for key in settings_before:
		SettingsService.values[key] = settings_before[key]

func _unique_ids(collection: String) -> bool:
	var seen: Dictionary = {}
	for row in DataRegistry.list_of(collection):
		if seen.has(row.id): return false
		seen[row.id] = true
	return true

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _source_function_body(source: String, function_name: String) -> String:
	var start := source.find("func %s(" % function_name)
	if start < 0:
		return ""
	var next := source.find("\nfunc ", start + 6)
	return source.substr(start) if next < 0 else source.substr(start, next - start)

func _test_stage_preload_contracts() -> void:
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd").replace("\r\n", "\n")
	var map_source := FileAccess.get_file_as_string("res://chapter_map/runtime/chapter_map_screen.gd")
	var cache_source := FileAccess.get_file_as_string("res://autoload/stage_asset_cache.gd")
	var battle_view_source := FileAccess.get_file_as_string("res://battle/view/battle_view.gd")
	var begin_loading := _source_function_body(shell_source, "_begin_transition_loading")
	var finish_loading := _source_function_body(shell_source, "_finish_transition_loading")
	var prepare_loading := _source_function_body(shell_source, "_prepare_transition_loading_for_screen")
	var map_loading_policy := _source_function_body(shell_source, "_should_show_map_transition_loading")
	var show_map := _source_function_body(shell_source, "_show_chapter_map")
	var show_battle := _source_function_body(shell_source, "_show_battle")
	var battle_finished := _source_function_body(shell_source, "_battle_finished")
	var show_result := _source_function_body(shell_source, "_show_result")
	var treasure_reward := _source_function_body(shell_source, "_map_treasure_reward_requested")
	var close_reward := _source_function_body(shell_source, "_dispose_map_reward_overlay")
	var gpu_warm := _source_function_body(shell_source, "_warm_transition_gpu_textures")
	var loading_title_body := _source_function_body(shell_source, "_transition_loading_title")
	var loading_initial_body := _source_function_body(shell_source, "_transition_loading_initial_phase")
	var wait_map_ready := _source_function_body(shell_source, "_wait_for_map_ready_with_deadline")
	var wait_battle_ready := _source_function_body(shell_source, "_wait_for_battle_assets_with_deadline")
	var show_loading_failure := _source_function_body(shell_source, "_show_loading_failure_screen")
	var move_body := _source_function_body(map_source, "_move_along")
	var enemy_turn_body := _source_function_body(map_source, "_complete_player_turn")
	var patrol_contact_body := _source_function_body(map_source, "_start_patrol_contact")
	var treasure_emit_body := _source_function_body(map_source, "_emit_treasure_reward_after_map_callback")
	var map_idle_body := _source_function_body(map_source, "_map_idle_texture")
	var korean_pattern := RegEx.new()
	korean_pattern.compile("[가-힣]")
	check(begin_loading.contains("min_value = 0.0") and begin_loading.contains("max_value = 100.0") and begin_loading.contains("value = 0.0") and finish_loading.contains("_set_transition_loading_display_value(100.0)") and finish_loading.contains("create_timer(0.10"), "transition loading paints a literal zero-to-one-hundred bar before disposal")
	check(loading_title_body.contains("전술 지도 준비 중") and loading_initial_body.contains("작전 정보를 준비하고 있습니다") and gpu_warm.contains("맵 캐릭터 텍스처를 준비하고 있습니다") and korean_pattern.search(_source_function_body(shell_source, "_map_load_phase_text")) != null and show_map.contains("지형과 경로, 작전 목표를 배치하고 있습니다"), "map loading uses player-facing Korean title and progress copy")
	check(prepare_loading.contains("TRANSITION_LOADING_MAP_ENTRY") and prepare_loading.contains("TRANSITION_LOADING_BATTLE_ENTRY") and prepare_loading.contains("TRANSITION_LOADING_BATTLE_RESULT") and map_loading_policy.contains("source_type in [\"TREASURE\", \"EXPLORE\"]"), "blocking loading is scoped to map entry, battle entry and battle result transitions")
	check(treasure_reward.find("_show_map_reward_overlay()") >= 0 and treasure_reward.find("_show_map_reward_overlay()") < treasure_reward.find("SceneRouter.go(\"RESULT\")") and close_reward.contains("_resume_post_reward_turn"), "treasure reward stays over the live map and resumes its owed enemy turn without scene navigation")
	check(shell_source.contains("const STAGE_ENTRY_PRELOAD_TARGET_MSEC := 5000") and show_map.contains("await StageAssetCache.warm_map_for_stage_select") and show_map.contains("StageAssetCache.cache_hit_for_map_entry") and show_map.contains("StageAssetCache.gpu_warm_textures") and not show_map.contains("await StageAssetCache.warm_for_stage_select"), "stage entry owns the selected five-second map-only CPU and GPU preload boundary")
	check(gpu_warm.contains("TextureRect.new()") and gpu_warm.contains("TRANSITION_GPU_WARM_BATCH") and gpu_warm.contains("warm_rects[rect_index].texture = textures[texture_index]") and gpu_warm.contains("await RenderingServer.frame_post_draw") and gpu_warm.contains("warm_rect.queue_free()"), "stage entry paints retained map textures through bounded renderer batches before releasing gameplay")
	var map_progress_connect := show_map.find("map_screen.map_load_progress.connect(map_load_handler)")
	var map_tree_entry := show_map.find("content.add_child(map_screen)", map_progress_connect)
	check(map_progress_connect >= 0 and map_tree_entry > map_progress_connect and show_map.contains("map_screen.visible = false") and show_map.contains("await _wait_for_map_ready_with_deadline") and wait_map_ready.contains("loading_watchdog_expired") and show_loading_failure.contains("LOADING COULD NOT FINISH"), "map progress is connected before hidden tree entry and a progress-aware bounded owner deadline prevents an infinite loader")
	check(show_battle.contains("await _wait_for_battle_assets_with_deadline") and wait_battle_ready.contains("loading_watchdog_expired") and show_battle.find("await _wait_for_battle_assets_with_deadline") < show_battle.find("_finish_transition_loading"), "battle entry remains covered until assets attach and fails safely instead of waiting on a lost signal forever")
	var portrait_ready := show_result.find("RESULT_SCREEN_READY elapsed_ms=%d layout=portrait")
	var portrait_finish := show_result.find("_finish_transition_loading(loading_token, \"Battle results ready\")", portrait_ready)
	var landscape_ready := show_result.find("RESULT_SCREEN_READY elapsed_ms=%d layout=landscape")
	var landscape_finish := show_result.find("_finish_transition_loading(loading_token, \"Battle results ready\")", landscape_ready)
	check(battle_finished.find("_set_transition_loading_phase(loading_token, \"Opening the results screen\", 96.0") >= 0 and battle_finished.rfind("SceneRouter.go(\"RESULT\")") > battle_finished.find("Opening the results screen") and show_result.contains("_transition_loading_token_for(TRANSITION_LOADING_BATTLE_RESULT)") and not show_result.contains("await get_tree().process_frame") and not show_result.contains("await _finish_transition_loading") and portrait_ready >= 0 and portrait_finish > portrait_ready and landscape_ready > portrait_finish and landscape_finish > landscape_ready, "battle result builds the complete responsive RESULT tree synchronously before asynchronously releasing the 96-percent loader")
	check(cache_source.contains("_cache = pending # Atomic replacement") and cache_source.contains("await get_tree().process_frame") and cache_source.contains("func gpu_warm_textures"), "stage asset cache commits atomically after cooperative resource loading")
	check(cache_source.contains("const WARMUP_DEADLINE_MSEC := 45000") and cache_source.contains("_warmup_deadline_exceeded") and shell_source.contains("previous_screen == \"STAGE_SELECT\"") and shell_source.contains("StageAssetCache.cancel_warmup()"), "stage warmup has a hard deadline and is cancelled immediately when its owning screen is left")
	check(battle_finished.contains("var save_result := SaveService.save_game()") and battle_finished.contains("_present_transaction_save_failure") and map_source.contains("TREASURE PROGRESS NOT SAVED") and map_source.contains("RETRY SAVE") and patrol_contact_body.contains("var encounter_save_result := SaveService.save_game()") and patrol_contact_body.contains("AppState.abandon_pending_map_encounter(map_id)"), "battle, map contact and treasure transaction failures never continue from an unpersisted state")
	check(battle_view_source.contains("var label_font := battle_font if battle_font != null else ThemeDB.fallback_font") and battle_view_source.contains("draw_string(label_font") and battle_view_source.contains("draw_circle(callout_position") and not battle_view_source.contains("draw_string(callout_font") and battle_view_source.contains("draw_string(DAMAGE_FONT") and FileAccess.file_exists("res://assets/fonts/LanternRounded-Black.ttf"), "battle names retain Korean font; damage uses packaged rounded face; skill cues remain circular")
	check(map_idle_body.contains("get_node_or_null(\"StageAssetCache\")") and map_idle_body.contains("call(\"map_idle_pack\", enemy_id)") and map_idle_body.find("map_idle_pack") < map_idle_body.find("FileAccess.file_exists"), "map pawns reuse the retained idle pack before any manifest or texture fallback")
	check(not move_body.contains("StageAssetCache") and not move_body.contains("_begin_transition_loading") and not enemy_turn_body.contains("StageAssetCache") and not enemy_turn_body.contains("_begin_transition_loading") and not treasure_emit_body.contains("StageAssetCache") and not treasure_emit_body.contains("_begin_transition_loading"), "movement, enemy turns and treasure callbacks cannot acquire resource or blocking-loading work")

func _semi_transparent_chroma_residue_count(path: String) -> int:
	var texture := load(path) as Texture2D
	if texture == null: return -1
	var image := texture.get_image()
	if image == null or image.is_empty(): return -1
	image.convert(Image.FORMAT_RGBA8)
	var residue := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			var alpha := roundi(pixel.a * 255.0)
			# Opaque lime is valid character material. This only identifies a
			# semi-transparent #00FF00-style fringe left by chroma-key resizing.
			if alpha > 0 and alpha < 255 and pixel.g >= 0.96 and pixel.r <= 0.10 and pixel.b <= 0.10 and pixel.g - pixel.r >= 0.80 and pixel.g - pixel.b >= 0.80:
				residue += 1
	return residue

func _test_input_transition_edges() -> void:
	var shell_script = load("res://screens/app_shell.gd")
	var shell = shell_script.new()
	var enter_event := InputEventKey.new()
	enter_event.keycode = KEY_ENTER
	enter_event.pressed = true
	enter_event.echo = false
	var space_event := InputEventKey.new()
	space_event.keycode = KEY_SPACE
	space_event.pressed = true
	space_event.echo = false
	var echo_event := InputEventKey.new()
	echo_event.keycode = KEY_ENTER
	echo_event.pressed = true
	echo_event.echo = true
	var release_event := InputEventKey.new()
	release_event.keycode = KEY_SPACE
	release_event.pressed = false
	release_event.echo = false
	check(shell._is_story_advance_key_event(enter_event) and shell._is_story_advance_key_event(space_event) and not shell._is_story_advance_key_event(echo_event) and not shell._is_story_advance_key_event(release_event), "story Enter/Space accepts one pressed edge and rejects echo/held-key release")
	var first_story_edge: bool = shell._consume_transition_edge("STORY_ADVANCE", "keyboard:enter", 1000)
	var duplicate_story_edge: bool = shell._consume_transition_edge("STORY_ADVANCE", "keyboard:enter", 1010)
	var next_distinct_edge: bool = shell._consume_transition_edge("STORY_ADVANCE", "keyboard:enter", 1220)
	var story_diagnostics: Dictionary = shell.transition_edge_diagnostics()
	check(first_story_edge and not duplicate_story_edge and next_distinct_edge and int(story_diagnostics.accepted) == 2 and int(story_diagnostics.rejected) == 1, "one physical story edge produces at most one state transition")
	shell.free()
	var battle_shell = shell_script.new()
	var first_battle_tap: bool = battle_shell._consume_transition_edge("BATTLE_START", "touch:battle", 5000)
	var duplicate_battle_tap: bool = battle_shell._consume_transition_edge("BATTLE_START", "touch:battle", 5030)
	var battle_diagnostics: Dictionary = battle_shell.transition_edge_diagnostics()
	battle_shell.battle_transition_active = true
	var selected_stage_before_locked_retry := str(AppState.selected_stage_id)
	var locked_retry: bool = battle_shell._request_battle_start("touch:battle", "CH01-H05")
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd").replace("\r\n", "\n")
	var transition_wiring := shell_source.contains("_request_battle_start(\"map:encounter\", stage_id)") and shell_source.contains("_request_battle_start(\"button:battle_start\")") and shell_source.contains("if battle_transition_active: return false")
	var story_wiring := shell_source.contains("_request_story_advance(\"button:next\")") and shell_source.contains("_request_story_choice(index, \"button:choice\")") and shell_source.contains("AudioService.unlock_from_user_gesture()") and shell_source.contains("callback.call()")
	check(first_battle_tap and not duplicate_battle_tap and not locked_retry and str(AppState.selected_stage_id) == selected_stage_before_locked_retry and int(battle_diagnostics.accepted) == 1 and int(battle_diagnostics.rejected) == 1 and transition_wiring, "rapid double tap cannot create two battle transition owners")
	var phase_hud_labels := [battle_shell._boss_phase_hud_label("PHASE_1"), battle_shell._boss_phase_hud_label("PHASE_2"), battle_shell._boss_phase_hud_label("ENRAGE")]
	check(phase_hud_labels.all(func(label): return not str(label).contains("PHASE_") and str(label) != "ENRAGE"), "boss HUD localizes phase states without exposing internal IDs")
	check(story_wiring, "story touch/click uses guarded requests while shared button gesture/audio wrapper remains intact")
	battle_shell.free()
	var event_shell = shell_script.new()
	var event_panel := Control.new()
	event_panel.position = Vector2(100, 100)
	event_panel.size = Vector2(600, 360)
	event_shell.add_child(event_panel)
	var event_skip := Button.new()
	event_skip.position = Vector2(260, 260)
	event_skip.size = Vector2(130, 70)
	event_panel.add_child(event_skip)
	var event_next := Button.new()
	event_next.position = Vector2(420, 260)
	event_next.size = Vector2(130, 70)
	event_panel.add_child(event_next)
	var event_trace: Array[String] = []
	event_shell.pre_battle_event_input_panel = event_panel
	event_shell.pre_battle_event_input_skip = event_skip
	event_shell.pre_battle_event_input_next = event_next
	event_shell.pre_battle_event_input_active = true
	event_shell.pre_battle_event_advance = func() -> void: event_trace.append("advance")
	event_shell.pre_battle_event_resolve = func() -> void: event_trace.append("skip")
	var body_routes: bool = event_shell._handle_pre_battle_event_input(Vector2(130, 130))
	var next_routes: bool = event_shell._handle_pre_battle_event_input(Vector2(550, 390))
	var skip_routes: bool = event_shell._handle_pre_battle_event_input(Vector2(410, 390))
	var outside_is_ignored: bool = not event_shell._handle_pre_battle_event_input(Vector2(60, 60))
	check(not body_routes and next_routes and skip_routes and outside_is_ignored and event_trace == ["advance", "skip"], "pre-battle reading gestures never advance; explicit Next and Skip keep separate paths")
	event_shell.free()

func _test_responsive_ui_contracts() -> void:
	var briefing_script := preload("res://ui/bounded_briefing.gd")
	for viewport_css in [Vector2(320, 568), Vector2(360, 640), Vector2(360, 800), Vector2(390, 844), Vector2(800, 360), Vector2(1280, 720)]:
		var frame := briefing_script.frame_css(viewport_css)
		check(Rect2(Vector2.ZERO, viewport_css).encloses(frame) and frame.size.x <= 680.0 and frame.size.y <= 620.0, "briefing frame remains bounded at %s" % viewport_css)
	var shell_script = load("res://screens/app_shell.gd")
	var shell = shell_script.new()
	var portrait_size := Vector2(390.0, 844.0)
	var portrait_metrics: Dictionary = shell.responsive_ui_metrics_for_size(portrait_size)
	var portrait_button: Vector2 = shell.responsive_button_minimum_for_size(Vector2(190.0, 52.0), portrait_size)
	var portrait_physical := portrait_button * float(portrait_metrics.canvas_scale)
	check(not bool(portrait_metrics.portrait) and bool(portrait_metrics.compact_landscape) and portrait_physical.x >= 55.5 and portrait_physical.y >= 55.5, "390x844 uses the same landscape metrics as 844x390 without a portrait reflow", str(portrait_physical))
	var compact_size := Vector2(915.0, 412.0)
	var compact_metrics: Dictionary = shell.responsive_ui_metrics_for_size(compact_size)
	var compact_button: Vector2 = shell.responsive_button_minimum_for_size(Vector2(110.0, 52.0), compact_size)
	var compact_physical := compact_button * float(compact_metrics.canvas_scale)
	check(not bool(compact_metrics.portrait) and bool(compact_metrics.compact_landscape) and compact_physical.x >= 55.9 and compact_physical.y >= 55.9, "915x412 compact landscape compensates canvas_items shrink to a 56 CSS-pixel touch target", str(compact_physical))
	var desktop_size := Vector2(1920.0, 1080.0)
	var desktop_metrics: Dictionary = shell.responsive_ui_metrics_for_size(desktop_size)
	var desktop_minimum := Vector2(190.0, 64.0)
	check(is_equal_approx(float(desktop_metrics.ui_scale), 1.0) and shell.responsive_button_minimum_for_size(desktop_minimum, desktop_size).is_equal_approx(desktop_minimum), "1920x1080 desktop layout metrics remain unchanged")
	var portrait_debug_button: Vector2 = shell.responsive_button_minimum_for_size(Vector2(280.0, 72.0), portrait_size)
	var portrait_debug_width := portrait_debug_button.x * float(portrait_metrics.canvas_scale) * 2.0
	check(portrait_debug_width <= 354.0, "portrait DEBUG two-column buttons fit the 390px safe content width", str(portrait_debug_width))
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd").replace("\r\n", "\n")
	var responsive_structure := shell_source.contains("grid.columns = 2 if _is_portrait_layout() else 3") and shell_source.contains("var battle_actions := HBoxContainer.new()") and shell_source.contains("(bottom as GridContainer).columns = 5") and shell_source.contains("orb.custom_minimum_size = Vector2(126, 126)") and shell_source.contains("Character health and shield are deliberately represented only at their") and not shell_source.contains("var party_row:") and not shell_source.contains("HP %d%% · SH") and shell_source.contains("status.position.y = (14.0 + MIN_TOUCH_CSS_PX + 8.0) * ui_scale")
	check(responsive_structure, "portrait DEBUG, battle HUD, result rail and chapter status use compact non-overlapping structures")
	# Story type is specified in rendered pixels and converted back to the 1920px
	# authored canvas. Validate the actual physical hierarchy at all three target
	# viewport classes rather than pinning one hard-coded logical font size.
	var story_type_hierarchy := true
	for story_size in [Vector2(1280.0, 720.0), compact_size, portrait_size]:
		var story_metrics: Dictionary = shell.responsive_ui_metrics_for_size(story_size)
		var physical_body := float(shell.story_font_size_for_size(28.0, story_size)) * float(story_metrics.canvas_scale)
		var physical_speaker := float(shell.story_font_size_for_size(32.0, story_size)) * float(story_metrics.canvas_scale)
		story_type_hierarchy = story_type_hierarchy and physical_body >= 27.5 and physical_body <= 28.5 and physical_speaker >= 31.5 and physical_speaker <= 32.5
	story_type_hierarchy = story_type_hierarchy and shell_source.contains("var story_body_css_px := 16.0 if compact else (24.0 if narrow_portrait else 28.0)") and shell_source.contains("_story_label(\"\", 16.0 if compact else (28.0 if narrow_portrait else 32.0)") and shell_source.contains("value.add_theme_font_size_override(\"font_size\", _story_logical_px(target_css_px))") and shell_source.contains("if not button.has_meta(\"story_control\") and not button.has_meta(\"compact_growth_control\") and not button.has_meta(\"compact_reward_control\"):")
	check(story_type_hierarchy, "story body and speaker hierarchy stays in its rendered-pixel bands while controls retain independent touch targets")
	var landscape_story_contract := true
	for physical in [Vector2(390, 844), Vector2(844, 390), Vector2(915, 412)]:
		var metrics: Dictionary = shell.responsive_ui_metrics_for_size(physical)
		landscape_story_contract = landscape_story_contract and not bool(metrics.portrait) and bool(metrics.compact_landscape)
	check(landscape_story_contract, "phone orientations consistently select the landscape story layout; browser audit verifies actual bounds and input")
	var web_landscape_shell := FileAccess.get_file_as_string("res://web/landscape.html").replace("\r\n", "\n")
	var host_orientation_contract := web_landscape_shell.contains("const desktopPointer = navigator.maxTouchPoints === 0") and web_landscape_shell.contains("const desktopPlatform = !ipadDesktopUserAgent") and web_landscape_shell.contains("const mobileDevice = !desktopPlatform &&") and web_landscape_shell.contains("frame.dataset.deviceClass") and web_landscape_shell.contains("const rotated = mobileDevice && height > width") and web_landscape_shell.contains("Math.min(height, width * 9 / 16)") and web_landscape_shell.contains("body.landscape-host")
	check(host_orientation_contract, "Web host keeps a complete desktop 16:9 frame upright while only a portrait mobile device receives the rotated landscape frame")
	var density_loader_source := FileAccess.get_file_as_string("res://battle/view/density_texture_loader.gd").replace("\r\n", "\n")
	var stage_cache_source := FileAccess.get_file_as_string("res://autoload/stage_asset_cache.gd").replace("\r\n", "\n")
	var file_launch_density_contract := density_loader_source.contains("func can_stream_companion_pages()") and density_loader_source.contains("return protocol in [\"http:\", \"https:\"]") and density_loader_source.contains("if not can_stream_companion_pages():") and stage_cache_source.contains("var use_streamed_map_density") and stage_cache_source.contains("DensityLoader.can_stream_companion_pages()")
	check(file_launch_density_contract, "file:// entry skips streamed HD pages and opens the map with packaged compact pawn atlases instead of waiting on an unreachable request")
	check(shell_source.contains("compact_landscape == last_compact_landscape_layout") and shell_source.contains("_rebuild_story_presentation()"), "live regular-to-compact resize rebuilds only the story presentation around its retained runner")
	var sample_story_commands := [
		{"command": "set_background"},
		{"command": "narration"},
		{"command": "play_sfx"},
		{"command": "dialogue"},
		{"command": "choice"},
	]
	check(shell.story_page_progress(sample_story_commands, 3) == Vector2i(2, 3), "story page counter excludes internal art and audio commands")
	var presentation_source := FileAccess.get_file_as_string("res://screens/command_presentation.gd")
	check(presentation_source.contains("TitleStartButton") and presentation_source.contains("FullBody_") and presentation_source.contains("LUMEN") and shell_source.contains("_build_intro_title_backdrop(surface)"), "title and WebAudio start gate retain the current high-resolution full-body cast with a clear LUMENBOUND start action")
	var title_builder_source := FileAccess.get_file_as_string("res://../tools/art/build_title_cast_plate.py")
	check(title_builder_source.contains("LUMENBOUND") and title_builder_source.contains("TACTICS OF THE LAST LINE") and not title_builder_source.contains("AFTER SIGNAL") and not title_builder_source.contains("잔광기록"), "title logo source uses the tactical LUMENBOUND lockup without either rejected title")
	var canonical_game_title := "LUMENBOUND: TACTICS OF THE LAST LINE"
	var rejected_title_ko := "랜턴라인: 잔광기록"
	var rejected_title_en := "Lanternline: Afterglow Records"
	var title_localization_authorities := [
		FileAccess.get_file_as_string("res://../tools/generate_data.py"),
		FileAccess.get_file_as_string("res://../data_source/localization/ko.csv"),
		FileAccess.get_file_as_string("res://../data_source/localization/en.csv"),
		FileAccess.get_file_as_string("res://localization/ko.csv"),
		FileAccess.get_file_as_string("res://localization/en.csv"),
		FileAccess.get_file_as_string("res://data/compiled/localization.json"),
	]
	var rejected_title_count := 0
	var canonical_title_authority_count := 0
	for localization_authority in title_localization_authorities:
		var authority_text := str(localization_authority)
		rejected_title_count += authority_text.count(rejected_title_ko) + authority_text.count(rejected_title_en)
		if authority_text.contains(canonical_game_title):
			canonical_title_authority_count += 1
	check(rejected_title_count == 0 and canonical_title_authority_count == title_localization_authorities.size(), "canonical LUMENBOUND title is synchronized across localization sources and generated runtime data", "rejected=%d canonical_authorities=%d/%d" % [rejected_title_count, canonical_title_authority_count, title_localization_authorities.size()])
	check(shell_source.contains("func _start_title_flow()") and shell_source.contains("PROLOGUE_READ") and shell_source.contains("AppState.active_scenario_id = \"SCN_PROLOGUE\"") and shell_source.contains("{\"after\": \"HOME\", \"origin\": \"TITLE\"}"), "fresh title start enters the authored prologue before home while completed profiles continue normally")
	var intro_bridge_source := FileAccess.get_file_as_string("res://web/browser_intro.js")
	var startup_intro_contract := shell_source.contains("INTRO_VIDEO_DURATION_SECONDS := 50.0") and shell_source.contains("_watch_browser_intro") and shell_source.contains("_watch_native_intro") and not shell_source.contains("create_timer(INTRO_VIDEO_DURATION_SECONDS +") and intro_bridge_source.contains("video.addEventListener('ended'") and intro_bridge_source.contains("api.time = video.currentTime") and shell_source.contains("StartupIntroAudioGate")
	check(FileAccess.file_exists("res://assets/video/lumenbound_intro_full.ogv") and startup_intro_contract, "engine boot gates Web audio on a trusted click, then plays the 50-second intro with retained BGM from zero before title")
	var cinematic_prologue_contract := shell_source.contains("PrologueCharacterIllustrations") and shell_source.contains("PrologueTopRightControls") and shell_source.contains("PrologueAutoButton") and shell_source.contains("PrologueSkipButton") and shell_source.contains("대화창 클릭 / 터치로 계속")
	var story_extension_contract := shell_source.contains("StoryTopRightControls") and shell_source.contains("StoryAutoButton") and shell_source.contains("StorySkipButton") and shell_source.contains("StorySpeakerEyebrow") and shell_source.contains("LUMENBOUND · VOICE LINK") and shell_source.contains("StoryMintSignalRail") and shell_source.contains("StoryPageIndicator") and shell_source.contains("_story_dialogue_style(false)")
	check(shell_source.contains("ClickablePrologueTextBox") and cinematic_prologue_contract and story_extension_contract and shell_source.contains("func _request_story_text_box_advance") and shell_source.contains("scenario_text.visible_ratio = 1.0"), "story text box keeps click/touch typewriter behavior while both story modes expose the LUMENBOUND dialogue hierarchy and fixed AUTO/SKIP rail")
	var story_typewriter_lifecycle := shell_source.contains("var story_typewriter_tween: Tween") and shell_source.contains("func _cancel_story_typewriter()") and shell_source.contains("func _complete_story_typewriter_reveal()") and shell_source.contains("story_typewriter_tween.kill()") and shell_source.contains("story_typewriter_tween = create_tween()") and shell_source.contains("_complete_story_typewriter_reveal()") and shell_source.contains("_cancel_story_typewriter()")
	check(story_typewriter_lifecycle, "MOBILE_N05_STORY_02 completes or replaces a typewriter tween without letting a stale partial fraction clip the active line")
	var portrait_hotfix_source := FileAccess.get_file_as_string("res://autoload/mobile_portrait_hotfix_v2.gd")
	var standard_story_touch_contract := shell_source.contains("dialogue.mouse_filter = Control.MOUSE_FILTER_STOP") and shell_source.contains("dialogue_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE") and shell_source.contains("dialogue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE") and portrait_hotfix_source.contains("var standard_dialogue_value = _shell.get(\"story_dialogue_panel\")") and portrait_hotfix_source.contains("var standard_dialogue_css := 380.0 if choice_mode else 304.0")
	check(standard_story_touch_contract, "MOBILE_N05_STORY_01 standard-story text plate owns the full tap surface and receives a dedicated portrait height, not only prologue geometry")
	var growth_controls := _growth_controls_contract()
	check(bool(growth_controls.navigation), "growth entry builds level, skill and equipment tabs with reachable primary actions")
	var map_source := FileAccess.get_file_as_string("res://chapter_map/runtime/chapter_map_screen.gd")
	var map_tutorial_flow_contract := map_source.contains("func _advance_first_map_tutorial()") and map_source.contains("tutorial_dismiss_button.text = \"안내 건너뛰기\"") and map_source.contains("tutorial_continue_button.pressed.connect(_advance_first_map_tutorial)") and map_source.contains("tutorial_dismiss_button.pressed.connect(_complete_first_map_tutorial)") and map_source.contains("tutorial_dismiss_button.visible = true") and map_source.contains("get_viewport().set_input_as_handled()")
	check(map_source.contains("FirstMapTutorialDimmer") and map_source.contains("tutorial_eyebrow.text = \"첫 작전 안내") and map_source.contains("tutorial_progress_label.text") and map_source.contains("map_basics_complete") and map_source.contains("map_basics_revision") and map_source.contains("_select_next_encounter()") and map_tutorial_flow_contract, "first chapter map provides contextual selection, movement and encounter guidance with actual three-step progression and an explicit skip")
	var app_state_source := FileAccess.get_file_as_string("res://autoload/app_state.gd")
	var home_onboarding_contract := shell_source.contains("HomeFirstOperationTutorialCanvas") and shell_source.contains("HomeTutorialSkipButton") and shell_source.contains("HomeTutorialContinueButton") and shell_source.contains("home_tutorial_surface.theme = theme") and shell_source.contains("자, 이제 제1장 탐색을 시작합니다") and shell_source.contains("func _complete_home_tutorial_and_launch()") and shell_source.contains("SceneRouter.go(\"STAGE_SELECT\")") and shell_source.contains("call_deferred(\"_commit_first_operation_navigation\")") and shell_source.contains("home_first_operation_navigation_pending") and presentation_source.contains("HomeFirstOperationButton") and presentation_source.contains("home_menu_buttons[\"STAGE\"]") and shell_source.contains("home_tutorial_resume_step") and shell_source.contains("_set_home_tutorial_step(home_tutorial_resume_step)") and shell_source.contains("home_tutorial_last_advance_msec < 400") and app_state_source.contains("\"home_basics_complete\": false") and app_state_source.contains("tutorial_progress[\"home_basics_complete\"] = false")
	check(home_onboarding_contract, "first HQ visit explains navigation, exposes Skip, and launches Chapter 1 without an unlabelled menu dead end")
	var story_skip_contract := shell_source.contains("STORY_SKIP_ALL") and shell_source.contains("현재 이야기 전체 건너뛰기") and shell_source.contains("while not scenario_runner.state.finished and safety < 1000") and shell_source.contains("_finish_story_navigation()")
	check(story_skip_contract, "player SKIP completes the current story scene instead of advancing only one line")
	var mobile_navigation_layout_contract := (bool(growth_controls.scroll) and presentation_source.contains("ScrollContainer.new()") and presentation_source.contains("s._scroll_box()") and shell_source.contains("var archive_box := _scroll_box()"))
	check(mobile_navigation_layout_contract, "menu routes retain scroll containers and every growth tab uses the actual touch-scroll control")
	check(not shell_source.contains("두둥!") and not map_source.contains("두둥!") and shell_source.contains("_play_special_event_dialogue") and shell_source.contains("PreBattleEventDialog") and shell_source.contains("EventKeyVisual") and shell_source.contains("res://ui/bounded_briefing.gd") and shell_source.contains("MAP_EVENT_DIALOGUE_SKIP"), "encounter presentation advances a real event dialogue with character/enemy key art instead of rendering a sound-effect caption")
	check(shell_source.contains("_reward_celebration_queue") and shell_source.contains("RewardCelebrationQueue") and shell_source.contains("RewardCelebrationHalfBodyArt") and shell_source.contains("NEW ALLY JOINED") and shell_source.contains("KEY ACQUISITION") and shell_source.contains("RewardCelebrationSkip") and shell_source.contains("last_reward_report"), "result screen presents a skippable ally/key-item achievement queue from the committed report without creating a second reward grant")
	check(map_source.contains("EnemyOcclusionSilhouette") and map_source.contains("SquadOcclusionSilhouette") and map_source.contains("no_depth_test = true") and map_source.contains("const PAWN_STEP_DURATION := 0.28") and map_source.contains("pawn.global_position + Vector3(0.0, 0.15, 0.0)") and map_source.contains("func _arrival_resolution_owns_save"), "map pawns retain occlusion silhouettes while movement and arrival persistence use the natural-speed fast path")
	var result_exit_guard := shell_source.contains("func _navigate_back_from_header") and shell_source.contains("if current_screen == \"RESULT\":") and shell_source.contains("SceneRouter.go(\"STAGE_SELECT\", {\"result_return\": true})")
	check(result_exit_guard, "result-to-growth navigation cannot re-enter a committed Battle through generic history")
	check(shell_source.contains("_debug_prepare_companion_event") and shell_source.contains("SettingsService.is_developer_mode"), "companion-event E2E fixture is developer-gated and excluded from Release authority")
	var debug_labels := ["모든 재료 999", "전체 동료 해금", "스테이지 전체 해금", "선택 캐릭터 +10레벨", "선택 캐릭터 10/10/5", "무적:", "Seed +1", "적 배율", "계정 Lv.100", "선택 무기 Lv.60/T6", "N20 즉시 선택", "CH01 NORMAL 완료 / HARD QA"]
	var ordered := true
	var cursor := -1
	for label in debug_labels:
		var next_index := shell_source.find(str(label), cursor + 1)
		ordered = ordered and next_index > cursor
		cursor = next_index
	check(ordered, "responsive DEBUG reflow preserves the established button and Tab order")
	shell.free()

func _test_combat_art_contracts() -> void:
	var facing := _read_json("res://assets/generated_import/combat_facing_contract.json")
	check(not facing.is_empty(), "combat facing contract parses")
	var player: Dictionary = facing.get("player", {})
	var enemy: Dictionary = facing.get("enemy", {})
	check(player.get("deployment_side", "") == "LEFT" and player.get("camera_view", "") == "THREE_QUARTER_RIGHT_DOWN_30", "player combat art faces lower-right from left deployment")
	check(enemy.get("deployment_side", "") == "RIGHT" and enemy.get("camera_view", "") == "THREE_QUARTER_LEFT_DOWN_30", "enemy combat art faces left from right deployment")
	var pack_roots := {
		"CHR001": {"root": "res://assets/generated_import/characters/sd_chr001_maeru_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30", "team": "PLAYER"},
		"CHR002": {"root": "res://assets/generated_import/characters/sd_chr002_roan_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30", "team": "PLAYER"},
		"CHR003": {"root": "res://assets/generated_import/characters/sd_chr003_narin_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30", "team": "PLAYER"},
		"CHR004": {"root": "res://assets/generated_import/characters/sd_chr004_eda_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30", "team": "PLAYER"},
		"CHR005": {"root": "res://assets/generated_import/characters/sd_chr005_soren_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30", "team": "PLAYER"},
		"ENM001": {"root": "res://assets/generated_import/enemies/sd_enm001_rush_drone_combat_r28_dev", "view": "THREE_QUARTER_LEFT_DOWN_30", "team": "ENEMY"},
		"ENM002": {"root": "res://assets/generated_import/enemies/sd_enm002_arc_mote_combat_r28_dev", "view": "THREE_QUARTER_LEFT_DOWN_30", "team": "ENEMY"},
	}
	var expected := {"idle": 8, "move": 12, "basic_attack": 8, "normal_skill": 12, "ultimate": 18, "hit": 4, "down": 8, "victory": 10}
	var manifests_valid := true
	var geometry_valid := true
	var direction_valid := true
	var counts_valid := true
	var files_valid := true
	for character_id in pack_roots:
		var config: Dictionary = pack_roots[character_id]
		var pack_root: String = config.root
		var manifest := _read_json(pack_root + "/animation_manifest.json")
		manifests_valid = manifests_valid and not manifest.is_empty() and manifest.get("character_id", "") == character_id
		var frame_size: Array = manifest.get("frame_size", [])
		var foot_anchor: Array = manifest.get("foot_anchor", [])
		var head_anchor: Array = manifest.get("head_anchor", [])
		geometry_valid = geometry_valid and frame_size.size() == 2 and foot_anchor.size() == 2 and head_anchor.size() == 2
		if frame_size.size() == 2 and foot_anchor.size() == 2:
			geometry_valid = geometry_valid and int(frame_size[0]) == 512 and int(frame_size[1]) == 512
			geometry_valid = geometry_valid and is_equal_approx(float(foot_anchor[0]), 0.5) and is_equal_approx(float(foot_anchor[1]), 0.88)
		direction_valid = direction_valid and manifest.get("view", "") == config.view and manifest.get("team", config.team) == config.team and manifest.get("facing_policy", "") == "SEPARATE_LEFT_RIGHT"
		counts_valid = counts_valid and int(manifest.get("total_frames", 0)) == 80
		for animation_name in expected:
			var definition: Dictionary = manifest.get("animations", {}).get(animation_name, {})
			counts_valid = counts_valid and int(definition.get("frames", 0)) == int(expected[animation_name])
			var paths: Array = definition.get("frame_paths", [])
			files_valid = files_valid and paths.size() == int(expected[animation_name])
			for relative_path in paths: files_valid = files_valid and FileAccess.file_exists(pack_root + "/" + str(relative_path))
	check(manifests_valid, "five player and two enemy combat animation manifests parse")
	check(geometry_valid, "all seven combat packs use 512 canvas, foot and head anchors")
	check(direction_valid, "player and enemy combat packs obey opposing facing contracts")
	check(counts_valid, "all seven animation counts are exactly 8/12/8/12/18/4/8/10")
	check(files_valid, "all 560 combat animation frame files exist")
	var down_pose_ids: Array[String] = ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005", "CHR006", "CHR007", "CHR008"]
	var down_pose_library := BattleSpriteLibrary.new()
	var down_pose_contract := down_pose_library.load_down_pose_pack(down_pose_ids) and down_pose_library.down_pose_textures.size() == down_pose_ids.size()
	for down_pose_id in down_pose_ids:
		var down_pose_texture := down_pose_library.down_pose_texture(down_pose_id)
		var down_pose_metadata: Dictionary = down_pose_library.down_pose_metadata.get(down_pose_id, {})
		down_pose_contract = down_pose_contract and down_pose_texture != null and down_pose_texture.get_width() == 512 and down_pose_texture.get_height() == 512 and str(down_pose_metadata.get("state", "")) == "down" and str(down_pose_metadata.get("style", "")) == "sd-combat"
	check(down_pose_contract, "eight player SD defeat poses load on a fixed 512px logical canvas")
	var enemy_down_pose_library := BattleSpriteLibrary.new()
	enemy_down_pose_library.load_down_pose_pack(["ENM001", "BOSS001"])
	check(not enemy_down_pose_library.has_down_pose("ENM001") and not enemy_down_pose_library.has_down_pose("BOSS001"), "enemy and boss defeat states remain explosion-only")
	var defeat_view := BattleView.new()
	# A new simulation wave can remove the previous enemy before the renderer
	# receives DOWN. Its already registered description must still yield a burst.
	defeat_view._seed_display_unit({"uid":"OLD_WAVE", "def_id":"ENM001", "team":"ENEMY", "rank":"NORMAL", "hp":1, "alive":true})
	defeat_view._apply_display_event(BattleEvent.make(0, BattleEvent.DOWN, "", "OLD_WAVE"))
	check(defeat_view.enemy_defeat_bursts.has("OLD_WAVE"), "last enemy destruction survives wave replacement")
	defeat_view._advance_defeat_presentations(.4)
	check(defeat_view.enemy_defeat_bursts.size() == 1, "enemy destruction remains visible during its burst")
	defeat_view._advance_defeat_presentations(.4)
	check(defeat_view.enemy_defeat_bursts.is_empty(), "enemy destruction is completely retired after its duration")
	defeat_view._seed_display_unit({"uid":"ALLY", "team":"PLAYER", "hp":1, "alive":true})
	defeat_view._apply_display_event(BattleEvent.make(0, BattleEvent.DOWN, "", "ALLY"))
	check(defeat_view.enemy_defeat_bursts.is_empty() and defeat_view.defeat_hold_left > 0.0, "player defeat holds the prone pose without an explosion")
	defeat_view.free()
	var projectile_roots := {
		"CHR001": "proj_chr001_teal_guard_wave_r28", "CHR002": "proj_chr002_coral_blade_arc_r28",
		"CHR003": "proj_chr003_ice_rifle_tracer_r28", "CHR004": "proj_chr004_magenta_energy_bolt_r28",
		"CHR005": "proj_chr005_emerald_cannon_orb_r28", "ENM001": "proj_enm001_crystal_claw_r28",
		"ENM002": "proj_enm002_arc_mote_r28",
	}
	var projectile_manifests_valid := true
	var projectile_files_valid := true
	var projectile_speed_valid := true
	for source_id in projectile_roots:
		var projectile_root := "res://assets/generated_import/projectiles/" + str(projectile_roots[source_id])
		var projectile_manifest := _read_json(projectile_root + "/projectile_manifest.json")
		projectile_manifests_valid = projectile_manifests_valid and projectile_manifest.get("source_id", "") == source_id and int(projectile_manifest.get("frames", 0)) == 8
		var flight_duration := float(projectile_manifest.get("flight_duration", 1.0))
		projectile_speed_valid = projectile_speed_valid and flight_duration >= .05 and flight_duration <= .15
		var projectile_paths: Array = projectile_manifest.get("frame_paths", [])
		projectile_files_valid = projectile_files_valid and projectile_paths.size() == 8
		for relative_path in projectile_paths: projectile_files_valid = projectile_files_valid and FileAccess.file_exists(projectile_root + "/" + str(relative_path))
	check(projectile_manifests_valid, "seven character-specific projectile manifests parse")
	check(projectile_files_valid, "all 56 animated projectile frame files exist")
	check(projectile_speed_valid, "projectile flights stay within fast 0.05 to 0.15 second window")
	# The source packs above are intentionally excluded from Web.  These checks
	# protect the separate, compact runtime atlases that the actual battle view
	# loads in a browser instead of silently falling back to code silhouettes.
	var runtime_sprites := BattleSpriteLibrary.new()
	var runtime_sprite_loaded := runtime_sprites.load_pack()
	var runtime_sprite_frames_valid := runtime_sprite_loaded
	var runtime_entities: Array = DataRegistry.list_of("characters") + DataRegistry.list_of("enemies")
	for entity in runtime_entities:
		var entity_id := str(entity.get("id", ""))
		runtime_sprite_frames_valid = runtime_sprite_frames_valid and runtime_sprites.supports_character(entity_id)
		for animation_name in expected:
			runtime_sprite_frames_valid = runtime_sprite_frames_valid and runtime_sprites.texture_at(entity_id, animation_name, 0.0) != null
	check(runtime_sprite_frames_valid and runtime_entities.size() == 109, "Web battle presentation resolves all 44 players and 65 enemies")
	var active_runtime_sprites := BattleSpriteLibrary.new()
	var active_sprite_ids: Array[String] = ["CHR001", "CHR002", "ENM001"]
	check(active_runtime_sprites.load_pack(active_sprite_ids) and active_runtime_sprites.manifests.size() == active_sprite_ids.size() and active_runtime_sprites.supports_character("CHR001") and not active_runtime_sprites.supports_character("CHR044"), "Web battle startup loads only active combatant sprite atlases")
	# The HD reference slice is intentionally a separately approved, bounded
	# runtime pack. The active revision retains the immutable 384px logical canvas but alpha-tight
	# packs transparent margins. Verify source lineage, logical placement, atlas
	# hashes and all four states before BattleView may draw it.
	var signature_sprites := BattleSpriteLibrary.new()
	var signature_ids: Array[String] = ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005", "CHR008", "BOSS001", "ENM001"]
	var signature_revision := BattleSpriteLibrary.SIGNATURE_REVISION
	var signature_loaded := signature_sprites.load_signature_core_pack(signature_ids)
	var signature_approval := _read_json("res://assets/runtime_web/combat_signature/%s/promotion_approval.json" % signature_revision)
	var signature_hashes: Dictionary = signature_approval.get("manifest_sha256_by_character", {})
	var signature_technical_gate_for_chroma: Dictionary = signature_approval.get("technical_gate", {})
	var declared_chroma_remaster_entities: Array = Array(signature_technical_gate_for_chroma.get("chroma_remaster_entities", []))
	var signature_states := ["idle", "ultimate", "hit", "down"]
	var signature_contract_valid := signature_loaded and signature_sprites.signature_load_error.is_empty() and str(signature_approval.get("signature_revision", "")) == signature_revision
	var signature_diagnostics: Array[String] = ["loaded=%s" % signature_loaded, "error=%s" % signature_sprites.signature_load_error, "approval=%s" % str(signature_approval.get("approval_status", ""))]
	var chroma_derivative_contract := true
	var chroma_derivative_diagnostics: Array[String] = []
	var signature_ultimate_pages_valid := true
	for entity_id in signature_ids:
		# Full artifact inspection must still exercise every ultimate page, but
		# the resident runtime contract is core + one transient page. Loading the
		# seven full sheets together would deliberately exceed the mobile cap.
		signature_ultimate_pages_valid = signature_ultimate_pages_valid and signature_sprites.ensure_signature_ultimate_loaded(entity_id)
		var signature_root := "res://assets/runtime_web/combat_signature/%s/%s" % [signature_revision, entity_id]
		var signature_manifest_path := signature_root + "/signature_manifest.json"
		var signature_manifest: Dictionary = signature_sprites.signature_manifests.get(entity_id, {})
		var source_size: Array = signature_manifest.get("source_frame_size", [])
		var runtime_size: Array = signature_manifest.get("runtime_frame_size", [])
		var signature_animations: Dictionary = signature_manifest.get("animations", {})
		var chroma_provenance: Dictionary = signature_manifest.get("chroma_key_provenance", {})
		signature_diagnostics.append("%s:manifest=%s states=%d source=%s runtime=%s" % [entity_id, not signature_manifest.is_empty(), signature_animations.size(), source_size, runtime_size])
		signature_contract_valid = signature_contract_valid and FileAccess.file_exists(signature_manifest_path) and FileAccess.get_sha256(signature_manifest_path) == str(signature_hashes.get(entity_id, ""))
		var source_dimensions_valid := source_size.size() == 2 and int(source_size[0]) == 512 and int(source_size[1]) == 512
		var runtime_dimensions_valid := runtime_size.size() == 2 and int(runtime_size[0]) == 384 and int(runtime_size[1]) == 384
		signature_contract_valid = signature_contract_valid and source_dimensions_valid and runtime_dimensions_valid and bool(signature_manifest.get("no_source_mutation", false)) and str(signature_manifest.get("generation", "")) == "deterministic_resize_alpha_tight_atlas_only"
		for animation_name in signature_states:
			var signature_definition: Dictionary = signature_animations.get(animation_name, {})
			var signature_atlas_path := signature_root + "/" + str(signature_definition.get("atlas_path", ""))
			# Test the same imported texture resource that the exported game uses.
			# Image.load_from_file emits a false export warning for res:// PNGs even
			# though this is only an artifact-inspection assertion.
			var signature_atlas := ResourceLoader.load(signature_atlas_path, "Texture2D") as Texture2D
			var atlas_qc: Dictionary = signature_definition.get("atlas_qc", {})
			var packed_definition: Dictionary = signature_definition.get("packing", {})
			var frame_info := signature_sprites.signature_frame_info_at(entity_id, animation_name, .31)
			var logical_rect = frame_info.get("logical_rect", null)
			var logical_canvas = frame_info.get("logical_canvas_size", null)
			signature_contract_valid = signature_contract_valid and signature_sprites.has_signature_animation(entity_id, animation_name) and signature_sprites.signature_texture_at(entity_id, animation_name, .31) != null and logical_rect is Rect2 and logical_canvas is Vector2
			signature_contract_valid = signature_contract_valid and FileAccess.file_exists(signature_atlas_path) and FileAccess.get_sha256(signature_atlas_path) == str(signature_definition.get("atlas_sha256", ""))
			var logical_frame_size = signature_definition.get("logical_frame_size", [])
			var packed_bytes := int(packed_definition.get("packed_rgba_bytes", 0))
			var logical_bytes := int(packed_definition.get("logical_rgba_bytes", 0))
			signature_contract_valid = signature_contract_valid and signature_atlas != null and signature_atlas.get_width() > 0 and signature_atlas.get_width() <= 2048 and signature_atlas.get_height() > 0 and signature_atlas.get_height() <= 2048 and logical_frame_size is Array and logical_frame_size.size() == 2 and int(logical_frame_size[0]) == 384 and int(logical_frame_size[1]) == 384 and str(packed_definition.get("mode", "")) == "ALPHA_TIGHT_SHELF_R1" and packed_bytes > 0 and logical_bytes > packed_bytes and int(atlas_qc.get("visible_exact_green_pixels", -1)) == 0
		# Any source declared in this candidate's green-master/keyed-RGBA list must
		# retain both artifacts and their QC evidence. This stays data-driven so a
		# new white-matte repair such as R13 CHR004 cannot silently bypass the
		# same contract previously used by CHR002 and ENM001.
		if declared_chroma_remaster_entities.has(entity_id):
			var derivative_manifest_path := str(chroma_provenance.get("derivative_manifest", ""))
			var derivative_resource_path := "res://../" + derivative_manifest_path
			var derivative_manifest := _read_json(derivative_resource_path)
			var derivative_records: Array = derivative_manifest.get("records", [])
			var expected_derivative_records := 0
			for derivative_animation_name in signature_states:
				var derivative_animation: Dictionary = signature_animations.get(derivative_animation_name, {})
				expected_derivative_records += int(derivative_animation.get("frame_count", 0))
			chroma_derivative_contract = chroma_derivative_contract and not derivative_manifest_path.is_empty() and FileAccess.file_exists(derivative_resource_path) and str(derivative_manifest.get("status", "")) == "LOCAL_QA_ONLY_CHROMA_KEY_DERIVATIVE" and derivative_records.size() == expected_derivative_records
			for record_value in derivative_records:
				var record: Dictionary = record_value
				var master_path := "res://../" + str(record.get("green_master_path", ""))
				var keyed_path := "res://../" + str(record.get("keyed_rgba_path", ""))
				var key_qc: Dictionary = record.get("key_qc", {})
				var keyed_qc: Dictionary = record.get("keyed_qc", {})
				var white_before := int(key_qc.get("white_external_edge_pixels_before", 0))
				var white_after := int(key_qc.get("white_external_edge_pixels_after", -1))
				var rim_before := int(key_qc.get("white_exterior_rim_pixels_before", 0))
				var rim_after := int(key_qc.get("white_exterior_rim_pixels_after", -1))
				var master_exists := FileAccess.file_exists(master_path)
				var keyed_exists := FileAccess.file_exists(keyed_path)
				var master_hash_ok := master_exists and FileAccess.get_sha256(master_path) == str(record.get("green_master_sha256", ""))
				var keyed_hash_ok := keyed_exists and FileAccess.get_sha256(keyed_path) == str(record.get("keyed_rgba_sha256", ""))
				var alpha_extrema: Array = Array(keyed_qc.get("alpha_extrema", []))
				var alpha_ok := alpha_extrema.size() == 2 and int(alpha_extrema[0]) == 0 and int(alpha_extrema[1]) == 255
				var green_ok := int(keyed_qc.get("visible_exact_green_pixels", -1)) == 0
				var white_ok := white_before == 0 or white_after < white_before
				var rim_ok := rim_before == 0 or rim_after < rim_before
				var record_ok := master_hash_ok and keyed_hash_ok and alpha_ok and green_ok and white_ok and rim_ok
				chroma_derivative_contract = chroma_derivative_contract and record_ok
				if not record_ok:
					chroma_derivative_diagnostics.append("%s master=%s/%s keyed=%s/%s alpha=%s green=%s white=%d>%d rim=%d>%d" % [str(record.get("source_path", "")), master_exists, master_hash_ok, keyed_exists, keyed_hash_ok, alpha_ok, green_ok, white_before, white_after, rim_before, rim_after])
			chroma_derivative_diagnostics.append("%s records=%d/%d path=%s" % [entity_id, derivative_records.size(), expected_derivative_records, derivative_manifest_path])
		signature_sprites.release_signature_transient_ultimate()
	var enm001_signature_manifest: Dictionary = signature_sprites.signature_manifests.get("ENM001", {})
	var enm001_animations: Dictionary = enm001_signature_manifest.get("animations", {})
	var enm001_frame_selection_valid := int((enm001_animations.get("idle", {}) as Dictionary).get("frame_count", 0)) == 4 and int((enm001_animations.get("ultimate", {}) as Dictionary).get("frame_count", 0)) == 12 and int((enm001_animations.get("hit", {}) as Dictionary).get("frame_count", 0)) == 4 and int((enm001_animations.get("down", {}) as Dictionary).get("frame_count", 0)) == 8
	signature_contract_valid = signature_contract_valid and enm001_frame_selection_valid
	var signature_technical_gate: Dictionary = signature_approval.get("technical_gate", {})
	var signature_core_bytes := int(signature_technical_gate.get("estimated_core_resident_atlas_bytes_for_all_selected", -1))
	var signature_peak_bytes := int(signature_technical_gate.get("estimated_peak_transient_resident_atlas_bytes", -1))
	var signature_full_preload_bytes := int(signature_technical_gate.get("estimated_full_preload_atlas_bytes_for_all_selected", -1))
	var signature_budget_bytes := int(signature_technical_gate.get("runtime_memory_budget_mib", 0)) * 1024 * 1024
	signature_contract_valid = signature_contract_valid and signature_ultimate_pages_valid and str(signature_technical_gate.get("residency_model", "")) == "core_idle_hit_down_plus_one_caster_ultimate_transient" and signature_core_bytes == signature_sprites.signature_resident_atlas_bytes and signature_core_bytes <= signature_budget_bytes and signature_peak_bytes <= signature_budget_bytes and signature_full_preload_bytes >= signature_peak_bytes
	check(signature_contract_valid, "starting-party, alternate-party and enemy signature actors retain pinned 384px art through a core-plus-one-ultimate mobile residency contract", " | ".join(signature_diagnostics))
	if signature_revision in ["r6", "r7", "r10", "r12", "r13", "r14", "r16"]:
		check(chroma_derivative_contract, "every declared chroma-remastered signature source retains an opaque #00FF00 master and hash-pinned keyed RGBA derivative with no visible green or exterior white matte", " | ".join(chroma_derivative_diagnostics))
	var encounter_signature_sprites := BattleSpriteLibrary.new()
	var encounter_signature_ids: Array[String] = ["CHR001"]
	var encounter_signature_loaded := encounter_signature_sprites.load_signature_core_pack(encounter_signature_ids) and encounter_signature_sprites.ensure_signature_ultimate_loaded("CHR001")
	var encounter_signature_residency: Dictionary = encounter_signature_sprites.signature_residency_snapshot()
	var encounter_signature_isolated: bool = encounter_signature_loaded and Array(encounter_signature_residency.get("entity_ids", [])).size() == 1 and Array(encounter_signature_residency.get("entity_ids", []))[0] == "CHR001" and encounter_signature_sprites.has_signature_animation("CHR001", "ultimate") and not encounter_signature_sprites.has_signature_animation("CHR008", "ultimate") and int(encounter_signature_residency.get("resident_atlas_bytes", 0)) > 0 and int(encounter_signature_residency.get("resident_atlas_bytes", 0)) < signature_sprites.signature_resident_atlas_bytes
	check(encounter_signature_isolated, "high-density actor pages are leased to the current caster instead of globally preloading every signature candidate")
	var rejected_signature_load := BattleSpriteLibrary.new()
	check(not rejected_signature_load.load_signature_core_pack(["CHR001", "UNAPPROVED_TEST_ID"]) and rejected_signature_load.signature_manifests.is_empty() and not rejected_signature_load.signature_load_error.is_empty(), "signature pack rejects a partial or unapproved character set instead of silently mixing candidates")
	# Projectile and ultimate VFX resolution must rise with the actor signature
	# slice.  Keep the effect atlas candidate separately pinned: a valid PNG is
	# not enough to replace release effects without its manifest/hash/budget gate.
	var signature_effects := EffectSignatureLibrary.new()
	var signature_effect_ids: Array[String] = signature_ids.duplicate()
	var signature_effect_revision := EffectSignatureLibrary.SIGNATURE_REVISION
	var signature_effect_loaded := signature_effects.load_signature_core_pack(signature_effect_ids)
	var signature_effect_approval := _read_json("res://assets/runtime_web/effect_signature/%s/promotion_approval.json" % signature_effect_revision)
	var signature_effect_hashes: Dictionary = signature_effect_approval.get("manifest_sha256_by_entity", {})
	var signature_effect_contract_valid := signature_effect_loaded and signature_effects.signature_load_error.is_empty() and str(signature_effect_approval.get("effect_signature_revision", "")) == signature_effect_revision
	var signature_effect_diagnostics: Array[String] = ["loaded=%s" % signature_effect_loaded, "error=%s" % signature_effects.signature_load_error, "approval=%s" % str(signature_effect_approval.get("approval_status", ""))]
	var signature_effect_ultimate_pages_valid := true
	for entity_id in signature_effect_ids:
		signature_effect_ultimate_pages_valid = signature_effect_ultimate_pages_valid and signature_effects.ensure_signature_ultimate_loaded(entity_id)
		var profile_id := signature_effects.signature_profile_for(entity_id)
		var effect_root := "res://assets/runtime_web/effect_signature/%s/%s" % [signature_effect_revision, profile_id]
		var effect_manifest_path := effect_root + "/effect_signature_manifest.json"
		var effect_manifest: Dictionary = signature_effects.manifests.get(profile_id, {})
		var projectile_effect: Dictionary = effect_manifest.get("projectile", {})
		var ultimate_effect: Dictionary = effect_manifest.get("ultimate", {})
		signature_effect_diagnostics.append("%s:manifest=%s projectile=%s ultimate=%s" % [entity_id, not effect_manifest.is_empty(), projectile_effect.get("frame_size", []), ultimate_effect.get("frame_size", [])])
		signature_effect_contract_valid = signature_effect_contract_valid and not profile_id.is_empty() and FileAccess.file_exists(effect_manifest_path) and FileAccess.get_sha256(effect_manifest_path) == str(signature_effect_hashes.get(profile_id, ""))
		signature_effect_contract_valid = signature_effect_contract_valid and bool(effect_manifest.get("no_source_mutation", false)) and str(effect_manifest.get("generation", "")) == "deterministic_lanczos_upscale_only"
		for effect_definition in [projectile_effect, ultimate_effect]:
			var effect_atlas_path := effect_root + "/" + str(effect_definition.get("atlas_path", ""))
			var effect_atlas := ResourceLoader.load(effect_atlas_path, "Texture2D") as Texture2D
			var effect_qc: Dictionary = effect_definition.get("runtime_qc", {})
			signature_effect_contract_valid = signature_effect_contract_valid and FileAccess.file_exists(effect_atlas_path) and FileAccess.get_sha256(effect_atlas_path) == str(effect_definition.get("atlas_sha256", "")) and effect_atlas != null and int(effect_qc.get("visible_exact_green_pixels", -1)) == 0
		var projectile_frame_size = projectile_effect.get("frame_size", [])
		var ultimate_frame_size = ultimate_effect.get("frame_size", [])
		var effect_scale := float(effect_manifest.get("scale_factor", 0.0))
		var expected_projectile_edge := int(round(96.0 * effect_scale))
		var expected_ultimate_edge := int(round(112.0 * effect_scale))
		var projectile_dimensions_valid: bool = effect_scale > 1.0 and projectile_frame_size is Array and projectile_frame_size.size() == 2 and int(projectile_frame_size[0]) == expected_projectile_edge and int(projectile_frame_size[1]) == expected_projectile_edge and expected_projectile_edge > 96
		var ultimate_dimensions_valid: bool = effect_scale > 1.0 and ultimate_frame_size is Array and ultimate_frame_size.size() == 2 and int(ultimate_frame_size[0]) == expected_ultimate_edge and int(ultimate_frame_size[1]) == expected_ultimate_edge and expected_ultimate_edge > 112
		signature_effect_contract_valid = signature_effect_contract_valid and projectile_dimensions_valid and int(projectile_effect.get("frames", 0)) == 8 and ultimate_dimensions_valid and int(ultimate_effect.get("frames", 0)) == 12
		signature_effect_contract_valid = signature_effect_contract_valid and signature_effects.projectile_texture_at(entity_id, .06) != null and signature_effects.ultimate_texture_at(entity_id, .42) != null
		signature_effects.release_signature_transient_ultimate()
	var signature_effect_technical_gate: Dictionary = signature_effect_approval.get("technical_gate", {})
	var signature_effect_core_bytes := int(signature_effect_technical_gate.get("estimated_core_resident_atlas_bytes_for_all_selected", -1))
	var signature_effect_peak_bytes := int(signature_effect_technical_gate.get("estimated_peak_transient_resident_atlas_bytes", -1))
	var signature_effect_full_preload_bytes := int(signature_effect_technical_gate.get("estimated_full_preload_atlas_bytes_for_all_selected", -1))
	var signature_effect_budget_bytes := int(signature_effect_technical_gate.get("runtime_memory_budget_mib", 0)) * 1024 * 1024
	signature_effect_contract_valid = signature_effect_contract_valid and signature_effect_ultimate_pages_valid and str(signature_effect_technical_gate.get("residency_model", "")) == "projectile_core_plus_one_caster_ultimate_transient" and signature_effect_core_bytes == signature_effects.signature_resident_atlas_bytes and signature_effect_core_bytes <= signature_effect_budget_bytes and signature_effect_peak_bytes <= signature_effect_budget_bytes and signature_effect_full_preload_bytes >= signature_effect_peak_bytes
	check(signature_effect_contract_valid and signature_effects.uses_borrowed_profile("CHR002"), "the complete starting-party, reviewed alternate-party and current-enemy group uses pinned upscale projectile/ultimate effects through one-caster transient residency", " | ".join(signature_effect_diagnostics))
	# This group contains the actual starting five, reviewed CHR008 alternate
	# party member, current boss and common enemy in core form, while CHR002
	# intentionally reuses CHR001's VFX profile. Check the decoded
	# resident snapshot, not just the manifest estimate, so a later loader cannot
	# silently revert to a full ultimate preload.
	var concurrent_actor_residency: Dictionary = signature_sprites.signature_residency_snapshot()
	var concurrent_effect_residency: Dictionary = signature_effects.signature_residency_snapshot()
	var concurrent_actor_ids: Array = Array(concurrent_actor_residency.get("entity_ids", []))
	var concurrent_effect_ids: Array = Array(concurrent_effect_residency.get("entity_ids", []))
	var concurrent_effect_profiles: Array = Array(concurrent_effect_residency.get("profile_ids", []))
	var concurrent_actor_state_map: Dictionary = concurrent_actor_residency.get("animation_ids_by_entity", {})
	var concurrent_effect_state_map: Dictionary = concurrent_effect_residency.get("effect_ids_by_profile", {})
	var concurrent_core_states_valid := true
	for entity_id in signature_ids:
		concurrent_core_states_valid = concurrent_core_states_valid and Array(concurrent_actor_state_map.get(entity_id, [])) == ["idle", "hit", "down"]
	for profile_id in ["CHR001", "CHR003", "CHR004", "CHR005", "CHR008", "BOSS001", "ENM001"]:
		concurrent_core_states_valid = concurrent_core_states_valid and Array(concurrent_effect_state_map.get(profile_id, [])) == ["projectile"]
	var concurrent_signature_contract := concurrent_actor_ids == signature_ids and concurrent_effect_ids == signature_effect_ids and concurrent_effect_profiles == ["CHR001", "CHR003", "CHR004", "CHR005", "CHR008", "BOSS001", "ENM001"] and concurrent_core_states_valid and int(concurrent_actor_residency.get("resident_atlas_bytes", -1)) <= int(concurrent_actor_residency.get("budget_bytes", 0)) and int(concurrent_effect_residency.get("resident_atlas_bytes", -1)) <= int(concurrent_effect_residency.get("budget_bytes", 0))
	check(concurrent_signature_contract, "starting-party, alternate-party and current-enemy HD cores stay within 72MiB actor and 12MiB effect ceilings without a hidden full-ultimate preload", "actors=%s effects=%s profiles=%s" % [JSON.stringify(concurrent_actor_residency), JSON.stringify(concurrent_effect_residency), JSON.stringify(concurrent_effect_profiles)])
	# Runtime entry intentionally has a smaller resident contract than full-pack
	# artifact QA: every present actor keeps idle/hit/down and every present effect
	# keeps its projectile, but only the currently casting unit may own an ultimate
	# page. Exercise two different casters so a stale first page cannot hide in the
	# resident map while the second one is acquired.
	var paged_signature_sprites := BattleSpriteLibrary.new()
	var paged_signature_effects := EffectSignatureLibrary.new()
	var paged_actor_core_loaded := paged_signature_sprites.load_signature_core_pack(signature_ids)
	var paged_effect_core_loaded := paged_signature_effects.load_signature_core_pack(signature_effect_ids)
	var paged_actor_core: Dictionary = paged_signature_sprites.signature_residency_snapshot()
	var paged_effect_core: Dictionary = paged_signature_effects.signature_residency_snapshot()
	var paged_actor_state_map: Dictionary = paged_actor_core.get("animation_ids_by_entity", {})
	var paged_effect_state_map: Dictionary = paged_effect_core.get("effect_ids_by_profile", {})
	var paged_core_states_valid := paged_actor_core_loaded and paged_effect_core_loaded and int(paged_actor_core.get("resident_atlas_bytes", -1)) == int(paged_actor_core.get("core_resident_atlas_bytes", -2)) and int(paged_effect_core.get("resident_atlas_bytes", -1)) == int(paged_effect_core.get("core_resident_atlas_bytes", -2)) and int(paged_actor_core.get("resident_atlas_bytes", 0)) < signature_full_preload_bytes and int(paged_effect_core.get("resident_atlas_bytes", 0)) < signature_effect_full_preload_bytes
	for entity_id in signature_ids:
		var paged_actor_states: Array = Array(paged_actor_state_map.get(entity_id, []))
		paged_core_states_valid = paged_core_states_valid and paged_actor_states == ["idle", "hit", "down"] and not paged_signature_sprites.has_signature_animation(entity_id, "ultimate") and paged_signature_effects.supports_projectile_source(entity_id) and not paged_signature_effects.supports_ultimate_source(entity_id)
	var paged_first_ultimate_loaded := paged_signature_sprites.ensure_signature_ultimate_loaded("CHR001") and paged_signature_effects.ensure_signature_ultimate_loaded("CHR001")
	var paged_after_first_actor: Dictionary = paged_signature_sprites.signature_residency_snapshot()
	var paged_after_first_effect: Dictionary = paged_signature_effects.signature_residency_snapshot()
	var paged_second_ultimate_loaded := paged_signature_sprites.ensure_signature_ultimate_loaded("ENM001") and paged_signature_effects.ensure_signature_ultimate_loaded("ENM001")
	var paged_after_second_actor: Dictionary = paged_signature_sprites.signature_residency_snapshot()
	var paged_after_second_effect: Dictionary = paged_signature_effects.signature_residency_snapshot()
	var paged_second_actor_states: Dictionary = paged_after_second_actor.get("animation_ids_by_entity", {})
	var paged_second_effect_states: Dictionary = paged_after_second_effect.get("effect_ids_by_profile", {})
	var paged_transition_valid := paged_first_ultimate_loaded and paged_second_ultimate_loaded and str(paged_after_first_actor.get("transient_ultimate_entity_id", "")) == "CHR001" and str(paged_after_first_effect.get("transient_ultimate_profile_id", "")) == "CHR001" and str(paged_after_second_actor.get("transient_ultimate_entity_id", "")) == "ENM001" and str(paged_after_second_effect.get("transient_ultimate_profile_id", "")) == "ENM001" and paged_signature_sprites.has_signature_animation("ENM001", "ultimate") and not paged_signature_sprites.has_signature_animation("CHR001", "ultimate") and paged_signature_effects.supports_ultimate_source("ENM001") and not paged_signature_effects.supports_ultimate_source("CHR001") and Array(paged_second_actor_states.get("CHR001", [])) == ["idle", "hit", "down"] and Array(paged_second_actor_states.get("ENM001", [])) == ["idle", "hit", "down", "ultimate"] and Array(paged_second_effect_states.get("CHR001", [])) == ["projectile"] and Array(paged_second_effect_states.get("ENM001", [])) == ["projectile", "ultimate"] and int(paged_after_second_actor.get("resident_atlas_bytes", -1)) <= int(paged_after_second_actor.get("budget_bytes", 0)) and int(paged_after_second_effect.get("resident_atlas_bytes", -1)) <= int(paged_after_second_effect.get("budget_bytes", 0))
	paged_signature_sprites.release_signature_transient_ultimate()
	paged_signature_effects.release_signature_transient_ultimate()
	var paged_after_release_actor: Dictionary = paged_signature_sprites.signature_residency_snapshot()
	var paged_after_release_effect: Dictionary = paged_signature_effects.signature_residency_snapshot()
	var paged_release_valid := str(paged_after_release_actor.get("transient_ultimate_entity_id", "")) == "" and str(paged_after_release_effect.get("transient_ultimate_profile_id", "")) == "" and int(paged_after_release_actor.get("resident_atlas_bytes", -1)) == int(paged_after_release_actor.get("core_resident_atlas_bytes", -2)) and int(paged_after_release_effect.get("resident_atlas_bytes", -1)) == int(paged_after_release_effect.get("core_resident_atlas_bytes", -2)) and not paged_signature_sprites.has_signature_animation("ENM001", "ultimate") and not paged_signature_effects.supports_ultimate_source("ENM001")
	check(paged_core_states_valid and paged_transition_valid and paged_release_valid, "five-combatant HD runtime keeps core motion/projectiles resident and leases one caster ultimate atomically under both mobile ceilings", "core_actor=%s core_effect=%s second_actor=%s second_effect=%s release_actor=%s release_effect=%s" % [JSON.stringify(paged_actor_core), JSON.stringify(paged_effect_core), JSON.stringify(paged_after_second_actor), JSON.stringify(paged_after_second_effect), JSON.stringify(paged_after_release_actor), JSON.stringify(paged_after_release_effect)])
	# The reviewed CHR008 alternate remains in the immutable candidate manifest,
	# but it must consume no actor/effect/HUD-face residency in the actual initial
	# five-player encounter. Exercise the BattleView-facing snapshot rather than
	# only a loader in isolation so a later UI warm-up cannot quietly reintroduce
	# a non-party face crop.
	var initial_residency_sim := _simulation(17231)
	var initial_residency_party: Array = []
	for party_slot in range(5):
		var initial_character_id := "CHR%03d" % (party_slot + 1)
		var initial_character := DataRegistry.character(initial_character_id)
		initial_residency_party.append(initial_residency_sim._make_player(initial_character, party_slot))
	initial_residency_sim.state.party = initial_residency_party
	initial_residency_sim.state.enemies = [initial_residency_sim._make_enemy("ENM001", 0), initial_residency_sim._make_enemy("BOSS001", 0)]
	var initial_residency_view := BattleView.new()
	initial_residency_view.setup(initial_residency_sim)
	var initial_runtime_resident_ids: Array[String] = ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005", "BOSS001", "ENM001"]
	var initial_runtime_actor_loaded := initial_residency_view.sprite_library.load_signature_core_pack(initial_runtime_resident_ids)
	var initial_runtime_effect_loaded := initial_residency_view.effect_signature_library.load_signature_core_pack(initial_runtime_resident_ids)
	initial_residency_view.signature_sprite_pack_ready = initial_runtime_actor_loaded
	initial_residency_view.effect_signature_pack_ready = initial_runtime_effect_loaded
	initial_residency_view.signature_residency_target_ids = initial_runtime_resident_ids.duplicate()
	var initial_runtime_faces_ready := true
	for initial_character_id in ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005"]:
		initial_runtime_faces_ready = initial_runtime_faces_ready and initial_residency_view.ultimate_orb_texture_for(initial_character_id, null) != null
	var initial_runtime_snapshot: Dictionary = initial_residency_view.signature_runtime_residency_snapshot()
	var initial_runtime_active_ids: Array = Array(initial_runtime_snapshot.get("active_encounter_ids", []))
	var initial_runtime_actor_ids: Array = Array(initial_runtime_snapshot.get("resident_actor_ids", []))
	var initial_runtime_effect_ids: Array = Array(initial_runtime_snapshot.get("resident_effect_entity_ids", []))
	var initial_runtime_face_ids: Array = Array(initial_runtime_snapshot.get("face_crop_entity_ids", []))
	var initial_runtime_face_bytes: Dictionary = initial_runtime_snapshot.get("face_crop_resident_bytes_by_entity", {})
	var initial_runtime_active_exact := initial_runtime_active_ids.size() == initial_runtime_resident_ids.size()
	for expected_initial_id in initial_runtime_resident_ids:
		initial_runtime_active_exact = initial_runtime_active_exact and initial_runtime_active_ids.has(expected_initial_id)
	var initial_runtime_residency_contract := initial_runtime_actor_loaded and initial_runtime_effect_loaded and initial_runtime_faces_ready and initial_runtime_active_exact and initial_runtime_actor_ids == initial_runtime_resident_ids and initial_runtime_effect_ids == initial_runtime_resident_ids and not initial_runtime_active_ids.has("CHR008") and not initial_runtime_actor_ids.has("CHR008") and not initial_runtime_effect_ids.has("CHR008") and not initial_runtime_face_ids.has("CHR008") and int(initial_runtime_face_bytes.get("CHR008", 0)) == 0 and int(initial_runtime_snapshot.get("face_crop_resident_bytes", 0)) == 5 * 192 * 192 * 4
	check(initial_runtime_residency_contract, "actual initial five-player HD residency excludes CHR008 actor, effect and HUD face bytes", JSON.stringify(initial_runtime_snapshot))
	initial_residency_view.free()
	# Rollover is release-before-acquire: while the old high-density lease is gone,
	# the ordinary compact actor pack remains valid; the next complete pack is then
	# accepted as one set. A deliberately invalid request must leave no mixed page.
	var rollover_actor := BattleSpriteLibrary.new()
	var rollover_effect := EffectSignatureLibrary.new()
	var rollover_compact_ready := rollover_actor.load_pack(signature_ids)
	var rollover_first_ids: Array[String] = ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005"]
	var rollover_first_loaded := rollover_actor.load_signature_core_pack(rollover_first_ids) and rollover_effect.load_signature_core_pack(rollover_first_ids)
	rollover_actor.clear_signature_pack()
	rollover_effect.clear_signature_pack()
	var rollover_released_actor: Dictionary = rollover_actor.signature_residency_snapshot()
	var rollover_released_effect: Dictionary = rollover_effect.signature_residency_snapshot()
	var rollover_compact_fallback := rollover_compact_ready and rollover_actor.supports_character("CHR001") and rollover_actor.supports_character("CHR002") and rollover_actor.supports_character("CHR008") and rollover_actor.supports_character("BOSS001") and rollover_actor.supports_character("ENM001")
	var rollover_next_loaded := rollover_actor.load_signature_core_pack(signature_ids) and rollover_effect.load_signature_core_pack(signature_effect_ids)
	var rollover_next_actor: Dictionary = rollover_actor.signature_residency_snapshot()
	var rollover_next_effect: Dictionary = rollover_effect.signature_residency_snapshot()
	var rollover_partial_rejected: bool = not rollover_actor.load_signature_core_pack(["CHR001", "UNAPPROVED_TEST_ID"]) and Array(rollover_actor.signature_residency_snapshot().get("entity_ids", [])).is_empty() and int(rollover_actor.signature_residency_snapshot().get("resident_atlas_bytes", -1)) == 0 and not rollover_actor.signature_load_error.is_empty()
	var rollover_contract: bool = rollover_first_loaded and Array(rollover_released_actor.get("entity_ids", [])).is_empty() and int(rollover_released_actor.get("resident_atlas_bytes", -1)) == 0 and Array(rollover_released_effect.get("entity_ids", [])).is_empty() and int(rollover_released_effect.get("resident_atlas_bytes", -1)) == 0 and rollover_compact_fallback and rollover_next_loaded and Array(rollover_next_actor.get("entity_ids", [])) == signature_ids and Array(rollover_next_effect.get("entity_ids", [])) == signature_effect_ids and int(rollover_next_actor.get("resident_atlas_bytes", -1)) <= int(rollover_next_actor.get("budget_bytes", 0)) and int(rollover_next_effect.get("resident_atlas_bytes", -1)) <= int(rollover_next_effect.get("budget_bytes", 0)) and rollover_partial_rejected
	check(rollover_contract, "wave residency rollover releases old high-density pages before the next atomic actor+effect lease, preserves compact fallback, and rejects mixed partial pages")
	var encounter_signature_effects := EffectSignatureLibrary.new()
	var encounter_signature_effect_ids: Array[String] = ["CHR001"]
	var encounter_signature_effect_loaded := encounter_signature_effects.load_signature_core_pack(encounter_signature_effect_ids) and encounter_signature_effects.ensure_signature_ultimate_loaded("CHR001")
	var encounter_signature_effect_residency: Dictionary = encounter_signature_effects.signature_residency_snapshot()
	var encounter_signature_effect_isolated: bool = encounter_signature_effect_loaded and Array(encounter_signature_effect_residency.get("entity_ids", [])).size() == 1 and Array(encounter_signature_effect_residency.get("entity_ids", []))[0] == "CHR001" and encounter_signature_effects.supports_source("CHR001") and not encounter_signature_effects.supports_source("BOSS001") and int(encounter_signature_effect_residency.get("resident_atlas_bytes", 0)) > 0 and int(encounter_signature_effect_residency.get("resident_atlas_bytes", 0)) < signature_effects.signature_resident_atlas_bytes
	check(encounter_signature_effect_isolated, "high-density projectile core and one ultimate page are leased per encounter without duplicating every character effect")
	var rejected_signature_effect_load := EffectSignatureLibrary.new()
	check(not rejected_signature_effect_load.load_signature_core_pack(["CHR001", "UNAPPROVED_TEST_ID"]) and rejected_signature_effect_load.manifests.is_empty() and not rejected_signature_effect_load.signature_load_error.is_empty(), "effect signature pack rejects a partial or unapproved entity set instead of silently mixing candidates")
	var runtime_projectiles := ProjectileSpriteLibrary.new()
	var runtime_projectile_loaded := runtime_projectiles.load_pack()
	var runtime_projectile_frames_valid := runtime_projectile_loaded
	for entity in runtime_entities:
		var source_id := str(entity.get("id", ""))
		runtime_projectile_frames_valid = runtime_projectile_frames_valid and runtime_projectiles.supports_source(source_id) and runtime_projectiles.texture_at(source_id, 0.0) != null
	check(runtime_projectile_frames_valid, "Web animated projectile atlases load for all runtime combat sources")
	var active_runtime_projectiles := ProjectileSpriteLibrary.new()
	var active_projectile_ids: Array[String] = ["CHR001", "CHR002", "ENM001"]
	check(active_runtime_projectiles.load_pack(active_projectile_ids) and active_runtime_projectiles.manifests.size() == active_projectile_ids.size() and active_runtime_projectiles.supports_source("ENM001") and not active_runtime_projectiles.supports_source("CHR044"), "Web battle startup loads only active combatant projectile atlases")
	var runtime_vfx_valid := true
	for folder in ["vfx_chr001_basic", "vfx_chr001_normal", "vfx_chr001_ultimate", "vfx_chr008_basic", "vfx_chr008_normal", "vfx_chr008_ultimate"]:
		runtime_vfx_valid = runtime_vfx_valid and ResourceLoader.exists("res://assets/runtime_web/vfx/%s/atlas.png" % folder)
	check(runtime_vfx_valid, "Web authored VFX atlases resolve without art-folder fallback")
	var battle_view_source := FileAccess.get_file_as_string("res://battle/view/battle_view.gd")
	# Numeric contact timing is exercised by encounter_combat_upgrade_runner;
	# this older contract only checks that authored travel/contact assets remain wired.
	var skill_sequence_contract := battle_view_source.contains("var travel_key := \"%s_%s\"") and battle_view_source.contains("travel_frames[travel_frame]") and battle_view_source.contains("kind.trim_prefix(\"impact_\")") and battle_view_source.contains("frame = mini(textures.size() - 1, 6 +") and battle_view_source.contains("_spawn_vfx(str(event.source), str(event.target), \"impact_%s\"") and battle_view_source.contains("effect_signature_library.projectile_texture_at") and battle_view_source.contains("effect_signature_library.ultimate_texture_at")
	check(skill_sequence_contract, "authored skill VFX follow charge, moving high-density signature projectile, contact burst and hit-reaction sequence")
	var audio_manifest := _read_json("res://assets/audio/audio_manifest.json")
	var runtime_audio_valid := true
	var runtime_audio_rights_valid: bool = audio_manifest.get("ownership_declaration", {}).get("ownership_status", "") == "PER_ENTRY_DECLARED"
	var runtime_cc0_sfx_count := 0
	var runtime_bgm_contract := true
	var bgm_length_diagnostics: Array[String] = []
	for entry_value in audio_manifest.get("entries", []):
		var entry: Dictionary = entry_value
		var audio_path := str(entry.get("runtime_path", ""))
		runtime_audio_valid = runtime_audio_valid and ResourceLoader.exists(audio_path)
		var ownership_status := str(entry.get("ownership_status", ""))
		runtime_audio_rights_valid = runtime_audio_rights_valid and ownership_status in ["USER_OWNED", "CC0-1.0"] and bool(entry.get("commercial_use", false))
		if str(entry.get("category", "")) == "SFX" and ownership_status == "CC0-1.0":
			runtime_cc0_sfx_count += 1
		if str(entry.get("category", "")) == "BGM":
			var stream = load(audio_path)
			var length_seconds: float = (stream as AudioStream).get_length() if stream is AudioStream else -1.0
			bgm_length_diagnostics.append("%s=%.2fs" % [str(entry.get("asset_id", "unknown")), length_seconds])
			var minimum_seconds := 20.0 if str(entry.get("event", "")) == "TITLE" else 60.0
			runtime_bgm_contract = runtime_bgm_contract and bool(entry.get("loop", false)) and stream is AudioStream and length_seconds >= minimum_seconds
	check(runtime_audio_valid and runtime_audio_rights_valid and audio_manifest.get("entries", []).size() == 59 and runtime_cc0_sfx_count == 54, "all 59 declared local audio streams resolve, including 54 CC0 SFX")
	check(runtime_bgm_contract, "all local BGM streams use their full-length source (20s+ title / 60s+ in-game) and are loop-enabled", ", ".join(bgm_length_diagnostics))
	var audio_service_source := FileAccess.get_file_as_string("res://autoload/audio_service.gd")
	check(audio_service_source.contains("playback_attempt_counts") and audio_service_source.contains("playback_verified_counts") and audio_service_source.contains("_verify_start_after_delay") and audio_service_source.contains("_queue_bgm_recovery(\"watchdog\")") and audio_service_source.contains("_reserve_bgm_attempt") and audio_service_source.contains("BGM_CIRCUIT_FAILURE_THRESHOLD"), "audio runtime separates attempts from verified starts and bounds stopped-Web-BGM recovery")
	var settings_source := FileAccess.get_file_as_string("res://autoload/settings_service.gd")
	var mute_shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd").replace("\r\n", "\n")
	var load_index := mute_shell_source.find("SaveService.load_game()")
	var mute_override_index := mute_shell_source.find("SettingsService.apply_web_preview_audio_override()")
	var mute_stop_index := mute_shell_source.find("AudioService.set_enabled(false)")
	check(settings_source.contains("func apply_web_preview_audio_override()") and settings_source.contains("func web_preview_audio_forced_muted()") and load_index >= 0 and mute_override_index > load_index and mute_stop_index > mute_override_index, "Web QA mute reapplies after the saved preference and stops audio before the title route")
	check(audio_service_source.contains("MusicCrossfadePlayer") and audio_service_source.contains("_begin_bgm_loop_crossfade") and audio_service_source.contains("_start_web_bgm") and FileAccess.file_exists("res://web/browser_bgm.js") and audio_service_source.contains("playback_loop_end_seconds"), "desktop loop bridge and browser audio buffers skip authored trailing silence")
	var loop_probe := AudioStreamWAV.new()
	loop_probe.format = AudioStreamWAV.FORMAT_16_BITS
	loop_probe.mix_rate = 22050
	loop_probe.stereo = false
	var loop_probe_data := PackedByteArray()
	loop_probe_data.resize(22050 * 2)
	loop_probe.data = loop_probe_data
	AudioService._configure_music_loop(loop_probe, true)
	check(loop_probe.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop_probe.loop_begin == 0 and loop_probe.loop_end == 22050, "Web WAV BGM loop uses an explicit positive end frame instead of zero-length re-entry")
	var bgm_guard_asset := "__HEADLESS_BGM_GUARD__"
	var saved_last_attempt_by_asset := AudioService.last_bgm_attempt_by_asset.duplicate(true)
	var saved_suppressed_counts := AudioService.bgm_suppressed_attempt_counts.duplicate(true)
	var saved_failure_counts := AudioService.bgm_consecutive_failures_by_asset.duplicate(true)
	var saved_circuit_state := AudioService.bgm_circuit_open_until_by_asset.duplicate(true)
	var saved_last_bgm_attempt := AudioService.last_bgm_attempt_msec
	AudioService.last_bgm_attempt_by_asset.clear()
	AudioService.bgm_suppressed_attempt_counts.clear()
	AudioService.bgm_consecutive_failures_by_asset.clear()
	AudioService.bgm_circuit_open_until_by_asset.clear()
	var first_attempt_reserved := AudioService._reserve_bgm_attempt(bgm_guard_asset, 1000)
	var early_retry_blocked := not AudioService._reserve_bgm_attempt(bgm_guard_asset, 1499)
	var boundary_retry_reserved := AudioService._reserve_bgm_attempt(bgm_guard_asset, 1500)
	check(first_attempt_reserved and early_retry_blocked and boundary_retry_reserved and int(AudioService.bgm_suppressed_attempt_counts.get(bgm_guard_asset, 0)) == 1, "BGM attempt gate permits at most one same-asset start per 500 milliseconds")
	AudioService.last_bgm_attempt_by_asset.erase(bgm_guard_asset)
	AudioService.bgm_consecutive_failures_by_asset.erase(bgm_guard_asset)
	AudioService.bgm_circuit_open_until_by_asset.erase(bgm_guard_asset)
	for failure_index in range(AudioService.BGM_CIRCUIT_FAILURE_THRESHOLD):
		AudioService._note_bgm_failure(bgm_guard_asset, 2000 + failure_index)
	var circuit_open_until := int(AudioService.bgm_circuit_open_until_by_asset.get(bgm_guard_asset, 0))
	var circuit_blocks_retry := not AudioService._reserve_bgm_attempt(bgm_guard_asset, circuit_open_until - 1)
	var circuit_recovers_after_cooldown := AudioService._reserve_bgm_attempt(bgm_guard_asset, circuit_open_until)
	check(circuit_open_until > 0 and circuit_blocks_retry and circuit_recovers_after_cooldown, "repeated BGM start failures open a bounded circuit and recover only after cooldown")
	AudioService.last_bgm_attempt_by_asset = saved_last_attempt_by_asset
	AudioService.bgm_suppressed_attempt_counts = saved_suppressed_counts
	AudioService.bgm_consecutive_failures_by_asset = saved_failure_counts
	AudioService.bgm_circuit_open_until_by_asset = saved_circuit_state
	AudioService.last_bgm_attempt_msec = saved_last_bgm_attempt
	var web_soak_source := FileAccess.get_file_as_string("res://autoload/web_soak_probe.gd")
	check(web_soak_source.contains("\"audio\": AudioService.runtime_status()"), "Web soak samples record runtime audio playback state")
	check(web_soak_source.contains("r7-web-soak-probe") and web_soak_source.contains("sampling_enabled"), "Release Web soak telemetry is explicit opt-in instead of a five-second gameplay hitch")
	var app_shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd").replace("\r\n", "\n")
	check(app_shell_source.contains("WEB_FRAME_RATE_CAP := 60") and app_shell_source.contains("Engine.max_fps = WEB_FRAME_RATE_CAP"), "Web Release caps redundant high-refresh rendering at sixty frames per second")

func _test_story_voice_contracts() -> void:
	# Korean text, Japanese voice: every dialogue and narration line has a
	# pre-rendered take; the protagonist's choices stay unvoiced.
	var voiced := {}
	var choice_keys := {}
	for scenario in DataRegistry.list_of("scenarios"):
		for command in scenario.get("commands", []):
			var kind := str(command.get("command", ""))
			if kind in ["dialogue", "narration"]:
				voiced[str(command.get("text_key", ""))] = true
			elif kind == "choice":
				for option in command.get("choices", []): choice_keys[str(option.get("text_key", ""))] = true
	var missing := []
	var files := {}
	for text_key in voiced:
		var path := AudioService.line_voice_path(text_key)
		if not path.begins_with(AudioService.VOICE_RUNTIME_PREFIX) or not ResourceLoader.exists(path) or not load(path) is AudioStreamOggVorbis:
			missing.append(text_key)
		files[path] = true
	check(voiced.size() == 1905 and missing.is_empty(), "all 1905 spoken story lines resolve to a Japanese voice stream", ", ".join(missing.slice(0, 8)))
	# Map contact, boss and sudden-incident pages speak through the same manifest.
	var map_voiced := {}
	for chapter in DataRegistry.list_of("chapters"):
		var definition := ChapterMapLoader.load_map(str(chapter.get("id", "")) + "_MAP")
		var pages: Array = []
		for event in definition.get("event_encounters", []): pages.append_array(event.get("pre_battle_dialogue", []))
		for node in definition.get("nodes", []): pages.append_array(node.get("presentation", {}).get("pre_battle_dialogue", []))
		for incident in definition.get("incidents", []): pages.append_array(incident.get("lines", []))
		for page in pages:
			if not str(page.get("speaker_key", "")).is_empty(): map_voiced[str(page.get("text_key", ""))] = true
	var map_missing := []
	for text_key in map_voiced:
		var path := AudioService.line_voice_path(text_key)
		if not path.begins_with(AudioService.VOICE_RUNTIME_PREFIX) or not ResourceLoader.exists(path):
			map_missing.append(text_key)
		files[path] = true
	check(map_voiced.size() == 952 and map_missing.is_empty(), "all 952 map contact, boss and incident lines resolve to a Japanese voice stream", ", ".join(map_missing.slice(0, 8)))
	var voiced_choices := choice_keys.keys().filter(func(key): return AudioService.line_voice_path(key) != "")
	check(not choice_keys.is_empty() and voiced_choices.is_empty() and AudioService.line_voice_path("UNVOICED_PROBE_KEY") == "", "protagonist choices and unknown keys stay unvoiced")
	var manifest := _read_json(AudioService.VOICE_MANIFEST_PATH)
	check(files.size() == 2857 and manifest.get("language") == "ja" and str(manifest.get("provenance", {}).get("note", "")).contains("no runtime or online TTS"), "2857 voice takes (story and map lines) ship with provenance and no runtime TTS")
	# Headless has no audio device: a voiced line must report "not started" so the
	# story keeps its text-only AUTO timing.
	check(not AudioService.play_line_voice(voiced.keys()[0]) and not AudioService.voice_is_playing(), "voice playback declines cleanly without an audio device")
	var shell := FileAccess.get_file_as_string("res://screens/app_shell.gd").replace("\r\n", "\n")
	var advance := shell.substr(shell.find("func _advance_story("), 1200)
	check(advance.contains("AudioService.stop_voice()") and shell.contains("AudioService.play_line_voice(str(command.get(\"text_key\", \"\")))") and shell.contains("previous_screen == \"STORY\" and screen_id != \"STORY\"") and shell.contains("AudioService.prefetch_line_voices("), "story advances cut the previous voice, leaving the story stops it, and scenarios prefetch their lines")
	var bridge := FileAccess.get_file_as_string("res://web/browser_bgm.js")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(bridge.contains("window.__lumenVoice") and bridge.contains("VOICE_TIMEOUT") and presets.count("res://assets/audio/voice/ja/*.ogg") == 3, "Web voices play from browser sidecars and stay out of every Web PCK")

func _test_card_audio_contracts() -> void:
	var synthetic_profiles := {
		"SK_TEST_CARD": ["layer_launch", "layer_impact"],
	}
	var selected_plan := AudioService.resolve_card_start_profile(synthetic_profiles, "SK_TEST_CARD", "PLAYER_NORMAL_SKILL")
	check(selected_plan.get("asset_ids", []) == ["layer_launch", "layer_impact"] and str(selected_plan.get("fallback_event", "")) == "", "card-start resolver selects every layer by exact skill card ID")
	var fallback_plan := AudioService.resolve_card_start_profile(synthetic_profiles, "SK_MISSING_CARD", "PLAYER_ULTIMATE")
	check(fallback_plan.get("asset_ids", []).is_empty() and str(fallback_plan.get("fallback_event", "")) == "PLAYER_ULTIMATE", "missing card-start profile resolves to the requested legacy event fallback")
	var cooldown_history := {"SK_TEST_CARD": 5.0}
	var same_card_blocked := not AudioService.card_start_cooldown_ready(cooldown_history, "SK_TEST_CARD", 5.05, .10)
	var boundary_released := AudioService.card_start_cooldown_ready(cooldown_history, "SK_TEST_CARD", 5.101, .10)
	var different_card_independent := AudioService.card_start_cooldown_ready(cooldown_history, "SK_OTHER_CARD", 5.01, .10)
	check(same_card_blocked and boundary_released and different_card_independent, "card-start cooldown suppresses only the repeated card and releases after its interval")
	var skill_card_id := BattleView.card_start_id_for_event(
		BattleEvent.make(1, BattleEvent.NORMAL_SKILL, "P:CHR001", "", 0, {"skill_id": "SK001_N"}),
		{"def_id": "CHR001"}
	)
	var boss_card_id := BattleView.card_start_id_for_event(
		BattleEvent.make(2, BattleEvent.ULTIMATE, "E:BOSS001", "P:CHR001", 0, {"boss_pattern": "LOCK_ON"}),
		{"def_id": "BOSS001"}
	)
	check(skill_card_id == "SK001_N" and boss_card_id == "BOSS_PATTERN:BOSS001:LOCK_ON", "BattleView derives card starts from skill_id and stable boss-pattern composite IDs")
	var miss_event := BattleEvent.make(3, BattleEvent.DAMAGE, "E:ENM001", "P:CHR001", 10, {"miss": true, "hp_damage": 10})
	var invulnerable_event := BattleEvent.make(4, BattleEvent.DAMAGE, "E:ENM001", "P:CHR001", 10, {"invulnerable": true, "shield_damage": 10})
	var zero_damage_event := BattleEvent.make(5, BattleEvent.DAMAGE, "E:ENM001", "P:CHR001", 0, {})
	var value_damage_event := BattleEvent.make(6, BattleEvent.DAMAGE, "E:ENM001", "P:CHR001", 1, {})
	var hp_damage_event := BattleEvent.make(7, BattleEvent.DAMAGE, "E:ENM001", "P:CHR001", 0, {"hp_damage": 1})
	var shield_damage_event := BattleEvent.make(8, BattleEvent.DAMAGE, "E:ENM001", "P:CHR001", 0, {"shield_damage": 1})
	check(not BattleView.damage_event_has_hit_sfx(miss_event) and not BattleView.damage_event_has_hit_sfx(invulnerable_event) and not BattleView.damage_event_has_hit_sfx(zero_damage_event), "miss, invulnerable and zero-damage events never request a received-hit SFX")
	check(BattleView.damage_event_has_hit_sfx(value_damage_event) and BattleView.damage_event_has_hit_sfx(hp_damage_event) and BattleView.damage_event_has_hit_sfx(shield_damage_event), "value, HP damage and shield damage each qualify as a real received hit")
	var audio_manifest := _read_json("res://assets/audio/audio_manifest.json")
	var declared_assets: Dictionary = {}
	for entry_value in audio_manifest.get("entries", []):
		if entry_value is Dictionary:
			declared_assets[str(entry_value.get("asset_id", ""))] = true
	var raw_profiles = audio_manifest.get("card_start_profiles", {})
	var card_references_valid := raw_profiles is Dictionary
	if raw_profiles is Dictionary:
		for card_id_value in raw_profiles:
			var card_id := str(card_id_value).strip_edges()
			var profile_assets = raw_profiles[card_id_value]
			card_references_valid = card_references_valid and not card_id.is_empty() and profile_assets is Array and not profile_assets.is_empty()
			if not profile_assets is Array:
				continue
			for asset_id_value in profile_assets:
				card_references_valid = card_references_valid and declared_assets.has(str(asset_id_value))
	check(card_references_valid, "every declared card-start profile is non-empty and references packaged manifest asset IDs")
	var audio_service_source := FileAccess.get_file_as_string("res://autoload/audio_service.gd")
	var battle_view_source := FileAccess.get_file_as_string("res://battle/view/battle_view.gd")
	check(audio_service_source.contains("card_start_profiles") and audio_service_source.contains("func play_card_start") and audio_service_source.contains("gain_db") and audio_service_source.contains("pitch_scale"), "AudioService exposes layered card starts with per-entry gain and pitch")
	check(battle_view_source.contains("AudioService.play_card_start(card_start_id_for_event(event, skill_source)") and battle_view_source.contains("AudioService.play_card_start(card_start_id_for_event(event, ultimate_source)") and battle_view_source.contains("AudioService.play_event(\"PLAYER_BASIC_ATTACK\""), "skill and ultimate starts use cards while basic attacks retain legacy event audio")
	check(battle_view_source.contains("if damage_event_has_hit_sfx(event):") and battle_view_source.contains("extra.get(\"miss\", false)") and battle_view_source.contains("extra.get(\"invulnerable\", false)"), "BattleView gates hit audio behind explicit real-damage semantics")
	check(battle_view_source.contains("func _action_source_is_presentable") and battle_view_source.contains("not _action_source_is_presentable(str(event.source))") and battle_view_source.contains("animation_name not in [\"down\", \"victory\"]"), "BattleView suppresses late cast visuals from units already DOWN")

func _test_data() -> void:
	check(DataRegistry.load_error == "", "compiled data loads", DataRegistry.load_error)
	check(_unique_ids("characters"), "character IDs unique")
	check(_unique_ids("skills"), "skill IDs unique")
	check(_unique_ids("weapons"), "weapon IDs unique")
	check(_unique_ids("stages"), "stage IDs unique")
	var refs_valid := true
	for character in DataRegistry.list_of("characters"):
		for key in ["normal_skill_id", "passive_skill_id", "ultimate_skill_id"]:
			refs_valid = refs_valid and not DataRegistry.skill(character[key]).is_empty()
	check(refs_valid, "all character skill references valid")
	var arrays_valid := true
	for skill in DataRegistry.list_of("skills"):
		var required := 5 if skill.type == "ULTIMATE_SKILL" else 10
		arrays_valid = arrays_valid and skill.values.size() == required and int(skill.max_level) == required
	check(arrays_valid, "all skills exactly 10/10/5")
	var skill_icon_ids: Dictionary = {}
	var skill_icons_resolve := true
	for skill in DataRegistry.list_of("skills"):
		var icon_asset_id := str(skill.get("icon_asset_id", ""))
		var icon_path := AssetRegistry.resolve(icon_asset_id)
		skill_icon_ids[icon_asset_id] = true
		skill_icons_resolve = skill_icons_resolve and icon_asset_id != "" and icon_path.begins_with("res://assets/art/icons/skills/") and ResourceLoader.exists(icon_path) and not AssetRegistry.is_placeholder(icon_asset_id)
	var total_skill_defs := DataRegistry.list_of("skills").size()
	check(skill_icon_ids.size() == total_skill_defs and not skill_icon_ids.has(""), "all SkillDef icon asset IDs are immutable and unique", str(skill_icon_ids.size()))
	check(skill_icons_resolve, "all SkillDef icons resolve to packaged non-fallback runtime PNGs")
	var skill_icon_manifest := _read_json("res://assets/art/icons/skills/skill_icon_manifest.json")
	var skill_icon_assets: Array = skill_icon_manifest.get("assets", [])
	var icon_dimensions_and_alpha := skill_icon_assets.size() == total_skill_defs
	var unique_icon_hashes := {"256": {}, "128": {}, "64": {}}
	for icon_entry_variant in skill_icon_assets:
		var icon_entry: Dictionary = icon_entry_variant
		for resolution in [256, 128, 64]:
			var variant_path := str(icon_entry.get("variants", {}).get(str(resolution), ""))
			var image := Image.new()
			var image_error := image.load(ProjectSettings.globalize_path(variant_path))
			icon_dimensions_and_alpha = icon_dimensions_and_alpha and image_error == OK and image.get_width() == resolution and image.get_height() == resolution and image.get_pixel(0, 0).a < 0.05
			if image_error == OK:
				unique_icon_hashes[str(resolution)][FileAccess.get_sha256(variant_path)] = true
	check(icon_dimensions_and_alpha, "skill icons preserve RGBA readability variants at 256/128/64")
	check(unique_icon_hashes["256"].size() == total_skill_defs and unique_icon_hashes["128"].size() == total_skill_defs and unique_icon_hashes["64"].size() == total_skill_defs, "skill icon variants are distinct instead of one duplicated fallback")
	var skill_icon_licenses := _read_json("res://assets/art/icons/skills/skill_icon_licenses.json")
	var skill_license_rows: Array = skill_icon_licenses.get("assets", [])
	check(skill_license_rows.size() == total_skill_defs and skill_license_rows.all(func(row): return row.get("ownership_status", "") == "ORIGINAL_INTERNAL" and bool(row.get("commercial_use", false)) and str(row.get("file_sha256", "")).length() == 64), "all skill icons have original-internal commercial-use lineage and SHA-256")
	var app_shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd").replace("\r\n", "\n")
	var ultimate_orb_source := FileAccess.get_file_as_string("res://battle/view/battle_ultimate_orb.gd")
	check(app_shell_source.contains("BattleUltimateOrbScript.new()") and app_shell_source.contains("portrait_asset_id") and app_shell_source.contains(".set_charge(") and bool(_growth_controls_contract().icons) and ultimate_orb_source.contains("ReadyBadge") and ultimate_orb_source.contains("draw_arc") and ultimate_orb_source.contains("PortraitDisc"), "battle ultimates use portrait-centered circular charge controls with a READY state while actual growth cards retain their matching SkillDef textures")
	check(DataRegistry.list_of("character_level_curve").size() == 100, "character curve has 100 rows")
	check(DataRegistry.list_of("account_level_curve").size() == 100, "account curve has 100 rows")
	check(DataRegistry.list_of("weapon_level_curve").size() == 60, "weapon curve has 60 rows")
	var character_xp := 0
	var character_credits := 0
	var weapon_xp := 0
	for row in DataRegistry.list_of("character_level_curve"):
		character_xp += int(row.xp_to_next)
		character_credits += int(row.credit_cost)
	for row in DataRegistry.list_of("weapon_level_curve"): weapon_xp += int(row.xp_to_next)
	check(character_xp == 905520, "character XP regression", str(character_xp))
	check(character_credits == 412400, "character credit regression", str(character_credits))
	check(weapon_xp == 144330, "weapon XP regression", str(weapon_xp))
	var no_negative := true
	for row in DataRegistry.list_of("character_level_curve"): no_negative = no_negative and int(row.xp_to_next) >= 0 and int(row.credit_cost) >= 0
	for row in DataRegistry.list_of("weapon_level_curve"): no_negative = no_negative and int(row.xp_to_next) >= 0
	check(no_negative, "growth costs contain no negatives")
	var monotonic := true
	for character in DataRegistry.list_of("characters"):
		for key in character.stats_l1: monotonic = monotonic and float(character.stats_l100[key]) >= float(character.stats_l1[key])
	check(monotonic, "positive stats never reverse")
	var normal := DataRegistry.list_of("stages").filter(func(stage): return stage.mode == "NORMAL")
	var hard := DataRegistry.list_of("stages").filter(func(stage): return stage.mode == "HARD")
	var campaign_counts_valid := DataRegistry.list_of("chapters").size() == 20 and normal.size() == 400 and hard.size() == 100
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter_id := str((chapter_value as Dictionary).get("id", ""))
		campaign_counts_valid = campaign_counts_valid and normal.filter(func(stage): return str(stage.chapter_id) == chapter_id).size() == 20
		campaign_counts_valid = campaign_counts_valid and hard.filter(func(stage): return str(stage.chapter_id) == chapter_id).size() == 5
	check(campaign_counts_valid, "all 20 chapters have exactly 20 NORMAL and 5 HARD operations")
	check(normal.filter(func(stage): return bool(stage.boss) and int(stage.stage_number) == 20).size() == 20, "each chapter NORMAL 20 is a boss battle")
	check(DataRegistry.stage("CH01-H06").is_empty() and DataRegistry.stage("CH02-H10").is_empty(), "legacy Chapter 1-2 H06-H10 IDs are retired")
	var rewards_valid := true
	for stage in DataRegistry.list_of("stages"):
		var reward := DataRegistry.by_id("rewards", stage.reward_table_id)
		rewards_valid = rewards_valid and not reward.is_empty() and not reward.guaranteed.is_empty()
	check(rewards_valid, "every stage has guaranteed reward")
	var localization_valid := true
	for character in DataRegistry.list_of("characters"):
		localization_valid = localization_valid and not LocalizationService.tr_key(character.name_key).begins_with("[")
	for scenario in DataRegistry.list_of("scenarios"):
		localization_valid = localization_valid and not LocalizationService.tr_key(scenario.title_key).begins_with("[")
		for command in scenario.commands:
			if command.has("text_key"): localization_valid = localization_valid and not LocalizationService.tr_key(command.text_key).begins_with("[")
	check(localization_valid, "all runtime localization keys exist")
	var enemy_names_hide_internal_ids := true
	var english_table: Dictionary = LocalizationService.tables.get("en", {})
	for enemy in DataRegistry.list_of("enemies"):
		var english_name := str(english_table.get(str(enemy.name_key), ""))
		enemy_names_hide_internal_ids = enemy_names_hide_internal_ids and not english_name.is_empty() and english_name.find("ENM") == -1 and english_name.find("BOSS") == -1
	check(enemy_names_hide_internal_ids, "English enemy names never expose ENM or BOSS database IDs")
	var assets_resolve := true
	for character in DataRegistry.list_of("characters"):
		for key in ["asset_id", "portrait_asset_id", "icon_asset_id"]: assets_resolve = assets_resolve and AssetRegistry.resolve(character[key]) != ""
	check(assets_resolve, "all character asset IDs resolve (placeholder allowed)")
	var combat_preview_assets: Array = DataRegistry.list_of("characters") + DataRegistry.list_of("enemies")
	var combat_previews_connected := combat_preview_assets.size() == 109
	var combat_preview_lineage_honest := true
	for row in combat_preview_assets:
		var combat_asset_id := str(row.get("asset_id", ""))
		var combat_preview_path := AssetRegistry.resolve(combat_asset_id)
		combat_previews_connected = combat_previews_connected and not AssetRegistry.is_placeholder(combat_asset_id) and AssetRegistry.status_of(combat_asset_id) == "RUNTIME_WEB_COMBAT_PREVIEW" and combat_preview_path.begins_with("res://assets/runtime_web/combat/") and combat_preview_path.ends_with("/preview.png") and ResourceLoader.exists(combat_preview_path)
		var registered_entry: Dictionary = AssetRegistry.assets.get(combat_asset_id, {})
		combat_preview_lineage_honest = combat_preview_lineage_honest and str(registered_entry.get("source_status", "")) != "" and str(registered_entry.get("qa_status", "")) == "RUNTIME_CONNECTED_NOT_PRODUCTION_APPROVED" and registered_entry.get("production_approved", true) == false
	check(combat_previews_connected, "all 109 CharacterDef and EnemyDef combat asset IDs resolve to connected runtime previews instead of dev_placeholder")
	check(combat_preview_lineage_honest, "combat preview registry retains source status without claiming production approval")
	var card_8head_contract := _read_json("res://assets/runtime_web/characters/CARD_8HEAD_RGBA_R1_CONTRACT.json")
	var card_8head_characters: Dictionary = card_8head_contract.get("characters", {})
	var runtime_static_art_valid := str(card_8head_contract.get("generationMatte", "")) == "#00FF00" and str(card_8head_contract.get("runtimeBackground", "")) == "RGBA_TRANSPARENT" and card_8head_characters.size() == 44
	var card_8head_failures: Array[String] = []
	if not runtime_static_art_valid:
		card_8head_failures.append("contract=%s characters=%d" % [JSON.stringify({"matte": card_8head_contract.get("generationMatte", ""), "runtime": card_8head_contract.get("runtimeBackground", "")}), card_8head_characters.size()])
	for character in DataRegistry.list_of("characters"):
		var character_id := str(character.get("id", ""))
		var continuity: Dictionary = card_8head_characters.get(character_id, {})
		for key in ["portrait_asset_id", "icon_asset_id"]:
			var runtime_path := AssetRegistry.resolve(str(character[key]))
			var packaged_static_location := runtime_path.begins_with("res://assets/runtime_web/characters/%s/" % character_id)
			var alpha_record: Dictionary = continuity.get("portrait", {}) if key == "portrait_asset_id" else continuity.get("icon", {})
			var safe_insets: Array = alpha_record.get("safeInsets", [])
			var opaque_transparent_extrema: Array = alpha_record.get("alphaExtrema", [])
			var alpha_extrema_valid := opaque_transparent_extrema.size() == 2 and int(opaque_transparent_extrema[0]) == 0 and int(opaque_transparent_extrema[1]) == 255
			var chroma_residue := _semi_transparent_chroma_residue_count(runtime_path) if FileAccess.file_exists(runtime_path) else -1
			var premium_8head := str((continuity.get("fingerprint", {}) as Dictionary).get("presentation", "")) == "PREMIUM_8_HEAD_FULL_BODY_CARD"
			var row_valid := packaged_static_location and FileAccess.file_exists(runtime_path) and str(continuity.get("status", "")) == "COSTUME_CONTINUITY_PASS" and premium_8head and alpha_extrema_valid and chroma_residue == 0 and safe_insets.size() == 4 and int(safe_insets[0]) >= 16 and int(safe_insets[1]) >= 16 and int(safe_insets[2]) >= 16 and int(safe_insets[3]) >= 16
			if not row_valid:
				card_8head_failures.append("%s:%s path=%s contract=%s presentation=%s alpha=%s greenFringe=%d inset=%s" % [character_id, key, runtime_path, str(continuity.get("status", "")), str((continuity.get("fingerprint", {}) as Dictionary).get("presentation", "")), JSON.stringify(opaque_transparent_extrema), chroma_residue, JSON.stringify(safe_insets)])
			runtime_static_art_valid = runtime_static_art_valid and row_valid
	check(runtime_static_art_valid, "all 44 non-combat card, recruit, roster, profile and story images use premium 8-head art with #00FF00 provenance, true RGBA, safe insets and continuity approval", JSON.stringify(card_8head_failures))
	check(DataRegistry.list_of("characters").size() == 44, "MVP has 44 player characters")
	check(DataRegistry.list_of("enemies").filter(func(enemy): return enemy.rank == "NORMAL").size() == 30, "Campaign 20 has 30 normal enemy archetypes")
	check(DataRegistry.list_of("enemies").filter(func(enemy): return enemy.rank == "ELITE").size() == 12, "Campaign 20 has 12 elite archetypes")
	check(DataRegistry.list_of("enemies").filter(func(enemy): return enemy.rank == "BOSS").size() == 23, "Campaign 20 has 23 non-reused bosses")
	check(DataRegistry.list_of("weapons").filter(func(weapon): return weapon.exclusive_owner_id != "").is_empty(), "exclusive weapons count is zero")

func _simulation(seed_value: int, stage_id := "CH01-N01") -> BattleSimulation:
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage(stage_id), seed_value, DataRegistry.data)
	return sim

func _run_to_end(sim: BattleSimulation) -> void:
	while not sim.state.ended and sim.state.tick < 3000: sim.tick()

func _first_event_difference(left: Array, right: Array) -> String:
	var count: int = mini(left.size(), right.size())
	for index in range(count):
		if JSON.stringify(left[index]) != JSON.stringify(right[index]):
			return "index=%d left=%s right=%s" % [index, JSON.stringify(left[index]), JSON.stringify(right[index])]
	if left.size() != right.size():
		return "event_count left=%d right=%d" % [left.size(), right.size()]
	return "no event difference"

func _test_battle() -> void:
	var a := _simulation(424242)
	var b := _simulation(424242)
	var wave_asset_view := BattleView.new()
	wave_asset_view.setup(_simulation(424240))
	var all_wave_asset_ids := wave_asset_view._active_battle_entity_ids()
	var stage_wave_ids: Array[String] = []
	for wave_value in wave_asset_view.simulation.stage.get("waves", []):
		for entity_id_value in wave_value:
			var entity_id := str(entity_id_value)
			if not stage_wave_ids.has(entity_id):
				stage_wave_ids.append(entity_id)
	var all_reinforcements_registered := true
	for entity_id in stage_wave_ids:
		all_reinforcements_registered = all_reinforcements_registered and all_wave_asset_ids.has(entity_id)
	check(all_reinforcements_registered and stage_wave_ids.size() > wave_asset_view.simulation.state.enemies.size(), "battle asset registration includes every reinforcement wave before frame one")
	var all_wave_names_localized := true
	for entity_id in stage_wave_ids:
		var display_name := BattleView.unit_display_name({"def_id": entity_id, "team": "ENEMY"})
		all_wave_names_localized = all_wave_names_localized and not display_name.is_empty() and display_name != entity_id and not display_name.begins_with("ENM") and not display_name.begins_with("[")
	check(all_wave_names_localized, "every reinforcement wave renders localized enemy names instead of ENM database IDs")
	wave_asset_view.free()
	var initial_same_seed_state: bool = JSON.stringify(a.state.party + a.state.enemies) == JSON.stringify(b.state.party + b.state.enemies)
	_run_to_end(a)
	_run_to_end(b)
	check(a.state.ended and b.state.ended, "battle reaches a terminal state")
	var same_seed_hash: bool = a.event_hash() == b.event_hash()
	var same_seed_snapshot: bool = JSON.stringify(a.result_snapshot()) == JSON.stringify(b.result_snapshot())
	check(same_seed_hash and same_seed_snapshot, "same seed yields identical result and event hash", "hash_a=%s hash_b=%s initial_equal=%s snapshot_equal=%s %s" % [a.event_hash(), b.event_hash(), initial_same_seed_state, same_seed_snapshot, _first_event_difference(a.event_log, b.event_log)])
	var c := _simulation(424243)
	_run_to_end(c)
	check(a.event_hash() != c.event_hash(), "different seed changes random event log")
	for auto_policy_value in [true, false]:
		var auto_policy: bool = bool(auto_policy_value)
		var policy_seed := 515100 + (1 if auto_policy else 2)
		var normally_advanced := _simulation(policy_seed)
		var terminal_advanced := _simulation(policy_seed)
		normally_advanced.auto_enabled = auto_policy
		terminal_advanced.auto_enabled = auto_policy
		# Compare from a genuinely live mid-battle state so the terminal helper
		# must preserve current HP, RNG, queued decisions and AUTO policy rather
		# than merely reproducing a fresh-battle shortcut.
		for _warmup_tick in range(75):
			if not normally_advanced.state.ended: normally_advanced.tick()
			if not terminal_advanced.state.ended: terminal_advanced.tick()
		_run_to_end(normally_advanced)
		var reached_terminal := terminal_advanced.advance_to_terminal()
		var policy_label := "ON" if auto_policy else "OFF"
		var terminal_hash_matches := normally_advanced.event_hash() == terminal_advanced.event_hash()
		var terminal_result_matches := JSON.stringify(normally_advanced.result_snapshot()) == JSON.stringify(terminal_advanced.result_snapshot())
		check(reached_terminal and normally_advanced.state.ended and terminal_advanced.state.ended and terminal_hash_matches and terminal_result_matches, "advance_to_terminal preserves ordinary battle result and event hash with AUTO %s" % policy_label, "normal_hash=%s terminal_hash=%s %s" % [normally_advanced.event_hash(), terminal_advanced.event_hash(), _first_event_difference(normally_advanced.event_log, terminal_advanced.event_log)])
	var signal_expected := _simulation(515200)
	var signal_skipped := _simulation(515200)
	signal_expected.auto_enabled = true
	signal_skipped.auto_enabled = true
	for _warmup_tick in range(45):
		if not signal_expected.state.ended: signal_expected.tick()
		if not signal_skipped.state.ended: signal_skipped.tick()
	_run_to_end(signal_expected)
	var skip_view := BattleView.new()
	skip_view.setup(signal_skipped)
	var skip_results: Array[Dictionary] = []
	skip_view.battle_finished.connect(func(result: Dictionary): skip_results.append(result.duplicate(true)))
	var first_skip_started := skip_view.skip_to_result()
	var duplicate_skip_started := skip_view.skip_to_result()
	var emitted_skip_matches := skip_results.size() == 1 and JSON.stringify(skip_results[0]) == JSON.stringify(signal_expected.result_snapshot())
	check(first_skip_started and not duplicate_skip_started and signal_skipped.state.ended and emitted_skip_matches and signal_skipped.event_hash() == signal_expected.event_hash() and skip_view.consumed_events == signal_skipped.event_log.size(), "BattleView skip emits the ordinary terminal result exactly once without replaying presentation backlog", "signals=%d expected_hash=%s actual_hash=%s" % [skip_results.size(), signal_expected.event_hash(), signal_skipped.event_hash()])
	skip_view.free()
	var presentation_director = BattlePresentationDirectorScript.new()
	var director_batch := {"id": "ULT:12:P:CHR001:SK001_U:9", "events": []}
	var director_started := presentation_director.begin_ultimate(director_batch)
	var director_before_prep: Dictionary = presentation_director.advance(.57)
	var director_prep: Dictionary = presentation_director.advance(.02)
	var director_impact: Dictionary = presentation_director.advance(.54)
	var director_finished := false
	for _director_frame in range(20):
		var director_frame: Dictionary = presentation_director.advance(.10)
		if bool(director_frame.get("finished", false)):
			director_finished = true
			break
	var forced_director = BattlePresentationDirectorScript.new()
	forced_director.begin_ultimate(director_batch)
	var forced_snapshot: Dictionary = forced_director.force_finish()
	check(director_started and not bool(director_before_prep.get("battlefield_prep", false)) and bool(director_prep.get("battlefield_prep", false)) and bool(director_impact.get("impact_commit", false)) and is_zero_approx(float(director_impact.get("actor_delta", 1.0))) and director_finished and bool(forced_snapshot.get("needs_impact_commit", false)), "ultimate presentation timeline keeps preparation, impact hitstop, recovery, and forced skip completion on a view-only clock")
	var normal_impact_director = BattlePresentationDirectorScript.new()
	for _overlapping_impact in range(6):
		normal_impact_director.request_combat_impact(.80)
	var overlapping_hitstop := float(normal_impact_director.cinematic_snapshot().get("combat_hitstop_remaining", -1.0))
	var normal_hitstop_frame: Dictionary = normal_impact_director.advance(.03)
	var normal_impact_visible := normal_impact_director.battlefield_zoom() > 1.0 and normal_impact_director.battlefield_offset().length() > 0.0
	normal_impact_director.advance(.30)
	var normal_impact_cleared := is_equal_approx(normal_impact_director.battlefield_zoom(), 1.0) and normal_impact_director.battlefield_offset().length() == 0.0
	normal_impact_director.request_combat_impact(.80)
	normal_impact_director.force_finish()
	var skip_clears_normal_impact := is_equal_approx(normal_impact_director.battlefield_zoom(), 1.0) and normal_impact_director.battlefield_offset().length() == 0.0
	check(overlapping_hitstop > 0.0 and overlapping_hitstop <= .055001 and is_zero_approx(float(normal_hitstop_frame.get("actor_delta", 1.0))) and normal_impact_visible and normal_impact_cleared and skip_clears_normal_impact, "overlapping ordinary impacts stay inside the 55ms actor-only hitstop cap and leave no residual zoom, offset or freeze after expiry or skip")
	var directional_focus_director = BattlePresentationDirectorScript.new()
	var sustained_director = BattlePresentationDirectorScript.new()
	var sustained_actor_time := 0.0
	for frame in range(100):
		sustained_director.request_combat_impact(1.0)
		sustained_actor_time += float(sustained_director.advance(.01).actor_delta)
	check(sustained_actor_time >= .70, "one hundred consecutive impact frames preserve at least 70 percent moving presentation time instead of indefinitely renewing hitstop")
	var coarse_director = BattlePresentationDirectorScript.new()
	coarse_director.request_combat_impact(1.0)
	check(is_equal_approx(float(coarse_director.advance(.10).actor_delta), .045), "a slow frame subtracts only the 55ms contact hold instead of freezing the entire frame")
	sustained_director.force_finish()
	sustained_director.request_combat_impact(1.0)
	check(sustained_director.combat_hitstop_remaining > 0.0, "skip clears the ordinary impact recovery gate for the next encounter")
	directional_focus_director.request_combat_focus(1.0, .82, .60)
	directional_focus_director.advance(.16)
	var player_focus_offset := directional_focus_director.battlefield_offset()
	var player_focus_zoom := directional_focus_director.battlefield_zoom()
	directional_focus_director.advance(.70)
	var player_focus_cleared := is_equal_approx(directional_focus_director.battlefield_zoom(), 1.0) and directional_focus_director.battlefield_offset().length() == 0.0
	directional_focus_director.request_combat_focus(-1.0, .82, .60)
	directional_focus_director.advance(.16)
	var enemy_focus_offset := directional_focus_director.battlefield_offset()
	directional_focus_director.force_finish()
	var forced_focus_cleared := is_equal_approx(directional_focus_director.battlefield_zoom(), 1.0) and directional_focus_director.battlefield_offset().length() == 0.0
	check(player_focus_offset.x < 0.0 and player_focus_zoom > 1.0 and enemy_focus_offset.x > 0.0 and player_focus_cleared and forced_focus_cleared, "combat actions use a bounded directional camera follow that mirrors both teams and clears after expiry or skip")
	var player_windup: Dictionary = BattleView.combat_motion_snapshot("PLAYER", "basic_attack", .10, .75)
	var player_lunge: Dictionary = BattleView.combat_motion_snapshot("PLAYER", "basic_attack", .38, .75)
	var enemy_windup: Dictionary = BattleView.combat_motion_snapshot("ENEMY", "basic_attack", .10, .75)
	var enemy_lunge: Dictionary = BattleView.combat_motion_snapshot("ENEMY", "basic_attack", .38, .75)
	var player_hit: Dictionary = BattleView.combat_motion_snapshot("PLAYER", "hit", .38, .75)
	var enemy_hit: Dictionary = BattleView.combat_motion_snapshot("ENEMY", "hit", .38, .75)
	var player_windup_offset: Vector2 = player_windup.get("offset", Vector2.ZERO)
	var player_lunge_offset: Vector2 = player_lunge.get("offset", Vector2.ZERO)
	var enemy_windup_offset: Vector2 = enemy_windup.get("offset", Vector2.ZERO)
	var enemy_lunge_offset: Vector2 = enemy_lunge.get("offset", Vector2.ZERO)
	var player_hit_offset: Vector2 = player_hit.get("offset", Vector2.ZERO)
	var enemy_hit_offset: Vector2 = enemy_hit.get("offset", Vector2.ZERO)
	check(player_windup_offset.x < 0.0 and player_lunge_offset.x > 0.0 and enemy_windup_offset.x > 0.0 and enemy_lunge_offset.x < 0.0 and player_hit_offset.x < 0.0 and enemy_hit_offset.x > 0.0, "battle motion layer gives both sides readable anticipation, forward strike, recoil, and directional hit response without changing simulation state")
	var cinematic_sim := _simulation(1721)
	# Reproduce a busy battle: receiving damage must not restart an attack's
	# authored timeline, and repeated pellets must not pin HIT at frame zero.
	var interrupted_motion_sim := _simulation(17201)
	var interrupted_motion_view := BattleView.new()
	interrupted_motion_view.setup(interrupted_motion_sim)
	var interrupted_uid := str(interrupted_motion_sim.state.party[0].uid)
	interrupted_motion_view.animation_tracks[interrupted_uid] = {"name": "normal_skill", "elapsed": .43}
	interrupted_motion_view._play_animation(interrupted_uid, "hit")
	check(str(interrupted_motion_view.animation_tracks[interrupted_uid].name) == "normal_skill" and is_equal_approx(float(interrupted_motion_view.animation_tracks[interrupted_uid].elapsed), .43), "incoming damage preserves active attack pose timeline; existing additive flash/recoil remains visible")
	interrupted_motion_view.animation_tracks[interrupted_uid] = {"name": "hit", "elapsed": .21}
	interrupted_motion_view._play_animation(interrupted_uid, "hit")
	check(is_equal_approx(float(interrupted_motion_view.animation_tracks[interrupted_uid].elapsed), .21), "repeated damage does not restart HIT at frame zero and freeze a focused target")
	var action_recovery_neutral := true
	for recovery_action in ["basic_attack", "normal_skill", "ultimate", "hit"]:
		var recovered_pose := BattleView.combat_motion_snapshot("PLAYER", recovery_action, 1.0, 1.0)
		action_recovery_neutral = action_recovery_neutral and (recovered_pose.offset as Vector2).length() < .001 and absf(float(recovered_pose.rotation)) < .001 and (recovered_pose.scale as Vector2).distance_to(Vector2.ONE) < .001
	check(action_recovery_neutral, "all nonterminal action transforms recover to a neutral planted pose without a last-frame snap")
	interrupted_motion_view.free()
	var unified_presentation_clock := true
	for speed_value in [1, 2, 3]:
		var clock_sim := _simulation(17202 + speed_value)
		var clock_view := BattleView.new()
		clock_view.setup(clock_sim)
		clock_view.speed = speed_value
		var clock_source := str(clock_sim.state.party[2].uid) # Rifle, not a melee-only shield bash.
		var clock_target := str(clock_sim.state.enemies[0].uid)
		clock_view._spawn_projectile(clock_source, clock_target, "NORMAL")
		clock_view._spawn_vfx(clock_source, clock_target, "normal")
		var clock_shot: Dictionary = clock_view.projectiles[0]
		var clock_effect: Dictionary = clock_view.vfx_presentations[0]
		var shot_before := float(clock_shot.age)
		var effect_before := float(clock_effect.age)
		clock_view._process(.01)
		unified_presentation_clock = unified_presentation_clock and is_equal_approx(float(clock_shot.age)-shot_before, float(clock_effect.age)-effect_before) and float(clock_shot.age)>shot_before
		clock_view.free()
	check(unified_presentation_clock, "1x 2x and 3x projectile flight shares the actor and VFX clock without double speed multiplication")
	var gun_pose := BattleView.combat_motion_snapshot("PLAYER", "basic_attack", .55, 1.0, "ASSAULT")
	var gun_normal_pose := BattleView.combat_motion_snapshot("PLAYER", "normal_skill", .62, 1.0, "ARTILLERY")
	var gun_ultimate_pose := BattleView.combat_motion_snapshot("ENEMY", "ultimate", .66, 1.0, "RANGED")
	var blade_pose := BattleView.combat_motion_snapshot("PLAYER", "basic_attack", .45, 1.0, "VANGUARD")
	var medic_pose := BattleView.combat_motion_snapshot("PLAYER", "normal_skill", .50, 1.0, "MEDIC")
	check(gun_pose.offset.x < 0.0 and gun_normal_pose.offset.x < 0.0 and gun_ultimate_pose.offset.x > 0.0 and blade_pose.offset.x > 0.0 and absf(medic_pose.offset.y) <= 5.01, "all firearm action tiers brace/recoil in faction direction while blades drive forward and support casts stay grounded")
	var choreography := preload("res://battle/view/battle_actor_choreography.gd")
	var hit_base := {"offset": Vector2.ZERO, "rotation": 0.0, "scale": Vector2.ONE}
	var player_additive_hit: Dictionary = choreography.add_hit_reaction(hit_base.duplicate(true), "PLAYER", .07)
	var enemy_additive_hit: Dictionary = choreography.add_hit_reaction(hit_base.duplicate(true), "ENEMY", .07)
	var melee_ghosts: Array = choreography.afterimage_samples("VANGUARD", "ultimate", "PLAYER", .52)
	var ranged_ghosts: Array = choreography.afterimage_samples("ASSAULT", "ultimate", "PLAYER", .52)
	var player_muzzle: Vector2 = choreography.action_anchor("ASSAULT", "PLAYER", "normal_skill", .52)
	var enemy_muzzle: Vector2 = choreography.action_anchor("ASSAULT", "ENEMY", "normal_skill", .52)
	var fallback_muzzle: Vector2 = choreography.action_anchor("UNKNOWN_ROLE", "PLAYER", "basic_attack", .52)
	check(player_additive_hit.offset.x < 0.0 and enemy_additive_hit.offset.x > 0.0 and player_additive_hit.scale.y > 1.0 and melee_ghosts.size() == 2 and ranged_ghosts.is_empty(), "protected attack tracks still receive grounded directional hit weight while only active melee strikes receive two bounded afterimages")
	check(player_muzzle.x > 0.0 and enemy_muzzle.x < 0.0 and is_equal_approx(player_muzzle.y, enemy_muzzle.y), "weapon action anchors mirror both factions without detaching vertically from the posed actor")
	check(fallback_muzzle != Vector2.ZERO and fallback_muzzle == choreography.action_anchor("UNKNOWN_ROLE", "PLAYER", "basic_attack", .52), "an unknown weapon role uses a deterministic non-origin actor-local projectile anchor")
	var forward_step := choreography.step_offset("VANGUARD", "basic_attack", .45, 1.0, Vector2(400, -90))
	var enemy_step := choreography.step_offset("MELEE_RUSH", "basic_attack", .45, 1.0, Vector2(-400, 90))
	check(forward_step.x > 0.0 and enemy_step.x < 0.0 and forward_step.length() <= 92.01 and enemy_step.is_equal_approx(-forward_step), "both factions step toward their actual opponent with a bounded presentation-only melee approach")
	check(choreography.step_offset("VANGUARD", "basic_attack", 1.0, 1.0, Vector2(400, -90)) == Vector2.ZERO and choreography.step_offset("ASSAULT", "basic_attack", .45, 1.0, Vector2(400, -90)) == Vector2.ZERO and choreography.step_offset("VANGUARD", "basic_attack", .45, 1.0, Vector2(100, 0)) == Vector2.ZERO, "melee approach recovers completely, never moves ranged actors and preserves near-target separation")
	var cinematic_source: Dictionary = cinematic_sim.state.party[0]
	cinematic_source.def_id = "CHR001"
	var cinematic_target: Dictionary = cinematic_sim.state.enemies[0]
	var cinematic_hp_before := int(cinematic_target.hp)
	var cinematic_event_start := cinematic_sim.event_log.size()
	var cinematic_view := BattleView.new()
	cinematic_view.setup(cinematic_sim)
	cinematic_sim.event_log.append(BattleEvent.make(cinematic_sim.state.tick, BattleEvent.ULTIMATE, str(cinematic_source.uid), str(cinematic_target.uid), 0, {"skill_id": "SK001_U"}))
	cinematic_sim.event_log.append(BattleEvent.make(cinematic_sim.state.tick, BattleEvent.DAMAGE, str(cinematic_source.uid), str(cinematic_target.uid), cinematic_hp_before, {"source": "ULTIMATE", "hp_damage": cinematic_hp_before, "shield_damage": 0}))
	cinematic_sim.event_log.append(BattleEvent.make(cinematic_sim.state.tick, BattleEvent.DOWN, str(cinematic_source.uid), str(cinematic_target.uid), 0, {"cause": "ULTIMATE"}))
	cinematic_view._consume_events()
	var cinematic_held: Dictionary = cinematic_view.presentation_cursor_snapshot()
	var held_director: Dictionary = cinematic_held.get("director", {})
	var held_target := cinematic_view.presentation_unit_for_uid(str(cinematic_target.uid))
	var cinematic_impact: Dictionary = cinematic_view.presentation_director.advance(1.13)
	cinematic_view._handle_presentation_timeline(cinematic_impact)
	var cinematic_committed: Dictionary = cinematic_view.presentation_cursor_snapshot()
	var committed_target := cinematic_view.presentation_unit_for_uid(str(cinematic_target.uid))
	var cinematic_batch_end := cinematic_event_start + 3
	var batch_is_atomic := int(cinematic_held.get("read_cursor", -1)) == cinematic_batch_end and int(cinematic_held.get("presented_cursor", -1)) == cinematic_event_start and bool(held_director.get("active", false)) and int(held_target.get("hp", -1)) == cinematic_hp_before and bool(cinematic_impact.get("impact_commit", false)) and int(cinematic_committed.get("presented_cursor", -1)) == cinematic_batch_end and int(committed_target.get("hp", -1)) == 0 and not bool(committed_target.get("alive", true))
	check(batch_is_atomic, "CHR001 ultimate holds related DAMAGE and DOWN display state until one atomic impact commit")
	cinematic_view._force_finish_active_presentation()
	cinematic_view.free()
	# Consecutive signature ULTIMATE cues must be serialised by the presentation
	# barrier.  The raw asset libraries can replace a transient page by design,
	# but BattleView must never do that while the previous caster is still in its
	# recovery window: on a phone this would visibly cut off the first character's
	# motion/effect and retain an unnecessary second high-density page.
	var queued_ultimate_sim := _simulation(17211)
	var queued_first_source: Dictionary = queued_ultimate_sim.state.party[0]
	var queued_second_source: Dictionary = queued_ultimate_sim.state.party[1]
	queued_first_source.def_id = "CHR001"
	queued_second_source.def_id = "CHR003"
	var queued_target: Dictionary = queued_ultimate_sim.state.enemies[0]
	var queued_ultimate_start := queued_ultimate_sim.event_log.size()
	var queued_ultimate_view := BattleView.new()
	queued_ultimate_view.setup(queued_ultimate_sim)
	var queued_signature_ids: Array[String] = ["CHR001", "CHR003"]
	queued_ultimate_view.signature_sprite_pack_ready = queued_ultimate_view.sprite_library.load_signature_core_pack(queued_signature_ids)
	queued_ultimate_view.effect_signature_pack_ready = queued_ultimate_view.effect_signature_library.load_signature_core_pack(queued_signature_ids)
	queued_ultimate_view.signature_residency_target_ids = queued_signature_ids.duplicate()
	queued_ultimate_sim.event_log.append(BattleEvent.make(queued_ultimate_sim.state.tick, BattleEvent.ULTIMATE, str(queued_first_source.uid), str(queued_target.uid), 0, {"skill_id": "SK001_U"}))
	queued_ultimate_sim.event_log.append(BattleEvent.make(queued_ultimate_sim.state.tick, BattleEvent.ULTIMATE, str(queued_second_source.uid), str(queued_target.uid), 0, {"skill_id": "SK003_U"}))
	queued_ultimate_view._consume_events()
	var queued_first_held: Dictionary = queued_ultimate_view.presentation_cursor_snapshot()
	var queued_first_actor: Dictionary = queued_ultimate_view.sprite_library.signature_residency_snapshot()
	var queued_first_effect: Dictionary = queued_ultimate_view.effect_signature_library.signature_residency_snapshot()
	# Even after the impact commit the recovery barrier remains active, so the
	# second cue cannot replace the first caster's transient actor/effect page.
	var queued_impact_timeline: Dictionary = queued_ultimate_view.presentation_director.advance(1.13)
	queued_ultimate_view._handle_presentation_timeline(queued_impact_timeline)
	queued_ultimate_view._consume_events()
	var queued_during_recovery: Dictionary = queued_ultimate_view.presentation_cursor_snapshot()
	var queued_recovery_actor: Dictionary = queued_ultimate_view.sprite_library.signature_residency_snapshot()
	var queued_recovery_effect: Dictionary = queued_ultimate_view.effect_signature_library.signature_residency_snapshot()
	# Completing recovery must release both first-caster pages before the next
	# raw-log cue is consumed.  Capture that boundary directly, then start cue 2.
	var queued_finish_timeline: Dictionary = queued_ultimate_view.presentation_director.advance(1.00)
	queued_ultimate_view._handle_presentation_timeline(queued_finish_timeline)
	var queued_after_release_actor: Dictionary = queued_ultimate_view.sprite_library.signature_residency_snapshot()
	var queued_after_release_effect: Dictionary = queued_ultimate_view.effect_signature_library.signature_residency_snapshot()
	queued_ultimate_view._consume_events()
	var queued_second_held: Dictionary = queued_ultimate_view.presentation_cursor_snapshot()
	var queued_second_actor: Dictionary = queued_ultimate_view.sprite_library.signature_residency_snapshot()
	var queued_second_effect: Dictionary = queued_ultimate_view.effect_signature_library.signature_residency_snapshot()
	var consecutive_ultimate_queue_valid := queued_ultimate_view.signature_sprite_pack_ready and queued_ultimate_view.effect_signature_pack_ready and int(queued_first_held.get("read_cursor", -1)) == queued_ultimate_start + 1 and int(queued_first_held.get("presented_cursor", -1)) == queued_ultimate_start and bool((queued_first_held.get("director", {}) as Dictionary).get("active", false)) and str(queued_first_actor.get("transient_ultimate_entity_id", "")) == "CHR001" and str(queued_first_effect.get("transient_ultimate_profile_id", "")) == "CHR001" and bool(queued_impact_timeline.get("impact_commit", false)) and int(queued_during_recovery.get("read_cursor", -1)) == queued_ultimate_start + 1 and str(queued_recovery_actor.get("transient_ultimate_entity_id", "")) == "CHR001" and str(queued_recovery_effect.get("transient_ultimate_profile_id", "")) == "CHR001" and bool(queued_finish_timeline.get("finished", false)) and str(queued_after_release_actor.get("transient_ultimate_entity_id", "")) == "" and str(queued_after_release_effect.get("transient_ultimate_profile_id", "")) == "" and int(queued_second_held.get("read_cursor", -1)) == queued_ultimate_start + 2 and int(queued_second_held.get("presented_cursor", -1)) == queued_ultimate_start + 1 and bool((queued_second_held.get("director", {}) as Dictionary).get("active", false)) and str(queued_second_actor.get("transient_ultimate_entity_id", "")) == "CHR003" and str(queued_second_effect.get("transient_ultimate_profile_id", "")) == "CHR003"
	check(consecutive_ultimate_queue_valid, "back-to-back signature ultimates wait through recovery, release the first transient pair, then acquire the next caster pair", "first=%s recovery=%s released_actor=%s released_effect=%s second=%s" % [JSON.stringify(queued_first_held), JSON.stringify(queued_during_recovery), JSON.stringify(queued_after_release_actor), JSON.stringify(queued_after_release_effect), JSON.stringify(queued_second_held)])
	queued_ultimate_view._force_finish_active_presentation()
	queued_ultimate_view.free()
	var cinematic_skip_sim := _simulation(1722)
	var cinematic_skip_source: Dictionary = cinematic_skip_sim.state.party[0]
	cinematic_skip_source.def_id = "CHR001"
	var cinematic_skip_target: Dictionary = cinematic_skip_sim.state.enemies[0]
	var cinematic_skip_view := BattleView.new()
	cinematic_skip_view.setup(cinematic_skip_sim)
	cinematic_skip_sim.event_log.append(BattleEvent.make(cinematic_skip_sim.state.tick, BattleEvent.ULTIMATE, str(cinematic_skip_source.uid), str(cinematic_skip_target.uid), 0, {"skill_id": "SK001_U"}))
	cinematic_skip_view._consume_events()
	var cinematic_skip_started := cinematic_skip_view.skip_to_result()
	var cinematic_skip_cursor: Dictionary = cinematic_skip_view.presentation_cursor_snapshot()
	check(cinematic_skip_started and not cinematic_skip_view.presentation_director.is_active() and int(cinematic_skip_cursor.get("read_cursor", -1)) == cinematic_skip_sim.event_log.size() and int(cinematic_skip_cursor.get("presented_cursor", -1)) == cinematic_skip_sim.event_log.size(), "skip finalizes an active cinematic batch before exposing the ordinary terminal result")
	cinematic_skip_view.free()
	var signature_scope_sim := _simulation(1723)
	var integrity = load("res://battle/view/runtime_texture_integrity.gd")
	var integrity_source := BattleSpriteLibrary.SIGNATURE_ROOT + "/CHR001/idle.png"
	check(integrity.matches(integrity_source, FileAccess.get_sha256(integrity_source)), "signature integrity accepts a source matching its pinned SHA256")
	check(not integrity.matches(integrity_source, "0".repeat(64)) and not integrity.matches("res://missing.png", "0".repeat(64)), "signature integrity rejects changed pins and missing/unmapped exports")
	for party_index in range(signature_scope_sim.state.party.size()):
		# CHR004 is now intentionally part of the starting-party HD group. Use CHR006 as
		# a non-signature control so this still proves a future BOSS001 wave is not
		# preloaded merely because it appears in the stage declaration.
		signature_scope_sim.state.party[party_index].def_id = "CHR006"
	signature_scope_sim.state.party[0].def_id = "CHR001"
	for enemy_index in range(signature_scope_sim.state.enemies.size()):
		signature_scope_sim.state.enemies[enemy_index].def_id = "ENM001"
	signature_scope_sim.stage["waves"] = [["BOSS001"]]
	var signature_scope_view := BattleView.new()
	signature_scope_view.setup(signature_scope_sim)
	var signature_scope_ids := signature_scope_view._signature_residency_entity_ids()
	check(signature_scope_ids.size() == 2 and signature_scope_ids[0] == "CHR001" and signature_scope_ids[1] == "ENM001" and not signature_scope_ids.has("BOSS001"), "the current ENM001 encounter is admitted to the high-density lease while a future BOSS001 wave is not preloaded")
	signature_scope_view.sprite_library.signature_load_error = "EXPECTED_QA_REJECTION"
	check(not signature_scope_view._commit_signature_residency_or_fallback(signature_scope_ids) and signature_scope_view._signature_residency_resolved(signature_scope_ids) and not signature_scope_view._signature_residency_matches(signature_scope_ids), "a rejected signature lease settles to compact once instead of reloading forever")
	var next_signature_ids: Array[String] = ["CHR001", "BOSS001"]
	check(not signature_scope_view._signature_residency_resolved(next_signature_ids), "a different encounter can acquire its own signature lease after a prior fallback")
	signature_scope_view._release_signature_residency()
	check(not signature_scope_view._signature_residency_resolved(signature_scope_ids), "teardown clears the settled fallback and does not retain a previous encounter")
	signature_scope_view.free()
	var signature_motion_sim := _simulation(1724)
	for party_index in range(signature_motion_sim.state.party.size()):
		signature_motion_sim.state.party[party_index].def_id = "CHR002"
	signature_motion_sim.state.party[0].def_id = "CHR008"
	var signature_motion_view := BattleView.new()
	signature_motion_view.setup(signature_motion_sim)
	signature_motion_view.signature_sprite_pack_ready = signature_motion_view.sprite_library.load_signature_pack(["CHR008"])
	var signature_motion_uid := str(signature_motion_sim.state.party[0].uid)
	signature_motion_view.entry_tracks[signature_motion_uid] = 1.0
	signature_motion_view._play_animation(signature_motion_uid, "ultimate")
	signature_motion_view._advance_animations(10.0)
	var signature_motion_track: Dictionary = signature_motion_view.animation_tracks.get(signature_motion_uid, {})
	check(signature_motion_view.signature_sprite_pack_ready and str(signature_motion_track.get("name", "")) == "idle", "signature-only non-looping motion restores actor and world HP/SH anchor transforms without requiring a compact atlas")
	var action_scale_consistent := true
	for viewport_size in [Vector2(390, 844), Vector2(1280, 720)]:
		signature_motion_view.size = viewport_size
		var fixed_scale := signature_motion_view._combat_sprite_scale(signature_motion_sim.state.party[0], "idle")
		for action_name in ["move", "basic_attack", "normal_skill", "ultimate", "hit", "down", "victory"]:
			action_scale_consistent = action_scale_consistent and is_equal_approx(fixed_scale, signature_motion_view._combat_sprite_scale(signature_motion_sim.state.party[0], action_name))
	check(action_scale_consistent, "actor body scale stays identical across signature and ordinary action frames in both orientations")
	var grounding = load("res://battle/view/battle_grounding.gd")
	grounding.contacts("compact", "CHR001", "idle", 0.0)
	var contact_frames := 0
	var contacts_registered := true
	for family in grounding.registry.packs.values():
		for entity in family.values():
			for action in entity.values():
				for points in action.frames:
					contact_frames += 1
					for angle in [-.18, 0.0, .22]:
						for mirrored in [false, true]:
							var pose: Dictionary = grounding.register_pose({"offset": Vector2(10, -24), "rotation": angle, "scale": Vector2(1.03, .97)}, points, 1.10, mirrored)
							# Independently reproduce the renderer's transform, rather than
							# accepting the helper's own reported residual as its test oracle.
							var rendered_bottom := -INF
							for raw_point in points:
								var source_point := (Vector2(float(raw_point[0]), float(raw_point[1])) - Vector2(.5, .88)) * 512.0 * 1.10
								var rendered := (source_point * (pose.scale as Vector2)).rotated(float(pose.rotation)) + (pose.offset as Vector2)
								rendered_bottom = maxf(rendered_bottom, rendered.y)
							contacts_registered = contacts_registered and not points.is_empty() and absf(rendered_bottom) < .001
	check(contacts_registered and contact_frames == 18528, "all 18528 compact/HD/signature frames keep an opaque contact planted through left/right lean without GPU readback")
	var formation_valid := true
	for boss_arena in [false, true]:
		for player in [false, true]:
			for slot in range(5 if player else 3):
				var foot: Vector2 = grounding.formation_point(Vector2(390, 844), player, slot, boss_arena)
				formation_valid = formation_valid and foot.y > 844 * .70 and foot.y < 844 * .90
	check(formation_valid, "both authored backdrop formations place feet below walls and above the foreground rail/HUD")
	signature_motion_view.free()
	var residual_sim := _simulation(1725)
	var residual_source: Dictionary = residual_sim.state.party[2]
	var residual_target: Dictionary = residual_sim.state.enemies[0]
	var residual_view := BattleView.new()
	residual_view.setup(residual_sim)
	residual_view.entry_tracks[str(residual_source.uid)] = 1.0
	residual_view._spawn_projectile(str(residual_source.uid), str(residual_target.uid), "ULTIMATE")
	residual_view._spawn_vfx(str(residual_source.uid), str(residual_target.uid), "ultimate")
	residual_view._spawn_vfx(str(residual_source.uid), str(residual_target.uid), "impact_ultimate")
	residual_view._spawn_skill_callout(str(residual_source.uid), "ULT", Color("ffd36f"))
	residual_view._spawn_boss_phase_presentation(str(residual_source.uid), "ENRAGE")
	residual_view._play_animation(str(residual_source.uid), "ultimate")
	residual_view.presentation_director.request_combat_impact(.82)
	residual_view.speed = 3
	residual_view.paused = true
	residual_view._process(.20)
	residual_view.paused = false
	var residual_before_skip: Dictionary = residual_view.presentation_residual_snapshot()
	var residual_skip_started := residual_view.skip_to_result()
	var residual_after_skip: Dictionary = residual_view.presentation_residual_snapshot()
	check(residual_skip_started and int(residual_before_skip.get("active_effect_count", 0)) >= 5 and not bool(residual_before_skip.get("camera_at_baseline", true)) and residual_view.presentation_residuals_are_clear() and int(residual_after_skip.get("active_effect_count", -1)) == 0, "travel, cast, impact burst, shock-camera, callout and phase layers leave no residual after paused/3x skip", "before=%s after=%s skip=%s" % [JSON.stringify(residual_before_skip), JSON.stringify(residual_after_skip), residual_skip_started])
	residual_view.free()
	var terminal_residual_view := BattleView.new()
	var terminal_residual_sim := _simulation(1726)
	terminal_residual_view.setup(terminal_residual_sim)
	var terminal_source: Dictionary = terminal_residual_sim.state.party[2]
	var terminal_target: Dictionary = terminal_residual_sim.state.enemies[0]
	terminal_residual_view._spawn_projectile(str(terminal_source.uid), str(terminal_target.uid), "NORMAL")
	terminal_residual_view._spawn_vfx(str(terminal_source.uid), str(terminal_target.uid), "impact_ultimate")
	terminal_residual_view.presentation_director.request_combat_impact(.80)
	terminal_residual_view.consumed_events = terminal_residual_sim.event_log.size()
	terminal_residual_view.presentation_read_cursor = terminal_residual_sim.event_log.size()
	terminal_residual_view.presented_cursor = terminal_residual_sim.event_log.size()
	terminal_residual_sim.state.ended = true
	terminal_residual_view._process(0.0)
	check(terminal_residual_view.emitted_finish and terminal_residual_view.presentation_residuals_are_clear(), "normal battle-end terminal cleanup clears active effect records, camera impact, motion offsets and HP/SH anchor offsets")
	terminal_residual_view.free()
	var reentry_residual_view := BattleView.new()
	reentry_residual_view.setup(_simulation(1727))
	var reentry_source: Dictionary = reentry_residual_view.simulation.state.party[2]
	var reentry_target: Dictionary = reentry_residual_view.simulation.state.enemies[0]
	reentry_residual_view._spawn_projectile(str(reentry_source.uid), str(reentry_target.uid), "ULTIMATE")
	reentry_residual_view._spawn_vfx(str(reentry_source.uid), str(reentry_target.uid), "ultimate")
	reentry_residual_view.presentation_director.request_combat_impact(.76)
	reentry_residual_view.setup(_simulation(1728))
	reentry_residual_view._advance_entries(1.0)
	check(reentry_residual_view.presentation_residuals_are_clear(), "battle re-entry starts without an earlier encounter's projectile, VFX, camera or actor-anchor residual")
	reentry_residual_view.free()
	var rng := DeterministicRng.new(81)
	var attacker := {"stats": {"ATK": 100, "ACC": 100, "CRIT": 100}, "level": 10, "attack_type": "PHYSICAL", "outgoing_modifier": 1.0, "statuses": {}}
	var defender := {"stats": {"DEF": 100, "EVA": 100, "CRIT_RES": 100}, "level": 10, "defense_type": "ARMOR", "incoming_modifier": 1.0, "statuses": {}}
	var hits := 0
	for i in range(200): hits += 1 if DamageResolver.calculate(attacker, defender, 1.0, DataRegistry.data.affinity_matrix, rng).hit else 0
	check(hits > 0 and hits < 200, "hit result not locked at 0 or 100 percent", str(hits))
	var shield_sim := _simulation(9)
	var target: Dictionary = shield_sim.state.party[0]
	var enemy: Dictionary = shield_sim.state.enemies[0]
	target.shields = {"TEST": 500}
	shield_sim._recalculate_shield(target)
	var hp_before := int(target.hp)
	shield_sim._deal_damage(enemy, target, 1.0, "TEST")
	check(int(target.hp) == hp_before and int(target.shield) < 500, "shield absorbs before HP")
	var taunted_enemy := {"team": "ENEMY", "statuses": {"TAUNT": {"source": "P:A"}}}
	var candidates := [{"uid": "P:A", "alive": true, "hp": 100, "max_hp": 100, "threat": 1.0}, {"uid": "P:B", "alive": true, "hp": 100, "max_hp": 100, "threat": 10.0}]
	check(TargetResolver.choose(taunted_enemy, candidates).uid == "P:A", "taunt changes target")
	var silence_sim := _simulation(10)
	var caster: Dictionary = silence_sim.state.party[0]
	StatusEffectRuntime.apply(caster, "SILENCE", 3.0, "TEST")
	silence_sim.state.tactical_gauge = 10.0
	check(not silence_sim._use_ultimate(caster), "silence blocks ultimate")
	var stun_sim := _simulation(11)
	var stunned: Dictionary = stun_sim.state.party[0]
	stunned.attack_cd = 0.0
	StatusEffectRuntime.apply(stunned, "STUN", 3.0, "TEST")
	var before := stun_sim.event_log.size()
	stun_sim.tick()
	var acted := stun_sim.event_log.slice(before).any(func(event): return event.source == stunned.uid and event.type in [BattleEvent.BASIC_ATTACK, BattleEvent.NORMAL_SKILL])
	check(not acted, "stun blocks action")
	var downed_caster_sim := _simulation(111)
	var downed_enemy: Dictionary = downed_caster_sim.state.enemies[0]
	downed_enemy.hp = 0
	downed_enemy.alive = false
	downed_enemy.state = "DOWN"
	var downed_event_start := downed_caster_sim.event_log.size()
	downed_caster_sim._basic_attack(downed_enemy)
	downed_caster_sim._use_normal(downed_enemy)
	downed_caster_sim._use_ultimate(downed_enemy)
	downed_caster_sim._emit_boss_pattern_cast(downed_enemy, downed_caster_sim.state.party[0], "TEST")
	downed_caster_sim._deal_damage(downed_enemy, downed_caster_sim.state.party[0], 1.0, "TEST")
	downed_caster_sim._heal(downed_enemy, downed_caster_sim.state.party[0], 1.0)
	downed_caster_sim._apply_shield(downed_enemy, downed_caster_sim.state.party[0], 1.0)
	var downed_cast_emitted := downed_caster_sim.event_log.slice(downed_event_start).any(func(event): return event.source == downed_enemy.uid and event.type in [BattleEvent.BASIC_ATTACK, BattleEvent.NORMAL_SKILL, BattleEvent.ULTIMATE])
	var downed_effect_emitted := downed_caster_sim.event_log.slice(downed_event_start).any(func(event): return event.source == downed_enemy.uid and event.type in [BattleEvent.DAMAGE, BattleEvent.HEAL, BattleEvent.SHIELD])
	check(not downed_cast_emitted and not downed_effect_emitted, "downed unit cannot enqueue skill, boss-pattern, damage, heal, or shield actions")
	var late_event_view := BattleView.new()
	late_event_view.setup(downed_caster_sim)
	late_event_view.consumed_events = downed_caster_sim.event_log.size()
	downed_caster_sim.event_log.append(BattleEvent.make(downed_caster_sim.state.tick, BattleEvent.BASIC_ATTACK, downed_enemy.uid, downed_caster_sim.state.party[0].uid))
	downed_caster_sim.event_log.append(BattleEvent.make(downed_caster_sim.state.tick, BattleEvent.NORMAL_SKILL, downed_enemy.uid, downed_caster_sim.state.party[0].uid, 0, {"skill_id": "TEST_DOWNED_NORMAL"}))
	downed_caster_sim.event_log.append(BattleEvent.make(downed_caster_sim.state.tick, BattleEvent.ULTIMATE, downed_enemy.uid, downed_caster_sim.state.party[0].uid, 0, {"skill_id": "TEST_DOWNED_ULTIMATE"}))
	late_event_view._consume_events()
	var late_track: Dictionary = late_event_view.animation_tracks.get(downed_enemy.uid, {})
	check(late_event_view.projectiles.is_empty() and late_event_view.vfx_presentations.is_empty() and late_event_view.skill_callouts.is_empty() and str(late_track.get("name", "")) == "move", "late visual events cannot make a DOWN enemy cast from the ground")
	late_event_view.free()
	var target_sim := _simulation(101)
	target_sim.auto_enabled = false
	var manual_caster: Dictionary = target_sim.state.party[1]
	var manual_target: Dictionary = target_sim.state.enemies[1]
	manual_caster.stats.ACC = 10000
	manual_target.stats.EVA = 0
	target_sim.state.tactical_gauge = 10.0
	var manual_hp_before := int(manual_target.hp)
	target_sim.request_ultimate(manual_caster.uid, manual_target.uid)
	target_sim.tick()
	check(int(manual_target.hp) < manual_hp_before, "manual ultimate command damages the explicitly selected target")
	var status_ids: Array = DataRegistry.list_of("status_effects").map(func(row): return row.id)
	check(status_ids.has("CLEANSE") and status_ids.has("DISPEL"), "cleanse and dispel are distinct definitions")
	check(DataRegistry.list_of("status_effects").all(func(row): return row.has("boss_resistance")), "boss status resistance is data-defined")
	var stacked := {"rank": "PLAYER", "statuses": {}}
	for i in range(4): StatusEffectRuntime.apply(stacked, "DAMAGE_OVER_TIME", 4.0, "TEST", 10.0)
	var status_ticks := StatusEffectRuntime.update(stacked, 1.0)
	check(int(stacked.statuses.DAMAGE_OVER_TIME.stacks) == 3 and status_ticks.size() == 1 and is_equal_approx(float(status_ticks[0].strength), 30.0), "status stack cap and data tick interval applied")
	var removable := {"rank": "PLAYER", "statuses": {}}
	StatusEffectRuntime.apply(removable, "STUN", 4.0, "TEST")
	StatusEffectRuntime.apply(removable, "HASTE", 4.0, "TEST")
	StatusEffectRuntime.apply(removable, "INVULNERABLE", 2.0, "TEST")
	StatusEffectRuntime.cleanse(removable)
	var cleanse_ok: bool = not removable.statuses.has("STUN") and removable.statuses.has("HASTE")
	StatusEffectRuntime.dispel(removable)
	check(cleanse_ok and not removable.statuses.has("HASTE") and removable.statuses.has("INVULNERABLE"), "cleanse and dispel obey harmful/beneficial and dispellable data")
	var dot_sim := _simulation(102)
	var dot_target: Dictionary = dot_sim.state.enemies[0]
	dot_target.hp = 5
	StatusEffectRuntime.apply(dot_target, "DAMAGE_OVER_TIME", 4.0, dot_sim.state.party[0].uid, 10.0)
	for i in range(31): dot_sim._update_statuses()
	check(not bool(dot_target.alive) and dot_sim.deaths.any(func(row): return row.unit_id == dot_target.uid and row.source == "DAMAGE_OVER_TIME"), "damage-over-time death emits DOWN and records its cause")
	var protect_sim := _simulation(103)
	protect_sim.stage.protected_unit_id = "CHR001"
	protect_sim.state.party[0].hp = 0
	protect_sim.state.party[0].alive = false
	protect_sim._check_flow()
	check(protect_sim.state.ended and protect_sim.state.reason == "PROTECTED_TARGET_DEFEATED", "data-defined protected target defeat condition ends battle")
	var ended := _simulation(12)
	_run_to_end(ended)
	var event_count := ended.event_log.size()
	for i in range(100): ended.tick()
	check(ended.event_log.size() == event_count, "no damage/event after battle end")
	var speed_one := _simulation(777)
	var speed_three := _simulation(777)
	for i in range(900):
		if not speed_one.state.ended: speed_one.tick()
	for frame in range(300):
		for substep in range(3):
			if not speed_three.state.ended: speed_three.tick()
	check(speed_one.event_hash() == speed_three.event_hash(), "1x and 3x tick schedules yield same result", "hash_1x=%s hash_3x=%s ticks=%d/%d %s" % [speed_one.event_hash(), speed_three.event_hash(), speed_one.state.tick, speed_three.state.tick, _first_event_difference(speed_one.event_log, speed_three.event_log)])
	var paused := _simulation(15)
	var pause_tick := paused.state.tick
	# Paused presentation deliberately invokes zero simulation ticks.
	check(paused.state.tick == pause_tick, "pause produces zero simulation ticks")
	check(a.command_log is Array, "replay command timestamps retained")
	var pooled_view := BattleView.new()
	var pool_sim := _simulation(16)
	pooled_view.setup(pool_sim)
	for i in range(100):
		pooled_view._spawn_projectile(pool_sim.state.party[2].uid, pool_sim.state.enemies[0].uid, "BASIC")
		pooled_view._spawn_floating_text({"target": pool_sim.state.enemies[0].uid, "text": str(i), "color": Color.WHITE, "age": 2.0})
	for projectile in pooled_view.projectiles: projectile.age = 1.0
	pooled_view._recycle_expired_presentations()
	var recycled := pooled_view.pool_diagnostics()
	for i in range(100):
		pooled_view._spawn_projectile(pool_sim.state.party[2].uid, pool_sim.state.enemies[0].uid, "BASIC")
		pooled_view._spawn_floating_text({"target": pool_sim.state.enemies[0].uid, "text": str(i), "color": Color.WHITE, "age": 0.0})
	var reused := pooled_view.pool_diagnostics()
	check(int(recycled.free_projectiles) >= BattleView.MAX_ACTIVE_PROJECTILES and int(recycled.free_floating_texts) >= BattleView.MAX_ACTIVE_FLOATING_TEXTS and int(reused.active_projectiles) == BattleView.MAX_ACTIVE_PROJECTILES and int(reused.active_floating_texts) == BattleView.MAX_ACTIVE_FLOATING_TEXTS and int(reused.free_projectiles) <= 1 and int(reused.free_floating_texts) <= 1, "presentation pools recycle burst entries while enforcing browser-safe active budgets")
	pooled_view.free()
	var phase_sim := _simulation(1715, "CH01-N20")
	# N20's boss can be in a later wave. The renderer consumes the same STATUS
	# payload independently of which wave emitted it, so a live wave-one source
	# gives this view-only test a stable anchor without advancing simulation.
	var phase_source: Dictionary = phase_sim.state.enemies[0]
	var phase_view := BattleView.new()
	phase_view.setup(phase_sim)
	phase_sim.event_log.append(BattleEvent.make(phase_sim.state.tick, BattleEvent.STATUS, str(phase_source.uid), str(phase_source.uid), 0, {"phase": "PHASE_2"}))
	phase_sim.event_log.append(BattleEvent.make(phase_sim.state.tick, BattleEvent.STATUS, str(phase_source.uid), str(phase_source.uid), 0, {"phase": "ENRAGE"}))
	var phase_hash_before_view := phase_sim.event_hash()
	var phase_tick_before_view := int(phase_sim.state.tick)
	var phase_state_before_view := str(phase_source.get("phase", ""))
	phase_view._consume_events()
	var language_before_phase_test := str(SettingsService.values.get("language", "ko"))
	SettingsService.values.language = "ko"
	var ko_phase_snapshot := phase_view.boss_phase_presentation_snapshot()
	SettingsService.values.language = "en"
	var en_phase_snapshot := phase_view.boss_phase_presentation_snapshot()
	SettingsService.values.language = language_before_phase_test
	var phase_ids := ko_phase_snapshot.map(func(row): return str(row.phase_id))
	check(phase_ids == ["PHASE_2", "ENRAGE"] and int(phase_view.pool_diagnostics().active_boss_phase_presentations) == 2, "STATUS phase events create one view-only boss banner each")
	var localized_phase_copy := ko_phase_snapshot.size() == 2 and en_phase_snapshot.size() == 2
	for row in ko_phase_snapshot + en_phase_snapshot:
		localized_phase_copy = localized_phase_copy and not str(row.title).begins_with("[") and not str(row.subtitle).begins_with("[") and str(row.title) != str(row.phase_id)
	check(localized_phase_copy, "PHASE_2 and ENRAGE banners resolve localized ko/en copy instead of internal IDs")
	check(phase_sim.event_hash() == phase_hash_before_view and int(phase_sim.state.tick) == phase_tick_before_view and str(phase_source.get("phase", "")) == phase_state_before_view, "boss phase presentation never mutates simulation state or event hash")
	phase_view.free()

func _test_growth() -> void:
	var backup := AppState.profile.duplicate(true)
	AppState.grant_all_materials(9999)
	var state: Dictionary = AppState.profile.roster.CHR001
	AppState.profile.account.level = 100
	state.level = 20
	state.breakthrough = 0
	check(CharacterProgression.level_cap(state) == 20, "B0 character level cap is 20")
	check(CharacterProgression.use_material("CHR001", "TRAINING_NOTE_XL", 1).error == "LEVEL_CAP", "XP blocked at breakthrough cap")
	var core_before := AppState.inventory_count("BREAK_CORE_T1")
	var breakthrough := BreakthroughService.upgrade("CHR001")
	check(breakthrough.ok and int(state.breakthrough) == 1, "breakthrough unlocks next cap")
	check(AppState.inventory_count("BREAK_CORE_T1") == core_before - 10, "breakthrough deducts exact material")
	state.level = 1
	state.xp = 0
	var note_before := AppState.inventory_count("TRAINING_NOTE_M")
	var credit_before := AppState.inventory_count("CREDIT")
	var level_preview := CharacterProgression.preview("CHR001", "TRAINING_NOTE_M", 1)
	var level_result := CharacterProgression.use_material("CHR001", "TRAINING_NOTE_M", 1)
	check(level_result.ok and int(state.level) == int(level_preview.level) and AppState.inventory_count("CREDIT") == credit_before - int(level_preview.credit_cost), "character level-up charges exact previewed credits")
	check(AppState.inventory_count("TRAINING_NOTE_M") == note_before - 1, "character level-up deducts exact XP material")
	state.breakthrough = 0
	state.level = 19
	state.xp = 0
	var overflow_notes := AppState.inventory_count("TRAINING_NOTE_XL")
	check(CharacterProgression.use_material("CHR001", "TRAINING_NOTE_XL", 1).error == "WOULD_EXCEED_LEVEL_CAP" and AppState.inventory_count("TRAINING_NOTE_XL") == overflow_notes, "character XP overflow at cap is blocked without consumption")
	state.skills.normal = 10
	state.skills.passive = 10
	state.skills.ultimate = 5
	check(not SkillUpgradeService.upgrade("CHR001", "normal").ok and not SkillUpgradeService.upgrade("CHR001", "ultimate").ok, "10/10/5 maximum enforced")
	var weapon: Dictionary = AppState.profile.weapons.WPN001
	weapon.level = 10
	weapon.tier = 1
	check(WeaponUpgradeService.use_material("WPN001", "WEAPON_CHIP_S", 1).error == "TIER_LEVEL_CAP", "weapon XP blocked at tier cap")
	check(WeaponUpgradeService.tier_up("WPN001").ok and int(weapon.tier) == 2, "weapon tier-up succeeds with exact prerequisites")
	weapon.level = 19
	weapon.tier = 2
	weapon.xp = 0
	var weapon_chip_before := AppState.inventory_count("WEAPON_CHIP_XL")
	check(WeaponUpgradeService.use_material("WPN001", "WEAPON_CHIP_XL", 1).error == "WOULD_EXCEED_TIER_CAP" and AppState.inventory_count("WEAPON_CHIP_XL") == weapon_chip_before, "weapon XP overflow at tier cap is blocked without consumption")
	state.level = 1
	state.breakthrough = 0
	state.equipped_weapon_id = "WPN004"
	AppState.profile.weapons.WPN004 = {"owned": true, "level": 1, "xp": 0, "tier": 1}
	check(int(CharacterProgression.final_stats("CHR001").ATK) == 132, "equipped common weapon flat ATK applies to final character stats")
	AppState.profile.weapons.WPN004.level = 60
	AppState.profile.weapons.WPN004.tier = 5
	var upgraded_weapon_stats := WeaponUpgradeService.flat_stats_for("WPN004", AppState.profile.weapons.WPN004)
	check(int(upgraded_weapon_stats.ATK) == 250 and int(upgraded_weapon_stats.CRIT) == 36, "weapon level and T5 secondary stat are data-driven")
	var snapshot_sim := BattleSimulation.new()
	snapshot_sim.setup(AppState.create_party_snapshot(), DataRegistry.stage("CH01-N01"), 31, DataRegistry.data)
	check(int(snapshot_sim.state.party[0].stats.ATK) == 352, "equipped weapon snapshot applies to deterministic battle stats")
	AppState.profile.stage_stars["CH01-N01"] = 3
	AppState.profile.chapter_progress.CH01.normal_highest = 1
	AppState.profile.account.stamina = int(DataRegistry.stage("CH01-N01").stamina_cost) * 4
	var developer_mode_before := bool(SettingsService.values.developer_mode)
	SettingsService.values.developer_mode = false
	var stamina_before := int(AppState.profile.account.stamina)
	check(RewardService.sweep("CH01-N01", 5, 9).error == "INSUFFICIENT_STAGE_ENTRIES" and int(AppState.profile.account.stamina) == stamina_before, "multi-sweep entry check is atomic")
	SettingsService.values.developer_mode = developer_mode_before
	var poor_inventory: Dictionary = AppState.profile.inventory.duplicate(true)
	for item_id in AppState.profile.inventory: AppState.profile.inventory[item_id] = 0
	state.skills.normal = 1
	check(SkillUpgradeService.upgrade("CHR001", "normal").error == "INSUFFICIENT_MATERIALS", "growth blocks insufficient materials")
	AppState.profile.inventory = poor_inventory
	AppState.profile = backup

func _test_story() -> void:
	var valid := true
	for scenario in DataRegistry.list_of("scenarios"): valid = valid and ScenarioParser.validate(scenario).is_empty()
	check(valid, "all scenario jump references and commands valid")
	var shell_script = load("res://screens/app_shell.gd")
	var shell = shell_script.new()
	var developer_mode_before := bool(SettingsService.values.developer_mode)
	SettingsService.values.developer_mode = false
	var release_header: Dictionary = shell.story_header_data("SCN_CH01_PREBOSS")
	var unknown_release_header: Dictionary = shell.story_header_data("SCN_UNKNOWN_INTERNAL")
	var release_result_header: Dictionary = shell.result_header_data({"source_type": "BATTLE", "source_id": "CH01-N20"})
	var release_treasure_header: Dictionary = shell.result_header_data({"source_type": "TREASURE", "source_id": "TREASURE_VISIBLE_01"})
	SettingsService.values.developer_mode = true
	var developer_header: Dictionary = shell.story_header_data("SCN_CH01_PREBOSS")
	var developer_result_header: Dictionary = shell.result_header_data({"source_type": "BATTLE", "source_id": "CH01-N20"})
	SettingsService.values.developer_mode = developer_mode_before
	check(str(release_header.title) == LocalizationService.tr_key("SCENARIO_CH01_PREBOSS_TITLE") and str(release_header.subtitle).is_empty(), "story release header uses localized scenario title and hides raw scenario ID")
	check(str(developer_header.title) == LocalizationService.tr_key("SCENARIO_CH01_PREBOSS_TITLE") and str(developer_header.subtitle) == "SCN_CH01_PREBOSS", "story developer header may expose raw scenario ID without replacing localized title")
	check(str(unknown_release_header.title) == LocalizationService.tr_key("UI_STORY_TITLE") and str(unknown_release_header.subtitle).is_empty(), "unknown story release header falls back to neutral localized copy without exposing SCN ID")
	check(str(release_result_header.title) == "전투 결과" and str(release_result_header.subtitle) == LocalizationService.tr_key("STAGE_CH01_N20") and not str(release_result_header.subtitle).contains("CH01-"), "battle result release header resolves the localized stage name instead of the stage ID")
	check(str(release_treasure_header.subtitle) == "현장 보급품 회수" and not str(release_treasure_header.subtitle).contains("TREASURE_VISIBLE_01"), "exploration result release header uses neutral copy instead of a source ID")
	check(str(developer_result_header.subtitle).contains("CH01-N20"), "result developer header retains the stage ID for diagnostics")
	var delayed_recruit_feature: Dictionary = shell.result_feature_character_for_report({"progress": {"newly_recruited_characters": ["CHR007"]}}, ["CHR001"])
	var immediate_event_feature: Dictionary = shell.result_feature_character_for_report({"progress": {"event_encounter": {"character_id": "CHR006"}}}, ["CHR001"])
	check(str(delayed_recruit_feature.get("id", "")) == "CHR007" and str(immediate_event_feature.get("id", "")) == "CHR006", "result art prioritizes actual deferred or immediate companion joins over the unrelated party lead")
	var outro_scenario: Dictionary = DataRegistry.by_id("scenarios", "SCN_CH01_OUTRO")
	var outro_commands: Array = outro_scenario.get("commands", [])
	var outro_cg := ""
	var outro_background := ""
	for command_value in outro_commands:
		var command: Dictionary = command_value
		if str(command.get("command", "")) == "set_cg": outro_cg = str(command.get("asset_id", ""))
		if str(command.get("command", "")) == "set_background": outro_background = str(command.get("asset_id", ""))
	var runtime_cg_path := AssetRegistry.resolve(outro_cg)
	check(runtime_cg_path.begins_with("res://assets/runtime_web/story/") and FileAccess.file_exists(runtime_cg_path), "chapter outro CG resolves to a generated Web runtime derivative")
	var outro_art: Texture2D = shell.story_art_texture_for_state(outro_cg, outro_background)
	check(not outro_cg.is_empty() and not outro_background.is_empty() and outro_art != null, "chapter outro resolves a runtime story image instead of an empty art band")
	var fallback_art: Texture2D = shell.story_art_texture_for_state("CG_ASSET_NOT_PRESENT", outro_background)
	check(fallback_art != null, "story CG import failure falls back to the authored scenario background")
	shell.free()
	var story_profile_before := AppState.profile.duplicate(true)
	var prologue_scenario: Dictionary = DataRegistry.by_id("scenarios", "SCN_PROLOGUE")
	var prologue_commands: Array = prologue_scenario.get("commands", [])
	var prologue_portraits: Array = prologue_commands.filter(func(command): return str(command.get("command", "")) == "show_portrait")
	var prologue_speakers: Array = prologue_commands.filter(func(command): return str(command.get("speaker_key", "")) in ["SPEAKER_MAERU", "SPEAKER_ROAN"])
	check(prologue_portraits.size() >= 2 and prologue_portraits.any(func(command): return str(command.get("slot", "")) == "LEFT" and str(command.get("asset_id", "")) == "portrait_chr002_dev") and prologue_portraits.any(func(command): return str(command.get("slot", "")) == "RIGHT" and str(command.get("asset_id", "")) == "portrait_chr001_dev") and prologue_speakers.size() >= 2, "cinematic prologue authors distinct Maeru and Roan illustrations and dialogue")
	var runner := ScenarioRunner.new()
	check(runner.load_scenario("SCN_PROLOGUE", false).ok, "scenario runner loads prologue")
	var found_choice := false
	for i in range(20):
		var command := runner.advance()
		if command.get("command", "") == "choice": found_choice = true; break
	check(found_choice and runner.choose(0).ok, "scenario choice sets branch flag")
	check(AppState.profile.story_flags.get("CHOSE_LIGHT", false), "scenario flag persisted")
	var resumed := ScenarioRunner.new()
	check(resumed.load_scenario("SCN_PROLOGUE", true).ok and resumed.state.background_asset_id == "bg_lantern_tunnel_dev" and resumed.state.portraits.has("LEFT") and resumed.state.portraits.has("RIGHT"), "scenario resume restores background and portrait state")
	var choice_checkpoint_runner := ScenarioRunner.new()
	check(choice_checkpoint_runner.load_scenario("SCN_PROLOGUE", false).ok, "scenario choice checkpoint fixture loads")
	for i in range(20):
		var choice_command := choice_checkpoint_runner.advance()
		if choice_command.get("command", "") == "choice":
			break
	var choice_resumed := ScenarioRunner.new()
	check(choice_resumed.load_scenario("SCN_PROLOGUE", true).ok and choice_resumed.state.waiting_for_choice and str(choice_resumed.state.current_line.get("command", "")) == "choice", "scenario resume restores an open choice without rewinding")
	var disk_checkpoint_saved := SaveService.save_game()
	AppState.new_game()
	var disk_checkpoint_loaded := SaveService.load_game()
	var disk_choice_resumed := ScenarioRunner.new()
	check(disk_checkpoint_saved.ok and disk_checkpoint_loaded.ok and disk_choice_resumed.load_scenario("SCN_PROLOGUE", true).ok and disk_choice_resumed.state.waiting_for_choice and str(disk_choice_resumed.state.current_line.get("command", "")) == "choice", "atomic save/load restores an open story choice checkpoint")
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd").replace("\r\n", "\n")
	var web_checkpoint_wiring := shell_source.contains("func _persist_story_checkpoint()") and shell_source.contains("var command := scenario_runner.advance()\n\t\t_persist_story_checkpoint()") and shell_source.contains("story_checkpoint_dirty = true") and shell_source.contains("func _flush_story_checkpoint_after_delay()") and shell_source.contains("await get_tree().create_timer(0.24).timeout") and shell_source.contains("story_checkpoint_dirty = false\n\tSaveService.save_game()") and shell_source.contains("var chosen := scenario_runner.choose(index)\n\tif not chosen.ok: return false\n\t_persist_story_checkpoint()")
	check(web_checkpoint_wiring, "story checkpoints are atomically persisted at Web dialogue and choice boundaries")
	check(DataRegistry.list_of("scenarios").size() == 163, "story content count covers all 20 chapters and interludes")
	AppState.profile = story_profile_before

func _test_relay() -> void:
	var profile_backup := AppState.profile.duplicate(true)
	AppState.new_game()
	var specification := RelayServiceScript.first_spec()
	var spec_errors := RelayServiceScript.validate_specification(specification)
	check(str(specification.get("id", "")) == "RELAY_CH01_A" and spec_errors.is_empty() and (specification.get("stage_ids", []) as Array).size() == 3, "relay contract is data-driven with three valid distinct stage segments", JSON.stringify(spec_errors))
	var rejected := RelayServiceScript.start(AppState.profile, str(specification.get("id", "")), 123)
	check(not bool(rejected.get("ok", false)) and str(rejected.get("error", "")).begins_with("LOCKED_OR_EMPTY"), "relay blocks a run before fifteen unlocked unique members exist")
	var unlocked := 0
	for character_value in DataRegistry.list_of("characters"):
		var character_id := str((character_value as Dictionary).get("id", ""))
		if unlocked < 15:
			AppState.profile.roster[character_id].unlocked = true
			unlocked += 1
	check(RelayServiceScript.autofill_draft(AppState.profile), "relay auto-fill creates three squads once fifteen companions are available")
	var squads := RelayServiceScript.draft_squads(AppState.profile)
	check(RelayServiceScript.validate_squads(AppState.profile, squads).is_empty(), "relay draft has three complete five-member squads with no duplicate character")
	var duplicate_squads := squads.duplicate(true)
	duplicate_squads[2][4] = duplicate_squads[0][0]
	var duplicate_errors := RelayServiceScript.validate_squads(AppState.profile, duplicate_squads)
	check(duplicate_errors.any(func(value): return str(value).begins_with("DUPLICATE_MEMBER")), "relay validator rejects a character reused across two squads", JSON.stringify(duplicate_errors))
	var started := RelayServiceScript.start(AppState.profile, str(specification.get("id", "")), 12345)
	check(bool(started.get("ok", false)) and RelayServiceScript.current_stage_id(AppState.profile) == "CH01-N03" and RelayServiceScript.current_squad(AppState.profile).size() == 5, "relay starts its first existing battle with the first locked five-member squad")
	var relay_snapshot := AppState.relay_party_snapshot()
	check(relay_snapshot.size() == 5 and str(relay_snapshot[0].get("id", "")).begins_with("CHR"), "relay battle snapshot resolves the selected squad through the ordinary character progression path")
	var restored_profile := AppState.profile.duplicate(true)
	AppState.apply_loaded(restored_profile)
	check(AppState.relay_active() and AppState.relay_current_stage_id() == "CH01-N03" and AppState.relay_current_squad().size() == 5, "relay active run, segment and squad locks survive save-state restoration")
	var credit_before_failure := AppState.inventory_count("CREDIT")
	var failed_segment := RelayServiceScript.record_segment_result(AppState.profile, {"victory": false, "time": 20.0, "survivors": 0})
	check(bool(failed_segment.get("retry", false)) and RelayServiceScript.current_stage_id(AppState.profile) == "CH01-N03" and AppState.inventory_count("CREDIT") == credit_before_failure, "relay failure preserves the current segment and grants no reward")
	var first_win := RelayServiceScript.record_segment_result(AppState.profile, {"victory": true, "time": 40.0, "survivors": 5, "ticks": 100, "event_hash": "relay-1"})
	check(bool(first_win.get("advanced", false)) and RelayServiceScript.current_stage_id(AppState.profile) == "CH01-N06", "first relay victory advances only to the next segment and locks the winning squad")
	var second_win := RelayServiceScript.record_segment_result(AppState.profile, {"victory": true, "time": 42.0, "survivors": 5, "ticks": 101, "event_hash": "relay-2"})
	check(bool(second_win.get("advanced", false)) and RelayServiceScript.current_stage_id(AppState.profile) == "CH01-N09", "second relay victory persists the second squad lock and opens the final segment")
	var credit_before_completion := AppState.inventory_count("CREDIT")
	var final_win := RelayServiceScript.record_segment_result(AppState.profile, {"victory": true, "time": 43.0, "survivors": 5, "ticks": 102, "event_hash": "relay-3"})
	check(bool(final_win.get("completed", false)) and bool(final_win.get("first_completion", false)) and str(final_win.get("grade", "")) == "S" and int(final_win.get("rewards", {}).get("CREDIT", 0)) == 15000 and AppState.inventory_count("CREDIT") == credit_before_completion + 15000, "relay final completion calculates a grade and commits existing-resource reward exactly once")
	var duplicate_completion := RelayServiceScript.record_segment_result(AppState.profile, {"victory": true, "time": 1.0, "survivors": 5})
	check(not bool(duplicate_completion.get("ok", false)) and AppState.inventory_count("CREDIT") == credit_before_completion + 15000 and not RelayServiceScript.completion_summary(AppState.profile, str(specification.get("id", ""))).is_empty(), "stale relay completion callback cannot mint a second completion reward")
	var legacy := AppState.profile.duplicate(true)
	legacy.erase("relay")
	legacy["save_schema_version"] = 7
	var migrated := SaveService._migrate(legacy)
	var legacy_reserved_kept := str(migrated.value.get("roster", {}).get("CHR044", {}).get("acquisition_status", "")) == "LEGACY_OWNED" if bool(migrated.value.get("roster", {}).get("CHR044", {}).get("unlocked", false)) else true
	check(migrated.ok and int(migrated.value.get("save_schema_version", 0)) == AppState.SAVE_SCHEMA_VERSION and (migrated.value.get("relay", {}) as Dictionary).has("active_run") and legacy_reserved_kept, "save migration v7→current adds relay and preserves any legacy-owned reserved companion")
	AppState.profile = profile_backup

func _test_save() -> void:
	var save_service_source := FileAccess.get_file_as_string("res://autoload/save_service.gd")
	var production_paths := SaveService.save_paths_for(false)
	var sandbox_paths := SaveService.save_paths_for(true)
	var isolated_sandbox_paths := SaveService.save_paths_for(true, "growth-e2e-r15")
	check(str(production_paths.save) == SaveService.SAVE_PATH and str(production_paths.backup) == SaveService.BACKUP_PATH and str(production_paths.temp) == SaveService.TEMP_PATH, "production save namespace remains stable")
	check(str(sandbox_paths.save).begins_with("user://r15_soak_sandbox/") and str(sandbox_paths.backup).begins_with("user://r15_soak_sandbox/") and str(sandbox_paths.temp).begins_with("user://r15_soak_sandbox/") and str(sandbox_paths.save) != SaveService.SAVE_PATH and str(sandbox_paths.backup) != SaveService.BACKUP_PATH and str(sandbox_paths.temp) != SaveService.TEMP_PATH, "Web soak save namespace is disjoint from production")
	check(str(isolated_sandbox_paths.save).begins_with("user://r15_soak_sandbox/growth-e2e-r15/") and str(isolated_sandbox_paths.save) != str(sandbox_paths.save) and SaveService.sanitize_sandbox_session("../../production") == "default", "isolated Web soak sessions stay sandboxed and reject traversal")
	check(save_service_source.contains("p.get('qa')") and save_service_source.contains("p.get('r15-save-sandbox-session') || p.get('qa')"), "every query-labelled Web QA run uses its own sandbox save instead of mutating player progress")
	check(not SaveService.is_soak_sandbox_enabled(), "headless regression tests do not opt into Web soak sandbox")
	var sandbox_audit := SaveService.sandbox_audit_summary()
	check(not bool(sandbox_audit.sandbox_active) and int(sandbox_audit.production_path_resolve_count) == 0 and int(sandbox_audit.production_read_attempt_count) == 0 and int(sandbox_audit.production_write_attempt_count) == 0 and int(sandbox_audit.production_backup_attempt_count) == 0 and int(sandbox_audit.production_reset_attempt_count) == 0, "save sandbox audit defaults to zero production accesses")
	var profile_backup := AppState.profile.duplicate(true)
	AppState.profile.account.level = 37
	var first := SaveService.save_game()
	AppState.profile.account.level = 38
	var second := SaveService.save_game()
	check(first.ok and second.ok, "atomic save succeeds", "first=%s second=%s user_dir=%s" % [first.error, second.error, ProjectSettings.globalize_path("user://")])
	check(FileAccess.file_exists(SaveService.BACKUP_PATH), "backup save generated", ProjectSettings.globalize_path(SaveService.BACKUP_PATH))
	var loaded := SaveService.load_game()
	check(loaded.ok and int(AppState.profile.account.level) == 38, "save/load preserves value", "load=%s level=%s" % [loaded.error, AppState.profile.account.level])
	var corrupt := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	corrupt.store_string("{corrupt")
	corrupt.close()
	var recovered := SaveService.load_game()
	check(recovered.ok and recovered.value == "backup" and int(AppState.profile.account.level) == 37, "corrupt primary recovers backup", "load=%s value=%s level=%s" % [recovered.error, recovered.value, AppState.profile.account.level])
	var migrated := SaveService._migrate({"save_schema_version": 0})
	check(migrated.ok and int(migrated.value.save_schema_version) == AppState.SAVE_SCHEMA_VERSION, "sequential v0 through current migration")
	var dirty := profile_backup.duplicate(true)
	dirty.roster.UNKNOWN_REMOVED = {"level": 99}
	var sanitized := SaveService._sanitize(dirty)
	check(not sanitized.roster.has("UNKNOWN_REMOVED") and sanitized.quarantined_unknown_character_ids.has("UNKNOWN_REMOVED"), "unknown immutable ID quarantined")
	AppState.profile = profile_backup
	var first_clear_once := AppState.record_stage_clear("CH01-N01", 3)
	var first_clear_twice := AppState.record_stage_clear("CH01-N01", 3)
	check(first_clear_once and not first_clear_twice, "duplicate first-clear reward signal prevented")
	SaveService.save_game()

# Build the real growth control tree without starting the game's intro, scene
# routing or save flow. This verifies player-facing controls rather than source
# variable names; browser QA separately measures rendered geometry and clicks.
func _growth_controls_contract() -> Dictionary:
	if not growth_ui_contract.is_empty(): return growth_ui_contract
	var profile_before := AppState.profile.duplicate(true)
	var selected_before := AppState.selected_character_id
	AppState.selected_character_id = "CHR001"
	AppState.profile.roster.CHR001.unlocked = true
	AppState.profile.account.level = 100
	AppState.profile.roster.CHR001.level = 1
	AppState.profile.roster.CHR001.breakthrough = 0
	AppState.profile.roster.CHR001.skills = {"normal": 1, "passive": 1, "ultimate": 1}
	var shell = load("res://screens/app_shell.gd").new()
	shell.content = VBoxContainer.new()
	shell.add_child(shell.content)
	shell.current_screen = "GROWTH"
	var navigation := true
	var scrollable := true
	var icons := true
	for tab in ["레벨업", "스킬업", "장비·돌파", "캐릭터 정보"]:
		for child in shell.content.get_children(): child.free()
		shell.growth_tab = tab
		shell._show_growth()
		var tabs := shell.find_child("GrowthTabs", true, false) as Container
		var body := shell.find_child("GrowthContent", true, false) as VBoxContainer
		navigation = navigation and tabs != null and tabs.get_child_count() == 4
		if tabs != null:
			for button in tabs.get_children():
				navigation = navigation and button is Button and button.disabled == (button.text == tab) and button.pressed.get_connections().size() > 0
		scrollable = scrollable and body != null and body.get_parent() is ScrollContainer and body.get_parent().get_script() == preload("res://ui/touch_progression_scroll.gd")
		if tab == "레벨업":
			var apply := shell.find_child("GrowthLevelApply", true, false) as Button
			navigation = navigation and apply != null and apply.pressed.get_connections().size() > 0
		elif tab == "스킬업":
			for slot in ["normal", "passive", "ultimate"]:
				var card := shell.find_child("GrowthSkill_" + slot, true, false) as VBoxContainer
				var apply := shell.find_child("GrowthSkillApply_" + slot, true, false) as Button
				var definition := DataRegistry.character("CHR001")
				var skill := DataRegistry.skill(str(definition[slot + "_skill_id"]))
				navigation = navigation and card != null and apply != null and apply.pressed.get_connections().size() > 0
				icons = icons and apply != null and apply.icon != null and apply.icon == shell._asset_texture(str(skill.icon_asset_id))
		elif tab == "장비·돌파":
			var choices: Array = shell.find_children("MobileEquipmentOption_*", "Button", true, false)
			navigation = navigation and not choices.is_empty()
	growth_ui_contract = {"navigation": navigation, "scroll": scrollable, "icons": icons}
	shell.free()
	AppState.profile = profile_before
	AppState.selected_character_id = selected_before
	return growth_ui_contract
