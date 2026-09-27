class_name GrowthPlanBuilder
extends RefCounted

## Selects one legal next growth action from the live profile.  The planner is
## deliberately side-effect free: execution remains in the actual progression
## services so tests and runtime never gain a parallel growth implementation.

const TRAINING_MATERIALS := ["TRAINING_NOTE_XL", "TRAINING_NOTE_L", "TRAINING_NOTE_M", "TRAINING_NOTE_S"]
const WEAPON_MATERIALS := ["WEAPON_CHIP_XL", "WEAPON_CHIP_L", "WEAPON_CHIP_M", "WEAPON_CHIP_S"]
const BREAK_CAPS := [20, 40, 60, 80, 90, 100]
const WEAPON_CAPS := [10, 20, 30, 40, 50, 60]

static func training_material_that_fits(character_id: String) -> String:
	if not AppState.profile.get("roster", {}).has(character_id):
		return ""
	for material_id in TRAINING_MATERIALS:
		if AppState.inventory_count(material_id) <= 0:
			continue
		var preview := CharacterProgression.preview(character_id, material_id, 1)
		if int(preview.get("unused_xp", 0)) == 0 and AppState.inventory_count("CREDIT") >= int(preview.get("credit_cost", 0)):
			return material_id
	return ""

static func weapon_material_that_fits(weapon_id: String) -> String:
	if not AppState.profile.get("weapons", {}).has(weapon_id):
		return ""
	for material_id in WEAPON_MATERIALS:
		if AppState.inventory_count(material_id) <= 0:
			continue
		var preview := WeaponUpgradeService.preview(weapon_id, material_id, 1)
		if preview.ok and WeaponUpgradeService.fits(preview.value):
			return material_id
	return ""

static func next_legal_action(party_ids: Array) -> Dictionary:
	# Unlock a cap only when a party member has actually reached it.  This keeps
	# earned EXP useful without directly mutating level or breakthrough state.
	for character_id_value in party_ids:
		var character_id := str(character_id_value)
		if _can_breakthrough(character_id):
			return {"kind": "BREAKTHROUGH", "character_id": character_id}
	for character_id_value in _characters_by_level(party_ids):
		var character_id := str(character_id_value)
		var material_id := training_material_that_fits(character_id)
		if not material_id.is_empty():
			return {"kind": "LEVEL", "character_id": character_id, "material_id": material_id}
	for character_id_value in party_ids:
		var character_id := str(character_id_value)
		for slot in ["normal", "passive", "ultimate"]:
			if not SkillUpgradeService.next_cost(character_id, slot).is_empty() and AppState.can_pay(SkillUpgradeService.next_cost(character_id, slot)):
				return {"kind": "SKILL", "character_id": character_id, "slot": slot}
	for weapon_id_value in _weapons_by_level(party_ids):
		var weapon_id := str(weapon_id_value)
		var material_id := weapon_material_that_fits(weapon_id)
		if not material_id.is_empty():
			return {"kind": "WEAPON_LEVEL", "weapon_id": weapon_id, "material_id": material_id}
	for weapon_id_value in _weapons_by_level(party_ids):
		var weapon_id := str(weapon_id_value)
		var tier_cost := WeaponUpgradeService.tier_up_cost(weapon_id)
		if not tier_cost.is_empty() and AppState.can_pay(tier_cost):
			return {"kind": "WEAPON_TIER", "weapon_id": weapon_id}
	return {}

static func execute(action: Dictionary) -> GameResult:
	match str(action.get("kind", "")):
		"LEVEL":
			return CharacterProgression.use_material(str(action.get("character_id", "")), str(action.get("material_id", "")), 1)
		"BREAKTHROUGH":
			return BreakthroughService.upgrade(str(action.get("character_id", "")))
		"SKILL":
			return SkillUpgradeService.upgrade(str(action.get("character_id", "")), str(action.get("slot", "")))
		"WEAPON_LEVEL":
			return WeaponUpgradeService.use_material(str(action.get("weapon_id", "")), str(action.get("material_id", "")), 1)
		"WEAPON_TIER":
			return WeaponUpgradeService.tier_up(str(action.get("weapon_id", "")))
	return GameResult.failure("INVALID_GROWTH_ACTION")

## "권장 성장": raise the party to the target operation's recommended profile
## (GrowthAdvisor.recommended_profile: level with its breakthroughs, skills and
## the equipped weapon) in one press. Levels go to the lowest member first, one
## level at a time, so a short inventory is shared instead of spent on one
## member; skills then rise one level per round across the party, and weapons
## come last. Nothing beyond the recommended profile is bought. Every step goes
## through the production services, which re-check materials, caps and credits.
##
## The preview runs the same plan against an isolated copy of the profile and
## restores the live profile before returning, so the player sees the result
## and the cost before anything is spent.
static func preview_to_recommended(party_ids: Array, stage_id := "") -> Dictionary:
	var live_profile: Dictionary = AppState.profile
	AppState.profile = live_profile.duplicate(true)
	var report := _raise_to_recommended(party_ids, stage_id)
	AppState.profile = live_profile
	return report

static func execute_to_recommended(party_ids: Array, stage_id := "") -> Dictionary:
	var preview := preview_to_recommended(party_ids, stage_id)
	var report := _raise_to_recommended(party_ids, stage_id)
	report["preview_matches_execution"] = _action_sequences_match(preview.get("actions", []), report.get("actions", []))
	return report

static func _raise_to_recommended(party_ids: Array, stage_id: String) -> Dictionary:
	var target_stage_id := stage_id if not stage_id.is_empty() else GrowthAdvisor.target_stage_id()
	var target := GrowthAdvisor.recommended_profile(DataRegistry.stage(target_stage_id))
	var members: Array[String] = []
	for character_id_value in party_ids:
		var character_id := str(character_id_value)
		if bool(AppState.profile.get("roster", {}).get(character_id, {}).get("unlocked", false)) and not members.has(character_id):
			members.append(character_id)
	var before := _growth_snapshot(members)
	var actions: Array = []
	var blocked: Dictionary = {}
	_raise_levels(members, target, actions, blocked)
	_raise_skills(members, target, actions, blocked)
	_raise_weapons(members, target, actions, blocked)
	var after := _growth_snapshot(members)
	var remaining := _remaining_to_profile(members, target)
	return {
		"ok": true,
		"stage_id": target_stage_id,
		"target": target,
		"actions": actions,
		"blocked": blocked,
		"reached": remaining.is_empty(),
		"shortages": _shortages(remaining),
		"accounting": _batch_accounting(before, after, actions.size(), actions.size(), 0),
		"members": _member_changes(members, before, after, target),
	}

static func _raise_levels(members: Array[String], target: Dictionary, actions: Array, blocked: Dictionary) -> void:
	var goal := int(target.level)
	while true:
		var candidates: Array[String] = []
		for character_id in members:
			if not blocked.has(character_id) and int(AppState.profile.roster[character_id].level) < goal:
				candidates.append(character_id)
		if candidates.is_empty():
			return
		candidates.sort_custom(func(left: String, right: String) -> bool:
			var left_level := int(AppState.profile.roster[left].level)
			var right_level := int(AppState.profile.roster[right].level)
			return left_level < right_level or (left_level == right_level and members.find(left) < members.find(right)))
		var character_id := candidates[0]
		var state: Dictionary = AppState.profile.roster[character_id]
		var level := int(state.level)
		if level >= int(BREAK_CAPS[clampi(int(state.breakthrough), 0, 5)]):
			var breakthrough := BreakthroughService.upgrade(character_id)
			if not breakthrough.ok:
				blocked[character_id] = "BREAKTHROUGH:" + str(breakthrough.error)
				continue
			actions.append({"kind": "BREAKTHROUGH", "character_id": character_id})
			continue
		if level >= CharacterProgression.level_cap(state):
			blocked[character_id] = "ACCOUNT_LEVEL"
			continue
		var leveled := CharacterProgression.level_to(character_id, level + 1)
		if not leveled.ok:
			blocked[character_id] = str(leveled.error)
			continue
		actions.append({"kind": "LEVEL_TO", "character_id": character_id, "target": level + 1})

static func _raise_skills(members: Array[String], target: Dictionary, actions: Array, blocked: Dictionary) -> void:
	var top := maxi(int(target.normal), maxi(int(target.passive), int(target.ultimate)))
	for step in range(2, top + 1):
		for character_id in members:
			for slot in ["normal", "passive", "ultimate"]:
				var key := "%s:%s" % [character_id, slot]
				var goal := mini(step, int(target[slot]))
				if blocked.has(key) or not SkillUpgradeService.supports_upgrade(character_id, slot):
					continue
				while int(AppState.profile.roster[character_id].skills[slot]) < goal:
					var upgraded := SkillUpgradeService.upgrade(character_id, slot)
					if not upgraded.ok:
						blocked[key] = str(upgraded.error)
						break
					actions.append({"kind": "SKILL", "character_id": character_id, "slot": slot})

static func _raise_weapons(members: Array[String], target: Dictionary, actions: Array, blocked: Dictionary) -> void:
	var goal := int(target.weapon_level)
	for character_id in members:
		var weapon_id := str(AppState.profile.roster[character_id].get("equipped_weapon_id", ""))
		if weapon_id.is_empty() or blocked.has(weapon_id) or not AppState.profile.get("weapons", {}).has(weapon_id):
			continue
		var weapon: Dictionary = AppState.profile.weapons[weapon_id]
		while int(weapon.level) < goal:
			if int(weapon.level) >= int(WEAPON_CAPS[clampi(int(weapon.tier), 1, 6) - 1]):
				var tier_up := WeaponUpgradeService.tier_up(weapon_id)
				if not tier_up.ok:
					blocked[weapon_id] = "TIER:" + str(tier_up.error)
					break
				actions.append({"kind": "WEAPON_TIER", "weapon_id": weapon_id})
				continue
			var chip := _weapon_chip_toward(weapon_id, goal)
			if chip.is_empty():
				blocked[weapon_id] = "INSUFFICIENT_MATERIALS"
				break
			var used := WeaponUpgradeService.use_material(weapon_id, chip, 1)
			if not used.ok:
				blocked[weapon_id] = str(used.error)
				break
			actions.append({"kind": "WEAPON_LEVEL", "weapon_id": weapon_id, "material_id": chip})

## The smallest chip that reaches the goal level, else the largest chip that
## still fits under the tier cap, so large chips are not spent on small gaps.
static func _weapon_chip_toward(weapon_id: String, goal_level: int) -> String:
	var state: Dictionary = AppState.profile.weapons[weapon_id]
	var curve: Array = DataRegistry.list_of("weapon_level_curve")
	var cap := int(WEAPON_CAPS[clampi(int(state.tier), 1, 6) - 1])
	var to_cap := -int(state.get("xp", 0))
	var to_goal := -int(state.get("xp", 0))
	for level in range(int(state.level), cap):
		to_cap += int(curve[level - 1].xp_to_next)
		if level < goal_level: to_goal += int(curve[level - 1].xp_to_next)
	var covering := ""
	var largest := ""
	for material_id in ["WEAPON_CHIP_S", "WEAPON_CHIP_M", "WEAPON_CHIP_L", "WEAPON_CHIP_XL"]:
		if AppState.inventory_count(material_id) <= 0:
			continue
		var value := int(WeaponUpgradeService.MATERIAL_XP[material_id])
		if value - to_cap >= WeaponUpgradeService.CAP_SURPLUS_TOLERANCE:
			continue
		largest = material_id
		if covering.is_empty() and value >= to_goal:
			covering = material_id
	return covering if not covering.is_empty() else largest

## What the party still needs to reach `target` from the live state. Character
## and weapon EXP count as TRAINING_XP / WEAPON_XP, and a stored note surplus
## counts as already paid.
static func _remaining_to_profile(members: Array[String], target: Dictionary) -> Dictionary:
	var need: Dictionary = {}
	var character_curve: Array = DataRegistry.list_of("character_level_curve")
	var weapon_curve: Array = DataRegistry.list_of("weapon_level_curve")
	var counted_weapons: Dictionary = {}
	for character_id in members:
		var state: Dictionary = AppState.profile.roster[character_id]
		var xp := -int(state.get("xp", 0)) - int(state.get("training_xp_reserve", 0))
		for level in range(int(state.level), int(target.level)):
			xp += int(character_curve[level - 1].xp_to_next)
			_add_cost(need, {"CREDIT": int(character_curve[level - 1].credit_cost)})
		if int(state.level) < int(target.level) and xp > 0:
			_add_cost(need, {"TRAINING_XP": xp})
		for step in range(int(state.breakthrough) + 1, int(target.breakthrough) + 1):
			_add_cost(need, DataRegistry.list_of("breakthroughs")[step].get("cost", {}))
		for slot in ["normal", "passive", "ultimate"]:
			if not SkillUpgradeService.supports_upgrade(character_id, slot):
				continue
			var kind := "ULTIMATE" if slot == "ultimate" else "NORMAL_OR_PASSIVE"
			for row in DataRegistry.list_of("skill_upgrade_costs"):
				if str(row.skill_type) == kind and int(row.target_level) > int(state.skills[slot]) and int(row.target_level) <= int(target[slot]):
					_add_cost(need, row.cost)
		var weapon_id := str(state.get("equipped_weapon_id", ""))
		if weapon_id.is_empty() or counted_weapons.has(weapon_id) or not AppState.profile.get("weapons", {}).has(weapon_id):
			continue
		counted_weapons[weapon_id] = true
		var weapon: Dictionary = AppState.profile.weapons[weapon_id]
		var weapon_xp := -int(weapon.get("xp", 0))
		for level in range(int(weapon.level), int(target.weapon_level)):
			weapon_xp += int(weapon_curve[level - 1].xp_to_next)
		if int(weapon.level) < int(target.weapon_level) and weapon_xp > 0:
			_add_cost(need, {"WEAPON_XP": weapon_xp})
		for row in DataRegistry.list_of("weapon_tier_costs"):
			if int(row.from_tier) >= int(weapon.tier) and int(row.from_tier) < int(target.weapon_tier):
				_add_cost(need, row.cost)
	return need

## Items still missing after the plan, with EXP pooled across note sizes.
static func _shortages(need: Dictionary) -> Dictionary:
	var owned := {
		"TRAINING_XP": _pooled_xp(CharacterProgression.MATERIAL_XP),
		"WEAPON_XP": _pooled_xp(WeaponUpgradeService.MATERIAL_XP),
	}
	var output: Dictionary = {}
	for item_id in need:
		var have := int(owned.get(item_id, AppState.inventory_count(str(item_id))))
		if int(need[item_id]) > have:
			output[item_id] = int(need[item_id]) - have
	return output

static func _pooled_xp(values: Dictionary) -> int:
	var total := 0
	for item_id in values:
		total += AppState.inventory_count(str(item_id)) * int(values[item_id])
	return total

static func _add_cost(target: Dictionary, cost: Dictionary) -> void:
	for item_id in cost:
		target[item_id] = int(target.get(item_id, 0)) + int(cost[item_id])

static func _member_changes(members: Array[String], before: Dictionary, after: Dictionary, target: Dictionary) -> Array:
	var output: Array = []
	for character_id in members:
		var from_state: Dictionary = before.party.get(character_id, {})
		var to_state: Dictionary = after.party.get(character_id, {})
		var skills: Dictionary = to_state.get("skills", {})
		output.append({
			"character_id": character_id,
			"before": from_state,
			"after": to_state,
			"reached": int(to_state.get("level", 1)) >= int(target.level)
				and int(skills.get("normal", 1)) >= int(target.normal)
				and int(skills.get("passive", 1)) >= int(target.passive)
				and int(skills.get("ultimate", 1)) >= int(target.ultimate)
				and int(to_state.get("weapon", {}).get("level", target.weapon_level)) >= int(target.weapon_level),
		})
	return output

static func _normalized_action(source_action: Variant) -> Dictionary:
	if not source_action is Dictionary:
		return {}
	var action: Dictionary = source_action.duplicate(true)
	action.erase("result")
	return action

static func _action_identity(action: Dictionary) -> String:
	return "%s|%s|%s|%s|%s" % [str(action.get("kind", "")), str(action.get("character_id", "")), str(action.get("weapon_id", "")), str(action.get("slot", "")), str(action.get("material_id", ""))]

static func _action_sequences_match(planned: Array, executed: Array) -> bool:
	if planned.size() != executed.size():
		return false
	for index in planned.size():
		if _action_identity(_normalized_action(planned[index])) != _action_identity(_normalized_action(executed[index])):
			return false
	return true

static func _growth_snapshot(party_ids: Array = []) -> Dictionary:
	var roster: Dictionary = {}
	for character_id_value in (party_ids if not party_ids.is_empty() else AppState.get_party()):
		var character_id := str(character_id_value)
		var character_state: Dictionary = AppState.profile.get("roster", {}).get(character_id, {})
		var weapon_id := str(character_state.get("equipped_weapon_id", ""))
		roster[character_id] = {
			"level": int(character_state.get("level", 1)),
			"xp": int(character_state.get("xp", 0)),
			"breakthrough": int(character_state.get("breakthrough", 0)),
			"skills": character_state.get("skills", {}).duplicate(true),
			"weapon_id": weapon_id,
			"weapon": AppState.profile.get("weapons", {}).get(weapon_id, {}).duplicate(true),
		}
	return {"inventory": AppState.profile.get("inventory", {}).duplicate(true), "party": roster}

static func _batch_accounting(before: Dictionary, after: Dictionary, planned_count: int, successful_count: int, rejected_count: int) -> Dictionary:
	var before_inventory: Dictionary = before.get("inventory", {})
	var after_inventory: Dictionary = after.get("inventory", {})
	var item_ids: Array = before_inventory.keys()
	for item_id in after_inventory.keys():
		if not item_ids.has(item_id):
			item_ids.append(item_id)
	item_ids.sort_custom(func(left, right): return str(left) < str(right))
	var inventory_delta: Dictionary = {}
	for item_id_value in item_ids:
		var item_id := str(item_id_value)
		var delta := int(after_inventory.get(item_id, 0)) - int(before_inventory.get(item_id, 0))
		if delta != 0:
			inventory_delta[item_id] = delta
	return {
		"planned": planned_count,
		"executed": successful_count,
		"successful": successful_count,
		"rejected": rejected_count,
		"inventory_delta": inventory_delta,
		"credit_delta": int(inventory_delta.get("CREDIT", 0)),
		"before": before.duplicate(true),
		"after": after.duplicate(true),
	}

static func _can_breakthrough(character_id: String) -> bool:
	var state: Dictionary = AppState.profile.get("roster", {}).get(character_id, {})
	if state.is_empty():
		return false
	var breakthrough := int(state.get("breakthrough", 0))
	if breakthrough >= BREAK_CAPS.size() - 1:
		return false
	if int(state.get("level", 1)) < int(BREAK_CAPS[breakthrough]):
		return false
	return AppState.can_pay(BreakthroughService.next_cost(character_id))

static func _characters_by_level(party_ids: Array) -> Array:
	var output: Array = []
	for character_id_value in party_ids:
		var character_id := str(character_id_value)
		var state: Dictionary = AppState.profile.get("roster", {}).get(character_id, {})
		if state.is_empty():
			continue
		var cap := mini(int(AppState.profile.get("account", {}).get("level", 1)), int(BREAK_CAPS[clampi(int(state.get("breakthrough", 0)), 0, 5)]))
		if int(state.get("level", 1)) < cap:
			output.append(character_id)
	output.sort_custom(func(left, right):
		var left_level := int(AppState.profile.roster[str(left)].get("level", 1))
		var right_level := int(AppState.profile.roster[str(right)].get("level", 1))
		return left_level < right_level or (left_level == right_level and str(left) < str(right))
	)
	return output

static func _weapons_by_level(party_ids: Array) -> Array:
	var output: Array = []
	for character_id_value in party_ids:
		var weapon_id := str(AppState.profile.get("roster", {}).get(str(character_id_value), {}).get("equipped_weapon_id", ""))
		var state: Dictionary = AppState.profile.get("weapons", {}).get(weapon_id, {})
		if weapon_id.is_empty() or state.is_empty() or output.has(weapon_id):
			continue
		var tier := clampi(int(state.get("tier", 1)), 1, 6)
		if int(state.get("level", 1)) < int(WEAPON_CAPS[tier - 1]):
			output.append(weapon_id)
	output.sort_custom(func(left, right):
		var left_level := int(AppState.profile.weapons[str(left)].get("level", 1))
		var right_level := int(AppState.profile.weapons[str(right)].get("level", 1))
		return left_level < right_level or (left_level == right_level and str(left) < str(right))
	)
	return output
