extends Node

## Captures the tactical battle flow through the real shell: the deployment
## screen, an ally selected for a move, the running battle and (on boss stages)
## a telegraphed area attack. Needs a rendering window (not --headless).
##   godot --path godot res://tools/capture_tactical_battle_qa.tscn -- <out_dir> <stage_id> <width> <height>

const BOOT_SCENE := preload("res://screens/boot/boot.tscn")

var shell: Control

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := str(args[0]) if args.size() > 0 else ProjectSettings.globalize_path("res://../reports/screenshots/tactical")
	var stage_id := str(args[1]) if args.size() > 1 else "CH01-N05"
	var width := int(args[2]) if args.size() > 2 else 1600
	var height := int(args[3]) if args.size() > 3 else 900
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().root.size = Vector2i(width, height)
	shell = BOOT_SCENE.instantiate()
	get_tree().root.add_child(shell)
	await _frames(2)
	# The boot intro sits in its own CanvasLayer above every screen.
	shell.call("_finish_intro_video")
	await _frames(2)
	AppState.selected_stage_id = stage_id
	shell.call("_show_screen", "BATTLE")
	var view: BattleView = null
	for frame in 600:
		await get_tree().process_frame
		view = shell.get("battle_view") as BattleView
		if view != null and view.assets_ready and view.get_node_or_null("BattleOverlay") != null:
			break
	var report := {"stage": stage_id, "size": [width, height], "shots": []}
	if view == null:
		print("TACTICAL_CAPTURE %s" % JSON.stringify({"pass": false, "error": "no battle view"}))
		get_tree().quit(1)
		return
	await _frames(90)
	report.deployment_active = view.deployment_active
	report.shots.append(_shot(out_dir, "%s_%dx%d_1_deploy.png" % [stage_id, width, height]))
	# Select the first ally by tapping its body, then preview a move target.
	var ally: Dictionary = view.simulation.state.party[0]
	var ally_point := view.cell_screen_center(int(ally.col), int(ally.lane)) + Vector2(0, -30)
	shell.call("_battle_tactical_tap", ally_point)
	await _frames(6)
	report.selected = str(shell.get("battle_selected_uid"))
	# The orb row must let a destination tap reach the near lane's cells.
	var orbs: Array = shell.get("ultimate_buttons")
	report.orbs_pass_through = not orbs.is_empty() and (orbs[0] as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE
	report.shots.append(_shot(out_dir, "%s_%dx%d_2_selected.png" % [stage_id, width, height]))
	shell.call("_battle_tactical_tap", view.cell_screen_center(0, 0))
	await _frames(40)
	report.moved_to = [int(view.simulation.find_unit(str(ally.uid)).col), int(view.simulation.find_unit(str(ally.uid)).lane)]
	shell.call("_start_deployed_battle")
	await _frames(240)
	report.tick_after_start = view.simulation.state.tick
	report.shots.append(_shot(out_dir, "%s_%dx%d_3_battle.png" % [stage_id, width, height]))
	# Wait for a telegraph (boss or enemy area) and capture it. QA only: the
	# party cannot fall and the clock runs at x3 so later waves are reached.
	view.simulation.options["invincible"] = true
	view.speed = 3
	for frame in 5400:
		await get_tree().process_frame
		if not view.simulation.pending_boss_casts.is_empty() or view.simulation.state.ended:
			break
	if not view.simulation.pending_boss_casts.is_empty():
		view.speed = 1
		report.telegraph = view.simulation.pending_boss_casts[0].get("label", "")
		await _frames(20)
		report.shots.append(_shot(out_dir, "%s_%dx%d_4_telegraph.png" % [stage_id, width, height]))
	report.pass = report.deployment_active and not str(report.selected).is_empty() and bool(report.orbs_pass_through) and int(report.tick_after_start) > 0
	print("TACTICAL_CAPTURE %s" % JSON.stringify(report))
	shell.queue_free()
	await _frames(2)
	get_tree().quit(0 if report.pass else 1)

func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame

func _shot(out_dir: String, file_name: String) -> String:
	var path := out_dir.path_join(file_name)
	get_tree().root.get_texture().get_image().save_png(path)
	return path
