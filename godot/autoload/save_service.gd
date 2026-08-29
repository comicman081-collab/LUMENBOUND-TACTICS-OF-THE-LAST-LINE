extends Node

const ChapterMapLoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const ChapterMapProgressScript := preload("res://chapter_map/model/chapter_map_progress.gd")
const MapExplorationServiceScript := preload("res://chapter_map/model/map_exploration_service.gd")
const MapSimulationScript := preload("res://chapter_map/model/map_simulation.gd")
const RelayServiceScript := preload("res://relay/relay_service.gd")

const SAVE_PATH := "user://save_v1.json"
const BACKUP_PATH := "user://save_v1.backup.json"
const TEMP_PATH := "user://save_v1.tmp.json"
const SOAK_SANDBOX_SAVE_PATH := "user://r15_soak_sandbox/save_v1.json"
const SOAK_SANDBOX_BACKUP_PATH := "user://r15_soak_sandbox/save_v1.backup.json"
const SOAK_SANDBOX_TEMP_PATH := "user://r15_soak_sandbox/save_v1.tmp.json"

# The Web soak harness is opt-in and deliberately uses its own user:// tree.
# It must never load, migrate, overwrite, back up, hash, or reset the user's
# production save files.  The query flag is read only in Web builds.
var soak_sandbox_enabled := false
var soak_sandbox_session := "default"
var soak_sandbox_audit := {
	"sandbox_active": false,
	"sandbox_session": "default",
	"sandbox_path_resolve_count": 0,
	"production_path_resolve_count": 0,
	"production_read_attempt_count": 0,
	"production_write_attempt_count": 0,
	"production_backup_attempt_count": 0,
	"production_reset_attempt_count": 0,
}

func _ready() -> void:
	soak_sandbox_enabled = _detect_web_soak_sandbox()
	soak_sandbox_session = _detect_web_soak_sandbox_session()
	soak_sandbox_audit.sandbox_active = soak_sandbox_enabled
	soak_sandbox_audit.sandbox_session = soak_sandbox_session
	if soak_sandbox_enabled:
		print("R15_SAVE_SANDBOX_ACTIVE session=%s paths=%s/*" % [soak_sandbox_session, _sandbox_directory_path(soak_sandbox_session)])

func is_soak_sandbox_enabled() -> bool:
	return soak_sandbox_enabled

static func save_paths_for(sandbox_enabled: bool, sandbox_session := "default") -> Dictionary:
	if sandbox_enabled:
		var safe_session := sanitize_sandbox_session(sandbox_session)
		if safe_session == "default":
			return {"save": SOAK_SANDBOX_SAVE_PATH, "backup": SOAK_SANDBOX_BACKUP_PATH, "temp": SOAK_SANDBOX_TEMP_PATH}
		var directory := _sandbox_directory_path(safe_session)
		return {"save": directory.path_join("save_v1.json"), "backup": directory.path_join("save_v1.backup.json"), "temp": directory.path_join("save_v1.tmp.json")}
	return {"save": SAVE_PATH, "backup": BACKUP_PATH, "temp": TEMP_PATH}

static func sanitize_sandbox_session(value: Variant) -> String:
	var candidate := str(value).strip_edges()
	if candidate.is_empty() or candidate == "default":
		return "default"
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]{1,48}$")
	return candidate if pattern.search(candidate) != null else "default"

static func _sandbox_directory_path(sandbox_session := "default") -> String:
	var safe_session := sanitize_sandbox_session(sandbox_session)
	return "user://r15_soak_sandbox" if safe_session == "default" else "user://r15_soak_sandbox/" + safe_session

func sandbox_audit_summary() -> Dictionary:
	return soak_sandbox_audit.duplicate(true)

func _active_paths(operation := "resolve") -> Dictionary:
	var paths := save_paths_for(soak_sandbox_enabled, soak_sandbox_session)
	if soak_sandbox_enabled:
		soak_sandbox_audit.sandbox_path_resolve_count = int(soak_sandbox_audit.sandbox_path_resolve_count) + 1
		var resolves_production := str(paths.save) == SAVE_PATH or str(paths.backup) == BACKUP_PATH or str(paths.temp) == TEMP_PATH
		if resolves_production:
			soak_sandbox_audit.production_path_resolve_count = int(soak_sandbox_audit.production_path_resolve_count) + 1
			match operation:
				"read": soak_sandbox_audit.production_read_attempt_count = int(soak_sandbox_audit.production_read_attempt_count) + 1
				"write": soak_sandbox_audit.production_write_attempt_count = int(soak_sandbox_audit.production_write_attempt_count) + 1
				"backup": soak_sandbox_audit.production_backup_attempt_count = int(soak_sandbox_audit.production_backup_attempt_count) + 1
				"reset": soak_sandbox_audit.production_reset_attempt_count = int(soak_sandbox_audit.production_reset_attempt_count) + 1
	return paths

func _ensure_active_save_directory() -> bool:
	# The normal save root is provided by Godot.  The opt-in Web soak save lives
	# in a child directory, which must be created before the first atomic write.
	# This branch never resolves or touches the production save namespace.
	if not soak_sandbox_enabled:
		return true
	var sandbox_directory := ProjectSettings.globalize_path(_sandbox_directory_path(soak_sandbox_session))
	var result := DirAccess.make_dir_recursive_absolute(sandbox_directory)
	return result == OK or result == ERR_ALREADY_EXISTS

func _detect_web_soak_sandbox() -> bool:
	if not OS.has_feature("web"):
		return false
	# JavaScriptBridge is Web-only at runtime. The guarded call preserves native
	# and headless execution while keeping URL parsing out of gameplay systems.
	# Godot's Web bridge marshals URLSearchParams results reliably as strings;
	# a JavaScript boolean can otherwise arrive as a non-bool Variant.
	var value = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('r15-save-sandbox')", true)
	return str(value) == "1"

func _detect_web_soak_sandbox_session() -> String:
	if not OS.has_feature("web") or not soak_sandbox_enabled:
		return "default"
	var value = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('r15-save-sandbox-session')", true)
	return sanitize_sandbox_session(value)

func save_game() -> GameResult:
	if not _ensure_active_save_directory():
		return _finish(false, "save sandbox directory could not be created")
	var paths := _active_paths("write")
	var save_path := str(paths.save)
	var backup_path := str(paths.backup)
	var temp_path := str(paths.temp)
	AppState.profile.settings = SettingsService.persisted_values()
	var payload: Dictionary = AppState.profile.duplicate(true)
	payload.erase("checksum")
	var checksum := _checksum_for(payload)
	payload["checksum"] = checksum
	var encoded := JSON.stringify(payload, "  ")
	var temp := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp == null:
		return _finish(false, "temporary save could not be opened")
	temp.store_string(encoded)
	temp.flush()
	temp.close()
	var verified := _read_valid(temp_path)
	if not verified.ok:
		return _finish(false, "temporary save verification failed: %s" % verified.error)
	var save_abs := ProjectSettings.globalize_path(save_path)
	var backup_abs := ProjectSettings.globalize_path(backup_path)
	var temp_abs := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(save_path):
		# In sandbox mode this always remains below user://r15_soak_sandbox/.
		_active_paths("backup")
		DirAccess.copy_absolute(save_abs, backup_abs)
		DirAccess.remove_absolute(save_abs)
	var rename_error := DirAccess.rename_absolute(temp_abs, save_abs)
	if rename_error != OK:
		return _finish(false, "atomic rename failed: %s" % error_string(rename_error))
	return _finish(true, "saved")

func load_game() -> GameResult:
	var paths := _active_paths("read")
	var primary := _read_valid(str(paths.save))
	if primary.ok:
		var migrated := _migrate(primary.value)
		if migrated.ok:
			AppState.apply_loaded(_sanitize(migrated.value))
			return GameResult.success("primary")
	var backup := _read_valid(str(paths.backup))
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
		elif version == 5:
			var pulse_definition: Dictionary = ChapterMapLoaderScript.load_map("CH01_MAP")
			var pulse_maps: Dictionary = data.get("chapter_map", {})
			var pulse_state: Dictionary = pulse_maps.get("CH01_MAP", ChapterMapProgressScript.create_default(pulse_definition))
			MapExplorationServiceScript.ensure_state(pulse_state, pulse_definition)
			pulse_maps["CH01_MAP"] = pulse_state
			data["chapter_map"] = pulse_maps
			data["save_schema_version"] = 6
			version = 6
		elif version == 6:
			# Chapter progress became data-driven so new chapters can be appended
			# without rewriting the player's existing CH01 progress or granting
			# roster/reward state. Map state remains lazy until that chapter unlocks.
			if not data.has("chapter_progress"): data["chapter_progress"] = {}
			var first_number := 999999
			var first_chapter_id := "CH01"
			for chapter_value in DataRegistry.list_of("chapters"):
				var chapter: Dictionary = chapter_value
				if int(chapter.get("number", first_number)) < first_number:
					first_number = int(chapter.get("number", first_number))
					first_chapter_id = str(chapter.get("id", first_chapter_id))
			for chapter_value in DataRegistry.list_of("chapters"):
				var chapter: Dictionary = chapter_value
				var chapter_id := str(chapter.get("id", ""))
				if chapter_id.is_empty(): continue
				if not data.chapter_progress.has(chapter_id):
					data.chapter_progress[chapter_id] = {"normal_highest": 0, "hard_unlocked": false, "unlocked": chapter_id == first_chapter_id}
				var progress: Dictionary = data.chapter_progress[chapter_id]
				if not progress.has("normal_highest"): progress["normal_highest"] = 0
				if not progress.has("hard_unlocked"): progress["hard_unlocked"] = false
				if not progress.has("unlocked"): progress["unlocked"] = chapter_id == first_chapter_id
			data["save_schema_version"] = 7
			version = 7
		elif version == 7:
			# Relay runs are additive and offline.  Migrate only their own ledger;
			# never touch stage stars, roster unlocks, map state, or inventory here.
			RelayServiceScript.ensure_profile(data)
			data["save_schema_version"] = 8
			version = 8
		elif version == 8:
			# Campaign 20 deliberately reserves CHR026-044 for later routes.  A
			# player who already owned one of those IDs must keep it; new/locked
			# entries remain visibly reserved instead of being silently granted.
			var roster: Dictionary = data.get("roster", {})
			for character_id_value in roster.keys():
				var character_id := str(character_id_value)
				var entry: Dictionary = roster[character_id]
				var character := DataRegistry.character(character_id)
				var source := str(character.get("acquisition_source", "RESERVED"))
				if bool(entry.get("unlocked", false)):
					entry["acquisition_status"] = "LEGACY_OWNED" if source == "RESERVED" else "OWNED"
				else:
					entry["acquisition_status"] = "LOCKED_ACQUIRABLE" if source == "EVENT_CONTACT" else "RESERVED_FUTURE"
				roster[character_id] = entry
			data["roster"] = roster
			data["legacy_retired_stage_ids"] = [
				"CH01-H06", "CH01-H07", "CH01-H08", "CH01-H09", "CH01-H10",
				"CH02-H06", "CH02-H07", "CH02-H08", "CH02-H09", "CH02-H10",
			]
			data["save_schema_version"] = 9
			version = 9
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
	var unknown_nodes: Array = []
	var unknown_treasures: Array = []
	if not data.has("chapter_map"): data["chapter_map"] = {}
	var known_map_ids: Dictionary = {}
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var chapter_id := str(chapter.get("id", ""))
		var map_id := str(chapter.get("map_id", chapter_id + "_MAP"))
		known_map_ids[map_id] = true
	for map_id_value in data.chapter_map.keys().duplicate():
		var map_id := str(map_id_value)
		if not known_map_ids.has(map_id):
			data.chapter_map.erase(map_id)
			continue
		var definition: Dictionary = ChapterMapLoaderScript.load_map(map_id)
		var map_state: Dictionary = data.chapter_map.get(map_id, {})
		MapExplorationServiceScript.ensure_state(map_state, definition)
		var known_nodes: Dictionary = {}
		for node in definition.get("nodes", []): known_nodes[str(node.node_id)] = true
		for node_id in map_state.get("cleared_nodes", []).duplicate():
			if not known_nodes.has(str(node_id)):
				unknown_nodes.append(str(node_id))
				map_state.cleared_nodes.erase(node_id)
		if str(map_state.get("last_selected_node", "")) != "" and not known_nodes.has(str(map_state.last_selected_node)):
			unknown_nodes.append(str(map_state.last_selected_node))
			map_state.last_selected_node = ""
		var known_treasures: Dictionary = {}
		for treasure in definition.get("treasures", []): known_treasures[str(treasure.get("treasure_id", ""))] = true
		for treasure_id in map_state.get("claimed_treasures", []).duplicate():
			if not known_treasures.has(str(treasure_id)):
				unknown_treasures.append(str(treasure_id))
				map_state.claimed_treasures.erase(treasure_id)
				map_state.treasure_states.erase(treasure_id)
		for treasure_id in map_state.get("revealed_treasures", []).duplicate():
			if not known_treasures.has(str(treasure_id)):
				if not unknown_treasures.has(str(treasure_id)): unknown_treasures.append(str(treasure_id))
				map_state.revealed_treasures.erase(treasure_id)
		data.chapter_map[map_id] = map_state
	data["quarantined_unknown_map_node_ids"] = unknown_nodes
	data["quarantined_unknown_treasure_ids"] = unknown_treasures
	return data

func export_save_json() -> String:
	return JSON.stringify(AppState.profile, "  ")

func reset_save_files() -> void:
	var paths := _active_paths("reset")
	for path in [str(paths.save), str(paths.backup), str(paths.temp)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	AppState.new_game()

func _finish(success: bool, message: String) -> GameResult:
	EventBus.save_completed.emit(success, message)
	return GameResult.success(message) if success else GameResult.failure(message)
