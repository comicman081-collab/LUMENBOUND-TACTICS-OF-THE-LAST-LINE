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
	# Every ordinary stage pawn is a live map enemy.  The old source carried only
	# five legacy patrol records, leaving NODE_N02 and most later encounters fixed
	# in place with no explanation.  Build a short legal local route around every
	# normal/elite stage while keeping bosses and authored special-event contacts
	# stationary story anchors.
	expanded["patrols"] = _complete_mobile_patrols(expanded, expanded["tiles"])
	expanded["macro_generated"] = true
	return expanded

static func _complete_mobile_patrols(definition: Dictionary, tiles: Array) -> Array:
	var tile_lookup: Dictionary = {}
	for tile_value in tiles:
		var tile: Dictionary = tile_value
		var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		tile_lookup[HexCoordScript.key(coord)] = tile
	var fixed_event_nodes: Dictionary = {}
	for event_value in definition.get("event_encounters", []):
		var event: Dictionary = event_value
		fixed_event_nodes[str(event.get("node_id", ""))] = true
	var patrols: Array = []
	for node_value in definition.get("nodes", []):
		var node: Dictionary = node_value
		var encounter_id := str(node.get("node_id", ""))
		var stage_id := str(node.get("stage_id", ""))
		var node_type := str(node.get("node_type", ""))
		if encounter_id.is_empty() or stage_id.is_empty():
			continue
		if node_type.contains("BOSS") or fixed_event_nodes.has(encounter_id):
			continue
		var origin := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
		if not _patrol_tile_is_walkable(tile_lookup, origin):
			continue
		var route: Array = [{"q": origin.x, "r": origin.y}]
		var direction_offset: int = absi(origin.x * 13 + origin.y * 7) % HexCoordScript.DIRECTIONS.size()
		var first_step := origin
		for offset in range(HexCoordScript.DIRECTIONS.size()):
			var candidate: Vector2i = origin + HexCoordScript.DIRECTIONS[(direction_offset + offset) % HexCoordScript.DIRECTIONS.size()]
			if _patrol_can_step(tile_lookup, origin, candidate):
				first_step = candidate
				route.append({"q": candidate.x, "r": candidate.y})
				break
		if first_step != origin:
			for offset in range(1, HexCoordScript.DIRECTIONS.size() + 1):
				var candidate: Vector2i = first_step + HexCoordScript.DIRECTIONS[(direction_offset + offset) % HexCoordScript.DIRECTIONS.size()]
				if candidate == origin or HexCoordScript.distance(origin, candidate) > 2:
					continue
				if _patrol_can_step(tile_lookup, first_step, candidate):
					route.append({"q": candidate.x, "r": candidate.y})
					break
		patrols.append({
			"encounter_id": encounter_id,
			"patrol_enabled": route.size() > 1,
			"patrol_mode": "PING_PONG",
			"patrol_route_hexes": route,
			"patrol_speed_ticks": 1,
			"wait_time_ticks": 0,
			"awareness_radius": 4 if node_type.contains("ELITE") else 3,
			"alert_radius": 1,
			"high_ground_bonus": 1,
			"engagement_radius": 0,
			"return_hex": {"q": origin.x, "r": origin.y},
			"leash_radius": 4,
		})
	return patrols

static func _patrol_tile_is_walkable(tile_lookup: Dictionary, coord: Vector2i) -> bool:
	var tile: Dictionary = tile_lookup.get(HexCoordScript.key(coord), {})
	return not tile.is_empty() and not bool(tile.get("movement_blocked", false))

static func _patrol_can_step(tile_lookup: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	if HexCoordScript.distance(from, to) != 1 or not _patrol_tile_is_walkable(tile_lookup, from) or not _patrol_tile_is_walkable(tile_lookup, to):
		return false
	var from_tile: Dictionary = tile_lookup.get(HexCoordScript.key(from), {})
	var to_tile: Dictionary = tile_lookup.get(HexCoordScript.key(to), {})
	return absi(int(from_tile.get("elevation", 0)) - int(to_tile.get("elevation", 0))) <= 1

static func generate_tiles(definition: Dictionary, macro: Dictionary) -> Array:
	var seed := int(macro.get("seed", 7011801))
	var corridor_radius := maxi(2, int(macro.get("corridor_radius", 4)))
	var routes: Array[Array] = _route_segments(definition)
	var road: Dictionary = {}
	var walkable: Dictionary = {}
	var patrol_corridor: Dictionary = {}
	var land: Dictionary = {}
	for route in routes:
		for coord in route:
			road[HexCoordScript.key(coord)] = true
			_mark_disc(land, coord, corridor_radius)
			# The road is the expedition backbone, not permission to cross every
			# forest hex rendered around it.  A one-ring shoulder keeps local route
			# choices while dense forest and cliff terraces remain real barriers.
			_mark_disc(walkable, coord, 1)
	# Encounter areas are deliberately wider than the travel corridor, producing
	# real local exploration spaces while retaining the same stage count.  Only a
	# compact arena around the encounter is traversable; the full seven-ring land
	# disc is presentation terrain and must never become one giant yellow grid.
	for node in definition.get("nodes", []):
		var node_coord := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
		_mark_disc(land, node_coord, corridor_radius + 3)
		_mark_disc(walkable, node_coord, 2)
	var start_value: Dictionary = definition.get("start_hex", {"q": 0, "r": 0})
	_mark_disc(walkable, Vector2i(int(start_value.get("q", 0)), int(start_value.get("r", 0))), 2)
	# Treasure, relay, event and authored patrol side branches are explicit
	# gameplay promises.  Connect each one to the road with a narrow legal trail
	# instead of making the entire decorative landmass traversable.
	var road_coords: Array[Vector2i] = []
	var road_keys: Array = road.keys()
	road_keys.sort()
	for road_key in road_keys:
		road_coords.append(HexCoordScript.from_key(str(road_key)))
	for target_coord in _navigation_targets(definition):
		_connect_navigation_target(land, walkable, road_coords, target_coord, corridor_radius)
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
		var is_walkable := walkable.has(str(key))
		var is_mobility_corridor := is_walkable or patrol_corridor.has(str(key))
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
			# Decorative forest/ruin terraces outside the authored expedition
			# lanes are physical barriers. Enemy-occupied cells are not special-
			# cased here: every patrol route is connected above, so reaching a mob
			# remains a legal terminal step without opening unrelated terrain.
			"movement_blocked": not is_walkable,
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

static func _navigation_targets(definition: Dictionary) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	for collection_name in ["treasures", "relays", "map_events"]:
		for value in definition.get(collection_name, []):
			var target: Dictionary = value
			targets.append(Vector2i(int(target.get("q", 0)), int(target.get("r", 0))))
	for patrol_value in definition.get("patrols", []):
		var patrol: Dictionary = patrol_value
		for point_value in patrol.get("patrol_route_hexes", []):
			var point: Dictionary = point_value
			targets.append(Vector2i(int(point.get("q", 0)), int(point.get("r", 0))))
	return targets

static func _connect_navigation_target(land: Dictionary, walkable: Dictionary, road_coords: Array[Vector2i], target: Vector2i, corridor_radius: int) -> void:
	if road_coords.is_empty():
		_mark_disc(land, target, maxi(2, corridor_radius - 1))
		_mark_disc(walkable, target, 1)
		return
	var nearest := road_coords[0]
	var nearest_distance := HexCoordScript.distance(target, nearest)
	for candidate in road_coords:
		var candidate_distance := HexCoordScript.distance(target, candidate)
		if candidate_distance < nearest_distance or (candidate_distance == nearest_distance and (candidate.x < nearest.x or (candidate.x == nearest.x and candidate.y < nearest.y))):
			nearest = candidate
			nearest_distance = candidate_distance
	for coord in route_line(target, nearest):
		_mark_disc(land, coord, maxi(2, corridor_radius - 1))
		_mark_disc(walkable, coord, 1)

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
