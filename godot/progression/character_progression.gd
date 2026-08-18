class_name CharacterProgression
extends RefCounted

const MATERIAL_XP := {"TRAINING_NOTE_S": 100, "TRAINING_NOTE_M": 500, "TRAINING_NOTE_L": 2500, "TRAINING_NOTE_XL": 10000}

static func level_cap(character_state: Dictionary) -> int:
	var caps := [20, 40, 60, 80, 90, 100]
	return mini(int(AppState.profile.account.level), caps[clampi(int(character_state.breakthrough), 0, 5)])

static func preview(character_id: String, item_id: String, quantity: int) -> Dictionary:
	var state: Dictionary = AppState.profile.roster[character_id].duplicate(true)
	var remaining := int(MATERIAL_XP.get(item_id, 0)) * maxi(0, quantity)
	var cap := level_cap(state)
	var curve: Array = DataRegistry.list_of("character_level_curve")
	var credit_cost := 0
	while remaining > 0 and int(state.level) < cap:
		var row: Dictionary = curve[int(state.level) - 1]
		var needed := int(row.xp_to_next) - int(state.xp)
		var used := mini(remaining, needed)
		state.xp = int(state.xp) + used
		remaining -= used
		if int(state.xp) >= int(curve[int(state.level) - 1].xp_to_next):
			credit_cost += int(row.credit_cost)
			state.xp = 0
			state.level = int(state.level) + 1
	return {"level": state.level, "xp": state.xp, "unused_xp": remaining, "cap": cap, "credit_cost": credit_cost}

static func use_material(character_id: String, item_id: String, quantity: int) -> GameResult:
	if not MATERIAL_XP.has(item_id) or quantity <= 0:
		return GameResult.failure("INVALID_MATERIAL")
	if AppState.inventory_count(item_id) < quantity:
		return GameResult.failure("INSUFFICIENT_MATERIALS")
	var state: Dictionary = AppState.profile.roster[character_id]
	if int(state.level) >= level_cap(state):
		return GameResult.failure("LEVEL_CAP")
	var result := preview(character_id, item_id, quantity)
	if int(result.unused_xp) > 0:
		return GameResult.failure("WOULD_EXCEED_LEVEL_CAP")
	if AppState.inventory_count("CREDIT") < int(result.credit_cost):
		return GameResult.failure("INSUFFICIENT_CREDIT")
	AppState.profile.inventory[item_id] = AppState.inventory_count(item_id) - quantity
	AppState.profile.inventory.CREDIT = AppState.inventory_count("CREDIT") - int(result.credit_cost)
	state.level = result.level
	state.xp = result.xp
	return GameResult.success(result)

static func final_stats(character_id: String) -> Dictionary:
	var definition := DataRegistry.character(character_id)
	var state: Dictionary = AppState.profile.roster[character_id]
	var level := int(state.level)
	var curve := float(DataRegistry.list_of("character_level_curve")[level - 1].curve)
	var multipliers := [1.0, 1.02, 1.04, 1.07, 1.10, 1.14]
	var output: Dictionary = {}
	for key in definition.stats_l1:
		var level_stat := MathUtil.round_half_up(float(definition.stats_l1[key]) + (float(definition.stats_l100[key]) - float(definition.stats_l1[key])) * curve)
		output[key] = MathUtil.round_half_up(level_stat * multipliers[int(state.breakthrough)])
	var weapon_id := str(state.get("equipped_weapon_id", ""))
	if not weapon_id.is_empty() and AppState.profile.weapons.has(weapon_id):
		var weapon_stats := WeaponUpgradeService.flat_stats_for(weapon_id, AppState.profile.weapons[weapon_id])
		for key in weapon_stats:
			output[key] = int(output.get(key, 0)) + int(weapon_stats[key])
	return output
