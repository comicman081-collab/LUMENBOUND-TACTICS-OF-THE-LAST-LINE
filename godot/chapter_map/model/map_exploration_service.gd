class_name MapExplorationService
extends RefCounted

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const GrowthAnalyzerScript := preload("res://progression/growth_affordability_analyzer.gd")
const MapSimulationScript := preload("res://chapter_map/model/map_simulation.gd")

static func ensure_state(state: Dictionary, definition: Dictionary) -> void:
	if not state.has("current_party_hex"):
		state.current_party_hex = [int(state.get("current_q", 0)), int(state.get("current_r", 0))]
	if not state.has("cleared_encounters"):
		state.cleared_encounters = state.get("cleared_nodes", []).duplicate()
	if not state.has("encounter_states"):
		state.encounter_states = {}
	if not state.has("treasure_states"):
		state.treasure_states = {}
	if not state.has("revealed_treasures"):
		state.revealed_treasures = []
	if not state.has("claimed_treasures"):
		state.claimed_treasures = []
	if not state.has("pending_encounter"):
		state.pending_encounter = {}
	if not state.has("last_map_camera_hex"):
		state.last_map_camera_hex = state.current_party_hex.duplicate()
	if not state.has("discovered_tiles"):
		state.discovered_tiles = []
	if not state.has("relay_states"):
		state.relay_states = {}
	if not state.has("map_event_states"):
		state.map_event_states = {}
	if not state.has("intel_states"):
		state.intel_states = {}
	if not state.has("exploration_completion"):
		state.exploration_completion = {}
	for treasure in definition.get("treasures", []):
		var treasure_id := str(treasure.get("treasure_id", ""))
		if treasure_id == "":
			continue
		if not state.treasure_states.has(treasure_id):
			state.treasure_states[treasure_id] = "UNDISCOVERED" if str(treasure.get("visibility", "VISIBLE")) == "HIDDEN" else "REVEALED"
	for relay in definition.get("relays", []):
		var relay_id := str(relay.get("relay_id", ""))
		if relay_id != "" and not state.relay_states.has(relay_id):
			state.relay_states[relay_id] = "OFFLINE"
	for event in definition.get("map_events", []):
		var event_id := str(event.get("event_id", ""))
		if event_id != "" and not state.map_event_states.has(event_id):
			state.map_event_states[event_id] = "UNDISCOVERED"
	MapSimulationScript.ensure_state(state, definition)

static func encounter_cleared(state: Dictionary, node_id: String) -> bool:
	return state.get("cleared_encounters", []).has(node_id) or state.get("cleared_nodes", []).has(node_id)

static func mark_encounter_cleared(state: Dictionary, node_id: String) -> void:
	if not state.cleared_encounters.has(node_id):
		state.cleared_encounters.append(node_id)
	if not state.cleared_nodes.has(node_id):
		state.cleared_nodes.append(node_id)
	state.encounter_states[node_id] = "CLEARED"

static func update_hidden_proximity(state: Dictionary, definition: Dictionary, current: Vector2i) -> Array[String]:
	ensure_state(state, definition)
	var changed: Array[String] = []
	for treasure in definition.get("treasures", []):
		if str(treasure.get("visibility", "VISIBLE")) != "HIDDEN":
			continue
		var treasure_id := str(treasure.get("treasure_id", ""))
		var previous := str(state.treasure_states.get(treasure_id, "UNDISCOVERED"))
		if previous == "CLAIMED":
			continue
		var distance := HexCoordScript.distance(current, Vector2i(int(treasure.get("q", 0)), int(treasure.get("r", 0))))
		var next := previous
		if distance <= 1:
			next = "REVEALED"
		elif distance <= 2 and previous == "UNDISCOVERED":
			next = "HINTED"
		if next != previous:
			state.treasure_states[treasure_id] = next
			if next == "REVEALED" and not state.revealed_treasures.has(treasure_id):
				state.revealed_treasures.append(treasure_id)
			changed.append(treasure_id)
	return changed

static func treasure_state(state: Dictionary, treasure_id: String) -> String:
	return str(state.get("treasure_states", {}).get(treasure_id, "UNDISCOVERED"))

static func can_render_treasure(state: Dictionary, treasure: Dictionary) -> bool:
	var status := treasure_state(state, str(treasure.get("treasure_id", "")))
	return status == "REVEALED" and status != "CLAIMED"

static func claim_treasure(state: Dictionary, definition: Dictionary, treasure_id: String) -> GameResult:
	ensure_state(state, definition)
	var treasure: Dictionary = {}
	for candidate in definition.get("treasures", []):
		if str(candidate.get("treasure_id", "")) == treasure_id:
			treasure = candidate
			break
	if treasure.is_empty():
		return GameResult.failure("UNKNOWN_TREASURE")
	if treasure_state(state, treasure_id) != "REVEALED":
		return GameResult.failure("TREASURE_NOT_REVEALED")
	if state.claimed_treasures.has(treasure_id):
		return GameResult.failure("TREASURE_ALREADY_CLAIMED")
	var pre_profile := AppState.profile.duplicate(true)
	var rewards: Dictionary = RewardService.resolve_direct(treasure.get("rewards", {}))
	state.treasure_states[treasure_id] = "CLAIMED"
	state.claimed_treasures.append(treasure_id)
	var post_profile := AppState.profile.duplicate(true)
	return GameResult.success({
		"source_type": "TREASURE",
		"source_id": treasure_id,
		"rewards": rewards,
		"pre_inventory": pre_profile.get("inventory", {}).duplicate(true),
		"post_inventory": post_profile.get("inventory", {}).duplicate(true),
		"growth": GrowthAnalyzerScript.analyze(pre_profile, post_profile),
	})

static func relay_state(state: Dictionary, relay_id: String) -> String:
	return str(state.get("relay_states", {}).get(relay_id, "OFFLINE"))

static func activate_relay(state: Dictionary, definition: Dictionary, relay_id: String) -> GameResult:
	ensure_state(state, definition)
	var relay := _relay(definition, relay_id)
	if relay.is_empty():
		return GameResult.failure("UNKNOWN_RELAY")
	if relay_state(state, relay_id) == "ACTIVE":
		return GameResult.failure("RELAY_ALREADY_ACTIVE")
	state.relay_states[relay_id] = "ACTIVE"
	var effects: Dictionary = relay.get("effects", {})
	_reveal_area(state, definition, Vector2i(int(relay.get("q", 0)), int(relay.get("r", 0))), int(effects.get("reveal_radius", 0)))
	var hinted := str(effects.get("hint_treasure_id", ""))
	if hinted != "" and treasure_state(state, hinted) == "UNDISCOVERED":
		state.treasure_states[hinted] = "HINTED"
	var intel_id := str(effects.get("intel_id", ""))
	if intel_id != "":
		state.intel_states[intel_id] = "DISCOVERED"
	_update_completion(state, definition)
	return GameResult.success({"relay_id": relay_id, "effects": effects.duplicate(true)})

static func can_fast_travel_between(state: Dictionary, definition: Dictionary, origin_id: String, destination_id: String) -> bool:
	if origin_id == destination_id or relay_state(state, origin_id) != "ACTIVE" or relay_state(state, destination_id) != "ACTIVE":
		return false
	var origin := _relay(definition, origin_id)
	var destination := _relay(definition, destination_id)
	if origin.is_empty() or destination.is_empty():
		return false
	# A destination must have been physically discovered first; an activated
	# relay can never expose a future region as a progression bypass.
	return state.get("visited_tiles", []).has(HexCoordScript.key(Vector2i(int(destination.get("q", 0)), int(destination.get("r", 0)))))

static func discover_event(state: Dictionary, definition: Dictionary, event_id: String) -> bool:
	ensure_state(state, definition)
	if _event(definition, event_id).is_empty() or str(state.map_event_states.get(event_id, "UNDISCOVERED")) != "UNDISCOVERED":
		return false
	state.map_event_states[event_id] = "DISCOVERED"
	_update_completion(state, definition)
	return true

static func event_state(state: Dictionary, event_id: String) -> String:
	return str(state.get("map_event_states", {}).get(event_id, "UNDISCOVERED"))

static func resolve_event(state: Dictionary, definition: Dictionary, event_id: String, choice_id: String) -> GameResult:
	ensure_state(state, definition)
	var event := _event(definition, event_id)
	if event.is_empty():
		return GameResult.failure("UNKNOWN_EVENT")
	if event_state(state, event_id) == "RESOLVED":
		return GameResult.failure("EVENT_ALREADY_RESOLVED")
	var choice: Dictionary = {}
	for candidate in event.get("choices", []):
		if str(candidate.get("choice_id", "")) == choice_id:
			choice = candidate
			break
	if choice.is_empty():
		return GameResult.failure("UNKNOWN_EVENT_CHOICE")
	var pre_profile := AppState.profile.duplicate(true)
	var rewards: Dictionary = RewardService.resolve_direct(choice.get("rewards", {}))
	state.map_event_states[event_id] = "RESOLVED"
	var effects: Dictionary = choice.get("effects", {})
	_reveal_area(state, definition, Vector2i(int(event.get("q", 0)), int(event.get("r", 0))), int(effects.get("reveal_radius", 0)))
	var hinted := str(effects.get("hint_treasure_id", ""))
	if hinted != "" and treasure_state(state, hinted) == "UNDISCOVERED":
		state.treasure_states[hinted] = "HINTED"
	var relay_id := str(effects.get("activate_relay_id", ""))
	if relay_id != "" and relay_state(state, relay_id) != "ACTIVE":
		activate_relay(state, definition, relay_id)
	var intel_id := str(choice.get("intel_id", effects.get("intel_id", "")))
	if intel_id != "":
		state.intel_states[intel_id] = "DISCOVERED"
	_update_completion(state, definition)
	var post_profile := AppState.profile.duplicate(true)
	return GameResult.success({
		"source_type": "MAP_EVENT", "source_id": event_id, "choice_id": choice_id,
		"rewards": rewards, "pre_inventory": pre_profile.get("inventory", {}).duplicate(true),
		"post_inventory": post_profile.get("inventory", {}).duplicate(true),
		"growth": GrowthAnalyzerScript.analyze(pre_profile, post_profile),
	})

static func update_proximity(state: Dictionary, definition: Dictionary, current: Vector2i) -> Array[String]:
	var changed := update_hidden_proximity(state, definition, current)
	for event in definition.get("map_events", []):
		var event_id := str(event.get("event_id", ""))
		if event_id == "" or event_state(state, event_id) != "UNDISCOVERED":
			continue
		if HexCoordScript.distance(current, Vector2i(int(event.get("q", 0)), int(event.get("r", 0)))) <= int(event.get("discover_radius", 1)):
			if discover_event(state, definition, event_id):
				changed.append(event_id)
	_update_completion(state, definition)
	return changed

static func completion(state: Dictionary, definition: Dictionary) -> Dictionary:
	_update_completion(state, definition)
	return state.get("exploration_completion", {}).duplicate(true)

static func _update_completion(state: Dictionary, definition: Dictionary) -> void:
	var battle_total: int = definition.get("nodes", []).filter(func(node): return str(node.get("stage_id", "")) != "").size()
	var visible_total: int = definition.get("treasures", []).filter(func(treasure): return str(treasure.get("visibility", "")) == "VISIBLE").size()
	var visible_claimed: int = 0
	var hidden_found: int = 0
	for treasure in definition.get("treasures", []):
		var id := str(treasure.get("treasure_id", ""))
		if str(treasure.get("visibility", "")) == "VISIBLE" and state.get("claimed_treasures", []).has(id):
			visible_claimed += 1
		if str(treasure.get("visibility", "")) == "HIDDEN" and treasure_state(state, id) != "UNDISCOVERED":
			hidden_found += 1
	var relays_active: int = 0
	for relay in definition.get("relays", []):
		if relay_state(state, str(relay.get("relay_id", ""))) == "ACTIVE": relays_active += 1
	var intel_found: int = state.get("intel_states", {}).size()
	var known_total: int = battle_total + visible_total + definition.get("relays", []).size() + definition.get("map_events", []).size()
	var known_done: int = state.get("cleared_encounters", []).size() + visible_claimed + relays_active + intel_found
	state.exploration_completion = {
		"percent": clampi(roundi(float(known_done) / float(maxi(1, known_total)) * 100.0), 0, 100),
		"encounters_done": state.get("cleared_encounters", []).size(), "encounters_total": battle_total,
		"visible_done": visible_claimed, "visible_total": visible_total,
		"hidden_found": hidden_found, "relays_done": relays_active, "relays_total": definition.get("relays", []).size(),
		"intel_found": intel_found,
	}

static func _reveal_area(state: Dictionary, definition: Dictionary, center: Vector2i, radius: int) -> void:
	if radius <= 0: return
	for tile in definition.get("tiles", []):
		var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		if HexCoordScript.distance(center, coord) <= radius:
			var key := HexCoordScript.key(coord)
			if not state.discovered_tiles.has(key): state.discovered_tiles.append(key)

static func _relay(definition: Dictionary, relay_id: String) -> Dictionary:
	for relay in definition.get("relays", []):
		if str(relay.get("relay_id", "")) == relay_id: return relay
	return {}

static func _event(definition: Dictionary, event_id: String) -> Dictionary:
	for event in definition.get("map_events", []):
		if str(event.get("event_id", "")) == event_id: return event
	return {}
