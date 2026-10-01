extends Node

## Measures how far the chapter map's 2D overlays (movement range, route, selection
## ring, persistent grid) drift from the 3D terrain when the camera moves, because
## they move as one rigid piece (valid only for an orthographic camera).
##   godot --headless --path godot res://tools/probe_map_overlay_qa.tscn -- <CHnn> [dx dz]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var chapter := int(str(args[0]).trim_prefix("CH")) if args.size() > 0 else 1
	var delta := Vector3(float(args[1]) if args.size() > 1 else 2.0, 0.0, float(args[2]) if args.size() > 2 else 1.0)
	_run.call_deferred(chapter, delta)

func _run(chapter: int, delta: Vector3) -> void:
	AppState.new_game()
	var stage := "CH%02d-N01" % chapter
	AppState.selected_stage_id = stage
	AppState.profile["tutorial_progress"] = {"map_basics_revision": 99, "map_basics_complete": true}
	for perspective in [true, false]:
		SettingsService.values["map_camera_perspective"] = perspective
		var screen = load("res://chapter_map/runtime/chapter_map_screen.gd").new()
		screen.map_id = AppState.map_id_for_stage(stage)
		screen.size = Vector2(1600, 800)
		add_child(screen)
		for frame in 1500:
			await get_tree().process_frame
			if bool(screen.map_ready_complete): break
		await get_tree().process_frame
		await get_tree().process_frame
		var camera: Camera3D = screen.camera
		var party := Vector2i(int(screen.map_state.current_q), int(screen.map_state.current_r))
		var coords: Array = []
		for dq in range(-3, 4):
			for dr in range(-3, 4):
				var coord := party + Vector2i(dq, dr)
				if screen.grid.has(coord) and screen.HexCoordScript.distance(party, coord) <= 3: coords.append(coord)
		var elevations := {}
		for coord in coords: elevations[int(screen.grid.tile(coord).get("elevation", 0))] = true
		# Exact projection before the camera moves.
		var before := {}
		for coord in coords:
			var height: float = float(screen.grid.tile(coord).get("elevation", 0)) * screen.ELEVATION_STEP + .105
			var points := PackedVector2Array()
			for corner in screen._movement_hex_corners(coord, height): points.append(screen._overlay_position_from_world(corner))
			before[coord] = points
		var origin_before: Vector2 = screen._overlay_position_from_world(Vector3.ZERO)
		var target_before: Vector3 = screen.camera_target
		screen.camera_target = target_before + delta
		for i in 4: await get_tree().process_frame
		var origin_after: Vector2 = screen._overlay_position_from_world(Vector3.ZERO)
		var rigid_shift := origin_after - origin_before
		var centre_shift: Vector2 = screen._overlay_position_from_world(target_before) - (screen._overlay_position_from_world(screen.camera_target) - Vector2.ZERO)
		var worst := 0.0
		var sum := 0.0
		var count := 0
		var by_level := {}
		for coord in coords:
			var height: float = float(screen.grid.tile(coord).get("elevation", 0)) * screen.ELEVATION_STEP + .105
			var points := PackedVector2Array()
			for corner in screen._movement_hex_corners(coord, height): points.append(screen._overlay_position_from_world(corner))
			var level := int(screen.grid.tile(coord).get("elevation", 0))
			for index in points.size():
				var exact: Vector2 = points[index]
				var rigid: Vector2 = (before[coord] as PackedVector2Array)[index] + rigid_shift
				var error := exact.distance_to(rigid)
				worst = maxf(worst, error)
				sum += error
				count += 1
				var bucket: Array = by_level.get(level, [0.0, 0])
				bucket[0] = float(bucket[0]) + error
				bucket[1] = int(bucket[1]) + 1
				by_level[level] = bucket
		var levels := []
		for level in by_level.keys():
			levels.append("L%d=%.1fpx" % [level, float(by_level[level][0]) / float(by_level[level][1])])
		print("PROBE chapter=%d perspective=%s cells=%d levels=%s camera_move=%.2f rigid_shift=%.1f px  error mean=%.1f max=%.1f px  per-level %s" % [chapter, perspective, coords.size(), elevations.keys(), delta.length(), rigid_shift.length(), sum / maxf(1.0, float(count)), worst, " ".join(levels)])
		screen.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
