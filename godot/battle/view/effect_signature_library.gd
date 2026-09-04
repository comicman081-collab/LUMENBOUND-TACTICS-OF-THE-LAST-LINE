class_name EffectSignatureLibrary
extends RefCounted

## The compact Web projectile/VFX atlases remain the baseline for every
## combatant.  This loader adds a separately pinned high-density effect slice
## for the currently reviewed reference group only.  It accepts a local-QA
## candidate in debug builds so a real phone capture can happen before a public
## release, but never lets an unreviewed candidate into a release export.

## R4 covers the actual starting five-player party (CHR002 still borrows
## CHR001's profile), the reviewed CHR008 alternate-party slice, and
## ENM001/BOSS001 through bounded 1.8× VFX derivatives. The projectile core
## plus one caster ultimate remains below 12MiB.
const SIGNATURE_REVISION := "r4"
const SIGNATURE_ROOT := "res://assets/runtime_web/effect_signature/" + SIGNATURE_REVISION
const SIGNATURE_APPROVAL_PATH := SIGNATURE_ROOT + "/promotion_approval.json"
const SIGNATURE_ENTITY_IDS: Array[String] = ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005", "CHR008", "BOSS001", "ENM001"]
## High-density effect pages are reusable visual profiles, not one duplicated
## atlas per party member.  CHR002 borrows the reviewed CHR001 energy family
## with its own runtime tint; this retains a 2× readable effect while keeping
## the encounter below the hard 12MiB VFX residency ceiling.
const SIGNATURE_PROFILE_BY_ENTITY := {
	"CHR001": "CHR001",
	"CHR002": "CHR001",
	"CHR003": "CHR003",
	"CHR004": "CHR004",
	"CHR005": "CHR005",
	"CHR008": "CHR008",
	"BOSS001": "BOSS001",
	"ENM001": "ENM001",
}
## Projectile sheets form the core encounter effect lease. One high-density
## ultimate sheet is acquired atomically for the current caster only, avoiding
## a permanent four-page ultimate preload as the party grows.
const SIGNATURE_CORE_EFFECTS := ["projectile"]
const SIGNATURE_EFFECTS := ["projectile", "ultimate"]
const SIGNATURE_HARD_MEMORY_BUDGET_BYTES := 12 * 1024 * 1024

var manifests: Dictionary = {}
var projectile_frames: Dictionary = {}
var ultimate_frames: Dictionary = {}
var signature_approval: Dictionary = {}
var signature_load_error := ""
var signature_resident_atlas_bytes := 0
## High-density effect pages are leased to the current encounter.  They must
## not become an invisible global preload as the roster grows.
var signature_resident_entity_ids: Array[String] = []
var signature_resident_profile_ids: Array[String] = []
var signature_resident_effect_ids_by_profile: Dictionary = {}
var signature_core_resident_atlas_bytes := 0
var signature_transient_ultimate_profile_id := ""


func clear_signature_pack() -> void:
	manifests.clear()
	projectile_frames.clear()
	ultimate_frames.clear()
	signature_approval.clear()
	signature_load_error = ""
	signature_resident_atlas_bytes = 0
	signature_resident_entity_ids.clear()
	signature_resident_profile_ids.clear()
	signature_resident_effect_ids_by_profile.clear()
	signature_core_resident_atlas_bytes = 0
	signature_transient_ultimate_profile_id = ""


func load_signature_pack(required_ids: Array[String]) -> bool:
	# The full effect family remains available to artifact QA. Runtime encounter
	# setup uses the projectile-only core lease and acquires a single ultimate
	# page only for the caster about to fire.
	return _load_signature_pack_with_effects(required_ids, SIGNATURE_EFFECTS, false)


func load_signature_core_pack(required_ids: Array[String]) -> bool:
	return _load_signature_pack_with_effects(required_ids, SIGNATURE_CORE_EFFECTS, true)


func _load_signature_pack_with_effects(required_ids: Array[String], requested_effects: Array, core_lease: bool) -> bool:
	clear_signature_pack()
	var ids_to_load: Array[String] = []
	for value in required_ids:
		var entity_id := str(value).strip_edges()
		if not entity_id.is_empty() and not ids_to_load.has(entity_id):
			ids_to_load.append(entity_id)
	if ids_to_load.is_empty():
		signature_load_error = "EFFECT_SIGNATURE_IDS_EMPTY"
		return false
	var effect_names := _normalized_effect_names(requested_effects)
	if effect_names.is_empty():
		signature_load_error = "EFFECT_SIGNATURE_NAMES_EMPTY"
		return false
	var profile_ids: Array[String] = []
	for entity_id in ids_to_load:
		var profile_id := signature_profile_for(entity_id)
		if profile_id.is_empty():
			signature_load_error = "EFFECT_SIGNATURE_PROFILE_MISSING:%s" % entity_id
			return false
		if not profile_ids.has(profile_id):
			profile_ids.append(profile_id)
	var approval_error := _load_signature_approval(profile_ids, effect_names)
	if not approval_error.is_empty():
		signature_load_error = approval_error
		return false
	var errors: Array[String] = []
	for profile_id in profile_ids:
		var load_error := _load_entity(profile_id, effect_names)
		if not load_error.is_empty():
			errors.append(load_error)
	signature_load_error = ";".join(errors)
	var loaded := errors.is_empty() and manifests.size() == profile_ids.size()
	if not loaded:
		# Do not keep a partial effect family alive after a failed encounter load.
		# A partial result would make later fallback behaviour and texture residency
		# nondeterministic across the same stage.
		var failure_error := signature_load_error
		clear_signature_pack()
		# The resident records must go away, but the view must still be able to
		# report why it selected the compact authored effect fallback.
		signature_load_error = failure_error if not failure_error.is_empty() else "EFFECT_SIGNATURE_LOAD_FAILED"
		return false
	signature_resident_entity_ids = ids_to_load.duplicate()
	signature_resident_profile_ids = profile_ids.duplicate()
	for profile_id in profile_ids:
		signature_resident_effect_ids_by_profile[profile_id] = effect_names.duplicate()
	signature_core_resident_atlas_bytes = signature_resident_atlas_bytes if core_lease else 0
	return true


func _normalized_effect_names(requested_effects: Array) -> Array[String]:
	var normalized: Array[String] = []
	for effect_value in requested_effects:
		var effect_name := str(effect_value).strip_edges()
		if effect_name in SIGNATURE_EFFECTS and not normalized.has(effect_name):
			normalized.append(effect_name)
	return normalized


func ensure_signature_ultimate_loaded(entity_id: String) -> bool:
	var profile_id := signature_profile_for(entity_id)
	if profile_id.is_empty() or not signature_resident_profile_ids.has(profile_id):
		signature_load_error = "EFFECT_SIGNATURE_TRANSIENT_PROFILE_NOT_RESIDENT:%s" % entity_id
		return false
	if ultimate_frames.has(profile_id) and not Array(ultimate_frames.get(profile_id, [])).is_empty():
		# Full artifact QA may intentionally load every ultimate page.  Such a page
		# is not transient and must not be removed by runtime cleanup semantics.
		return true
	if not signature_transient_ultimate_profile_id.is_empty() and signature_transient_ultimate_profile_id != profile_id:
		release_signature_transient_ultimate()
	var projected_effect_map := signature_resident_effect_ids_by_profile.duplicate(true)
	var profile_effects: Array = Array(projected_effect_map.get(profile_id, [])).duplicate()
	if not profile_effects.has("ultimate"):
		profile_effects.append("ultimate")
	projected_effect_map[profile_id] = profile_effects
	var projected_bytes := _resident_atlas_bytes_for_effect_map(signature_resident_profile_ids, projected_effect_map)
	if projected_bytes <= 0 or projected_bytes > _signature_memory_ceiling_bytes():
		signature_load_error = "EFFECT_SIGNATURE_TRANSIENT_MEMORY_BUDGET_EXCEEDED:%d>%d" % [projected_bytes, _signature_memory_ceiling_bytes()]
		return false
	var load_error := _load_entity(profile_id, ["ultimate"])
	if not load_error.is_empty():
		signature_load_error = load_error
		return false
	signature_resident_effect_ids_by_profile = projected_effect_map
	signature_resident_atlas_bytes = projected_bytes
	signature_transient_ultimate_profile_id = profile_id
	signature_load_error = ""
	return true


func release_signature_transient_ultimate() -> void:
	if signature_transient_ultimate_profile_id.is_empty():
		return
	var profile_id := signature_transient_ultimate_profile_id
	ultimate_frames.erase(profile_id)
	var profile_effects: Array = Array(signature_resident_effect_ids_by_profile.get(profile_id, [])).duplicate()
	profile_effects.erase("ultimate")
	signature_resident_effect_ids_by_profile[profile_id] = profile_effects
	signature_resident_atlas_bytes = _resident_atlas_bytes_for_effect_map(signature_resident_profile_ids, signature_resident_effect_ids_by_profile)
	signature_transient_ultimate_profile_id = ""


func signature_residency_snapshot() -> Dictionary:
	return {
		"entity_ids": signature_resident_entity_ids.duplicate(),
		"profile_ids": signature_resident_profile_ids.duplicate(),
		"effect_ids_by_profile": signature_resident_effect_ids_by_profile.duplicate(true),
		"core_resident_atlas_bytes": signature_core_resident_atlas_bytes,
		"transient_ultimate_profile_id": signature_transient_ultimate_profile_id,
		"resident_atlas_bytes": signature_resident_atlas_bytes,
		"budget_bytes": SIGNATURE_HARD_MEMORY_BUDGET_BYTES,
	}


func signature_profile_for(entity_id: String) -> String:
	return str(SIGNATURE_PROFILE_BY_ENTITY.get(entity_id, ""))


func uses_borrowed_profile(entity_id: String) -> bool:
	var profile_id := signature_profile_for(entity_id)
	return not profile_id.is_empty() and profile_id != entity_id


func _load_signature_approval(required_ids: Array[String], requested_effects: Array = SIGNATURE_EFFECTS) -> String:
	if not FileAccess.file_exists(SIGNATURE_APPROVAL_PATH):
		return "EFFECT_SIGNATURE_APPROVAL_MISSING"
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SIGNATURE_APPROVAL_PATH))
	if not parsed is Dictionary:
		return "EFFECT_SIGNATURE_APPROVAL_PARSE_FAILED"
	var approval: Dictionary = parsed
	if str(approval.get("effect_signature_revision", "")).to_lower() != SIGNATURE_REVISION:
		return "EFFECT_SIGNATURE_APPROVAL_REVISION_MISMATCH"
	var approval_status := str(approval.get("approval_status", ""))
	var allowed_local_qa := approval_status == "LOCAL_QA_ONLY" and OS.is_debug_build()
	if approval_status != "APPROVED_FOR_RUNTIME" and not allowed_local_qa:
		return "EFFECT_SIGNATURE_APPROVAL_NOT_RELEASED:%s" % approval_status
	var hashes_value = approval.get("manifest_sha256_by_entity", {})
	if not hashes_value is Dictionary:
		return "EFFECT_SIGNATURE_APPROVAL_HASHES_MISSING"
	var manifest_hashes: Dictionary = hashes_value
	for entity_id in required_ids:
		if str(manifest_hashes.get(entity_id, "")).length() != 64:
			return "EFFECT_SIGNATURE_APPROVAL_ENTITY_MISSING:%s" % entity_id
	var technical_gate_value = approval.get("technical_gate", {})
	if not technical_gate_value is Dictionary:
		return "EFFECT_SIGNATURE_APPROVAL_TECHNICAL_GATE_MISSING"
	var technical_gate: Dictionary = technical_gate_value
	var declared_budget_mib := int(technical_gate.get("runtime_memory_budget_mib", 0))
	if declared_budget_mib <= 0:
		return "EFFECT_SIGNATURE_APPROVAL_MEMORY_BUDGET_MISSING"
	var estimated_bytes := _resident_atlas_bytes_for(required_ids, requested_effects)
	if estimated_bytes <= 0:
		return "EFFECT_SIGNATURE_MEMORY_ESTIMATE_INVALID:%d" % estimated_bytes
	var allowed_bytes := mini(SIGNATURE_HARD_MEMORY_BUDGET_BYTES, declared_budget_mib * 1024 * 1024)
	if estimated_bytes > allowed_bytes:
		return "EFFECT_SIGNATURE_MEMORY_BUDGET_EXCEEDED:%d>%d" % [estimated_bytes, allowed_bytes]
	signature_approval = approval
	signature_resident_atlas_bytes = estimated_bytes
	return ""


func _signature_memory_ceiling_bytes() -> int:
	var technical_gate_value = signature_approval.get("technical_gate", {})
	var declared_budget_mib := 0
	if technical_gate_value is Dictionary:
		declared_budget_mib = int((technical_gate_value as Dictionary).get("runtime_memory_budget_mib", 0))
	return mini(SIGNATURE_HARD_MEMORY_BUDGET_BYTES, declared_budget_mib * 1024 * 1024)


func _resident_atlas_bytes_for(required_ids: Array[String], requested_effects: Array = SIGNATURE_EFFECTS) -> int:
	var effect_map: Dictionary = {}
	var normalized_effects := _normalized_effect_names(requested_effects)
	if normalized_effects.is_empty():
		return -1
	for entity_id in required_ids:
		effect_map[entity_id] = normalized_effects
	return _resident_atlas_bytes_for_effect_map(required_ids, effect_map)


func _resident_atlas_bytes_for_effect_map(required_ids: Array[String], effect_map: Dictionary) -> int:
	var total_bytes := 0
	var seen_atlases: Dictionary = {}
	for entity_id in required_ids:
		var manifest_path := SIGNATURE_ROOT + "/" + entity_id + "/effect_signature_manifest.json"
		if not FileAccess.file_exists(manifest_path):
			return -1
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not parsed is Dictionary:
			return -1
		var manifest: Dictionary = parsed
		var requested_effect_values = effect_map.get(entity_id, [])
		if not requested_effect_values is Array:
			return -1
		var requested_effects := _normalized_effect_names(requested_effect_values as Array)
		if requested_effects.is_empty():
			return -1
		for effect_name in requested_effects:
			var effect_value = manifest.get(effect_name, {})
			if not effect_value is Dictionary:
				return -1
			var effect: Dictionary = effect_value
			var atlas_path := str(effect.get("atlas_path", ""))
			var atlas_size = effect.get("atlas_size", [])
			if atlas_path.is_empty() or not atlas_size is Array or atlas_size.size() != 2:
				return -1
			var atlas_key := entity_id + "/" + atlas_path
			if seen_atlases.has(atlas_key):
				continue
			var width := int(atlas_size[0])
			var height := int(atlas_size[1])
			if width <= 0 or height <= 0:
				return -1
			seen_atlases[atlas_key] = true
			total_bytes += width * height * 4
	return total_bytes


func _declared_frame_size(definition_value) -> Vector2i:
	if not definition_value is Dictionary:
		return Vector2i.ZERO
	var definition: Dictionary = definition_value
	var frame_size_value = definition.get("frame_size", [])
	if not frame_size_value is Array or frame_size_value.size() != 2:
		return Vector2i.ZERO
	var width := int(frame_size_value[0])
	var height := int(frame_size_value[1])
	if width <= 0 or height <= 0 or width != height:
		return Vector2i.ZERO
	return Vector2i(width, height)


func _load_entity(entity_id: String, requested_effects: Array = SIGNATURE_EFFECTS) -> String:
	var pack_root := SIGNATURE_ROOT + "/" + entity_id
	var manifest_path := pack_root + "/effect_signature_manifest.json"
	if not FileAccess.file_exists(manifest_path):
		return "%s:EFFECT_SIGNATURE_MANIFEST_MISSING" % entity_id
	var expected_hashes_value = signature_approval.get("manifest_sha256_by_entity", {})
	if not expected_hashes_value is Dictionary:
		return "%s:EFFECT_SIGNATURE_APPROVAL_HASHES_INVALID" % entity_id
	var expected_manifest_hash := str((expected_hashes_value as Dictionary).get(entity_id, ""))
	if FileAccess.get_sha256(manifest_path) != expected_manifest_hash:
		return "%s:EFFECT_SIGNATURE_MANIFEST_HASH_MISMATCH" % entity_id
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		return "%s:EFFECT_SIGNATURE_MANIFEST_PARSE_FAILED" % entity_id
	var manifest: Dictionary = parsed
	if str(manifest.get("entity_id", "")) != entity_id:
		return "%s:EFFECT_SIGNATURE_ENTITY_ID_MISMATCH" % entity_id
	if not bool(manifest.get("no_source_mutation", false)) or str(manifest.get("generation", "")) != "deterministic_lanczos_upscale_only" or float(manifest.get("scale_factor", 0.0)) <= 1.0:
		return "%s:EFFECT_SIGNATURE_PROVENANCE_INVALID" % entity_id
	var projectile_definition = manifest.get("projectile", {})
	var ultimate_definition = manifest.get("ultimate", {})
	var projectile_frame_size := _declared_frame_size(projectile_definition)
	var ultimate_frame_size := _declared_frame_size(ultimate_definition)
	if projectile_frame_size.x <= 96 or projectile_frame_size.y <= 96:
		return "%s:PROJECTILE_FRAME_SIZE_NOT_UPSCALED" % entity_id
	if ultimate_frame_size.x <= 112 or ultimate_frame_size.y <= 112:
		return "%s:ULTIMATE_FRAME_SIZE_NOT_UPSCALED" % entity_id
	var effect_names := _normalized_effect_names(requested_effects)
	if effect_names.is_empty():
		return "%s:EFFECT_SIGNATURE_REQUESTED_EFFECTS_EMPTY" % entity_id
	var staged_projectile_frames: Array = Array(projectile_frames.get(entity_id, [])).duplicate()
	var staged_ultimate_frames: Array = Array(ultimate_frames.get(entity_id, [])).duplicate()
	if effect_names.has("projectile"):
		var projectile_result := _load_effect_frames(pack_root, projectile_definition, projectile_frame_size, 8, 8, "%s:PROJECTILE" % entity_id)
		if not bool(projectile_result.get("ok", false)):
			return str(projectile_result.get("error", "%s:PROJECTILE_LOAD_FAILED" % entity_id))
		staged_projectile_frames = Array(projectile_result.get("frames", [])).duplicate()
	if effect_names.has("ultimate"):
		var ultimate_result := _load_effect_frames(pack_root, ultimate_definition, ultimate_frame_size, 12, 4, "%s:ULTIMATE" % entity_id)
		if not bool(ultimate_result.get("ok", false)):
			return str(ultimate_result.get("error", "%s:ULTIMATE_LOAD_FAILED" % entity_id))
		staged_ultimate_frames = Array(ultimate_result.get("frames", [])).duplicate()
	manifests[entity_id] = manifest
	if effect_names.has("projectile"):
		projectile_frames[entity_id] = staged_projectile_frames
	if effect_names.has("ultimate"):
		ultimate_frames[entity_id] = staged_ultimate_frames
	return ""


func _load_effect_frames(pack_root: String, definition_value, expected_frame_size: Vector2i, expected_count: int, expected_columns: int, error_prefix: String) -> Dictionary:
	if not definition_value is Dictionary:
		return {"ok": false, "error": error_prefix + ":DEFINITION_INVALID"}
	var definition: Dictionary = definition_value
	var frame_size = definition.get("frame_size", [])
	if not frame_size is Array or frame_size.size() != 2 or int(frame_size[0]) != expected_frame_size.x or int(frame_size[1]) != expected_frame_size.y:
		return {"ok": false, "error": error_prefix + ":FRAME_SIZE_INVALID"}
	if int(definition.get("frames", 0)) != expected_count or int(definition.get("atlas_columns", 0)) != expected_columns:
		return {"ok": false, "error": error_prefix + ":FRAME_LAYOUT_INVALID"}
	var atlas_path := str(definition.get("atlas_path", ""))
	if atlas_path.is_empty() or atlas_path != atlas_path.get_file():
		return {"ok": false, "error": error_prefix + ":ATLAS_PATH_INVALID"}
	var full_atlas_path := pack_root + "/" + atlas_path
	var expected_hash := str(definition.get("atlas_sha256", ""))
	if expected_hash.length() != 64 or not FileAccess.file_exists(full_atlas_path) or FileAccess.get_sha256(full_atlas_path) != expected_hash:
		return {"ok": false, "error": error_prefix + ":ATLAS_HASH_MISMATCH"}
	var atlas := _load_runtime_texture(full_atlas_path)
	if atlas == null:
		return {"ok": false, "error": error_prefix + ":ATLAS_LOAD_FAILED"}
	var indices_value = definition.get("frame_indices", [])
	if not indices_value is Array or indices_value.size() != expected_count:
		return {"ok": false, "error": error_prefix + ":FRAME_INDICES_INVALID"}
	var textures: Array[Texture2D] = []
	for index_value in indices_value:
		var cell := int(index_value)
		if cell < 0:
			return {"ok": false, "error": error_prefix + ":FRAME_INDEX_NEGATIVE"}
		var frame := AtlasTexture.new()
		frame.atlas = atlas
		frame.region = Rect2(float(cell % expected_columns) * expected_frame_size.x, float(cell / expected_columns) * expected_frame_size.y, expected_frame_size.x, expected_frame_size.y)
		textures.append(frame)
	return {"ok": textures.size() == expected_count, "frames": textures, "error": error_prefix + ":FRAME_COUNT_INVALID"}


func _load_runtime_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var imported = load(path)
		if imported is Texture2D:
			return imported
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func supports_source(entity_id: String) -> bool:
	return supports_projectile_source(entity_id) and supports_ultimate_source(entity_id)


func supports_projectile_source(entity_id: String) -> bool:
	var profile_id := signature_profile_for(entity_id)
	return not profile_id.is_empty() and manifests.has(profile_id) and projectile_frames.has(profile_id) and not Array(projectile_frames.get(profile_id, [])).is_empty()


func supports_ultimate_source(entity_id: String) -> bool:
	var profile_id := signature_profile_for(entity_id)
	return not profile_id.is_empty() and manifests.has(profile_id) and ultimate_frames.has(profile_id) and not Array(ultimate_frames.get(profile_id, [])).is_empty()


func projectile_texture_at(entity_id: String, elapsed: float) -> Texture2D:
	if not supports_projectile_source(entity_id):
		return null
	var profile_id := signature_profile_for(entity_id)
	var textures: Array = projectile_frames[profile_id]
	var duration := maxf(.01, float(manifests[profile_id].get("projectile", {}).get("flight_duration", .12)))
	var progress := clampf(elapsed / duration, 0.0, .999)
	return textures[mini(int(floor(progress * textures.size())), textures.size() - 1)] as Texture2D


func ultimate_texture_at(entity_id: String, progress: float) -> Texture2D:
	if not supports_ultimate_source(entity_id):
		return null
	var profile_id := signature_profile_for(entity_id)
	var textures: Array = ultimate_frames[profile_id]
	var clamped_progress := clampf(progress, 0.0, .999)
	return textures[mini(int(floor(clamped_progress * textures.size())), textures.size() - 1)] as Texture2D


func projectile_draw_size(entity_id: String) -> Vector2:
	var profile_id := signature_profile_for(entity_id)
	var value = manifests.get(profile_id, {}).get("projectile", {}).get("draw_size", [])
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2(96.0, 96.0)
