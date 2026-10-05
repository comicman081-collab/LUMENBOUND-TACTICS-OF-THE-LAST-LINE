extends Node

## Run with the existing COMMON.ps1 isolated user-path setup:
## godot --headless --path godot res://chapter_map/tests/map_fps_regression.tscn
## Tests exact visible coverage, including cached selection between camera steps.
const Screen := preload("res://chapter_map/runtime/chapter_map_screen.gd")
const CellGrid := preload("res://chapter_map/runtime/map_cell_grid.gd")
const Overlay := preload("res://chapter_map/ui/map_presentation_overlay.gd")
const Loader := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const Rig := preload("res://chapter_map/view/map_camera_rig.gd")
const Hex := preload("res://chapter_map/model/hex_coord.gd")
const Minimap := preload("res://chapter_map/ui/chapter_route_minimap.gd")
var failures := 0
var views := 0
var visible_cells := 0
var old_cells := 0
var selected_cells := 0
var projection_calls := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("MAP_FPS_REGRESSION " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_projection_cache()
	_minimap_cache()
	var screen := Screen.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	screen.camera = camera
	screen.overlay = Control.new()
	var cell_grid := CellGrid.new()
	add_child(cell_grid)
	for chapter in [1, 7, 15]:
		screen.definition = Loader.load_map("CH%02d_MAP" % chapter)
		check(not screen.definition.is_empty(), "chapter %d loads" % chapter)
		screen.grid.load_tiles(screen.definition.get("tiles", []))
		cell_grid.configure(screen)
		var nodes: Array = screen.definition.get("nodes", [])
		for node_index in [0, nodes.size() / 2, nodes.size() - 1]:
			var node: Dictionary = nodes[int(node_index)]
			var coord := Vector2i(int(node.q), int(node.r))
			var target := Hex.axial_to_world(coord, screen.TILE_SIZE, float(screen.grid.tile(coord).get("elevation", 0)) * screen.ELEVATION_STEP)
			for perspective in [true, false]:
				for shape in [Vector2i(1600, 800), Vector2i(480, 800)]:
					viewport.size = shape
					screen.overlay.size = Vector2(shape)
					for zoom in [0.72, 1.4]:
						for yaw in [-0.13, 0.0, 0.11]:
							_set_camera(screen, target, zoom, yaw, perspective)
							cell_grid._select_chunks(screen)
							_verify_coverage(screen, cell_grid, true)
							if not perspective:
								_set_camera(screen, target, zoom * 0.8, yaw, false)
								check(cell_grid._selection_needs_refresh(screen), "orthographic lens change forces selection refresh")
							# Less than every reselection threshold, so the old mesh
							# set must cover the newly exposed strip conservatively.
							_set_camera(screen, target + Vector3(0.60, 0, -0.60), zoom + (0.015 if perspective else 0.0), yaw + 0.024, perspective)
							check(not cell_grid._selection_needs_refresh(screen), "padded view stays inside reuse thresholds")
							_verify_coverage(screen, cell_grid, false)
	screen.overlay.free()
	screen.free()
	viewport.queue_free()
	cell_grid.queue_free()
	await get_tree().process_frame
	print("MAP_FPS_REGRESSION views=%d visible_cells=%d old_submitted_cells=%d selected_cells=%d reduction=%.1f%% failures=%d" % [views, visible_cells, old_cells, selected_cells, 100.0 * (1.0 - float(selected_cells) / maxf(1.0, old_cells)), failures])
	get_tree().quit(0 if failures == 0 else 1)

func _set_camera(screen, target: Vector3, zoom: float, yaw: float, perspective: bool) -> void:
	screen.camera_target = target
	screen.camera.projection = Camera3D.PROJECTION_PERSPECTIVE if perspective else Camera3D.PROJECTION_ORTHOGONAL
	screen.camera.fov = Rig.fov_degrees()
	screen.camera.size = Rig.view_size(zoom)
	screen.camera.position = target + Rig.offset(screen.camera.size, yaw, perspective)
	screen.camera.look_at(target, Vector3.UP)
	screen._refresh_overlay_view()

func _verify_coverage(screen, cell_grid, collect_counts: bool) -> void:
	views += 1
	var selected := {}
	for key in cell_grid._selected_keys:
		selected[key] = true
	var frame := PackedVector2Array([Vector2.ZERO, Vector2(screen.overlay.size.x, 0), screen.overlay.size, Vector2(0, screen.overlay.size.y)])
	var frame_rect := Rect2(Vector2.ZERO, screen.overlay.size)
	var reach: float = maxf(screen.overlay_view_distance * CellGrid.FAR_FACTOR, 24.0)
	for key in cell_grid.chunks:
		var chunk: Dictionary = cell_grid.chunks[key]
		var low: Vector3 = chunk.lo
		var high: Vector3 = chunk.hi
		var gap := Vector2(clampf(screen.camera_target.x, low.x, high.x) - screen.camera_target.x, clampf(screen.camera_target.z, low.z, high.z) - screen.camera_target.z).length()
		if gap > reach:
			continue
		var in_front := true
		for corner_index in range(8):
			var corner := Vector3(high.x if corner_index & 1 else low.x, high.y if corner_index & 2 else low.y, high.z if corner_index & 4 else low.z)
			if (corner - screen.overlay_view_origin).dot(screen.overlay_view_forward) < CellGrid.DEPTH_MARGIN:
				in_front = false
				break
		if not in_front:
			continue
		if collect_counts:
			old_cells += chunk.cells.size()
			if selected.has(key): selected_cells += chunk.cells.size()
		for index in chunk.cells:
			var polygon := PackedVector2Array()
			var bounds := Rect2()
			for corner in cell_grid.cells[int(index)].corners:
				var point: Vector2 = screen.camera.unproject_position(corner)
				if polygon.is_empty(): bounds = Rect2(point, Vector2.ZERO)
				else: bounds = bounds.expand(point)
				polygon.append(point)
			if not bounds.intersects(frame_rect, true):
				continue
			if not Geometry2D.intersect_polygons(polygon, frame).is_empty():
				visible_cells += 1
				check(selected.has(key), "visible hex lost in selected/reused view: " + str(key))

func _count_projection(world: Vector3) -> Vector2:
	projection_calls += 1
	return Vector2(world.x * 10.0, world.z * 10.0)

func _projection_cache() -> void:
	var overlay := Overlay.new()
	overlay.projector = _count_projection
	overlay.set_route([Vector3.ZERO, Vector3.ONE, Vector3(2, 0, 3)], 2, Color.CYAN)
	overlay.set_rim([[Vector3.ZERO, Vector3(1, 0, 0)], [Vector3.ONE, Vector3(2, 0, 1)]], Vector3.ONE)
	overlay.apply_projection_serial(1)
	overlay._refresh_projected_geometry()
	var initial := projection_calls
	var points := overlay.projected_route.duplicate()
	for frame in 360:
		overlay._process(1.0 / 60.0)
		overlay._refresh_projected_geometry()
	check(initial == 8 and projection_calls == initial, "stationary route/rim performs zero repeat projections")
	check(points == overlay.projected_route, "stationary projection points remain exact")
	overlay.apply_projection_serial(2)
	overlay._refresh_projected_geometry()
	check(projection_calls == initial * 2, "camera serial invalidates cached points once")
	overlay.set_route([Vector3.ZERO, Vector3.ONE], 1, Color.CYAN)
	overlay._refresh_projected_geometry()
	check(overlay.projected_route.size() == 2, "route replacement invalidates cache")
	print("MAP_FPS_CACHE initial_projections=%d repeated_idle_projections=0 frames=360" % initial)
	overlay.free()

func _minimap_cache() -> void:
	var minimap := Minimap.new()
	minimap.size = Vector2(240, 160)
	add_child(minimap)
	var tiles: Array = []
	for q in range(-3, 4):
		for r in range(-3, 4):
			tiles.append({"q": q, "r": r, "terrain_type": "FOREST"})
	tiles.append({"q": 60, "r": 0, "terrain_type": "ROAD"})
	var definition := {"map_id": "MINIMAP_CACHE_TEST", "tiles": tiles,
		"nodes": [{"node_id": "PATROL", "stage_id": "CH01-N01", "q": 1, "r": 0}]}
	var state := {"current_q": 0, "current_r": 0, "visited_tiles": [],
		"discovered_tiles": ["3,0"], "patrol_states": {"PATROL": {"q": 1, "r": 0}}}
	minimap.configure(definition, state, {}, false, 1)
	var first_revision := minimap.terrain_revision
	check(minimap.explored.size() == 8 and not minimap.explored.has("60,0"), "minimap retains exact explored cells and fog")
	minimap.configure(definition, state, {"q": 1, "r": 0}, false, 1)
	check(minimap.terrain_revision == first_revision and minimap.selected_coord == Vector2i(1, 0), "destination selection preserves cached terrain")
	state.patrol_states.PATROL = {"q": -1, "r": 0}
	minimap.configure(definition, state, {}, false, 1)
	check(minimap.terrain_revision == first_revision, "patrol-only turn preserves cached terrain")
	check(minimap.markers.any(func(marker): return marker.kind == "enemy" and marker.coord == Vector2i(-1, 0)), "patrol marker still follows its live coordinate")
	state.current_q = 1
	minimap.configure(definition, state, {}, false, 1)
	check(minimap.terrain_revision > first_revision and minimap.current_coord == Vector2i(1, 0), "squad movement invalidates terrain framing")
	var movement_revision := minimap.terrain_revision
	minimap.full_map = true
	minimap.configure(definition, state, {}, false, 1)
	check(minimap.terrain_revision > movement_revision and not minimap.explored.has("60,0"), "expanded map redraws explored terrain only")
	var expanded_revision := minimap.terrain_revision
	minimap.size = Vector2(700, 400)
	check(minimap.terrain_revision > expanded_revision, "resize invalidates terrain projection")
	minimap.queue_free()
