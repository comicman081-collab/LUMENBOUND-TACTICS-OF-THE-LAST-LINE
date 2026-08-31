class_name MapExplorationService
extends RefCounted

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const GrowthAnalyzerScript := preload("res://progression/growth_affordability_analyzer.gd")
const MapSimulationScript := preload("res://chapter_map/model/map_simulation.gd")
const BASE_PLAYER_VISION_RADIUS := 8
const INITIAL_PLAYER_MOVE_POINTS := 3
const INITIAL_MOVEMENT_REPAIR_REVISION := 1

static func ensure_state(state: Dictionary, definition: Dictionary, grid = null) -> bool:
	var changed := false
	if not state.has("current_party_hex"):
		state.current_party_hex = [int(state.get("current_q", 0)), int(state.get("current_r", 0))]
		changed = true
	if not state.has("last_pre_contact_hex"):
		state.last_pre_contact_hex = state.current_party_hex.duplicate()
		changed = true
	if not state.has("pending_reveal"):
		state.pending_reveal = {}
		changed = true
	if not state.has("reveal_consumed"):
		state.reveal_consumed = []
		changed = true
	if not state.has("cleared_encounters"):
		state.cleared_encounters = state.get("cleared_nodes", []).duplicate()
		changed = true
	if not state.has("encounter_states"):
		state.encounter_states = {}
		changed = true
	if not state.has("treasure_states"):
		state.treasure_states = {}
		changed = true
	if not state.has("revealed_treasures"):
		state.revealed_treasures = []
		changed = true
	if not state.has("claimed_treasures"):
		state.claimed_treasures = []
		changed = true
	if not state.has("post_reward_turn_pending"):
		state.post_reward_turn_pending = false
		changed = true
	if not state.has("map_leader_id"):
		state.map_leader_id = ""
		changed = true
	if not state.has("pending_encounter"):
		state.pending_encounter = {}
		changed = true
	if not state.has("last_map_camera_hex"):
		state.last_map_camera_hex = state.current_party_hex.duplicate()
		changed = true
	if not state.has("discovered_tiles"):
		state.discovered_tiles = []
		changed = true
	if not state.has("relay_states"):
		state.relay_states = {}
		changed = true
	if not state.has("map_event_states"):
		state.map_event_states = {}
		changed = true
	if not state.has("intel_states"):
		state.intel_states = {}
		changed = true
	if not state.has("movement_points"):
		state.movement_points = 0
		changed = true
	if not state.has("movement_points_max"):
		state.movement_points_max = 0
		changed = true
	if not state.has("exploration_pulse"):
		state.exploration_pulse = 0
		changed = true
	if not state.has("event_encounter_states"):
		state.event_encounter_states = {}
		changed = true
	if not state.has("recruitment_states"):
		state.recruitment_states = {}
		changed = true
	if not state.has("recruitment_progress"):
		state.recruitment_progress = {}
		changed = true
	if not state.has("exploration_completion"):
		state.exploration_completion = {}
		changed = true
	for treasure in definition.get("treasures", []):
		var treasure_id := str(treasure.get("treasure_id", ""))
		if treasure_id == "":
			continue
		if not state.treasure_states.has(treasure_id):
			state.treasure_states[treasure_id] = "UNDISCOVERED" if str(treasure.get("visibility", "VISIBLE")) == "HIDDEN" else "REVEALED"
			changed = true
	for relay in definition.get("relays", []):
		var relay_id := str(relay.get("relay_id", ""))
		if relay_id != "" and not state.relay_states.has(relay_id):
			state.relay_states[relay_id] = "OFFLINE"
			changed = true
	for event in definition.get("map_events", []):
		var event_id := str(event.get("event_id", ""))
		if event_id != "" and not state.map_event_states.has(event_id):
			state.map_event_states[event_id] = "UNDISCOVERED"
			changed = true
	for encounter in definition.get("event_encounters", []):
		var encounter_id := str(encounter.get("event_encounter_id", ""))
		if encounter_id != "" and not state.event_encounter_states.has(encounter_id):
			state.event_encounter_states[encounter_id] = "AVAILABLE"
			changed = true
		for recruitment_value in recruitment_specs(encounter):
			var recruitment: Dictionary = recruitment_value
			var recruit_id := str(recruitment.get("character_id", ""))
			if recruit_id != "" and not state.recruitment_states.has(recruit_id):
				state.recruitment_states[recruit_id] = "UNMET"
				changed = true
	var movement_max := movement_capacity(AppState.profile, definition)
	var prior_movement_max := int(state.get("movement_points_max", 0))
	if prior_movement_max != movement_max:
		state.movement_points_max = movement_max
		# Existing saves receive a full first pulse rather than an empty movement
		# bar after migration. Capacity is always clamped to its data-driven max.
		state.movement_points = clampi(int(state.get("movement_points", movement_max)), 0, movement_max)
		if prior_movement_max <= 0 or (int(state.get("exploration_pulse", 0)) == 0 and int(state.movement_points) >= prior_movement_max):
			state.movement_points = movement_max
		changed = true
	# A short-lived Web deployment persisted `1/3` on an otherwise untouched
	# starting map. Repair only that unmistakable initial state; an ordinary
	# in-progress turn at 1/3 keeps its exact remaining movement.
	if int(state.get("initial_movement_repair_revision", 0)) < INITIAL_MOVEMENT_REPAIR_REVISION:
		var start: Dictionary = definition.get("start_hex", {"q": 0, "r": 0})
		var start_coord := Vector2i(int(start.get("q", 0)), int(start.get("r", 0)))
		var current_coord := Vector2i(int(state.get("current_q", 0)), int(state.get("current_r", 0)))
		var visited: Array = state.get("visited_tiles", [])
		var untouched_start: bool = current_coord == start_coord \
			and visited.size() <= 1 \
			and (visited.is_empty() or visited.has(HexCoordScript.key(start_coord))) \
			and int(state.get("exploration_pulse", 0)) == 0 \
			and int(state.get("map_simulation_state", {}).get("tick", 0)) == 0 \
			and state.get("cleared_nodes", []).is_empty() \
			and state.get("cleared_encounters", []).is_empty()
		if untouched_start and int(state.get("movement_points", 0)) < movement_max:
			state.movement_points_max = movement_max
			state.movement_points = movement_max
		state.initial_movement_repair_revision = INITIAL_MOVEMENT_REPAIR_REVISION
		changed = true
	if MapSimulationScript.ensure_state(state, definition, grid):
		changed = true
	return changed

static func movement_capacity(profile: Dictionary, definition: Dictionary) -> int:
	var rules: Dictionary = definition.get("exploration_rules", {})
	var capacity := maxi(1, int(rules.get("base_move_points", 3)))
	var level := int(profile.get("account", {}).get("level", 1))
	for milestone_value in rules.get("account_level_milestones", []):
		var milestone: Dictionary = milestone_value
		if level >= int(milestone.get("level", 9999)):
			capacity += maxi(0, int(milestone.get("bonus", 0)))
	var inventory: Dictionary = profile.get("inventory", {})
	for module_value in rules.get("mobility_items", []):
		var module: Dictionary = module_value
		if int(inventory.get(str(module.get("item_id", "")), 0)) > 0:
			capacity += maxi(0, int(module.get("bonus", 0)))
	return clampi(capacity, 1, maxi(1, int(rules.get("max_move_points", 8))))

static func player_vision_radius(profile: Dictionary, definition: Dictionary) -> int:
	# The campaign begins with three movement points and eight clear sight cells.
	# Every permanent movement-capacity increase reveals exactly one extra ring.
	return BASE_PLAYER_VISION_RADIUS + maxi(0, movement_capacity(profile, definition) - INITIAL_PLAYER_MOVE_POINTS)

static func _movement_state_initialized(state: Dictionary) -> bool:
	# Movement/UI hot paths run many times per click and once per crossed hex. A
	# canonical live map already owns these fields; rebuilding a validation
	# HexGrid just to read or decrement one integer blocks the Web main thread.
	if not state.has("movement_points") \
		or not state.has("movement_points_max") \
		or not state.has("exploration_pulse") \
		or int(state.get("initial_movement_repair_revision", 0)) < INITIAL_MOVEMENT_REPAIR_REVISION:
		return false
	var maximum := int(state.get("movement_points_max", 0))
	var remaining := int(state.get("movement_points", -1))
	return maximum > 0 and remaining >= 0 and remaining <= maximum

static func _proximity_state_initialized(state: Dictionary, definition: Dictionary) -> bool:
	if not state.has("treasure_states") \
		or not state.has("revealed_treasures") \
		or not state.has("claimed_treasures") \
		or not state.has("map_event_states") \
		or not state.has("exploration_completion"):
		return false
	for treasure_value in definition.get("treasures", []):
		var treasure: Dictionary = treasure_value
		var treasure_id := str(treasure.get("treasure_id", ""))
		if not treasure_id.is_empty() and not state.treasure_states.has(treasure_id):
			return false
	for event_value in definition.get("map_events", []):
		var event: Dictionary = event_value
		var event_id := str(event.get("event_id", ""))
		if not event_id.is_empty() and not state.map_event_states.has(event_id):
			return false
	return true

static func refill_movement(state: Dictionary, definition: Dictionary, grid = null) -> void:
	if not _movement_state_initialized(state):
		ensure_state(state, definition, grid)
	state.exploration_pulse = int(state.get("exploration_pulse", 0)) + 1
	state.movement_points_max = movement_capacity(AppState.profile, definition)
	state.movement_points = int(state.movement_points_max)

static func complete_player_move_turn(state: Dictionary, definition: Dictionary, grid, party_coord: Vector2i) -> Dictionary:
	## One player action owns exactly one enemy phase and one movement refill.
	## Keeping this transaction in the model prevents idle frames, pawn tween
	## steps, and the WAIT button from advancing patrol time independently.
	ensure_state(state, definition, grid)
	var tick_before := int(state.get("map_simulation_state", {}).get("tick", 0))
	var pulse_before := int(state.get("exploration_pulse", 0))
	# One player action owns one enemy action. The former WAIT helper expanded one
	# turn into several ticks and let enemies move repeatedly behind one caption.
	var update: Dictionary = MapSimulationScript.advance_ticks(state, definition, grid, party_coord, 1, player_vision_radius(AppState.profile, definition))
	refill_movement(state, definition, grid)
	update.tick_before = tick_before
	update.tick_after = int(state.get("map_simulation_state", {}).get("tick", 0))
	update.pulse_before = pulse_before
	update.pulse_after = int(state.get("exploration_pulse", 0))
	update.movement_points = int(state.get("movement_points", 0))
	return update

static func spend_movement(state: Dictionary, definition: Dictionary, steps: int, grid = null) -> bool:
	if not _movement_state_initialized(state):
		ensure_state(state, definition, grid)
	if steps <= 0 or int(state.get("movement_points", 0)) < steps:
		return false
	state.movement_points = int(state.movement_points) - steps
	return true

static func movement_remaining(state: Dictionary, definition: Dictionary, grid = null) -> int:
	# Once migration has initialized movement, this is deliberately a pure getter.
	# Legacy/malformed payloads still take the canonical repair path exactly once.
	if _movement_state_initialized(state):
		return int(state.get("movement_points", 0))
	ensure_state(state, definition, grid)
	return int(state.get("movement_points", 0))

static func event_encounter_for_node(definition: Dictionary, node_id: String) -> Dictionary:
	for encounter_value in definition.get("event_encounters", []):
		var encounter: Dictionary = encounter_value
		if str(encounter.get("node_id", "")) == node_id:
			return encounter
	return {}

static func recruitment_specs(encounter: Dictionary) -> Array:
	# One contact may introduce a duo while still owning exactly one map/battle
	# transaction. Legacy single-character events remain byte-for-byte valid.
	var specs: Array = []
	for value in encounter.get("recruitments", []):
		if value is Dictionary and not str(value.get("character_id", "")).is_empty():
			specs.append(value)
	if not specs.is_empty():
		return specs
	var character_id := str(encounter.get("character_id", ""))
	if not character_id.is_empty():
			specs.append({
			"character_id": character_id,
			"recruitment_timing": str(encounter.get("recruitment_timing", "IMMEDIATE_ON_VICTORY")),
			"recruit_after_stage_id": str(encounter.get("recruit_after_stage_id", "")),
			"battle_victories_required": int(encounter.get("battle_victories_required", 1)),
		})
	return specs

static func event_encounter_state(state: Dictionary, encounter_id: String) -> String:
	return str(state.get("event_encounter_states", {}).get(encounter_id, "AVAILABLE"))

static func resolve_event_encounter_victory(state: Dictionary, definition: Dictionary, node_id: String, cleared_stage_id: String, event_encounter_id := "") -> Dictionary:
	ensure_state(state, definition)
	var encounter := event_encounter_for_node(definition, node_id)
	if not event_encounter_id.is_empty():
		for candidate_value in definition.get("event_encounters", []):
			var candidate: Dictionary = candidate_value
			if str(candidate.get("event_encounter_id", "")) == event_encounter_id:
				encounter = candidate
				break
	if encounter.is_empty():
		return {}
	var encounter_id := str(encounter.get("event_encounter_id", ""))
	if encounter_id.is_empty() or event_encounter_state(state, encounter_id) == "RESOLVED":
		return {}
	state.event_encounter_states[encounter_id] = "RESOLVED"
	var recruit_now_ids: Array[String] = []
	var delayed: Array[Dictionary] = []
	var recruitments := recruitment_specs(encounter)
	for recruitment_value in recruitments:
		var recruitment: Dictionary = recruitment_value
		var character_id := str(recruitment.get("character_id", ""))
		if character_id.is_empty(): continue
		var timing := str(recruitment.get("recruitment_timing", "IMMEDIATE_ON_VICTORY"))
		var has_battle_route := recruitment.has("battle_victories_required")
		var required_victories := clampi(int(recruitment.get("battle_victories_required", 1)), 1, 5)
		if has_battle_route and required_victories > 1:
			state.recruitment_states[character_id] = "PENDING"
			state.recruitment_progress[character_id] = {
				"victories": 1,
				"required": required_victories,
				"counted_stage_ids": [cleared_stage_id],
			}
			delayed.append({
				"character_id": character_id,
				"battle_victories_required": required_victories,
				"battle_victories_remaining": required_victories - 1,
			})
		elif timing == "IMMEDIATE_ON_VICTORY" or (has_battle_route and required_victories == 1):
			state.recruitment_states[character_id] = "READY"
			state.recruitment_progress[character_id] = {
				"victories": 1,
				"required": 1,
				"counted_stage_ids": [cleared_stage_id],
			}
			recruit_now_ids.append(character_id)
		else:
			var after_stage_id := str(recruitment.get("recruit_after_stage_id", cleared_stage_id))
			state.recruitment_states[character_id] = "PENDING"
			delayed.append({"character_id": character_id, "recruit_after_stage_id": after_stage_id})
	return {
		"event_encounter_id": encounter_id,
		"character_id": str(recruitments[0].get("character_id", "")) if not recruitments.is_empty() else "",
		"recruit_now": not recruit_now_ids.is_empty(),
		"recruit_now_ids": recruit_now_ids,
		"delayed_recruitments": delayed,
	}

static func resolve_deferred_recruitments(state: Dictionary, definition: Dictionary, cleared_stage_id: String) -> Array[String]:
	ensure_state(state, definition)
	var ready: Array[String] = []
	for encounter_value in definition.get("event_encounters", []):
		var encounter: Dictionary = encounter_value
		for recruitment_value in recruitment_specs(encounter):
			var recruitment: Dictionary = recruitment_value
			var character_id := str(recruitment.get("character_id", ""))
			if character_id.is_empty() or str(state.get("recruitment_states", {}).get(character_id, "UNMET")) != "PENDING": continue
			if recruitment.has("battle_victories_required"):
				var required_victories := clampi(int(recruitment.get("battle_victories_required", 1)), 1, 5)
				var progress: Dictionary = state.recruitment_progress.get(character_id, {
					"victories": 1,
					"required": required_victories,
					"counted_stage_ids": [],
				})
				var counted_stage_ids: Array = progress.get("counted_stage_ids", [])
				if not counted_stage_ids.has(cleared_stage_id):
					counted_stage_ids.append(cleared_stage_id)
					progress.victories = int(progress.get("victories", 0)) + 1
				progress.required = required_victories
				progress.counted_stage_ids = counted_stage_ids
				state.recruitment_progress[character_id] = progress
				if int(progress.get("victories", 0)) >= required_victories:
					state.recruitment_states[character_id] = "READY"
					ready.append(character_id)
				continue
			if str(recruitment.get("recruitment_timing", "")) != "AFTER_STAGE_CLEAR": continue
			if str(recruitment.get("recruit_after_stage_id", "")) != cleared_stage_id: continue
			state.recruitment_states[character_id] = "READY"
			ready.append(character_id)
	return ready

static func encounter_cleared(state: Dictionary, node_id: String) -> bool:
	return state.get("cleared_encounters", []).has(node_id) or state.get("cleared_nodes", []).has(node_id)

static func mark_encounter_cleared(state: Dictionary, node_id: String) -> void:
	if not state.cleared_encounters.has(node_id):
		state.cleared_encounters.append(node_id)
	if not state.cleared_nodes.has(node_id):
		state.cleared_nodes.append(node_id)
	state.encounter_states[node_id] = "CLEARED"

static func update_hidden_proximity(state: Dictionary, definition: Dictionary, current: Vector2i, grid = null) -> Array[String]:
	if not _proximity_state_initialized(state, definition):
		ensure_state(state, definition, grid)
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
	var pre_profile := _growth_profile_snapshot()
	var rewards: Dictionary = RewardService.resolve_direct(treasure.get("rewards", {}))
	state.treasure_states[treasure_id] = "CLAIMED"
	state.claimed_treasures.append(treasure_id)
	var post_profile := _growth_profile_snapshot()
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

static func discover_event(state: Dictionary, definition: Dictionary, event_id: String, grid = null) -> bool:
	if not _proximity_state_initialized(state, definition):
		ensure_state(state, definition, grid)
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
	var pre_profile := _growth_profile_snapshot()
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
	var post_profile := _growth_profile_snapshot()
	return GameResult.success({
		"source_type": "MAP_EVENT", "source_id": event_id, "choice_id": choice_id,
		"rewards": rewards, "pre_inventory": pre_profile.get("inventory", {}).duplicate(true),
		"post_inventory": post_profile.get("inventory", {}).duplicate(true),
		"growth": GrowthAnalyzerScript.analyze(pre_profile, post_profile),
	})

static func _growth_profile_snapshot() -> Dictionary:
	# Growth affordability reads only these four branches. Excluding chapter-map
	# traversal/patrol/fog state prevents treasure and map-event pickups from
	# cloning the expanded world twice before opening the result screen.
	var source: Dictionary = AppState.profile
	return {
		"account": source.get("account", {}).duplicate(true),
		"inventory": source.get("inventory", {}).duplicate(true),
		"roster": source.get("roster", {}).duplicate(true),
		"weapons": source.get("weapons", {}).duplicate(true),
	}

static func update_proximity(state: Dictionary, definition: Dictionary, current: Vector2i, grid = null) -> Array[String]:
	var changed := update_hidden_proximity(state, definition, current, grid)
	for event in definition.get("map_events", []):
		var event_id := str(event.get("event_id", ""))
		if event_id == "" or event_state(state, event_id) != "UNDISCOVERED":
			continue
		if HexCoordScript.distance(current, Vector2i(int(event.get("q", 0)), int(event.get("r", 0)))) <= int(event.get("discover_radius", 1)):
			if discover_event(state, definition, event_id, grid):
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
