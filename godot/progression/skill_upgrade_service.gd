class_name SkillUpgradeService
extends RefCounted

static func upgrade(character_id: String, slot: String) -> GameResult:
	if not slot in ["normal", "passive", "ultimate"]:
		return GameResult.failure("INVALID_SLOT")
	var state: Dictionary = AppState.profile.roster[character_id]
	var current := int(state.skills[slot])
	var maximum := 5 if slot == "ultimate" else 10
	if current >= maximum:
		return GameResult.failure("MAX_SKILL_LEVEL")
	var kind := "ULTIMATE" if slot == "ultimate" else "NORMAL_OR_PASSIVE"
	var cost: Dictionary = {}
	for row in DataRegistry.list_of("skill_upgrade_costs"):
		if row.skill_type == kind and int(row.target_level) == current + 1:
			cost = row.cost
			break
	if cost.is_empty() or not AppState.pay(cost):
		return GameResult.failure("INSUFFICIENT_MATERIALS")
	state.skills[slot] = current + 1
	return GameResult.success({"level": current + 1, "cost": cost})

static func comparison(character_id: String, slot: String) -> Dictionary:
	var definition := DataRegistry.character(character_id)
	var skill_id: String = str(definition["%s_skill_id" % slot])
	var skill := DataRegistry.skill(skill_id)
	var current := int(AppState.profile.roster[character_id].skills[slot])
	var values: Array = skill.values
	var current_value := float(values[current - 1])
	var next_value = null if current >= values.size() else float(values[current])
	return {"current": current_value, "next": next_value, "increase": 0.0 if next_value == null else next_value - current_value, "max": current >= values.size()}

static func next_cost(character_id: String, slot: String) -> Dictionary:
	if not slot in ["normal", "passive", "ultimate"]:
		return {}
	var current := int(AppState.profile.roster[character_id].skills[slot])
	var maximum := 5 if slot == "ultimate" else 10
	if current >= maximum:
		return {}
	var kind := "ULTIMATE" if slot == "ultimate" else "NORMAL_OR_PASSIVE"
	for row in DataRegistry.list_of("skill_upgrade_costs"):
		if row.skill_type == kind and int(row.target_level) == current + 1:
			return row.cost
	return {}
