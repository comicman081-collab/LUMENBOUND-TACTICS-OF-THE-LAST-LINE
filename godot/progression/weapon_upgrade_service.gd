class_name WeaponUpgradeService
extends RefCounted

const MATERIAL_XP := {"WEAPON_CHIP_S": 100, "WEAPON_CHIP_M": 500, "WEAPON_CHIP_L": 2500, "WEAPON_CHIP_XL": 10000}
const CAPS := [10, 20, 30, 40, 50, 60]

static func use_material(weapon_id: String, item_id: String, quantity: int) -> GameResult:
	if not MATERIAL_XP.has(item_id) or AppState.inventory_count(item_id) < quantity or quantity <= 0:
		return GameResult.failure("INSUFFICIENT_MATERIALS")
	var result := preview(weapon_id, item_id, quantity)
	if not result.ok:
		return result
	if int(result.value.unused_xp) > 0:
		return GameResult.failure("WOULD_EXCEED_TIER_CAP")
	var state: Dictionary = AppState.profile.weapons[weapon_id]
	state.level = result.value.level
	state.xp = result.value.xp
	AppState.profile.inventory[item_id] = AppState.inventory_count(item_id) - quantity
	return result

static func preview(weapon_id: String, item_id: String, quantity: int) -> GameResult:
	if not MATERIAL_XP.has(item_id) or quantity <= 0 or not AppState.profile.weapons.has(weapon_id):
		return GameResult.failure("INVALID_MATERIAL")
	var state: Dictionary = AppState.profile.weapons[weapon_id].duplicate(true)
	var cap: int = int(CAPS[int(state.tier) - 1])
	if int(state.level) >= cap:
		return GameResult.failure("TIER_LEVEL_CAP")
	var remaining: int = int(MATERIAL_XP[item_id]) * quantity
	var curve: Array = DataRegistry.list_of("weapon_level_curve")
	while remaining > 0 and int(state.level) < cap:
		var needed := int(curve[int(state.level) - 1].xp_to_next) - int(state.xp)
		var used := mini(remaining, needed)
		state.xp = int(state.xp) + used
		remaining -= used
		if int(state.xp) >= int(curve[int(state.level) - 1].xp_to_next):
			state.level = int(state.level) + 1
			state.xp = 0
	return GameResult.success({"level": state.level, "xp": state.xp, "unused_xp": remaining})

static func flat_stats_for(weapon_id: String, state: Dictionary) -> Dictionary:
	var definition := DataRegistry.by_id("weapons", weapon_id)
	if definition.is_empty() or not bool(state.get("owned", false)):
		return {}
	var level := clampi(int(state.get("level", 1)), 1, 60)
	var progress := float(level - 1) / 59.0
	var output: Dictionary = {}
	var primary := str(definition.get("primary_stat", ""))
	if not primary.is_empty():
		output[primary] = MathUtil.round_half_up(lerpf(float(definition.get("primary_l1", 0)), float(definition.get("primary_l60", 0)), progress))
	var tier := clampi(int(state.get("tier", 1)), 1, 6)
	var secondary := str(definition.get("secondary_stat", ""))
	if tier >= 3 and not secondary.is_empty():
		output[secondary] = int(definition.get("secondary_t5", 0)) if tier >= 5 else int(definition.get("secondary_t3", 0))
	return output

static func tier_up(weapon_id: String) -> GameResult:
	var state: Dictionary = AppState.profile.weapons[weapon_id]
	var tier := int(state.tier)
	if tier >= 6: return GameResult.failure("MAX_TIER")
	if int(state.level) < CAPS[tier - 1]: return GameResult.failure("REQUIRES_TIER_CAP_LEVEL")
	var row: Dictionary = DataRegistry.data.get("weapon_tier_costs", [])[tier - 1] if DataRegistry.data.has("weapon_tier_costs") else {}
	if row.is_empty(): return GameResult.failure("MISSING_TIER_COST")
	if not AppState.pay(row.cost): return GameResult.failure("INSUFFICIENT_MATERIALS")
	state.tier = tier + 1
	return GameResult.success(state.tier)

static func tier_up_cost(weapon_id: String) -> Dictionary:
	if not AppState.profile.weapons.has(weapon_id):
		return {}
	var tier := int(AppState.profile.weapons[weapon_id].tier)
	if tier >= 6:
		return {}
	for row in DataRegistry.list_of("weapon_tier_costs"):
		if int(row.from_tier) == tier:
			return row.cost
	return {}
