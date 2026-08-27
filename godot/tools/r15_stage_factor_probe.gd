extends Node

## A bounded, data-only tuning probe for the cells that missed R15's target
## curve.  The candidate factor is applied to a deep copy of StageDef, so this
## tool cannot alter shipping data.  It still executes the shipping
## BattleSimulation and the same manual-ultimate policy used by R15's matrix.

const BalanceHarnessScript := preload("res://tools/balance_hardening_matrix.gd")
const PARTY_IDS := ["CHR001", "CHR002", "CHR003", "CHR005", "CHR008"]
const FACTORS_BY_STAGE := {
	"CH01-N05": [2.955, 2.96, 2.97],
	"CH01-N09": [2.16, 2.17, 2.18, 2.19, 2.20],
	"CH01-N10": [1.50, 1.52, 1.54, 1.55, 1.56],
}
const STAGE_INDEX := {"CH01-N05": 4, "CH01-N09": 8, "CH01-N10": 9}

var runs_per_cell := 30
var harness: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		runs_per_cell = clampi(int(args[0]), 10, 200)
	call_deferred("_run")

func _run() -> void:
	harness = BalanceHarnessScript.new()
	var started_ms := Time.get_ticks_msec()
	var rows: Array = []
	for stage_id in FACTORS_BY_STAGE.keys():
		var stage: Dictionary = DataRegistry.stage(str(stage_id))
		for factor in FACTORS_BY_STAGE[stage_id]:
			for control in ["AUTO", "SCRIPTED_MANUAL_ULTIMATE"]:
				var row := _run_candidate(stage, float(factor), str(control), rows.size())
				rows.append(row)
				print("R15_FACTOR %s factor=%.3f %s wins=%d/%d mean=%.3f" % [stage_id, factor, control, row.wins, row.runs, row.mean_time])
	var report := {
		"schema_version": 1,
		"simulation": "BattleSimulation fixed 30 Hz",
		"runs_per_cell": runs_per_cell,
		"rows": rows,
		"elapsed_wall_seconds": float(Time.get_ticks_msec() - started_ms) / 1000.0,
	}
	var report_dir := ProjectSettings.globalize_path("res://").path_join("../reports/r15").simplify_path()
	DirAccess.make_dir_recursive_absolute(report_dir)
	var file := FileAccess.open(report_dir.path_join("R15_STAGE_FACTOR_PROBE.json"), FileAccess.WRITE)
	if file == null:
		printerr("Could not write R15 factor probe report")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	if harness != null:
		harness.free()
		harness = null
	print("R15_FACTOR_PROBE_COMPLETE rows=%d seconds=%.3f" % [rows.size(), report.elapsed_wall_seconds])
	get_tree().quit(0)

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

func _run_candidate(stage: Dictionary, factor: float, control: String, cell_index: int) -> Dictionary:
	var wins := 0
	var times: Array[float] = []
	var timeouts := 0
	for run_index in range(runs_per_cell):
		var candidate: Dictionary = stage.duplicate(true)
		candidate.post_cap_scale = factor
		var sim := BattleSimulation.new()
		sim.auto_enabled = control == "AUTO"
		# Match r15_balance_matrix.gd exactly so a factor result is directly
		# comparable to the final 200-seed acceptance matrix.
		var control_index := 0 if control == "AUTO" else 1
		var seed := 1500000 + int(STAGE_INDEX.get(str(stage.id), cell_index)) * 100000 + 10000 + control_index * 5000 + run_index
		sim.setup(_party_snapshot(_profile(int(stage.recommended_level))), candidate, seed, DataRegistry.data, {"retain_event_log": false})
		while not sim.state.ended and sim.state.tick < int(float(stage.time_limit) * 30.0) + 5:
			if control == "SCRIPTED_MANUAL_ULTIMATE" and sim.state.tick % 15 == 0:
				harness._request_manual_ultimate(sim)
			sim.tick()
		var result := sim.result_snapshot()
		if bool(result.victory): wins += 1
		if str(result.reason) == "TIMEOUT": timeouts += 1
		times.append(float(result.time))
	times.sort()
	return {
		"stage_id": stage.id,
		"factor": factor,
		"control": control,
		"runs": runs_per_cell,
		"wins": wins,
		"win_rate": float(wins) / runs_per_cell,
		"mean_time": harness._mean(times),
		"p10_time": harness._percentile(times, 0.10),
		"p50_time": harness._percentile(times, 0.50),
		"p90_time": harness._percentile(times, 0.90),
		"timeout_rate": float(timeouts) / runs_per_cell,
	}
