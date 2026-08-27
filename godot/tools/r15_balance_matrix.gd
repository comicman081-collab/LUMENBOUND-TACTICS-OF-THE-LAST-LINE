extends Node

## R15's Chapter 1 matrix deliberately reuses the shipping BattleSimulation
## and the established manual-ultimate policy.  It contains no approximate
## combat calculator and never writes balance numbers back into data.

const BalanceHarnessScript := preload("res://tools/balance_hardening_matrix.gd")
const PARTY_IDS := ["CHR001", "CHR002", "CHR003", "CHR005", "CHR008"]
const PROFILES := {
	"LOW": {"ratio": 0.875, "normal": 1, "passive": 1, "ultimate": 1, "weapon_bonus": 0},
	"RECOMMENDED": {"ratio": 1.0, "normal": 2, "passive": 2, "ultimate": 1, "weapon_bonus": 0},
	"HIGH": {"ratio": 1.15, "normal": 3, "passive": 3, "ultimate": 2, "weapon_bonus": 5},
}
const PROFILE_IDS := ["LOW", "RECOMMENDED", "HIGH"]
const CONTROLS := ["AUTO", "SCRIPTED_MANUAL_ULTIMATE"]

var runs_per_cell := 200
var output_name := "R15_CH01_BALANCE_MATRIX.json"
var max_cells := 0
var resume_enabled := false
var start_cell := 0
var harness: Node
var report_dir := ""
var output_path := ""
var checkpoint_path := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1: runs_per_cell = clampi(int(args[0]), 1, 1000)
	if args.size() >= 2: output_name = str(args[1]).get_file()
	if args.size() >= 3: max_cells = maxi(0, int(args[2]))
	if args.size() >= 4: resume_enabled = str(args[3]).to_lower() in ["1", "true", "resume"]
	if args.size() >= 5: start_cell = maxi(0, int(args[4]))
	call_deferred("_run")

func _run() -> void:
	harness = BalanceHarnessScript.new()
	var started_ms := Time.get_ticks_msec()
	report_dir = ProjectSettings.globalize_path("res://").path_join("../reports/r15").simplify_path()
	DirAccess.make_dir_recursive_absolute(report_dir)
	output_path = report_dir.path_join(output_name)
	checkpoint_path = report_dir.path_join("%s.checkpoint.json" % output_name.get_basename())
	var stages: Array = DataRegistry.list_of("stages").duplicate()
	stages.sort_custom(func(a, b):
		if str(a.mode) == str(b.mode): return int(a.stage_number) < int(b.stage_number)
		return str(a.mode) == "NORMAL"
	)
	var descriptors: Array = []
	for stage_index in stages.size():
		var stage: Dictionary = stages[stage_index]
		for profile_id in PROFILE_IDS:
			for control in CONTROLS:
				descriptors.append({"stage": stage, "stage_index": stage_index, "profile": str(profile_id), "control": str(control)})
	var cell_limit := descriptors.size() if max_cells == 0 else mini(max_cells, descriptors.size())
	var cells_by_key := _load_resume_cells(descriptors) if resume_enabled else {}
	# A fresh run invalidates any stale checkpoint before combat work begins.
	# This also makes an interruption before the first completed cell resumable
	# without accidentally importing cells from an older configuration.
	if not resume_enabled:
		if not _write_checkpoint([], float(Time.get_ticks_msec() - started_ms) / 1000.0):
			_finish_with_error("Could not initialize R15 balance checkpoint")
			return
	for cell_index in range(cell_limit):
		if cell_index < start_cell:
			continue
		var descriptor: Dictionary = descriptors[cell_index]
		var key := _cell_key(str(descriptor.stage.id), str(descriptor.profile), str(descriptor.control))
		if cells_by_key.has(key):
			print("R15_BALANCE_RESUME_SKIP cell=%d key=%s" % [cell_index, key])
			continue
		var cell := _run_cell(descriptor.stage, int(descriptor.stage_index), str(descriptor.profile), str(descriptor.control))
		cells_by_key[key] = cell
		var checkpoint_cells := _ordered_cells(descriptors, cell_limit, cells_by_key)
		if not _write_checkpoint(checkpoint_cells, float(Time.get_ticks_msec() - started_ms) / 1000.0):
			_finish_with_error("Could not write R15 balance checkpoint after cell %d" % cell_index)
			return
		print("R15_BALANCE cell=%d %s %s %s wins=%d/%d mean=%.3f" % [cell_index, descriptor.stage.id, descriptor.profile, descriptor.control, cell.wins, cell.runs, cell.mean_time])
	var cells := _ordered_cells(descriptors, cell_limit, cells_by_key)
	var report := _build_report(cells, float(Time.get_ticks_msec() - started_ms) / 1000.0)
	if not _atomic_write_json(output_path, report):
		_finish_with_error("Could not write R15 balance report: %s" % output_path)
		return
	if harness != null:
		harness.free()
		harness = null
	print("R15_BALANCE_MATRIX_COMPLETE total_runs=%d cells=%d/%d seconds=%.3f path=%s" % [report.total_runs, cells.size(), cell_limit, report.elapsed_wall_seconds, output_path])
	get_tree().quit(0)

func _build_report(cells: Array, elapsed_seconds: float) -> Dictionary:
	# Keep the established final schema intact.  Checkpoints use this same schema,
	# so a resumed run can merge completed cells without a conversion step.
	return {
		"schema_version": 1,
		"engine": Engine.get_version_info().string,
		"simulation": "BattleSimulation fixed 30 Hz",
		"runs_per_cell": runs_per_cell,
		"max_cells": max_cells,
		"total_runs": cells.size() * runs_per_cell,
		"party_ids": PARTY_IDS,
		"controls": CONTROLS,
		"profiles": PROFILES,
		"manual_policy": {"id": BalanceHarnessScript.MANUAL_POLICY_ID, "decision_ticks": BalanceHarnessScript.MANUAL_DECISION_TICKS},
		"cells": cells,
		"elapsed_wall_seconds": elapsed_seconds,
	}

func _cell_key(stage_id: String, profile_id: String, control: String) -> String:
	return "%s|%s|%s" % [stage_id, profile_id, control]

func _ordered_cells(descriptors: Array, cell_limit: int, cells_by_key: Dictionary) -> Array:
	var ordered: Array = []
	for cell_index in range(cell_limit):
		var descriptor: Dictionary = descriptors[cell_index]
		var key := _cell_key(str(descriptor.stage.id), str(descriptor.profile), str(descriptor.control))
		if cells_by_key.has(key):
			ordered.append(cells_by_key[key])
	return ordered

func _load_resume_cells(descriptors: Array) -> Dictionary:
	var source := _read_json_dictionary(checkpoint_path)
	if source.is_empty():
		source = _read_json_dictionary(output_path)
	var cells_by_key: Dictionary = {}
	if source.is_empty():
		print("R15_BALANCE_RESUME no compatible checkpoint; starting from requested cell %d" % start_cell)
		return cells_by_key
	if int(source.get("schema_version", -1)) != 1 or int(source.get("runs_per_cell", -1)) != runs_per_cell:
		printerr("R15_BALANCE_RESUME ignored incompatible checkpoint schema/runs_per_cell")
		return cells_by_key
	var checkpoint_policy: Dictionary = source.get("manual_policy", {})
	if str(checkpoint_policy.get("id", "")) != BalanceHarnessScript.MANUAL_POLICY_ID or int(checkpoint_policy.get("decision_ticks", 0)) != BalanceHarnessScript.MANUAL_DECISION_TICKS:
		printerr("R15_BALANCE_RESUME ignored checkpoint from a different manual policy")
		return cells_by_key
	var descriptors_by_key: Dictionary = {}
	for descriptor_value in descriptors:
		var descriptor: Dictionary = descriptor_value
		descriptors_by_key[_cell_key(str(descriptor.stage.id), str(descriptor.profile), str(descriptor.control))] = descriptor
	for value in source.get("cells", []):
		if not value is Dictionary:
			continue
		var cell: Dictionary = value
		if int(cell.get("runs", -1)) != runs_per_cell:
			continue
		var stage_id := str(cell.get("stage_id", ""))
		var profile_id := str(cell.get("profile", ""))
		var control := str(cell.get("control", ""))
		if stage_id.is_empty() or not profile_id in PROFILE_IDS or not control in CONTROLS:
			continue
		var key := _cell_key(stage_id, profile_id, control)
		if not descriptors_by_key.has(key):
			continue
		var descriptor: Dictionary = descriptors_by_key[key]
		if not _cell_has_expected_seeds(cell, int(descriptor.stage_index), profile_id):
			printerr("R15_BALANCE_RESUME rejected legacy/unpaired seed cell: %s" % key)
			continue
		cells_by_key[key] = cell
	print("R15_BALANCE_RESUME loaded_cells=%d checkpoint=%s" % [cells_by_key.size(), checkpoint_path])
	return cells_by_key

func _cell_has_expected_seeds(cell: Dictionary, stage_index: int, profile_id: String) -> bool:
	var run_results: Array = cell.get("run_results", [])
	if run_results.size() != runs_per_cell:
		return false
	for run_index in range(runs_per_cell):
		var row = run_results[run_index]
		if not row is Dictionary or int(row.get("seed", -1)) != _seed_for(stage_index, profile_id, run_index):
			return false
	return true

func _seed_for(stage_index: int, profile_id: String, run_index: int) -> int:
	return 1500000 + stage_index * 100000 + PROFILE_IDS.find(profile_id) * 10000 + run_index

func _write_checkpoint(cells: Array, elapsed_seconds: float) -> bool:
	return _atomic_write_json(checkpoint_path, _build_report(cells, elapsed_seconds))

func _read_json_dictionary(path: String) -> Dictionary:
	var candidates := [path, path + ".backup"]
	for candidate in candidates:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		file = null
		if parsed is Dictionary:
			return parsed
	return {}

func _atomic_write_json(path: String, payload: Dictionary) -> bool:
	var temporary := path + ".tmp"
	var backup := path + ".backup"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "  "))
	file.flush()
	file = null
	var verification_file := FileAccess.open(temporary, FileAccess.READ)
	if verification_file == null:
		return false
	var verified = JSON.parse_string(verification_file.get_as_text())
	verification_file = null
	if not verified is Dictionary:
		DirAccess.remove_absolute(temporary)
		return false
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(path):
		if DirAccess.rename_absolute(path, backup) != OK:
			DirAccess.remove_absolute(temporary)
			return false
	if DirAccess.rename_absolute(temporary, path) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, path)
		return false
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	return true

func _finish_with_error(message: String) -> void:
	printerr(message)
	if harness != null:
		harness.free()
		harness = null
	get_tree().quit(2)

func _profile_spec(profile_id: String, recommended_level: int) -> Dictionary:
	var base: Dictionary = PROFILES[profile_id]
	var level := clampi(int(round(float(recommended_level) * float(base.ratio))), 1, 100)
	var weapon_level := clampi(level + int(base.weapon_bonus), 1, 60)
	return {
		"level": level,
		"normal": int(base.normal),
		"passive": int(base.passive),
		"ultimate": int(base.ultimate),
		"weapon_level": weapon_level,
	}

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
		if str(weapon.weapon_class) == weapon_class: return str(weapon.id)
	return ""

func _breakthrough_for_level(level: int) -> int:
	if level <= 20: return 0
	if level <= 40: return 1
	if level <= 60: return 2
	if level <= 80: return 3
	if level <= 90: return 4
	return 5

func _run_cell(stage: Dictionary, stage_index: int, profile_id: String, control: String) -> Dictionary:
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
		# AUTO and scripted manual are paired on the same seed for a fair policy
		# comparison.  Control mode must never perturb the random sequence key.
		var seed := _seed_for(stage_index, profile_id, run_index)
		var sim := BattleSimulation.new()
		sim.auto_enabled = control == "AUTO"
		sim.setup(party, stage, seed, DataRegistry.data, {"retain_event_log": false})
		while not sim.state.ended and sim.state.tick < int(float(stage.time_limit) * 30.0) + 5:
			if control == "SCRIPTED_MANUAL_ULTIMATE" and sim.state.tick % BalanceHarnessScript.MANUAL_DECISION_TICKS == 0:
				harness._request_manual_ultimate(sim)
			sim.tick()
		var result := sim.result_snapshot()
		var lowest_hp: float = float(harness._lowest_hp_ratio(sim.state.party))
		if bool(result.victory): wins += 1
		if str(result.reason) == "TIMEOUT": timeout_count += 1
		times.append(float(result.time))
		survivor_total += int(result.survivors)
		lowest_hp_total += lowest_hp
		harness._merge_counts(damage_totals, result.damage)
		harness._merge_counts(healing_totals, result.healing)
		harness._merge_counts(ultimate_totals, result.ultimate_uses_by_character)
		for death in result.deaths:
			var cause := str(death.get("source", "UNKNOWN"))
			death_causes[cause] = int(death_causes.get(cause, 0)) + 1
		run_rows.append({"seed": seed, "victory": result.victory, "reason": result.reason, "time": result.time, "survivors": result.survivors, "lowest_hp_ratio": lowest_hp})
	times.sort()
	return {
		"stage_id": stage.id, "profile": profile_id, "profile_spec": profile, "control": control,
		"runs": runs_per_cell, "wins": wins, "win_rate": float(wins) / runs_per_cell,
		"mean_time": harness._mean(times), "p10_time": harness._percentile(times, 0.10), "p50_time": harness._percentile(times, 0.50), "p90_time": harness._percentile(times, 0.90),
		"mean_survivors": float(survivor_total) / runs_per_cell, "mean_lowest_hp_ratio": lowest_hp_total / runs_per_cell, "timeout_rate": float(timeout_count) / runs_per_cell,
		"damage_totals": damage_totals, "healing_totals": healing_totals, "ultimate_totals": ultimate_totals, "death_causes": death_causes, "run_results": run_rows,
	}
