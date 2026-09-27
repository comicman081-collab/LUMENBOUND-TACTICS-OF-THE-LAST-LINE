extends Node

## Explained growth recommendations and the result / growth screens that show them.

const Advisor := preload("res://progression/growth_advisor.gd")
const ResultPresentation := preload("res://screens/result_presentation.gd")

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
	_test_target_and_power()
	_test_level_recommendations()
	_test_post_cap_skill_requirement()
	await _test_result_screen()
	await _test_growth_screen()
	await _test_growth_menu()
	print("GROWTH_ADVISOR total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _advance_to(stage_number: int) -> void:
	AppState.new_game()
	AppState.selected_stage_id = "CH01-N01"
	var chapter := DataRegistry.chapter("CH01")
	for stage_id in chapter.required_stage_ids:
		if int(DataRegistry.stage(str(stage_id)).stage_number) < stage_number:
			AppState.profile.first_clear[str(stage_id)] = true
	AppState.profile.chapter_progress.CH01.normal_highest = stage_number - 1

func _test_target_and_power() -> void:
	AppState.new_game()
	AppState.selected_stage_id = "CH01-N01"
	check(Advisor.target_stage_id() == "CH01-N01", "ADVISOR_01 a fresh save targets the first operation")
	var state: Dictionary = AppState.profile.roster.CHR001.duplicate(true)
	var stronger := state.duplicate(true)
	stronger.level = 10
	check(Advisor.combat_power("CHR001", stronger) > Advisor.combat_power("CHR001", state), "ADVISOR_02 combat power rises with level")
	_advance_to(6)
	var target := Advisor.target_stage_id()
	check(int(DataRegistry.stage(target).stage_number) >= 6, "ADVISOR_03 the target follows campaign progress")
	var report := Advisor.party_report(AppState.get_party())
	check(float(report.readiness) < 1.0 and int(report.recommended_power) > int(report.party_power) and not str(report.verdict).is_empty(), "ADVISOR_04 an under-levelled party reports a readiness gap with a verdict")

func _test_level_recommendations() -> void:
	_advance_to(6)
	var party := AppState.get_party()
	var downed := ["CHR003"]
	var entries := Advisor.recommendations(party, downed, 3)
	check(not entries.is_empty() and str(entries[0].kind) == "LEVEL_TO", "ADVISOR_05 levels come first when the party is below the recommended level")
	check(str(entries[0].character_id) == "CHR003" and str(entries[0].reason).contains("쓰러졌습니다") and str(entries[0].reason).contains("권장 Lv."), "ADVISOR_06 the member who went down is recommended first, with readable reasons")
	check(str(entries[0].gain).contains("전투력 +"), "ADVISOR_07 each recommendation states its expected gain")
	var before_level := int(AppState.profile.roster.CHR003.level)
	var outcome: GameResult = Advisor.execute(entries[0])
	check(outcome.ok and int(AppState.profile.roster.CHR003.level) == int(entries[0].action.target) and int(AppState.profile.roster.CHR003.level) > before_level, "ADVISOR_08 applying a recommendation uses the normal level service")
	AppState.profile.inventory["TRAINING_NOTE_S"] = 0
	AppState.profile.inventory["TRAINING_NOTE_M"] = 0
	AppState.profile.inventory["TRAINING_NOTE_L"] = 0
	AppState.profile.inventory["TRAINING_NOTE_XL"] = 0
	var blocked := Advisor.recommendations(party, [], 5)
	var explained := false
	for entry in blocked:
		if str(entry.kind) == "BLOCKED" and str(entry.reason).contains("부족"): explained = true
	check(explained, "ADVISOR_09 without materials the advisor explains what is missing instead of going silent")

func _test_post_cap_skill_requirement() -> void:
	var ch04_stage := DataRegistry.stage("CH04-N20")
	var ch04 := Advisor.expected_skill_levels(ch04_stage)
	var ch04_profile := Advisor.recommended_profile(ch04_stage)
	check(int(ch04.normal) == 2 and int(ch04.passive) == 2 and int(ch04.ultimate) == 1 and int(ch04_profile.level) == int(ch04_stage.recommended_level) and int(ch04_profile.weapon_level) == mini(60, int(ch04_stage.recommended_level)) and Advisor.skill_requirement_text(ch04_stage).contains("무기 Lv."), "ADVISOR_10 chapters 1-4 recommend skills 2/2/1 and a weapon at the recommended level")
	var ch05 := Advisor.expected_skill_levels(DataRegistry.stage("CH05-N01"))
	var ch20 := Advisor.expected_skill_levels(DataRegistry.stage("CH20-N20"))
	check(int(ch05.normal) == 3 and int(ch05.ultimate) == 1 and int(ch20.normal) == 10 and int(ch20.passive) == 10 and int(ch20.ultimate) == 5, "ADVISOR_11 after the level cap the balance expects skills to climb to their maximum by chapter 20")
	AppState.new_game()
	for character_id in AppState.get_party():
		var state: Dictionary = AppState.profile.roster[str(character_id)]
		state.level = 100
		state.breakthrough = 5
	var report := Advisor.party_report(AppState.get_party(), [], "CH12-N10")
	var member: Dictionary = report.members[0]
	check(float(report.readiness) < 1.0 and not Dictionary(member.skill_gaps).is_empty() and str(Advisor.skill_requirement_text(DataRegistry.stage("CH12-N10"))).contains("궁극기 Lv."), "ADVISOR_12 a level-100 party with starting skills is not reported as ready for a late chapter")

func _shell() -> Node:
	var shell := preload("res://screens/boot/boot.tscn").instantiate()
	add_child(shell)
	await get_tree().process_frame
	return shell

func _test_result_screen() -> void:
	_advance_to(6)
	var shell = await _shell()
	shell.battle_party_ids.clear()
	for character_id in AppState.get_party(): shell.battle_party_ids.append(str(character_id))
	shell.last_battle_result = {"victory": true, "time": 40.0, "survivors": 4, "damage": {"CHR001": 400, "CHR005": 1200, "CHR003": 300}, "healing": {}, "deaths": [{"unit_id": "P:CHR003", "tick": 100}], "event_hash": "TEST"}
	shell.last_rewards = {"CREDIT": 3000}
	shell.last_reward_report = {"source_type": "BATTLE", "source_id": "CH01-N05", "rewards": {"CREDIT": 3000}, "growth": {}, "progress": {}}
	shell.current_screen = "BATTLE"
	shell._show_screen("RESULT")
	await get_tree().process_frame
	var header: Node = shell.find_child("ResultHeader", true, false)
	var contribution: Node = shell.find_child("ResultContribution", true, false)
	check(header != null and contribution != null and shell.find_child("ResultMvp", true, false) != null, "RESULT_UI_01 result shows header, MVP and contribution")
	var texts: Array[String] = []
	for label_value in shell.find_children("*", "Label", true, false): texts.append((label_value as Label).text)
	var joined := "\n".join(texts)
	check(joined.contains("★★☆") and joined.contains("전원 생존 4/5") and joined.contains("소탕"), "RESULT_UI_02 stars and the missed condition are spelled out")
	check(joined.contains("쓰러짐") and joined.contains("MVP"), "RESULT_UI_03 contribution marks who went down and names the MVP")
	var buttons: Array[String] = []
	for button_value in shell.find_children("*", "Button", true, false): buttons.append((button_value as Button).text)
	var growth_free: bool = shell.find_child("ResultGrowthAdvice", true, false) == null and shell.find_child("GrowthAdviceApply", true, false) == null \
		and not buttons.any(func(text): return text.contains("파티 성장") or text.begins_with("NEW")) and not joined.contains("새롭게 가능한 성장")
	check(growth_free, "RESULT_UI_04 the result offers no party growth (it lives in the lobby / map menu)")
	shell.queue_free()
	await get_tree().process_frame

func _test_growth_menu() -> void:
	var shell = await _shell()
	_advance_to(6)
	AppState.profile.inventory["CREDIT"] = 500000
	AppState.profile.inventory["TRAINING_NOTE_M"] = 200
	shell._show_screen("HOME")
	await get_tree().process_frame
	var home_menu: Button = shell.find_child("GrowthMenuButton", true, false)
	check(home_menu != null and home_menu.text == "메뉴", "MENU_01 the lobby has a 메뉴 button")
	home_menu.pressed.emit()
	await get_tree().process_frame
	var level_entry: Button = shell.find_child("GrowthMenuLevelUp", true, false)
	var skill_entry: Button = shell.find_child("GrowthMenuSkillUp", true, false)
	check(level_entry != null and skill_entry != null and level_entry.text.begins_with("레벨업") and skill_entry.text.begins_with("스킬업"), "MENU_02 the menu holds separate 레벨업 and 스킬업 entries")
	check(level_entry.text.contains("지금 가능"), "MENU_03 each entry says whether growth is affordable now")
	skill_entry.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(shell.current_screen == "GROWTH" and str(shell.growth_tab) == "스킬업" and shell.find_child("GrowthMenuLayer", true, false) == null, "MENU_04 스킬업 closes the menu and opens growth on the skill tab")
	check(AppState.get_party().has(str(AppState.selected_character_id)), "MENU_05 the growth screen opens on a party member")
	shell.current_screen = "HOME"
	shell._open_growth_menu_tab("레벨업")
	await get_tree().process_frame
	await get_tree().process_frame
	var header: Node = shell.find_child("ScreenHeader", true, false)
	var titled := false
	if header != null:
		for label_value in header.find_children("*", "Label", true, false): titled = titled or (label_value as Label).text == "레벨업"
	check(shell.current_screen == "GROWTH" and str(shell.growth_tab) == "레벨업" and titled, "MENU_06 레벨업 opens growth on the level tab, titled by the tab")
	shell._show_screen("RELAY")
	await get_tree().process_frame
	var relay_menu: Button = shell.find_child("GrowthMenuButton", true, false)
	var relay_header: Node = shell.find_child("ScreenHeader", true, false)
	check(shell.current_screen == "RELAY" and relay_menu != null and relay_menu.is_visible_in_tree() and relay_header != null and relay_menu.get_parent() == relay_header, "MENU_08 the relay operation screen has a 메뉴 button in its header")
	relay_menu.pressed.emit()
	await get_tree().process_frame
	check(shell.find_child("GrowthMenuSkillUp", true, false) != null, "MENU_09 the relay 메뉴 opens the same level-up / skill-up menu")
	var recommended: Button = shell.find_child("GrowthMenuRecommended", true, false)
	var level_before := int(AppState.profile.roster[str(AppState.get_party()[0])].level)
	check(recommended != null and recommended.text.begins_with("권장 성장") and not recommended.disabled, "MENU_10 the menu offers 권장 성장 for the whole party", recommended.text if recommended != null else "missing")
	recommended.pressed.emit()
	await get_tree().process_frame
	var result: Label = shell.find_child("GrowthMenuResult", true, false)
	check(result != null and result.text.begins_with("권장 성장") and int(AppState.profile.roster[str(AppState.get_party()[0])].level) > level_before, "MENU_11 권장 성장 from the menu applies growth and shows the result in the reopened menu", result.text if result != null else "")
	shell.queue_free()
	await get_tree().process_frame
	var map_script := load("res://chapter_map/runtime/chapter_map_screen.gd")
	var map_screen: Control = map_script.new()
	check(map_screen.has_signal("menu_requested"), "MENU_07 the chapter map (relay camp and field movement) exposes the menu")
	map_screen.free()

func _test_growth_screen() -> void:
	# The shell boots from the save a previous 권장 성장 press wrote, so the
	# state is set after boot.
	var shell = await _shell()
	_advance_to(6)
	AppState.selected_character_id = "CHR001"
	shell.growth_tab = "레벨업"
	shell._show_screen("GROWTH")
	await get_tree().process_frame
	var labels: Array[String] = []
	for button_value in shell.find_children("*", "Button", true, false): labels.append((button_value as Button).text)
	check(shell.find_child("GrowthGuide", true, false) != null and shell.find_child("ReadinessBar", true, false) != null, "GROWTH_UI_01 growth screen opens with the party guide and readiness")
	check(labels.has("권장") and labels.any(func(text): return text.contains("Lv.")), "GROWTH_UI_02 party tabs show levels and the level card offers a recommended-level jump")
	var apply: Button = shell.find_child("GrowthRecommendedApply", true, false)
	check(apply != null and not apply.disabled, "GROWTH_UI_03 the guide offers one 권장 성장 press for the whole party")
	# With the materials a first clear supplies, one press reaches the profile.
	for item_id in ["TRAINING_NOTE_L", "TRAINING_NOTE_M", "TRAINING_NOTE_S", "WEAPON_CHIP_M", "WEAPON_CHIP_S", "SKILL_BOOK_T1", "SKILL_TOKEN_T1", "ULT_BOOK_T1"]:
		AppState.profile.inventory[item_id] = int(AppState.profile.inventory.get(item_id, 0)) + 200
	AppState.profile.inventory["CREDIT"] = 5000000
	shell._show_screen("GROWTH")
	await get_tree().process_frame
	apply = shell.find_child("GrowthRecommendedApply", true, false)
	apply.pressed.emit()
	await get_tree().process_frame
	var profile := Advisor.recommended_profile(DataRegistry.stage(Advisor.target_stage_id()))
	var all_reached := true
	for member_id in AppState.get_party():
		var member: Dictionary = AppState.profile.roster[str(member_id)]
		var weapon: Dictionary = AppState.profile.weapons.get(str(member.get("equipped_weapon_id", "")), {"level": profile.weapon_level})
		all_reached = all_reached and int(member.level) >= int(profile.level) and int(member.skills.normal) >= int(profile.normal) and int(member.skills.passive) >= int(profile.passive) and int(member.skills.ultimate) >= int(profile.ultimate) and int(weapon.level) >= int(profile.weapon_level)
	check(all_reached and str(shell.growth_feedback).begins_with("권장 성장 완료"), "GROWTH_UI_04 권장 성장 raises every member's level, skills and weapon to the recommended profile", str(shell.growth_feedback))
	check(shell.find_child("GrowthRecommendedApply", true, false) == null and float(Advisor.party_report(AppState.get_party()).readiness) >= 0.995, "GROWTH_UI_05 once reached the guide reports the recommended level instead of a button")
	shell.queue_free()
	await get_tree().process_frame
