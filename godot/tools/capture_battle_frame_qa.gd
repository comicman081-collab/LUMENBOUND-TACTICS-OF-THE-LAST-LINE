extends Node

## One deterministic battle frame through the real shell, for before/after
## comparisons of the battle drawing. Needs a rendering window (not --headless).
##   godot --path godot --resolution 1600x900 res://tools/capture_battle_frame_qa.tscn -- <out_dir> <tag> <stage_id> [clock] [mode]
## The regional floor clock is pinned (`clock`, default 3.0 s) so ornaments and
## motes stand in the same place in every run; mode is "ready" (deployment panel
## up, the default) or "fight" (battle running a moment, invincible allies).

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := str(args[0])
	var tag := str(args[1])
	var stage_id := str(args[2])
	var clock := float(args[3]) if args.size() > 3 else 3.0
	var mode := str(args[4]) if args.size() > 4 else "ready"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var shell: Control = load("res://screens/boot/boot.tscn").instantiate()
	get_tree().root.add_child(shell)
	await _frames(2)
	shell.call("_finish_intro_video")
	await _frames(2)
	SettingsService.values["battle_cutin_mode"] = "OFF"
	AppState.selected_stage_id = stage_id
	shell.call("_show_screen", "BATTLE")
	var view: BattleView = null
	for frame in 900:
		await get_tree().process_frame
		view = shell.get("battle_view") as BattleView
		if view != null and view.assets_ready and view.get_node_or_null("BattleOverlay") != null:
			break
	if view == null:
		print("CAPTURE_FAIL no battle view")
		get_tree().quit(1)
		return
	await _frames(60)
	if mode == "fight":
		shell.call("_start_deployed_battle")
		view.simulation.options["invincible"] = true
		await get_tree().create_timer(1.2).timeout
	view.set("region_clock_override", clock)
	view.paused = true
	await _frames(4)
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("%s_%s_%s.png" % [tag, stage_id, mode])
	get_tree().root.get_texture().get_image().save_png(path)
	print("SHOT ", path.get_file())
	get_tree().quit(0)
