extends Node

const Planner := preload("res://progression/growth_plan_builder.gd")
const Affordability := preload("res://progression/growth_affordability_analyzer.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	var original := AppState.profile.duplicate(true)
	AppState.grant_all_materials(999999)
	AppState.profile.account.level = 100
	var fixed_count := 0
	for character in DataRegistry.list_of("characters"):
		var cid := str(character.id)
		var state: Dictionary = AppState.profile.roster[cid]
		var skill := DataRegistry.skill(str(character.ultimate_skill_id))
		if str(skill.effect) not in ["BUFF", "DEBUFF"]:
			continue
		fixed_count += 1
		state.unlocked = true
		state.level = 100
		state.breakthrough = 5
		state.skills = {"normal": 10, "passive": 10, "ultimate": 2}
		var weapon: Dictionary = AppState.profile.weapons[str(state.equipped_weapon_id)]
		weapon.level = 60
		weapon.tier = 6
		var before := AppState.profile.duplicate(true)
		check(not SkillUpgradeService.supports_upgrade(cid, "ultimate") and SkillUpgradeService.next_cost(cid, "ultimate").is_empty(), cid + " fixed effect offers no purchase")
		check(SkillUpgradeService.upgrade(cid, "ultimate").error == "FIXED_SKILL_EFFECT" and AppState.profile == before, cid + " fixed effect preserves inventory and existing level")
		check(Planner.next_legal_action([cid]).is_empty(), cid + " recommended plan excludes fixed effect")
		var candidates := Affordability.candidates(AppState.profile)
		var found := false
		for candidate in candidates:
			if str(candidate.key) == "SKILL:%s:ultimate" % cid: found = true
		check(not found, cid + " reward opportunity excludes fixed effect")
		check(is_equal_approx(float(SkillUpgradeService.comparison(cid, "ultimate").current), float(skill.values[1])), cid + " existing coefficient and skill level remain intact")
	check(fixed_count == 8, "all eight fixed ultimate effects reviewed")
	for cid in ["CHR001", "UNKNOWN_CHARACTER"]:
		if AppState.profile.roster.has(cid):
			AppState.profile.roster[cid].unlocked = false
		var before := AppState.profile.duplicate(true)
		var expected := "CHARACTER_LOCKED" if cid == "CHR001" else "UNKNOWN_CHARACTER"
		check(CharacterProgression.use_material(cid, "TRAINING_NOTE_S", 1).error == expected, cid + " level authority")
		check(SkillUpgradeService.upgrade(cid, "normal").error == expected, cid + " skill authority")
		check(BreakthroughService.upgrade(cid).error == expected, cid + " breakthrough authority")
		check(AppState.profile == before, cid + " rejected mutations preserve full profile")
	var state: Dictionary = AppState.profile.roster.CHR001
	state.unlocked = true
	state.level = 1
	state.xp = 0
	state.breakthrough = 0
	state.skills = {"normal": 1, "passive": 1, "ultimate": 1}
	var target := state.duplicate(true)
	target.level = 10
	var before_preview := AppState.profile.duplicate(true)
	var target_before := target.duplicate(true)
	var current_stats := CharacterProgression.final_stats("CHR001")
	var target_stats := CharacterProgression.final_stats("CHR001", target)
	check(int(target_stats.HP) > int(current_stats.HP) and int(target_stats.ATK) > int(current_stats.ATK), "target level previews actual stat growth")
	check(AppState.profile == before_preview and target == target_before, "stat preview mutates neither live profile nor override")
	check(CharacterProgression.final_stats("CHR001", state) == current_stats, "explicit current state preserves established stats")
	check(SkillUpgradeService.supports_upgrade("CHR012", "normal"), "normal DEBUFF still follows its real damage coefficient")
	var cost := SkillUpgradeService.next_cost("CHR001", "normal").duplicate(true)
	var inventory_before: Dictionary = AppState.profile.inventory.duplicate(true)
	var upgraded := SkillUpgradeService.upgrade("CHR001", "normal")
	check(upgraded.ok and int(state.skills.normal) == 2, "ordinary skill upgrade remains available")
	var exact := true
	for item_id in inventory_before:
		if AppState.inventory_count(str(item_id)) != int(inventory_before[item_id]) - int(cost.get(item_id, 0)): exact = false
	check(exact, "ordinary skill deducts only exact previewed cost")
	state.skills.normal = 10
	var max_before := AppState.profile.duplicate(true)
	check(SkillUpgradeService.upgrade("CHR001", "normal").error == "MAX_SKILL_LEVEL" and AppState.profile == max_before, "ordinary max level preserves inventory")
	AppState.profile = original
	print("GROWTH_SERVICE_AUTHORITY total=%d pass=%d fail=%d" % [checks, checks-failures, failures])
	get_tree().quit(0 if failures == 0 else 1)
