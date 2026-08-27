extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var project_root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var required := ["characters.csv", "character_level_curve.csv", "account_level_curve.csv", "skills.json", "weapons.csv", "weapon_level_curve.csv", "enemies.csv", "stages.csv", "stage_rewards.json", "chapters.json", "affinity_matrix.json", "status_effects.json", "chapter_story_triggers.json"]
	var hashes: Dictionary = {}
	for name in required:
		var path := project_root.path_join("data_source").path_join(name)
		if not FileAccess.file_exists(path):
			printerr("missing source: ", path)
			quit(2)
			return
		var file := FileAccess.open(path, FileAccess.READ)
		hashes[name] = file.get_as_text().sha256_text()
	var compiled_path := "res://data/compiled/game_data.json"
	var compiled := FileAccess.open(compiled_path, FileAccess.READ)
	if compiled == null or not JSON.parse_string(compiled.get_as_text()) is Dictionary:
		printerr("compiled JSON invalid; run tools/generate_data.py")
		quit(3)
		return
	var stamp := FileAccess.open("res://data/compiled/compile_stamp.json", FileAccess.WRITE)
	stamp.store_string(JSON.stringify({"compiler": "godot-verifier-1", "source_sha256": hashes}, "  "))
	print("data source and compiled JSON verified")
	quit(0)
