extends Node

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS | ", message)
	else:
		failures.append(message)
		printerr("FAIL | ", message)


func _run() -> void:
	var definition_value = JSON.parse_string(FileAccess.get_file_as_string("res://data/compiled/chapter_maps/CH01_MAP.json"))
	_check(definition_value is Dictionary, "chapter map test definition parses")
	if not definition_value is Dictionary:
		get_tree().quit(1)
		return
	var definition: Dictionary = definition_value
	var party: Array[String] = ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005"]
	var cache := get_tree().root.get_node_or_null("StageAssetCache")
	_check(cache != null, "StageAssetCache autoload is present")
	if cache == null:
		get_tree().quit(1)
		return
	var plan: Dictionary = cache.target_plan("CH01_MAP", definition, party, "CH01-N01", [])
	_check(str(plan.get("stage_ids", [""])[0]) == "CH01-N01", "selected stage remains the first preload target")
	_check((plan.get("unlocked_stage_ids", []) as Array).has("CH01-N01"), "empty unlock input derives available node stages from AppState")
	_check(await cache.warm_for_stage_select("CH01_MAP", definition, party, "CH01-N01", []), "focused stage cache warmup completes")
	_check(cache.cache_hit_for_stage_select("CH01_MAP", definition, party, "CH01-N01", []), "completed signature is reused")
	var entities: Array[String] = []
	for entity_value in DataRegistry.stage("CH01-N01").get("waves", []):
		for id_value in entity_value:
			var id := str(id_value)
			if not entities.has(id): entities.append(id)
	entities.append_array(party)
	_check(cache.has_battle_assets(entities, false), "battle frames and VFX are retained for selected stage")
	_check(not cache.map_idle_pack("CHR001").is_empty(), "map idle pack retains an actor atlas frame")
	_check(not cache.gpu_warm_textures().is_empty(), "renderer warm list exposes retained backing textures")
	print("STAGE_ASSET_CACHE_SUMMARY fail=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
