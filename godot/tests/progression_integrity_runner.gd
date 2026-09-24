extends Node

## Regression checks for progression/reward integrity fixes: archive replays,
## owned-only party presets, abandoned battle transactions, the unreadable-save
## write lock, per-battle seeds and stage-list results on the chapter map.

var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS | " + label)
	else:
		failed += 1
		print("FAIL | " + label)
		push_error(label)

func _ready() -> void:
	_test_archive_replay()
	_test_party_presets()
	_test_abandoned_battle_transaction()
	_test_stage_list_result_keeps_squad()
	_test_battle_seed()
	_test_unreadable_save_lock()
	await _test_archive_screen()
	print("PROGRESSION_INTEGRITY total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run_scenario(scenario_id: String, replay: bool) -> void:
	var runner := ScenarioRunner.new()
	runner.replay = replay
	runner.load_scenario(scenario_id, not replay)
	var safety := 0
	while not runner.state.finished and safety < 1000:
		safety += 1
		var command := runner.advance()
		if str(command.get("command", "")) == "choice":
			runner.choose(0)

func _test_archive_replay() -> void:
	AppState.new_game()
	check(not AppState.scenario_seen("SCN_CH01_MID_A") and not AppState.scenario_seen("SCN_CH01_OUTRO"), "ARCHIVE_01 unreached campaign scenes are not listed")
	var shards_before := AppState.inventory_count("LANTERN_SHARD")
	_run_scenario("SCN_PROLOGUE", false)
	var shards_after_first := AppState.inventory_count("LANTERN_SHARD")
	check(shards_after_first > shards_before and AppState.scenario_completed("SCN_PROLOGUE") and AppState.scenario_seen("SCN_PROLOGUE"), "ARCHIVE_02 first playthrough grants its reward once and marks completion")
	var flags_before := JSON.stringify(AppState.profile.story_flags)
	_run_scenario("SCN_PROLOGUE", true)
	check(AppState.inventory_count("LANTERN_SHARD") == shards_after_first and JSON.stringify(AppState.profile.story_flags) == flags_before and not AppState.profile.last_scenario_position.has("SCN_PROLOGUE"), "ARCHIVE_03 replay grants nothing, sets no flags and leaves no checkpoint")
	check(not bool(AppState.profile.roster.CHR007.unlocked), "ARCHIVE_04 fixture keeps CHR007 locked before its outro")
	_run_scenario("SCN_CH01_OUTRO", true)
	check(not bool(AppState.profile.roster.CHR007.unlocked), "ARCHIVE_05 replaying an outro cannot recruit its companion")
	_run_scenario("SCN_CH01_OUTRO", false)
	check(bool(AppState.profile.roster.CHR007.unlocked) and str(AppState.profile.roster.CHR007.acquisition_status) == "OWNED", "ARCHIVE_06 the real outro recruits through unlock_character")

func _test_party_presets() -> void:
	AppState.new_game()
	var all_owned := true
	for party in AppState.profile.parties:
		for character_id in party:
			all_owned = all_owned and bool(AppState.profile.roster[str(character_id)].unlocked)
	check(all_owned, "PARTY_01 fresh presets contain only owned companions")
	check(AppState.party_block_reason().is_empty(), "PARTY_02 the active fresh preset is deployable")
	AppState.profile.parties[1] = ["CHR001", "CHR002", "CHR003", "CHR006", "CHR008"]
	check(not AppState.party_block_reason(AppState.profile.parties[1]).is_empty(), "PARTY_03 a preset with a locked recruit is blocked before entry")
	var legacy := AppState.profile.duplicate(true)
	AppState.apply_loaded(legacy)
	var repaired: Array = AppState.profile.parties[1]
	var unique := {}
	for character_id in repaired: unique[str(character_id)] = true
	check(unique.size() == 5 and not repaired.has("CHR006") and not repaired.has("CHR008") and repaired.slice(0, 3) == ["CHR001", "CHR002", "CHR003"], "PARTY_04 loading repairs legacy presets and keeps owned members in place")

func _test_abandoned_battle_transaction() -> void:
	AppState.new_game()
	# Release rules: developer builds never charge stamina, so refunds are moot.
	var developer_before := bool(SettingsService.values.get("developer_mode", false))
	SettingsService.values["developer_mode"] = false
	var stamina_before := int(AppState.profile.account.stamina)
	check(AppState.begin_battle_transaction("CH01-N01") and int(AppState.profile.account.stamina) < stamina_before, "TXN_01 fixture pays the entry cost")
	check(not AppState.begin_battle_transaction("CH01-N01"), "TXN_02 a live token refuses a second battle")
	AppState.abandon_battle_transaction("CH01-N01")
	check(AppState.pending_battle_token.is_empty() and int(AppState.profile.account.stamina) == stamina_before, "TXN_03 abandoning an unstarted battle releases the token and refunds the cost")
	check(AppState.begin_battle_transaction("CH01-N01"), "TXN_04 the next battle can start after an abandoned entry")
	AppState.abandon_battle_transaction("CH01-N01")
	SettingsService.values["developer_mode"] = developer_before

func _test_stage_list_result_keeps_squad() -> void:
	AppState.new_game()
	var state := AppState.chapter_map_state()
	var before := Vector2i(int(state.current_q), int(state.current_r))
	check(state.get("pending_encounter", {}).is_empty() and AppState.begin_battle_transaction("CH01-N01"), "MAP_RESULT_01 fixture starts a stage-list battle without a map contact")
	AppState.apply_battle_result_to_map("CH01-N01", true)
	check(Vector2i(int(state.current_q), int(state.current_r)) == before and AppState.pending_battle_token.is_empty(), "MAP_RESULT_02 a stage-list victory never teleports the squad")

func _test_battle_seed() -> void:
	var developer_before := bool(SettingsService.values.get("developer_mode", false))
	SettingsService.values["developer_mode"] = false
	var seeds := {}
	for index in range(8):
		seeds[AppState.next_battle_seed()] = true
		OS.delay_usec(50)
	check(seeds.size() > 1, "SEED_01 Release battles and sweeps draw fresh seeds")
	SettingsService.values["developer_mode"] = developer_before

func _test_archive_screen() -> void:
	AppState.new_game()
	_run_scenario("SCN_PROLOGUE", false)
	var shell := preload("res://screens/boot/boot.tscn").instantiate()
	add_child(shell)
	await get_tree().process_frame
	shell._show_screen("ARCHIVE")
	await get_tree().process_frame
	var labels: Array[String] = []
	for button_value in shell.find_children("*", "Button", true, false):
		labels.append((button_value as Button).text)
	var prologue_title := LocalizationService.tr_key(str(DataRegistry.by_id("scenarios", "SCN_PROLOGUE").title_key))
	var mid_title := LocalizationService.tr_key(str(DataRegistry.by_id("scenarios", "SCN_CH01_MID_A").title_key))
	check(labels.any(func(text): return text.begins_with(prologue_title)) and not labels.any(func(text): return text.begins_with(mid_title)), "ARCHIVE_07 the archive screen lists seen scenes and hides unreached ones")
	shell.queue_free()
	await get_tree().process_frame

func _test_unreadable_save_lock() -> void:
	AppState.new_game()
	var paths := SaveService.save_paths_for(false)
	for key in ["save", "backup", "temp"]:
		if FileAccess.file_exists(str(paths[key])): DirAccess.remove_absolute(ProjectSettings.globalize_path(str(paths[key])))
	var newer := AppState.profile.duplicate(true)
	newer["save_schema_version"] = AppState.SAVE_SCHEMA_VERSION + 1
	newer["checksum"] = SaveService._checksum_for(newer)
	var file := FileAccess.open(str(paths.save), FileAccess.WRITE)
	file.store_string(JSON.stringify(newer))
	file.close()
	var loaded := SaveService.load_game()
	check(not loaded.ok and not SaveService.write_lock_reason.is_empty(), "SAVE_LOCK_01 a newer save locks writes instead of loading a fresh profile")
	check(not SaveService.save_game().ok and FileAccess.get_file_as_string(str(paths.save)).contains("\"save_schema_version\":%d" % (AppState.SAVE_SCHEMA_VERSION + 1)), "SAVE_LOCK_02 the locked save file is never overwritten")
	var archived := SaveService.archive_unreadable_save_and_unlock()
	var archive_found := false
	for name in DirAccess.get_files_at(ProjectSettings.globalize_path("user://")):
		if name.begins_with("save_v1.unreadable_"): archive_found = true
	check(archived.ok and archive_found and SaveService.write_lock_reason.is_empty(), "SAVE_LOCK_03 choosing to start over archives the unreadable save first")
	check(SaveService.save_game().ok, "SAVE_LOCK_04 saving resumes after the archive")
	for key in ["save", "backup", "temp"]:
		if FileAccess.file_exists(str(paths[key])): DirAccess.remove_absolute(ProjectSettings.globalize_path(str(paths[key])))
