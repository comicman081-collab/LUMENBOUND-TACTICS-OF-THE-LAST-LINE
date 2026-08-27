extends Node

## Reproducible, paired H05 probe.  Every policy receives the exact same seed
## and shipping StageDef/character data.  This is diagnostic-only and never
## writes balance values back to data_source or DataRegistry.

const PARTY_IDS := ["CHR001", "CHR002", "CHR003", "CHR005", "CHR008"]
const STAGE_ID := "CH01-H05"
const BASE_SEED := 5150000
const POLICY_AUTO := "AUTO"
const POLICY_MANUAL_AOE_2 := "SCRIPTED_MANUAL_ULTIMATE_AOE_2"
const POLICY_MANUAL_AOE_3 := "SCRIPTED_MANUAL_ULTIMATE_AOE_3"
const POLICIES := [POLICY_AUTO, POLICY_MANUAL_AOE_2, POLICY_MANUAL_AOE_3]

var runs := 200
var output_name := "R15_H05_PAIRED_ULTIMATE_POLICY_PROBE.json"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		runs = clampi(int(args[0]), 1, 1000)
	if args.size() >= 2:
		output_name = str(args[1]).get_file()
	call_deferred("_run")

func _run() -> void:
	var started_ms := Time.get_ticks_msec()
	var stage: Dictionary = DataRegistry.stage(STAGE_ID)
	var profile := _profile(int(stage.recommended_level))
	var party := _party_snapshot(profile)
	var results_by_policy := {}
	for policy in POLICIES:
		results_by_policy[policy] = []

	for run_index in range(runs):
		var seed := BASE_SEED + run_index
		for policy in POLICIES:
			results_by_policy[policy].append(_simulate(stage, party, seed, str(policy)))

	var summaries := {}
	for policy in POLICIES:
		summaries[policy] = _summarize(results_by_policy[policy])
		var summary: Dictionary = summaries[policy]
		print("H05_PAIRED %s wins=%d/%d mean=%.3f ult_mean=%.3f" % [
			policy, summary.wins, summary.runs, summary.mean_time, summary.mean_total_ultimate_uses
		])

	var paired := {
		"auto_vs_manual_aoe_2": _pair_summary(results_by_policy[POLICY_AUTO], results_by_policy[POLICY_MANUAL_AOE_2], POLICY_AUTO, POLICY_MANUAL_AOE_2),
		"auto_vs_manual_aoe_3": _pair_summary(results_by_policy[POLICY_AUTO], results_by_policy[POLICY_MANUAL_AOE_3], POLICY_AUTO, POLICY_MANUAL_AOE_3),
		"manual_aoe_2_vs_3": _pair_summary(results_by_policy[POLICY_MANUAL_AOE_2], results_by_policy[POLICY_MANUAL_AOE_3], POLICY_MANUAL_AOE_2, POLICY_MANUAL_AOE_3),
	}
	var seed_rows: Array = []
	for run_index in range(runs):
		seed_rows.append({
			"seed": BASE_SEED + run_index,
			POLICY_AUTO: results_by_policy[POLICY_AUTO][run_index],
			POLICY_MANUAL_AOE_2: results_by_policy[POLICY_MANUAL_AOE_2][run_index],
			POLICY_MANUAL_AOE_3: results_by_policy[POLICY_MANUAL_AOE_3][run_index],
		})

	var report := {
		"schema_version": 1,
		"engine": Engine.get_version_info().string,
		"simulation": "shipping BattleSimulation fixed 30 Hz",
		"stage_id": STAGE_ID,
		"profile": "RECOMMENDED",
		"profile_spec": profile,
		"party_ids": PARTY_IDS,
		"base_seed": BASE_SEED,
		"runs_per_policy": runs,
		"paired_seed_count": runs,
		"shipping_data_mutated": false,
		"policies": {
			POLICY_AUTO: {"auto_enabled": true},
			POLICY_MANUAL_AOE_2: {"auto_enabled": false, "manual_poll_ticks": 15, "aoe_enemy_threshold": 2},
			POLICY_MANUAL_AOE_3: {"auto_enabled": false, "manual_poll_ticks": 15, "aoe_enemy_threshold": 3},
		},
		"summaries": summaries,
		"paired_comparisons": paired,
		"seed_results": seed_rows,
		"elapsed_wall_seconds": float(Time.get_ticks_msec() - started_ms) / 1000.0,
	}
	var report_dir := ProjectSettings.globalize_path("res://").path_join("../reports/r15").simplify_path()
	DirAccess.make_dir_recursive_absolute(report_dir)
	var path := report_dir.path_join(output_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write H05 paired policy report: ", path)
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	print("H05_PAIRED_PROBE_COMPLETE simulations=%d seconds=%.3f path=%s" % [runs * POLICIES.size(), report.elapsed_wall_seconds, path])
	get_tree().quit(0)

func _simulate(stage: Dictionary, party: Array, seed: int, policy: String) -> Dictionary:
	var sim := BattleSimulation.new()
	sim.auto_enabled = policy == POLICY_AUTO
	sim.setup(party, stage, seed, DataRegistry.data, {"retain_event_log": false})
	var aoe_threshold := 2 if policy == POLICY_MANUAL_AOE_2 else 3
	while not sim.state.ended and sim.state.tick < int(float(stage.time_limit) * 30.0) + 5:
		if policy != POLICY_AUTO and sim.state.tick % 15 == 0:
			_request_manual_ultimate(sim, aoe_threshold)
		sim.tick()
	var result := sim.result_snapshot()
	var total_ultimate_uses := 0
	for count in result.ultimate_uses_by_character.values():
		total_ultimate_uses += int(count)
	return {
		"victory": bool(result.victory),
		"reason": str(result.reason),
		"time": float(result.time),
		"survivors": int(result.survivors),
		"total_ultimate_uses": total_ultimate_uses,
		"ultimate_uses_by_character": result.ultimate_uses_by_character,
	}

func _request_manual_ultimate(sim: BattleSimulation, aoe_enemy_threshold: int) -> void:
	var enemies := sim.alive_enemies()
	if enemies.is_empty(): return
	var lowest := TargetResolver.lowest_hp(sim.state.party)
	var alive_allies := sim.state.party.filter(func(unit): return UnitState.alive(unit))
	var average_hp := 1.0
	if not alive_allies.is_empty():
		average_hp = float(alive_allies.reduce(func(total, unit): return float(total) + UnitState.hp_ratio(unit), 0.0)) / alive_allies.size()
	var incoming := float(enemies.reduce(func(total, enemy): return float(total) + float(enemy.stats.get("ATK", 0)), 0.0))
	var target: Dictionary = enemies[0]
	for enemy in enemies:
		if str(enemy.rank) == "BOSS": target = enemy
		elif str(target.rank) == "NORMAL" and str(enemy.rank) == "ELITE": target = enemy
	var candidates: Array = []
	for unit in sim.state.party:
		if not UnitState.alive(unit): continue
		var skill := DataRegistry.skill(str(unit.ultimate_skill_id))
		if not SkillRuntime.can_use_ultimate(unit, skill, sim.state.tactical_gauge): continue
		var effect := str(skill.effect)
		var score := -1.0
		if effect == "SHIELD" and (UnitState.hp_ratio(lowest) < .82 or (UnitState.hp_ratio(lowest) < .95 and float(lowest.get("shield", 0)) < incoming * .8)): score = 1200.0
		elif effect == "HEAL" and (UnitState.hp_ratio(lowest) < .72 or average_hp < .82): score = 1100.0 + (1.0 - UnitState.hp_ratio(lowest)) * 100.0
		elif effect == "AOE_DAMAGE" and enemies.size() >= aoe_enemy_threshold: score = 700.0 + enemies.size()
		elif effect == "DEBUFF" and str(target.rank) in ["BOSS", "ELITE"]: score = 650.0
		elif effect == "DAMAGE" and str(target.rank) in ["BOSS", "ELITE"]: score = 600.0
		elif effect == "BUFF" and sim.state.time_limit - sim.state.time_elapsed > 10.0: score = 300.0
		elif effect == "DAMAGE" and sim.state.tactical_gauge > 8.0: score = 100.0
		if score >= 0.0: candidates.append({"unit": unit, "score": score})
	if candidates.is_empty(): return
	candidates.sort_custom(func(a, b): return float(a.score) > float(b.score))
	var chosen: Dictionary = candidates[0].unit
	sim.request_ultimate(str(chosen.uid), str(target.uid))

func _summarize(rows: Array) -> Dictionary:
	var wins := 0
	var timeouts := 0
	var time_total := 0.0
	var survivor_total := 0
	var ultimate_total := 0
	var ultimate_by_character := {}
	var times: Array[float] = []
	for row in rows:
		if bool(row.victory): wins += 1
		if str(row.reason) == "TIMEOUT": timeouts += 1
		time_total += float(row.time)
		times.append(float(row.time))
		survivor_total += int(row.survivors)
		ultimate_total += int(row.total_ultimate_uses)
		for character_id in row.ultimate_uses_by_character:
			ultimate_by_character[character_id] = int(ultimate_by_character.get(character_id, 0)) + int(row.ultimate_uses_by_character[character_id])
	times.sort()
	return {
		"runs": rows.size(),
		"wins": wins,
		"win_rate": float(wins) / rows.size(),
		"mean_time": time_total / rows.size(),
		"p10_time": _percentile(times, .10),
		"p50_time": _percentile(times, .50),
		"p90_time": _percentile(times, .90),
		"timeout_rate": float(timeouts) / rows.size(),
		"mean_survivors": float(survivor_total) / rows.size(),
		"total_ultimate_uses": ultimate_total,
		"mean_total_ultimate_uses": float(ultimate_total) / rows.size(),
		"ultimate_uses_by_character": ultimate_by_character,
	}

func _pair_summary(left_rows: Array, right_rows: Array, left_policy: String, right_policy: String) -> Dictionary:
	var both_win := 0
	var left_only_win := 0
	var right_only_win := 0
	var both_loss := 0
	var time_delta_total := 0.0
	var both_win_time_delta_total := 0.0
	var both_win_count := 0
	for index in range(mini(left_rows.size(), right_rows.size())):
		var left: Dictionary = left_rows[index]
		var right: Dictionary = right_rows[index]
		var left_win := bool(left.victory)
		var right_win := bool(right.victory)
		if left_win and right_win:
			both_win += 1
			both_win_count += 1
			both_win_time_delta_total += float(right.time) - float(left.time)
		elif left_win:
			left_only_win += 1
		elif right_win:
			right_only_win += 1
		else:
			both_loss += 1
		time_delta_total += float(right.time) - float(left.time)
	return {
		"left_policy": left_policy,
		"right_policy": right_policy,
		"paired_seeds": mini(left_rows.size(), right_rows.size()),
		"both_win": both_win,
		"left_only_win": left_only_win,
		"right_only_win": right_only_win,
		"both_loss": both_loss,
		"net_win_difference_right_minus_left": right_only_win - left_only_win,
		"win_rate_delta_right_minus_left": float(right_only_win - left_only_win) / mini(left_rows.size(), right_rows.size()),
		"mean_paired_time_delta_right_minus_left": time_delta_total / mini(left_rows.size(), right_rows.size()),
		"mean_time_delta_right_minus_left_when_both_win": both_win_time_delta_total / both_win_count if both_win_count > 0 else 0.0,
	}

func _profile(recommended_level: int) -> Dictionary:
	return {"level": recommended_level, "normal": 2, "passive": 2, "ultimate": 1, "weapon_level": recommended_level}

func _party_snapshot(profile: Dictionary) -> Array:
	var output: Array = []
	for character_id in PARTY_IDS:
		var definition := DataRegistry.character(character_id).duplicate(true)
		var weapon_id := ""
		for weapon in DataRegistry.list_of("weapons"):
			if str(weapon.weapon_class) == str(definition.weapon_class):
				weapon_id = str(weapon.id)
				break
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

func _breakthrough_for_level(level: int) -> int:
	if level <= 20: return 0
	if level <= 40: return 1
	if level <= 60: return 2
	if level <= 80: return 3
	if level <= 90: return 4
	return 5

func _percentile(sorted_values: Array[float], percentile: float) -> float:
	if sorted_values.is_empty(): return 0.0
	return sorted_values[clampi(int(floor((sorted_values.size() - 1) * percentile)), 0, sorted_values.size() - 1)]
