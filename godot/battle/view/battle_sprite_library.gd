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
## R13 includes the actual starting five-player party (CHR001 through CHR005),
## the reviewed CHR008 alternate-party slice, and the current common enemy/boss
## group. CHR004 derives from an immutable #00FF00 master and separately
## retained keyed-RGBA source, so a white matte cannot reach a runtime atlas by
## accident. The runtime uses core pages plus one caster ultimate transient
## lease, whose measured peak remains below 72MiB.
const SIGNATURE_REVISION := "r13"
const SIGNATURE_ROOT := "res://assets/runtime_web/combat_signature/" + SIGNATURE_REVISION
const SIGNATURE_APPROVAL_PATH := SIGNATURE_ROOT + "/promotion_approval.json"
const SIGNATURE_ANIMATIONS := ["idle", "ultimate", "hit", "down"]
## Core state pages stay resident for every actor in the current encounter.
## Ultimate pages are an atomic, one-caster transient lease so a full party can
## retain crisp idle/hit/down art without permanently decoding every expensive
## ultimate sheet at once.
const SIGNATURE_CORE_ANIMATIONS := ["idle", "hit", "down"]
const SIGNATURE_HARD_MEMORY_BUDGET_BYTES := 72 * 1024 * 1024

var manifests: Dictionary = {}
var frames: Dictionary = {}
var load_error := ""
## High-density signature cells are deliberately separate from the compact
## all-action atlas.  The active 128px packs remain the mobile baseline while
## CHR001/BOSS001 keep more source density for idle, ultimate, hit, and down.
var signature_manifests: Dictionary = {}
var signature_frames: Dictionary = {}
## Parallel immutable metadata for alpha-tight R5 frames.  R4 stores a full
## 384px cell and therefore falls back to [0, 0, 384, 384] automatically.
## R5 stores a packed texture region plus its original logical-canvas rect.
var signature_frame_metadata: Dictionary = {}
var signature_load_error := ""
var signature_approval: Dictionary = {}
var signature_resident_atlas_bytes := 0
## Signature atlases are an encounter lease, never a global roster preload.
## This list is intentionally kept alongside the live decoded references so
## callers can prove exactly which high-density pages are resident.
var signature_resident_entity_ids: Array[String] = []
var signature_resident_animation_ids_by_entity: Dictionary = {}
var signature_core_resident_atlas_bytes := 0
var signature_transient_ultimate_entity_id := ""

func load_pack(required_ids: Array[String] = []) -> bool:
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
	var ids_to_load: Array[String] = []
	if required_ids.is_empty():
		for character_id in pack_roots:
			ids_to_load.append(str(character_id))
	else:
		for character_id in required_ids:
			if pack_roots.has(character_id) and not ids_to_load.has(character_id):
				ids_to_load.append(character_id)
	for character_id in ids_to_load:
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

func clear_signature_pack() -> void:
	signature_manifests.clear()
	signature_frames.clear()
	signature_frame_metadata.clear()
	signature_load_error = ""
	signature_approval.clear()
	signature_resident_atlas_bytes = 0
	signature_resident_entity_ids.clear()
	signature_resident_animation_ids_by_entity.clear()
	signature_core_resident_atlas_bytes = 0
	signature_transient_ultimate_entity_id = ""

func load_signature_pack(required_ids: Array[String] = []) -> bool:
	# Full-page load is retained for manifest/artifact QA. Runtime encounter
	# setup calls `load_signature_core_pack` instead, which avoids treating every
	# actor's ultimate sheet as permanently resident.
	return _load_signature_pack_with_states(required_ids, SIGNATURE_ANIMATIONS, false)


func load_signature_core_pack(required_ids: Array[String] = []) -> bool:
	return _load_signature_pack_with_states(required_ids, SIGNATURE_CORE_ANIMATIONS, true)


func _load_signature_pack_with_states(required_ids: Array[String], requested_states: Array, core_lease: bool) -> bool:
	clear_signature_pack()
	var ids_to_load: Array[String] = []
	for character_id in required_ids:
		var id := str(character_id).strip_edges()
		if not id.is_empty() and not ids_to_load.has(id):
			ids_to_load.append(id)
	if ids_to_load.is_empty():
		signature_load_error = "SIGNATURE_IDS_EMPTY"
		return false
	var states_to_load := _normalized_signature_states(requested_states)
	if states_to_load.is_empty():
		signature_load_error = "SIGNATURE_STATES_EMPTY"
		return false
	var approval_error := _load_signature_approval(ids_to_load, states_to_load)
	if not approval_error.is_empty():
		signature_load_error = approval_error
		return false
	var errors: Array[String] = []
	for id in ids_to_load:
		var error := _load_signature_character(id, SIGNATURE_ROOT + "/" + id, states_to_load)
		if not error.is_empty():
			errors.append(error)
	signature_load_error = ";".join(errors)
	var loaded := errors.is_empty() and signature_manifests.size() == ids_to_load.size()
	if not loaded:
		# A failed mixed request must not retain a partially loaded encounter.
		# Keeping only a subset would make a later fallback look like an approved
		# resident pack while silently changing the memory and identity contract.
		var failure_error := signature_load_error
		clear_signature_pack()
		# `clear_signature_pack()` deliberately removes all runtime references, but
		# the caller still needs the concrete reason to prove that it selected the
		# compact fallback rather than silently accepting a partial lease.
		signature_load_error = failure_error if not failure_error.is_empty() else "SIGNATURE_LOAD_FAILED"
		return false
	signature_resident_entity_ids = ids_to_load.duplicate()
	for id in ids_to_load:
		signature_resident_animation_ids_by_entity[id] = states_to_load.duplicate()
	signature_core_resident_atlas_bytes = signature_resident_atlas_bytes if core_lease else 0
	return true


func _normalized_signature_states(requested_states: Array) -> Array[String]:
	var normalized: Array[String] = []
	for state_value in requested_states:
		var state_name := str(state_value).strip_edges()
		if state_name in SIGNATURE_ANIMATIONS and not normalized.has(state_name):
			normalized.append(state_name)
	return normalized


func ensure_signature_ultimate_loaded(entity_id: String) -> bool:
	var normalized_id := entity_id.strip_edges()
	if normalized_id.is_empty() or not signature_resident_entity_ids.has(normalized_id):
		signature_load_error = "SIGNATURE_TRANSIENT_ENTITY_NOT_RESIDENT:%s" % normalized_id
		return false
	if has_signature_animation(normalized_id, "ultimate"):
		# A full QA pack already owns this page permanently.  Do not label it as a
		# transient page, or a later cleanup would accidentally strip a page from
		# the full-pack artifact validation path.
		return true
	# A transient lease never keeps two actors' expensive ultimate sheets. Release
	# the previous one before acquiring the next so even the loader's peak stays
	# inside the same decoded-RGBA ceiling.
	if not signature_transient_ultimate_entity_id.is_empty() and signature_transient_ultimate_entity_id != normalized_id:
		release_signature_transient_ultimate()
	var projected_state_map := signature_resident_animation_ids_by_entity.duplicate(true)
	var entity_states: Array = Array(projected_state_map.get(normalized_id, [])).duplicate()
	if not entity_states.has("ultimate"):
		entity_states.append("ultimate")
	projected_state_map[normalized_id] = entity_states
	var projected_bytes := _signature_resident_atlas_bytes_for_state_map(signature_resident_entity_ids, projected_state_map)
	if projected_bytes <= 0 or projected_bytes > _signature_memory_ceiling_bytes():
		signature_load_error = "SIGNATURE_TRANSIENT_MEMORY_BUDGET_EXCEEDED:%d>%d" % [projected_bytes, _signature_memory_ceiling_bytes()]
		return false
	var load_error := _load_signature_character(normalized_id, SIGNATURE_ROOT + "/" + normalized_id, ["ultimate"])
	if not load_error.is_empty():
		signature_load_error = load_error
		return false
	signature_resident_animation_ids_by_entity = projected_state_map
	signature_resident_atlas_bytes = projected_bytes
	signature_transient_ultimate_entity_id = normalized_id
	signature_load_error = ""
	return true


func release_signature_transient_ultimate() -> void:
	if signature_transient_ultimate_entity_id.is_empty():
		return
	var entity_id := signature_transient_ultimate_entity_id
	if signature_frames.has(entity_id):
		(signature_frames[entity_id] as Dictionary).erase("ultimate")
	if signature_frame_metadata.has(entity_id):
		(signature_frame_metadata[entity_id] as Dictionary).erase("ultimate")
	var entity_states: Array = Array(signature_resident_animation_ids_by_entity.get(entity_id, [])).duplicate()
	entity_states.erase("ultimate")
	signature_resident_animation_ids_by_entity[entity_id] = entity_states
	signature_resident_atlas_bytes = _signature_resident_atlas_bytes_for_state_map(signature_resident_entity_ids, signature_resident_animation_ids_by_entity)
	signature_transient_ultimate_entity_id = ""


func signature_residency_snapshot() -> Dictionary:
	return {
		"entity_ids": signature_resident_entity_ids.duplicate(),
		"animation_ids_by_entity": signature_resident_animation_ids_by_entity.duplicate(true),
		"core_resident_atlas_bytes": signature_core_resident_atlas_bytes,
		"transient_ultimate_entity_id": signature_transient_ultimate_entity_id,
		"resident_atlas_bytes": signature_resident_atlas_bytes,
		"budget_bytes": SIGNATURE_HARD_MEMORY_BUDGET_BYTES,
	}

func _load_signature_approval(required_ids: Array[String], requested_states: Array = SIGNATURE_ANIMATIONS) -> String:
	## An atlas candidate is not a release asset merely because it decodes.  The
	## separate approval record pins the exact immutable manifests reviewed for
	## this revision.  LOCAL_QA_ONLY is accepted only by a debug build so actual
	## capture can precede review; public exports require APPROVED_FOR_RUNTIME.
	if not FileAccess.file_exists(SIGNATURE_APPROVAL_PATH):
		return "SIGNATURE_APPROVAL_MISSING"
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SIGNATURE_APPROVAL_PATH))
	if not parsed is Dictionary:
		return "SIGNATURE_APPROVAL_PARSE_FAILED"
	var approval: Dictionary = parsed
	if str(approval.get("signature_revision", "")).to_lower() != SIGNATURE_REVISION:
		return "SIGNATURE_APPROVAL_REVISION_MISMATCH"
	var approval_status := str(approval.get("approval_status", ""))
	var allowed_local_qa := approval_status == "LOCAL_QA_ONLY" and OS.is_debug_build()
	if approval_status != "APPROVED_FOR_RUNTIME" and not allowed_local_qa:
		return "SIGNATURE_APPROVAL_NOT_RELEASED:%s" % approval_status
	var hashes_value = approval.get("manifest_sha256_by_character", {})
	if not hashes_value is Dictionary:
		return "SIGNATURE_APPROVAL_HASHES_MISSING"
	var manifest_hashes: Dictionary = hashes_value
	for id in required_ids:
		var expected_hash := str(manifest_hashes.get(id, ""))
		if expected_hash.length() != 64:
			return "SIGNATURE_APPROVAL_CHARACTER_MISSING:%s" % id
	var technical_gate_value = approval.get("technical_gate", {})
	if not technical_gate_value is Dictionary:
		return "SIGNATURE_APPROVAL_TECHNICAL_GATE_MISSING"
	var technical_gate: Dictionary = technical_gate_value
	var declared_budget_mib := int(technical_gate.get("runtime_memory_budget_mib", 0))
	if declared_budget_mib <= 0:
		return "SIGNATURE_APPROVAL_MEMORY_BUDGET_MISSING"
	var actual_bytes := _signature_resident_atlas_bytes_for(required_ids, requested_states)
	if actual_bytes <= 0:
		return "SIGNATURE_MEMORY_ESTIMATE_INVALID:%d" % actual_bytes
	var allowed_bytes := mini(SIGNATURE_HARD_MEMORY_BUDGET_BYTES, declared_budget_mib * 1024 * 1024)
	if actual_bytes > allowed_bytes:
		return "SIGNATURE_MEMORY_BUDGET_EXCEEDED:%d>%d" % [actual_bytes, allowed_bytes]
	signature_resident_atlas_bytes = actual_bytes
	signature_approval = approval
	return ""

func _signature_memory_ceiling_bytes() -> int:
	var technical_gate_value = signature_approval.get("technical_gate", {})
	var declared_budget_mib := 0
	if technical_gate_value is Dictionary:
		declared_budget_mib = int((technical_gate_value as Dictionary).get("runtime_memory_budget_mib", 0))
	return mini(SIGNATURE_HARD_MEMORY_BUDGET_BYTES, declared_budget_mib * 1024 * 1024)


func _signature_resident_atlas_bytes_for(required_ids: Array[String], requested_states: Array = SIGNATURE_ANIMATIONS) -> int:
	var states_by_entity: Dictionary = {}
	var normalized_states := _normalized_signature_states(requested_states)
	if normalized_states.is_empty():
		return -1
	for character_id in required_ids:
		states_by_entity[character_id] = normalized_states
	return _signature_resident_atlas_bytes_for_state_map(required_ids, states_by_entity)


func _signature_resident_atlas_bytes_for_state_map(required_ids: Array[String], states_by_entity: Dictionary) -> int:
	## Count decoded RGBA atlas backing storage before ResourceLoader creates it.
	## New signature entities cannot quietly push a mobile battle beyond the
	## reviewed limit merely because each individual atlas has a valid hash.
	var total_bytes := 0
	var seen_atlases: Dictionary = {}
	for character_id in required_ids:
		var manifest_path := SIGNATURE_ROOT + "/" + character_id + "/signature_manifest.json"
		if not FileAccess.file_exists(manifest_path):
			return -1
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not parsed is Dictionary:
			return -1
		var manifest: Dictionary = parsed
		var animations_value = manifest.get("animations", {})
		if not animations_value is Dictionary:
			return -1
		var animations: Dictionary = animations_value
		var requested_state_values = states_by_entity.get(character_id, [])
		if not requested_state_values is Array:
			return -1
		var requested_states := _normalized_signature_states(requested_state_values as Array)
		if requested_states.is_empty():
			return -1
		for animation_name in requested_states:
			var animation_value = animations.get(animation_name, {})
			if not animation_value is Dictionary:
				return -1
			var animation: Dictionary = animation_value
			var atlas_path := str(animation.get("atlas_path", ""))
			var atlas_size_value = animation.get("atlas_size", [])
			if atlas_path.is_empty() or not atlas_size_value is Array or atlas_size_value.size() != 2:
				return -1
			var atlas_key := character_id + "/" + atlas_path
			if seen_atlases.has(atlas_key):
				continue
			var width := int(atlas_size_value[0])
			var height := int(atlas_size_value[1])
			if width <= 0 or height <= 0:
				return -1
			seen_atlases[atlas_key] = true
			total_bytes += width * height * 4
	return total_bytes

func _load_signature_character(character_id: String, pack_root: String, requested_states: Array = SIGNATURE_ANIMATIONS) -> String:
	var manifest_path := pack_root + "/signature_manifest.json"
	if not FileAccess.file_exists(manifest_path):
		return "%s:SIGNATURE_MANIFEST_MISSING" % character_id
	var expected_hashes_value = signature_approval.get("manifest_sha256_by_character", {})
	if not expected_hashes_value is Dictionary:
		return "%s:SIGNATURE_APPROVAL_HASHES_INVALID" % character_id
	var expected_manifest_hash := str((expected_hashes_value as Dictionary).get(character_id, ""))
	if FileAccess.get_sha256(manifest_path) != expected_manifest_hash:
		return "%s:SIGNATURE_MANIFEST_HASH_MISMATCH" % character_id
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return "%s:SIGNATURE_MANIFEST_OPEN_FAILED" % character_id
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return "%s:SIGNATURE_MANIFEST_PARSE_FAILED" % character_id
	var manifest: Dictionary = parsed
	if str(manifest.get("character_id", "")) != character_id:
		return "%s:SIGNATURE_CHARACTER_ID_MISMATCH" % character_id
	var runtime_frame_size = manifest.get("runtime_frame_size", [])
	if not runtime_frame_size is Array or runtime_frame_size.size() != 2 or int(runtime_frame_size[0]) != 384 or int(runtime_frame_size[1]) != 384:
		return "%s:SIGNATURE_RUNTIME_FRAME_SIZE_INVALID" % character_id
	var generation := str(manifest.get("generation", ""))
	if not bool(manifest.get("no_source_mutation", false)) or generation not in ["deterministic_resize_and_atlas_only", "deterministic_resize_alpha_tight_atlas_only"]:
		return "%s:SIGNATURE_PROVENANCE_INVALID" % character_id
	var animation_definitions = manifest.get("animations", {})
	if not animation_definitions is Dictionary or animation_definitions.is_empty():
		return "%s:SIGNATURE_ANIMATIONS_MISSING" % character_id
	for required_animation in SIGNATURE_ANIMATIONS:
		if not animation_definitions.has(required_animation):
			return "%s:SIGNATURE_REQUIRED_ANIMATION_MISSING:%s" % [character_id, required_animation]
	var states_to_load := _normalized_signature_states(requested_states)
	if states_to_load.is_empty():
		return "%s:SIGNATURE_REQUESTED_STATES_EMPTY" % character_id
	# Build new state pages beside the existing core lease, then publish only
	# after every requested state validates. A failed transient ultimate leaves
	# the old core renderable instead of creating a partial mixed actor.
	var character_frames: Dictionary = (signature_frames.get(character_id, {}) as Dictionary).duplicate()
	var character_metadata: Dictionary = (signature_frame_metadata.get(character_id, {}) as Dictionary).duplicate()
	var atlas_cache: Dictionary = {}
	for animation_name_value in states_to_load:
		var animation_name := str(animation_name_value)
		var definition_value = animation_definitions[animation_name]
		if not definition_value is Dictionary:
			return "%s:SIGNATURE_ANIMATION_INVALID:%s" % [character_id, animation_name]
		var definition: Dictionary = definition_value
		var atlas_path := str(definition.get("atlas_path", ""))
		var frame_records = definition.get("frames", [])
		if atlas_path.is_empty() or atlas_path != atlas_path.get_file() or not frame_records is Array or frame_records.is_empty():
			return "%s:SIGNATURE_FRAME_RECORDS_MISSING:%s" % [character_id, animation_name]
		var full_atlas_path := pack_root + "/" + atlas_path
		var declared_atlas_hash := str(definition.get("atlas_sha256", ""))
		if declared_atlas_hash.length() != 64 or not FileAccess.file_exists(full_atlas_path) or FileAccess.get_sha256(full_atlas_path) != declared_atlas_hash:
			return "%s:SIGNATURE_ATLAS_HASH_MISMATCH:%s" % [character_id, animation_name]
		var atlas_texture: Texture2D = atlas_cache.get(atlas_path)
		if atlas_texture == null:
			atlas_texture = _load_runtime_texture(full_atlas_path)
			if atlas_texture == null:
				return "%s:SIGNATURE_ATLAS_LOAD_FAILED:%s" % [character_id, atlas_path]
			atlas_cache[atlas_path] = atlas_texture
		var textures: Array[Texture2D] = []
		var metadata: Array[Dictionary] = []
		var logical_frame_size_value = definition.get("logical_frame_size", runtime_frame_size)
		if not logical_frame_size_value is Array or logical_frame_size_value.size() != 2:
			return "%s:SIGNATURE_LOGICAL_FRAME_SIZE_INVALID:%s" % [character_id, animation_name]
		var logical_frame_size := Vector2i(int(logical_frame_size_value[0]), int(logical_frame_size_value[1]))
		if logical_frame_size.x <= 0 or logical_frame_size.y <= 0:
			return "%s:SIGNATURE_LOGICAL_FRAME_SIZE_INVALID:%s" % [character_id, animation_name]
		for record_value in frame_records:
			if not record_value is Dictionary:
				return "%s:SIGNATURE_FRAME_RECORD_INVALID:%s" % [character_id, animation_name]
			var record: Dictionary = record_value
			var region_value = record.get("region", [])
			if not region_value is Array or region_value.size() != 4:
				return "%s:SIGNATURE_REGION_INVALID:%s" % [character_id, animation_name]
			var region := Rect2(float(region_value[0]), float(region_value[1]), float(region_value[2]), float(region_value[3]))
			if region.size.x <= 0.0 or region.size.y <= 0.0:
				return "%s:SIGNATURE_REGION_INVALID:%s" % [character_id, animation_name]
			var logical_rect_value = record.get("logical_rect", [0, 0, logical_frame_size.x, logical_frame_size.y])
			if not logical_rect_value is Array or logical_rect_value.size() != 4:
				return "%s:SIGNATURE_LOGICAL_RECT_INVALID:%s" % [character_id, animation_name]
			var logical_rect := Rect2(float(logical_rect_value[0]), float(logical_rect_value[1]), float(logical_rect_value[2]), float(logical_rect_value[3]))
			if logical_rect.size.x <= 0.0 or logical_rect.size.y <= 0.0 or logical_rect.position.x < 0.0 or logical_rect.position.y < 0.0 or logical_rect.end.x > float(logical_frame_size.x) or logical_rect.end.y > float(logical_frame_size.y):
				return "%s:SIGNATURE_LOGICAL_RECT_INVALID:%s" % [character_id, animation_name]
			var texture := AtlasTexture.new()
			texture.atlas = atlas_texture
			texture.region = region
			textures.append(texture)
			metadata.append({"logical_rect": logical_rect, "logical_canvas_size": Vector2(logical_frame_size)})
		if textures.is_empty():
			return "%s:SIGNATURE_ANIMATION_EMPTY:%s" % [character_id, animation_name]
		character_frames[animation_name] = textures
		character_metadata[animation_name] = metadata
	signature_manifests[character_id] = manifest
	signature_frames[character_id] = character_frames
	signature_frame_metadata[character_id] = character_metadata
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

func has_signature_animation(character_id: String, animation_name: String) -> bool:
	return signature_frames.has(character_id) and signature_frames[character_id].has(animation_name) and not signature_frames[character_id][animation_name].is_empty()


func _signature_frame_index(character_id: String, animation_name: String, elapsed: float) -> int:
	if not has_signature_animation(character_id, animation_name):
		return -1
	var definition: Dictionary = signature_manifests[character_id].get("animations", {}).get(animation_name, {})
	var textures: Array = signature_frames[character_id][animation_name]
	if textures.is_empty():
		return -1
	var fps := maxf(1.0, float(definition.get("fps", 12)))
	var index := int(floor(elapsed * fps))
	if bool(definition.get("loop", false)):
		index %= textures.size()
	else:
		index = mini(index, textures.size() - 1)
	return index


func signature_frame_info_at(character_id: String, animation_name: String, elapsed: float) -> Dictionary:
	## The logical rect reconstructs R5's source placement without allocating a
	## blank 384px texture for every frame.  R4 metadata is synthesized as a
	## full-canvas rect so callers remain revision-agnostic.
	var index := _signature_frame_index(character_id, animation_name, elapsed)
	if index < 0:
		return {}
	var textures: Array = signature_frames[character_id][animation_name]
	if index >= textures.size() or not textures[index] is Texture2D:
		return {}
	var metadata: Array = signature_frame_metadata.get(character_id, {}).get(animation_name, [])
	var default_canvas := Vector2(384.0, 384.0)
	var logical_rect := Rect2(Vector2.ZERO, default_canvas)
	var logical_canvas_size := default_canvas
	if index < metadata.size() and metadata[index] is Dictionary:
		var record: Dictionary = metadata[index]
		var record_rect = record.get("logical_rect", logical_rect)
		if record_rect is Rect2:
			logical_rect = record_rect
		var record_canvas = record.get("logical_canvas_size", logical_canvas_size)
		if record_canvas is Vector2:
			logical_canvas_size = record_canvas
	return {
		"texture": textures[index],
		"logical_rect": logical_rect,
		"logical_canvas_size": logical_canvas_size,
		"frame_index": index,
	}


func signature_texture_at(character_id: String, animation_name: String, elapsed: float) -> Texture2D:
	var frame_info := signature_frame_info_at(character_id, animation_name, elapsed)
	var texture = frame_info.get("texture", null)
	if texture is Texture2D:
		return texture as Texture2D
	return null

func duration(character_id: String, animation_name: String) -> float:
	if not has_animation(character_id, animation_name): return 0.0
	var definition: Dictionary = manifests[character_id].animations.get(animation_name, {})
	return float(frames[character_id][animation_name].size()) / maxf(1.0, float(definition.get("fps", 12)))


func signature_duration(character_id: String, animation_name: String) -> float:
	if not has_signature_animation(character_id, animation_name): return 0.0
	var definition: Dictionary = signature_manifests.get(character_id, {}).get("animations", {}).get(animation_name, {})
	return float(signature_frames[character_id][animation_name].size()) / maxf(1.0, float(definition.get("fps", 12)))

func is_looping(character_id: String, animation_name: String) -> bool:
	return bool(manifests.get(character_id, {}).get("animations", {}).get(animation_name, {}).get("loop", false))

func signature_is_looping(character_id: String, animation_name: String) -> bool:
	return bool(signature_manifests.get(character_id, {}).get("animations", {}).get(animation_name, {}).get("loop", false))

func head_anchor(character_id: String) -> Vector2:
	var value: Array = manifests.get(character_id, {}).get("head_anchor", [0.5, 0.08])
	return Vector2(float(value[0]), float(value[1]))


func signature_head_anchor(character_id: String) -> Vector2:
	var value: Array = signature_manifests.get(character_id, {}).get("head_anchor", [0.5, 0.08])
	return Vector2(float(value[0]), float(value[1]))

func source_faces_right(character_id: String) -> bool:
	# The authored view is the single runtime orientation authority. BattleView
	# compares it with the unit team and mirrors only when the source and desired
	# enemy-facing direction differ. This keeps source packs reusable without
	# allowing a left-facing player or right-facing enemy into combat.
	var view := str(manifests.get(character_id, {}).get("view", "THREE_QUARTER_RIGHT_DOWN_30"))
	return view.contains("RIGHT")


func signature_source_faces_right(character_id: String) -> bool:
	var view := str(signature_manifests.get(character_id, {}).get("view", "THREE_QUARTER_RIGHT_DOWN_30"))
	return view.contains("RIGHT")

func frame_canvas_size(character_id: String) -> Vector2:
	var value: Array = manifests.get(character_id, {}).get("frame_size", [512, 512])
	return Vector2(float(value[0]), float(value[1]))

func supports_character(character_id: String) -> bool:
	return manifests.has(character_id) and frames.has(character_id)
