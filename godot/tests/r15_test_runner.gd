extends Node

## R15 keeps its assertions separate from the historical baseline suite.  These
## checks assert the Chapter 1-2 content-completion contract against the
## runtime assets actually packaged for Web rather than editor-only sources.

const ANIMATIONS := ["idle", "move", "basic_attack", "normal_skill", "ultimate", "hit", "down", "victory"]
const EXPECTED_FRAMES := {"idle": 8, "move": 12, "basic_attack": 8, "normal_skill": 12, "ultimate": 18, "hit": 4, "down": 8, "victory": 10}
const GrowthPlanBuilderScript := preload("res://progression/growth_plan_builder.gd")
const AppShellScript := preload("res://screens/app_shell.gd")

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
		failures.append(name + (": " + details if details != "" else ""))
		printerr("FAIL | ", name, " | ", details)

func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _run() -> void:
	print("LANTERNLINE R15 CONTENT TESTS | Godot ", Engine.get_version_info().get("string", "unknown"))
	_test_content_counts()
	_test_runtime_combat_assets()
	_test_runtime_projectiles_and_vfx()
	_test_stage_content()
	_test_map_bindings()
	_test_scenario_content()
	_test_story_progression_triggers()
	_test_result_refresh_boundaries()
	_test_full_chapter_transaction_route()
	_test_growth_material_planner_edges()
	_test_growth_recommended_batch()
	print("R15_TEST_SUMMARY total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	if not failures.is_empty(): print("R15_FAILURES=", JSON.stringify(failures))
	get_tree().quit(0 if failed == 0 else 1)

func _test_content_counts() -> void:
	check(DataRegistry.list_of("characters").size() == 44, "CONTENT_01 44 player definitions")
	var enemies := DataRegistry.list_of("enemies")
	var normals := enemies.filter(func(value): return str(value.get("rank", "")) == "NORMAL")
	var elites := enemies.filter(func(value): return str(value.get("rank", "")) == "ELITE")
	var bosses := enemies.filter(func(value): return str(value.get("rank", "")) == "BOSS")
	check(normals.size() == 12 and elites.size() == 3 and bosses.size() == 5, "CONTENT_02 12 normal, three elite, five non-reused boss definitions")
	var contact_recruits: Dictionary = {}
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var definition := ChapterMapLoader.load_map(str(chapter.get("map_id", "")))
		for event_value in definition.get("event_encounters", []):
			var event: Dictionary = event_value
			for recruitment_value in event.get("recruitments", []):
				contact_recruits[str((recruitment_value as Dictionary).get("character_id", ""))] = true
	var acquisition_valid := true
	for character_value in DataRegistry.list_of("characters"):
		var character: Dictionary = character_value
		var character_id := str(character.get("id", ""))
		if int(character_id.trim_prefix("CHR")) >= 9:
			acquisition_valid = acquisition_valid and str(character.get("acquisition_source", "")) == "EVENT_CONTACT" and contact_recruits.has(character_id)
	check(acquisition_valid, "CONTENT_02A every expansion companion declares the same EVENT_CONTACT acquisition authority as its map recruitment")

func _entity_ids() -> Array:
	var ids: Array[String] = []
	for row_value in DataRegistry.list_of("characters") + DataRegistry.list_of("enemies"):
		ids.append(str((row_value as Dictionary).get("id", "")))
	return ids

func _test_runtime_combat_assets() -> void:
	var library := BattleSpriteLibrary.new()
	check(library.load_pack() and library.load_error == "", "CONTENT_03 runtime combat animation libraries load", library.load_error)
	var all_entities_valid := true
	for entity_id in _entity_ids():
		all_entities_valid = all_entities_valid and library.supports_character(entity_id)
		for animation_name in ANIMATIONS:
			all_entities_valid = all_entities_valid and library.has_animation(entity_id, animation_name)
			all_entities_valid = all_entities_valid and library.texture_at(entity_id, animation_name, 0.0) != null
			var manifest: Dictionary = library.manifests.get(entity_id, {})
			var indices: Array = manifest.get("animations", {}).get(animation_name, {}).get("frame_indices", [])
			all_entities_valid = all_entities_valid and indices.size() == int(EXPECTED_FRAMES[animation_name])
	check(all_entities_valid and _entity_ids().size() == 64, "CONTENT_04 all 44 players and 20 enemies resolve 80-frame combat packs")
	var runtime_manifest := _json("res://assets/runtime_web/runtime_combat_manifest.json")
	var static_fallback := false
	for entry_value in runtime_manifest.get("combat", []):
		var entry: Dictionary = entry_value
		static_fallback = static_fallback or str(entry.get("status", "")) == "RUNTIME_CARD_STATIC_PRESENTATION"
	check(not static_fallback, "CONTENT_05 runtime combat manifest contains no static-card battle fallback")

func _test_runtime_projectiles_and_vfx() -> void:
	var projectile_library := ProjectileSpriteLibrary.new()
	check(projectile_library.load_pack() and projectile_library.load_error == "", "CONTENT_06 all runtime projectile libraries load", projectile_library.load_error)
	var projectiles_valid := true
	for entity_id in _entity_ids():
		projectiles_valid = projectiles_valid and projectile_library.supports_source(entity_id)
		projectiles_valid = projectiles_valid and projectile_library.texture_at(entity_id, 0.0) != null
		projectiles_valid = projectiles_valid and int(projectile_library.manifests.get(entity_id, {}).get("frames", 0)) == 8
	check(projectiles_valid, "CONTENT_07 64 entity-specific animated projectile packs resolve")
	var manifest := _json("res://assets/runtime_web/runtime_combat_manifest.json")
	var vfx_by_source: Dictionary = {}
	var vfx_files_valid := true
	for entry_value in manifest.get("vfx", []):
		var entry: Dictionary = entry_value
		var folder := str(entry.get("folder", ""))
		var tokens := folder.split("_")
		var source_id := str(tokens[1]).to_upper() if tokens.size() >= 3 else ""
		var kind := str(tokens[2]) if tokens.size() >= 3 else ""
		if not vfx_by_source.has(source_id): vfx_by_source[source_id] = []
		vfx_by_source[source_id].append(kind)
		# Atlas PNGs can be read directly during the same incremental-sync run,
		# before an editor import cache exists, so assert the packaged source path.
		vfx_files_valid = vfx_files_valid and FileAccess.file_exists("res://assets/runtime_web/" + str(entry.get("path", "")))
	var vfx_coverage := true
	var signature_metadata_valid := true
	for entity_id in _entity_ids():
		var kinds: Array = vfx_by_source.get(entity_id, [])
		for kind in ["basic", "normal", "ultimate"]: vfx_coverage = vfx_coverage and kinds.has(kind)
		var ultimate_manifest := _json("res://assets/runtime_web/vfx/vfx_%s_ultimate/vfx_manifest.json" % entity_id.to_lower())
		signature_metadata_valid = signature_metadata_valid and str(ultimate_manifest.get("layer", "")) == "SIGNATURE" and not str(ultimate_manifest.get("motion_shape", "")).is_empty() and not str(ultimate_manifest.get("primary", "")).is_empty() and not str(ultimate_manifest.get("secondary", "")).is_empty()
	check(vfx_coverage and vfx_files_valid, "CONTENT_08 every player and enemy has basic, normal, and ultimate runtime VFX")
	var battle_source := FileAccess.get_file_as_string("res://battle/view/battle_view.gd")
	var shared_base_valid := FileAccess.file_exists("res://assets/runtime_web/vfx/vfx_base_signal_breaker_ultimate/atlas.png") and battle_source.contains("VFX_UNIT_PROFILES") and battle_source.contains("SIGNAL_BREAKER_ULTIMATE_BASE_KEY") and battle_source.contains("_draw_vfx_signature_accent")
	check(signature_metadata_valid and shared_base_valid, "CONTENT_09 all 64 VFX signatures have profiled colour/motion metadata over the shared original ultimate base")
	var boss_motion_grammar_valid := true
	for grammar in ["implode", "resonance", "lockon", "gate_reverse", "network"]:
		boss_motion_grammar_valid = boss_motion_grammar_valid and battle_source.contains("\"ultimate\": \"%s\"" % grammar) and battle_source.contains("\t\t\"%s\":" % grammar)
	check(boss_motion_grammar_valid, "CONTENT_10 five bosses have non-reused ultimate motion grammars")

func _test_stage_content() -> void:
	var normal_stages := DataRegistry.list_of("stages").filter(func(stage): return str(stage.get("mode", "")) == "NORMAL")
	var hard_stages := DataRegistry.list_of("stages").filter(func(stage): return str(stage.get("mode", "")) == "HARD")
	var chapter_stage_counts_valid := normal_stages.size() == 40 and hard_stages.size() == 20
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var chapter_id := str(chapter.get("id", ""))
		chapter_stage_counts_valid = chapter_stage_counts_valid and normal_stages.filter(func(stage): return str(stage.get("chapter_id", "")) == chapter_id).size() == 20 and hard_stages.filter(func(stage): return str(stage.get("chapter_id", "")) == chapter_id).size() == 10
	check(chapter_stage_counts_valid, "STAGE_01 both chapters have exact NORMAL 20 / HARD 10 (30 battles each)")
	var rosters_valid := true
	var every_stage_has_waves := true
	for stage in DataRegistry.list_of("stages"):
		var waves: Array = stage.get("waves", [])
		every_stage_has_waves = every_stage_has_waves and not waves.is_empty()
		for wave_value in waves:
			var wave: Array = wave_value
			for enemy_id in wave:
				rosters_valid = rosters_valid and not DataRegistry.enemy(str(enemy_id)).is_empty()
	check(every_stage_has_waves and rosters_valid, "STAGE_02 all sixty stages reference valid populated enemy rosters")
	var expected_boss_stages := {"BOSS001": "CH01-N20", "BOSS002": "CH01-H10", "BOSS003": "CH01-H03", "BOSS004": "CH02-N20", "BOSS005": "CH02-H10"}
	var boss_placement_valid := true
	var boss_counts: Dictionary = {}
	for stage_value in DataRegistry.list_of("stages"):
		var boss_stage: Dictionary = stage_value
		for wave_value in boss_stage.get("waves", []):
			for enemy_id_value in wave_value:
				var enemy_id := str(enemy_id_value)
				if expected_boss_stages.has(enemy_id):
					boss_counts[enemy_id] = int(boss_counts.get(enemy_id, 0)) + 1
					boss_placement_valid = boss_placement_valid and str(boss_stage.get("id", "")) == str(expected_boss_stages[enemy_id])
	for boss_id in expected_boss_stages:
		boss_placement_valid = boss_placement_valid and int(boss_counts.get(boss_id, 0)) == 1
	check(boss_placement_valid, "STAGE_03 five bosses are each placed once at their unique expanded finale operation")
	var ch01_new_normals_integrated := true
	for enemy_id in ["ENM010", "ENM011", "ENM012"]:
		var found := false
		for stage_value in DataRegistry.list_of("stages"):
			var stage: Dictionary = stage_value
			if str(stage.get("chapter_id", "")) != "CH01": continue
			for wave_value in stage.get("waves", []):
				if (wave_value as Array).has(enemy_id): found = true
		ch01_new_normals_integrated = ch01_new_normals_integrated and found
	var boss_pattern_signatures: Dictionary = {}
	var boss_patterns_unique := true
	for boss_id in ["BOSS001", "BOSS002", "BOSS003", "BOSS004", "BOSS005"]:
		var signature := JSON.stringify(DataRegistry.enemy(boss_id).get("patterns", []))
		boss_patterns_unique = boss_patterns_unique and not signature.is_empty() and not boss_pattern_signatures.has(signature)
		boss_pattern_signatures[signature] = true
	var h03 := DataRegistry.stage("CH01-H03")
	check(ch01_new_normals_integrated and boss_patterns_unique and bool(h03.get("boss", false)), "STAGE_04 CH01 new normal archetypes are playable and every boss has unique patterns with H03 boss metadata")

func _test_map_bindings() -> void:
	var maps_valid := true
	var map_stage_ids: Dictionary = {}
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var definition := ChapterMapLoader.load_map(str(chapter.get("map_id", "")))
		var errors := ChapterMapLoader.validate(definition)
		maps_valid = maps_valid and not definition.is_empty() and errors.is_empty()
		var normal_nodes := 0
		var hard_nodes := 0
		for node_value in definition.get("nodes", []):
			var node: Dictionary = node_value
			var type := str(node.get("node_type", ""))
			var stage_id := str(node.get("stage_id", ""))
			if type.begins_with("NORMAL_"):
				normal_nodes += 1
				map_stage_ids[stage_id] = true
			elif type.begins_with("HARD_"):
				hard_nodes += 1
				map_stage_ids[stage_id] = true
		var companion_events := 0
		var special_enemy_events := 0
		var event_dialogue_valid := true
		for event_value in definition.get("event_encounters", []):
			var event: Dictionary = event_value
			var event_kind := str(event.get("event_kind", ""))
			companion_events += 1 if event_kind == "COMPANION" else 0
			special_enemy_events += 1 if event_kind == "SPECIAL_ENEMY" else 0
			var pages: Array = event.get("pre_battle_dialogue", [])
			event_dialogue_valid = event_dialogue_valid and pages.size() >= 2 and pages.size() <= 4
			for page_value in pages:
				var page: Dictionary = page_value if page_value is Dictionary else {}
				event_dialogue_valid = event_dialogue_valid and str(page.get("speaker_kind", "")) in ["COMMAND", "COMPANION", "ENEMY"] and not str(page.get("text_key", "")).is_empty()
			if event_kind == "SPECIAL_ENEMY":
				event_dialogue_valid = event_dialogue_valid and not DataRegistry.enemy(str(event.get("enemy_id", ""))).is_empty() and event.get("recruitments", []).is_empty()
		maps_valid = maps_valid and normal_nodes == 20 and hard_nodes == 10 and companion_events == 15 and special_enemy_events == 4 and event_dialogue_valid
	check(maps_valid, "MAP_01 both maps validate with 30 battle nodes and 15 companion / 4 special-enemy pre-battle events")
	var all_stage_bindings := true
	for stage in DataRegistry.list_of("stages"): all_stage_bindings = all_stage_bindings and map_stage_ids.has(str(stage.id))
	check(all_stage_bindings and map_stage_ids.size() == 60, "MAP_02 all sixty stage IDs bind once to chapter map encounter nodes")
	var expected_node_scenarios: Dictionary = {}
	var expected_start_scenarios: Dictionary = {}
	for trigger_value in DataRegistry.list_of("chapter_story_triggers"):
		var trigger: Dictionary = trigger_value
		if str(trigger.get("event", "")) == "STAGE_CLEAR":
			expected_node_scenarios[str(trigger.get("stage_id", ""))] = str(trigger.get("scenario_id", ""))
		elif str(trigger.get("event", "")) == "MAP_ENTER":
			var chapter_id := str(trigger.get("id", "")).split("_")[1]
			expected_start_scenarios[chapter_id] = str(trigger.get("scenario_id", ""))
	var scenario_audit_valid := true
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var definition := ChapterMapLoader.load_map(str(chapter.get("map_id", "")))
		for node_value in definition.get("nodes", []):
			var node: Dictionary = node_value
			var expected_scenario_id: String = str(expected_start_scenarios.get(str(chapter.get("id", "")), "") if str(node.get("node_type", "")) == "START" else expected_node_scenarios.get(str(node.get("stage_id", "")), ""))
			scenario_audit_valid = scenario_audit_valid and str(node.get("scenario_id", "")) == str(expected_scenario_id)
	check(scenario_audit_valid, "MAP_03 map nodes expose the exact runtime story-trigger scenario IDs for content audit")

func _test_scenario_content() -> void:
	var scenarios := DataRegistry.list_of("scenarios")
	var commands_valid := scenarios.size() == 15
	var visual_contract_valid := true
	var portrait_ids: Dictionary = {}
	var background_ids: Dictionary = {}
	for scenario in scenarios:
		commands_valid = commands_valid and not scenario.get("commands", []).is_empty()
		var has_background := false
		var has_portrait := false
		var has_expression_change := false
		for command_value in scenario.get("commands", []):
			var command: Dictionary = command_value
			var type := str(command.get("command", ""))
			if type == "set_background" or type == "set_cg":
				var background_id := str(command.get("asset_id", ""))
				var background_path := AssetRegistry.resolve(background_id)
				has_background = has_background or not background_id.is_empty()
				background_ids[background_id] = true
				visual_contract_valid = visual_contract_valid and not background_path.is_empty() and ResourceLoader.exists(background_path)
			elif type == "show_portrait":
				var portrait_id := str(command.get("asset_id", ""))
				var portrait_path := AssetRegistry.resolve(portrait_id)
				has_portrait = has_portrait or not portrait_id.is_empty()
				portrait_ids[portrait_id] = true
				visual_contract_valid = visual_contract_valid and not str(command.get("expression", "")).is_empty() and not portrait_path.is_empty() and ResourceLoader.exists(portrait_path)
			elif type == "set_expression":
				has_expression_change = has_expression_change or not str(command.get("expression", "")).is_empty()
		visual_contract_valid = visual_contract_valid and has_background and has_portrait and has_expression_change
	check(commands_valid, "STORY_01 all 15 compiled scenarios have executable command lists")
	check(visual_contract_valid and portrait_ids.size() >= 4 and background_ids.size() >= 4, "STORY_04 all 15 scenarios resolve authored portrait, expression-state and background/CG presentation")
	var iri_story: Dictionary = DataRegistry.by_id("scenarios", "SCN_REL_IRI")
	var iri_portraits: Array = iri_story.get("commands", []).filter(func(command): return str(command.get("command", "")) == "show_portrait")
	var iri_speakers: Array = iri_story.get("commands", []).filter(func(command): return str(command.get("speaker_key", "")) == "SPEAKER_IRI")
	check(iri_portraits.size() == 1 and str(iri_portraits[0].get("asset_id", "")) == "portrait_chr008_dev" and iri_speakers.size() >= 1, "STORY_05 Iri relationship story uses CHR008 portrait and localized Iri speaker identity")
	var preboss: Dictionary = DataRegistry.by_id("scenarios", "SCN_CH01_PREBOSS")
	var starts_battle_from_story: bool = preboss.get("commands", []).any(func(command): return str(command.get("command", "")) == "start_battle")
	check(not starts_battle_from_story, "STORY_06 pre-boss story returns to the map; only the N20 pawn contact starts battle")

func _test_story_progression_triggers() -> void:
	var triggers: Array = DataRegistry.list_of("chapter_story_triggers")
	var ids: Dictionary = {}
	var valid := triggers.size() == 12
	for trigger_value in triggers:
		var trigger: Dictionary = trigger_value
		var trigger_id := str(trigger.get("id", ""))
		valid = valid and not trigger_id.is_empty() and not ids.has(trigger_id)
		valid = valid and not DataRegistry.by_id("scenarios", str(trigger.get("scenario_id", ""))).is_empty()
		ids[trigger_id] = true
	check(valid, "STORY_02 twelve unique data-driven Chapter 1-2 map/stage story triggers resolve")
	AppState.new_game()
	var intro_queued := AppState.queue_story_event("MAP_ENTER")
	var intro := AppState.next_pending_story_trigger()
	AppState.complete_story_trigger_for_scenario(str(intro.get("scenario_id", "")))
	var intro_not_requeued := not AppState.queue_story_event("MAP_ENTER")
	var mid_queued := AppState.queue_story_event("STAGE_CLEAR", "CH01-N03")
	var mid := AppState.next_pending_story_trigger()
	check(intro_queued and str(intro.get("scenario_id", "")) == "SCN_CH01_INTRO" and intro_not_requeued and mid_queued and str(mid.get("scenario_id", "")) == "SCN_CH01_MID_A", "STORY_03 trigger completion persists and stage-clear queues next unread story once")
	AppState.new_game()
	var pre_clear := AppState.profile.duplicate(true)
	AppState.record_stage_clear("CH01-N01", 3)
	var shell := AppShellScript.new()
	var newly_unlocked: Array = shell.call("_newly_unlocked_stage_ids", pre_clear, AppState.profile.duplicate(true))
	shell.free()
	check(newly_unlocked == ["CH01-N02"], "STORY_07 result progression summary reports only the newly unlocked next operation")

func _test_result_refresh_boundaries() -> void:
	# Use the opt-in save sandbox so these crash/reload fixtures never read or
	# overwrite the player's normal user://save_v1.json namespace.
	var backup_profile := AppState.profile.duplicate(true)
	var backup_token := AppState.pending_battle_token
	var backup_stage := AppState.selected_stage_id
	var backup_sandbox := SaveService.soak_sandbox_enabled
	var backup_sandbox_session := SaveService.soak_sandbox_session
	var backup_screen := SceneRouter.current_screen
	var backup_history := SceneRouter.history.duplicate()
	var developer_mode_before := bool(SettingsService.values.developer_mode)
	# Entry/reload boundaries assert normal-player stamina semantics even though
	# the headless runner itself is a debug build with developer tools enabled.
	SettingsService.values.developer_mode = false
	SaveService.soak_sandbox_enabled = true
	SaveService.soak_sandbox_session = "r15_result_refresh_audit"
	SaveService.reset_save_files()
	AppState.new_game()

	# A view callback is not a commit authority. Without a live entry token even
	# a prepared encounter plus syntactically valid victory result must leave every
	# persistent field alone, including the hostile-pawn lifecycle.
	var definition := ChapterMapLoader.load_map("CH01_MAP")
	AppState.selected_stage_id = "CH01-N01"
	var tokenless_n01: Dictionary = ChapterMapLoader.node_for_stage(definition, "CH01-N01")
	var tokenless_return: Dictionary = definition.get("start_hex", {"q": 0, "r": 0})
	AppState.prepare_map_encounter("CH01-N01", str(tokenless_n01.get("node_id", "")), Vector2i(int(tokenless_return.get("q", 0)), int(tokenless_return.get("r", 0))))
	var tokenless_before := _persistent_profile(AppState.profile)
	var tokenless_shell := AppShellScript.new()
	tokenless_shell.call("_battle_finished", {"victory": true, "survivors": 5, "time": 10.0, "ticks": 300, "damage": {}, "healing": {}})
	var tokenless_after := _persistent_profile(AppState.profile)
	check(JSON.stringify(_canonical(tokenless_before)) == JSON.stringify(_canonical(tokenless_after)) and not bool(AppState.profile.first_clear.get("CH01-N01", false)), "RESULT_TXN_01 tokenless or stale victory callback cannot mutate canonical progression", JSON.stringify({"changed_profile_keys": _changed_dictionary_keys(tokenless_before, tokenless_after), "first_clear": AppState.profile.first_clear.get("CH01-N01", false), "pending_token": AppState.pending_battle_token}))
	tokenless_shell.free()
	SaveService.reset_save_files()

	# Build the exact N03 map-contact transaction. The battle result commits one
	# reward, first-clear/map state, and its mandatory story before the atomic save.
	AppState.profile.chapter_progress.CH01.normal_highest = 2
	for stage_id in ["CH01-N01", "CH01-N02"]:
		AppState.profile.first_clear[stage_id] = true
		AppState.profile.stage_stars[stage_id] = 3
	AppState.selected_stage_id = "CH01-N03"
	AppState.refresh_chapter_map_reveal()
	var n02: Dictionary = ChapterMapLoader.node_for_stage(definition, "CH01-N02")
	var n03: Dictionary = ChapterMapLoader.node_for_stage(definition, "CH01-N03")
	var n02_coord := Vector2i(int(n02.get("q", 0)), int(n02.get("r", 0)))
	AppState.set_chapter_map_position(n02_coord, str(n02.get("node_id", "")))
	check(AppState.prepare_map_encounter("CH01-N03", str(n03.get("node_id", "")), n02_coord), "RESULT_TXN_02 N03 map contact prepares exactly one pending encounter")
	check(AppState.begin_battle_transaction("CH01-N03"), "RESULT_TXN_03 N03 owns exactly one battle entry token")
	var commit_token := AppState.pending_battle_token
	var inventory_before: Dictionary = AppState.profile.inventory.duplicate(true)
	var commit_shell := AppShellScript.new()
	commit_shell.call("_battle_finished", {"victory": true, "survivors": 5, "time": 20.0, "ticks": 600, "damage": {}, "healing": {}})
	var committed_profile := _persistent_profile(AppState.profile)
	var committed_inventory: Dictionary = AppState.profile.inventory.duplicate(true)
	var committed_reveal: Dictionary = AppState.chapter_map_state().get("pending_reveal", {}).duplicate(true)
	var commit_contract := bool(AppState.profile.first_clear.get("CH01-N03", false))
	commit_contract = commit_contract and int(AppState.profile.chapter_progress.CH01.normal_highest) == 3
	commit_contract = commit_contract and AppState.chapter_map_state().get("cleared_encounters", []).has(str(n03.get("node_id", "")))
	commit_contract = commit_contract and str(AppState.next_pending_story_trigger().get("scenario_id", "")) == "SCN_CH01_MID_A"
	commit_contract = commit_contract and JSON.stringify(_canonical(inventory_before)) != JSON.stringify(_canonical(committed_inventory))
	check(commit_contract, "RESULT_TXN_04 one committed victory grants reward, first clear, hostile removal and pending story together", JSON.stringify({"first": AppState.profile.first_clear.get("CH01-N03", false), "highest": AppState.profile.chapter_progress.CH01.normal_highest, "cleared": AppState.chapter_map_state().get("cleared_encounters", []), "story": AppState.next_pending_story_trigger(), "rewards": commit_shell.last_rewards, "token": commit_token}))
	check(str(committed_reveal.get("reveal_id", "")) == commit_token, "RESULT_TXN_05 result commit persists one presentation-only map reveal token", JSON.stringify({"token": commit_token, "pending_reveal": committed_reveal, "processed_rewards": AppState.chapter_map_state().get("processed_reward_tokens", [])}))

	AppState.new_game()
	var committed_load := SaveService.load_game()
	var loaded_profile := _persistent_profile(AppState.profile)
	check(committed_load.ok and JSON.stringify(_canonical(loaded_profile)) == JSON.stringify(_canonical(committed_profile)) and str(AppState.next_pending_story_trigger().get("scenario_id", "")) == "SCN_CH01_MID_A", "RESULT_REFRESH_01 save/load preserves the complete commit and pending mandatory story", JSON.stringify({"load_ok": committed_load.ok, "load_error": committed_load.error, "same": JSON.stringify(_canonical(loaded_profile)) == JSON.stringify(_canonical(committed_profile)), "story": AppState.next_pending_story_trigger()}))
	check(AppState.chapter_map_state().get("pending_reveal", {}) == committed_reveal, "RESULT_REFRESH_02 unconsumed map reveal survives reload without recreation")

	# Re-delivery after reload has no runtime token. It must not grant items,
	# advance first-clear state, remove another pawn, or enqueue another story.
	var before_duplicate := _persistent_profile(AppState.profile)
	commit_shell.call("_battle_finished", {"victory": true, "survivors": 5, "time": 20.0, "ticks": 600, "damage": {}, "healing": {}})
	var after_duplicate := _persistent_profile(AppState.profile)
	check(JSON.stringify(_canonical(before_duplicate)) == JSON.stringify(_canonical(after_duplicate)) and commit_shell.last_rewards.is_empty(), "RESULT_REFRESH_03 duplicate result callback after reload is a persistent no-op")

	var consumed_reveal := AppState.consume_chapter_map_pending_reveal()
	var consumed_saved := SaveService.save_game()
	AppState.new_game()
	var consumed_loaded := SaveService.load_game()
	check(str(consumed_reveal.get("reveal_id", "")) == commit_token and consumed_saved.ok and consumed_loaded.ok and AppState.consume_chapter_map_pending_reveal().is_empty() and AppState.chapter_map_state().get("reveal_consumed", []).has(commit_token), "RESULT_REFRESH_04 consumed reveal never replays after save/load", JSON.stringify({"token": commit_token, "consumed": consumed_reveal, "save_ok": consumed_saved.ok, "load_ok": consumed_loaded.ok, "pending": AppState.chapter_map_state().get("pending_reveal", {}), "ledger": AppState.chapter_map_state().get("reveal_consumed", [])}))
	commit_shell.free()

	# Real map flow saves prepare_map_encounter before begin_battle_transaction.
	# A mid-battle refresh therefore restores the pre-contact snapshot: no spent
	# entry, no reward, no clear, and the hostile remains available to retry.
	SaveService.reset_save_files()
	var start: Dictionary = definition.get("start_hex", {"q": 0, "r": 0})
	var start_coord := Vector2i(int(start.get("q", 0)), int(start.get("r", 0)))
	var n01: Dictionary = ChapterMapLoader.node_for_stage(definition, "CH01-N01")
	var n01_coord := Vector2i(int(n01.get("q", 0)), int(n01.get("r", 0)))
	AppState.set_chapter_map_position(n01_coord, str(n01.get("node_id", "")))
	var pre_contact_inventory: Dictionary = AppState.profile.inventory.duplicate(true)
	var pre_contact_stamina := int(AppState.profile.account.stamina)
	# The preceding debug-build reload reapplies the build capability. This
	# assertion deliberately exercises the normal-player transaction instead.
	SettingsService.values.developer_mode = false
	check(AppState.prepare_map_encounter("CH01-N01", str(n01.get("node_id", "")), start_coord) and SaveService.save_game().ok, "MID_BATTLE_REFRESH_01 pre-contact recovery snapshot is atomically saved before entry")
	check(AppState.begin_battle_transaction("CH01-N01") and int(AppState.profile.account.stamina) < pre_contact_stamina, "MID_BATTLE_REFRESH_02 live entry consumes only the unsaved runtime transaction")
	var mid_battle_loaded := SaveService.load_game()
	var recovered_state := AppState.chapter_map_state()
	var hostile_preserved: bool = not recovered_state.get("cleared_encounters", []).has(str(n01.get("node_id", ""))) and str(recovered_state.get("encounter_states", {}).get(str(n01.get("node_id", "")), "UNRESOLVED")) != "CLEARED"
	var recovery_contract := mid_battle_loaded.ok and Vector2i(int(recovered_state.current_q), int(recovered_state.current_r)) == start_coord
	recovery_contract = recovery_contract and recovered_state.get("pending_encounter", {}).is_empty() and AppState.pending_battle_token.is_empty()
	recovery_contract = recovery_contract and hostile_preserved and not bool(AppState.profile.first_clear.get("CH01-N01", false))
	recovery_contract = recovery_contract and JSON.stringify(_canonical(AppState.profile.inventory)) == JSON.stringify(_canonical(pre_contact_inventory))
	recovery_contract = recovery_contract and int(AppState.profile.account.stamina) == pre_contact_stamina
	check(recovery_contract, "MID_BATTLE_REFRESH_03 reload returns pre-contact with hostile, entry, inventory and rewards intact")

	SaveService.reset_save_files()
	SaveService.soak_sandbox_enabled = backup_sandbox
	SaveService.soak_sandbox_session = backup_sandbox_session
	AppState.profile = backup_profile
	AppState.pending_battle_token = backup_token
	AppState.selected_stage_id = backup_stage
	SceneRouter.current_screen = backup_screen
	SceneRouter.history = backup_history
	SettingsService.values.developer_mode = developer_mode_before

func _test_full_chapter_transaction_route() -> void:
	# This is the data-authoritative counterpart to the browser route evidence:
	# every Chapter 1-2 operation must be able to own one normal-player map
	# transaction, commit exactly once, unlock its successor, and survive an
	# atomic load without relying on development authority. It deliberately does
	# not impersonate physical camera movement or BattleSimulation visuals.
	var backup_profile := AppState.profile.duplicate(true)
	var backup_token := AppState.pending_battle_token
	var backup_stage := AppState.selected_stage_id
	var backup_sandbox := SaveService.soak_sandbox_enabled
	var backup_sandbox_session := SaveService.soak_sandbox_session
	var backup_developer_mode := bool(SettingsService.values.developer_mode)
	SaveService.soak_sandbox_enabled = true
	SaveService.soak_sandbox_session = "r15_full_chapter_route"
	SaveService.reset_save_files()
	SettingsService.values.developer_mode = false
	AppState.new_game()
	# This fixture is about the one-shot transaction and unlock authority, not
	# about stamina economy. The live player-facing E2E uses ordinary stamina.
	AppState.profile.account.stamina = 999
	AppState.refresh_chapter_map_reveal("CH01_MAP")
	var shell := AppShellScript.new()
	var committed := true
	var duplicated := true
	var expected_cleared_by_map: Dictionary = {}
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var map_id := str(chapter.get("map_id", ""))
		var definition := ChapterMapLoader.load_map(map_id)
		var route: Array = []
		route.append_array(chapter.get("normal_stage_ids", []))
		route.append_array(chapter.get("hard_stage_ids", []))
		var expected_cleared: Array[String] = []
		for stage_value in route:
			var stage_id := str(stage_value)
			var node: Dictionary = ChapterMapLoader.node_for_stage(definition, stage_id)
			var state := AppState.chapter_map_state(map_id)
			var return_coord := Vector2i(int(state.get("current_q", 0)), int(state.get("current_r", 0)))
			AppState.selected_stage_id = stage_id
			var unlocked := AppState.is_stage_unlocked(stage_id)
			var prepared := not node.is_empty() and AppState.prepare_map_encounter(stage_id, str(node.get("node_id", "")), return_coord, map_id)
			var began := prepared and AppState.begin_battle_transaction(stage_id)
			var inventory_before: Dictionary = AppState.profile.inventory.duplicate(true)
			if began:
				shell.call("_battle_finished", {"victory": true, "survivors": 5, "time": 30.0, "ticks": 900, "damage": {}, "healing": {}})
			var after_commit := _persistent_profile(AppState.profile)
			var map_state := AppState.chapter_map_state(map_id)
			var node_id := str(node.get("node_id", ""))
			var did_clear := bool(AppState.profile.first_clear.get(stage_id, false)) and int(AppState.profile.stage_stars.get(stage_id, 0)) == 3
			did_clear = did_clear and map_state.get("cleared_encounters", []).has(node_id) and map_state.get("pending_encounter", {}).is_empty() and AppState.pending_battle_token.is_empty()
			did_clear = did_clear and JSON.stringify(_canonical(inventory_before)) != JSON.stringify(_canonical(AppState.profile.inventory))
			committed = committed and unlocked and prepared and began and did_clear
			expected_cleared.append(node_id)
			# A second view callback has no live entry token and must be persistent no-op.
			shell.call("_battle_finished", {"victory": true, "survivors": 5, "time": 30.0, "ticks": 900, "damage": {}, "healing": {}})
			duplicated = duplicated and JSON.stringify(_canonical(after_commit)) == JSON.stringify(_canonical(_persistent_profile(AppState.profile)))
		expected_cleared_by_map[map_id] = expected_cleared
	var all_cleared := true
	var hard_routes_complete := true
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var map_id := str(chapter.get("map_id", ""))
		var final_state := AppState.chapter_map_state(map_id)
		var expected_cleared: Array = expected_cleared_by_map.get(map_id, [])
		all_cleared = all_cleared and expected_cleared.all(func(node_id): return final_state.get("cleared_encounters", []).has(node_id))
		var hard_final := str((chapter.get("hard_stage_ids", []) as Array).back())
		hard_routes_complete = hard_routes_complete and bool(AppState.profile.chapter_progress.get(str(chapter.get("id", "")), {}).get("hard_unlocked", false)) and int(AppState.profile.stage_stars.get(hard_final, 0)) == 3
	var expansion_recruits_complete := true
	for number in range(9, 45): expansion_recruits_complete = expansion_recruits_complete and bool(AppState.profile.roster.get("CHR%03d" % number, {}).get("unlocked", false))
	check(committed and duplicated and all_cleared and hard_routes_complete and expansion_recruits_complete, "FULL_ROUTE_01 all Chapter 1-2 NORMAL/HARD transactions commit once with companion outcomes", JSON.stringify({"committed": committed, "duplicated": duplicated, "maps": expected_cleared_by_map, "hard": hard_routes_complete, "expansion_recruited": expansion_recruits_complete}))
	var saved_profile := _persistent_profile(AppState.profile)
	var saved := SaveService.save_game()
	AppState.new_game()
	var loaded := SaveService.load_game()
	var restored := saved.ok and loaded.ok and JSON.stringify(_canonical(_persistent_profile(AppState.profile))) == JSON.stringify(_canonical(saved_profile))
	for map_id_value in expected_cleared_by_map:
		var map_id := str(map_id_value)
		var restored_state := AppState.chapter_map_state(map_id)
		var expected_cleared: Array = expected_cleared_by_map[map_id]
		restored = restored and expected_cleared.all(func(node_id): return restored_state.get("cleared_encounters", []).has(node_id)) and restored_state.get("pending_encounter", {}).is_empty()
	check(restored, "FULL_ROUTE_02 completed Chapter 1-2 normal/hard transaction state survives reload", JSON.stringify({"save": saved.ok, "load": loaded.ok, "maps": expected_cleared_by_map}))
	shell.free()
	SaveService.reset_save_files()
	SaveService.soak_sandbox_enabled = backup_sandbox
	SaveService.soak_sandbox_session = backup_sandbox_session
	AppState.profile = backup_profile
	AppState.pending_battle_token = backup_token
	AppState.selected_stage_id = backup_stage
	SettingsService.values.developer_mode = backup_developer_mode

func _test_growth_material_planner_edges() -> void:
	# These are isolated planner fixtures. The production executor remains the
	# actual CharacterProgression/BreakthroughService API and is verified below.
	var backup := AppState.profile.duplicate(true)
	AppState.new_game()
	var state: Dictionary = AppState.profile.roster["CHR001"]
	state.level = 19
	state.xp = 1100
	state.breakthrough = 0
	AppState.profile.inventory.TRAINING_NOTE_L = 1
	AppState.profile.inventory.TRAINING_NOTE_M = 1
	AppState.profile.inventory.TRAINING_NOTE_S = 1
	AppState.profile.inventory.CREDIT = 9999
	var fitting := GrowthPlanBuilderScript.training_material_that_fits("CHR001")
	var used := CharacterProgression.use_material("CHR001", fitting, 1) if not fitting.is_empty() else GameResult.failure("NO_FIT")
	check(fitting == "TRAINING_NOTE_S" and used.ok, "GROWTH_PLAN_01 smaller legal EXP material selected when larger materials overflow cap")
	state.xp = 1500
	AppState.profile.inventory.TRAINING_NOTE_S = 1
	check(GrowthPlanBuilderScript.training_material_that_fits("CHR001").is_empty(), "GROWTH_PLAN_02 no EXP material selected when every option would exceed cap")
	state.level = 20
	state.xp = 0
	AppState.profile.inventory.BREAK_CORE_T1 = 10
	AppState.profile.inventory.ROLE_TOKEN_T1 = 5
	AppState.profile.inventory.CREDIT = 10000
	check(GrowthPlanBuilderScript.training_material_that_fits("CHR001").is_empty(), "GROWTH_PLAN_03 EXP material blocked exactly at breakthrough cap")
	var breakthrough := BreakthroughService.upgrade("CHR001")
	var account_curve: Array = DataRegistry.list_of("account_level_curve")
	AppState.profile.account.level = 20
	AppState.profile.account.xp = int(account_curve[19].get("xp_to_next", 0)) - 5
	AccountProgression.grant_stage_xp(1, 0)
	AppState.profile.inventory.TRAINING_NOTE_S = 1
	var post_breakthrough_material := GrowthPlanBuilderScript.training_material_that_fits("CHR001")
	var post_breakthrough_use := CharacterProgression.use_material("CHR001", post_breakthrough_material, 1) if not post_breakthrough_material.is_empty() else GameResult.failure("NO_FIT")
	check(breakthrough.ok and int(AppState.profile.account.level) == 21 and not post_breakthrough_material.is_empty() and post_breakthrough_use.ok, "GROWTH_PLAN_04 actual breakthrough plus account-cap increase re-enables legal EXP material selection", "%s / %s" % [breakthrough.error, post_breakthrough_material])
	var weapon_id := str(AppState.profile.roster["CHR001"].equipped_weapon_id)
	var weapon: Dictionary = AppState.profile.weapons[weapon_id]
	weapon.level = 9
	weapon.xp = 290
	weapon.tier = 1
	AppState.profile.inventory.WEAPON_CHIP_L = 1
	AppState.profile.inventory.WEAPON_CHIP_M = 1
	AppState.profile.inventory.WEAPON_CHIP_S = 1
	var weapon_fitting := GrowthPlanBuilderScript.weapon_material_that_fits(weapon_id)
	var weapon_used := WeaponUpgradeService.use_material(weapon_id, weapon_fitting, 1) if not weapon_fitting.is_empty() else GameResult.failure("NO_FIT")
	check(weapon_fitting == "WEAPON_CHIP_S" and weapon_used.ok, "GROWTH_PLAN_05 smaller legal weapon chip selected when larger chips overflow tier cap", "%s / %s" % [weapon_fitting, weapon_used.error])
	AppState.profile = backup

func _test_growth_recommended_batch() -> void:
	var backup := AppState.profile.duplicate(true)
	AppState.new_game()
	var party_ids := AppState.get_party().duplicate()
	var before := AppState.profile.duplicate(true)
	var preview := GrowthPlanBuilderScript.preview_recommended_batch(party_ids, 99)
	var batch := GrowthPlanBuilderScript.execute_recommended_batch(party_ids, 99)
	var actions: Array = batch.get("actions", [])
	var all_legal := bool(batch.get("ok", false)) and actions.size() == 12
	for action_value in actions:
		var action: Dictionary = action_value
		all_legal = all_legal and not str(action.get("kind", "")).is_empty() and action.has("result")
	var changed := JSON.stringify(before.get("inventory", {})) != JSON.stringify(AppState.profile.get("inventory", {}))
	check(all_legal and changed, "GROWTH_PLAN_06 bounded recommended party batch uses actual legal progression services")
	check(actions.size() == 12, "GROWTH_PLAN_07 player-facing recommendation never exceeds twelve service actions")
	var preview_actions: Array = preview.get("actions", [])
	var accounting: Dictionary = batch.get("accounting", {})
	var preview_accounting: Dictionary = preview.get("accounting", {})
	check(bool(batch.get("preview_matches_execution", false)) and _same_action_sequence(preview_actions, actions) and int(accounting.get("planned", -1)) == actions.size() and int(accounting.get("successful", -1)) == actions.size() and int(accounting.get("rejected", -1)) == 0 and accounting.get("inventory_delta", {}) == preview_accounting.get("inventory_delta", {}), "GROWTH_PLAN_10 preview, service execution, and material accounting match exactly")
	var next_after := GrowthPlanBuilderScript.next_legal_action(party_ids)
	var lowest_level := 999
	var highest_level := 0
	for character_id_value in party_ids:
		var level := int(AppState.profile.roster[str(character_id_value)].get("level", 1))
		lowest_level = mini(lowest_level, level)
		highest_level = maxi(highest_level, level)
	check(not next_after.is_empty() and lowest_level > 1 and highest_level - lowest_level <= 3, "GROWTH_PLAN_08 batch recomputes a continuation without starving low-level party members")
	var after_first := AppState.profile.duplicate(true)
	AppState.profile = before.duplicate(true)
	var replay := GrowthPlanBuilderScript.execute_recommended_batch(party_ids, 12)
	var replay_actions: Array = replay.get("actions", [])
	var deterministic := replay_actions.size() == actions.size()
	for index in mini(actions.size(), replay_actions.size()):
		var left: Dictionary = actions[index]
		var right: Dictionary = replay_actions[index]
		deterministic = deterministic and str(left.get("kind", "")) == str(right.get("kind", "")) and str(left.get("character_id", left.get("weapon_id", ""))) == str(right.get("character_id", right.get("weapon_id", ""))) and str(left.get("material_id", "")) == str(right.get("material_id", ""))
	check(deterministic, "GROWTH_PLAN_09 same fresh snapshot yields deterministic recommended action order")
	var empty_before := AppState.profile.duplicate(true)
	for item_id in AppState.profile.inventory.keys():
		AppState.profile.inventory[item_id] = 0
	var no_action_profile := AppState.profile.duplicate(true)
	var empty_batch := GrowthPlanBuilderScript.execute_recommended_batch(party_ids, 12)
	check(bool(empty_batch.get("ok", false)) and empty_batch.get("actions", []).is_empty() and int(empty_batch.get("accounting", {}).get("executed", -1)) == 0 and JSON.stringify(AppState.profile) == JSON.stringify(no_action_profile), "GROWTH_PLAN_11 no legal actions performs no service transaction or state mutation")
	AppState.profile = before.duplicate(true)
	var first_action: Dictionary = GrowthPlanBuilderScript.next_legal_action(party_ids)
	var partial := GrowthPlanBuilderScript.execute_action_sequence([first_action, {"kind": "INVALID"}, first_action], 12)
	check(not bool(partial.get("ok", true)) and str(partial.get("error", "")) == "INVALID_GROWTH_ACTION" and partial.get("actions", []).size() == 1 and str(partial.get("failed_action", {}).get("kind", "")) == "INVALID" and int(partial.get("accounting", {}).get("planned", -1)) == 3 and int(partial.get("accounting", {}).get("successful", -1)) == 1 and int(partial.get("accounting", {}).get("rejected", -1)) == 1, "GROWTH_PLAN_12 rejected action stops the batch with exact partial accounting and no later action")
	AppState.profile = before.duplicate(true)
	var preview_live_before := AppState.profile.duplicate(true)
	var preview_one := GrowthPlanBuilderScript.preview_recommended_batch(party_ids, 12)
	var preview_two := GrowthPlanBuilderScript.preview_recommended_batch(party_ids, 12)
	check(JSON.stringify(AppState.profile) == JSON.stringify(preview_live_before) and _same_action_sequence(preview_one.get("actions", []), preview_two.get("actions", [])), "GROWTH_PLAN_13 preview is side-effect free for the live profile and deterministic from one snapshot")
	var first_batch := GrowthPlanBuilderScript.execute_recommended_batch(party_ids, 12)
	var anti_starvation_levels: Array[int] = []
	for character_id_value in party_ids:
		anti_starvation_levels.append(int(AppState.profile.roster[str(character_id_value)].get("level", 1)))
	var anti_starvation: bool = anti_starvation_levels.min() > 1 and anti_starvation_levels.max() - anti_starvation_levels.min() <= 3 and first_batch.get("actions", []).size() == 12
	check(anti_starvation, "GROWTH_PLAN_14 balanced batch leaves no active party member at level one while another is far ahead")
	var persistent_before_save := _persistent_profile(AppState.profile)
	var saved := SaveService.save_game()
	AppState.new_game()
	var loaded := SaveService.load_game()
	check(saved.ok and loaded.ok and JSON.stringify(_canonical(_persistent_profile(AppState.profile))) == JSON.stringify(_canonical(persistent_before_save)), "GROWTH_PLAN_15 batch save and reload preserve level, EXP, breakthrough, inventory, and credit exactly")
	AppState.profile = empty_before
	AppState.profile = backup

func _same_action_sequence(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		var left_action: Dictionary = left[index]
		var right_action: Dictionary = right[index]
		var left_signature := "%s|%s|%s|%s|%s" % [str(left_action.get("kind", "")), str(left_action.get("character_id", "")), str(left_action.get("weapon_id", "")), str(left_action.get("slot", "")), str(left_action.get("material_id", ""))]
		var right_signature := "%s|%s|%s|%s|%s" % [str(right_action.get("kind", "")), str(right_action.get("character_id", "")), str(right_action.get("weapon_id", "")), str(right_action.get("slot", "")), str(right_action.get("material_id", ""))]
		if left_signature != right_signature:
			return false
	return true

func _persistent_profile(value: Dictionary) -> Dictionary:
	var persistent := value.duplicate(true)
	for key in ["quarantined_unknown_character_ids", "quarantined_unknown_map_node_ids", "quarantined_unknown_treasure_ids"]:
		persistent.erase(key)
	return persistent

func _changed_dictionary_keys(before: Dictionary, after: Dictionary) -> Array[String]:
	var keys: Dictionary = {}
	for key_value in before.keys(): keys[str(key_value)] = true
	for key_value in after.keys(): keys[str(key_value)] = true
	var changed: Array[String] = []
	for key in keys:
		if JSON.stringify(_canonical(before.get(key))) != JSON.stringify(_canonical(after.get(key))):
			changed.append(str(key))
	changed.sort()
	return changed

func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		var keys: Array = source.keys()
		keys.sort_custom(func(left, right): return str(left) < str(right))
		var output: Dictionary = {}
		for key in keys:
			output[str(key)] = _canonical(source[key])
		return output
	if value is Array:
		var output_array: Array = []
		for entry in value:
			output_array.append(_canonical(entry))
		return output_array
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value
