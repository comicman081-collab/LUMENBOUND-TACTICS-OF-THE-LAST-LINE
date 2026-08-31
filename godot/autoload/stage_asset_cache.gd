## Stage-select scoped, presentation-free asset cache.
##
## This node deliberately does not instantiate a Control, Viewport, BattleView, or
## map scene.  It retains decoded resources so the map and the first battle can
## share the same immutable runtime inputs without a synchronous Web decode.
extends Node

signal warmup_progress_changed(value: float, phase: String)
signal warmup_finished(signature: String, complete: bool)

const COMBAT_ROOT := "res://assets/runtime_web/combat"
const PROJECTILE_ROOT := "res://assets/runtime_web/projectiles"
const NORMAL_BACKGROUND_PATH := "res://assets/art/backgrounds/BG_BATTLE_GLASS_RAIL/bg_battle_glass_rail_1920x1080.png"
const BOSS_BACKGROUND_PATH := "res://assets/art/backgrounds/BG_BOSS_SIGNAL_CATHEDRAL/bg_boss_signal_cathedral_1920x1080.png"
const BATTLE_FONT_PATH := "res://assets/fonts/NotoSansKR-VF.ttf"
const WARMUP_DEADLINE_MSEC := 5000

var progress_value := 0.0
var progress_phase := "IDLE"
var warming := false
var ready_signature := ""
var map_ready_signature := ""

var _generation := 0
var _active_signature := ""
var _warm_started_msec := 0
var _cache: Dictionary = {}


func signature_for(map_id: String, definition: Dictionary, party_ids: Array, selected_stage_id := "", unlocked_stage_ids := []) -> String:
	var plan := target_plan(map_id, definition, party_ids, selected_stage_id, unlocked_stage_ids)
	return JSON.stringify({
		"map_id": str(plan.get("map_id", "")),
		"party": _unique_sorted_strings(plan.get("party_ids", [])),
		"selected": str(plan.get("selected_stage_id", "")),
		"unlocked": _unique_sorted_strings(plan.get("unlocked_stage_ids", [])),
		"entities": _unique_sorted_strings(plan.get("entity_ids", [])),
		"boss": bool(plan.get("requires_boss_background", false)),
	}).sha256_text()


func target_plan(map_id: String, definition: Dictionary, party_ids: Array, selected_stage_id := "", unlocked_stage_ids := []) -> Dictionary:
	var party := _unique_strings(party_ids)
	var unlocked := _unique_sorted_strings(unlocked_stage_ids)
	if unlocked.is_empty():
		unlocked = _unlocked_stage_ids_from_definition(definition)
	var selected := str(selected_stage_id).strip_edges()
	var stage_ids: Array[String] = []
	if not selected.is_empty():
		stage_ids.append(selected)
	for stage_id in unlocked:
		if not stage_ids.has(stage_id):
			stage_ids.append(stage_id)

	var entities: Array[String] = []
	entities.append_array(party)
	var boss_required := false
	for stage_id in stage_ids:
		var stage := DataRegistry.stage(stage_id)
		if stage.is_empty():
			continue
		boss_required = boss_required or bool(stage.get("boss", false))
		for wave_value in stage.get("waves", []):
			if not wave_value is Array:
				continue
			for entity_value in wave_value:
				var entity_id := str(entity_value).strip_edges()
				if not entity_id.is_empty() and not entities.has(entity_id):
					entities.append(entity_id)

	# Map event contacts are visible while their corresponding stage node is
	# unlocked. Keep both special-enemy and recruit character art ready.
	var node_stage_ids: Dictionary = {}
	for node_value in definition.get("nodes", []):
		if node_value is Dictionary:
			var node: Dictionary = node_value
			node_stage_ids[str(node.get("node_id", ""))] = str(node.get("stage_id", ""))
	for encounter_value in definition.get("event_encounters", []):
		if not encounter_value is Dictionary:
			continue
		var encounter: Dictionary = encounter_value
		var encounter_stage_id := str(encounter.get("stage_id", "")).strip_edges()
		if encounter_stage_id.is_empty():
			encounter_stage_id = str(node_stage_ids.get(str(encounter.get("node_id", "")), "")).strip_edges()
		if not encounter_stage_id.is_empty() and not stage_ids.has(encounter_stage_id):
			continue
		for key in ["enemy_id", "character_id"]:
			var event_entity_id := str(encounter.get(key, "")).strip_edges()
			if not event_entity_id.is_empty() and not entities.has(event_entity_id):
				entities.append(event_entity_id)
		for recruitment_value in encounter.get("recruitments", []):
			if recruitment_value is Dictionary:
				var recruit_id := str((recruitment_value as Dictionary).get("character_id", "")).strip_edges()
				if not recruit_id.is_empty() and not entities.has(recruit_id):
					entities.append(recruit_id)
	return {
		"map_id": map_id,
		"party_ids": party,
		"selected_stage_id": selected,
		"unlocked_stage_ids": _unique_sorted_strings(unlocked),
		"stage_ids": stage_ids,
		"entity_ids": entities,
		"requires_boss_background": boss_required,
	}


func cache_hit_for_stage_select(map_id: String, definition: Dictionary, party_ids: Array, selected_stage_id := "", unlocked_stage_ids := []) -> bool:
	var signature := signature_for(map_id, definition, party_ids, selected_stage_id, unlocked_stage_ids)
	return not ready_signature.is_empty() and ready_signature == signature and not _cache.is_empty()


func cache_hit_for_map_entry(map_id: String, definition: Dictionary, party_ids: Array, selected_stage_id := "", unlocked_stage_ids := []) -> bool:
	var signature := signature_for(map_id, definition, party_ids, selected_stage_id, unlocked_stage_ids)
	return not map_ready_signature.is_empty() and map_ready_signature == signature and not _cache.is_empty()


func cancel_warmup() -> void:
	_generation += 1
	if warming:
		warming = false
		_active_signature = ""
		_warm_started_msec = 0
		_set_progress(0.0, "CANCELLED")


func _warmup_deadline_exceeded(started_msec: int) -> bool:
	return started_msec > 0 and Time.get_ticks_msec() - started_msec >= WARMUP_DEADLINE_MSEC


func warm_for_stage_select(map_id: String, definition: Dictionary, party_ids: Array, selected_stage_id := "", unlocked_stage_ids := []) -> bool:
	var plan := target_plan(map_id, definition, party_ids, selected_stage_id, unlocked_stage_ids)
	var signature := signature_for(map_id, definition, party_ids, selected_stage_id, unlocked_stage_ids)
	if cache_hit_for_stage_select(map_id, definition, party_ids, selected_stage_id, unlocked_stage_ids):
		_set_progress(1.0, "READY")
		return true
	if warming and _active_signature == signature:
		while warming and _active_signature == signature:
			if _warmup_deadline_exceeded(_warm_started_msec):
				cancel_warmup()
				return false
			await get_tree().process_frame
		return ready_signature == signature

	cancel_warmup()
	_generation += 1
	var generation := _generation
	_active_signature = signature
	warming = true
	_warm_started_msec = Time.get_ticks_msec()
	_set_progress(0.0, "PLAN")
	var pending := _empty_bundle(plan)
	var tasks := _build_tasks(plan)
	var complete := true
	var total := maxi(1, tasks.size())
	var slice_started_usec := Time.get_ticks_usec()
	for index in range(tasks.size()):
		if generation != _generation:
			return false
		if _warmup_deadline_exceeded(_warm_started_msec):
			complete = false
			break
		var task: Dictionary = tasks[index]
		_set_progress(float(index) / float(total), str(task.get("phase", "LOAD")))
		if not _load_task(task, pending):
			complete = false
		# A browser frame is yielded by elapsed work budget, not once per tiny JSON or
		# cached resource lookup. The old one-task/one-frame policy added seconds of
		# artificial latency even when every operation completed in microseconds.
		if not OS.has_feature("web") or index == tasks.size() - 1 or Time.get_ticks_usec() - slice_started_usec >= 9000:
			await get_tree().process_frame
			slice_started_usec = Time.get_ticks_usec()
	if generation != _generation:
		return false

	_finalize_bundle(pending)
	warming = false
	_active_signature = ""
	_warm_started_msec = 0
	if complete:
		_cache = pending # Atomic replacement: consumers never observe a partial bundle.
		ready_signature = signature
		map_ready_signature = signature
		_set_progress(1.0, "READY")
	else:
		_set_progress(0.0, "FAILED")
	warmup_finished.emit(signature, complete)
	return complete


func warm_map_for_stage_select(map_id: String, definition: Dictionary, party_ids: Array, selected_stage_id := "", unlocked_stage_ids := []) -> bool:
	# Stage entry owns the map and its visible pawns. Projectile atlases, battle
	# backgrounds and cast/impact VFX belong to the separately permitted BATTLE
	# loading boundary; decoding all of them here exceeded the five-second map
	# budget and retained tens of MiB that the chapter map could not display.
	var plan := target_plan(map_id, definition, party_ids, selected_stage_id, unlocked_stage_ids)
	var signature := signature_for(map_id, definition, party_ids, selected_stage_id, unlocked_stage_ids)
	if cache_hit_for_map_entry(map_id, definition, party_ids, selected_stage_id, unlocked_stage_ids):
		_set_progress(1.0, "MAP_READY")
		return true
	if warming and _active_signature == signature:
		while warming and _active_signature == signature:
			if _warmup_deadline_exceeded(_warm_started_msec):
				cancel_warmup()
				return false
			await get_tree().process_frame
		return cache_hit_for_map_entry(map_id, definition, party_ids, selected_stage_id, unlocked_stage_ids)

	cancel_warmup()
	_generation += 1
	var generation := _generation
	_active_signature = signature
	warming = true
	_warm_started_msec = Time.get_ticks_msec()
	_set_progress(0.0, "MAP_PLAN")
	var pending := _empty_bundle(plan)
	var tasks := _build_map_tasks(plan)
	var complete := true
	var total := maxi(1, tasks.size())
	var slice_started_usec := Time.get_ticks_usec()
	for index in range(tasks.size()):
		if generation != _generation:
			return false
		if _warmup_deadline_exceeded(_warm_started_msec):
			complete = false
			break
		var task: Dictionary = tasks[index]
		_set_progress(float(index) / float(total), str(task.get("phase", "MAP_LOAD")))
		if not _load_task(task, pending):
			complete = false
		if not OS.has_feature("web") or index == tasks.size() - 1 or Time.get_ticks_usec() - slice_started_usec >= 9000:
			await get_tree().process_frame
			slice_started_usec = Time.get_ticks_usec()
	if generation != _generation:
		return false

	_finalize_map_bundle(pending)
	warming = false
	_active_signature = ""
	_warm_started_msec = 0
	if complete:
		_cache = pending
		ready_signature = ""
		map_ready_signature = signature
		_set_progress(1.0, "MAP_READY")
	else:
		_set_progress(0.0, "FAILED")
	warmup_finished.emit(signature, complete)
	return complete


func map_idle_pack(id: String) -> Dictionary:
	return (_cache.get("map_idle_packs", {}) as Dictionary).get(id, {})


func battle_bundle(entity_ids: Array, require_boss := false) -> Dictionary:
	if not has_battle_assets(entity_ids, require_boss):
		return {}
	var requested := _unique_sorted_strings(entity_ids)
	var bundle := {
		"entity_ids": requested,
		"require_boss": require_boss,
		"actor_manifests": {}, "actor_atlases": {}, "actor_frames": {},
		"projectile_manifests": {}, "projectile_atlases": {}, "projectile_frames": {},
		"vfx_atlases": {}, "vfx_frames": {}, "fallback_previews": {},
		"normal_background": _cache.get("normal_background"),
		"boss_background": _cache.get("boss_background"),
		"battle_font": _cache.get("battle_font"),
	}
	for id in requested:
		for key in ["actor_manifests", "actor_atlases", "actor_frames", "projectile_manifests", "projectile_atlases", "projectile_frames", "fallback_previews"]:
			(bundle[key] as Dictionary)[id] = (_cache.get(key, {}) as Dictionary).get(id)
		for vfx_key in (_cache.get("vfx_atlases", {}) as Dictionary):
			if str(vfx_key).begins_with("base_") or str(vfx_key).begins_with(id.to_lower() + "_"):
				(bundle["vfx_atlases"] as Dictionary)[vfx_key] = (_cache.vfx_atlases as Dictionary)[vfx_key]
				(bundle["vfx_frames"] as Dictionary)[vfx_key] = (_cache.vfx_frames as Dictionary)[vfx_key]
	return bundle


func has_battle_assets(entity_ids: Array, require_boss := false) -> bool:
	if _cache.is_empty() or _cache.get("normal_background") == null or _cache.get("battle_font") == null:
		return false
	if require_boss and _cache.get("boss_background") == null:
		return false
	for id in _unique_sorted_strings(entity_ids):
		if not (_cache.get("actor_manifests", {}) as Dictionary).has(id) or not (_cache.get("actor_frames", {}) as Dictionary).has(id):
			return false
		if not (_cache.get("projectile_manifests", {}) as Dictionary).has(id) or not (_cache.get("projectile_frames", {}) as Dictionary).has(id):
			return false
	var cached_vfx: Dictionary = _cache.get("vfx_frames", {})
	for key in _required_vfx_keys(_unique_sorted_strings(entity_ids)):
		var frames_value = cached_vfx.get(key, [])
		if not frames_value is Array or frames_value.size() != 12:
			return false
	return true


func gpu_warm_textures() -> Array[Texture2D]:
	## Returns unique immutable backing textures for a renderer-owned, one-per-
	## frame warm pass. This cache itself never creates a viewport or draws.
	var result: Array[Texture2D] = []
	for texture_value in _textures_from_bundle(_cache):
		if texture_value is Texture2D and not result.has(texture_value):
			result.append(texture_value)
	return result


func _empty_bundle(plan: Dictionary) -> Dictionary:
	return {
		"plan": plan,
		"actor_manifests": {}, "actor_atlases": {}, "actor_frames": {},
		"projectile_manifests": {}, "projectile_atlases": {}, "projectile_frames": {},
		"vfx_atlases": {}, "vfx_frames": {}, "fallback_previews": {}, "map_idle_packs": {},
		"normal_background": null, "boss_background": null, "battle_font": null,
	}


func _build_tasks(plan: Dictionary) -> Array:
	var tasks: Array = []
	for entity_id in plan.get("entity_ids", []):
		tasks.append({"kind": "actor_manifest", "id": entity_id, "phase": "ACTOR_MANIFEST:%s" % entity_id})
		tasks.append({"kind": "actor_atlas", "id": entity_id, "phase": "ACTOR_ATLAS:%s" % entity_id})
		tasks.append({"kind": "projectile_manifest", "id": entity_id, "phase": "PROJECTILE_MANIFEST:%s" % entity_id})
		tasks.append({"kind": "projectile_atlas", "id": entity_id, "phase": "PROJECTILE_ATLAS:%s" % entity_id})
		tasks.append({"kind": "preview", "id": entity_id, "phase": "PREVIEW:%s" % entity_id})
	tasks.append({"kind": "normal_background", "phase": "BATTLE_BACKGROUND"})
	if bool(plan.get("requires_boss_background", false)):
		tasks.append({"kind": "boss_background", "phase": "BOSS_BACKGROUND"})
	tasks.append({"kind": "font", "phase": "BATTLE_FONT"})
	for key in _required_vfx_keys(plan.get("entity_ids", [])):
		tasks.append({"kind": "vfx", "key": key, "phase": "VFX:%s" % key})
	return tasks


func _build_map_tasks(plan: Dictionary) -> Array:
	var tasks: Array = []
	for entity_id in plan.get("entity_ids", []):
		tasks.append({"kind": "actor_manifest", "id": entity_id, "phase": "MAP_ACTOR_MANIFEST:%s" % entity_id})
		tasks.append({"kind": "actor_atlas", "id": entity_id, "phase": "MAP_ACTOR_ATLAS:%s" % entity_id})
	return tasks


func _load_task(task: Dictionary, pending: Dictionary) -> bool:
	var kind := str(task.get("kind", ""))
	var id := str(task.get("id", ""))
	match kind:
		"actor_manifest":
			var manifest := _read_json("%s/%s/animation_manifest.json" % [COMBAT_ROOT, id])
			if manifest.is_empty(): return false
			pending.actor_manifests[id] = manifest
		"actor_atlas":
			var actor_manifest: Dictionary = pending.actor_manifests.get(id, {})
			var atlas_path := str(actor_manifest.get("atlas_path", "atlas.png"))
			var atlas := load("%s/%s/%s" % [COMBAT_ROOT, id, atlas_path]) as Texture2D
			if atlas == null: return false
			pending.actor_atlases[id] = atlas
		"projectile_manifest":
			var projectile_manifest := _read_json("%s/%s/projectile_manifest.json" % [PROJECTILE_ROOT, id])
			if projectile_manifest.is_empty(): return false
			pending.projectile_manifests[id] = projectile_manifest
		"projectile_atlas":
			var projectile: Dictionary = pending.projectile_manifests.get(id, {})
			var projectile_path := str(projectile.get("atlas_path", "atlas.png"))
			var projectile_atlas := load("%s/%s/%s" % [PROJECTILE_ROOT, id, projectile_path]) as Texture2D
			if projectile_atlas == null: return false
			pending.projectile_atlases[id] = projectile_atlas
		"preview":
			var preview := load("%s/%s/preview.png" % [COMBAT_ROOT, id]) as Texture2D
			if preview == null: return false
			pending.fallback_previews[id] = preview
		"normal_background":
			pending.normal_background = load(NORMAL_BACKGROUND_PATH) as Texture2D
			return pending.normal_background != null
		"boss_background":
			pending.boss_background = load(BOSS_BACKGROUND_PATH) as Texture2D
			return pending.boss_background != null
		"font":
			pending.battle_font = load(BATTLE_FONT_PATH) as Font
			return pending.battle_font != null
		"vfx":
			var key := str(task.get("key", ""))
			var vfx := load("res://assets/runtime_web/vfx/vfx_%s/atlas.png" % key) as Texture2D
			if vfx == null: return false
			pending.vfx_atlases[key] = vfx
		_:
			return false
	return true


func _finalize_bundle(pending: Dictionary) -> void:
	for id in pending.actor_atlases:
		var manifest: Dictionary = pending.actor_manifests.get(id, {})
		var animations: Dictionary = manifest.get("animations", {})
		var actor_frames: Dictionary = {}
		var frame_size: Array = manifest.get("frame_size", [104, 104])
		var columns := maxi(1, int(manifest.get("atlas_columns", 1)))
		for animation_name in animations:
			var animation: Dictionary = animations[animation_name]
			var frames: Array[Texture2D] = []
			for index_value in animation.get("frame_indices", []):
				frames.append(_atlas_frame(pending.actor_atlases[id], int(index_value), columns, frame_size))
			if not frames.is_empty():
				actor_frames[animation_name] = frames
		pending.actor_frames[id] = actor_frames
		var idle: Dictionary = animations.get("idle", {})
		var indices: Array = idle.get("frame_indices", [])
		if indices.is_empty(): indices = [0]
		var first_frame := int(indices[0])
		var texture := _atlas_frame(pending.actor_atlases[id], first_frame, columns, frame_size)
		var foot_anchor: Array = manifest.get("foot_anchor", [0.5, 0.88])
		pending.map_idle_packs[id] = {"source_id": id, "texture": texture, "frame_size": Vector2(float(frame_size[0]), float(frame_size[1])), "columns": columns, "animations": animations, "idle_frame_indices": indices.slice(0, mini(8, indices.size())), "idle_fps": float(idle.get("fps", 12.0)), "foot_anchor": Vector2(float(foot_anchor[0]), float(foot_anchor[1]))}
	for id in pending.projectile_atlases:
		var projectile_manifest: Dictionary = pending.projectile_manifests.get(id, {})
		var projectile_size: Array = projectile_manifest.get("frame_size", [96, 96])
		var projectile_columns := maxi(1, int(projectile_manifest.get("atlas_columns", 1)))
		var projectile_frames: Array[Texture2D] = []
		for index_value in projectile_manifest.get("frame_indices", []):
			projectile_frames.append(_atlas_frame(pending.projectile_atlases[id], int(index_value), projectile_columns, projectile_size))
		pending.projectile_frames[id] = projectile_frames
	for key in pending.vfx_atlases:
		var vfx_frames: Array[Texture2D] = []
		for frame in range(12):
			vfx_frames.append(_atlas_frame(pending.vfx_atlases[key], frame, 4, [112, 112]))
		pending.vfx_frames[key] = vfx_frames


func _finalize_map_bundle(pending: Dictionary) -> void:
	for id in pending.actor_atlases:
		var manifest: Dictionary = pending.actor_manifests.get(id, {})
		var animations: Dictionary = manifest.get("animations", {})
		var frame_size: Array = manifest.get("frame_size", [104, 104])
		var columns := maxi(1, int(manifest.get("atlas_columns", 1)))
		var idle: Dictionary = animations.get("idle", {})
		var indices: Array = idle.get("frame_indices", [])
		if indices.is_empty():
			indices = [0]
		var texture := _atlas_frame(pending.actor_atlases[id], int(indices[0]), columns, frame_size)
		var foot_anchor: Array = manifest.get("foot_anchor", [0.5, 0.88])
		pending.map_idle_packs[id] = {
			"source_id": id,
			"texture": texture,
			"frame_size": Vector2(float(frame_size[0]), float(frame_size[1])),
			"columns": columns,
			"animations": animations,
			"idle_frame_indices": indices.slice(0, mini(8, indices.size())),
			"idle_fps": float(idle.get("fps", 12.0)),
			"foot_anchor": Vector2(float(foot_anchor[0]), float(foot_anchor[1])),
		}


func _atlas_frame(atlas: Texture2D, index: int, columns: int, frame_size: Array) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(float(index % columns) * float(frame_size[0]), float(index / columns) * float(frame_size[1]), float(frame_size[0]), float(frame_size[1]))
	return texture


func _required_vfx_keys(entity_ids: Array) -> Array[String]:
	# This is the canonical runtime contract, not a broad manifest scan. It avoids
	# a second synchronous JSON read during stage-select planning and matches the
	# VFX keys BattleView can emit for each participating entity.
	var keys: Array[String] = ["base_signal_breaker_ultimate"]
	for entity_id in entity_ids:
		for kind in ["basic", "normal", "ultimate"]:
			var key := "%s_%s" % [str(entity_id).to_lower(), kind]
			if not keys.has(key):
				keys.append(key)
	return keys


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _unique_sorted_strings(values: Array) -> Array[String]:
	var result := _unique_strings(values)
	result.sort()
	return result


func _unique_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var id := str(value).strip_edges()
		if not id.is_empty() and not result.has(id): result.append(id)
	return result


func _unlocked_stage_ids_from_definition(definition: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var state := get_tree().root.get_node_or_null("AppState")
	if state == null or not state.has_method("is_stage_unlocked"):
		return result
	for node_value in definition.get("nodes", []):
		if not node_value is Dictionary:
			continue
		var stage_id := str((node_value as Dictionary).get("stage_id", "")).strip_edges()
		if not stage_id.is_empty() and bool(state.call("is_stage_unlocked", stage_id)) and not result.has(stage_id):
			result.append(stage_id)
	result.sort()
	return result


func _textures_from_bundle(bundle: Dictionary) -> Array:
	var result: Array = []
	for value in bundle.values():
		if value is Texture2D:
			result.append(value)
		elif value is Dictionary:
			result.append_array(_textures_from_bundle(value))
	return result


func _set_progress(value: float, phase: String) -> void:
	progress_value = clampf(value, 0.0, 1.0)
	progress_phase = phase
	warmup_progress_changed.emit(progress_value, progress_phase)
