class_name BattleSpriteLibrary
extends RefCounted

const PACK_ROOTS := {
	"CHR001": {"root": "res://assets/art/sd/CHR001", "view": "THREE_QUARTER_RIGHT_DOWN_30", "facing": "SEPARATE_LEFT_RIGHT"},
	"CHR002": {"root": "res://assets/generated_import/characters/sd_chr002_roan_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30"},
	"CHR003": {"root": "res://assets/generated_import/characters/sd_chr003_narin_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30"},
	"CHR004": {"root": "res://assets/generated_import/characters/sd_chr004_eda_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30"},
	"CHR005": {"root": "res://assets/generated_import/characters/sd_chr005_soren_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30"},
	"CHR008": {"root": "res://assets/art/sd/CHR008", "view": "THREE_QUARTER_RIGHT_DOWN_30", "facing": "SEPARATE_LEFT_RIGHT"},
	"ENM001": {"root": "res://assets/art/enemies/ENM001", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
	"ENM002": {"root": "res://assets/generated_import/enemies/sd_enm002_arc_mote_combat_r28_dev", "view": "THREE_QUARTER_LEFT_DOWN_30"},
	"ENM007": {"root": "res://assets/art/enemies/ENM007", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
	"BOSS001": {"root": "res://assets/art/bosses/BOSS001", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
}

var manifests: Dictionary = {}
var frames: Dictionary = {}
var load_error := ""

func load_pack() -> bool:
	manifests.clear()
	frames.clear()
	load_error = ""
	var errors: Array[String] = []
	for character_id in PACK_ROOTS:
		var config: Dictionary = PACK_ROOTS[character_id]
		var error := _load_character(str(character_id), str(config.root), str(config.view), str(config.get("facing", "SEPARATE_LEFT_RIGHT")))
		if not error.is_empty(): errors.append(error)
	load_error = ";".join(errors)
	return not manifests.is_empty()

func _load_character(character_id: String, pack_root: String, expected_view: String, expected_facing: String) -> String:
	var manifest_path := pack_root + "/animation_manifest.json"
	if not FileAccess.file_exists(manifest_path): return "%s:MANIFEST_MISSING" % character_id
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null: return "%s:MANIFEST_OPEN_FAILED" % character_id
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return "%s:MANIFEST_PARSE_FAILED" % character_id
	var manifest: Dictionary = parsed
	if str(manifest.get("character_id", "")) != character_id: return "%s:CHARACTER_ID_MISMATCH" % character_id
	if manifest.get("view", "") != expected_view: return "%s:VIEW_CONTRACT_MISMATCH" % character_id
	if manifest.get("facing_policy", "") != expected_facing: return "%s:FACING_POLICY_MISMATCH" % character_id
	var character_frames: Dictionary = {}
	for animation_name in manifest.get("animations", {}):
		var textures: Array[Texture2D] = []
		var definition: Dictionary = manifest.animations[animation_name]
		for relative_path in definition.get("frame_paths", []):
			var resource = load(pack_root + "/" + str(relative_path))
			if not resource is Texture2D: return "%s:FRAME_LOAD_FAILED:%s" % [character_id, relative_path]
			textures.append(resource)
		character_frames[animation_name] = textures
	manifests[character_id] = manifest
	frames[character_id] = character_frames
	return ""

func has_animation(character_id: String, animation_name: String) -> bool:
	return frames.has(character_id) and frames[character_id].has(animation_name) and not frames[character_id][animation_name].is_empty()

func texture_at(character_id: String, animation_name: String, elapsed: float) -> Texture2D:
	if not has_animation(character_id, animation_name): return null
	var definition: Dictionary = manifests[character_id].animations.get(animation_name, {})
	var textures: Array = frames[character_id][animation_name]
	var fps := maxf(1.0, float(definition.get("fps", 12)))
	var index := int(floor(elapsed * fps))
	if definition.get("loop", false): index %= textures.size()
	else: index = mini(index, textures.size() - 1)
	return textures[index]

func duration(character_id: String, animation_name: String) -> float:
	if not has_animation(character_id, animation_name): return 0.0
	var definition: Dictionary = manifests[character_id].animations.get(animation_name, {})
	return float(frames[character_id][animation_name].size()) / maxf(1.0, float(definition.get("fps", 12)))

func is_looping(character_id: String, animation_name: String) -> bool:
	return bool(manifests.get(character_id, {}).get("animations", {}).get(animation_name, {}).get("loop", false))

func head_anchor(character_id: String) -> Vector2:
	var value: Array = manifests.get(character_id, {}).get("head_anchor", [0.5, 0.08])
	return Vector2(float(value[0]), float(value[1]))

func supports_character(character_id: String) -> bool:
	return manifests.has(character_id) and frames.has(character_id)
