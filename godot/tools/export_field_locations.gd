extends Node

func _ready() -> void:
	var records: Dictionary = {}
	for number in range(2, 21):
		var id := "CH%02d" % number
		var definition := ChapterMapLoader.load_map(id + "_MAP")
		var grid := HexGrid.new()
		grid.load_tiles(definition.tiles)
		var used: Dictionary = {}
		for node in definition.nodes: used[HexCoord.key(Vector2i(int(node.q), int(node.r)))] = true
		for patrol in definition.patrols:
			for point in patrol.get("patrol_route_hexes", []): used[HexCoord.key(Vector2i(int(point.q), int(point.r)))] = true
		var positions: Array = []
		for anchor_id in ["NODE_START", "NODE_N08", "NODE_N16"]:
			var anchor: Dictionary = definition.nodes.filter(func(n): return n.node_type == "START" if anchor_id == "NODE_START" else n.node_id == anchor_id)[0]
			var origin := Vector2i(int(anchor.q), int(anchor.r))
			var found := false
			for distance in range(1, 4):
				for q in range(origin.x-distance, origin.x+distance+1):
					for r in range(origin.y-distance, origin.y+distance+1):
						var point := Vector2i(q,r)
						if HexCoord.distance(origin,point) != distance or used.has(HexCoord.key(point)) or not grid.traversable(point): continue
						if HexPathfinder.find_path(grid, origin, point).is_empty(): continue
						positions.append({"q":q,"r":r,"anchor":anchor_id})
						used[HexCoord.key(point)] = true
						found = true
						break
					if found: break
				if found: break
			if not found: push_error("No existing field route " + id); get_tree().quit(1); return
		records[id] = {"positions": positions, "tile_fingerprint": preload("res://chapter_map/view/natural_terrain_library.gd").tile_fingerprint(definition)}
	var output := FileAccess.open("res://../data_source/chapter_field_locations.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(records,"  "))
	print("FIELD_LOCATIONS_READY regions=",records.size())
	get_tree().quit()
