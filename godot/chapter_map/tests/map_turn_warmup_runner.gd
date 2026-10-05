extends Node

const ProbeScript := preload("res://autoload/web_soak_probe.gd")

var failures := 0
var checks := 0

func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 96)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0.0, 2.0, 5.4)
	camera.look_at(Vector3(0.0, 0.75, 0.0), Vector3.UP)
	camera.make_current()
	var warm := ProbeScript.create_map_awareness_warmup()
	root.add_child(warm)
	# The actual map cue begins empty and receives this text on the enemy turn.
	var runtime_cue := Label3D.new()
	runtime_cue.font_size = 50
	runtime_cue.outline_size = 9
	runtime_cue.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	runtime_cue.no_depth_test = true
	runtime_cue.text = "! 추적"
	root.add_child(runtime_cue)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(warm.font == runtime_cue.font and warm.texture_filter == runtime_cue.texture_filter, "uses the map cue's font/filter defaults")
	_check(warm.alpha_cut == runtime_cue.alpha_cut and warm.alpha_cut == Label3D.ALPHA_CUT_DISABLED, "ordinary alpha path matches the runtime cue")
	_check(warm.shaded == runtime_cue.shaded and warm.double_sided == runtime_cue.double_sided, "unshaded double-sided flags match")
	_check(warm.fixed_size == runtime_cue.fixed_size and warm.billboard == runtime_cue.billboard and warm.no_depth_test == runtime_cue.no_depth_test, "billboard/depth/size flags match")
	var warm_textures := _surface_textures(warm)
	var cue_textures := _surface_textures(runtime_cue)
	_check(not warm_textures.is_empty() and not cue_textures.is_empty(), "both text nodes created real glyph surfaces")
	for texture in cue_textures:
		_check(texture.is_valid() and warm_textures.has(texture), "runtime glyph surface reuses a warmed font atlas")
	print("MAP_TURN_WARMUP_REGRESSION checks=%d failures=%d warmed_surfaces=%d runtime_surfaces=%d" % [checks, failures, warm_textures.size(), cue_textures.size()])
	get_tree().quit(0 if failures == 0 else 1)

func _surface_textures(label: Label3D) -> Array[RID]:
	var result: Array[RID] = []
	var mesh := label.get_base()
	for index in range(RenderingServer.mesh_get_surface_count(mesh)):
		var material := RenderingServer.mesh_surface_get_material(mesh, index)
		var texture = RenderingServer.material_get_param(material, "texture_albedo")
		if texture is RID:
			result.append(texture)
	return result

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("MAP_TURN_WARMUP_FAIL %s" % label)
