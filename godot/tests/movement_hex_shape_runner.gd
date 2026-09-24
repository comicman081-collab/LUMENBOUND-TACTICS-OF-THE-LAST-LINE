extends Node

func _ready() -> void:
	var screen := ChapterMapScreen.new()
	screen.natural_terrain_info = {"test": true}
	var checked := 0
	var maximum_error := 0.0
	var grid_complete := true
	var grid_cells := 0
	var persistent := preload("res://chapter_map/runtime/map_cell_grid.gd").new()
	for chapter in range(1, 21):
		var definition := ChapterMapLoader.load_map("CH%02d_MAP" % chapter)
		screen.definition = definition
		screen.grid.load_tiles(definition.tiles)
		persistent.configure(screen)
		grid_complete = grid_complete and persistent.cells.size() == definition.tiles.size()
		grid_cells += persistent.cells.size()
		for tile in definition.tiles:
			if bool(tile.get("movement_blocked", false)): continue
			var coord := Vector2i(int(tile.q), int(tile.r))
			var height := float(tile.elevation) * .86 + .105
			var corners := screen._movement_hex_corners(coord, height)
			var center := HexCoord.axial_to_world(coord, 1.08, height)
			for i in range(6):
				maximum_error = maxf(maximum_error, absf(corners[i].y - height))
				maximum_error = maxf(maximum_error, absf(corners[i].distance_to(center) - 1.08 * .92))
				maximum_error = maxf(maximum_error, absf(corners[i].distance_to(corners[(i+1)%6]) - 1.08 * .92))
			checked += 1
	persistent.free()
	screen.free()
	var ok := checked > 1000 and maximum_error < .0001 and grid_complete
	print("MOVEMENT_HEX_SHAPE chapters=20 cells=%d max_error=%f pass=%s" % [checked, maximum_error, ok])
	print("PERSISTENT_MAP_GRID chapters=20 cells=%d all_tiles=%s" % [grid_cells, grid_complete])
	get_tree().quit(0 if ok else 1)
