extends Node

const STAGES := ["CH01-N01", "CH01-N05", "CH01-N10", "CH01-H01", "CH01-H05"]
const PROFILES := ["A_INITIAL", "B_RECOMMENDED", "C_RECOMMENDED_UPGRADED", "D_MINUS_15", "E_PLUS_15"]
const CONTROLS := ["AUTO", "SCRIPTED_MANUAL_ULTIMATE"]
const PARTY_IDS := ["CHR001", "CHR002", "CHR003", "CHR005", "CHR008"]
const DEFAULT_RUNS := 200
const MANUAL_POLICY_ID := "HEALTH_GATED_AOE2_CADENCE30"
const MANUAL_DECISION_TICKS := 30

var runs_per_cell := DEFAULT_RUNS
var output_name := "before_matrix.json"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		runs_per_cell = clampi(int(args[0]), 1, 1000)
	if args.size() >= 2:
		output_name = str(args[1]).get_file()
	call_deferred("_run")

func _run() -> void:
	var started_ms := Time.get_ticks_msec()
	var cells: Array = []
	for stage_id in STAGES:
		var stage := DataRegistry.stage(stage_id)
		for profile_id in PROFILES:
			for control in CONTROLS:
				var cell := _run_cell(stage, profile_id, control)
				cells.append(cell)
				print("BALANCE_CELL %s %s %s wins=%d/%d mean=%.3f" % [stage_id, profile_id, control, cell.wins, cell.runs, cell.mean_time])
	var report := {
		"schema_version": 1,
		"engine": Engine.get_version_info().string,
		"simulation": "BattleSimulation fixed 30 Hz",
		"runs_per_cell": runs_per_cell,
		"total_runs": cells.size() * runs_per_cell,
		"party_ids": PARTY_IDS,
		"manual_policy": {"id": MANUAL_POLICY_ID, "decision_ticks": MANUAL_DECISION_TICKS},
		"cells": cells,
		"elapsed_wall_seconds": float(Time.get_ticks_msec() - started_ms) / 1000.0,
	}
	var report_dir := ProjectSettings.globalize_path("res://").path_join("../reports/balance_hardening").simplify_path()
	DirAccess.make_dir_recursive_absolute(report_dir)
	var path := report_dir.path_join(output_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write balance report: ", path)
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	print("BALANCE_MATRIX_COMPLETE total_runs=%d seconds=%.3f path=%s" % [report.total_runs, report.elapsed_wall_seconds, path])
	get_tree().quit(0)

func _run_cell(stage: Dictionary, profile_id: String, control: String) -> Dictionary:
	var times: Array[float] = []
	var run_rows: Array = []
	var wins := 0
	var survivor_total := 0
	var lowest_hp_total := 0.0
	var timeout_count := 0
	var damage_totals: Dictionary = {}
	var healing_totals: Dictionary = {}
	var ultimate_totals: Dictionary = {}
	var death_causes: Dictionary = {}
	var profile := _profile_spec(profile_id, int(stage.recommended_level))
	var party := _party_snapshot(profile)
	for run_index in range(runs_per_cell):
		var seed := 810000 + STAGES.find(str(stage.id)) * 100000 + PROFILES.find(profile_id) * 10000 + run_index
		var sim := BattleSimulation.new()
		sim.auto_enabled = control == "AUTO"
		sim.setup(party, stage, seed, DataRegistry.data, {"retain_event_log": false})
		while not sim.state.ended and sim.state.tick < int(float(stage.time_limit) * 30.0) + 5:
			if control == "SCRIPTED_MANUAL_ULTIMATE" and sim.state.tick % MANUAL_DECISION_TICKS == 0:
				_request_manual_ultimate(sim)
			sim.tick()
		var result := sim.result_snapshot()
		var lowest_hp := _lowest_hp_ratio(sim.state.party)
		if bool(result.victory): wins += 1
		if str(result.reason) == "TIMEOUT": timeout_count += 1
		times.append(float(result.time))
		survivor_total += int(result.survivors)
		lowest_hp_total += lowest_hp
		_merge_counts(damage_totals, result.damage)
		_merge_counts(healing_totals, result.healing)
		_merge_counts(ultimate_totals, result.ultimate_uses_by_character)
		for death in result.deaths:
			var cause := str(death.get("source", "UNKNOWN"))
			death_causes[cause] = int(death_causes.get(cause, 0)) + 1
		run_rows.append({
			"seed": seed,
			"victory": result.victory,
			"reason": result.reason,
			"time": result.time,
			"survivors": result.survivors,
			"lowest_hp_ratio": lowest_hp,
			"damage": result.damage,
			"healing": result.healing,
			"ultimate_uses": result.ultimate_uses_by_character,
			"deaths": result.deaths,
		})
	times.sort()
	var mean_time := _mean(times)
	return {
		"stage_id": stage.id,
		"profile": profile_id,
		"profile_spec": profile,
		"control": control,
		"runs": runs_per_cell,
		"wins": wins,
		"win_rate": float(wins) / runs_per_cell,
		"mean_time": mean_time,
		"p10_time": _percentile(times, 0.10),
		"p50_time": _percentile(times, 0.50),
		"p90_time": _percentile(times, 0.90),
		"mean_survivors": float(survivor_total) / runs_per_cell,
		"mean_lowest_hp_ratio": lowest_hp_total / runs_per_cell,
		"timeout_rate": float(timeout_count) / runs_per_cell,
		"damage_totals": damage_totals,
		"healing_totals": healing_totals,
		"ultimate_totals": ultimate_totals,
		"death_causes": death_causes,
		"run_results": run_rows,
	}

func _profile_spec(profile_id: String, recommended_level: int) -> Dictionary:
	match profile_id:
		"A_INITIAL":
			return {"level": 1, "normal": 1, "passive": 1, "ultimate": 1, "weapon_level": 1}
		"B_RECOMMENDED":
			return {"level": recommended_level, "normal": 2, "passive": 2, "ultimate": 1, "weapon_level": recommended_level}
		"C_RECOMMENDED_UPGRADED":
			return {"level": recommended_level, "normal": 4, "passive": 4, "ultimate": 2, "weapon_level": mini(60, recommended_level + 10)}
		"D_MINUS_15":
			var lower := maxi(1, int(floor(recommended_level * 0.85)))
			return {"level": lower, "normal": 1, "passive": 1, "ultimate": 1, "weapon_level": lower}
		_:
			var higher := mini(100, int(ceil(recommended_level * 1.15)))
			return {"level": higher, "normal": 3, "passive": 3, "ultimate": 2, "weapon_level": mini(60, higher + 5)}

func _party_snapshot(profile: Dictionary) -> Array:
	var output: Array = []
	for character_id in PARTY_IDS:
		var definition := DataRegistry.character(character_id).duplicate(true)
		var weapon_id := _weapon_for_class(str(definition.weapon_class))
		var weapon_level := int(profile.weapon_level)
		definition.progress = {
			"level": int(profile.level),
			"breakthrough": _breakthrough_for_level(int(profile.level)),
			"skills": {"normal": int(profile.normal), "passive": int(profile.passive), "ultimate": int(profile.ultimate)},
			"equipped_weapon_id": weapon_id,
			"weapon_state": {"owned": true, "level": weapon_level, "xp": 0, "tier": clampi(int(ceil(weapon_level / 10.0)), 1, 6)},
		}
		output.append(definition)
	return output

func _weapon_for_class(weapon_class: String) -> String:
	for weapon in DataRegistry.list_of("weapons"):
		if str(weapon.weapon_class) == weapon_class:
			return str(weapon.id)
	return ""

func _breakthrough_for_level(level: int) -> int:
	if level <= 20: return 0
	if level <= 40: return 1
	if level <= 60: return 2
	if level <= 80: return 3
	if level <= 90: return 4
	return 5

func _request_manual_ultimate(sim: BattleSimulation) -> void:
	var enemies := sim.alive_enemies()
	if enemies.is_empty():
		return
	var alive_allies := sim.state.party.filter(func(unit): return UnitState.alive(unit))
	if alive_allies.is_empty():
		return
	var lowest := TargetResolver.lowest_hp(alive_allies)
	var lowest_hp := UnitState.hp_ratio(lowest)
	var average_hp := float(alive_allies.reduce(func(total, unit): return float(total) + UnitState.hp_ratio(unit), 0.0)) / alive_allies.size()
	var incoming := float(enemies.reduce(func(total, enemy): return float(total) + float(enemy.stats.get("ATK", 0)), 0.0))
	var lowest_shield := float(lowest.get("shield", 0))
	var shield_sufficient := lowest_shield >= incoming and average_hp >= .82
	var safe_for_two_target_aoe := (lowest_hp >= .88 and average_hp >= .92) or shield_sufficient
	var strong_target: Dictionary = {}
	for enemy in enemies:
		if str(enemy.rank) == "BOSS":
			strong_target = enemy
			break
		if strong_target.is_empty() and str(enemy.rank) == "ELITE":
			strong_target = enemy
	var target: Dictionary = strong_target if not strong_target.is_empty() else enemies[0]
	var candidates: Array = []
	for unit in alive_allies:
		var skill := DataRegistry.skill(str(unit.ultimate_skill_id))
		if not SkillRuntime.can_use_ultimate(unit, skill, sim.state.tactical_gauge):
			continue
		var effect := str(skill.effect)
		var score := -1.0
		# Selected by the 4,000-run same-seed R15 policy probe.  Defense is always
		# evaluated before offense; a two-target AOE is permitted only while the
		# party is healthy or the weakest ally is adequately shielded.  Against a
		# boss/elite, deliberate single-target/debuff use outranks area damage.
		if effect == "SHIELD" and (lowest_hp < .82 or (lowest_hp < .95 and lowest_shield < incoming * .8)):
			score = 1400.0 + (1.0 - lowest_hp) * 100.0
		elif effect == "HEAL" and (lowest_hp < .72 or average_hp < .82):
			score = 1300.0 + (1.0 - lowest_hp) * 100.0
		elif effect in ["DAMAGE", "DEBUFF"] and not strong_target.is_empty():
			score = 950.0 if effect == "DEBUFF" else 900.0
		elif effect == "AOE_DAMAGE" and enemies.size() >= 3:
			score = 760.0 + enemies.size()
		elif effect == "AOE_DAMAGE" and enemies.size() == 2 and safe_for_two_target_aoe:
			score = 720.0
		elif effect == "BUFF" and sim.state.time_limit - sim.state.time_elapsed > 10.0 and alive_allies.size() >= 3:
			score = 300.0
		elif effect == "DAMAGE" and sim.state.tactical_gauge > 8.0:
			score = 120.0
		if score >= 0.0:
			candidates.append({"unit": unit, "score": score, "effect": effect})
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b):
		if float(a.score) == float(b.score):
			return str(a.unit.uid) < str(b.unit.uid)
		return float(a.score) > float(b.score)
	)
	var chosen: Dictionary = candidates[0]
	var target_id := str(target.uid) if str(chosen.effect) in ["DAMAGE", "DEBUFF", "AOE_DAMAGE"] else ""
	sim.request_ultimate(str(chosen.unit.uid), target_id)

func _lowest_hp_ratio(party: Array) -> float:
	var lowest := 1.0
	for unit in party:
		lowest = minf(lowest, UnitState.hp_ratio(unit) if UnitState.alive(unit) else 0.0)
	return lowest

func _merge_counts(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		target[key] = int(target.get(key, 0)) + int(source[key])

func _mean(values: Array[float]) -> float:
	if values.is_empty(): return 0.0
	return float(values.reduce(func(total, value): return float(total) + value, 0.0)) / values.size()

func _percentile(sorted_values: Array[float], percentile: float) -> float:
	if sorted_values.is_empty(): return 0.0
	return sorted_values[clampi(int(floor((sorted_values.size() - 1) * percentile)), 0, sorted_values.size() - 1)]
