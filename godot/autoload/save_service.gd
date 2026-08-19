extends Node

const ChapterMapLoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const ChapterMapProgressScript := preload("res://chapter_map/model/chapter_map_progress.gd")
const MapExplorationServiceScript := preload("res://chapter_map/model/map_exploration_service.gd")
const MapSimulationScript := preload("res://chapter_map/model/map_simulation.gd")

const SAVE_PATH := "user://save_v1.json"
const BACKUP_PATH := "user://save_v1.backup.json"
const TEMP_PATH := "user://save_v1.tmp.json"

func save_game() -> GameResult:
	AppState.profile.settings = SettingsService.values.duplicate(true)
	var payload: Dictionary = AppState.profile.duplicate(true)
	payload.erase("checksum")
	var checksum := _checksum_for(payload)
	payload["checksum"] = checksum
	var encoded := JSON.stringify(payload, "  ")
	var temp := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if temp == null:
		return _finish(false, "temporary save could not be opened")
	temp.store_string(encoded)
	temp.flush()
	temp.close()
	var verified := _read_valid(TEMP_PATH)
	if not verified.ok:
		return _finish(false, "temporary save verification failed: %s" % verified.error)
	var save_abs := ProjectSettings.globalize_path(SAVE_PATH)
	var backup_abs := ProjectSettings.globalize_path(BACKUP_PATH)
	var temp_abs := ProjectSettings.globalize_path(TEMP_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(save_abs, backup_abs)
		DirAccess.remove_absolute(save_abs)
	var rename_error := DirAccess.rename_absolute(temp_abs, save_abs)
	if rename_error != OK:
		return _finish(false, "atomic rename failed: %s" % error_string(rename_error))
	return _finish(true, "saved")

func load_game() -> GameResult:
	var primary := _read_valid(SAVE_PATH)
	if primary.ok:
		var migrated := _migrate(primary.value)
		if migrated.ok:
			AppState.apply_loaded(_sanitize(migrated.value))
			return GameResult.success("primary")
	var backup := _read_valid(BACKUP_PATH)
	if backup.ok:
		var migrated_backup := _migrate(backup.value)
		if migrated_backup.ok:
			AppState.apply_loaded(_sanitize(migrated_backup.value))
			return GameResult.success("backup")
	return GameResult.failure("no valid save; new profile retained")

func _read_valid(path: String) -> GameResult:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return GameResult.failure("missing")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return GameResult.failure("invalid JSON")
	var parsed = parser.data
	if not parsed is Dictionary:
		return GameResult.failure("invalid JSON")
	var stored: String = str(parsed.get("checksum", ""))
	parsed.erase("checksum")
	if stored == "" or stored != _checksum_for(parsed):
		return GameResult.failure("checksum mismatch")
	return GameResult.success(parsed)

func _checksum_for(payload: Dictionary) -> String:
	return JSON.stringify(_canonical_value(payload)).sha256_text()

func _canonical_value(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		var keys: Array = source.keys()
		keys.sort_custom(func(left, right): return str(left) < str(right))
		var normalized: Dictionary = {}
		for key in keys:
			normalized[str(key)] = _canonical_value(source[key])
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for entry in value:
			normalized_array.append(_canonical_value(entry))
		return normalized_array
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value

func _migrate(data: Dictionary) -> GameResult:
	var version := int(data.get("save_schema_version", 0))
	if version > AppState.SAVE_SCHEMA_VERSION:
		return GameResult.failure("save is newer than this build")
	while version < AppState.SAVE_SCHEMA_VERSION:
		if version == 0:
			data["save_schema_version"] = 1
			version = 1
		elif version == 1:
			var definition: Dictionary = ChapterMapLoaderScript.load_map("CH01_MAP")
			data["chapter_map"] = {"CH01_MAP": ChapterMapProgressScript.migrate_from_profile(data, definition)}
			data["save_schema_version"] = 2
			version = 2
		elif version == 2:
			var macro_definition: Dictionary = ChapterMapLoaderScript.load_map("CH01_MAP")
			var chapter_maps: Dictionary = data.get("chapter_map", {})
			var compact_state: Dictionary = chapter_maps.get("CH01_MAP", {})
			chapter_maps["CH01_MAP"] = ChapterMapProgressScript.reanchor_macro_state(compact_state, macro_definition)
			data["chapter_map"] = chapter_maps
			data["save_schema_version"] = 3
			version = 3
		elif version == 3:
			var exploration_definition: Dictionary = ChapterMapLoaderScript.load_map("CH01_MAP")
			var exploration_maps: Dictionary = data.get("chapter_map", {})
			var exploration_state: Dictionary = exploration_maps.get("CH01_MAP", ChapterMapProgressScript.create_default(exploration_definition))
			MapExplorationServiceScript.ensure_state(exploration_state, exploration_definition)
			exploration_maps["CH01_MAP"] = exploration_state
			data["chapter_map"] = exploration_maps
			data["save_schema_version"] = 4
			version = 4
		elif version == 4:
			var dynamic_definition: Dictionary = ChapterMapLoaderScript.load_map("CH01_MAP")
			var dynamic_maps: Dictionary = data.get("chapter_map", {})
			var dynamic_state: Dictionary = dynamic_maps.get("CH01_MAP", ChapterMapProgressScript.create_default(dynamic_definition))
			MapExplorationServiceScript.ensure_state(dynamic_state, dynamic_definition)
			MapSimulationScript.ensure_state(dynamic_state, dynamic_definition)
			dynamic_maps["CH01_MAP"] = dynamic_state
			data["chapter_map"] = dynamic_maps
			data["save_schema_version"] = 5
			version = 5
		else:
			return GameResult.failure("missing migration from %d" % version)
	return GameResult.success(data)

func _sanitize(data: Dictionary) -> Dictionary:
	# Unknown immutable IDs are quarantined, not silently remapped.
	var known_characters: Dictionary = {}
	for entry in DataRegistry.list_of("characters"):
		known_characters[entry.id] = true
	var removed: Array = []
	for character_id in data.get("roster", {}).keys():
		if not known_characters.has(character_id):
			removed.append(character_id)
	for character_id in removed:
		data.roster.erase(character_id)
	data["quarantined_unknown_character_ids"] = removed
	var definition: Dictionary = ChapterMapLoaderScript.load_map("CH01_MAP")
	var known_nodes: Dictionary = {}
	for node in definition.get("nodes", []): known_nodes[str(node.node_id)] = true
	var map_state: Dictionary = data.get("chapter_map", {}).get("CH01_MAP", {})
	MapExplorationServiceScript.ensure_state(map_state, definition)
	var unknown_nodes: Array = []
	for node_id in map_state.get("cleared_nodes", []).duplicate():
		if not known_nodes.has(str(node_id)):
			unknown_nodes.append(str(node_id))
			map_state.cleared_nodes.erase(node_id)
	if str(map_state.get("last_selected_node", "")) != "" and not known_nodes.has(str(map_state.last_selected_node)):
		unknown_nodes.append(str(map_state.last_selected_node))
		map_state.last_selected_node = ""
	data["quarantined_unknown_map_node_ids"] = unknown_nodes
	var known_treasures: Dictionary = {}
	for treasure in definition.get("treasures", []): known_treasures[str(treasure.get("treasure_id", ""))] = true
	var unknown_treasures: Array = []
	for treasure_id in map_state.get("claimed_treasures", []).duplicate():
		if not known_treasures.has(str(treasure_id)):
			unknown_treasures.append(str(treasure_id))
			map_state.claimed_treasures.erase(treasure_id)
			map_state.treasure_states.erase(treasure_id)
	for treasure_id in map_state.get("revealed_treasures", []).duplicate():
		if not known_treasures.has(str(treasure_id)):
			if not unknown_treasures.has(str(treasure_id)): unknown_treasures.append(str(treasure_id))
			map_state.revealed_treasures.erase(treasure_id)
	if not data.has("chapter_map"): data["chapter_map"] = {}
	data.chapter_map["CH01_MAP"] = map_state
	data["quarantined_unknown_treasure_ids"] = unknown_treasures
	return data

func export_save_json() -> String:
	return JSON.stringify(AppState.profile, "  ")

func reset_save_files() -> void:
	for path in [SAVE_PATH, BACKUP_PATH, TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	AppState.new_game()

func _finish(success: bool, message: String) -> GameResult:
	EventBus.save_completed.emit(success, message)
	return GameResult.success(message) if success else GameResult.failure(message)
