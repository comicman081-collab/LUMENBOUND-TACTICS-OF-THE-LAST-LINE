class_name ChapterRouteMinimap
extends Control

# Read-only overview of the macro chapter route. The real map remains the
# selectable 3D surface; this panel only makes the deliberately long R7 route
# legible without forcing the camera to zoom so far out that terrain fails.

var normal_points: Array[Vector2] = []
var hard_points: Array[Vector2] = []
var relay_points: Array[Vector2] = []
var landmark_points: Array[Vector2] = []
var enemy_points: Array[Vector2] = []
var treasure_points: Array[Vector2] = []
var revealed_coords: Dictionary = {}
var current_coord := Vector2i.ZERO
var selected_coord := Vector2i(-99999, -99999)
var show_hard := false
var bounds_min := Vector2.ZERO
var bounds_max := Vector2.ONE
var static_route_signature := ""
var exploration_signature := ""

func configure(map_definition: Dictionary, state: Dictionary, selected: Dictionary, hard_visible: bool) -> void:
	var next_static_signature := "%s:%d:%d:%d" % [
		str(map_definition.get("map_id", "")),
		hash(map_definition.get("nodes", [])),
		hash(map_definition.get("normal_route", [])),
		hash(map_definition.get("hard_route", [])),
	]
	if next_static_signature != static_route_signature:
		static_route_signature = next_static_signature
		normal_points.clear()
		hard_points.clear()
		var nodes_by_stage: Dictionary = {}
		for raw_node in map_definition.get("nodes", []):
			var node: Dictionary = raw_node
			var stage_id := str(node.get("stage_id", ""))
			if stage_id != "":
				nodes_by_stage[stage_id] = _axial_point(Vector2i(int(node.get("q", 0)), int(node.get("r", 0))))
		for stage_id in map_definition.get("normal_route", []):
			if nodes_by_stage.has(str(stage_id)):
				normal_points.append(nodes_by_stage[str(stage_id)])
		for stage_id in map_definition.get("hard_route", []):
			if nodes_by_stage.has(str(stage_id)):
				hard_points.append(nodes_by_stage[str(stage_id)])
	var next_exploration_signature := "%d:%d:%d:%d" % [
		hash(state.get("revealed_tiles", [])),
		hash(state.get("relay_states", {})),
		hash(state.get("cleared_encounters", [])),
		hash(state.get("treasure_states", {})),
	]
	if next_exploration_signature != exploration_signature:
		exploration_signature = next_exploration_signature
		relay_points.clear()
		landmark_points.clear()
		enemy_points.clear()
		treasure_points.clear()
		revealed_coords.clear()
		for raw_key in state.get("revealed_tiles", []):
			revealed_coords[str(raw_key)] = true
		for relay in map_definition.get("relays", []):
			if str(state.get("relay_states", {}).get(str(relay.get("relay_id", "")), "OFFLINE")) == "ACTIVE":
				relay_points.append(_axial_point(Vector2i(int(relay.get("q", 0)), int(relay.get("r", 0)))))
		for landmark in map_definition.get("landmarks", []):
			if str(landmark.get("kind", "")) == "MAJOR":
				var coord := Vector2i(int(landmark.get("q", 0)), int(landmark.get("r", 0)))
				if revealed_coords.has("%d,%d" % [coord.x, coord.y]):
					landmark_points.append(_axial_point(coord))
		var cleared_encounters: Array = state.get("cleared_encounters", [])
		for node in map_definition.get("nodes", []):
			var node_id := str(node.get("node_id", ""))
			var stage_id := str(node.get("stage_id", ""))
			var coord := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
			if stage_id != "" and revealed_coords.has("%d,%d" % [coord.x, coord.y]) and not cleared_encounters.has(node_id):
				enemy_points.append(_axial_point(coord))
		for treasure in map_definition.get("treasures", []):
			var treasure_id := str(treasure.get("treasure_id", ""))
			var coord := Vector2i(int(treasure.get("q", 0)), int(treasure.get("r", 0)))
			if str(state.get("treasure_states", {}).get(treasure_id, "UNDISCOVERED")) == "REVEALED":
				treasure_points.append(_axial_point(coord))
	show_hard = hard_visible
	current_coord = Vector2i(int(state.get("current_q", 0)), int(state.get("current_r", 0)))
	selected_coord = Vector2i(int(selected.get("q", -99999)), int(selected.get("r", -99999))) if not selected.is_empty() else Vector2i(-99999, -99999)
	_recalculate_bounds()
	queue_redraw()

func _axial_point(coord: Vector2i) -> Vector2:
	return Vector2(float(coord.x) + float(coord.y) * 0.5, float(coord.y))

func _recalculate_bounds() -> void:
	var all_points := normal_points + hard_points + [_axial_point(current_coord)]
	if all_points.is_empty():
		bounds_min = Vector2.ZERO
		bounds_max = Vector2.ONE
		return
	bounds_min = all_points[0]
	bounds_max = all_points[0]
	for point in all_points:
		bounds_min = bounds_min.min(point)
		bounds_max = bounds_max.max(point)
	var pad := Vector2(maxf(2.0, (bounds_max.x - bounds_min.x) * 0.08), maxf(1.3, (bounds_max.y - bounds_min.y) * 0.16))
	bounds_min -= pad
	bounds_max += pad

func _map_point(point: Vector2) -> Vector2:
	var safe_size := Vector2(maxf(1.0, size.x), maxf(1.0, size.y))
	var usable := safe_size - Vector2(24.0, 34.0)
	var span := bounds_max - bounds_min
	var denominator := Vector2(maxf(0.001, span.x), maxf(0.001, span.y))
	var normalized := (point - bounds_min) / denominator
	return Vector2(12.0 + normalized.x * usable.x, 24.0 + normalized.y * usable.y)

func _draw_route(points: Array[Vector2], color: Color, dimmed: bool) -> void:
	if points.is_empty():
		return
	var line := PackedVector2Array()
	for point in points:
		line.append(_map_point(point))
	if line.size() >= 2:
		draw_polyline(line, color.darkened(0.35) if dimmed else color, 2.5, true)
	for index in range(line.size()):
		var point := line[index]
		var node_color := color.darkened(0.50) if dimmed else color
		draw_circle(point, 5.5 if index == line.size() - 1 else 4.2, Color("061522"))
		draw_circle(point, 3.8 if index == line.size() - 1 else 2.7, node_color)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_panel_style(), rect)
	var font := get_theme_default_font()
	draw_string(font, Vector2(12.0, 16.0), "탐색 경로", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color("c8eee8"))
	_draw_route(normal_points, Color("5fe5c8"), show_hard)
	_draw_route(hard_points, Color("d38cff"), not show_hard)
	for point in landmark_points:
		draw_circle(_map_point(point), 4.8, Color("b7a76a"))
	for point in relay_points:
		draw_circle(_map_point(point), 4.0, Color("68f1d2"))
	for point in enemy_points:
		draw_circle(_map_point(point), 3.2, Color("e57276"))
	for point in treasure_points:
		draw_circle(_map_point(point), 3.2, Color("f2cd75"))
	var current := _map_point(_axial_point(current_coord))
	draw_circle(current, 8.0, Color("071b25"))
	draw_circle(current, 5.2, Color("f4c56a"))
	if selected_coord.x > -90000:
		var selected := _map_point(_axial_point(selected_coord))
		draw_arc(selected, 8.0, 0.0, TAU, 20, Color("edfff8"), 1.7, true)
	var legend_y := size.y - 9.0
	draw_string(font, Vector2(12.0, legend_y), "● 부대", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color("f4c56a"))
	draw_string(font, Vector2(size.x * 0.46, legend_y), "━ 일반", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color("5fe5c8"))
	draw_string(font, Vector2(size.x * 0.75, legend_y), "━ 위험", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color("d38cff"))

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("071925e8")
	style.border_color = Color("315a69")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style
