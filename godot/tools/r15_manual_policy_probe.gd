extends Node

## Diagnostic-only paired policy probe.  It reuses the shipping
## BattleSimulation and immutable DataRegistry definitions.  Every policy for
## a stage receives the same 200 seeds; this file never writes shipping data.

const BalanceHarnessScript := preload("res://tools/balance_hardening_matrix.gd")
const PARTY_IDS := ["CHR001", "CHR002", "CHR003", "CHR005", "CHR008"]
const STAGE_IDS := ["CH01-N07", "CH01-N10", "CH01-H01", "CH01-H04", "CH01-H05"]
const BASE_SEED := 6150000
const POLICY_AUTO := "AUTO"
const POLICY_CURRENT_M3 := "CURRENT_M3"
const POLICY_HEALTH_GATED_AOE2 := "HEALTH_GATED_AOE2"
const POLICY_HEALTH_GATED_AOE2_CADENCE30 := "HEALTH_GATED_AOE2_CADENCE30"
const POLICIES := [
	POLICY_AUTO,
	POLICY_CURRENT_M3,
	POLICY_HEALTH_GATED_AOE2,
	POLICY_HEALTH_GATED_AOE2_CADENCE30,
]

var runs := 200
var output_name := "R15_MANUAL_POLICY_PAIRED_PROBE.json"
var harness: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		runs = clampi(int(args[0]), 1, 1000)
	if args.size() >= 2:
		output_name = str(args[1]).get_file()
	call_deferred("_run")

func _run() -> void:
	harness = BalanceHarnessScript.new()
	var started_ms := Time.get_ticks_msec()
	var stage_reports: Array = []
	for stage_index in range(STAGE_IDS.size()):
		var stage_id: String = STAGE_IDS[stage_index]
		var stage: Dictionary = DataRegistry.stage(stage_id)
		var profile := _profile(int(stage.recommended_level))
		var party := _party_snapshot(profile)
		var rows_by_policy: Dictionary = {}
		for policy in POLICIES:
			rows_by_policy[policy] = []
		for run_index in range(runs):
			var seed := BASE_SEED + stage_index * 10000 + run_index
			for policy in POLICIES:
				rows_by_policy[policy].append(_simulate(stage, party, seed, str(policy)))
		var summaries: Dictionary = {}
		var comparisons: Dictionary = {}
		for policy in POLICIES:
			summaries[policy] = _summarize(rows_by_policy[policy])
			if policy != POLICY_AUTO:
				comparisons[policy] = _pair_summary(rows_by_policy[POLICY_AUTO], rows_by_policy[policy], POLICY_AUTO, str(policy))
		var seed_rows: Array = []
		for run_index in range(runs):
			var seed_row := {"seed": BASE_SEED + stage_index * 10000 + run_index}
			for policy in POLICIES:
				seed_row[policy] = rows_by_policy[policy][run_index]
			seed_rows.append(seed_row)
		stage_reports.append({
			"stage_id": stage_id,
			"profile": "RECOMMENDED",
			"profile_spec": profile,
			"summaries": summaries,
			"paired_vs_auto": comparisons,
			"seed_results": seed_rows,
		})
		print("R15_POLICY_PROBE %s AUTO=%d M3=%d HG2=%d HG2_30=%d / %d" % [
			stage_id,
			int(summaries[POLICY_AUTO].wins),
			int(summaries[POLICY_CURRENT_M3].wins),
			int(summaries[POLICY_HEALTH_GATED_AOE2].wins),
			int(summaries[POLICY_HEALTH_GATED_AOE2_CADENCE30].wins),
			runs,
		])
	var verdicts := _policy_verdicts(stage_reports)
	var report := {
		"schema_version": 1,
		"engine": Engine.get_version_info().string,
		"simulation": "shipping BattleSimulation fixed 30 Hz",
		"shipping_data_mutated": false,
		"stages": STAGE_IDS,
		"party_ids": PARTY_IDS,
		"profile": "RECOMMENDED",
		"base_seed": BASE_SEED,
		"runs_per_policy_stage": runs,
		"paired_seed_count_per_policy_stage": runs,
		"policies": {
			POLICY_AUTO: {"auto_enabled": true, "decision_ticks": 30},
			POLICY_CURRENT_M3: {"auto_enabled": false, "manual_poll_ticks": 15, "aoe_enemy_threshold": 3, "source": "balance_hardening_matrix.gd"},
			POLICY_HEALTH_GATED_AOE2: {"auto_enabled": false, "manual_poll_ticks": 15, "health_gated_two_target_aoe": true},
			POLICY_HEALTH_GATED_AOE2_CADENCE30: {"auto_enabled": false, "manual_poll_ticks": 30, "health_gated_two_target_aoe": true},
		},
		"health_gate": {
			"defense_priority": "SHIELD then HEAL before offense",
			"two_target_aoe": "lowest_hp >= 0.88 and average_hp >= 0.92, or lowest shield >= expected incoming and average_hp >= 0.82",
			"strong_enemy_priority": "single/debuff before AOE when a boss or elite is present",
		},
		"noninferiority_margin": -0.025,
		"policy_verdicts": verdicts,
		"stage_results": stage_reports,
		"elapsed_wall_seconds": float(Time.get_ticks_msec() - started_ms) / 1000.0,
	}
	var report_dir := ProjectSettings.globalize_path("res://").path_join("../reports/r15").simplify_path()
	DirAccess.make_dir_recursive_absolute(report_dir)
	var json_path := report_dir.path_join(output_name)
	var markdown_path := report_dir.path_join("%s.md" % output_name.get_basename())
	if not _write_text(json_path, JSON.stringify(report, "  ")) or not _write_text(markdown_path, _markdown_report(report)):
		printerr("Could not write R15 manual policy probe reports")
		_finish(2)
		return
	print("R15_MANUAL_POLICY_PROBE_COMPLETE simulations=%d seconds=%.3f path=%s" % [STAGE_IDS.size() * POLICIES.size() * runs, report.elapsed_wall_seconds, json_path])
	_finish(0)

func _simulate(stage: Dictionary, party: Array, seed: int, policy: String) -> Dictionary:
	var sim := BattleSimulation.new()
	sim.auto_enabled = policy == POLICY_AUTO
	sim.setup(party, stage, seed, DataRegistry.data, {"retain_event_log": false})
	var decision_ticks := 30 if policy == POLICY_HEALTH_GATED_AOE2_CADENCE30 else 15
	while not sim.state.ended and sim.state.tick < int(float(stage.time_limit) * 30.0) + 5:
		if policy != POLICY_AUTO and sim.state.tick % decision_ticks == 0:
			if policy == POLICY_CURRENT_M3:
				harness._request_manual_ultimate(sim)
			else:
				_request_health_gated_ultimate(sim)
		sim.tick()
	var result := sim.result_snapshot()
	var lowest_hp := float(harness._lowest_hp_ratio(sim.state.party))
	var total_ultimate_uses := 0
	for count in result.ultimate_uses_by_character.values():
		total_ultimate_uses += int(count)
	return {
		"seed": seed,
		"victory": bool(result.victory),
		"reason": str(result.reason),
		"time": float(result.time),
		"survivors": int(result.survivors),
		"lowest_hp_ratio": lowest_hp,
		"total_ultimate_uses": total_ultimate_uses,
		"ultimate_uses_by_character": result.ultimate_uses_by_character,
	}

func _request_health_gated_ultimate(sim: BattleSimulation) -> void:
	var enemies := sim.alive_enemies()
	if enemies.is_empty():
		return
	var alive_allies := sim.state.party.filter(func(unit): return UnitState.alive(unit))
	if alive_allies.is_empty():
		return
	var lowest := TargetResolver.lowest_hp(alive_allies)
	var lowest_hp := UnitState.hp_ratio(lowest)
	var average_hp := float(alive_allies.reduce(func(total, unit): return float(total) + UnitState.hp_ratio(unit), 0.0)) / alive_allies.size()
	var expected_incoming := float(enemies.reduce(func(total, enemy): return float(total) + float(enemy.stats.get("ATK", 0)), 0.0))
	var lowest_shield := float(lowest.get("shield", 0))
	var shield_sufficient := lowest_shield >= expected_incoming and average_hp >= .82
	var safe_for_two_target_aoe := (lowest_hp >= .88 and average_hp >= .92) or shield_sufficient
	var strong_target: Dictionary = {}
	for enemy in enemies:
		if str(enemy.rank) == "BOSS":
			strong_target = enemy
			break
		if strong_target.is_empty() and str(enemy.rank) == "ELITE":
			strong_target = enemy
	var fallback_target: Dictionary = strong_target if not strong_target.is_empty() else enemies[0]
	var candidates: Array = []
	for unit in alive_allies:
		var skill := DataRegistry.skill(str(unit.ultimate_skill_id))
		if not SkillRuntime.can_use_ultimate(unit, skill, sim.state.tactical_gauge):
			continue
		var effect := str(skill.effect)
		var score := -1.0
		if effect == "SHIELD" and (lowest_hp < .82 or (lowest_hp < .95 and lowest_shield < expected_incoming * .8)):
			score = 1400.0 + (1.0 - lowest_hp) * 100.0
		elif effect == "HEAL" and (lowest_hp < .72 or average_hp < .82):
			score = 1300.0 + (1.0 - lowest_hp) * 100.0
		elif effect in ["DAMAGE", "DEBUFF"] and not strong_target.is_empty():
			# A boss/elite is a higher-value manual target than a two-target AOE.
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
	var target_id := str(fallback_target.uid) if str(chosen.effect) in ["DAMAGE", "DEBUFF", "AOE_DAMAGE"] else ""
	sim.request_ultimate(str(chosen.unit.uid), target_id)

func _summarize(rows: Array) -> Dictionary:
	var wins := 0
	var timeouts := 0
	var time_total := 0.0
	var survivor_total := 0
	var lowest_hp_total := 0.0
	var ultimate_total := 0
	var ultimate_by_character: Dictionary = {}
	var times: Array[float] = []
	for row_value in rows:
		var row: Dictionary = row_value
		if bool(row.victory): wins += 1
		if str(row.reason) == "TIMEOUT": timeouts += 1
		time_total += float(row.time)
		times.append(float(row.time))
		survivor_total += int(row.survivors)
		lowest_hp_total += float(row.lowest_hp_ratio)
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
		"mean_lowest_hp_ratio": lowest_hp_total / rows.size(),
		"total_ultimate_uses": ultimate_total,
		"mean_total_ultimate_uses": float(ultimate_total) / rows.size(),
		"ultimate_uses_by_character": ultimate_by_character,
	}

func _pair_summary(auto_rows: Array, candidate_rows: Array, left_policy: String, right_policy: String) -> Dictionary:
	var both_win := 0
	var auto_only_win := 0
	var candidate_only_win := 0
	var both_loss := 0
	var paired_time_delta_total := 0.0
	var both_win_time_delta_total := 0.0
	var both_win_count := 0
	for index in range(mini(auto_rows.size(), candidate_rows.size())):
		var auto_row: Dictionary = auto_rows[index]
		var candidate_row: Dictionary = candidate_rows[index]
		var auto_win := bool(auto_row.victory)
		var candidate_win := bool(candidate_row.victory)
		if auto_win and candidate_win:
			both_win += 1
			both_win_count += 1
			both_win_time_delta_total += float(candidate_row.time) - float(auto_row.time)
		elif auto_win:
			auto_only_win += 1
		elif candidate_win:
			candidate_only_win += 1
		else:
			both_loss += 1
		paired_time_delta_total += float(candidate_row.time) - float(auto_row.time)
	var pair_count := mini(auto_rows.size(), candidate_rows.size())
	return {
		"left_policy": left_policy,
		"right_policy": right_policy,
		"paired_seeds": pair_count,
		"both_win": both_win,
		"left_only_win": auto_only_win,
		"right_only_win": candidate_only_win,
		"both_loss": both_loss,
		"net_win_difference_right_minus_left": candidate_only_win - auto_only_win,
		"win_rate_delta_right_minus_left": float(candidate_only_win - auto_only_win) / pair_count,
		"mean_paired_time_delta_right_minus_left": paired_time_delta_total / pair_count,
		"mean_time_delta_right_minus_left_when_both_win": both_win_time_delta_total / both_win_count if both_win_count > 0 else 0.0,
	}

func _policy_verdicts(stage_reports: Array) -> Dictionary:
	var verdicts: Dictionary = {}
	for policy in POLICIES:
		if policy == POLICY_AUTO:
			continue
		var deltas: Array = []
		var noninferior_all := true
		var h05_rate := 0.0
		for stage_report_value in stage_reports:
			var stage_report: Dictionary = stage_report_value
			var delta := float(stage_report.paired_vs_auto[policy].win_rate_delta_right_minus_left)
			deltas.append(delta)
			if delta < -.025:
				noninferior_all = false
			if str(stage_report.stage_id) == "CH01-H05":
				h05_rate = float(stage_report.summaries[policy].win_rate)
		verdicts[policy] = {
			"noninferior_all_stages_at_margin": noninferior_all,
			"mean_win_rate_delta_vs_auto": float(deltas.reduce(func(total, value): return float(total) + value, 0.0)) / deltas.size(),
			"minimum_stage_delta_vs_auto": deltas.min(),
			"h05_win_rate": h05_rate,
			"h05_target_45_to_75": h05_rate >= .45 and h05_rate <= .75,
		}
	return verdicts

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

func _write_text(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file = null
	return true

func _markdown_report(report: Dictionary) -> String:
	var lines := PackedStringArray([
		"# R15 Same-seed Manual Ultimate Policy Probe",
		"",
		"Shipping `BattleSimulation`, StageDef, character and skill data were reused without mutation.",
		"Every policy used the same %d seeds per stage." % runs,
		"",
		"| Stage | Policy | Wins | Win rate | Mean time | Survivors | Delta vs AUTO |",
		"|---|---:|---:|---:|---:|---:|---:|",
	])
	for stage_report_value in report.stage_results:
		var stage_report: Dictionary = stage_report_value
		for policy in POLICIES:
			var summary: Dictionary = stage_report.summaries[policy]
			var delta := 0.0 if policy == POLICY_AUTO else float(stage_report.paired_vs_auto[policy].win_rate_delta_right_minus_left)
			lines.append("| %s | %s | %d/%d | %.1f%% | %.3fs | %.3f | %+.1fpp |" % [stage_report.stage_id, policy, summary.wins, summary.runs, float(summary.win_rate) * 100.0, summary.mean_time, summary.mean_survivors, delta * 100.0])
	lines.append("")
	lines.append("## Policy verdicts")
	lines.append("")
	for policy in report.policy_verdicts:
		var verdict: Dictionary = report.policy_verdicts[policy]
		lines.append("- **%s**: all-stage noninferior=%s; mean delta=%+.1fpp; minimum delta=%+.1fpp; H05=%.1f%% (target 45–75%%: %s)." % [policy, verdict.noninferior_all_stages_at_margin, float(verdict.mean_win_rate_delta_vs_auto) * 100.0, float(verdict.minimum_stage_delta_vs_auto) * 100.0, float(verdict.h05_win_rate) * 100.0, verdict.h05_target_45_to_75])
	lines.append("")
	lines.append("The probe is diagnostic evidence only; it does not alter shipping policy or balance data.")
	return "\n".join(lines) + "\n"

func _finish(exit_code: int) -> void:
	if harness != null:
		harness.free()
		harness = null
	get_tree().quit(exit_code)
