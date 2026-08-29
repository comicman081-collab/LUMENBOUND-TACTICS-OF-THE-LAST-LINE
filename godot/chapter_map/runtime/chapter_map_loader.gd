class_name ChapterMapLoader
extends RefCounted

const COMPILED_ROOT := "res://data/compiled/chapter_maps/"
const MacroWorldGeneratorScript := preload("res://chapter_map/model/macro_world_generator.gd")
const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const HexGridScript := preload("res://chapter_map/model/hex_grid.gd")
static var cached_maps: Dictionary = {}

static func load_map(map_id: String) -> Dictionary:
	if cached_maps.has(map_id):
		return cached_maps[map_id]
	var path := COMPILED_ROOT + map_id + ".json"
	if not FileAccess.file_exists(path): return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var definition := MacroWorldGeneratorScript.expand(parsed) if parsed is Dictionary else {}
	cached_maps[map_id] = definition
	return definition

static func validate(definition: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var tile_keys: Dictionary = {}
	for tile in definition.get("tiles", []):
		var key := "%d,%d" % [int(tile.get("q", 0)), int(tile.get("r", 0))]
		if tile_keys.has(key): errors.append("duplicate tile " + key)
		tile_keys[key] = tile
	var node_ids: Dictionary = {}
	var normal := 0
	var hard := 0
	for node in definition.get("nodes", []):
		var node_id := str(node.get("node_id", ""))
		var key := "%d,%d" % [int(node.get("q", 0)), int(node.get("r", 0))]
		if node_ids.has(node_id): errors.append("duplicate node " + node_id)
		node_ids[node_id] = true
		if not tile_keys.has(key): errors.append("node outside map " + node_id)
		elif bool(tile_keys[key].get("movement_blocked", false)): errors.append("node on blocked tile " + node_id)
		var stage_id := str(node.get("stage_id", ""))
		if stage_id != "" and DataRegistry.stage(stage_id).is_empty(): errors.append("unknown stage " + stage_id)
		if node.get("node_type", "") in ["NORMAL_BATTLE", "NORMAL_ELITE", "NORMAL_BOSS"]: normal += 1
		if node.get("node_type", "") in ["HARD_BATTLE", "HARD_ELITE", "HARD_BOSS"]: hard += 1
	if normal != 20: errors.append("NORMAL node count %d" % normal)
	if hard != 5: errors.append("HARD node count %d" % hard)
	if definition.get("normal_route", []).size() != 20: errors.append("NORMAL route count %d" % definition.get("normal_route", []).size())
	if definition.get("hard_route", []).size() != 5: errors.append("HARD route count %d" % definition.get("hard_route", []).size())
	var exploration_rules: Dictionary = definition.get("exploration_rules", {})
	var base_move_points := int(exploration_rules.get("base_move_points", 0))
	var max_move_points := int(exploration_rules.get("max_move_points", 0))
	if base_move_points < 3 or base_move_points > 4: errors.append("base move points must be 3 or 4")
	if max_move_points != 8: errors.append("max move points must be 8")
	if base_move_points > max_move_points: errors.append("base move points exceed max")
	for milestone_value in exploration_rules.get("account_level_milestones", []):
		var milestone: Dictionary = milestone_value
		if int(milestone.get("level", 0)) <= 0 or int(milestone.get("bonus", -1)) < 0:
			errors.append("invalid movement milestone")
	var route_module_ids: Dictionary = {}
	for mobility_value in exploration_rules.get("mobility_items", []):
		var mobility: Dictionary = mobility_value
		var item_id := str(mobility.get("item_id", ""))
		if item_id.is_empty() or DataRegistry.by_id("items", item_id).is_empty(): errors.append("unknown mobility item " + item_id)
		if int(mobility.get("bonus", -1)) < 0: errors.append("invalid mobility item bonus " + item_id)
		if route_module_ids.has(item_id): errors.append("duplicate mobility item " + item_id)
		route_module_ids[item_id] = true
	var event_encounter_ids: Dictionary = {}
	for event_encounter_value in definition.get("event_encounters", []):
		var event_encounter: Dictionary = event_encounter_value
		var event_encounter_id := str(event_encounter.get("event_encounter_id", ""))
		var node_id := str(event_encounter.get("node_id", ""))
		if event_encounter_id.is_empty() or event_encounter_ids.has(event_encounter_id): errors.append("invalid or duplicate event encounter " + event_encounter_id)
		event_encounter_ids[event_encounter_id] = true
		if not node_ids.has(node_id): errors.append("event encounter unknown node " + node_id)
		if str(event_encounter.get("marker", "")) != "BANG": errors.append("event encounter marker invalid " + event_encounter_id)
		if str(event_encounter.get("entry_type", "")) != "EVENT_CONTACT": errors.append("event encounter entry invalid " + event_encounter_id)
		var event_kind := str(event_encounter.get("event_kind", "COMPANION"))
		if event_kind not in ["COMPANION", "SPECIAL_ENEMY"]: errors.append("event encounter kind invalid " + event_encounter_id)
		if str(event_encounter.get("title_key", "")).is_empty() or str(event_encounter.get("body_key", "")).is_empty() or str(event_encounter.get("contact_outcome_key", "")).is_empty(): errors.append("event encounter localization missing " + event_encounter_id)
		var dialogue: Array = event_encounter.get("pre_battle_dialogue", [])
		if dialogue.size() < 2 or dialogue.size() > 4:
			errors.append("event encounter dialogue count invalid " + event_encounter_id)
		for page_value in dialogue:
			if not page_value is Dictionary:
				errors.append("event encounter dialogue invalid " + event_encounter_id)
				continue
			var page: Dictionary = page_value
			var speaker_kind := str(page.get("speaker_kind", ""))
			if speaker_kind not in ["COMMAND", "COMPANION", "ENEMY"] or str(page.get("text_key", "")).is_empty():
				errors.append("event encounter dialogue payload invalid " + event_encounter_id)
			if speaker_kind == "COMPANION" and DataRegistry.character(str(page.get("speaker_id", ""))).is_empty():
				errors.append("event encounter dialogue companion invalid " + event_encounter_id)
			if speaker_kind == "ENEMY" and DataRegistry.enemy(str(page.get("speaker_id", ""))).is_empty():
				errors.append("event encounter dialogue enemy invalid " + event_encounter_id)
		var recruitments: Array = event_encounter.get("recruitments", [])
		if recruitments.is_empty() and not str(event_encounter.get("character_id", "")).is_empty():
			recruitments = [{
				"character_id": str(event_encounter.get("character_id", "")),
				"recruitment_timing": str(event_encounter.get("recruitment_timing", "")),
				"recruit_after_stage_id": str(event_encounter.get("recruit_after_stage_id", "")),
			}]
		if event_kind == "COMPANION" and (recruitments.is_empty() or recruitments.size() > 2):
			errors.append("event encounter recruitment count invalid " + event_encounter_id)
		if event_kind == "SPECIAL_ENEMY" and (not recruitments.is_empty() or DataRegistry.enemy(str(event_encounter.get("enemy_id", ""))).is_empty()):
			errors.append("special enemy contract invalid " + event_encounter_id)
		for recruitment_value in recruitments:
			if not recruitment_value is Dictionary:
				errors.append("event encounter recruitment invalid " + event_encounter_id)
				continue
			var recruitment: Dictionary = recruitment_value
			var character_id := str(recruitment.get("character_id", ""))
			var recruitment_timing := str(recruitment.get("recruitment_timing", ""))
			if DataRegistry.character(character_id).is_empty(): errors.append("event encounter unknown character " + character_id)
			if recruitment_timing not in ["IMMEDIATE_ON_VICTORY", "AFTER_STAGE_CLEAR"]: errors.append("event encounter recruitment timing invalid " + event_encounter_id)
			if recruitment_timing == "AFTER_STAGE_CLEAR" and DataRegistry.stage(str(recruitment.get("recruit_after_stage_id", ""))).is_empty(): errors.append("event encounter recruit stage invalid " + event_encounter_id)
			var route_battles := int(recruitment.get("battle_victories_required", 1))
			if recruitment.has("battle_victories_required") and (route_battles < 1 or route_battles > 5): errors.append("event encounter battle route invalid " + event_encounter_id)
	var treasure_ids: Dictionary = {}
	for treasure in definition.get("treasures", []):
		var treasure_id := str(treasure.get("treasure_id", ""))
		var treasure_key := "%d,%d" % [int(treasure.get("q", 0)), int(treasure.get("r", 0))]
		if treasure_id == "" or treasure_ids.has(treasure_id): errors.append("invalid or duplicate treasure " + treasure_id)
		treasure_ids[treasure_id] = true
		if not tile_keys.has(treasure_key): errors.append("treasure outside map " + treasure_id)
		elif bool(tile_keys[treasure_key].get("movement_blocked", false)): errors.append("treasure on blocked tile " + treasure_id)
		if str(treasure.get("visibility", "")) not in ["VISIBLE", "HIDDEN"]: errors.append("invalid treasure visibility " + treasure_id)
		if str(treasure.get("landmark_key", "")).is_empty() or treasure.has("landmark"): errors.append("treasure localization contract invalid " + treasure_id)
		if treasure.get("rewards", {}).is_empty(): errors.append("treasure without reward " + treasure_id)
	var patrol_ids: Dictionary = {}
	for patrol in definition.get("patrols", []):
		var encounter_id := str(patrol.get("encounter_id", ""))
		if encounter_id == "" or patrol_ids.has(encounter_id): errors.append("invalid or duplicate patrol " + encounter_id)
		patrol_ids[encounter_id] = true
		if not node_ids.has(encounter_id): errors.append("patrol unknown encounter " + encounter_id)
		var route: Array = patrol.get("patrol_route_hexes", [])
		if route.is_empty(): errors.append("patrol without route " + encounter_id)
		for point in route:
			var coord := Vector2i(int(point.get("q", 0)), int(point.get("r", 0)))
			if not tile_keys.has(HexCoordScript.key(coord)) or bool(tile_keys.get(HexCoordScript.key(coord), {}).get("movement_blocked", false)):
				errors.append("patrol point invalid " + encounter_id)
	var relay_ids: Dictionary = {}
	for relay in definition.get("relays", []):
		var relay_id := str(relay.get("relay_id", ""))
		var relay_key := "%d,%d" % [int(relay.get("q", 0)), int(relay.get("r", 0))]
		if relay_id == "" or relay_ids.has(relay_id): errors.append("invalid or duplicate relay " + relay_id)
		relay_ids[relay_id] = true
		if not tile_keys.has(relay_key) or bool(tile_keys.get(relay_key, {}).get("movement_blocked", false)): errors.append("relay outside map " + relay_id)
	var event_ids: Dictionary = {}
	for event in definition.get("map_events", []):
		var event_id := str(event.get("event_id", ""))
		var event_key := "%d,%d" % [int(event.get("q", 0)), int(event.get("r", 0))]
		if event_id == "" or event_ids.has(event_id): errors.append("invalid or duplicate map event " + event_id)
		event_ids[event_id] = true
		if not tile_keys.has(event_key) or bool(tile_keys.get(event_key, {}).get("movement_blocked", false)): errors.append("event outside map " + event_id)
		if str(event.get("title_key", "")).is_empty() or str(event.get("body_key", "")).is_empty(): errors.append("event localization keys missing " + event_id)
		if event.has("title") or event.has("body"): errors.append("event contains raw localized text " + event_id)
		var choices: Array = event.get("choices", [])
		if choices.size() < 1 or choices.size() > 2: errors.append("event choice count " + event_id)
		for choice in choices:
			if str(choice.get("choice_id", "")).is_empty() or str(choice.get("label_key", "")).is_empty(): errors.append("event choice localization missing " + event_id)
			if choice.has("label"): errors.append("event choice contains raw localized text " + event_id)
	# A visible objective on an isolated island is a broken gameplay promise. Use
	# the exact same grid/can_step/pathfinder authority as both the player and
	# normal-enemy chase logic, so neither side can enter a tile the other side
	# considers illegal and every authored mob, treasure or event is reachable.
	var grid := HexGridScript.new()
	grid.load_tiles(definition.get("tiles", []))
	var start_value: Dictionary = definition.get("start_hex", {"q": 0, "r": 0})
	var start_coord := Vector2i(int(start_value.get("q", 0)), int(start_value.get("r", 0)))
	if not grid.traversable(start_coord):
		errors.append("start hex is not traversable")
	else:
		# Flood the legal component once. Running A* independently for every one of
		# the authored objectives made validation itself a cold-start bottleneck on
		# Web; this is linear in map size and preserves the same can_step authority.
		var connected: Dictionary = {HexCoordScript.key(start_coord): true}
		var frontier: Array[Vector2i] = [start_coord]
		var frontier_index := 0
		while frontier_index < frontier.size():
			var current: Vector2i = frontier[frontier_index]
			frontier_index += 1
			for neighbor in HexCoordScript.neighbors(current):
				var neighbor_key := HexCoordScript.key(neighbor)
				if connected.has(neighbor_key) or not grid.can_step(current, neighbor):
					continue
				connected[neighbor_key] = true
				frontier.append(neighbor)
		var connectivity_targets: Array[Dictionary] = []
		for node in definition.get("nodes", []):
			connectivity_targets.append({"kind": "node", "id": str(node.get("node_id", "")), "q": int(node.get("q", 0)), "r": int(node.get("r", 0))})
		for treasure in definition.get("treasures", []):
			connectivity_targets.append({"kind": "treasure", "id": str(treasure.get("treasure_id", "")), "q": int(treasure.get("q", 0)), "r": int(treasure.get("r", 0))})
		for relay in definition.get("relays", []):
			connectivity_targets.append({"kind": "relay", "id": str(relay.get("relay_id", "")), "q": int(relay.get("q", 0)), "r": int(relay.get("r", 0))})
		for event in definition.get("map_events", []):
			connectivity_targets.append({"kind": "event", "id": str(event.get("event_id", "")), "q": int(event.get("q", 0)), "r": int(event.get("r", 0))})
		for patrol in definition.get("patrols", []):
			var patrol_id := str(patrol.get("encounter_id", ""))
			for point_index in range((patrol.get("patrol_route_hexes", []) as Array).size()):
				var point: Dictionary = patrol.get("patrol_route_hexes", [])[point_index]
				connectivity_targets.append({"kind": "patrol", "id": "%s[%d]" % [patrol_id, point_index], "q": int(point.get("q", 0)), "r": int(point.get("r", 0))})
		for target in connectivity_targets:
			var target_coord := Vector2i(int(target.q), int(target.r))
			if grid.traversable(target_coord) and not connected.has(HexCoordScript.key(target_coord)):
				errors.append("unreachable %s %s" % [str(target.kind), str(target.id)])
	return errors

static func node_for_stage(definition: Dictionary, stage_id: String) -> Dictionary:
	for node in definition.get("nodes", []):
		if str(node.get("stage_id", "")) == stage_id: return node
	return {}

static func node_by_id(definition: Dictionary, node_id: String) -> Dictionary:
	for node in definition.get("nodes", []):
		if str(node.get("node_id", "")) == node_id: return node
	return {}
