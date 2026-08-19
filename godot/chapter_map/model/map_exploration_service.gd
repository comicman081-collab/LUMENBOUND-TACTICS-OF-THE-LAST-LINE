class_name MapExplorationService
extends RefCounted

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const GrowthAnalyzerScript := preload("res://progression/growth_affordability_analyzer.gd")

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
	for treasure in definition.get("treasures", []):
		var treasure_id := str(treasure.get("treasure_id", ""))
		if treasure_id == "":
			continue
		if not state.treasure_states.has(treasure_id):
			state.treasure_states[treasure_id] = "UNDISCOVERED" if str(treasure.get("visibility", "VISIBLE")) == "HIDDEN" else "REVEALED"

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
