extends Node

## Captures the phase-2 presentation through the real shell. Needs a rendering
## window (not --headless).
##   godot --path godot --resolution WxH res://tools/capture_presentation_phase2_qa.tscn -- <out_dir> <W> <H> battle [stage]
##   godot --path godot --resolution WxH res://tools/capture_presentation_phase2_qa.tscn -- <out_dir> <W> <H> map
## battle: regular enemies as three-body squads, a body dropping out, and the
## next wave waiting behind the enemy side.
## map: chapter 1 map surface, UI, markers, route preview, a hop step and the
## encounter transition.

var out_dir := ""
var tag := ""
var shell: Control
var report := {"shots": [], "notes": []}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = str(args[0])
	var width := int(args[1])
	var height := int(args[2])
	tag = "%dx%d" % [width, height]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().root.size = Vector2i(width, height)
	var mode := str(args[3]) if args.size() > 3 else "battle"
	var extra := str(args[4]) if args.size() > 4 else ""
	if mode == "map":
		_run_map.call_deferred(extra)
	else:
		_run_battle.call_deferred(extra if not extra.is_empty() else "CH01-N05")

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame

func _shot(name: String) -> void:
	await _frames(3)
	var path := out_dir.path_join("%s_%s.png" % [tag, name])
	get_tree().root.get_texture().get_image().save_png(path)
	report.shots.append(path.get_file())
	print("SHOT ", path.get_file())

func _boot() -> void:
	shell = load("res://screens/boot/boot.tscn").instantiate()
	get_tree().root.add_child(shell)
	await _frames(2)
	shell.call("_finish_intro_video")
	await _frames(2)

func _finish(label: String) -> void:
	print("%s %s" % [label, JSON.stringify(report)])
	get_tree().quit(0)

func _run_battle(stage_id: String) -> void:
	await _boot()
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
	shell.call("_start_deployed_battle")
	view.simulation.options["invincible"] = true
	await _wait(2.4)
	report.notes.append("next_wave=%d squads=%s" % [view.next_wave_layout().size(), JSON.stringify(view.swarm_snapshot())])
	await _shot("21_squads_next_wave")
	# Knock one squad to half and another to a sliver through the shown HP, then
	# hold the frame mid-burst.
	var squads: Array = view.simulation.state.enemies.filter(func(unit): return BattleView.swarm_unit(unit) and UnitState.alive(unit))
	view.paused = true
	for index in range(mini(2, squads.size())):
		var unit: Dictionary = squads[index]
		var shown: Dictionary = view.presentation_display_units.get(str(unit.uid), {})
		if shown.is_empty(): continue
		shown.hp = int(float(unit.max_hp) * (.5 if index == 0 else .2))
		view.presentation_display_units[str(unit.uid)] = shown
	view._track_swarm_members()
	for drop in view.swarm_drops: drop.age = .12
	view.queue_redraw()
	report.notes.append("after_hits=%s" % JSON.stringify(view.swarm_snapshot()))
	await _shot("22_squad_drop")
	for drop in view.swarm_drops: drop.age = BattleView.SWARM_DROP_DURATION
	view._track_swarm_members()
	view.queue_redraw()
	await _shot("23_squads_thinned")
	_finish("PHASE2_BATTLE_CAPTURE")

func _map_screen() -> Node:
	return shell.content.get_node_or_null("ChapterMapScreen") if shell != null else null

func _run_map(_stage: String) -> void:
	await _boot()
	AppState.profile.story_flags["story.trigger.TRIG_CH01_INTRO"] = true
	AppState.profile.pending_story_triggers.clear()
	AppState.profile["tutorial_progress"] = {"map_basics_revision": 99, "map_basics_complete": true}
	AppState.selected_stage_id = "CH01-N01"
	shell.call("_show_screen", "STAGE_SELECT")
	var map_screen: Node = null
	for frame in 1800:
		await get_tree().process_frame
		map_screen = _map_screen()
		if map_screen != null and bool(map_screen.get("map_ready_complete")) and (map_screen as Control).visible:
			break
	if map_screen == null:
		print("CAPTURE_FAIL no map")
		get_tree().quit(1)
		return
	await _wait(1.6)
	map_screen = _map_screen()
	report.notes.append("start=%s" % JSON.stringify(map_screen.call("presentation_phase2_snapshot")))
	await _shot("31_map_overview")
	# Route preview: dotted glowing line, arrowhead, step count, range rim.
	map_screen.call("_select_next_encounter")
	await _wait(0.9)
	report.notes.append("route=%s" % JSON.stringify(map_screen.call("presentation_phase2_snapshot")))
	await _shot("32_route_preview")
	map_screen.call("_show_map_notice", "경로 미리보기 · 같은 노란 칸을 한 번 더 클릭하면 이동합니다")
	await _wait(0.3)
	await _shot("33_notice_toast")
	# Marker designs on nearby cells (QA injection: the boss/elite nodes sit far
	# outside the opening vision radius).
	var fx: Control = map_screen.get("map_fx_overlay")
	var pawn: Node3D = map_screen.get("pawn")
	var base: Vector3 = pawn.global_position
	fx.set("extra_markers", [
		{"kind": "BOSS", "world": base + Vector3(-3.2, 1.4, -1.2), "phase": 0.0},
		{"kind": "ELITE", "world": base + Vector3(-1.2, 1.4, -2.6), "phase": 1.0},
		{"kind": "EVENT", "world": base + Vector3(1.4, 1.4, -2.8), "phase": 2.0},
		{"kind": "TREASURE", "world": base + Vector3(3.0, 1.4, -1.0), "phase": 3.0},
	])
	await _wait(0.2)
	await _shot("34_markers")
	fx.set("extra_markers", [])
	map_screen.call("_clear_selection")
	await _wait(0.3)
	# A real one-cell move, preferring a terrace change, caught mid-hop.
	var reachable: Dictionary = map_screen.get("movement_range_reachable")
	var grid = map_screen.get("grid")
	var here := Vector2i(int(map_screen.get("map_state").get("current_q", 0)), int(map_screen.get("map_state").get("current_r", 0)))
	var here_elevation := int(grid.tile(here).get("elevation", 0))
	var step := Vector2i(-9999, -9999)
	for key in reachable.keys():
		var coord := HexCoord.from_key(str(key))
		if coord == here or int(reachable[key]) != 1: continue
		if step.x == -9999 or int(grid.tile(coord).get("elevation", 0)) != here_elevation:
			step = coord
	if step.x != -9999:
		var path: Array[Vector2i] = [here, step]
		report.notes.append("hop_step=%s elev %d->%d" % [step, here_elevation, int(grid.tile(step).get("elevation", 0))])
		map_screen.call("_move_along", path)
		await get_tree().create_timer(0.15).timeout
		report.notes.append("mid_hop=%s" % JSON.stringify(map_screen.call("presentation_phase2_snapshot")))
		await _shot("35_hop")
		await get_tree().create_timer(0.2).timeout
		await _shot("36_landing_dust")
		await _wait(3.0)
	map_screen.call("_toggle_minimap")
	await _wait(0.2)
	await _shot("37_minimap_collapsed")
	map_screen.call("_toggle_minimap")
	# Encounter transition through the real shell path.
	SettingsService.values["map_reduced_transition"] = false
	AppState.selected_stage_id = "CH01-N01"
	shell.call("_play_map_battle_transition")
	await get_tree().create_timer(0.3).timeout
	await _shot("38_encounter_push_in")
	await get_tree().create_timer(0.5).timeout
	await _shot("39_encounter_panel")
	await _wait(1.2)
	_finish("PHASE2_MAP_CAPTURE")
