extends RefCounted

const ROOT := "res://assets/art/chapter_map/NaturalEnvR2/"

static func instantiate_river(definition: Dictionary, owner_node: Node, parent: Node3D) -> bool:
	var directory := ROOT + str(definition.get("map_id", "")) + "/"
	var manifest_path := directory + "manifest.json"
	if not FileAccess.file_exists(manifest_path): return false
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or not str(manifest.get("blender", "")).begins_with("5."): return false
	var fingerprint := preload("res://chapter_map/view/natural_terrain_library.gd").tile_fingerprint(definition)
	if fingerprint.is_empty() or manifest.get("tile_fingerprint", "") != fingerprint: return false
	var packed := load(directory + "river.glb") as PackedScene
	if packed == null: return false
	var template := packed.instantiate()
	var palette := preload("res://chapter_map/view/region_palette.gd").for_definition(definition)
	var water := ShaderMaterial.new()
	water.shader = preload("res://chapter_map/shaders/natural_river.gdshader")
	water.set_shader_parameter("water_color", palette.canopy.lerp(Color("245d67"), .68))
	var bank := ShaderMaterial.new()
	bank.shader = preload("res://chapter_map/view/web_map_material_policy.gd").surface_shader(preload("res://chapter_map/shaders/natural_river_bank.gdshader"))
	bank.set_shader_parameter("soil_color", palette.ground)
	var timber := StandardMaterial3D.new()
	preload("res://chapter_map/view/web_map_material_policy.gd").apply(timber)
	timber.albedo_color = palette.road.darkened(.17)
	timber.roughness = .96
	var root := Node3D.new()
	root.name = "NaturalBlenderRiver"
	parent.add_child(root)
	var meshes: Array[MeshInstance3D] = []
	_collect(template, meshes)
	for mesh in meshes:
		var instance := MeshInstance3D.new()
		instance.name = mesh.name
		instance.mesh = mesh.mesh
		instance.transform = mesh.transform
		instance.material_override = water if str(mesh.name).begins_with("WATER") else (timber if str(mesh.name).begins_with("TIMBER") else bank)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
		if root.get_child_count() % 4 == 0:
			await owner_node.get_tree().process_frame
		if not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
			template.free()
			if is_instance_valid(root): root.queue_free()
			return true
	template.free()
	owner_node.set_meta("natural_river_chunks", meshes.size())
	owner_node.set_meta("natural_bridge_tiles", int(manifest.get("bridge_tiles", 0)))
	return true

static func _collect(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D: meshes.append(node)
	for child in node.get_children(): _collect(child, meshes)
