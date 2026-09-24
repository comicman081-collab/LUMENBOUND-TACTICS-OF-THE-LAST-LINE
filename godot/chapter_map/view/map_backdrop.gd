extends Node3D

const Hex := preload("res://chapter_map/model/hex_coord.gd")
const BedShader := preload("res://chapter_map/shaders/forest_backdrop.gdshader")
const TILE_SIZE := 1.08
const BED_Y := -1.34

static func bounds_for(tiles: Array) -> Rect2:
	var bounds := Rect2(Vector2.ZERO, Vector2.ONE)
	for tile in tiles:
		var point := Hex.axial_to_world(Vector2i(int(tile.q), int(tile.r)), TILE_SIZE)
		bounds = bounds.expand(Vector2(point.x, point.z))
	# Larger than the maximum camera frustum at every permitted map anchor.
	return bounds.grow(100.0)

static func local_bounds_for(center_coord: Vector2i, radius_world: float) -> Rect2:
	var center := Hex.axial_to_world(center_coord, TILE_SIZE)
	var radius := maxf(8.0, radius_world)
	return Rect2(Vector2(center.x - radius, center.z - radius), Vector2(radius * 2.0, radius * 2.0))

func configure(definition: Dictionary, grid, natural_surface := false, focus_coord := Vector2i(0, 0), local_radius_world := 0.0) -> void:
	# A chapter can span hundreds of axial columns while the squad may only view
	# a small fog-gated neighbourhood. Building the forest for the entire chapter
	# on Web made the first operation wait on invisible trees.
	for child in get_children():
		child.queue_free()
	name = "ContinuousForestBackdrop"
	var bounds := local_bounds_for(focus_coord, local_radius_world) if local_radius_world > 0.0 else bounds_for(definition.get("tiles", []))
	var bed := MeshInstance3D.new()
	bed.name = "ContinuousForestFloor"
	var plane := PlaneMesh.new()
	plane.size = bounds.size
	bed.mesh = plane
	bed.position = Vector3(bounds.get_center().x, BED_Y, bounds.get_center().y)
	var material := ShaderMaterial.new()
	material.shader = BedShader
	var palette := preload("res://chapter_map/view/region_palette.gd").for_definition(definition)
	material.set_shader_parameter("soil_dark", palette.ground.darkened(.36))
	material.set_shader_parameter("soil_light", palette.bed_light)
	set_meta("region_family", palette.family)
	bed.material_override = material
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed)
	var crowns: Array[Transform3D] = []
	var crowns_alt: Array[Transform3D] = []
	var trunks: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var rocks_alt: Array[Transform3D] = []
	# A sparse, deterministic grove field sits entirely below playable ground.
	# Its density and styles match the existing low-poly forest, not an unrelated
	# indoor battle picture. These nodes never join the grid, collision or fog.
	# Large campaign bounds retain the former broad safe margin. A local Web
	# district needs a small inset, otherwise its usable area is empty.
	var edge_margin := minf(60.0, minf(bounds.size.x, bounds.size.y) * 0.10)
	for x in range(int(bounds.position.x + edge_margin), int(bounds.end.x - edge_margin), 3):
		for z in range(int(bounds.position.y + edge_margin), int(bounds.end.y - edge_margin), 3):
			var seed_value := absi(x * 173 + z * 311)
			if seed_value % 5 == 0: continue
			# Loose groves and occasional clearings replace a uniform tree lattice.
			var grove := sin(float(x) * .14 + cos(float(z) * .11)) * cos(float(z) * .13)
			if grove < -.34 and seed_value % 3 != 0: continue
			var point := Vector3(float(x) + sin(float(seed_value)) * 1.4, BED_Y, float(z) + cos(float(seed_value) * .7) * 1.4)
			var coord := Hex.world_to_axial(point, TILE_SIZE)
			if natural_surface and grid.has(coord):
				# Broad background groves now sit on the baked landscape, rather than
				# disappearing under hills or standing inside the player's open lanes.
				var tile: Dictionary = grid.tile(coord)
				if str(tile.get("terrain_type", "")) != "FOREST" or not bool(tile.get("movement_blocked", false)): continue
				point.y = preload("res://chapter_map/view/natural_terrain_library.gd").surface_height(grid, point)
			# The grid covers cells whose foreground chunk is intentionally absent.
			# Excluding every grid cell also excluded the actual visible holes. Keep
			# undergrowth there; depth hides it underneath present terrain. Never
			# put background shrubs beneath a river, bridge or authored road lane.
			var lane := false
			for neighbor in [coord]:
				if grid.has(neighbor) and str(grid.tile(neighbor).get("terrain_type", "")) in ["ROAD", "BRIDGE", "SHALLOW_WATER", "RIVER"]:
					lane = true
					break
			if lane: continue
			var scale_value := .70 + float(seed_value % 9) * .065
			var crown := Transform3D(Basis(Vector3.UP, float(seed_value % 17) * .37).scaled(Vector3(4.25 * scale_value, 2.25 * scale_value, 3.8 * scale_value)), point + Vector3(0, .84 * scale_value, 0))
			if seed_value % 3 == 0: crowns_alt.append(crown)
			else: crowns.append(crown)
			trunks.append(Transform3D(Basis(Vector3.UP, float(seed_value % 17) * .37).scaled(Vector3(1.7, 2.4, 1.7) * scale_value), point + Vector3(0, .42 * scale_value, 0)))
			if seed_value % 7 == 1:
				var stone := Transform3D(Basis(Vector3.UP, float(seed_value % 13) * .48).scaled(Vector3(3.0, 2.0, 2.5)), point + Vector3(.85, .15, -.5))
				if seed_value % 2 == 0: rocks_alt.append(stone)
				else: rocks.append(stone)
	var kit := preload("res://chapter_map/view/environment_mesh_library.gd").load_once()
	var canopy: Mesh = kit.get("canopy")
	if canopy == null:
		var fallback := SphereMesh.new()
		fallback.radius = .24
		fallback.height = .4
		fallback.radial_segments = 7
		fallback.rings = 3
		canopy = fallback
	var trunk: Mesh = kit.get("trunk")
	if trunk == null: trunk = CylinderMesh.new()
	_add_batch("DistantForestCrowns", canopy, crowns, palette.canopy.lightened(.10))
	_add_batch("DistantForestCrownsAlt", kit.get("canopy_alt", canopy), crowns_alt, palette.canopy.lightened(.18))
	_add_batch("DistantForestTrunks", trunk, trunks, Color("413c2d"))
	if kit.has("boulder"):
		_add_batch("DistantMossRocks", kit.boulder, rocks, palette.ruins)
		_add_batch("DistantMossRocksAlt", kit.get("boulder_alt", kit.boulder), rocks_alt, palette.ruins.lerp(palette.ground, .15))
	set_meta("background_instance_count", crowns.size() + crowns_alt.size() + trunks.size() + rocks.size() + rocks_alt.size())
	set_meta("background_bounds", bounds)

func _add_batch(label: String, mesh: Mesh, transforms: Array[Transform3D], color: Color) -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://chapter_map/view/web_map_material_policy.gd").surface_shader(preload("res://chapter_map/shaders/environment_surface.gdshader"))
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("surface_kind", 0 if "Crowns" in label else (2 if "Trunks" in label else 1))
	var chunks := {}
	for transform in transforms:
		var key := Vector2i(floori(transform.origin.x / 32.0), floori(transform.origin.z / 32.0))
		if not chunks.has(key): chunks[key] = []
		chunks[key].append(transform)
	for key in chunks:
		var values: Array = chunks[key]
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = mesh
		batch.instance_count = values.size()
		for index in values.size(): batch.set_instance_transform(index, values[index])
		var instance := MultiMeshInstance3D.new()
		instance.name = "%s_%d_%d" % [label, key.x, key.y]
		instance.multimesh = batch
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
