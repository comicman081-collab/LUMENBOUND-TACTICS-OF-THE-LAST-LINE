extends Node

const STAGES := ["CH01-H05"]
const FACTORS_BY_STAGE := {
	"CH01-H05": [1.385, 1.390, 1.395, 1.3975],
}
const PARTY_IDS := ["CHR001", "CHR002", "CHR003", "CHR005", "CHR008"]
var runs := 50

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): runs = clampi(int(args[0]), 10, 200)
	call_deferred("_run")

func _run() -> void:
	var rows: Array = []
	for stage_id in STAGES:
		var stage := DataRegistry.stage(stage_id)
		var party := _party(int(stage.recommended_level))
		for factor in FACTORS_BY_STAGE[stage_id]:
			for control in ["AUTO", "MANUAL"]:
				var wins := 0
				var times: Array[float] = []
				for i in range(runs):
					var sim := BattleSimulation.new()
					sim.auto_enabled = control == "AUTO"
					var candidate_stage: Dictionary = stage.duplicate(true)
					candidate_stage.post_cap_scale = factor
					var seed := 810000 + 4 * 100000 + 1 * 10000 + (0 if control == "AUTO" else 5000) + i
					sim.setup(party, candidate_stage, seed, DataRegistry.data, {"retain_event_log": false})
					while not sim.state.ended:
						if control == "MANUAL" and sim.state.tick % 15 == 0: _manual(sim)
						sim.tick()
					var result := sim.result_snapshot()
					if result.victory: wins += 1
					times.append(float(result.time))
				var mean := float(times.reduce(func(total, value): return float(total) + value, 0.0)) / runs
				var row := {"stage_id": stage_id, "factor": factor, "control": control, "runs": runs, "wins": wins, "win_rate": float(wins) / runs, "mean_time": mean}
				rows.append(row)
				print("PROBE %s factor=%.2f %s wins=%d/%d mean=%.2f" % [stage_id, factor, control, wins, runs, mean])
	var directory := ProjectSettings.globalize_path("res://").path_join("../reports/balance_hardening").simplify_path()
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("factor_probe_h05_fine.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"runs_per_cell": runs, "rows": rows}, "  "))
	get_tree().quit(0)

func _party(level: int) -> Array:
	var output: Array = []
	for character_id in PARTY_IDS:
		var definition := DataRegistry.character(character_id).duplicate(true)
		var weapon_id := ""
		for weapon in DataRegistry.list_of("weapons"):
			if str(weapon.weapon_class) == str(definition.weapon_class): weapon_id = str(weapon.id); break
		definition.progress = {"level": level, "breakthrough": 0 if level <= 20 else 1, "skills": {"normal": 2, "passive": 2, "ultimate": 1}, "equipped_weapon_id": weapon_id, "weapon_state": {"owned": true, "level": level, "xp": 0, "tier": clampi(int(ceil(level / 10.0)), 1, 6)}}
		output.append(definition)
	return output

func _manual(sim: BattleSimulation) -> void:
	var enemies := sim.alive_enemies()
	if enemies.is_empty(): return
	var target: Dictionary = enemies[0]
	for enemy in enemies:
		if str(enemy.rank) in ["BOSS", "ELITE"]: target = enemy
	var lowest := TargetResolver.lowest_hp(sim.state.party)
	var alive_allies := sim.state.party.filter(func(unit): return UnitState.alive(unit))
	var average_hp := 1.0
	if not alive_allies.is_empty(): average_hp = float(alive_allies.reduce(func(total, unit): return float(total) + UnitState.hp_ratio(unit), 0.0)) / alive_allies.size()
	var incoming := float(enemies.reduce(func(total, enemy): return float(total) + float(enemy.stats.get("ATK", 0)), 0.0))
	var best: Dictionary = {}
	var best_score := -1.0
	for unit in sim.state.party:
		if not UnitState.alive(unit): continue
		var skill := DataRegistry.skill(str(unit.ultimate_skill_id))
		if not SkillRuntime.can_use_ultimate(unit, skill, sim.state.tactical_gauge): continue
		var effect := str(skill.effect)
		var score := -1.0
		if effect == "SHIELD" and (UnitState.hp_ratio(lowest) < .85 or (UnitState.hp_ratio(lowest) < .97 and float(lowest.get("shield", 0)) < incoming * .9)): score = 1200.0
		elif effect == "HEAL" and (UnitState.hp_ratio(lowest) < .58 or average_hp < .72): score = 1100.0 + (1.0 - UnitState.hp_ratio(lowest)) * 100.0
		elif effect == "AOE_DAMAGE" and enemies.size() >= 3: score = 700.0 + enemies.size()
		elif effect == "DEBUFF" and str(target.rank) in ["BOSS", "ELITE"]: score = 650.0
		elif effect == "DAMAGE" and str(target.rank) in ["BOSS", "ELITE"]: score = 600.0
		elif effect == "BUFF" and sim.state.time_limit - sim.state.time_elapsed > 10.0: score = 300.0
		elif effect == "DAMAGE" and sim.state.tactical_gauge > 8.0: score = 100.0
		if score > best_score: best_score = score; best = unit
	if not best.is_empty(): sim.request_ultimate(str(best.uid), str(target.uid))
