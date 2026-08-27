extends Node

## Minimal dynamic entrypoint for the fresh-profile chain.  Its diagnostics
## identify launcher/load/constructor failures before progression code runs.

const RUNNER_PATH := "res://tests/progression/r15_fresh_progression_runner.gd"

func _ready() -> void:
	_write_state("BOOT_START")
	_mark("R15_E2E_BOOT_START")
	call_deferred("_run")

func _run() -> void:
	var runner_script = load(RUNNER_PATH)
	if runner_script == null or not runner_script.can_instantiate():
		_fail("R15_E2E_BOOT_FAIL runner load", 90)
		return
	_write_state("RUNNER_LOADED")
	_mark("R15_E2E_RUNNER_LOADED")
	var runner = runner_script.new()
	if runner == null:
		_fail("R15_E2E_BOOT_FAIL runner instantiation", 91)
		return
	_write_state("RUNNER_INSTANTIATED")
	_mark("R15_E2E_RUNNER_INSTANTIATED")
	var report: Dictionary = runner.run()
	var complete := bool(report.get("completed_normal_route", false))
	if complete:
		_mark("R15_E2E_EXIT_PASS")
		get_tree().quit(0)
	else:
		printerr("R15_E2E_EXIT_FAIL | ", JSON.stringify(report.get("errors", [])))
		get_tree().quit(1)

func _mark(marker: String) -> void:
	print(marker)

func _fail(marker: String, code: int) -> void:
	_write_state(marker)
	printerr(marker)
	get_tree().quit(code)

func _write_state(state: String) -> void:
	var report_dir := ProjectSettings.globalize_path("res://").path_join("../reports/r15").simplify_path()
	DirAccess.make_dir_recursive_absolute(report_dir)
	var output := FileAccess.open(report_dir.path_join("R15_PROGRESSION_BOOTSTRAP_STATE.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"state": state, "msec": Time.get_ticks_msec()}))
