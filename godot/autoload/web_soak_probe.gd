extends Node

const WebMovementOverlayScript := preload("res://chapter_map/runtime/web_movement_overlay.gd")
const EnvironmentWaterShader := preload("res://chapter_map/shaders/water_environment.gdshader")

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
		# WebGL creates several renderer variants lazily on their first visible draw.
		# Starting this before the trusted sound click moves those one-time compiles
		# into the silent boot gate instead of letting the first map entry, route
		# selection, or post-move yellow range starve WebAudio later.
		_prewarm_web_render_pipelines()

func _web_soak_sampling_requested() -> bool:
	if not OS.has_feature("web"):
		return false
	var value = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('r7-web-soak-probe')", true)
	return str(value).strip_edges().to_lower() in ["1", "true", "yes", "on"]

func _prewarm_web_render_pipelines() -> void:
	# Compatibility/Web compiles several 3D shader/pipeline variants on their first
	# visible draw. When that first draw happened during map entry it produced
	# repeated 100-150ms frames and starved the main-thread audio mixer. Render one
	# tiny representative scene before the user starts audio, then discard it; the
	# actual map can reuse the warmed vertex-colour, MultiMesh, sprite and overlay
	# pipelines without changing any gameplay or save state.
	if not OS.has_feature("web") or web_render_warmup_complete:
		return
	var warmup_started_usec := Time.get_ticks_usec()
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

	var terrain_material := StandardMaterial3D.new()
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

	var prop_material := StandardMaterial3D.new()
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

	var road_material := StandardMaterial3D.new()
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

	var sprite_image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	sprite_image.fill(Color.WHITE)
	var sprite := Sprite3D.new()
	sprite.texture = ImageTexture.create_from_image(sprite_image)
	sprite.position = Vector3(0.0, 0.75, 0.3)
	sprite.pixel_size = 0.08
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	root.add_child(sprite)

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
	var sample_cells: Array[PackedVector2Array] = []
	var sample_grid := PackedVector2Array()
	var sample_boundary := PackedVector2Array()
	for row in range(6):
		for column in range(7):
			var center := Vector2(7.0 + float(column) * 13.0 + (6.5 if row % 2 == 1 else 0.0), 8.0 + float(row) * 13.0)
			var polygon := PackedVector2Array([
				center + Vector2(-6.0, 0.0),
				center + Vector2(-3.0, -5.0),
				center + Vector2(3.0, -5.0),
				center + Vector2(6.0, 0.0),
				center + Vector2(3.0, 5.0),
				center + Vector2(-3.0, 5.0),
			])
			sample_cells.append(polygon)
			for edge_index in range(6):
				sample_grid.append(polygon[edge_index])
				sample_grid.append(polygon[(edge_index + 1) % 6])
				if row in [0, 5] or column in [0, 6]:
					sample_boundary.append(polygon[edge_index])
					sample_boundary.append(polygon[(edge_index + 1) % 6])
	movement_overlay.call("set_geometry", sample_cells, sample_grid, sample_boundary)
	for segment_index in range(48):
		var segment := ColorRect.new()
		segment.color = Color("4fd3c2")
		segment.size = Vector2(9.0, 2.0)
		segment.position = Vector2(float((segment_index * 11) % 88), float((segment_index * 7) % 88))
		segment.pivot_offset = segment.size * 0.5
		segment.rotation = float(segment_index % 6) * PI / 3.0
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas_root.add_child(segment)

	# Six actual draw frames cover 3D and Canvas pipeline creation plus two steady
	# frames. This completes while audio is still locked by the browser.
	for _frame_index in range(6):
		await get_tree().process_frame
	warmup_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# A disabled SubViewport must not remain attached in the Web build. Godot's
	# single-threaded Compatibility renderer may later dereference one of its
	# released scene objects and leave the canvas black while audio keeps playing.
	# The warmed driver programs survive this short-lived viewport; scene owners do
	# not need to remain in the active tree.
	warmup_viewport.queue_free()
	web_render_warmup_complete = true
	print("WEB_RENDER_WARMUP_COMPLETE %.2fms" % (float(Time.get_ticks_usec() - warmup_started_usec) / 1000.0))

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
