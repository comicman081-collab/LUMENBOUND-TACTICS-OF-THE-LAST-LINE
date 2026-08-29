class_name R15FreshProgressionRunner
extends RefCounted

## A service-level Chapter 1 E2E.  This is intentionally distinct from the
## SceneTree entrypoint so startup, runner loading, and progression logic each
## produce an unambiguous checkpoint without mocking game services.

const CHECKPOINT_STAGES := {"CH01-N03": true, "CH01-N06": true, "CH01-N10": true, "CH01-N15": true, "CH01-N19": true, "CH01-N20": true}
const MAX_GROWTH_ACTIONS_PER_STAGE := 100
const GrowthPlanBuilderScript := preload("res://progression/growth_plan_builder.gd")

var errors: Array[String] = []
var rows: Array = []
var save_reload_mismatches := 0
var save_reload_differences: Array = []
var duplicate_reward_attempts := 0
var illegal_growth_actions := 0
var dead_ends := 0

func run() -> Dictionary:
	_mark("R15_FRESH_E2E_START")
	AppState.new_game()
	if not AppState.is_stage_unlocked("CH01-N01") or AppState.is_stage_unlocked("CH01-N02"):
		return _finish_failure("fresh stage-lock invariant failed")
	var initial_save := SaveService.save_game()
	if not initial_save.ok:
		return _finish_failure("fresh save failed: %s" % initial_save.error)
	var stages: Array = DataRegistry.list_of("stages").filter(func(value): return str(value.get("mode", "")) == "NORMAL" and str(value.get("chapter_id", "")) == "CH01")
	stages.sort_custom(func(left, right): return int(left.get("stage_number", 0)) < int(right.get("stage_number", 0)))
	if stages.size() != 20:
		return _finish_failure("expected exactly twenty Chapter 1 normal stages")
	for index in stages.size():
		var stage: Dictionary = stages[index]
		var stage_id := str(stage.get("id", ""))
		if not _run_stage(stage, 1515000 + index):
			break
	var complete := errors.is_empty() and rows.size() == 20 and bool(AppState.profile.get("first_clear", {}).get("CH01-N20", false))
	var report := _report(complete)
	_write_report(report)
	if complete:
		_mark("R15_FRESH_E2E_PASS")
	else:
		_mark("R15_FRESH_E2E_FAIL")
	return report

func _run_stage(stage: Dictionary, seed: int) -> bool:
	var stage_id := str(stage.get("id", ""))
	_mark("R15_%s_BEGIN" % stage_id.replace("-", "_"))
	if not AppState.is_stage_unlocked(stage_id):
		return _stage_failure(stage_id, "stage is locked before transaction")
	var map_definition := ChapterMapLoader.load_map("CH01_MAP")
	var node := ChapterMapLoader.node_for_stage(map_definition, stage_id)
	if node.is_empty():
		return _stage_failure(stage_id, "map node is missing")
	var map_state := AppState.chapter_map_state("CH01_MAP")
	var return_hex := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	AppState.selected_stage_id = stage_id
	if not AppState.prepare_map_encounter(stage_id, str(node.get("node_id", "")), return_hex):
		return _stage_failure(stage_id, "map encounter preparation failed")
	if not AppState.begin_battle_transaction(stage_id):
		return _stage_failure(stage_id, "stage-entry transaction failed")
	var pre_reward_profile: Dictionary = AppState.profile.duplicate(true)
	var battle := _battle(stage, seed)
	if not bool(battle.get("victory", false)):
		AppState.apply_battle_result_to_map(stage_id, false)
		return _stage_failure(stage_id, "battle failed: %s" % str(battle.get("reason", "unknown")))
	_mark("R15_%s_BATTLE_DONE" % stage_id.replace("-", "_"))
	var stars := 1 + (1 if int(battle.get("survivors", 0)) == 5 else 0) + (1 if float(battle.get("time", 9999.0)) <= float(stage.get("target_time", 0.0)) else 0)
	var first := AppState.record_stage_clear(stage_id, stars)
	if not first:
		return _stage_failure(stage_id, "first-clear invariant failed")
	if not AppState.claim_pending_reward_once(stage_id):
		return _stage_failure(stage_id, "reward transaction could not be claimed")
	var rewards := RewardService.resolve(stage_id, 1, seed, true)
	AccountProgression.grant_stage_xp(int(stage.get("stamina_cost", 0)), 20)
	for character_id_value in AppState.get_party():
		RelationshipService.grant(str(character_id_value), 10)
	AppState.queue_story_event("STAGE_CLEAR", stage_id)
	if not AppState.apply_battle_result_to_map(stage_id, true):
		return _stage_failure(stage_id, "map victory application failed")
	# A post-resolution duplicate callback has no transaction token and must not
	# mint a second reward.
	if AppState.claim_pending_reward_once(stage_id):
		duplicate_reward_attempts += 1
		return _stage_failure(stage_id, "duplicate reward claim succeeded")
	_mark("R15_%s_REWARD_COMMITTED" % stage_id.replace("-", "_"))
	var post_reward_profile: Dictionary = AppState.profile.duplicate(true)
	var affordability := GrowthAffordabilityAnalyzer.analyze(pre_reward_profile, post_reward_profile)
	var growth_actions := _apply_growth(stage_id)
	if not errors.is_empty():
		return false
	_mark("R15_%s_GROWTH_EXECUTED" % stage_id.replace("-", "_"))
	var saved := SaveService.save_game()
	if not saved.ok:
		return _stage_failure(stage_id, "save failed: %s" % saved.error)
	_mark("R15_%s_SAVE_OK" % stage_id.replace("-", "_"))
	if CHECKPOINT_STAGES.has(stage_id):
		var before_reload_profile: Dictionary = AppState.profile.duplicate(true)
		var before_reload_persistent := _persistent_profile(before_reload_profile)
		var before_reload_hash := _profile_hash(before_reload_persistent)
		var loaded := SaveService.load_game()
		var after_reload_persistent := _persistent_profile(AppState.profile)
		var after_reload_hash := _profile_hash(after_reload_persistent)
		if not loaded.ok or before_reload_hash != after_reload_hash:
			save_reload_mismatches += 1
			var difference := _first_difference(_canonical(before_reload_persistent), _canonical(after_reload_persistent))
			save_reload_differences.append({"stage_id": stage_id, "save_result": loaded.error if not loaded.ok else "ok", "before_hash": before_reload_hash, "after_hash": after_reload_hash, "first_difference": difference})
			return _stage_failure(stage_id, "save/reload mismatch: %s" % JSON.stringify(difference))
		_mark("R15_%s_RELOAD_OK" % stage_id.replace("-", "_"))
	rows.append({
		"stage_id": stage_id,
		"battle": battle,
		"first_clear": first,
		"stars": stars,
		"rewards": rewards,
		"newly_affordable": affordability.get("newly_affordable", []),
		"growth_summary": affordability.get("summary", {}),
		"applied_growth": growth_actions,
		"account": AppState.profile.get("account", {}).duplicate(true),
		"party": _party_progress(),
		"inventory": AppState.profile.get("inventory", {}).duplicate(true),
	})
	_write_report(_report(false))
	_mark("R15_%s_PASS" % stage_id.replace("-", "_"))
	return true

func _battle(stage: Dictionary, seed: int) -> Dictionary:
	var simulation := BattleSimulation.new()
	simulation.setup(AppState.create_party_snapshot(), stage, seed, DataRegistry.data)
	simulation.auto_enabled = true
	var tick_limit := int(float(stage.get("time_limit", 90.0)) * 30.0) + 5
	while not simulation.state.ended and simulation.state.tick < tick_limit:
		simulation.tick()
	return simulation.result_snapshot()

func _apply_growth(stage_id: String) -> Array:
	var actions: Array = []
	var party_ids: Array = AppState.get_party().duplicate()
	for index in MAX_GROWTH_ACTIONS_PER_STAGE:
		var action: Dictionary = GrowthPlanBuilderScript.next_legal_action(party_ids)
		if action.is_empty():
			return actions
		var outcome: GameResult = GrowthPlanBuilderScript.execute(action)
		if not outcome.ok:
			illegal_growth_actions += 1
			_stage_failure(stage_id, "planned growth action failed: %s" % outcome.error)
			return actions
		action["result"] = outcome.value
		actions.append(action)
	dead_ends += 1
	_stage_failure(stage_id, "growth action safety limit reached")
	return actions

func _stage_failure(stage_id: String, reason: String) -> bool:
	var message := "%s: %s" % [stage_id, reason]
	errors.append(message)
	printerr("R15_STAGE_FAIL | ", message)
	return false

func _finish_failure(reason: String) -> Dictionary:
	errors.append(reason)
	printerr("R15_BOOT_FAIL | ", reason)
	var report := _report(false)
	_write_report(report)
	return report

func _party_progress() -> Dictionary:
	var output: Dictionary = {}
	for character_id_value in AppState.get_party():
		var character_id := str(character_id_value)
		var state: Dictionary = AppState.profile.get("roster", {}).get(character_id, {})
		var weapon_id := str(state.get("equipped_weapon_id", ""))
		output[character_id] = {
			"level": int(state.get("level", 1)),
			"xp": int(state.get("xp", 0)),
			"breakthrough": int(state.get("breakthrough", 0)),
			"skills": state.get("skills", {}).duplicate(true),
			"weapon": AppState.profile.get("weapons", {}).get(weapon_id, {}).duplicate(true),
		}
	return output

func _report(completed: bool) -> Dictionary:
	return {
		"schema_version": 2,
		"simulation": "fresh profile; actual stage transaction + BattleSimulation + RewardService + Growth services + SaveService",
		"completed_normal_route": completed,
		"stages_completed": rows.size(),
		"first_clear_duplicates": duplicate_reward_attempts,
		"illegal_growth_actions": illegal_growth_actions,
		"save_reload_mismatches": save_reload_mismatches,
		"save_reload_differences": save_reload_differences.duplicate(true),
		"dead_ends": dead_ends,
		"errors": errors.duplicate(),
		"rows": rows.duplicate(true),
		"final_account": AppState.profile.get("account", {}).duplicate(true),
		"final_party": _party_progress(),
		"final_inventory": AppState.profile.get("inventory", {}).duplicate(true),
	}

func _write_report(report: Dictionary) -> void:
	var report_dir := ProjectSettings.globalize_path("res://").path_join("../reports/r15").simplify_path()
	DirAccess.make_dir_recursive_absolute(report_dir)
	var output := FileAccess.open(report_dir.path_join("R15_PROGRESSION_SIMULATION.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "  "))

func _mark(marker: String) -> void:
	print(marker)

func _profile_hash(profile: Dictionary) -> String:
	return JSON.stringify(_canonical(profile)).sha256_text()

func _persistent_profile(profile: Dictionary) -> Dictionary:
	var persistent := profile.duplicate(true)
	# SaveService._sanitize adds these empty diagnostic arrays after a valid
	# load. They are runtime-derived quarantine reports, not persisted progress.
	for key in ["quarantined_unknown_character_ids", "quarantined_unknown_map_node_ids", "quarantined_unknown_treasure_ids"]:
		persistent.erase(key)
	return persistent

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
		var output: Array = []
		for entry in value:
			output.append(_canonical(entry))
		return output
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value

func _first_difference(left: Variant, right: Variant, path := "$") -> Dictionary:
	if typeof(left) != typeof(right):
		return {"path": path, "before": left, "after": right, "reason": "type"}
	if left is Dictionary:
		var left_dict: Dictionary = left
		var right_dict: Dictionary = right
		var keys: Array = left_dict.keys()
		for key in right_dict.keys():
			if not keys.has(key):
				keys.append(key)
		keys.sort_custom(func(a, b): return str(a) < str(b))
		for key in keys:
			if not left_dict.has(key) or not right_dict.has(key):
				return {"path": "%s.%s" % [path, str(key)], "before": left_dict.get(key, "<missing>"), "after": right_dict.get(key, "<missing>"), "reason": "key"}
			var nested := _first_difference(left_dict[key], right_dict[key], "%s.%s" % [path, str(key)])
			if not nested.is_empty():
				return nested
		return {}
	if left is Array:
		var left_array: Array = left
		var right_array: Array = right
		if left_array.size() != right_array.size():
			return {"path": path, "before_size": left_array.size(), "after_size": right_array.size(), "reason": "array_size"}
		for index in left_array.size():
			var nested := _first_difference(left_array[index], right_array[index], "%s[%d]" % [path, index])
			if not nested.is_empty():
				return nested
		return {}
	if left != right:
		return {"path": path, "before": left, "after": right, "reason": "value"}
	return {}
