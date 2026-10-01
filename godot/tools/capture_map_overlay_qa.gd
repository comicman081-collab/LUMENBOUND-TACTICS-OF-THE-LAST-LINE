extends Node

## Captures the chapter map with the movement range, route guide, selection ring and
## orientation grid for one camera set-up, so the 3D range (native) and the projected
## range (web path, LUMEN_MAP_PROJECTED_OVERLAY=1) can be compared by eye.
##   godot --path godot --resolution 1600x900 res://tools/capture_map_overlay_qa.tscn -- <out_dir> <chapter> <perspective 0|1> [projected 0|1]
## Frames: start, pan, route, zoom, moment.

var out_dir := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = str(args[0]) if args.size() > 0 else "user://map_overlay_capture"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var chapter := int(args[1]) if args.size() > 1 else 1
	var perspective := (str(args[2]) != "0") if args.size() > 2 else true
	var projected := (str(args[3]) == "1") if args.size() > 3 else false
	_run.call_deferred(chapter, perspective, projected)

func _frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await _frames(3)
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name))
	print("SHOT ", name)

func _run(chapter: int, perspective: bool, projected: bool) -> void:
	AppState.new_game()
	AppState.profile["tutorial_progress"] = {"map_basics_revision": 99, "map_basics_complete": true}
	SettingsService.values["map_camera_perspective"] = perspective
	var stage := "CH%02d-N01" % chapter
	AppState.selected_stage_id = stage
	var screen = load("res://chapter_map/runtime/chapter_map_screen.gd").new()
	screen.map_id = AppState.map_id_for_stage(stage)
	screen.projected_overlay_enabled = projected
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	for frame in 1500:
		await get_tree().process_frame
		if bool(screen.map_ready_complete):
			break
	await get_tree().create_timer(2.5).timeout
	print("CAPTURE chapter=%d perspective=%s projected=%s cells=%d" % [chapter, perspective, projected, screen.movement_range_reachable.size()])
	await _shot("a_start.png")
	screen.camera_target = screen.camera_target + Vector3(2.6, 0.0, 1.8)
	await get_tree().create_timer(1.2).timeout
	await _shot("b_pan.png")
	# A destination on the other side of a terrace, with its selection ring.
	var party := Vector2i(int(screen.map_state.current_q), int(screen.map_state.current_r))
	var party_level := int(screen.grid.tile(party).get("elevation", 0))
	var best := party
	var best_score := -1
	for key in screen.movement_range_reachable.keys():
		var coord: Vector2i = HexCoord.from_key(str(key))
		var score := absi(int(screen.grid.tile(coord).get("elevation", 0)) - party_level) * 10 + HexCoord.distance(party, coord)
		if score > best_score:
			best_score = score
			best = coord
	var path: Array[Vector2i] = screen._find_player_path(party, best)
	screen.preview_path = path
	screen.selected_node = {"node_id": "overlay_capture", "q": best.x, "r": best.y}
	screen._update_route_mesh()
	screen.camera_target = screen.camera_target - Vector3(2.6, 0.0, 1.8)
	await get_tree().create_timer(1.2).timeout
	await _shot("c_route.png")
	screen.camera_zoom = 1.5
	await get_tree().create_timer(1.2).timeout
	await _shot("d_zoom_in.png")
	screen.camera_zoom = 0.75
	await get_tree().create_timer(1.2).timeout
	await _shot("e_zoom_out.png")
	get_tree().quit(0)
