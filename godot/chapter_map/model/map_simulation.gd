class_name MapSimulation
extends RefCounted

## Deterministic logical simulation for the Chapter Map.  Rendering and tween
## animation never feed back into this state: a saved tick, patrol route and
## player coordinate always produce the same next state.

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const HexGridScript := preload("res://chapter_map/model/hex_grid.gd")
const HexPathfinderScript := preload("res://chapter_map/model/hex_pathfinder.gd")

const TICK_SECONDS := 0.25
const PATROL_IDLE := "IDLE"
const PATROL_MOVING := "PATROL"
const PATROL_WAIT := "WAIT"
const PATROL_ALERT := "ALERT"
const PATROL_CHASE := "CHASE_SHORT"
const PATROL_RETURN := "RETURN"
const PATROL_ENGAGED := "ENGAGED"
const PATROL_CLEARED := "CLEARED"

const UNAWARE := "UNAWARE"
const SUSPICIOUS := "SUSPICIOUS"
const ALERT := "ALERT"

static func ensure_state(state: Dictionary, definition: Dictionary, grid = null) -> bool:
	var changed := false
	if not state.has("map_simulation_state"):
		state.map_simulation_state = {"tick": 0, "seed": int(definition.get("map_simulation", {}).get("seed", 140701)), "paused": false}
		changed = true
	if not state.has("patrol_states"):
		state.patrol_states = {}
		changed = true
	if not state.has("patrol_positions"):
		state.patrol_positions = {}
		changed = true
	# Save migration and AppState restoration can initialize map state before a
	# runtime HexGrid exists.  Build a tiny data-only grid in that case so the
	# authoritative repair rejects both route-invalid and non-walkable hexes.
	var validation_grid = grid
	if validation_grid == null:
		validation_grid = HexGridScript.new()
		validation_grid.load_tiles(definition.get("tiles", []))
	# The party coordinate is saved separately from the immutable selected-node ID.
	# Older compact-map saves can therefore carry a syntactically valid q/r pair
	# that is outside the expanded macro terrain. Repair that *authoritative map
	# state* before any Node3D is created; a view-side clamp would leave the next
	# refresh or battle return stranded over ocean again.
	var party_coord := Vector2i(int(state.get("current_q", 0)), int(state.get("current_r", 0)))
	# A coordinate being mathematically inside the terrain is not sufficient for
	# a saved party position.  Older saves could keep a valid macro-map hex that
	# was never actually traversed or revealed; rendering the pawn there places it
	# above an ocean/gap even though the hex grid accepts it.  Treat the visited +
	# revealed route history as the authoritative ownership proof for the squad.
	if not _party_coordinate_is_authoritative(state, party_coord, validation_grid, definition):
		var party_anchor := _party_repair_anchor(state, definition, validation_grid)
		state.current_q = party_anchor.x
		state.current_r = party_anchor.y
		state.current_party_hex = [party_anchor.x, party_anchor.y]
		state.last_map_camera_hex = [party_anchor.x, party_anchor.y]
		var party_key := HexCoordScript.key(party_anchor)
		if not state.has("visited_tiles"):
			state.visited_tiles = []
			changed = true
		if not state.visited_tiles.has(party_key):
			state.visited_tiles.append(party_key)
		if not state.has("revealed_tiles"):
			state.revealed_tiles = []
			changed = true
		if not state.revealed_tiles.has(party_key):
			# This repairs only the saved party/checkpoint itself.  Route expansion
			# remains owned by the normal progression reveal rules.
			state.revealed_tiles.append(party_key)
		changed = true
	else:
		# current_party_hex is a compatibility cache. Keep it synchronized without
		# changing a valid logical party coordinate.
		var party_cache: Array = state.get("current_party_hex", [])
		if party_cache.size() != 2 or int(party_cache[0]) != party_coord.x or int(party_cache[1]) != party_coord.y:
			state.current_party_hex = [party_coord.x, party_coord.y]
			changed = true
	var patrols: Array = definition.get("patrols", []).duplicate(true)
	patrols.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("encounter_id", "")) < str(right.get("encounter_id", ""))
	)
	var occupied: Dictionary = {}
	for patrol in patrols:
		var encounter_id := str(patrol.get("encounter_id", ""))
		if encounter_id.is_empty():
			continue
		var route: Array = patrol.get("patrol_route_hexes", [])
		var origin: Dictionary = route[0] if not route.is_empty() else patrol.get("return_hex", {"q": 0, "r": 0})
		if not state.patrol_states.has(encounter_id):
			state.patrol_states[encounter_id] = _default_runtime(origin)
			changed = true
		var saved: Dictionary = state.patrol_states[encounter_id].duplicate(true)
		var lifecycle_cleared: bool = str(state.get("encounter_states", {}).get(encounter_id, "")) == PATROL_CLEARED or state.get("cleared_encounters", []).has(encounter_id)
		if lifecycle_cleared:
			# A cleared encounter must remain cleared; save repair never revives it
			# or changes progression lifecycle state.
			if str(saved.get("patrol_state", "")) != PATROL_CLEARED:
				saved.patrol_state = PATROL_CLEARED
				changed = true
			state.patrol_states[encounter_id] = saved
			continue
		# Old saves from before patrol runtime state existed could retain a default
		# (0, 0) coordinate.  That is a valid axial coordinate syntactically, but
		# not a valid coordinate for this encounter and can render its pawn over
		# the ocean.  Repair from authored patrol data before any view consumes it.
		if not _runtime_coord_is_valid(saved, patrol, origin, validation_grid):
			saved = _default_runtime(origin)
			changed = true
		else:
			var normalized := _canonicalize_runtime(saved, patrol, origin)
			# Dictionary equality is semantic here; JSON key order after a save/load
			# must not turn an already canonical patrol into a repeat repair.
			if normalized != saved:
				saved = normalized
				changed = true
		var coord := Vector2i(int(saved.get("q", origin.get("q", 0))), int(saved.get("r", origin.get("r", 0))))
		var coord_key := HexCoordScript.key(coord)
		if occupied.has(coord_key):
			var alternate := _first_unoccupied_patrol_coord(patrol, origin, validation_grid, occupied)
			if alternate != Vector2i(-999999, -999999):
				saved = _default_runtime({"q": alternate.x, "r": alternate.y})
				coord = alternate
				coord_key = HexCoordScript.key(coord)
				changed = true
		occupied[coord_key] = encounter_id
		state.patrol_states[encounter_id] = saved
		# patrol_positions is a cached compatibility field.  Always synchronize it
		# from the repaired runtime state instead of preserving stale save data.
		var desired_position := [int(saved.get("q", origin.get("q", 0))), int(saved.get("r", origin.get("r", 0)))]
		var cached_position: Array = state.patrol_positions.get(encounter_id, [])
		var cached_matches := cached_position.size() == 2 and int(cached_position[0]) == int(desired_position[0]) and int(cached_position[1]) == int(desired_position[1])
		if not cached_matches:
			state.patrol_positions[encounter_id] = desired_position
			changed = true
	return changed

static func _party_coordinate_is_authoritative(state: Dictionary, coord: Vector2i, grid, definition: Dictionary) -> bool:
	if not grid.traversable(coord):
		return false
	var key := HexCoordScript.key(coord)
	var visited: Array = state.get("visited_tiles", [])
	if visited.has(key):
		return true
	# Sequential save migrations predate visited-tile history.  A cleared authored
	# checkpoint is still a trustworthy location, but an arbitrary map coordinate
	# is not.  This keeps legacy N06/N10 restores intact without permitting a
	# random traversable ocean-side macro hex to become the party location.
	var cleared: Array = state.get("cleared_nodes", [])
	for node in definition.get("nodes", []):
		if not cleared.has(str(node.get("node_id", ""))):
			continue
		if int(node.get("q", 0)) == coord.x and int(node.get("r", 0)) == coord.y:
			return true
	return false

static func _party_repair_anchor(state: Dictionary, definition: Dictionary, grid) -> Vector2i:
	# Prefer the last confirmed traversal.  This makes an imported coordinate
	# repair deterministic without trusting a stale selected-node UI cache.
	var visited: Array = state.get("visited_tiles", [])
	for index in range(visited.size() - 1, -1, -1):
		var visited_coord := HexCoordScript.from_key(str(visited[index]))
		if grid.traversable(visited_coord):
			return visited_coord
	# A legacy payload may lack last_selected_node but still retain cleared stage
	# IDs. Definition order is stable, so the final matching node is deterministic.
	var cleared: Array = state.get("cleared_nodes", [])
	var cleared_anchor := Vector2i(999999, 999999)
	for node in definition.get("nodes", []):
		if not cleared.has(str(node.get("node_id", ""))):
			continue
		var cleared_coord := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
		if grid.traversable(cleared_coord):
			cleared_anchor = cleared_coord
	if cleared_anchor != Vector2i(999999, 999999):
		return cleared_anchor
	# A selected node remains a safe migration anchor only when it already belongs
	# to known map state.  It must not resurrect an unvisited macro-map coordinate.
	var last_selected := str(state.get("last_selected_node", ""))
	if not last_selected.is_empty():
		for node in definition.get("nodes", []):
			if str(node.get("node_id", "")) != last_selected:
				continue
			var selected_coord := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
			if grid.traversable(selected_coord) and (cleared.has(last_selected) or state.get("revealed_tiles", []).has(HexCoordScript.key(selected_coord))):
				return selected_coord
	var start: Dictionary = definition.get("start_hex", {"q": 0, "r": 0})
	var start_coord := Vector2i(int(start.get("q", 0)), int(start.get("r", 0)))
	if grid.traversable(start_coord):
		return start_coord
	# Definition validation guarantees a traversable start, but keep a safe
	# deterministic fallback for malformed future content rather than returning
	# a coordinate that can create a void pawn.
	var keys: Array = grid.tiles.keys()
	keys.sort()
	return HexCoordScript.from_key(str(keys[0])) if not keys.is_empty() else Vector2i.ZERO

static func _default_runtime(origin: Dictionary) -> Dictionary:
	return {
		"current_patrol_index": 0,
		"direction": 1,
		"wait_remaining": 0,
		"next_move_tick": 0,
		"patrol_state": PATROL_IDLE,
		"awareness": UNAWARE,
		"q": int(origin.get("q", 0)),
		"r": int(origin.get("r", 0)),
	}

static func _runtime_coord_is_valid(runtime: Dictionary, patrol: Dictionary, origin: Dictionary, grid = null) -> bool:
	if not runtime.has("q") or not runtime.has("r"):
		return false
	var coord := Vector2i(int(runtime.get("q", 0)), int(runtime.get("r", 0)))
	if grid != null and not grid.traversable(coord):
		return false
	var mode := str(patrol.get("patrol_mode", "LOOP"))
	if mode == "GUARD_AREA":
		var home: Dictionary = patrol.get("return_hex", origin)
		var home_coord := Vector2i(int(home.get("q", 0)), int(home.get("r", 0)))
		return HexCoordScript.distance(coord, home_coord) <= maxi(1, int(patrol.get("guard_radius", 3)))
	var route: Array = patrol.get("patrol_route_hexes", [])
	if route.is_empty():
		return coord == Vector2i(int(origin.get("q", 0)), int(origin.get("r", 0)))
	for route_hex in route:
		if coord == Vector2i(int(route_hex.get("q", 0)), int(route_hex.get("r", 0))):
			return true
	return false

static func _canonicalize_runtime(runtime: Dictionary, patrol: Dictionary, origin: Dictionary) -> Dictionary:
	var normalized := runtime.duplicate(true)
	var route: Array = patrol.get("patrol_route_hexes", [])
	var coord := Vector2i(int(normalized.get("q", origin.get("q", 0))), int(normalized.get("r", origin.get("r", 0))))
	var route_index := -1
	for index in range(route.size()):
		var route_hex: Dictionary = route[index]
		if coord == Vector2i(int(route_hex.get("q", 0)), int(route_hex.get("r", 0))):
			route_index = index
			break
	if route_index >= 0:
		if int(normalized.get("current_patrol_index", 0)) != route_index:
			normalized.current_patrol_index = route_index
	else:
		var clamped_index := clampi(int(normalized.get("current_patrol_index", 0)), 0, maxi(0, route.size() - 1))
		if int(normalized.get("current_patrol_index", 0)) != clamped_index:
			normalized.current_patrol_index = clamped_index
	var mode := str(patrol.get("patrol_mode", "LOOP"))
	if mode == "LOOP":
		if int(normalized.get("direction", 1)) != 1:
			normalized.direction = 1
	else:
		var direction := int(normalized.get("direction", 1))
		var canonical_direction := -1 if direction == -1 else 1
		if direction != canonical_direction:
			normalized.direction = canonical_direction
	return normalized

static func _first_unoccupied_patrol_coord(patrol: Dictionary, origin: Dictionary, grid, occupied: Dictionary) -> Vector2i:
	var candidates: Array[Dictionary] = [origin]
	for route_hex in patrol.get("patrol_route_hexes", []):
		candidates.append(route_hex)
	for candidate in candidates:
		var coord := Vector2i(int(candidate.get("q", 0)), int(candidate.get("r", 0)))
		if grid.traversable(coord) and not occupied.has(HexCoordScript.key(coord)):
			return coord
	return Vector2i(-999999, -999999)

static func runtime_coordinate_is_valid(state: Dictionary, definition: Dictionary, grid, encounter_id: String) -> bool:
	var patrol := patrol_definition(definition, encounter_id)
	if patrol.is_empty():
		return false
	var route: Array = patrol.get("patrol_route_hexes", [])
	var origin: Dictionary = route[0] if not route.is_empty() else patrol.get("return_hex", {"q": 0, "r": 0})
	var runtime: Dictionary = state.get("patrol_states", {}).get(encounter_id, {})
	return _runtime_coord_is_valid(runtime, patrol, origin, grid)

static func render_coord_or_authored(state: Dictionary, definition: Dictionary, grid, encounter_id: String, authored_coord: Vector2i) -> Vector2i:
	# This is intentionally pure.  MapScreen can protect rendering from a bad
	# simulation payload, but it must never repair or mutate gameplay state.
	return coord_for(state, encounter_id) if runtime_coordinate_is_valid(state, definition, grid, encounter_id) else authored_coord

static func patrol_definition(definition: Dictionary, encounter_id: String) -> Dictionary:
	for patrol in definition.get("patrols", []):
		if str(patrol.get("encounter_id", "")) == encounter_id:
			return patrol
	return {}

static func coord_for(state: Dictionary, encounter_id: String) -> Vector2i:
	var patrol: Dictionary = state.get("patrol_states", {}).get(encounter_id, {})
	return Vector2i(int(patrol.get("q", 0)), int(patrol.get("r", 0)))

static func pursuit_path(state: Dictionary, definition: Dictionary, grid, from_coord: Vector2i, encounter_id: String, allowed: Dictionary = {}) -> Array[Vector2i]:
	# UI route previews must be derived from the same saved patrol coordinate as
	# the map simulation.  This is intentionally pure with respect to patrol time:
	# rendering can request a re-path without advancing logical state.
	ensure_state(state, definition, grid)
	return HexPathfinderScript.find_path(grid, from_coord, coord_for(state, encounter_id), allowed)

static func disengage_after_battle(state: Dictionary, definition: Dictionary, encounter_id: String, party_coord: Vector2i) -> bool:
	## A patrol can enter the stationary squad's hex. Returning both actors to
	## that same hex after defeat would cause the 0.25 s map tick to immediately
	## start the encounter again. Move only the patrol to the nearest available
	## authored route point and suppress contact until the squad leaves its saved
	## return hex. This state is deterministic and survives save/reload.
	var patrol := patrol_definition(definition, encounter_id)
	if patrol.is_empty() or not bool(patrol.get("patrol_enabled", false)):
		return false
	ensure_state(state, definition)
	var runtime: Dictionary = state.get("patrol_states", {}).get(encounter_id, {}).duplicate(true)
	if runtime.is_empty() or str(runtime.get("patrol_state", "")) == PATROL_CLEARED:
		return false
	var current := Vector2i(int(runtime.get("q", party_coord.x)), int(runtime.get("r", party_coord.y)))
	var occupied: Dictionary = {}
	for other_id_value in state.get("patrol_states", {}).keys():
		var other_id := str(other_id_value)
		if other_id == encounter_id:
			continue
		var other: Dictionary = state.patrol_states.get(other_id, {})
		if str(other.get("patrol_state", "")) == PATROL_CLEARED:
			continue
		occupied[HexCoordScript.key(Vector2i(int(other.get("q", 0)), int(other.get("r", 0))))] = true
	var candidates: Array = patrol.get("patrol_route_hexes", []).duplicate(true)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_coord := Vector2i(int(left.get("q", 0)), int(left.get("r", 0)))
		var right_coord := Vector2i(int(right.get("q", 0)), int(right.get("r", 0)))
		var left_distance := HexCoordScript.distance(current, left_coord)
		var right_distance := HexCoordScript.distance(current, right_coord)
		if left_distance != right_distance:
			return left_distance < right_distance
		if left_coord.x != right_coord.x:
			return left_coord.x < right_coord.x
		return left_coord.y < right_coord.y
	)
	var retreat := current
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var coord := Vector2i(int(candidate.get("q", current.x)), int(candidate.get("r", current.y)))
		if coord == party_coord or occupied.has(HexCoordScript.key(coord)):
			continue
		retreat = coord
		break
	runtime.q = retreat.x
	runtime.r = retreat.y
	for index in range(patrol.get("patrol_route_hexes", []).size()):
		var route_hex: Dictionary = patrol.patrol_route_hexes[index]
		if retreat == Vector2i(int(route_hex.get("q", 0)), int(route_hex.get("r", 0))):
			runtime.current_patrol_index = index
			break
	runtime.patrol_state = PATROL_RETURN
	runtime.awareness = UNAWARE
	runtime.wait_remaining = maxi(1, int(patrol.get("wait_time_ticks", 0)))
	runtime.next_move_tick = int(state.get("map_simulation_state", {}).get("tick", 0)) + maxi(2, int(patrol.get("patrol_speed_ticks", 2)))
	runtime.contact_suppressed = true
	runtime.disengage_party_q = party_coord.x
	runtime.disengage_party_r = party_coord.y
	state.patrol_states[encounter_id] = runtime
	state.patrol_positions[encounter_id] = [retreat.x, retreat.y]
	return true

static func advance_ticks(state: Dictionary, definition: Dictionary, grid, party_coord: Vector2i, tick_count := 1) -> Dictionary:
	ensure_state(state, definition, grid)
	var result := {"changed": [], "moves": [], "contacts": [], "awareness": {}}
	if bool(state.get("map_simulation_state", {}).get("paused", false)):
		return result
	for _step in range(maxi(0, tick_count)):
		state.map_simulation_state.tick = int(state.map_simulation_state.get("tick", 0)) + 1
		var tick := int(state.map_simulation_state.tick)
		var contacts: Array[String] = []
		for raw_patrol in definition.get("patrols", []):
			var encounter_id := str(raw_patrol.get("encounter_id", ""))
			if encounter_id.is_empty():
				continue
			var patrol: Dictionary = raw_patrol
			var runtime: Dictionary = state.patrol_states.get(encounter_id, {}).duplicate(true)
			if runtime.is_empty():
				continue
			if str(state.get("encounter_states", {}).get(encounter_id, "")) == PATROL_CLEARED:
				runtime.patrol_state = PATROL_CLEARED
				state.patrol_states[encounter_id] = runtime
				continue
			var previous := Vector2i(int(runtime.get("q", 0)), int(runtime.get("r", 0)))
			if patrol_is_stationary(definition, patrol):
				runtime.awareness = UNAWARE
				runtime.patrol_state = PATROL_IDLE
				state.patrol_states[encounter_id] = runtime
				state.patrol_positions[encounter_id] = [previous.x, previous.y]
				result.awareness[encounter_id] = UNAWARE
				continue
			var contact_suppressed := bool(runtime.get("contact_suppressed", false))
			if contact_suppressed:
				var disengage_party := Vector2i(int(runtime.get("disengage_party_q", party_coord.x)), int(runtime.get("disengage_party_r", party_coord.y)))
				if party_coord != disengage_party:
					runtime.contact_suppressed = false
					runtime.erase("disengage_party_q")
					runtime.erase("disengage_party_r")
					contact_suppressed = false
			var awareness := UNAWARE if contact_suppressed else awareness_for(patrol, runtime, party_coord, grid, definition)
			runtime.awareness = awareness
			if awareness != UNAWARE:
				runtime.patrol_state = PATROL_ALERT
				runtime = _advance_chase(runtime, patrol, party_coord, grid)
			else:
				# Unaware enemies hold position. Once the party is recognized, every
				# mobile enemy action advances toward the party instead of wandering.
				runtime.patrol_state = PATROL_IDLE
			var current := Vector2i(int(runtime.get("q", 0)), int(runtime.get("r", 0)))
			state.patrol_states[encounter_id] = runtime
			state.patrol_positions[encounter_id] = [current.x, current.y]
			result.awareness[encounter_id] = awareness
			if current != previous:
				result.changed.append(encounter_id)
				result.moves.append({"encounter_id": encounter_id, "from": [previous.x, previous.y], "to": [current.x, current.y]})
			var contact_radius := maxi(0, int(patrol.get("engagement_radius", 0)))
			if not contact_suppressed and HexCoordScript.distance(current, party_coord) <= contact_radius and (awareness == ALERT or current == party_coord):
				contacts.append(encounter_id)
		contacts.sort()
		if not contacts.is_empty():
			result.contacts = contacts
			break
	return result

static func advance_wait(state: Dictionary, definition: Dictionary, grid, party_coord: Vector2i) -> Dictionary:
	var pulses := maxi(1, int(definition.get("map_simulation", {}).get("wait_pulse_ticks", 4)))
	return advance_ticks(state, definition, grid, party_coord, pulses)

static func contacts_at_party_coord(state: Dictionary, definition: Dictionary, grid, party_coord: Vector2i) -> Array[String]:
	## Pure contact query used while the player pawn crosses a hex. Enemy time is
	## advanced only by the single enemy phase after movement has finished.
	var contacts: Array[String] = []
	for patrol_value in definition.get("patrols", []):
		var patrol: Dictionary = patrol_value
		var encounter_id := str(patrol.get("encounter_id", ""))
		if encounter_id.is_empty() or str(state.get("encounter_states", {}).get(encounter_id, "")) == PATROL_CLEARED:
			continue
		var runtime: Dictionary = state.get("patrol_states", {}).get(encounter_id, {})
		if runtime.is_empty() or str(runtime.get("patrol_state", "")) == PATROL_CLEARED:
			continue
		var contact_suppressed := bool(runtime.get("contact_suppressed", false))
		if contact_suppressed:
			var disengage_party := Vector2i(int(runtime.get("disengage_party_q", party_coord.x)), int(runtime.get("disengage_party_r", party_coord.y)))
			contact_suppressed = party_coord == disengage_party
		if contact_suppressed:
			continue
		var enemy_coord := Vector2i(int(runtime.get("q", 0)), int(runtime.get("r", 0)))
		var awareness := awareness_for(patrol, runtime, party_coord, grid, definition)
		var contact_radius := maxi(0, int(patrol.get("engagement_radius", 0)))
		if HexCoordScript.distance(enemy_coord, party_coord) <= contact_radius and (awareness == ALERT or enemy_coord == party_coord):
			contacts.append(encounter_id)
	contacts.sort()
	return contacts

static func awareness_for(patrol: Dictionary, runtime: Dictionary, party_coord: Vector2i, grid, definition: Dictionary) -> String:
	var enemy_coord := Vector2i(int(runtime.get("q", 0)), int(runtime.get("r", 0)))
	var radius := maxi(10, int(patrol.get("awareness_radius", 10)))
	var alert_radius := maxi(0, int(patrol.get("alert_radius", 1)))
	var enemy_tile: Dictionary = grid.tile(enemy_coord)
	var party_tile: Dictionary = grid.tile(party_coord)
	if int(enemy_tile.get("elevation", 0)) > int(party_tile.get("elevation", 0)):
		radius += int(patrol.get("high_ground_bonus", 1))
	var distance := HexCoordScript.distance(enemy_coord, party_coord)
	# The authored requirement is a roughly ten-hex recognition radius. Requiring
	# a separate straight-line LOS test let a single viaduct/cliff blocker make a
	# nearby enemy inert even though both units shared a valid walking route.
	if distance > radius:
		return UNAWARE
	return ALERT if distance <= alert_radius else SUSPICIOUS

static func has_line_of_sight(grid, definition: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	var explicit: Dictionary = {}
	for blocker in definition.get("los_blockers", []):
		explicit[HexCoordScript.key(Vector2i(int(blocker.get("q", 0)), int(blocker.get("r", 0))))] = true
	var line := HexCoordScript.line(from, to)
	var source_elevation := int(grid.tile(from).get("elevation", 0))
	var target_elevation := int(grid.tile(to).get("elevation", 0))
	for index in range(1, maxi(1, line.size() - 1)):
		var coord: Vector2i = line[index]
		var tile: Dictionary = grid.tile(coord)
		if tile.is_empty() or explicit.has(HexCoordScript.key(coord)) or bool(tile.get("los_blocker", false)):
			return false
		if int(tile.get("elevation", 0)) >= maxi(source_elevation, target_elevation) + 2:
			return false
	return true

static func risk_for_path(state: Dictionary, definition: Dictionary, grid, path: Array[Vector2i]) -> String:
	ensure_state(state, definition, grid)
	var watched := false
	for coord in path:
		for patrol in definition.get("patrols", []):
			var encounter_id := str(patrol.get("encounter_id", ""))
			if encounter_id.is_empty() or str(state.get("encounter_states", {}).get(encounter_id, "")) == PATROL_CLEARED:
				continue
			var enemy_coord := coord_for(state, encounter_id)
			var radius := maxi(0, int(patrol.get("engagement_radius", 0)))
			if HexCoordScript.distance(enemy_coord, coord) <= radius:
				return "ENCOUNTER"
			var runtime: Dictionary = state.get("patrol_states", {}).get(encounter_id, {})
			var test_runtime := runtime.duplicate(true)
			if awareness_for(patrol, test_runtime, coord, grid, definition) != UNAWARE:
				watched = true
	return "WATCHED" if watched else "SAFE"

static func should_render_pawn(coord: Vector2i, camera_coord: Vector2i, radius: int) -> bool:
	return HexCoordScript.distance(coord, camera_coord) <= maxi(1, radius)

static func _advance_patrol(runtime: Dictionary, patrol: Dictionary, grid, tick: int) -> Dictionary:
	if not bool(patrol.get("patrol_enabled", false)):
		return runtime
	if int(runtime.get("wait_remaining", 0)) > 0:
		runtime.wait_remaining = int(runtime.wait_remaining) - 1
		runtime.patrol_state = PATROL_WAIT
		return runtime
	if tick < int(runtime.get("next_move_tick", 0)):
		return runtime
	var route: Array = patrol.get("patrol_route_hexes", [])
	if route.size() <= 1:
		return runtime
	var index := clampi(int(runtime.get("current_patrol_index", 0)), 0, route.size() - 1)
	var direction := int(runtime.get("direction", 1))
	var mode := str(patrol.get("patrol_mode", "LOOP"))
	if mode == "LOOP":
		index = (index + 1) % route.size()
	else:
		if index + direction >= route.size() or index + direction < 0:
			direction *= -1
		index += direction
	var target: Dictionary = route[index]
	var current := Vector2i(int(runtime.get("q", 0)), int(runtime.get("r", 0)))
	var next_coord := Vector2i(int(target.get("q", current.x)), int(target.get("r", current.y)))
	if grid.can_step(current, next_coord):
		runtime.q = next_coord.x
		runtime.r = next_coord.y
		runtime.current_patrol_index = index
		runtime.direction = direction
		runtime.wait_remaining = maxi(0, int(patrol.get("wait_time_ticks", 0)))
	runtime.next_move_tick = tick + maxi(1, int(patrol.get("patrol_speed_ticks", 2)))
	return runtime

static func _advance_chase(runtime: Dictionary, patrol: Dictionary, party_coord: Vector2i, grid) -> Dictionary:
	var current := Vector2i(int(runtime.get("q", 0)), int(runtime.get("r", 0)))
	if current == party_coord:
		return runtime
	# Use the same authoritative pathfinder as the player. The old greedy adjacent
	# choice could stall forever at a blocked hex even when a route around it was
	# available, creating enemies that appeared close but never moved.
	var chase_path: Array[Vector2i] = HexPathfinderScript.find_path(grid, current, party_coord)
	if chase_path.size() >= 2 and grid.can_step(current, chase_path[1]):
		var next_coord: Vector2i = chase_path[1]
		runtime.q = next_coord.x
		runtime.r = next_coord.y
		runtime.patrol_state = PATROL_CHASE
	return runtime

static func patrol_is_stationary(definition: Dictionary, patrol: Dictionary) -> bool:
	## Bosses, special-event contacts and recruitable companions are fixed story
	## anchors. Only normal enemies may chase the party during an enemy phase.
	var encounter_id := str(patrol.get("encounter_id", ""))
	if bool(patrol.get("stationary", false)):
		return true
	for node_value in definition.get("nodes", []):
		var node: Dictionary = node_value
		if str(node.get("node_id", "")) != encounter_id:
			continue
		var stage := DataRegistry.stage(str(node.get("stage_id", "")))
		if bool(stage.get("boss", false)):
			return true
		break
	for event_value in definition.get("event_encounters", []):
		var event: Dictionary = event_value
		if str(event.get("node_id", "")) == encounter_id:
			return true
	return false
