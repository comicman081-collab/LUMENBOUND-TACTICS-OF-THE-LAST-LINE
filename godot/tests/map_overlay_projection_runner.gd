extends Node

## The chapter map's world-space overlays (movement range, orientation grid, route
## guide, selection ring) must stay on the terrain top of every elevation for any
## camera: pan, zoom, perspective or orthographic, camera moment. They used to slide
## as one rigid piece, which is only right for an orthographic camera.
##   godot --headless --path godot res://tests/map_overlay_projection_runner.tscn

const WorldCellOverlay := preload("res://chapter_map/runtime/world_cell_overlay.gd")
const CHAPTERS := [1, 7, 15]
const PIXEL_TOLERANCE := 0.05

var checks := 0
var failures := 0

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("MAP_OVERLAY_FAIL ", label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	AppState.new_game()
	AppState.profile["tutorial_progress"] = {"map_basics_revision": 99, "map_basics_complete": true}
	for chapter in CHAPTERS:
		for perspective in [true, false]:
			await _check_chapter(int(chapter), bool(perspective))
	await _check_native_path()
	var ok := failures == 0 and checks > 100
	print("MAP_OVERLAY_PROJECTION chapters=%d checks=%d failures=%d pass=%s" % [CHAPTERS.size(), checks, failures, ok])
	get_tree().quit(0 if ok else 1)

func _make_screen(chapter: int, perspective: bool, projected: bool) -> Control:
	SettingsService.values["map_camera_perspective"] = perspective
	var stage := "CH%02d-N01" % chapter
	AppState.selected_stage_id = stage
	var screen = load("res://chapter_map/runtime/chapter_map_screen.gd").new()
	screen.map_id = AppState.map_id_for_stage(stage)
	screen.size = Vector2(1600, 800)
	screen.projected_overlay_enabled = projected
	add_child(screen)
	for frame in 1500:
		await get_tree().process_frame
		if bool(screen.map_ready_complete):
			break
	for frame in 4:
		await get_tree().process_frame
	return screen

func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame

func _check_chapter(chapter: int, perspective: bool) -> void:
	var tag := "CH%02d/%s" % [chapter, "persp" if perspective else "ortho"]
	var screen = await _make_screen(chapter, perspective, true)
	_check(bool(screen.map_ready_complete), "%s map ready" % tag)
	_check(screen.web_movement_overlay != null and screen.web_movement_overlay.cell_count > 0, "%s range shown" % tag)
	_check(screen.overlay_view_serial > 0, "%s view published" % tag)
	var levels := {}
	for key in screen.web_movement_visible_keys:
		levels[int(screen.grid.tile(HexCoord.from_key(key)).get("elevation", 0))] = true
	var line := "MAP_OVERLAY %s cells=%d levels=%s" % [tag, screen.web_movement_visible_keys.size(), levels.keys()]

	# 1. The shared matrix is exactly Camera3D.unproject_position().
	var projection_error := _projection_error(screen)
	_check(projection_error < PIXEL_TOLERANCE, "%s matrix vs unproject_position %.4fpx" % [tag, projection_error])
	# 2. Cells sit at their own terrain top, and the border edges match the range.
	var geometry := _range_geometry(screen)
	_check(int(geometry.cells) == screen.web_movement_visible_keys.size(), "%s one centre per range cell (%d)" % [tag, int(geometry.cells)])
	_check(float(geometry.height_error) < 0.0001, "%s cell heights %.5f" % [tag, float(geometry.height_error)])
	_check(bool(geometry.border_exact), "%s border edges = outer edges of the range" % tag)
	var bands := _band_shape(screen)
	_check(int(bands.bands) > 0, "%s border bands exist" % tag)
	_check(float(bands.width_error) < 0.0005, "%s band width %.5f" % [tag, float(bands.width_error)])
	_check(float(bands.joint_error) < 0.0005, "%s band joints %.5f" % [tag, float(bands.joint_error)])
	_check(_uniforms_current(screen), "%s uniforms current" % tag)
	line += " proj_err=%.4f height_err=%.5f" % [projection_error, float(geometry.height_error)]

	# 3. A route over different heights and a selection ring follow the terrain.
	_arrange_route(screen)
	var route_error := _route_error(screen)
	_check(screen.web_route_overlay.visible, "%s route visible" % tag)
	_check(route_error < PIXEL_TOLERANCE, "%s route error %.4fpx" % [tag, route_error])
	_check(_ring_error(screen) < PIXEL_TOLERANCE, "%s ring error" % tag)
	_check(screen.web_selected_overlay.visible, "%s ring visible" % tag)

	# 4. Panning the camera keeps everything exact (the old rigid slide drifted).
	var serial: int = screen.overlay_view_serial
	screen.camera_target = screen.camera_target + Vector3(2.6, 0.0, 1.8)
	await _frames(4)
	_check(screen.overlay_view_serial > serial, "%s pan publishes a new view" % tag)
	_check(_projection_error(screen) < PIXEL_TOLERANCE, "%s matrix after pan" % tag)
	_check(_uniforms_current(screen), "%s uniforms after pan" % tag)
	var pan_route_error := _route_error(screen)
	_check(pan_route_error < PIXEL_TOLERANCE, "%s route after pan %.4fpx" % [tag, pan_route_error])
	_check(_ring_error(screen) < PIXEL_TOLERANCE, "%s ring after pan" % tag)
	_check(screen.web_route_view_serial == screen.overlay_view_serial, "%s route serial" % tag)
	line += " route_err=%.4f after_pan=%.4f" % [route_error, pan_route_error]

	# 5. Zoom changes the same way.
	serial = screen.overlay_view_serial
	screen.camera_zoom = 0.9 if float(screen.camera_zoom) > 1.0 else 1.4
	await _frames(4)
	_check(screen.overlay_view_serial > serial, "%s zoom publishes a new view" % tag)
	_check(_route_error(screen) < PIXEL_TOLERANCE, "%s route after zoom" % tag)
	_check(_uniforms_current(screen), "%s uniforms after zoom" % tag)

	# 6. A camera moment moves the camera without touching the look-at point.
	serial = screen.overlay_view_serial
	var started: bool = screen.play_camera_moment("impact", Vector3.INF)
	if started:
		var target_before: Vector3 = screen.camera_target
		await _frames(6)
		_check(screen.overlay_view_serial >= serial + 2, "%s moment publishes views (%d)" % [tag, screen.overlay_view_serial - serial])
		_check(_route_error(screen) < PIXEL_TOLERANCE, "%s route during moment" % tag)
		_check(_uniforms_current(screen), "%s uniforms during moment" % tag)
		line += " moment_views=%d target_moved=%s" % [screen.overlay_view_serial - serial, not target_before.is_equal_approx(screen.camera_target)]

	# 7. The orientation grid is built, only in front of the camera, and current.
	await _frames(8)
	var grid: Control = screen.persistent_cell_grid
	_check(int(grid.drawn_cells) > 0, "%s grid draws cells (%d)" % [tag, int(grid.drawn_cells)])
	_check(grid.open_layer.triangle_count() > 0, "%s grid triangles" % tag)
	_check(_chunks_in_front(screen), "%s grid chunks in front of the camera" % tag)
	_check(_uniforms_current(screen), "%s grid uniforms" % tag)
	line += " grid_cells=%d/%d tris=%d" % [int(grid.drawn_cells), grid.cells.size(), grid.open_layer.triangle_count() + grid.blocked_layer.triangle_count()]
	print(line)
	screen.queue_free()
	await get_tree().process_frame

func _check_native_path() -> void:
	var screen = await _make_screen(1, true, false)
	_check(screen.web_movement_overlay == null, "native: no projected range layer")
	_check(screen.movement_range_fill.mesh != null, "native: 3D range fill built")
	_check(screen.persistent_cell_grid.drawn_cells > 0, "native: orientation grid drawn")
	screen.queue_free()
	await get_tree().process_frame

func _projection_error(screen) -> float:
	var worst := 0.0
	for key in screen.web_movement_visible_keys:
		var coord: Vector2i = HexCoord.from_key(key)
		var height: float = float(screen.grid.tile(coord).get("elevation", 0)) * screen.ELEVATION_STEP + 0.105
		for corner in screen._movement_hex_corners(coord, height):
			var exact: Vector2 = screen._overlay_position_from_world(corner)
			var mirrored: Vector2 = WorldCellOverlay.project(screen.overlay_view_to_clip, corner, screen.overlay_view_size)
			worst = maxf(worst, exact.distance_to(mirrored))
	return worst

## Reads back the meshes the range layers hold: one centre per cell at the terrain
## top (first vertex of each cell triangle), and the middle line of every border band.
func _range_geometry(screen) -> Dictionary:
	var centres := {}
	var height_error := 0.0
	var border_edges := {}
	var border_height_error := 0.0
	var overlay = screen.web_movement_overlay
	for mesh in overlay.seam_layer.meshes:
		var arrays: Array = (mesh as ArrayMesh).surface_get_arrays(0)
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		for index in range(0, vertices.size(), 3):
			var centre := Vector2(vertices[index].x, vertices[index].y)
			var coord: Vector2i = HexCoord.world_to_axial(Vector3(centre.x, 0.0, centre.y), screen.TILE_SIZE)
			centres[coord] = true
			var expected: float = float(screen.grid.tile(coord).get("elevation", 0)) * screen.ELEVATION_STEP + 0.105
			for vertex_index in [index, index + 1, index + 2]:
				height_error = maxf(height_error, absf(float(uvs[vertex_index].x) - expected))
	# A border band triangle with two middle-line vertices (distance 1) carries one
	# whole border edge.
	for mesh in overlay.border_layer.meshes:
		var arrays: Array = (mesh as ArrayMesh).surface_get_arrays(0)
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		for index in range(0, vertices.size(), 3):
			var middle: Array = []
			for vertex_index in [index, index + 1, index + 2]:
				if is_equal_approx(float(uvs[vertex_index].y), 1.0):
					middle.append(vertex_index)
			if middle.size() != 2:
				continue
			border_edges[_edge_key(Vector2(vertices[middle[0]].x, vertices[middle[0]].y), Vector2(vertices[middle[1]].x, vertices[middle[1]].y))] = true
			border_height_error = maxf(border_height_error, absf(float(uvs[middle[0]].x) - float(uvs[middle[1]].x)))
	# Expected border: edges whose neighbour is outside the range, found with the
	# direction -> corner mapping the 3D ribbons use.
	var expected_edges := {}
	for key in screen.web_movement_visible_keys:
		var coord: Vector2i = HexCoord.from_key(key)
		var corners: Array[Vector3] = screen._movement_hex_corners(coord, float(screen.grid.tile(coord).get("elevation", 0)) * screen.ELEVATION_STEP + 0.105)
		for direction_index in range(HexCoord.DIRECTIONS.size()):
			if screen.movement_range_reachable.has(HexCoord.key(coord + HexCoord.DIRECTIONS[direction_index])):
				continue
			var pair: Vector2i = screen._movement_boundary_corner_indices(direction_index)
			expected_edges[_edge_key(Vector2(corners[pair.x].x, corners[pair.x].z), Vector2(corners[pair.y].x, corners[pair.y].z))] = true
	return {
		"cells": centres.size(),
		"height_error": maxf(height_error, border_height_error),
		"border_exact": border_edges.size() == expected_edges.size() and not border_edges.is_empty() and _same_keys(border_edges, expected_edges),
	}

## Every border band keeps both sides BORDER_HALF_WIDTH from its edge, and the bands
## that meet at a corner end on the same two points (a mitred join, no gap or overlap).
func _band_shape(screen) -> Dictionary:
	var width_error := 0.0
	var joint_error := 0.0
	var bands := 0
	var joints := {}
	var half_width: float = screen.web_movement_overlay.BORDER_HALF_WIDTH
	for mesh in screen.web_movement_overlay.border_layer.meshes:
		var arrays: Array = (mesh as ArrayMesh).surface_get_arrays(0)
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		for base in range(0, vertices.size(), 12):
			bands += 1
			var inner_from := Vector2(vertices[base].x, vertices[base].y)
			var inner_to := Vector2(vertices[base + 1].x, vertices[base + 1].y)
			var to := Vector2(vertices[base + 2].x, vertices[base + 2].y)
			var from := Vector2(vertices[base + 5].x, vertices[base + 5].y)
			var outer_to := Vector2(vertices[base + 8].x, vertices[base + 8].y)
			var outer_from := Vector2(vertices[base + 11].x, vertices[base + 11].y)
			var along := (to - from).normalized()
			var normal := Vector2(-along.y, along.x)
			for side in [inner_from, inner_to, outer_from, outer_to]:
				var reference := from if side == inner_from or side == outer_from else to
				width_error = maxf(width_error, absf(absf((side - reference).dot(normal)) - half_width))
			# Both ends are mirrored around the middle line.
			width_error = maxf(width_error, ((inner_from + outer_from) * 0.5).distance_to(from))
			width_error = maxf(width_error, ((inner_to + outer_to) * 0.5).distance_to(to))
			for pair in [[from, inner_from, outer_from], [to, inner_to, outer_to]]:
				var key := "%d,%d" % [roundi(pair[0].x * 1000.0), roundi(pair[0].y * 1000.0)]
				# Compare the two sides without caring which is "inner": store the
				# offsets sorted by their x then y.
				var low: Vector2 = pair[1] if (pair[1].x < pair[2].x or (is_equal_approx(pair[1].x, pair[2].x) and pair[1].y < pair[2].y)) else pair[2]
				var high: Vector2 = pair[2] if low == pair[1] else pair[1]
				if joints.has(key):
					var seen: Array = joints[key]
					joint_error = maxf(joint_error, maxf(low.distance_to(seen[0]), high.distance_to(seen[1])))
				else:
					joints[key] = [low, high]
	return {"bands": bands, "width_error": width_error, "joint_error": joint_error}

func _edge_key(a: Vector2, b: Vector2) -> String:
	var first := "%.3f,%.3f" % [a.x, a.y]
	var second := "%.3f,%.3f" % [b.x, b.y]
	return first + "|" + second if first < second else second + "|" + first

func _same_keys(a: Dictionary, b: Dictionary) -> bool:
	for key in a.keys():
		if not b.has(key):
			return false
	return true

func _uniforms_current(screen) -> bool:
	var layers: Array = [screen.web_movement_overlay.seam_layer, screen.web_movement_overlay.border_layer, screen.persistent_cell_grid.open_layer, screen.persistent_cell_grid.blocked_layer]
	for layer in layers:
		var matrix: Projection = layer.layer_material.get_shader_parameter("world_to_clip")
		if matrix != screen.overlay_view_to_clip:
			return false
		if layer.layer_material.get_shader_parameter("target_size") != screen.overlay_view_size:
			return false
	return true

## Route over the party's range, ending on the cell whose height differs most from
## the party's, so the guide crosses terraces; plus a selected target on it.
func _arrange_route(screen) -> void:
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
	screen.selected_node = {"node_id": "overlay_test", "q": best.x, "r": best.y}
	screen._update_route_mesh()

func _route_error(screen) -> float:
	var worst := 0.0
	var points := PackedVector2Array()
	for coord in screen.preview_path:
		var surface_y: float = float(screen.grid.tile(coord).get("elevation", 0)) * screen.ELEVATION_STEP + 0.57
		points.append(screen._overlay_position_from_world(HexCoord.axial_to_world(coord, screen.TILE_SIZE, surface_y)))
	if points.size() < 2:
		return 1.0e9
	for index in range(points.size() - 1):
		var segment: ColorRect = screen.web_route_rects[index]
		worst = maxf(worst, (segment.position + segment.pivot_offset).distance_to((points[index] + points[index + 1]) * 0.5))
		worst = maxf(worst, absf(segment.size.x - points[index].distance_to(points[index + 1])))
		worst = maxf(worst, absf(angle_difference(segment.rotation, (points[index + 1] - points[index]).angle())) * 10.0)
	return worst

func _ring_error(screen) -> float:
	var selected: Dictionary = screen.selected_node
	var coord := Vector2i(int(selected.get("q", 0)), int(selected.get("r", 0)))
	var centre := HexCoord.axial_to_world(coord, screen.TILE_SIZE, float(screen.grid.tile(coord).get("elevation", 0)) * screen.ELEVATION_STEP + 0.18)
	var points := PackedVector2Array()
	for point_index in range(6):
		var angle := PI / 6.0 + TAU * float(point_index) / 6.0
		points.append(screen._overlay_position_from_world(centre + Vector3(cos(angle) * 0.66, 0.0, sin(angle) * 0.66)))
	var worst := 0.0
	for edge_index in range(6):
		var edge: ColorRect = screen.web_selected_rects[edge_index]
		worst = maxf(worst, (edge.position + edge.pivot_offset).distance_to((points[edge_index] + points[(edge_index + 1) % 6]) * 0.5))
	return worst

## Every cell of a drawn chunk is safely in front of the camera plane.
func _chunks_in_front(screen) -> bool:
	var grid: Control = screen.persistent_cell_grid
	for key in grid._selected_keys:
		var chunk: Dictionary = grid.chunks[key]
		if not bool(chunk.built):
			continue
		for index in chunk.cells:
			for corner in grid.cells[int(index)].corners:
				var depth: float = (corner - screen.camera.global_position).dot(-screen.camera.global_transform.basis.z)
				if depth < grid.DEPTH_MARGIN - 0.001:
					return false
	return true
