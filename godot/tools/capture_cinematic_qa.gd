extends Node

## Offscreen visual QA for the cinematic title / story / battle / result pass.
## Run with: --position 10000,10000 --resolution 1920x1080 res://tools/capture_cinematic_qa.tscn -- --out=<dir>

const BOOT_SCENE := preload("res://screens/boot/boot.tscn")

var shell = null
var output_dir := ""

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--out="): output_dir = str(arg).substr(6)
	if output_dir.is_empty(): output_dir = ProjectSettings.globalize_path("user://cinematic_qa")
	DirAccess.make_dir_recursive_absolute(output_dir)
	get_tree().root.size = Vector2i(1920, 1080)
	AppState.new_game()
	shell = BOOT_SCENE.instantiate()
	get_tree().root.add_child(shell)
	await _frames(3)
	# The native build plays the intro movie on boot; end it so the captures
	# show the screens rather than the video overlay.
	shell._finish_intro_video()
	await _wait(0.4)
	shell._show_screen("TITLE")
	await _wait(1.4)
	await _save("01_title.png")
	await _wait(1.6)
	await _save("02_title_later.png")
	AppState.active_scenario_id = "SCN_PROLOGUE"
	AppState.profile.last_scenario_position.erase("SCN_PROLOGUE")
	shell._show_screen("STORY")
	await _wait(0.5)
	for _index in range(3):
		shell._advance_story()
		await _wait(0.35)
	await _wait(1.2)
	await _save("03_story_prologue.png")
	AppState.active_scenario_id = "SCN_CH01_INTRO"
	AppState.profile.last_scenario_position.erase("SCN_CH01_INTRO")
	shell.story_auto = false
	shell._show_screen("STORY")
	await _wait(1.4)
	await _save("04_story_chapter.png")
	AppState.selected_stage_id = "CH01-N01"
	AppState.profile.chapter_progress.CH01.normal_highest = 0
	shell._show_screen("BATTLE")
	var waited := 0.0
	while (shell.battle_view == null or not is_instance_valid(shell.battle_view) or not shell.battle_view.assets_ready) and waited < 25.0:
		await _wait(0.25)
		waited += 0.25
	await _wait(1.0)
	await _save("05_battle_opening.png")
	await _wait(4.5)
	await _save("06_battle_fight.png")
	await _wait(3.0)
	await _save("07_battle_later.png")
	var simulation: BattleSimulation = shell.battle_view.simulation
	var safety := 0
	while not simulation.state.ended and safety < 12000:
		simulation.tick()
		safety += 1
	shell._battle_finished(simulation.result_snapshot())
	await _wait(1.5)
	await _save("08_result.png")
	shell._open_recommended_growth(AppState.get_party())
	await _wait(1.0)
	await _save("09_growth.png")
	print("CINEMATIC_QA_DONE path=%s" % output_dir)
	shell.queue_free()
	shell = null
	await _frames(3)
	get_tree().quit(0)

func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame

func _save(filename: String) -> void:
	await _frames(2)
	var image := get_tree().root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("CAPTURE_EMPTY " + filename)
		return
	image.save_png(output_dir.path_join(filename))
	print("CAPTURED " + filename)
