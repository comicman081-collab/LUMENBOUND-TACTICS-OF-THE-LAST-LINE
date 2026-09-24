extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := ProjectSettings.globalize_path("res://../data_source/art_source/natural_terrain_r1/inputs")
	DirAccess.make_dir_recursive_absolute(output)
	for number in range(1, 21):
		var id := "CH%02d_MAP" % number
		var definition := ChapterMapLoader.load_map(id)
		var palette: Dictionary = preload("res://chapter_map/view/region_palette.gd").for_definition(definition)
		var colors: Dictionary = {}
		for key in ["ground", "road", "ruins", "canopy", "bed_light"]:
			colors[key] = (palette[key] as Color).to_html(false)
		var tiles: Array = []
		for tile in definition.tiles:
			tiles.append({"q": int(tile.q), "r": int(tile.r), "elevation": int(tile.elevation), "terrain": str(tile.terrain_type), "blocked": bool(tile.get("movement_blocked", false))})
		var file := FileAccess.open(output.path_join(id + ".json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"map_id": id, "tiles": tiles, "tile_fingerprint": JSON.stringify(tiles).sha256_text(), "palette": colors, "tile_size": 1.08, "elevation_step": 0.86, "chunk_span": 12}, "\t"))
		print("NATURAL_TERRAIN_SOURCE ", id, " tiles=", tiles.size())
	get_tree().quit()
