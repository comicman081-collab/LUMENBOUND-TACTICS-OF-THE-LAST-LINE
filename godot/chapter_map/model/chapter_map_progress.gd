class_name ChapterMapProgress
extends RefCounted

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const ChapterMapLoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const MacroWorldGeneratorScript := preload("res://chapter_map/model/macro_world_generator.gd")

static func create_default(definition: Dictionary) -> Dictionary:
	var start: Dictionary = definition.get("start_hex", {"q": 0, "r": 0})
	var state := {
		"current_q": int(start.get("q", 0)), "current_r": int(start.get("r", 0)),
		"visited_tiles": [], "revealed_tiles": [], "cleared_nodes": [],
		"pending_reveal": {}, "reveal_consumed": [],
		"last_selected_node": "", "camera_zoom": 1.0, "camera_center": [0.0, 0.0],
		"processed_battle_tokens": [], "processed_reward_tokens": [],
		"current_party_hex": [int(start.get("q", 0)), int(start.get("r", 0))],
		# The discrete hex occupied immediately before a hostile-contact step.
		# This is a recovery guard, not a second party-position authority.
		"last_pre_contact_hex": [int(start.get("q", 0)), int(start.get("r", 0))],
		"cleared_encounters": [], "encounter_states": {},
		"treasure_states": {}, "revealed_treasures": [], "claimed_treasures": [],
		"pending_encounter": {}, "last_map_camera_hex": [int(start.get("q", 0)), int(start.get("r", 0))],
		"discovered_tiles": [], "patrol_states": {}, "patrol_positions": {},
		"relay_states": {}, "map_event_states": {}, "intel_states": {},
		# Exploration pulses are a map-only pacing contract.  They are never
		# stamina, never enter BattleSimulation, and use axial steps as their
		# only authority so the same save/input follows the same route.
		"movement_points": 0, "movement_points_max": 0, "exploration_pulse": 0,
		"event_encounter_states": {}, "recruitment_states": {}, "recruitment_progress": {},
		"exploration_completion": {},
		"map_simulation_state": {"tick": 0, "seed": int(definition.get("map_simulation", {}).get("seed", 140701)), "paused": false}
	}
	state.visited_tiles.append("%d,%d" % [state.current_q, state.current_r])
	refresh_reveal(state, definition, 0, 0, false)
	return state

static func migrate_from_profile(profile: Dictionary, definition: Dictionary) -> Dictionary:
	var state := create_default(definition)
	var chapter_id := str(definition.get("chapter_id", "CH01"))
	var chapter_progress: Dictionary = profile.get("chapter_progress", {}).get(chapter_id, {})
	var highest_normal := int(chapter_progress.get("normal_highest", 0))
	var highest_hard := 0
	var hard_route: Array = definition.get("hard_route", [])
	for index in range(hard_route.size()):
		if int(profile.get("stage_stars", {}).get(str(hard_route[index]), 0)) > 0: highest_hard = index + 1
	var normal_route: Array = definition.get("normal_route", [])
	var current_stage := str(hard_route[highest_hard - 1]) if highest_hard > 0 else (str(normal_route[highest_normal - 1]) if highest_normal > 0 and highest_normal <= normal_route.size() else "")
	if current_stage != "":
		var current_node := ChapterMapLoaderScript.node_for_stage(definition, current_stage)
		if not current_node.is_empty():
			state.current_q = int(current_node.q)
			state.current_r = int(current_node.r)
			state.last_selected_node = str(current_node.node_id)
	for node in definition.get("nodes", []):
		var stage_id := str(node.get("stage_id", ""))
		if stage_id != "" and int(profile.get("stage_stars", {}).get(stage_id, 0)) > 0:
			state.cleared_nodes.append(str(node.node_id))
	refresh_reveal(state, definition, highest_normal, highest_hard, bool(chapter_progress.get("hard_unlocked", false)))
	return state

static func reanchor_macro_state(state: Dictionary, definition: Dictionary) -> Dictionary:
	## v2 stored the prior compact map q/r positions.  Node IDs are immutable,
	## so they are the migration authority for the expanded R10 macro map.
	var migrated := state.duplicate(true)
	var target: Dictionary = {}
	var last_id := str(migrated.get("last_selected_node", ""))
	if last_id != "":
		for node in definition.get("nodes", []):
			if str(node.get("node_id", "")) == last_id:
				target = node
				break
	if target.is_empty():
		for node in definition.get("nodes", []):
			if migrated.get("cleared_nodes", []).has(str(node.get("node_id", ""))):
				target = node
	if target.is_empty():
		target = definition.get("start_hex", {"q": 0, "r": 0})
	migrated.current_q = int(target.get("q", 0))
	migrated.current_r = int(target.get("r", 0))
	migrated.camera_center = [0.0, 0.0]
	return migrated

static func refresh_reveal(state: Dictionary, definition: Dictionary, highest_normal: int, highest_hard: int, hard_unlocked: bool) -> void:
	var revealed: Dictionary = {}
	var visible_nodes: Array[Dictionary] = []
	for node in definition.get("nodes", []):
		var stage_id := str(node.get("stage_id", ""))
		if stage_id == "":
			visible_nodes.append(node)
		elif definition.get("normal_route", []).find(stage_id) >= 0 and definition.get("normal_route", []).find(stage_id) <= highest_normal:
			visible_nodes.append(node)
		elif hard_unlocked and definition.get("hard_route", []).find(stage_id) >= 0 and definition.get("hard_route", []).find(stage_id) <= highest_hard:
			visible_nodes.append(node)
	for node in visible_nodes:
		var center := Vector2i(int(node.q), int(node.r))
		for tile in definition.get("tiles", []):
			var coord := Vector2i(int(tile.q), int(tile.r))
			if HexCoordScript.distance(center, coord) <= 1: revealed[HexCoordScript.key(coord)] = true
	# Macro maps reveal the actual travel corridor to the next unlocked
	# encounter.  This is intentionally not a teleport: every intermediate hex
	# is eligible for the same deterministic A* route and can be visited/saved.
	if not definition.get("macro_world", {}).is_empty():
		for node in visible_nodes:
			var stage_id := str(node.get("stage_id", ""))
			if stage_id == "":
				continue
			for coord in MacroWorldGeneratorScript.route_to_stage(definition, stage_id):
				revealed[HexCoordScript.key(coord)] = true
				for neighbor in HexCoordScript.neighbors(coord):
					revealed[HexCoordScript.key(neighbor)] = true
	var start: Dictionary = definition.get("start_hex", {"q": 0, "r": 0})
	revealed["%d,%d" % [int(start.q), int(start.r)]] = true
	# Exploration devices can reveal a local area without changing the authored
	# stage unlock route.  Keep these discovered cells when stage progression
	# refreshes the normal route rather than silently erasing a repaired relay's
	# map information.
	for key in state.get("discovered_tiles", []):
		revealed[str(key)] = true
	state.revealed_tiles = revealed.keys()
	state.revealed_tiles.sort()

static func mark_visited(state: Dictionary, path: Array[Vector2i]) -> void:
	for coord in path:
		var key := HexCoordScript.key(coord)
		if not state.visited_tiles.has(key): state.visited_tiles.append(key)
	if not path.is_empty():
		state.current_q = path[-1].x
		state.current_r = path[-1].y
		state.current_party_hex = [path[-1].x, path[-1].y]

static func record_clear_once(state: Dictionary, node_id: String, battle_token: String) -> bool:
	if state.processed_battle_tokens.has(battle_token): return false
	state.processed_battle_tokens.append(battle_token)
	if not state.cleared_nodes.has(node_id): state.cleared_nodes.append(node_id)
	return true

static func queue_reveal_once(state: Dictionary, reveal_id: String, source_stage_id: String, tile_keys: Array[String], unlocked_stage_ids: Array[String]) -> bool:
	if reveal_id.is_empty() or (tile_keys.is_empty() and unlocked_stage_ids.is_empty()):
		return false
	if state.get("reveal_consumed", []).has(reveal_id):
		return false
	var pending: Dictionary = state.get("pending_reveal", {})
	if not pending.is_empty():
		return str(pending.get("reveal_id", "")) == reveal_id
	tile_keys.sort()
	unlocked_stage_ids.sort()
	state.pending_reveal = {
		"reveal_id": reveal_id,
		"source_stage_id": source_stage_id,
		"tile_keys": tile_keys,
		"unlocked_stage_ids": unlocked_stage_ids,
	}
	return true

static func consume_pending_reveal(state: Dictionary) -> Dictionary:
	var pending: Dictionary = state.get("pending_reveal", {})
	if pending.is_empty():
		return {}
	var reveal_id := str(pending.get("reveal_id", ""))
	if reveal_id.is_empty() or state.get("reveal_consumed", []).has(reveal_id):
		state.pending_reveal = {}
		return {}
	state.reveal_consumed.append(reveal_id)
	state.pending_reveal = {}
	return pending.duplicate(true)
