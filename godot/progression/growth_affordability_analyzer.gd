class_name GrowthAffordabilityAnalyzer
extends RefCounted

## Computes growth opportunities against immutable inventory snapshots.
## It intentionally reports independently affordable candidates; it never sums
## mutually competing costs into a misleading "total upgrades" number.

const CHARACTER_XP := {"TRAINING_NOTE_S": 100, "TRAINING_NOTE_M": 500, "TRAINING_NOTE_L": 2500, "TRAINING_NOTE_XL": 10000}
const WEAPON_XP := {"WEAPON_CHIP_S": 100, "WEAPON_CHIP_M": 500, "WEAPON_CHIP_L": 2500, "WEAPON_CHIP_XL": 10000}
const BREAK_CAPS := [20, 40, 60, 80, 90, 100]
const WEAPON_CAPS := [10, 20, 30, 40, 50, 60]

static func analyze(before_profile: Dictionary, after_profile: Dictionary) -> Dictionary:
	var before := candidates(before_profile)
	var after := candidates(after_profile)
	var before_keys: Dictionary = {}
	for candidate in before:
		before_keys[str(candidate.key)] = true
	var newly: Array[Dictionary] = []
	for candidate in after:
		if not before_keys.has(str(candidate.key)):
			newly.append(candidate)
	return {"newly_affordable": newly, "summary": summary(after), "before_summary": summary(before)}

static func candidates(profile: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var inventory: Dictionary = profile.get("inventory", {})
	var account_level := int(profile.get("account", {}).get("level", 1))
	for character_id in profile.get("roster", {}):
		var state: Dictionary = profile.roster[character_id]
		if not bool(state.get("unlocked", false)):
			continue
		var level := _level_candidate(str(character_id), state, inventory, account_level)
		if not level.is_empty(): output.append(level)
		var breakthrough := _breakthrough_candidate(str(character_id), state, inventory)
		if not breakthrough.is_empty(): output.append(breakthrough)
		for slot in ["normal", "passive", "ultimate"]:
			var skill := _skill_candidate(str(character_id), state, slot, inventory)
			if not skill.is_empty(): output.append(skill)
	for weapon_id in profile.get("weapons", {}):
		var weapon_state: Dictionary = profile.weapons[weapon_id]
		if not bool(weapon_state.get("owned", false)):
			continue
		var weapon_level := _weapon_level_candidate(str(weapon_id), weapon_state, inventory)
		if not weapon_level.is_empty(): output.append(weapon_level)
		var weapon_tier := _weapon_tier_candidate(str(weapon_id), weapon_state, inventory)
		if not weapon_tier.is_empty(): output.append(weapon_tier)
	return output

static func summary(candidate_list: Array) -> Dictionary:
	var level_characters: Dictionary = {}
	var breakthrough_characters: Dictionary = {}
	var skill_characters: Dictionary = {}
	var weapon_levels: Dictionary = {}
	var weapon_tiers: Dictionary = {}
	for candidate in candidate_list:
		match str(candidate.get("kind", "")):
			"LEVEL": level_characters[str(candidate.character_id)] = true
			"BREAKTHROUGH": breakthrough_characters[str(candidate.character_id)] = true
			"SKILL": skill_characters[str(candidate.character_id)] = true
			"WEAPON_LEVEL": weapon_levels[str(candidate.weapon_id)] = true
			"WEAPON_TIER": weapon_tiers[str(candidate.weapon_id)] = true
	return {
		"level_characters": level_characters.size(),
		"breakthrough_characters": breakthrough_characters.size(),
		"skill_characters": skill_characters.size(),
		"weapon_levels": weapon_levels.size(),
		"weapon_tiers": weapon_tiers.size(),
	}

static func _level_candidate(character_id: String, state: Dictionary, inventory: Dictionary, account_level: int) -> Dictionary:
	var cap := mini(account_level, BREAK_CAPS[clampi(int(state.get("breakthrough", 0)), 0, 5)])
	var current_level := int(state.get("level", 1))
	if current_level >= cap:
		return {}
	for material_id in CHARACTER_XP:
		if int(inventory.get(material_id, 0)) <= 0:
			continue
		var preview := _character_preview(state, int(CHARACTER_XP[material_id]), cap)
		if int(preview.get("unused_xp", 0)) == 0 and int(preview.get("level", current_level)) > current_level and int(inventory.get("CREDIT", 0)) >= int(preview.get("credit_cost", 0)):
			return {"key": "LEVEL:%s" % character_id, "kind": "LEVEL", "character_id": character_id, "from_level": current_level, "to_level": int(preview.level), "material_id": material_id}
	return {}

static func _character_preview(state: Dictionary, exp_value: int, cap: int) -> Dictionary:
	var level := int(state.get("level", 1))
	var xp := int(state.get("xp", 0))
	var remaining := exp_value
	var credit_cost := 0
	var curve: Array = DataRegistry.list_of("character_level_curve")
	while remaining > 0 and level < cap:
		var row: Dictionary = curve[level - 1]
		var needed := int(row.get("xp_to_next", 0)) - xp
		var used := mini(remaining, needed)
		xp += used
		remaining -= used
		if xp >= int(row.get("xp_to_next", 0)):
			credit_cost += int(row.get("credit_cost", 0))
			xp = 0
			level += 1
	return {"level": level, "xp": xp, "unused_xp": remaining, "credit_cost": credit_cost}

static func _breakthrough_candidate(character_id: String, state: Dictionary, inventory: Dictionary) -> Dictionary:
	var current := int(state.get("breakthrough", 0))
	if current >= 5 or int(state.get("level", 1)) < BREAK_CAPS[current]:
		return {}
	var cost: Dictionary = DataRegistry.list_of("breakthroughs")[current + 1].get("cost", {})
	if _can_pay(inventory, cost):
		return {"key": "BREAKTHROUGH:%s" % character_id, "kind": "BREAKTHROUGH", "character_id": character_id, "from_breakthrough": current, "to_breakthrough": current + 1}
	return {}

static func _skill_candidate(character_id: String, state: Dictionary, slot: String, inventory: Dictionary) -> Dictionary:
	var current := int(state.get("skills", {}).get(slot, 1))
	var maximum := 5 if slot == "ultimate" else 10
	if current >= maximum:
		return {}
	var kind := "ULTIMATE" if slot == "ultimate" else "NORMAL_OR_PASSIVE"
	var cost: Dictionary = {}
	for row in DataRegistry.list_of("skill_upgrade_costs"):
		if str(row.get("skill_type", "")) == kind and int(row.get("target_level", 0)) == current + 1:
			cost = row.get("cost", {})
			break
	if _can_pay(inventory, cost):
		return {"key": "SKILL:%s:%s" % [character_id, slot], "kind": "SKILL", "character_id": character_id, "slot": slot, "from_level": current, "to_level": current + 1}
	return {}

static func _weapon_level_candidate(weapon_id: String, state: Dictionary, inventory: Dictionary) -> Dictionary:
	var current_level := int(state.get("level", 1))
	var tier := clampi(int(state.get("tier", 1)), 1, 6)
	var cap: int = int(WEAPON_CAPS[tier - 1])
	if current_level >= cap:
		return {}
	for material_id in WEAPON_XP:
		if int(inventory.get(material_id, 0)) <= 0:
			continue
		var preview := _weapon_preview(state, int(WEAPON_XP[material_id]), cap)
		if int(preview.get("unused_xp", 0)) == 0 and int(preview.get("level", current_level)) > current_level:
			return {"key": "WEAPON_LEVEL:%s" % weapon_id, "kind": "WEAPON_LEVEL", "weapon_id": weapon_id, "from_level": current_level, "to_level": int(preview.level), "material_id": material_id}
	return {}

static func _weapon_preview(state: Dictionary, exp_value: int, cap: int) -> Dictionary:
	var level := int(state.get("level", 1))
	var xp := int(state.get("xp", 0))
	var remaining := exp_value
	var curve: Array = DataRegistry.list_of("weapon_level_curve")
	while remaining > 0 and level < cap:
		var needed := int(curve[level - 1].get("xp_to_next", 0)) - xp
		var used := mini(remaining, needed)
		xp += used
		remaining -= used
		if xp >= int(curve[level - 1].get("xp_to_next", 0)):
			xp = 0
			level += 1
	return {"level": level, "xp": xp, "unused_xp": remaining}

static func _weapon_tier_candidate(weapon_id: String, state: Dictionary, inventory: Dictionary) -> Dictionary:
	var tier := int(state.get("tier", 1))
	if tier >= 6 or int(state.get("level", 1)) < WEAPON_CAPS[tier - 1]:
		return {}
	var cost: Dictionary = {}
	for row in DataRegistry.list_of("weapon_tier_costs"):
		if int(row.get("from_tier", 0)) == tier:
			cost = row.get("cost", {})
			break
	if _can_pay(inventory, cost):
		return {"key": "WEAPON_TIER:%s" % weapon_id, "kind": "WEAPON_TIER", "weapon_id": weapon_id, "from_tier": tier, "to_tier": tier + 1}
	return {}

static func _can_pay(inventory: Dictionary, cost: Dictionary) -> bool:
	if cost.is_empty():
		return false
	for item_id in cost:
		if int(inventory.get(item_id, 0)) < int(cost[item_id]):
			return false
	return true
