class_name ChapterMapScreen
extends Control

signal battle_requested(stage_id: String)
signal formation_requested
signal fallback_requested
signal sweep_requested(stage_id: String, count: int)
signal treasure_reward_requested(report: Dictionary)

const MAP_ID := "CH01_MAP"
const TILE_SIZE := 1.08
const VIEWPORT_SIZE := Vector2i(1280, 720)
const STREAM_RADIUS := 8
const PAWN_VISUAL_BASE_Y := 0.56
const PAWN_STEP_DURATION := 0.28
const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const HexGridScript := preload("res://chapter_map/model/hex_grid.gd")
const HexPathfinderScript := preload("res://chapter_map/model/hex_pathfinder.gd")
const ChapterMapLoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const ChapterMapProgressScript := preload("res://chapter_map/model/chapter_map_progress.gd")
const ChapterRouteMinimapScript := preload("res://chapter_map/ui/chapter_route_minimap.gd")
const MapExplorationServiceScript := preload("res://chapter_map/model/map_exploration_service.gd")

var definition: Dictionary
var grid = HexGridScript.new()
var map_state: Dictionary
var viewport: SubViewport
var viewport_container: SubViewportContainer
var overlay: Control
var map_area: Control
var map_frame: PanelContainer
var camera: Camera3D
var camera_target := Vector3.ZERO
var camera_zoom := 1.0
var world_root: Node3D
var pawn: Node3D
var pawn_visual: Node3D
var pawn_banner: MeshInstance3D
var pawn_sprite: Sprite3D
var pawn_motion_state := "IDLE"
var pawn_motion_phase := 0.0
var pawn_last_position := Vector3.ZERO
var node_buttons: Dictionary = {}
var node_markers: Dictionary = {}
var enemy_pawns: Dictionary = {}
var enemy_animation_packs: Dictionary = {}
var treasure_visuals: Dictionary = {}
var tile_meshes: Dictionary = {}
var tile_dressing_roots: Dictionary = {}
var active_dressing_root: Node3D
var stream_anchor := Vector2i(999999, 999999)
var blender_mesh_library: Dictionary = {}
var route_mesh: MeshInstance3D
var route_segments: Array[MeshInstance3D] = []
var route_nodes: Array[MeshInstance3D] = []
var selected_ring: MeshInstance3D
var selected_node: Dictionary = {}
var selected_treasure: Dictionary = {}
var preview_path: Array[Vector2i] = []
var detail_title: Label
var detail_body: RichTextLabel
var move_button: Button
var battle_button: Button
var fast_travel_button: Button
var sweep_buttons: Array[Button] = []
var status_label: Label
var next_encounter_button: Button
var legend_card: PanelContainer
var legend_label: Label
var route_minimap: ChapterRouteMinimap
var moving := false
var movement_generation := 0
var active_movement_path: Array[Vector2i] = []
var pawn_step_trails: Array[MeshInstance3D] = []
var movement_camera_tween: Tween
var dragging := false
var drag_origin := Vector2.ZERO
var camera_origin := Vector3.ZERO
var hard_overlay := false
var toolbar: HBoxContainer
var map_toolbar_buttons: Array[Button] = []
var detail_panel: PanelContainer
var detail_scroll: ScrollContainer
var compact_optional_buttons: Array[Control] = []

func _ready() -> void:
	definition = ChapterMapLoaderScript.load_map(MAP_ID)
	grid.load_tiles(definition.get("tiles", []))
	map_state = AppState.chapter_map_state(MAP_ID)
	MapExplorationServiceScript.ensure_state(map_state, definition)
	MapExplorationServiceScript.update_hidden_proximity(map_state, definition, Vector2i(int(map_state.current_q), int(map_state.current_r)))
	camera_zoom = clampf(float(map_state.get("camera_zoom", 1.0)), 0.72, 1.55)
	_build_interface()
	_build_world()
	_refresh_state_visuals()
	_focus_current(true)

func _build_interface() -> void:
	# This screen lives inside AppShell's content VBox.  Viewport-wide anchors
	# make it cover the shell header on compact portrait displays, so the parent
	# container owns our bounds instead.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	# The root may fill ChapterMapScreen; ChapterMapScreen itself is constrained
	# by AppShell's content container above.
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.custom_minimum_size = Vector2(0.0, 280.0)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	toolbar = HBoxContainer.new()
	root.add_child(toolbar)
	var normal_button := _button("일반 작전", func(): hard_overlay = false; _refresh_state_visuals(), Vector2(128, 56))
	var hard_button := _button("위험 작전", func(): hard_overlay = true; _refresh_state_visuals(), Vector2(128, 56))
	var current_button := _button("현재 부대", func(): _focus_current(false), Vector2(116, 56))
	var overview_button := _button("구역 개요", _focus_full_map, Vector2(116, 56))
	var skip_button := _button("이동 건너뛰기", skip_movement, Vector2(132, 56))
	for action_button in [normal_button, hard_button, current_button, overview_button, skip_button]:
		toolbar.add_child(action_button)
		map_toolbar_buttons.append(action_button)
	var formation := _button("파티 편성", func(): formation_requested.emit(), Vector2(116, 56))
	toolbar.add_child(formation)
	compact_optional_buttons.append(formation)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	var fallback := _button("목록형 접근성", func(): fallback_requested.emit(), Vector2(150, 56))
	toolbar.add_child(fallback)
	compact_optional_buttons.append(fallback)
	map_area = Control.new()
	map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(map_area)
	map_frame = PanelContainer.new()
	map_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_frame.clip_contents = true
	# The map is the primary product surface, not a developer canvas.  Keep the
	# frame as a dark vignette without a persistent cyan debug-outline.
	map_frame.add_theme_stylebox_override("panel", _panel_style(Color("071b2cdd"), Color("17384b"), 0, 15))
	map_area.add_child(map_frame)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_frame.add_child(layer)
	viewport_container = SubViewportContainer.new()
	# The container owns presentation sizing so the 3D map fills both desktop and
	# portrait layouts.  Do not manually resize its SubViewport while this is on:
	# Godot rejects that combination and emits a warning on each reflow.
	viewport_container.stretch = true
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.gui_input.connect(_on_map_input)
	layer.add_child(viewport_container)
	viewport = SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport_container.add_child(viewport)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The overlay carries actual stage buttons. PASS keeps transparent space
	# available for map pan while allowing those children to receive a tap.
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	# A PASS control is above the SubViewportContainer, so route its transparent
	# tap/drag area explicitly. Without this, portrait taps can visually land on
	# a marker yet never reach the mathematical nearest-node selector.
	overlay.gui_input.connect(_on_map_input)
	layer.add_child(overlay)
	status_label = Label.new()
	status_label.position = Vector2(22, 18)
	status_label.add_theme_font_size_override("font_size", 22)
	status_label.add_theme_color_override("font_shadow_color", Color("031018"))
	status_label.add_theme_constant_override("shadow_offset_x", 2)
	status_label.add_theme_constant_override("shadow_offset_y", 2)
	status_label.modulate = Color("d7f8ef")
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(status_label)
	# A macro chapter map deliberately places upcoming encounters outside the
	# current camera window.  This is a player-facing navigation aid, not a
	# debug warp: it selects the next real stage node so route preview, movement
	# confirmation, stamina transaction, and battle entry remain unchanged.
	next_encounter_button = _button("다음 조우", _select_next_encounter, Vector2(248, 52))
	next_encounter_button.tooltip_text = "현재 공개된 다음 조우로 카메라 이동"
	overlay.add_child(next_encounter_button)
	legend_card = PanelContainer.new()
	legend_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	legend_card.position = Vector2(18, -58)
	legend_card.add_theme_stylebox_override("panel", _panel_style(Color("071421d9"), Color("315369"), 1, 9))
	overlay.add_child(legend_card)
	legend_label = Label.new()
	legend_label.text = "◆ 현재 부대   ◇ 도달 가능   ✓ 클리어   ★ 완전 클리어   🔒 잠김"
	legend_label.add_theme_font_size_override("font_size", 16)
	legend_label.modulate = Color("d4def0")
	legend_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend_card.add_child(legend_label)
	route_minimap = ChapterRouteMinimapScript.new()
	route_minimap.name = "ChapterRouteMinimap"
	route_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	route_minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	overlay.add_child(route_minimap)
	detail_panel = PanelContainer.new()
	detail_panel.add_theme_stylebox_override("panel", _panel_style(Color("0c1b2af7"), Color("64d7c2"), 2, 16))
	map_area.add_child(detail_panel)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_child(detail_scroll)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 9)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail_box)
	detail_title = Label.new()
	detail_title.add_theme_font_size_override("font_size", 28)
	detail_title.add_theme_color_override("font_color", Color("e9fff9"))
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(detail_title)
	detail_body = RichTextLabel.new()
	detail_body.bbcode_enabled = true
	detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_body.add_theme_font_size_override("normal_font_size", 17)
	detail_body.add_theme_color_override("default_color", Color("d8e7ef"))
	detail_body.custom_minimum_size = Vector2(350, 278)
	detail_box.add_child(detail_body)
	move_button = _button("경로를 따라 이동", _confirm_move)
	detail_box.add_child(move_button)
	fast_travel_button = _button("클리어 지점 빠른 이동", _fast_travel)
	detail_box.add_child(fast_travel_button)
	battle_button = _button("기존 실시간 전투 시작", _request_battle)
	detail_box.add_child(battle_button)
	var sweep_row := HBoxContainer.new()
	detail_box.add_child(sweep_row)
	for raw_count in [1, 5, 10]:
		var count: int = int(raw_count)
		var sweep := _button("소탕 %d" % count, func(value: int = count): _request_sweep(value), Vector2(112, 58))
		sweep_buttons.append(sweep)
		sweep_row.add_child(sweep)
	detail_box.add_child(_button("선택 취소", _clear_selection))
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_update_panel()

func _apply_responsive_layout() -> void:
	if detail_panel == null or map_frame == null: return
	var size := _runtime_layout_size()
	var portrait := size.y > size.x
	var ui_scale := _portrait_ui_scale(size)
	var compact := portrait or size.x <= 980.0
	for index in range(map_toolbar_buttons.size()):
		var action_button := map_toolbar_buttons[index]
		if portrait:
			action_button.custom_minimum_size = Vector2(68.0 * ui_scale, 50.0 * ui_scale)
			action_button.add_theme_font_size_override("font_size", roundi(15.0 * ui_scale))
			action_button.text = ["일반", "위험", "부대", "개요", "스킵"][index]
		else:
			action_button.custom_minimum_size = [Vector2(128, 56), Vector2(128, 56), Vector2(116, 56), Vector2(116, 56), Vector2(132, 56)][index]
			action_button.add_theme_font_size_override("font_size", 18)
			action_button.text = ["일반 작전", "위험 작전", "현재 부대", "구역 개요", "이동 건너뛰기"][index]
	if status_label != null:
		status_label.position = Vector2(14.0 * ui_scale, 14.0 * ui_scale) if portrait else Vector2(22, 18)
		status_label.add_theme_font_size_override("font_size", roundi(17.0 * ui_scale) if portrait else 22)
	if next_encounter_button != null:
		var next_width := 188.0 * ui_scale if portrait else 248.0
		var next_height := 48.0 * ui_scale if portrait else 52.0
		next_encounter_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		next_encounter_button.offset_left = -next_width - (12.0 * ui_scale if portrait else 18.0)
		next_encounter_button.offset_right = -(12.0 * ui_scale if portrait else 18.0)
		next_encounter_button.offset_top = 14.0 * ui_scale if portrait else 18.0
		next_encounter_button.offset_bottom = next_encounter_button.offset_top + next_height
		next_encounter_button.add_theme_font_size_override("font_size", roundi(16.0 * ui_scale) if portrait else 17)
	if legend_card != null:
		legend_card.visible = not portrait
		legend_card.position = Vector2(12.0 * ui_scale, -112.0 * ui_scale) if portrait else Vector2(18, -58)
		legend_card.custom_minimum_size = Vector2(0.0, 76.0 * ui_scale) if portrait else Vector2.ZERO
	if legend_label != null:
		legend_label.add_theme_font_size_override("font_size", roundi(14.0 * ui_scale) if portrait else 16)
	if route_minimap != null:
		if portrait:
			var map_width := clampf(size.x * 0.52, 176.0, 244.0)
			route_minimap.custom_minimum_size = Vector2(map_width, 132.0)
			route_minimap.position = Vector2(12.0, -154.0)
		else:
			route_minimap.custom_minimum_size = Vector2(230.0, 150.0)
			route_minimap.position = Vector2(18.0, -224.0)
	# Node labels are actual stage-selection controls. They must retain an
	# explicit phone-sized hit region instead of shrinking with the 1920 canvas.
	for node_id in node_buttons:
		var node_button: Button = node_buttons[node_id]
		if portrait:
			node_button.custom_minimum_size = Vector2(72.0 * ui_scale, 56.0 * ui_scale)
			node_button.size = node_button.custom_minimum_size
			node_button.add_theme_font_size_override("font_size", roundi(15.0 * ui_scale))
		else:
			node_button.custom_minimum_size = Vector2(86.0, 40.0)
			node_button.size = Vector2(86.0, 40.0)
			node_button.add_theme_font_size_override("font_size", 15)
	var has_selection := not selected_node.is_empty() or not selected_treasure.is_empty()
	if compact:
		# A real mobile bottom sheet reserves the top status strip and bottom safe
		# area before it takes map space. It is not a desktop right panel scaled down.
		map_frame.offset_right = 0.0
		detail_panel.anchor_left = 0.0
		detail_panel.anchor_right = 1.0
		detail_panel.anchor_top = 1.0
		detail_panel.anchor_bottom = 1.0
		detail_panel.offset_left = 8.0 * ui_scale if portrait else 16.0
		detail_panel.offset_right = -8.0 * ui_scale if portrait else -16.0
		detail_panel.offset_top = -330.0 * ui_scale if portrait else -246.0
		detail_panel.offset_bottom = -8.0 * ui_scale if portrait else -16.0
		detail_panel.visible = has_selection
		detail_body.custom_minimum_size = Vector2(0.0, 84.0 * ui_scale if portrait else 102.0)
		detail_body.add_theme_font_size_override("normal_font_size", roundi(17.0 * ui_scale) if portrait else 17)
	else:
		var show_detail := has_selection
		map_frame.offset_right = -414.0 if show_detail else 0.0
		detail_panel.anchor_left = 1.0
		detail_panel.anchor_right = 1.0
		detail_panel.anchor_top = 0.0
		detail_panel.anchor_bottom = 1.0
		detail_panel.offset_left = -400.0
		detail_panel.offset_right = -12.0
		detail_panel.offset_top = 0.0
		detail_panel.offset_bottom = 0.0
		detail_panel.visible = show_detail
		detail_body.custom_minimum_size = Vector2(350.0, 278.0)
	if compact_optional_buttons.size() >= 2:
		compact_optional_buttons[0].visible = not compact
		compact_optional_buttons[1].visible = not compact

func _runtime_layout_width() -> float:
	return _runtime_layout_size().x

func _runtime_layout_size() -> Vector2:
	var window_size := DisplayServer.window_get_size()
	var width := float(window_size.x)
	var height := float(window_size.y)
	# Web exports keep the logical Godot width while CSS scales the canvas.
	# Read browser dimensions explicitly so portrait phones get a true mobile
	# sheet and correctly proportioned 3D render target.
	if OS.has_feature("web"):
		var browser_width = JavaScriptBridge.eval("window.innerWidth", true)
		var browser_height = JavaScriptBridge.eval("window.innerHeight", true)
		if browser_width is int or browser_width is float:
			width = float(browser_width)
		if browser_height is int or browser_height is float:
			height = float(browser_height)
	return Vector2(width, height)

func _portrait_ui_scale(runtime_size: Vector2) -> float:
	if runtime_size.y <= runtime_size.x: return 1.0
	return clampf(1920.0 / maxf(320.0, runtime_size.x), 2.8, 4.9)

func _panel_style(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style

func _button(text_value: String, callback: Callable, minimum := Vector2(350, 58)) -> Button:
	var button := Button.new()
	button.text = text_value
	var runtime_size := _runtime_layout_size()
	var ui_scale := _portrait_ui_scale(runtime_size)
	button.custom_minimum_size = Vector2(minf(minimum.x * ui_scale, 840.0), minimum.y * ui_scale) if runtime_size.y > runtime_size.x else minimum
	button.add_theme_font_size_override("font_size", roundi(18.0 * ui_scale))
	button.add_theme_stylebox_override("normal", _panel_style(Color("102d43"), Color("3f7798"), 1, 11))
	button.add_theme_stylebox_override("hover", _panel_style(Color("1b5369"), Color("84f2db"), 2, 11))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("17485d"), Color("ffd17b"), 2, 11))
	button.pressed.connect(callback)
	return button

func _build_world() -> void:
	world_root = Node3D.new()
	world_root.name = "ChapterMapWorld"
	viewport.add_child(world_root)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("05131f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("7fa89d")
	environment.ambient_light_energy = 0.38
	# The map uses a restrained filmic pass and a very low fog density to make
	# elevation, coast and distant route sections recede. This is visual depth,
	# not a gameplay fog-of-war substitute.
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.72
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.82
	environment.adjustment_contrast = 1.16
	environment.adjustment_saturation = 0.86
	environment.fog_enabled = true
	environment.fog_light_color = Color("0a3145")
	environment.fog_light_energy = 0.46
	environment.fog_density = 0.0022
	environment.fog_sky_affect = 0.42
	world_environment.environment = environment
	world_root.add_child(world_environment)
	_create_world_backdrop()
	_create_world_island_shelf()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54, -38, 0)
	sun.light_color = Color("ffeac4")
	sun.light_energy = 0.82
	# A single bounded compatibility shadow makes terrain height and pawn contact
	# readable without adding a multi-light shadow budget to mobile Web.
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 26.0
	sun.directional_shadow_fade_start = 0.72
	sun.light_angular_distance = 1.8
	world_root.add_child(sun)
	_load_blender_kit()
	_stream_visible_tiles(Vector2i(int(map_state.current_q), int(map_state.current_r)), true)
	route_mesh = MeshInstance3D.new()
	world_root.add_child(route_mesh)
	selected_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.54
	ring_mesh.outer_radius = 0.66
	ring_mesh.rings = 8
	ring_mesh.ring_segments = 24
	selected_ring.mesh = ring_mesh
	selected_ring.material_override = _material(Color("6ff6dd"), Color("28d7bd"))
	selected_ring.visible = false
	world_root.add_child(selected_ring)
	for node in definition.get("nodes", []):
		_create_node_marker(node)
		_create_node_button(node)
		if str(node.get("stage_id", "")) != "":
			_create_enemy_pawn(node)
	for treasure in definition.get("treasures", []):
		_create_treasure_visual(treasure)
	# Nodes are created after the initial interface reflow. Apply the active
	# viewport profile once more so first-load portrait controls are touch-sized.
	_apply_responsive_layout()
	_create_pawn()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.2 / camera_zoom
	camera.near = 0.1
	camera.far = 100.0
	world_root.add_child(camera)
	camera.make_current()

func _material(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.4
	return material

func _create_world_backdrop() -> void:
	# A low-cost water field makes hidden territory read as a real coastline rather
	# than a black prototype board. It has no gameplay or tile-selection role.
	var water := MeshInstance3D.new()
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(360.0, 220.0)
	water.mesh = water_mesh
	water.position = Vector3(1.8, -0.58, -1.8)
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; void fragment(){ float t=TIME*0.24; vec2 p=UV*18.0; float w=sin(p.x*2.4+p.y*1.7+t)*0.5+0.5; float r=sin(p.y*4.1-p.x*1.3-t*0.7)*0.5+0.5; float ripple=smoothstep(0.82,0.97,fract(p.x*0.42+p.y*0.78+t*0.38)); vec3 deep=vec3(0.012,0.058,0.105); vec3 tide=vec3(0.028,0.19,0.27); ALBEDO=mix(deep,tide,w*0.44+r*0.13)+vec3(0.018,0.075,0.082)*ripple; EMISSION=vec3(0.0,0.042,0.066)*(w*0.36+ripple*0.22); }"
	var water_material := ShaderMaterial.new()
	water_material.shader = shader
	water.material_override = water_material
	water.set_meta("water_material", water_material)
	world_root.add_child(water)
	var horizon := MeshInstance3D.new()
	var horizon_mesh := PlaneMesh.new()
	horizon_mesh.size = Vector2(320.0, 92.0)
	horizon.mesh = horizon_mesh
	horizon.position = Vector3(1.0, 2.8, -8.7)
	horizon.rotation_degrees.x = 90.0
	horizon.material_override = _material(Color("0a2433"), Color("082937"))
	world_root.add_child(horizon)

func _create_world_island_shelf() -> void:
	# The tactical grid remains mathematical, but its visual support is an
	# authored coastline.  This is deliberately sized from the complete route,
	# not the first streamed screen: a long chapter must not turn back into a
	# sequence of detached island-board pieces as the squad walks away from start.
	var route_points: Array[Vector3] = []
	for node in definition.get("nodes", []):
		if str(node.get("node_type", "")) == "START" or str(node.get("stage_id", "")) != "":
			route_points.append(HexCoordScript.axial_to_world(Vector2i(int(node.get("q", 0)), int(node.get("r", 0))), TILE_SIZE))
	if route_points.is_empty():
		route_points.append(Vector3.ZERO)
	var min_x := route_points[0].x
	var max_x := route_points[0].x
	var min_z := route_points[0].z
	var max_z := route_points[0].z
	for point in route_points:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
	var shelf_center := Vector3((min_x + max_x) * 0.5, -0.95, (min_z + max_z) * 0.5)
	# A broad tapered shelf sits beneath the entire authored route.  The edge is
	# intentionally well outside the local stream radius, so it reads as a coast
	# at chapter scale rather than as an artificial blue hex perimeter.
	var shelf_radius := maxf(max_x - min_x, max_z - min_z * 1.2) * 0.58 + 14.0
	var shelf_aspect := Vector3(1.18, 1.0, 0.62)
	var deep_shelf := MeshInstance3D.new()
	var deep_mesh := CylinderMesh.new()
	deep_mesh.top_radius = shelf_radius
	deep_mesh.bottom_radius = shelf_radius + 2.8
	deep_mesh.height = 0.82
	deep_mesh.radial_segments = 36
	deep_shelf.mesh = deep_mesh
	deep_shelf.position = shelf_center
	deep_shelf.scale = shelf_aspect
	deep_shelf.material_override = _material(Color("12322f"), Color("082c2b"))
	world_root.add_child(deep_shelf)
	var moss_shelf := MeshInstance3D.new()
	var moss_mesh := CylinderMesh.new()
	moss_mesh.top_radius = shelf_radius - 2.2
	moss_mesh.bottom_radius = shelf_radius - 0.9
	moss_mesh.height = 0.34
	moss_mesh.radial_segments = 36
	moss_shelf.mesh = moss_mesh
	moss_shelf.position = shelf_center + Vector3(0.0, 0.48, 0.0)
	moss_shelf.scale = shelf_aspect
	moss_shelf.material_override = _material(Color("234e43"), Color("103b38"))
	world_root.add_child(moss_shelf)

func _load_blender_kit() -> void:
	var kit_path := "res://assets/art/chapter_map/R7/CH01_MAP_KIT_R7.glb"
	if not ResourceLoader.exists(kit_path): return
	var packed := load(kit_path) as PackedScene
	if packed == null: return
	var kit := packed.instantiate()
	_collect_kit_meshes(kit)
	kit.free()

func _collect_kit_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		blender_mesh_library[str(node.name)] = {
			"mesh": mesh_node.mesh,
			"scale": mesh_node.scale,
			"rotation": mesh_node.rotation
		}
	for child in node.get_children(): _collect_kit_meshes(child)

func _kit_mesh_for(terrain: String) -> Mesh:
	var prefix: String = str({
		"FOREST": "HEX_FOREST_",
		"ROAD": "HEX_ROAD_",
		"RUINS": "HEX_RUIN_",
		"SHALLOW_WATER": "HEX_WATER_",
		"DEEP_WATER": "HEX_DEEP_"
	}.get(terrain, "HEX_FOREST_"))
	for key in blender_mesh_library:
		if str(key).begins_with(prefix): return blender_mesh_library[key].mesh
	return null

func _create_tile(tile: Dictionary) -> void:
	var coord := Vector2i(int(tile.q), int(tile.r))
	var terrain_type := str(tile.terrain_type)
	# Water is represented by the continuous tide field and island coastline.
	# It stays fully present in Grid data for pathing/reveal, without rendering a
	# literal hex-board sea around the land.
	if terrain_type in ["SHALLOW_WATER", "DEEP_WATER"]:
		return
	var instance := MeshInstance3D.new()
	var surface_y := float(tile.elevation) * 0.42
	# Each traversable cell has a compact, low-poly land cap.  It is intentionally
	# not a flat coloured board: stacked side walls make the seeded elevation tiers
	# legible even when the camera is close to the moving squad.
	var elevation := int(tile.elevation)
	var cap := CylinderMesh.new()
	cap.top_radius = TILE_SIZE * .96
	cap.bottom_radius = TILE_SIZE * (1.01 + minf(float(elevation), 3.0) * .025)
	cap.height = .22 + float(elevation) * .24
	cap.radial_segments = 6
	instance.mesh = cap
	instance.rotation_degrees.y = 30.0
	instance.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y - cap.height * .5)
	instance.set_meta("tile", tile)
	instance.set_meta("blender_kit", false)
	world_root.add_child(instance)
	tile_meshes[HexCoordScript.key(coord)] = instance
	active_dressing_root = Node3D.new()
	active_dressing_root.name = "TerrainDressing_%s" % HexCoordScript.key(coord)
	world_root.add_child(active_dressing_root)
	tile_dressing_roots[HexCoordScript.key(coord)] = active_dressing_root
	_create_terrain_dressing(tile, HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y), coord)
	active_dressing_root = null

func _stream_visible_tiles(center: Vector2i, force := false) -> void:
	if not force and HexCoordScript.distance(stream_anchor, center) < 3:
		return
	stream_anchor = center
	var wanted: Dictionary = {}
	for tile in definition.get("tiles", []):
		var coord := Vector2i(int(tile.q), int(tile.r))
		if HexCoordScript.distance(center, coord) <= STREAM_RADIUS:
			wanted[HexCoordScript.key(coord)] = tile
	for key in tile_meshes.keys():
		if wanted.has(str(key)):
			continue
		var stale: MeshInstance3D = tile_meshes[key]
		if is_instance_valid(stale):
			stale.queue_free()
		var dressing: Node3D = tile_dressing_roots.get(key)
		if is_instance_valid(dressing):
			dressing.queue_free()
		tile_meshes.erase(key)
		tile_dressing_roots.erase(key)
	for key in wanted:
		if not tile_meshes.has(key):
			_create_tile(wanted[key])

func _kit_component(prefix: String) -> Dictionary:
	for key in blender_mesh_library:
		if str(key).begins_with(prefix): return blender_mesh_library[key]
	return {}

func _spawn_kit_component(prefix: String, location: Vector3, scale_factor := 1.0, yaw := 0.0, parent: Node3D = null) -> MeshInstance3D:
	var info := _kit_component(prefix)
	var mesh: Mesh = info.get("mesh")
	if mesh == null: return null
	var part := MeshInstance3D.new()
	part.name = prefix
	part.mesh = mesh
	part.position = location
	part.scale = info.get("scale", Vector3.ONE) * scale_factor
	part.rotation = info.get("rotation", Vector3.ZERO)
	part.rotation.y += yaw
	if parent != null:
		parent.add_child(part)
	elif active_dressing_root != null:
		active_dressing_root.add_child(part)
	else:
		world_root.add_child(part)
	return part

func _spawn_kit_components(prefix: String, location: Vector3, scale_factor := 1.0, yaw := 0.0, parent: Node3D = null) -> Array[MeshInstance3D]:
	var spawned: Array[MeshInstance3D] = []
	for key in blender_mesh_library:
		if not str(key).begins_with(prefix):
			continue
		var info: Dictionary = blender_mesh_library[key]
		var mesh: Mesh = info.get("mesh")
		if mesh == null:
			continue
		var part := MeshInstance3D.new()
		part.name = str(key)
		part.mesh = mesh
		part.position = location
		part.scale = info.get("scale", Vector3.ONE) * scale_factor
		part.rotation = info.get("rotation", Vector3.ZERO)
		part.rotation.y += yaw
		if parent != null:
			parent.add_child(part)
		elif active_dressing_root != null:
			active_dressing_root.add_child(part)
		else:
			world_root.add_child(part)
		spawned.append(part)
	return spawned

func _has_node_at(coord: Vector2i) -> bool:
	for node in definition.get("nodes", []):
		if int(node.q) == coord.x and int(node.r) == coord.y: return true
	return false

func _create_terrain_dressing(tile: Dictionary, tile_position: Vector3, coord: Vector2i) -> void:
	var terrain := str(tile.terrain_type)
	var variant := int(tile.visual_variant)
	var yaw := float(tile.rotation_step) * PI / 3.0
	var elevated := int(tile.elevation) > 0
	if elevated:
		var height_scale := 0.94 + float(int(tile.elevation)) * 0.12
		_spawn_kit_component("PROP_CLIFF_FACET_A", tile_position + Vector3(-0.62, -0.06, 0.14), height_scale, yaw)
		_spawn_kit_component("PROP_CLIFF_FACET_B", tile_position + Vector3(0.44, -0.08, -0.48), height_scale * .82, yaw + 0.8)
		for strata_index in range(5):
			_spawn_kit_component("PROP_STRATA_RING_STRATUM_%d" % strata_index, tile_position + Vector3(0.0, -0.04, 0.02), height_scale, yaw)
	var terrain_cluster := terrain == "FOREST" and variant in [0, 4, 7]
	if terrain_cluster:
		_spawn_kit_components("PROP_TERRAIN_FOREST", tile_position + Vector3(0.0, 0.04, 0.0), 0.92 + float(int(tile.elevation)) * .05, yaw)
	elif terrain == "RUINS" and variant in [1, 5]:
		_spawn_kit_components("PROP_TERRAIN_RUIN", tile_position + Vector3(0.0, 0.04, 0.0), 0.86, yaw)
	if terrain == "FOREST" and not _has_node_at(coord):
		# Place silhouette props on selected seeded variants rather than every
		# forest hex.  The cleared gaps make the long route readable and avoid a
		# synthetic grid of identical tree crowns.
		if not terrain_cluster and variant in [0, 3, 5, 7]:
			var prop_offset := Vector3(-0.37, 0.42, 0.26) if variant % 2 == 0 else Vector3(0.38, 0.42, -0.30)
			var tree_prefix := "PROP_TREE_A" if variant % 2 == 0 else "PROP_TREE_B"
			var tree_scale := 1.02 + float(variant % 3) * 0.12
			_spawn_kit_component(tree_prefix + "_TRUNK", tile_position + prop_offset, tree_scale, yaw)
			_spawn_kit_component(tree_prefix + "_CROWN_0", tile_position + prop_offset + Vector3(0.0, 0.58, 0.0), tree_scale, yaw)
			_spawn_kit_component(tree_prefix + "_CROWN_1", tile_position + prop_offset + Vector3(0.15, 0.70, -0.10), tree_scale, yaw)
			_spawn_kit_component(tree_prefix + "_CROWN_2", tile_position + prop_offset + Vector3(-0.15, 0.75, 0.10), tree_scale, yaw)
			if variant == 0:
				var companion_offset := Vector3(0.37, 0.42, -0.22)
				_spawn_kit_component("PROP_TREE_B_TRUNK", tile_position + companion_offset, 0.72, yaw + 0.55)
				_spawn_kit_component("PROP_TREE_B_CROWN_0", tile_position + companion_offset + Vector3(0.0, 0.48, 0.0), 0.72, yaw + 0.55)
				_spawn_kit_component("PROP_TREE_B_CROWN_1", tile_position + companion_offset + Vector3(0.12, 0.60, -0.08), 0.72, yaw + 0.55)
		elif variant in [1, 4]:
			_spawn_kit_component("PROP_CRYSTAL_SHARD_1", tile_position + Vector3(0.34, 0.13, 0.18), 0.72, yaw)
	elif terrain == "RUINS":
		_spawn_kit_component("PROP_RUIN_RELAY_0", tile_position + Vector3(0.34, 0.23, -0.20), 0.86, yaw)
		_spawn_kit_component("PROP_RUIN_RELAY_1", tile_position + Vector3(0.34, 0.18, -0.20), 0.86, yaw)
		_spawn_kit_component("PROP_RUIN_RELAY_ARCH", tile_position + Vector3(0.30, 0.38, -0.20), 0.86, yaw)
		if variant != 0:
			_spawn_kit_component("PROP_RELAY_LAMP_LANTERN", tile_position + Vector3(-0.28, 0.60, 0.25), 0.72, yaw)
	elif terrain == "ROAD":
		# The route is a real severed signal rail.  It is visible independently of
		# the mathematical tile beneath it, so this cannot read as coloured hexes.
		_spawn_kit_components("PROP_DORMANT_RAIL", tile_position + Vector3(0.0, 0.24, 0.0), 0.82, yaw)
		if variant in [0, 3, 6]:
			_spawn_kit_component("PROP_ROUTE_PLINTH_BASE", tile_position + Vector3(0.0, 0.16, 0.0), 0.82, yaw)
			_spawn_kit_component("PROP_ROUTE_PLINTH_TRIM", tile_position + Vector3(0.0, 0.20, 0.0), 0.82, yaw)
			_spawn_kit_component("PROP_SIGNAL_SPINE_RAIL", tile_position + Vector3(0.0, 0.25, 0.0), 0.82, yaw)
			for relay_index in range(3):
				_spawn_kit_component("PROP_SIGNAL_SPINE_RELAY_%d" % relay_index, tile_position + Vector3(0.0, 0.31, 0.0), 0.82, yaw)
			_spawn_kit_component("PROP_SIGNAL_SPINE_RIB_L", tile_position + Vector3(0.0, 0.28, 0.0), 0.82, yaw)
			_spawn_kit_component("PROP_SIGNAL_SPINE_RIB_R", tile_position + Vector3(0.0, 0.28, 0.0), 0.82, yaw)
		if variant in [2, 5, 8]:
			_spawn_kit_component("PROP_RELAY_LAMP_STEM", tile_position + Vector3(0.34, 0.31, -0.28), 0.60, yaw)
			_spawn_kit_component("PROP_RELAY_LAMP_LANTERN", tile_position + Vector3(0.34, 0.67, -0.28), 0.60, yaw)
	elif terrain in ["SHALLOW_WATER", "DEEP_WATER"] and variant != 0:
		_spawn_kit_component("PROP_COAST_FOAM_ARC_0", tile_position + Vector3(-0.18, 0.08, -0.20), 0.76, yaw)
		_spawn_kit_component("PROP_COAST_FOAM_ARC_1", tile_position + Vector3(0.16, 0.08, 0.18), 0.76, yaw)

func _terrain_color(terrain: String, revealed: bool) -> Color:
	if not revealed:
		match terrain:
			"ROAD": return Color("4c4939")
			"RUINS": return Color("464553")
			"SHALLOW_WATER": return Color("1d5365")
			"DEEP_WATER": return Color("123d60")
			_: return Color("294b43")
	match terrain:
		"ROAD": return Color("9b865c")
		"RUINS": return Color("746873")
		"SHALLOW_WATER": return Color("2d7891")
		"DEEP_WATER": return Color("123b66")
		_: return Color("356f58")

func _create_node_button(node: Dictionary) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(86, 40)
	button.size = Vector2(86, 40)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_outline_color", Color("06101d"))
	button.add_theme_constant_override("outline_size", 4)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func(): _select_node(node))
	overlay.add_child(button)
	node_buttons[str(node.node_id)] = button

func _create_node_marker(node: Dictionary) -> void:
	var marker_root := Node3D.new()
	marker_root.name = "EncounterMarker_%s" % str(node.node_id)
	var coord := Vector2i(int(node.q), int(node.r))
	marker_root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * 0.42 + 0.18)
	var hard_stage := str(node.get("stage_id", "")).contains("-H")
	var stage_id := str(node.get("stage_id", ""))
	var node_type := str(node.get("node_type", ""))
	var marker_prefix := "MARKER_NORMAL"
	if node_type == "START":
		marker_prefix = "MARKER_NORMAL"
	elif hard_stage:
		marker_prefix = "MARKER_HARD_GATE"
	elif node_type.contains("BOSS") or stage_id.ends_with("N10"):
		marker_prefix = "MARKER_BOSS"
	elif node_type.contains("ELITE"):
		marker_prefix = "MARKER_ELITE"
	var marker_parts := _spawn_kit_components(marker_prefix, Vector3.ZERO, 1.04, 0.0, marker_root)
	if marker_parts.is_empty():
		var fallback := MeshInstance3D.new()
		var fallback_mesh := CylinderMesh.new()
		fallback_mesh.top_radius = 0.42
		fallback_mesh.bottom_radius = 0.54
		fallback_mesh.height = 0.15
		fallback_mesh.radial_segments = 6
		fallback.mesh = fallback_mesh
		fallback.name = "FallbackMarkerSymbol"
		fallback.material_override = _material(Color("78eed9"), Color("319f92"))
		marker_root.add_child(fallback)
	# Three persistent visual anchors make it clear this is a long broken relay
	# route, even when the streamed local terrain hides far-away node labels.
	if stage_id.ends_with("N03") or stage_id.ends_with("N07") or stage_id.ends_with("N10"):
		_spawn_kit_components("PROP_SIGNAL_TOWER", Vector3(0.62, 0.06, -0.30), 0.76 if stage_id.ends_with("N03") else 1.0, 0.18, marker_root)
	elif stage_id.ends_with("H05"):
		_spawn_kit_components("PROP_SIGNAL_BEACON", Vector3(0.56, 0.05, -0.30), 0.92, -0.30, marker_root)
	world_root.add_child(marker_root)
	node_markers[str(node.node_id)] = marker_root

func _enemy_for_node(node: Dictionary) -> Dictionary:
	var stage := DataRegistry.stage(str(node.get("stage_id", "")))
	var first_enemy_id := ""
	var boss_enemy_id := ""
	for wave in stage.get("waves", []):
		for enemy_id in wave:
			var enemy := DataRegistry.enemy(str(enemy_id))
			if str(enemy.get("rank", "")) == "BOSS": boss_enemy_id = str(enemy_id)
			elif first_enemy_id == "": first_enemy_id = str(enemy_id)
	var selected_id := boss_enemy_id if not boss_enemy_id.is_empty() else first_enemy_id
	return DataRegistry.enemy(selected_id)

func _map_idle_texture(enemy_id: String) -> Dictionary:
	var manifest_path := "res://assets/runtime_web/combat/%s/animation_manifest.json" % enemy_id
	if not FileAccess.file_exists(manifest_path): return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary: return {}
	var atlas_path := "res://assets/runtime_web/combat/%s/%s" % [enemy_id, str(parsed.get("atlas_path", "atlas.png"))]
	var atlas := load(atlas_path) as Texture2D
	if atlas == null: return {}
	var frame_size: Array = parsed.get("frame_size", [104, 104])
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(0, 0, float(frame_size[0]), float(frame_size[1]))
	var idle_frames := int(parsed.get("animations", {}).get("idle", {}).get("frames", 1))
	return {"texture": texture, "frame_size": Vector2(float(frame_size[0]), float(frame_size[1])), "columns": int(parsed.get("atlas_columns", 1)), "frames": clampi(idle_frames, 1, 8)}

func _create_enemy_pawn(node: Dictionary) -> void:
	var enemy := _enemy_for_node(node)
	if enemy.is_empty(): return
	var node_id := str(node.get("node_id", ""))
	var root := Node3D.new()
	root.name = "EnemyMapPawn_%s" % node_id
	var coord := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
	root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * 0.42 + 0.18)
	var rank := str(enemy.get("rank", "NORMAL"))
	var scale_factor := 1.0 if rank == "NORMAL" else (1.28 if rank == "ELITE" else 1.72)
	var shadow := MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.38 * scale_factor
	shadow_mesh.bottom_radius = 0.50 * scale_factor
	shadow_mesh.height = 0.025
	shadow_mesh.radial_segments = 12
	shadow.mesh = shadow_mesh
	shadow.position.y = 0.02
	shadow.material_override = _material(Color("061019"))
	root.add_child(shadow)
	var danger_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.34 * scale_factor
	ring_mesh.outer_radius = 0.42 * scale_factor
	ring_mesh.rings = 8
	ring_mesh.ring_segments = 18
	danger_ring.mesh = ring_mesh
	var threat_color := Color("d85d67") if rank == "NORMAL" else (Color("ef9a47") if rank == "ELITE" else Color("dc5dcc"))
	danger_ring.material_override = _material(threat_color, threat_color.darkened(0.1))
	danger_ring.position.y = 0.06
	root.add_child(danger_ring)
	var sprite := Sprite3D.new()
	sprite.name = "EnemyIdleSprite"
	var pack := _map_idle_texture(str(enemy.get("id", "")))
	if not pack.is_empty():
		sprite.texture = pack.texture
		enemy_animation_packs[node_id] = pack
	else:
		var fallback := QuadMesh.new()
		fallback.size = Vector2(0.72 * scale_factor, 0.72 * scale_factor)
		var fallback_mesh := MeshInstance3D.new()
		fallback_mesh.mesh = fallback
		fallback_mesh.material_override = _material(threat_color, threat_color)
		fallback_mesh.position.y = 0.62 * scale_factor
		root.add_child(fallback_mesh)
	# Combat atlases use 104px frames while the squad leader is rendered from a
	# 512px icon.  The previous 0.007 world-pixel value made hostile pawns read
	# as decoration at the edge of a route.  Keep the actual combat art, but give
	# it a deliberate map-pawn scale and use the manifest foot anchor so it sits
	# on its hostile ring rather than sinking into the terrain.
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.0165 * scale_factor
	var sprite_world_height := float(pack.get("frame_size", Vector2(104.0, 104.0)).y) * sprite.pixel_size
	sprite.position.y = 0.16 + sprite_world_height * 0.38
	sprite.no_depth_test = true
	sprite.render_priority = 12
	root.add_child(sprite)
	var threat := Label3D.new()
	threat.text = "위협" if rank == "NORMAL" else ("정예" if rank == "ELITE" else "보스")
	threat.font_size = 46 if rank == "BOSS" else 38
	threat.outline_size = 8
	threat.modulate = threat_color.lightened(0.16)
	threat.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	threat.no_depth_test = true
	threat.position.y = sprite.position.y + sprite_world_height * 0.48 + 0.10
	root.add_child(threat)
	world_root.add_child(root)
	enemy_pawns[node_id] = root

func _create_treasure_visual(treasure: Dictionary) -> void:
	var treasure_id := str(treasure.get("treasure_id", ""))
	if treasure_id.is_empty(): return
	var root := Node3D.new()
	root.name = "Treasure_%s" % treasure_id
	var coord := Vector2i(int(treasure.get("q", 0)), int(treasure.get("r", 0)))
	root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * 0.42 + 0.16)
	var shadow := MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.34
	shadow_mesh.bottom_radius = 0.46
	shadow_mesh.height = 0.02
	shadow_mesh.radial_segments = 12
	shadow.mesh = shadow_mesh
	shadow.material_override = _material(Color("061019"))
	shadow.position.y = 0.01
	root.add_child(shadow)
	var crate := MeshInstance3D.new()
	var crate_mesh := BoxMesh.new()
	crate_mesh.size = Vector3(0.56, 0.34, 0.40)
	crate.mesh = crate_mesh
	crate.material_override = _material(Color("875a2f"), Color("6f3c1f"))
	crate.position.y = 0.22
	root.add_child(crate)
	var lid := MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(0.61, 0.11, 0.45)
	lid.mesh = lid_mesh
	lid.material_override = _material(Color("e2a853"), Color("b97830"))
	lid.position.y = 0.43
	root.add_child(lid)
	var seal := MeshInstance3D.new()
	var seal_mesh := SphereMesh.new()
	seal_mesh.radius = 0.09
	seal_mesh.height = 0.18
	seal.mesh = seal_mesh
	seal.material_override = _material(Color("b9fff2"), Color("6af8d4"))
	seal.position = Vector3(0, 0.50, 0.22)
	root.add_child(seal)
	var glow := MeshInstance3D.new()
	var glow_mesh := TorusMesh.new()
	glow_mesh.inner_radius = 0.38
	glow_mesh.outer_radius = 0.46
	glow_mesh.rings = 8
	glow_mesh.ring_segments = 18
	glow.mesh = glow_mesh
	glow.material_override = _material(Color("edcc76"), Color("f7d76f"))
	glow.position.y = 0.065
	root.add_child(glow)
	if str(treasure.get("visibility", "VISIBLE")) == "HIDDEN":
		crate.visible = false
		lid.visible = false
		seal.visible = false
		glow.visible = false
		_spawn_kit_component("PROP_CRYSTAL_SHARD_1", Vector3(0.20, 0.12, -0.10), 0.76, 0.0, root)
	root.set_meta("crate", crate)
	root.set_meta("lid", lid)
	root.set_meta("seal", seal)
	root.set_meta("glow", glow)
	world_root.add_child(root)
	treasure_visuals[treasure_id] = root

func _node_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 5
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	return style

func _create_pawn() -> void:
	pawn = Node3D.new()
	pawn.name = "SquadPawn"
	pawn.position = _pawn_world_position()
	world_root.add_child(pawn)
	var contact_shadow := MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.54
	shadow_mesh.bottom_radius = 0.64
	shadow_mesh.height = 0.025
	shadow_mesh.radial_segments = 16
	contact_shadow.mesh = shadow_mesh
	contact_shadow.position.y = 0.015
	contact_shadow.material_override = _material(Color("061019"))
	pawn.add_child(contact_shadow)
	var pedestal := MeshInstance3D.new()
	var pedestal_mesh := CylinderMesh.new()
	pedestal_mesh.top_radius = 0.43
	pedestal_mesh.bottom_radius = 0.54
	pedestal_mesh.height = 0.16
	pedestal_mesh.radial_segments = 8
	pedestal.mesh = pedestal_mesh
	pedestal.material_override = _material(Color("18485a"), Color("196b71"))
	pedestal.position.y = 0.07
	pawn.add_child(pedestal)
	var crest := MeshInstance3D.new()
	var crest_mesh := TorusMesh.new()
	crest_mesh.inner_radius = 0.28
	crest_mesh.outer_radius = 0.36
	crest_mesh.rings = 8
	crest_mesh.ring_segments = 16
	crest.mesh = crest_mesh
	crest.material_override = _material(Color("e8b45d"), Color("d88c32"))
	crest.position.y = 0.17
	pawn.add_child(crest)
	pawn_visual = Node3D.new()
	pawn_visual.name = "PawnVisual"
	pawn_visual.position.y = PAWN_VISUAL_BASE_Y
	pawn.add_child(pawn_visual)
	_spawn_kit_components("SQUAD_STANDARD", Vector3(0.0, 0.02, 0.0), 1.48, 0.0, pawn_visual)
	var lead_id := str(AppState.get_party()[0])
	var lead := DataRegistry.character(lead_id)
	var texture_path := AssetRegistry.resolve(str(lead.get("icon_asset_id", "")))
	if texture_path != "" and ResourceLoader.exists(texture_path):
		pawn_sprite = Sprite3D.new()
		pawn_sprite.texture = load(texture_path) as Texture2D
		pawn_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		pawn_sprite.pixel_size = 0.0054
		pawn_sprite.position.y = 0.34
		# This is a UI-readable pawn portrait, never a terrain occluder.  The
		# contact shadow and standard beneath it still establish ground contact.
		pawn_sprite.no_depth_test = true
		pawn_sprite.render_priority = 4
		pawn_visual.add_child(pawn_sprite)
	else:
		# The Blender-made standard remains legible for leaders without a map-pawn
		# portrait instead of falling back to a grey capsule or generic primitive.
		pawn_visual.position.y += 0.08
	pawn_banner = MeshInstance3D.new()
	var signal_mesh := PrismMesh.new()
	signal_mesh.left_to_right = 0.52
	signal_mesh.size = Vector3(0.30, 0.46, 0.12)
	pawn_banner.mesh = signal_mesh
	pawn_banner.material_override = _material(Color("f1b864"), Color("dc8f39"))
	pawn_banner.position = Vector3(0.0, 1.15, 0.0)
	pawn_visual.add_child(pawn_banner)
	pawn_last_position = pawn.position

func _pawn_world_position() -> Vector3:
	var coord := Vector2i(int(map_state.current_q), int(map_state.current_r))
	return HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * 0.42 + 0.14)

func _update_route_mesh() -> void:
	for segment in route_segments: segment.queue_free()
	for node in route_nodes: node.queue_free()
	route_segments.clear()
	route_nodes.clear()
	selected_ring.visible = false
	var immediate := ImmediateMesh.new()
	if preview_path.size() >= 2:
		immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _material(Color("93fff0"), Color("36d8c5")))
		for coord in preview_path:
			immediate.surface_add_vertex(HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * 0.42 + 0.54))
		immediate.surface_end()
		for index in range(preview_path.size() - 1):
			var from := HexCoordScript.axial_to_world(preview_path[index], TILE_SIZE, float(grid.tile(preview_path[index]).get("elevation", 0)) * 0.42 + 0.57)
			var to := HexCoordScript.axial_to_world(preview_path[index + 1], TILE_SIZE, float(grid.tile(preview_path[index + 1]).get("elevation", 0)) * 0.42 + 0.57)
			var ribbon := MeshInstance3D.new()
			var ribbon_mesh := BoxMesh.new()
			ribbon_mesh.size = Vector3(0.18, 0.045, from.distance_to(to))
			ribbon.mesh = ribbon_mesh
			ribbon.material_override = _material(Color("4fd3c2"), Color("31e0c2"))
			ribbon.position = (from + to) * 0.5
			world_root.add_child(ribbon)
			ribbon.look_at(to, Vector3.UP)
			route_segments.append(ribbon)
			var pulse := MeshInstance3D.new()
			var pulse_mesh := CylinderMesh.new()
			pulse_mesh.top_radius = 0.12
			pulse_mesh.bottom_radius = 0.15
			pulse_mesh.height = 0.055
			pulse_mesh.radial_segments = 6
			pulse.mesh = pulse_mesh
			pulse.material_override = _material(Color("f5bc62"), Color("f3a83e"))
			pulse.position = to + Vector3(0.0, 0.035, 0.0)
			world_root.add_child(pulse)
			route_nodes.append(pulse)
	var selected_target: Dictionary = selected_node if not selected_node.is_empty() else selected_treasure
	if not selected_target.is_empty():
		var selected_coord := Vector2i(int(selected_target.get("q", 0)), int(selected_target.get("r", 0)))
		selected_ring.position = HexCoordScript.axial_to_world(selected_coord, TILE_SIZE, float(grid.tile(selected_coord).get("elevation", 0)) * 0.42 + 0.18)
		selected_ring.visible = true
	route_mesh.mesh = immediate

func _refresh_state_visuals() -> void:
	if definition.is_empty(): return
	AppState.refresh_chapter_map_reveal(MAP_ID)
	var revealed: Dictionary = {}
	for key in map_state.get("revealed_tiles", []): revealed[str(key)] = true
	for key in tile_meshes:
		var instance: MeshInstance3D = tile_meshes[key]
		var tile: Dictionary = instance.get_meta("tile")
		if bool(instance.get_meta("blender_kit")) and revealed.has(key):
			instance.material_override = null
		else:
			instance.material_override = _material(_terrain_color(str(tile.terrain_type), revealed.has(key)))
	for node in definition.get("nodes", []):
		var button: Button = node_buttons[str(node.node_id)]
		var marker_root: Node3D = node_markers.get(str(node.node_id))
		var stage_id := str(node.get("stage_id", ""))
		var is_hard := stage_id.contains("-H")
		var key := "%d,%d" % [int(node.q), int(node.r)]
		button.visible = revealed.has(key) and (stage_id == "" or hard_overlay == is_hard)
		if marker_root != null: marker_root.visible = button.visible
		if not button.visible: continue
		var stars := int(AppState.profile.stage_stars.get(stage_id, 0)) if stage_id != "" else 0
		var unlocked := stage_id == "" or AppState.is_stage_unlocked(stage_id)
		var marker := "◆" if stage_id == "" else ("★" if stars == 3 else ("✓" if stars > 0 else ("◇" if unlocked else "🔒")))
		var short_id := stage_id.replace("CH01-", "") if stage_id != "" else "CAMP"
		button.text = "%s %s" % [marker, short_id]
		button.tooltip_text = stage_id if stage_id != "" else "릴레이 캠프"
		var fill := Color("143347") if not unlocked else Color("15465a")
		var border := Color("5d7892") if not unlocked else Color("70ecd9")
		if stars > 0:
			fill = Color("1c5a53")
			border = Color("f2c46b")
		if stage_id == "":
			fill = Color("175264")
			border = Color("f2c46b")
		button.add_theme_stylebox_override("normal", _node_style(fill, border))
		button.add_theme_stylebox_override("hover", _node_style(fill.lightened(0.16), Color("fff1b5")))
		button.add_theme_stylebox_override("pressed", _node_style(fill.darkened(0.12), Color("ffffff")))
		button.disabled = moving
		if marker_root != null:
			var marker_color := Color("78eed9") if unlocked else Color("5a7083")
			if stars > 0: marker_color = Color("f0c56e")
			if stage_id == "": marker_color = Color("f0c56e")
			for marker_child in marker_root.get_children():
				if marker_child is MeshInstance3D and (str(marker_child.name).contains("SYMBOL") or str(marker_child.name).contains("FallbackMarker")):
					(marker_child as MeshInstance3D).material_override = _material(marker_color, marker_color.darkened(0.18))
		var enemy_root: Node3D = enemy_pawns.get(str(node.node_id))
		if enemy_root != null:
			var cleared := MapExplorationServiceScript.encounter_cleared(map_state, str(node.node_id)) or stars > 0
			enemy_root.visible = button.visible and not cleared and unlocked
			# A cleared relay stays in the map as a quiet visual anchor, but the
			# hostile pawn is gone.  This keeps the encounter readable before text.
			if marker_root != null and cleared:
				marker_root.visible = button.visible
	for treasure in definition.get("treasures", []):
		var treasure_id := str(treasure.get("treasure_id", ""))
		var root: Node3D = treasure_visuals.get(treasure_id)
		if root == null: continue
		var state := MapExplorationServiceScript.treasure_state(map_state, treasure_id)
		var revealed_treasure := state == "REVEALED"
		# HIDDEN/HINTED keeps only the authored crystal/ruin dressing created
		# above.  Do not expose the cache ring, chest, route, or exact target
		# before proximity has actually revealed it.
		root.visible = state != "UNDISCOVERED" and state != "CLAIMED"
		for visual_name in ["crate", "lid", "seal", "glow"]:
			var visual = root.get_meta(visual_name, null)
			if visual == null: continue
			visual.visible = revealed_treasure
			if visual_name == "glow" and revealed_treasure:
				visual.scale = Vector3.ONE
	status_label.text = "제1장  ·  꺼진 노선의 신호  ·  %s" % ["위험 작전" if hard_overlay else "일반 작전"]
	_update_route_minimap()
	_update_next_encounter_button()
	_update_panel()

func _update_route_minimap() -> void:
	if route_minimap == null: return
	route_minimap.configure(definition, map_state, selected_node, hard_overlay)

func _next_encounter_node() -> Dictionary:
	var route: Array = definition.get("hard_route", []) if hard_overlay else definition.get("normal_route", [])
	var cleared_candidate: Dictionary = {}
	for stage_value in route:
		var stage_id := str(stage_value)
		if not AppState.is_stage_unlocked(stage_id): continue
		var node := ChapterMapLoaderScript.node_for_stage(definition, stage_id)
		if node.is_empty(): continue
		var stars := int(AppState.profile.stage_stars.get(stage_id, 0))
		if stars <= 0: return node
		if cleared_candidate.is_empty(): cleared_candidate = node
	return cleared_candidate

func _update_next_encounter_button() -> void:
	if next_encounter_button == null: return
	var next_node := _next_encounter_node()
	next_encounter_button.visible = not next_node.is_empty()
	next_encounter_button.disabled = moving or next_node.is_empty()
	if next_node.is_empty(): return
	var stage_id := str(next_node.get("stage_id", ""))
	next_encounter_button.text = "다음 조우  ·  %s" % stage_id.replace("CH01-", "")

func _select_next_encounter() -> void:
	var next_node := _next_encounter_node()
	if next_node.is_empty(): return
	_select_node(next_node)

func _select_node(node: Dictionary) -> void:
	if moving: return
	selected_treasure = {}
	selected_node = node
	AppState.selected_map_node_id = str(node.node_id)
	map_state.last_selected_node = str(node.node_id)
	var allowed: Dictionary = {}
	for key in map_state.revealed_tiles: allowed[str(key)] = true
	preview_path = HexPathfinderScript.find_path(grid, Vector2i(int(map_state.current_q), int(map_state.current_r)), Vector2i(int(node.q), int(node.r)), allowed)
	preview_path = _truncate_at_first_unresolved_encounter(preview_path)
	if not preview_path.is_empty() and preview_path[-1] != Vector2i(int(node.q), int(node.r)):
		selected_node = _node_at_coord(preview_path[-1])
		AppState.selected_map_node_id = str(selected_node.get("node_id", ""))
	_update_route_mesh()
	# Frame both the squad and the hostile pawn while retaining enough route
	# context to make movement legible.  This keeps a selected N01 from being
	# clipped behind the panel on a wide Chapter 1 map.
	_focus_preview_route()
	_update_panel()

func _select_treasure(treasure: Dictionary) -> void:
	if moving: return
	var treasure_id := str(treasure.get("treasure_id", ""))
	# A hint is an environmental observation, not a navigable treasure marker.
	# The player may discover it while traversing the map; only REVEALED opens
	# an exact collection route and the reward panel.
	if MapExplorationServiceScript.treasure_state(map_state, treasure_id) != "REVEALED":
		return
	selected_node = {}
	selected_treasure = treasure
	# Treasure selection is the explicit opt-in for a short exploratory detour.
	# Do not restrict this route to currently revealed tiles: otherwise a hinted
	# side branch can be visible but unreachable. Unresolved encounters still
	# cut the route below, so this never lets a treasure selection bypass battle.
	preview_path = HexPathfinderScript.find_path(grid, Vector2i(int(map_state.current_q), int(map_state.current_r)), Vector2i(int(treasure.q), int(treasure.r)))
	preview_path = _truncate_at_first_unresolved_encounter(preview_path)
	if not preview_path.is_empty() and preview_path[-1] != Vector2i(int(treasure.q), int(treasure.r)):
		selected_treasure = {}
		selected_node = _node_at_coord(preview_path[-1])
	_update_route_mesh()
	_focus_preview_route()
	_update_panel()

func _focus_preview_route() -> void:
	if preview_path.size() <= 1:
		_focus_current(false)
		return
	var midpoint_index := clampi(int(round(float(preview_path.size() - 1) * 0.55)), 1, preview_path.size() - 1)
	_focus_coord(preview_path[midpoint_index], false)

func _truncate_at_first_unresolved_encounter(path: Array[Vector2i]) -> Array[Vector2i]:
	if path.size() <= 1: return path
	for index in range(1, path.size()):
		var coord := path[index]
		for node in definition.get("nodes", []):
			if str(node.get("stage_id", "")).is_empty(): continue
			if int(node.get("q", 0)) != coord.x or int(node.get("r", 0)) != coord.y: continue
			if not MapExplorationServiceScript.encounter_cleared(map_state, str(node.get("node_id", ""))) and int(AppState.profile.stage_stars.get(str(node.get("stage_id", "")), 0)) <= 0:
				return path.slice(0, index + 1)
	return path

func _node_at_coord(coord: Vector2i) -> Dictionary:
	for node in definition.get("nodes", []):
		if int(node.get("q", 0)) == coord.x and int(node.get("r", 0)) == coord.y:
			return node
	return {}

func _update_panel() -> void:
	if detail_title == null: return
	_apply_responsive_layout()
	_update_route_minimap()
	if selected_node.is_empty() and selected_treasure.is_empty():
		detail_title.text = "조우 타일을 선택하세요"
		detail_body.text = "[color=#91aac8]한 번 선택하면 예상 경로를 표시합니다. 이동 확정 전에는 위치와 저장 데이터가 바뀌지 않습니다.[/color]\n\n클리어 타일: 빠른 이동\n3성 타일: 원격 소탕\n맵 이동: 작전력 소비 없음"
		move_button.visible = false
		fast_travel_button.visible = false
		battle_button.visible = false
		for button in sweep_buttons: button.visible = false
		_set_action_states(true, true, true)
		return
	if not selected_treasure.is_empty():
		var treasure_id := str(selected_treasure.get("treasure_id", ""))
		detail_title.text = "탐색 보급품 · 발견됨"
		detail_body.text = "[color=#f1d77a][b]%s[/b][/color]\n환경 단서를 따라 확인된 보급품입니다.\n\n예상 이동  [color=#85e8ff]%d 구간[/color]\n\n도착하면 보급품을 회수합니다. 이동에는 작전력을 소비하지 않습니다." % [str(selected_treasure.get("landmark", "탐색 지점")).replace("_", " "), maxi(0, preview_path.size() - 1)]
		move_button.visible = true
		move_button.text = "보급품으로 이동"
		move_button.disabled = preview_path.size() <= 1
		fast_travel_button.visible = false
		battle_button.visible = false
		for button in sweep_buttons: button.visible = false
		return
	var stage_id := str(selected_node.get("stage_id", ""))
	if stage_id == "":
		detail_title.text = "기점 • 릴레이 캠프"
		detail_body.text = "[color=#78e6d0]START[/color]\n부대의 탐색 기준점입니다."
		move_button.visible = false
		fast_travel_button.visible = false
		battle_button.visible = false
		for button in sweep_buttons: button.visible = false
		_set_action_states(preview_path.size() <= 1, true, true)
		return
	var stage := DataRegistry.stage(stage_id)
	var reward := DataRegistry.by_id("rewards", stage.reward_table_id)
	var stars := int(AppState.profile.stage_stars.get(stage_id, 0))
	var unlocked := AppState.is_stage_unlocked(stage_id)
	var at_node := int(map_state.current_q) == int(selected_node.q) and int(map_state.current_r) == int(selected_node.r)
	var attempts := "무제한"
	if stage.mode == "HARD": attempts = "%d/%d 사용" % [int(AppState.profile.hard_attempts.counts.get(stage_id, 0)), int(stage.daily_attempts)]
	var lock_reason := "" if unlocked else ("CH01-N10 클리어 필요" if stage.mode == "HARD" else "직전 NORMAL 클리어 필요")
	var operation_type := "위험 작전" if stage.mode == "HARD" else "일반 작전"
	detail_title.text = "%s%s" % [LocalizationService.tr_key(stage.name_key), " · 대형 조우" if stage.boss else ""]
	detail_body.text = "[color=#7cf1dc][b]%s[/b][/color]\n[color=#f1d77a]권장 Lv.%d[/color]     작전력 [b]%d[/b]     제한 %d초\n완료 등급  %s\n입장 횟수  %s\n예상 이동  [color=#85e8ff]%d 구간[/color]\n\n[color=#9cc5dc][b]3성 조건[/b][/color]\n클리어 · 전투불능 0 · %d초 내\n\n[color=#9cc5dc][b]획득 가능 보상[/b][/color]\n%s%s" % [operation_type, int(stage.recommended_level), int(stage.stamina_cost), int(stage.time_limit), "★".repeat(stars) + "☆".repeat(3-stars), attempts, maxi(0, preview_path.size()-1), int(stage.target_time), _reward_text(reward), "\n\n[color=#ffbd7a][b]잠금[/b]  " + lock_reason + "[/color]" if not unlocked else ""]
	# Keep the primary map actions above the portrait bottom edge. Remote farming
	# tools appear only after their real unlock condition, rather than occupying
	# the first-visit encounter sheet as disabled controls.
	move_button.visible = not at_node
	move_button.text = "경로를 따라 조우로 이동"
	fast_travel_button.visible = stars > 0
	var uncleared_encounter := not MapExplorationServiceScript.encounter_cleared(map_state, str(selected_node.get("node_id", ""))) and stars <= 0
	# An uncleared hostile starts combat by physical contact only.  Cleared
	# stages retain their normal repeat-battle action without an enemy pawn.
	battle_button.visible = not uncleared_encounter
	battle_button.text = "기존 실시간 전투 재도전"
	for button in sweep_buttons: button.visible = stars >= 3
	move_button.disabled = not unlocked or preview_path.size() <= 1 or (uncleared_encounter and not AppState.can_enter_stage(stage_id))
	fast_travel_button.disabled = stars <= 0 or at_node or not bool(selected_node.get("fast_travel_allowed", false))
	battle_button.disabled = not at_node or not AppState.can_enter_stage(stage_id)
	for index in range(sweep_buttons.size()):
		var count: int = int([1, 5, 10][index])
		sweep_buttons[index].disabled = stars < 3 or not AppState.can_enter_stage_count(stage_id, count)

func _set_action_states(move_disabled: bool, fast_disabled: bool, battle_disabled: bool) -> void:
	move_button.disabled = move_disabled
	fast_travel_button.disabled = fast_disabled
	battle_button.disabled = battle_disabled
	for button in sweep_buttons: button.disabled = true

func _reward_text(reward: Dictionary) -> String:
	var lines: Array[String] = []
	for entry in reward.get("guaranteed", []): lines.append("• %s ×%d" % [str(entry.get("item_id", "?")), int(entry.get("quantity", entry.get("min", 1)))])
	for entry in reward.get("bonus", []): lines.append("• %s %.0f%%" % [str(entry.get("item_id", "?")), float(entry.get("chance", 0.0))*100.0])
	return "\n".join(lines)

func _confirm_move() -> void:
	if moving or preview_path.size() <= 1: return
	_move_along(preview_path.duplicate())

func _move_along(path: Array[Vector2i]) -> void:
	moving = true
	pawn_motion_state = "WALK"
	movement_generation += 1
	var generation := movement_generation
	active_movement_path = path.duplicate()
	_refresh_state_visuals()
	_focus_current(true)
	await get_tree().create_timer(0.10).timeout
	for index in range(1, path.size()):
		var coord := path[index]
		_stream_visible_tiles(coord)
		var target := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * 0.42 + 0.14)
		_set_pawn_facing(pawn.position, target)
		_spawn_pawn_step_trail(pawn.position)
		var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(pawn, "position", target, PAWN_STEP_DURATION)
		await tween.finished
		if generation != movement_generation: return
		pawn_last_position = target
		# Keep a small amount of the route in frame instead of locking the camera
		# exactly to every footstep; this makes travelled distance immediately legible.
		if index == 1 or index % 3 == 0 or index == path.size() - 1:
			_follow_moving_pawn(target)
		var proximity_changes := MapExplorationServiceScript.update_hidden_proximity(map_state, definition, coord)
		if not proximity_changes.is_empty(): _refresh_state_visuals()
	ChapterMapProgressScript.mark_visited(map_state, path)
	map_state.last_selected_node = str(selected_node.get("node_id", ""))
	SaveService.save_game()
	moving = false
	pawn_motion_state = "ARRIVE"
	await get_tree().create_timer(0.16).timeout
	pawn_motion_state = "IDLE"
	active_movement_path.clear()
	preview_path = [path[-1]]
	_update_route_mesh()
	_refresh_state_visuals()
	_resolve_arrival(path)
	# Do not snap to the destination after walking: the stepped follow camera has
	# already kept the squad in view and retains surrounding terrain context.

func _follow_moving_pawn(position: Vector3) -> void:
	var follow_strength := clampf(float(SettingsService.values.get("map_camera_follow_strength", 0.72)), 0.0, 1.0)
	var desired := position - Vector3(0.0, 0.46, 0.0)
	var next_target := camera_target.lerp(desired, maxf(0.24, follow_strength * 0.58))
	if movement_camera_tween != null and movement_camera_tween.is_valid():
		movement_camera_tween.kill()
	movement_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	movement_camera_tween.tween_method(func(value: Vector3): camera_target = value, camera_target, next_target, 0.32)

func _spawn_pawn_step_trail(position: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.13
	mesh.bottom_radius = 0.20
	mesh.height = 0.025
	mesh.radial_segments = 6
	marker.mesh = mesh
	marker.material_override = _material(Color("4cd9d0"), Color("64fff0"))
	marker.position = position + Vector3(0.0, 0.035, 0.0)
	world_root.add_child(marker)
	pawn_step_trails.append(marker)
	if pawn_step_trails.size() > 7:
		var oldest = pawn_step_trails.pop_front()
		if is_instance_valid(oldest): oldest.queue_free()
	var fade := create_tween()
	fade.tween_property(marker, "scale", Vector3(1.75, 1.0, 1.75), 0.30)
	fade.parallel().tween_property(marker, "position:y", marker.position.y + 0.10, 0.30)
	fade.tween_callback(marker.queue_free)

func skip_movement() -> void:
	if not moving or active_movement_path.is_empty(): return
	var skipped_path := active_movement_path.duplicate()
	movement_generation += 1
	ChapterMapProgressScript.mark_visited(map_state, skipped_path)
	pawn.position = _pawn_world_position()
	preview_path = [skipped_path[-1]]
	active_movement_path.clear()
	moving = false
	pawn_motion_state = "IDLE"
	_update_route_mesh()
	_refresh_state_visuals()
	SaveService.save_game()
	_resolve_arrival(skipped_path)

func _resolve_arrival(path: Array[Vector2i]) -> void:
	if path.is_empty(): return
	var arrival := path[-1]
	var proximity_changes := MapExplorationServiceScript.update_hidden_proximity(map_state, definition, arrival)
	if not proximity_changes.is_empty():
		_refresh_state_visuals()
	if not selected_treasure.is_empty() and arrival == Vector2i(int(selected_treasure.q), int(selected_treasure.r)):
		var report := MapExplorationServiceScript.claim_treasure(map_state, definition, str(selected_treasure.treasure_id))
		if report.ok:
			SaveService.save_game()
			treasure_reward_requested.emit(report.value)
		return
	if selected_node.is_empty() or str(selected_node.get("stage_id", "")).is_empty(): return
	if arrival != Vector2i(int(selected_node.q), int(selected_node.r)): return
	if MapExplorationServiceScript.encounter_cleared(map_state, str(selected_node.node_id)) or int(AppState.profile.stage_stars.get(str(selected_node.stage_id), 0)) > 0:
		return
	var return_coord := path[path.size() - 2] if path.size() >= 2 else Vector2i(int(map_state.current_q), int(map_state.current_r))
	if AppState.prepare_map_encounter(str(selected_node.stage_id), str(selected_node.node_id), return_coord, MAP_ID):
		SaveService.save_game()
		battle_requested.emit(str(selected_node.stage_id))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and moving:
		skip_movement()

func _fast_travel() -> void:
	if selected_node.is_empty(): return
	var stage_id := str(selected_node.get("stage_id", ""))
	if int(AppState.profile.stage_stars.get(stage_id, 0)) <= 0: return
	AppState.set_chapter_map_position(Vector2i(int(selected_node.q), int(selected_node.r)), str(selected_node.node_id), MAP_ID)
	pawn.position = _pawn_world_position()
	pawn_motion_state = "ARRIVE"
	await get_tree().create_timer(0.12).timeout
	pawn_motion_state = "IDLE"
	SaveService.save_game()
	preview_path = [Vector2i(int(selected_node.q), int(selected_node.r))]
	_update_route_mesh()
	_update_panel()

func _request_battle() -> void:
	if selected_node.is_empty() or battle_button.disabled: return
	battle_requested.emit(str(selected_node.get("stage_id", "")))

func _request_sweep(count: int) -> void:
	if not selected_node.is_empty(): sweep_requested.emit(str(selected_node.get("stage_id", "")), count)

func _clear_selection() -> void:
	selected_node = {}
	selected_treasure = {}
	preview_path.clear()
	_update_route_mesh()
	_update_panel()

func _set_pawn_facing(from: Vector3, to: Vector3) -> void:
	var direction := to - from
	direction.y = 0.0
	if direction.length_squared() < 0.0001: return
	pawn.rotation.y = atan2(direction.x, direction.z)

func _focus_current(immediate: bool) -> void:
	_focus_coord(Vector2i(int(map_state.current_q), int(map_state.current_r)), immediate)

func _focus_coord(coord: Vector2i, immediate: bool) -> void:
	_stream_visible_tiles(coord)
	var next_target := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * 0.42)
	if immediate or bool(SettingsService.values.get("map_instant_focus", false)):
		camera_target = next_target
	else:
		create_tween().tween_method(func(value: Vector3): camera_target = value, camera_target, next_target, 0.35)

func _focus_full_map() -> void:
	var overview_node := ChapterMapLoaderScript.node_for_stage(definition, "CH01-N05")
	camera_target = HexCoordScript.axial_to_world(Vector2i(int(overview_node.get("q", 0)), int(overview_node.get("r", 0))), TILE_SIZE)
	camera_zoom = 0.72
	map_state.camera_zoom = camera_zoom
	_stream_visible_tiles(HexCoordScript.world_to_axial(camera_target, TILE_SIZE))

func _on_map_input(event: InputEvent) -> void:
	# The SubViewport receives direct pointer events, bypassing AppShell's
	# shared Button wrapper.  Unlock deferred WebAudio on the first map gesture.
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		AudioService.unlock_from_user_gesture()
	if moving: return
	if event is InputEventScreenTouch:
		# Mobile Web sends screen touch events instead of mouse buttons on some
		# browsers. Keep the same tap-vs-drag threshold as desktop and never let a
		# touch pan accidentally confirm a long route.
		if event.pressed:
			dragging = true
			drag_origin = event.position
			camera_origin = camera_target
		else:
			if dragging and event.position.distance_to(drag_origin) <= 24.0 * _portrait_ui_scale(_runtime_layout_size()):
				_select_node_near_screen(event.position)
			dragging = false
	elif event is InputEventScreenDrag:
		if not dragging: return
		var touch_delta: Vector2 = event.position - drag_origin
		camera_target = camera_origin + Vector3(-touch_delta.x * 0.012 / camera_zoom, 0, -touch_delta.y * 0.012 / camera_zoom)
		camera_target.x = clampf(camera_target.x, -42.0, 170.0)
		camera_target.z = clampf(camera_target.z, -58.0, 30.0)
		map_state.camera_center = [camera_target.x, camera_target.z]
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_origin = event.position
				camera_origin = camera_target
			else:
				# A tap selects the nearest visible encounter in screen space. Map
				# traversal remains based on stable axial node data, not physics picks.
				if dragging and event.position.distance_to(drag_origin) <= 18.0 * _portrait_ui_scale(_runtime_layout_size()):
					_select_node_near_screen(event.position)
				dragging = false
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera_zoom = clampf(camera_zoom + (0.08 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.08), 0.72, 1.55)
			map_state.camera_zoom = camera_zoom
	elif event is InputEventMouseMotion and dragging:
		var delta: Vector2 = event.position - drag_origin
		camera_target = camera_origin + Vector3(-delta.x * 0.012 / camera_zoom, 0, -delta.y * 0.012 / camera_zoom)
		camera_target.x = clampf(camera_target.x, -42.0, 170.0)
		camera_target.z = clampf(camera_target.z, -58.0, 30.0)
		map_state.camera_center = [camera_target.x, camera_target.z]

func _select_node_near_screen(screen_position: Vector2) -> void:
	if camera == null or viewport == null or viewport_container == null: return
	var viewport_size := Vector2(viewport.size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0: return
	var surface_scale := viewport_container.size / viewport_size
	var runtime_size := _runtime_layout_size()
	var hit_radius := 72.0 * _portrait_ui_scale(runtime_size) if runtime_size.y > runtime_size.x else 46.0
	var closest: Dictionary = {}
	var closest_kind := ""
	var closest_distance := INF
	for node in definition.get("nodes", []):
		var node_button: Button = node_buttons.get(str(node.get("node_id", "")))
		if node_button == null or not node_button.visible: continue
		var coord := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
		var world_position := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * 0.42 + 0.72)
		var projected := camera.unproject_position(world_position) * surface_scale
		var distance := projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = node
			closest_kind = "NODE"
	for treasure in definition.get("treasures", []):
		var treasure_id := str(treasure.get("treasure_id", ""))
		var treasure_state := MapExplorationServiceScript.treasure_state(map_state, treasure_id)
		# HINTED caches intentionally have no exact selectable target. The map
		# keeps their authored environmental clue visible but routing stays hidden
		# until the party reaches the area and the cache becomes REVEALED.
		if treasure_state != "REVEALED": continue
		var root: Node3D = treasure_visuals.get(treasure_id)
		if root == null or not root.visible: continue
		var coord := Vector2i(int(treasure.get("q", 0)), int(treasure.get("r", 0)))
		var world_position := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * 0.42 + 0.62)
		var projected := camera.unproject_position(world_position) * surface_scale
		var distance := projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = treasure
			closest_kind = "TREASURE"
	if not closest.is_empty() and closest_distance <= hit_radius:
		if closest_kind == "TREASURE": _select_treasure(closest)
		else: _select_node(closest)

func _process(delta: float) -> void:
	if camera == null: return
	pawn_motion_phase += delta * (8.5 if pawn_motion_state == "WALK" else 3.0)
	if pawn_visual != null:
		var bob := sin(pawn_motion_phase) * (0.060 if pawn_motion_state == "WALK" else 0.018)
		if pawn_motion_state == "ARRIVE": bob = abs(sin(pawn_motion_phase * 1.8)) * 0.075
		pawn_visual.position.y = PAWN_VISUAL_BASE_Y + bob
		var visual_scale := 1.0
		if pawn_motion_state == "WALK": visual_scale = 1.04 + sin(pawn_motion_phase * 0.5) * 0.025
		pawn_visual.scale = Vector3.ONE * visual_scale
	if pawn_banner != null:
		pawn_banner.rotation.y = sin(pawn_motion_phase * 0.5) * 0.14
	if selected_ring != null and selected_ring.visible:
		var pulse := 1.0 + sin(pawn_motion_phase * 1.4) * 0.08
		selected_ring.scale = Vector3(pulse, 1.0, pulse)
	for node_id in enemy_animation_packs:
		var root: Node3D = enemy_pawns.get(node_id)
		if root == null or not root.visible: continue
		var pack: Dictionary = enemy_animation_packs[node_id]
		var sprite: Sprite3D = null
		for child in root.get_children():
			if child is Sprite3D:
				sprite = child
				break
		if sprite == null or not sprite.texture is AtlasTexture: continue
		var atlas_texture := sprite.texture as AtlasTexture
		var frame_size: Vector2 = pack.get("frame_size", Vector2(104, 104))
		var frame := int(floor(Time.get_ticks_msec() / 150.0)) % maxi(1, int(pack.get("frames", 1)))
		atlas_texture.region = Rect2(float(frame % int(pack.get("columns", 1))) * frame_size.x, float(frame / int(pack.get("columns", 1))) * frame_size.y, frame_size.x, frame_size.y)
	for treasure_id in treasure_visuals:
		var root: Node3D = treasure_visuals[treasure_id]
		if root == null or not root.visible: continue
		var glow = root.get_meta("glow", null)
		if glow != null and glow.visible:
			var pulse := 1.0 + sin(pawn_motion_phase * 1.5 + float(treasure_id.hash() % 9)) * 0.08
			glow.scale = Vector3(pulse, 1.0, pulse)
	camera.size = 13.2 / camera_zoom
	camera.position = camera_target + Vector3(9.4, 12.8, 11.2)
	camera.look_at(camera_target, Vector3.UP)
	_stream_visible_tiles(HexCoordScript.world_to_axial(camera_target, TILE_SIZE))
	# The render target grows on responsive layouts.  Scaling node controls from
	# the original 1280×720 constant displaced labels from their actual 3D
	# encounter markers after a resize; use the live SubViewport size instead.
	var scale := overlay.size / Vector2(viewport.size)
	var runtime_size := _runtime_layout_size()
	var portrait := runtime_size.y > runtime_size.x
	var ui_scale := _portrait_ui_scale(runtime_size)
	for node in definition.get("nodes", []):
		var button: Button = node_buttons.get(str(node.node_id))
		if button == null or not button.visible: continue
		var coord := Vector2i(int(node.q), int(node.r))
		var projected := camera.unproject_position(HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * 0.42 + 0.72))
		var label_offset := Vector2(0, (-78.0 if str(node.get("node_type", "")) == "START" else -62.0) * ui_scale) if portrait else Vector2(0, -126 if str(node.get("node_type", "")) == "START" else -86)
		button.position = Vector2(projected.x * scale.x, projected.y * scale.y) - button.size * 0.5 + label_offset
