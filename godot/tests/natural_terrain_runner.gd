extends Node

const Natural := preload("res://chapter_map/view/natural_terrain_library.gd")
var buckets: Dictionary = {}
var failed := 0
var passed := 0

func _ready() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print(("PASS | " if ok else "FAIL | ") + label)

func _index_meshes(node: Node, parent_transform := Transform3D.IDENTITY) -> void:
	var transform: Transform3D = parent_transform * node.transform if node is Node3D else parent_transform
	if node is MeshInstance3D:
		var vertices: PackedVector3Array = node.mesh.get_faces()
		for offset in range(0, vertices.size(), 3):
			var triangle: Array[Vector3] = [transform * vertices[offset], transform * vertices[offset+1], transform * vertices[offset+2]]
			var minimum := Vector2(INF, INF)
			var maximum := Vector2(-INF, -INF)
			for point in triangle:
				minimum = minimum.min(Vector2(point.x, point.z))
				maximum = maximum.max(Vector2(point.x, point.z))
			for x in range(floori(minimum.x / 2.0), floori(maximum.x / 2.0) + 1):
				for z in range(floori(minimum.y / 2.0), floori(maximum.y / 2.0) + 1):
					var key := Vector2i(x,z)
					if not buckets.has(key): buckets[key] = []
					buckets[key].append(triangle)
	for child in node.get_children(): _index_meshes(child, transform)

func _mesh_height(point: Vector3) -> float:
	var candidates: Array = buckets.get(Vector2i(floori(point.x / 2.0), floori(point.z / 2.0)), [])
	for triangle in candidates:
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		var determinant: float = (b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
		if absf(determinant) < .000001: continue
		var wa: float = ((b.z-c.z)*(point.x-c.x)+(c.x-b.x)*(point.z-c.z))/determinant
		var wb: float = ((c.z-a.z)*(point.x-c.x)+(a.x-c.x)*(point.z-c.z))/determinant
		var wc := 1.0-wa-wb
		if minf(wa,minf(wb,wc)) >= -.0001: return a.y*wa+b.y*wb+c.y*wc
	return INF

func _validate_map(map_id: String) -> void:
	buckets.clear()
	print("VALIDATING_NATURAL_MAP ", map_id)
	var definition := ChapterMapLoader.load_map(map_id)
	var grid := HexGrid.new()
	grid.load_tiles(definition.tiles)
	var info := Natural.descriptor(definition)
	check(not info.is_empty(), "Blender 5.x terrain matches the canonical map fingerprint")
	if info.is_empty(): return
	check(str(info.manifest.blender).begins_with("5."), "runtime manifest uses the user-selected Blender 5.x series")
	var source := (load(str(info.path)) as PackedScene).instantiate()
	_index_meshes(source)
	var checked := 0
	var gaps := 0
	var maximum_error := 0.0
	var maximum_sampler_error := 0.0
	for tile in definition.tiles:
		var coord := Vector2i(int(tile.q), int(tile.r))
		if not grid.traversable(coord): continue
		var a := HexCoord.axial_to_world(coord, 1.08, float(tile.elevation)*.86+.018)
		for neighbor in HexCoord.neighbors(coord):
			if not grid.traversable(neighbor): continue
			var b := HexCoord.axial_to_world(neighbor,1.08,float(grid.tile(neighbor).elevation)*.86+.018)
			for weight in [0.0,.25,.5,.75,1.0]:
				var sample := a.lerp(b,weight)
				var height := _mesh_height(sample)
				checked += 1
				if is_inf(height):
					gaps += 1
					print("MESH_GAP from=",coord," to=",neighbor," weight=",weight," position=",sample)
					continue
				maximum_error = maxf(maximum_error,absf(height-sample.y))
				maximum_sampler_error = maxf(maximum_sampler_error,absf(height-Natural.surface_height(grid,sample)))
	check(checked>1000 and gaps==0, "all sampled legal walk edges exist in the imported Blender mesh")
	check(maximum_error < .002, "imported terrain matches actual pawn walk heights within 2 mm")
	check(maximum_sampler_error < .002, "overlay and prop height sampler matches the imported Blender surface")
	var changed := definition.duplicate(true)
	changed.tiles[0].elevation += 1
	check(Natural.descriptor(changed).is_empty(), "stale baked geometry is rejected after canonical terrain changes")
	source.free()
	print("NATURAL_GEOMETRY_SAMPLES count=%d gaps=%d max_walk_error=%f max_sampler_error=%f" % [checked,gaps,maximum_error,maximum_sampler_error])

func _run() -> void:
	for chapter in range(1, 21):
		_validate_map("CH%02d_MAP" % chapter)
	print("NATURAL_TERRAIN_SUMMARY total=%d pass=%d fail=%d" % [passed+failed,passed,failed])
	get_tree().quit(0 if failed==0 else 1)
