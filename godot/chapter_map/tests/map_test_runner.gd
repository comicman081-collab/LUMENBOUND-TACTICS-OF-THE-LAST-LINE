extends Node

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const HexGridScript := preload("res://chapter_map/model/hex_grid.gd")
const HexPathfinderScript := preload("res://chapter_map/model/hex_pathfinder.gd")
const LoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const ProgressScript := preload("res://chapter_map/model/chapter_map_progress.gd")
const ExplorationScript := preload("res://chapter_map/model/map_exploration_service.gd")
const GrowthAnalyzerScript := preload("res://progression/growth_affordability_analyzer.gd")

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
	print("R13 SRPG MAP TESTS | Godot ", Engine.get_version_info().get("string", "unknown"))
	definition = LoaderScript.load_map("CH01_MAP")
	grid = HexGridScript.new()
	grid.load_tiles(definition.get("tiles", []))
	_test_data()
	_test_coordinates()
	_test_paths()
	_test_unlock_and_progress()
	_test_save_and_migration()
	_test_transactions_and_roundtrip()
	_test_encounters_and_treasures()
	_test_reward_affordability()
	_test_regressions()
	print("MAP_TEST_SUMMARY total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	if not failures.is_empty(): print("FAILURES=", JSON.stringify(failures))
	get_tree().quit(0 if failed == 0 else 1)

func _test_data() -> void:
	check(not definition.is_empty(), "CH01 map JSON parses")
	check(LoaderScript.validate(definition).is_empty(), "map data schema and references validate", " | ".join(LoaderScript.validate(definition)))
	var node_ids: Dictionary = {}
	for node in definition.nodes: node_ids[str(node.node_id)] = true
	check(node_ids.size() == definition.nodes.size(), "all map node IDs unique")
	var normal: Array = definition.nodes.filter(func(node): return str(node.node_type).begins_with("NORMAL_"))
	var hard: Array = definition.nodes.filter(func(node): return str(node.node_type).begins_with("HARD_"))
	check(normal.size() == 10, "map has exactly 10 NORMAL battle nodes")
	check(hard.size() == 5, "map has exactly 5 HARD battle nodes")
	check(definition.nodes.filter(func(node): return str(node.get("stage_id", "")) != "").all(func(node): return not DataRegistry.stage(str(node.stage_id)).is_empty()), "all battle nodes reference valid stages")
	check(definition.nodes.all(func(node): return grid.has(Vector2i(int(node.q), int(node.r)))), "all nodes occupy valid tiles")
	check(definition.nodes.all(func(node): return grid.traversable(Vector2i(int(node.q), int(node.r)))), "no node collides with blocked terrain")
	check(definition.tiles.any(func(tile): return bool(tile.movement_blocked)), "map includes blocked deep-water terrain")
	check(bool(definition.get("macro_generated", false)) and int(definition.get("macro_world", {}).get("linear_scale_viewports", 0)) >= 10, "map uses ten-plus-viewport deterministic macro layout")
	var n01 := LoaderScript.node_for_stage(definition, "CH01-N01")
	var n10 := LoaderScript.node_for_stage(definition, "CH01-N10")
	check(HexCoordScript.distance(Vector2i.ZERO, Vector2i(int(n10.q), int(n10.r))) >= 90, "NORMAL route spans ten-plus local map lengths")
	check(LoaderScript.load_map("CH01_MAP").get("tiles", []) == definition.get("tiles", []), "macro terrain seed is deterministic across loads")
	var visible_treasures: Array = definition.get("treasures", []).filter(func(treasure): return str(treasure.get("visibility", "")) == "VISIBLE")
	var hidden_treasures: Array = definition.get("treasures", []).filter(func(treasure): return str(treasure.get("visibility", "")) == "HIDDEN")
	check(visible_treasures.size() >= 6 and hidden_treasures.size() >= 4, "side branches include visible and hidden treasure targets")
	check(definition.get("treasures", []).all(func(treasure): return grid.traversable(Vector2i(int(treasure.q), int(treasure.r)))), "all treasure targets occupy traversable tiles")
	check(definition.nodes.filter(func(node): return str(node.get("stage_id", "")) != "").all(func(node): return DataRegistry.stage(str(node.stage_id)).get("waves", []).all(func(wave): return wave.all(func(enemy_id): return not DataRegistry.enemy(str(enemy_id)).is_empty()))), "all encounter nodes resolve actual enemy definitions")

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

func _test_unlock_and_progress() -> void:
	var backup := AppState.profile.duplicate(true)
	AppState.new_game()
	check(AppState.is_stage_unlocked("CH01-N01"), "N01 initially unlocked")
	check(not AppState.is_stage_unlocked("CH01-N02"), "N02 initially locked")
	check(not AppState.is_stage_unlocked("CH01-H01"), "HARD gate initially locked")
	for number in range(1, 11): AppState.record_stage_clear("CH01-N%02d" % number, 3)
	check(AppState.is_stage_unlocked("CH01-H01"), "N10 clear opens HARD gate")
	check(not AppState.is_stage_unlocked("CH01-H02"), "H02 waits for H01")
	AppState.record_stage_clear("CH01-H01", 2)
	check(AppState.is_stage_unlocked("CH01-H02"), "H01 clear unlocks H02 exactly")
	var state := AppState.chapter_map_state()
	var h01 := LoaderScript.node_for_stage(definition, "CH01-H01")
	check(state.revealed_tiles.has("%d,%d" % [int(h01.q), int(h01.r)]), "HARD route reveal follows N10 clear")
	var fresh := ProgressScript.create_default(definition)
	var before: int = fresh.revealed_tiles.size()
	ProgressScript.refresh_reveal(fresh, definition, 1, 0, false)
	check(fresh.revealed_tiles.size() >= before and fresh.revealed_tiles.has("2,0"), "victory reveals next NORMAL region")
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
	AppState.profile = saved_profile

func _test_transactions_and_roundtrip() -> void:
	var backup := AppState.profile.duplicate(true)
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
	var inventory_before: Dictionary = AppState.profile.inventory.duplicate(true)
	var stamina_fast := int(AppState.profile.account.stamina)
	AppState.set_chapter_map_position(Vector2i(1, 0), "NODE_N01")
	check(AppState.profile.inventory == inventory_before and int(AppState.profile.account.stamina) == stamina_fast, "fast-travel position update grants no reward and costs no stamina")
	check(str(LoaderScript.node_for_stage(definition, "CH01-N01").node_id) == "NODE_N01", "map to battle stage ID adapter stable")
	check(str(LoaderScript.node_by_id(definition, "NODE_N01").stage_id) == "CH01-N01", "battle to map node ID adapter stable")
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
