extends Node

## A fresh-profile Chapter 1 walk. Rewards, first-clear state, affordability,
## character levelling, skills and weapons all use the same runtime services as
## the game; this is intentionally not a spreadsheet approximation.

const PARTY_IDS := ["CHR001", "CHR002", "CHR003", "CHR005", "CHR008"]
const TRAINING_MATERIALS := ["TRAINING_NOTE_XL", "TRAINING_NOTE_L", "TRAINING_NOTE_M", "TRAINING_NOTE_S"]
const WEAPON_MATERIALS := ["WEAPON_CHIP_XL", "WEAPON_CHIP_L", "WEAPON_CHIP_M", "WEAPON_CHIP_S"]

func _ready() -> void:
	# This is a headless-only test scene.  Enter synchronously so its startup
	# marker is observable even when no idle frame is scheduled by the runner.
	_run()

func _run() -> void:
	_write_execution_state("BOOT", "")
	AppState.new_game()
	AppState.profile.active_party = 3
	var stages: Array = DataRegistry.list_of("stages").filter(func(value): return str(value.mode) == "NORMAL")
	stages.sort_custom(func(a, b): return int(a.stage_number) < int(b.stage_number))
	var rows: Array = []
	var all_cleared := true
	for index in stages.size():
		var stage: Dictionary = stages[index]
		_write_execution_state("BATTLE_START", str(stage.id))
		var before := AppState.profile.duplicate(true)
		var result := _battle(stage, 1515000 + index)
		var first := false
		var rewards: Dictionary = {}
		if bool(result.victory):
			first = AppState.record_stage_clear(str(stage.id), 3)
			rewards = RewardService.resolve(str(stage.id), 1, 1515000 + index, first)
			AccountProgression.grant_stage_xp(int(stage.stamina_cost), 20 if first else 0)
		else:
			all_cleared = false
		var after_reward := AppState.profile.duplicate(true)
		var growth_before := GrowthAffordabilityAnalyzer.analyze(before, after_reward)
		var applied_growth := _apply_available_growth()
		rows.append({
			"stage_id": stage.id,
			"battle": {"victory": result.victory, "reason": result.reason, "time": result.time, "survivors": result.survivors, "seed": result.seed},
			"first_clear": first,
			"rewards": rewards,
			"newly_affordable": growth_before.get("newly_affordable", []),
			"growth_summary": growth_before.get("summary", {}),
			"applied_growth": applied_growth,
			"account": AppState.profile.account.duplicate(true),
			"party": _party_progress(),
			"inventory": AppState.profile.inventory.duplicate(true),
		})
		print("R15_PROGRESSION_STAGE %s victory=%s growth_actions=%d" % [stage.id, str(result.victory), applied_growth.size()])
		# Persist a checkpoint after every completed stage.  This makes a failed or
		# interrupted long run auditable instead of leaving only a stale report.
		_write_checkpoint(rows, false)
		_write_execution_state("STAGE_COMPLETE", str(stage.id))
		if not bool(result.victory): break
	var report := {
		"schema_version": 1,
		"simulation": "fresh profile; BattleSimulation + RewardService + Growth services",
		"completed_normal_route": all_cleared and rows.size() == 10,
		"stages_completed": rows.size(),
		"rows": rows,
		"final_account": AppState.profile.account.duplicate(true),
		"final_party": _party_progress(),
		"final_inventory": AppState.profile.inventory.duplicate(true),
	}
	var report_dir := ProjectSettings.globalize_path("res://").path_join("../reports/r15").simplify_path()
	DirAccess.make_dir_recursive_absolute(report_dir)
	var output := FileAccess.open(report_dir.path_join("R15_PROGRESSION_SIMULATION.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	print("R15_PROGRESSION_COMPLETE stages=%d cleared=%s" % [rows.size(), str(report.completed_normal_route)])
	_write_execution_state("COMPLETE", "")
	get_tree().quit(0 if bool(report.completed_normal_route) else 1)

func _battle(stage: Dictionary, seed: int) -> Dictionary:
	var sim := BattleSimulation.new()
	sim.auto_enabled = true
	sim.setup(_party_snapshot(), stage, seed, DataRegistry.data, {"retain_event_log": false, "retain_event_hash": false})
	while not sim.state.ended and sim.state.tick < int(float(stage.time_limit) * 30.0) + 5:
		sim.tick()
		# A 30-tick heartbeat keeps this full-simulation test observable without
		# changing its outcome or simulation rate.
		if sim.state.tick % 30 == 0:
			_write_heartbeat(str(stage.id), sim.state.tick, int(float(stage.time_limit) * 30.0))
	return sim.result_snapshot()

func _party_snapshot() -> Array:
	var output: Array = []
	for character_id in PARTY_IDS:
		var definition := DataRegistry.character(character_id).duplicate(true)
		var state: Dictionary = AppState.profile.roster[character_id].duplicate(true)
		state.weapon_state = AppState.profile.weapons.get(str(state.get("equipped_weapon_id", "")), {}).duplicate(true)
		definition.progress = state
		output.append(definition)
	return output

func _apply_available_growth() -> Array:
	var actions: Array = []
	# Consume the actual earned notes through CharacterProgression, always
	# selecting the currently lowest-level eligible member.  Earlier R15 work
	# only consumed M notes, leaving the real L/XL reward inventory unused and
	# producing an artificial N07 progression failure.
	var training_actions := 0
	while training_actions < 64:
		var character_id := _lowest_level_character_with_training()
		if character_id.is_empty(): break
		var material_id := _training_material_that_fits(character_id)
		if material_id.is_empty(): break
		var level_result := CharacterProgression.use_material(character_id, material_id, 1)
		if not level_result.ok: break
		actions.append({"kind": "LEVEL", "character_id": character_id, "material_id": material_id, "result": level_result.value})
		training_actions += 1
	if training_actions >= 64:
		push_error("R15 progression training material loop safety limit reached")
	for character_id in PARTY_IDS:
		var breakthrough := BreakthroughService.upgrade(character_id)
		if breakthrough.ok: actions.append({"kind": "BREAKTHROUGH", "character_id": character_id, "result": breakthrough.value})
	for character_id in PARTY_IDS:
		for slot in ["normal", "passive", "ultimate"]:
			var skill := SkillUpgradeService.upgrade(character_id, slot)
			if skill.ok: actions.append({"kind": "SKILL", "character_id": character_id, "slot": slot, "result": skill.value})
	var weapon_actions := 0
	while weapon_actions < 64:
		var weapon_id := _lowest_level_weapon_with_chip()
		if weapon_id.is_empty(): break
		var chip_id := _weapon_chip_that_fits(weapon_id)
		if chip_id.is_empty(): break
		var weapon := WeaponUpgradeService.use_material(weapon_id, chip_id, 1)
		if not weapon.ok: break
		actions.append({"kind": "WEAPON_LEVEL", "weapon_id": weapon_id, "material_id": chip_id, "result": weapon.value})
		weapon_actions += 1
	if weapon_actions >= 64:
		push_error("R15 progression weapon material loop safety limit reached")
	for character_id in PARTY_IDS:
		var weapon_id := str(AppState.profile.roster[character_id].get("equipped_weapon_id", ""))
		var tier := WeaponUpgradeService.tier_up(weapon_id)
		if tier.ok: actions.append({"kind": "WEAPON_TIER", "weapon_id": weapon_id, "result": tier.value})
	return actions

func _highest_available(materials: Array) -> String:
	for material_id in materials:
		if AppState.inventory_count(str(material_id)) > 0: return str(material_id)
	return ""

func _training_material_that_fits(character_id: String) -> String:
	for material_id in TRAINING_MATERIALS:
		if AppState.inventory_count(str(material_id)) <= 0:
			continue
		var preview := CharacterProgression.preview(character_id, str(material_id), 1)
		if int(preview.get("unused_xp", 0)) != 0:
			continue
		if AppState.inventory_count("CREDIT") >= int(preview.get("credit_cost", 0)):
			return str(material_id)
	return ""

func _weapon_chip_that_fits(weapon_id: String) -> String:
	for chip_id in WEAPON_MATERIALS:
		if AppState.inventory_count(str(chip_id)) <= 0:
			continue
		var preview := WeaponUpgradeService.preview(weapon_id, str(chip_id), 1)
		if preview.ok and int(preview.value.get("unused_xp", 0)) == 0:
			return str(chip_id)
	return ""

func _lowest_level_character() -> String:
	var candidate := ""
	var candidate_level := 999
	for character_id in PARTY_IDS:
		var state: Dictionary = AppState.profile.roster[character_id]
		var cap := min(int(AppState.profile.account.level), [20, 40, 60, 80, 90, 100][clampi(int(state.breakthrough), 0, 5)])
		if int(state.level) >= cap: continue
		if int(state.level) < candidate_level:
			candidate = character_id
			candidate_level = int(state.level)
	return candidate

func _lowest_level_character_with_training() -> String:
	var candidates: Array = []
	for character_id in PARTY_IDS:
		var state: Dictionary = AppState.profile.roster[character_id]
		var cap := min(int(AppState.profile.account.level), [20, 40, 60, 80, 90, 100][clampi(int(state.breakthrough), 0, 5)])
		if int(state.level) < cap:
			candidates.append(character_id)
	candidates.sort_custom(func(left, right): return int(AppState.profile.roster[left].level) < int(AppState.profile.roster[right].level))
	for character_id in candidates:
		if not _training_material_that_fits(str(character_id)).is_empty():
			return str(character_id)
	return ""

func _lowest_level_equipped_weapon() -> String:
	var candidate := ""
	var candidate_level := 999
	for character_id in PARTY_IDS:
		var weapon_id := str(AppState.profile.roster[character_id].get("equipped_weapon_id", ""))
		var state: Dictionary = AppState.profile.weapons.get(weapon_id, {})
		if state.is_empty() or int(state.level) >= 60: continue
		var tier_cap := [10, 20, 30, 40, 50, 60][clampi(int(state.tier) - 1, 0, 5)]
		if int(state.level) >= tier_cap: continue
		if int(state.level) < candidate_level:
			candidate = weapon_id
			candidate_level = int(state.level)
	return candidate

func _lowest_level_weapon_with_chip() -> String:
	var candidates: Array = []
	for character_id in PARTY_IDS:
		var weapon_id := str(AppState.profile.roster[character_id].get("equipped_weapon_id", ""))
		var state: Dictionary = AppState.profile.weapons.get(weapon_id, {})
		if state.is_empty():
			continue
		var tier_cap := [10, 20, 30, 40, 50, 60][clampi(int(state.tier) - 1, 0, 5)]
		if int(state.level) < tier_cap and not candidates.has(weapon_id):
			candidates.append(weapon_id)
	candidates.sort_custom(func(left, right): return int(AppState.profile.weapons[left].level) < int(AppState.profile.weapons[right].level))
	for weapon_id in candidates:
		if not _weapon_chip_that_fits(str(weapon_id)).is_empty():
			return str(weapon_id)
	return ""

func _party_progress() -> Dictionary:
	var output: Dictionary = {}
	for character_id in PARTY_IDS:
		var state: Dictionary = AppState.profile.roster[character_id]
		output[character_id] = {
			"level": state.level,
			"xp": state.xp,
			"breakthrough": state.breakthrough,
			"skills": state.skills.duplicate(true),
			"weapon": AppState.profile.weapons.get(str(state.equipped_weapon_id), {}).duplicate(true),
		}
	return output

func _write_checkpoint(rows: Array, completed: bool) -> void:
	var report_dir := ProjectSettings.globalize_path("res://").path_join("../reports/r15").simplify_path()
	DirAccess.make_dir_recursive_absolute(report_dir)
	var checkpoint := {
		"schema_version": 1,
		"simulation": "fresh profile; BattleSimulation + RewardService + Growth services",
		"completed_normal_route": completed,
		"stages_completed": rows.size(),
		"rows": rows,
		"final_account": AppState.profile.account.duplicate(true),
		"final_party": _party_progress(),
		"final_inventory": AppState.profile.inventory.duplicate(true),
	}
	var output := FileAccess.open(report_dir.path_join("R15_PROGRESSION_CHECKPOINT.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(checkpoint, "  "))

func _write_heartbeat(stage_id: String, tick: int, tick_limit: int) -> void:
	var report_dir := ProjectSettings.globalize_path("res://").path_join("../reports/r15").simplify_path()
	DirAccess.make_dir_recursive_absolute(report_dir)
	var output := FileAccess.open(report_dir.path_join("R15_PROGRESSION_HEARTBEAT.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({
		"stage_id": stage_id,
		"tick": tick,
		"tick_limit": tick_limit,
		"wall_time_msec": Time.get_ticks_msec(),
	}, "  "))

func _write_execution_state(phase: String, stage_id: String) -> void:
	var report_dir := ProjectSettings.globalize_path("res://").path_join("../reports/r15").simplify_path()
	DirAccess.make_dir_recursive_absolute(report_dir)
	var output := FileAccess.open(report_dir.path_join("R15_PROGRESSION_EXECUTION_STATE.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({
		"phase": phase,
		"stage_id": stage_id,
		"wall_time_msec": Time.get_ticks_msec(),
	}, "  "))
