extends RefCounted

const MANIFEST := "res://data/runtime_texture_integrity.json"
static var verified: Dictionary = {}
static var entries: Dictionary = {}
static var manifest_loaded := false

static func matches(source_path: String, source_sha256: String) -> bool:
	if source_sha256.length() != 64: return false
	var key := source_path + ":" + source_sha256
	if verified.has(key): return true
	var valid := false
	if FileAccess.file_exists(source_path):
		valid = FileAccess.get_sha256(source_path) == source_sha256
	else:
		if not manifest_loaded:
			manifest_loaded = true
			if FileAccess.file_exists(MANIFEST):
				var value = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
				if value is Dictionary and int(value.get("schema_version", 0)) == 1:
					entries = value.get("textures", {})
		var entry: Dictionary = entries.get(source_path, {})
		if str(entry.get("source_sha256", "")) != source_sha256: return false
		var imported_path := str(entry.get("imported_path", ""))
		var imported_hash := str(entry.get("imported_sha256", ""))
		if not imported_path.begins_with("res://.godot/imported/") or imported_hash.length() != 64: return false
		var descriptor := ConfigFile.new()
		if descriptor.load(source_path + ".import") != OK: return false
		if str(descriptor.get_value("remap", "path", "")) != imported_path: return false
		valid = FileAccess.file_exists(imported_path) and FileAccess.get_sha256(imported_path) == imported_hash
	# Packed resources are immutable for the process lifetime. Cache successful
	# validation so repeated ultimates do not SHA-hash megabytes on the main thread.
	if valid: verified[key] = true
	return valid
