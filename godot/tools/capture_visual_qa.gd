extends Node

const BOOT_SCENE := preload("res://screens/boot/boot.tscn")

var shell = null
var output_dir := ""
var captures: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	output_dir = ProjectSettings.globalize_path("res://../reports/screenshots")
	var make_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if make_error != OK:
		push_error("CAPTURE_DIR_FAILED: %s" % error_string(make_error))
		get_tree().quit(2)
		return
	get_tree().root.size = Vector2i(1920, 1080)
	shell = BOOT_SCENE.instantiate()
	get_tree().root.add_child(shell)
	await get_tree().process_frame
	await get_tree().process_frame

	await _capture_screen("TITLE", "title.png")
	await _capture_screen("HOME", "home.png")
	AppState.active_scenario_id = "SCN_PROLOGUE"
	AppState.profile.last_scenario_position.erase("SCN_PROLOGUE")
	await _capture_screen("STORY", "story.png")
	await _capture_screen("FORMATION", "formation.png")
	AppState.selected_character_id = "CHR001"
	await _capture_screen("CHARACTER_DETAIL", "character_detail.png")
	await _capture_screen("GROWTH", "skill_upgrade.png")
	await _capture_screen("GROWTH", "weapon_upgrade.png")
	# First map entry intentionally routes through the Chapter 1 intro.  The
	# isolated visual-QA profile has already captured a story screen above, so
	# mark only that trigger complete before taking the dedicated map capture.
	# This keeps the production first-time flow untouched while ensuring this
	# background capture actually validates the rendered ChapterMapScreen.
	AppState.profile.story_flags["story.trigger.TRIG_CH01_INTRO"] = true
	AppState.profile.pending_story_triggers.clear()
	await _capture_screen("STAGE_SELECT", "chapter_map.png")
	# A synthetic offscreen window resize can queue the same responsive reflow
	# used by a phone rotation.  Let that deferred rebuild finish, then acquire
	# the *current* map instance; retaining the pre-reflow node captured only the
	# shell background after that instance was freed.
	await get_tree().create_timer(0.85).timeout
	await get_tree().process_frame
	var map_screen: Node = shell.content.get_node_or_null("ChapterMapScreen")
	if map_screen == null:
		push_error("CAPTURE_CHAPTER_MAP_NOT_FOUND")
		get_tree().quit(7)
		return
	map_screen.call("_select_next_encounter")
	await get_tree().create_timer(0.85).timeout
	await _save_viewport("chapter_map_n01_selected.png", "STAGE_SELECT_N01_SELECTED")

	AppState.selected_stage_id = "CH01-N01"
	shell._show_screen("BATTLE")
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_viewport("battle.png", "BATTLE")
	shell._toggle_battle_pause()
	await get_tree().process_frame
	await _save_viewport("battle_pause.png", "BATTLE_PAUSE")
	shell._toggle_battle_pause()
	var simulation: BattleSimulation = shell.battle_view.simulation
	var safety := 0
	while not simulation.state.ended and safety < 10000:
		simulation.tick()
		safety += 1
	if not simulation.state.ended:
		push_error("CAPTURE_BATTLE_DID_NOT_END")
		get_tree().quit(3)
		return
	shell._battle_finished(simulation.result_snapshot())
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_viewport("result.png", "RESULT")

	var manifest := {
		"kind": "WINDOWS_BACKGROUND_VISUAL_QA_CAPTURE",
		"created": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info().get("string", "unknown"),
		"renderer": RenderingServer.get_current_rendering_method(),
		"capture_mode": "OFFSCREEN_WINDOW_NO_FOREGROUND_AUTOMATION",
		"logical_size": [1920, 1080],
		"captures": captures,
	}
	var manifest_path := output_dir.path_join("capture_manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		push_error("CAPTURE_MANIFEST_OPEN_FAILED")
		get_tree().quit(4)
		return
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	print("VISUAL_QA_CAPTURE_SUMMARY total=%d path=%s" % [captures.size(), output_dir])
	# Release the large UI/CanvasItem graph before process teardown.  Destroying
	# the full shell only during exit can leave a CanvasItem RID in the Windows
	# offscreen capture path and has caused an exit-time OpenGL crash despite
	# successful PNG writes.
	await _finish_cleanly(0)


func _finish_cleanly(exit_code: int) -> void:
	if shell != null and is_instance_valid(shell):
		shell.queue_free()
		shell = null
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit(exit_code)


func _capture_screen(screen_id: String, filename: String) -> void:
	shell._show_screen(screen_id)
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_viewport(filename, screen_id)


func _save_viewport(filename: String, screen_id: String) -> void:
	await get_tree().process_frame
	var image := get_tree().root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("CAPTURE_EMPTY_IMAGE: %s" % screen_id)
		get_tree().quit(5)
		return
	var path := output_dir.path_join(filename)
	var save_error := image.save_png(path)
	if save_error != OK:
		push_error("CAPTURE_SAVE_FAILED: %s %s" % [path, error_string(save_error)])
		get_tree().quit(6)
		return
	captures.append({
		"screen": screen_id,
		"file": filename,
		"width": image.get_width(),
		"height": image.get_height(),
		"bytes": FileAccess.get_file_as_bytes(path).size(),
		"sha256": FileAccess.get_sha256(path),
	})
	print("CAPTURED %s %s" % [screen_id, path])
