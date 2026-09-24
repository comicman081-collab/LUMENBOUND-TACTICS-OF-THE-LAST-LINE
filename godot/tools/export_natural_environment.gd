extends Node

func _ready() -> void: call_deferred("_run")

func _run() -> void:
	var output := ProjectSettings.globalize_path("res://../data_source/art_source/natural_environment_r1/inputs")
	DirAccess.make_dir_recursive_absolute(output)
	for number in range(1, 21):
		var id := "CH%02d_MAP" % number
		var definition := ChapterMapLoader.load_map(id)
		var grid := HexGrid.new()
		grid.load_tiles(definition.tiles)
		var river: Dictionary = definition.get("river_geometry", {})
		var points: Array = []
		for p: Vector3 in river.get("points", []):
			var tile: Dictionary = grid.tile(HexCoord.world_to_axial(p, 1.08))
			points.append([p.x, float(tile.get("elevation", 0)) * .86 + .052, p.z])
		var path := output.path_join(id + ".json")
		if FileAccess.file_exists(path): push_error("Fresh environment inputs required"); get_tree().quit(1); return
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"map_id": id, "river_points": points,
			"tile_fingerprint": preload("res://chapter_map/view/natural_terrain_library.gd").tile_fingerprint(definition)}, "\t"))
		print("NATURAL_ENV_SOURCE ", id, " river_points=", points.size())
	get_tree().quit()
