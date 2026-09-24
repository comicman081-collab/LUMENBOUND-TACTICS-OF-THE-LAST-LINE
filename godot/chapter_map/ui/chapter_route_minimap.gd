class_name ChapterRouteMinimap
extends Control

signal expand_requested
const Hex := preload("res://chapter_map/model/hex_coord.gd")
const UNKNOWN := Color("08131d")
const TERRAIN_COLORS := {
	"FOREST": Color("416858"), "ROAD": Color("b5aa7a"), "RUINS": Color("797f84"),
	"SHALLOW_WATER": Color("32677b"), "DEEP_WATER": Color("224454"),
	"BRIDGE": Color("c5a371"), "MOUNTAIN": Color("59656c"), "CLIFF": Color("59656c"),
}
const SQUAD_COLOR := Color("fff0a1")
const TREASURE_COLOR := Color("f0a640")
const ENEMY_COLOR := Color("ef6f6e")
const RELAY_COLOR := Color("6be9d1")
const LANDMARK_COLOR := Color("c9b5dd")
var full_map := false
var tiles: Dictionary = {}
var explored: Dictionary = {}
var markers: Array[Dictionary] = []
var current_coord := Vector2i.ZERO
var selected_coord := Vector2i(-99999, -99999)
var bounds_min := Vector2.ZERO
var bounds_max := Vector2.ONE
var map_signature := ""
var survey_signature := ""
var last_tap_msec := -1000
var terrain_count := 0
var ui_scale := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "더블클릭 / 두 번 탭: 전체 지도"

func configure(definition: Dictionary, state: Dictionary, selected: Dictionary, _hard_visible: bool, vision_radius := 8) -> void:
	var next_map := "%s:%d" % [str(definition.get("map_id", "")), definition.get("tiles", []).size()]
	if next_map != map_signature:
		map_signature = next_map
		survey_signature = ""
		tiles.clear()
		for tile in definition.get("tiles", []):
			tiles[Hex.key(Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0))))] = tile
	current_coord = Vector2i(int(state.get("current_q", 0)), int(state.get("current_r", 0)))
	selected_coord = Vector2i(int(selected.get("q", -99999)), int(selected.get("r", -99999)))
	var next_survey := "%d:%d:%s:%d" % [hash(state.get("visited_tiles", [])), hash(state.get("discovered_tiles", [])), Hex.key(current_coord), vision_radius]
	if next_survey != survey_signature:
		survey_signature = next_survey
		explored.clear()
		# revealed_tiles includes future unlocked corridors. It is routing
		# authority, not evidence that the player has explored those places.
		for key in state.get("discovered_tiles", []):
			if tiles.has(str(key)): explored[str(key)] = true
		var visited: Array = state.get("visited_tiles", []).duplicate()
		visited.append(Hex.key(current_coord))
		for key in visited:
			var center := Hex.from_key(str(key))
			for dq in range(-vision_radius, vision_radius + 1):
				for dr in range(maxi(-vision_radius, -dq - vision_radius), mini(vision_radius, -dq + vision_radius) + 1):
					var visible_key := Hex.key(center + Vector2i(dq, dr))
					if tiles.has(visible_key): explored[visible_key] = true
	markers.clear()
	for relay in definition.get("relays", []):
		_add_marker(relay, RELAY_COLOR, "relay")
	for landmark in definition.get("landmarks", []):
		if str(landmark.get("kind", "")) == "MAJOR": _add_marker(landmark, LANDMARK_COLOR, "landmark")
	for treasure in definition.get("treasures", []):
		if str(state.get("treasure_states", {}).get(str(treasure.get("treasure_id", "")), "UNDISCOVERED")) == "REVEALED":
			_add_marker(treasure, TREASURE_COLOR, "treasure")
	for node in definition.get("nodes", []):
		var node_id := str(node.get("node_id", ""))
		var stage_id := str(node.get("stage_id", ""))
		if stage_id.is_empty() or state.get("cleared_encounters", []).has(node_id): continue
		if str(state.get("encounter_states", {}).get(node_id, "")) == "CLEARED": continue
		# Locked-stage pawns are hidden on the map, so they are hidden here too.
		if not AppState.is_stage_unlocked(stage_id): continue
		var patrol: Dictionary = state.get("patrol_states", {}).get(node_id, {})
		var live := Vector2i(int(patrol.get("q", node.get("q", 0))), int(patrol.get("r", node.get("r", 0))))
		if Hex.distance(current_coord, live) <= vision_radius:
			_add_marker({"q": live.x, "r": live.y}, ENEMY_COLOR, "enemy")
	_recalculate_bounds()
	queue_redraw()

func _add_marker(item: Dictionary, color: Color, kind: String) -> void:
	var coord := Vector2i(int(item.get("q", 0)), int(item.get("r", 0)))
	if explored.has(Hex.key(coord)):
		markers.append({"coord": coord, "color": color, "kind": kind})

func _point(coord: Vector2i) -> Vector2:
	var world := Hex.axial_to_world(coord)
	return Vector2(world.x, world.z)

func _recalculate_bounds() -> void:
	var center := _point(current_coord)
	bounds_min = center - Vector2(17, 12)
	bounds_max = center + Vector2(17, 12)
	if full_map:
		for key in explored:
			var point := _point(Hex.from_key(str(key)))
			bounds_min = bounds_min.min(point - Vector2(3, 3))
			bounds_max = bounds_max.max(point + Vector2(3, 3))

func _map_scale() -> float:
	var span := bounds_max - bounds_min
	return maxf(0.001, minf((size.x - 28.0 * ui_scale) / span.x, (size.y - 60.0 * ui_scale) / span.y))

func _map_point(point: Vector2) -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.5) + (point - (bounds_min + bounds_max) * 0.5) * _map_scale()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.double_click and not full_map: expand_requested.emit()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		var now := Time.get_ticks_msec()
		if now - last_tap_msec < 380 and not full_map:
			expand_requested.emit()
			last_tap_msec = -1000
		else:
			last_tap_msec = now
		accept_event()

func exploration_snapshot() -> Dictionary:
	var records: Array = []
	for marker in markers: records.append({"coord": Hex.key(marker.coord), "kind": marker.kind})
	return {"full_map": full_map, "explored_tiles": explored.keys(), "markers": records, "drawn_tiles": terrain_count, "total_tiles": tiles.size()}

func _draw() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = UNKNOWN
	style.border_color = Color("48717e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	draw_style_box(style, Rect2(Vector2.ZERO, size))
	var scale := _map_scale()
	var terrain_rect := Rect2(Vector2(10, 26) * ui_scale, size - Vector2(20, 54) * ui_scale)
	terrain_count = 0
	for key in explored:
		var tile: Dictionary = tiles[key]
		var point := _map_point(_point(Hex.from_key(str(key))))
		if not terrain_rect.grow(-scale).has_point(point): continue
		var corners := PackedVector2Array()
		for index in range(6):
			var angle := PI / 3.0 * index - PI / 6.0
			corners.append(point + Vector2(cos(angle), sin(angle)) * (scale + 0.35))
		var color: Color = TERRAIN_COLORS.get(str(tile.get("terrain_type", "FOREST")), Color("536b5e"))
		color = color.lightened(clampf(float(tile.get("elevation", 0)) * 0.018, 0.0, 0.12))
		# Most of each region is impassable forest; darken it so the walkable
		# corridors read as the route at a glance.
		if bool(tile.get("movement_blocked", false)):
			color = color.darkened(0.45)
		draw_colored_polygon(corners, color)
		terrain_count += 1
	var marker_outer := 6.5 if full_map else 4.4
	var marker_inner := 4.8 if full_map else 3.2
	for marker in markers:
		var point := _map_point(_point(marker.coord))
		if not terrain_rect.grow(-6).has_point(point): continue
		draw_circle(point, marker_outer, UNKNOWN)
		draw_circle(point, marker_inner, marker.color)
	var current := _map_point(_point(current_coord))
	draw_circle(current, 9 if full_map else 7, UNKNOWN)
	draw_circle(current, 6 if full_map else 4.5, SQUAD_COLOR)
	draw_arc(current, 10 if full_map else 8, -PI * 0.75, PI * 0.25, 16, Color("fff8cf"), 1.5, true)
	if explored.has(Hex.key(selected_coord)):
		var selected := _map_point(_point(selected_coord))
		if terrain_rect.grow(-8).has_point(selected): draw_arc(selected, 7, 0, TAU, 20, Color.WHITE, 1.4, true)
	var font := get_theme_default_font()
	draw_string(font, Vector2(12, 18) * ui_scale, "전체 지도 · 탐색한 지역" if full_map else "미니맵", HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, roundi((15 if full_map else 12) * ui_scale), Color("d5eee9"))
	if not full_map:
		draw_string(font, Vector2(12 * ui_scale, size.y - 10 * ui_scale), "더블클릭 · 전체 지도", HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, roundi(11 * ui_scale), Color("d7d8c2"))
		return
	# Each legend entry uses the exact marker colour drawn on the map.
	var font_size := roundi(14 * ui_scale)
	var baseline := size.y - 12 * ui_scale
	var x := 14.0 * ui_scale
	for entry in [[SQUAD_COLOR, "부대"], [TREASURE_COLOR, "보물"], [ENEMY_COLOR, "적"], [RELAY_COLOR, "중계기"], [LANDMARK_COLOR, "명소"]]:
		var dot := Vector2(x + 6 * ui_scale, baseline - font_size * 0.35)
		draw_circle(dot, 6.5 * ui_scale, UNKNOWN)
		draw_circle(dot, 4.8 * ui_scale, entry[0])
		x += 16 * ui_scale
		draw_string(font, Vector2(x, baseline), str(entry[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("e6e4cf"))
		x += font.get_string_size(str(entry[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 18 * ui_scale
	draw_string(font, Vector2(x + 6 * ui_scale, baseline), "어두운 칸: 지나갈 수 없는 지형", HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, size.x - x - 20 * ui_scale), font_size, Color("aab3a8"))
