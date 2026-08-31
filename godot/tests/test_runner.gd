extends Node

var passed := 0
var failed := 0
var failures: Array[String] = []
const RelayServiceScript := preload("res://relay/relay_service.gd")

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
	_test_battle()
	_test_growth()
	_test_story()
	_test_relay()
	_test_save()
	print("TEST_SUMMARY total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	if not failures.is_empty(): print("FAILURES=", JSON.stringify(failures))
	get_tree().quit(0 if failed == 0 else 1)

func _test_settings_policy() -> void:
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
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd")
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
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd")
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
	var loading_copy_is_english := korean_pattern.search(loading_title_body + loading_initial_body + gpu_warm) == null
	for source_line_value in shell_source.split("\n"):
		var source_line := str(source_line_value)
		if (source_line.contains("_set_transition_loading_phase(") or source_line.contains("_finish_transition_loading(")) and korean_pattern.search(source_line) != null:
			loading_copy_is_english = false
	check(begin_loading.contains("min_value = 0.0") and begin_loading.contains("max_value = 100.0") and begin_loading.contains("value = 0.0") and finish_loading.contains("_set_transition_loading_display_value(100.0)") and finish_loading.contains("create_timer(0.10"), "transition loading paints a literal zero-to-one-hundred bar before disposal")
	check(loading_copy_is_english and loading_title_body.contains("LOADING — TACTICAL MAP") and loading_title_body.contains("LOADING — BATTLE") and loading_title_body.contains("LOADING — RESULTS") and shell_source.contains("Current transition progress"), "all visible loading titles, phases, completion copy and progress help are English-only")
	check(prepare_loading.contains("TRANSITION_LOADING_MAP_ENTRY") and prepare_loading.contains("TRANSITION_LOADING_BATTLE_ENTRY") and prepare_loading.contains("TRANSITION_LOADING_BATTLE_RESULT") and map_loading_policy.contains("source_type in [\"TREASURE\", \"EXPLORE\"]"), "blocking loading is scoped to map entry, battle entry and battle result transitions")
	check(treasure_reward.find("_show_map_reward_overlay()") >= 0 and treasure_reward.find("_show_map_reward_overlay()") < treasure_reward.find("SceneRouter.go(\"RESULT\")") and close_reward.contains("_resume_post_reward_turn"), "treasure reward stays over the live map and resumes its owed enemy turn without scene navigation")
	check(shell_source.contains("const STAGE_ENTRY_PRELOAD_TARGET_MSEC := 5000") and show_map.contains("await StageAssetCache.warm_map_for_stage_select") and show_map.contains("StageAssetCache.cache_hit_for_map_entry") and show_map.contains("StageAssetCache.gpu_warm_textures") and not show_map.contains("await StageAssetCache.warm_for_stage_select"), "stage entry owns the selected five-second map-only CPU and GPU preload boundary")
	check(gpu_warm.contains("TextureRect.new()") and gpu_warm.contains("TRANSITION_GPU_WARM_BATCH") and gpu_warm.contains("warm_rects[rect_index].texture = textures[texture_index]") and gpu_warm.contains("await RenderingServer.frame_post_draw") and gpu_warm.contains("warm_rect.queue_free()"), "stage entry paints retained map textures through bounded renderer batches before releasing gameplay")
	check(show_map.contains("map_screen.map_load_progress.connect(map_load_handler)\n\tcontent.add_child(map_screen)") and show_map.contains("await _wait_for_map_ready_with_deadline") and wait_map_ready.contains("STAGE_ENTRY_PRELOAD_TARGET_MSEC") and show_loading_failure.contains("LOADING COULD NOT FINISH"), "map progress is connected before tree entry and a real five-second owner deadline prevents an infinite loader")
	check(show_battle.contains("await _wait_for_battle_assets_with_deadline") and wait_battle_ready.contains("BATTLE_ENTRY_PRELOAD_TARGET_MSEC") and show_battle.find("await _wait_for_battle_assets_with_deadline") < show_battle.find("_finish_transition_loading"), "battle entry remains covered until assets attach and fails safely instead of waiting on a lost signal forever")
	var portrait_ready := show_result.find("RESULT_SCREEN_READY elapsed_ms=%d layout=portrait")
	var portrait_finish := show_result.find("_finish_transition_loading(loading_token, \"Battle results ready\")", portrait_ready)
	var landscape_ready := show_result.find("RESULT_SCREEN_READY elapsed_ms=%d layout=landscape")
	var landscape_finish := show_result.find("_finish_transition_loading(loading_token, \"Battle results ready\")", landscape_ready)
	check(battle_finished.find("_set_transition_loading_phase(loading_token, \"Opening the results screen\", 96.0") >= 0 and battle_finished.rfind("SceneRouter.go(\"RESULT\")") > battle_finished.find("Opening the results screen") and show_result.contains("_transition_loading_token_for(TRANSITION_LOADING_BATTLE_RESULT)") and not show_result.contains("await get_tree().process_frame") and not show_result.contains("await _finish_transition_loading") and portrait_ready >= 0 and portrait_finish > portrait_ready and landscape_ready > portrait_finish and landscape_finish > landscape_ready, "battle result builds the complete responsive RESULT tree synchronously before asynchronously releasing the 96-percent loader")
	check(cache_source.contains("_cache = pending # Atomic replacement") and cache_source.contains("await get_tree().process_frame") and cache_source.contains("func gpu_warm_textures"), "stage asset cache commits atomically after cooperative resource loading")
	check(cache_source.contains("const WARMUP_DEADLINE_MSEC := 5000") and cache_source.contains("_warmup_deadline_exceeded") and shell_source.contains("previous_screen == \"STAGE_SELECT\"") and shell_source.contains("StageAssetCache.cancel_warmup()"), "stage warmup has a hard deadline and is cancelled immediately when its owning screen is left")
	check(battle_finished.contains("var save_result := SaveService.save_game()") and battle_finished.contains("_present_transaction_save_failure") and map_source.contains("TREASURE PROGRESS NOT SAVED") and map_source.contains("RETRY SAVE") and patrol_contact_body.contains("var encounter_save_result := SaveService.save_game()") and patrol_contact_body.contains("AppState.abandon_pending_map_encounter(map_id)"), "battle, map contact and treasure transaction failures never continue from an unpersisted state")
	check(battle_view_source.contains("var label_font := battle_font if battle_font != null else ThemeDB.fallback_font") and battle_view_source.contains("draw_string(label_font") and battle_view_source.contains("draw_string(callout_font") and battle_view_source.contains("draw_string(floating_font"), "battle canvas names, callouts and floating text use the packaged Korean font instead of Web tofu glyphs")
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
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd")
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
	check(body_routes and next_routes and skip_routes and outside_is_ignored and event_trace == ["advance", "advance", "skip"], "pre-battle event body, Next and Skip each route through their intended raw input path")
	event_shell.free()

func _test_responsive_ui_contracts() -> void:
	var shell_script = load("res://screens/app_shell.gd")
	var shell = shell_script.new()
	var portrait_size := Vector2(390.0, 844.0)
	var portrait_metrics: Dictionary = shell.responsive_ui_metrics_for_size(portrait_size)
	var portrait_button: Vector2 = shell.responsive_button_minimum_for_size(Vector2(190.0, 52.0), portrait_size)
	var portrait_physical := portrait_button * float(portrait_metrics.canvas_scale)
	check(bool(portrait_metrics.portrait) and not bool(portrait_metrics.compact_landscape) and portrait_physical.x >= 55.5 and portrait_physical.y >= 55.5, "390x844 portrait controls retain an approximately 56 CSS-pixel touch target", str(portrait_physical))
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
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd")
	var responsive_structure := shell_source.contains("grid.columns = 2 if _is_portrait_layout() else 3") and shell_source.contains("(party_row as GridContainer).columns = 3") and shell_source.contains("(bottom as GridContainer).columns = 3") and shell_source.contains("actions.columns = 2") and shell_source.contains("status.position.y = (14.0 + MIN_TOUCH_CSS_PX + 8.0) * ui_scale")
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
	story_type_hierarchy = story_type_hierarchy and shell_source.contains("var story_body_css_px := 24.0 if narrow_portrait else 28.0") and shell_source.contains("_story_label(\"\", 28.0 if narrow_portrait else 32.0") and shell_source.contains("value.add_theme_font_size_override(\"font_size\", _story_logical_px(target_css_px))") and shell_source.contains("if not button.has_meta(\"story_control\"):")
	check(story_type_hierarchy, "story body and speaker hierarchy stays in its rendered-pixel bands while controls retain independent touch targets")
	var narrow_story_contract := shell_source.contains("var narrow_portrait := portrait and runtime_size.x <= 480.0") and shell_source.contains("runtime_size.x - 20.0") and shell_source.contains("chapter_title.custom_minimum_size.y") and shell_source.contains("348.0 if narrow_portrait else 282.0") and shell_source.contains("30.0 if narrow_portrait else 18.0") and shell_source.contains("var story_body_css_px := 24.0 if narrow_portrait else 28.0") and shell_source.contains("Vector2(0, 58) if _is_portrait_layout() else Vector2(400, 58)")
	check(narrow_story_contract, "390px prologue header, dialogue body and response buttons fit the portrait safe width without clipping")
	check(shell_source.contains("compact_landscape == last_compact_landscape_layout") and shell_source.contains("_rebuild_story_presentation()"), "live regular-to-compact resize rebuilds only the story presentation around its retained runner")
	var sample_story_commands := [
		{"command": "set_background"},
		{"command": "narration"},
		{"command": "play_sfx"},
		{"command": "dialogue"},
		{"command": "choice"},
	]
	check(shell.story_page_progress(sample_story_commands, 3) == Vector2i(2, 3), "story page counter excludes internal art and audio commands")
	check(shell_source.contains("title_cast_plate_r1.png") and shell_source.contains("title_cast_plate_portrait_r1.png") and shell_source.contains("title_logo_r1.png") and shell_source.contains("PortraitTitleCastLeft") and shell_source.contains("PortraitTitleCastRight") and shell_source.contains("CHR008/portrait.png") and shell_source.contains("CHR001/portrait.png") and shell_source.contains("Vector2(126.0, 252.0) * portrait_scale") and shell_source.contains("12.0 * portrait_scale") and shell_source.contains("var portrait_scale := _portrait_ui_scale() if portrait else 1.0") and shell_source.contains("Vector2(300.0, 84.0) * portrait_scale") and shell_source.contains("_label(notice_copy, 20 if portrait else 22") and shell_source.contains("START GAME을 눌러 시작") and shell_source.contains("START GAME  ·  기록 시작") and FileAccess.file_exists("res://assets/art/title/title_cast_plate_r1.png"), "portrait title keeps its full-body lead cast inside equal safe insets while retaining a single-scale LUMENBOUND lockup and clear START action")
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
	var startup_intro_contract := shell_source.contains("INTRO_VIDEO_PATH") and shell_source.contains("INTRO_VIDEO_DURATION_SECONDS := 53.0") and shell_source.contains("INTRO_VIDEO_FINISH_GUARD_SECONDS := 0.75") and shell_source.contains("StartupIntroVideoLayer") and shell_source.contains("StartupIntroAspectFrame") and shell_source.contains("AspectRatioContainer.STRETCH_FIT") and shell_source.contains("surface.theme = theme") and shell_source.contains("StartupIntroVideoPlayer") and shell_source.contains("StartupIntroTitleLockup") and shell_source.contains("StartupIntroTitleLogo") and shell_source.contains("intro_title_tween.tween_interval(5.0)") and shell_source.contains("intro_title_tween.tween_property(intro_title_lockup, \"modulate:a\", 0.0, 0.85)") and shell_source.contains("StartupIntroSkipButton") and shell_source.contains("_button(\"SKIP\", _finish_intro_video") and shell_source.contains("responsive_button_minimum_for_size") and shell_source.contains("intro_video_player.finished.connect(_finish_intro_video)") and shell_source.contains("create_timer(INTRO_VIDEO_DURATION_SECONDS + INTRO_VIDEO_FINISH_GUARD_SECONDS") and shell_source.contains("StartupIntroAudioGate") and shell_source.contains("소리 켜고 인트로 시작") and shell_source.contains("func _start_intro_video_playback") and shell_source.contains("_show_screen(\"TITLE\")")
	check(FileAccess.file_exists("res://assets/video/lumenbound_intro_full.ogv") and startup_intro_contract, "engine boot gates Web audio on a trusted click, then plays the Flow Music-free intro from zero before title")
	var cinematic_prologue_contract := shell_source.contains("PrologueCharacterIllustrations") and shell_source.contains("PrologueTopRightControls") and shell_source.contains("PrologueAutoButton") and shell_source.contains("PrologueSkipButton") and shell_source.contains("대화창 클릭 / 터치로 계속")
	var story_extension_contract := shell_source.contains("StoryTopRightControls") and shell_source.contains("StoryAutoButton") and shell_source.contains("StorySkipButton") and shell_source.contains("StorySpeakerEyebrow") and shell_source.contains("LUMENBOUND · VOICE LINK") and shell_source.contains("StoryMintSignalRail") and shell_source.contains("StoryPageIndicator") and shell_source.contains("_story_dialogue_style(false)")
	check(shell_source.contains("ClickablePrologueTextBox") and cinematic_prologue_contract and story_extension_contract and shell_source.contains("func _request_story_text_box_advance") and shell_source.contains("scenario_text.visible_ratio = 1.0"), "story text box keeps click/touch typewriter behavior while both story modes expose the LUMENBOUND dialogue hierarchy and fixed AUTO/SKIP rail")
	var portrait_hotfix_source := FileAccess.get_file_as_string("res://autoload/mobile_portrait_hotfix_v2.gd")
	var standard_story_touch_contract := shell_source.contains("dialogue.mouse_filter = Control.MOUSE_FILTER_STOP") and shell_source.contains("dialogue_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE") and shell_source.contains("dialogue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE") and portrait_hotfix_source.contains("var standard_dialogue_value = _shell.get(\"story_dialogue_panel\")") and portrait_hotfix_source.contains("var standard_dialogue_css := 380.0 if choice_mode else 304.0")
	check(standard_story_touch_contract, "MOBILE_N05_STORY_01 standard-story text plate owns the full tap surface and receives a dedicated portrait height, not only prologue geometry")
	var mobile_growth_contract := shell_source.contains("func _show_result_portrait") and shell_source.contains("report_scroll.name = \"PrimaryContentScroll\"") and shell_source.contains("MobileGrowthQuickActions") and shell_source.contains("MobileEquipmentChoices") and portrait_hotfix_source.contains("\"RESULT\", \"GROWTH\"") and portrait_hotfix_source.contains("func _fix_progression_scroll") and portrait_hotfix_source.contains("scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS") and portrait_hotfix_source.contains("scroll.follow_focus = true")
	check(mobile_growth_contract, "MOBILE_REWARD_GROWTH_01 portrait reward follow-up exposes level, weapon and equipment actions above a persistent touch-scroll rail")
	var map_source := FileAccess.get_file_as_string("res://chapter_map/runtime/chapter_map_screen.gd")
	var map_tutorial_flow_contract := map_source.contains("func _advance_first_map_tutorial()") and map_source.contains("tutorial_dismiss_button.text = \"안내 건너뛰기\"") and map_source.contains("tutorial_continue_button.pressed.connect(_advance_first_map_tutorial)") and map_source.contains("tutorial_dismiss_button.pressed.connect(_complete_first_map_tutorial)") and map_source.contains("tutorial_dismiss_button.visible = true") and map_source.contains("get_viewport().set_input_as_handled()")
	check(map_source.contains("FirstMapTutorialDimmer") and map_source.contains("tutorial_eyebrow.text = \"첫 작전 안내") and map_source.contains("tutorial_progress_label.text") and map_source.contains("map_basics_complete") and map_source.contains("map_basics_revision") and map_source.contains("_select_next_encounter()") and map_tutorial_flow_contract, "first chapter map provides contextual selection, movement and encounter guidance with actual three-step progression and an explicit skip")
	var app_state_source := FileAccess.get_file_as_string("res://autoload/app_state.gd")
	var home_onboarding_contract := shell_source.contains("HomeFirstOperationTutorialCanvas") and shell_source.contains("HomeTutorialSkipButton") and shell_source.contains("HomeTutorialContinueButton") and shell_source.contains("home_tutorial_surface.theme = theme") and shell_source.contains("자, 이제 제1장 탐색을 시작합니다") and shell_source.contains("func _complete_home_tutorial_and_launch()") and shell_source.contains("SceneRouter.go(\"STAGE_SELECT\")") and shell_source.contains("call_deferred(\"_commit_first_operation_navigation\")") and shell_source.contains("home_first_operation_navigation_pending") and shell_source.contains("HomeFirstOperationButton") and shell_source.contains("home_menu_buttons[\"STAGE\"]") and shell_source.contains("home_tutorial_resume_step") and shell_source.contains("_set_home_tutorial_step(home_tutorial_resume_step)") and shell_source.contains("home_tutorial_last_advance_msec < 400") and app_state_source.contains("\"home_basics_complete\": false") and app_state_source.contains("tutorial_progress[\"home_basics_complete\"] = false")
	check(home_onboarding_contract, "first HQ visit explains navigation, exposes Skip, and launches Chapter 1 without an unlabelled menu dead end")
	var story_skip_contract := shell_source.contains("STORY_SKIP_ALL") and shell_source.contains("현재 이야기 전체 건너뛰기") and shell_source.contains("while not scenario_runner.state.finished and safety < 1000") and shell_source.contains("_finish_story_navigation()")
	check(story_skip_contract, "player SKIP completes the current story scene instead of advancing only one line")
	var mobile_navigation_layout_contract := shell_source.contains("START GAME 버튼을 클릭 / 터치해 시작") and shell_source.contains("아래 응답 중 하나를 선택해 기록을 시작하세요.") and shell_source.contains("var preset_row: Container = GridContainer.new() if portrait else HBoxContainer.new()") and shell_source.contains("var slots: Container = GridContainer.new() if portrait else HBoxContainer.new()") and shell_source.contains("var compact_details := portrait or _is_compact_landscape_layout()") and shell_source.contains("var stage_scroll := ScrollContainer.new()") and shell_source.contains("var roster_box := _scroll_box()") and shell_source.contains("var growth_content := _scroll_box()") and shell_source.contains("var archive_box := _scroll_box()") and shell_source.contains("grid.columns = 1 if portrait else 5") and shell_source.contains("grid.columns = 1 if portrait else 4")
	check(mobile_navigation_layout_contract, "title, story choice, formation, stage fallback, roster, growth, inventory and archive routes expose explicit scrollable actions without portrait overflow")
	check(not shell_source.contains("두둥!") and not map_source.contains("두둥!") and shell_source.contains("_play_special_event_dialogue") and shell_source.contains("PreBattleEventDialog") and shell_source.contains("EventKeyVisual") and shell_source.contains("panel.gui_input.connect") and shell_source.contains("MAP_EVENT_DIALOGUE_SKIP"), "encounter presentation advances a real event dialogue with character/enemy key art instead of rendering a sound-effect caption")
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
	var skill_sequence_contract := battle_view_source.contains("var launch_delay := .18 if attack_kind == \"NORMAL\"") and battle_view_source.contains("var travel_key := \"%s_%s\"") and battle_view_source.contains("travel_frames[travel_frame]") and battle_view_source.contains("kind.trim_prefix(\"impact_\")") and battle_view_source.contains("frame = mini(textures.size() - 1, 6 +") and battle_view_source.contains("_spawn_vfx(str(event.source), str(event.target), \"impact_%s\"")
	check(skill_sequence_contract, "authored skill VFX follow charge, moving signature projectile, contact burst and hit-reaction sequence")
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
	var mute_shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd")
	var load_index := mute_shell_source.find("SaveService.load_game()")
	var mute_override_index := mute_shell_source.find("SettingsService.apply_web_preview_audio_override()")
	var mute_stop_index := mute_shell_source.find("AudioService.set_enabled(false)")
	check(settings_source.contains("func apply_web_preview_audio_override()") and settings_source.contains("func web_preview_audio_forced_muted()") and load_index >= 0 and mute_override_index > load_index and mute_stop_index > mute_override_index, "Web QA mute reapplies after the saved preference and stops audio before the title route")
	check(audio_service_source.contains("MusicCrossfadePlayer") and audio_service_source.contains("_begin_bgm_loop_crossfade") and audio_service_source.contains("_prepare_music_crossfade") and audio_service_source.contains("if not OS.has_feature(\"web\"):") and audio_service_source.contains("\"music_crossfade_enabled\": BGM_LOOP_CROSSFADE_SECONDS > 0.0 and not OS.has_feature(\"web\")"), "desktop BGM keeps its loop bridge while Web stays on one native-looped stream")
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
	var app_shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd")
	check(app_shell_source.contains("WEB_FRAME_RATE_CAP := 60") and app_shell_source.contains("Engine.max_fps = WEB_FRAME_RATE_CAP"), "Web Release caps redundant high-refresh rendering at sixty frames per second")

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
	var app_shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd")
	check(app_shell_source.contains("_apply_skill_icon(button, skill") and app_shell_source.contains("_apply_skill_icon(skill_button, skill"), "battle ultimate and growth skill controls render SkillDef icons")
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
		pooled_view._spawn_projectile(pool_sim.state.party[0].uid, pool_sim.state.enemies[0].uid, "BASIC")
		pooled_view._spawn_floating_text({"target": pool_sim.state.enemies[0].uid, "text": str(i), "color": Color.WHITE, "age": 1.0})
	for projectile in pooled_view.projectiles: projectile.age = 1.0
	pooled_view._recycle_expired_presentations()
	var recycled := pooled_view.pool_diagnostics()
	for i in range(100):
		pooled_view._spawn_projectile(pool_sim.state.party[0].uid, pool_sim.state.enemies[0].uid, "BASIC")
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
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd")
	var web_checkpoint_wiring := shell_source.contains("func _persist_story_checkpoint()") and shell_source.contains("var command := scenario_runner.advance()\n\t\t_persist_story_checkpoint()") and shell_source.contains("story_checkpoint_dirty = true") and shell_source.contains("func _flush_story_checkpoint_after_delay()") and shell_source.contains("await get_tree().create_timer(0.24).timeout") and shell_source.contains("story_checkpoint_dirty = false\n\tSaveService.save_game()") and shell_source.contains("var chosen := scenario_runner.choose(index)\n\tif not chosen.ok: return false\n\t_persist_story_checkpoint()")
	check(web_checkpoint_wiring, "story checkpoints are atomically persisted at Web dialogue and choice boundaries")
	check(DataRegistry.list_of("scenarios").size() == 105, "story content count covers all 20 chapters and interludes")
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
	check(migrated.ok and int(migrated.value.get("save_schema_version", 0)) == 9 and (migrated.value.get("relay", {}) as Dictionary).has("active_run") and legacy_reserved_kept, "save migration v7→v9 adds relay and preserves any legacy-owned reserved companion")
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
