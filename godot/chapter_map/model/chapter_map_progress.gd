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
		"last_selected_node": "", "camera_zoom": 1.0, "camera_center": [0.0, 0.0],
		"processed_battle_tokens": []
	}
	state.visited_tiles.append("%d,%d" % [state.current_q, state.current_r])
	refresh_reveal(state, definition, 0, 0, false)
	return state

static func migrate_from_profile(profile: Dictionary, definition: Dictionary) -> Dictionary:
	var state := create_default(definition)
	var highest_normal := int(profile.get("chapter_progress", {}).get("CH01", {}).get("normal_highest", 0))
	var highest_hard := 0
	for number in range(1, 6):
		if int(profile.get("stage_stars", {}).get("CH01-H%02d" % number, 0)) > 0: highest_hard = number
	var current_stage := "CH01-H%02d" % highest_hard if highest_hard > 0 else ("CH01-N%02d" % highest_normal if highest_normal > 0 else "")
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
	refresh_reveal(state, definition, highest_normal, highest_hard, highest_normal >= 10)
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
		elif stage_id.contains("-N") and int(stage_id.right(2)) <= mini(10, highest_normal + 1):
			visible_nodes.append(node)
		elif stage_id.contains("-H") and hard_unlocked and int(stage_id.right(2)) <= mini(5, highest_hard + 1):
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
	state.revealed_tiles = revealed.keys()
	state.revealed_tiles.sort()

static func mark_visited(state: Dictionary, path: Array[Vector2i]) -> void:
	for coord in path:
		var key := HexCoordScript.key(coord)
		if not state.visited_tiles.has(key): state.visited_tiles.append(key)
	if not path.is_empty():
		state.current_q = path[-1].x
		state.current_r = path[-1].y

static func record_clear_once(state: Dictionary, node_id: String, battle_token: String) -> bool:
	if state.processed_battle_tokens.has(battle_token): return false
	state.processed_battle_tokens.append(battle_token)
	if not state.cleared_nodes.has(node_id): state.cleared_nodes.append(node_id)
	return true
