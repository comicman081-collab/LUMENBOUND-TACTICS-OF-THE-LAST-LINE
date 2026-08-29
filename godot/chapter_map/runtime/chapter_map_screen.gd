class_name ChapterMapScreen
extends Control

signal battle_requested(stage_id: String)
signal formation_requested
signal fallback_requested
signal sweep_requested(stage_id: String, count: int)
signal treasure_reward_requested(report: Dictionary)

const DEFAULT_MAP_ID := "CH01_MAP"
const TILE_SIZE := 1.08
const ELEVATION_STEP := 0.64
const VIEWPORT_SIZE := Vector2i(1280, 720)
# The panel-aware orthographic framing can expose almost eighteen axial cells
# along its long diagonal.  A radius of fourteen still showed the edge of the
# streamed terrain when the camera offset a HARD encounter away from the side
# panel, making a valid marker read as if it floated over the ocean.  Twenty
# retains a bounded slice of the 96-hex world while covering the full visible
# neighbourhood at every supported zoom and aspect ratio.
# Keep a little more than a full camera neighbourhood resident, while avoiding
# a long-map return rebuilding every distant terrain-dressing component at
# once.  The stream follows both camera panning and squad travel, so this does
# not alter axial topology, reveal, pathfinding, or what destinations exist.
const STREAM_RADIUS := 16
const OCEAN_SURFACE_Y := -1.55
const CAMERA_TERRAIN_MARGIN := 2.8
const CAMERA_TERRAIN_SEARCH_RADIUS := 16
const PAWN_VISUAL_BASE_Y := 0.18
const PAWN_STEP_DURATION := 0.18
const DIRECT_DOUBLE_CLICK_WINDOW_MSEC := 460
# A moving patrol may leave its authored node while the squad is walking toward
# it.  Re-route a bounded number of times so contact still happens at the live
# enemy coordinate, without ever turning a node click into an instant battle.
const MAX_LIVE_ENCOUNTER_REPLANS := 3
const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const HexGridScript := preload("res://chapter_map/model/hex_grid.gd")
const HexPathfinderScript := preload("res://chapter_map/model/hex_pathfinder.gd")
const ChapterMapLoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const ChapterMapProgressScript := preload("res://chapter_map/model/chapter_map_progress.gd")
const ChapterRouteMinimapScript := preload("res://chapter_map/ui/chapter_route_minimap.gd")
const MapExplorationServiceScript := preload("res://chapter_map/model/map_exploration_service.gd")
const MapSimulationScript := preload("res://chapter_map/model/map_simulation.gd")
const MacroWorldGeneratorScript := preload("res://chapter_map/model/macro_world_generator.gd")
const EnvironmentFXControllerScript := preload("res://chapter_map/presentation/environment_fx_controller.gd")
const EnvironmentWaterShader := preload("res://chapter_map/shaders/water_environment.gdshader")

var definition: Dictionary
var grid = HexGridScript.new()
var map_state: Dictionary
var viewport: SubViewport
var viewport_container: SubViewportContainer
var presentation_layer: Control
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
var pawn_occlusion_silhouette: Sprite3D
var pawn_animation_pack: Dictionary = {}
var pawn_motion_state := "IDLE"
var pawn_motion_phase := 0.0
var pawn_last_position := Vector3.ZERO
var node_buttons: Dictionary = {}
var node_markers: Dictionary = {}
var enemy_pawns: Dictionary = {}
var enemy_animation_packs: Dictionary = {}
var treasure_visuals: Dictionary = {}
var relay_visuals: Dictionary = {}
var event_visuals: Dictionary = {}
var landmark_visuals: Dictionary = {}
var tile_meshes: Dictionary = {}
var tile_dressing_roots: Dictionary = {}
var active_dressing_root: Node3D
var terrain_surface: MeshInstance3D
var terrain_material: StandardMaterial3D
var terrain_cap_material_cache: Dictionary = {}
var map_world_environment: Environment
var map_water_material: ShaderMaterial
var map_sun: DirectionalLight3D
var map_fill: DirectionalLight3D
var environment_fx: EnvironmentFXController
var stream_anchor := Vector2i(999999, 999999)
var blender_mesh_library: Dictionary = {}
var movement_range_fill: MeshInstance3D
var movement_range_grid: MeshInstance3D
var movement_range_boundary: MeshInstance3D
var movement_range_reachable: Dictionary = {}
var route_mesh: MeshInstance3D
var route_segments: Array[MeshInstance3D] = []
var route_nodes: Array[MeshInstance3D] = []
var selected_ring: MeshInstance3D
var selected_node: Dictionary = {}
var selected_treasure: Dictionary = {}
var selected_relay: Dictionary = {}
var selected_event: Dictionary = {}
var preview_path: Array[Vector2i] = []
var preview_risk := "SAFE"
var detail_title: Label
var detail_body: RichTextLabel
var move_button: Button
var battle_button: Button
var fast_travel_button: Button
var sweep_buttons: Array[Button] = []
var status_label: Label
var status_backplate: PanelContainer
var next_encounter_button: Button
var legend_card: PanelContainer
var legend_label: Label
var route_minimap: ChapterRouteMinimap
var moving := false
var movement_generation := 0
var live_encounter_replans := 0
var active_movement_path: Array[Vector2i] = []
var pawn_step_trails: Array[MeshInstance3D] = []
var movement_camera_tween: Tween
var preview_camera_tween: Tween
var movement_skip_requested := false
var turn_transitioning := false
var pending_turn_completion := false
var pending_turn_label := ""
var direct_move_pending := false
var last_node_pointer_id := ""
var last_node_pointer_msec := -100000
var node_touch_pointer_id := ""
var node_touch_origin := Vector2.ZERO
var node_touch_tap_valid := false
var last_map_pointer_click_valid := false
var last_map_pointer_click_msec := -100000
var last_map_pointer_click_position := Vector2.ZERO
var dragging := false
var drag_origin := Vector2.ZERO
var camera_origin := Vector3.ZERO
var hard_overlay := false
var toolbar: HFlowContainer
var toolbar_spacer: Control
var map_toolbar_buttons: Array[Button] = []
var detail_panel: PanelContainer
var detail_scroll: ScrollContainer
var compact_optional_buttons: Array[Control] = []
var wait_button: Button
var map_simulation_paused := false
var map_notice := ""
var map_notice_until_msec := 0
var map_id := ""
var tutorial_canvas_layer: CanvasLayer
var tutorial_surface: Control
var tutorial_dimmer: ColorRect
var tutorial_panel: PanelContainer
var tutorial_inner_frame: PanelContainer
var tutorial_scroll: ScrollContainer
var tutorial_eyebrow: Label
var tutorial_title: Label
var tutorial_body: RichTextLabel
var tutorial_continue_button: Button
var tutorial_progress_label: Label
var tutorial_dismiss_button: Button
var tutorial_step := 0
var tutorial_pointer_active := false
var tutorial_pointer_tap_valid := false
var tutorial_pointer_origin := Vector2.ZERO
var tutorial_pointer_started_msec := -100000

func _ready() -> void:
	if map_id.is_empty():
		map_id = AppState.map_id_for_stage(AppState.selected_stage_id)
	if ChapterMapLoaderScript.load_map(map_id).is_empty():
		map_id = DEFAULT_MAP_ID
	definition = ChapterMapLoaderScript.load_map(map_id)
	grid.load_tiles(definition.get("tiles", []))
	map_state = AppState.chapter_map_state(map_id)
	# A battle return creates a fresh map screen. Restore the route layer from the
	# canonical node/axial state before any HUD labels are built; otherwise an H01
	# victory reopens the NORMAL overlay and "next encounter" incorrectly points
	# back to N01 even though H02 was just unlocked.
	hard_overlay = _hard_overlay_from_state(map_state, definition)
	var repaired_map_state := MapExplorationServiceScript.ensure_state(map_state, definition, grid)
	MapExplorationServiceScript.update_proximity(map_state, definition, Vector2i(int(map_state.current_q), int(map_state.current_r)))
	# Persist a one-time legacy patrol repair before the player can navigate or
	# refresh.  This is map state migration, not a view-side fallback.
	if repaired_map_state:
		SaveService.save_game()
	camera_zoom = clampf(float(map_state.get("camera_zoom", 1.0)), 0.72, 1.55)
	_build_interface()
	_build_world()
	_refresh_state_visuals()
	_focus_current(true)
	if _first_map_tutorial_active():
		call_deferred("_start_first_map_tutorial")
	call_deferred("_present_pending_reveal_once")

static func _hard_overlay_from_state(state: Dictionary, map_definition: Dictionary) -> bool:
	var last_node_id := str(state.get("last_selected_node", ""))
	if not last_node_id.is_empty():
		var last_node := ChapterMapLoaderScript.node_by_id(map_definition, last_node_id)
		var last_stage_id := str(last_node.get("stage_id", ""))
		if not last_stage_id.is_empty():
			return last_stage_id.contains("-H")
	# Legacy or repaired saves can retain a canonical axial position without a
	# selected-node ID. Resolve that position deterministically rather than
	# falling back to the NORMAL layer.
	var current_q := int(state.get("current_q", 0))
	var current_r := int(state.get("current_r", 0))
	for node_value in map_definition.get("nodes", []):
		var node: Dictionary = node_value
		if int(node.get("q", 0)) != current_q or int(node.get("r", 0)) != current_r:
			continue
		var stage_id := str(node.get("stage_id", ""))
		if not stage_id.is_empty():
			return stage_id.contains("-H")
	return false

func _present_pending_reveal_once() -> void:
	var reveal := AppState.consume_chapter_map_pending_reveal(map_id)
	if reveal.is_empty():
		return
	# Persist consumption before showing the transient notice.  A browser refresh
	# during the presentation must restore canonical unlocks without replaying it.
	SaveService.save_game()
	_show_map_notice(reveal_notice_text(reveal, SettingsService.is_developer_mode()))

func stage_display_text(stage_id: String, compact := false, include_internal_id := false) -> String:
	var stage := DataRegistry.stage(stage_id)
	var label := "새 조우" if compact else "새 작전"
	if not stage.is_empty():
		if compact:
			label = "%s %d" % ["위험" if str(stage.get("mode", "NORMAL")) == "HARD" else "일반", int(stage.get("stage_number", 0))]
		else:
			var name_key := str(stage.get("name_key", ""))
			label = LocalizationService.tr_key(name_key).replace(" (DEV)", "") if not name_key.is_empty() else "새 작전"
	if include_internal_id and not stage_id.is_empty():
		label += " [%s]" % stage_id
	return label

func reveal_notice_text(reveal: Dictionary, include_internal_ids := false) -> String:
	var stage_ids: Array = reveal.get("unlocked_stage_ids", [])
	if stage_ids.is_empty():
		var source_stage_id := str(reveal.get("source_stage_id", ""))
		if not source_stage_id.is_empty():
			stage_ids.append(source_stage_id)
	var labels: Array[String] = []
	for stage_id_value in stage_ids:
		labels.append(stage_display_text(str(stage_id_value), false, include_internal_ids))
	return "새 탐색 경로 공개" + (" · " + ", ".join(labels) if not labels.is_empty() else "")

func relay_status_display(status_id: String) -> String:
	return "신호 연결됨" if status_id == "ACTIVE" else "신호 복구 필요"

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
	# A flow container preserves the single desktop row while giving portrait
	# phones a real two-row touch toolbar.  A fixed HBox clipped WAIT outside the
	# 390 px canvas even though the rest of the map reflowed correctly.
	toolbar = HFlowContainer.new()
	toolbar.alignment = FlowContainer.ALIGNMENT_BEGIN
	root.add_child(toolbar)
	var normal_button := _button("일반 작전", func(): hard_overlay = false; _refresh_state_visuals(), Vector2(128, 56))
	var hard_button := _button("위험 작전", func(): hard_overlay = true; _refresh_state_visuals(), Vector2(128, 56))
	var current_button := _button("현재 부대", func(): _focus_current(false), Vector2(116, 56))
	var overview_button := _button("구역 개요", _focus_full_map, Vector2(116, 56))
	var skip_button := _button("이동 건너뛰기", skip_movement, Vector2(132, 56))
	for action_button in [normal_button, hard_button, current_button, overview_button, skip_button]:
		toolbar.add_child(action_button)
		map_toolbar_buttons.append(action_button)
	wait_button = _button("대기", _wait_pulse, Vector2(86, 56))
	wait_button.tooltip_text = "이동하지 않고 턴을 종료합니다. 적 턴 뒤 다음 아군 턴이 자동으로 시작됩니다."
	toolbar.add_child(wait_button)
	var formation := _button("파티 편성", func(): formation_requested.emit(), Vector2(116, 56))
	toolbar.add_child(formation)
	compact_optional_buttons.append(formation)
	toolbar_spacer = Control.new()
	toolbar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(toolbar_spacer)
	var fallback := _button("목록형 접근성", func(): fallback_requested.emit(), Vector2(150, 56))
	toolbar.add_child(fallback)
	compact_optional_buttons.append(fallback)
	if SettingsService.is_developer_mode():
		var fx_tuning := _button("FX 조정", func(): environment_fx.toggle_development_panel(map_area), Vector2(112, 56))
		fx_tuning.tooltip_text = "환경 프리셋과 날씨 표현 조정 · 개발 전용"
		toolbar.add_child(fx_tuning)
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
	presentation_layer = Control.new()
	presentation_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_frame.add_child(presentation_layer)
	viewport_container = SubViewportContainer.new()
	# The container owns presentation sizing so the 3D map fills both desktop and
	# portrait layouts.  Do not manually resize its SubViewport while this is on:
	# Godot rejects that combination and emits a warning on each reflow.
	viewport_container.stretch = true
	viewport_container.tooltip_text = "한 번 클릭: 경로 확인 · 더블클릭/터치: 노란 범위 안에서 즉시 이동"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.gui_input.connect(_on_map_input)
	presentation_layer.add_child(viewport_container)
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
	presentation_layer.add_child(overlay)
	# Environment FX is inserted between the SubViewport and actual map controls.
	# It affects only world presentation and can never tint/map-block HUD input.
	environment_fx = EnvironmentFXControllerScript.new()
	environment_fx.name = "EnvironmentFXController"
	environment_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	environment_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presentation_layer.add_child(environment_fx)
	presentation_layer.move_child(environment_fx, presentation_layer.get_children().find(overlay))
	environment_fx.attach_canvas(presentation_layer)
	status_label = Label.new()
	status_label.position = Vector2(22, 18)
	status_label.custom_minimum_size = Vector2(520, 34)
	status_label.size = Vector2(520, 34)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.clip_text = false
	status_label.add_theme_font_size_override("font_size", 28)
	status_label.add_theme_color_override("font_color", Color("f2fffc"))
	status_label.add_theme_color_override("font_outline_color", Color("02080f"))
	status_label.add_theme_constant_override("outline_size", 5)
	status_label.add_theme_color_override("font_shadow_color", Color("031018"))
	status_label.add_theme_constant_override("shadow_offset_x", 3)
	status_label.add_theme_constant_override("shadow_offset_y", 3)
	status_label.modulate = Color.WHITE
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The status is live tactical information drawn over a visually busy 3D map.
	# A single low-profile backplate preserves the existing HUD language while
	# preventing forest highlights from erasing the movement/turn readout.
	status_backplate = PanelContainer.new()
	status_backplate.name = "MapStatusBackplate"
	status_backplate.show_behind_parent = true
	status_backplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_backplate.position = Vector2(-8, -5)
	status_backplate.size = status_label.size + Vector2(16, 10)
	status_backplate.add_theme_stylebox_override("panel", _panel_style(Color("05131eef"), Color("456f82"), 1, 8))
	status_label.add_child(status_backplate)
	overlay.add_child(status_label)
	# A macro chapter map deliberately places upcoming encounters outside the
	# current camera window.  This is a player-facing navigation aid, not a
	# debug warp: it selects the next real stage node so route preview, movement
	# confirmation, stamina transaction, and battle entry remain unchanged.
	next_encounter_button = _button("다음 조우", _select_next_encounter, Vector2(248, 52))
	next_encounter_button.tooltip_text = "현재 공개된 다음 조우로 카메라 이동"
	next_encounter_button.add_theme_color_override("font_color", Color("fff4cf"))
	next_encounter_button.add_theme_color_override("font_hover_color", Color("ffffff"))
	next_encounter_button.add_theme_color_override("font_pressed_color", Color("fff1b5"))
	next_encounter_button.add_theme_color_override("font_outline_color", Color("030a11"))
	next_encounter_button.add_theme_constant_override("outline_size", 4)
	next_encounter_button.add_theme_stylebox_override("normal", _panel_style(Color("071827f2"), Color("e3b85e"), 2, 10))
	next_encounter_button.add_theme_stylebox_override("hover", _panel_style(Color("123b4d"), Color("86f2dc"), 2, 10))
	next_encounter_button.add_theme_stylebox_override("pressed", _panel_style(Color("102d43"), Color("ffe099"), 2, 10))
	overlay.add_child(next_encounter_button)
	legend_card = PanelContainer.new()
	legend_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	legend_card.position = Vector2(18, -58)
	legend_card.add_theme_stylebox_override("panel", _panel_style(Color("071421d9"), Color("315369"), 1, 9))
	overlay.add_child(legend_card)
	legend_label = Label.new()
	legend_label.text = "◆ 현재 부대   ▰ 반투명 노랑: 이번 턴 이동 가능   더블클릭/터치: 즉시 이동   ✓ 클리어   ★ 완전 클리어   🔒 잠김"
	legend_label.add_theme_font_size_override("font_size", 20)
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
	var detail_panel_style := _panel_style(Color("0c1b2af7"), Color("64d7c2"), 2, 16)
	detail_panel_style.content_margin_bottom = 20.0
	detail_panel.add_theme_stylebox_override("panel", detail_panel_style)
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
	detail_title.add_theme_font_size_override("font_size", 34)
	detail_title.add_theme_color_override("font_color", Color("e9fff9"))
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(detail_title)
	detail_body = RichTextLabel.new()
	detail_body.bbcode_enabled = true
	detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_body.add_theme_font_size_override("normal_font_size", 24)
	detail_body.add_theme_color_override("default_color", Color("edf6fb"))
	detail_body.custom_minimum_size = Vector2(350, 278)
	detail_box.add_child(detail_body)
	move_button = _button("경로를 따라 이동", _confirm_move)
	move_button.add_theme_color_override("font_color", Color("fff2c6"))
	move_button.add_theme_color_override("font_hover_color", Color("ffffff"))
	move_button.add_theme_color_override("font_outline_color", Color("030a11"))
	move_button.add_theme_constant_override("outline_size", 3)
	move_button.add_theme_stylebox_override("normal", _panel_style(Color("123448"), Color("d7ab50"), 2, 11))
	move_button.add_theme_stylebox_override("hover", _panel_style(Color("1a4b5d"), Color("8af3dc"), 2, 11))
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
	_build_first_map_tutorial()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_update_panel()

func _first_map_tutorial_active() -> bool:
	if map_id != "CH01_MAP":
		return false
	var progress_value = AppState.profile.get("tutorial_progress", {})
	if not (progress_value is Dictionary):
		return false
	return not bool((progress_value as Dictionary).get("map_basics_complete", false)) and int(AppState.profile.get("stage_stars", {}).get("CH01-N01", 0)) <= 0

func _build_first_map_tutorial() -> void:
	if not _first_map_tutorial_active():
		return
	# CanvasLayer deliberately escapes the AppShell content slot, but that also
	# breaks Control-theme inheritance. Bind the bundled full Korean variable font
	# to every briefing text role so Web never falls back to tofu glyphs.
	var briefing_font := load("res://assets/fonts/NotoSansKR-VF.ttf") as Font
	var briefing_meta_font := _tutorial_weighted_font(briefing_font, 620.0, 0.04)
	var briefing_title_font := _tutorial_weighted_font(briefing_font, 720.0, 0.08)
	var briefing_body_font := _tutorial_weighted_font(briefing_font, 650.0, 0.08)
	# ChapterMapScreen is constrained to AppShell's content slot.  A dedicated
	# CanvasLayer makes FULL_RECT mean the actual viewport, so the shell header and
	# every map control receive the same briefing dim instead of leaving a bright
	# interactive strip above the modal.
	tutorial_canvas_layer = CanvasLayer.new()
	tutorial_canvas_layer.name = "FirstMapTutorialCanvas"
	tutorial_canvas_layer.layer = 90
	add_child(tutorial_canvas_layer)
	tutorial_surface = Control.new()
	tutorial_surface.name = "FirstMapTutorialSurface"
	tutorial_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_canvas_layer.add_child(tutorial_surface)
	tutorial_dimmer = ColorRect.new()
	tutorial_dimmer.name = "FirstMapTutorialDimmer"
	tutorial_dimmer.color = Color("01050bcc")
	tutorial_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	tutorial_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_dimmer.z_index = 90
	tutorial_surface.add_child(tutorial_dimmer)
	tutorial_panel = PanelContainer.new()
	tutorial_panel.name = "FirstMapTutorial"
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	tutorial_panel.z_index = 91
	var outer_style := _panel_style(Color("07121bfc"), Color("e8c878"), 2, 16)
	outer_style.content_margin_left = 6.0
	outer_style.content_margin_right = 6.0
	outer_style.content_margin_top = 6.0
	outer_style.content_margin_bottom = 6.0
	tutorial_panel.add_theme_stylebox_override("panel", outer_style)
	tutorial_surface.add_child(tutorial_panel)
	tutorial_inner_frame = PanelContainer.new()
	var inner_style := _panel_style(Color("091722fa"), Color("806b3e"), 1, 12)
	inner_style.content_margin_left = 0.0
	inner_style.content_margin_right = 0.0
	inner_style.content_margin_top = 0.0
	inner_style.content_margin_bottom = 0.0
	tutorial_inner_frame.add_theme_stylebox_override("panel", inner_style)
	tutorial_panel.add_child(tutorial_inner_frame)
	var content_margin := MarginContainer.new()
	tutorial_inner_frame.add_child(content_margin)
	var tutorial_box := VBoxContainer.new()
	tutorial_box.add_theme_constant_override("separation", 12)
	content_margin.add_child(tutorial_box)
	var tutorial_header := HBoxContainer.new()
	tutorial_header.alignment = BoxContainer.ALIGNMENT_BEGIN
	tutorial_box.add_child(tutorial_header)
	tutorial_eyebrow = Label.new()
	tutorial_eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_eyebrow.add_theme_font_size_override("font_size", 22)
	tutorial_eyebrow.add_theme_color_override("font_color", Color("9af2df"))
	tutorial_eyebrow.add_theme_color_override("font_outline_color", Color("02070c"))
	tutorial_eyebrow.add_theme_constant_override("outline_size", 3)
	if briefing_meta_font != null:
		tutorial_eyebrow.add_theme_font_override("font", briefing_meta_font)
	tutorial_header.add_child(tutorial_eyebrow)
	tutorial_dismiss_button = Button.new()
	tutorial_dismiss_button.text = "안내 건너뛰기"
	tutorial_dismiss_button.tooltip_text = "첫 작전 안내를 마치고 바로 지도를 조작합니다"
	tutorial_dismiss_button.custom_minimum_size = Vector2(138, 44)
	tutorial_dismiss_button.add_theme_font_size_override("font_size", 19)
	tutorial_dismiss_button.add_theme_color_override("font_color", Color("e8d29b"))
	if briefing_meta_font != null:
		tutorial_dismiss_button.add_theme_font_override("font", briefing_meta_font)
	tutorial_dismiss_button.add_theme_stylebox_override("normal", _panel_style(Color("0c2230"), Color("806b3e"), 1, 8))
	tutorial_dismiss_button.add_theme_stylebox_override("hover", _panel_style(Color("143848"), Color("9cebd8"), 1, 8))
	tutorial_dismiss_button.pressed.connect(_complete_first_map_tutorial)
	tutorial_header.add_child(tutorial_dismiss_button)
	tutorial_title = Label.new()
	tutorial_title.add_theme_font_size_override("font_size", 38)
	tutorial_title.add_theme_color_override("font_color", Color("f6d383"))
	tutorial_title.add_theme_color_override("font_outline_color", Color("02070c"))
	tutorial_title.add_theme_constant_override("outline_size", 4)
	if briefing_title_font != null:
		tutorial_title.add_theme_font_override("font", briefing_title_font)
	tutorial_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_box.add_child(tutorial_title)
	var divider := HSeparator.new()
	divider.modulate = Color("b7955299")
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_box.add_child(divider)
	tutorial_scroll = ScrollContainer.new()
	tutorial_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tutorial_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tutorial_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_box.add_child(tutorial_scroll)
	tutorial_body = RichTextLabel.new()
	tutorial_body.bbcode_enabled = true
	tutorial_body.fit_content = true
	tutorial_body.scroll_active = false
	tutorial_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_body.add_theme_font_size_override("normal_font_size", 25)
	tutorial_body.add_theme_font_size_override("bold_font_size", 25)
	tutorial_body.add_theme_constant_override("line_separation", 10)
	tutorial_body.add_theme_color_override("default_color", Color("fffaf0"))
	# The body sits on an opaque navy reading surface. A black outline reduced the
	# visible white stroke area at 1280x720 and made the copy look gray; keep the
	# semibold glyph face clean and reserve outlines for the gold display title.
	tutorial_body.add_theme_constant_override("outline_size", 0)
	tutorial_body.add_theme_constant_override("shadow_offset_x", 0)
	tutorial_body.add_theme_constant_override("shadow_offset_y", 0)
	if briefing_body_font != null:
		tutorial_body.add_theme_font_override("normal_font", briefing_body_font)
	if briefing_title_font != null:
		tutorial_body.add_theme_font_override("bold_font", briefing_title_font)
	tutorial_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_scroll.add_child(tutorial_body)
	var tutorial_footer := VBoxContainer.new()
	tutorial_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	tutorial_footer.add_theme_constant_override("separation", 2)
	tutorial_box.add_child(tutorial_footer)
	tutorial_continue_button = Button.new()
	tutorial_continue_button.flat = true
	tutorial_continue_button.custom_minimum_size = Vector2(420, 46)
	tutorial_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tutorial_continue_button.add_theme_font_size_override("font_size", 23)
	tutorial_continue_button.add_theme_color_override("font_color", Color("9af2df"))
	tutorial_continue_button.add_theme_color_override("font_hover_color", Color("c2fff0"))
	tutorial_continue_button.add_theme_color_override("font_pressed_color", Color("f3d68a"))
	tutorial_continue_button.add_theme_color_override("font_outline_color", Color("02070c"))
	tutorial_continue_button.add_theme_constant_override("outline_size", 2)
	if briefing_meta_font != null:
		tutorial_continue_button.add_theme_font_override("font", briefing_meta_font)
	tutorial_continue_button.add_theme_stylebox_override("normal", _panel_style(Color("07131f00"), Color("07131f00"), 0, 6))
	tutorial_continue_button.add_theme_stylebox_override("hover", _panel_style(Color("12303b99"), Color("6fcbb8"), 1, 6))
	tutorial_continue_button.pressed.connect(_advance_first_map_tutorial)
	tutorial_footer.add_child(tutorial_continue_button)
	tutorial_progress_label = Label.new()
	tutorial_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_progress_label.add_theme_font_size_override("font_size", 19)
	tutorial_progress_label.add_theme_color_override("font_color", Color("b4c8d3"))
	tutorial_progress_label.add_theme_color_override("font_outline_color", Color("02070c"))
	tutorial_progress_label.add_theme_constant_override("outline_size", 2)
	if briefing_meta_font != null:
		tutorial_progress_label.add_theme_font_override("font", briefing_meta_font)
	tutorial_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_footer.add_child(tutorial_progress_label)
	_set_tutorial_step(1)

func _input(event: InputEvent) -> void:
	# The briefing promises that any short click/tap progresses the current step,
	# including its title and body. Track this at screen level so a RichTextLabel
	# or ScrollContainer cannot create dead zones. A drag remains a scroll gesture.
	# The explicit skip control is exempted so it can finish the guide immediately.
	if tutorial_panel == null or not tutorial_panel.visible:
		return
	var threshold := 18.0 * _portrait_ui_scale(_runtime_layout_size())
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _tutorial_skip_contains(event.position):
				_reset_tutorial_pointer()
				return
			tutorial_pointer_active = true
			tutorial_pointer_tap_valid = true
			tutorial_pointer_origin = event.position
			tutorial_pointer_started_msec = Time.get_ticks_msec()
		elif tutorial_pointer_active:
			var short_click: bool = tutorial_pointer_tap_valid and tutorial_short_tap_policy(tutorial_pointer_origin, event.position, Time.get_ticks_msec() - tutorial_pointer_started_msec, false, threshold, 800)
			_reset_tutorial_pointer()
			if short_click:
				_advance_first_map_tutorial()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and tutorial_pointer_active:
		if event.position.distance_to(tutorial_pointer_origin) > threshold:
			tutorial_pointer_tap_valid = false
	elif event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			if _tutorial_skip_contains(event.position):
				_reset_tutorial_pointer()
				return
			tutorial_pointer_active = true
			tutorial_pointer_tap_valid = not event.canceled
			tutorial_pointer_origin = event.position
			tutorial_pointer_started_msec = Time.get_ticks_msec()
		elif tutorial_pointer_active:
			var short_tap: bool = tutorial_pointer_tap_valid and tutorial_short_tap_policy(tutorial_pointer_origin, event.position, Time.get_ticks_msec() - tutorial_pointer_started_msec, event.canceled, 24.0 * _portrait_ui_scale(_runtime_layout_size()), 900)
			_reset_tutorial_pointer()
			if short_tap:
				_advance_first_map_tutorial()
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == 0 and tutorial_pointer_active:
		if event.position.distance_to(tutorial_pointer_origin) > 24.0 * _portrait_ui_scale(_runtime_layout_size()):
			tutorial_pointer_tap_valid = false

static func tutorial_short_tap_policy(origin: Vector2, released_at: Vector2, elapsed_msec: int, canceled: bool, movement_threshold: float, duration_limit_msec: int) -> bool:
	return not canceled and elapsed_msec >= 0 and elapsed_msec <= duration_limit_msec and released_at.distance_to(origin) <= movement_threshold

func _tutorial_skip_contains(point: Vector2) -> bool:
	return tutorial_dismiss_button != null and tutorial_dismiss_button.visible and tutorial_dismiss_button.get_global_rect().has_point(point)

func _reset_tutorial_pointer() -> void:
	tutorial_pointer_active = false
	tutorial_pointer_tap_valid = false
	tutorial_pointer_started_msec = -100000

func _hide_first_map_tutorial_modal() -> void:
	_reset_tutorial_pointer()
	if tutorial_surface != null:
		tutorial_surface.visible = false
	if tutorial_dimmer != null:
		tutorial_dimmer.visible = false
	if tutorial_panel != null:
		tutorial_panel.visible = false

func _advance_first_map_tutorial() -> void:
	if not _first_map_tutorial_active():
		return
	if tutorial_step >= 3:
		_complete_first_map_tutorial()
		return
	_set_tutorial_step(tutorial_step + 1)

func _start_first_map_tutorial() -> void:
	if not _first_map_tutorial_active() or tutorial_panel == null:
		return
	# The first route is selected for the player once so the connection between
	# an encounter marker, its route, and the right-side confirmation is visible
	# before any input is required.
	_select_next_encounter()
	_set_tutorial_step(1)
	_show_map_notice("첫 작전 안내 · 반투명 노란 칸이 이번 턴의 정확한 이동 범위입니다")

func _set_tutorial_step(step: int) -> void:
	if tutorial_panel == null:
		return
	tutorial_step = clampi(step, 1, 3)
	tutorial_eyebrow.text = "첫 작전 안내  ·  %d / 3" % tutorial_step
	tutorial_progress_label.text = "%d / 3" % tutorial_step
	if tutorial_dimmer != null:
		tutorial_dimmer.visible = true
	if tutorial_surface != null:
		tutorial_surface.visible = true
	tutorial_panel.visible = true
	_reset_tutorial_pointer()
	match tutorial_step:
		1:
			tutorial_title.text = "황금빛 이동 범위를 읽으세요"
			tutorial_body.text = "지도 위 [color=#f1cf7a][b]! 조우[/b][/color] 또는 오른쪽 위 [color=#8de7d1][b]다음 조우[/b][/color]를 선택하면 실제 이동 경로가 표시됩니다.\n\n반투명 황금색 칸과 굵은 외곽선은 이번 아군 턴에 도달할 수 있는 정확한 범위입니다."
			tutorial_continue_button.text = "클릭 / 터치하여 지도를 확인"
		2:
			tutorial_title.text = "목적지를 바로 확정하세요"
			tutorial_body.text = "선택한 목적지를 [color=#f1cf7a][b]더블클릭[/b][/color]하거나 [color=#8de7d1][b]한 번 터치[/b][/color]하면 별도의 이동 버튼 없이 출발합니다.\n\n먼 조우는 이동력만큼 전진한 뒤 안전하게 중간 정지하며, 기존 이동 버튼도 그대로 사용할 수 있습니다."
			tutorial_continue_button.text = "클릭 / 터치하여 이동 준비"
		_:
			tutorial_title.text = "적 턴 뒤 다음 행동이 이어집니다"
			tutorial_body.text = "이동이 끝나면 아군 턴이 즉시 종료되고 적 부대가 한 번 행동합니다. 이어서 이동력이 보충된 다음 아군 턴이 자동으로 시작됩니다.\n\n적과 접촉하면 조우 이벤트 카드 뒤 전투로 전환되며, 보물과 현장 이벤트는 도착한 칸에서 바로 처리됩니다."
			tutorial_continue_button.text = "클릭 / 터치하여 작전 계속"

func _complete_first_map_tutorial() -> void:
	if not _first_map_tutorial_active():
		return
	AppState.profile.tutorial_progress["map_basics_complete"] = true
	_hide_first_map_tutorial_modal()
	SaveService.save_game()

func _apply_tutorial_layout(size: Vector2, portrait: bool, compact: bool, ui_scale: float) -> void:
	if tutorial_panel == null:
		return
	if tutorial_dimmer != null:
		tutorial_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Keep the tutorial's focus, but let the player read the real map beneath
		# it on a phone instead of turning the first interaction into a dark wall.
		tutorial_dimmer.color = Color("01050b96") if portrait else Color("01050bcc")
	# Landscape keeps the broad briefing card.  On portrait phones this becomes a
	# compact lower instruction sheet: the map, reachable yellow cells and the
	# highlighted encounter must remain visible while the tutorial explains them.
	# Long copy stays scrollable instead of claiming the entire viewport.
	tutorial_panel.anchor_left = 0.10
	tutorial_panel.anchor_right = 0.90
	tutorial_panel.anchor_top = 0.48 if portrait else 0.105
	tutorial_panel.anchor_bottom = 0.955 if portrait else 0.96
	tutorial_panel.offset_left = 0.0
	tutorial_panel.offset_right = 0.0
	tutorial_panel.offset_top = 0.0
	tutorial_panel.offset_bottom = 0.0
	tutorial_panel.custom_minimum_size = Vector2.ZERO
	var padding := roundi((36.0 if compact else 42.0) * ui_scale)
	if portrait:
		padding = roundi(20.0 * ui_scale)
	var content_margin := tutorial_inner_frame.get_child(0) as MarginContainer
	content_margin.add_theme_constant_override("margin_left", padding)
	content_margin.add_theme_constant_override("margin_right", padding)
	content_margin.add_theme_constant_override("margin_top", padding)
	content_margin.add_theme_constant_override("margin_bottom", padding)
	# Font targets are specified in rendered CSS pixels, not logical 1920x1080
	# pixels.  Without this conversion a nominal 25 px body becomes only 16-17 px
	# in the standard 1280x720 Web view and loses the reference's authority.
	tutorial_eyebrow.add_theme_font_size_override("font_size", _tutorial_logical_px(16.0 if portrait else (18.0 if compact else 20.0), size))
	tutorial_title.add_theme_font_size_override("font_size", _tutorial_logical_px(25.0 if portrait else (29.0 if compact else 32.0), size))
	var tutorial_body_size := _tutorial_logical_px(20.0 if portrait else (23.0 if compact else 24.0), size)
	tutorial_body.add_theme_font_size_override("normal_font_size", tutorial_body_size)
	tutorial_body.add_theme_font_size_override("bold_font_size", tutorial_body_size)
	tutorial_body.add_theme_constant_override("line_separation", _tutorial_logical_px(7.0, size))
	# `_runtime_layout_size()` is reported in CSS-like pixels while this Control
	# still lives on the fixed logical canvas.  Mixing `size.x` into the minimum
	# width makes the prompt collapse on a 390 px portrait viewport.  Scale one
	# authored physical target instead; the portrait value remains inside the
	# 80%-wide modal after its 36 px safety margins are applied.
	var continue_width := (228.0 if portrait else 420.0) * ui_scale
	tutorial_continue_button.custom_minimum_size = Vector2(continue_width, 46.0 * ui_scale)
	tutorial_continue_button.add_theme_font_size_override("font_size", _tutorial_logical_px(17.0 if portrait else (18.0 if compact else 20.0), size))
	tutorial_progress_label.add_theme_font_size_override("font_size", _tutorial_logical_px(14.0 if portrait else (15.0 if compact else 17.0), size))
	# Keep the explicit skip control in every viewport. The prior portrait-only
	# hiding left phone players with no visible way to decline a first-run guide.
	# A compact 102 px control still fits beside the eyebrow in the 320 px class.
	tutorial_dismiss_button.custom_minimum_size = Vector2((102.0 if portrait else 132.0) * ui_scale, 44.0 * ui_scale)
	tutorial_dismiss_button.add_theme_font_size_override("font_size", _tutorial_logical_px(13.0 if portrait else 18.0, size))
	tutorial_dismiss_button.visible = true

func _tutorial_logical_px(target_css_px: float, runtime_size: Vector2) -> int:
	var safe_size := Vector2(maxf(1.0, runtime_size.x), maxf(1.0, runtime_size.y))
	var canvas_scale := minf(safe_size.x / 1920.0, safe_size.y / 1080.0)
	return maxi(1, roundi(target_css_px / maxf(canvas_scale, 0.001)))

func _tutorial_weighted_font(base_font: Font, weight: float, embolden: float) -> Font:
	if base_font == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base_font
	variation.variation_opentype = {"wght": weight}
	variation.variation_embolden = embolden
	return variation

func _apply_responsive_layout() -> void:
	if detail_panel == null or map_frame == null: return
	var size := _runtime_layout_size()
	var portrait := size.y > size.x
	var compact := portrait or size.x <= 980.0
	# The project keeps a 1920x1080 logical canvas.  On a 915x412 phone the
	# canvas scale is only about 0.38, so a 56-logical-pixel control would become
	# a 21 CSS-pixel target.  Compact landscape needs the same physical touch
	# compensation as portrait instead of inheriting the desktop dimensions.
	var ui_scale := _compact_ui_scale(size) if compact else 1.0
	# Six core tactical actions fit in one 56px portrait rail.  This replaces the
	# previous two/three-row toolbar, which obscured too much of the actual map
	# before the player could see their move range or target.
	toolbar.add_theme_constant_override("h_separation", roundi((2.0 if portrait else 10.0) * ui_scale))
	toolbar.add_theme_constant_override("v_separation", roundi(6.0 * ui_scale) if portrait else 0)
	for index in range(map_toolbar_buttons.size()):
		var action_button := map_toolbar_buttons[index]
		if compact:
			action_button.custom_minimum_size = Vector2((56.0 if portrait else 112.0) * ui_scale, 56.0 * ui_scale)
			action_button.add_theme_font_size_override("font_size", roundi((17.0 if portrait else 18.0) * ui_scale))
			action_button.text = ["일반", "위험", "부대", "개요", "스킵"][index]
		else:
			action_button.custom_minimum_size = [Vector2(128, 56), Vector2(128, 56), Vector2(116, 56), Vector2(116, 56), Vector2(132, 56)][index]
			action_button.add_theme_font_size_override("font_size", 24)
			action_button.text = ["일반 작전", "위험 작전", "현재 부대", "구역 개요", "이동 건너뛰기"][index]
	if wait_button != null:
		wait_button.custom_minimum_size = Vector2((56.0 if portrait else 112.0) * ui_scale, 56.0 * ui_scale) if compact else Vector2(86, 56)
		wait_button.add_theme_font_size_override("font_size", roundi((17.0 if portrait else 18.0) * ui_scale) if compact else 24)
		wait_button.text = "대기"
	if toolbar_spacer != null:
		toolbar_spacer.visible = not compact
	if status_label != null:
		status_label.position = Vector2(14.0, 14.0) * ui_scale if compact else Vector2(22, 18)
		status_label.size = Vector2((360.0 if portrait else 430.0) * ui_scale, 36.0 * ui_scale) if compact else Vector2(560, 38)
		status_label.add_theme_font_size_override("font_size", roundi((21.0 if portrait else 24.0) * ui_scale) if compact else 29)
		if status_backplate != null:
			status_backplate.position = Vector2(-8.0, -5.0) * ui_scale if compact else Vector2(-8, -5)
			status_backplate.size = status_label.size + (Vector2(16.0, 10.0) * ui_scale if compact else Vector2(16, 10))
	if next_encounter_button != null:
		var next_width := (188.0 if portrait else 248.0) * ui_scale
		var next_height := (56.0 if compact else 52.0) * ui_scale
		next_encounter_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		next_encounter_button.offset_left = -next_width - (12.0 * ui_scale if compact else 18.0)
		next_encounter_button.offset_right = -(12.0 * ui_scale if compact else 18.0)
		# Portrait uses a second status row.  Keeping both controls on the same row
		# made the operation title and `next encounter` button overlap by ~180 px.
		next_encounter_button.offset_top = (10.0 if portrait else 14.0) * ui_scale if compact else 18.0
		next_encounter_button.offset_bottom = next_encounter_button.offset_top + next_height
		next_encounter_button.add_theme_font_size_override("font_size", roundi(20.0 * ui_scale) if compact else 23)
	if legend_card != null:
		# The minimap already carries the compact Korean legend. Hiding this
		# secondary card prevents a clipped narrow label from reading as release
		# debug residue on constrained embedded Web viewports.
		legend_card.visible = false
		legend_card.position = Vector2(12.0 * ui_scale, -112.0 * ui_scale) if portrait else Vector2(18, -58)
		legend_card.custom_minimum_size = Vector2(0.0, 76.0 * ui_scale) if portrait else Vector2.ZERO
	if legend_label != null:
		legend_label.add_theme_font_size_override("font_size", roundi(17.0 * ui_scale) if portrait else 20)
	if route_minimap != null:
		if portrait:
			var map_width := clampf(size.x * 0.52, 176.0, 244.0)
			route_minimap.custom_minimum_size = Vector2(map_width, 132.0)
			route_minimap.position = Vector2(12.0, -154.0)
		elif compact:
			route_minimap.custom_minimum_size = Vector2(230.0 * ui_scale, 150.0 * ui_scale)
			route_minimap.position = Vector2(18.0 * ui_scale, -224.0 * ui_scale)
		else:
			route_minimap.custom_minimum_size = Vector2(230.0, 150.0)
			route_minimap.position = Vector2(18.0, -224.0)
	# Node labels are actual stage-selection controls. They must retain an
	# explicit phone-sized hit region instead of shrinking with the 1920 canvas.
	for node_id in node_buttons:
		var node_button: Button = node_buttons[node_id]
		if compact:
			node_button.custom_minimum_size = Vector2(72.0 * ui_scale, 56.0 * ui_scale)
			node_button.size = node_button.custom_minimum_size
			node_button.add_theme_font_size_override("font_size", roundi(20.0 * ui_scale))
		else:
			node_button.custom_minimum_size = Vector2(92.0, 42.0)
			node_button.size = Vector2(92.0, 42.0)
			node_button.add_theme_font_size_override("font_size", 21)
	var has_selection := not selected_node.is_empty() or not selected_treasure.is_empty() or not selected_relay.is_empty() or not selected_event.is_empty()
	if compact:
		# A real mobile bottom sheet reserves the top status strip and bottom safe
		# area before it takes map space. It is not a desktop right panel scaled down.
		map_frame.offset_right = 0.0
		detail_panel.anchor_left = 0.0
		detail_panel.anchor_right = 1.0
		detail_panel.anchor_top = 1.0
		detail_panel.anchor_bottom = 1.0
		detail_panel.offset_left = (8.0 if portrait else 16.0) * ui_scale
		detail_panel.offset_right = -(8.0 if portrait else 16.0) * ui_scale
		var bottom_safe_margin := 20.0 if portrait else 26.0
		# The contextual card remains scrollable; it does not need to reserve a
		# desktop inspector's height on a phone.  This returns roughly 42px of
		# vertical map visibility on the common 390×844 portrait viewport.
		var sheet_height := 280.0 if portrait else 230.0
		detail_panel.offset_top = -(sheet_height + bottom_safe_margin) * ui_scale
		detail_panel.offset_bottom = -bottom_safe_margin * ui_scale
		detail_panel.visible = has_selection
		detail_title.add_theme_font_size_override("font_size", roundi(28.0 * ui_scale))
		detail_body.custom_minimum_size = Vector2(0.0, (70.0 if portrait else 102.0) * ui_scale)
		detail_body.add_theme_font_size_override("normal_font_size", roundi((21.0 if portrait else 23.0) * ui_scale))
		# Every contextual action remains finger-sized after canvas_items scales the
		# 1920x1080 surface down to a compact browser viewport.
		for child in detail_scroll.find_children("*", "Button", true, false):
			var detail_action := child as Button
			detail_action.custom_minimum_size.y = 56.0 * ui_scale
			detail_action.add_theme_font_size_override("font_size", roundi(19.0 * ui_scale))
	else:
		var show_detail := has_selection
		map_frame.offset_right = -414.0 if show_detail else 0.0
		detail_panel.anchor_left = 1.0
		detail_panel.anchor_right = 1.0
		detail_panel.anchor_top = 0.0
		detail_panel.anchor_bottom = 0.0
		detail_panel.offset_left = -400.0
		detail_panel.offset_right = -12.0
		# Desktop detail is a contextual stage card, not a permanently tall
		# inspector. Preserve scrolling for long rewards but return visual space to
		# the map when the current selection only needs a short decision.
		detail_panel.offset_top = 14.0
		detail_panel.offset_bottom = 560.0
		detail_panel.visible = show_detail
		detail_title.add_theme_font_size_override("font_size", 34)
		detail_body.custom_minimum_size = Vector2(350.0, 246.0)
		detail_body.add_theme_font_size_override("normal_font_size", 24)
	_apply_tutorial_layout(size, portrait, compact, ui_scale)
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

func _compact_ui_scale(runtime_size: Vector2) -> float:
	if runtime_size.y > runtime_size.x:
		return _portrait_ui_scale(runtime_size)
	if runtime_size.x <= 980.0:
		return clampf(1080.0 / maxf(360.0, runtime_size.y), 1.0, 3.0)
	return 1.0

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
	button.add_theme_font_size_override("font_size", roundi(24.0 * ui_scale))
	button.add_theme_stylebox_override("normal", _panel_style(Color("102d43"), Color("3f7798"), 1, 11))
	button.add_theme_stylebox_override("hover", _panel_style(Color("1b5369"), Color("84f2db"), 2, 11))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("17485d"), Color("ffd17b"), 2, 11))
	button.pressed.connect(callback)
	return button

func _add_occlusion_silhouette(source: Sprite3D, parent: Node3D, silhouette_name: String, color: Color) -> Sprite3D:
	if source == null or source.texture == null:
		return null
	var silhouette := Sprite3D.new()
	silhouette.name = silhouette_name
	# This low-opacity duplicate is deliberately no-depth. The normal pawn still
	# participates in terrain depth; only its exact animated contour survives
	# when a dam wall or tall plateau hides it from the camera.
	silhouette.texture = source.texture
	silhouette.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	silhouette.pixel_size = source.pixel_size
	silhouette.position = source.position
	silhouette.scale = Vector3(1.075, 1.075, 1.075)
	silhouette.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	silhouette.no_depth_test = true
	silhouette.shaded = false
	silhouette.modulate = Color(color.r, color.g, color.b, 0.28)
	silhouette.render_priority = source.render_priority - 1
	silhouette.set_meta("occlusion_silhouette", true)
	parent.add_child(silhouette)
	return silhouette

func _build_world() -> void:
	world_root = Node3D.new()
	world_root.name = "ChapterMapWorld"
	viewport.add_child(world_root)
	var world_environment := WorldEnvironment.new()
	map_world_environment = Environment.new()
	map_world_environment.background_mode = Environment.BG_COLOR
	map_world_environment.background_color = Color("0a2634")
	map_world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	map_world_environment.ambient_light_color = Color("9cb59d")
	# Compatibility/Web maps need enough bounce light that elevation reads as
	# moss, stone, and layered earth—not as a field of near-black hex walls.
	map_world_environment.ambient_light_energy = 0.74
	# The map uses a restrained filmic pass and a very low fog density to make
	# elevation, coast and distant route sections recede. This is visual depth,
	# not a gameplay fog-of-war substitute.
	map_world_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	map_world_environment.tonemap_exposure = 0.96
	map_world_environment.adjustment_enabled = true
	map_world_environment.adjustment_brightness = 0.94
	map_world_environment.adjustment_contrast = 1.23
	map_world_environment.adjustment_saturation = 1.02
	map_world_environment.fog_enabled = true
	map_world_environment.fog_light_color = Color("315f66")
	map_world_environment.fog_light_energy = 0.34
	map_world_environment.fog_density = 0.0022
	map_world_environment.fog_sky_affect = 0.42
	world_environment.environment = map_world_environment
	world_root.add_child(world_environment)
	_load_blender_kit()
	_load_terrain_relief()
	_create_world_backdrop()
	_create_world_island_shelf()
	_create_connected_terrain_surface()
	_create_boundary_coastline()
	_create_signal_causeways()
	map_sun = DirectionalLight3D.new()
	map_sun.rotation_degrees = Vector3(-42, -38, 0)
	map_sun.light_color = Color("ffeac4")
	map_sun.light_energy = 0.98
	# A single bounded compatibility shadow makes terrain height and pawn contact
	# readable without adding a multi-light shadow budget to mobile Web.
	map_sun.shadow_enabled = true
	map_sun.directional_shadow_max_distance = 34.0
	map_sun.directional_shadow_fade_start = 0.72
	map_sun.light_angular_distance = 1.8
	world_root.add_child(map_sun)
	map_fill = DirectionalLight3D.new()
	map_fill.rotation_degrees = Vector3(-48, 136, 0)
	map_fill.light_color = Color("8fd8de")
	map_fill.light_energy = 0.48
	map_fill.shadow_enabled = false
	world_root.add_child(map_fill)
	_stream_visible_tiles(Vector2i(int(map_state.current_q), int(map_state.current_r)), true)
	movement_range_fill = MeshInstance3D.new()
	movement_range_fill.name = "MovementRangeYellowFill"
	movement_range_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(movement_range_fill)
	movement_range_grid = MeshInstance3D.new()
	movement_range_grid.name = "MovementRangeYellowCellGrid"
	movement_range_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(movement_range_grid)
	movement_range_boundary = MeshInstance3D.new()
	movement_range_boundary.name = "MovementRangeYellowBoundary"
	movement_range_boundary.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(movement_range_boundary)
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
	for relay in definition.get("relays", []):
		_create_relay_visual(relay)
	for event in definition.get("map_events", []):
		_create_event_visual(event)
	for landmark in definition.get("landmarks", []):
		_create_landmark_visual(landmark)
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
	if environment_fx != null:
		environment_fx.bind_world(map_world_environment, terrain_material, map_water_material, map_sun, map_fill)
		_refresh_environment_presentation()

func _material(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	# Ground, road and encounter-terrace meshes deliberately rely on their
	# upward-facing production triangles.  Keep back-face culling explicit so a
	# future material default cannot hide a reversed-winding regression behind a
	# two-sided workaround.
	material.cull_mode = BaseMaterial3D.CULL_BACK
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.4
	return material

func _add_route_accent_light(parent: Node3D, local_position: Vector3, energy: float) -> void:
	# Small unshadowed amber pools give route/encounter landmarks a visual focal
	# hierarchy without spending a Compatibility-Web shadow budget. They are
	# presentation only and deliberately do not alter node selection or discovery.
	var accent := OmniLight3D.new()
	accent.name = "RouteAmberAccent"
	accent.light_color = Color("ffc77a")
	accent.light_energy = energy
	accent.omni_range = 3.35
	accent.omni_attenuation = 1.75
	accent.shadow_enabled = false
	accent.position = local_position
	parent.add_child(accent)

func _create_world_backdrop() -> void:
	# A low-cost water field makes hidden territory read as a real coastline rather
	# than a black prototype board. It has no gameplay or tile-selection role.
	var water := MeshInstance3D.new()
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(360.0, 220.0)
	water.mesh = water_mesh
	# The long-map ocean is a real world backdrop, not a foreground occluder.
	# Keep it well below the lowest generated terrain socket so the production
	# depth pass can correctly show a grounded squad, hostile, shadow and ring.
	water.position = Vector3(1.8, OCEAN_SURFACE_Y, -1.8)
	var water_material := ShaderMaterial.new()
	water_material.shader = EnvironmentWaterShader
	# Water is a backdrop. Draw it before all physical terrain, route and pawn
	# meshes so it contributes only where the map has no nearer world surface.
	water_material.render_priority = -127
	water.material_override = water_material
	map_water_material = water_material
	water.set_meta("water_material", water_material)
	world_root.add_child(water)
	# Do not place an opaque, fixed world-space horizon plane behind this macro
	# map.  The chapter spans far beyond the origin; once the camera reached the
	# HARD branch, the old finite plane crossed in front of H02 and hid valid
	# terrain/pawns while their screen-space labels remained visible.  The
	# Environment background, low fog and ocean plane already provide the distant
	# backdrop without introducing an occluding edge into the traversable world.

func _terrain_surface_color(tile: Dictionary) -> Color:
	# R10 gives each world role a durable hue family before lighting is applied.
	# This is intentionally a restrained terrain palette, not rainbow navigation:
	# moss/olive land, burnished route, cool slate ruins and blue water must still
	# survive mist and rain without collapsing back into the old teal board.
	var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
	var phase: int = abs(coord.x * 13 + coord.y * 19) % 4
	var noise := (float(phase) - 1.5) * 0.018
	var base := Color("2f4c25")
	match str(tile.get("terrain_type", "FOREST")):
		"FOREST":
			base = [Color("294923"), Color("36552a"), Color("415d2d"), Color("2f4d2c")][phase]
		"ROAD": base = [Color("674020"), Color("7a4e24"), Color("5d3d23"), Color("855829")][phase]
		"RUINS": base = [Color("3d4652"), Color("48515d"), Color("36434f"), Color("515966")][phase]
		"SHALLOW_WATER": base = [Color("1b4c79"), Color("20598b"), Color("174368"), Color("296394")][phase]
	return Color(clampf(base.r + noise, 0.0, 1.0), clampf(base.g + noise, 0.0, 1.0), clampf(base.b + noise, 0.0, 1.0), 1.0)

func _terrain_corner_key(point: Vector3) -> String:
	return "%d:%d" % [roundi(point.x * 1000.0), roundi(point.z * 1000.0)]

func _create_connected_terrain_surface() -> void:
	# Navigation continues to use individual axial cells, but the visible ground
	# is a single shared-vertex landscape. This makes gentle slopes, ridges and
	# clearings read as a world surface instead of a field of isolated hex slabs.
	var corner_totals: Dictionary = {}
	var corner_counts: Dictionary = {}
	var terrain_tiles: Array = []
	for raw_tile in definition.get("tiles", []):
		var tile: Dictionary = raw_tile
		if bool(tile.get("movement_blocked", false)) or str(tile.get("terrain_type", "")) == "DEEP_WATER":
			continue
		terrain_tiles.append(tile)
		var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		var center := HexCoordScript.axial_to_world(coord, TILE_SIZE)
		var height := float(tile.get("elevation", 0)) * ELEVATION_STEP
		for corner_index in range(6):
			var angle := PI / 6.0 + float(corner_index) * PI / 3.0
			var corner := center + Vector3(cos(angle) * TILE_SIZE, 0.0, sin(angle) * TILE_SIZE)
			var key := _terrain_corner_key(corner)
			corner_totals[key] = float(corner_totals.get(key, 0.0)) + height
			corner_counts[key] = int(corner_counts.get(key, 0)) + 1
	if terrain_tiles.is_empty():
		return
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tile in terrain_tiles:
		var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		var center := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(tile.get("elevation", 0)) * ELEVATION_STEP + 0.006)
		var tint := _terrain_surface_color(tile)
		for corner_index in range(6):
			var next_index := (corner_index + 1) % 6
			var angle_a := PI / 6.0 + float(corner_index) * PI / 3.0
			var angle_b := PI / 6.0 + float(next_index) * PI / 3.0
			var point_a := HexCoordScript.axial_to_world(coord, TILE_SIZE) + Vector3(cos(angle_a) * TILE_SIZE * 1.003, 0.0, sin(angle_a) * TILE_SIZE * 1.003)
			var point_b := HexCoordScript.axial_to_world(coord, TILE_SIZE) + Vector3(cos(angle_b) * TILE_SIZE * 1.003, 0.0, sin(angle_b) * TILE_SIZE * 1.003)
			point_a.y = float(corner_totals.get(_terrain_corner_key(point_a), 0.0)) / maxf(1.0, float(corner_counts.get(_terrain_corner_key(point_a), 1))) + 0.004
			point_b.y = float(corner_totals.get(_terrain_corner_key(point_b), 0.0)) / maxf(1.0, float(corner_counts.get(_terrain_corner_key(point_b), 1))) + 0.004
			var normal := Plane(center, point_a, point_b).normal
			if normal.y < 0.0: normal = -normal
			# Godot considers clockwise triangles front-facing for this X/Z map mesh.
			# Keep that engine-facing order while CULL_BACK remains enabled: using the
			# mathematically positive-Y order here silently culled the real ground and
			# left a valid pawn looking as if it stood over ocean.
			for vertex in [center, point_a, point_b]:
				surface_tool.set_color(tint)
				surface_tool.set_normal(normal)
				surface_tool.add_vertex(vertex)
	var mesh := surface_tool.commit()
	if mesh == null:
		return
	terrain_surface = MeshInstance3D.new()
	terrain_surface.name = "ConnectedTerrainSurface"
	terrain_surface.mesh = mesh
	terrain_material = StandardMaterial3D.new()
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 0.92
	terrain_material.metallic = 0.0
	terrain_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# The generated continuous mesh uses Godot's clockwise front-face contract.
	# Keep production back-face culling active; the controlled N04 coverage probe
	# confirmed that disabling culling does not resolve the missing-root defect.
	terrain_material.cull_mode = BaseMaterial3D.CULL_BACK
	terrain_surface.material_override = terrain_material
	world_root.add_child(terrain_surface)

func _create_boundary_coastline() -> void:
	# Boundary-aware reef placement follows the actual macro-map shoreline, so
	# the ocean has a readable coast at every streamed district instead of only a
	# few fixed showcase props near the starting area.
	# This is one continuous low-poly shallow-water ribbon, not a sea of water
	# hexes. At game scale it gives the coast a pale wet edge before the deep tide
	# begins, which makes a long land/water diagonal read as shoreline rather
	# than the edge of a prototype board.
	var shallow_mesh := ImmediateMesh.new()
	var shallow_material := _material(Color("2a8f91"), Color("0f6a70"))
	shallow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shallow_material.albedo_color.a = 0.82
	shallow_material.emission_energy_multiplier = 0.34
	shallow_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, shallow_material)
	for raw_tile in definition.get("tiles", []):
		var tile: Dictionary = raw_tile
		if bool(tile.get("movement_blocked", false)):
			continue
		var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		for direction_index in range(HexCoordScript.DIRECTIONS.size()):
			var direction: Vector2i = HexCoordScript.DIRECTIONS[direction_index]
			if grid.has(coord + direction):
				continue
			var center := HexCoordScript.axial_to_world(coord, TILE_SIZE)
			var neighbor := HexCoordScript.axial_to_world(coord + direction, TILE_SIZE)
			var normal := (neighbor - center).normalized()
			var tangent := Vector3(-normal.z, 0.0, normal.x)
			var inner_center := center + normal * TILE_SIZE * 0.56
			var outer_center := center + normal * TILE_SIZE * 1.74
			# Keep this only a hair below the land surface.  The former ribbon sat
			# at the deep-ocean plane, where its colour was swallowed by the large
			# dark water backdrop at gameplay camera distance.
			inner_center.y = -0.022
			outer_center.y = -0.045
			var inner_left := inner_center - tangent * TILE_SIZE * 0.60
			var inner_right := inner_center + tangent * TILE_SIZE * 0.60
			var outer_left := outer_center - tangent * TILE_SIZE * 0.74
			var outer_right := outer_center + tangent * TILE_SIZE * 0.74
			for vertex in [inner_left, outer_left, outer_right, inner_left, outer_right, inner_right]:
				shallow_mesh.surface_add_vertex(vertex)
			# Sparse, deterministic selection avoids a repeated once-per-hex foam
			# ring while ensuring every route district gets some coastal structure.
			var signature: int = absi(coord.x * 31 + coord.y * 17 + direction_index * 7)
			if signature % 5 != 0:
				continue
			var edge := center.lerp(neighbor, 0.58)
			edge.y = -0.018
			var yaw := atan2(neighbor.z - center.z, neighbor.x - center.x)
			_spawn_kit_components("PROP_COAST_FOAM", edge, 0.70 + float(signature % 3) * 0.13, yaw)
			if signature % 10 == 0:
				_spawn_kit_component("PROP_CLIFF_FACET_B", edge + Vector3(0.10, 0.10, -0.08), 0.38, yaw)
	shallow_mesh.surface_end()
	if shallow_mesh.get_surface_count() > 0:
		var shallow_instance := MeshInstance3D.new()
		shallow_instance.name = "ContinuousShallowCoastline"
		shallow_instance.mesh = shallow_mesh
		world_root.add_child(shallow_instance)

func _create_signal_causeways() -> void:
	# Stage coordinates are intentionally far apart.  This subdued stone-and-
	# signal causeway makes the route a physical part of the world even across a
	# broad valley or coast, without reverting to isolated hex podiums.  It also
	# gives every encounter a reliable visual ground contact at map scale.
	var shoulder_mesh := ImmediateMesh.new()
	var landing_mesh := ImmediateMesh.new()
	var landing_edge_mesh := ImmediateMesh.new()
	var base_mesh := ImmediateMesh.new()
	var inlay_mesh := ImmediateMesh.new()
	# The shoulder follows the *same deterministic greedy route* used to create
	# macro-map traversable terrain.  A cube-interpolated visual line could cut
	# across a different equal-cost corridor, which made late-chapter squad
	# positions look as if they stood in open water even though pathfinding had
	# correctly kept them on a valid tile.
	# This is the navigable expedition spine, not a thin UI trace.  It remains
	# legible where the macro route crosses a coastal cut, so a squad is never
	# visually stranded on a featureless water field while its logical hex is
	# correctly traversable.
	shoulder_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("385c47")))
	# Encounter clearings are deliberately larger, organic terrain terraces. They
	# give a moving hostile a readable ground contact even while it patrols one
	# cell away from its authored stage node; this avoids the visual impression of
	# a pawn hovering over the ocean between two macro districts.
	landing_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("3f7057")))
	landing_edge_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("1d3e35")))
	base_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("4d5943"), Color("182e2a")))
	inlay_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("68bcb0"), Color("21635d")))
	var landing_cells: Dictionary = {}
	var route_sets: Array = [definition.get("normal_route", []), definition.get("hard_route", [])]
	for route_index in range(route_sets.size()):
		var route: Array = route_sets[route_index]
		var previous := Vector2i(int(definition.get("start_hex", {}).get("q", 0)), int(definition.get("start_hex", {}).get("r", 0)))
		if route_index == 1:
			var normal_route: Array = definition.get("normal_route", [])
			var branch_node := ChapterMapLoaderScript.node_for_stage(definition, str(normal_route.back())) if not normal_route.is_empty() else {}
			if not branch_node.is_empty():
				previous = Vector2i(int(branch_node.get("q", 0)), int(branch_node.get("r", 0)))
		for stage_id in route:
			var node := ChapterMapLoaderScript.node_for_stage(definition, str(stage_id))
			if node.is_empty():
				continue
			var target := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
			var path := MacroWorldGeneratorScript.route_line(previous, target)
			for point_index in range(maxi(0, path.size() - 1)):
				var from_coord: Vector2i = path[point_index]
				var to_coord: Vector2i = path[point_index + 1]
				var from := HexCoordScript.axial_to_world(from_coord, TILE_SIZE, float(grid.tile(from_coord).get("elevation", 0)) * ELEVATION_STEP + 0.032)
				var to := HexCoordScript.axial_to_world(to_coord, TILE_SIZE, float(grid.tile(to_coord).get("elevation", 0)) * ELEVATION_STEP + 0.032)
				var direction := (to - from).normalized()
				var tangent := Vector3(-direction.z, 0.0, direction.x)
				_add_causeway_segment(shoulder_mesh, from + Vector3(0.0, 0.034, 0.0), to + Vector3(0.0, 0.034, 0.0), tangent, 0.48)
				_add_causeway_segment(base_mesh, from, to, tangent, 0.36)
				_add_causeway_segment(inlay_mesh, from + Vector3(0.0, 0.012, 0.0), to + Vector3(0.0, 0.012, 0.0), tangent, 0.055)
			landing_cells[HexCoordScript.key(target)] = target
			previous = target
	# Selected encounter coordinates can move along their authored patrol route.
	# Treat those few cells as part of the same landmark clearing rather than
	# forcing the squad/enemy visual to depend on a single static node center.
	for patrol_value in definition.get("patrols", []):
		var patrol: Dictionary = patrol_value
		for route_value in patrol.get("patrol_route_hexes", []):
			var route_coord := Vector2i(int(route_value.get("q", 0)), int(route_value.get("r", 0)))
			if grid.traversable(route_coord):
				landing_cells[HexCoordScript.key(route_coord)] = route_coord
	var landing_keys: Array = landing_cells.keys()
	landing_keys.sort()
	for landing_key in landing_keys:
		var landing_coord: Vector2i = landing_cells[landing_key]
		var platform_center := HexCoordScript.axial_to_world(landing_coord, TILE_SIZE, float(grid.tile(landing_coord).get("elevation", 0)) * ELEVATION_STEP + 0.047)
		_add_route_landing(landing_mesh, platform_center, 1.38)
		_add_route_landing_edge(landing_edge_mesh, platform_center, 1.38, 0.20)
	shoulder_mesh.surface_end()
	landing_mesh.surface_end()
	landing_edge_mesh.surface_end()
	base_mesh.surface_end()
	inlay_mesh.surface_end()
	if shoulder_mesh.get_surface_count() > 0:
		var shoulder_instance := MeshInstance3D.new()
		shoulder_instance.name = "SignalRouteGroundShoulder"
		shoulder_instance.mesh = shoulder_mesh
		world_root.add_child(shoulder_instance)
	if landing_mesh.get_surface_count() > 0:
		var landing_instance := MeshInstance3D.new()
		landing_instance.name = "SignalRouteLandingTerraces"
		landing_instance.mesh = landing_mesh
		world_root.add_child(landing_instance)
	if landing_edge_mesh.get_surface_count() > 0:
		var landing_edge_instance := MeshInstance3D.new()
		landing_edge_instance.name = "SignalRouteLandingEdges"
		landing_edge_instance.mesh = landing_edge_mesh
		world_root.add_child(landing_edge_instance)
	if base_mesh.get_surface_count() > 0:
		var base_instance := MeshInstance3D.new()
		base_instance.name = "SignalRouteCauseway"
		base_instance.mesh = base_mesh
		world_root.add_child(base_instance)
	if inlay_mesh.get_surface_count() > 0:
		var inlay_instance := MeshInstance3D.new()
		inlay_instance.name = "SignalRouteInlay"
		inlay_instance.mesh = inlay_mesh
		world_root.add_child(inlay_instance)

func _add_causeway_segment(mesh: ImmediateMesh, from: Vector3, to: Vector3, tangent: Vector3, half_width: float) -> void:
	var from_left := from - tangent * half_width
	var from_right := from + tangent * half_width
	var to_left := to - tangent * half_width
	var to_right := to + tangent * half_width
	# Match Godot's clockwise front-face convention used by the connected terrain.
	# CULL_BACK stays on; this is the real visual surface rather than a two-sided
	# safety mask.
	for vertex in [from_left, to_left, to_right, from_left, to_right, from_right]:
		mesh.surface_add_vertex(vertex)

func _add_route_landing(mesh: ImmediateMesh, center: Vector3, radius: float) -> void:
	# Softened twelve-sided terraces are encounter clearings and signal docks,
	# deliberately distinct from the mathematical six-sided selection grid.
	var points: Array[Vector3] = []
	for index in range(12):
		var angle := float(index) * TAU / 12.0 + PI / 12.0
		var irregularity := 0.92 if index % 2 == 0 else 1.0
		points.append(center + Vector3(cos(angle) * radius * irregularity, 0.0, sin(angle) * radius * irregularity))
	for index in range(points.size()):
		mesh.surface_add_vertex(center)
		mesh.surface_add_vertex(points[index])
		mesh.surface_add_vertex(points[(index + 1) % points.size()])

func _add_route_landing_edge(mesh: ImmediateMesh, center: Vector3, radius: float, depth: float) -> void:
	# A shallow irregular skirt gives each encounter clearing a readable height
	# break without reintroducing a field of isolated hex columns.
	var top_points: Array[Vector3] = []
	var bottom_points: Array[Vector3] = []
	for index in range(12):
		var angle := float(index) * TAU / 12.0 + PI / 12.0
		var irregularity := 0.92 if index % 2 == 0 else 1.0
		var top := center + Vector3(cos(angle) * radius * irregularity, 0.0, sin(angle) * radius * irregularity)
		top_points.append(top)
		bottom_points.append(top - Vector3(0.0, depth, 0.0))
	for index in range(top_points.size()):
		var next_index := (index + 1) % top_points.size()
		for vertex in [top_points[index], bottom_points[index], bottom_points[next_index], top_points[index], bottom_points[next_index], top_points[next_index]]:
			mesh.surface_add_vertex(vertex)

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
	_create_landmass_formations(route_points)
	_create_coastal_landmarks(route_points, shelf_center, shelf_radius, shelf_aspect)
	_create_deep_water_reef_silhouettes(route_points, shelf_center, shelf_radius, shelf_aspect)

func _create_coastal_landmarks(route_points: Array[Vector3], shelf_center: Vector3, shelf_radius: float, shelf_aspect: Vector3) -> void:
	# The coast needs its own silhouette and small points of interest. These are
	# sparse Blender-kit reefs, foam arcs and abandoned signal pieces—not a
	# blanket of decorative particles—so open water reads as an explorable shore
	# instead of an empty teal board boundary.
	if route_points.is_empty():
		return
	var coast_anchors: Array[Dictionary] = [
		{"point": route_points[mini(1, route_points.size() - 1)] + Vector3(4.2, -0.49, 1.4), "scale": 1.40, "yaw": 0.20},
		{"point": route_points[mini(3, route_points.size() - 1)] + Vector3(4.6, -0.49, 0.8), "scale": 1.64, "yaw": -0.18},
		{"point": route_points[mini(4, route_points.size() - 1)] + Vector3(4.1, -0.49, -1.7), "scale": 1.36, "yaw": 0.46},
		{"point": route_points[route_points.size() / 2] + Vector3(3.4, -0.49, -2.5), "scale": 1.12, "yaw": -0.52},
		{"point": route_points[mini(7, route_points.size() - 1)] + Vector3(4.3, -0.49, 1.5), "scale": 1.42, "yaw": 0.08},
		{"point": route_points[route_points.size() - 2] + Vector3(4.8, -0.49, 1.0), "scale": 1.55, "yaw": 0.72}
	]
	for coast in coast_anchors:
		var point: Vector3 = coast.point
		var scale_factor := float(coast.scale)
		var yaw := float(coast.yaw)
		_spawn_kit_components("PROP_COAST_FOAM", point, scale_factor, yaw)
		_spawn_kit_component("PROP_CLIFF_FACET_A", point + Vector3(-0.42, 0.10, 0.24), scale_factor * 0.72, yaw)
		_spawn_kit_component("PROP_CLIFF_FACET_B", point + Vector3(0.36, 0.06, -0.22), scale_factor * 0.56, yaw + 0.44)
		if int(absf(point.x)) % 2 == 0:
			_spawn_kit_components("PROP_SIGNAL_BEACON", point + Vector3(-0.34, 0.08, 0.38), scale_factor * 0.44, yaw - 0.24)
	# A few low, broad reflected bands give the water a shoreline rhythm at the
	# wide zoom without adding a texture atlas or a continuous particle cost.
	for band_index in range(4):
		var band := MeshInstance3D.new()
		var band_mesh := TorusMesh.new()
		band_mesh.inner_radius = 1.25 + float(band_index) * 0.52
		band_mesh.outer_radius = band_mesh.inner_radius + 0.026
		band_mesh.rings = 24
		band_mesh.ring_segments = 8
		band.mesh = band_mesh
		band.position = shelf_center + Vector3(shelf_radius * shelf_aspect.x * 0.36 + float(band_index) * 2.4, -0.535, -shelf_radius * shelf_aspect.z * 0.34 + float(band_index % 2) * 3.8)
		band.scale = Vector3(1.85, 0.18, 0.62)
		band.rotation_degrees = Vector3(0.0, 18.0 + float(band_index) * 11.0, 0.0)
		var water_line := _material(Color("3d8f98"), Color("116c76"))
		water_line.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_line.albedo_color.a = 0.44
		water_line.emission_energy_multiplier = 0.42
		band.material_override = water_line
		world_root.add_child(band)

func _create_deep_water_reef_silhouettes(route_points: Array[Vector3], shelf_center: Vector3, shelf_radius: float, shelf_aspect: Vector3) -> void:
	# Two or three broad silhouettes are much more useful at overview scale than
	# dozens of tiny foam marks.  They intentionally sit well away from routes so
	# they add deep-water identity without suggesting a traversable side path.
	if route_points.is_empty():
		return
	var reef_anchors: Array[Dictionary] = [
		{"point": shelf_center + Vector3(shelf_radius * shelf_aspect.x * 0.34, -0.46, -shelf_radius * shelf_aspect.z * 0.23), "scale": 2.25, "yaw": 0.42},
		{"point": shelf_center + Vector3(shelf_radius * shelf_aspect.x * 0.18, -0.48, shelf_radius * shelf_aspect.z * 0.38), "scale": 1.72, "yaw": -0.24},
		{"point": shelf_center + Vector3(-shelf_radius * shelf_aspect.x * 0.28, -0.49, shelf_radius * shelf_aspect.z * 0.20), "scale": 1.48, "yaw": 0.74},
	]
	for reef in reef_anchors:
		var point: Vector3 = reef.point
		var scale_factor := float(reef.scale)
		var yaw := float(reef.yaw)
		_spawn_kit_component("PROP_CLIFF_FACET_A", point, scale_factor, yaw)
		_spawn_kit_component("PROP_CLIFF_FACET_B", point + Vector3(0.48, 0.08, -0.34), scale_factor * 0.66, yaw + 0.38)
		_spawn_kit_components("PROP_COAST_FOAM", point + Vector3(-0.22, -0.045, 0.20), scale_factor * 0.82, yaw - 0.16)

func _create_landmass_formations(route_points: Array[Vector3]) -> void:
	# Three deliberately broad relief shelves bind local hex cells into memorable
	# terrain districts. They sit under, never over, walkable cells: gameplay
	# still reads mathematical axial tiles while the map stops looking like an
	# isolated collection of identical columns.
	if route_points.size() < 3:
		return
	for formation_definition in [
		{"index": 1, "prefix": "RELIEF_FOREST_MESA_A", "radius": 8.8, "aspect": Vector3(1.55, 1.0, 0.68), "color": Color("1b4a41"), "height": 0.42},
		{"index": route_points.size() / 2, "prefix": "RELIEF_RUIN_TERRACE_B", "radius": 10.5, "aspect": Vector3(1.42, 1.0, 0.72), "color": Color("24463d"), "height": 0.58},
		{"index": route_points.size() - 2, "prefix": "RELIEF_COAST_SHELF_C", "radius": 9.4, "aspect": Vector3(1.36, 1.0, 0.70), "color": Color("244b49"), "height": 0.48}
	]:
		var anchor: Vector3 = route_points[int(formation_definition.index)]
		var anchor_coord := HexCoordScript.world_to_axial(anchor, TILE_SIZE)
		var anchor_surface := float(grid.tile(anchor_coord).get("elevation", 0)) * ELEVATION_STEP
		# The authored relief becomes the large continuous district floor. A very
		# small offset keeps it above the individual mathematical cells, visually
		# breaking up the old disconnected-hex-column silhouette without changing
		# pathing, collision, or the source axial coordinates.
		var relief_parts := _spawn_kit_components(str(formation_definition.prefix), anchor + Vector3(0.0, anchor_surface + 0.02, 0.0), 1.0, 0.0)
		if not relief_parts.is_empty():
			# Source meshes are authored at a compact reusable scale. Expand only
			# X/Z here so they become a connected district floor while preserving
			# the shallow strata height under the gameplay tile caps.
			var lateral_scale := float(formation_definition.radius) / 3.4
			for relief_part in relief_parts:
				relief_part.scale.x *= lateral_scale * float(formation_definition.aspect.x)
				relief_part.scale.z *= lateral_scale * float(formation_definition.aspect.z)
			var ridge_parts := _spawn_kit_components("RELIEF_RIDGE_A", anchor + Vector3(0.0, anchor_surface + 0.16, 0.0), 0.90, float(int(formation_definition.index) % 3) * 0.48)
			for ridge_part in ridge_parts:
				ridge_part.scale.x *= lateral_scale * 0.85
				ridge_part.scale.z *= lateral_scale * 0.58
			continue
		var formation := MeshInstance3D.new()
		formation.name = "TerrainLandmassFormation"
		var formation_mesh := CylinderMesh.new()
		formation_mesh.top_radius = float(formation_definition.radius)
		formation_mesh.bottom_radius = float(formation_definition.radius) + 1.2
		formation_mesh.height = float(formation_definition.height)
		formation_mesh.radial_segments = 9
		formation.mesh = formation_mesh
		formation.scale = formation_definition.aspect
		formation.rotation_degrees.y = 18.0 + float(int(formation_definition.index) % 3) * 14.0
		formation.position = anchor + Vector3(0.0, -0.52, 0.0)
		formation.material_override = _material(formation_definition.color, formation_definition.color.darkened(0.58))
		world_root.add_child(formation)

func _load_blender_kit() -> void:
	var kit_path := "res://assets/art/chapter_map/R11/CH01_MAP_KIT_R11.glb"
	if not ResourceLoader.exists(kit_path): return
	var packed := load(kit_path) as PackedScene
	if packed == null: return
	var kit := packed.instantiate()
	_collect_kit_meshes(kit)
	kit.free()

func _load_terrain_relief() -> void:
	# This project-owned source is built headlessly by tools/blender and is kept
	# separate from asset_share so shared generator originals are never mutated.
	var relief_path := "res://assets/art/chapter_map/R7/CH01_TERRAIN_RELIEF_R7.glb"
	if not ResourceLoader.exists(relief_path): return
	var packed := load(relief_path) as PackedScene
	if packed == null: return
	var relief := packed.instantiate()
	_collect_kit_meshes(relief)
	relief.free()

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

func _terrain_cap_top_material(terrain: String, coord: Vector2i) -> StandardMaterial3D:
	# Imported cap meshes preserve their bevel and separate side surface, while
	# this small palette cache prevents every streamed forest hex from sharing one
	# chalky top colour.  Four stable, low-chroma families read as weathered land
	# rather than painted tabletop tokens.
	var phase: int = abs(coord.x * 7 + coord.y * 11) % 4
	var key := "%s_%d" % [terrain, phase]
	if terrain_cap_material_cache.has(key):
		return terrain_cap_material_cache[key]
	var colors: Array[Color] = [Color("263d22"), Color("314723"), Color("3c4f28"), Color("29412a")]
	match terrain:
		"ROAD": colors = [Color("62401f"), Color("704923"), Color("543a22"), Color("79522a")]
		"RUINS": colors = [Color("39424d"), Color("454c57"), Color("303c47"), Color("4d5360")]
	var material := _material(colors[phase])
	material.roughness = 0.88
	terrain_cap_material_cache[key] = material
	return material

func _create_tile(tile: Dictionary) -> void:
	var coord := Vector2i(int(tile.q), int(tile.r))
	var terrain_type := str(tile.terrain_type)
	# Water is represented by the continuous tide field and island coastline.
	# It stays fully present in Grid data for pathing/reveal, without rendering a
	# literal hex-board sea around the land.
	if terrain_type in ["SHALLOW_WATER", "DEEP_WATER"]:
		return
	var instance := MeshInstance3D.new()
	var surface_y := float(tile.elevation) * ELEVATION_STEP
	# Prefer the authored Blender low-poly kit. It carries bevelled edge normals,
	# layered terrain materials, and avoids the old uniform runtime cylinder slab
	# impression. The small procedural cap remains only as a safe import fallback.
	var kit_prefix := str({"FOREST": "HEX_FOREST_", "ROAD": "HEX_ROAD_", "RUINS": "HEX_RUIN_"}.get(terrain_type, "HEX_FOREST_"))
	var kit_info := _kit_component(kit_prefix)
	if not kit_info.is_empty() and kit_info.get("mesh") is Mesh:
		var kit_mesh: Mesh = kit_info.get("mesh")
		instance.mesh = kit_mesh
		instance.scale = kit_info.get("scale", Vector3.ONE)
		# The authored hex is now a thin readable surface accent, not the whole
		# landmass. Broad Blender relief carries the district silhouette below it;
		# this prevents the old black-walled column field while retaining precise
		# selectable hex locations for map input and accessibility.
		# Retain a substantial, dark-sided cap.  At the lower R7 scale a 2/3-height
		# terrace lost its vertical face at the gameplay camera distance.
		instance.scale.y *= 0.62
		instance.rotation = kit_info.get("rotation", Vector3.ZERO)
		# Blender add_hex exports material slot 0 as walkable top and slot 1 as its
		# separately-authored cliff wall. Do not flatten both with material_override:
		# only vary the top, retaining the darker height-reading side surface.
		instance.set_surface_override_material(0, _terrain_cap_top_material(terrain_type, coord))
		var kit_height := maxf(0.18, kit_mesh.get_aabb().size.y * instance.scale.y)
		instance.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y - kit_height * .5)
		instance.set_meta("blender_kit", true)
	else:
		var elevation := int(tile.elevation)
		var cap := CylinderMesh.new()
		cap.top_radius = TILE_SIZE * .96
		cap.bottom_radius = TILE_SIZE * (1.01 + minf(float(elevation), 3.0) * .025)
		cap.height = .10 + float(elevation) * .07
		cap.radial_segments = 6
		instance.mesh = cap
		instance.rotation_degrees.y = 30.0
		instance.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y - cap.height * .5)
		instance.set_meta("blender_kit", false)
	instance.set_meta("tile", tile)
	# The Blender-authored cap is the final local ground authority for streamed
	# macro districts. It is deliberately thin and bevelled—not the former tall
	# prototype prism—so it closes any continuous-surface seam while preserving
	# readable terrain, contact shadows and grounded pawns at every live hex.
	instance.visible = true
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
	# R7's old component clusters each carried their own hex-sized support
	# platform. They made even a connected world surface look like stacked game
	# pieces. Keep only sparse asymmetric rock outcrops; the broad shared terrain
	# mesh now owns every slope, terrace and cliff silhouette.
	var outcrop := elevated and not _has_node_at(coord) and (variant == 7 or (terrain == "RUINS" and variant == 5))
	if outcrop:
		var height_scale := 0.72 + float(int(tile.elevation)) * 0.10
		_spawn_kit_component("PROP_CLIFF_FACET_A", tile_position + Vector3(-0.42, 0.00, 0.12), height_scale, yaw)
		_spawn_kit_component("PROP_CLIFF_FACET_B", tile_position + Vector3(0.28, 0.02, -0.26), height_scale * .64, yaw + 0.8)
	var terrain_cluster := false
	if terrain == "FOREST" and not _has_node_at(coord):
		# Place silhouette props on selected seeded variants rather than every
		# forest hex.  The cleared gaps make the long route readable and avoid a
		# synthetic grid of identical tree crowns.  Coordinate-derived phase adds
		# five stable scale/lean families, so streaming never makes the forest pop
		# into a new layout while adjacent tiles still avoid clone-like silhouettes.
		if not terrain_cluster and variant in [0, 3, 5, 7]:
			var tree_phase: int = abs(coord.x * 17 + coord.y * 31 + variant * 13) % 5
			var prop_offset := Vector3(-0.37, 0.42, 0.26) if tree_phase % 2 == 0 else Vector3(0.38, 0.42, -0.30)
			var tree_prefix := "PROP_TREE_A" if tree_phase % 2 == 0 else "PROP_TREE_B"
			var tree_scale := 0.84 + float(tree_phase) * 0.12
			var tree_yaw := yaw + float(tree_phase - 2) * 0.13
			_spawn_kit_component(tree_prefix + "_TRUNK", tile_position + prop_offset, tree_scale, tree_yaw)
			_spawn_kit_component(tree_prefix + "_CROWN_0", tile_position + prop_offset + Vector3(0.0, 0.58, 0.0), tree_scale, tree_yaw)
			_spawn_kit_component(tree_prefix + "_CROWN_1", tile_position + prop_offset + Vector3(0.15, 0.70, -0.10), tree_scale, tree_yaw)
			_spawn_kit_component(tree_prefix + "_CROWN_2", tile_position + prop_offset + Vector3(-0.15, 0.75, 0.10), tree_scale, tree_yaw)
			if tree_phase >= 3:
				var companion_prefix := "PROP_TREE_B" if tree_prefix == "PROP_TREE_A" else "PROP_TREE_A"
				var companion_offset := Vector3(0.36, 0.42, -0.22) if tree_phase == 3 else Vector3(-0.17, 0.42, -0.42)
				var companion_scale := tree_scale * (0.52 if tree_phase == 3 else 0.64)
				_spawn_kit_component(companion_prefix + "_TRUNK", tile_position + companion_offset, companion_scale, tree_yaw + 0.58)
				_spawn_kit_component(companion_prefix + "_CROWN_0", tile_position + companion_offset + Vector3(0.0, 0.48, 0.0), companion_scale, tree_yaw + 0.58)
				_spawn_kit_component(companion_prefix + "_CROWN_1", tile_position + companion_offset + Vector3(0.12, 0.60, -0.08), companion_scale, tree_yaw + 0.58)
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
	button.custom_minimum_size = Vector2(92, 42)
	button.size = Vector2(92, 42)
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", Color("f4fffd"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("fff1ba"))
	button.add_theme_color_override("font_disabled_color", Color("c6d4dc"))
	button.add_theme_color_override("font_outline_color", Color("02080f"))
	button.add_theme_constant_override("outline_size", 6)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func(): _select_node(node))
	button.gui_input.connect(func(event: InputEvent): _on_node_button_input(event, node))
	overlay.add_child(button)
	node_buttons[str(node.node_id)] = button

func _on_node_button_input(event: InputEvent, node: Dictionary) -> void:
	if moving or turn_transitioning or map_simulation_paused:
		return
	var node_id := str(node.get("node_id", ""))
	var touch_tap_valid := true
	if event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			node_touch_pointer_id = node_id
			node_touch_origin = event.position
			node_touch_tap_valid = not event.canceled
			return
		touch_tap_valid = node_touch_tap_valid and node_touch_pointer_id == node_id and not event.canceled and event.position.distance_to(node_touch_origin) <= 24.0 * _portrait_ui_scale(_runtime_layout_size())
		node_touch_pointer_id = ""
		node_touch_tap_valid = false
	elif event is InputEventScreenDrag and event.index == 0:
		if node_touch_pointer_id == node_id and event.position.distance_to(node_touch_origin) > 24.0 * _portrait_ui_scale(_runtime_layout_size()):
			node_touch_tap_valid = false
		return
	var repeated_pointer_click := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var now_msec := Time.get_ticks_msec()
		repeated_pointer_click = node_id == last_node_pointer_id and now_msec - last_node_pointer_msec >= 0 and now_msec - last_node_pointer_msec <= DIRECT_DOUBLE_CLICK_WINDOW_MSEC
		if event.double_click or repeated_pointer_click:
			last_node_pointer_id = ""
			last_node_pointer_msec = -100000
		else:
			last_node_pointer_id = node_id
			last_node_pointer_msec = now_msec
	if direct_move_gesture_policy(event, repeated_pointer_click, touch_tap_valid):
		_select_node(node)
		_activate_selected_route_from_pointer()

func _create_node_marker(node: Dictionary) -> void:
	var marker_root := Node3D.new()
	marker_root.name = "EncounterMarker_%s" % str(node.node_id)
	var coord := Vector2i(int(node.q), int(node.r))
	marker_root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.18)
	# A thin locally-authored signal socket gives the encounter beacon and its
	# pawn a shared physical contact point. On the long streamed macro map this
	# is also a real low-profile clearing: it prevents a valid encounter from
	# ever reading as a sprite suspended over a seam between terrain districts.
	# It is not a stage-select card; the terrain material, shallow bevel, route
	# inlay, and local props keep it part of the world surface.
	var socket := MeshInstance3D.new()
	socket.name = "SignalSocketGround"
	var socket_mesh := CylinderMesh.new()
	socket_mesh.top_radius = 1.18
	socket_mesh.bottom_radius = 1.28
	socket_mesh.height = 0.085
	socket_mesh.radial_segments = 12
	socket.mesh = socket_mesh
	socket.position.y = -0.138
	socket.rotation_degrees.y = 15.0
	var socket_tile: Dictionary = grid.tile(coord)
	socket.material_override = _material(_terrain_surface_color(socket_tile).lightened(0.08))
	marker_root.add_child(socket)
	var hard_stage := str(node.get("stage_id", "")).contains("-H")
	var stage_id := str(node.get("stage_id", ""))
	var node_type := str(node.get("node_type", ""))
	var marker_prefix := "MARKER_NORMAL"
	if node_type == "START":
		marker_prefix = "MARKER_NORMAL"
	elif hard_stage:
		marker_prefix = "MARKER_HARD_GATE"
	elif node_type.contains("BOSS") or bool(DataRegistry.stage(stage_id).get("boss", false)):
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
	if stage_id.ends_with("N03") or stage_id.ends_with("N07") or stage_id.ends_with("N10") or stage_id.ends_with("N15") or stage_id.ends_with("N20"):
		_spawn_kit_components("PROP_SIGNAL_TOWER", Vector3(0.62, 0.06, -0.30), 0.76 if stage_id.ends_with("N03") else 1.0, 0.18, marker_root)
	elif stage_id.ends_with("H05") or stage_id.ends_with("H10"):
		_spawn_kit_components("PROP_SIGNAL_BEACON", Vector3(0.56, 0.05, -0.30), 0.92, -0.30, marker_root)
	if not hard_stage:
		_add_route_accent_light(marker_root, Vector3(0.0, 0.72, 0.0), 1.05 if stage_id.ends_with("N20") else 0.48)
	world_root.add_child(marker_root)
	node_markers[str(node.node_id)] = marker_root

func _node_overlay_anchor(node: Dictionary) -> Vector3:
	# Stage UI must follow the actual world marker that was instantiated for this
	# encounter, not a second copy of the axial/elevation formula.  The map is
	# rendered into a fixed SubViewport and its Control overlay is stretched by a
	# sibling container, so this preserves one real 3D anchor while the required
	# SubViewport-to-overlay scale conversion happens only at projection time.
	var marker: Node3D = node_markers.get(str(node.get("node_id", "")))
	if marker != null and is_instance_valid(marker):
		return marker.global_position + Vector3(0.0, 0.58, 0.0)
	var coord := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
	return HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.76)

func _overlay_position_from_world(world_position: Vector3) -> Vector2:
	# Camera3D returns pixels in its 1280×720 SubViewport. The sibling overlay
	# lives in the stretched parent map frame, so this single conversion is
	# necessary and must not be repeated by individual label call sites.
	if camera == null or viewport == null or overlay == null:
		return Vector2.ZERO
	var viewport_size := Vector2(viewport.size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector2.ZERO
	return camera.unproject_position(world_position) * (overlay.size / viewport_size)

func _overlay_anchor_is_visible(world_position: Vector3, control_size: Vector2) -> bool:
	# Camera3D.unproject_position() still yields a numeric coordinate for an
	# anchor behind the camera.  Treating that number as an on-screen label put
	# distant stage UI over the ocean while its actual 3D marker was outside the
	# view frustum.  The map never turns hidden/offscreen markers into floating
	# overlay targets: the actual 3D marker remains the source of truth and the
	# `next encounter` navigation action can deliberately focus it.
	if camera == null or overlay == null or camera.is_position_behind(world_position):
		return false
	var projected := _overlay_position_from_world(world_position)
	var padding := control_size * 0.68
	return Rect2(-padding, overlay.size + padding * 2.0).has_point(projected)

func _has_streamed_ground(coord: Vector2i) -> bool:
	var ground: MeshInstance3D = tile_meshes.get(HexCoordScript.key(coord))
	return ground != null and is_instance_valid(ground) and ground.visible

func _map_entity_is_locally_renderable(coord: Vector2i, camera_coord: Vector2i, radius: int) -> bool:
	return _has_streamed_ground(coord) and MapSimulationScript.should_render_pawn(coord, camera_coord, radius)

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

func _event_encounter_for_node(node_id: String) -> Dictionary:
	return MapExplorationServiceScript.event_encounter_for_node(definition, node_id)

func _map_idle_texture(enemy_id: String) -> Dictionary:
	var manifest_path := "res://assets/runtime_web/combat/%s/animation_manifest.json" % enemy_id
	if not FileAccess.file_exists(manifest_path): return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary: return {}
	var atlas_path := "res://assets/runtime_web/combat/%s/%s" % [enemy_id, str(parsed.get("atlas_path", "atlas.png"))]
	var atlas := _load_runtime_map_texture(atlas_path)
	if atlas == null: return {}
	var frame_size: Array = parsed.get("frame_size", [104, 104])
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	var animations: Dictionary = parsed.get("animations", {})
	var idle_animation: Dictionary = animations.get("idle", {})
	var idle_indices: Array = idle_animation.get("frame_indices", [])
	if idle_indices.is_empty(): idle_indices = [0]
	var first_frame := int(idle_indices[0])
	var columns := maxi(1, int(parsed.get("atlas_columns", 1)))
	texture.region = Rect2(float(first_frame % columns) * float(frame_size[0]), float(first_frame / columns) * float(frame_size[1]), float(frame_size[0]), float(frame_size[1]))
	var foot_anchor: Array = parsed.get("foot_anchor", [0.5, 0.88])
	return {
		# Preserve the immutable asset owner alongside the texture.  Event
		# companions must be auditable as their own CharacterDef SD pack, never
		# merely as a visually plausible generic map pawn.
		"source_id": enemy_id,
		"texture": texture,
		"frame_size": Vector2(float(frame_size[0]), float(frame_size[1])),
		"columns": columns,
		"animations": animations,
		"idle_frame_indices": idle_indices.slice(0, mini(8, idle_indices.size())),
		"idle_fps": float(idle_animation.get("fps", 12.0)),
		"foot_anchor": Vector2(float(foot_anchor[0]), float(foot_anchor[1])),
	}

static func _sprite_center_y_for_foot(contact_y: float, parent_base_y: float, frame_height: float, pixel_size: float, foot_anchor_y: float) -> float:
	# Sprite3D is centred on its frame. Reconstruct the centre from the authored
	# normalized foot anchor so every frame keeps the same physical contact point.
	return contact_y - parent_base_y + (foot_anchor_y - 0.5) * frame_height * pixel_size

static func _animation_indices(pack: Dictionary, animation_name: String) -> Array:
	var animation: Dictionary = pack.get("animations", {}).get(animation_name, {})
	var indices: Array = animation.get("frame_indices", [])
	if indices.is_empty():
		indices = pack.get("idle_frame_indices", [0])
	return indices

static func _animation_fps(pack: Dictionary, animation_name: String) -> float:
	var animation: Dictionary = pack.get("animations", {}).get(animation_name, {})
	return maxf(1.0, float(animation.get("fps", pack.get("idle_fps", 12.0))))

static func _animation_frame(pack: Dictionary, animation_name: String, elapsed_msec: int) -> int:
	var indices := _animation_indices(pack, animation_name)
	var frame_cursor := int(floor(float(elapsed_msec) * _animation_fps(pack, animation_name) / 1000.0)) % maxi(1, indices.size())
	return int(indices[frame_cursor])

func _load_runtime_map_texture(path: String) -> Texture2D:
	## Runtime map pawns share the exact packaged combat art. A raw-PNG load
	## keeps a newly synced map pawn visible until the editor cache catches up.
	if ResourceLoader.exists(path):
		var imported = load(path)
		if imported is Texture2D: return imported
	var image := Image.load_from_file(path)
	if image == null or image.is_empty(): return null
	return ImageTexture.create_from_image(image)

func _create_enemy_pawn(node: Dictionary) -> void:
	var node_id := str(node.get("node_id", ""))
	var special_event := _event_encounter_for_node(node_id)
	var enemy := _enemy_for_node(node)
	# A SPECIAL_ENEMY contact is authored around one identifiable monster.  The
	# map pawn must therefore use that event identity instead of the stage wave's
	# first generic enemy; otherwise the ! dialogue names one creature while the
	# world visibly presents another.
	if str(special_event.get("event_kind", "")) == "SPECIAL_ENEMY":
		var event_enemy := DataRegistry.enemy(str(special_event.get("enemy_id", "")))
		if not event_enemy.is_empty(): enemy = event_enemy
	if enemy.is_empty(): return
	var companion_ids: Array[String] = []
	if not special_event.is_empty():
		for recruitment_value in MapExplorationServiceScript.recruitment_specs(special_event):
			companion_ids.append(str(recruitment_value.get("character_id", "")))
	var companion: Dictionary = DataRegistry.character(companion_ids[0]) if not companion_ids.is_empty() else {}
	var is_event_contact := not special_event.is_empty()
	var is_companion_event := not companion.is_empty()
	var is_companion_duo := companion_ids.size() == 2
	var root := Node3D.new()
	root.name = ("CompanionEventMapPawn_" if is_companion_event else "EnemyMapPawn_") + node_id
	# Static encounters do not have patrol state.  Asking MapSimulation for all
	# enemies silently returned its default (0, 0), which could place a valid
	# stage pawn over open water.  Use the authored node coordinate unless this
	# encounter explicitly owns a live patrol route.
	var coord := _encounter_coord(node)
	root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.18)
	var rank := "EVENT" if is_companion_event else str(enemy.get("rank", "NORMAL"))
	var scale_factor := 1.12 if is_companion_event else (1.0 if rank == "NORMAL" else (1.28 if rank == "ELITE" else 1.72))
	# Hostile pawns can travel along a patrol route whose logical coordinate is
	# valid but lies at the seam between two streamed macro districts.  Give
	# every hostile the same physical terrain socket used by the squad and the
	# encounter marker.  It follows the real pawn transform, so it cannot drift
	# from the patrol simulation or become a screen-only placement workaround.
	var grounding_patch := MeshInstance3D.new()
	grounding_patch.name = "EnemyGroundingTerrace"
	var grounding_mesh := CylinderMesh.new()
	grounding_mesh.top_radius = 1.08 * scale_factor
	grounding_mesh.bottom_radius = 1.20 * scale_factor
	grounding_mesh.height = 0.078
	grounding_mesh.radial_segments = 12
	grounding_patch.mesh = grounding_mesh
	grounding_patch.position.y = -0.108
	grounding_patch.rotation_degrees.y = 15.0
	var enemy_tile: Dictionary = grid.tile(coord)
	grounding_patch.material_override = _material(_terrain_surface_color(enemy_tile).lightened(0.035))
	root.add_child(grounding_patch)
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
	var threat_color := Color("7ee7d5") if is_companion_event else (Color("ff8d70") if is_event_contact else (Color("d85d67") if rank == "NORMAL" else (Color("ef9a47") if rank == "ELITE" else Color("dc5dcc"))))
	danger_ring.material_override = _material(threat_color, threat_color.darkened(0.1))
	danger_ring.position.y = 0.06
	root.add_child(danger_ring)
	var sprite := Sprite3D.new()
	sprite.name = "EnemyIdleSprite"
	var pack := _map_idle_texture(str(companion.get("id", enemy.get("id", ""))))
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
	# A hostile is a physical world pawn, not a HUD marker.  It must participate
	# in the same depth pass as its terrain socket, shadow, ring and road; a
	# no-depth sprite could remain visible after the true root had disappeared
	# behind the ocean or a bad terrain seam.
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.no_depth_test = false
	var enemy_frame_size: Vector2 = pack.get("frame_size", Vector2(104.0, 104.0))
	var enemy_anchor: Vector2 = pack.get("foot_anchor", Vector2(0.5, 0.88))
	var sprite_world_height := enemy_frame_size.y * sprite.pixel_size
	sprite.position.y = _sprite_center_y_for_foot(0.08, 0.0, enemy_frame_size.y, sprite.pixel_size, enemy_anchor.y)
	if is_companion_duo:
		sprite.position.x = -0.34
	sprite.render_priority = 12
	root.add_child(sprite)
	_add_occlusion_silhouette(sprite, root, "EnemyOcclusionSilhouette", Color("ff746e") if not is_companion_event else Color("75f3dc"))
	if is_companion_duo:
		# A duo remains one map contact and one battle transaction, but both
		# recruitable people must be visibly represented by their own SD art.
		# Keep the primary animation registry stable for patrol processing and
		# animate the second companion from its own immutable combat pack below.
		var second_sprite := Sprite3D.new()
		second_sprite.name = "CompanionEventSecondaryIdleSprite"
		var second_pack := _map_idle_texture(companion_ids[1])
		if not second_pack.is_empty():
			second_sprite.texture = second_pack.texture
			second_sprite.set_meta("animation_pack", second_pack)
			second_sprite.set_meta("animation_phase_msec", 190)
		second_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		second_sprite.pixel_size = sprite.pixel_size
		second_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		second_sprite.no_depth_test = false
		var second_frame_size: Vector2 = second_pack.get("frame_size", enemy_frame_size)
		var second_anchor: Vector2 = second_pack.get("foot_anchor", enemy_anchor)
		second_sprite.position = Vector3(0.34, _sprite_center_y_for_foot(0.08, 0.0, second_frame_size.y, second_sprite.pixel_size, second_anchor.y), 0.0)
		second_sprite.render_priority = 12
		root.add_child(second_sprite)
		_add_occlusion_silhouette(second_sprite, root, "CompanionSecondaryOcclusionSilhouette", Color("75f3dc"))
	var threat := Label3D.new()
	threat.text = "!" if is_event_contact else ("위협" if rank == "NORMAL" else ("정예" if rank == "ELITE" else "보스"))
	threat.font_size = 56 if is_event_contact else (46 if rank == "BOSS" else 38)
	threat.outline_size = 8
	threat.modulate = threat_color.lightened(0.16)
	threat.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	threat.no_depth_test = true
	threat.position.y = sprite.position.y + sprite_world_height * 0.48 + 0.10
	root.add_child(threat)
	var awareness := Label3D.new()
	awareness.name = "AwarenessCue"
	awareness.text = ""
	awareness.font_size = 50
	awareness.outline_size = 9
	awareness.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	awareness.no_depth_test = true
	awareness.position.y = threat.position.y + 0.40
	root.add_child(awareness)
	root.set_meta("threat_ring", danger_ring)
	root.set_meta("awareness_label", awareness)
	root.set_meta("node_id", node_id)
	root.set_meta("companion_event", is_companion_event)
	root.set_meta("event_contact", is_event_contact)
	if is_event_contact:
		root.set_meta("event_marker", threat)
		root.set_meta("event_marker_base_y", threat.position.y)
		root.set_meta("event_marker_phase", float(node_id.hash() % 19) * 0.31)
	if is_companion_event:
		root.set_meta("event_companion_ids", companion_ids)
		# Event contacts deliberately use the companion's own SD art, not an
		# enemy fallback.  Keep the authored ! above the pawn on a small diegetic
		# pulse so it survives dense terrain and remains legible at map scale.
	world_root.add_child(root)
	enemy_pawns[node_id] = root

func _create_treasure_visual(treasure: Dictionary) -> void:
	var treasure_id := str(treasure.get("treasure_id", ""))
	if treasure_id.is_empty(): return
	var root := Node3D.new()
	root.name = "Treasure_%s" % treasure_id
	var coord := Vector2i(int(treasure.get("q", 0)), int(treasure.get("r", 0)))
	root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.16)
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

func _create_relay_visual(relay: Dictionary) -> void:
	var relay_id := str(relay.get("relay_id", ""))
	if relay_id.is_empty(): return
	var root := Node3D.new()
	root.name = "MapRelay_%s" % relay_id
	var coord := Vector2i(int(relay.get("q", 0)), int(relay.get("r", 0)))
	root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.18)
	var parts := _spawn_kit_components("PROP_SIGNAL_TOWER", Vector3.ZERO, 0.78, 0.0, root)
	if parts.is_empty():
		var mast := MeshInstance3D.new()
		var mast_mesh := CylinderMesh.new()
		mast_mesh.top_radius = 0.12
		mast_mesh.bottom_radius = 0.22
		mast_mesh.height = 1.25
		mast_mesh.radial_segments = 6
		mast.mesh = mast_mesh
		mast.position.y = 0.62
		mast.material_override = _material(Color("1e5361"), Color("15535c"))
		root.add_child(mast)
	var signal_ring := MeshInstance3D.new()
	var signal_mesh := TorusMesh.new()
	signal_mesh.inner_radius = 0.26
	signal_mesh.outer_radius = 0.34
	signal_mesh.rings = 8
	signal_mesh.ring_segments = 16
	signal_ring.mesh = signal_mesh
	signal_ring.position.y = 1.10
	signal_ring.material_override = _material(Color("5b8090"), Color("224552"))
	root.add_child(signal_ring)
	var label := Label3D.new()
	label.text = "릴레이"
	label.font_size = 34
	label.outline_size = 7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 1.48
	label.modulate = Color("a7d4de")
	root.add_child(label)
	root.set_meta("signal", signal_ring)
	root.set_meta("label", label)
	world_root.add_child(root)
	relay_visuals[relay_id] = root

func _create_event_visual(event: Dictionary) -> void:
	var event_id := str(event.get("event_id", ""))
	if event_id.is_empty(): return
	var root := Node3D.new()
	root.name = "MapEvent_%s" % event_id
	var coord := Vector2i(int(event.get("q", 0)), int(event.get("r", 0)))
	root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.16)
	_spawn_kit_component("PROP_CRYSTAL_SHARD_1", Vector3(0.0, 0.06, 0.0), 0.95, 0.0, root)
	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.11
	beacon_mesh.height = 0.22
	beacon.mesh = beacon_mesh
	beacon.position.y = 0.62
	beacon.material_override = _material(Color("78d9d0"), Color("6effd5"))
	root.add_child(beacon)
	root.set_meta("beacon", beacon)
	world_root.add_child(root)
	event_visuals[event_id] = root

func _create_landmark_visual(landmark: Dictionary) -> void:
	var landmark_id := str(landmark.get("landmark_id", ""))
	if landmark_id.is_empty(): return
	var root := Node3D.new()
	root.name = "Landmark_%s" % landmark_id
	var coord := Vector2i(int(landmark.get("q", 0)), int(landmark.get("r", 0)))
	root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.16)
	var is_major := str(landmark.get("kind", "MINOR")) == "MAJOR"
	_spawn_kit_components(str(landmark.get("prop", "PROP_CRYSTAL_SHARD_1")), Vector3.ZERO, 1.05 if is_major else 0.70, 0.0, root)
	if is_major:
		var label := Label3D.new()
		label.text = str(landmark.get("name", "지형 표식"))
		label.font_size = 32
		label.outline_size = 7
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position.y = 1.35
		label.modulate = Color("c9e9e4")
		root.add_child(label)
	world_root.add_child(root)
	landmark_visuals[landmark_id] = root

func _node_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.68)
	style.shadow_size = 7
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	return style

func _create_pawn() -> void:
	pawn = Node3D.new()
	pawn.name = "SquadPawn"
	pawn.position = _pawn_world_position()
	world_root.add_child(pawn)
	# This shared, shallow squad clearing follows the logical pawn one hex at a
	# time. It provides a visible physical ground socket at the map's streaming
	# boundary rather than allowing a valid save coordinate to look like it is
	# floating over the ocean while its surrounding terrain chunk wakes up.
	var grounding_patch := MeshInstance3D.new()
	grounding_patch.name = "SquadGroundingTerrace"
	var grounding_mesh := CylinderMesh.new()
	grounding_mesh.top_radius = 1.10
	grounding_mesh.bottom_radius = 1.20
	grounding_mesh.height = 0.075
	grounding_mesh.radial_segments = 12
	grounding_patch.mesh = grounding_mesh
	grounding_patch.position.y = -0.104
	grounding_patch.rotation_degrees.y = 15.0
	var party_coord := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	var party_tile: Dictionary = grid.tile(party_coord)
	grounding_patch.material_override = _material(_terrain_surface_color(party_tile).lightened(0.05))
	pawn.add_child(grounding_patch)
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
	# The map pawn is its own small SD token, not a large profile-card cutout.
	# Keep the same combat-atlas rendering contract as hostile pawns so both
	# sides share a coherent map scale, shadow, and light direction.
	pawn_visual.position.y = 0.18
	pawn.add_child(pawn_visual)
	_spawn_kit_components("SQUAD_STANDARD", Vector3(0.0, 0.02, 0.0), 1.48, 0.0, pawn_visual)
	var lead_id := str(AppState.get_party()[0])
	pawn_animation_pack = _map_idle_texture(lead_id)
	if not pawn_animation_pack.is_empty():
		pawn_sprite = Sprite3D.new()
		pawn_sprite.name = "SquadIdleSprite"
		pawn_sprite.texture = pawn_animation_pack.texture
		pawn_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		pawn_sprite.pixel_size = 0.0152
		# Keep the squad in the production world depth pass for the same reason as
		# hostile pawns: a map pawn cannot claim grounded placement while bypassing
		# the terrain, water and encounter-socket depth relationships.
		pawn_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		pawn_sprite.no_depth_test = false
		var leader_frame_size: Vector2 = pawn_animation_pack.get("frame_size", Vector2(104.0, 104.0))
		var leader_anchor: Vector2 = pawn_animation_pack.get("foot_anchor", Vector2(0.5, 0.88))
		pawn_sprite.position.y = _sprite_center_y_for_foot(0.15, PAWN_VISUAL_BASE_Y, leader_frame_size.y, pawn_sprite.pixel_size, leader_anchor.y)
		pawn_sprite.render_priority = 10
		pawn_visual.add_child(pawn_sprite)
		pawn_occlusion_silhouette = _add_occlusion_silhouette(pawn_sprite, pawn_visual, "SquadOcclusionSilhouette", Color("69f4e2"))
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
	pawn_banner.position = Vector3(0.0, 1.05, 0.0)
	pawn_visual.add_child(pawn_banner)
	pawn_last_position = pawn.position

func _pawn_world_position() -> Vector3:
	var coord := Vector2i(int(map_state.current_q), int(map_state.current_r))
	return HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.14)

func _movement_overlay_material(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.render_priority = 1
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.0
	return material

func _movement_hex_corners(coord: Vector2i, surface_y: float) -> Array[Vector3]:
	var center := HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y)
	var corners: Array[Vector3] = []
	var radius := TILE_SIZE * 0.92
	for index in range(6):
		var angle := deg_to_rad(30.0 + float(index) * 60.0)
		corners.append(center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	return corners

static func _movement_boundary_corner_indices(direction_index: int) -> Vector2i:
	return Vector2i(posmod(5 - direction_index, 6), posmod(6 - direction_index, 6))

func _unresolved_encounter_stop_hexes() -> Dictionary:
	var stop_hexes: Dictionary = {}
	for node_value in definition.get("nodes", []):
		var node: Dictionary = node_value
		var stage_id := str(node.get("stage_id", ""))
		var node_id := str(node.get("node_id", ""))
		if stage_id.is_empty() or MapExplorationServiceScript.encounter_cleared(map_state, node_id) or int(AppState.profile.stage_stars.get(stage_id, 0)) > 0:
			continue
		stop_hexes[HexCoordScript.key(_encounter_coord(node))] = true
	return stop_hexes

func _movement_range_allowlist() -> Dictionary:
	# A revealed treasure explicitly authorizes its short exploratory detour;
	# mirror that existing path rule so the yellow range never understates where
	# the confirmed treasure route can actually travel.
	return {} if not selected_treasure.is_empty() else _path_reveal_allowlist()

func _append_range_triangle(vertices: Array[Vector3], a: Vector3, b: Vector3, c: Vector3) -> void:
	# ImmediateMesh reports an engine error when surface_end closes a surface that
	# received no vertices. Keep zero-area geometry out as well: a collapsed edge
	# should behave like no highlight, not create an invalid GPU triangle.
	if (b - a).cross(c - a).length_squared() <= 0.00000001:
		return
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)

func _movement_triangle_mesh(vertices: Array[Vector3], material: Material) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	if vertices.size() < 3:
		return mesh
	var valid_vertices: Array[Vector3] = []
	for index in range(0, vertices.size() - 2, 3):
		var a := vertices[index]
		var b := vertices[index + 1]
		var c := vertices[index + 2]
		if (b - a).cross(c - a).length_squared() <= 0.00000001:
			continue
		valid_vertices.append(a)
		valid_vertices.append(b)
		valid_vertices.append(c)
	if valid_vertices.is_empty():
		return mesh
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for vertex in valid_vertices:
		mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	return mesh

func _append_range_edge_ribbon(vertices: Array[Vector3], from: Vector3, to: Vector3, half_width: float) -> void:
	if half_width <= 0.0 or from.distance_squared_to(to) <= 0.00000001:
		return
	var tangent := (to - from).normalized()
	var side := Vector3(-tangent.z, 0.0, tangent.x) * half_width
	var a := from - side
	var b := from + side
	var c := to + side
	var d := to - side
	_append_range_triangle(vertices, a, b, c)
	_append_range_triangle(vertices, a, c, d)

func _clear_movement_range_overlay() -> void:
	movement_range_reachable.clear()
	movement_range_fill.mesh = null
	movement_range_grid.mesh = null
	movement_range_boundary.mesh = null

func _update_movement_range_overlay() -> void:
	if movement_range_fill == null or movement_range_grid == null or movement_range_boundary == null:
		return
	var movement_points := MapExplorationServiceScript.movement_remaining(map_state, definition)
	if moving or turn_transitioning or movement_points <= 0:
		_clear_movement_range_overlay()
		return
	var current := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	movement_range_reachable = HexPathfinderScript.reachable_within(grid, current, movement_points, _movement_range_allowlist(), _unresolved_encounter_stop_hexes())
	var reachable_keys: Array = movement_range_reachable.keys()
	reachable_keys.sort()
	if reachable_keys.is_empty():
		_clear_movement_range_overlay()
		return
	var fill_vertices: Array[Vector3] = []
	for key_value in reachable_keys:
		var coord := HexCoordScript.from_key(str(key_value))
		var surface_y := float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.105
		var center := HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y)
		var corners := _movement_hex_corners(coord, surface_y)
		for corner_index in range(6):
			# Match the Compatibility renderer's clockwise top-face authority.
			_append_range_triangle(fill_vertices, center, corners[corner_index], corners[(corner_index + 1) % 6])
	var fill_mesh := _movement_triangle_mesh(fill_vertices, _movement_overlay_material(Color("f6b93f68"), Color("9a5f12")))
	movement_range_fill.mesh = fill_mesh if fill_mesh.get_surface_count() > 0 else null
	# Every reachable cell keeps a subtle translucent seam. Shared edges are
	# emitted once so adjacent highlights remain individually countable without
	# becoming brighter than the rest of the grid.
	var cell_grid_vertices: Array[Vector3] = []
	var emitted_edges: Dictionary = {}
	for key_value in reachable_keys:
		var coord := HexCoordScript.from_key(str(key_value))
		var surface_y := float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.125
		var corners := _movement_hex_corners(coord, surface_y)
		for direction_index in range(HexCoordScript.DIRECTIONS.size()):
			var neighbour := coord + HexCoordScript.DIRECTIONS[direction_index]
			var neighbour_key := HexCoordScript.key(neighbour)
			var edge_parts := [str(key_value), neighbour_key]
			edge_parts.sort()
			var edge_key := "%s|%s" % [edge_parts[0], edge_parts[1]]
			if emitted_edges.has(edge_key):
				continue
			emitted_edges[edge_key] = true
			var edge_indices := _movement_boundary_corner_indices(direction_index)
			_append_range_edge_ribbon(cell_grid_vertices, corners[edge_indices.x], corners[edge_indices.y], 0.030)
	var cell_grid_mesh := _movement_triangle_mesh(cell_grid_vertices, _movement_overlay_material(Color("ffd36ba8"), Color("b57618")))
	movement_range_grid.mesh = cell_grid_mesh if cell_grid_mesh.get_surface_count() > 0 else null
	var boundary_vertices: Array[Vector3] = []
	for key_value in reachable_keys:
		var coord := HexCoordScript.from_key(str(key_value))
		var surface_y := float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.135
		var corners := _movement_hex_corners(coord, surface_y)
		for direction_index in range(HexCoordScript.DIRECTIONS.size()):
			var neighbour := coord + HexCoordScript.DIRECTIONS[direction_index]
			if movement_range_reachable.has(HexCoordScript.key(neighbour)):
				continue
			# DIRECTIONS rotate clockwise in axial/world space while corner indices
			# rotate counter-clockwise. Map each outward direction to its actual edge.
			var edge_indices := _movement_boundary_corner_indices(direction_index)
			var from: Vector3 = corners[edge_indices.x]
			var to: Vector3 = corners[edge_indices.y]
			_append_range_edge_ribbon(boundary_vertices, from, to, 0.070)
	var boundary_mesh := _movement_triangle_mesh(boundary_vertices, _movement_overlay_material(Color("fff0a6f5"), Color("ffb52b")))
	movement_range_boundary.mesh = boundary_mesh if boundary_mesh.get_surface_count() > 0 else null

func _update_route_mesh() -> void:
	for segment in route_segments: segment.queue_free()
	for node in route_nodes: node.queue_free()
	route_segments.clear()
	route_nodes.clear()
	selected_ring.visible = false
	var immediate := ImmediateMesh.new()
	var route_color := Color("4fd3c2") if preview_risk == "SAFE" else (Color("e7bd63") if preview_risk == "WATCHED" else Color("e87972"))
	var movement_points := MapExplorationServiceScript.movement_remaining(map_state, definition)
	var route_exceeds_pulse := preview_path.size() - 1 > movement_points
	if preview_path.size() >= 2:
		var guide_color := Color("657989") if route_exceeds_pulse else route_color.lightened(0.18)
		immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _material(guide_color, guide_color.darkened(0.18)))
		for coord in preview_path:
			immediate.surface_add_vertex(HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.54))
		immediate.surface_end()
		for index in range(preview_path.size() - 1):
			var segment_color := route_color if index < movement_points else Color("516471")
			var from := HexCoordScript.axial_to_world(preview_path[index], TILE_SIZE, float(grid.tile(preview_path[index]).get("elevation", 0)) * ELEVATION_STEP + 0.57)
			var to := HexCoordScript.axial_to_world(preview_path[index + 1], TILE_SIZE, float(grid.tile(preview_path[index + 1]).get("elevation", 0)) * ELEVATION_STEP + 0.57)
			var ribbon := MeshInstance3D.new()
			var ribbon_mesh := BoxMesh.new()
			ribbon_mesh.size = Vector3(0.18, 0.045, from.distance_to(to))
			ribbon.mesh = ribbon_mesh
			ribbon.material_override = _material(segment_color, segment_color.darkened(0.05))
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
			pulse.material_override = _material(Color("f5bc62") if index < movement_points else Color("667580"), Color("f3a83e") if index < movement_points else Color("34424c"))
			pulse.position = to + Vector3(0.0, 0.035, 0.0)
			world_root.add_child(pulse)
			route_nodes.append(pulse)
	var selected_target: Dictionary = selected_node if not selected_node.is_empty() else (selected_treasure if not selected_treasure.is_empty() else (selected_relay if not selected_relay.is_empty() else selected_event))
	if not selected_target.is_empty():
		var selected_coord := Vector2i(int(selected_target.get("q", 0)), int(selected_target.get("r", 0)))
		selected_ring.position = HexCoordScript.axial_to_world(selected_coord, TILE_SIZE, float(grid.tile(selected_coord).get("elevation", 0)) * ELEVATION_STEP + 0.18)
		selected_ring.visible = true
	route_mesh.mesh = immediate
	_update_movement_range_overlay()

func _refresh_state_visuals() -> void:
	if definition.is_empty(): return
	AppState.refresh_chapter_map_reveal(map_id)
	var revealed := _path_reveal_allowlist()
	_update_movement_range_overlay()
	for key in tile_meshes:
		var instance: MeshInstance3D = tile_meshes[key]
		var tile: Dictionary = instance.get_meta("tile")
		# Keep the thin authored terrain cap visible. It is the streamed local
		# surface that guarantees an actual renderable ground under map pawns when
		# the broad continuous landscape crosses a long-map district boundary.
		instance.visible = true
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
		var special_event := _event_encounter_for_node(str(node.get("node_id", "")))
		var marker := "◆" if stage_id == "" else ("★" if stars == 3 else ("✓" if stars > 0 else ("!" if not special_event.is_empty() and unlocked else ("◇" if unlocked else "🔒"))))
		var display_label := stage_display_text(stage_id, true, SettingsService.is_developer_mode()) if stage_id != "" else "탐색 거점"
		button.text = "%s %s" % [marker, display_label]
		button.tooltip_text = stage_display_text(stage_id, false, SettingsService.is_developer_mode()) if stage_id != "" else "릴레이 캠프"
		var fill := Color("081b2a") if not unlocked else Color("0b3040")
		var border := Color("71889a") if not unlocked else Color("80f3dc")
		if stars > 0:
			fill = Color("123b39")
			border = Color("ffd477")
		if stage_id == "":
			fill = Color("10364a")
			border = Color("ffd477")
		button.add_theme_stylebox_override("normal", _node_style(fill, border))
		button.add_theme_stylebox_override("hover", _node_style(fill.lightened(0.16), Color("fff1b5")))
		button.add_theme_stylebox_override("pressed", _node_style(fill.darkened(0.12), Color("ffffff")))
		button.disabled = moving or turn_transitioning or map_simulation_paused
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
			var encounter_coord := _encounter_coord(node)
			var camera_coord := HexCoordScript.world_to_axial(camera_target, TILE_SIZE)
			enemy_root.visible = button.visible and not cleared and unlocked and _map_entity_is_locally_renderable(encounter_coord, camera_coord, STREAM_RADIUS + 2)
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
	for relay in definition.get("relays", []):
		var relay_id := str(relay.get("relay_id", ""))
		var relay_root: Node3D = relay_visuals.get(relay_id)
		if relay_root == null: continue
		var relay_key := "%d,%d" % [int(relay.get("q", 0)), int(relay.get("r", 0))]
		var relay_active := MapExplorationServiceScript.relay_state(map_state, relay_id) == "ACTIVE"
		relay_root.visible = relay_active or revealed.has(relay_key)
		var relay_signal = relay_root.get_meta("signal", null)
		if relay_signal is MeshInstance3D:
			(relay_signal as MeshInstance3D).material_override = _material(Color("71f7d3") if relay_active else Color("4c6876"), Color("48f4d1") if relay_active else Color("183744"))
		var relay_label = relay_root.get_meta("label", null)
		if relay_label is Label3D:
			(relay_label as Label3D).text = "활성 릴레이" if relay_active else "고장 난 릴레이"
	for event in definition.get("map_events", []):
		var event_id := str(event.get("event_id", ""))
		var event_root: Node3D = event_visuals.get(event_id)
		if event_root == null: continue
		var event_status := MapExplorationServiceScript.event_state(map_state, event_id)
		event_root.visible = event_status == "DISCOVERED"
	for node_id in enemy_pawns:
		_update_enemy_pawn_from_simulation(str(node_id))
	var completion := MapExplorationServiceScript.completion(map_state, definition)
	if Time.get_ticks_msec() >= map_notice_until_msec:
		var status_runtime_size := _runtime_layout_size()
		var compact_status := status_runtime_size.y > status_runtime_size.x or status_runtime_size.x <= 980.0
		var status_template := "제1장 · %s · 이동 %d/%d · 탐험 %d%%" if compact_status else "제1장  ·  꺼진 노선의 신호  ·  %s  ·  이동 %d/%d  ·  탐험 %d%%"
		var status_mode := ("위험" if hard_overlay else "일반") if compact_status else ("위험 작전" if hard_overlay else "일반 작전")
		status_label.text = status_template % [status_mode, int(map_state.get("movement_points", 0)), int(map_state.get("movement_points_max", 0)), int(completion.get("percent", 0))]
	if wait_button != null: wait_button.disabled = moving or turn_transitioning or map_simulation_paused
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
	next_encounter_button.disabled = moving or turn_transitioning or next_node.is_empty()
	if next_node.is_empty(): return
	var stage_id := str(next_node.get("stage_id", ""))
	next_encounter_button.text = "다음 조우  ·  %s" % stage_display_text(stage_id, true, SettingsService.is_developer_mode())

func _select_next_encounter() -> void:
	var next_node := _next_encounter_node()
	if next_node.is_empty(): return
	_select_node(next_node)

func _select_node(node: Dictionary) -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	selected_treasure = {}
	selected_relay = {}
	selected_event = {}
	selected_node = node
	live_encounter_replans = 0
	AppState.selected_map_node_id = str(node.node_id)
	map_state.last_selected_node = str(node.node_id)
	var allowed := _path_reveal_allowlist()
	preview_path = HexPathfinderScript.find_path(grid, Vector2i(int(map_state.current_q), int(map_state.current_r)), _encounter_coord(node), allowed)
	preview_path = _truncate_at_first_unresolved_encounter(preview_path)
	if not preview_path.is_empty() and preview_path[-1] != _encounter_coord(node):
		selected_node = _node_at_coord(preview_path[-1])
		AppState.selected_map_node_id = str(selected_node.get("node_id", ""))
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, preview_path)
	_update_route_mesh()
	# Frame both the squad and the hostile pawn while retaining enough route
	# context to make movement legible.  This keeps a selected N01 from being
	# clipped behind the panel on a wide Chapter 1 map.
	_focus_preview_route()
	_update_panel()
	if _first_map_tutorial_active() and tutorial_step > 0:
		_set_tutorial_step(2)

func _select_treasure(treasure: Dictionary) -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	var treasure_id := str(treasure.get("treasure_id", ""))
	# A hint is an environmental observation, not a navigable treasure marker.
	# The player may discover it while traversing the map; only REVEALED opens
	# an exact collection route and the reward panel.
	if MapExplorationServiceScript.treasure_state(map_state, treasure_id) != "REVEALED":
		return
	selected_node = {}
	selected_relay = {}
	selected_event = {}
	selected_treasure = treasure
	# Treasure selection is the explicit opt-in for a short exploratory detour.
	# Do not restrict this route to currently revealed tiles: otherwise a hinted
	# side branch can be visible but unreachable. Unresolved encounters still
	# cut the route below, so this never lets a treasure selection bypass battle.
	preview_path = HexPathfinderScript.find_path(grid, Vector2i(int(map_state.current_q), int(map_state.current_r)), Vector2i(int(treasure.q), int(treasure.r)))
	preview_path = _truncate_at_first_unresolved_encounter(preview_path)
	_retarget_truncated_path_to_encounter(Vector2i(int(treasure.q), int(treasure.r)))
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, preview_path)
	_update_route_mesh()
	_focus_preview_route()
	_update_panel()

func _select_relay(relay: Dictionary) -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	selected_node = {}
	selected_treasure = {}
	selected_event = {}
	selected_relay = relay
	var relay_coord := Vector2i(int(relay.get("q", 0)), int(relay.get("r", 0)))
	preview_path = HexPathfinderScript.find_path(grid, Vector2i(int(map_state.current_q), int(map_state.current_r)), relay_coord)
	preview_path = _truncate_at_first_unresolved_encounter(preview_path)
	_retarget_truncated_path_to_encounter(relay_coord)
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, preview_path)
	_update_route_mesh()
	_focus_preview_route()
	_update_panel()

func _select_event(event: Dictionary) -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	selected_node = {}
	selected_treasure = {}
	selected_relay = {}
	selected_event = event
	var event_coord := Vector2i(int(event.get("q", 0)), int(event.get("r", 0)))
	preview_path = HexPathfinderScript.find_path(grid, Vector2i(int(map_state.current_q), int(map_state.current_r)), event_coord)
	preview_path = _truncate_at_first_unresolved_encounter(preview_path)
	_retarget_truncated_path_to_encounter(event_coord)
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, preview_path)
	_update_route_mesh()
	_focus_preview_route()
	_update_panel()

func _focus_preview_route() -> void:
	if preview_path.size() <= 1:
		_focus_current(false)
		return
	var pulse_path := _path_for_current_pulse(preview_path)
	var focus_path := pulse_path if pulse_path.size() > 1 else preview_path
	var midpoint_index := clampi(int(round(float(focus_path.size() - 1) * 0.62)), 1, focus_path.size() - 1)
	_focus_coord(focus_path[midpoint_index], false)

func _truncate_at_first_unresolved_encounter(path: Array[Vector2i]) -> Array[Vector2i]:
	if path.size() <= 1: return path
	for index in range(1, path.size()):
		var coord := path[index]
		for node in definition.get("nodes", []):
			if str(node.get("stage_id", "")).is_empty(): continue
			if _encounter_coord(node) != coord: continue
			if not MapExplorationServiceScript.encounter_cleared(map_state, str(node.get("node_id", ""))) and int(AppState.profile.stage_stars.get(str(node.get("stage_id", "")), 0)) <= 0:
				return path.slice(0, index + 1)
	return path

func _node_at_coord(coord: Vector2i) -> Dictionary:
	for node in definition.get("nodes", []):
		var node_coord := _encounter_coord(node)
		if node_coord == coord:
			return node
	return {}

func _retarget_truncated_path_to_encounter(requested_target: Vector2i) -> bool:
	if preview_path.is_empty() or preview_path[-1] == requested_target:
		return false
	var blocking_node := _node_at_coord(preview_path[-1])
	if blocking_node.is_empty():
		return false
	selected_treasure = {}
	selected_relay = {}
	selected_event = {}
	selected_node = blocking_node
	AppState.selected_map_node_id = str(blocking_node.get("node_id", ""))
	map_state.last_selected_node = str(blocking_node.get("node_id", ""))
	return true

func _encounter_coord(node: Dictionary) -> Vector2i:
	var node_id := str(node.get("node_id", ""))
	var authored_coord := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
	if not MapSimulationScript.patrol_definition(definition, node_id).is_empty() and not MapExplorationServiceScript.encounter_cleared(map_state, node_id):
		return MapSimulationScript.render_coord_or_authored(map_state, definition, grid, node_id, authored_coord)
	return authored_coord

func _update_enemy_pawn_from_simulation(node_id: String, animate := false) -> void:
	var root: Node3D = enemy_pawns.get(node_id)
	if root == null: return
	var node := ChapterMapLoaderScript.node_by_id(definition, node_id)
	if node.is_empty(): return
	var coord := _encounter_coord(node)
	var target := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.18)
	var prior := root.position
	var moving_until := int(root.get_meta("patrol_motion_until_msec", 0))
	if animate and prior.distance_to(target) > 0.08:
		var motion := create_tween()
		motion.set_trans(Tween.TRANS_SINE)
		motion.set_ease(Tween.EASE_IN_OUT)
		motion.tween_property(root, "position", target, 0.22)
		_spawn_patrol_step_cue(prior, target)
		root.set_meta("patrol_motion_until_msec", Time.get_ticks_msec() + 240)
	elif Time.get_ticks_msec() >= moving_until:
		root.position = target
	var runtime: Dictionary = map_state.get("patrol_states", {}).get(node_id, {})
	var awareness_state := str(runtime.get("awareness", MapSimulationScript.UNAWARE))
	var awareness_label = root.get_meta("awareness_label", null)
	if awareness_label is Label3D:
		(awareness_label as Label3D).text = "!" if awareness_state == MapSimulationScript.ALERT else ("?" if awareness_state == MapSimulationScript.SUSPICIOUS else "")
		(awareness_label as Label3D).modulate = Color("ff766f") if awareness_state == MapSimulationScript.ALERT else Color("f4d77c")
	var ring = root.get_meta("threat_ring", null)
	if ring is MeshInstance3D:
		var warning := Color("e96871") if awareness_state == MapSimulationScript.ALERT else (Color("e4bd62") if awareness_state == MapSimulationScript.SUSPICIOUS else Color("a95762"))
		(ring as MeshInstance3D).material_override = _material(warning, warning.darkened(0.14))

func _spawn_patrol_step_cue(from: Vector3, to: Vector3) -> void:
	# A concise, diegetic after-signal makes WAIT visibly causal without drawing
	# a permanent debug patrol line across the release map.
	var cue := MeshInstance3D.new()
	var cue_mesh := TorusMesh.new()
	cue_mesh.inner_radius = 0.18
	cue_mesh.outer_radius = 0.23
	cue_mesh.rings = 6
	cue_mesh.ring_segments = 14
	cue.mesh = cue_mesh
	cue.position = from + Vector3(0.0, 0.12, 0.0)
	cue.material_override = _material(Color("e5ba65"), Color("e0953f"))
	world_root.add_child(cue)
	var cue_tween := create_tween()
	cue_tween.set_parallel(true)
	cue_tween.tween_property(cue, "scale", Vector3(2.1, 1.0, 2.1), 0.34)
	cue_tween.tween_property(cue, "position", to + Vector3(0.0, 0.10, 0.0), 0.34)
	cue_tween.chain().tween_callback(cue.queue_free)

func _show_map_notice(text_value: String) -> void:
	map_notice = text_value
	# Keep exploration feedback visible long enough to survive a mobile tap and
	# the short pawn-motion tween; otherwise a completed Wait can look inert.
	map_notice_until_msec = Time.get_ticks_msec() + 3200
	if status_label != null:
		status_label.text = map_notice

func _wait_pulse() -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	_complete_player_turn("대기")

func _complete_player_turn(action_label: String) -> void:
	if map_simulation_paused:
		pending_turn_completion = true
		pending_turn_label = action_label
		turn_transitioning = true
		moving = false
		return
	if turn_transitioning:
		return
	turn_transitioning = true
	moving = false
	movement_skip_requested = false
	active_movement_path.clear()
	_show_map_notice("%s · 적 턴 진행 중" % action_label)
	_refresh_state_visuals()
	if move_button != null: move_button.disabled = true
	if wait_button != null: wait_button.disabled = true
	if next_encounter_button != null: next_encounter_button.disabled = true
	var party_coord := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	var update := MapExplorationServiceScript.complete_player_move_turn(map_state, definition, grid, party_coord)
	for node_id in update.get("changed", []):
		_update_enemy_pawn_from_simulation(str(node_id), true)
	for node_id in update.get("awareness", {}).keys():
		_update_enemy_pawn_from_simulation(str(node_id))
	if not update.get("changed", []).is_empty():
		await get_tree().create_timer(0.30).timeout
	if not is_inside_tree():
		return
	SaveService.save_game()
	pending_turn_completion = false
	pending_turn_label = ""
	if not update.get("contacts", []).is_empty():
		turn_transitioning = false
		_start_patrol_contact(str(update.contacts[0]), party_coord, true)
		return
	turn_transitioning = false
	_rebuild_selected_preview()
	_refresh_state_visuals()
	_show_map_notice("적 턴 완료 · 다음 아군 턴 · 이동 %d/%d · 순찰 %d체 이동" % [int(map_state.get("movement_points", 0)), int(map_state.get("movement_points_max", 0)), int(update.get("changed", []).size())])

func _start_patrol_contact(node_id: String, return_coord: Vector2i, movement_refilled := false) -> void:
	if not map_state.get("pending_encounter", {}).is_empty(): return
	var node := ChapterMapLoaderScript.node_by_id(definition, node_id)
	if node.is_empty() or not AppState.is_stage_unlocked(str(node.get("stage_id", ""))): return
	if MapExplorationServiceScript.encounter_cleared(map_state, node_id): return
	movement_generation += 1
	moving = false
	turn_transitioning = false
	movement_skip_requested = false
	live_encounter_replans = 0
	active_movement_path.clear()
	if not movement_refilled:
		MapExplorationServiceScript.refill_movement(map_state, definition)
	if map_state.get("patrol_states", {}).has(node_id):
		map_state.patrol_states[node_id].patrol_state = MapSimulationScript.PATROL_ENGAGED
	if AppState.prepare_map_encounter(str(node.get("stage_id", "")), node_id, return_coord, map_id):
		_complete_first_map_tutorial()
		SaveService.save_game()
		battle_requested.emit(str(node.get("stage_id", "")))

func _update_panel() -> void:
	if detail_title == null: return
	_apply_responsive_layout()
	_update_route_minimap()
	if selected_node.is_empty() and selected_treasure.is_empty() and selected_relay.is_empty() and selected_event.is_empty():
		detail_title.text = "조우 타일을 선택하세요"
		detail_body.text = "[color=#91aac8]한 번 클릭하면 경로 확인 · 더블클릭 또는 터치하면 노란 범위 안에서 즉시 이동합니다.[/color]\n\n이동 완료: 적 턴 자동 진행 → 다음 아군 턴\n클리어 타일: 빠른 이동\n3성 타일: 원격 소탕\n맵 이동: 작전력 소비 없음"
		move_button.visible = false
		fast_travel_button.visible = false
		battle_button.visible = false
		for button in sweep_buttons: button.visible = false
		_set_action_states(true, true, true)
		return
	if not selected_relay.is_empty():
		var relay_id := str(selected_relay.get("relay_id", ""))
		var relay_status := MapExplorationServiceScript.relay_state(map_state, relay_id)
		var relay_coord := Vector2i(int(selected_relay.get("q", 0)), int(selected_relay.get("r", 0)))
		var at_relay := Vector2i(int(map_state.current_q), int(map_state.current_r)) == relay_coord
		detail_title.text = str(selected_relay.get("name", "지역 릴레이"))
		detail_body.text = "[color=#78e6d0][b]%s[/b][/color]\n%s\n\n예상 이동  [color=#85e8ff]%d 구간[/color]  ·  %s\n\n복구하면 주변 지도 정보와 탐색 단서를 복원합니다. 성장 재료는 소비하지 않습니다." % [relay_status_display(relay_status), "연결된 활성 릴레이 사이를 빠르게 이동할 수 있습니다." if relay_status == "ACTIVE" else "현장 접근 후 신호를 복구할 수 있습니다.", maxi(0, preview_path.size() - 1), _risk_text()]
		move_button.visible = true
		move_button.text = "릴레이 복구" if at_relay and relay_status != "ACTIVE" else "릴레이로 이동"
		if not at_relay: move_button.text = _movement_action_text(move_button.text)
		move_button.disabled = (at_relay and relay_status == "ACTIVE") or (not at_relay and (preview_path.size() <= 1 or MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0))
		fast_travel_button.visible = relay_status == "ACTIVE" and not at_relay and not _active_relay_at_party().is_empty()
		fast_travel_button.text = "활성 릴레이로 빠른 이동"
		fast_travel_button.disabled = not MapExplorationServiceScript.can_fast_travel_between(map_state, definition, str(_active_relay_at_party().get("relay_id", "")), relay_id)
		battle_button.visible = false
		for button in sweep_buttons: button.visible = false
		return
	if not selected_event.is_empty():
		var event_id := str(selected_event.get("event_id", ""))
		var event_coord := Vector2i(int(selected_event.get("q", 0)), int(selected_event.get("r", 0)))
		var at_event := Vector2i(int(map_state.current_q), int(map_state.current_r)) == event_coord
		var choices: Array = selected_event.get("choices", [])
		var resolved := MapExplorationServiceScript.event_state(map_state, event_id) == "RESOLVED"
		detail_title.text = LocalizationService.tr_key(str(selected_event.get("title_key", "MAP_EVENT_DEFAULT_TITLE")))
		detail_body.text = "%s\n\n예상 이동  [color=#85e8ff]%d 구간[/color]  ·  %s" % [LocalizationService.tr_key(str(selected_event.get("body_key", "MAP_EVENT_DEFAULT_BODY"))), maxi(0, preview_path.size() - 1), _risk_text()]
		move_button.visible = not resolved
		move_button.text = LocalizationService.tr_key(str(choices[0].get("label_key", "MAP_EVENT_DEFAULT_CHOICE_PRIMARY"))) if at_event and not choices.is_empty() else LocalizationService.tr_key("MAP_EVENT_MOVE_TO")
		if not at_event: move_button.text = _movement_action_text(move_button.text)
		move_button.disabled = resolved or (not at_event and (preview_path.size() <= 1 or MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0))
		fast_travel_button.visible = at_event and not resolved and choices.size() > 1
		fast_travel_button.text = LocalizationService.tr_key(str(choices[1].get("label_key", "MAP_EVENT_DEFAULT_CHOICE_SECONDARY"))) if choices.size() > 1 else ""
		fast_travel_button.disabled = resolved
		battle_button.visible = false
		for button in sweep_buttons: button.visible = false
		return
	if not selected_treasure.is_empty():
		var landmark_key := str(selected_treasure.get("landmark_key", ""))
		var landmark_name := LocalizationService.tr_key(landmark_key) if not landmark_key.is_empty() else LocalizationService.tr_key("MAP_TREASURE_DETAIL_TITLE")
		detail_title.text = LocalizationService.tr_key("MAP_TREASURE_DETAIL_TITLE")
		detail_body.text = LocalizationService.tr_key("MAP_TREASURE_DETAIL_BODY") % [landmark_name, maxi(0, preview_path.size() - 1), _risk_text()]
		move_button.visible = true
		move_button.text = _movement_action_text(LocalizationService.tr_key("MAP_TREASURE_MOVE"))
		move_button.disabled = preview_path.size() <= 1 or MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0
		fast_travel_button.visible = false
		battle_button.visible = false
		for button in sweep_buttons: button.visible = false
		return
	var stage_id := str(selected_node.get("stage_id", ""))
	if stage_id == "":
		detail_title.text = "기점 • 릴레이 캠프"
		detail_body.text = "[color=#78e6d0]출발 거점[/color]\n부대의 탐색 기준점입니다."
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
	# Uncleared patrol encounters are selected at their live simulation hex, not
	# permanently at the authored marker. Keep the action state aligned with the
	# same coordinate that pathfinding and physical contact use.
	var at_node := Vector2i(int(map_state.current_q), int(map_state.current_r)) == _encounter_coord(selected_node)
	var attempts := "무제한"
	if stage.mode == "HARD":
		attempts = "무제한 (DEV)" if SettingsService.is_developer_mode() else "%d/%d 사용" % [int(AppState.profile.hard_attempts.counts.get(stage_id, 0)), int(stage.daily_attempts)]
	var lock_reason := "" if unlocked else ("최종 일반 작전 클리어 필요" if stage.mode == "HARD" else "직전 일반 작전 클리어 필요")
	var operation_type := "위험 작전" if stage.mode == "HARD" else "일반 작전"
	var special_event := _event_encounter_for_node(str(selected_node.get("node_id", "")))
	var title_override := LocalizationService.tr_key(str(special_event.get("title_key", ""))) if not special_event.is_empty() and stars <= 0 else ""
	detail_title.text = title_override if not title_override.is_empty() else "%s%s" % [LocalizationService.tr_key(stage.name_key), " · 대형 조우" if stage.boss else ""]
	var event_brief := "\n\n[color=#7ee7d5][b]! 특별 조우[/b][/color]\n%s" % LocalizationService.tr_key(str(special_event.get("body_key", ""))) if not special_event.is_empty() and stars <= 0 else ""
	detail_body.text = "[color=#7cf1dc][b]%s[/b][/color]\n[color=#f1d77a]권장 Lv.%d[/color]     작전력 [b]%d[/b]     제한 %d초\n완료 등급  %s\n입장 횟수  %s\n예상 이동  [color=#85e8ff]%d 구간[/color]  ·  %s\n%s%s\n\n[color=#9cc5dc][b]3성 조건[/b][/color]\n클리어 · 전투불능 0 · %d초 내\n\n[color=#9cc5dc][b]획득 가능 보상[/b][/color]\n%s%s" % [operation_type, int(stage.recommended_level), int(stage.stamina_cost), int(stage.time_limit), "★".repeat(stars) + "☆".repeat(3-stars), attempts, maxi(0, preview_path.size()-1), _risk_text(), _movement_summary(), event_brief, int(stage.target_time), _reward_text(reward), "\n\n[color=#ffbd7a][b]잠금[/b]  " + lock_reason + "[/color]" if not unlocked else ""]
	# Do not leave a disabled first-contact action unexplained.  This is only
	# presentation copy: the immutable AppState transaction remains the sole
	# authority for stamina, HARD entries and stage unlocks.
	if unlocked and not at_node and not AppState.can_enter_stage(stage_id):
		var entry_reason := ""
		if int(AppState.profile.account.get("stamina", 0)) < int(stage.stamina_cost):
			entry_reason = "작전력이 부족합니다 · 전투 시작 시에만 작전력이 차감됩니다"
		elif stage.mode == "HARD" and int(AppState.profile.hard_attempts.counts.get(stage_id, 0)) >= int(stage.daily_attempts):
			entry_reason = "오늘의 HARD 입장 횟수를 모두 사용했습니다"
		else:
			entry_reason = "현재 입장 조건을 다시 확인 중입니다 · 이동과 전투는 차감되지 않았습니다"
		detail_body.text += "\n\n[color=#ffbd7a][b]이동 불가[/b]  %s[/color]" % entry_reason
	# Keep the primary map actions above the portrait bottom edge. Remote farming
	# tools appear only after their real unlock condition, rather than occupying
	# the first-visit encounter sheet as disabled controls.
	move_button.visible = not at_node
	move_button.text = _movement_action_text("! 구조 신호 방향" if not special_event.is_empty() and stars <= 0 else "조우 방향")
	# Put the blocked-entry reason on the action itself as well.  The explanatory
	# copy above can fall below a narrow landscape sheet, whereas the disabled
	# primary action must remain immediately understandable.
	if unlocked and not AppState.can_enter_stage(stage_id):
		if int(AppState.profile.account.get("stamina", 0)) < int(stage.stamina_cost):
			move_button.text = "작전력 부족"
		elif stage.mode == "HARD" and int(AppState.profile.hard_attempts.counts.get(stage_id, 0)) >= int(stage.daily_attempts):
			move_button.text = "오늘 HARD 입장 횟수 소진"
		else:
			move_button.text = "입장 조건 확인 필요"
	fast_travel_button.visible = stars > 0
	var uncleared_encounter := not MapExplorationServiceScript.encounter_cleared(map_state, str(selected_node.get("node_id", ""))) and stars <= 0
	# An uncleared hostile starts combat by physical contact only.  Cleared
	# stages retain their normal repeat-battle action without an enemy pawn.
	battle_button.visible = not uncleared_encounter
	battle_button.text = "기존 실시간 전투 재도전"
	for button in sweep_buttons: button.visible = stars >= 3
	move_button.disabled = not unlocked or preview_path.size() <= 1 or MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0 or (uncleared_encounter and not AppState.can_enter_stage(stage_id))
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
	for entry in reward.get("guaranteed", []): lines.append("• %s ×%d" % [_display_item_name(str(entry.get("item_id", "?"))), int(entry.get("quantity", entry.get("min", 1)))])
	for entry in reward.get("bonus", []): lines.append("• %s %.0f%%" % [_display_item_name(str(entry.get("item_id", "?"))), float(entry.get("chance", 0.0))*100.0])
	return "\n".join(lines)

func _display_item_name(item_id: String) -> String:
	var item := DataRegistry.by_id("items", item_id)
	return LocalizationService.tr_key(str(item.get("name_key", item_id.replace("_", " ")))).replace(" (DEV)", "")

func _risk_text() -> String:
	return "[color=#71e6c7]안전 경로[/color]" if preview_risk == "SAFE" else ("[color=#f0c46b]경계 구간 가능[/color]" if preview_risk == "WATCHED" else "[color=#f07f79]적 접촉 예상[/color]")

func _movement_action_text(destination_label: String) -> String:
	var full_steps := maxi(0, preview_path.size() - 1)
	if full_steps <= 0:
		return destination_label
	var pulse_steps := mini(full_steps, MapExplorationServiceScript.movement_remaining(map_state, definition))
	if pulse_steps < full_steps:
		return "%s · %d칸 후 중간 정지" % [destination_label, pulse_steps]
	return "%s · %d칸 이동" % [destination_label, pulse_steps]

func _movement_summary() -> String:
	var rules: Dictionary = definition.get("exploration_rules", {})
	var account_level := int(AppState.profile.get("account", {}).get("level", 1))
	var level_bonus := 0
	for milestone_value in rules.get("account_level_milestones", []):
		var milestone: Dictionary = milestone_value
		if account_level >= int(milestone.get("level", 9999)):
			level_bonus += maxi(0, int(milestone.get("bonus", 0)))
	var module_bonus := 0
	var inventory: Dictionary = AppState.profile.get("inventory", {})
	for module_value in rules.get("mobility_items", []):
		var module: Dictionary = module_value
		if int(inventory.get(str(module.get("item_id", "")), 0)) > 0:
			module_bonus += maxi(0, int(module.get("bonus", 0)))
	var base_points := maxi(1, int(rules.get("base_move_points", 3)))
	var max_points := maxi(1, int(rules.get("max_move_points", 8)))
	return "이번 턴 [color=#ffd66d]%d/%d칸[/color] · 노란 영역 안에서만 이동\n[color=#91aac8]기본 %d · 계정 Lv.%d +%d · 노선 모듈 +%d · 최종 상한 %d[/color]" % [int(map_state.get("movement_points", 0)), int(map_state.get("movement_points_max", 0)), base_points, account_level, level_bonus, module_bonus, max_points]

func _active_relay_at_party() -> Dictionary:
	var current := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	for relay in definition.get("relays", []):
		if MapExplorationServiceScript.relay_state(map_state, str(relay.get("relay_id", ""))) == "ACTIVE" and current == Vector2i(int(relay.get("q", 0)), int(relay.get("r", 0))):
			return relay
	return {}

static func direct_move_gesture_policy(event: InputEvent, repeated_pointer_click := false, touch_tap_valid := true) -> bool:
	## Desktop keeps single-click as preview and promotes the second click to a
	## confirmed route. Godot Web normally supplies `double_click`, but browsers
	## and automation bridges can deliver the same physical gesture as two plain
	## presses; the caller-provided repeat flag preserves the same user contract.
	## Touch has no hover/double-click convention, so a short released tap confirms
	## while drag/cancel gestures remain camera controls.
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and event.pressed and (event.double_click or repeated_pointer_click)
	if event is InputEventScreenTouch:
		return event.index == 0 and not event.pressed and not event.canceled and touch_tap_valid
	return false

func _can_begin_selected_route() -> bool:
	if moving or turn_transitioning or map_simulation_paused or preview_path.size() <= 1:
		return false
	if selected_node.is_empty() and selected_treasure.is_empty() and selected_relay.is_empty() and selected_event.is_empty():
		return movement_range_reachable.has(HexCoordScript.key(preview_path[-1]))
	return move_button != null and move_button.visible and not move_button.disabled

func _activate_selected_route_from_pointer() -> void:
	if _can_begin_selected_route():
		_confirm_move()
		return
	if preview_path.size() > 1 or (selected_node.is_empty() and selected_treasure.is_empty() and selected_relay.is_empty() and selected_event.is_empty()):
		return
	var current := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	var target := _selected_target_coord()
	_show_map_notice("현재 위치입니다 · 다른 노란 칸을 선택하세요" if current == target else "현재 공개된 경로로 연결되지 않습니다 · 노란 이동 가능 칸을 선택하세요")

func _confirm_move() -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	if not selected_relay.is_empty() and preview_path.size() <= 1:
		_activate_selected_relay()
		return
	if not selected_event.is_empty() and preview_path.size() <= 1:
		_resolve_selected_event(0)
		return
	if preview_path.size() <= 1: return
	var pulse_path := _path_for_current_pulse(preview_path)
	if pulse_path.size() <= 1:
		_show_map_notice("이동 범위를 모두 사용했습니다 · 대기로 다음 탐색 펄스를 시작하세요")
		_update_panel()
		return
	if _first_map_tutorial_active() and tutorial_step > 0:
		_set_tutorial_step(3)
	_move_along(pulse_path)

func _set_direct_hex_route(coord: Vector2i) -> bool:
	var key := HexCoordScript.key(coord)
	var current := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	if coord == current or not movement_range_reachable.has(key):
		return false
	if _unresolved_encounter_stop_hexes().has(key):
		for node_value in definition.get("nodes", []):
			var node: Dictionary = node_value
			if _encounter_coord(node) == coord:
				_select_node(node)
				return preview_path.size() > 1
	var path := HexPathfinderScript.find_path(grid, current, coord, _path_reveal_allowlist())
	if path.size() <= 1:
		return false
	selected_node = {}
	selected_treasure = {}
	selected_relay = {}
	selected_event = {}
	preview_path = path
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, preview_path)
	_update_route_mesh()
	_focus_preview_route()
	_update_panel()
	return true

func _path_for_current_pulse(path: Array[Vector2i]) -> Array[Vector2i]:
	var steps := maxi(0, MapExplorationServiceScript.movement_remaining(map_state, definition))
	if path.size() <= 1 or steps <= 0:
		return [path[0]] if not path.is_empty() else []
	return path.slice(0, mini(path.size(), steps + 1))

func _selected_target_coord() -> Vector2i:
	if not selected_node.is_empty(): return _encounter_coord(selected_node)
	if not selected_treasure.is_empty(): return Vector2i(int(selected_treasure.get("q", 0)), int(selected_treasure.get("r", 0)))
	if not selected_relay.is_empty(): return Vector2i(int(selected_relay.get("q", 0)), int(selected_relay.get("r", 0)))
	if not selected_event.is_empty(): return Vector2i(int(selected_event.get("q", 0)), int(selected_event.get("r", 0)))
	return Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))

func _path_reveal_allowlist() -> Dictionary:
	# "스테이지 전체 해금" is a Development-only navigation aid.  It must
	# not mutate canonical fog/reveal data or a player save, but debug encounters
	# still need a real traversable route to exercise the existing battle loop.
	# Release builds continue to use only the persisted reveal authority.
	var allowed: Dictionary = {}
	if AppState.debug_unlock_all_enabled():
		for tile in definition.get("tiles", []):
			allowed["%d,%d" % [int(tile.get("q", 0)), int(tile.get("r", 0))]] = true
		return allowed
	for key in map_state.get("revealed_tiles", []):
		allowed[str(key)] = true
	return allowed

func _rebuild_selected_preview() -> void:
	var current := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	var target := _selected_target_coord()
	if current == target:
		preview_path = [current]
	else:
		var allowed: Dictionary = {}
		# Treasure detours remain routable once revealed; other interactions use
		# the discovered route authority.
		if selected_treasure.is_empty():
			allowed = _path_reveal_allowlist()
		preview_path = HexPathfinderScript.find_path(grid, current, target, allowed)
		preview_path = _truncate_at_first_unresolved_encounter(preview_path)
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, preview_path)
	_update_route_mesh()

func _activate_selected_relay() -> void:
	if selected_relay.is_empty(): return
	var result := MapExplorationServiceScript.activate_relay(map_state, definition, str(selected_relay.get("relay_id", "")))
	if result.ok:
		SaveService.save_game()
		_refresh_state_visuals()

func _resolve_selected_event(choice_index: int) -> void:
	if selected_event.is_empty(): return
	var choices: Array = selected_event.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size(): return
	var result := MapExplorationServiceScript.resolve_event(map_state, definition, str(selected_event.get("event_id", "")), str(choices[choice_index].get("choice_id", "")))
	if result.ok:
		SaveService.save_game()
		_refresh_state_visuals()
		if not result.value.get("rewards", {}).is_empty(): treasure_reward_requested.emit(result.value)

func _move_along(path: Array[Vector2i]) -> void:
	if path.size() <= 1 or moving or turn_transitioning or map_simulation_paused:
		return
	moving = true
	movement_skip_requested = false
	pawn_motion_state = "WALK"
	movement_generation += 1
	var generation := movement_generation
	active_movement_path = path.duplicate()
	var traveled_path: Array[Vector2i] = [Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))]
	if preview_camera_tween != null and preview_camera_tween.is_valid():
		preview_camera_tween.kill()
	_refresh_state_visuals()
	_focus_current(true)
	await get_tree().create_timer(0.03).timeout
	for index in range(1, path.size()):
		if generation != movement_generation:
			return
		if not MapExplorationServiceScript.spend_movement(map_state, definition, 1):
			break
		var coord := path[index]
		var prior_coord := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
		map_state.last_pre_contact_hex = [prior_coord.x, prior_coord.y]
		_stream_visible_tiles(coord)
		var target := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.14)
		_set_pawn_facing(pawn.position, target)
		_spawn_pawn_step_trail(pawn.position)
		if movement_skip_requested:
			pawn.position = target
		else:
			var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(pawn, "position", target, PAWN_STEP_DURATION)
			await tween.finished
		if generation != movement_generation: return
		pawn_last_position = target
		traveled_path.append(coord)
		# Keep a small amount of the route in frame instead of locking the camera
		# exactly to every footstep; this makes travelled distance immediately legible.
		if index == 1 or index % 3 == 0 or index == path.size() - 1:
			_follow_moving_pawn(target)
		# Logical party position advances on the same discrete hex boundary that
		# the pawn animation reaches.  The map simulation may then interrupt this
		# route, but never reads tween progress or rendered Node3D coordinates.
		ChapterMapProgressScript.mark_visited(map_state, [coord])
		var proximity_changes := MapExplorationServiceScript.update_proximity(map_state, definition, coord)
		if not proximity_changes.is_empty(): _refresh_state_visuals()
		var contacts := MapSimulationScript.contacts_at_party_coord(map_state, definition, grid, coord)
		if not contacts.is_empty():
			_start_patrol_contact(str(contacts[0]), prior_coord)
			return
	var arrival := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	map_state.last_selected_node = str(selected_node.get("node_id", ""))
	if not _arrival_resolution_owns_save(arrival):
		SaveService.save_game()
	moving = false
	pawn_motion_state = "ARRIVE"
	await get_tree().create_timer(0.06).timeout
	pawn_motion_state = "IDLE"
	active_movement_path.clear()
	movement_skip_requested = false
	var arrival_outcome := _resolve_arrival(traveled_path)
	_rebuild_selected_preview()
	_refresh_state_visuals()
	if arrival_outcome == "STAY" and is_inside_tree():
		_complete_player_turn("이동 완료")
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
	# The authoritative coroutine still spends and resolves each crossed tile once;
	# this flag only removes the remaining visual waits.
	movement_skip_requested = true

func _resolve_arrival(path: Array[Vector2i]) -> String:
	if path.is_empty(): return "STAY"
	var arrival := path[-1]
	var proximity_changes := MapExplorationServiceScript.update_proximity(map_state, definition, arrival)
	if not proximity_changes.is_empty():
		_refresh_state_visuals()
	if not selected_treasure.is_empty() and arrival == Vector2i(int(selected_treasure.q), int(selected_treasure.r)):
		var report := MapExplorationServiceScript.claim_treasure(map_state, definition, str(selected_treasure.treasure_id))
		if report.ok:
			SaveService.save_game()
			treasure_reward_requested.emit(report.value)
			return "TRANSITION"
	if not selected_relay.is_empty() and arrival == Vector2i(int(selected_relay.get("q", 0)), int(selected_relay.get("r", 0))):
		_activate_selected_relay()
		return "STAY"
	if not selected_event.is_empty() and arrival == Vector2i(int(selected_event.get("q", 0)), int(selected_event.get("r", 0))):
		_update_panel()
		return "STAY"
	if selected_node.is_empty() or str(selected_node.get("stage_id", "")).is_empty(): return "STAY"
	var node_id := str(selected_node.get("node_id", ""))
	if MapExplorationServiceScript.encounter_cleared(map_state, node_id) or int(AppState.profile.stage_stars.get(str(selected_node.stage_id), 0)) > 0:
		return "STAY"
	var live_enemy_coord := _encounter_coord(selected_node)
	if arrival != live_enemy_coord:
		if MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0:
			return "STAY"
		# Patrol simulation advances only at discrete map ticks.  Do not pretend the
		# old preview endpoint is still hostile after the enemy moved; deterministically
		# re-plan to the current pawn position, then require real contact.
		if _continue_live_encounter_pursuit(arrival, live_enemy_coord):
			return "REPLAN"
		_show_map_notice("순찰 적이 경로를 벗어났습니다 · 다시 선택하여 추적")
		return "STAY"
	var return_coord := path[path.size() - 2] if path.size() >= 2 else Vector2i(int(map_state.current_q), int(map_state.current_r))
	map_state.last_pre_contact_hex = [return_coord.x, return_coord.y]
	_start_patrol_contact(node_id, return_coord)
	return "TRANSITION"

func _arrival_resolution_owns_save(arrival: Vector2i) -> bool:
	# Avoid two complete Web filesystem transactions at the same destination.
	# Treasure/relay claims and a real encounter each persist their atomic result;
	# the movement layer only saves arrivals with no immediate transaction.
	if not selected_treasure.is_empty() and arrival == Vector2i(int(selected_treasure.get("q", 0)), int(selected_treasure.get("r", 0))):
		return true
	if not selected_relay.is_empty() and arrival == Vector2i(int(selected_relay.get("q", 0)), int(selected_relay.get("r", 0))):
		return true
	if not selected_node.is_empty() and arrival == _encounter_coord(selected_node):
		var node_id := str(selected_node.get("node_id", ""))
		var stage_id := str(selected_node.get("stage_id", ""))
		return not MapExplorationServiceScript.encounter_cleared(map_state, node_id) and int(AppState.profile.stage_stars.get(stage_id, 0)) <= 0
	return false

func _continue_live_encounter_pursuit(arrival: Vector2i, live_enemy_coord: Vector2i) -> bool:
	var node_id := str(selected_node.get("node_id", ""))
	# Static encounters always retain their authored coordinate.  Only actual
	# patrols may change their target after the user confirmed movement.
	if MapSimulationScript.patrol_definition(definition, node_id).is_empty():
		return false
	if live_encounter_replans >= MAX_LIVE_ENCOUNTER_REPLANS:
		return false
	var allowed := _path_reveal_allowlist()
	var pursuit_path := MapSimulationScript.pursuit_path(map_state, definition, grid, arrival, node_id, allowed)
	pursuit_path = _truncate_at_first_unresolved_encounter(pursuit_path)
	if pursuit_path.size() <= 1 or pursuit_path[-1] != live_enemy_coord:
		return false
	live_encounter_replans += 1
	preview_path = pursuit_path
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, pursuit_path)
	_update_route_mesh()
	_refresh_state_visuals()
	_show_map_notice("순찰 적 재포착 · 경로 갱신 %d/%d" % [live_encounter_replans, MAX_LIVE_ENCOUNTER_REPLANS])
	# The prior movement coroutine has fully reached its discrete arrival point.
	# Defer the next segment so it cannot overlap a stale tween or create two
	# encounter transactions in one frame.
	call_deferred("_move_along", pursuit_path)
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		map_simulation_paused = true
		map_state.map_simulation_state.paused = true
		if moving: skip_movement()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		map_simulation_paused = false
		map_state.map_simulation_state.paused = false
		if pending_turn_completion:
			var resume_label := pending_turn_label
			pending_turn_completion = false
			pending_turn_label = ""
			turn_transitioning = false
			call_deferred("_complete_player_turn", resume_label)

func _fast_travel() -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	if not selected_event.is_empty():
		_resolve_selected_event(1)
		return
	if not selected_relay.is_empty():
		var origin := _active_relay_at_party()
		var destination_id := str(selected_relay.get("relay_id", ""))
		if origin.is_empty() or not MapExplorationServiceScript.can_fast_travel_between(map_state, definition, str(origin.get("relay_id", "")), destination_id): return
		AppState.set_chapter_map_position(Vector2i(int(selected_relay.get("q", 0)), int(selected_relay.get("r", 0))), "", map_id)
		pawn.position = _pawn_world_position()
		_focus_current(false)
		SaveService.save_game()
		preview_path = [Vector2i(int(selected_relay.get("q", 0)), int(selected_relay.get("r", 0)))]
		_update_route_mesh()
		_update_panel()
		return
	if selected_node.is_empty(): return
	var stage_id := str(selected_node.get("stage_id", ""))
	if int(AppState.profile.stage_stars.get(stage_id, 0)) <= 0: return
	AppState.set_chapter_map_position(Vector2i(int(selected_node.q), int(selected_node.r)), str(selected_node.node_id), map_id)
	pawn.position = _pawn_world_position()
	pawn_motion_state = "ARRIVE"
	await get_tree().create_timer(0.04).timeout
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
	live_encounter_replans = 0
	selected_treasure = {}
	selected_relay = {}
	selected_event = {}
	preview_path.clear()
	preview_risk = "SAFE"
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
	var next_target := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP)
	if immediate or bool(SettingsService.values.get("map_instant_focus", false)):
		# An immediate focus changes districts in one frame, so its local detail
		# terrain must be ready before the camera is moved.
		_stream_visible_tiles(coord, true)
		camera_target = _clamp_camera_target_to_terrain(next_target)
	else:
		# Do not evict the current district before this tween begins. _process()
		# advances the stream anchor along the focus path, keeping real terrain
		# under the camera for the entire transition instead of flashing ocean.
		if preview_camera_tween != null and preview_camera_tween.is_valid():
			preview_camera_tween.kill()
		preview_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		preview_camera_tween.tween_method(func(value: Vector3): camera_target = _clamp_camera_target_to_terrain(value), camera_target, next_target, 0.35)

func _focus_full_map() -> void:
	var normal_route: Array = definition.get("normal_route", [])
	var overview_index := mini(4, normal_route.size() - 1)
	var overview_node := ChapterMapLoaderScript.node_for_stage(definition, str(normal_route[overview_index])) if overview_index >= 0 else {}
	var overview_coord := Vector2i(int(overview_node.get("q", 0)), int(overview_node.get("r", 0)))
	camera_target = _clamp_camera_target_to_terrain(HexCoordScript.axial_to_world(overview_coord, TILE_SIZE))
	camera_zoom = 0.72
	map_state.camera_zoom = camera_zoom
	_stream_visible_tiles(HexCoordScript.world_to_axial(camera_target, TILE_SIZE))

func _clamp_camera_target_to_terrain(candidate: Vector3) -> Vector3:
	# Camera navigation is constrained by the generated traversable land itself,
	# not by the former broad hard-coded world rectangle. This preserves smooth
	# pan along the 96-hex route while preventing a drag or legacy camera value
	# from centring the viewport in empty ocean where a pawn can look detached.
	if grid.traversable(HexCoordScript.world_to_axial(candidate, TILE_SIZE)):
		return candidate
	var origin := HexCoordScript.world_to_axial(candidate, TILE_SIZE)
	var closest_world := Vector3.ZERO
	var closest_distance := INF
	for dq in range(-CAMERA_TERRAIN_SEARCH_RADIUS, CAMERA_TERRAIN_SEARCH_RADIUS + 1):
		for dr in range(-CAMERA_TERRAIN_SEARCH_RADIUS, CAMERA_TERRAIN_SEARCH_RADIUS + 1):
			var coord := origin + Vector2i(dq, dr)
			if HexCoordScript.distance(origin, coord) > CAMERA_TERRAIN_SEARCH_RADIUS or not grid.traversable(coord):
				continue
			var world := HexCoordScript.axial_to_world(coord, TILE_SIZE)
			var distance := Vector2(candidate.x - world.x, candidate.z - world.z).length()
			if distance < closest_distance:
				closest_distance = distance
				closest_world = world
	if is_inf(closest_distance):
		var start: Dictionary = definition.get("start_hex", {"q": 0, "r": 0})
		closest_world = HexCoordScript.axial_to_world(Vector2i(int(start.get("q", 0)), int(start.get("r", 0))), TILE_SIZE)
		closest_distance = Vector2(candidate.x - closest_world.x, candidate.z - closest_world.z).length()
	if closest_distance <= CAMERA_TERRAIN_MARGIN:
		return candidate
	var offset := Vector2(candidate.x - closest_world.x, candidate.z - closest_world.z).normalized() * CAMERA_TERRAIN_MARGIN
	return Vector3(closest_world.x + offset.x, candidate.y, closest_world.z + offset.y)

func _on_map_input(event: InputEvent) -> void:
	# The SubViewport receives direct pointer events, bypassing AppShell's
	# shared Button wrapper.  Unlock deferred WebAudio on the first map gesture.
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		AudioService.unlock_from_user_gesture()
	if moving or turn_transitioning or map_simulation_paused: return
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
				_select_node_near_screen(event.position, direct_move_gesture_policy(event))
			dragging = false
	elif event is InputEventScreenDrag:
		if not dragging: return
		var touch_delta: Vector2 = event.position - drag_origin
		camera_target = _clamp_camera_target_to_terrain(camera_origin + Vector3(-touch_delta.x * 0.012 / camera_zoom, 0, -touch_delta.y * 0.012 / camera_zoom))
		map_state.camera_center = [camera_target.x, camera_target.z]
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var pointer_threshold := 18.0 * _portrait_ui_scale(_runtime_layout_size())
				var now_msec := Time.get_ticks_msec()
				var repeated_pointer_click: bool = last_map_pointer_click_valid and now_msec - last_map_pointer_click_msec >= 0 and now_msec - last_map_pointer_click_msec <= DIRECT_DOUBLE_CLICK_WINDOW_MSEC and event.position.distance_to(last_map_pointer_click_position) <= pointer_threshold
				direct_move_pending = direct_move_gesture_policy(event, repeated_pointer_click)
				if direct_move_pending:
					last_map_pointer_click_valid = false
				dragging = true
				drag_origin = event.position
				camera_origin = camera_target
			else:
				# A tap selects the nearest visible encounter in screen space. Map
				# traversal remains based on stable axial node data, not physics picks.
				var completed_click: bool = dragging and event.position.distance_to(drag_origin) <= 18.0 * _portrait_ui_scale(_runtime_layout_size())
				var activate_route := direct_move_pending
				if completed_click:
					_select_node_near_screen(event.position, activate_route)
					if not activate_route:
						last_map_pointer_click_valid = true
						last_map_pointer_click_msec = Time.get_ticks_msec()
						last_map_pointer_click_position = event.position
				else:
					last_map_pointer_click_valid = false
				dragging = false
				direct_move_pending = false
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera_zoom = clampf(camera_zoom + (0.08 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.08), 0.72, 1.55)
			map_state.camera_zoom = camera_zoom
	elif event is InputEventMouseMotion and dragging:
		var delta: Vector2 = event.position - drag_origin
		camera_target = _clamp_camera_target_to_terrain(camera_origin + Vector3(-delta.x * 0.012 / camera_zoom, 0, -delta.y * 0.012 / camera_zoom))
		map_state.camera_center = [camera_target.x, camera_target.z]

func _select_node_near_screen(screen_position: Vector2, activate_route := false) -> bool:
	if camera == null or viewport == null or viewport_container == null: return false
	var viewport_size := Vector2(viewport.size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0: return false
	var surface_scale := viewport_container.size / viewport_size
	var runtime_size := _runtime_layout_size()
	var hit_radius := 72.0 * _portrait_ui_scale(runtime_size) if runtime_size.y > runtime_size.x else 46.0
	var closest: Dictionary = {}
	var closest_kind := ""
	var closest_distance := INF
	# Hostile pawns take priority over their authored stage marker: selecting one
	# previews a route but cannot start combat before the squad really reaches it.
	for node_id in enemy_pawns:
		var hostile_root: Node3D = enemy_pawns[node_id]
		if hostile_root == null or not hostile_root.visible: continue
		var hostile_projected := camera.unproject_position(hostile_root.position + Vector3(0.0, 0.68, 0.0)) * surface_scale
		var hostile_distance := hostile_projected.distance_to(screen_position)
		if hostile_distance < closest_distance:
			closest_distance = hostile_distance
			closest = ChapterMapLoaderScript.node_by_id(definition, str(node_id))
			closest_kind = "NODE"
	for node in definition.get("nodes", []):
		var node_button: Button = node_buttons.get(str(node.get("node_id", "")))
		if node_button == null or not node_button.visible: continue
		var projected := _overlay_position_from_world(_node_overlay_anchor(node))
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
		var world_position := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.62)
		var projected := camera.unproject_position(world_position) * surface_scale
		var distance := projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = treasure
			closest_kind = "TREASURE"
	for relay in definition.get("relays", []):
		var relay_id := str(relay.get("relay_id", ""))
		var relay_root: Node3D = relay_visuals.get(relay_id)
		if relay_root == null or not relay_root.visible: continue
		var relay_projected := camera.unproject_position(relay_root.position + Vector3(0.0, 0.82, 0.0)) * surface_scale
		var relay_distance := relay_projected.distance_to(screen_position)
		if relay_distance < closest_distance:
			closest_distance = relay_distance
			closest = relay
			closest_kind = "RELAY"
	for event in definition.get("map_events", []):
		var event_id := str(event.get("event_id", ""))
		var event_root: Node3D = event_visuals.get(event_id)
		if event_root == null or not event_root.visible: continue
		var event_projected := camera.unproject_position(event_root.position + Vector3(0.0, 0.62, 0.0)) * surface_scale
		var event_distance := event_projected.distance_to(screen_position)
		if event_distance < closest_distance:
			closest_distance = event_distance
			closest = event
			closest_kind = "EVENT"
	if not closest.is_empty() and closest_distance <= hit_radius:
		if closest_kind == "TREASURE": _select_treasure(closest)
		elif closest_kind == "RELAY": _select_relay(closest)
		elif closest_kind == "EVENT": _select_event(closest)
		else: _select_node(closest)
		if activate_route:
			_activate_selected_route_from_pointer()
		return true
	if activate_route:
		var reachable_coord := Vector2i(999999, 999999)
		var reachable_distance := INF
		var current := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
		for key_value in movement_range_reachable.keys():
			var coord := HexCoordScript.from_key(str(key_value))
			if coord == current:
				continue
			var surface_y := float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.14
			var projected := camera.unproject_position(HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y)) * surface_scale
			var distance := projected.distance_to(screen_position)
			if distance < reachable_distance:
				reachable_distance = distance
				reachable_coord = coord
		if reachable_distance <= hit_radius and _set_direct_hex_route(reachable_coord):
			_activate_selected_route_from_pointer()
			return true
	return false

func _process(delta: float) -> void:
	if camera == null: return
	_refresh_environment_presentation()
	pawn_motion_phase += delta * (8.5 if pawn_motion_state == "WALK" else 3.0)
	if pawn_visual != null:
		# Motion is authored in the atlas. Moving/scaling the entire cutout would
		# lift its foot anchor from the terrace and make the pawn look airborne.
		pawn_visual.position.y = PAWN_VISUAL_BASE_Y
		pawn_visual.scale = Vector3.ONE
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
		var animation_name := "move" if Time.get_ticks_msec() < int(root.get_meta("patrol_motion_until_msec", 0)) else "idle"
		var frame := _animation_frame(pack, animation_name, Time.get_ticks_msec())
		atlas_texture.region = Rect2(float(frame % int(pack.get("columns", 1))) * frame_size.x, float(frame / int(pack.get("columns", 1))) * frame_size.y, frame_size.x, frame_size.y)
		for child in root.get_children():
			if not child is Sprite3D or child == sprite:
				continue
			var secondary_pack_value = child.get_meta("animation_pack", {})
			if not secondary_pack_value is Dictionary or not (child as Sprite3D).texture is AtlasTexture:
				continue
			var secondary_pack: Dictionary = secondary_pack_value
			var secondary_texture := (child as Sprite3D).texture as AtlasTexture
			var secondary_size: Vector2 = secondary_pack.get("frame_size", Vector2(104, 104))
			var secondary_frame := _animation_frame(secondary_pack, "idle", Time.get_ticks_msec() + int(child.get_meta("animation_phase_msec", 0)))
			secondary_texture.region = Rect2(float(secondary_frame % int(secondary_pack.get("columns", 1))) * secondary_size.x, float(secondary_frame / int(secondary_pack.get("columns", 1))) * secondary_size.y, secondary_size.x, secondary_size.y)
		if bool(root.get_meta("event_contact", false)):
			var marker_phase := float(root.get_meta("event_marker_phase", 0.0))
			var event_marker = root.get_meta("event_marker", null)
			if event_marker is Label3D:
				(event_marker as Label3D).position.y = float(root.get_meta("event_marker_base_y", 1.0)) + sin(pawn_motion_phase * 1.7 + marker_phase) * 0.09
			var event_ring = root.get_meta("threat_ring", null)
			if event_ring is MeshInstance3D:
				var marker_pulse := 1.0 + sin(pawn_motion_phase * 1.35 + marker_phase) * 0.07
				(event_ring as MeshInstance3D).scale = Vector3(marker_pulse, 1.0, marker_pulse)
	if pawn_sprite != null and pawn_sprite.texture is AtlasTexture and not pawn_animation_pack.is_empty():
		var leader_atlas := pawn_sprite.texture as AtlasTexture
		var leader_frame_size: Vector2 = pawn_animation_pack.get("frame_size", Vector2(104, 104))
		var leader_columns := maxi(1, int(pawn_animation_pack.get("columns", 1)))
		var leader_animation := "move" if pawn_motion_state == "WALK" else ("victory" if pawn_motion_state == "ARRIVE" else "idle")
		var leader_frame := _animation_frame(pawn_animation_pack, leader_animation, Time.get_ticks_msec())
		leader_atlas.region = Rect2(float(leader_frame % leader_columns) * leader_frame_size.x, float(leader_frame / leader_columns) * leader_frame_size.y, leader_frame_size.x, leader_frame_size.y)
	for treasure_id in treasure_visuals:
		var root: Node3D = treasure_visuals[treasure_id]
		if root == null or not root.visible: continue
		var glow = root.get_meta("glow", null)
		if glow != null and glow.visible:
			var pulse := 1.0 + sin(pawn_motion_phase * 1.5 + float(treasure_id.hash() % 9)) * 0.08
			glow.scale = Vector3(pulse, 1.0, pulse)
	camera.size = 13.2 / camera_zoom
	# A higher orthographic angle keeps a distant shelf or ridge from visually
	# covering a valid route pawn while preserving the 2.5D chapter-map read.
	# The simulation still owns X/Z; this only improves the production camera's
	# depth separation of terrain, sockets and map pawns.
	# The R8 camera is intentionally lower than the old tactical-board angle so
	# cliff faces occupy enough screen space to communicate elevation.
	camera.position = camera_target + Vector3(9.2, 14.2, 8.8)
	camera.look_at(camera_target, Vector3.UP)
	if environment_fx != null:
		environment_fx.set_camera_phase(camera_target)
	var camera_coord := HexCoordScript.world_to_axial(camera_target, TILE_SIZE)
	_stream_visible_tiles(camera_coord)
	# Rendering is streamed, but patrol state never is: offscreen hostiles retain
	# only their tiny logical state and wake visually when the camera returns.
	for node_id in enemy_pawns:
		var root: Node3D = enemy_pawns[node_id]
		var node := ChapterMapLoaderScript.node_by_id(definition, str(node_id))
		if root == null or node.is_empty(): continue
		var stage_id := str(node.get("stage_id", ""))
		var unlocked := stage_id != "" and AppState.is_stage_unlocked(stage_id)
		var cleared := MapExplorationServiceScript.encounter_cleared(map_state, str(node_id)) or int(AppState.profile.stage_stars.get(stage_id, 0)) > 0
		var encounter_coord := _encounter_coord(node)
		root.visible = unlocked and not cleared and _map_entity_is_locally_renderable(encounter_coord, camera_coord, STREAM_RADIUS + 2) and (not stage_id.contains("-H") or hard_overlay)
	# The render target grows on responsive layouts.  Scaling node controls from
	# the original 1280×720 constant displaced labels from their actual 3D
	# encounter markers after a resize; use the live SubViewport size instead.
	var runtime_size := _runtime_layout_size()
	var portrait := runtime_size.y > runtime_size.x
	var ui_scale := _portrait_ui_scale(runtime_size)
	var navigation_reveal := _path_reveal_allowlist()
	for node in definition.get("nodes", []):
		var button: Button = node_buttons.get(str(node.node_id))
		if button == null: continue
		var stage_id := str(node.get("stage_id", ""))
		var revealed: bool = navigation_reveal.has("%d,%d" % [int(node.get("q", 0)), int(node.get("r", 0))])
		var semantic_visible: bool = bool(revealed and (stage_id == "" or hard_overlay == stage_id.contains("-H")))
		var node_coord := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
		# A world-space encounter label is permitted only when its associated
		# streamed terrain cap is present and visible.  This keeps both the label
		# and the enemy pawn attached to real local ground at long-map boundaries.
		# Do not let the orthographic camera project a distant marker into the
		# middle of the current district.  The streamed tile radius is the render
		# authority, so labels outside its interior remain on the minimap until the
		# player focuses or travels to that district.
		var label_in_local_stream: bool = HexCoordScript.distance(node_coord, camera_coord) <= STREAM_RADIUS - 2
		var anchor := _node_overlay_anchor(node)
		button.visible = semantic_visible and label_in_local_stream and _has_streamed_ground(node_coord) and _overlay_anchor_is_visible(anchor, button.size)
		var stage_marker: Node3D = node_markers.get(str(node.get("node_id", "")))
		if stage_marker != null:
			stage_marker.visible = button.visible
		if not button.visible: continue
		var projected := _overlay_position_from_world(anchor)
		var label_offset := Vector2(0, (-78.0 if str(node.get("node_type", "")) == "START" else -62.0) * ui_scale) if portrait else Vector2(0, -126 if str(node.get("node_type", "")) == "START" else -86)
		button.position = projected - button.size * 0.5 + label_offset

func _refresh_environment_presentation() -> void:
	if environment_fx == null:
		return
	# Environment is a derived, transient grade based on canonical axial
	# position. It never writes that coordinate, its save payload or simulation.
	environment_fx.set_transient_map_context(Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0))), hard_overlay)
