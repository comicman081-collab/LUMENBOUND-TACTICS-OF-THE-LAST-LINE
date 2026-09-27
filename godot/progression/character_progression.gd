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
	if not AppState.profile.get("roster", {}).has(character_id) or DataRegistry.character(character_id).is_empty():
		return GameResult.failure("UNKNOWN_CHARACTER")
	if not bool(AppState.profile.roster[character_id].get("unlocked", false)):
		return GameResult.failure("CHARACTER_LOCKED")
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

static func final_stats(character_id: String, state_override: Dictionary = {}) -> Dictionary:
	var definition := DataRegistry.character(character_id)
	var state: Dictionary = AppState.profile.roster[character_id] if state_override.is_empty() else state_override
	var level := int(state.level)
	var curve := float(DataRegistry.list_of("character_level_curve")[level - 1].curve)
	var multipliers := [1.0, 1.02, 1.04, 1.07, 1.10, 1.14]
	var output: Dictionary = {}
	for key in definition.stats_l1:
		var level_stat := MathUtil.round_half_up(float(definition.stats_l1[key]) + (float(definition.stats_l100[key]) - float(definition.stats_l1[key])) * curve)
		output[key] = MathUtil.round_half_up(level_stat * multipliers[int(state.breakthrough)])
	var weapon_id := str(state.get("equipped_weapon_id", ""))
	if not weapon_id.is_empty() and AppState.profile.weapons.has(weapon_id):
		# A what-if state (GrowthAdvisor's recommended profile) may carry the
		# raised weapon it assumes instead of the owned weapon state.
		var weapon_stats := WeaponUpgradeService.flat_stats_for(weapon_id, state.get("weapon_state_override", AppState.profile.weapons[weapon_id]))
		for key in weapon_stats:
			output[key] = int(output.get(key, 0)) + int(weapon_stats[key])
	return output

## Target-level transaction. Surplus from an indivisible note is retained on
## this character, including at a cap, and used before any further notes.
static func preview_target(character_id: String, target_level: int) -> Dictionary:
	var state: Dictionary = AppState.profile.get("roster", {}).get(character_id, {})
	if state.is_empty() or DataRegistry.character(character_id).is_empty():
		return {"ok": false, "error": "UNKNOWN_CHARACTER"}
	var current := int(state.get("level", 1))
	var cap := level_cap(state)
	var result := {"ok": false, "error": "", "from_level": current, "level": target_level, "cap": cap, "materials": {}, "credit_cost": 0, "required_xp": 0, "reserve_xp": int(state.get("training_xp_reserve", 0))}
	if not bool(state.get("unlocked", false)):
		result.error = "CHARACTER_LOCKED"
		return result
	if target_level <= current or target_level > cap:
		result.error = "LEVEL_CAP" if current >= cap else "INVALID_TARGET_LEVEL"
		return result
	var curve: Array = DataRegistry.list_of("character_level_curve")
	var required := -int(state.get("xp", 0))
	for level in range(current, target_level):
		required += int(curve[level - 1].xp_to_next)
		result.credit_cost += int(curve[level - 1].credit_cost)
	result.required_xp = maxi(0, required)
	var reserve := maxi(0, int(state.get("training_xp_reserve", 0)))
	var shortage := maxi(0, required - reserve)
	var selection := _select_notes(shortage)
	result.materials = selection.get("materials", {})
	result.reserve_xp = reserve + int(selection.get("xp", 0)) - required
	if not bool(selection.get("ok", false)):
		result.error = "INSUFFICIENT_MATERIALS"
	elif AppState.inventory_count("CREDIT") < int(result.credit_cost):
		result.error = "INSUFFICIENT_CREDIT"
	else:
		result.ok = true
	return result

static func maximum_target(character_id: String) -> int:
	var state: Dictionary = AppState.profile.get("roster", {}).get(character_id, {})
	if state.is_empty(): return 1
	var best := int(state.get("level", 1))
	for target in range(best + 1, level_cap(state) + 1):
		if not bool(preview_target(character_id, target).get("ok", false)): break
		best = target
	return best

static func level_to(character_id: String, target_level: int) -> GameResult:
	# Recompute against current inventory. Never trust a stale UI preview.
	var plan := preview_target(character_id, target_level)
	if not bool(plan.get("ok", false)): return GameResult.failure(str(plan.get("error", "INVALID_TARGET_LEVEL")))
	for item_id in plan.materials:
		AppState.profile.inventory[item_id] = AppState.inventory_count(item_id) - int(plan.materials[item_id])
	AppState.profile.inventory.CREDIT = AppState.inventory_count("CREDIT") - int(plan.credit_cost)
	var state: Dictionary = AppState.profile.roster[character_id]
	state.level = target_level
	state.xp = 0
	state.training_xp_reserve = int(plan.reserve_xp)
	return GameResult.success(plan)

static func _select_notes(required: int) -> Dictionary:
	if required <= 0: return {"ok": true, "materials": {}, "xp": 0}
	# Divisible denominations permit descending exact-fill plus one overshoot
	# candidate at each denomination. Choose least EXP, then fewest whole notes.
	var ids := ["TRAINING_NOTE_XL", "TRAINING_NOTE_L", "TRAINING_NOTE_M", "TRAINING_NOTE_S"]
	var used: Dictionary = {}
	var provided := 0
	var quantity := 0
	var best: Dictionary = {}
	for item_id in ids:
		var value := int(MATERIAL_XP[item_id])
		var available := maxi(0, AppState.inventory_count(item_id))
		var count := mini(available, maxi(0, required - provided) / value)
		if count > 0:
			used[item_id] = count
			provided += count * value
			quantity += count
		if provided >= required:
			return {"ok": true, "materials": used, "xp": provided}
		if count < available:
			var candidate := used.duplicate()
			candidate[item_id] = count + 1
			var amount := provided + value
			if best.is_empty() or amount < int(best.xp) or (amount == int(best.xp) and quantity + 1 < int(best.quantity)):
				best = {"ok": true, "materials": candidate, "xp": amount, "quantity": quantity + 1}
	return best if not best.is_empty() else {"ok": false, "materials": used, "xp": provided}
