class_name ChapterMapLoader
extends RefCounted

const COMPILED_ROOT := "res://data/compiled/chapter_maps/"
const MacroWorldGeneratorScript := preload("res://chapter_map/model/macro_world_generator.gd")
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
	return errors

static func node_for_stage(definition: Dictionary, stage_id: String) -> Dictionary:
	for node in definition.get("nodes", []):
		if str(node.get("stage_id", "")) == stage_id: return node
	return {}

static func node_by_id(definition: Dictionary, node_id: String) -> Dictionary:
	for node in definition.get("nodes", []):
		if str(node.get("node_id", "")) == node_id: return node
	return {}
