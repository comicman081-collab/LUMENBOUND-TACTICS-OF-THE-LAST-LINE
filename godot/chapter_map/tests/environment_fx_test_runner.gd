extends Node

const EnvironmentFXControllerScript := preload("res://chapter_map/presentation/environment_fx_controller.gd")
const ChapterMapLoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const HexGridScript := preload("res://chapter_map/model/hex_grid.gd")
const MapExplorationServiceScript := preload("res://chapter_map/model/map_exploration_service.gd")

var passed := 0
var failed := 0
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, name: String, details := "") -> void:
	if condition:
		passed += 1
		print("PASS | ", name)
	else:
		failed += 1
		failures.append(name + (": " + details if not details.is_empty() else ""))
		printerr("FAIL | ", name, " | ", details)

func _run() -> void:
	print("R16 ENVIRONMENT FX TESTS | Godot ", Engine.get_version_info().get("string", "unknown"))
	_test_presets_and_transition()
	_test_authority_isolation()
	_test_quality_and_resource_bounds()
	print("R16_ENVIRONMENT_TEST_SUMMARY total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	if not failures.is_empty(): print("FAILURES=", JSON.stringify(failures))
	get_tree().quit(0 if failed == 0 else 1)

func _test_presets_and_transition() -> void:
	var controller = EnvironmentFXControllerScript.new()
	add_child(controller)
	var expected := ["CLEAR_DAY", "MIST_DAY", "DUSK", "NIGHT", "NIGHT_RAIN", "STORM"]
	check(controller.preset_ids() == expected, "R16_ENV_01 canonical preset set is complete")
	for preset_id in expected:
		var values: Dictionary = controller.preset_values(preset_id)
		check(float(values.get("brightness", 0.0)) > 0.0 and float(values.get("brightness", 2.0)) <= 1.2, "R16_ENV_02 %s brightness is compatibility-safe" % preset_id)
		check(float(values.get("fog_density", -1.0)) >= 0.0 and float(values.get("rain", -1.0)) >= 0.0 and float(values.get("rain", 2.0)) <= 1.0, "R16_ENV_03 %s fog/rain ranges are valid" % preset_id)
	controller.set_preset("NIGHT_RAIN", 1.0)
	controller._process(0.35)
	check(controller.active_preset != "NIGHT_RAIN" and controller.transition_progress() > 0.0 and controller.transition_progress() < 1.0, "R16_TRANSITION_01 preset transition interpolates instead of hard-cutting")
	controller._process(0.70)
	check(controller.active_preset == "NIGHT_RAIN" and is_equal_approx(controller.transition_progress(), 1.0), "R16_TRANSITION_02 transition reaches authored target")
	var rain_values: Dictionary = controller.current_values
	controller.set_preset("STORM", 0.5)
	controller._process(0.5)
	check(float(controller.current_values.get("rain", 0.0)) > float(rain_values.get("rain", 0.0)) and float(controller.current_values.get("fog_density", 0.0)) > float(rain_values.get("fog_density", 0.0)), "R16_ENV_04 storm is visibly denser than night rain")
	controller.queue_free()

func _test_authority_isolation() -> void:
	var definition: Dictionary = ChapterMapLoaderScript.load_map("CH01_MAP")
	var grid = HexGridScript.new()
	grid.load_tiles(definition.get("tiles", []))
	# Resolve the canonical map container before snapshotting. The legacy service
	# may add its already-existing map block on first access; that initialization
	# is explicitly outside the environment controller being tested.
	var map_before := AppState.chapter_map_state("CH01_MAP").duplicate(true)
	var profile_before := AppState.profile.duplicate(true)
	var battle_seed_before := AppState.battle_seed
	var save_schema_before := AppState.SAVE_SCHEMA_VERSION
	var controller = EnvironmentFXControllerScript.new()
	add_child(controller)
	for preset_id in controller.preset_ids():
		controller.set_preset(preset_id, 0.5)
		controller._process(0.5)
		controller.set_transient_map_context(Vector2i(90, 0), true)
		controller._process(0.9)
	check(AppState.profile == profile_before, "R16_AUTHORITY_01 environment leaves profile/reward/growth exact")
	check(AppState.chapter_map_state("CH01_MAP") == map_before, "R16_AUTHORITY_02 environment leaves canonical map state exact")
	check(AppState.battle_seed == battle_seed_before, "R16_AUTHORITY_03 environment leaves battle RNG seed exact")
	check(AppState.SAVE_SCHEMA_VERSION == save_schema_before, "R16_AUTHORITY_04 environment adds no save-schema mutation")
	var map_copy := map_before.duplicate(true)
	MapExplorationServiceScript.ensure_state(map_copy, definition, grid)
	check(map_copy.get("current_party_hex", []) == map_before.get("current_party_hex", []), "R16_AUTHORITY_05 transient weather does not alter map coordinate repair")
	controller.queue_free()

func _test_quality_and_resource_bounds() -> void:
	var controller = EnvironmentFXControllerScript.new()
	add_child(controller)
	controller.set_quality_tier("LOW")
	check(controller.quality_tier == "LOW", "R16_QUALITY_01 low tier is available")
	controller.set_quality_tier("HIGH")
	check(controller.quality_tier == "HIGH", "R16_QUALITY_02 high tier is available")
	var child_count := controller.get_child_count()
	for index in range(100):
		for preset_id in ["CLEAR_DAY", "NIGHT_RAIN", "STORM", "CLEAR_DAY"]:
			controller.set_preset(preset_id, 0.5)
			controller._process(0.5)
	check(controller.get_child_count() == child_count and controller.rain_rects.size() == 0, "R16_LEAK_01 100 transitions create no unbounded FX nodes")
	var source := FileAccess.get_file_as_string("res://chapter_map/presentation/environment_fx_controller.gd")
	check(not source.contains("AppState.") and not source.contains("SaveService.") and not source.contains("RandomNumberGenerator"), "R16_AUTHORITY_06 presentation controller has no gameplay/save/RNG dependency")
	check(source.contains("if portrait:") and source.contains("viewport_size.x * 0.045") and source.contains("PRESET_TOP_LEFT"), "R16_UI_01 portrait development FX panel derives an unclipped viewport-relative sheet")
	controller.queue_free()
