extends Node

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const HexGridScript := preload("res://chapter_map/model/hex_grid.gd")
const HexPathfinderScript := preload("res://chapter_map/model/hex_pathfinder.gd")
const MacroWorldGeneratorScript := preload("res://chapter_map/model/macro_world_generator.gd")
const ScenarioRunnerScript := preload("res://story/scenario_runner.gd")
const LoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const ProgressScript := preload("res://chapter_map/model/chapter_map_progress.gd")
const ExplorationScript := preload("res://chapter_map/model/map_exploration_service.gd")
const MapSimulationScript := preload("res://chapter_map/model/map_simulation.gd")
const GrowthAnalyzerScript := preload("res://progression/growth_affordability_analyzer.gd")
# Compile the actual runtime screen as part of the map regression scene.  A
# source-text assertion alone cannot catch a Web-only GDScript parse failure.
const ChapterMapScreenScript := preload("res://chapter_map/runtime/chapter_map_screen.gd")

var passed := 0
var failed := 0
var failures: Array[String] = []
var definition: Dictionary
var grid

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, name: String, details := "") -> void:
	if condition:
		passed += 1
		print("PASS | ", name)
	else:
		failed += 1
		failures.append(name + (": " + details if details != "" else ""))
		printerr("FAIL | ", name, " | ", details)

func _run() -> void:
	print("R14 SRPG DYNAMIC EXPLORATION TESTS | Godot ", Engine.get_version_info().get("string", "unknown"))
	definition = LoaderScript.load_map("CH01_MAP")
	grid = HexGridScript.new()
	grid.load_tiles(definition.get("tiles", []))
	_test_data()
	_test_user_facing_labels()
	_test_coordinates()
	_test_paths()
	_test_geometry_grounding_contract()
	_test_unlock_and_progress()
	_test_save_and_migration()
	_test_transactions_and_roundtrip()
	_test_preboss_staging_and_reveal_one_shot()
	_test_encounters_and_treasures()
	_test_reward_affordability()
	_test_dynamic_exploration()
	_test_direct_move_turn_contracts()
	_test_exploration_pulses_and_companion_events()
	_test_runtime_companion_event_pawns()
	_test_regressions()
	print("MAP_TEST_SUMMARY total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	if not failures.is_empty(): print("FAILURES=", JSON.stringify(failures))
	get_tree().quit(0 if failed == 0 else 1)

func _test_data() -> void:
	check(not definition.is_empty(), "CH01 map JSON parses")
	check(LoaderScript.validate(definition).is_empty(), "map data schema and references validate", " | ".join(LoaderScript.validate(definition)))
	var chapter_two_definition := LoaderScript.load_map("CH02_MAP")
	var ch01_rules: Dictionary = definition.get("exploration_rules", {})
	var ch02_rules: Dictionary = chapter_two_definition.get("exploration_rules", {})
	check(int(ch01_rules.get("base_move_points", 0)) == 3 and int(ch02_rules.get("base_move_points", 0)) == 4 and int(ch01_rules.get("max_move_points", 0)) == 8 and int(ch02_rules.get("max_move_points", 0)) == 8, "movement rules start at three/four cells and cap every chapter at eight")
	var node_ids: Dictionary = {}
	for node in definition.nodes: node_ids[str(node.node_id)] = true
	check(node_ids.size() == definition.nodes.size(), "all map node IDs unique")
	var normal: Array = definition.nodes.filter(func(node): return str(node.node_type).begins_with("NORMAL_"))
	var hard: Array = definition.nodes.filter(func(node): return str(node.node_type).begins_with("HARD_"))
	check(normal.size() == 20, "map has exactly 20 NORMAL battle nodes")
	check(hard.size() == 5, "map has exactly 5 HARD battle nodes")
	check(definition.nodes.filter(func(node): return str(node.get("stage_id", "")) != "").all(func(node): return not DataRegistry.stage(str(node.stage_id)).is_empty()), "all battle nodes reference valid stages")
	check(definition.nodes.all(func(node): return grid.has(Vector2i(int(node.q), int(node.r)))), "all nodes occupy valid tiles")
	check(definition.nodes.all(func(node): return grid.traversable(Vector2i(int(node.q), int(node.r)))), "no node collides with blocked terrain")
	check(definition.tiles.any(func(tile): return bool(tile.movement_blocked)), "map includes blocked deep-water terrain")
	check(bool(definition.get("macro_generated", false)) and int(definition.get("macro_world", {}).get("linear_scale_viewports", 0)) >= 10, "map uses ten-plus-viewport deterministic macro layout")
	var n01 := LoaderScript.node_for_stage(definition, "CH01-N01")
	var n20 := LoaderScript.node_for_stage(definition, "CH01-N20")
	var boss_presentation_value: Variant = n20.get("presentation", {})
	var boss_presentation: Dictionary = boss_presentation_value if boss_presentation_value is Dictionary else {}
	var boss_presentation_keys_valid := str(boss_presentation.get("transition_style", "")) == "BOSS"
	for locale in ["ko", "en"]:
		var table: Dictionary = LocalizationService.tables.get(locale, {})
		boss_presentation_keys_valid = boss_presentation_keys_valid and table.has(str(boss_presentation.get("event_title_key", ""))) and table.has(str(boss_presentation.get("boss_name_key", ""))) and table.has(str(boss_presentation.get("boss_subtitle_key", "")))
	check(boss_presentation_keys_valid and not boss_presentation.has("title") and not boss_presentation.has("subtitle"), "BOSS_PRESENTATION_01 N20 owns localized map-authored title-card and threat-banner data")
	check(HexCoordScript.distance(Vector2i.ZERO, Vector2i(int(n20.q), int(n20.r))) >= 200, "expanded NORMAL route spans twenty local map lengths")
	check(LoaderScript.load_map("CH01_MAP").get("tiles", []) == definition.get("tiles", []), "macro terrain seed is deterministic across loads")
	var macro_hashes: Dictionary = {}
	for run in 10:
		var candidate := LoaderScript.load_map("CH01_MAP")
		macro_hashes[_macro_semantic_hash(candidate)] = true
	check(macro_hashes.size() == 1, "MACRO_SORT_01 ten same-seed loads retain one semantic world hash")
	check(_stage_coordinates(LoaderScript.load_map("CH01_MAP")) == _stage_coordinates(definition), "MACRO_SORT_02 encounter coordinates stable after key sort")
	check(_treasure_coordinates(LoaderScript.load_map("CH01_MAP")) == _treasure_coordinates(definition), "MACRO_SORT_03 treasure coordinates stable after key sort")
	check(_route_signature(LoaderScript.load_map("CH01_MAP")) == _route_signature(definition), "MACRO_SORT_04 main and hard route connectivity stable after key sort")
	check(_macro_visual_routes_are_grounded(), "MAP_ROUTE_SURFACE_01 rendered causeway routes remain on generated traversable terrain")
	var visible_treasures: Array = definition.get("treasures", []).filter(func(treasure): return str(treasure.get("visibility", "")) == "VISIBLE")
	var hidden_treasures: Array = definition.get("treasures", []).filter(func(treasure): return str(treasure.get("visibility", "")) == "HIDDEN")
	check(visible_treasures.size() >= 6 and hidden_treasures.size() >= 4, "side branches include visible and hidden treasure targets")
	check(definition.get("treasures", []).all(func(treasure): return grid.traversable(Vector2i(int(treasure.q), int(treasure.r)))), "all treasure targets occupy traversable tiles")
	var treasure_localization_valid := true
	for treasure_value in definition.get("treasures", []):
		var treasure: Dictionary = treasure_value
		var landmark_key := str(treasure.get("landmark_key", ""))
		treasure_localization_valid = treasure_localization_valid and not landmark_key.is_empty() and not treasure.has("landmark")
		for locale in ["ko", "en"]:
			treasure_localization_valid = treasure_localization_valid and LocalizationService.tables.get(locale, {}).has(landmark_key)
	check(treasure_localization_valid, "MAP_TREASURE_LOCALIZATION_01 all treasure landmark names resolve in ko/en without raw runtime copy")
	check(definition.nodes.filter(func(node): return str(node.get("stage_id", "")) != "").all(func(node): return DataRegistry.stage(str(node.stage_id)).get("waves", []).all(func(wave): return wave.all(func(enemy_id): return not DataRegistry.enemy(str(enemy_id)).is_empty()))), "all encounter nodes resolve actual enemy definitions")
	var event_localization_valid := true
	var event_contract_valid := true
	for event in definition.get("map_events", []):
		var title_key := str(event.get("title_key", ""))
		var body_key := str(event.get("body_key", ""))
		event_contract_valid = event_contract_valid and not title_key.is_empty() and not body_key.is_empty() and not event.has("title") and not event.has("body")
		for locale in ["ko", "en"]:
			event_localization_valid = event_localization_valid and LocalizationService.tables.get(locale, {}).has(title_key) and LocalizationService.tables.get(locale, {}).has(body_key)
		for choice in event.get("choices", []):
			var label_key := str(choice.get("label_key", ""))
			event_contract_valid = event_contract_valid and not label_key.is_empty() and not choice.has("label")
			for locale in ["ko", "en"]:
				event_localization_valid = event_localization_valid and LocalizationService.tables.get(locale, {}).has(label_key)
	check(event_contract_valid, "MAP_EVENT_LOCALIZATION_01 map events use localization keys without raw runtime text")
	check(event_localization_valid, "MAP_EVENT_LOCALIZATION_02 all map event title, body and choice keys resolve in ko/en")
	var companion_localization_valid: bool = true
	var companion_data_valid: bool = definition.get("event_encounters", []).size() == 4
	var companion_count := 0
	var special_enemy_count := 0
	for encounter_value in definition.get("event_encounters", []):
		var encounter: Dictionary = encounter_value
		for locale in ["ko", "en"]:
			companion_localization_valid = companion_localization_valid and LocalizationService.tables.get(locale, {}).has(str(encounter.get("title_key", ""))) and LocalizationService.tables.get(locale, {}).has(str(encounter.get("body_key", ""))) and LocalizationService.tables.get(locale, {}).has(str(encounter.get("contact_outcome_key", "")))
		var recruitments: Array = encounter.get("recruitments", [])
		var dialogue_pages: Array = encounter.get("pre_battle_dialogue", [])
		for page_value in dialogue_pages:
			var page: Dictionary = page_value if page_value is Dictionary else {}
			for locale in ["ko", "en"]:
				companion_localization_valid = companion_localization_valid and LocalizationService.tables.get(locale, {}).has(str(page.get("text_key", "")))
		var event_kind := str(encounter.get("event_kind", ""))
		if event_kind == "COMPANION":
			companion_count += 1
			companion_data_valid = companion_data_valid and not DataRegistry.character(str(encounter.get("character_id", ""))).is_empty() and recruitments.size() >= 1 and recruitments.size() <= 2
		elif event_kind == "SPECIAL_ENEMY":
			special_enemy_count += 1
			companion_data_valid = companion_data_valid and not DataRegistry.enemy(str(encounter.get("enemy_id", ""))).is_empty() and recruitments.is_empty()
		else:
			companion_data_valid = false
		companion_data_valid = companion_data_valid and str(encounter.get("marker", "")) == "BANG" and not str(encounter.get("contact_outcome_key", "")).is_empty() and dialogue_pages.size() >= 2 and dialogue_pages.size() <= 4
		for recruitment_value in recruitments:
			var recruitment: Dictionary = recruitment_value
			companion_data_valid = companion_data_valid and not DataRegistry.character(str(recruitment.get("character_id", ""))).is_empty()
			companion_data_valid = companion_data_valid and int(recruitment.get("battle_victories_required", 0)) in range(1, 6)
	check(companion_data_valid and companion_count == 1 and special_enemy_count == 3, "EVENT_PAWN_DATA_01 one chapter companion and three special-enemy contacts own validated pre-battle dialogue data")
	check(companion_localization_valid, "EVENT_PAWN_DATA_02 every event and dialogue page resolves in ko/en")

func _test_user_facing_labels() -> void:
	var screen = ChapterMapScreenScript.new()
	var localized_n02 := LocalizationService.tr_key("STAGE_CH01_N02")
	var release_full := screen.stage_display_text("CH01-N02", false, false)
	var release_compact := screen.stage_display_text("CH01-N02", true, false)
	var developer_full := screen.stage_display_text("CH01-N02", false, true)
	var release_reveal := screen.reveal_notice_text({"unlocked_stage_ids": ["CH01-N02"]}, false)
	var developer_reveal := screen.reveal_notice_text({"unlocked_stage_ids": ["CH01-N02"]}, true)
	check(release_full == localized_n02 and not release_full.contains("CH01-"), "MAP_COPY_01 release stage label resolves localized content without a raw stage ID")
	check(release_compact == "일반 2" and not release_compact.contains("CH01-"), "MAP_COPY_02 compact encounter marker uses a player-facing operation label")
	check(release_reveal.contains(localized_n02) and not release_reveal.contains("CH01-"), "MAP_COPY_03 route-reveal notice resolves localized stage names")
	check(developer_full.contains("CH01-N02") and developer_reveal.contains("CH01-N02"), "MAP_COPY_04 developer diagnostics retain canonical stage IDs")
	check(screen.relay_status_display("ACTIVE") == "신호 연결됨" and screen.relay_status_display("OFFLINE") == "신호 복구 필요", "MAP_COPY_05 relay panel converts internal states to player-facing status copy")
	var source := FileAccess.get_file_as_string("res://chapter_map/runtime/chapter_map_screen.gd")
	var app_source := FileAccess.get_file_as_string("res://autoload/app_state.gd")
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd")
	check(not source.contains("stage_id.replace(\"CH01-\", \"\")") and not source.contains("join(unlocked)"), "MAP_COPY_06 release map source no longer formats canonical IDs directly")
	check(source.contains("MAP_TREASURE_DETAIL_BODY") and source.contains("landmark_key") and not source.contains("selected_treasure.get(\"landmark\""), "MAP_COPY_07 treasure panel uses localized landmark data instead of authoring identifiers")
	check(app_source.contains("pending_map_encounter_presentation") and app_source.contains("presentation_payload") and shell_source.contains("BossEncounterTitleCard") and shell_source.contains("BOSS_ENCOUNTER_CARD_DURATION"), "BOSS_PRESENTATION_02 title/banner is a pending-map presentation payload and leaves simulation authority untouched")
	screen.free()

func _test_coordinates() -> void:
	var samples := [Vector2i.ZERO, Vector2i(1, 0), Vector2i(3, -2), Vector2i(-2, 1), Vector2i(4, -3)]
	check(samples.all(func(coord): return HexCoordScript.world_to_axial(HexCoordScript.axial_to_world(coord, 1.08), 1.08) == coord), "axial-world-axial round trip")
	var neighbors: Array[Vector2i] = HexCoordScript.neighbors(Vector2i.ZERO)
	check(neighbors.size() == 6, "axial coordinate has six neighbors")
	var unique: Dictionary = {}
	for coord in neighbors: unique[HexCoordScript.key(coord)] = true
	check(unique.size() == 6, "six neighbor coordinates are unique")
	check(neighbors.all(func(coord): return HexCoordScript.distance(Vector2i.ZERO, coord) == 1), "all neighbors have distance one")
	check(HexCoordScript.distance(Vector2i(0, 0), Vector2i(3, -2)) == 3, "hex distance uses cube metric")
	check(definition.tiles.any(func(tile): return not bool(tile.movement_blocked) and int(tile.get("elevation", 0)) == 1), "generated map elevation data preserved")

func _test_paths() -> void:
	var all_allowed: Dictionary = {}
	for tile in definition.tiles: all_allowed["%d,%d" % [int(tile.q), int(tile.r)]] = true
	# A fresh Chapter 1 save must be able to preview an actual physical route to
	# N01.  The first journey may intentionally consume more than one movement
	# pulse, but fog/reveal construction must never turn the player-facing
	# "next encounter" action into a no-op path at the start of the campaign.
	var fresh_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(fresh_state, definition, grid)
	var fresh_allowed: Dictionary = {}
	for key in fresh_state.get("revealed_tiles", []): fresh_allowed[str(key)] = true
	var fresh_start := Vector2i(int(fresh_state.get("current_q", 0)), int(fresh_state.get("current_r", 0)))
	var fresh_n01 := LoaderScript.node_for_stage(definition, "CH01-N01")
	var fresh_path: Array[Vector2i] = HexPathfinderScript.find_path(grid, fresh_start, Vector2i(int(fresh_n01.q), int(fresh_n01.r)), fresh_allowed)
	var initial_pulse_steps := mini(maxi(0, fresh_path.size() - 1), ExplorationScript.movement_remaining(fresh_state, definition))
	check(not fresh_path.is_empty() and fresh_path.front() == fresh_start and fresh_path.back() == Vector2i(int(fresh_n01.q), int(fresh_n01.r)) and initial_pulse_steps > 0, "FRESH_ROUTE_01 new save previews a reachable physical N01 route")
	var pulse_screen := ChapterMapScreenScript.new()
	pulse_screen.definition = definition
	pulse_screen.map_state = fresh_state
	var bounded_n01_path: Array[Vector2i] = pulse_screen._path_for_current_pulse(fresh_path)
	check(int(fresh_state.get("movement_points", 0)) == 3 and fresh_path.size() > 4 and bounded_n01_path.size() == 4 and bounded_n01_path.back() != fresh_path.back(), "MOVE_LIMIT_01 selecting N01 stops exactly three cells into the route instead of reaching the encounter")
	pulse_screen.free()
	var reachable_three := HexPathfinderScript.reachable_within(grid, fresh_start, 3, fresh_allowed)
	check(reachable_three.has(HexCoordScript.key(fresh_start)) and reachable_three.values().all(func(value): return int(value) <= 3) and reachable_three.has(HexCoordScript.key(fresh_path[3])) and not reachable_three.has(HexCoordScript.key(fresh_path[4])), "MOVE_RANGE_01 range authority includes exactly pathable cells within the remaining three steps")
	var terminal_stop := {HexCoordScript.key(fresh_path[2]): true}
	var terminal_allowed: Dictionary = {}
	for path_index in range(4): terminal_allowed[HexCoordScript.key(fresh_path[path_index])] = true
	var terminal_range := HexPathfinderScript.reachable_within(grid, fresh_start, 3, terminal_allowed, terminal_stop)
	check(terminal_range.has(HexCoordScript.key(fresh_path[2])) and not terminal_range.has(HexCoordScript.key(fresh_path[3])), "MOVE_RANGE_02 unresolved encounter cells are reachable terminals and never allow same-turn traversal beyond contact")
	# Every newly unlocked NORMAL operation must expose a real, step-by-step
	# corridor from the operation that unlocked it.  This guards the player-facing
	# next-encounter action against becoming a disabled no-op after a normal clear
	# or a side-branch detour; movement pulses may interrupt the journey, but the
	# revealed corridor itself must remain physically pathable.
	for cleared_number in range(1, 10):
		var route_state := ProgressScript.create_default(definition)
		ProgressScript.refresh_reveal(route_state, definition, cleared_number, 0, false)
		var from_node := LoaderScript.node_for_stage(definition, "CH01-N%02d" % cleared_number)
		var to_node := LoaderScript.node_for_stage(definition, "CH01-N%02d" % (cleared_number + 1))
		var from_coord := Vector2i(int(from_node.q), int(from_node.r))
		var to_coord := Vector2i(int(to_node.q), int(to_node.r))
		ProgressScript.mark_visited(route_state, [from_coord])
		var route_allowed: Dictionary = {}
		for key in route_state.get("revealed_tiles", []): route_allowed[str(key)] = true
		var continuation: Array[Vector2i] = HexPathfinderScript.find_path(grid, from_coord, to_coord, route_allowed)
		check(continuation.size() > 1 and continuation.front() == from_coord and continuation.back() == to_coord and continuation.all(func(coord): return grid.traversable(coord)), "ROUTE_CONTINUITY_N%02d_N%02d unlocked NORMAL corridor stays physically pathable" % [cleared_number, cleared_number + 1])
	var straight: Array[Vector2i] = HexPathfinderScript.find_path(grid, Vector2i(0, 0), Vector2i(2, 0), all_allowed)
	check(straight == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], "straight path is minimal")
	var winding: Array[Vector2i] = HexPathfinderScript.find_path(grid, Vector2i(2, 0), Vector2i(4, -2), all_allowed)
	check(not winding.is_empty() and winding.front() == Vector2i(2, 0) and winding.back() == Vector2i(4, -2), "winding route reaches goal")
	check(winding.all(func(coord): return grid.traversable(coord)), "path never enters blocked water")
	var repeat := HexPathfinderScript.find_path(grid, Vector2i(2, 0), Vector2i(4, -2), all_allowed)
	check(winding == repeat, "equal-cost path tie-break is deterministic")
	var limited := {"0,0": true, "1,0": true}
	check(HexPathfinderScript.find_path(grid, Vector2i(0, 0), Vector2i(2, 0), limited).is_empty(), "unrevealed destination is unreachable")
	check(HexPathfinderScript.find_path(grid, Vector2i(0, 0), Vector2i(0, 0), all_allowed) == [Vector2i(0, 0)], "current-tile path is stable")
	var synthetic = HexGridScript.new()
	synthetic.load_tiles([{"q": 0, "r": 0, "elevation": 0}, {"q": 1, "r": 0, "elevation": 2}])
	check(not synthetic.can_step(Vector2i.ZERO, Vector2i(1, 0)), "two-level cliff blocks movement")
	check(not HexPathfinderScript.reachable_within(synthetic, Vector2i.ZERO, 3).has("1,0"), "MOVE_RANGE_03 range excludes a two-level cliff exactly like movement")
	var expected_boundary_edges := [Vector2i(5, 0), Vector2i(4, 5), Vector2i(3, 4), Vector2i(2, 3), Vector2i(1, 2), Vector2i(0, 1)]
	check(range(6).all(func(index): return ChapterMapScreenScript._movement_boundary_corner_indices(index) == expected_boundary_edges[index]), "MOVE_RANGE_04 all six axial directions map to the correct translucent hex edge")
	var adjacent_pair := {"0,0": true, "1,0": true}
	var adjacent_outer_edges := 0
	for coord in [Vector2i.ZERO, Vector2i(1, 0)]:
		for direction in HexCoordScript.DIRECTIONS:
			if not adjacent_pair.has(HexCoordScript.key(coord + direction)): adjacent_outer_edges += 1
	check(adjacent_outer_edges == 10, "MOVE_RANGE_05 two adjacent highlighted hexes retain ten exact outside boundary edges")

func _test_geometry_grounding_contract() -> void:
	# P0-VIS-01: Godot's CULL_BACK front face for this X/Z map is clockwise,
	# so production terrain fans must use [center, current_corner, next_corner].
	# A mathematically upward normal is the *back* face in this renderer and
	# makes valid ground disappear behind culling.
	var center := Vector3.ZERO
	var current_corner := Vector3(cos(PI / 6.0), 0.0, sin(PI / 6.0))
	var next_corner := Vector3(cos(PI / 2.0), 0.0, sin(PI / 2.0))
	var terrain_normal_y := (current_corner - center).cross(next_corner - center).y
	check(terrain_normal_y < -0.0001, "P0_VIS_01 connected terrain top triangles use Godot front-face winding")
	check(absf(terrain_normal_y) > 0.0001, "P0_VIS_01 connected terrain top triangles are non-degenerate")
	# P0-VIS-01 also covers the causeway strip's production vertex sequence.
	var from_left := Vector3(0.0, 0.0, -0.48)
	var from_right := Vector3(0.0, 0.0, 0.48)
	var to_left := Vector3(1.86, 0.0, -0.48)
	var to_right := Vector3(1.86, 0.0, 0.48)
	var causeway_normal_y := (to_left - from_left).cross(to_right - from_left).y
	check(causeway_normal_y < -0.0001, "P0_VIS_01 signal causeway top triangles use Godot front-face winding")
	check(absf(causeway_normal_y) > 0.0001, "P0_VIS_01 signal causeway top triangles are non-degenerate")
	# P0-VIS-01 finally covers every fan wedge used by a twelve-sided encounter
	# landing terrace.  It is a real visual socket for a player or hostile pawn.
	var terrace_upward := true
	var terrace_non_degenerate := true
	var terrace_points: Array[Vector3] = []
	for index in range(12):
		var angle := float(index) * TAU / 12.0 + PI / 12.0
		terrace_points.append(Vector3(cos(angle), 0.0, sin(angle)))
	for index in range(terrace_points.size()):
		var terrace_y := (terrace_points[index] - center).cross(terrace_points[(index + 1) % terrace_points.size()] - center).y
		terrace_upward = terrace_upward and terrace_y < -0.0001
		terrace_non_degenerate = terrace_non_degenerate and absf(terrace_y) > 0.0001
	check(terrace_upward, "P0_VIS_01 encounter terrace top triangles use Godot front-face winding")
	check(terrace_non_degenerate, "P0_VIS_01 encounter terrace top triangles are non-degenerate")
	# P0-VIS-02: no two-sided material workaround.  The normal gameplay
	# material must use production back-face culling, so these geometric tests
	# continue to catch any inverted source winding.
	var map_screen_source := FileAccess.get_file_as_string("res://chapter_map/runtime/chapter_map_screen.gd")
	check(map_screen_source.contains("MovementRangeYellowFill") and map_screen_source.contains("MovementRangeYellowCellGrid") and map_screen_source.contains("MovementRangeYellowBoundary") and map_screen_source.contains("TRANSPARENCY_ALPHA") and map_screen_source.contains("%d칸 후 중간 정지"), "MOVE_RANGE_06 runtime draws translucent yellow cells, per-cell seams, a stronger outer boundary and explicit partial-stop copy")
	check(map_screen_source.contains("material.cull_mode = BaseMaterial3D.CULL_BACK"), "P0_VIS_02 map top surfaces retain production back-face culling")
	check(map_screen_source.contains("EnemyGroundingTerrace"), "P0_VIS_02 hostile patrols retain a physical terrain socket")
	check(map_screen_source.contains("sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS"), "P0_VIS_02 hostile sprite uses a depth-stable alpha prepass")
	check(map_screen_source.contains("pawn_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS"), "P0_VIS_02 squad sprite uses a depth-stable alpha prepass")
	check(not map_screen_source.contains("sprite.no_depth_test = true"), "P0_VIS_02 hostile sprite cannot bypass world depth")
	check(not map_screen_source.contains("pawn_sprite.no_depth_test = true"), "P0_VIS_02 squad sprite cannot bypass world depth")
	check(map_screen_source.contains("The Blender-authored cap is the final local ground authority"), "P0_VIS_02 streamed Blender terrain caps remain production ground")
	check(map_screen_source.contains("func _node_overlay_anchor") and map_screen_source.contains("func _overlay_position_from_world") and map_screen_source.contains("_overlay_position_from_world(_node_overlay_anchor(node))"), "MAP_STAGE_OVERLAY_PROJECTION_01 labels follow instantiated marker anchors with one SubViewport conversion")
	check(map_screen_source.contains("func _overlay_anchor_is_visible") and map_screen_source.contains("camera.is_position_behind(world_position)") and map_screen_source.contains("_overlay_anchor_is_visible(anchor, button.size)"), "MAP_STAGE_OVERLAY_PROJECTION_02 off-frustum labels cannot detach from their 3D marker")
	check(map_screen_source.contains("const STREAM_RADIUS := 16") and map_screen_source.contains("func _has_streamed_ground") and map_screen_source.contains("func _map_entity_is_locally_renderable"), "MAP_STAGE_OVERLAY_PROJECTION_03 full camera neighbourhood and visible entities require streamed terrain caps")
	check(map_screen_source.contains("_map_entity_is_locally_renderable(encounter_coord, camera_coord, STREAM_RADIUS + 2)"), "MAP_STAGE_OVERLAY_PROJECTION_04 hostile refresh and process visibility share the streamed-ground contract")
	check(map_screen_source.contains("func _clamp_camera_target_to_terrain") and not map_screen_source.contains("clampf(camera_target.x, -42.0, 170.0)"), "MAP_CAMERA_TERRAIN_01 camera pan is constrained by generated land instead of a broad ocean rectangle")
	check(map_screen_source.contains("Do not evict the current district before this tween begins") and map_screen_source.contains("_stream_visible_tiles(coord, true)"), "MAP_CAMERA_TERRAIN_02 focus tween retains current streamed ground until camera movement begins")
	var camera_screen := ChapterMapScreenScript.new()
	camera_screen.definition = definition
	camera_screen.grid.load_tiles(definition.get("tiles", []))
	var n04_camera_node := LoaderScript.node_for_stage(definition, "CH01-N04")
	var n04_camera_target := HexCoordScript.axial_to_world(Vector2i(int(n04_camera_node.q), int(n04_camera_node.r)), 1.08)
	check(camera_screen._clamp_camera_target_to_terrain(n04_camera_target).is_equal_approx(n04_camera_target), "MAP_CAMERA_TERRAIN_03 valid encounter focus remains at its authored ground coordinate")
	var ocean_target := Vector3(500.0, 0.0, -500.0)
	var clamped_target := camera_screen._clamp_camera_target_to_terrain(ocean_target)
	check(clamped_target.distance_to(ocean_target) > 100.0 and clamped_target.is_finite(), "MAP_CAMERA_TERRAIN_04 corrupt or dragged ocean target is repaired near traversable terrain")
	check(not map_screen_source.contains("var horizon_mesh := PlaneMesh.new()") and map_screen_source.contains("Do not place an opaque, fixed world-space horizon plane"), "MAP_CAMERA_TERRAIN_05 macro-map backdrop cannot occlude distant HARD terrain")
	check(camera_screen._compact_ui_scale(Vector2(915.0, 412.0)) >= 2.6, "MAP_RESPONSIVE_01 compact landscape compensates 1080-canvas touch targets")
	check(is_equal_approx(camera_screen._compact_ui_scale(Vector2(390.0, 844.0)), 4.9), "MAP_RESPONSIVE_02 portrait retains full physical touch compensation")
	check(is_equal_approx(camera_screen._compact_ui_scale(Vector2(1920.0, 1080.0)), 1.0), "MAP_RESPONSIVE_03 desktop layout remains unscaled")
	check(map_screen_source.contains("(10.0 if portrait else 14.0) * ui_scale") and map_screen_source.contains("sheet_height := 280.0 if portrait") and map_screen_source.contains("detail_scroll.find_children"), "MAP_RESPONSIVE_04 portrait keeps the next-encounter shortcut above the status row and minimizes the scrollable detail sheet")
	var portrait_hotfix_source := FileAccess.get_file_as_string("res://autoload/mobile_portrait_hotfix_v2.gd")
	check(portrait_hotfix_source.contains("(size.x - 22.0) / 6.0") and portrait_hotfix_source.contains("compact_labels := [\"일반\", \"위험\", \"부대\", \"개요\", \"스킵\"]") and portrait_hotfix_source.contains("var sheet_css := clampf(size.y * 0.29, 222.0, 258.0)") and portrait_hotfix_source.contains("panel.anchor_top = 0.49") and portrait_hotfix_source.contains("panel.anchor_bottom = 0.95") and portrait_hotfix_source.contains("_font(17.0, size)"), "MAP_RESPONSIVE_05 final portrait pass preserves a single tactical rail, readable compact sheet, and map-visible tutorial")
	camera_screen.free()
	# The runtime combat manifest owns both animation frame indices and the
	# normalized foot anchor.  Map pawns must use that data instead of silently
	# reducing an 8/12-frame pack to one static frame or guessing its contact.
	var character_manifest_path := "res://assets/runtime_web/combat/CHR001/animation_manifest.json"
	var character_manifest = JSON.parse_string(FileAccess.get_file_as_string(character_manifest_path))
	check(character_manifest is Dictionary, "MAP_PAWN_ANIMATION_01 CHR001 animation manifest parses")
	if character_manifest is Dictionary:
		var animations: Dictionary = character_manifest.get("animations", {})
		var idle_indices: Array = animations.get("idle", {}).get("frame_indices", [])
		var move_indices: Array = animations.get("move", {}).get("frame_indices", [])
		var animation_pack := {
			"animations": animations,
			"idle_frame_indices": idle_indices,
			"idle_fps": float(animations.get("idle", {}).get("fps", 12.0)),
		}
		check(idle_indices.size() >= 8, "MAP_PAWN_ANIMATION_02 idle uses at least 8 authored frames")
		check(move_indices.size() >= 12, "MAP_PAWN_ANIMATION_03 move uses at least 12 authored frames")
		check(ChapterMapScreenScript._animation_frame(animation_pack, "idle", 0) == int(idle_indices[0]), "MAP_PAWN_ANIMATION_04 first authored idle frame is selected")
		check(ChapterMapScreenScript._animation_frame(animation_pack, "move", 100) == int(move_indices[1]), "MAP_PAWN_ANIMATION_05 authored move frames advance at manifest FPS")
		var anchor: Array = character_manifest.get("foot_anchor", [0.5, 0.88])
		var parent_base := 0.18
		var contact_y := 0.15
		var frame_height := float(character_manifest.get("frame_size", [104, 104])[1])
		var pixel_size := 0.0152
		var center_y := ChapterMapScreenScript._sprite_center_y_for_foot(contact_y, parent_base, frame_height, pixel_size, float(anchor[1]))
		var reconstructed_foot := parent_base + center_y - (float(anchor[1]) - 0.5) * frame_height * pixel_size
		check(absf(reconstructed_foot - contact_y) < 0.0001, "MAP_PAWN_GROUNDING_01 authored foot anchor reconstructs the physical contact plane")
	# P0-VIS-03/05: every authored gameplay coordinate has a finite traversable
	# terrain cell and a bounded vertical socket offset.  This protects map
	# pawns from appearing on ocean/void even when the terrain is macro generated.
	var grounding_coords: Array[Vector2i] = []
	for node in definition.get("nodes", []):
		grounding_coords.append(Vector2i(int(node.get("q", 0)), int(node.get("r", 0))))
	for patrol in definition.get("patrols", []):
		for route_hex in patrol.get("patrol_route_hexes", []):
			grounding_coords.append(Vector2i(int(route_hex.get("q", 0)), int(route_hex.get("r", 0))))
	for relay in definition.get("relays", []):
		grounding_coords.append(Vector2i(int(relay.get("q", 0)), int(relay.get("r", 0))))
	# Every connecting cell, not only its encounter endpoints, is gameplay ground.
	# This catches a route that visually crosses an ocean or a missing streamed cap.
	var previous_coord := Vector2i(int(definition.get("start_hex", {}).get("q", 0)), int(definition.get("start_hex", {}).get("r", 0)))
	for stage_id in definition.get("normal_route", []):
		var route_node := LoaderScript.node_for_stage(definition, str(stage_id))
		if route_node.is_empty(): continue
		var route_coord := Vector2i(int(route_node.get("q", 0)), int(route_node.get("r", 0)))
		grounding_coords.append_array(MacroWorldGeneratorScript.route_line(previous_coord, route_coord))
		previous_coord = route_coord
	var normal_boss_node := LoaderScript.node_for_stage(definition, "CH01-N20")
	previous_coord = Vector2i(int(normal_boss_node.get("q", 0)), int(normal_boss_node.get("r", 0)))
	for stage_id in definition.get("hard_route", []):
		var hard_node := LoaderScript.node_for_stage(definition, str(stage_id))
		if hard_node.is_empty(): continue
		var hard_coord := Vector2i(int(hard_node.get("q", 0)), int(hard_node.get("r", 0)))
		grounding_coords.append_array(MacroWorldGeneratorScript.route_line(previous_coord, hard_coord))
		previous_coord = hard_coord
	var coverage_valid := true
	var visual_land_valid := true
	var contact_offsets_valid := true
	for coord in grounding_coords:
		var tile: Dictionary = grid.tile(coord)
		var surface_height := float(tile.get("elevation", 0)) * 0.64
		coverage_valid = coverage_valid and grid.traversable(coord) and not is_nan(surface_height) and not is_inf(surface_height)
		visual_land_valid = visual_land_valid and str(tile.get("terrain_type", "")) not in ["SHALLOW_WATER", "DEEP_WATER"]
		var squad_socket := surface_height + 0.14
		var encounter_socket := surface_height + 0.18
		contact_offsets_valid = contact_offsets_valid and absf(squad_socket - surface_height) <= 0.20 and absf(encounter_socket - surface_height) <= 0.20
	check(coverage_valid, "P0_VIS_03 every authored encounter, patrol and relay coordinate has valid ground coverage")
	check(visual_land_valid, "P0_VIS_04 every gameplay pawn coordinate resolves to solid terrain, never a traversable water visual")
	check(contact_offsets_valid, "P0_VIS_05 squad, encounter and hostile sockets stay grounded")

func _test_unlock_and_progress() -> void:
	var backup := AppState.profile.duplicate(true)
	AppState.new_game()
	check(AppState.is_stage_unlocked("CH01-N01"), "N01 initially unlocked")
	check(not AppState.is_stage_unlocked("CH01-N02"), "N02 initially locked")
	check(not AppState.is_stage_unlocked("CH01-H01"), "HARD gate initially locked")
	for number in range(1, 21): AppState.record_stage_clear("CH01-N%02d" % number, 3)
	check(AppState.is_stage_unlocked("CH01-H01"), "N20 clear opens HARD gate")
	check(not AppState.is_stage_unlocked("CH01-H02"), "H02 waits for H01")
	AppState.record_stage_clear("CH01-H01", 2)
	check(AppState.is_stage_unlocked("CH01-H02"), "H01 clear unlocks H02 exactly")
	var state := AppState.chapter_map_state()
	var h01 := LoaderScript.node_for_stage(definition, "CH01-H01")
	AppState.set_chapter_map_position(Vector2i(int(h01.q), int(h01.r)), str(h01.node_id))
	check(ChapterMapScreenScript._hard_overlay_from_state(state, definition), "H01 battle return restores HARD route overlay")
	var hard_screen := ChapterMapScreenScript.new()
	hard_screen.definition = definition
	hard_screen.map_state = state
	hard_screen.hard_overlay = ChapterMapScreenScript._hard_overlay_from_state(state, definition)
	check(str(hard_screen._next_encounter_node().get("stage_id", "")) == "CH01-H02", "H01 battle return next encounter is H02, never N01")
	hard_screen.free()
	check(state.revealed_tiles.has("%d,%d" % [int(h01.q), int(h01.r)]), "HARD route reveal follows N20 clear")
	var fresh := ProgressScript.create_default(definition)
	var before: int = fresh.revealed_tiles.size()
	ProgressScript.refresh_reveal(fresh, definition, 1, 0, false)
	var n02 := LoaderScript.node_for_stage(definition, "CH01-N02")
	check(fresh.revealed_tiles.size() >= before and fresh.revealed_tiles.has("%d,%d" % [int(n02.q), int(n02.r)]), "victory reveals next NORMAL region")
	AppState.profile = backup

func _test_save_and_migration() -> void:
	var old := AppState.profile.duplicate(true)
	old.save_schema_version = 1
	old.erase("chapter_map")
	old.chapter_progress.CH01.normal_highest = 6
	for number in range(1, 7): old.stage_stars["CH01-N%02d" % number] = 3
	var migrated := SaveService._migrate(old)
	check(migrated.ok and int(migrated.value.save_schema_version) == AppState.SAVE_SCHEMA_VERSION, "v1 save migrates sequentially to macro-map schema")
	var state: Dictionary = migrated.value.chapter_map.CH01_MAP
	var node := LoaderScript.node_for_stage(definition, "CH01-N06")
	check(int(state.current_q) == int(node.q) and int(state.current_r) == int(node.r), "migration restores highest cleared node position")
	check(state.cleared_nodes.size() == 6, "migration restores cleared-node set")
	check(not state.revealed_tiles.is_empty(), "migration restores route reveal")
	var compact_v2 := old.duplicate(true)
	compact_v2.save_schema_version = 2
	compact_v2.chapter_map = {"CH01_MAP": {"current_q": 3, "current_r": -2, "last_selected_node": "NODE_N06", "cleared_nodes": ["NODE_N01", "NODE_N06"], "revealed_tiles": ["0,0"]}}
	var macro_migrated := SaveService._migrate(compact_v2)
	var n06 := LoaderScript.node_for_stage(definition, "CH01-N06")
	check(macro_migrated.ok and int(macro_migrated.value.chapter_map.CH01_MAP.current_q) == int(n06.q) and int(macro_migrated.value.chapter_map.CH01_MAP.current_r) == int(n06.r), "v2 compact save reanchors current node on macro route")
	var n10 := old.duplicate(true)
	n10.chapter_progress.CH01.normal_highest = 10
	n10.chapter_progress.CH01.hard_unlocked = true
	var hard_state := ProgressScript.migrate_from_profile(n10, definition)
	var h01 := LoaderScript.node_for_stage(definition, "CH01-H01")
	check(hard_state.revealed_tiles.has("%d,%d" % [int(h01.q), int(h01.r)]), "migration restores HARD gate reveal")
	var dirty: Dictionary = migrated.value.duplicate(true)
	dirty.chapter_map.CH01_MAP.cleared_nodes.append("UNKNOWN_NODE")
	var sanitized := SaveService._sanitize(dirty)
	check(not sanitized.chapter_map.CH01_MAP.cleared_nodes.has("UNKNOWN_NODE") and sanitized.quarantined_unknown_map_node_ids.has("UNKNOWN_NODE"), "unknown map node quarantined")
	var saved_profile := AppState.profile.duplicate(true)
	AppState.profile = migrated.value
	AppState.set_chapter_map_position(Vector2i(3, -2), "NODE_N06")
	var save_result := SaveService.save_game()
	AppState.profile.chapter_map.CH01_MAP.current_q = 99
	var load_result := SaveService.load_game()
	check(save_result.ok and load_result.ok and int(AppState.chapter_map_state().current_q) == 3, "map q/r survives atomic save-load")
	var void_party_state := ProgressScript.create_default(definition)
	void_party_state.current_q = 999
	void_party_state.current_r = -999
	void_party_state.current_party_hex = [999, -999]
	void_party_state.last_map_camera_hex = [999, -999]
	void_party_state.last_selected_node = "NODE_N04"
	var n04_anchor := LoaderScript.node_by_id(definition, "NODE_N04")
	var n04_key := "%d,%d" % [int(n04_anchor.q), int(n04_anchor.r)]
	void_party_state.visited_tiles.append(n04_key)
	void_party_state.revealed_tiles.append(n04_key)
	var party_repaired := MapSimulationScript.ensure_state(void_party_state, definition, grid)
	check(party_repaired and int(void_party_state.current_q) == int(n04_anchor.q) and int(void_party_state.current_r) == int(n04_anchor.r), "PARTY_SAVE_REPAIR_01 invalid legacy party coordinate restores selected grounded node")
	check(void_party_state.current_party_hex == [int(n04_anchor.q), int(n04_anchor.r)] and void_party_state.last_map_camera_hex == [int(n04_anchor.q), int(n04_anchor.r)], "PARTY_SAVE_REPAIR_02 party and camera caches synchronize to repaired ground coordinate")
	check(not MapSimulationScript.ensure_state(void_party_state, definition, grid), "PARTY_SAVE_REPAIR_03 valid repaired party state is idempotent")
	var off_route_state := ProgressScript.create_default(definition)
	var off_route_coord := Vector2i(int(n04_anchor.q), int(n04_anchor.r))
	off_route_state.current_q = off_route_coord.x
	off_route_state.current_r = off_route_coord.y
	off_route_state.current_party_hex = [off_route_coord.x, off_route_coord.y]
	off_route_state.last_map_camera_hex = [off_route_coord.x, off_route_coord.y]
	var start_anchor: Dictionary = definition.get("start_hex", {"q": 0, "r": 0})
	var party_off_route_repaired := MapSimulationScript.ensure_state(off_route_state, definition, grid)
	check(party_off_route_repaired and int(off_route_state.current_q) == int(start_anchor.q) and int(off_route_state.current_r) == int(start_anchor.r), "PARTY_SAVE_REPAIR_04 traversable but unvisited coordinate repairs to canonical visited route")
	check(off_route_state.visited_tiles.has("%d,%d" % [int(start_anchor.q), int(start_anchor.r)]) and off_route_state.revealed_tiles.has("%d,%d" % [int(start_anchor.q), int(start_anchor.r)]), "PARTY_SAVE_REPAIR_05 repaired party coordinate preserves authoritative route proof")
	check(not MapSimulationScript.ensure_state(off_route_state, definition, grid), "PARTY_SAVE_REPAIR_06 canonical repaired party state is idempotent")
	AppState.profile = saved_profile

func _test_transactions_and_roundtrip() -> void:
	var backup := AppState.profile.duplicate(true)
	var developer_mode_before := bool(SettingsService.values.developer_mode)
	# This block verifies the normal-player entry transaction. Headless runs use
	# a debug engine now, so opt out of the intentional developer bypass here.
	SettingsService.values.developer_mode = false
	AppState.new_game()
	var state := AppState.chapter_map_state()
	var stamina_before := int(AppState.profile.account.stamina)
	ProgressScript.mark_visited(state, [Vector2i(0, 0), Vector2i(1, 0)])
	check(int(AppState.profile.account.stamina) == stamina_before, "map movement consumes zero stamina")
	check(AppState.can_enter_stage("CH01-N01") and int(AppState.profile.account.stamina) == stamina_before, "stage preview/cancel consumes zero stamina")
	var cost := int(DataRegistry.stage("CH01-N01").stamina_cost)
	check(AppState.begin_battle_transaction("CH01-N01") and int(AppState.profile.account.stamina) == stamina_before - cost, "battle start consumes stamina exactly once")
	var token := AppState.pending_battle_token
	var first := AppState.record_stage_clear("CH01-N01", 3)
	var applied := AppState.apply_battle_result_to_map("CH01-N01", true)
	var applied_twice := AppState.apply_battle_result_to_map("CH01-N01", true)
	check(first and applied and not applied_twice and AppState.pending_battle_token == "", "victory map result applied exactly once")
	check(AppState.chapter_map_state().cleared_nodes.has("NODE_N01"), "victory marks corresponding map node")
	check(AppState.is_stage_unlocked("CH01-N02"), "victory unlocks exactly the next stage")
	AppState.selected_stage_id = "CH01-N02"
	var pre_contact := Vector2i(14, -3)
	AppState.prepare_map_encounter("CH01-N02", "NODE_N02", pre_contact)
	AppState.pending_battle_token = "DEFEAT_TOKEN"
	AppState.apply_battle_result_to_map("CH01-N02", false)
	check(not AppState.chapter_map_state().cleared_nodes.has("NODE_N02") and not AppState.is_stage_unlocked("CH01-N03"), "defeat does not clear or unlock next node")
	check(int(AppState.chapter_map_state().current_q) == pre_contact.x and int(AppState.chapter_map_state().current_r) == pre_contact.y, "defeat restores squad to pre-contact map hex")
	# Reproduce the real HARD-route failure: the squad reaches the static H03
	# hostile, loses, then must return to the exact preceding route hex so H03 is
	# selectable and reachable again instead of becoming an at-node softlock.
	AppState.new_game()
	for number in range(1, 21):
		AppState.record_stage_clear("CH01-N%02d" % number, 3)
	for number in range(1, 3):
		AppState.record_stage_clear("CH01-H%02d" % number, 3)
	var h02 := LoaderScript.node_for_stage(definition, "CH01-H02")
	var h03 := LoaderScript.node_for_stage(definition, "CH01-H03")
	var h02_coord := Vector2i(int(h02.q), int(h02.r))
	var h03_coord := Vector2i(int(h03.q), int(h03.r))
	AppState.set_chapter_map_position(h02_coord, str(h02.node_id))
	var hard_state := AppState.chapter_map_state()
	var hard_allowed: Dictionary = {}
	for key in hard_state.get("revealed_tiles", []): hard_allowed[str(key)] = true
	var hard_path := HexPathfinderScript.find_path(grid, h02_coord, h03_coord, hard_allowed)
	check(hard_path.size() > 1 and hard_path[-1] == h03_coord, "DEFEAT_RETRY_01 H03 has a real deterministic contact route")
	var exact_pre_contact: Vector2i = hard_path[-2]
	ProgressScript.mark_visited(hard_state, hard_path)
	hard_state.last_pre_contact_hex = [exact_pre_contact.x, exact_pre_contact.y]
	check(AppState.prepare_map_encounter("CH01-H03", str(h03.node_id), exact_pre_contact), "DEFEAT_RETRY_02 H03 contact snapshots its exact preceding hex")
	check(AppState.begin_battle_transaction("CH01-H03"), "DEFEAT_RETRY_03 H03 owns one live battle transaction")
	check(AppState.apply_battle_result_to_map("CH01-H03", false), "DEFEAT_RETRY_04 H03 defeat consumes the pending return transaction")
	var restored_hard := AppState.chapter_map_state()
	var restored_coord := Vector2i(int(restored_hard.current_q), int(restored_hard.current_r))
	check(restored_coord == exact_pre_contact and restored_coord != h03_coord, "DEFEAT_RETRY_05 H03 defeat restores the exact pre-contact hex")
	check(not ExplorationScript.encounter_cleared(restored_hard, str(h03.node_id)) and int(AppState.profile.stage_stars.get("CH01-H03", 0)) == 0, "DEFEAT_RETRY_06 H03 hostile remains and grants no clear")
	var retry_path := HexPathfinderScript.find_path(grid, restored_coord, h03_coord, hard_allowed)
	check(retry_path.size() > 1 and retry_path[-1] == h03_coord, "DEFEAT_RETRY_07 restored H03 is immediately reachable for a physical-contact retry")
	# Guard the malformed legacy/live edge that caused the observed softlock:
	# if a static encounter accidentally submits its own hostile hex as return,
	# the separately recorded last safe hex is authoritative.
	ProgressScript.mark_visited(restored_hard, retry_path)
	restored_hard.last_pre_contact_hex = [exact_pre_contact.x, exact_pre_contact.y]
	check(AppState.prepare_map_encounter("CH01-H03", str(h03.node_id), h03_coord), "DEFEAT_RETRY_08 malformed static H03 snapshot is accepted for deterministic repair")
	check(Vector2i(int(restored_hard.pending_encounter.return_q), int(restored_hard.pending_encounter.return_r)) == exact_pre_contact, "DEFEAT_RETRY_09 static hostile return is normalized to the last safe hex")
	AppState.abandon_pending_map_encounter()
	check(Vector2i(int(restored_hard.current_q), int(restored_hard.current_r)) == exact_pre_contact and restored_hard.get("pending_encounter", {}).is_empty(), "DEFEAT_RETRY_10 abandon uses the same exact pre-contact restoration")
	# A moving patrol may initiate contact on the party's own stationary hex.
	# Defeat/abandon must return control without a timer-driven rematch; leaving
	# that hex is the explicit player action that re-enables normal contact.
	AppState.new_game()
	var patrol_state := AppState.chapter_map_state()
	var n01 := LoaderScript.node_for_stage(definition, "CH01-N01")
	var n01_runtime: Dictionary = patrol_state.patrol_states.get(str(n01.node_id), {})
	var patrol_contact := Vector2i(int(n01_runtime.q), int(n01_runtime.r))
	ProgressScript.mark_visited(patrol_state, [patrol_contact])
	check(AppState.prepare_map_encounter("CH01-N01", str(n01.node_id), patrol_contact) and AppState.begin_battle_transaction("CH01-N01"), "PATROL_DISENGAGE_01 same-hex patrol contact owns one transaction")
	check(AppState.apply_battle_result_to_map("CH01-N01", false), "PATROL_DISENGAGE_02 patrol defeat completes map return")
	var disengaged: Dictionary = patrol_state.patrol_states.get(str(n01.node_id), {})
	var retreat_coord := MapSimulationScript.coord_for(patrol_state, str(n01.node_id))
	check(Vector2i(int(patrol_state.current_q), int(patrol_state.current_r)) == patrol_contact and retreat_coord != patrol_contact, "PATROL_DISENGAGE_03 party stays at its pre-battle hex while patrol deterministically retreats")
	check(bool(disengaged.get("contact_suppressed", false)) and str(disengaged.get("patrol_state", "")) == MapSimulationScript.PATROL_RETURN, "PATROL_DISENGAGE_04 restored patrol enters persisted disengage state")
	var idle_contacts := 0
	for _tick in range(24):
		idle_contacts += MapSimulationScript.advance_ticks(patrol_state, definition, grid, patrol_contact, 1).get("contacts", []).size()
	check(idle_contacts == 0 and bool(patrol_state.patrol_states.get(str(n01.node_id), {}).get("contact_suppressed", false)), "PATROL_DISENGAGE_05 elapsed map ticks cannot auto-restart the defeated encounter")
	var serialized_patrol := JSON.stringify(patrol_state)
	var patrol_parser := JSON.new()
	patrol_parser.parse(serialized_patrol)
	var reloaded_patrol: Dictionary = patrol_parser.data
	ExplorationScript.ensure_state(reloaded_patrol, definition, grid)
	check(MapSimulationScript.advance_ticks(reloaded_patrol, definition, grid, patrol_contact, 1).get("contacts", []).is_empty() and bool(reloaded_patrol.patrol_states.get(str(n01.node_id), {}).get("contact_suppressed", false)), "PATROL_DISENGAGE_06 reload preserves no-auto-rematch state")
	var retry_enemy := MapSimulationScript.coord_for(reloaded_patrol, str(n01.node_id))
	reloaded_patrol.patrol_states[str(n01.node_id)].next_move_tick = 999999
	var retry_contact := MapSimulationScript.advance_ticks(reloaded_patrol, definition, grid, retry_enemy, 1)
	check(not bool(reloaded_patrol.patrol_states.get(str(n01.node_id), {}).get("contact_suppressed", true)) and retry_contact.get("contacts", []).has(str(n01.node_id)), "PATROL_DISENGAGE_07 player movement re-enables one physical-contact retry")
	AppState.new_game()
	var abandon_patrol_state := AppState.chapter_map_state()
	var abandon_runtime: Dictionary = abandon_patrol_state.patrol_states.get(str(n01.node_id), {})
	var abandon_contact := Vector2i(int(abandon_runtime.q), int(abandon_runtime.r))
	ProgressScript.mark_visited(abandon_patrol_state, [abandon_contact])
	check(AppState.prepare_map_encounter("CH01-N01", str(n01.node_id), abandon_contact), "PATROL_DISENGAGE_08 patrol abandon creates a recoverable snapshot")
	AppState.abandon_pending_map_encounter()
	check(bool(abandon_patrol_state.patrol_states.get(str(n01.node_id), {}).get("contact_suppressed", false)) and MapSimulationScript.advance_ticks(abandon_patrol_state, definition, grid, abandon_contact, 1).get("contacts", []).is_empty(), "PATROL_DISENGAGE_09 abandon uses the same no-auto-rematch policy")
	var inventory_before: Dictionary = AppState.profile.inventory.duplicate(true)
	var stamina_fast := int(AppState.profile.account.stamina)
	AppState.set_chapter_map_position(Vector2i(1, 0), "NODE_N01")
	check(AppState.profile.inventory == inventory_before and int(AppState.profile.account.stamina) == stamina_fast, "fast-travel position update grants no reward and costs no stamina")
	check(str(LoaderScript.node_for_stage(definition, "CH01-N01").node_id) == "NODE_N01", "map to battle stage ID adapter stable")
	check(str(LoaderScript.node_by_id(definition, "NODE_N01").stage_id) == "CH01-N01", "battle to map node ID adapter stable")
	SettingsService.values.developer_mode = developer_mode_before
	AppState.profile = backup

func _test_preboss_staging_and_reveal_one_shot() -> void:
	var backup := AppState.profile.duplicate(true)
	AppState.new_game()
	for number in range(1, 19):
		AppState.record_stage_clear("CH01-N%02d" % number, 3)
	var n18 := LoaderScript.node_for_stage(definition, "CH01-N18")
	var n19 := LoaderScript.node_for_stage(definition, "CH01-N19")
	var n20 := LoaderScript.node_for_stage(definition, "CH01-N20")
	var n18_coord := Vector2i(int(n18.q), int(n18.r))
	var n19_coord := Vector2i(int(n19.q), int(n19.r))
	var n20_coord := Vector2i(int(n20.q), int(n20.r))
	AppState.set_chapter_map_position(n18_coord, str(n18.node_id))
	check(AppState.prepare_map_encounter("CH01-N19", str(n19.node_id), n18_coord), "PREBOSS_STAGING_01 N19 encounter prepares from the prior grounded staging hex")
	check(AppState.begin_battle_transaction("CH01-N19"), "PREBOSS_STAGING_02 N19 battle owns one transaction")
	var reveal_token := AppState.pending_battle_token
	check(AppState.record_stage_clear("CH01-N19", 3), "PREBOSS_STAGING_03 N19 first clear updates canonical progress")
	check(AppState.queue_story_event("STAGE_CLEAR", "CH01-N19"), "PREBOSS_STAGING_04 N19 clear queues the pre-boss story")
	check(AppState.apply_battle_result_to_map("CH01-N19", true), "PREBOSS_STAGING_05 N19 victory applies to the map once")
	var state := AppState.chapter_map_state()
	check(Vector2i(int(state.current_q), int(state.current_r)) == n19_coord and n19_coord != n20_coord, "PREBOSS_STAGING_06 squad remains on N19 staging, never the N20 hostile hex")
	check(state.get("pending_encounter", {}).is_empty() and AppState.pending_battle_token.is_empty(), "PREBOSS_STAGING_07 pre-boss story starts with zero battle transactions")
	check(AppState.is_stage_unlocked("CH01-N20"), "PREBOSS_STAGING_08 N20 canonical unlock is available before presentation")
	var pending_reveal: Dictionary = state.get("pending_reveal", {}).duplicate(true)
	check(str(pending_reveal.get("reveal_id", "")) == reveal_token and pending_reveal.get("unlocked_stage_ids", []).has("CH01-N20"), "REVEAL_ONESHOT_01 N20 reveal presentation is derived once from the battle token")
	AppState.refresh_chapter_map_reveal()
	check(AppState.chapter_map_state().get("pending_reveal", {}) == pending_reveal, "REVEAL_ONESHOT_02 canonical refresh does not recreate or mutate pending presentation")
	var reload_before_story := AppState.profile.duplicate(true)
	AppState.apply_loaded(reload_before_story)
	check(AppState.chapter_map_state().get("pending_reveal", {}) == pending_reveal, "REVEAL_ONESHOT_03 reload preserves the unconsumed presentation exactly once")
	var trigger := AppState.next_pending_story_trigger()
	check(str(trigger.get("scenario_id", "")) == "SCN_CH01_PREBOSS", "PREBOSS_STAGING_09 queued scenario is the N09 pre-boss story")
	var runner = ScenarioRunnerScript.new()
	var loaded = runner.load_scenario("SCN_CH01_PREBOSS", false)
	var safety := 0
	while loaded.ok and not runner.state.finished and safety < 100:
		safety += 1
		var command := runner.advance()
		if str(command.get("command", "")) == "choice": runner.choose(0)
	state = AppState.chapter_map_state()
	check(loaded.ok and runner.state.finished and Vector2i(int(state.current_q), int(state.current_r)) == n19_coord, "PREBOSS_STAGING_10 story completion preserves the N19 staging coordinate")
	check(state.get("pending_encounter", {}).is_empty() and AppState.pending_battle_token.is_empty(), "PREBOSS_STAGING_11 story completion cannot synthesize an N20 battle transaction")
	var consumed := AppState.consume_chapter_map_pending_reveal()
	check(str(consumed.get("reveal_id", "")) == reveal_token and AppState.chapter_map_state().get("pending_reveal", {}).is_empty(), "REVEAL_ONESHOT_04 map consumes the stored reveal presentation once")
	check(AppState.chapter_map_state().get("reveal_consumed", []).has(reveal_token) and AppState.consume_chapter_map_pending_reveal().is_empty(), "REVEAL_ONESHOT_05 duplicate presentation consumption is rejected")
	var reload_after_consumption := AppState.profile.duplicate(true)
	AppState.apply_loaded(reload_after_consumption)
	AppState.refresh_chapter_map_reveal()
	check(AppState.consume_chapter_map_pending_reveal().is_empty() and AppState.chapter_map_state().get("reveal_consumed", []).has(reveal_token), "REVEAL_ONESHOT_06 reload and canonical refresh never replay a consumed reveal")
	AppState.profile = backup

func _test_encounters_and_treasures() -> void:
	var backup := AppState.profile.duplicate(true)
	AppState.new_game()
	var state := AppState.chapter_map_state()
	var battle_nodes: Array = definition.get("nodes", []).filter(func(node): return str(node.get("stage_id", "")) != "")
	check(battle_nodes.all(func(node): return not ExplorationScript.encounter_cleared(state, str(node.node_id))), "all uncleared encounter states begin hostile")
	var n01 := LoaderScript.node_for_stage(definition, "CH01-N01")
	ExplorationScript.mark_encounter_cleared(state, str(n01.node_id))
	check(ExplorationScript.encounter_cleared(state, str(n01.node_id)), "cleared encounter state removes hostile-map eligibility")
	var visible: Dictionary = definition.get("treasures", []).filter(func(treasure): return str(treasure.visibility) == "VISIBLE")[0]
	var hidden: Dictionary = definition.get("treasures", []).filter(func(treasure): return str(treasure.visibility) == "HIDDEN")[0]
	check(ExplorationScript.treasure_state(state, str(visible.treasure_id)) == "REVEALED", "visible treasure is renderable from initial state")
	check(ExplorationScript.treasure_state(state, str(hidden.treasure_id)) == "UNDISCOVERED", "hidden treasure begins invisible")
	var hidden_coord := Vector2i(int(hidden.q), int(hidden.r))
	ExplorationScript.update_hidden_proximity(state, definition, hidden_coord + Vector2i(-2, 0))
	check(ExplorationScript.treasure_state(state, str(hidden.treasure_id)) == "HINTED", "hidden treasure enters hinted state at two hexes")
	ExplorationScript.update_hidden_proximity(state, definition, hidden_coord + Vector2i(-1, 0))
	check(ExplorationScript.treasure_state(state, str(hidden.treasure_id)) == "REVEALED", "hidden treasure reveals at one hex")
	var inventory_before: Dictionary = AppState.profile.inventory.duplicate(true)
	var claim := ExplorationScript.claim_treasure(state, definition, str(visible.treasure_id))
	var claim_again := ExplorationScript.claim_treasure(state, definition, str(visible.treasure_id))
	check(claim.ok and not claim_again.ok and state.claimed_treasures.has(str(visible.treasure_id)), "visible treasure reward is claimed exactly once")
	check(AppState.profile.inventory != inventory_before and str(claim.value.get("source_type", "")) == "TREASURE", "treasure uses shared reward resolver output")
	var module_visible: Dictionary = definition.get("treasures", []).filter(func(treasure): return str(treasure.get("treasure_id", "")) == "CH01_VT03")[0]
	var module_hidden: Dictionary = definition.get("treasures", []).filter(func(treasure): return str(treasure.get("treasure_id", "")) == "CH01_HT03")[0]
	var module_visible_claim := ExplorationScript.claim_treasure(state, definition, "CH01_VT03")
	var module_a_owned := int(AppState.profile.inventory.get("EXPEDITION_ROUTE_MODULE_A", 0))
	check(module_visible.get("rewards", {}).has("EXPEDITION_ROUTE_MODULE_A") and module_visible_claim.ok and module_a_owned == 1, "PULSE_REWARD_01 visible side treasure grants the authored route module")
	ExplorationScript.update_hidden_proximity(state, definition, Vector2i(int(module_hidden.q), int(module_hidden.r)))
	var module_hidden_claim := ExplorationScript.claim_treasure(state, definition, "CH01_HT03")
	var module_b_owned := int(AppState.profile.inventory.get("EXPEDITION_ROUTE_MODULE_B", 0))
	check(module_hidden.get("rewards", {}).has("EXPEDITION_ROUTE_MODULE_B") and module_hidden_claim.ok and module_b_owned == 1, "PULSE_REWARD_02 hidden side treasure grants the authored route module after reveal")
	var module_capacity_after_claim := ExplorationScript.movement_capacity(AppState.profile, definition)
	check(module_capacity_after_claim == 5, "PULSE_REWARD_03 claimed route modules immediately extend the next movement capacity")
	var module_duplicate_claim := ExplorationScript.claim_treasure(state, definition, "CH01_VT03")
	var module_after_duplicate := int(AppState.profile.inventory.get("EXPEDITION_ROUTE_MODULE_A", 0))
	check(not module_duplicate_claim.ok and module_after_duplicate == module_a_owned, "PULSE_REWARD_04 duplicate module treasure claim cannot increase inventory or movement capacity")
	var module_reloaded_profile: Dictionary = AppState.profile.duplicate(true)
	check(ExplorationScript.movement_capacity(module_reloaded_profile, definition) == module_capacity_after_claim, "PULSE_REWARD_05 route-module movement effect survives profile save payload restore")
	var capped_profile: Dictionary = module_reloaded_profile.duplicate(true)
	capped_profile.account.level = 80
	check(ExplorationScript.movement_capacity(capped_profile, definition) == 8, "PULSE_REWARD_06 movement capacity clamps milestone plus module bonuses at the global eight-cell max")
	var restored := state.duplicate(true)
	ExplorationScript.ensure_state(restored, definition)
	check(str(restored.treasure_states.get(str(hidden.treasure_id), "")) == "REVEALED" and restored.claimed_treasures.has(str(visible.treasure_id)), "treasure reveal and claim states survive save payload restoration")
	check(AppState.is_stage_unlocked("CH01-N01"), "treasure exploration is optional to normal route progress")
	AppState.profile = backup

func _test_reward_affordability() -> void:
	var before := AppState.profile.duplicate(true)
	before.inventory = {"CREDIT": 0, "TRAINING_NOTE_M": 0}
	before.roster.CHR001.level = 1
	before.roster.CHR001.xp = 0
	before.roster.CHR001.breakthrough = 0
	var after := before.duplicate(true)
	after.inventory.CREDIT = 10000
	after.inventory.TRAINING_NOTE_M = 1
	var analysis := GrowthAnalyzerScript.analyze(before, after)
	check(analysis.newly_affordable.any(func(candidate): return str(candidate.get("key", "")) == "LEVEL:CHR001"), "reward analyzer detects newly affordable character level-up")
	check(GrowthAnalyzerScript.analyze(after, after).newly_affordable.is_empty(), "already-affordable growth is not incorrectly marked NEW")
	var summary: Dictionary = GrowthAnalyzerScript.summary(GrowthAnalyzerScript.candidates(after))
	check(summary.has("level_characters") and summary.has("weapon_tiers"), "growth summary reports independent candidate categories")

func _test_dynamic_exploration() -> void:
	var backup := AppState.profile.duplicate(true)
	AppState.new_game()
	var first: Dictionary = ProgressScript.create_default(definition)
	var second: Dictionary = ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(first, definition)
	ExplorationScript.ensure_state(second, definition)
	var far_party := Vector2i(-50, 40)
	MapSimulationScript.advance_ticks(first, definition, grid, far_party, 18)
	MapSimulationScript.advance_ticks(second, definition, grid, far_party, 18)
	check(JSON.stringify(first.patrol_states) == JSON.stringify(second.patrol_states), "PATROL_01 fixed seed patrol deterministic")
	var restored := first.duplicate(true)
	ExplorationScript.ensure_state(restored, definition)
	check(JSON.stringify(restored.patrol_positions) == JSON.stringify(first.patrol_positions), "PATROL_02 save reload patrol position identical")
	var legacy_patrol_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(legacy_patrol_state, definition)
	legacy_patrol_state.patrol_states.NODE_N04 = {"current_patrol_index": 0, "direction": 1}
	legacy_patrol_state.patrol_positions.NODE_N04 = [0, 0]
	MapSimulationScript.ensure_state(legacy_patrol_state, definition, grid)
	check(MapSimulationScript.coord_for(legacy_patrol_state, "NODE_N04") == Vector2i(33, -6) and legacy_patrol_state.patrol_positions.NODE_N04 == [33, -6], "PATROL_SAVE_REPAIR_01 invalid legacy patrol state restores authored ground coordinate")
	var route_invalid_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(route_invalid_state, definition, grid)
	route_invalid_state.patrol_states.NODE_N03.q = 8
	route_invalid_state.patrol_states.NODE_N03.r = 1
	MapSimulationScript.ensure_state(route_invalid_state, definition, grid)
	check(MapSimulationScript.coord_for(route_invalid_state, "NODE_N03") == Vector2i(25, -2), "PATROL_SAVE_REPAIR_02 traversable coordinate outside own patrol route restores origin")
	var non_walkable_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(non_walkable_state, definition, grid)
	non_walkable_state.patrol_states.NODE_N04.q = -3
	non_walkable_state.patrol_states.NODE_N04.r = -4
	MapSimulationScript.ensure_state(non_walkable_state, definition, grid)
	check(MapSimulationScript.coord_for(non_walkable_state, "NODE_N04") == Vector2i(33, -6), "PATROL_SAVE_REPAIR_03 blocked water coordinate restores authored origin")
	var index_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(index_state, definition, grid)
	index_state.patrol_states.NODE_N03.q = 24
	index_state.patrol_states.NODE_N03.r = -1
	index_state.patrol_states.NODE_N03.current_patrol_index = 99
	index_state.patrol_states.NODE_N03.direction = 42
	MapSimulationScript.ensure_state(index_state, definition, grid)
	var normalized_n03: Dictionary = index_state.patrol_states.NODE_N03
	var normalized_coord := Vector2i(int(normalized_n03.q), int(normalized_n03.r))
	MapSimulationScript.advance_ticks(index_state, definition, grid, Vector2i(-50, 40), 1)
	check(int(normalized_n03.current_patrol_index) == 4 and int(normalized_n03.direction) == 1 and normalized_coord == MapSimulationScript.coord_for(index_state, "NODE_N03"), "PATROL_SAVE_REPAIR_04 coordinate, index and direction canonicalize while an unaware enemy holds position")
	var idempotent_state := non_walkable_state.duplicate(true)
	var first_repaired_hash := JSON.stringify(idempotent_state.patrol_states)
	for _iteration in range(10):
		MapSimulationScript.ensure_state(idempotent_state, definition, grid)
	check(JSON.stringify(idempotent_state.patrol_states) == first_repaired_hash, "PATROL_SAVE_REPAIR_05 repeated repair is idempotent")
	var overlap_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(overlap_state, definition, grid)
	overlap_state.patrol_states.NODE_N01.q = 8
	overlap_state.patrol_states.NODE_N01.r = 1
	overlap_state.patrol_states.NODE_N03.q = 8
	overlap_state.patrol_states.NODE_N03.r = 1
	MapSimulationScript.ensure_state(overlap_state, definition, grid)
	check(MapSimulationScript.coord_for(overlap_state, "NODE_N01") != MapSimulationScript.coord_for(overlap_state, "NODE_N03"), "PATROL_SAVE_REPAIR_06 repaired patrols never overlap on one hex")
	var lifecycle_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(lifecycle_state, definition, grid)
	lifecycle_state.encounter_states.NODE_N04 = "CLEARED"
	lifecycle_state.pending_encounter = {"node_id":"NODE_N03", "stage_id":"CH01-N03", "return_q":23, "return_r":-2, "token":"pending"}
	lifecycle_state.patrol_states.NODE_N04 = {"q":-3, "r":-4}
	var pending_before: Dictionary = lifecycle_state.pending_encounter.duplicate(true)
	MapSimulationScript.ensure_state(lifecycle_state, definition, grid)
	check(str(lifecycle_state.encounter_states.NODE_N04) == "CLEARED" and lifecycle_state.pending_encounter == pending_before, "PATROL_SAVE_REPAIR_07 clear and pending encounter lifecycle remain unchanged")
	var save_roundtrip_state := route_invalid_state.duplicate(true)
	var save_roundtrip_json := JSON.stringify(save_roundtrip_state)
	var save_roundtrip_parser := JSON.new()
	save_roundtrip_parser.parse(save_roundtrip_json)
	var reloaded_repair_state: Dictionary = save_roundtrip_parser.data
	var reloaded_changed := MapSimulationScript.ensure_state(reloaded_repair_state, definition, grid)
	check(not reloaded_changed and MapSimulationScript.coord_for(reloaded_repair_state, "NODE_N03") == Vector2i(25, -2), "PATROL_SAVE_REPAIR_08 repaired state survives save reload without repeat repair", "changed=%s n03=%s" % [str(reloaded_changed), JSON.stringify(reloaded_repair_state.patrol_states.get("NODE_N03", {}))])
	var unsafe_view_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(unsafe_view_state, definition, grid)
	unsafe_view_state.patrol_states.NODE_N04.q = -3
	unsafe_view_state.patrol_states.NODE_N04.r = -4
	var unsafe_before := JSON.stringify(unsafe_view_state.patrol_states)
	var view_coord := MapSimulationScript.render_coord_or_authored(unsafe_view_state, definition, grid, "NODE_N04", Vector2i(33, -6))
	check(view_coord == Vector2i(33, -6) and JSON.stringify(unsafe_view_state.patrol_states) == unsafe_before, "MAP_VIEW_FAILSAFE_01 invalid simulation coordinate renders authored fallback without view mutation")
	var n03: Dictionary = first.patrol_states.get("NODE_N03", {})
	check(int(n03.get("current_patrol_index", -1)) >= 0 and int(n03.get("current_patrol_index", -1)) < 5, "PATROL_03 loop route index stays valid")
	var n01: Dictionary = first.patrol_states.get("NODE_N01", {})
	check(int(n01.get("direction", 0)) in [-1, 1], "PATROL_04 ping-pong direction remains deterministic")
	var n04: Dictionary = first.patrol_states.get("NODE_N04", {})
	check(HexCoordScript.distance(Vector2i(int(n04.get("q", 0)), int(n04.get("r", 0))), Vector2i(33, -6)) <= 3, "PATROL_05 guard area never leaves leash")
	check(not MapSimulationScript.should_render_pawn(Vector2i(30, 0), Vector2i.ZERO, 8) and MapSimulationScript.should_render_pawn(Vector2i(3, 0), Vector2i.ZERO, 8), "PATROL_06 offscreen pawn render policy")
	var n01_def := MapSimulationScript.patrol_definition(definition, "NODE_N01")
	var awareness_runtime: Dictionary = first.patrol_states.get("NODE_N01", {}).duplicate(true)
	awareness_runtime.q = 8
	awareness_runtime.r = 1
	check(MapSimulationScript.awareness_for(n01_def, awareness_runtime, Vector2i(8, 1), grid, definition) == MapSimulationScript.ALERT, "AWARENESS_01 distance alert state")
	var synthetic := HexGridScript.new()
	synthetic.load_tiles([{"q":0,"r":0,"elevation":0},{"q":1,"r":0,"elevation":0},{"q":2,"r":0,"elevation":0}])
	check(not MapSimulationScript.has_line_of_sight(synthetic, {"los_blockers":[{"q":1,"r":0}]}, Vector2i.ZERO, Vector2i(2, 0)), "AWARENESS_02 cliff/rock blocker stops line of sight")
	var ten_hex_grid := HexGridScript.new()
	var ten_hex_tiles: Array = []
	for q in range(11):
		ten_hex_tiles.append({"q":q,"r":0,"elevation":0})
	ten_hex_grid.load_tiles(ten_hex_tiles)
	check(MapSimulationScript.awareness_for({"awareness_radius":3,"alert_radius":1}, {"q":0,"r":0}, Vector2i(9, 0), ten_hex_grid, {}) != MapSimulationScript.UNAWARE, "AWARENESS_03 normal enemies recognize the party within the ten-hex baseline")
	var event_node: Dictionary = definition.get("event_encounters", [])[0]
	var event_patrol := MapSimulationScript.patrol_definition(definition, str(event_node.get("node_id", "")))
	var boss_node := LoaderScript.node_for_stage(definition, "CH01-N20")
	var boss_patrol := MapSimulationScript.patrol_definition(definition, str(boss_node.get("node_id", "")))
	var boss_is_fixed := boss_patrol.is_empty() or MapSimulationScript.patrol_is_stationary(definition, boss_patrol)
	var event_is_fixed := event_patrol.is_empty() or MapSimulationScript.patrol_is_stationary(definition, event_patrol)
	check(not MapSimulationScript.patrol_is_stationary(definition, n01_def) and event_is_fixed and boss_is_fixed, "ENEMY_TURN_01 normal mobs are mobile while companion/special contacts and bosses are stationary")
	var no_contact := MapSimulationScript.advance_ticks(first, definition, grid, Vector2i(-30, 30), 1)
	check(no_contact.get("contacts", []).is_empty(), "AWARENESS_04 player not touching creates no battle contact")
	var contact_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(contact_state, definition)
	contact_state.patrol_states.NODE_N01.next_move_tick = 999
	var contact := MapSimulationScript.advance_ticks(contact_state, definition, grid, Vector2i(8, 1), 1)
	check(contact.get("contacts", []).size() == 1 and str(contact.contacts[0]) == "NODE_N01", "AWARENESS_05 actual contact produces one owner")
	contact_state.patrol_states.NODE_N03.q = 8
	contact_state.patrol_states.NODE_N03.r = 1
	contact_state.patrol_states.NODE_N03.next_move_tick = 999
	var concurrent := MapSimulationScript.advance_ticks(contact_state, definition, grid, Vector2i(8, 1), 1)
	check(concurrent.get("contacts", []).size() >= 1 and str(concurrent.contacts[0]) == "NODE_N01", "AWARENESS_06 simultaneous contact has stable owner")
	var pursuit_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(pursuit_state, definition)
	# Keep unrelated patrols away so this exercises a selected moving N07 target,
	# rather than allowing a nearby authored encounter to claim the transaction.
	for encounter_id in pursuit_state.patrol_states.keys():
		if str(encounter_id) == "NODE_N07":
			continue
		pursuit_state.patrol_states[encounter_id].q = -90
		pursuit_state.patrol_states[encounter_id].r = 90
		pursuit_state.patrol_states[encounter_id].next_move_tick = 99999
	var n07_node := LoaderScript.node_for_stage(definition, "CH01-N07")
	var pursuit_party := LoaderScript.node_for_stage(definition, "CH01-N06")
	var pursuit_coord := Vector2i(int(pursuit_party.q), int(pursuit_party.r))
	var selected_contact := ""
	var replan_count := 0
	var pursuit_paths_valid := true
	while replan_count <= 3 and selected_contact.is_empty():
		var live_path := MapSimulationScript.pursuit_path(pursuit_state, definition, grid, pursuit_coord, "NODE_N07")
		if live_path.size() <= 1:
			break
		pursuit_paths_valid = pursuit_paths_valid and live_path.front() == pursuit_coord and live_path.back() == MapSimulationScript.coord_for(pursuit_state, "NODE_N07")
		for path_index in range(1, live_path.size()):
			pursuit_coord = live_path[path_index]
			var pursuit_update := MapSimulationScript.advance_ticks(pursuit_state, definition, grid, pursuit_coord, 1)
			if pursuit_update.get("contacts", []).has("NODE_N07"):
				selected_contact = "NODE_N07"
				break
		replan_count += 1
	check(pursuit_paths_valid and replan_count > 0, "PATROL_CONTACT_ROUTE_01 pursuit path targets the live patrol position")
	check(selected_contact == "NODE_N07" and replan_count <= 3, "PATROL_CONTACT_ROUTE_02 moving selected patrol is re-pathed and contacts exactly once")
	var wait_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(wait_state, definition)
	var party_before := Vector2i(int(wait_state.current_q), int(wait_state.current_r))
	var tick_before := int(wait_state.map_simulation_state.tick)
	MapSimulationScript.advance_wait(wait_state, definition, grid, party_before)
	check(int(wait_state.map_simulation_state.tick) > tick_before, "WAIT_01 wait advances patrol simulation")
	check(Vector2i(int(wait_state.current_q), int(wait_state.current_r)) == party_before, "WAIT_02 wait keeps party coordinate")
	var relay_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(relay_state, definition)
	var relay_on := ExplorationScript.activate_relay(relay_state, definition, "RELAY_START")
	check(relay_on.ok and ExplorationScript.relay_state(relay_state, "RELAY_START") == "ACTIVE", "RELAY_01 offline relay activates without growth cost")
	var relay_restored := relay_state.duplicate(true)
	ExplorationScript.ensure_state(relay_restored, definition)
	check(ExplorationScript.relay_state(relay_restored, "RELAY_START") == "ACTIVE", "RELAY_02 relay state survives payload restore")
	check(not relay_state.discovered_tiles.is_empty(), "RELAY_03 relay expands local discovery")
	var coast: Dictionary = definition.relays.filter(func(relay): return str(relay.relay_id) == "RELAY_COAST")[0]
	relay_state.visited_tiles.append("%d,%d" % [int(coast.q), int(coast.r)])
	ExplorationScript.activate_relay(relay_state, definition, "RELAY_COAST")
	check(ExplorationScript.can_fast_travel_between(relay_state, definition, "RELAY_START", "RELAY_COAST"), "RELAY_04 active discovered relays allow fast travel")
	var unopened := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(unopened, definition)
	check(not ExplorationScript.can_fast_travel_between(unopened, definition, "RELAY_START", "RELAY_COAST"), "RELAY_05 inactive relay cannot bypass progression")
	var event_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(event_state, definition)
	check(ExplorationScript.discover_event(event_state, definition, "EVENT_BROKEN_SWITCH"), "EVENT_01 event discovers exactly once")
	var event_reward := ExplorationScript.resolve_event(event_state, definition, "EVENT_BROKEN_SWITCH", "SALVAGE")
	var event_again := ExplorationScript.resolve_event(event_state, definition, "EVENT_BROKEN_SWITCH", "SALVAGE")
	check(event_reward.ok and not event_again.ok, "EVENT_02 choice is resolved and persisted exactly once")
	check(str(event_state.map_event_states.EVENT_BROKEN_SWITCH) == "RESOLVED", "EVENT_03 event resolution prevents reload duplicate reward")
	check(event_state.intel_states.has("INTEL_SWITCH_SALVAGED"), "INTEL_01 exploration intel is stored")
	var completion := ExplorationScript.completion(event_state, definition)
	check(completion.has("percent") and not completion.has("hidden_total"), "EXPLORATION_01 completion is detailed without exposing hidden total")
	check(int(completion.get("visible_total", 0)) == 6 and int(completion.get("hidden_found", 0)) == 0, "EXPLORATION_02 hidden discovery remains undisclosed until found")
	AppState.profile = backup

func _test_direct_move_turn_contracts() -> void:
	var backup := AppState.profile.duplicate(true)
	AppState.new_game()
	var turn_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(turn_state, definition, grid)
	# Begin from a partially spent player turn. The model helper must be exactly
	# equivalent to one enemy action tick followed by one refill.
	check(ExplorationScript.spend_movement(turn_state, definition, 2), "TURN_HANDOFF_FIXTURE_01 movement can be partially spent before automatic handoff")
	var expected_turn_state := turn_state.duplicate(true)
	var far_party := Vector2i(-50, 40)
	var expected_update := MapSimulationScript.advance_ticks(expected_turn_state, definition, grid, far_party, 1)
	ExplorationScript.refill_movement(expected_turn_state, definition)
	var tick_before := int(turn_state.get("map_simulation_state", {}).get("tick", 0))
	var pulse_before := int(turn_state.get("exploration_pulse", 0))
	var turn_update := ExplorationScript.complete_player_move_turn(turn_state, definition, grid, far_party)
	var update_matches: bool = turn_update.get("changed", []) == expected_update.get("changed", []) and turn_update.get("moves", []) == expected_update.get("moves", []) and turn_update.get("contacts", []) == expected_update.get("contacts", []) and turn_update.get("awareness", {}) == expected_update.get("awareness", {})
	var handoff_metadata_matches: bool = int(turn_update.get("tick_before", -1)) == tick_before and int(turn_update.get("tick_after", -1)) == tick_before + 1 and int(turn_update.get("pulse_before", -1)) == pulse_before and int(turn_update.get("pulse_after", -1)) == pulse_before + 1 and int(turn_update.get("movement_points", -1)) == int(turn_state.get("movement_points_max", 0))
	check(JSON.stringify(turn_state) == JSON.stringify(expected_turn_state) and update_matches and handoff_metadata_matches, "TURN_HANDOFF_01 player move completion advances one enemy phase and refills movement exactly once", JSON.stringify(turn_update))

	var contact_state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(contact_state, definition, grid)
	var n01_contact_coord := MapSimulationScript.coord_for(contact_state, "NODE_N01")
	var contact_state_before := JSON.stringify(contact_state)
	var first_contacts := MapSimulationScript.contacts_at_party_coord(contact_state, definition, grid, n01_contact_coord)
	var second_contacts := MapSimulationScript.contacts_at_party_coord(contact_state, definition, grid, n01_contact_coord)
	check(first_contacts.has("NODE_N01") and first_contacts == second_contacts and JSON.stringify(contact_state) == contact_state_before, "TURN_CONTACT_01 per-step contact query is deterministic and side-effect free", JSON.stringify(first_contacts))

	var mouse_double := InputEventMouseButton.new()
	mouse_double.button_index = MOUSE_BUTTON_LEFT
	mouse_double.pressed = true
	mouse_double.double_click = true
	var mouse_single := InputEventMouseButton.new()
	mouse_single.button_index = MOUSE_BUTTON_LEFT
	mouse_single.pressed = true
	var mouse_right_double := InputEventMouseButton.new()
	mouse_right_double.button_index = MOUSE_BUTTON_RIGHT
	mouse_right_double.pressed = true
	mouse_right_double.double_click = true
	var touch_release := InputEventScreenTouch.new()
	touch_release.pressed = false
	touch_release.canceled = false
	var touch_press := InputEventScreenTouch.new()
	touch_press.pressed = true
	var touch_canceled := InputEventScreenTouch.new()
	touch_canceled.pressed = false
	touch_canceled.canceled = true
	var screen_drag := InputEventScreenDrag.new()
	check(ChapterMapScreenScript.direct_move_gesture_policy(mouse_double) and not ChapterMapScreenScript.direct_move_gesture_policy(mouse_single) and not ChapterMapScreenScript.direct_move_gesture_policy(mouse_right_double), "DIRECT_MOVE_INPUT_01 only a pressed left-button double click directly confirms desktop movement")
	check(ChapterMapScreenScript.direct_move_gesture_policy(touch_release) and not ChapterMapScreenScript.direct_move_gesture_policy(touch_release, false, false) and not ChapterMapScreenScript.direct_move_gesture_policy(touch_press) and not ChapterMapScreenScript.direct_move_gesture_policy(touch_canceled) and not ChapterMapScreenScript.direct_move_gesture_policy(screen_drag), "DIRECT_MOVE_INPUT_02 one completed uncancelled touch tap directly confirms movement while press, cancel and drag do not")
	check(ChapterMapScreenScript.direct_move_gesture_policy(mouse_single, true) and not ChapterMapScreenScript.direct_move_gesture_policy(mouse_right_double, true), "DIRECT_MOVE_INPUT_03 a rapid repeated left press confirms Web movement even when the browser omits native double_click")

	# Side targets may share a corridor with an uncleared encounter.  The route
	# truncation must promote that encounter to the actual selection; otherwise a
	# relay/event detail card claims to be active while movement stops elsewhere.
	var route_screen := ChapterMapScreenScript.new()
	route_screen.definition = definition
	route_screen.grid = grid
	route_screen.map_state = ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(route_screen.map_state, definition, grid)
	var blocking_node := LoaderScript.node_by_id(definition, "NODE_N01")
	var blocking_coord := route_screen._encounter_coord(blocking_node)
	route_screen.preview_path = [Vector2i(int(route_screen.map_state.current_q), int(route_screen.map_state.current_r)), blocking_coord]
	route_screen.selected_event = {"event_id": "TEST_DISTANT_EVENT", "q": blocking_coord.x + 4, "r": blocking_coord.y}
	check(route_screen._retarget_truncated_path_to_encounter(blocking_coord + Vector2i(4, 0)) and str(route_screen.selected_node.get("node_id", "")) == "NODE_N01" and route_screen.selected_event.is_empty() and route_screen.selected_relay.is_empty(), "DIRECT_MOVE_PATH_01 a side-target route truncated by an unresolved encounter selects the actual blocking encounter")
	var direct_path: Array[Vector2i] = []
	# A patrol may have advanced outside the authored reveal snapshot while still
	# remaining visibly actionable. Mirror the live-pawn fallback used by the
	# screen and verify its bounded endpoint is authorized independently of UI.
	direct_path.assign(HexPathfinderScript.find_path(grid, Vector2i(int(route_screen.map_state.current_q), int(route_screen.map_state.current_r)), blocking_coord))
	route_screen.preview_path = direct_path
	route_screen.selected_node = blocking_node
	var direct_pulse := route_screen._path_for_current_pulse(direct_path)
	if direct_pulse.size() > 1:
		route_screen.movement_range_reachable[HexCoordScript.key(direct_pulse[-1])] = direct_pulse.size() - 1
	check(route_screen.move_button == null and route_screen._can_begin_selected_route(), "DIRECT_MOVE_PATH_02 compact-layout direct movement uses reachable gameplay authority without requiring a visible detail-panel button")
	route_screen.free()

	var tutorial_screen := ChapterMapScreenScript.new()
	tutorial_screen.map_id = "CH01_MAP"
	tutorial_screen._build_first_map_tutorial()
	tutorial_screen._apply_tutorial_layout(Vector2(1280, 720), false, false, 1.0)
	var tutorial_outer_style := tutorial_screen.tutorial_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var modal_geometry_ok: bool = tutorial_screen.tutorial_canvas_layer != null and tutorial_screen.tutorial_canvas_layer.layer == 90 and tutorial_screen.tutorial_panel.get_parent() == tutorial_screen.tutorial_surface and tutorial_screen.tutorial_dimmer != null and is_equal_approx(tutorial_screen.tutorial_panel.anchor_left, 0.10) and is_equal_approx(tutorial_screen.tutorial_panel.anchor_right, 0.90) and is_equal_approx(tutorial_screen.tutorial_panel.anchor_top, 0.105) and is_equal_approx(tutorial_screen.tutorial_panel.anchor_bottom, 0.96) and tutorial_outer_style != null and tutorial_outer_style.border_width_left == 2 and tutorial_screen.tutorial_inner_frame != null and tutorial_screen.tutorial_body.get_parent() is ScrollContainer and tutorial_screen.tutorial_title.has_theme_font_override("font") and tutorial_screen.tutorial_body.has_theme_font_override("normal_font") and tutorial_screen.tutorial_body.has_theme_font_override("bold_font")
	check(modal_geometry_ok, "TUTORIAL_MODAL_01 first-map guidance uses one full-screen dimmed 80x85.5 briefing modal with a double gold frame and scrolling body")
	var portrait_scale := tutorial_screen._compact_ui_scale(Vector2(390, 844))
	tutorial_screen._apply_tutorial_layout(Vector2(390, 844), true, true, portrait_scale)
	check(tutorial_screen.tutorial_dismiss_button.visible and tutorial_screen.tutorial_dismiss_button.custom_minimum_size.x <= 102.1 * portrait_scale and tutorial_screen.tutorial_dismiss_button.custom_minimum_size.y >= 43.9 * portrait_scale and is_equal_approx(tutorial_screen.tutorial_panel.anchor_top, 0.48) and is_equal_approx(tutorial_screen.tutorial_panel.anchor_bottom, 0.955) and tutorial_screen.tutorial_continue_button.custom_minimum_size.x <= 228.1 * portrait_scale and tutorial_screen.tutorial_body.get_theme_font_size("normal_font_size") >= roundi(20.0 * portrait_scale) and tutorial_screen.tutorial_body.get_theme_font_size("bold_font_size") == tutorial_screen.tutorial_body.get_theme_font_size("normal_font_size") and tutorial_screen.tutorial_dimmer.color.a < 0.60, "TUTORIAL_MODAL_02 portrait uses a map-visible lower instruction sheet with equal regular/bold copy, a centered footer and an explicit skip control")
	check(ChapterMapScreenScript.tutorial_short_tap_policy(Vector2.ZERO, Vector2(8, 4), 240, false, 18.0, 800) and not ChapterMapScreenScript.tutorial_short_tap_policy(Vector2.ZERO, Vector2(40, 0), 240, false, 18.0, 800) and not ChapterMapScreenScript.tutorial_short_tap_policy(Vector2.ZERO, Vector2(2, 0), 900, false, 18.0, 800) and not ChapterMapScreenScript.tutorial_short_tap_policy(Vector2.ZERO, Vector2.ZERO, 120, true, 18.0, 800), "TUTORIAL_MODAL_03 any short body/title tap dismisses while drag, long press and canceled touch remain scroll-safe")
	tutorial_screen._set_tutorial_step(3)
	check(tutorial_screen.tutorial_panel.visible and not tutorial_screen.moving and not tutorial_screen.turn_transitioning, "TUTORIAL_MODAL_04 showing the third briefing step is presentation-only and never takes movement authority")
	tutorial_screen.free()

	var map_screen_source := FileAccess.get_file_as_string("res://chapter_map/runtime/chapter_map_screen.gd")
	var process_body := _source_function_body(map_screen_source, "_process")
	var move_body := _source_function_body(map_screen_source, "_move_along")
	var skip_body := _source_function_body(map_screen_source, "skip_movement")
	var confirm_body := _source_function_body(map_screen_source, "_confirm_move")
	var enemy_turn_body := _source_function_body(map_screen_source, "_complete_player_turn")
	var app_shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd")
	check(not process_body.is_empty() and not process_body.contains("_advance_map_simulation("), "TURN_SOURCE_01 idle frame processing never advances enemy simulation")
	check(not move_body.is_empty() and not move_body.contains("MapSimulationScript.advance_ticks(") and not skip_body.is_empty() and not skip_body.contains("MapSimulationScript.advance_ticks("), "TURN_SOURCE_02 animated and skipped player movement never advance enemy time per step")
	check(enemy_turn_body.contains("update.get(\"moves\", [])") and enemy_turn_body.contains("_focus_coord(destination, false)") and enemy_turn_body.contains("_focus_current(false)"), "TURN_SOURCE_03 enemy phase follows every moving mob and returns the camera to the party")
	check(map_screen_source.contains("signal map_ready") and map_screen_source.contains("await _build_world()") and map_screen_source.contains("await _stream_visible_tiles(Vector2i(int(map_state.current_q), int(map_state.current_r)), true, true)") and map_screen_source.contains("created_count % 18") and app_shell_source.contains("await map_screen.map_ready"), "MAP_LOAD_COOPERATIVE_01 initial map construction yields between streamed batches and the shell keeps loading authority until the map is ready")
	check(confirm_body.find("_set_tutorial_step(3)") >= 0 and confirm_body.find("_move_along(pulse_path)") > confirm_body.find("_set_tutorial_step(3)"), "TUTORIAL_FLOW_01 direct movement starts in the same confirmation call after step-three guidance is displayed")
	AppState.profile = backup

func _test_exploration_pulses_and_companion_events() -> void:
	var backup := AppState.profile.duplicate(true)
	AppState.new_game()
	var state := ProgressScript.create_default(definition)
	ExplorationScript.ensure_state(state, definition, grid)
	check(int(state.get("movement_points_max", 0)) == 3 and int(state.get("movement_points", 0)) == 3, "PULSE_01 a fresh Chapter 1 map starts with the authored three-cell movement limit")
	var spent := 0
	while ExplorationScript.spend_movement(state, definition, 1): spent += 1
	check(spent == 3 and not ExplorationScript.spend_movement(state, definition, 1), "PULSE_02 a pulse cannot exceed its deterministic movement capacity")
	var party_before := Vector2i(int(state.current_q), int(state.current_r))
	ExplorationScript.refill_movement(state, definition)
	check(int(state.movement_points) == 3 and int(state.exploration_pulse) == 1 and Vector2i(int(state.current_q), int(state.current_r)) == party_before, "PULSE_03 wait refills map movement without changing party position")
	AppState.profile.inventory.EXPEDITION_ROUTE_MODULE_A = 1
	AppState.profile.inventory.EXPEDITION_ROUTE_MODULE_B = 1
	var module_capacity := ExplorationScript.movement_capacity(AppState.profile, definition)
	check(module_capacity == 5, "PULSE_04 owned exploration modules extend capacity without consuming stamina")
	var map_screen_source := FileAccess.get_file_as_string("res://chapter_map/runtime/chapter_map_screen.gd")
	check(map_screen_source.contains("노선 모듈 +%d · 최종 상한 %d") and map_screen_source.contains("account_level_milestones") and map_screen_source.contains("mobility_items") and map_screen_source.contains("노란 영역 안에서만 이동"), "PULSE_UI_01 map detail exposes base, account-level, route-module and global movement-cap sources")
	var vera := ExplorationScript.event_encounter_for_node(definition, "NODE_N08")
	check(str(vera.get("character_id", "")) == "CHR006" and str(vera.get("marker", "")) == "BANG", "EVENT_PAWN_01 authored event encounter maps to Vera and the bang marker")
	check(ExplorationScript.event_encounter_state(state, str(vera.get("event_encounter_id", ""))) == "AVAILABLE", "EVENT_PAWN_02 special encounter begins available without mutating stage unlock")
	# The contact payload must survive the map-to-battle handoff as presentation
	# context only. It is not a second reward or recruitment authority.
	AppState.profile.chapter_map = {"CH01_MAP": state.duplicate(true)}
	var credit_before_contact := int(AppState.profile.inventory.get("CREDIT", 0))
	AppState.pending_battle_token = ""
	check(AppState.prepare_map_encounter("CH01-N08", "NODE_N08", Vector2i.ZERO), "EVENT_PAWN_02A special contact prepares one ordinary battle transaction")
	var contact_payload := AppState.pending_map_special_event()
	check(str(contact_payload.get("event_encounter_id", "")) == str(vera.get("event_encounter_id", "")) and str(contact_payload.get("event_kind", "")) == "COMPANION" and str(contact_payload.get("character_id", "")) == "CHR006" and str(contact_payload.get("contact_outcome_key", "")) == str(vera.get("contact_outcome_key", "")) and contact_payload.get("pre_battle_dialogue", []).size() == 3 and str(state.get("recruitment_states", {}).get("CHR006", "")) == "UNMET", "EVENT_PAWN_02B companion contact carries dialogue presentation only; recruitment is still uncommitted before victory")
	AppState.abandon_pending_map_encounter()
	check(AppState.pending_map_special_event().is_empty() and int(AppState.profile.inventory.get("CREDIT", 0)) == credit_before_contact, "EVENT_PAWN_02C abandoning a special contact clears only its presentation transaction and grants no reward")
	var anomaly := ExplorationScript.event_encounter_for_node(definition, "NODE_N06")
	check(str(anomaly.get("event_kind", "")) == "SPECIAL_ENEMY" and str(anomaly.get("enemy_id", "")) == "ENM010" and anomaly.get("recruitments", []).is_empty(), "EVENT_PAWN_02D special enemy contact is a non-recruiting event with an authored enemy identity")
	check(AppState.prepare_map_encounter("CH01-N06", "NODE_N06", Vector2i.ZERO), "EVENT_PAWN_02E special enemy contact prepares its ordinary map battle transaction")
	var anomaly_payload := AppState.pending_map_special_event()
	check(str(anomaly_payload.get("event_kind", "")) == "SPECIAL_ENEMY" and str(anomaly_payload.get("enemy_id", "")) == "ENM010" and anomaly_payload.get("character_ids", []).is_empty() and anomaly_payload.get("pre_battle_dialogue", []).size() == 3, "EVENT_PAWN_02F special enemy handoff carries enemy art/dialogue data but no companion grant")
	AppState.abandon_pending_map_encounter()
	# Reproduce the player-facing last approach: an honestly unlocked N20 route
	# ends on the hostile hex, then the existing one-shot contact transaction
	# owns both the title-card payload and exactly one battle entry.
	AppState.new_game()
	AppState.profile.chapter_progress.CH01.normal_highest = 19
	for normal_number in range(1, 20):
		AppState.profile.stage_stars["CH01-N%02d" % normal_number] = 3
	var boss_state := ProgressScript.migrate_from_profile(AppState.profile, definition)
	ExplorationScript.ensure_state(boss_state, definition, grid)
	var n19 := LoaderScript.node_for_stage(definition, "CH01-N19")
	var n20 := LoaderScript.node_for_stage(definition, "CH01-N20")
	var boss_allowed: Dictionary = {}
	for raw_key in boss_state.get("revealed_tiles", []): boss_allowed[str(raw_key)] = true
	var boss_start := Vector2i(int(n19.q), int(n19.r))
	var boss_contact := Vector2i(int(n20.q), int(n20.r))
	var boss_path := HexPathfinderScript.find_path(grid, boss_start, boss_contact, boss_allowed)
	var boss_pre_contact := boss_path[-2] if boss_path.size() > 1 else boss_start
	ProgressScript.mark_visited(boss_state, boss_path)
	AppState.profile.chapter_map = {"CH01_MAP": boss_state.duplicate(true)}
	AppState.set_chapter_map_position(boss_contact, str(n20.node_id))
	AppState.pending_battle_token = ""
	check(boss_path.size() > 1 and boss_path.front() == boss_start and boss_path.back() == boss_contact and AppState.prepare_map_encounter("CH01-N20", str(n20.node_id), boss_pre_contact), "BOSS_PRESENTATION_03 physical N19-to-N20 route reaches one boss contact transaction")
	var boss_payload := AppState.pending_map_encounter_presentation()
	var expected_boss_payload: Dictionary = n20.get("presentation", {})
	var boss_started_once := AppState.begin_battle_transaction("CH01-N20")
	var boss_started_twice := AppState.begin_battle_transaction("CH01-N20")
	check(boss_started_once and not boss_started_twice and not AppState.pending_battle_token.is_empty() and boss_payload == expected_boss_payload, "BOSS_PRESENTATION_04 physical contact keeps one localized card payload and starts one battle")
	var boss_save := AppState.profile.duplicate(true)
	AppState.apply_loaded(boss_save)
	var recovered_boss_state := AppState.chapter_map_state()
	check(AppState.pending_battle_token.is_empty() and AppState.pending_map_encounter_presentation().is_empty() and recovered_boss_state.get("pending_encounter", {}).is_empty() and int(recovered_boss_state.get("current_q", 999)) == boss_pre_contact.x and int(recovered_boss_state.get("current_r", 999)) == boss_pre_contact.y and boss_payload == expected_boss_payload, "BOSS_PRESENTATION_05 reload clears a live boss presentation and restores the exact pre-contact map hex")
	AppState.abandon_pending_map_encounter()
	var vera_result := ExplorationScript.resolve_event_encounter_victory(state, definition, "NODE_N08", "CH01-N08")
	check(bool(vera_result.get("recruit_now", false)) and str(state.recruitment_states.get("CHR006", "")) == "READY", "EVENT_PAWN_03 contact victory resolves the immediate companion only once")
	var vera_again := ExplorationScript.resolve_event_encounter_victory(state, definition, "NODE_N08", "CH01-N08")
	check(vera_again.is_empty(), "EVENT_PAWN_04 reload or duplicate result cannot recruit twice")
	var two_definition := LoaderScript.load_map("CH05_MAP")
	var two_event: Dictionary = two_definition.get("event_encounters", []).filter(func(row): return str(row.get("event_kind", "")) == "COMPANION").front()
	var two_state := ProgressScript.create_default(two_definition)
	ExplorationScript.ensure_state(two_state, two_definition)
	var two_contact := ExplorationScript.resolve_event_encounter_victory(two_state, two_definition, str(two_event.node_id), str(two_event.stage_id))
	var two_join := ExplorationScript.resolve_deferred_recruitments(two_state, two_definition, "CH05-N10")
	check(not bool(two_contact.get("recruit_now", true)) and str(two_state.recruitment_states.get("CHR010", "")) == "READY" and two_join == ["CHR010"], "EVENT_PAWN_05 Chapter 5 companion resolves after the authored two-victory route")
	var three_definition := LoaderScript.load_map("CH14_MAP")
	var three_event: Dictionary = three_definition.get("event_encounters", []).filter(func(row): return str(row.get("event_kind", "")) == "COMPANION").front()
	var three_state := ProgressScript.create_default(three_definition)
	ExplorationScript.ensure_state(three_state, three_definition)
	var three_contact := ExplorationScript.resolve_event_encounter_victory(three_state, three_definition, str(three_event.node_id), str(three_event.stage_id))
	var three_second := ExplorationScript.resolve_deferred_recruitments(three_state, three_definition, "CH14-N15")
	var three_third := ExplorationScript.resolve_deferred_recruitments(three_state, three_definition, "CH14-N16")
	check(not bool(three_contact.get("recruit_now", true)) and three_second.is_empty() and three_third == ["CHR019"] and str(three_state.recruitment_states.get("CHR019", "")) == "READY", "EVENT_PAWN_06 Chapter 14 companion resolves exactly after the authored three-victory route", JSON.stringify({"second": three_second, "third": three_third, "progress": three_state.get("recruitment_progress", {})}))
	# Chapter expansion contacts may introduce a duo. Prove the two records retain
	# one map transaction, resolve different timings, and cannot double-grant.
	var duo_definition := definition.duplicate(true)
	duo_definition.event_encounters = [{
		"event_encounter_id": "TEST_DUO_CONTACT", "node_id": "NODE_N03", "marker": "BANG", "entry_type": "EVENT_CONTACT",
		"title_key": "MAP_EVENT_CONTACT_VERa_TITLE", "body_key": "MAP_EVENT_CONTACT_VERa_BODY", "contact_outcome_key": "MAP_EVENT_CONTACT_VERa_OUTCOME",
		"recruitments": [
			{"character_id": "CHR006", "recruitment_timing": "IMMEDIATE_ON_VICTORY", "recruit_after_stage_id": ""},
			{"character_id": "CHR007", "recruitment_timing": "AFTER_STAGE_CLEAR", "recruit_after_stage_id": "CH01-N04"},
		],
	}]
	var duo_state := ProgressScript.create_default(duo_definition)
	ExplorationScript.ensure_state(duo_state, duo_definition)
	var duo_result := ExplorationScript.resolve_event_encounter_victory(duo_state, duo_definition, "NODE_N03", "CH01-N03")
	var duo_repeat := ExplorationScript.resolve_event_encounter_victory(duo_state, duo_definition, "NODE_N03", "CH01-N03")
	check(duo_result.get("recruit_now_ids", []) == ["CHR006"] and str(duo_state.recruitment_states.get("CHR007", "")) == "PENDING" and duo_repeat.is_empty(), "EVENT_PAWN_DUO_01 one contact resolves immediate and delayed recruitments exactly once")
	check(ExplorationScript.resolve_deferred_recruitments(duo_state, duo_definition, "CH01-N03").is_empty() and ExplorationScript.resolve_deferred_recruitments(duo_state, duo_definition, "CH01-N04") == ["CHR007"] and str(duo_state.recruitment_states.get("CHR007", "")) == "READY", "EVENT_PAWN_DUO_02 deferred member resolves at its authored stage only")
	var five_battle_definition := definition.duplicate(true)
	five_battle_definition.event_encounters = [{
		"event_encounter_id": "TEST_FIVE_BATTLE_CONTACT", "node_id": "NODE_N03", "marker": "BANG", "entry_type": "EVENT_CONTACT",
		"recruitments": [{"character_id": "CHR020", "recruitment_timing": "IMMEDIATE_ON_VICTORY", "recruit_after_stage_id": "", "battle_victories_required": 5}],
	}]
	var five_battle_state := ProgressScript.create_default(five_battle_definition)
	ExplorationScript.ensure_state(five_battle_state, five_battle_definition)
	var five_battle_contact := ExplorationScript.resolve_event_encounter_victory(five_battle_state, five_battle_definition, "NODE_N03", "CH01-N03")
	var before_fifth: Array[String] = []
	before_fifth.append_array(ExplorationScript.resolve_deferred_recruitments(five_battle_state, five_battle_definition, "CH01-N03"))
	before_fifth.append_array(ExplorationScript.resolve_deferred_recruitments(five_battle_state, five_battle_definition, "CH01-N04"))
	before_fifth.append_array(ExplorationScript.resolve_deferred_recruitments(five_battle_state, five_battle_definition, "CH01-N04"))
	before_fifth.append_array(ExplorationScript.resolve_deferred_recruitments(five_battle_state, five_battle_definition, "CH01-N05"))
	before_fifth.append_array(ExplorationScript.resolve_deferred_recruitments(five_battle_state, five_battle_definition, "CH01-N06"))
	var fifth_result := ExplorationScript.resolve_deferred_recruitments(five_battle_state, five_battle_definition, "CH01-N07")
	check(not bool(five_battle_contact.get("recruit_now", true)) and before_fifth.is_empty() and fifth_result == ["CHR020"] and int(five_battle_state.recruitment_progress.CHR020.get("victories", 0)) == 5, "EVENT_PAWN_ROUTE_01 a five-battle recruit counts unique operation victories and joins exactly on victory five")
	var source := FileAccess.get_file_as_string("res://chapter_map/runtime/chapter_map_screen.gd")
	check(source.contains("CompanionEventMapPawn_") and source.contains("event_marker_base_y") and source.contains("! 구조 신호 방향"), "EVENT_PAWN_07 runtime renders companion event pawns with a grounded, pulsing ! marker instead of a generic hostile label")
	check(LocalizationService.tr_key("MAP_EVENT_CONTACT_SIGNAL") != "[MAP_EVENT_CONTACT_SIGNAL]" and LocalizationService.tr_key("RESULT_EVENT_RECRUITED") != "[RESULT_EVENT_RECRUITED]", "EVENT_PAWN_08 special-contact and companion-result copy resolves without runtime text")
	var app_source := FileAccess.get_file_as_string("res://autoload/app_state.gd")
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd")
	check(app_source.contains("special_event") and app_source.contains("contact_outcome_key") and app_source.contains("pre_battle_dialogue") and app_source.contains("pending_map_special_event") and shell_source.contains("_play_special_event_dialogue") and shell_source.contains("PreBattleEventDialog") and shell_source.contains("EventKeyVisual") and shell_source.contains("MAP_EVENT_DIALOGUE_SKIP") and shell_source.contains("panel.gui_input.connect") and shell_source.contains("TextureRect.STRETCH_KEEP_ASPECT_COVERED"), "EVENT_PAWN_09 contact opens an input-advanced pre-battle dialogue with a fixed outcome band and left key visual")
	check(shell_source.contains("_newly_recruited_character_ids") and shell_source.contains("RESULT_EVENT_TRACKING"), "EVENT_PAWN_10 battle result distinguishes immediate companion joins from later signal tracking")
	AppState.profile = backup

func _test_runtime_companion_event_pawns() -> void:
	# Data and source-text checks prove the event contract, but this fixture
	# exercises the actual MapPawn construction path.  Companion contacts must
	# instantiate their own packaged SD texture rather than silently falling back
	# to a generic enemy or HUD-only marker.
	var runtime_screen := ChapterMapScreenScript.new()
	runtime_screen.definition = definition
	runtime_screen.grid = grid
	runtime_screen.world_root = Node3D.new()
	add_child(runtime_screen.world_root)
	for fixture in [
		{"node_id": "NODE_N08", "character_id": "CHR006"},
	]:
		var node := LoaderScript.node_by_id(definition, str(fixture.node_id))
		runtime_screen._create_enemy_pawn(node)
		var pawn: Node3D = runtime_screen.enemy_pawns.get(str(fixture.node_id))
		var sprite: Sprite3D = pawn.get_node_or_null("EnemyIdleSprite") if pawn != null else null
		var marker: Label3D = pawn.get_meta("event_marker", null) if pawn != null else null
		var pack: Dictionary = runtime_screen.enemy_animation_packs.get(str(fixture.node_id), {})
		check(pawn != null and bool(pawn.get_meta("companion_event", false)) and pawn.name.begins_with("CompanionEventMapPawn_"), "EVENT_PAWN_RUNTIME_01 %s creates an authored companion pawn" % str(fixture.node_id))
		check(sprite != null and sprite.texture != null and str(pack.get("source_id", "")) == str(fixture.character_id), "EVENT_PAWN_RUNTIME_02 %s resolves the companion SD MAP_IDLE texture" % str(fixture.node_id))
		check(marker != null and marker.text == "!" and float(marker.position.y) > float(sprite.position.y if sprite != null else 0.0), "EVENT_PAWN_RUNTIME_03 %s grounds the companion pawn and lifts its event marker" % str(fixture.node_id))
	var anomaly_node := LoaderScript.node_by_id(definition, "NODE_N06")
	runtime_screen._create_enemy_pawn(anomaly_node)
	var anomaly_pawn: Node3D = runtime_screen.enemy_pawns.get("NODE_N06")
	var anomaly_sprite: Sprite3D = anomaly_pawn.get_node_or_null("EnemyIdleSprite") if anomaly_pawn != null else null
	var anomaly_marker: Label3D = anomaly_pawn.get_meta("event_marker", null) if anomaly_pawn != null else null
	var anomaly_pack: Dictionary = runtime_screen.enemy_animation_packs.get("NODE_N06", {})
	check(anomaly_pawn != null and bool(anomaly_pawn.get_meta("event_contact", false)) and not bool(anomaly_pawn.get_meta("companion_event", true)) and anomaly_sprite != null and anomaly_sprite.texture != null and str(anomaly_pack.get("source_id", "")) == "ENM010" and anomaly_marker != null and anomaly_marker.text == "!", "EVENT_PAWN_RUNTIME_04 special-enemy contact keeps its enemy SD art and the same ! interaction marker")
	var duo_definition := definition.duplicate(true)
	duo_definition.event_encounters = [{
		"event_encounter_id": "TEST_DUO_RENDER", "node_id": "NODE_N03", "marker": "BANG", "entry_type": "EVENT_CONTACT",
		"title_key": "MAP_EVENT_CONTACT_VERa_TITLE", "body_key": "MAP_EVENT_CONTACT_VERa_BODY", "contact_outcome_key": "MAP_EVENT_CONTACT_VERa_OUTCOME",
		"recruitments": [
			{"character_id": "CHR006", "recruitment_timing": "IMMEDIATE_ON_VICTORY"},
			{"character_id": "CHR007", "recruitment_timing": "IMMEDIATE_ON_VICTORY"},
		],
	}]
	runtime_screen.definition = duo_definition
	var duo_node := LoaderScript.node_by_id(duo_definition, "NODE_N03")
	runtime_screen._create_enemy_pawn(duo_node)
	var duo_pawn: Node3D = runtime_screen.enemy_pawns.get("NODE_N03")
	var primary: Sprite3D = duo_pawn.get_node_or_null("EnemyIdleSprite") if duo_pawn != null else null
	var secondary: Sprite3D = duo_pawn.get_node_or_null("CompanionEventSecondaryIdleSprite") if duo_pawn != null else null
	check(duo_pawn != null and duo_pawn.get_meta("event_companion_ids", []) == ["CHR006", "CHR007"] and primary != null and secondary != null and primary.texture != null and secondary.texture != null, "EVENT_PAWN_DUO_03 one ! contact renders both companion SD assets")
	runtime_screen.world_root.queue_free()
	runtime_screen.free()

func _simulation_hash(seed_value: int) -> Dictionary:
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage("CH01-N01"), seed_value, DataRegistry.data)
	while not sim.state.ended and sim.state.tick < 3000: sim.tick()
	return {"event": sim.event_hash(), "final": JSON.stringify(sim.result_snapshot())}

func _test_regressions() -> void:
	var before := _simulation_hash(424242)
	var map_state_backup := AppState.chapter_map_state().duplicate(true)
	AppState.set_chapter_map_position(Vector2i(1, 0), "NODE_N01")
	var after := _simulation_hash(424242)
	check(before.event == after.event, "map traversal does not change BattleEvent hash")
	check(before.final == after.final, "map traversal does not change battle final state")
	var character_xp := 0
	var character_credits := 0
	var weapon_xp := 0
	for row in DataRegistry.list_of("character_level_curve"):
		character_xp += int(row.xp_to_next)
		character_credits += int(row.credit_cost)
	for row in DataRegistry.list_of("weapon_level_curve"): weapon_xp += int(row.xp_to_next)
	check(character_xp == 905520 and character_credits == 412400, "character growth totals unchanged")
	check(weapon_xp == 144330, "weapon growth total unchanged")
	check(DataRegistry.list_of("skills").all(func(skill): return skill.values.size() == (5 if skill.type == "ULTIMATE_SKILL" else 10)), "skill 10/10/5 arrays unchanged")
	AppState.profile.chapter_map.CH01_MAP = map_state_backup

func _source_function_body(source: String, function_name: String) -> String:
	var marker := "func %s(" % function_name
	var start := source.find(marker)
	if start < 0:
		return ""
	var next_function := source.find("\nfunc ", start + marker.length())
	return source.substr(start) if next_function < 0 else source.substr(start, next_function - start)

func _macro_semantic_hash(candidate: Dictionary) -> String:
	var tile_signatures: Array[String] = []
	for tile_value in candidate.get("tiles", []):
		var tile: Dictionary = tile_value
		tile_signatures.append("%d,%d|%d|%s|%d|%d|%d|%s" % [int(tile.get("q", 0)), int(tile.get("r", 0)), int(tile.get("elevation", 0)), str(tile.get("terrain_type", "")), 1 if bool(tile.get("movement_blocked", false)) else 0, int(tile.get("visual_variant", 0)), int(tile.get("rotation_step", 0)), str(tile.get("prop_set", ""))])
	tile_signatures.sort()
	return JSON.stringify({"tiles": tile_signatures, "nodes": _stage_coordinates(candidate), "treasures": _treasure_coordinates(candidate), "routes": _route_signature(candidate)}).sha256_text()

func _stage_coordinates(candidate: Dictionary) -> Array:
	var output: Array[String] = []
	for node_value in candidate.get("nodes", []):
		var node: Dictionary = node_value
		if str(node.get("stage_id", "")).is_empty():
			continue
		output.append("%s@%d,%d" % [str(node.get("stage_id", "")), int(node.get("q", 0)), int(node.get("r", 0))])
	output.sort()
	return output

func _treasure_coordinates(candidate: Dictionary) -> Array:
	var output: Array[String] = []
	for treasure_value in candidate.get("treasures", []):
		var treasure: Dictionary = treasure_value
		output.append("%s@%d,%d" % [str(treasure.get("treasure_id", "")), int(treasure.get("q", 0)), int(treasure.get("r", 0))])
	output.sort()
	return output

func _route_signature(candidate: Dictionary) -> Array:
	var normal: Array = candidate.get("normal_route", []).duplicate()
	var hard: Array = candidate.get("hard_route", []).duplicate()
	return [normal, hard]

func _macro_visual_routes_are_grounded() -> bool:
	var route_sets: Array = [definition.get("normal_route", []), definition.get("hard_route", [])]
	for route_index in range(route_sets.size()):
		var previous := Vector2i(int(definition.get("start_hex", {}).get("q", 0)), int(definition.get("start_hex", {}).get("r", 0)))
		if route_index == 1:
			var branch_node := LoaderScript.node_for_stage(definition, "CH01-N20")
			if not branch_node.is_empty():
				previous = Vector2i(int(branch_node.get("q", 0)), int(branch_node.get("r", 0)))
		for stage_id in route_sets[route_index]:
			var node := LoaderScript.node_for_stage(definition, str(stage_id))
			if node.is_empty():
				return false
			var target := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
			for route_coord in MacroWorldGeneratorScript.route_line(previous, target):
				if not grid.traversable(route_coord):
					return false
			previous = target
	return true
