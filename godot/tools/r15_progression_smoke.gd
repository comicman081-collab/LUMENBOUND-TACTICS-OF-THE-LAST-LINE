extends Node

## Isolates project startup and the R15 progression script preload.  This is a
## diagnostic test only; it never mutates game state or reward data.
const ProgressionScript := preload("res://tools/r15_progression_simulation.gd")

func _ready() -> void:
	_write("READY")
	call_deferred("_run")

func _run() -> void:
	var probe := ProgressionScript.new()
	probe.free()
	_write("PRELOAD_OK")
	get_tree().quit()

func _write(state: String) -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("../reports/r15").simplify_path()
	DirAccess.make_dir_recursive_absolute(root)
	var output := FileAccess.open(root.path_join("R15_PROGRESSION_SMOKE.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"state": state, "msec": Time.get_ticks_msec()}))
