class_name BattleSpriteLibrary
extends RefCounted

const PACK_ROOTS := {
	"CHR001": {"root": "res://assets/runtime_web/combat/CHR001", "view": "THREE_QUARTER_RIGHT_DOWN_30", "facing": "SEPARATE_LEFT_RIGHT"},
	"CHR002": {"root": "res://assets/runtime_web/combat/CHR002", "view": "THREE_QUARTER_RIGHT_DOWN_30"},
	"CHR003": {"root": "res://assets/runtime_web/combat/CHR003", "view": "THREE_QUARTER_RIGHT_DOWN_30"},
	"CHR004": {"root": "res://assets/runtime_web/combat/CHR004", "view": "THREE_QUARTER_RIGHT_DOWN_30"},
	"CHR005": {"root": "res://assets/runtime_web/combat/CHR005", "view": "THREE_QUARTER_RIGHT_DOWN_30"},
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

# CHR006–008 do not yet have preserved multi-frame combat source packs. Their
# project-owned transparent roster cards are still packaged for formation and
# roster screens, so turn those cards into stable battle canvases at runtime
# instead of ever falling back to code-drawn people. The renderer keeps these
# explicitly marked as card-source presentation until authored SD packs replace
# them; no image is duplicated into the Web PCK.
const RUNTIME_CARD_PACKS := {
	"CHR006": {"path": "res://assets/runtime_web/characters/CHR006_card_384x576.png", "view": "THREE_QUARTER_RIGHT_DOWN_30", "facing": "SEPARATE_LEFT_RIGHT"},
	"CHR007": {"path": "res://assets/runtime_web/characters/CHR007_card_384x576.png", "view": "THREE_QUARTER_RIGHT_DOWN_30", "facing": "SEPARATE_LEFT_RIGHT"},
	"CHR008": {"path": "res://assets/runtime_web/characters/CHR008_card_384x576.png", "view": "THREE_QUARTER_RIGHT_DOWN_30", "facing": "SEPARATE_LEFT_RIGHT"},
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
	for character_id in RUNTIME_CARD_PACKS:
		var card_config: Dictionary = RUNTIME_CARD_PACKS[character_id]
		var card_error := _load_runtime_card(str(character_id), str(card_config.path), str(card_config.view), str(card_config.facing))
		if not card_error.is_empty(): errors.append(card_error)
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
		var atlas_resource = load(pack_root + "/" + str(manifest.atlas_path))
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

func _load_runtime_card(character_id: String, path: String, expected_view: String, expected_facing: String) -> String:
	var source = load(path)
	if not source is Texture2D: return "%s:CARD_SOURCE_LOAD_FAILED" % character_id
	var source_texture: Texture2D = source
	var source_image: Image = source_texture.get_image()
	if source_image == null or source_image.is_empty(): return "%s:CARD_SOURCE_IMAGE_FAILED" % character_id
	# Preserve the portrait's original proportions in a common 512px battle
	# canvas; doing this at runtime reuses the already packaged source card.
	source_image.resize(288, 432, Image.INTERPOLATE_LANCZOS)
	var canvas := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	canvas.blend_rect(source_image, Rect2i(0, 0, source_image.get_width(), source_image.get_height()), Vector2i(112, 19))
	var texture := ImageTexture.create_from_image(canvas)
	if texture == null: return "%s:CARD_CANVAS_CREATE_FAILED" % character_id
	var animation_defs := {}
	for animation_name in ["idle", "move", "basic_attack", "normal_skill", "ultimate", "hit", "down", "victory", "stun"]:
		animation_defs[animation_name] = {"fps": 12, "loop": animation_name in ["idle", "move", "stun"], "card_source": true}
	var character_frames := {}
	for animation_name in animation_defs:
		character_frames[animation_name] = [texture]
	manifests[character_id] = {
		"asset_id": "runtime_card_battle_%s" % character_id.to_lower(),
		"character_id": character_id,
		"status": "RUNTIME_CARD_STATIC_PRESENTATION",
		"source_path": path,
		"frame_size": [512, 512],
		"head_anchor": [0.5, 0.12],
		"foot_anchor": [0.5, 0.88],
		"view": expected_view,
		"facing_policy": expected_facing,
		"animations": animation_defs,
	}
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

func frame_canvas_size(character_id: String) -> Vector2:
	var value: Array = manifests.get(character_id, {}).get("frame_size", [512, 512])
	return Vector2(float(value[0]), float(value[1]))

func supports_character(character_id: String) -> bool:
	return manifests.has(character_id) and frames.has(character_id)
