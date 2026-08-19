class_name ChapterMapLoader
extends RefCounted

const COMPILED_ROOT := "res://data/compiled/chapter_maps/"
const MacroWorldGeneratorScript := preload("res://chapter_map/model/macro_world_generator.gd")
const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
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
	if normal != 10: errors.append("NORMAL node count %d" % normal)
	if hard != 5: errors.append("HARD node count %d" % hard)
	var treasure_ids: Dictionary = {}
	for treasure in definition.get("treasures", []):
		var treasure_id := str(treasure.get("treasure_id", ""))
		var treasure_key := "%d,%d" % [int(treasure.get("q", 0)), int(treasure.get("r", 0))]
		if treasure_id == "" or treasure_ids.has(treasure_id): errors.append("invalid or duplicate treasure " + treasure_id)
		treasure_ids[treasure_id] = true
		if not tile_keys.has(treasure_key): errors.append("treasure outside map " + treasure_id)
		elif bool(tile_keys[treasure_key].get("movement_blocked", false)): errors.append("treasure on blocked tile " + treasure_id)
		if str(treasure.get("visibility", "")) not in ["VISIBLE", "HIDDEN"]: errors.append("invalid treasure visibility " + treasure_id)
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
		if event.get("choices", []).size() < 1 or event.get("choices", []).size() > 2: errors.append("event choice count " + event_id)
	return errors

static func node_for_stage(definition: Dictionary, stage_id: String) -> Dictionary:
	for node in definition.get("nodes", []):
		if str(node.get("stage_id", "")) == stage_id: return node
	return {}

static func node_by_id(definition: Dictionary, node_id: String) -> Dictionary:
	for node in definition.get("nodes", []):
		if str(node.get("node_id", "")) == node_id: return node
	return {}
