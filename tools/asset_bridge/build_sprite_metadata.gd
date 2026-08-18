extends SceneTree

const REQUIRED := {"idle": 8, "move": 12, "basic_attack": 8, "normal_skill": 12, "ultimate": 18, "hit": 4, "down": 8, "victory": 10}

func _init() -> void:
	var output := {"schema_version": 1, "frame_size": [512, 512], "foot_anchor": [0.5, 0.88], "default_fps": 12, "required_animations": REQUIRED, "note": "Factory exports are DEV_PLACEHOLDER and do not yet satisfy all eight final SD animation rows."}
	var file := FileAccess.open("res://assets/generated_import/sprite_contract.json", FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(output, "  "))
	quit(0)

