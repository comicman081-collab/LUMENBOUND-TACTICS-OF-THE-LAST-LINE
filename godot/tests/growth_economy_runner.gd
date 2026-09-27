extends Node

## The growth economy behind "권장 성장": following the required route from a
## new game, one press before each operation reaches that operation's
## recommended profile (level with breakthroughs, skills, weapon) for the whole
## party, using only the starting inventory and the rewards of the operations
## cleared before it. Also covers the v9 → v10 save migration that grants the
## same supply for operations cleared before it existed.

var passed := 0
var failed := 0

func check(ok: bool, label: String, detail := "") -> void:
	if ok:
		passed += 1
		print("PASS | " + label)
	else:
		failed += 1
		print("FAIL | " + label + ("" if detail.is_empty() else " | " + detail))
		push_error(label)

func _ready() -> void:
	_test_first_clear_account_floor()
	_test_required_route()
	_test_sparse_presses()
	_test_v9_migration()
	print("GROWTH_ECONOMY total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _required_route() -> Array[String]:
	var chapters: Array = DataRegistry.list_of("chapters").duplicate()
	chapters.sort_custom(func(left, right): return str(left.id) < str(right.id))
	var route: Array[String] = []
	for chapter_value in chapters:
		for stage_id in chapter_value.get("required_stage_ids", []):
			route.append(str(stage_id))
	return route

func _growth_first_clear_items(stage_ids: Array[String]) -> Dictionary:
	var total: Dictionary = {}
	for stage_id in stage_ids:
		var stage := DataRegistry.stage(stage_id)
		for row in DataRegistry.list_of("rewards"):
			if str(row.get("id", "")) != str(stage.get("reward_table_id", "")): continue
			for item in row.get("growth_first_clear", []):
				total[str(item.item_id)] = int(total.get(str(item.item_id), 0)) + int(item.quantity)
			break
	return total

func _test_first_clear_account_floor() -> void:
	AppState.new_game()
	var stage := DataRegistry.stage("CH01-N05")
	var first := AppState.record_stage_clear("CH01-N05", 3)
	check(first and int(AppState.profile.account.level) >= int(stage.recommended_level) + AccountProgression.FIRST_CLEAR_LEVEL_LEAD, "ECONOMY_01 a first clear lifts the account ahead of the operation's recommended level")
	var level_after := int(AppState.profile.account.level)
	AppState.record_stage_clear("CH01-N05", 3)
	check(int(AppState.profile.account.level) == level_after, "ECONOMY_02 a repeat clear does not lift the account again")

func _test_required_route() -> void:
	AppState.new_game()
	var party: Array = AppState.get_party().duplicate()
	var route := _required_route()
	var misses: Array[String] = []
	var first_miss := ""
	var seed := 1
	for stage_id in route:
		var report := GrowthPlanBuilder.execute_to_recommended(party, stage_id)
		if not bool(report.get("reached", false)):
			misses.append(stage_id)
			if first_miss.is_empty():
				first_miss = "%s blocked=%s shortages=%s" % [stage_id, JSON.stringify(report.get("blocked", {})), JSON.stringify(report.get("shortages", {}))]
		var stage := DataRegistry.stage(stage_id)
		var first := AppState.record_stage_clear(stage_id, 3)
		RewardService.resolve(stage_id, 1, seed, first)
		AccountProgression.grant_stage_xp(int(stage.stamina_cost), 20 if first else 0)
		seed += 1
	check(route.size() >= 200 and misses.is_empty(), "ECONOMY_03 on the required route one 권장 성장 press before every operation reaches its recommended profile", "route=%d misses=%d first=%s" % [route.size(), misses.size(), first_miss])
	var final_profile := GrowthAdvisor.recommended_profile(DataRegistry.stage(route[route.size() - 1]))
	var at_final := true
	for character_id_value in party:
		var state: Dictionary = AppState.profile.roster[str(character_id_value)]
		var weapon: Dictionary = AppState.profile.weapons.get(str(state.get("equipped_weapon_id", "")), {})
		at_final = at_final and int(state.level) == int(final_profile.level) and int(state.skills.normal) >= int(final_profile.normal) and int(state.skills.ultimate) >= int(final_profile.ultimate) and int(weapon.get("level", 0)) >= int(final_profile.weapon_level)
	check(at_final, "ECONOMY_04 the party finishes the campaign at the final operation's recommended profile")
	var report := GrowthAdvisor.party_report(party, [], route[route.size() - 1])
	check(float(report.readiness) >= 0.995, "ECONOMY_05 the advisor agrees the party is ready for the final operation", "readiness=%.3f" % float(report.readiness))
	print("INFO | credits left after the campaign: %s" % MathUtil.comma(AppState.inventory_count("CREDIT")))

## A player who ignores growth until each chapter's boss still reaches the
## boss's recommended profile with one press: the supply accumulates.
func _test_sparse_presses() -> void:
	AppState.new_game()
	var party: Array = AppState.get_party().duplicate()
	var bosses: Dictionary = {}
	for chapter_value in DataRegistry.list_of("chapters"):
		var required: Array = chapter_value.get("required_stage_ids", [])
		if not required.is_empty(): bosses[str(required[required.size() - 1])] = true
	var misses: Array[String] = []
	var seed := 1
	for stage_id in _required_route():
		if bosses.has(stage_id) and not bool(GrowthPlanBuilder.execute_to_recommended(party, stage_id).get("reached", false)):
			misses.append(stage_id)
		var stage := DataRegistry.stage(stage_id)
		var first := AppState.record_stage_clear(stage_id, 3)
		RewardService.resolve(stage_id, 1, seed, first)
		AccountProgression.grant_stage_xp(int(stage.stamina_cost), 20 if first else 0)
		seed += 1
	check(bosses.size() == 20 and misses.is_empty(), "ECONOMY_09 growing only before each chapter boss still reaches the boss's recommended profile in one press", "misses=%s" % str(misses))

func _test_v9_migration() -> void:
	AppState.new_game()
	var legacy := AppState.profile.duplicate(true)
	legacy["save_schema_version"] = 9
	legacy.account.level = 5
	var cleared: Array[String] = []
	for stage_id in DataRegistry.chapter("CH01").required_stage_ids.slice(0, 10):
		legacy.first_clear[str(stage_id)] = true
		cleared.append(str(stage_id))
	var top_recommended := 0
	for stage_id in cleared:
		top_recommended = maxi(top_recommended, int(DataRegistry.stage(stage_id).recommended_level))
	var expected := _growth_first_clear_items(cleared)
	var inventory_before: Dictionary = legacy.inventory.duplicate(true)
	var migrated := SaveService._migrate(legacy)
	var value: Dictionary = migrated.value if migrated.ok else {}
	var granted_exactly := not expected.is_empty()
	for item_id in expected:
		granted_exactly = granted_exactly and int(value.get("inventory", {}).get(item_id, 0)) - int(inventory_before.get(item_id, 0)) == int(expected[item_id])
	check(migrated.ok and int(value.get("save_schema_version", 0)) == AppState.SAVE_SCHEMA_VERSION and granted_exactly, "ECONOMY_06 v9 saves receive exactly the growth supply of the operations they already cleared")
	var notice: Dictionary = value.get("growth_economy_notice", {})
	var notice_items: Dictionary = notice.get("items", {})
	var notice_matches := notice_items.size() == expected.size()
	for item_id in expected:
		notice_matches = notice_matches and int(notice_items.get(item_id, 0)) == int(expected[item_id])
	check(int(value.get("account", {}).get("level", 0)) == mini(100, top_recommended + AccountProgression.FIRST_CLEAR_LEVEL_LEAD) and notice_matches and int(notice.get("account_from", 0)) == 5, "ECONOMY_07 the migration lifts the account once and records a one-time notice")
	var fresh := AppState.profile.duplicate(true)
	fresh["save_schema_version"] = 9
	var fresh_migrated := SaveService._migrate(fresh)
	check(fresh_migrated.ok and not Dictionary(fresh_migrated.value).has("growth_economy_notice"), "ECONOMY_08 a save with no cleared operation migrates without a notice")
