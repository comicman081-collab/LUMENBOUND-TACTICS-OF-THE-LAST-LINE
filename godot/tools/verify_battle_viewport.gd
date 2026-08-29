extends Node

const BOOT_SCENE := preload("res://screens/boot/boot.tscn")

var shell: Control

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# This must run through a real offscreen window rather than headless mode:
	# the regression appeared only when CanvasItem layout resolved a narrow Web-
	# like portrait viewport.
	get_tree().root.size = Vector2i(566, 850)
	shell = BOOT_SCENE.instantiate()
	get_tree().root.add_child(shell)
	await get_tree().process_frame
	await get_tree().process_frame
	AppState.selected_stage_id = "CH01-H03"
	shell.call("_show_screen", "BATTLE")
	for frame in 8:
		await get_tree().process_frame
	var battle_view: Control = shell.get("battle_view") as Control
	var content: Control = shell.get("content") as Control
	var overlay := battle_view.get_node_or_null("BattleOverlay") if battle_view != null else null
	var passed := battle_view != null and content != null and overlay != null
	passed = passed and battle_view.visible and battle_view.size.x >= 500.0 and battle_view.size.y >= 420.0
	passed = passed and battle_view.size.x >= content.size.x - 2.0
	var output_dir := ProjectSettings.globalize_path("res://../reports/screenshots")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var image := get_tree().root.get_texture().get_image()
	var save_error := image.save_png(output_dir.path_join("battle_portrait_smoke.png"))
	passed = passed and save_error == OK
	print("BATTLE_PORTRAIT_VIEWPORT %s" % JSON.stringify({
		"pass": passed,
		"battle_size": [battle_view.size.x, battle_view.size.y] if battle_view != null else [],
		"content_size": [content.size.x, content.size.y] if content != null else [],
		"has_overlay": overlay != null,
		"screenshot": output_dir.path_join("battle_portrait_smoke.png"),
	}))
	if shell != null:
		shell.queue_free()
		await get_tree().process_frame
	get_tree().quit(0 if passed else 1)
