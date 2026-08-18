class_name ProjectileSpriteLibrary
extends RefCounted

const PACK_ROOTS := {
	"CHR001": "res://assets/generated_import/projectiles/proj_chr001_teal_guard_wave_r28",
	"CHR002": "res://assets/generated_import/projectiles/proj_chr002_coral_blade_arc_r28",
	"CHR003": "res://assets/generated_import/projectiles/proj_chr003_ice_rifle_tracer_r28",
	"CHR004": "res://assets/generated_import/projectiles/proj_chr004_magenta_energy_bolt_r28",
	"CHR005": "res://assets/generated_import/projectiles/proj_chr005_emerald_cannon_orb_r28",
	"ENM001": "res://assets/generated_import/projectiles/proj_enm001_crystal_claw_r28",
	"ENM002": "res://assets/generated_import/projectiles/proj_enm002_arc_mote_r28",
}

var manifests: Dictionary = {}
var frames: Dictionary = {}
var load_error := ""

func load_pack() -> bool:
	manifests.clear()
	frames.clear()
	var errors: Array[String] = []
	for source_id in PACK_ROOTS:
		var error := _load_projectile(str(source_id), str(PACK_ROOTS[source_id]))
		if not error.is_empty(): errors.append(error)
	load_error = ";".join(errors)
	return not manifests.is_empty()

func _load_projectile(source_id: String, pack_root: String) -> String:
	var manifest_path := pack_root + "/projectile_manifest.json"
	if not FileAccess.file_exists(manifest_path): return "%s:MANIFEST_MISSING" % source_id
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null: return "%s:MANIFEST_OPEN_FAILED" % source_id
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return "%s:MANIFEST_PARSE_FAILED" % source_id
	var manifest: Dictionary = parsed
	if str(manifest.get("source_id", "")) != source_id: return "%s:SOURCE_ID_MISMATCH" % source_id
	if int(manifest.get("frames", 0)) != 8: return "%s:FRAME_COUNT_MISMATCH" % source_id
	var textures: Array[Texture2D] = []
	for relative_path in manifest.get("frame_paths", []):
		var resource = load(pack_root + "/" + str(relative_path))
		if not resource is Texture2D: return "%s:FRAME_LOAD_FAILED:%s" % [source_id, relative_path]
		textures.append(resource)
	if textures.size() != 8: return "%s:TEXTURE_COUNT_MISMATCH" % source_id
	manifests[source_id] = manifest
	frames[source_id] = textures
	return ""

func supports_source(source_id: String) -> bool:
	return manifests.has(source_id) and frames.has(source_id)

func texture_at(source_id: String, elapsed: float) -> Texture2D:
	if not supports_source(source_id): return null
	var textures: Array = frames[source_id]
	var progress := clampf(elapsed / maxf(.01, duration(source_id)), 0.0, 1.0)
	var index := mini(int(floor(progress * textures.size())), textures.size() - 1)
	return textures[index]

func duration(source_id: String) -> float:
	if not supports_source(source_id): return 0.32
	return float(manifests[source_id].get("flight_duration", .12))

func runtime_size(source_id: String) -> Vector2:
	var value: Array = manifests.get(source_id, {}).get("runtime_size", [80, 64])
	return Vector2(float(value[0]), float(value[1]))
