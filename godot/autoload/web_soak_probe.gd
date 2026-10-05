extends Node

signal web_map_pipeline_progress(phase: String, percent: int)
signal web_map_pipelines_ready
signal web_title_pipelines_ready

const WebMovementOverlayScript := preload("res://chapter_map/runtime/web_movement_overlay.gd")
const EnvironmentWaterShader := preload("res://chapter_map/shaders/water_environment.gdshader")
const MapAtmosphereShader := preload("res://chapter_map/shaders/map_atmosphere.gdshader")
const TitlePuppetShader := preload("res://ui/shaders/title_puppet.gdshader")
const TitleHaloShader := preload("res://ui/shaders/title_halo.gdshader")

const SAMPLE_INTERVAL_SECONDS := 5.0
const MAX_SAMPLES := 240

var elapsed_seconds := 0.0
var sample_accumulator := 0.0
var samples: Array[Dictionary] = []
var minimum_fps := 1000000.0
var maximum_static_memory := 0.0
var interval_max_frame_msec := 0.0
var interval_frames_over_33ms := 0
var interval_frames_over_50ms := 0
var interval_frames_over_100ms := 0
var interval_frame_count := 0
var web_render_warmup_complete := false
var web_title_warmup_complete := false
var web_map_warmup_running := false
var web_render_resource_cache: Dictionary = {}
var sampling_enabled := false

func web_render_resource(key: String):
	# Only immutable Resource owners survive the boot warmup. Keeping scene nodes
	# or a disabled SubViewport alive crashes Godot Web's Compatibility renderer,
	# while retaining a Mesh/Material RID is safe and lets the real map reuse the
	# exact object that was submitted during the silent boot gate.
	return web_render_resource_cache.get(key, null)

func _runtime_material_key(color: Color, emission := Color.BLACK) -> String:
	return "runtime_material:%s|%s" % [color.to_html(true), emission.to_html(true)]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web") and SettingsService.is_developer_mode() and SaveService.is_soak_sandbox_enabled():
		var local_probe := load("res://qa/local_gameplay_probe.gd") as Script
		add_child(local_probe.new())
	# Runtime telemetry is opt-in. Serialising the full audio/object sample and
	# forwarding it through the browser console every five seconds created its own
	# rhythmic main-thread hitch in ordinary Release play. Pipeline warmup remains
	# active for every Web launch; only the QA sampler is gated by the URL flag.
	sampling_enabled = _web_soak_sampling_requested()
	set_process(OS.has_feature("web") and sampling_enabled)
	if OS.has_feature("web"):
		if sampling_enabled:
			var sandbox_state := "active" if SaveService.is_soak_sandbox_enabled() else "inactive"
			print("R7_WEB_SOAK_PROBE_READY interval=5s max_samples=240 sandbox=%s" % sandbox_state)
		# The first interactive screen is 2D. Do not compile the entire tactical
		# world's 3D variants before the player can even start the intro. Map entry
		# has its own loading/input boundary and retains the same warmed resources.
		_prewarm_web_title_pipelines()

func _web_soak_sampling_requested() -> bool:
	if not OS.has_feature("web"):
		return false
	var value = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('r7-web-soak-probe')", true)
	return str(value).strip_edges().to_lower() in ["1", "true", "yes", "on"]

func ensure_web_map_pipelines() -> void:
	if not OS.has_feature("web") or web_render_warmup_complete:
		return
	if not web_title_warmup_complete:
		await web_title_pipelines_ready
	if web_map_warmup_running:
		await web_map_pipelines_ready
		return
	web_map_warmup_running = true
	await _prewarm_web_render_pipelines()
	web_map_warmup_running = false
	web_map_pipelines_ready.emit()

func _prewarm_web_title_pipelines() -> void:
	var started_usec := Time.get_ticks_usec()
	_set_boot_loading_phase("시작 화면 그래픽", 10)
	var viewport := SubViewport.new()
	viewport.name = "WebTitlePipelineWarmup"
	viewport.size = Vector2i(96, 96)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var canvas_root := Control.new()
	canvas_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(canvas_root)
	_add_title_pipeline_samples(canvas_root)
	await _warmup_draw_slice("타이틀 연출", 90)
	for _frame_index in range(6):
		await get_tree().process_frame
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.queue_free()
	web_title_warmup_complete = true
	JavaScriptBridge.eval("document.getElementById('lantern-render-loading')?.remove(); window.__lanternRenderReady = true;", true)
	web_title_pipelines_ready.emit()
	print("WEB_TITLE_WARMUP_COMPLETE %.2fms" % (float(Time.get_ticks_usec() - started_usec) / 1000.0))

func _prewarm_web_render_pipelines() -> void:
	# Compatibility/Web compiles several 3D shader/pipeline variants on their first
	# visible draw. When that first draw happened during map entry it produced
	# repeated 100-150ms frames and starved the main-thread audio mixer. Render one
	# tiny representative scene under the first map-entry loading gate, discard it;
	# actual map can reuse the warmed vertex-colour, MultiMesh, sprite and overlay
	# pipelines without changing any gameplay or save state.
	if not OS.has_feature("web") or web_render_warmup_complete:
		return
	var warmup_started_usec := Time.get_ticks_usec()
	web_map_pipeline_progress.emit("지도 그래픽 초기화", 0)
	var warmup_viewport := SubViewport.new()
	warmup_viewport.name = "WebRenderPipelineWarmup"
	warmup_viewport.size = Vector2i(96, 96)
	warmup_viewport.own_world_3d = true
	warmup_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	warmup_viewport.transparent_bg = false
	add_child(warmup_viewport)
	var root := Node3D.new()
	warmup_viewport.add_child(root)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0a2634")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9cb59d")
	environment.ambient_light_energy = 0.74
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_density = 0.0022
	environment_node.environment = environment
	root.add_child(environment_node)
	var water := MeshInstance3D.new()
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(5.0, 5.0)
	water.mesh = water_mesh
	water.position = Vector3(0.0, -0.65, 0.0)
	var water_material := ShaderMaterial.new()
	water_material.shader = EnvironmentWaterShader
	water_material.render_priority = -127
	web_render_resource_cache["water_material"] = water_material
	water.material_override = water_material
	root.add_child(water)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_energy = 0.98
	# Compatibility/Web disables the chapter-map directional shadow pass. Match
	# the production variant exactly or this warmup would compile the wrong one.
	sun.shadow_enabled = false
	root.add_child(sun)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0.0, 3.0, 5.4)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.make_current()
	await _warmup_draw_slice("배경과 조명", 15)

	var terrain_material := StandardMaterial3D.new()
	preload("res://chapter_map/view/web_map_material_policy.gd").apply(terrain_material)
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 0.94
	terrain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	web_render_resource_cache["terrain_material"] = terrain_material
	var terrain_tool := SurfaceTool.new()
	terrain_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in [Vector3(-1.4, -0.4, 0.0), Vector3(-0.2, -0.4, 0.0), Vector3(-0.8, 0.55, 0.0)]:
		terrain_tool.set_color(Color("52765a"))
		terrain_tool.set_normal(Vector3(0.0, 0.0, 1.0))
		terrain_tool.add_vertex(vertex)
	var terrain_instance := MeshInstance3D.new()
	terrain_instance.mesh = terrain_tool.commit()
	terrain_instance.material_override = terrain_material
	terrain_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(terrain_instance)
	await _warmup_draw_slice("지형 표현", 25)

	var prop_material := StandardMaterial3D.new()
	preload("res://chapter_map/view/web_map_material_policy.gd").apply(prop_material)
	prop_material.albedo_color = Color("4a3a2d")
	prop_material.roughness = 0.82
	prop_material.cull_mode = BaseMaterial3D.CULL_BACK
	web_render_resource_cache[_runtime_material_key(Color("4a3a2d"))] = prop_material
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.055
	trunk_mesh.bottom_radius = 0.075
	trunk_mesh.height = 0.28
	trunk_mesh.radial_segments = 5
	web_render_resource_cache["dressing_mesh:trunk"] = trunk_mesh
	var prop_multimesh := MultiMesh.new()
	prop_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	prop_multimesh.mesh = trunk_mesh
	prop_multimesh.instance_count = 2
	prop_multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0.15, 0.0, 0.0)))
	prop_multimesh.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(0.65, 0.0, 0.0)))
	var prop_instance := MultiMeshInstance3D.new()
	prop_instance.multimesh = prop_multimesh
	prop_instance.material_override = prop_material
	prop_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(prop_instance)
	await _warmup_draw_slice("환경 오브젝트", 35)

	var road_material := StandardMaterial3D.new()
	preload("res://chapter_map/view/web_map_material_policy.gd").apply(road_material)
	road_material.albedo_color = Color("c9a45d")
	road_material.roughness = 0.82
	road_material.cull_mode = BaseMaterial3D.CULL_BACK
	road_material.emission_enabled = true
	road_material.emission = Color("302714")
	road_material.emission_energy_multiplier = 1.4
	web_render_resource_cache[_runtime_material_key(Color("c9a45d"), Color("302714"))] = road_material
	var sleeper_mesh := BoxMesh.new()
	sleeper_mesh.size = Vector3(0.54, 0.055, 0.10)
	web_render_resource_cache["dressing_mesh:sleeper"] = sleeper_mesh
	var road_multimesh := MultiMesh.new()
	road_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	road_multimesh.mesh = sleeper_mesh
	road_multimesh.instance_count = 2
	road_multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(-0.45, 0.0, 0.55)))
	road_multimesh.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(0.45, 0.0, 0.55)))
	var road_instance := MultiMeshInstance3D.new()
	road_instance.multimesh = road_multimesh
	road_instance.material_override = road_material
	road_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(road_instance)
	await _warmup_draw_slice("길과 다리", 45)

	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.42
	marker_mesh.bottom_radius = 0.54
	marker_mesh.height = 0.15
	marker_mesh.radial_segments = 6
	web_render_resource_cache["fallback_marker_mesh"] = marker_mesh
	var signal_socket_mesh := CylinderMesh.new()
	signal_socket_mesh.top_radius = 1.18
	signal_socket_mesh.bottom_radius = 1.28
	signal_socket_mesh.height = 0.085
	signal_socket_mesh.radial_segments = 12
	web_render_resource_cache["signal_socket_mesh"] = signal_socket_mesh
	var signal_socket_instance := MeshInstance3D.new()
	signal_socket_instance.mesh = signal_socket_mesh
	signal_socket_instance.position = Vector3(1.2, -0.14, 0.0)
	signal_socket_instance.rotation_degrees.y = 15.0
	signal_socket_instance.material_override = prop_material
	root.add_child(signal_socket_instance)
	var marker_instance := MeshInstance3D.new()
	marker_instance.mesh = marker_mesh
	marker_instance.position = Vector3(1.2, 0.0, 0.0)
	var marker_material := StandardMaterial3D.new()
	preload("res://chapter_map/view/web_map_material_policy.gd").apply(marker_material)
	marker_material.albedo_color = Color("78eed9")
	marker_material.roughness = 0.82
	marker_material.cull_mode = BaseMaterial3D.CULL_BACK
	marker_material.emission_enabled = true
	marker_material.emission = Color("319f92")
	marker_material.emission_energy_multiplier = 1.4
	web_render_resource_cache[_runtime_material_key(Color("78eed9"), Color("319f92"))] = marker_material
	marker_instance.material_override = marker_material
	root.add_child(marker_instance)
	var marker_accent := OmniLight3D.new()
	marker_accent.light_color = Color("ffc77a")
	marker_accent.light_energy = 0.48
	marker_accent.omni_range = 3.35
	marker_accent.omni_attenuation = 1.75
	marker_accent.shadow_enabled = false
	marker_accent.position = Vector3(1.2, 0.72, 0.0)
	root.add_child(marker_accent)
	await _warmup_draw_slice("조우 표시", 55)

	var route_material := StandardMaterial3D.new()
	route_material.albedo_color = Color("4fd3c2d8")
	route_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	route_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	route_material.no_depth_test = true
	var route_mesh := ImmediateMesh.new()
	route_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, route_material)
	for vertex in [Vector3(-0.8, -0.8, 0.2), Vector3(0.8, -0.8, 0.2), Vector3(0.0, -0.58, 0.2)]:
		route_mesh.surface_add_vertex(vertex)
	route_mesh.surface_end()
	var route_instance := MeshInstance3D.new()
	route_instance.mesh = route_mesh
	root.add_child(route_instance)
	await _warmup_draw_slice("이동 경로", 60)

	var sprite_image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	sprite_image.fill(Color.WHITE)
	var sprite := Sprite3D.new()
	sprite.texture = ImageTexture.create_from_image(sprite_image)
	sprite.position = Vector3(0.0, 0.75, 0.3)
	sprite.pixel_size = 0.08
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	root.add_child(sprite)
	await _warmup_draw_slice("캐릭터 표시", 65)
	# An empty AwarenessCue creates no glyph surface until the first enemy turn.
	# Its ordinary alpha Label3D material differs from the opaque-prepass Sprite3D
	# above. GLES3 initializes its base, instanced and depth program variants together;
	# the measured cold turn spent ~230ms linking those five programs. Draw the exact
	# label flags and Korean glyphs now, while input/audio remain behind the boot gate.
	# Godot's get_material_for_2d cache retains the shader after this node is freed.
	root.add_child(create_map_awareness_warmup())
	await _warmup_draw_slice("적 인지 표시", 67)

	# Warm the actual R17 terrain/foliage/water shaders, not just the older
	# StandardMaterial placeholders. Both mesh and instanced variants are used
	# by real maps. Preparing them here avoids first-map and first-move compiles.
	var map_shaders := [
		preload("res://chapter_map/shaders/terrain_surface.gdshader"),
		preload("res://chapter_map/shaders/environment_surface.gdshader"),
		preload("res://chapter_map/shaders/forest_backdrop.gdshader"),
		preload("res://chapter_map/shaders/river_current.gdshader"),
		preload("res://chapter_map/shaders/ground_contact.gdshader"),
		preload("res://chapter_map/shaders/natural_river.gdshader"),
		preload("res://chapter_map/shaders/natural_river_bank.gdshader"),
	]
	for shader_index in map_shaders.size():
		var shader_material := ShaderMaterial.new()
		shader_material.shader = map_shaders[shader_index]
		if shader_index < 2 or shader_index == 6:
			shader_material.shader = preload("res://chapter_map/view/web_map_material_policy.gd").surface_shader(map_shaders[shader_index])
		var mesh_variant := MeshInstance3D.new()
		mesh_variant.mesh = terrain_instance.mesh
		mesh_variant.material_override = shader_material
		mesh_variant.position.z = 0.04 * float(shader_index + 1)
		mesh_variant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mesh_variant)
		var instanced_variant := MultiMeshInstance3D.new()
		instanced_variant.multimesh = prop_multimesh
		instanced_variant.material_override = shader_material
		instanced_variant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instanced_variant)
		web_render_resource_cache["r17_shader_material_%d" % shader_index] = shader_material
		await _warmup_draw_slice("맵 재질 %d / %d" % [shader_index + 1, map_shaders.size()], 70 + shader_index * 4)

	# The map's Web-only range and route presentation is Canvas-based so movement
	# never uploads three dynamic 3D meshes. Exercise the exact custom draw path
	# and a representative pool of rotated ColorRects here as well; otherwise the
	# first confirmed move still pays an 80-90ms one-time Canvas pipeline cost.
	var canvas_root := Control.new()
	canvas_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	warmup_viewport.add_child(canvas_root)
	var movement_overlay: Control = WebMovementOverlayScript.new()
	movement_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_root.add_child(movement_overlay)
	# World-space hex cells with an outer ring of border edges, projected through a
	# throwaway camera that frames them inside the 96px warm-up viewport.
	var sample_cells: Array = []
	for row in range(6):
		for column in range(7):
			var centre := Vector3(float(column) - 3.0 + (0.5 if row % 2 == 1 else 0.0), 0.2, float(row) * 0.87 - 2.2)
			var corners: Array[Vector3] = []
			for corner_index in range(6):
				var angle := PI / 6.0 + TAU * float(corner_index) / 6.0
				corners.append(centre + Vector3(cos(angle), 0.0, sin(angle)) * 0.5)
			sample_cells.append({"corners": corners, "boundary": 0x3F if row in [0, 5] or column in [0, 6] else 0})
	movement_overlay.call("set_world_cells", sample_cells)
	var sample_eye := Transform3D(Basis.looking_at(Vector3(0.0, -1.0, -0.55).normalized(), Vector3.UP), Vector3(0.0, 9.0, 5.5))
	var sample_to_clip := Projection.create_perspective(38.0, 1.0, 0.1, 100.0, false) * Projection(sample_eye.affine_inverse())
	movement_overlay.call("apply_view", sample_to_clip, Vector2(warmup_viewport.size), 1.0)
	# The map's tilt-shift/haze pass reads the screen copy; link it here so the first
	# map frame does not pay that compile (it sits under the same loading gate).
	var atmosphere_rect := ColorRect.new()
	atmosphere_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	atmosphere_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	atmosphere_rect.color = Color.WHITE
	var atmosphere_material := ShaderMaterial.new()
	atmosphere_material.shader = MapAtmosphereShader
	atmosphere_rect.material = atmosphere_material
	canvas_root.add_child(atmosphere_rect)
	for segment_index in range(48):
		var segment := ColorRect.new()
		segment.color = Color("4fd3c2")
		segment.size = Vector2(9.0, 2.0)
		segment.position = Vector2(float((segment_index * 11) % 88), float((segment_index * 7) % 88))
		segment.pivot_offset = segment.size * 0.5
		segment.rotation = float(segment_index % 6) * PI / 3.0
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas_root.add_child(segment)

	await _warmup_draw_slice("지도 표시", 96)
	for _frame_index in range(6):
		await get_tree().process_frame
	warmup_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Retain immutable Mesh/Material resources, never an attached disabled viewport.
	warmup_viewport.queue_free()
	web_render_warmup_complete = true
	print("WEB_MAP_WARMUP_COMPLETE %.2fms" % (float(Time.get_ticks_usec() - warmup_started_usec) / 1000.0))

func _add_title_pipeline_samples(canvas_root: Control) -> void:
	# The title's live-2D puppet and its lantern halo are two more canvas programs (the puppet is by
	# far the largest). Link them here, with the real textures bound, so the title does not
	# freeze for the compile when the intro ends.
	var puppet_rect := ColorRect.new()
	puppet_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	puppet_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	puppet_rect.color = Color.WHITE
	var puppet_material := ShaderMaterial.new()
	puppet_material.shader = TitlePuppetShader
	var title_rig := preload("res://ui/title_live2d_rig.gd")
	var hero_cfg: Dictionary = title_rig.HEROES["CHR001"]
	puppet_material.set_shader_parameter("hero_tex", load(title_rig.ASSET_DIR + String(hero_cfg.hero)))
	puppet_material.set_shader_parameter("mask_a", load(title_rig.ASSET_DIR + String(hero_cfg.mask_a)))
	puppet_material.set_shader_parameter("mask_b", load(title_rig.ASSET_DIR + String(hero_cfg.mask_b)))
	var lantern_cfg: Dictionary = hero_cfg.lantern
	puppet_material.set_shader_parameter("lantern_tex", load(title_rig.ASSET_DIR + String(lantern_cfg.file)))
	puppet_material.set_shader_parameter("lantern_rect", lantern_cfg.rect)
	puppet_material.set_shader_parameter("fx2", Vector4(1.0, 0.0, 0.0, 2.0))
	puppet_rect.material = puppet_material
	canvas_root.add_child(puppet_rect)
	var halo_rect := ColorRect.new()
	halo_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	halo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo_rect.color = Color.WHITE
	var halo_material := ShaderMaterial.new()
	halo_material.shader = TitleHaloShader
	halo_material.set_shader_parameter("rect_px", Vector2(96.0, 96.0))
	halo_material.set_shader_parameter("center_px", Vector2(48.0, 48.0))
	halo_material.set_shader_parameter("unit_px", 60.0)
	halo_rect.material = halo_material
	canvas_root.add_child(halo_rect)
	web_render_resource_cache["title_puppet_material"] = puppet_material
	web_render_resource_cache["title_halo_material"] = halo_material

static func create_map_awareness_warmup() -> Label3D:
	var awareness := Label3D.new()
	awareness.name = "MapAwarenessPipelineWarmup"
	awareness.text = "! 추적\n경계 복귀"
	awareness.font_size = 50
	awareness.outline_size = 9
	awareness.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	awareness.no_depth_test = true
	awareness.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	awareness.position = Vector3(0.0, 0.75, 0.6)
	return awareness

func _warmup_draw_slice(label: String, percent: int) -> void:
	if web_title_warmup_complete:
		web_map_pipeline_progress.emit(label, percent)
	else:
		_set_boot_loading_phase(label, percent)
	var started := Time.get_ticks_usec()
	# Flush each family in its own draw boundary; never pile all driver links
	# into a single frame. Map compiles use the existing map loading boundary;
	# they never recreate the startup overlay or reset the title-ready signal.
	await get_tree().process_frame
	await get_tree().process_frame
	print("WEB_RENDER_WARMUP_SLICE %s %.2fms" % [label, float(Time.get_ticks_usec()-started)/1000.0])

func _set_boot_loading_phase(label: String, percent: int) -> void:
	var message := JSON.stringify(label)
	JavaScriptBridge.eval("""(() => {
	let gate = document.getElementById('lantern-render-loading');
	if (!gate) {
	  gate = document.createElement('div'); gate.id='lantern-render-loading';
	  gate.setAttribute('role','status'); gate.setAttribute('aria-live','polite');
	  gate.style.cssText='position:fixed;inset:0;z-index:2147483646;display:flex;align-items:center;justify-content:center;background:radial-gradient(ellipse at 50%% 35%%,#143a43,#060e18 72%%);color:#e6f0ed;font-family:system-ui,sans-serif;text-align:center;touch-action:none';
	  gate.innerHTML='<style>@keyframes lanternBootSpin{to{transform:rotate(360deg)}}</style><div style="max-width:300px;padding:24px"><div style="margin:0 auto 22px;width:38px;height:38px;border:2px solid #24434b;border-top-color:#88dbc5;border-radius:50%%;animation:lanternBootSpin 1.1s linear infinite;will-change:transform"></div><div style="font-size:19px;letter-spacing:.08em">전투 세계 준비 중</div><div id="lantern-render-phase" style="font-size:14px;color:#aac3c6;margin-top:14px"></div><p style="font-size:12px;line-height:1.6;color:#8ca6ad">첫 실행은 그래픽 준비에 시간이 걸릴 수 있습니다.</p></div>';
	  document.body.appendChild(gate);
	  const blockKeys = event => {
	    if (document.getElementById('lantern-render-loading')) { event.preventDefault(); event.stopImmediatePropagation(); }
	    else { window.removeEventListener('keydown',blockKeys,true); window.removeEventListener('keyup',blockKeys,true); }
	  };
	  window.addEventListener('keydown',blockKeys,true); window.addEventListener('keyup',blockKeys,true);
	}
	document.getElementById('lantern-render-phase').textContent = %s + ' · %d%%';
	window.__lanternRenderReady = false;
	})();""" % [message, percent], true)

func _process(delta: float) -> void:
	var frame_msec := delta * 1000.0
	interval_max_frame_msec = maxf(interval_max_frame_msec, frame_msec)
	interval_frame_count += 1
	if frame_msec > 33.34: interval_frames_over_33ms += 1
	if frame_msec > 50.0: interval_frames_over_50ms += 1
	if frame_msec > 100.0: interval_frames_over_100ms += 1
	elapsed_seconds += delta
	sample_accumulator += delta
	if sample_accumulator < SAMPLE_INTERVAL_SECONDS:
		return
	sample_accumulator = fmod(sample_accumulator, SAMPLE_INTERVAL_SECONDS)
	_capture_sample()

func _capture_sample() -> void:
	var fps := float(Engine.get_frames_per_second())
	var static_memory := float(Performance.get_monitor(Performance.MEMORY_STATIC))
	var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	minimum_fps = min(minimum_fps, fps)
	maximum_static_memory = max(maximum_static_memory, static_memory)
	var sample := {
		"sample": samples.size() + 1,
		"elapsed_seconds": snappedf(elapsed_seconds, 0.001),
		"fps": fps,
		"static_memory_bytes": int(static_memory),
		"node_count": node_count,
		"orphan_node_count": orphan_count,
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"interval_frame_count": interval_frame_count,
		"max_frame_msec": snappedf(interval_max_frame_msec, 0.01),
		"frames_over_33ms": interval_frames_over_33ms,
		"frames_over_50ms": interval_frames_over_50ms,
		"frames_over_100ms": interval_frames_over_100ms,
		# Runtime playback evidence is intentionally metadata-only.  It proves
		# that the WebAudio gate opened and the wired events reached actual
		# AudioStreamPlayers without recording or exposing any audio content.
		"audio": AudioService.runtime_status(),
	}
	interval_max_frame_msec = 0.0
	interval_frames_over_33ms = 0
	interval_frames_over_50ms = 0
	interval_frames_over_100ms = 0
	interval_frame_count = 0
	if samples.size() >= MAX_SAMPLES:
		samples.pop_front()
	samples.append(sample)
	print("R7_WEB_SOAK_SAMPLE ", JSON.stringify(sample))
	# Emit a non-invasive namespace audit every 30 seconds.  This observes only
	# SaveService's resolved paths; it does not open or inspect production saves.
	if SaveService.is_soak_sandbox_enabled() and samples.size() % 6 == 0:
		print("R7_WEB_SOAK_SAVE_AUDIT ", JSON.stringify(SaveService.sandbox_audit_summary()))
	if samples.size() == MAX_SAMPLES:
		print("R7_WEB_SOAK_COMPLETE ", JSON.stringify(summary()))

func summary() -> Dictionary:
	var fps_total := 0.0
	for sample in samples:
		fps_total += float(sample.fps)
	var first_memory := int(samples.front().static_memory_bytes) if not samples.is_empty() else 0
	var last_memory := int(samples.back().static_memory_bytes) if not samples.is_empty() else 0
	var report := {
		"samples": samples.size(),
		"elapsed_seconds": snappedf(elapsed_seconds, 0.001),
		"average_fps": snappedf(fps_total / max(1, samples.size()), 0.01),
		"minimum_fps": minimum_fps if minimum_fps < 1000000.0 else 0.0,
		"memory_start_bytes": first_memory,
		"memory_end_bytes": last_memory,
		"memory_delta_bytes": last_memory - first_memory,
		"maximum_static_memory_bytes": int(maximum_static_memory),
		"orphan_nodes": int(samples.back().orphan_node_count) if not samples.is_empty() else 0,
	}
	if SaveService.is_soak_sandbox_enabled():
		report["save_sandbox_audit"] = SaveService.sandbox_audit_summary()
	return report
