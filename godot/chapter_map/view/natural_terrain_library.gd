extends RefCounted

# Runtime authority accepts only the user's selected Blender 5.x pipeline.
const ROOT := "res://assets/art/chapter_map/NaturalR1/"
const TILE_SIZE := 1.08
const ELEVATION_STEP := .86

static func tile_fingerprint(definition: Dictionary) -> String:
	var tiles: Array = []
	for tile in definition.get("tiles", []):
		# A baked mesh is usable only for a complete authored tile signature.
		# Sparse/legacy transition data must take the procedural terrain path,
		# rather than aborting map construction or guessing a matching height.
		if not tile is Dictionary or not tile.has_all(["q", "r", "elevation", "terrain_type"]): return ""
		tiles.append({"q": int(tile.q), "r": int(tile.r), "elevation": int(tile.elevation), "terrain": str(tile.terrain_type), "blocked": bool(tile.get("movement_blocked", false))})
	return JSON.stringify(tiles).sha256_text()

static func anchor_height(grid, coord: Vector2i) -> float:
	var tile: Dictionary = grid.tile(coord)
	var height := float(tile.get("elevation", 0)) * ELEVATION_STEP + .018
	if str(tile.get("terrain_type", "")) in ["SHALLOW_WATER", "DEEP_WATER"]: height -= .32
	return height

static func surface_height(grid, point: Vector3) -> float:
	# Matches the exact triangular centre lattice authored in Blender. Adjacent
	# legal walk centres are connected by edges with the original linear height.
	var q := (sqrt(3.0) / 3.0 * point.x - point.z / 3.0) / TILE_SIZE
	var r := (2.0 / 3.0 * point.z) / TILE_SIZE
	var iq := floori(q)
	var ir := floori(r)
	var fq := q - float(iq)
	var fr := r - float(ir)
	var coords: Array[Vector2i]
	var weights: Vector3
	if fq + fr <= 1.0:
		coords = [Vector2i(iq, ir), Vector2i(iq + 1, ir), Vector2i(iq, ir + 1)]
		weights = Vector3(1.0 - fq - fr, fq, fr)
	else:
		coords = [Vector2i(iq + 1, ir + 1), Vector2i(iq, ir + 1), Vector2i(iq + 1, ir)]
		weights = Vector3(fq + fr - 1.0, 1.0 - fq, 1.0 - fr)
	for coord in coords:
		if not grid.has(coord):
			return anchor_height(grid, HexCoord.world_to_axial(point, TILE_SIZE))
	return anchor_height(grid, coords[0]) * weights.x + anchor_height(grid, coords[1]) * weights.y + anchor_height(grid, coords[2]) * weights.z

static func descriptor(definition: Dictionary) -> Dictionary:
	var id := str(definition.get("map_id", ""))
	if not id.begins_with("CH") or not id.ends_with("_MAP") or "/" in id or ".." in id: return {}
	var directory := ROOT + id + "/"
	var manifest_path := directory + "manifest.json"
	if not FileAccess.file_exists(manifest_path): return {}
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or not str(manifest.get("blender", "")).begins_with("5."): return {}
	var fingerprint := tile_fingerprint(definition)
	if fingerprint.is_empty() or manifest.get("map_id", "") != id or manifest.get("tile_fingerprint", "") != fingerprint: return {}
	if str(manifest.get("status", "")) not in ["LOCAL_QA_CANDIDATE", "LOCAL_QA_VERIFIED"]: return {}
	var path := directory + "terrain.glb"
	if not ResourceLoader.exists(path): return {}
	return {"path": path, "manifest": manifest}

static func instantiate_chunks(info: Dictionary, owner_node: Node, parent: Node3D, material: Material) -> Dictionary:
	if info.is_empty() or not is_instance_valid(owner_node) or not owner_node.is_inside_tree(): return {}
	var packed := load(str(info.path)) as PackedScene
	if packed == null: return {}
	var source := packed.instantiate()
	var meshes: Array[MeshInstance3D] = []
	_collect(source, meshes)
	if meshes.is_empty():
		source.free()
		return {}
	var next_root := Node3D.new()
	next_root.name = "NaturalBlenderTerrain"
	parent.add_child(next_root)
	var first: MeshInstance3D
	for template in meshes:
		var instance := MeshInstance3D.new()
		instance.name = template.name
		instance.mesh = template.mesh
		instance.transform = template.transform
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		next_root.add_child(instance)
		if first == null: first = instance
		# Keep geometry registration/upload cooperative even on a cold Web driver.
		await owner_node.get_tree().process_frame
		if not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
			source.free()
			if is_instance_valid(next_root): next_root.queue_free()
			return {}
	source.free()
	return {"root": next_root, "first": first, "chunks": meshes.size(), "manifest": info.manifest}

static func _collect(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D: meshes.append(node)
	for child in node.get_children(): _collect(child, meshes)
