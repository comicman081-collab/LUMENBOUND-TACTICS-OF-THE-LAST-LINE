class_name BattleSpriteLibrary
extends RefCounted

const PACK_ROOTS := {
	"CHR001": {"root": "res://assets/runtime_web/combat/CHR001", "view": "THREE_QUARTER_RIGHT_DOWN_30", "facing": "SEPARATE_LEFT_RIGHT"},
	"CHR002": {"root": "res://assets/runtime_web/combat/CHR002", "view": "THREE_QUARTER_RIGHT_DOWN_30"},
	"CHR003": {"root": "res://assets/runtime_web/combat/CHR003", "view": "THREE_QUARTER_RIGHT_DOWN_30"},
	"CHR004": {"root": "res://assets/runtime_web/combat/CHR004", "view": "THREE_QUARTER_RIGHT_DOWN_30"},
	"CHR005": {"root": "res://assets/runtime_web/combat/CHR005", "view": "THREE_QUARTER_RIGHT_DOWN_30"},
	"CHR006": {"root": "res://assets/runtime_web/combat/CHR006", "view": "THREE_QUARTER_RIGHT_DOWN_30", "facing": "SEPARATE_LEFT_RIGHT"},
	"CHR007": {"root": "res://assets/runtime_web/combat/CHR007", "view": "THREE_QUARTER_RIGHT_DOWN_30", "facing": "SEPARATE_LEFT_RIGHT"},
	"CHR008": {"root": "res://assets/runtime_web/combat/CHR008", "view": "THREE_QUARTER_RIGHT_DOWN_30", "facing": "SEPARATE_LEFT_RIGHT"},
	"ENM001": {"root": "res://assets/runtime_web/combat/ENM001", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
	"ENM002": {"root": "res://assets/runtime_web/combat/ENM002", "view": "THREE_QUARTER_LEFT_DOWN_30"},
	"ENM003": {"root": "res://assets/runtime_web/combat/ENM003", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
	"ENM004": {"root": "res://assets/runtime_web/combat/ENM004", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
	"ENM005": {"root": "res://assets/runtime_web/combat/ENM005", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
	"ENM006": {"root": "res://assets/runtime_web/combat/ENM006", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
	"ENM007": {"root": "res://assets/runtime_web/combat/ENM007", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
	"ENM008": {"root": "res://assets/runtime_web/combat/ENM008", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
	"ENM009": {"root": "res://assets/runtime_web/combat/ENM009", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
	"BOSS001": {"root": "res://assets/runtime_web/combat/BOSS001", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
	"BOSS002": {"root": "res://assets/runtime_web/combat/BOSS002", "view": "THREE_QUARTER_LEFT_DOWN_30", "facing": "MIRROR_SAFE"},
}

var manifests: Dictionary = {}
var frames: Dictionary = {}
var load_error := ""

func load_pack() -> bool:
	manifests.clear()
	frames.clear()
	load_error = ""
	var errors: Array[String] = []
	var pack_roots: Dictionary = PACK_ROOTS.duplicate(true)
	for definition_value in DataRegistry.list_of("characters") + DataRegistry.list_of("enemies"):
		var definition: Dictionary = definition_value
		var entity_id := str(definition.get("id", ""))
		if entity_id.is_empty() or pack_roots.has(entity_id):
			continue
		var is_player := entity_id.begins_with("CHR")
		pack_roots[entity_id] = {
			"root": "res://assets/runtime_web/combat/%s" % entity_id,
			"view": "THREE_QUARTER_RIGHT_DOWN_30" if is_player else "THREE_QUARTER_LEFT_DOWN_30",
			"facing": "SEPARATE_LEFT_RIGHT" if is_player else "MIRROR_SAFE",
		}
	for character_id in pack_roots:
		var config: Dictionary = pack_roots[character_id]
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
	var atlas_texture: Texture2D = null
	var atlas_frame_size := Vector2(512, 512)
	var atlas_columns := int(manifest.get("atlas_columns", 0))
	if not str(manifest.get("atlas_path", "")).is_empty():
		var atlas_resource := _load_runtime_texture(pack_root + "/" + str(manifest.atlas_path))
		if not atlas_resource is Texture2D: return "%s:ATLAS_LOAD_FAILED" % character_id
		atlas_texture = atlas_resource
		var frame_size: Array = manifest.get("frame_size", [512, 512])
		atlas_frame_size = Vector2(float(frame_size[0]), float(frame_size[1]))
		if atlas_columns <= 0: return "%s:ATLAS_COLUMNS_INVALID" % character_id
	for animation_name in manifest.get("animations", {}):
		var textures: Array[Texture2D] = []
		var definition: Dictionary = manifest.animations[animation_name]
		if atlas_texture != null:
			for frame_index in definition.get("frame_indices", []):
				var cell := int(frame_index)
				var texture := AtlasTexture.new()
				texture.atlas = atlas_texture
				texture.region = Rect2(float(cell % atlas_columns) * atlas_frame_size.x, float(cell / atlas_columns) * atlas_frame_size.y, atlas_frame_size.x, atlas_frame_size.y)
				textures.append(texture)
		else:
			for relative_path in definition.get("frame_paths", []):
				var resource = load(pack_root + "/" + str(relative_path))
				if not resource is Texture2D: return "%s:FRAME_LOAD_FAILED:%s" % [character_id, relative_path]
				textures.append(resource)
		if textures.is_empty(): return "%s:ANIMATION_EMPTY:%s" % [character_id, animation_name]
		character_frames[animation_name] = textures
	manifests[character_id] = manifest
	frames[character_id] = character_frames
	return ""

func _load_runtime_texture(path: String) -> Texture2D:
	## A freshly synchronized PNG may not have a local editor import cache yet.
	## A stale Godot .import descriptor reports valid=false while the immutable
	## runtime PNG itself is still valid. Decode that exact PNG buffer first so
	## headless QA does not emit a failed ResourceLoader error before applying
	## the normal imported-resource path. This is an import-cache recovery only:
	## it never replaces entity artwork with a card, silhouette, or placeholder.
	var import_descriptor_path := path + ".import"
	if FileAccess.file_exists(import_descriptor_path):
		var import_descriptor := FileAccess.get_file_as_string(import_descriptor_path)
		if import_descriptor.contains("valid=false"):
			var raw_png := FileAccess.get_file_as_bytes(path)
			var raw_image := Image.new()
			var decode_error := raw_image.load_png_from_buffer(raw_png)
			if decode_error == OK and not raw_image.is_empty():
				return ImageTexture.create_from_image(raw_image)
	if ResourceLoader.exists(path):
		var imported = load(path)
		if imported is Texture2D: return imported
	var image := Image.load_from_file(path)
	if image == null or image.is_empty(): return null
	return ImageTexture.create_from_image(image)

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

func source_faces_right(character_id: String) -> bool:
	# The authored view is the single runtime orientation authority. BattleView
	# compares it with the unit team and mirrors only when the source and desired
	# enemy-facing direction differ. This keeps source packs reusable without
	# allowing a left-facing player or right-facing enemy into combat.
	var view := str(manifests.get(character_id, {}).get("view", "THREE_QUARTER_RIGHT_DOWN_30"))
	return view.contains("RIGHT")

func frame_canvas_size(character_id: String) -> Vector2:
	var value: Array = manifests.get(character_id, {}).get("frame_size", [512, 512])
	return Vector2(float(value[0]), float(value[1]))

func supports_character(character_id: String) -> bool:
	return manifests.has(character_id) and frames.has(character_id)
