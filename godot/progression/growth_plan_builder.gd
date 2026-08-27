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
		if preview.ok and int(preview.value.get("unused_xp", 0)) == 0:
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

## Creates the exact bounded action sequence against an isolated copy of the
## current profile.  This deliberately invokes the same service APIs as the
## eventual transaction, but restores the live profile before returning.  A
## player can therefore see the target sequence before anything is spent, and
## the executor can prove that the preview and actual sequence matched.
static func preview_recommended_batch(party_ids: Array, max_actions := 12) -> Dictionary:
	var live_profile: Dictionary = AppState.profile
	AppState.profile = live_profile.duplicate(true)
	var preview := _plan_recommended_batch(party_ids, clampi(max_actions, 1, 12))
	AppState.profile = live_profile
	return preview

## Executes a supplied sequence only through the production growth services.
## It stops at the first rejected service result and never attempts a later
## action.  This is used by the player-facing recommended batch and gives
## headless tests a way to verify partial accounting without test-only profile
## mutation hooks.
static func execute_action_sequence(action_sequence: Array, max_actions := 12) -> Dictionary:
	var limit := clampi(max_actions, 1, 12)
	var planned_actions: Array = []
	for source_action in action_sequence.slice(0, limit):
		var action := _normalized_action(source_action)
		if not action.is_empty():
			planned_actions.append(action)
	var before := _growth_snapshot()
	var actions: Array = []
	var failure := ""
	var failed_action: Dictionary = {}
	for action_value in planned_actions:
		var action: Dictionary = action_value
		var outcome := execute(action)
		if not outcome.ok:
			failure = str(outcome.error)
			failed_action = action.duplicate(true)
			break
		var record := action.duplicate(true)
		record["result"] = outcome.value
		actions.append(record)
	var after := _growth_snapshot()
	return {
		"ok": failure.is_empty(),
		"planned_actions": planned_actions,
		"actions": actions,
		"error": failure,
		"failed_action": failed_action,
		"accounting": _batch_accounting(before, after, planned_actions.size(), actions.size(), 0 if failure.is_empty() else 1),
	}

## Executes a bounded sequence through the same production progression
## services used by the individual growth controls.  This is intentionally not
## a profile mutator: every entry still validates materials, caps and credits
## in CharacterProgression / BreakthroughService / SkillUpgradeService /
## WeaponUpgradeService.  The UI uses a small batch so players can review the
## resulting party state between presses instead of silently spending an
## entire inventory.
static func execute_recommended_batch(party_ids: Array, max_actions := 12) -> Dictionary:
	# UI policy: a player-facing batch never exceeds twelve transactions.  The
	# progression runner can still request one action at a time, while a button
	# press stays inspectable and cannot silently consume the entire inventory.
	var limit := clampi(max_actions, 1, 12)
	var preview := preview_recommended_batch(party_ids, limit)
	if not bool(preview.get("ok", false)):
		return preview
	var execution := execute_action_sequence(preview.get("actions", []), limit)
	execution["preview_actions"] = preview.get("actions", []).duplicate(true)
	execution["preview_exhausted"] = bool(preview.get("exhausted", false))
	execution["preview_matches_execution"] = _action_sequences_match(execution.get("planned_actions", []), execution.get("actions", []))
	execution["exhausted"] = bool(execution.get("ok", false)) and next_legal_action(party_ids).is_empty()
	execution["has_more"] = not bool(execution.get("exhausted", false))
	return execution

static func _plan_recommended_batch(party_ids: Array, limit: int) -> Dictionary:
	var before := _growth_snapshot()
	var actions: Array = []
	var failure := ""
	var failed_action: Dictionary = {}
	for _step in range(limit):
		var action := next_legal_action(party_ids)
		if action.is_empty():
			break
		var outcome := execute(action)
		if not outcome.ok:
			failure = str(outcome.error)
			failed_action = action.duplicate(true)
			break
		var record := action.duplicate(true)
		record["result"] = outcome.value
		actions.append(record)
	var after := _growth_snapshot()
	return {
		"ok": failure.is_empty(),
		"actions": actions,
		"error": failure,
		"failed_action": failed_action,
		"exhausted": failure.is_empty() and next_legal_action(party_ids).is_empty(),
		"accounting": _batch_accounting(before, after, actions.size(), actions.size(), 0 if failure.is_empty() else 1),
	}

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

static func _growth_snapshot() -> Dictionary:
	var roster: Dictionary = {}
	for character_id_value in AppState.get_party():
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
