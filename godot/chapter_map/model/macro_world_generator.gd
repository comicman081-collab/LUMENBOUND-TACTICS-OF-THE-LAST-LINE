class_name MacroWorldGenerator
extends RefCounted

## Deterministic macro-map expansion for ChapterMapScreen.
##
## Only the authored encounter nodes and world-generation contract live in the
## source JSON.  The terrain corridor is generated from that immutable seed at
## load time, so a chapter can be more than ten viewport lengths long without
## checking thousands of copied terrain rows into the content source.

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")

static func expand(definition: Dictionary) -> Dictionary:
	var macro: Dictionary = definition.get("macro_world", {})
	if macro.is_empty():
		return definition
	var expanded := definition.duplicate(true)
	expanded["tiles"] = generate_tiles(expanded, macro)
	expanded["macro_generated"] = true
	return expanded

static func generate_tiles(definition: Dictionary, macro: Dictionary) -> Array:
	var seed := int(macro.get("seed", 7011801))
	var corridor_radius := maxi(2, int(macro.get("corridor_radius", 4)))
	var routes: Array[Array] = _route_segments(definition)
	var road: Dictionary = {}
	var patrol_corridor: Dictionary = {}
	var land: Dictionary = {}
	for route in routes:
		for coord in route:
			road[HexCoordScript.key(coord)] = true
			_mark_disc(land, coord, corridor_radius)
	# Encounter areas are deliberately wider than the travel corridor, producing
	# real local exploration spaces while retaining the same stage count.
	for node in definition.get("nodes", []):
		_mark_disc(land, Vector2i(int(node.get("q", 0)), int(node.get("r", 0))), corridor_radius + 3)
	for patrol in definition.get("patrols", []):
		for patrol_hex in patrol.get("patrol_route_hexes", []):
			var patrol_coord := Vector2i(int(patrol_hex.get("q", 0)), int(patrol_hex.get("r", 0)))
			patrol_corridor[HexCoordScript.key(patrol_coord)] = true
	var rows: Array = []
	var keys: Array = land.keys()
	# The key string is stable ("q,r"), and Godot's built-in sort avoids a
	# costly GDScript comparator for the large macro map at every cold start.
	# Tile order is not gameplay state; key-sorted output remains deterministic.
	keys.sort()
	for key in keys:
		var coord := HexCoordScript.from_key(str(key))
		var is_road := road.has(str(key))
		var is_mobility_corridor := is_road or patrol_corridor.has(str(key))
		var value := _coord_hash(coord, seed)
		var terrain := "ROAD" if is_road else ("RUINS" if value % 17 == 0 else "FOREST")
		# Elevation is visual-only in the chapter traversal layer, but it must
		# form broad, legible terraces—not isolated dice-roll columns.  The two
		# low-frequency waves create plateau-sized bands while the seeded hash only
		# chooses small ridge accents.  Road and patrol corridors remain 0/1 so the
		# authored movement graph and live patrol routes retain legal step topology.
		var elevation := _terrain_elevation(coord, seed, is_mobility_corridor, value)
		rows.append({
			"q": coord.x, "r": coord.y,
			"elevation": elevation,
			"terrain_type": terrain,
			"movement_blocked": false,
			"movement_cost": 1,
			# Nine stable variants deliberately prevent the forest and route from
			# reading as one repeated prop per hex in a streamed neighbourhood.
			"visual_variant": value % 9,
			"rotation_step": int(value / 9) % 6,
			"prop_set": "MACRO_%s" % terrain,
			"fog_initial": true,
		})
	# Keep a handful of explicit blocked tide entries outside the travelable
	# corridor.  These give pathing, fog and validation an unambiguous water
	# boundary while the runtime renders one continuous ocean instead of water
	# hexes.
	var bounds: Dictionary = macro.get("bounds", {})
	var min_q := int(bounds.get("min_q", -12))
	var max_q := int(bounds.get("max_q", 112))
	var min_r := int(bounds.get("min_r", -28))
	var max_r := int(bounds.get("max_r", 20))
	for coord in [Vector2i(min_q, min_r), Vector2i(max_q, min_r), Vector2i(min_q, max_r), Vector2i(max_q, max_r)]:
		rows.append({
			"q": coord.x, "r": coord.y, "elevation": 0,
			"terrain_type": "DEEP_WATER", "movement_blocked": true,
			"movement_cost": 1, "visual_variant": 0, "rotation_step": 0,
			"prop_set": "TIDE_BOUNDARY", "fog_initial": true,
		})
	return rows

static func _terrain_elevation(coord: Vector2i, seed: int, is_road: bool, hash_value: int) -> int:
	if is_road:
		return 1 if hash_value % 23 in [0, 1, 2] else 0
	var phase := float(seed % 97) * 0.037
	var terrace_wave := sin(float(coord.x) * 0.32 + float(coord.y) * 0.18 + phase)
	var ridge_wave := sin(float(coord.x) * 0.11 - float(coord.y) * 0.39 - phase * 0.73)
	var relief := terrace_wave * 0.72 + ridge_wave * 0.48
	var elevation := 0
	if relief > 0.76:
		elevation = 3
	elif relief > 0.24:
		elevation = 2
	elif relief > -0.42:
		elevation = 1
	# Keep a few deterministic local breaks so broad contours retain a faceted,
	# hand-authored character without turning back into random one-cell pillars.
	if elevation > 0 and hash_value % 17 == 0:
		elevation -= 1
	return elevation

static func route_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [from]
	var current := from
	while current != to:
		var candidates := HexCoordScript.neighbors(current)
		candidates.sort_custom(func(left, right):
			var left_distance := HexCoordScript.distance(left, to)
			var right_distance := HexCoordScript.distance(right, to)
			return left_distance < right_distance or (left_distance == right_distance and (left.x < right.x or (left.x == right.x and left.y < right.y)))
		)
		current = candidates[0]
		path.append(current)
	return path

static func route_to_stage(definition: Dictionary, stage_id: String) -> Array[Vector2i]:
	var route_ids: Array = definition.get("hard_route", []) if stage_id.contains("-H") else definition.get("normal_route", [])
	var previous: Dictionary = {"q": int(definition.get("start_hex", {}).get("q", 0)), "r": int(definition.get("start_hex", {}).get("r", 0))}
	if stage_id.contains("-H"):
		var normal_route: Array = definition.get("normal_route", [])
		if not normal_route.is_empty():
			previous = _node_for_stage(definition, str(normal_route.back()))
	for candidate_id in route_ids:
		var node := _node_for_stage(definition, str(candidate_id))
		if node.is_empty(): continue
		if str(candidate_id) == stage_id:
			return route_line(Vector2i(int(previous.q), int(previous.r)), Vector2i(int(node.q), int(node.r)))
		previous = node
	return []

static func _route_segments(definition: Dictionary) -> Array[Array]:
	var segments: Array[Array] = []
	var previous := {"q": int(definition.get("start_hex", {}).get("q", 0)), "r": int(definition.get("start_hex", {}).get("r", 0))}
	for stage_id in definition.get("normal_route", []):
		var node := _node_for_stage(definition, str(stage_id))
		if node.is_empty(): continue
		segments.append(route_line(Vector2i(int(previous.q), int(previous.r)), Vector2i(int(node.q), int(node.r))))
		previous = node
	var normal_route: Array = definition.get("normal_route", [])
	if not normal_route.is_empty():
		previous = _node_for_stage(definition, str(normal_route.back()))
	for stage_id in definition.get("hard_route", []):
		var hard_node := _node_for_stage(definition, str(stage_id))
		if hard_node.is_empty(): continue
		segments.append(route_line(Vector2i(int(previous.q), int(previous.r)), Vector2i(int(hard_node.q), int(hard_node.r))))
		previous = hard_node
	return segments

static func _node_for_stage(definition: Dictionary, stage_id: String) -> Dictionary:
	for node in definition.get("nodes", []):
		if str(node.get("stage_id", "")) == stage_id:
			return node
	return {}

static func _mark_disc(target: Dictionary, center: Vector2i, radius: int) -> void:
	for dq in range(-radius, radius + 1):
		for dr in range(-radius, radius + 1):
			var coord := center + Vector2i(dq, dr)
			if HexCoordScript.distance(center, coord) <= radius:
				target[HexCoordScript.key(coord)] = true

static func _coord_hash(coord: Vector2i, seed: int) -> int:
	var value := int(seed) ^ int(coord.x * 73856093) ^ int(coord.y * 19349663)
	value = (value ^ (value >> 13)) * 1274126177
	return abs(value ^ (value >> 16))
