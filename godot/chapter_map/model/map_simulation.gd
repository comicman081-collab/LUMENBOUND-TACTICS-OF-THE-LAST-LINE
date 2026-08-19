class_name MapSimulation
extends RefCounted

## Deterministic logical simulation for the Chapter Map.  Rendering and tween
## animation never feed back into this state: a saved tick, patrol route and
## player coordinate always produce the same next state.

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")

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

static func ensure_state(state: Dictionary, definition: Dictionary) -> void:
	if not state.has("map_simulation_state"):
		state.map_simulation_state = {"tick": 0, "seed": int(definition.get("map_simulation", {}).get("seed", 140701)), "paused": false}
	if not state.has("patrol_states"):
		state.patrol_states = {}
	if not state.has("patrol_positions"):
		state.patrol_positions = {}
	for patrol in definition.get("patrols", []):
		var encounter_id := str(patrol.get("encounter_id", ""))
		if encounter_id.is_empty():
			continue
		var route: Array = patrol.get("patrol_route_hexes", [])
		var origin: Dictionary = route[0] if not route.is_empty() else patrol.get("return_hex", {"q": 0, "r": 0})
		if not state.patrol_states.has(encounter_id):
			state.patrol_states[encounter_id] = {
				"current_patrol_index": 0,
				"direction": 1,
				"wait_remaining": 0,
				"next_move_tick": 0,
				"patrol_state": PATROL_IDLE,
				"awareness": UNAWARE,
				"q": int(origin.get("q", 0)),
				"r": int(origin.get("r", 0)),
			}
		var saved: Dictionary = state.patrol_states[encounter_id]
		if not state.patrol_positions.has(encounter_id):
			state.patrol_positions[encounter_id] = [int(saved.get("q", origin.get("q", 0))), int(saved.get("r", origin.get("r", 0)))]

static func patrol_definition(definition: Dictionary, encounter_id: String) -> Dictionary:
	for patrol in definition.get("patrols", []):
		if str(patrol.get("encounter_id", "")) == encounter_id:
			return patrol
	return {}

static func coord_for(state: Dictionary, encounter_id: String) -> Vector2i:
	var patrol: Dictionary = state.get("patrol_states", {}).get(encounter_id, {})
	return Vector2i(int(patrol.get("q", 0)), int(patrol.get("r", 0)))

static func advance_ticks(state: Dictionary, definition: Dictionary, grid, party_coord: Vector2i, tick_count := 1) -> Dictionary:
	ensure_state(state, definition)
	var result := {"changed": [], "contacts": [], "awareness": {}}
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
			var awareness := awareness_for(patrol, runtime, party_coord, grid, definition)
			runtime.awareness = awareness
			if awareness == ALERT:
				runtime.patrol_state = PATROL_ALERT
				if bool(patrol.get("chase_short", false)):
					runtime = _advance_chase(runtime, patrol, party_coord, grid)
			else:
				runtime = _advance_patrol(runtime, patrol, grid, tick)
				if str(runtime.get("patrol_state", "")) != PATROL_WAIT:
					runtime.patrol_state = PATROL_MOVING if bool(patrol.get("patrol_enabled", false)) else PATROL_IDLE
			var current := Vector2i(int(runtime.get("q", 0)), int(runtime.get("r", 0)))
			state.patrol_states[encounter_id] = runtime
			state.patrol_positions[encounter_id] = [current.x, current.y]
			result.awareness[encounter_id] = awareness
			if current != previous:
				result.changed.append(encounter_id)
			var contact_radius := maxi(0, int(patrol.get("engagement_radius", 0)))
			if HexCoordScript.distance(current, party_coord) <= contact_radius and (awareness == ALERT or current == party_coord):
				contacts.append(encounter_id)
		contacts.sort()
		if not contacts.is_empty():
			result.contacts = contacts
			break
	return result

static func advance_wait(state: Dictionary, definition: Dictionary, grid, party_coord: Vector2i) -> Dictionary:
	var pulses := maxi(1, int(definition.get("map_simulation", {}).get("wait_pulse_ticks", 4)))
	return advance_ticks(state, definition, grid, party_coord, pulses)

static func awareness_for(patrol: Dictionary, runtime: Dictionary, party_coord: Vector2i, grid, definition: Dictionary) -> String:
	var enemy_coord := Vector2i(int(runtime.get("q", 0)), int(runtime.get("r", 0)))
	var radius := maxi(1, int(patrol.get("awareness_radius", 3)))
	var alert_radius := maxi(0, int(patrol.get("alert_radius", 1)))
	var enemy_tile: Dictionary = grid.tile(enemy_coord)
	var party_tile: Dictionary = grid.tile(party_coord)
	if int(enemy_tile.get("elevation", 0)) > int(party_tile.get("elevation", 0)):
		radius += int(patrol.get("high_ground_bonus", 1))
	var distance := HexCoordScript.distance(enemy_coord, party_coord)
	if distance > radius or not has_line_of_sight(grid, definition, enemy_coord, party_coord):
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
	ensure_state(state, definition)
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
	var home: Dictionary = patrol.get("return_hex", {"q": current.x, "r": current.y})
	var home_coord := Vector2i(int(home.get("q", current.x)), int(home.get("r", current.y)))
	var leash := maxi(1, int(patrol.get("guard_radius", 3)))
	var choices := HexCoordScript.neighbors(current)
	choices.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var ld := HexCoordScript.distance(left, party_coord)
		var rd := HexCoordScript.distance(right, party_coord)
		return ld < rd or (ld == rd and (left.x < right.x or (left.x == right.x and left.y < right.y))))
	for candidate in choices:
		if grid.can_step(current, candidate) and HexCoordScript.distance(home_coord, candidate) <= leash:
			runtime.q = candidate.x
			runtime.r = candidate.y
			runtime.patrol_state = PATROL_CHASE
			return runtime
	return runtime
