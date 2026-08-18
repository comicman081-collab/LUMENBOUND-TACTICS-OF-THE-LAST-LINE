extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../reports/character_stats_export.csv").simplify_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_csv_line(PackedStringArray(["character_id", "level", "HP", "ATK", "DEF", "HEAL_POWER"]))
	for character in DataRegistry.list_of("characters"):
		for level in range(1, 101):
			var curve := float(DataRegistry.list_of("character_level_curve")[level - 1].curve)
			var values: Array[String] = [character.id, str(level)]
			for stat in ["HP", "ATK", "DEF", "HEAL_POWER"]:
				values.append(str(MathUtil.round_half_up(float(character.stats_l1[stat]) + (float(character.stats_l100[stat]) - float(character.stats_l1[stat])) * curve)))
			file.store_csv_line(PackedStringArray(values))
	print("wrote ", path)
	quit(0)

