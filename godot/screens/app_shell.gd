extends Control

const BattleViewScene := preload("res://battle/scenes/battle_root.tscn")
const ChapterMapScene := preload("res://chapter_map/view/chapter_map_root.tscn")
const ChapterMapLoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const MapExplorationServiceScript := preload("res://chapter_map/model/map_exploration_service.gd")
const HexGridScript := preload("res://chapter_map/model/hex_grid.gd")
const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const GrowthAffordabilityAnalyzerScript := preload("res://progression/growth_affordability_analyzer.gd")
const GrowthPlanBuilderScript := preload("res://progression/growth_plan_builder.gd")
const RelayServiceScript := preload("res://relay/relay_service.gd")
const DESIGN_VIEWPORT_SIZE := Vector2(1920.0, 1080.0)
const COMPACT_LANDSCAPE_MAX_WIDTH := 980.0
const MIN_TOUCH_CSS_PX := 56.0
const SPECIAL_EVENT_CONTACT_DURATION := 1.85
const BOSS_ENCOUNTER_CARD_DURATION := 0.82
var content: VBoxContainer
var footer_status: Label
var safe_margin: MarginContainer
var current_screen := "TITLE"
var stage_mode := "NORMAL"
var formation_slot := 0
var scenario_runner: ScenarioRunner
var scenario_speaker: Label
var scenario_text: RichTextLabel
var scenario_choices: VBoxContainer
var story_background: TextureRect
var story_portrait: TextureRect
var story_portrait_layer: Control
var story_art_status: Label
var story_dialogue_panel: PanelContainer
var story_speaker_eyebrow: Label
var story_click_hint: Label
var story_page_indicator: Label
var story_auto_button: Button
var story_skip_button: Button
var story_is_prologue := false
var active_chapter_map_screen: Control
var story_auto := false
var story_auto_left := 0.0
var story_ui_hidden := false
var story_controls: Control
var battle_view: BattleView
var battle_hud: Label
var ultimate_buttons: Array[Button] = []
var party_status_labels: Array[Label] = []
var battle_auto_button: Button
var battle_skip_button: Button
var battle_speed_button: Button
var battle_pause_panel: PanelContainer
var battle_pause_center: CenterContainer
var battle_portrait_layout := false
var viewport_gate: ColorRect
var viewport_gate_label: Label
var interface_font: Font
var orientation_forced_pause := false
var last_portrait_layout := false
var last_compact_landscape_layout := false
var layout_refresh_queued := false
var orientation_probe_left := 0.0
var compact_touch_probe_left := 0.0
var last_battle_result: Dictionary = {}
var last_rewards: Dictionary = {}
var last_reward_report: Dictionary = {}
var last_growth_plan_actions: Array = []
var last_growth_plan_report: Dictionary = {}
var battle_party_ids: Array[String] = []
var relay_edit_squad := 0
var relay_edit_slot := 0
var debug_reset_armed := false
var battle_transition_active := false
# Pre-battle event modals run while the map is still the active scene. Keep a
# raw-input bridge so an embedded Web canvas cannot leave the event card
# without a responsive click, touch, Next, or Skip route.
var pre_battle_event_input_active := false
var pre_battle_event_input_panel: Control
var pre_battle_event_input_next: Button
var pre_battle_event_input_skip: Button
var pre_battle_event_advance: Callable
var pre_battle_event_resolve: Callable
# Development-only capture aid. It is armed only by the explicit DEBUG-menu
# fixture below, is consumed by the next companion contact, and never changes
# the short player-facing encounter transition in a normal or Release run.
var debug_companion_card_visual_hold := false
var transition_edge_blocked_until_msec := 0
var transition_edge_accept_count := 0
var transition_edge_reject_count := 0
var transition_edge_last_action := ""
var transition_edge_last_source := ""
var story_checkpoint_dirty := false
var story_checkpoint_save_scheduled := false
const TRANSITION_EDGE_DEBOUNCE_MSEC := 220

func _ready() -> void:
	_build_root()
	EventBus.screen_changed.connect(_show_screen)
	SaveService.load_game()
	# SaveService restores the player's normal preference after autoloads have
	# entered the tree. Re-apply the URL-only visual-QA mute here so a saved
	# audio-enabled value cannot restart BGM in the explicitly silent preview.
	SettingsService.apply_web_preview_audio_override()
	if SettingsService.web_preview_audio_forced_muted():
		AudioService.set_enabled(false)
	# A persistent save diagnostic belonged to the development shell.  Saving is
	# still atomic and reported by its own action feedback, but Release screens
	# must not expose a bottom-right implementation status.
	footer_status.visible = false
	_show_screen("TITLE")

func _build_root() -> void:
	var background := ColorRect.new()
	background.color = Color("080b12")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var background_art := TextureRect.new()
	background_art.name = "R6BackgroundArt"
	background_art.texture = load("res://assets/art/backgrounds/BG_STORY_RELAY/bg_story_relay_1920x1080.png") as Texture2D
	background_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background_art.modulate = Color(0.34, 0.42, 0.52, 0.42)
	background_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background_art)
	var background_scrim := ColorRect.new()
	background_scrim.color = Color("080b1288")
	background_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background_scrim)
	safe_margin = MarginContainer.new()
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		safe_margin.add_theme_constant_override(side, 32)
	add_child(safe_margin)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	safe_margin.add_child(content)
	get_window().size_changed.connect(_on_window_size_changed)
	_apply_safe_area()
	# Browser viewport changes do not always emit Godot's window-size signal.
	# Establish the initial responsive state now; _process also probes at a small
	# cadence so a live battle presentation can reflow without restarting it.
	last_portrait_layout = _is_portrait_layout()
	last_compact_landscape_layout = _is_compact_landscape_layout()
	footer_status = Label.new()
	footer_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer_status.modulate = Color("88a4c9")
	footer_status.text = "오프라인 탐색 기록"
	footer_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer_status.position.y = -34
	add_child(footer_status)
	theme = _make_theme()
	_build_viewport_gate()

func _make_theme() -> Theme:
	var value := Theme.new()
	var ui_scale := _responsive_control_scale()
	# The earlier subset deliberately reduced the Web payload, but it omitted
	# glyphs introduced by localized reward names.  Use the project-owned OFL
	# variable font so every Korean runtime string remains readable.
	var bundled_font := load("res://assets/fonts/NotoSansKR-VF.ttf") as Font
	if bundled_font != null:
		interface_font = bundled_font
		value.default_font = bundled_font
	value.default_font_size = roundi(28.0 * ui_scale)
	# Text-heavy Korean flows need their narrative to lead the hierarchy. Keep
	# touch targets at their existing physical size while lowering default button
	# type below body text; touch size and type size are deliberately independent.
	# Labels carry the primary reading task. Keep generic controls comfortably
	# tappable, but do not let their type compete with Korean narrative copy.
	value.set_font_size("font_size", "Button", roundi(24.0 * ui_scale))
	value.set_font_size("font_size", "Label", roundi(28.0 * ui_scale))
	value.set_color("font_color", "Label", Color("f4f7fb"))
	value.set_color("font_color", "Button", Color("f4f7fb"))
	value.set_color("font_hover_color", "Button", Color("f4f7fb"))
	value.set_color("font_pressed_color", "Button", Color("f4f7fb"))
	value.set_color("font_disabled_color", "Button", Color("8f9caf"))
	value.set_color("font_focus_color", "Button", Color("f4f7fb"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("151c2b")
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color("ffffff18")
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate()
	hover.bg_color = Color("1b2536")
	hover.border_color = Color("78e6d080")
	var pressed := normal.duplicate()
	pressed.bg_color = Color("0e1320")
	pressed.border_color = Color("78e6d0")
	pressed.content_margin_top = 13
	pressed.content_margin_bottom = 11
	var focus := normal.duplicate()
	focus.border_width_left = 2
	focus.border_width_top = 2
	focus.border_width_right = 2
	focus.border_width_bottom = 2
	focus.border_color = Color("78e6d0cc")
	var disabled := normal.duplicate()
	disabled.bg_color = Color("0e1320")
	disabled.border_color = Color("ffffff0d")
	value.set_stylebox("normal", "Button", normal)
	value.set_stylebox("hover", "Button", hover)
	value.set_stylebox("pressed", "Button", pressed)
	value.set_stylebox("focus", "Button", focus)
	value.set_stylebox("disabled", "Button", disabled)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("0e1320f2")
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.border_color = Color("ffffff18")
	panel.shadow_color = Color("00000066")
	panel.shadow_size = 12
	panel.corner_radius_top_left = 16
	panel.corner_radius_top_right = 16
	panel.corner_radius_bottom_left = 16
	panel.corner_radius_bottom_right = 16
	panel.content_margin_left = 20
	panel.content_margin_right = 20
	panel.content_margin_top = 16
	panel.content_margin_bottom = 16
	value.set_stylebox("panel", "PanelContainer", panel)
	return value

func _build_viewport_gate() -> void:
	viewport_gate = ColorRect.new()
	viewport_gate.name = "R6ViewportGate"
	viewport_gate.color = Color("05070bf2")
	viewport_gate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_gate.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport_gate.z_index = 1000
	viewport_gate.visible = false
	add_child(viewport_gate)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_gate.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(620, 260)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(column)
	var gate_title := Label.new()
	gate_title.text = "LANTERNLINE"
	gate_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if interface_font != null: gate_title.add_theme_font_override("font", interface_font)
	gate_title.add_theme_font_size_override("font_size", 40)
	gate_title.add_theme_color_override("font_color", Color("78e6d0"))
	gate_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gate_title)
	viewport_gate_label = Label.new()
	viewport_gate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	viewport_gate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# This safety screen must not inherit a platform fallback font.  Explicitly
	# bind the bundled Korean font because Web fallback chains can vary by host.
	if interface_font != null: viewport_gate_label.add_theme_font_override("font", interface_font)
	viewport_gate_label.add_theme_font_size_override("font_size", 22)
	viewport_gate_label.add_theme_color_override("font_color", Color("f4f7fb"))
	viewport_gate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(viewport_gate_label)
	_update_viewport_gate()

func _update_viewport_gate() -> void:
	# Portrait is a first-class responsive layout, not a blocked orientation.
	# Keep the node for backwards-compatible scene ownership, but it never blocks
	# input or pauses battle on a phone rotation.
	if viewport_gate != null:
		viewport_gate.visible = false
	if orientation_forced_pause:
		if battle_view != null: battle_view.paused = false
		orientation_forced_pause = false

func _on_window_size_changed() -> void:
	_refresh_responsive_shell_metrics()
	var portrait := _is_portrait_layout()
	_queue_orientation_reflow_if_needed(portrait, _is_compact_landscape_layout())

func _refresh_responsive_shell_metrics() -> void:
	_apply_safe_area()
	if theme != null:
		var ui_scale := _responsive_control_scale()
		theme.default_font_size = roundi(28.0 * ui_scale)
		# Keep the narrative-first hierarchy after a resize/orientation reflow.
		# Button hit targets are managed separately, so they do not need to regain
		# the old, oversized 20px type here.
		theme.set_font_size("font_size", "Button", roundi(24.0 * ui_scale))
		theme.set_font_size("font_size", "Label", roundi(28.0 * ui_scale))

func _queue_orientation_reflow_if_needed(portrait := _is_portrait_layout(), compact_landscape := _is_compact_landscape_layout()) -> void:
	if (portrait == last_portrait_layout and compact_landscape == last_compact_landscape_layout) or layout_refresh_queued:
		return
	last_portrait_layout = portrait
	last_compact_landscape_layout = compact_landscape
	layout_refresh_queued = true
	call_deferred("_refresh_orientation_layout")

func _refresh_orientation_layout() -> void:
	layout_refresh_queued = false
	# Web browsers can change innerWidth/innerHeight before forwarding Godot's
	# resize signal. Refresh the shell metrics here as well, otherwise portrait
	# font overrides remain scaled after rotating back to landscape.
	_refresh_responsive_shell_metrics()
	# The live battle simulation must never be reconstructed merely because a
	# handset rotated. Rebuild only its presentation controls around the existing
	# BattleView/Simulation so ticks, RNG, and commands remain intact.
	if current_screen == "BATTLE" and battle_view != null and battle_view.simulation != null:
		_rebuild_battle_overlay()
		return
	# Unlike a static menu, story rotation can happen midway through an unread
	# line or while a choice is open.  Rebuild only the presentation tree while
	# retaining the live ScenarioRunner, so portrait gets its intended readable
	# metrics without advancing, replaying, or checkpointing the narrative.
	if current_screen == "STORY" and scenario_runner != null:
		_rebuild_story_presentation()
		return
	# The chapter map stores only stable map state in AppState/SaveService, so it
	# can be rebuilt on a rotation without changing traversal, rewards, or battle
	# state. Rebuilding clears portrait-only control overrides before landscape.
	if current_screen in ["HOME", "TITLE", "RESULT", "ROSTER", "GROWTH", "CHARACTER_DETAIL", "INVENTORY", "ARCHIVE", "SETTINGS", "DEBUG", "LICENSE", "STAGE_SELECT", "STAGE_DETAIL", "FORMATION"]:
		_show_screen(current_screen)

func _is_portrait_layout() -> bool:
	var size := _runtime_layout_size()
	return size.y > size.x

func _runtime_layout_size() -> Vector2:
	var window_size := DisplayServer.window_get_size()
	var width := float(window_size.x)
	var height := float(window_size.y)
	if OS.has_feature("web"):
		var browser_width = JavaScriptBridge.eval("window.innerWidth", true)
		var browser_height = JavaScriptBridge.eval("window.innerHeight", true)
		if browser_width is int or browser_width is float: width = float(browser_width)
		if browser_height is int or browser_height is float: height = float(browser_height)
	return Vector2(maxf(1.0, width), maxf(1.0, height))

func responsive_ui_metrics_for_size(size: Vector2) -> Dictionary:
	# `canvas_items` with aspect=expand uses the smaller physical/design ratio.
	# Compact phones therefore need the inverse ratio applied to UI metrics or a
	# nominal 56 logical-pixel button can collapse to about 21 CSS px at 915x412.
	var safe_size := Vector2(maxf(1.0, size.x), maxf(1.0, size.y))
	var portrait := safe_size.y > safe_size.x
	var compact_landscape := not portrait and safe_size.x <= COMPACT_LANDSCAPE_MAX_WIDTH
	var canvas_scale := minf(safe_size.x / DESIGN_VIEWPORT_SIZE.x, safe_size.y / DESIGN_VIEWPORT_SIZE.y)
	canvas_scale = maxf(canvas_scale, 0.001)
	var ui_scale := 1.0
	if portrait:
		ui_scale = clampf(1.0 / canvas_scale, 2.8, 4.9)
	elif compact_landscape:
		ui_scale = clampf(1.0 / canvas_scale, 1.0, 3.2)
	return {
		"portrait": portrait,
		"compact_landscape": compact_landscape,
		"canvas_scale": canvas_scale,
		"ui_scale": ui_scale,
	}

func responsive_button_minimum_for_size(minimum: Vector2, size: Vector2) -> Vector2:
	var metrics := responsive_ui_metrics_for_size(size)
	var ui_scale := float(metrics.ui_scale)
	if bool(metrics.portrait):
		return Vector2(
			minf(maxf(minimum.x, MIN_TOUCH_CSS_PX) * ui_scale, 840.0),
			maxf(minimum.y, MIN_TOUCH_CSS_PX) * ui_scale
		)
	if bool(metrics.compact_landscape):
		var minimum_touch_logical := MIN_TOUCH_CSS_PX / float(metrics.canvas_scale)
		return Vector2(maxf(minimum.x, minimum_touch_logical), maxf(minimum.y, minimum_touch_logical))
	return minimum

func story_font_size_for_size(target_css_px: float, size: Vector2) -> int:
	# Story type is specified in rendered pixels, while the project is authored on
	# a 1920x1080 canvas. Convert the requested reading size back to logical pixels
	# so 1280x720 Web, compact landscape and portrait all preserve the same visual
	# hierarchy instead of inheriting the canvas shrink factor.
	var canvas_scale := float(responsive_ui_metrics_for_size(size).canvas_scale)
	return maxi(1, roundi(target_css_px / maxf(canvas_scale, 0.001)))

static func story_page_progress(commands: Array, current_command_index: int) -> Vector2i:
	# A "page" is a player-facing text card, not an internal art/audio command.
	# This keeps the footer stable when the runner consumes several presentation
	# commands between two pieces of readable copy.
	var current_page := 0
	var total_pages := 0
	for command_index in range(commands.size()):
		var command: Dictionary = commands[command_index]
		if str(command.get("command", "")) not in ["dialogue", "narration", "choice"]:
			continue
		total_pages += 1
		if command_index <= current_command_index:
			current_page = total_pages
	return Vector2i(current_page, total_pages)

func _story_logical_px(target_css_px: float) -> int:
	return story_font_size_for_size(target_css_px, _runtime_layout_size())

func _story_weighted_font(weight: float, embolden: float = 0.0) -> Font:
	if interface_font == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = interface_font
	variation.variation_opentype = {"wght": weight}
	variation.variation_embolden = embolden
	return variation

func _is_compact_landscape_layout() -> bool:
	return bool(responsive_ui_metrics_for_size(_runtime_layout_size()).compact_landscape)

func _portrait_ui_scale() -> float:
	var metrics := responsive_ui_metrics_for_size(_runtime_layout_size())
	return float(metrics.ui_scale) if bool(metrics.portrait) else 1.0

func _responsive_control_scale() -> float:
	return float(responsive_ui_metrics_for_size(_runtime_layout_size()).ui_scale)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveService.save_game()

func _unhandled_key_input(event: InputEvent) -> void:
	if current_screen != "STORY" or not _is_story_advance_key_event(event): return
	get_viewport().set_input_as_handled()
	AudioService.unlock_from_user_gesture()
	_request_story_advance("keyboard:%d" % int((event as InputEventKey).keycode))

func _input(event: InputEvent) -> void:
	if not pre_battle_event_input_active:
		return
	var pressed := false
	var position := Vector2(-1, -1)
	if event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		position = event.position
	elif event is InputEventScreenTouch:
		pressed = event.pressed
		position = event.position
	if not pressed or not _handle_pre_battle_event_input(position):
		return
	AudioService.unlock_from_user_gesture()
	get_viewport().set_input_as_handled()

func _handle_pre_battle_event_input(position: Vector2) -> bool:
	if not pre_battle_event_input_active or pre_battle_event_input_panel == null or not is_instance_valid(pre_battle_event_input_panel):
		return false
	if not pre_battle_event_input_panel.get_global_rect().has_point(position):
		return false
	if pre_battle_event_input_skip != null and is_instance_valid(pre_battle_event_input_skip) and pre_battle_event_input_skip.get_global_rect().has_point(position):
		if pre_battle_event_resolve.is_valid():
			pre_battle_event_resolve.call()
		return true
	if pre_battle_event_input_next != null and is_instance_valid(pre_battle_event_input_next) and pre_battle_event_input_next.get_global_rect().has_point(position):
		if pre_battle_event_advance.is_valid():
			pre_battle_event_advance.call()
		return true
	if pre_battle_event_advance.is_valid():
		pre_battle_event_advance.call()
	return true

func _is_story_advance_key_event(event: InputEvent) -> bool:
	if not event is InputEventKey: return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo: return false
	return key_event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]

func _consume_transition_edge(action: String, source: String, now_msec := -1) -> bool:
	var edge_time := Time.get_ticks_msec() if now_msec < 0 else now_msec
	if edge_time < transition_edge_blocked_until_msec:
		transition_edge_reject_count += 1
		return false
	transition_edge_blocked_until_msec = edge_time + TRANSITION_EDGE_DEBOUNCE_MSEC
	transition_edge_accept_count += 1
	transition_edge_last_action = action
	transition_edge_last_source = source
	return true

func transition_edge_diagnostics() -> Dictionary:
	return {
		"accepted": transition_edge_accept_count,
		"rejected": transition_edge_reject_count,
		"last_action": transition_edge_last_action,
		"last_source": transition_edge_last_source,
		"blocked_until_msec": transition_edge_blocked_until_msec,
		"debounce_msec": TRANSITION_EDGE_DEBOUNCE_MSEC,
	}

func _apply_safe_area() -> void:
	if safe_margin == null: return
	_update_viewport_gate()
	# The footer sits outside the content MarginContainer. Give it the same
	# portrait-safe clearance as the top/header area so it cannot overlap the
	# bottom action row or a device gesture zone.
	if footer_status != null:
		footer_status.position.y = -roundf(34.0 * _portrait_ui_scale()) if _is_portrait_layout() else -34.0
		footer_status.add_theme_font_size_override("font_size", roundi(16.0 * _portrait_ui_scale()))
	var window_size := DisplayServer.window_get_size()
	var area := DisplayServer.get_display_safe_area()
	var responsive_mobile := _is_portrait_layout() or _is_compact_landscape_layout()
	var base_margin := roundi(18.0 * _responsive_control_scale()) if responsive_mobile else 32
	if window_size.x <= 0 or window_size.y <= 0 or area.size.x <= 0 or area.size.y <= 0:
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]: safe_margin.add_theme_constant_override(side, base_margin)
		return
	var scale_x := 1920.0 / window_size.x
	var scale_y := 1080.0 / window_size.y
	safe_margin.add_theme_constant_override("margin_left", maxi(base_margin, int(area.position.x * scale_x)))
	safe_margin.add_theme_constant_override("margin_top", maxi(base_margin, int(area.position.y * scale_y)))
	safe_margin.add_theme_constant_override("margin_right", maxi(base_margin, int((window_size.x - area.end.x) * scale_x)))
	safe_margin.add_theme_constant_override("margin_bottom", maxi(base_margin, int((window_size.y - area.end.y) * scale_y)))

func _process(delta: float) -> void:
	# Some mobile Web engines update window.innerWidth/innerHeight without
	# forwarding a Godot resize event. Poll infrequently to avoid per-frame JS
	# bridge work while still preserving the current battle simulation.
	orientation_probe_left -= delta
	if orientation_probe_left <= 0.0:
		orientation_probe_left = 0.25
		_queue_orientation_reflow_if_needed()
	compact_touch_probe_left -= delta
	if compact_touch_probe_left <= 0.0:
		compact_touch_probe_left = 0.25
		# ChapterMapScreen owns its own button factory and can reapply compact
		# layout metrics after node selection. Reassert the shell-wide physical
		# touch contract without changing map gameplay or focus order.
		if _is_compact_landscape_layout() and content != null:
			_apply_compact_touch_targets(content)
		_apply_chapter_map_shell_overrides()
	if current_screen == "STORY" and story_auto and scenario_runner != null and not scenario_runner.state.waiting_for_choice and not AudioService.voice_is_playing():
		story_auto_left -= delta
		if story_auto_left <= 0:
			_advance_story()
	if current_screen == "BATTLE" and battle_view != null and battle_view.simulation != null:
		_update_battle_hud()

func _clear() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	battle_view = null
	battle_hud = null
	ultimate_buttons.clear()
	party_status_labels.clear()
	battle_auto_button = null
	battle_skip_button = null
	battle_speed_button = null
	battle_pause_panel = null
	battle_pause_center = null
	battle_portrait_layout = false
	story_background = null
	story_portrait = null
	story_portrait_layer = null
	story_art_status = null
	story_dialogue_panel = null
	story_speaker_eyebrow = null
	story_click_hint = null
	story_page_indicator = null
	story_auto_button = null
	story_skip_button = null
	story_is_prologue = false
	active_chapter_map_screen = null

func _show_screen(screen_id: String) -> void:
	if not SceneRouter.screen_allowed(screen_id, SettingsService.is_developer_mode()):
		screen_id = "HOME"
		SceneRouter.current_screen = "HOME"
		AppState.route_payload = {}
	current_screen = screen_id
	_clear()
	match screen_id:
		"TITLE": _show_title()
		"HOME": _show_home()
		"STORY": _show_story()
		"FORMATION": _show_formation()
		"RELAY": _show_relay()
		"STAGE_SELECT": _show_chapter_map()
		"STAGE_LIST_FALLBACK": _show_stage_select()
		"STAGE_DETAIL": _show_stage_detail()
		"BATTLE": _show_battle()
		"RESULT": _show_result()
		"ROSTER": _show_roster()
		"GROWTH", "CHARACTER_DETAIL": _show_growth()
		"INVENTORY": _show_inventory()
		"ARCHIVE": _show_archive()
		"SETTINGS": _show_settings()
		"DEBUG": _show_debug()
		"LICENSE": _show_license()
		_: _show_home()
	_apply_compact_touch_targets(content)
	_apply_chapter_map_shell_overrides()

func _title(text_value: String, subtitle := "") -> void:
	var portrait := _is_portrait_layout()
	var ui_scale := _responsive_control_scale()
	# In portrait, the back action gets its own top-bar row. A long Korean
	# chapter title must never be squeezed behind that control.
	var header: BoxContainer = VBoxContainer.new() if portrait and current_screen not in ["TITLE", "HOME"] else HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(header)
	if current_screen not in ["TITLE", "HOME"]:
		# A RESULT screen is terminal for its Battle view.  Letting generic history
		# walk back into BATTLE would construct a fresh battle from an already
		# committed transaction after visiting Growth, which is both confusing and
		# outside the map -> battle -> result authority flow.  Result exits always
		# return to the canonical chapter map; other screens retain normal history.
		header.add_child(_button("‹ 뒤로", _navigate_back_from_header, false, Vector2(104 if portrait else 120, 54 if portrait else 60)))
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(labels)
	var title_label := Label.new()
	title_label.text = text_value
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.custom_minimum_size.x = 0.0
	title_label.add_theme_font_size_override("font_size", roundi((34.0 if portrait else 42.0) * ui_scale))
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels.add_child(title_label)
	if subtitle != "":
		var sub := Label.new()
		sub.text = subtitle
		sub.modulate = Color("91aac8")
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		labels.add_child(sub)
	var accent := ColorRect.new()
	accent.color = Color("57d4c1")
	accent.custom_minimum_size = Vector2(0, 3)
	accent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(accent)

func _navigate_back_from_header() -> void:
	if current_screen == "RESULT":
		SceneRouter.go("STAGE_SELECT")
	else:
		SceneRouter.back("HOME")

func _button(text_value: String, callback: Callable, disabled := false, minimum := Vector2(190, 64)) -> Button:
	var button := Button.new()
	button.text = text_value
	var metrics := responsive_ui_metrics_for_size(_runtime_layout_size())
	button.custom_minimum_size = responsive_button_minimum_for_size(minimum, _runtime_layout_size())
	if bool(metrics.portrait) or bool(metrics.compact_landscape):
		button.add_theme_font_size_override("font_size", roundi(19.0 * float(metrics.ui_scale)))
	button.disabled = disabled
	# WebAudio must be resumed in the same call stack as a real button press.
	# Keeping this wrapper at the shared button factory covers title, map,
	# formation, growth and settings without duplicating platform branches.
	button.pressed.connect(func():
		AudioService.unlock_from_user_gesture()
		callback.call()
	)
	return button

func _apply_compact_touch_targets(root: Node) -> void:
	if root == null or not _is_compact_landscape_layout(): return
	var metrics := responsive_ui_metrics_for_size(_runtime_layout_size())
	var minimum_touch_logical := MIN_TOUCH_CSS_PX / float(metrics.canvas_scale)
	# Touch accessibility is determined by the physical hit box, not oversized
	# lettering. This cap lets dense story controls stay secondary on compact Web
	# viewports while preserving the 56 CSS-pixel touch target.
	var minimum_font_logical := roundi(18.0 * float(metrics.ui_scale))
	_apply_compact_touch_targets_recursive(root, minimum_touch_logical, minimum_font_logical)

func _apply_compact_touch_targets_recursive(root: Node, minimum_touch_logical: float, minimum_font_logical: int) -> void:
	for child in root.get_children():
		# The 3D chapter world can contain hundreds of render nodes but no screen
		# controls. Avoid walking it every responsive probe; map overlay buttons are
		# siblings of the SubViewport and remain covered by this traversal.
		if child is SubViewport:
			continue
		if child is Button:
			var button := child as Button
			var current := button.custom_minimum_size
			var target := Vector2(maxf(current.x, minimum_touch_logical), maxf(current.y, minimum_touch_logical))
			if not current.is_equal_approx(target):
				button.custom_minimum_size = target
			# Story controls have their own deliberately quieter type scale.  Their
			# physical target is still enlarged above, so never re-inflate that type
			# just because the viewport happens to be a compact landscape one.
			if not button.has_meta("story_control"):
				var current_font := button.get_theme_font_size("font_size")
				if current_font < minimum_font_logical:
					button.add_theme_font_size_override("font_size", minimum_font_logical)
		_apply_compact_touch_targets_recursive(child, minimum_touch_logical, minimum_font_logical)

func _story_button(text_value: String, callback: Callable, disabled := false, minimum := Vector2(190, 58)) -> Button:
	var button := _button(text_value, callback, disabled, minimum)
	# Story controls are secondary navigation, not the line the player came to
	# read. Their generous physical hit area remains untouched, while the type
	# stays clearly subordinate to a Korean narration line on every canvas scale.
	button.set_meta("story_control", true)
	button.add_theme_font_size_override("font_size", _story_logical_px(17.0))
	return button

func _apply_chapter_map_shell_overrides() -> void:
	if active_chapter_map_screen == null or not is_instance_valid(active_chapter_map_screen): return
	var status_value = active_chapter_map_screen.get("status_label")
	var next_value = active_chapter_map_screen.get("next_encounter_button")
	if not status_value is Label or not next_value is Button: return
	var status := status_value as Label
	var next_button := next_value as Button
	var metrics := responsive_ui_metrics_for_size(_runtime_layout_size())
	if bool(metrics.portrait):
		var ui_scale := float(metrics.ui_scale)
		var touch_height := MIN_TOUCH_CSS_PX * ui_scale
		next_button.offset_bottom = next_button.offset_top + touch_height
		next_button.custom_minimum_size.y = maxf(next_button.custom_minimum_size.y, touch_height)
		# Keep the chapter status on a separate visual line below the top-right
		# encounter shortcut. At 390px the former 350px status and 188px button
		# geometrically overlapped over most of their text.
		status.position.y = (14.0 + MIN_TOUCH_CSS_PX + 8.0) * ui_scale
		return
	if bool(metrics.compact_landscape):
		var compact_touch_height := MIN_TOUCH_CSS_PX / float(metrics.canvas_scale)
		next_button.offset_bottom = next_button.offset_top + compact_touch_height
		next_button.custom_minimum_size.y = maxf(next_button.custom_minimum_size.y, compact_touch_height)

func _make_primary_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("78e6d0")
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color("c8fff4")
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate()
	hover.bg_color = Color("9af0de")
	var pressed := normal.duplicate()
	pressed.bg_color = Color("5cc9b5")
	pressed.content_margin_top = 13
	pressed.content_margin_bottom = 11
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color("080b12"))
	button.add_theme_color_override("font_hover_color", Color("080b12"))
	button.add_theme_color_override("font_pressed_color", Color("080b12"))

func _label(text_value: String, size_value := 21, color := Color("dcecff")) -> Label:
	var value := Label.new()
	value.text = text_value
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_font_size_override("font_size", roundi(float(size_value) * _responsive_control_scale()))
	value.modulate = color
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return value

func _panel() -> VBoxContainer:
	return _panel_box(content)

func _panel_box(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box

func _asset_texture(asset_id: String) -> Texture2D:
	var path := AssetRegistry.resolve(asset_id)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func story_art_texture_for_state(cg_asset_id: String, background_asset_id: String) -> Texture2D:
	# A CG is the preferred story image, but a missing/import-failed CG must never
	# turn an authored story beat into an empty black presentation band.  The
	# scenario background is the deterministic visual fallback and does not alter
	# any scenario, save, or progression authority.
	var cg_texture := _asset_texture(cg_asset_id) if not cg_asset_id.is_empty() else null
	if cg_texture != null:
		return cg_texture
	return _asset_texture(background_asset_id)

func _apply_skill_icon(button: Button, skill: Dictionary, max_width: int) -> void:
	var icon_asset_id := str(skill.get("icon_asset_id", ""))
	var icon_texture := _asset_texture(icon_asset_id)
	if icon_texture == null:
		return
	button.icon = icon_texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", max_width)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = "%s · %s" % [LocalizationService.tr_key(str(skill.get("name_key", ""))), str(skill.get("effect", ""))]

func _character_art_frame_style() -> StyleBoxFlat:
	# The Web fallback-safe opaque CHR002 delivery derivative and all transparent
	# legacy art share this same presentation card.  This is deliberately a UI
	# contract, not a per-character backdrop, so the lineup cannot look like a
	# mixture of cutouts and temporary blue image tiles.
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.018, 0.035, 0.075, 1.0)
	frame.border_width_left = 1
	frame.border_width_top = 1
	frame.border_width_right = 1
	frame.border_width_bottom = 1
	frame.border_color = Color("77d8d442")
	frame.corner_radius_top_left = 8
	frame.corner_radius_top_right = 8
	frame.corner_radius_bottom_left = 8
	frame.corner_radius_bottom_right = 8
	frame.content_margin_left = 4
	frame.content_margin_right = 4
	frame.content_margin_top = 4
	frame.content_margin_bottom = 4
	return frame

func _art_rect(asset_id: String, minimum: Vector2, mode := TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = minimum * _portrait_ui_scale()
	frame.add_theme_stylebox_override("panel", _character_art_frame_style())
	var art := TextureRect.new()
	art.texture = _asset_texture(asset_id)
	# Art cards are content controls too. Without this scale a 260 px portrait
	# card collapses to roughly 50 physical pixels on the retained 1920 canvas.
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = mode
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)
	return frame

func _format_counts(values: Dictionary, bullet := true) -> String:
	if values.is_empty(): return "없음"
	var keys := values.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append(("• " if bullet else "") + "%s  ×%s" % [_display_runtime_name(str(key)), MathUtil.comma(int(values[key]))])
	return "\n".join(parts) if bullet else "   ".join(parts)

func _format_stats(values: Dictionary) -> String:
	var keys := ["HP", "ATK", "DEF", "ACC", "EVA", "CRIT", "HEAL_POWER", "HASTE"]
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s %s" % [key, MathUtil.comma(int(values.get(key, 0)))])
	return "   ".join(parts.slice(0, 4)) + "\n" + "   ".join(parts.slice(4, 8))

func _format_stage_waves(waves: Array) -> String:
	var lines: Array[String] = []
	for index in range(waves.size()):
		var counts: Dictionary = {}
		for enemy_id in waves[index]:
			counts[str(enemy_id)] = int(counts.get(str(enemy_id), 0)) + 1
		lines.append("WAVE %d   %s" % [index + 1, _format_counts(counts, false)])
	return "\n".join(lines)

func _format_reward_entries(entries: Array) -> String:
	if entries.is_empty(): return "없음"
	var lines: Array[String] = []
	for entry in entries:
		var amount := int(entry.get("quantity", entry.get("min", 1)))
		var amount_max := int(entry.get("max", amount))
		var amount_text := "×%d" % amount if amount == amount_max else "×%d~%d" % [amount, amount_max]
		var chance_text := ""
		if entry.has("chance"): chance_text = "  %d%%" % roundi(float(entry.chance) * 100.0)
		lines.append("• %s  %s%s" % [_display_item_name(str(entry.get("item_id", "UNKNOWN"))), amount_text, chance_text])
	return "\n".join(lines)

func _scroll_box() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	return box

func _show_title() -> void:
	AudioService.play_bgm("audio_bgm_title_en")
	var portrait := _is_portrait_layout()
	# Portrait is a composed title canvas, not a desktop title squeezed into a
	# handset.  The canvas itself still uses the project-wide 1920×1080 logical
	# surface, so every authored title metric below is converted back to the
	# intended CSS-like physical size before it is presented on a phone.
	var portrait_scale := _portrait_ui_scale() if portrait else 1.0
	var stage := Control.new()
	stage.name = "CommercialTitleStage"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Leave a deliberate lower breathing zone on a 390×844 class display rather
	# than forcing the title to consume every safe pixel and create a scrollable
	# first impression.
	stage.custom_minimum_size.y = (680.0 if portrait else 720.0) * portrait_scale
	stage.clip_contents = true
	content.add_child(stage)
	var cast_plate := TextureRect.new()
	cast_plate.name = "TitleBackdropPlate"
	cast_plate.texture = load("res://assets/art/title/title_cast_plate_portrait_r1.png" if portrait else "res://assets/art/title/title_cast_plate_r1.png") as Texture2D
	cast_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cast_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cast_plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# The legacy portrait plate contains intentionally edge-cropped figures. It
	# remains as atmospheric scenery, but must not be the readable cast layer on
	# a narrow screen; the two whole-character plates below own that role.
	cast_plate.modulate = Color(0.42, 0.48, 0.58, 0.34) if portrait else Color.WHITE
	cast_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(cast_plate)
	var center_scrim := ColorRect.new()
	center_scrim.color = Color("020712b3") if portrait else Color("02071224")
	center_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(center_scrim)
	if portrait:
		# Keep both lead characters completely inside a 390×844-class safe frame.
		# Their scale is deliberately subordinate to the start action, while the
		# equal side insets make the composition survive narrow browser gutters.
		# The title is a non-combat surface: use the canonical 8-head portraits,
		# never the legacy compact cards which may contain SD placeholders.
		var left_cast := _portrait_title_cast_member("PortraitTitleCastLeft", "res://assets/runtime_web/characters/CHR008/portrait.png", false, portrait_scale)
		stage.add_child(left_cast)
		var right_cast := _portrait_title_cast_member("PortraitTitleCastRight", "res://assets/runtime_web/characters/CHR001/portrait.png", true, portrait_scale)
		stage.add_child(right_cast)
	var logo := TextureRect.new()
	logo.name = "FantasyTitleLogo"
	logo.texture = load("res://assets/art/title/title_logo_r1.png") as Texture2D
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_preset(Control.PRESET_CENTER)
	# The prior portrait logo used desktop logical pixels and therefore rendered
	# as a small, low-contrast stamp.  Target a 300px-wide title mark that still
	# leaves the center clear of the full-body cast plate.
	logo.size = Vector2(300.0, 84.0) * portrait_scale if portrait else Vector2(1120, 300)
	logo.position = -logo.size * 0.5 + (Vector2(0.0, -134.0) * portrait_scale if portrait else Vector2(0, -165))
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(logo)
	var cta := VBoxContainer.new()
	cta.name = "TitleCallToAction"
	cta.alignment = BoxContainer.ALIGNMENT_CENTER
	cta.add_theme_constant_override("separation", roundi(14.0 * portrait_scale) if portrait else 14)
	cta.set_anchors_preset(Control.PRESET_CENTER)
	cta.size = Vector2(330.0, 208.0) * portrait_scale if portrait else Vector2(620, 230)
	cta.position = -cta.size * 0.5 + (Vector2(0.0, 138.0) * portrait_scale if portrait else Vector2(0, 192))
	stage.add_child(cta)
	var notice_copy := "턴제 탐험 · 실시간 SD 전투" if portrait else "프롤로그 · 제1장 · 제2장 탐색 / 실시간 SD 전투"
	# `_label` already converts physical target type to the authored 1920px
	# canvas. Passing the portrait scale here a second time turns this quiet
	# support line into the largest object on a phone title screen.
	var notice := _label(notice_copy, 20 if portrait else 22, Color("d8e9e7"))
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_constant_override("outline_size", 4)
	notice.add_theme_color_override("font_outline_color", Color("06101c"))
	cta.add_child(notice)
	var start := _button("START GAME  ·  기록 시작", _start_title_flow, false, Vector2(430, 88))
	_make_title_start_button(start)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.add_theme_font_size_override("font_size", roundi(23.0 * portrait_scale) if portrait else 25)
	cta.add_child(start)
	var guide := _label("TAP TO BEGIN" if portrait else "CLICK / TOUCH TO BEGIN", 15 if portrait else 16, Color("d3ad63"))
	guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cta.add_child(guide)

func _portrait_title_cast_member(node_name: String, texture_path: String, align_right: bool, portrait_scale: float) -> TextureRect:
	var cast_member := TextureRect.new()
	cast_member.name = node_name
	cast_member.texture = load(texture_path) as Texture2D
	cast_member.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cast_member.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# 126×252 CSS px intentionally fits an entire 2:3 character with a 12px
	# exterior safety inset. The CTA remains the central, unobstructed action.
	cast_member.size = Vector2(126.0, 252.0) * portrait_scale
	cast_member.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT if align_right else Control.PRESET_BOTTOM_LEFT)
	cast_member.position = Vector2(
		-(cast_member.size.x + 12.0 * portrait_scale) if align_right else 12.0 * portrait_scale,
		-(cast_member.size.y + 14.0 * portrait_scale)
	)
	cast_member.modulate = Color(1.0, 1.0, 1.0, 0.94)
	cast_member.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cast_member

func _start_title_flow() -> void:
	AppState.profile.tutorial_progress.title_seen = true
	# A completed prologue should not replay on every launch. An unfinished first
	# run resumes its saved line, while a fresh profile enters the authored
	# click-through prologue before the home screen.
	if bool(AppState.profile.story_flags.get("PROLOGUE_READ", false)):
		SceneRouter.go("HOME")
		return
	AppState.active_scenario_id = "SCN_PROLOGUE"
	SceneRouter.go("STORY", {"after": "HOME", "origin": "TITLE"})

func _make_title_start_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("07101eea")
	normal.border_color = Color("e3b862")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.shadow_color = Color("000000aa")
	normal.shadow_size = 12
	normal.content_margin_top = 16
	normal.content_margin_bottom = 16
	normal.content_margin_left = 28
	normal.content_margin_right = 28
	var hover := normal.duplicate()
	hover.bg_color = Color("18273aeF")
	hover.border_color = Color("ffe0a0")
	var pressed := normal.duplicate()
	pressed.bg_color = Color("030812f2")
	pressed.border_color = Color("78e6d0")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color("fff0c4"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("9df6e4"))
	button.add_theme_constant_override("outline_size", 2)
	button.add_theme_color_override("font_outline_color", Color("271407"))

func _show_home() -> void:
	AudioService.play_bgm("audio_bgm_lobby")
	AppState.refresh_stamina()
	_title("랜턴라인 본부", "오프라인 싱글플레이 버티컬 슬라이스")
	var resource_bar := _panel()
	resource_bar.add_child(_label("계정 Lv.%d   작전력 %d/%d   크레딧 %s" % [AppState.profile.account.level, AppState.profile.account.stamina, AppState.account_max_stamina(), MathUtil.comma(AppState.inventory_count("CREDIT"))], 28, Color("ffe28a")))
	var portrait := _is_portrait_layout()
	var body: BoxContainer = VBoxContainer.new() if portrait else HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	content.add_child(body)
	var menu := GridContainer.new()
	menu.columns = 2 if portrait else 3
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(menu)
	# Four portrait rows must leave room for the featured character and the
	# persistent save action.  72 physical px remains comfortably above the
	# 56 logical-px touch target while avoiding a clipped last row.
	var menu_height := 72.0 if portrait else 108.0
	menu.add_child(_button("메인 스토리", func(): AppState.active_scenario_id = "SCN_PROLOGUE"; SceneRouter.go("STORY", {"after": "HOME"}), false, Vector2(235, menu_height)))
	menu.add_child(_button("챕터 / 스테이지", func(): SceneRouter.go("STAGE_SELECT"), false, Vector2(235, menu_height)))
	menu.add_child(_button("릴레이 작전", func(): SceneRouter.go("RELAY"), false, Vector2(235, menu_height)))
	menu.add_child(_button("파티 편성", func(): SceneRouter.go("FORMATION"), false, Vector2(235, menu_height)))
	menu.add_child(_button("캐릭터 / 성장", func(): SceneRouter.go("ROSTER"), false, Vector2(235, menu_height)))
	menu.add_child(_button("인벤토리", func(): SceneRouter.go("INVENTORY"), false, Vector2(235, menu_height)))
	menu.add_child(_button("스토리 아카이브", func(): SceneRouter.go("ARCHIVE"), false, Vector2(235, menu_height)))
	menu.add_child(_button("설정 / 라이선스", func(): SceneRouter.go("SETTINGS"), false, Vector2(235, menu_height)))
	menu.add_child(_button("개발자 도구", func(): SceneRouter.go("DEBUG"), not SettingsService.is_developer_mode(), Vector2(235, menu_height)))
	var pilot := PanelContainer.new()
	pilot.custom_minimum_size = Vector2(0, (140.0 if portrait else 430.0) * _portrait_ui_scale())
	body.add_child(pilot)
	var pilot_box: BoxContainer = HBoxContainer.new() if portrait else VBoxContainer.new()
	pilot_box.add_theme_constant_override("separation", 12)
	pilot.add_child(pilot_box)
	var featured := DataRegistry.character("CHR001")
	var featured_art := _art_rect(str(featured.portrait_asset_id), Vector2(118 if portrait else 320, 116 if portrait else 340))
	pilot_box.add_child(featured_art)
	var featured_copy: BoxContainer = VBoxContainer.new()
	featured_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	featured_copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if portrait: pilot_box.add_child(featured_copy)
	var featured_name := _label(LocalizationService.tr_key(featured.name_key), 25, Color("78e6d0"))
	featured_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(featured_copy if portrait else pilot_box).add_child(featured_name)
	var featured_role := _label("%s • %s" % [featured.role, featured.preferred_position], 17, Color("a8b7ff"))
	featured_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(featured_copy if portrait else pilot_box).add_child(featured_role)
	var row: BoxContainer = VBoxContainer.new() if portrait else HBoxContainer.new()
	content.add_child(row)
	row.add_child(_button("즉시 저장", func(): _report_result(SaveService.save_game()), false, Vector2(180, 58)))
	var party_names: Array[String] = []
	for character_id in AppState.get_party():
		party_names.append(_display_character_name(str(character_id)))
	row.add_child(_label("현재 파티: " + ", ".join(party_names), 18, Color("8ba8c8")))

func _show_relay() -> void:
	AudioService.play_bgm("audio_bgm_lobby")
	var specification := RelayServiceScript.first_spec()
	if specification.is_empty():
		_title("릴레이 작전", "계약 데이터가 없습니다.")
		content.add_child(_label("릴레이 계약 데이터 검증 실패", 24, Color("ff7f8a")))
		return
	var relay_id := str(specification.get("id", ""))
	var active := RelayServiceScript.active_run(AppState.profile)
	_title("삼중 노선 릴레이", str(specification.get("subtitle", "기존 전투를 연속 작전으로 재구성합니다.")))
	var scroll := _scroll_box()
	if not active.is_empty():
		_show_relay_active_run(scroll, specification, active)
		return
	_show_relay_draft(scroll, specification)
	var completion := RelayServiceScript.completion_summary(AppState.profile, relay_id)
	if not completion.is_empty():
		var completed_box := _panel_box(scroll)
		completed_box.add_child(_label("완료 기록  ·  최고 등급 %s  ·  완주 %d회" % [str(completion.get("best_grade", "B")), int(completion.get("runs_completed", 0))], 22, Color("9cf2df")))
		completed_box.add_child(_label("첫 완주 보상은 한 번만 지급됩니다. 재도전은 편성·기록 갱신용입니다.", 17, Color("9fb2ca")))

func _show_relay_draft(parent: VBoxContainer, specification: Dictionary) -> void:
	var unlocked_count := RelayServiceScript.unlocked_character_ids(AppState.profile).size()
	var draft_box := _panel_box(parent)
	draft_box.add_child(_label("계약 편성  ·  해금 동료 %d / 15명 필요" % unlocked_count, 25, Color("f1d77a")))
	draft_box.add_child(_label("세 부대의 15명은 전부 달라야 합니다. 각 구간 승리 후 그 부대는 잠기며, 패배하면 현재 구간만 다시 도전합니다.", 18, Color("cdd9e9")))
	var quick_actions := HBoxContainer.new()
	draft_box.add_child(quick_actions)
	quick_actions.add_child(_button("15명 자동 편성", func():
		if RelayServiceScript.autofill_draft(AppState.profile):
			SaveService.save_game()
			_show_screen("RELAY")
		else:
			footer_status.text = "릴레이에는 해금 동료 15명이 필요합니다."
	, unlocked_count < 15, Vector2(230, 58)))
	quick_actions.add_child(_button("편성 초기화", func():
		AppState.profile.relay.draft_squads = [[], [], []]
		SaveService.save_game()
		_show_screen("RELAY")
	, false, Vector2(190, 58)))
	var squads := RelayServiceScript.draft_squads(AppState.profile)
	for squad_index in range(RelayServiceScript.SQUAD_COUNT):
		var squad_box := _panel_box(parent)
		var selected_mark := "  ◀ 선택" if relay_edit_squad == squad_index else ""
		squad_box.add_child(_label("%d부대%s" % [squad_index + 1, selected_mark], 23, Color("78e6d0") if relay_edit_squad == squad_index else Color("a8b7ff")))
		var slots := GridContainer.new()
		slots.columns = 1 if _is_portrait_layout() else 5
		squad_box.add_child(slots)
		var squad: Array = squads[squad_index]
		for slot_index in range(RelayServiceScript.SQUAD_SIZE):
			var character_id := str(squad[slot_index]) if slot_index < squad.size() else ""
			var character := DataRegistry.character(character_id)
			var slot_text := "SLOT %d\n%s" % [slot_index + 1, _display_character_name(character_id) if not character.is_empty() else "선택 필요"]
			var is_selected := relay_edit_squad == squad_index and relay_edit_slot == slot_index
			slots.add_child(_button(slot_text, func(s := squad_index, p := slot_index): relay_edit_squad = s; relay_edit_slot = p; _show_screen("RELAY"), false, Vector2(180, 76)))
	var roster_box := _panel_box(parent)
	roster_box.add_child(_label("%d부대 · 슬롯 %d 선택" % [relay_edit_squad + 1, relay_edit_slot + 1], 22, Color("f1d77a")))
	roster_box.add_child(_label("이미 다른 릴레이 부대에 있는 동료를 선택하면 그 기존 슬롯은 비워집니다.", 17, Color("9fb2ca")))
	var roster_grid := GridContainer.new()
	roster_grid.columns = 2 if _is_portrait_layout() else 5
	roster_box.add_child(roster_grid)
	for character_id in RelayServiceScript.unlocked_character_ids(AppState.profile):
		var character := DataRegistry.character(character_id)
		roster_grid.add_child(_button("%s\n%s · %s" % [_display_character_name(character_id), str(character.get("role", "")), str(character.get("preferred_position", ""))], func(value := character_id):
			RelayServiceScript.set_draft_member(AppState.profile, relay_edit_squad, relay_edit_slot, value)
			SaveService.save_game()
			_show_screen("RELAY")
		, false, Vector2(190, 74)))
	var validation := RelayServiceScript.validate_squads(AppState.profile, squads)
	var ready := validation.is_empty()
	var start_box := _panel_box(parent)
	start_box.add_child(_label("계약 보상  ·  " + _format_counts(specification.get("completion_rewards", {}), false), 20, Color("9cf2df")))
	if not ready:
		start_box.add_child(_label("시작 조건: " + ", ".join(validation), 17, Color("ffbd7a")))
	var start := _button("릴레이 시작  ·  3개 구간", func(): _start_relay_contract(str(specification.get("id", ""))), not ready, Vector2(340, 72))
	_make_primary_button(start)
	start_box.add_child(start)

func _show_relay_active_run(parent: VBoxContainer, specification: Dictionary, run: Dictionary) -> void:
	var segment_index := int(run.get("segment_index", 0))
	var stage_ids: Array = specification.get("stage_ids", [])
	var progress_box := _panel_box(parent)
	progress_box.add_child(_label("작전 진행  ·  구간 %d / %d" % [segment_index + 1, stage_ids.size()], 27, Color("f1d77a")))
	progress_box.add_child(_label("현재 구간은 %s입니다. 앞선 승리 부대는 고정되며 이 화면을 닫거나 새로고침해도 저장됩니다." % _stage_display_name(RelayServiceScript.current_stage_id(AppState.profile)), 19, Color("cdd9e9")))
	var squads: Array = run.get("squads", [])
	var results: Array = run.get("segment_results", [])
	for squad_index in range(RelayServiceScript.SQUAD_COUNT):
		var squad_box := _panel_box(parent)
		var status := "현재 출전" if squad_index == segment_index else ("구간 완료 · 잠김" if squad_index < results.size() else "대기")
		squad_box.add_child(_label("%d부대 · %s" % [squad_index + 1, status], 22, Color("78e6d0") if squad_index == segment_index else Color("a8b7ff")))
		var names: Array[String] = []
		if squad_index < squads.size() and squads[squad_index] is Array:
			for character_id_value in squads[squad_index]: names.append(_display_character_name(str(character_id_value)))
		squad_box.add_child(_label(" · ".join(names), 18, Color("e8f3ff")))
		if squad_index < results.size():
			var result: Dictionary = results[squad_index]
			squad_box.add_child(_label("승리 · %.1f초 · 생존 %d" % [float(result.get("time", 0.0)), int(result.get("survivors", 0))], 16, Color("9cf2df")))
	var actions := HBoxContainer.new()
	parent.add_child(actions)
	var begin := _button("현재 구간 전투 시작", _request_relay_battle_start, false, Vector2(300, 72))
	_make_primary_button(begin)
	actions.add_child(begin)
	actions.add_child(_button("계약 포기", func(): RelayServiceScript.cancel(AppState.profile); SaveService.save_game(); _show_screen("RELAY"), false, Vector2(190, 72)))

func _start_relay_contract(relay_id: String) -> void:
	var started := RelayServiceScript.start(AppState.profile, relay_id, AppState.battle_seed + Time.get_ticks_msec())
	if not bool(started.get("ok", false)):
		footer_status.text = "릴레이 시작 실패: %s" % str(started.get("error", "UNKNOWN"))
		return
	SaveService.save_game()
	_show_screen("RELAY")

func _request_relay_battle_start() -> void:
	if battle_transition_active or not AppState.relay_active():
		return
	var stage_id := AppState.relay_current_stage_id()
	if stage_id.is_empty() or AppState.relay_current_squad().size() != RelayServiceScript.SQUAD_SIZE:
		footer_status.text = "릴레이 저장 상태가 유효하지 않습니다."
		return
	AppState.selected_stage_id = stage_id
	battle_transition_active = true
	SceneRouter.go("BATTLE")

func _show_story(reuse_runtime_state := false) -> void:
	AudioService.play_bgm("audio_bgm_story")
	var portrait := _is_portrait_layout()
	var ui_scale := _portrait_ui_scale()
	var story_header := story_header_data(AppState.active_scenario_id)
	story_is_prologue = AppState.active_scenario_id == "SCN_PROLOGUE"
	if story_is_prologue:
		_build_prologue_story_presentation(portrait, ui_scale, story_header)
	else:
		_title(str(story_header.title), str(story_header.subtitle))
		_build_standard_story_presentation(portrait, ui_scale)
	if reuse_runtime_state and scenario_runner != null:
		_refresh_story_art()
		_restore_story_view_after_reflow()
		_refresh_story_control_states()
		return
	scenario_runner = ScenarioRunner.new()
	var loaded := scenario_runner.load_scenario(AppState.active_scenario_id, true)
	if not loaded.ok:
		scenario_text.text = loaded.error
		return
	_refresh_story_art()
	story_auto_left = 1.0
	_refresh_story_control_states()
	_advance_story()

func _build_standard_story_presentation(portrait: bool, ui_scale: float) -> void:
	var stage := PanelContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(stage)
	var layer := VBoxContainer.new()
	layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(layer)
	var art_space := Control.new()
	# Compact landscape gives priority to the reading panel and keeps just enough
	# art height for the fixed 56px AUTO/SKIP rail; wide and portrait layouts retain
	# the established character presentation band.
	art_space.custom_minimum_size.y = float(_story_logical_px(76.0)) if _is_compact_landscape_layout() else (236.0 * ui_scale if portrait else 320.0)
	art_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layer.add_child(art_space)
	story_background = TextureRect.new()
	story_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	story_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	story_background.modulate = Color(.48, .58, .68, .55)
	art_space.add_child(story_background)
	story_portrait = TextureRect.new()
	story_portrait.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	story_portrait.position = Vector2(-262.0 * ui_scale, -142.0 * ui_scale) if portrait else Vector2(-500, -245)
	story_portrait.size = Vector2(262.0 * ui_scale, 304.0 * ui_scale) if portrait else Vector2(500, 500)
	story_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	story_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art_space.add_child(story_portrait)
	# Asset provenance is useful while authoring, but it is not player-facing
	# story UI.  Keep the label available only in the developer build.
	story_art_status = _label("", 16, Color("78e6d0"))
	story_art_status.visible = SettingsService.is_developer_mode()
	story_art_status.position = Vector2(18.0 * ui_scale, 16.0 * ui_scale) if portrait else Vector2(24, 20)
	story_art_status.size = Vector2(900.0 * ui_scale, 40.0 * ui_scale) if portrait else Vector2(900, 40)
	art_space.add_child(story_art_status)
	_build_story_top_right_controls(art_space, portrait, false)
	var dialogue := PanelContainer.new()
	dialogue.add_theme_stylebox_override("panel", _story_dialogue_style(false))
	layer.add_child(dialogue)
	_build_story_dialogue_content(dialogue, portrait, false)

func _build_prologue_story_presentation(portrait: bool, ui_scale: float, story_header: Dictionary) -> void:
	var stage := PanelContainer.new()
	stage.name = "PrologueCinematicStage"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_stylebox_override("panel", _prologue_stage_style())
	content.add_child(stage)
	var canvas := Control.new()
	canvas.name = "PrologueCinematicCanvas"
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(canvas)

	story_background = TextureRect.new()
	story_background.name = "PrologueBackground"
	story_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	story_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	story_background.modulate = Color(0.72, 0.82, 0.94, 0.72)
	story_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(story_background)
	var cinematic_scrim := ColorRect.new()
	cinematic_scrim.name = "PrologueCinematicScrim"
	cinematic_scrim.color = Color(0.008, 0.016, 0.045, 0.38)
	cinematic_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cinematic_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(cinematic_scrim)
	var lower_scrim := ColorRect.new()
	lower_scrim.name = "PrologueLowerScrim"
	lower_scrim.color = Color(0.006, 0.014, 0.04, 0.48)
	lower_scrim.anchor_left = 0.0
	lower_scrim.anchor_top = 0.48
	lower_scrim.anchor_right = 1.0
	lower_scrim.anchor_bottom = 1.0
	lower_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(lower_scrim)

	story_portrait_layer = Control.new()
	story_portrait_layer.name = "PrologueCharacterIllustrations"
	story_portrait_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_portrait_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(story_portrait_layer)

	var chapter_plate := PanelContainer.new()
	chapter_plate.name = "PrologueChapterPlate"
	chapter_plate.anchor_left = 0.0
	chapter_plate.anchor_top = 0.0
	chapter_plate.anchor_right = 0.0
	chapter_plate.anchor_bottom = 0.0
	chapter_plate.offset_left = float(_story_logical_px(20.0))
	chapter_plate.offset_top = float(_story_logical_px(18.0))
	chapter_plate.offset_right = float(_story_logical_px(344.0 if portrait else 506.0))
	chapter_plate.offset_bottom = float(_story_logical_px(116.0 if portrait else 88.0))
	chapter_plate.add_theme_stylebox_override("panel", _prologue_plate_style(ui_scale))
	canvas.add_child(chapter_plate)
	var chapter_copy := VBoxContainer.new()
	chapter_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chapter_plate.add_child(chapter_copy)
	var eyebrow := _label("PROLOGUE · THE LAST LINE", _story_logical_px(13.0), Color("78e6d0"))
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chapter_copy.add_child(eyebrow)
	var chapter_title := _label(str(story_header.title), _story_logical_px(30.0), Color("f4f7ff"))
	chapter_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chapter_copy.add_child(chapter_title)

	_build_story_top_right_controls(canvas, portrait, true)

	story_art_status = _label("", 14, Color("78e6d0"))
	# The cinematic opening is itself the QA target; never stamp authoring jargon
	# over the composition, even in a Development export.
	story_art_status.visible = false
	story_art_status.anchor_left = 0.0
	story_art_status.anchor_top = 0.0
	story_art_status.anchor_right = 0.0
	story_art_status.anchor_bottom = 0.0
	story_art_status.offset_left = 32.0 * ui_scale
	story_art_status.offset_top = 144.0 * ui_scale
	story_art_status.offset_right = 800.0 * ui_scale
	story_art_status.offset_bottom = 188.0 * ui_scale
	story_art_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(story_art_status)

	var dialogue_margin := MarginContainer.new()
	dialogue_margin.name = "PrologueDialogueMargin"
	dialogue_margin.anchor_left = 0.0
	dialogue_margin.anchor_top = 1.0
	dialogue_margin.anchor_right = 1.0
	dialogue_margin.anchor_bottom = 1.0
	dialogue_margin.offset_left = float(_story_logical_px(18.0 if portrait else 100.0))
	dialogue_margin.offset_top = -float(_story_logical_px(282.0))
	dialogue_margin.offset_right = -float(_story_logical_px(18.0 if portrait else 100.0))
	dialogue_margin.offset_bottom = -float(_story_logical_px(18.0))
	canvas.add_child(dialogue_margin)
	var dialogue := PanelContainer.new()
	dialogue.add_theme_stylebox_override("panel", _story_dialogue_style(true))
	dialogue_margin.add_child(dialogue)
	_build_story_dialogue_content(dialogue, portrait, true)

func _build_story_top_right_controls(parent: Control, portrait: bool, cinematic: bool) -> void:
	var runtime_size := _runtime_layout_size()
	var auto_minimum := responsive_button_minimum_for_size(Vector2(132, 64), runtime_size)
	var skip_minimum := responsive_button_minimum_for_size(Vector2(142, 64), runtime_size)
	var separation := float(_story_logical_px(10.0))
	var right_inset := float(_story_logical_px(20.0))
	var top_inset := float(_story_logical_px(126.0 if portrait and cinematic else 18.0))
	story_controls = HBoxContainer.new()
	story_controls.name = "PrologueTopRightControls" if cinematic else "StoryTopRightControls"
	story_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_controls.anchor_left = 1.0
	story_controls.anchor_top = 0.0
	story_controls.anchor_right = 1.0
	story_controls.anchor_bottom = 0.0
	story_controls.offset_left = -(auto_minimum.x + skip_minimum.x + separation + right_inset)
	story_controls.offset_top = top_inset
	story_controls.offset_right = -right_inset
	story_controls.offset_bottom = top_inset + maxf(auto_minimum.y, skip_minimum.y)
	story_controls.add_theme_constant_override("separation", roundi(separation))
	parent.add_child(story_controls)
	story_auto_button = _story_button("AUTO", _toggle_story_auto, false, Vector2(132, 64))
	story_auto_button.name = "PrologueAutoButton" if cinematic else "StoryAutoButton"
	_style_story_overlay_button(story_auto_button, Color("58d8c6"))
	story_controls.add_child(story_auto_button)
	story_skip_button = _story_button("SKIP  ▶", _skip_story_from_control, false, Vector2(142, 64))
	story_skip_button.name = "PrologueSkipButton" if cinematic else "StorySkipButton"
	_style_story_overlay_button(story_skip_button, Color("e6bd68"))
	story_controls.add_child(story_skip_button)

func _build_story_dialogue_content(dialogue: PanelContainer, portrait: bool, cinematic: bool) -> void:
	story_dialogue_panel = dialogue
	dialogue.name = "ClickablePrologueTextBox" if story_is_prologue else "ClickableStoryTextBox"
	dialogue.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	dialogue.gui_input.connect(_on_story_text_box_input)
	# AUTO/SKIP live in the fixed top-right rail. The reading surface retains only
	# the secondary navigation that is useful beside the current line.
	var compact := _is_compact_landscape_layout()
	dialogue.custom_minimum_size.y = float(_story_logical_px(244.0 if cinematic else (220.0 if compact else 284.0)))
	var dialogue_frame := HBoxContainer.new()
	dialogue_frame.name = "StoryDialogueFrame"
	dialogue_frame.add_theme_constant_override("separation", _story_logical_px(18.0))
	dialogue.add_child(dialogue_frame)
	var signal_rail := ColorRect.new()
	signal_rail.name = "StoryMintSignalRail"
	signal_rail.color = Color("5cdbc9")
	signal_rail.custom_minimum_size.x = float(_story_logical_px(3.0))
	signal_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_frame.add_child(signal_rail)
	var dialogue_box := VBoxContainer.new()
	dialogue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_box.add_theme_constant_override("separation", _story_logical_px(4.0 if compact else 8.0))
	dialogue_frame.add_child(dialogue_box)
	story_speaker_eyebrow = _label("LUMENBOUND · VOICE LINK", _story_logical_px(14.0), Color("9af2df"))
	story_speaker_eyebrow.name = "StorySpeakerEyebrow"
	story_speaker_eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_speaker_eyebrow.add_theme_color_override("font_outline_color", Color("01050a"))
	story_speaker_eyebrow.add_theme_constant_override("outline_size", _story_logical_px(1.0))
	var story_meta_font := _story_weighted_font(620.0, 0.04)
	var story_title_font := _story_weighted_font(700.0, 0.07)
	var story_body_font := _story_weighted_font(650.0, 0.07)
	if story_meta_font != null:
		story_speaker_eyebrow.add_theme_font_override("font", story_meta_font)
	dialogue_box.add_child(story_speaker_eyebrow)
	scenario_speaker = _label("", _story_logical_px(32.0), Color("f6d383"))
	scenario_speaker.add_theme_color_override("font_outline_color", Color("01050a"))
	scenario_speaker.add_theme_color_override("font_shadow_color", Color("000000b8"))
	scenario_speaker.add_theme_constant_override("outline_size", _story_logical_px(2.0))
	scenario_speaker.add_theme_constant_override("shadow_offset_x", _story_logical_px(1.0))
	scenario_speaker.add_theme_constant_override("shadow_offset_y", _story_logical_px(1.0))
	if story_title_font != null:
		scenario_speaker.add_theme_font_override("font", story_title_font)
	dialogue_box.add_child(scenario_speaker)
	scenario_text = RichTextLabel.new()
	scenario_text.bbcode_enabled = true
	scenario_text.fit_content = true
	scenario_text.scroll_active = false
	scenario_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scenario_text.custom_minimum_size.y = float(_story_logical_px(44.0 if compact else (96.0 if cinematic else 88.0)))
	scenario_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Render body copy at 28px and the speaker at 32px, independent of the authored
	# 1920x1080 canvas. These values remain inside the requested 25-30 / 28-34px
	# reading bands at 1280x720, compact landscape and portrait.
	scenario_text.add_theme_font_size_override("normal_font_size", _story_logical_px(28.0))
	scenario_text.add_theme_font_size_override("bold_font_size", _story_logical_px(28.0))
	scenario_text.add_theme_color_override("default_color", Color("fffaf0"))
	# The opaque dialogue plate already provides contrast. Preserve the full white
	# face of Korean glyphs instead of shrinking it with a dark pixel outline.
	scenario_text.add_theme_constant_override("outline_size", 0)
	scenario_text.add_theme_constant_override("shadow_offset_x", 0)
	scenario_text.add_theme_constant_override("shadow_offset_y", 0)
	scenario_text.add_theme_constant_override("line_separation", _story_logical_px(8.0))
	if story_body_font != null:
		scenario_text.add_theme_font_override("normal_font", story_body_font)
	if story_title_font != null:
		scenario_text.add_theme_font_override("bold_font", story_title_font)
	# Let the surrounding dialogue panel own click/touch progression. Choice and
	# control buttons keep their own input, so a click on a choice never advances
	# the scenario twice.
	scenario_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scenario_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.add_child(scenario_text)
	scenario_choices = VBoxContainer.new()
	scenario_choices.add_theme_constant_override("separation", _story_logical_px(8.0))
	dialogue_box.add_child(scenario_choices)
	var story_footer := HBoxContainer.new()
	story_footer.name = "StoryProgressFooter"
	story_footer.mouse_filter = Control.MOUSE_FILTER_PASS
	dialogue_box.add_child(story_footer)
	story_click_hint = _label("대화창 클릭 / 터치로 계속  >", _story_logical_px(16.0), Color("9af2df"))
	story_click_hint.name = "StoryClickAdvanceHint"
	story_click_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_click_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	story_click_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if story_meta_font != null:
		story_click_hint.add_theme_font_override("font", story_meta_font)
	story_footer.add_child(story_click_hint)
	story_page_indicator = _label("PAGE · -- / --", _story_logical_px(16.0), Color("b9d4dc"))
	story_page_indicator.name = "StoryPageIndicator"
	story_page_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	story_page_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if story_meta_font != null:
		story_page_indicator.add_theme_font_override("font", story_meta_font)
	story_footer.add_child(story_page_indicator)
	if cinematic:
		return
	var story_secondary_controls: Control = GridContainer.new() if portrait else HBoxContainer.new()
	story_secondary_controls.name = "StorySecondaryControls"
	if story_secondary_controls is GridContainer:
		(story_secondary_controls as GridContainer).columns = 2
	dialogue_box.add_child(story_secondary_controls)
	story_secondary_controls.add_child(_story_button("다음", func(): _request_story_advance("button:next"), false, Vector2(130, 58)))
	story_secondary_controls.add_child(_story_button("로그", _show_story_log, false, Vector2(110, 58)))
	story_secondary_controls.add_child(_story_button("UI 숨기기", _toggle_story_ui, false, Vector2(140, 58)))
	if SettingsService.is_developer_mode(): story_secondary_controls.add_child(_story_button("DEV 전체 스킵", _dev_skip_story, false, Vector2(160, 58)))

func _prologue_stage_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.008, 0.016, 0.042, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color("4f8ea877")
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	return style

func _prologue_plate_style(ui_scale: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.036, 0.082, 0.76)
	style.border_width_left = max(1, roundi(ui_scale))
	style.border_color = Color("62d8c8")
	style.corner_radius_top_right = roundi(12.0 * ui_scale)
	style.corner_radius_bottom_right = roundi(12.0 * ui_scale)
	style.content_margin_left = 18.0 * ui_scale
	style.content_margin_right = 20.0 * ui_scale
	style.content_margin_top = 10.0 * ui_scale
	style.content_margin_bottom = 10.0 * ui_scale
	return style

func _story_dialogue_style(cinematic: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.009, 0.021, 0.052, 0.93 if cinematic else 0.90)
	var border_width := maxi(1, _story_logical_px(1.25))
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = Color("d7b967cc")
	var radius := _story_logical_px(14.0)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = float(_story_logical_px(22.0))
	style.content_margin_right = float(_story_logical_px(24.0))
	style.content_margin_top = float(_story_logical_px(18.0))
	style.content_margin_bottom = float(_story_logical_px(16.0))
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
	style.shadow_size = _story_logical_px(8.0)
	return style

func _style_story_overlay_button(button: Button, accent: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.009, 0.025, 0.061, 0.95)
	var border_width := maxi(1, _story_logical_px(1.25))
	normal.border_width_left = border_width
	normal.border_width_top = border_width
	normal.border_width_right = border_width
	normal.border_width_bottom = border_width
	normal.border_color = accent
	var radius := _story_logical_px(9.0)
	normal.corner_radius_top_left = radius
	normal.corner_radius_top_right = radius
	normal.corner_radius_bottom_left = radius
	normal.corner_radius_bottom_right = radius
	normal.content_margin_left = float(_story_logical_px(14.0))
	normal.content_margin_right = float(_story_logical_px(14.0))
	var hover := normal.duplicate()
	hover.bg_color = Color(accent.r * 0.16, accent.g * 0.16, accent.b * 0.16, 0.96)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(accent.r * 0.24, accent.g * 0.24, accent.b * 0.24, 0.98)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_font_size_override("font_size", _story_logical_px(17.0))
	button.add_theme_color_override("font_color", Color("f4f7ff"))
	button.add_theme_color_override("font_hover_color", accent.lightened(0.28))

func _on_story_text_box_input(event: InputEvent) -> void:
	var pressed := false
	var source := ""
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		pressed = mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT
		source = "dialogue:mouse"
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
		source = "dialogue:touch"
	if not pressed:
		return
	AudioService.unlock_from_user_gesture()
	accept_event()
	_request_story_text_box_advance(source)

func _request_story_text_box_advance(source: String) -> bool:
	if current_screen != "STORY" or scenario_runner == null or scenario_runner.state.waiting_for_choice:
		return false
	# The first click completes a line that is still typing; the next click moves
	# to the following box. This keeps fast readers in control without skipping
	# an unread line accidentally.
	if scenario_text != null and scenario_text.visible_ratio < 0.999:
		scenario_text.visible_ratio = 1.0
		story_auto_left = float(SettingsService.values.auto_delay)
		return true
	return _request_story_advance(source)

func _refresh_story_dialogue_chrome(command_type: String) -> void:
	if story_speaker_eyebrow != null:
		match command_type:
			"narration": story_speaker_eyebrow.text = "LUMENBOUND · FIELD RECORD"
			"choice": story_speaker_eyebrow.text = "LUMENBOUND · RESPONSE"
			_: story_speaker_eyebrow.text = "LUMENBOUND · VOICE LINK"
	if story_click_hint != null:
		story_click_hint.text = "아래 응답을 선택해 계속" if command_type == "choice" else "대화창 클릭 / 터치로 계속  >"
	if story_page_indicator == null or scenario_runner == null:
		return
	var current_command_index := int(scenario_runner.state.current_line.get("command_index", scenario_runner.state.command_index - 1))
	var commands: Array = scenario_runner.scenario.get("commands", [])
	var progress := story_page_progress(commands, current_command_index)
	story_page_indicator.text = "PAGE · %02d / %02d" % [progress.x, progress.y] if progress.y > 0 else "PAGE · -- / --"

func _rebuild_story_presentation() -> void:
	_clear()
	_show_story(true)

func _restore_story_view_after_reflow() -> void:
	if scenario_runner == null:
		return
	var command := scenario_runner.state.current_line
	var type := str(command.get("command", ""))
	if type in ["dialogue", "narration"]:
		scenario_speaker.text = "나레이션" if type == "narration" else LocalizationService.tr_key(command.get("speaker_key", ""))
		scenario_text.text = LocalizationService.tr_key(command.get("text_key", ""))
		# A rotation is presentation-only: never restart the typewriter animation
		# or consume the remaining automatic-advance delay.
		scenario_text.visible_ratio = 1.0
	elif type == "choice" or scenario_runner.state.waiting_for_choice:
		scenario_speaker.text = "선택"
		scenario_text.text = "당신의 기록 방식을 선택하세요."
		for i in range(command.get("choices", []).size()):
			var choice: Dictionary = command.choices[i]
			scenario_choices.add_child(_story_button(LocalizationService.tr_key(choice.text_key), func(index := i): _request_story_choice(index, "button:choice"), false, Vector2(400, 58)))
	else:
		scenario_text.text = ""
	_refresh_story_dialogue_chrome("choice" if scenario_runner.state.waiting_for_choice else type)
	if story_ui_hidden:
		scenario_text.visible = false
		scenario_speaker.visible = false
		scenario_choices.visible = false
		story_speaker_eyebrow.visible = false
		story_click_hint.visible = false
		story_page_indicator.visible = false

func story_header_data(scenario_id: String) -> Dictionary:
	var scenario := DataRegistry.by_id("scenarios", scenario_id)
	var title_key := str(scenario.get("title_key", ""))
	var localized_title := LocalizationService.tr_key(title_key) if not title_key.is_empty() else LocalizationService.tr_key("UI_STORY_TITLE")
	# Stable scenario IDs are useful diagnostics, but they are content-pipeline
	# identifiers rather than player-facing episode names. Keep them exclusively
	# behind the existing developer-mode gate.
	return {
		"title": localized_title,
		"subtitle": scenario_id if SettingsService.is_developer_mode() else "",
	}

func _stage_display_name(stage_id: String) -> String:
	var stage := DataRegistry.stage(stage_id)
	if stage.is_empty():
		return "작전 기록"
	var name_key := str(stage.get("name_key", ""))
	if name_key.is_empty():
		return "작전 기록"
	return LocalizationService.tr_key(name_key).replace(" (DEV)", "")

func result_header_data(report: Dictionary) -> Dictionary:
	var source_type := str(report.get("source_type", "BATTLE"))
	var source_id := str(report.get("source_id", ""))
	if source_id.is_empty() and source_type in ["BATTLE", "SWEEP"]:
		source_id = str(AppState.selected_stage_id)
	var title := "보상 결과"
	var subtitle := "보상 정산"
	match source_type:
		"BATTLE":
			title = "전투 결과"
			subtitle = _stage_display_name(source_id)
		"SWEEP":
			title = "소탕 결과"
			subtitle = _stage_display_name(source_id)
		"TREASURE":
			title = "탐색 보상"
			subtitle = "현장 보급품 회수"
		"MAP_EVENT":
			title = "탐색 결과"
			subtitle = "탐색 기록 완료"
		"RELAY":
			title = "릴레이 구간 결과"
			var relay: Dictionary = report.get("relay", {})
			if bool(relay.get("completed", false)):
				subtitle = "계약 완주 · 등급 %s" % str(relay.get("grade", "B"))
			elif bool(relay.get("retry", false)):
				subtitle = "현재 구간 재도전 가능"
			else:
				subtitle = "다음 구간으로 편성 잠금 유지"
	if SettingsService.is_developer_mode() and not source_id.is_empty():
		subtitle += " · [%s]" % source_id
	return {"title": title, "subtitle": subtitle}

func _advance_story() -> void:
	if scenario_runner == null: return
	for choice in scenario_choices.get_children(): choice.queue_free()
	var guard := 0
	while guard < 20:
		guard += 1
		var command := scenario_runner.advance()
		_persist_story_checkpoint()
		_refresh_story_art()
		var type := str(command.get("command", ""))
		if type in ["dialogue", "narration"]:
			scenario_speaker.text = "나레이션" if type == "narration" else LocalizationService.tr_key(command.get("speaker_key", ""))
			scenario_text.text = LocalizationService.tr_key(command.get("text_key", ""))
			_refresh_story_dialogue_chrome(type)
			scenario_text.visible_ratio = 0.0
			var reveal_duration := maxf(.05, scenario_text.text.length() * float(SettingsService.values.text_speed))
			create_tween().tween_property(scenario_text, "visible_ratio", 1.0, reveal_duration)
			story_auto_left = float(SettingsService.values.auto_delay) + maxf(.5, scenario_text.text.length() * float(SettingsService.values.text_speed))
			return
		if type == "choice":
			scenario_speaker.text = "선택"
			scenario_text.text = "당신의 기록 방식을 선택하세요."
			_refresh_story_dialogue_chrome(type)
			for i in range(command.get("choices", []).size()):
				var choice: Dictionary = command.choices[i]
				scenario_choices.add_child(_button(LocalizationService.tr_key(choice.text_key), func(index := i): _request_story_choice(index, "button:choice"), false, Vector2(400, 58)))
			return
		if type == "start_battle":
			AppState.selected_stage_id = command.stage_id
			SceneRouter.go("FORMATION", {"after": "STAGE_DETAIL"})
			return
		if type == "end_scenario" or scenario_runner.state.finished:
			_finish_story_navigation()
			return
		if type in ["wait", "fade_in", "fade_out"]:
			continue
		if type == "play_voice":
			story_auto_left = 0.2
			return

func _request_story_advance(source: String) -> bool:
	if current_screen != "STORY" or scenario_runner == null or scenario_runner.state.waiting_for_choice: return false
	if not _consume_transition_edge("STORY_ADVANCE", source): return false
	_advance_story()
	return true

func _request_story_choice(index: int, source: String) -> bool:
	if current_screen != "STORY" or scenario_runner == null or not scenario_runner.state.waiting_for_choice: return false
	if not _consume_transition_edge("STORY_CHOICE", source): return false
	var chosen := scenario_runner.choose(index)
	if not chosen.ok: return false
	_persist_story_checkpoint()
	_advance_story()
	return true

func _persist_story_checkpoint() -> void:
	# ScenarioRunner owns the in-memory checkpoint.  The shell owns persistence:
	# Web tabs do not reliably deliver a close notification, so interactive lines
	# and choices must be written at their state boundary rather than only when a
	# screen is left intentionally.
	if scenario_runner == null or scenario_runner.state.scenario_id.is_empty():
		return
	if AppState.profile.last_scenario_position.has(scenario_runner.state.scenario_id):
		story_checkpoint_dirty = true
		if not story_checkpoint_save_scheduled:
			story_checkpoint_save_scheduled = true
			_flush_story_checkpoint_after_delay()

func _flush_story_checkpoint_after_delay() -> void:
	# Web file verification and atomic backup are intentionally off the physical
	# button edge. Coalesce rapid Next/SKIP presses, paint the new line first, and
	# persist one checkpoint after the short input burst.
	await get_tree().create_timer(0.24).timeout
	story_checkpoint_save_scheduled = false
	if not story_checkpoint_dirty:
		return
	story_checkpoint_dirty = false
	SaveService.save_game()

func _refresh_story_art() -> void:
	if scenario_runner == null: return
	if story_background != null:
		story_background.texture = story_art_texture_for_state(scenario_runner.state.cg_asset_id, scenario_runner.state.background_asset_id)
		story_background.visible = story_background.texture != null
	if story_is_prologue and story_portrait_layer != null:
		_refresh_prologue_portrait_layer()
	var portrait_id := ""
	if not scenario_runner.state.portraits.is_empty():
		var slots := scenario_runner.state.portraits.keys()
		var portrait_data: Dictionary = scenario_runner.state.portraits[slots[slots.size() - 1]]
		portrait_id = str(portrait_data.get("asset_id", ""))
	var portrait_path := AssetRegistry.resolve(portrait_id)
	if story_portrait != null:
		story_portrait.texture = load(portrait_path) as Texture2D if not portrait_path.is_empty() else null
		story_portrait.visible = not portrait_id.is_empty()
	if story_art_status != null:
		if SettingsService.is_developer_mode():
			story_art_status.text = "CINEMATIC PROLOGUE PREVIEW" if story_is_prologue else "ART PREVIEW"

func _refresh_prologue_portrait_layer() -> void:
	for child in story_portrait_layer.get_children():
		story_portrait_layer.remove_child(child)
		child.queue_free()
	if scenario_runner == null or scenario_runner.state.portraits.is_empty():
		return
	var current_line: Dictionary = scenario_runner.state.current_line
	var active_asset_id := _portrait_asset_for_speaker(str(current_line.get("speaker_key", "")))
	var portrait_layout := _is_portrait_layout()
	var ui_scale := _portrait_ui_scale()
	var ordered_slots := ["LEFT", "CENTER", "RIGHT"]
	for slot in scenario_runner.state.portraits.keys():
		if str(slot) not in ordered_slots:
			ordered_slots.append(str(slot))
	for slot_index in range(ordered_slots.size()):
		var slot := str(ordered_slots[slot_index])
		if not scenario_runner.state.portraits.has(slot):
			continue
		var portrait_data: Dictionary = scenario_runner.state.portraits[slot]
		var asset_id := str(portrait_data.get("asset_id", ""))
		var texture := _asset_texture(asset_id)
		if texture == null:
			continue
		var art := TextureRect.new()
		art.name = "ProloguePortrait_%s" % slot
		art.texture = texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var is_active := active_asset_id.is_empty() or active_asset_id == asset_id
		art.modulate = Color(0.88, 0.94, 1.0, 0.60 if is_active else 0.30)
		_configure_prologue_portrait_rect(art, slot, portrait_layout, ui_scale)
		story_portrait_layer.add_child(art)

func _configure_prologue_portrait_rect(art: TextureRect, slot: String, portrait_layout: bool, ui_scale: float) -> void:
	art.anchor_top = 1.0
	art.anchor_bottom = 1.0
	if portrait_layout:
		match slot:
			"LEFT":
				art.anchor_left = 0.0
				art.anchor_right = 0.0
				art.offset_left = -92.0 * ui_scale
				art.offset_right = 390.0 * ui_scale
			"RIGHT":
				art.anchor_left = 1.0
				art.anchor_right = 1.0
				art.offset_left = -390.0 * ui_scale
				art.offset_right = 92.0 * ui_scale
			_:
				art.anchor_left = 0.5
				art.anchor_right = 0.5
				art.offset_left = -246.0 * ui_scale
				art.offset_right = 246.0 * ui_scale
		art.offset_top = -900.0 * ui_scale
		art.offset_bottom = -220.0 * ui_scale
		return
	match slot:
		"LEFT":
			art.anchor_left = 0.0
			art.anchor_right = 0.0
			art.offset_left = -70.0
			art.offset_right = 700.0
		"RIGHT":
			art.anchor_left = 1.0
			art.anchor_right = 1.0
			art.offset_left = -700.0
			art.offset_right = 70.0
		_:
			art.anchor_left = 0.5
			art.anchor_right = 0.5
			art.offset_left = -385.0
			art.offset_right = 385.0
	art.offset_top = -900.0
	art.offset_bottom = 36.0

func _portrait_asset_for_speaker(speaker_key: String) -> String:
	return str({
		"SPEAKER_MAERU": "portrait_chr001_dev",
		"SPEAKER_ROAN": "portrait_chr002_dev",
		"SPEAKER_NARIN": "portrait_chr003_dev",
		"SPEAKER_EDA": "portrait_chr004_dev",
		"SPEAKER_SOREN": "portrait_chr005_dev",
		"SPEAKER_IRI": "portrait_chr008_dev",
	}.get(speaker_key, ""))

func _toggle_story_auto() -> void:
	story_auto = not story_auto
	story_auto_left = 0.45
	_refresh_story_control_states()

func _refresh_story_control_states() -> void:
	if story_auto_button != null:
		story_auto_button.text = "AUTO  ON" if story_auto else "AUTO"
		story_auto_button.add_theme_color_override("font_color", Color("8ff3e3") if story_auto else Color("f4f7ff"))
	if story_skip_button != null:
		story_skip_button.tooltip_text = "프롤로그 전체 건너뛰기" if story_is_prologue else "이미 읽은 대사 건너뛰기"

func _skip_story_from_control() -> void:
	if story_is_prologue:
		_skip_prologue_to_end()
	else:
		_skip_story()

func _skip_prologue_to_end() -> void:
	if scenario_runner == null or not _consume_transition_edge("STORY_SKIP_ALL", "button:skip-all"):
		return
	var safety := 0
	while not scenario_runner.state.finished and safety < 1000:
		safety += 1
		var command := scenario_runner.advance()
		if str(command.get("command", "")) == "choice":
			scenario_runner.choose(0)
	_persist_story_checkpoint()
	_finish_story_navigation()

func _skip_story() -> void:
	if scenario_runner != null and scenario_runner.can_skip_current(): _request_story_advance("button:skip")
	else: footer_status.text = "읽은 대사만 건너뛸 수 있습니다."

func _dev_skip_story() -> void:
	if not SettingsService.is_developer_mode() or scenario_runner == null: return
	var safety := 0
	while not scenario_runner.state.finished and safety < 1000:
		safety += 1
		var command := scenario_runner.advance()
		if command.get("command", "") == "choice": scenario_runner.choose(0)
		elif command.get("command", "") == "start_battle": continue
	_finish_story_navigation()

func _finish_story_navigation() -> void:
	# STORY is entered from the home/archive as well as the chapter-map
	# progression queue. Preserve the caller's stable return contract so a
	# mandatory post-battle scene cannot strand the player in Formation.
	var destination := str(AppState.route_payload.get("after", "FORMATION"))
	if destination not in ["HOME", "ARCHIVE", "FORMATION", "STAGE_DETAIL", "STAGE_SELECT"]:
		destination = "FORMATION"
	story_checkpoint_dirty = false
	SaveService.save_game()
	SceneRouter.go(destination, {"story_return": true})

func _show_story_log() -> void:
	if scenario_runner == null: return
	var dialog := AcceptDialog.new()
	dialog.title = "대사 로그"
	var lines: Array[String] = []
	for line in scenario_runner.state.dialogue_log:
		lines.append(LocalizationService.tr_key(line.get("speaker_key", "")) + ": " + LocalizationService.tr_key(line.get("text_key", "")))
	dialog.dialog_text = "\n\n".join(lines)
	add_child(dialog)
	dialog.popup_centered(Vector2i(980, 620))
	dialog.confirmed.connect(dialog.queue_free)

func _toggle_story_ui() -> void:
	story_ui_hidden = not story_ui_hidden
	scenario_text.visible = not story_ui_hidden
	scenario_speaker.visible = not story_ui_hidden
	scenario_choices.visible = not story_ui_hidden
	if story_speaker_eyebrow != null: story_speaker_eyebrow.visible = not story_ui_hidden
	if story_click_hint != null: story_click_hint.visible = not story_ui_hidden
	if story_page_indicator != null: story_page_indicator.visible = not story_ui_hidden
	if story_ui_hidden:
		footer_status.text = "UI 숨김 — 화면 하단 버튼으로 복구"

func _show_formation() -> void:
	_title("파티 편성", "전열 2 / 중열 2 / 후열 1 • 중복 편성 불가 • 프리셋 5개")
	var preset_row := HBoxContainer.new()
	content.add_child(preset_row)
	for i in range(5):
		preset_row.add_child(_button("PRESET %d" % (i + 1), func(index := i): AppState.profile.active_party = index; _show_screen("FORMATION"), i == int(AppState.profile.active_party), Vector2(150, 56)))
	var slots := HBoxContainer.new()
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(slots)
	var position_names := ["전열 A", "전열 B", "중열 A", "중열 B", "후열"]
	for i in range(5):
		var character := DataRegistry.character(AppState.get_party()[i])
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(220, 205)
		card.add_theme_constant_override("separation", 6)
		slots.add_child(card)
		card.add_child(_art_rect(str(character.icon_asset_id), Vector2(220, 112)))
		var marker := "◆ " if formation_slot == i else ""
		var button := _button("%s%s\n%s • %s" % [marker, position_names[i], LocalizationService.tr_key(character.name_key), character.role], func(index := i): formation_slot = index; _show_screen("FORMATION"), false, Vector2(220, 82))
		card.add_child(button)
	var roster_box := _scroll_box()
	roster_box.add_child(_label("선택 슬롯 %d에 배치할 캐릭터" % (formation_slot + 1), 24, Color("f1d77a")))
	var grid := GridContainer.new()
	grid.columns = 4
	roster_box.add_child(grid)
	for character in DataRegistry.list_of("characters"):
		var unlocked := bool(AppState.profile.roster[character.id].unlocked)
		var roster_card := VBoxContainer.new()
		roster_card.custom_minimum_size = Vector2(250, 184)
		roster_card.add_theme_constant_override("separation", 5)
		grid.add_child(roster_card)
		roster_card.add_child(_art_rect(str(character.icon_asset_id), Vector2(250, 104)))
		roster_card.add_child(_button("%s\n%s / %s" % [LocalizationService.tr_key(character.name_key), character.role, character.preferred_position], func(character_id: String = str(character.id)): AppState.set_party_slot(formation_slot, character_id); SaveService.save_game(); _show_screen("FORMATION"), not unlocked, Vector2(250, 74)))
	var actions := HBoxContainer.new()
	content.add_child(actions)
	var formation_destination := str(AppState.route_payload.get("after", "STAGE_SELECT"))
	if formation_destination not in ["STAGE_DETAIL", "STAGE_SELECT"]:
		formation_destination = "STAGE_SELECT"
	var formation_action_text := "스테이지 상세로" if formation_destination == "STAGE_DETAIL" else "스테이지 선택으로"
	actions.add_child(_button(formation_action_text, func(destination := formation_destination): SceneRouter.go(destination), false, Vector2(240, 64)))
	actions.add_child(_button("저장", func(): _report_result(SaveService.save_game()), false, Vector2(140, 64)))

func _show_stage_select() -> void:
	var selected_stage: Dictionary = DataRegistry.stage(AppState.selected_stage_id)
	var selected_chapter_id := str(selected_stage.get("chapter_id", "CH01"))
	_title("접근성 스테이지 목록", "챕터별 장거리 육각 맵의 목록형 보존 화면")
	var chapter_row := HBoxContainer.new()
	content.add_child(chapter_row)
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var chapter_id := str(chapter.get("id", ""))
		var progress: Dictionary = AppState.profile.get("chapter_progress", {}).get(chapter_id, {})
		var chapter_name := LocalizationService.tr_key(str(chapter.get("name_key", "")))
		chapter_row.add_child(_button(chapter_name, func(id := chapter_id, first_stage := str(chapter.get("normal_stage_ids", [""])[0])): AppState.selected_stage_id = first_stage; stage_mode = "NORMAL"; _show_screen("STAGE_SELECT"), chapter_id.is_empty() or not bool(progress.get("unlocked", false)), Vector2(190, 58)))
	var mode_row := HBoxContainer.new()
	content.add_child(mode_row)
	mode_row.add_child(_button("NORMAL", func(): stage_mode = "NORMAL"; _show_screen("STAGE_SELECT"), stage_mode == "NORMAL", Vector2(180, 60)))
	mode_row.add_child(_button("HARD", func(): stage_mode = "HARD"; _show_screen("STAGE_SELECT"), stage_mode == "HARD", Vector2(180, 60)))
	var selected_chapter: Dictionary = DataRegistry.chapter(selected_chapter_id)
	var selected_progress: Dictionary = AppState.profile.get("chapter_progress", {}).get(selected_chapter_id, {})
	if stage_mode == "HARD" and not bool(selected_progress.get("hard_unlocked", false)) and not AppState.debug_unlock_all_enabled():
		var normal_route: Array = selected_chapter.get("normal_stage_ids", [])
		var final_normal := str(normal_route.back()) if not normal_route.is_empty() else ""
		content.add_child(_label("HARD는 %s 클리어 후 해금됩니다." % _stage_display_name(final_normal), 24, Color("ffbd7a")))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(grid)
	for stage in DataRegistry.list_of("stages"):
		if stage.mode != stage_mode or str(stage.get("chapter_id", "")) != selected_chapter_id: continue
		var stars := int(AppState.profile.stage_stars.get(stage.id, 0))
		var unlocked := AppState.is_stage_unlocked(stage.id)
		var boss := " · 보스" if stage.boss else ""
		var stage_name := LocalizationService.tr_key(str(stage.name_key))
		grid.add_child(_button("%s%s\n권장 Lv.%d\n%s" % [stage_name, boss, stage.recommended_level, "★".repeat(stars) + "☆".repeat(3 - stars)], func(stage_id: String = str(stage.id)): AppState.selected_stage_id = stage_id; SceneRouter.go("STAGE_DETAIL"), not unlocked, Vector2(235, 120)))

func _show_chapter_map() -> void:
	AppState.queue_story_event("MAP_ENTER")
	var pending_story := AppState.next_pending_story_trigger()
	if not pending_story.is_empty():
		AppState.active_scenario_id = str(pending_story.get("scenario_id", ""))
		SaveService.save_game()
		SceneRouter.go("STORY", {"after": "STAGE_SELECT", "origin": "CHAPTER_MAP"})
		return
	AudioService.play_bgm("audio_bgm_lobby")
	var selected_stage: Dictionary = DataRegistry.stage(AppState.selected_stage_id)
	var chapter_id := str(selected_stage.get("chapter_id", "CH01"))
	var chapter: Dictionary = DataRegistry.chapter(chapter_id)
	var map_id := AppState.map_id_for_chapter(chapter_id)
	_title(LocalizationService.tr_key(str(chapter.get("name_key", ""))), "탐색 경로를 따라 조우를 선택하고, 기존 실시간 전투에 진입합니다.")
	var definition: Dictionary = ChapterMapLoaderScript.load_map(map_id)
	var errors: Array[String] = ChapterMapLoaderScript.validate(definition)
	if not errors.is_empty():
		content.add_child(_label("맵 데이터 검증 실패\n" + "\n".join(errors), 22, Color("ff7f8a")))
		content.add_child(_button("목록형 fail-safe 열기", func(): SceneRouter.go("STAGE_LIST_FALLBACK"), false, Vector2(260, 64)))
		return
	var map_screen = ChapterMapScene.instantiate()
	map_screen.map_id = map_id
	map_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_screen.battle_requested.connect(_map_battle_requested)
	map_screen.formation_requested.connect(func(): SceneRouter.go("FORMATION"))
	map_screen.fallback_requested.connect(func(): SceneRouter.go("STAGE_LIST_FALLBACK"))
	map_screen.sweep_requested.connect(_map_sweep_requested)
	map_screen.treasure_reward_requested.connect(_map_treasure_reward_requested)
	content.add_child(map_screen)
	active_chapter_map_screen = map_screen
	_apply_chapter_map_shell_overrides()

func _map_battle_requested(stage_id: String) -> void:
	_request_battle_start("map:encounter", stage_id)

func _map_sweep_requested(stage_id: String, count: int) -> void:
	AppState.selected_stage_id = stage_id
	_sweep(count)

func _map_treasure_reward_requested(report: Dictionary) -> void:
	last_rewards = report.get("rewards", {}).duplicate(true)
	last_reward_report = report.duplicate(true)
	last_battle_result = {"victory": true, "time": 0.0, "survivors": 5, "seed": AppState.battle_seed, "event_hash": "%s:%s" % [str(report.get("source_type", "EXPLORE")), str(report.get("source_id", ""))], "damage": {}, "healing": {}, "source_type": str(report.get("source_type", "TREASURE"))}
	SceneRouter.go("RESULT")

func _show_stage_detail() -> void:
	var stage := DataRegistry.stage(AppState.selected_stage_id)
	_title(LocalizationService.tr_key(str(stage.name_key)) + (" • 보스" if stage.boss else ""), "권장 Lv.%d • %d 작전력 • %d초" % [stage.recommended_level, stage.stamina_cost, stage.time_limit])
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	content.add_child(columns)
	var wave_box := _panel_box(columns)
	wave_box.add_child(_label("적 편성 • %d 웨이브" % stage.waves.size(), 25, Color("a8b7ff")))
	wave_box.add_child(_label(_format_stage_waves(stage.waves), 21))
	var reward := DataRegistry.by_id("rewards", stage.reward_table_id)
	var reward_box := _panel_box(columns)
	reward_box.add_child(_label("획득 가능 보상", 25, Color("78e6d0")))
	reward_box.add_child(_label(_format_reward_entries(reward.get("guaranteed", [])), 21, Color("8fe0b6")))
	reward_box.add_child(_label("추가 보상\n" + _format_reward_entries(reward.get("bonus", [])), 18, Color("cdd5e3")))
	reward_box.add_child(_label("희귀 재료 8회 실패 후 다음 1회 보장\n소탕도 동일한 RewardResolver 사용", 17, Color("8e9aaf")))
	var attempts := "무제한"
	if stage.mode == "HARD":
		attempts = "무제한 (DEV)" if SettingsService.is_developer_mode() else "%d/%d" % [AppState.profile.hard_attempts.counts.get(stage.id, 0), stage.daily_attempts]
	wave_box.add_child(_label("입장 횟수 %s   현재 %s/3성" % [attempts, AppState.profile.stage_stars.get(stage.id, 0)], 20, Color("e9c979")))
	var actions := HBoxContainer.new()
	content.add_child(actions)
	actions.add_child(_button("파티 편성", func(): SceneRouter.go("FORMATION"), false, Vector2(190, 66)))
	actions.add_child(_button("전투 시작", func(): _request_battle_start("button:battle_start"), not AppState.can_enter_stage(stage.id), Vector2(210, 66)))
	for count in [1, 5, 10]:
		var sweep_disabled: bool = int(AppState.profile.stage_stars.get(stage.id, 0)) < 3 or not AppState.can_enter_stage_count(stage.id, int(count))
		actions.add_child(_button("소탕 %d회" % count, func(value: int = int(count)): _sweep(value), sweep_disabled, Vector2(160, 66)))

func _request_battle_start(source: String, stage_id := "") -> bool:
	if battle_transition_active: return false
	if not _consume_transition_edge("BATTLE_START", source): return false
	if not stage_id.is_empty(): AppState.selected_stage_id = stage_id
	return _start_battle()

func _start_battle() -> bool:
	if battle_transition_active: return false
	if not AppState.begin_battle_transaction(AppState.selected_stage_id):
		footer_status.text = "입장 조건/작전력/일일 횟수를 확인하세요."
		return false
	battle_transition_active = true
	_play_map_battle_transition()
	return true

func _play_map_battle_transition() -> void:
	var veil := ColorRect.new()
	veil.name = "R7HexSignalTransition"
	veil.color = Color("06101c00")
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)
	var special_event := AppState.pending_map_special_event()
	var encounter_presentation := AppState.pending_map_encounter_presentation()
	var focus := Label.new()
	var stage := DataRegistry.stage(AppState.selected_stage_id)
	var encounter_title := LocalizationService.tr_key(str(stage.get("name_key", AppState.selected_stage_id)))
	if not special_event.is_empty():
		encounter_title = LocalizationService.tr_key(str(special_event.get("title_key", "MAP_EVENT_DEFAULT_TITLE")))
	elif not str(encounter_presentation.get("event_title_key", "")).is_empty():
		encounter_title = LocalizationService.tr_key(str(encounter_presentation.get("event_title_key", "")))
	var encounter_heading := "적군 조우"
	if not special_event.is_empty():
		encounter_heading = LocalizationService.tr_key("MAP_EVENT_CONTACT_SIGNAL")
	elif str(encounter_presentation.get("transition_style", "")).to_upper() == "BOSS":
		encounter_heading = LocalizationService.tr_key("MAP_BOSS_CONTACT_CAPTION")
	focus.text = "%s\n%s" % [encounter_heading, encounter_title]
	focus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	focus.add_theme_font_size_override("font_size", 48)
	focus.add_theme_constant_override("outline_size", 8)
	focus.add_theme_color_override("font_outline_color", Color("06101c"))
	focus.modulate = Color("7cebd000")
	focus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(focus)
	# A ! contact is an authored event, not a decorative 1.85-second title card.
	# Its dialogue window owns input until the player chooses Next or Skip, then
	# hands off exactly once to the already-created battle transaction.  The
	# payload remains read-only presentation data: recruitment, rewards, and the
	# event-complete flag still belong exclusively to the victory resolver.
	if not special_event.is_empty():
		await _play_special_event_dialogue(veil, special_event, focus)
		veil.queue_free()
		SceneRouter.go("BATTLE")
		return
	var boss_card: PanelContainer
	if str(encounter_presentation.get("transition_style", "")) == "BOSS":
		# This is an original signal-readout card, not a copied reference layout.
		# It only consumes map-authored localization keys and fades before the
		# unchanged realtime battle scene owns input and simulation.
		boss_card = PanelContainer.new()
		boss_card.name = "BossEncounterTitleCard"
		boss_card.set_anchors_preset(Control.PRESET_CENTER)
		boss_card.position = Vector2(-330, 64)
		boss_card.size = Vector2(660, 144)
		boss_card.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var boss_style := StyleBoxFlat.new()
		boss_style.bg_color = Color("17172ae8")
		boss_style.border_color = Color("e6a85a")
		boss_style.set_border_width_all(2)
		boss_style.set_corner_radius_all(16)
		boss_style.content_margin_left = 24
		boss_style.content_margin_right = 24
		boss_style.content_margin_top = 14
		boss_style.content_margin_bottom = 14
		boss_card.add_theme_stylebox_override("panel", boss_style)
		veil.add_child(boss_card)
		var boss_copy := VBoxContainer.new()
		boss_copy.alignment = BoxContainer.ALIGNMENT_CENTER
		boss_copy.add_theme_constant_override("separation", 3)
		boss_card.add_child(boss_copy)
		var boss_caption := _label(LocalizationService.tr_key("MAP_BOSS_CONTACT_CAPTION"), 15, Color("f3c884"))
		boss_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss_copy.add_child(boss_caption)
		var boss_name := _label(LocalizationService.tr_key(str(encounter_presentation.get("boss_name_key", "MAP_BOSS_UNKNOWN_NAME"))), 34, Color("fff0cf"))
		boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss_copy.add_child(boss_name)
		var boss_subtitle := _label(LocalizationService.tr_key(str(encounter_presentation.get("boss_subtitle_key", "MAP_BOSS_UNKNOWN_SUBTITLE"))), 17, Color("b9cfde"))
		boss_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss_copy.add_child(boss_subtitle)
	if not special_event.is_empty():
		var character := DataRegistry.character(str(special_event.get("character_id", "")))
		var contact_character_ids: Array[String] = []
		for character_id_value in special_event.get("character_ids", []):
			var contact_character_id := str(character_id_value)
			if not contact_character_id.is_empty() and not DataRegistry.character(contact_character_id).is_empty():
				contact_character_ids.append(contact_character_id)
		if contact_character_ids.is_empty() and not character.is_empty():
			contact_character_ids.append(str(character.get("id", "")))
		var event_panel := PanelContainer.new()
		event_panel.name = "CompanionEventContactCard"
		event_panel.set_anchors_preset(Control.PRESET_CENTER)
		# Every authored companion encounter uses this same card frame: the
		# recruitment outcome lives in a fixed bottom band instead of following
		# the variable-length body copy.  This is presentation-only; the
		# immutable outcome key is still owned by the map encounter payload.
		# AppShell uses a 1920-wide design canvas.  A narrow desktop card
		# became a narrow 192 physical px column in portrait Web, forcing Korean
		# copy and the recruitment result into unreadable fragments.  Portrait uses
		# the same card hierarchy but a deliberately wide, shallow frame so its
		# fixed result band has a single reliable reading line.
		var portrait_contact_layout := _is_portrait_layout()
		var event_card_size := Vector2(1680, 690) if portrait_contact_layout else Vector2(820, 300)
		event_panel.position = Vector2(-840, -330) if portrait_contact_layout else Vector2(-410, 60)
		event_panel.size = event_card_size
		event_panel.custom_minimum_size = event_card_size
		event_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var event_style := StyleBoxFlat.new()
		event_style.bg_color = Color("102638e8")
		event_style.border_color = Color("7cebd0")
		event_style.set_border_width_all(2)
		event_style.set_corner_radius_all(14)
		event_style.content_margin_left = 14
		event_style.content_margin_right = 18
		event_style.content_margin_top = 10
		event_style.content_margin_bottom = 10
		event_panel.add_theme_stylebox_override("panel", event_style)
		veil.add_child(event_panel)
		var event_layout := VBoxContainer.new()
		event_layout.add_theme_constant_override("separation", 8)
		event_panel.add_child(event_layout)
		var event_row := HBoxContainer.new()
		event_row.add_theme_constant_override("separation", 12)
		event_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		event_layout.add_child(event_row)
		if contact_character_ids.size() == 1 and not character.is_empty():
			event_row.add_child(_art_rect(str(character.get("portrait_asset_id", "")), Vector2(126, 176)))
		elif contact_character_ids.size() > 1:
			# Duo contact keeps the established card and result-band geometry, but
			# makes both faces and names independently readable before auto-battle.
			# It is presentation-only: recruitment ownership remains in AppState.
			var duo_portraits := HBoxContainer.new()
			duo_portraits.name = "DuoContactPortraits"
			duo_portraits.custom_minimum_size = Vector2(132, 132)
			duo_portraits.add_theme_constant_override("separation", 5)
			for contact_character_id in contact_character_ids.slice(0, 2):
				var contact_definition := DataRegistry.character(str(contact_character_id))
				var contact_column := VBoxContainer.new()
				contact_column.name = "DuoContactPortrait_%s" % str(contact_character_id)
				contact_column.custom_minimum_size = Vector2(63, 0)
				contact_column.alignment = BoxContainer.ALIGNMENT_CENTER
				contact_column.add_child(_art_rect(str(contact_definition.get("portrait_asset_id", "")), Vector2(62, 96)))
				var contact_name := _label(_display_character_name(str(contact_character_id)), 12, Color("f6fffe"))
				contact_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				contact_name.add_theme_constant_override("outline_size", 1)
				contact_name.add_theme_color_override("font_outline_color", Color("153e43"))
				contact_column.add_child(contact_name)
				duo_portraits.add_child(contact_column)
			event_row.add_child(duo_portraits)
		var event_copy := VBoxContainer.new()
		event_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		event_row.add_child(event_copy)
		event_copy.add_child(_label(LocalizationService.tr_key("MAP_EVENT_CONTACT_SIGNAL"), 21, Color("7cebd0")))
		event_copy.add_child(_label(_display_character_name(str(special_event.get("character_id", ""))), 34, Color("ffe28a")))
		var event_body := _label(LocalizationService.tr_key(str(special_event.get("body_key", "MAP_EVENT_DEFAULT_BODY"))), 22, Color("eef6ff"))
		event_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		event_copy.add_child(event_body)
		var outcome_key := str(special_event.get("contact_outcome_key", ""))
		if not outcome_key.is_empty():
			var outcome_panel := PanelContainer.new()
			outcome_panel.name = "CompanionOutcomePanel"
			outcome_panel.custom_minimum_size = Vector2(0, 62)
			var outcome_style := StyleBoxFlat.new()
			outcome_style.bg_color = Color("082f3ee8")
			outcome_style.border_color = Color("4fbfaa")
			outcome_style.set_border_width_all(1)
			outcome_style.set_corner_radius_all(8)
			outcome_style.content_margin_left = 12
			outcome_style.content_margin_right = 12
			outcome_panel.add_theme_stylebox_override("panel", outcome_style)
			event_layout.add_child(outcome_panel)
			var outcome_row := HBoxContainer.new()
			outcome_row.name = "CompanionOutcomeRow"
			outcome_row.add_theme_constant_override("separation", 10)
			outcome_panel.add_child(outcome_row)
			var outcome_caption := _label("조우 결과", 19, Color("b8fff2"))
			outcome_caption.custom_minimum_size = Vector2(102, 0)
			outcome_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			outcome_row.add_child(outcome_caption)
			# The caption stays quiet, while the actual recruitment rule is one
			# deliberate emphasis step brighter and thicker.  This is the only
			# readability polish suggested by the independent mobile-card review;
			# position, payload, timing and encounter authority remain unchanged.
			var outcome := _label(LocalizationService.tr_key(outcome_key), 24, Color("f5fffd"))
			outcome.name = "CompanionOutcomeText"
			outcome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			outcome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			outcome.add_theme_constant_override("outline_size", 2)
			outcome.add_theme_color_override("font_outline_color", Color("163f44"))
			outcome_row.add_child(outcome)
	var reduced := bool(SettingsService.values.get("map_reduced_transition", false))
	# A companion contact carries player-facing context, so hold it long enough
	# to be read before the existing battle scene takes ownership.  This remains
	# presentation-only and does not delay or mutate the battle transaction.
	# Event contacts are the only transitions that communicate a persistent
	# player-facing outcome.  Keep the card on screen long enough to read its
	# immediate/deferred recruitment result before battle begins.
	var duration := 0.12 if reduced else (SPECIAL_EVENT_CONTACT_DURATION if not special_event.is_empty() else (BOSS_ENCOUNTER_CARD_DURATION if boss_card != null else 0.46))
	if not special_event.is_empty() and debug_companion_card_visual_hold:
		# Visual QA uses the exact production card, then gives the browser capture
		# enough wall-clock time to sample it.  The flag is one-shot and can only
		# be armed from the Development build's explicit fixture.
		duration = 8.0
		debug_companion_card_visual_hold = false
	var intro_duration := minf(0.10, duration * 0.24)
	var outro_duration := minf(0.08, duration * 0.18)
	var hold_duration := maxf(0.02, duration - intro_duration - outro_duration)
	var tween := create_tween()
	tween.tween_property(veil, "color", Color("06101cf2"), intro_duration)
	tween.parallel().tween_property(focus, "modulate", Color("fff0c8"), intro_duration)
	if not special_event.is_empty():
		tween.parallel().tween_property(veil.get_node_or_null("CompanionEventContactCard"), "modulate", Color.WHITE, intro_duration)
	if boss_card != null:
		tween.parallel().tween_property(boss_card, "modulate", Color.WHITE, intro_duration)
	tween.tween_interval(hold_duration)
	tween.tween_property(focus, "modulate", Color("fff0c800"), outro_duration)
	if not special_event.is_empty():
		tween.parallel().tween_property(veil.get_node_or_null("CompanionEventContactCard"), "modulate", Color("ffffff00"), outro_duration)
	if boss_card != null:
		tween.parallel().tween_property(boss_card, "modulate", Color("ffffff00"), outro_duration)
	await tween.finished
	veil.queue_free()
	SceneRouter.go("BATTLE")

func _event_dialogue_speaker_name(page: Dictionary) -> String:
	var speaker_kind := str(page.get("speaker_kind", "COMMAND"))
	var speaker_id := str(page.get("speaker_id", ""))
	if speaker_kind == "COMPANION":
		return _display_character_name(speaker_id)
	if speaker_kind == "ENEMY":
		var enemy := DataRegistry.enemy(speaker_id)
		return LocalizationService.tr_key(str(enemy.get("name_key", speaker_id))) if not enemy.is_empty() else LocalizationService.tr_key("MAP_EVENT_ENEMY_SIGNAL_NAME")
	return LocalizationService.tr_key("MAP_EVENT_COMMAND_NAME")

func _play_special_event_dialogue(veil: ColorRect, special_event: Dictionary, focus: Label) -> void:
	var dialogue: Array = special_event.get("pre_battle_dialogue", [])
	if dialogue.is_empty():
		dialogue = [
			{"speaker_kind": "COMMAND", "speaker_id": "", "text_key": str(special_event.get("body_key", "MAP_EVENT_DEFAULT_BODY"))},
			{"speaker_kind": "COMMAND", "speaker_id": "", "text_key": str(special_event.get("contact_outcome_key", "MAP_EVENT_DEFAULT_BODY"))},
		]
	var panel := PanelContainer.new()
	panel.name = "PreBattleEventDialog"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var portrait_layout := _is_portrait_layout()
	# The encounter is staged as a dialogue scene, not a centered text alert:
	# a permanent left key-visual identifies the companion/special enemy while
	# every command page continues on the right.  Keeping this art visible on
	# command pages prevents the familiar VN problem where the player loses
	# track of who the event is about between narration lines.
	# This is the one high-attention surface in the map flow.  Treat it as a
	# compact tactical briefing, not a legacy message box: the portrait gets a
	# stable editorial column, the narrative owns the reading column, and the
	# consequence plus the primary action remain visible without competing.
	# Portrait keeps the same two-column encounter grammar, but it needs enough
	# vertical room for a readable Korean paragraph and the 56px touch controls.
	# This height is intentionally calculated against the expanded mobile canvas;
	# it prevents children from spilling below the modal on a 390×844 class phone.
	var panel_size := Vector2(1690, 1720) if portrait_layout else Vector2(1500, 750)
	panel.position = Vector2(-845, -860) if portrait_layout else Vector2(-750, -375)
	panel.size = panel_size
	panel.custom_minimum_size = panel_size
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	# The event dialog is a modal interaction surface.  Explicit input filters
	# keep its full copy/key-visual area tappable on Web while allowing the two
	# bottom controls to remain ordinary Buttons.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("08121ff8")
	panel_style.border_color = Color("89ecd9")
	panel_style.set_border_width_all(2)
	panel_style.shadow_color = Color("02050bcf")
	panel_style.shadow_size = 20
	panel_style.shadow_offset = Vector2(0, 10)
	panel_style.set_corner_radius_all(18)
	panel_style.content_margin_left = 42
	panel_style.content_margin_right = 42
	panel_style.content_margin_top = 30
	panel_style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", panel_style)
	veil.add_child(panel)
	var layout := VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_PASS
	layout.add_theme_constant_override("separation", 14)
	panel.add_child(layout)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_theme_constant_override("separation", 18)
	layout.add_child(header)
	var signal_badge := PanelContainer.new()
	signal_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var signal_badge_style := StyleBoxFlat.new()
	signal_badge_style.bg_color = Color("113344")
	signal_badge_style.border_color = Color("4fd9c2")
	signal_badge_style.set_border_width_all(1)
	signal_badge_style.set_corner_radius_all(7)
	signal_badge_style.content_margin_left = 14
	signal_badge_style.content_margin_right = 14
	signal_badge_style.content_margin_top = 7
	signal_badge_style.content_margin_bottom = 7
	signal_badge.add_theme_stylebox_override("panel", signal_badge_style)
	signal_badge.custom_minimum_size = Vector2(310 if portrait_layout else 230, 0)
	header.add_child(signal_badge)
	var contact_signal := _label(LocalizationService.tr_key("MAP_EVENT_CONTACT_SIGNAL"), 21 if not portrait_layout else 25, Color("9df5e4"))
	contact_signal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contact_signal.add_theme_font_override("font", _story_weighted_font(650, 0.25))
	signal_badge.add_child(contact_signal)
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)
	var page_counter := _label("", 21 if not portrait_layout else 25, Color("cce6ec"))
	page_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	page_counter.add_theme_font_override("font", _story_weighted_font(600, 0.15))
	header.add_child(page_counter)
	var title := _label(LocalizationService.tr_key(str(special_event.get("title_key", "MAP_EVENT_DEFAULT_TITLE"))), 46 if not portrait_layout else 52, Color("ffe1a0"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_override("font", _story_weighted_font(720, 0.35))
	title.add_theme_constant_override("line_spacing", 2)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(title)
	var main_row := HBoxContainer.new()
	main_row.mouse_filter = Control.MOUSE_FILTER_PASS
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 34)
	layout.add_child(main_row)
	var portrait_frame := PanelContainer.new()
	portrait_frame.name = "EventKeyVisual"
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	portrait_frame.custom_minimum_size = Vector2(460, 440) if portrait_layout else Vector2(398, 380)
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = Color("061925")
	portrait_style.border_color = Color("4ed2bf")
	portrait_style.set_border_width_all(1)
	portrait_style.set_corner_radius_all(12)
	portrait_style.content_margin_left = 12
	portrait_style.content_margin_right = 12
	portrait_style.content_margin_top = 12
	portrait_style.content_margin_bottom = 12
	portrait_frame.add_theme_stylebox_override("panel", portrait_style)
	main_row.add_child(portrait_frame)
	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_PASS
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 16)
	main_row.add_child(copy)
	var speaker_label := _label("", 29 if not portrait_layout else 35, Color("91f5df"))
	speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speaker_label.add_theme_font_override("font", _story_weighted_font(650, 0.25))
	copy.add_child(speaker_label)
	var dialogue_label := _label("", 36 if not portrait_layout else 42, Color("f7fbff"))
	dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_label.add_theme_font_override("font", _story_weighted_font(510, 0.08))
	dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.add_theme_constant_override("line_spacing", 12)
	dialogue_label.add_theme_constant_override("outline_size", 1)
	dialogue_label.add_theme_color_override("font_outline_color", Color("08101b"))
	copy.add_child(dialogue_label)
	var outcome_panel := PanelContainer.new()
	outcome_panel.name = "PreBattleEventOutcomeBand"
	outcome_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	outcome_panel.custom_minimum_size = Vector2(0, 88 if not portrait_layout else 106)
	var outcome_style := StyleBoxFlat.new()
	outcome_style.bg_color = Color("0b2b35")
	outcome_style.border_color = Color("4ecab7")
	outcome_style.set_border_width_all(1)
	outcome_style.set_corner_radius_all(12)
	outcome_style.content_margin_left = 22
	outcome_style.content_margin_right = 22
	outcome_style.content_margin_top = 8
	outcome_style.content_margin_bottom = 8
	outcome_panel.add_theme_stylebox_override("panel", outcome_style)
	layout.add_child(outcome_panel)
	var outcome := _label(LocalizationService.tr_key(str(special_event.get("contact_outcome_key", "MAP_EVENT_DEFAULT_BODY"))), 25 if not portrait_layout else 30, Color("edfffb"))
	outcome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outcome.add_theme_font_override("font", _story_weighted_font(590, 0.15))
	outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outcome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outcome.add_theme_constant_override("outline_size", 1)
	outcome.add_theme_color_override("font_outline_color", Color("103f48"))
	outcome_panel.add_child(outcome)
	var controls: BoxContainer = VBoxContainer.new() if portrait_layout else HBoxContainer.new()
	controls.mouse_filter = Control.MOUSE_FILTER_PASS
	controls.alignment = BoxContainer.ALIGNMENT_END
	controls.add_theme_constant_override("separation", 16)
	layout.add_child(controls)
	var hint := _label(LocalizationService.tr_key("MAP_EVENT_DIALOGUE_HINT"), 20 if not portrait_layout else 24, Color("b8d7dd"))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls.add_child(hint)
	var skip_button := _button(LocalizationService.tr_key("MAP_EVENT_DIALOGUE_SKIP"), func() -> void: pass, false, Vector2(220 if not portrait_layout else 276, 72 if not portrait_layout else 86))
	skip_button.name = "EventDialogueSkip"
	skip_button.add_theme_font_override("font", _story_weighted_font(620, 0.18))
	skip_button.add_theme_font_size_override("font_size", _story_logical_px(17.0) if portrait_layout else 23)
	var skip_normal := StyleBoxFlat.new()
	skip_normal.bg_color = Color("132435")
	skip_normal.border_color = Color("6b9ead")
	skip_normal.set_border_width_all(1)
	skip_normal.set_corner_radius_all(9)
	var skip_hover := skip_normal.duplicate()
	skip_hover.bg_color = Color("1d3b50")
	skip_button.add_theme_stylebox_override("normal", skip_normal)
	skip_button.add_theme_stylebox_override("hover", skip_hover)
	skip_button.add_theme_stylebox_override("pressed", skip_hover)
	skip_button.add_theme_color_override("font_color", Color("e2f3f4"))
	var next_button := _button(LocalizationService.tr_key("MAP_EVENT_DIALOGUE_NEXT"), func() -> void: pass, false, Vector2(214 if not portrait_layout else 264, 72 if not portrait_layout else 86))
	next_button.name = "EventDialogueNext"
	next_button.add_theme_font_override("font", _story_weighted_font(700, 0.30))
	next_button.add_theme_font_size_override("font_size", _story_logical_px(18.0) if portrait_layout else 24)
	_make_primary_button(next_button)
	if portrait_layout:
		# `_button` raises generic portrait controls to the full touch target on
		# both axes.  In this paired action row we preserve the touch height while
		# setting two truthful, side-by-side widths that leave the dialogue hint
		# readable above them.
		skip_button.custom_minimum_size = Vector2(_story_logical_px(112.0), _story_logical_px(56.0))
		next_button.custom_minimum_size = Vector2(_story_logical_px(132.0), _story_logical_px(56.0))
		var action_row := HBoxContainer.new()
		action_row.alignment = BoxContainer.ALIGNMENT_END
		action_row.add_theme_constant_override("separation", _story_logical_px(10.0))
		action_row.add_child(skip_button)
		action_row.add_child(next_button)
		controls.add_child(action_row)
	else:
		controls.add_child(skip_button)
		controls.add_child(next_button)
	var page_index := 0
	var resolved := false
	var update_page: Callable
	var advance_page: Callable
	update_page = func() -> void:
		var page_value: Variant = dialogue[clampi(page_index, 0, dialogue.size() - 1)]
		var page: Dictionary = page_value if page_value is Dictionary else {}
		speaker_label.text = _event_dialogue_speaker_name(page)
		dialogue_label.text = LocalizationService.tr_key(str(page.get("text_key", special_event.get("body_key", "MAP_EVENT_DEFAULT_BODY"))))
		page_counter.text = "%d / %d" % [page_index + 1, dialogue.size()]
		next_button.text = LocalizationService.tr_key("MAP_EVENT_DIALOGUE_BATTLE") if page_index >= dialogue.size() - 1 else LocalizationService.tr_key("MAP_EVENT_DIALOGUE_NEXT")
		for child in portrait_frame.get_children():
			child.free()
		var speaker_kind := str(page.get("speaker_kind", "COMMAND"))
		var event_kind := str(special_event.get("event_kind", "COMPANION"))
		var key_visual_added := false
		if event_kind == "COMPANION":
			var character := DataRegistry.character(str(special_event.get("character_id", "")))
			if not character.is_empty():
				# Non-combat contacts always use the established 8-head standing
				# art.  COVERED makes the framed presentation a half-body crop
				# without fabricating a second character variant.
				# Keep the character's face and silhouette intact.  The former COVERED
				# crop was visually forceful but could cut a head or hair detail; this
				# briefing frame deliberately preserves a readable 8-head portrait.
				var character_art := _art_rect(str(character.get("portrait_asset_id", "")), Vector2(436, 416) if portrait_layout else Vector2(374, 356), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
				# `_art_rect` normally scales a standalone portrait for a mobile card.
				# This event frame is already size-governed, so applying that scale here
				# made it consume the whole horizontal row and collapsed the dialogue.
				character_art.custom_minimum_size = Vector2(436, 416) if portrait_layout else Vector2(374, 356)
				portrait_frame.add_child(character_art)
				key_visual_added = true
		elif event_kind == "SPECIAL_ENEMY":
			var enemy := DataRegistry.enemy(str(special_event.get("enemy_id", "")))
			if not enemy.is_empty():
				# Special enemies deliberately use their registered combat preview:
				# this keeps the map contact, warning marker, and coming battle
				# recognisably about the same enemy rather than a generic icon.
				var enemy_art := _art_rect(str(enemy.get("asset_id", "")), Vector2(436, 416) if portrait_layout else Vector2(374, 356), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
				enemy_art.custom_minimum_size = Vector2(436, 416) if portrait_layout else Vector2(374, 356)
				portrait_frame.add_child(enemy_art)
				key_visual_added = true
		if not key_visual_added:
			var threat_glyph := _label("!", 144 if portrait_layout else 116, Color("ffb77a") if speaker_kind == "ENEMY" else Color("79ecda"))
			threat_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			threat_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			portrait_frame.add_child(threat_glyph)
	update_page.call()
	advance_page = func() -> void:
		if page_index < dialogue.size() - 1:
			page_index += 1
			update_page.call()
		else:
			resolved = true
	skip_button.pressed.connect(func() -> void: resolved = true)
	next_button.pressed.connect(advance_page)
	pre_battle_event_input_panel = panel
	pre_battle_event_input_next = next_button
	pre_battle_event_input_skip = skip_button
	pre_battle_event_advance = advance_page
	pre_battle_event_resolve = func() -> void: resolved = true
	pre_battle_event_input_active = true
	# The whole event body is a VN-like advance target. Buttons keep their own
	# input, while clicking/tapping any empty dialogue or key-visual area follows
	# the same single advancement path as Next.  Skip remains intentionally
	# separate: it resolves presentation only and never commits event rewards.
	panel.gui_input.connect(func(event: InputEvent) -> void:
		var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		var touched: bool = event is InputEventScreenTouch and event.pressed
		if clicked or touched:
			_handle_pre_battle_event_input(event.position)
			panel.accept_event()
	)
	var intro := create_tween()
	intro.tween_property(veil, "color", Color("06101cf4"), 0.12)
	intro.parallel().tween_property(focus, "modulate", Color("fff0c8"), 0.12)
	intro.parallel().tween_property(panel, "modulate", Color.WHITE, 0.12)
	await intro.finished
	focus.visible = false
	while not resolved:
		await get_tree().process_frame
	pre_battle_event_input_active = false
	pre_battle_event_input_panel = null
	pre_battle_event_input_next = null
	pre_battle_event_input_skip = null
	pre_battle_event_advance = Callable()
	pre_battle_event_resolve = Callable()
	var outro := create_tween()
	outro.tween_property(panel, "modulate", Color("ffffff00"), 0.10)
	outro.parallel().tween_property(veil, "color", Color("06101c00"), 0.10)
	await outro.finished

func _show_battle() -> void:
	battle_transition_active = false
	var stage := DataRegistry.stage(AppState.selected_stage_id)
	AudioService.play_bgm("audio_bgm_boss" if bool(stage.boss) else "audio_bgm_battle")
	var simulation := BattleSimulation.new()
	# Both party providers return an untyped Variant Array at runtime.  Assigning
	# that directly to the typed Array[String] fails in the Web/portrait battle
	# path before BattleView is instantiated, leaving only the background/BGM.
	# Normalize each stable ID explicitly so entry cannot blank the whole screen.
	battle_party_ids.clear()
	var selected_party_ids: Array = AppState.relay_current_squad() if AppState.relay_active() else AppState.get_party()
	for party_id_value in selected_party_ids:
		battle_party_ids.append(str(party_id_value))
	var party_snapshot := AppState.relay_party_snapshot() if AppState.relay_active() else AppState.create_party_snapshot()
	if party_snapshot.size() != 5:
		footer_status.text = "전투 편성 데이터가 유효하지 않습니다."
		SceneRouter.go("RELAY" if AppState.relay_active() else "FORMATION")
		return
	simulation.setup(party_snapshot, stage, AppState.battle_seed, DataRegistry.data, AppState.effective_battle_debug_options())
	simulation.auto_enabled = bool(SettingsService.values.battle_auto)
	battle_view = BattleViewScene.instantiate()
	# BattleView is a canvas-drawn Control.  A VBoxContainer only grants it the
	# full combat width when it participates in the horizontal expand contract;
	# vertical expansion alone can collapse its draw rect to zero on a narrow Web
	# viewport, leaving only the lobby background and active BGM.  Keep it as one
	# full-width responsive battlefield on both desktop and portrait mobile.
	battle_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_view.custom_minimum_size = Vector2(0.0, 420.0)
	battle_view.setup(simulation)
	battle_view.speed = int(SettingsService.values.battle_speed)
	battle_view.battle_finished.connect(_battle_finished)
	content.add_child(battle_view)
	_build_battle_overlay()

func _rebuild_battle_overlay() -> void:
	if battle_view == null or battle_view.simulation == null: return
	var previous_overlay := battle_view.get_node_or_null("BattleOverlay")
	if previous_overlay != null:
		previous_overlay.free()
	ultimate_buttons.clear()
	party_status_labels.clear()
	battle_hud = null
	battle_auto_button = null
	battle_speed_button = null
	battle_pause_panel = null
	battle_pause_center = null
	_build_battle_overlay()

func _build_battle_overlay() -> void:
	if battle_view == null or battle_view.simulation == null: return
	var overlay := VBoxContainer.new()
	overlay.name = "BattleOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	var portrait := _is_portrait_layout()
	battle_portrait_layout = portrait
	var ui_scale := _portrait_ui_scale()
	overlay.add_theme_constant_override("separation", roundi(6.0 * ui_scale) if portrait else 8)
	battle_view.add_child(overlay)
	var top: BoxContainer = VBoxContainer.new() if portrait else HBoxContainer.new()
	top.add_theme_constant_override("separation", roundi(5.0 * ui_scale) if portrait else 8)
	overlay.add_child(top)
	battle_hud = _label("", 22, Color.WHITE)
	battle_hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if portrait else HORIZONTAL_ALIGNMENT_LEFT
	battle_hud.custom_minimum_size = Vector2(0.0, 28.0 * ui_scale) if portrait else Vector2.ZERO
	top.add_child(battle_hud)
	var battle_actions: Container = GridContainer.new() if portrait else HBoxContainer.new()
	if battle_actions is GridContainer:
		(battle_actions as GridContainer).columns = 2
		battle_actions.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(battle_actions)
	battle_auto_button = _button("AUTO", _toggle_battle_auto, false, Vector2(130, 56))
	battle_auto_button.name = "BattleAutoButton"
	battle_auto_button.tooltip_text = "기본 공격·일반 스킬과 조건부 필살기를 자동 운용합니다."
	battle_actions.add_child(battle_auto_button)
	battle_speed_button = _button("×1", _cycle_battle_speed, false, Vector2(110, 56))
	battle_speed_button.name = "BattleSpeedButton"
	battle_actions.add_child(battle_speed_button)
	battle_actions.add_child(_button("일시정지", _toggle_battle_pause, false, Vector2(140, 56)))
	battle_skip_button = _button("SKIP ▶", _skip_battle, false, Vector2(130, 56))
	battle_skip_button.name = "BattleSkipButton"
	battle_skip_button.tooltip_text = "현재 AUTO 설정과 전투 상태를 유지한 채 남은 전투를 즉시 계산합니다."
	battle_actions.add_child(battle_skip_button)
	var party_row: Container = GridContainer.new() if portrait else HBoxContainer.new()
	party_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if party_row is GridContainer:
		# Three compact readouts keep all five allies visible in two rows. Names and
		# HP remain two-line cards while returning one full row to the battlefield.
		(party_row as GridContainer).columns = 3
	party_row.add_theme_constant_override("separation", roundi(6.0 * ui_scale) if portrait else 8)
	overlay.add_child(party_row)
	for unit in battle_view.simulation.state.party:
		var status_label := _label("", 15, Color("cfe6ff"))
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if portrait else HORIZONTAL_ALIGNMENT_CENTER
		status_label.custom_minimum_size = Vector2(0.0, 40.0 * ui_scale) if portrait else Vector2(0, 58)
		party_status_labels.append(status_label)
		if portrait:
			# Party readouts sit over an animated battlefield. A translucent card
			# keeps HP/shield data legible without consuming the central combat lane.
			var status_card := PanelContainer.new()
			status_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			status_card.add_theme_stylebox_override("panel", _battle_party_status_style())
			status_card.add_child(status_label)
			party_row.add_child(status_card)
		else:
			party_row.add_child(status_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay.add_child(spacer)
	var bottom: Container = GridContainer.new() if portrait else HBoxContainer.new()
	if bottom is GridContainer:
		# Five ultimates remain simultaneously visible in a 3+2 arrangement instead
		# of consuming three portrait rows. Child order (and therefore Tab order) is
		# unchanged.
		(bottom as GridContainer).columns = 3
	else:
		(bottom as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(bottom)
	for unit in battle_view.simulation.state.party:
		var definition := DataRegistry.character(unit.def_id)
		var skill := DataRegistry.skill(definition.ultimate_skill_id)
		var button := _button("%s\nULT %d" % [LocalizationService.tr_key(definition.name_key), skill.tactical_cost], func(uid: String = str(unit.uid)): _request_ultimate(uid), false, Vector2(112 if portrait else 220, 64 if portrait else 78))
		_apply_skill_icon(button, skill, 38 if portrait else 58)
		ultimate_buttons.append(button)
		bottom.add_child(button)
	battle_pause_center = CenterContainer.new()
	battle_pause_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_pause_center.mouse_filter = Control.MOUSE_FILTER_STOP
	battle_pause_center.visible = battle_view.paused
	battle_view.add_child(battle_pause_center)
	battle_pause_panel = PanelContainer.new()
	battle_pause_panel.custom_minimum_size = Vector2(0 if portrait else 620, 410)
	if portrait:
		battle_pause_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	battle_pause_center.add_child(battle_pause_panel)
	var pause_box := VBoxContainer.new()
	pause_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_box.add_theme_constant_override("separation", 14)
	battle_pause_panel.add_child(pause_box)
	var pause_title := _label("전투 일시정지", 36, Color("f1d77a"))
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_box.add_child(pause_title)
	var pause_help := _label("시뮬레이션 Tick 0 • 전투 설정", 18, Color("91aac8"))
	pause_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_box.add_child(pause_help)
	pause_box.add_child(_button("계속", _toggle_battle_pause, false, Vector2(300, 62)))
	pause_box.add_child(_button("AUTO 전환", _toggle_battle_auto, false, Vector2(300, 62)))
	pause_box.add_child(_button("배속 변경", _cycle_battle_speed, false, Vector2(300, 62)))
	pause_box.add_child(_button("전투 SKIP", _skip_battle, false, Vector2(300, 62)))
	var pause_actions := HBoxContainer.new()
	pause_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_box.add_child(pause_actions)
	pause_actions.add_child(_button("재시작", func(): SceneRouter.go("BATTLE"), false, Vector2(190, 62)))
	pause_actions.add_child(_button("나가기", _abandon_battle, false, Vector2(190, 62)))
	_update_battle_hud()

func _update_battle_hud() -> void:
	var simulation := battle_view.simulation
	var remain := maxf(0, simulation.state.time_limit - simulation.state.time_elapsed)
	var boss_text := ""
	if simulation.has_boss():
		var boss: Dictionary = simulation.alive_enemies().filter(func(unit): return unit.rank == "BOSS")[0]
		boss_text = "  보스 %d/%d [%s]" % [boss.hp, boss.max_hp, _boss_phase_hud_label(str(boss.get("phase", "PHASE_1")))]
	battle_hud.text = "WAVE %d/%d   %.1fs   TACTICAL %.2f/10%s" % [simulation.state.wave, simulation.state.wave_count, remain, simulation.state.tactical_gauge, boss_text]
	if battle_auto_button != null:
		battle_auto_button.text = "AUTO ON" if simulation.auto_enabled else "AUTO OFF"
	if battle_speed_button != null:
		battle_speed_button.text = "×%d" % battle_view.speed
	for i in range(mini(party_status_labels.size(), simulation.state.party.size())):
		var ally: Dictionary = simulation.state.party[i]
		var definition := DataRegistry.character(ally.def_id)
		var status_text := "-" if ally.statuses.is_empty() else ", ".join(ally.statuses.keys())
		if battle_portrait_layout:
			var display_name := LocalizationService.tr_key(definition.name_key).replace(" (DEV)", "")
			var hp_percent := roundi(float(ally.hp) / maxf(1.0, float(ally.max_hp)) * 100.0)
			party_status_labels[i].text = "%s\nHP %d%% · SH %s%s" % [display_name, hp_percent, _compact_number(int(ally.shield)), " · " + status_text if status_text != "-" else ""]
		else:
			party_status_labels[i].text = "%s  HP %s/%s\nSH %s  %s" % [LocalizationService.tr_key(definition.name_key), _compact_number(int(ally.hp)), _compact_number(int(ally.max_hp)), _compact_number(int(ally.shield)), status_text]
	for i in range(ultimate_buttons.size()):
		var unit: Dictionary = simulation.state.party[i]
		var skill := DataRegistry.skill(unit.ultimate_skill_id)
		ultimate_buttons[i].disabled = not SkillRuntime.can_use_ultimate(unit, skill, simulation.state.tactical_gauge)

func _boss_phase_hud_label(phase_id: String) -> String:
	match phase_id:
		"PHASE_2": return LocalizationService.tr_key("BATTLE_BOSS_PHASE_2_HUD")
		"ENRAGE": return LocalizationService.tr_key("BATTLE_BOSS_ENRAGE_HUD")
		_: return LocalizationService.tr_key("BATTLE_BOSS_PHASE_1_HUD")

func _battle_party_status_style() -> StyleBoxFlat:
	var card := StyleBoxFlat.new()
	card.bg_color = Color("071522d8")
	card.border_color = Color("2c6079cc")
	card.set_border_width_all(1)
	card.set_corner_radius_all(7)
	card.content_margin_left = 8
	card.content_margin_right = 8
	card.content_margin_top = 3
	card.content_margin_bottom = 3
	return card

func _toggle_battle_auto() -> void:
	if battle_view == null or battle_view.simulation == null: return
	battle_view.simulation.auto_enabled = not battle_view.simulation.auto_enabled
	SettingsService.values.battle_auto = battle_view.simulation.auto_enabled
	_update_battle_hud()

func _skip_battle() -> void:
	if battle_view == null or battle_view.simulation == null or battle_view.emitted_finish or battle_view.skip_in_progress:
		return
	var skip_button := battle_skip_button
	if skip_button != null:
		skip_button.disabled = true
		skip_button.text = "계산 중…"
	var started := battle_view.skip_to_result()
	# A successful skip emits battle_finished synchronously and replaces this
	# screen.  Only restore the control when the simulation guard rejected it.
	if not started and skip_button != null and is_instance_valid(skip_button):
		skip_button.disabled = false
		skip_button.text = "SKIP ▶"

func _request_ultimate(unit_id: String) -> void:
	if battle_view == null or battle_view.simulation == null: return
	var simulation := battle_view.simulation
	var unit := simulation.find_unit(unit_id)
	if unit.is_empty(): return
	var skill := DataRegistry.skill(unit.ultimate_skill_id)
	if str(skill.get("effect", "")) not in ["DAMAGE", "DEBUFF"]:
		simulation.request_ultimate(unit_id)
		return
	var targets := simulation.alive_enemies()
	if targets.size() <= 1:
		simulation.request_ultimate(unit_id, "" if targets.is_empty() else str(targets[0].uid))
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "필살기 대상 선택"
	dialog.dialog_text = "보스/엘리트/일반 적 중 대상을 지정하세요."
	var selector := OptionButton.new()
	selector.custom_minimum_size = Vector2(520, 64)
	for target in targets:
		selector.add_item("%s • %s • HP %s/%s" % [target.def_id, target.rank, _compact_number(int(target.hp)), _compact_number(int(target.max_hp))])
	dialog.add_child(selector)
	add_child(dialog)
	dialog.confirmed.connect(func(): simulation.request_ultimate(unit_id, str(targets[selector.selected].uid)); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(700, 300))

func _cycle_battle_speed() -> void:
	if battle_view == null: return
	battle_view.speed = battle_view.speed % 3 + 1
	SettingsService.values.battle_speed = battle_view.speed
	_update_battle_hud()

func _toggle_battle_pause() -> void:
	if battle_view == null: return
	battle_view.paused = not battle_view.paused
	if battle_pause_center != null: battle_pause_center.visible = battle_view.paused

func _compact_number(value: int) -> String:
	if absi(value) >= 1000000: return "%.1fM" % (value / 1000000.0)
	if absi(value) >= 1000: return "%.1fK" % (value / 1000.0)
	return str(value)

func _battle_finished(result: Dictionary) -> void:
	if AppState.relay_active():
		_relay_battle_finished(result)
		return
	last_battle_result = result
	last_rewards = {}
	last_reward_report = {}
	var pre_profile := AppState.profile.duplicate(true)
	var battle_map_id := AppState.map_id_for_stage(AppState.selected_stage_id)
	var pending_special_event := AppState.pending_map_special_event(battle_map_id)
	var first := false
	var story_queued := false
	var stage_chapter_id := ""
	if result.victory:
		var stage := DataRegistry.stage(AppState.selected_stage_id)
		stage_chapter_id = str(stage.get("chapter_id", ""))
		var stars := 1 + (1 if int(result.survivors) == 5 else 0) + (1 if float(result.time) <= float(stage.target_time) else 0)
		# A battle transaction receives one immutable token at entry.  Reloads,
		# duplicate callbacks, and result-screen revisits cannot mutate canonical
		# progression or grant it twice.  Claim is deliberately the commit gate:
		# tokenless/stale victory callbacks remain presentation-only no-ops.
		if AppState.claim_pending_reward_once(stage.id, battle_map_id):
			first = AppState.record_stage_clear(stage.id, stars)
			last_rewards = RewardService.resolve(stage.id, 1, AppState.battle_seed + int(result.ticks), first)
			AccountProgression.grant_stage_xp(int(stage.stamina_cost), 20 if first else 0)
			for character_id in AppState.get_party(): RelationshipService.grant(character_id, 10)
			story_queued = AppState.queue_story_event("STAGE_CLEAR", str(stage.id))
	AppState.apply_battle_result_to_map(AppState.selected_stage_id, bool(result.get("victory", false)), battle_map_id)
	var post_profile := AppState.profile.duplicate(true)
	var pending_story := AppState.next_pending_story_trigger() if story_queued else {}
	last_reward_report = {
		"source_type": "BATTLE",
		"source_id": AppState.selected_stage_id,
		"rewards": last_rewards.duplicate(true),
		"pre_inventory": pre_profile.get("inventory", {}).duplicate(true),
		"post_inventory": post_profile.get("inventory", {}).duplicate(true),
		"growth": GrowthAffordabilityAnalyzerScript.analyze(pre_profile, post_profile),
		"progress": {
			"first_clear": first,
			"newly_unlocked_stages": _newly_unlocked_stage_ids(pre_profile, post_profile),
			"hard_route_unlocked": not stage_chapter_id.is_empty() and not bool(pre_profile.get("chapter_progress", {}).get(stage_chapter_id, {}).get("hard_unlocked", false)) and bool(post_profile.get("chapter_progress", {}).get(stage_chapter_id, {}).get("hard_unlocked", false)),
			"pending_story_id": str(pending_story.get("scenario_id", "")),
			"event_encounter": _event_encounter_result_payload(pending_special_event, bool(result.get("victory", false))),
			"newly_recruited_characters": _newly_recruited_character_ids(pre_profile, post_profile),
		},
	}
	SaveService.save_game()
	SceneRouter.go("RESULT")

func _relay_battle_finished(result: Dictionary) -> void:
	last_battle_result = result.duplicate(true)
	last_rewards = {}
	last_reward_report = {}
	var pre_profile := AppState.profile.duplicate(true)
	var relay_id := str(RelayServiceScript.active_run(AppState.profile).get("relay_id", ""))
	var outcome := RelayServiceScript.record_segment_result(AppState.profile, result)
	if not bool(outcome.get("ok", false)):
		footer_status.text = "릴레이 결과 반영 실패: %s" % str(outcome.get("error", "UNKNOWN"))
		SceneRouter.go("RELAY")
		return
	if bool(result.get("victory", false)):
		for character_id in battle_party_ids:
			RelationshipService.grant(character_id, 10)
	last_rewards = (outcome.get("rewards", {}) as Dictionary).duplicate(true)
	var post_profile := AppState.profile.duplicate(true)
	last_reward_report = {
		"source_type": "RELAY",
		"source_id": relay_id,
		"rewards": last_rewards.duplicate(true),
		"pre_inventory": pre_profile.get("inventory", {}).duplicate(true),
		"post_inventory": post_profile.get("inventory", {}).duplicate(true),
		"growth": GrowthAffordabilityAnalyzerScript.analyze(pre_profile, post_profile),
		"relay": {
			"victory": bool(result.get("victory", false)),
			"retry": bool(outcome.get("retry", false)),
			"advanced": bool(outcome.get("advanced", false)),
			"completed": bool(outcome.get("completed", false)),
			"first_completion": bool(outcome.get("first_completion", false)),
			"grade": str(outcome.get("grade", "")),
			"next_segment": int(outcome.get("segment_index", -1)) + 1,
		},
	}
	SaveService.save_game()
	SceneRouter.go("RESULT")

func _abandon_battle() -> void:
	if AppState.relay_active():
		SaveService.save_game()
		SceneRouter.go("RELAY")
		return
	AppState.abandon_pending_map_encounter(AppState.map_id_for_stage(AppState.selected_stage_id))
	SaveService.save_game()
	SceneRouter.go("STAGE_SELECT")

func _display_item_name(item_id: String) -> String:
	var item := DataRegistry.by_id("items", item_id)
	var fallback := item_id.replace("_", " ")
	return LocalizationService.tr_key(str(item.get("name_key", fallback))).replace(" (DEV)", "")

func _display_character_name(character_id: String) -> String:
	var definition := DataRegistry.character(character_id)
	return LocalizationService.tr_key(str(definition.get("name_key", character_id))).replace(" (DEV)", "")

func _newly_recruited_character_ids(pre_profile: Dictionary, post_profile: Dictionary) -> Array[String]:
	var recruited: Array[String] = []
	for character_value in DataRegistry.list_of("characters"):
		var character: Dictionary = character_value
		var character_id := str(character.get("id", ""))
		if character_id.is_empty():
			continue
		var before: Dictionary = pre_profile.get("roster", {}).get(character_id, {})
		var after: Dictionary = post_profile.get("roster", {}).get(character_id, {})
		if not bool(before.get("unlocked", false)) and bool(after.get("unlocked", false)):
			recruited.append(character_id)
	return recruited

func _event_encounter_result_payload(special_event: Dictionary, victory: bool, map_id := "") -> Dictionary:
	if special_event.is_empty() or not victory:
		return {}
	var character_id := str(special_event.get("character_id", ""))
	var resolved_map_id := map_id if not map_id.is_empty() else AppState.map_id_for_stage(AppState.selected_stage_id)
	var recruitment_state := str(AppState.chapter_map_state(resolved_map_id).get("recruitment_states", {}).get(character_id, ""))
	return {
		"character_id": character_id,
		"recruitment_timing": str(special_event.get("recruitment_timing", "")),
		"recruit_after_stage_id": str(special_event.get("recruit_after_stage_id", "")),
		"recruitment_state": recruitment_state,
	}

func _display_runtime_name(runtime_id: String) -> String:
	# Runtime IDs are stable save/combat keys, not player-facing text. Every
	# result, reward, wave, and inventory view flows through this resolver so
	# CHR001 / TRAINING_NOTE_M-style implementation codes cannot leak into a
	# release build.
	var item := DataRegistry.by_id("items", runtime_id)
	if not item.is_empty():
		return LocalizationService.tr_key(str(item.get("name_key", runtime_id))).replace(" (DEV)", "")
	var character := DataRegistry.character(runtime_id)
	if not character.is_empty():
		return LocalizationService.tr_key(str(character.get("name_key", runtime_id))).replace(" (DEV)", "")
	var enemy := DataRegistry.enemy(runtime_id)
	if not enemy.is_empty():
		return LocalizationService.tr_key(str(enemy.get("name_key", runtime_id))).replace(" (DEV)", "")
	var weapon := DataRegistry.by_id("weapons", runtime_id)
	if not weapon.is_empty():
		return LocalizationService.tr_key(str(weapon.get("name_key", runtime_id))).replace(" (DEV)", "")
	return runtime_id.replace("_", " ")

func _growth_candidate_text(candidate: Dictionary) -> String:
	var kind := str(candidate.get("kind", ""))
	var character_id := str(candidate.get("character_id", ""))
	var character_name := _display_character_name(character_id)
	if kind == "LEVEL":
		return "%s\nLv.%d → Lv.%d 가능" % [character_name, int(candidate.get("from_level", 0)), int(candidate.get("to_level", 0))]
	if kind == "BREAKTHROUGH":
		return "%s\n돌파 B%d → B%d 가능" % [character_name, int(candidate.get("from_breakthrough", 0)), int(candidate.get("to_breakthrough", 0))]
	if kind == "SKILL":
		var definition := DataRegistry.character(character_id)
		var slot := str(candidate.get("slot", "normal"))
		var skill_id := str(definition.get(slot + "_skill_id", ""))
		var skill := DataRegistry.skill(skill_id)
		var skill_name := LocalizationService.tr_key(str(skill.get("name_key", slot.to_upper()))).replace(" (DEV)", "")
		return "%s\n%s  Lv.%d → Lv.%d 가능" % [character_name, skill_name, int(candidate.get("from_level", 0)), int(candidate.get("to_level", 0))]
	var weapon_id := str(candidate.get("weapon_id", ""))
	var weapon := DataRegistry.by_id("weapons", weapon_id)
	var weapon_name := LocalizationService.tr_key(str(weapon.get("name_key", weapon_id))).replace(" (DEV)", "")
	if kind == "WEAPON_TIER":
		return "%s\nT%d → T%d 티어업 가능" % [weapon_name, int(candidate.get("from_tier", 0)), int(candidate.get("to_tier", 0))]
	return "%s\nLv.%d → Lv.%d 가능" % [weapon_name, int(candidate.get("from_level", 0)), int(candidate.get("to_level", 0))]

func _goto_growth_candidate(candidate: Dictionary) -> void:
	var character_id := str(candidate.get("character_id", ""))
	if character_id.is_empty():
		var weapon_id := str(candidate.get("weapon_id", ""))
		for roster_id in AppState.profile.get("roster", {}):
			if str(AppState.profile.roster[roster_id].get("equipped_weapon_id", "")) == weapon_id:
				character_id = str(roster_id)
				break
	if character_id.is_empty(): character_id = str(AppState.get_party()[0])
	AppState.selected_character_id = character_id
	SceneRouter.go("GROWTH")

func _growth_plan_action_text(action: Dictionary) -> String:
	var kind := str(action.get("kind", ""))
	var character_id := str(action.get("character_id", ""))
	if kind == "LEVEL":
		return "%s · %s 사용" % [_display_character_name(character_id), _display_item_name(str(action.get("material_id", "")))]
	if kind == "BREAKTHROUGH":
		return "%s · 돌파" % _display_character_name(character_id)
	if kind == "SKILL":
		return "%s · %s 강화" % [_display_character_name(character_id), str(action.get("slot", "")).to_upper()]
	var weapon_id := str(action.get("weapon_id", ""))
	if kind == "WEAPON_LEVEL":
		return "%s · %s 사용" % [_display_runtime_name(weapon_id), _display_item_name(str(action.get("material_id", "")))]
	if kind == "WEAPON_TIER":
		return "%s · 티어업" % _display_runtime_name(weapon_id)
	return "권장 성장"

func _apply_recommended_party_growth(max_actions := 12) -> void:
	var before_profile := AppState.profile.duplicate(true)
	var result: Dictionary = GrowthPlanBuilderScript.execute_recommended_batch(AppState.get_party(), max_actions)
	last_growth_plan_actions = result.get("actions", []).duplicate(true)
	var after_profile := AppState.profile.duplicate(true)
	var accounting: Dictionary = result.get("accounting", {})
	last_growth_plan_report = {
		"requested_limit": mini(max_actions, 12),
		"applied_count": last_growth_plan_actions.size(),
		"planned_count": int(accounting.get("planned", 0)),
		"successful_count": int(accounting.get("successful", last_growth_plan_actions.size())),
		"rejected_count": int(accounting.get("rejected", 0)),
		"preview_matches_execution": bool(result.get("preview_matches_execution", false)),
		"planned_actions": result.get("preview_actions", []).duplicate(true),
		"pre_inventory": before_profile.get("inventory", {}).duplicate(true),
		"post_inventory": after_profile.get("inventory", {}).duplicate(true),
		"pre_party": _party_growth_snapshot(before_profile),
		"post_party": _party_growth_snapshot(after_profile),
		"has_more": bool(result.get("has_more", not GrowthPlanBuilderScript.next_legal_action(AppState.get_party()).is_empty())),
		"error": str(result.get("error", "")),
	}
	if not bool(result.get("ok", false)):
		footer_status.text = "권장 성장 %d단계 적용 후 중단: %s" % [last_growth_plan_actions.size(), str(result.get("error", "UNKNOWN"))]
		_show_screen("GROWTH")
		return
	if last_growth_plan_actions.is_empty():
		footer_status.text = "현재 파티에 즉시 적용 가능한 권장 성장이 없습니다."
	else:
		SaveService.save_game()
		footer_status.text = "권장 성장 %d단계 적용 완료%s" % [last_growth_plan_actions.size(), " · 추가 권장 성장 있음" if bool(last_growth_plan_report.get("has_more", false)) else ""]
	_show_screen("GROWTH")

func _party_growth_snapshot(profile_value: Dictionary) -> Dictionary:
	var snapshot: Dictionary = {}
	for character_id_value in AppState.get_party():
		var character_id := str(character_id_value)
		var state: Dictionary = profile_value.get("roster", {}).get(character_id, {})
		snapshot[character_id] = {
			"level": int(state.get("level", 1)),
			"xp": int(state.get("xp", 0)),
			"breakthrough": int(state.get("breakthrough", 0)),
		}
	return snapshot

func _growth_plan_result_text(report: Dictionary) -> String:
	if report.is_empty():
		return ""
	var level_changes: Array[String] = []
	var before_party: Dictionary = report.get("pre_party", {})
	var after_party: Dictionary = report.get("post_party", {})
	for character_id_value in AppState.get_party():
		var character_id := str(character_id_value)
		var before: Dictionary = before_party.get(character_id, {})
		var after: Dictionary = after_party.get(character_id, {})
		if int(before.get("level", 1)) != int(after.get("level", 1)) or int(before.get("breakthrough", 0)) != int(after.get("breakthrough", 0)):
			level_changes.append("%s Lv.%d→%d%s" % [_display_character_name(character_id), int(before.get("level", 1)), int(after.get("level", 1)), " · B%d→B%d" % [int(before.get("breakthrough", 0)), int(after.get("breakthrough", 0))] if int(before.get("breakthrough", 0)) != int(after.get("breakthrough", 0)) else ""])
	var spent: Array[String] = []
	var before_inventory: Dictionary = report.get("pre_inventory", {})
	var after_inventory: Dictionary = report.get("post_inventory", {})
	var ids: Array = before_inventory.keys()
	ids.sort()
	for item_id_value in ids:
		var item_id := str(item_id_value)
		var used := int(before_inventory.get(item_id, 0)) - int(after_inventory.get(item_id, 0))
		if used > 0:
			spent.append("%s %s" % [_display_item_name(item_id), MathUtil.comma(used)])
	var message := "예정 %d · 실제 성공 %d/%d단계" % [int(report.get("planned_count", report.get("applied_count", 0))), int(report.get("successful_count", report.get("applied_count", 0))), int(report.get("requested_limit", 12))]
	if int(report.get("rejected_count", 0)) > 0:
		message += " · 거절 %d" % int(report.get("rejected_count", 0))
	if not bool(report.get("preview_matches_execution", true)):
		message += "\n경고: 예상과 실행 순서가 달라졌습니다."
	if not level_changes.is_empty(): message += "\n파티 변화: " + " / ".join(level_changes)
	if not spent.is_empty(): message += "\n소비: " + " · ".join(spent)
	message += "\n" + ("추가 권장 성장 있음 — 계속 적용할 수 있습니다." if bool(report.get("has_more", false)) else "현재 권장 성장 단계가 없습니다.")
	if not str(report.get("error", "")).is_empty(): message += "\n중단 사유: " + str(report.get("error", ""))
	return message

func _reward_item_card(parent: Node, item_name: String, amount: int, before: int, after: int, font_size: int) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, 92.0 * _portrait_ui_scale())
	var style := StyleBoxFlat.new()
	style.bg_color = Color("142b3d")
	style.border_color = Color("3e8f91")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	card.add_child(body)
	var heading := HBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(heading)
	var name_label := _label(item_name, font_size + 1, Color("e7f7f4"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(name_label)
	var amount_label := _label("+%s" % MathUtil.comma(amount), font_size + 6, Color("76f1c9"))
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(amount_label)
	body.add_child(_label("보유량   %s  →  %s" % [MathUtil.comma(before), MathUtil.comma(after)], font_size - 1, Color("b8d8e5")))

func _reward_summary_card(parent: VBoxContainer, text_value: String, font_size: int) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1e2737")
	style.border_color = Color("8c7a3f")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	card.add_child(_label(text_value, font_size, Color("e6edf8")))

func _add_reward_clarity(parent: VBoxContainer, font_size: int) -> void:
	var source_type := str(last_reward_report.get("source_type", "BATTLE"))
	parent.add_child(_label("보상 내역 · 탐색 보상" if source_type != "BATTLE" else "보상 내역 · 전투 보상", font_size + 5, Color("8fe0b6")))
	var rewards: Dictionary = last_reward_report.get("rewards", last_rewards)
	var before_inventory: Dictionary = last_reward_report.get("pre_inventory", {})
	var after_inventory: Dictionary = last_reward_report.get("post_inventory", AppState.profile.get("inventory", {}))
	if rewards.is_empty():
		parent.add_child(_label("획득 보상 없음", font_size, Color("91aac8")))
	else:
		# At the 1280×720 review size a single reward column pushes the NEW
		# affordance below the fold. Two compact cards preserve item diffs while
		# keeping the growth impact visible without a scroll on landscape screens.
		var reward_grid := GridContainer.new()
		reward_grid.columns = 1 if _is_portrait_layout() else 2
		reward_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reward_grid.add_theme_constant_override("h_separation", 10)
		reward_grid.add_theme_constant_override("v_separation", 8)
		parent.add_child(reward_grid)
		var reward_keys: Array = rewards.keys()
		reward_keys.sort()
		for item_id in reward_keys:
			var before := int(before_inventory.get(item_id, 0))
			var after := int(after_inventory.get(item_id, before + int(rewards[item_id])))
			_reward_item_card(reward_grid, _display_item_name(str(item_id)), int(rewards[item_id]), before, after, font_size)
	var growth: Dictionary = last_reward_report.get("growth", {})
	var newly: Array = growth.get("newly_affordable", [])
	parent.add_child(_label("이번 보상으로 새롭게 가능한 성장", font_size + 5, Color("f1d77a")))
	if newly.is_empty():
		_reward_summary_card(parent, "새로 열린 성장 없음\n이번 보상으로 새롭게 열린 성장 항목은 없습니다.", font_size - 1)
	else:
		for candidate in newly:
			var candidate_button := _button("NEW  ·  " + _growth_candidate_text(candidate), func(value: Dictionary = candidate.duplicate(true)): _goto_growth_candidate(value), false, Vector2(460, 76))
			_make_primary_button(candidate_button)
			parent.add_child(candidate_button)
	var summary: Dictionary = growth.get("summary", {})
	_reward_summary_card(parent, "현재 재료로 성장 가능한 후보\n레벨업 %d명 · 돌파 %d명 · 스킬 %d명 · 무기 강화 %d개 · 티어업 %d개" % [int(summary.get("level_characters", 0)), int(summary.get("breakthrough_characters", 0)), int(summary.get("skill_characters", 0)), int(summary.get("weapon_levels", 0)), int(summary.get("weapon_tiers", 0))], font_size)
	_add_progress_unlock_summary(parent, font_size)

func _unlocked_stage_ids_for_profile(profile_snapshot: Dictionary) -> Array[String]:
	var unlocked: Array[String] = []
	var stars: Dictionary = profile_snapshot.get("stage_stars", {})
	for stage_value in DataRegistry.list_of("stages"):
		var stage: Dictionary = stage_value
		var stage_id := str(stage.get("id", ""))
		var stage_number := int(stage.get("stage_number", 0))
		var chapter_id := str(stage.get("chapter_id", ""))
		var chapter_progress: Dictionary = profile_snapshot.get("chapter_progress", {}).get(chapter_id, {})
		var chapter_definition: Dictionary = DataRegistry.chapter(chapter_id)
		if not bool(chapter_progress.get("unlocked", false)):
			continue
		var is_unlocked := false
		if str(stage.get("mode", "NORMAL")) == "HARD":
			var hard_route: Array = chapter_definition.get("hard_stage_ids", [])
			var prior_hard_id := str(hard_route[stage_number - 2]) if stage_number > 1 and stage_number - 2 < hard_route.size() else ""
			is_unlocked = bool(chapter_progress.get("hard_unlocked", false)) and (stage_number == 1 or int(stars.get(prior_hard_id, 0)) > 0)
		else:
			is_unlocked = stage_number == 1 or int(chapter_progress.get("normal_highest", 0)) >= stage_number - 1
		if is_unlocked and not stage_id.is_empty():
			unlocked.append(stage_id)
	unlocked.sort()
	return unlocked

func _newly_unlocked_stage_ids(pre_profile: Dictionary, post_profile: Dictionary) -> Array[String]:
	var before := _unlocked_stage_ids_for_profile(pre_profile)
	var newly: Array[String] = []
	for stage_id in _unlocked_stage_ids_for_profile(post_profile):
		if not before.has(stage_id):
			newly.append(stage_id)
	return newly

func _add_progress_unlock_summary(parent: VBoxContainer, font_size: int) -> void:
	var progress: Dictionary = last_reward_report.get("progress", {})
	var lines: Array[String] = []
	if bool(progress.get("first_clear", false)):
		lines.append("첫 클리어 기록 완료")
	var newly: Array = progress.get("newly_unlocked_stages", [])
	for stage_id_value in newly:
		var stage := DataRegistry.stage(str(stage_id_value))
		lines.append("새 작전 해금 · %s" % LocalizationService.tr_key(str(stage.get("name_key", stage_id_value))))
	if bool(progress.get("hard_route_unlocked", false)):
		lines.append("HARD 탐색 경로가 열렸습니다.")
	var event_encounter: Dictionary = progress.get("event_encounter", {})
	if not event_encounter.is_empty():
		var event_name := _display_character_name(str(event_encounter.get("character_id", "")))
		if str(event_encounter.get("recruitment_state", "")) == "READY":
			lines.append(LocalizationService.tr_key("RESULT_EVENT_RECRUITED") % event_name)
		elif str(event_encounter.get("recruitment_state", "")) == "PENDING":
			var later_stage := DataRegistry.stage(str(event_encounter.get("recruit_after_stage_id", "")))
			var later_name := LocalizationService.tr_key(str(later_stage.get("name_key", "")))
			lines.append(LocalizationService.tr_key("RESULT_EVENT_TRACKING") % [event_name, later_name])
	for character_id_value in progress.get("newly_recruited_characters", []):
		var recruited_name := _display_character_name(str(character_id_value))
		var recruited_line := LocalizationService.tr_key("RESULT_EVENT_RECRUITED") % recruited_name
		if not lines.has(recruited_line):
			lines.append(recruited_line)
	var scenario_id := str(progress.get("pending_story_id", ""))
	if not scenario_id.is_empty():
		var scenario := DataRegistry.by_id("scenarios", scenario_id)
		var title_key := str(scenario.get("title_key", ""))
		lines.append("이어지는 이야기 · %s" % (LocalizationService.tr_key(title_key) if not title_key.is_empty() else LocalizationService.tr_key("UI_STORY_TITLE")))
	if not lines.is_empty():
		_reward_summary_card(parent, "진행 변화\n" + "\n".join(lines), font_size)
	var relay: Dictionary = last_reward_report.get("relay", {})
	if not relay.is_empty():
		var relay_lines: Array[String] = []
		if bool(relay.get("retry", false)):
			relay_lines.append("현재 구간 패배 · 앞선 구간 승리와 부대 잠금은 유지됩니다.")
		elif bool(relay.get("completed", false)):
			relay_lines.append("계약 완주 · 등급 %s" % str(relay.get("grade", "B")))
			relay_lines.append("첫 완주 보상 지급" if bool(relay.get("first_completion", false)) else "재도전 기록 갱신 · 첫 완주 보상은 이미 수령했습니다.")
		elif bool(relay.get("advanced", false)):
			relay_lines.append("%d구간 완료 · 다음 부대가 출전합니다." % int(relay.get("next_segment", 0)))
		if not relay_lines.is_empty():
			_reward_summary_card(parent, "릴레이 진행\n" + "\n".join(relay_lines), font_size)

func _result_feature_character() -> Dictionary:
	return result_feature_character_for_report(last_reward_report, battle_party_ids if not battle_party_ids.is_empty() else AppState.get_party())

func _reward_celebration_queue() -> Array[Dictionary]:
	# Result presentation reads the committed delta only. It cannot call a
	# reward/recruitment/progression service, so close/skip/rebuild/reload never
	# turns a visual acknowledgement into a second grant.
	var entries: Array[Dictionary] = []
	var progress: Dictionary = last_reward_report.get("progress", {})
	if bool(last_battle_result.get("victory", false)):
		entries.append({
			"kind": "CLEAR",
			"eyebrow": "FIRST CLEAR" if bool(progress.get("first_clear", false)) else "OPERATION COMPLETE",
			"title": "첫 작전 클리어 기록" if bool(progress.get("first_clear", false)) else "작전 승리",
			"body": "승리 기록이 확정되었습니다. 이어지는 획득 보상을 확인하세요.",
			"character": _result_feature_character(),
			"accent": Color("9cb8ff"),
		})
	# New allies are individual cards and use the actual transition delta. A
	# deferred contact therefore appears only on the later victory where its
	# authored recruitment gate is really met.
	for character_id_value in progress.get("newly_recruited_characters", []):
		var character := DataRegistry.character(str(character_id_value))
		if not character.is_empty():
			entries.append({
				"kind": "ALLY",
				"eyebrow": "NEW ALLY JOINED",
				"title": "%s 합류" % _display_character_name(str(character.get("id", ""))),
				"body": "동료 계약이 확정되었습니다. 파티·성장 화면에서 바로 편성할 수 있습니다.",
				"character": character,
				"accent": Color("ffd77a"),
			})
	# Only data-authored RARE/MAJOR item deltas become individual celebration
	# pages; credit and ordinary consumables stay in the concise reward ledger.
	var rewards: Dictionary = last_reward_report.get("rewards", last_rewards)
	var reward_ids: Array = rewards.keys()
	reward_ids.sort()
	for item_id_value in reward_ids:
		var item_id := str(item_id_value)
		var item := DataRegistry.by_id("items", item_id)
		if str(item.get("presentation_tier", "STANDARD")) not in ["RARE", "MAJOR"]:
			continue
		entries.append({
			"kind": "KEY_ITEM",
			"eyebrow": "KEY ACQUISITION",
			"title": _display_item_name(item_id),
			"body": "%s 등급 전리품  +%s" % [str(item.get("presentation_tier", "RARE")), MathUtil.comma(int(rewards[item_id]))],
			"character": _result_feature_character(),
			"accent": Color("81e9d5") if str(item.get("presentation_tier", "")) == "RARE" else Color("ffd77a"),
		})
	return entries

func _add_reward_celebration(parent: Node, font_size: int, compact := false) -> void:
	var celebrations := _reward_celebration_queue()
	if celebrations.is_empty():
		return
	var card := Control.new()
	card.name = "RewardCelebrationQueue"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var height := (188.0 if compact else 236.0) * _portrait_ui_scale()
	card.custom_minimum_size = Vector2(0.0, height)
	parent.add_child(card)
	var backdrop := Panel.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("0a2331f2")
	card_style.border_color = Color("81e9d5")
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(16)
	backdrop.add_theme_stylebox_override("panel", card_style)
	card.add_child(backdrop)
	# The translucent right-side half-body is a non-interactive presentation
	# layer. A character-specific card is retained for ally joins; key items use
	# the actual reporting lead, never a made-up illustration.
	var art := TextureRect.new()
	art.name = "RewardCelebrationHalfBodyArt"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchor(SIDE_LEFT, 0.56)
	art.set_anchor(SIDE_TOP, 0.0)
	art.set_anchor(SIDE_RIGHT, 1.0)
	art.set_anchor(SIDE_BOTTOM, 1.0)
	art.offset_left = -10.0
	art.offset_top = -height * 0.18
	art.offset_right = -8.0
	art.offset_bottom = 0.0
	art.modulate = Color(1.0, 1.0, 1.0, 0.46)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)
	var copy := VBoxContainer.new()
	copy.set_anchor(SIDE_LEFT, 0.0)
	copy.set_anchor(SIDE_TOP, 0.0)
	copy.set_anchor(SIDE_RIGHT, 0.67)
	copy.set_anchor(SIDE_BOTTOM, 1.0)
	copy.offset_left = 22.0
	copy.offset_top = 17.0
	copy.offset_right = -6.0
	copy.offset_bottom = -54.0
	copy.add_theme_constant_override("separation", 3)
	card.add_child(copy)
	var eyebrow := _label("", font_size - 1, Color("81e9d5"))
	copy.add_child(eyebrow)
	var title := _label("", font_size + (7 if compact else 10), Color("fff4d4"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_color_override("font_outline_color", Color("05111d"))
	copy.add_child(title)
	var body := _label("", font_size, Color("d8edf3"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(body)
	var controls := HBoxContainer.new()
	controls.set_anchor(SIDE_LEFT, 0.0)
	controls.set_anchor(SIDE_TOP, 1.0)
	controls.set_anchor(SIDE_RIGHT, 0.67)
	controls.set_anchor(SIDE_BOTTOM, 1.0)
	controls.offset_left = 18.0
	controls.offset_top = -46.0
	controls.offset_right = -8.0
	controls.offset_bottom = -10.0
	controls.add_theme_constant_override("separation", 8)
	card.add_child(controls)
	var page_counter := _label("", font_size - 2, Color("b8d8e5"))
	page_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls.add_child(page_counter)
	var skip_button := _button("보상 스킵", func() -> void: pass, false, Vector2(132 if compact else 152, 42 if compact else 48))
	skip_button.name = "RewardCelebrationSkip"
	controls.add_child(skip_button)
	var next_button := _button("다음", func() -> void: pass, false, Vector2(112 if compact else 132, 42 if compact else 48))
	next_button.name = "RewardCelebrationNext"
	controls.add_child(next_button)
	var queue_index := 0
	var show_entry: Callable
	show_entry = func() -> void:
		var entry: Dictionary = celebrations[queue_index]
		var accent: Color = entry.get("accent", Color("81e9d5"))
		card_style.border_color = accent
		eyebrow.text = str(entry.get("eyebrow", "ACQUISITION"))
		eyebrow.add_theme_color_override("font_color", accent)
		title.text = str(entry.get("title", ""))
		body.text = str(entry.get("body", ""))
		page_counter.text = "%d / %d" % [queue_index + 1, celebrations.size()]
		next_button.text = "결과 보기" if queue_index >= celebrations.size() - 1 else "다음"
		var entry_character: Dictionary = entry.get("character", {})
		art.texture = _asset_texture(str(entry_character.get("portrait_asset_id", ""))) if not entry_character.is_empty() else null
		art.visible = art.texture != null
		card.modulate = Color(1.0, 1.0, 1.0, 0.0)
		card.scale = Vector2(0.985, 0.985)
		var reveal := create_tween()
		reveal.set_parallel(true)
		reveal.tween_property(card, "modulate", Color.WHITE, 0.14)
		reveal.tween_property(card, "scale", Vector2.ONE, 0.18)
	show_entry.call()
	skip_button.pressed.connect(func() -> void: card.queue_free())
	next_button.pressed.connect(func() -> void:
		if queue_index >= celebrations.size() - 1:
			card.queue_free()
			return
		queue_index += 1
		show_entry.call()
	)

func result_feature_character_for_report(report: Dictionary, party: Array) -> Dictionary:
	# A companion-contact victory is a story result as well as a battle result.
	# The eventual N09-style recruitment has no pending special-event payload, so
	# newly committed recruits take precedence. This prevents a genuine delayed
	# join notice from being paired with an unrelated party-lead portrait.
	var progress: Dictionary = report.get("progress", {})
	for recruited_id_value in progress.get("newly_recruited_characters", []):
		var recruited_character := DataRegistry.character(str(recruited_id_value))
		if not recruited_character.is_empty():
			return recruited_character
	var event_encounter: Dictionary = progress.get("event_encounter", {})
	var event_character_id := str(event_encounter.get("character_id", ""))
	if not event_character_id.is_empty():
		var event_character := DataRegistry.character(event_character_id)
		if not event_character.is_empty():
			return event_character
	return DataRegistry.character(str(party[0])) if not party.is_empty() else {}

func _show_result() -> void:
	AudioService.play_bgm("audio_bgm_lobby")
	var result_header := result_header_data(last_reward_report)
	_title(str(result_header.title), str(result_header.subtitle))
	# A desktop-side illustration/report split spills past a 390 px portrait
	# viewport.  Keep the complete report scrollable, but reserve a separate
	# bottom action rail inside the device safe area so map return is never
	# stranded below the fold.
	if _is_portrait_layout():
		_show_result_portrait()
		return
	# Keep the full report scrollable independently from the action rail.  The
	# former expanding HBox consumed the complete landscape height and could
	# leave the return/growth actions below the visible safe area.
	var report_scroll := ScrollContainer.new()
	report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	report_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(report_scroll)
	var compact_landscape := _is_compact_landscape_layout()
	var hero := HBoxContainer.new()
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.custom_minimum_size = Vector2(0.0, 360.0 if compact_landscape else 500.0)
	hero.add_theme_constant_override("separation", 18)
	report_scroll.add_child(hero)
	var lead := _result_feature_character()
	var art_panel := PanelContainer.new()
	art_panel.custom_minimum_size = Vector2(220, 360) if compact_landscape else Vector2(260, 500)
	hero.add_child(art_panel)
	art_panel.add_child(_art_rect(str(lead.portrait_asset_id), Vector2(200, 330) if compact_landscape else Vector2(240, 470)))
	var box := _panel_box(hero)
	box.add_child(_label("VICTORY" if last_battle_result.get("victory", false) else "DEFEAT", 52, Color("f1d77a") if last_battle_result.get("victory", false) else Color("ff7f8a")))
	box.add_child(_label("시간 %.2fs  ·  생존 %d" % [last_battle_result.get("time", 0), last_battle_result.get("survivors", 0)], 26))
	_add_reward_celebration(box, 20)
	_add_reward_clarity(box, 23)
	box.add_child(_label("가한 피해\n%s\n\n회복\n%s" % [_format_counts(last_battle_result.get("damage", {})), _format_counts(last_battle_result.get("healing", {}))], 19, Color("cdd5e3")))
	var actions := HBoxContainer.new()
	content.add_child(actions)
	var result_is_relay := str(last_reward_report.get("source_type", "")) == "RELAY"
	var growth_party := battle_party_ids if result_is_relay and not battle_party_ids.is_empty() else AppState.get_party()
	actions.add_child(_button("권장 파티 성장", func(party := growth_party): AppState.selected_character_id = str(party[0]); SceneRouter.go("GROWTH"), false, Vector2(220, 66)))
	actions.add_child(_button("릴레이 작전으로" if result_is_relay else "챕터 맵으로", func(): SceneRouter.go("RELAY" if result_is_relay else "STAGE_SELECT"), false, Vector2(220, 66)))
	actions.add_child(_button("홈", func(): SceneRouter.go("HOME"), false, Vector2(160, 66)))

func _show_result_portrait() -> void:
	var ui_scale := _portrait_ui_scale()
	var report_scroll := ScrollContainer.new()
	report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	report_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(report_scroll)
	var report := VBoxContainer.new()
	report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report.add_theme_constant_override("separation", roundi(10.0 * ui_scale))
	report_scroll.add_child(report)
	var lead := _result_feature_character()
	var art_panel := PanelContainer.new()
	art_panel.custom_minimum_size = Vector2(0.0, 224.0 * ui_scale)
	report.add_child(art_panel)
	art_panel.add_child(_art_rect(str(lead.portrait_asset_id), Vector2(310, 218)))
	var box := _panel_box(report)
	box.add_child(_label("VICTORY" if last_battle_result.get("victory", false) else "DEFEAT", 40, Color("f1d77a") if last_battle_result.get("victory", false) else Color("ff7f8a")))
	box.add_child(_label("시간 %.2fs  ·  생존 %d" % [last_battle_result.get("time", 0), last_battle_result.get("survivors", 0)], 20))
	box.add_child(_label("결정론 기록  %s" % str(last_battle_result.get("event_hash", "")).left(16), 14, Color("7e9dbd")))
	_add_reward_celebration(box, 15, true)
	_add_reward_clarity(box, 16)
	box.add_child(_label("가한 피해\n%s\n\n회복\n%s" % [_format_counts(last_battle_result.get("damage", {})), _format_counts(last_battle_result.get("healing", {}))], 15, Color("cdd5e3")))
	var actions := GridContainer.new()
	actions.columns = 2
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", roundi(7.0 * ui_scale))
	content.add_child(actions)
	var result_is_relay := str(last_reward_report.get("source_type", "")) == "RELAY"
	var growth_party := battle_party_ids if result_is_relay and not battle_party_ids.is_empty() else AppState.get_party()
	actions.add_child(_button("권장 파티 성장", func(party := growth_party): AppState.selected_character_id = str(party[0]); SceneRouter.go("GROWTH"), false, Vector2(320, 52)))
	actions.add_child(_button("릴레이 작전으로" if result_is_relay else "챕터 맵으로", func(): SceneRouter.go("RELAY" if result_is_relay else "STAGE_SELECT"), false, Vector2(320, 52)))
	actions.add_child(_button("홈", func(): SceneRouter.go("HOME"), false, Vector2(320, 52)))

func _sweep(count: int) -> void:
	var pre_profile := AppState.profile.duplicate(true)
	var result := RewardService.sweep(AppState.selected_stage_id, count, AppState.battle_seed + count)
	if result.ok:
		last_battle_result = {"victory": true, "time": 0.0, "survivors": 5, "seed": AppState.battle_seed + count, "event_hash": "SWEEP_USES_REWARD_RESOLVER", "damage": {}, "healing": {}}
		last_rewards = result.value
		var post_profile := AppState.profile.duplicate(true)
		last_reward_report = {
			"source_type": "SWEEP", "source_id": AppState.selected_stage_id,
			"rewards": last_rewards.duplicate(true),
			"pre_inventory": pre_profile.get("inventory", {}).duplicate(true),
			"post_inventory": post_profile.get("inventory", {}).duplicate(true),
			"growth": GrowthAffordabilityAnalyzerScript.analyze(pre_profile, post_profile),
		}
		SaveService.save_game()
		SceneRouter.go("RESULT")
	else: footer_status.text = result.error

func _show_roster() -> void:
	_title("캐릭터 목록", "44명 • 역할/위치/공격/방어 계통 검증")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(grid)
	for character in DataRegistry.list_of("characters"):
		var progress: Dictionary = AppState.profile.roster[character.id]
		var lock_prefix := "잠김 · " if not bool(progress.unlocked) else ""
		grid.add_child(_button("%s%s\n%s • %s\nLv.%d B%d • 관계 %d" % [lock_prefix, LocalizationService.tr_key(character.name_key), character.role, character.preferred_position, progress.level, progress.breakthrough, progress.relationship_level], func(character_id: String = str(character.id)): AppState.selected_character_id = character_id; SceneRouter.go("CHARACTER_DETAIL"), false, Vector2(290, 130)))

func _show_growth() -> void:
	var cid := AppState.selected_character_id
	var definition := DataRegistry.character(cid)
	var progress: Dictionary = AppState.profile.roster[cid]
	_title(LocalizationService.tr_key(definition.name_key), "정보 • 능력치 • 스킬 • 레벨업 • 돌파 • 무기 • 관계 • 프로필")
	var hero := HBoxContainer.new()
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.add_theme_constant_override("separation", 18)
	content.add_child(hero)
	var portrait_panel := PanelContainer.new()
	portrait_panel.custom_minimum_size = Vector2(306, 372)
	hero.add_child(portrait_panel)
	portrait_panel.add_child(_art_rect(str(definition.portrait_asset_id), Vector2(282, 350)))
	var summary := _panel_box(hero)
	summary.add_child(_label("%s / %s / %s→%s" % [definition.role, definition.preferred_position, definition.attack_type, definition.defense_type], 23, Color("91d8d0")))
	summary.add_child(_label("Lv.%d (상한 %d)  EXP %d   B%d   관계 Lv.%d" % [progress.level, CharacterProgression.level_cap(progress), progress.xp, progress.breakthrough, progress.relationship_level], 25))
	summary.add_child(_label("상세 능력치\n%s" % _format_stats(CharacterProgression.final_stats(cid)), 19, Color("a8bed8")))
	if not bool(progress.unlocked):
		summary.add_child(_label("스토리 해금 전 프로필입니다. 초상화·역할·기본 능력치는 확인할 수 있지만 성장, 장비, 편성 및 보상 적용은 해금 후에만 가능합니다.", 18, Color("f1d77a")))
		return
	var level_preview := CharacterProgression.preview(cid, "TRAINING_NOTE_L", 1)
	summary.add_child(_label("레벨업 예상: Lv.%d / EXP %d • 크레딧 %s • 잉여 EXP %d" % [level_preview.level, level_preview.xp, MathUtil.comma(int(level_preview.credit_cost)), level_preview.unused_xp], 18, Color("f1d77a") if int(level_preview.unused_xp) > 0 else Color("8fe0b6")))
	var party_selector := HBoxContainer.new()
	party_selector.add_theme_constant_override("separation", 8)
	content.add_child(party_selector)
	for party_id_variant in AppState.get_party():
		var party_id := str(party_id_variant)
		party_selector.add_child(_button(_display_character_name(party_id), func(value: String = party_id): AppState.selected_character_id = value; _show_screen("GROWTH"), party_id == cid, Vector2(156, 52)))
	var next_plan_action: Dictionary = GrowthPlanBuilderScript.next_legal_action(AppState.get_party())
	var plan_preview: Dictionary = GrowthPlanBuilderScript.preview_recommended_batch(AppState.get_party(), 12) if not next_plan_action.is_empty() else {}
	var plan_box := _panel_box(content)
	plan_box.add_child(_label("권장 파티 성장", 22, Color("f1d77a")))
	if next_plan_action.is_empty():
		plan_box.add_child(_label("현재 보유 재료로 즉시 적용 가능한 파티 성장 항목이 없습니다.", 17, Color("91aac8")))
	else:
		var preview_texts: Array[String] = []
		var preview_actions: Array = plan_preview.get("actions", [])
		for preview_action_value in preview_actions.slice(0, 3):
			preview_texts.append(_growth_plan_action_text(preview_action_value))
		var preview_suffix := " 외 %d건" % (preview_actions.size() - preview_texts.size()) if preview_actions.size() > preview_texts.size() else ""
		plan_box.add_child(_label("다음: %s\n예정 %d단계: %s%s\n균형 우선으로 실제 재료·크레딧을 검증해 최대 12단계만 적용합니다. 개별 성장 규칙과 재료 차감은 동일 서비스가 처리합니다." % [_growth_plan_action_text(next_plan_action), preview_actions.size(), " / ".join(preview_texts), preview_suffix], 17, Color("c7d9ed")))
		var recommended_label := "권장 성장 계속 · 최대 12단계" if bool(last_growth_plan_report.get("has_more", false)) and not last_growth_plan_actions.is_empty() else "권장 파티 성장 적용 · 최대 12단계"
		var recommended_button := _button(recommended_label, func(): _apply_recommended_party_growth(12), false, Vector2(360, 62))
		_make_primary_button(recommended_button)
		plan_box.add_child(recommended_button)
	if not last_growth_plan_actions.is_empty():
		var action_texts: Array[String] = []
		for action in last_growth_plan_actions.slice(0, 4):
			action_texts.append(_growth_plan_action_text(action))
		var suffix := " 외 %d건" % (last_growth_plan_actions.size() - action_texts.size()) if last_growth_plan_actions.size() > action_texts.size() else ""
		plan_box.add_child(_label("직전 적용 %d단계: %s%s" % [last_growth_plan_actions.size(), " / ".join(action_texts), suffix], 15, Color("8fe0b6")))
		plan_box.add_child(_label(_growth_plan_result_text(last_growth_plan_report), 16, Color("c7d9ed")))
	var grid := GridContainer.new()
	grid.columns = 3
	content.add_child(grid)
	# Offer every authored training-note denomination.  The actual preview/service
	# remains the authority, so an oversized note cannot silently waste EXP at a
	# breakthrough cap and smaller legal notes remain usable in the Web UI.
	for material_id in ["TRAINING_NOTE_S", "TRAINING_NOTE_M", "TRAINING_NOTE_L", "TRAINING_NOTE_XL"]:
		var material_preview := CharacterProgression.preview(cid, material_id, 1)
		var material_disabled: bool = AppState.inventory_count(material_id) < 1 or AppState.inventory_count("CREDIT") < int(material_preview.credit_cost) or int(material_preview.unused_xp) > 0 or int(progress.level) >= CharacterProgression.level_cap(progress)
		grid.add_child(_button("레벨업\n%s %d개 · Lv.%d" % [_display_item_name(material_id), AppState.inventory_count(material_id), int(material_preview.level)], func(value: String = material_id): _report_result(CharacterProgression.use_material(cid, value, 1)); _show_screen("GROWTH"), material_disabled, Vector2(290, 86)))
	grid.add_child(_button("돌파 B%d→B%d" % [progress.breakthrough, mini(5, int(progress.breakthrough) + 1)], func(): _report_result(BreakthroughService.upgrade(cid)); _show_screen("GROWTH"), int(progress.breakthrough) >= 5, Vector2(290, 86)))
	grid.add_child(_button("관계 경험 +50 (DEV 선물)", func(): RelationshipService.grant(cid, 50); _show_screen("GROWTH"), int(progress.relationship_level) >= 20, Vector2(290, 86)))
	for slot in ["normal", "passive", "ultimate"]:
		var comparison := SkillUpgradeService.comparison(cid, slot)
		var max_level := 5 if slot == "ultimate" else 10
		var next_text := "MAX" if comparison.max else "%.3f→%.3f (+%.3f)" % [comparison.current, comparison.next, comparison.increase]
		var skill_id := str(definition.get(slot + "_skill_id", ""))
		var skill := DataRegistry.skill(skill_id)
		var skill_button := _button("%s Lv.%d/%d\n%s" % [LocalizationService.tr_key(str(skill.get("name_key", slot.to_upper()))).replace(" (DEV)", ""), progress.skills[slot], max_level, next_text], func(value: String = str(slot)): _report_result(SkillUpgradeService.upgrade(cid, value)); _show_screen("GROWTH"), comparison.max, Vector2(290, 98))
		_apply_skill_icon(skill_button, skill, 64)
		grid.add_child(skill_button)
	var weapon_id := str(progress.equipped_weapon_id)
	var weapon_state: Dictionary = AppState.profile.weapons[weapon_id]
	var weapon_preview := WeaponUpgradeService.preview(weapon_id, "WEAPON_CHIP_M", 1)
	var weapon_level_disabled: bool = AppState.inventory_count("WEAPON_CHIP_M") < 1 or not weapon_preview.ok or int(weapon_preview.value.get("unused_xp", 0)) > 0
	grid.add_child(_button("%s 강화\nLv.%d T%d" % [_display_runtime_name(weapon_id), weapon_state.level, weapon_state.tier], func(): _report_result(WeaponUpgradeService.use_material(weapon_id, "WEAPON_CHIP_M", 1)); _show_screen("GROWTH"), weapon_level_disabled, Vector2(290, 86)))
	grid.add_child(_button("%s 티어업" % _display_runtime_name(weapon_id), func(): _report_result(WeaponUpgradeService.tier_up(weapon_id)); _show_screen("GROWTH"), int(weapon_state.tier) >= 6, Vector2(290, 86)))
	var detail_box := _panel()
	var detail_lines: Array[String] = []
	detail_lines.append("레벨업 재료: %s 1/%d • %s %s/%s" % [_display_item_name("TRAINING_NOTE_L"), AppState.inventory_count("TRAINING_NOTE_L"), _display_item_name("CREDIT"), MathUtil.comma(AppState.inventory_count("CREDIT")), MathUtil.comma(int(level_preview.credit_cost))])
	detail_lines.append("돌파 요구: %s" % _cost_detail(BreakthroughService.next_cost(cid)))
	for slot in ["normal", "passive", "ultimate"]:
		var comparison := SkillUpgradeService.comparison(cid, slot)
		var value_text := "MAX" if comparison.max else "%.3f → %.3f / 실제 +%.3f" % [comparison.current, comparison.next, comparison.increase]
		detail_lines.append("%s: %s • 요구 %s" % [slot.to_upper(), value_text, _cost_detail(SkillUpgradeService.next_cost(cid, slot))])
	detail_lines.append("무기 강화: %s 1/%d • 현재 추가 %s" % [_display_item_name("WEAPON_CHIP_M"), AppState.inventory_count("WEAPON_CHIP_M"), _format_counts(WeaponUpgradeService.flat_stats_for(weapon_id, weapon_state), false)])
	detail_lines.append("무기 티어업 요구: %s" % _cost_detail(WeaponUpgradeService.tier_up_cost(weapon_id)))
	detail_box.add_child(_label("\n".join(detail_lines), 17, Color("b8cae0")))
	var compatible := HBoxContainer.new()
	content.add_child(compatible)
	compatible.add_child(_label("호환 %s:" % definition.weapon_class, 19, Color("91aac8")))
	for weapon in DataRegistry.list_of("weapons"):
		if weapon.weapon_class == definition.weapon_class:
			compatible.add_child(_button("%s 장착" % _display_runtime_name(str(weapon.id)), func(value: String = str(weapon.id)): progress.equipped_weapon_id = value; SaveService.save_game(); _show_screen("GROWTH"), weapon.id == weapon_id, Vector2(150, 58)))
	var missing_items: Array[String] = []
	var current_costs: Array = [BreakthroughService.next_cost(cid), SkillUpgradeService.next_cost(cid, "normal"), SkillUpgradeService.next_cost(cid, "passive"), SkillUpgradeService.next_cost(cid, "ultimate"), WeaponUpgradeService.tier_up_cost(weapon_id)]
	for cost in current_costs:
		for item_id in cost:
			if AppState.inventory_count(str(item_id)) < int(cost[item_id]) and not missing_items.has(str(item_id)):
				missing_items.append(str(item_id))
	if AppState.inventory_count("TRAINING_NOTE_L") < 1: missing_items.append("TRAINING_NOTE_L")
	if AppState.inventory_count("WEAPON_CHIP_M") < 1: missing_items.append("WEAPON_CHIP_M")
	var footer := HBoxContainer.new()
	content.add_child(footer)
	if missing_items.is_empty():
		footer.add_child(_button("재료 획득처 보기", func(): SceneRouter.go("STAGE_SELECT"), false, Vector2(230, 60)))
	else:
		for item_id in missing_items.slice(0, 3):
			footer.add_child(_button("%s 획득처" % _display_item_name(str(item_id)), func(value: String = str(item_id)): _go_to_item_source(value), false, Vector2(230, 60)))
	footer.add_child(_button("인벤토리", func(): SceneRouter.go("INVENTORY"), false, Vector2(170, 60)))
	footer.add_child(_label("B3 프로필 추가 / B5 승리 테두리 해제", 18, Color("879fba")))

func _cost_detail(cost: Dictionary) -> String:
	if cost.is_empty(): return "MAX / 없음"
	var parts: Array[String] = []
	for item_id in cost:
		var stages := _source_stages_for_item(str(item_id))
		var source := "획득처 없음"
		if not stages.is_empty():
			source = ",".join(stages.slice(0, 3))
			if stages.size() > 3: source += " 외 %d" % (stages.size() - 3)
		parts.append("%s %s/%s [%s]" % [_display_item_name(str(item_id)), MathUtil.comma(AppState.inventory_count(str(item_id))), MathUtil.comma(int(cost[item_id])), source])
	return " · ".join(parts)

func _source_stages_for_item(item_id: String) -> Array[String]:
	var result: Array[String] = []
	for reward in DataRegistry.list_of("rewards"):
		for bucket in ["guaranteed", "bonus", "first_clear"]:
			for entry in reward.get(bucket, []):
				if str(entry.get("item_id", "")) == item_id and not result.has(str(reward.stage_id)):
					result.append(str(reward.stage_id))
	return result

func _go_to_item_source(item_id: String) -> void:
	var stages := _source_stages_for_item(item_id)
	if stages.is_empty():
		footer_status.text = "%s: 현재 Chapter 1 반복 획득처 없음" % _display_item_name(item_id)
		return
	AppState.selected_stage_id = stages[0]
	SceneRouter.go("STAGE_DETAIL")

func _show_inventory() -> void:
	_title("인벤토리", "통화·경험치·돌파·스킬·무기·조각")
	var grid := GridContainer.new()
	grid.columns = 4
	var scroll_box := _scroll_box()
	scroll_box.add_child(grid)
	for item in DataRegistry.list_of("items"):
		var count := AppState.inventory_count(item.id)
		if count > 0:
			grid.add_child(_button("%s\n%s" % [_display_item_name(str(item.id)), MathUtil.comma(count)], func(): footer_status.text = "획득처: Chapter 1 스테이지 상세에서 확인", false, Vector2(260, 76)))

func _show_archive() -> void:
	_title("스토리 아카이브", "메인 7편 + 캐릭터 개인 스토리 2편")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(grid)
	for scenario in DataRegistry.list_of("scenarios"):
		var relation_locked: bool = str(scenario.chapter_id) == "REL" and ((str(scenario.id) == "SCN_REL_MAERU" and int(AppState.profile.roster.CHR001.relationship_level) < 2) or (str(scenario.id) == "SCN_REL_IRI" and int(AppState.profile.roster.CHR008.relationship_level) < 2))
		grid.add_child(_button("%s\n%s" % [LocalizationService.tr_key(scenario.title_key), scenario.chapter_id], func(scenario_id: String = str(scenario.id)): AppState.active_scenario_id = scenario_id; AppState.profile.last_scenario_position.erase(scenario_id); SceneRouter.go("STORY", {"after": "ARCHIVE"}), relation_locked, Vector2(320, 90)))

func _show_settings() -> void:
	_title("설정", "로컬 설정은 저장 파일에 보존")
	var box := _panel()
	box.add_child(_button("언어: %s" % SettingsService.values.language, func(): SettingsService.values.language = "en" if SettingsService.values.language == "ko" else "ko"; _show_screen("SETTINGS"), false, Vector2(300, 64)))
	box.add_child(_button("로컬 오디오: %s" % ("ON" if SettingsService.values.audio_enabled else "OFF"), func():
		AudioService.set_enabled(not bool(SettingsService.values.audio_enabled))
		SaveService.save_game()
		_show_screen("SETTINGS"), false, Vector2(300, 64)))
	box.add_child(_button("텍스트 속도: %.2fs" % SettingsService.values.text_speed, func(): SettingsService.values.text_speed = .01 if float(SettingsService.values.text_speed) >= .03 else float(SettingsService.values.text_speed) + .01; _show_screen("SETTINGS"), false, Vector2(300, 64)))
	box.add_child(_button("전투 AUTO 기본: %s" % SettingsService.values.battle_auto, func(): SettingsService.values.battle_auto = not SettingsService.values.battle_auto; _show_screen("SETTINGS"), false, Vector2(300, 64)))
	box.add_child(_button("맵 카메라 추적: %d%%" % roundi(float(SettingsService.values.map_camera_follow_strength) * 100.0), func(): SettingsService.values.map_camera_follow_strength = 0.35 if float(SettingsService.values.map_camera_follow_strength) > 0.7 else float(SettingsService.values.map_camera_follow_strength) + 0.2; _show_screen("SETTINGS"), false, Vector2(360, 64)))
	box.add_child(_button("맵 집중선 감소: %s" % SettingsService.values.map_reduced_transition, func(): SettingsService.values.map_reduced_transition = not SettingsService.values.map_reduced_transition; _show_screen("SETTINGS"), false, Vector2(360, 64)))
	box.add_child(_button("맵 즉시 포커스: %s" % SettingsService.values.map_instant_focus, func(): SettingsService.values.map_instant_focus = not SettingsService.values.map_instant_focus; _show_screen("SETTINGS"), false, Vector2(360, 64)))
	box.add_child(_button("오픈소스 / 제3자 라이선스", func(): SceneRouter.go("LICENSE"), false, Vector2(360, 64)))
	box.add_child(_button("설정 저장", func(): _report_result(SaveService.save_game()), false, Vector2(220, 64)))

func _show_license() -> void:
	_title("오픈소스 라이선스", "Godot와 제3자/공용 팩토리 출처 분리")
	var box := _scroll_box()
	box.add_child(_label("Godot Engine\nMIT License — Copyright Godot Engine contributors. 전체 라이선스는 배포본의 LICENSES 문서를 참조하십시오.\n\n공용 Asset Share Procedural Factory\nMIT / 버전 0.1.0. 동기화된 결과는 DEV_PLACEHOLDER이며 원본 manifest SHA-256과 출처를 보존합니다.\n\n현재 신규 코드 기반 도형 UI/SD placeholder는 프로젝트 자체 제작물입니다. 외부 생성 API나 원격 에셋은 사용하지 않았습니다.", 20))

func _show_debug() -> void:
	if not SettingsService.is_developer_mode():
		SceneRouter.go("HOME")
		return
	_title("개발자 디버그", "일반 저장 규칙과 분리된 로컬 개발 옵션")
	var box := _scroll_box()
	var grid := GridContainer.new()
	# Two portrait columns fit the 390px safe width; the creation order remains
	# untouched so keyboard QA keeps the established Tab sequence.
	grid.columns = 2 if _is_portrait_layout() else 3
	box.add_child(grid)
	grid.add_child(_button("모든 재료 999", func(): AppState.grant_all_materials(); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("전체 동료 해금", func(): _debug_unlock_roster(); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("스테이지 전체 해금: %s" % AppState.debug_options.unlock_all, func(): AppState.debug_options.unlock_all = not AppState.debug_options.unlock_all; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("선택 캐릭터 +10레벨", func(): _debug_level_character(10); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("선택 캐릭터 10/10/5", func(): AppState.profile.roster[AppState.selected_character_id].skills = {"normal": 10, "passive": 10, "ultimate": 5}; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("무적: %s" % AppState.debug_options.invincible, func(): AppState.debug_options.invincible = not AppState.debug_options.invincible; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("Seed +1 (%d)" % AppState.battle_seed, func(): AppState.battle_seed += 1; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("적 배율 %.1f×" % AppState.debug_options.enemy_multiplier, func(): AppState.debug_options.enemy_multiplier = 1.0 if float(AppState.debug_options.enemy_multiplier) >= 2.0 else float(AppState.debug_options.enemy_multiplier) + .25; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("계정 Lv.100", func(): AppState.profile.account.level = 100; _show_screen("DEBUG"), int(AppState.profile.account.level) == 100, Vector2(280, 72)))
	grid.add_child(_button("선택 무기 Lv.60/T6", func(): _debug_max_weapon(); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("N20 즉시 선택", func(): AppState.selected_stage_id = "CH01-N20"; SceneRouter.go("STAGE_DETAIL"), false, Vector2(280, 72)))
	grid.add_child(_button("고급 SD 전투 QA (CHR009-013 / BOSS003)", _debug_prepare_premium_sd_battle_qa, false, Vector2(280, 72)))
	grid.add_child(_button("리뉴얼 SD 전투 QA (CHR014·027·037·040·043 / BOSS003)", _debug_prepare_renewal_sd_battle_qa, false, Vector2(280, 72)))
	grid.add_child(_button("CH01 NORMAL 완료 / HARD QA", func(): _debug_unlock_chapter_hard(); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("N04 특별 조우 QA", func(): _debug_prepare_companion_event("NODE_N04"); SceneRouter.go("STAGE_SELECT"), false, Vector2(280, 72)))
	grid.add_child(_button("N04 카드 시각 QA (8초 홀드)", func(): _debug_prepare_companion_card_visual_qa("NODE_N04"); SceneRouter.go("STAGE_SELECT"), false, Vector2(280, 72)))
	grid.add_child(_button("N04 카드 프리뷰 QA (8초 홀드)", _debug_preview_companion_card, false, Vector2(280, 72)))
	grid.add_child(_button("N08 지연 합류 QA", func(): _debug_prepare_companion_event("NODE_N08"); SceneRouter.go("STAGE_SELECT"), false, Vector2(280, 72)))
	grid.add_child(_button("N10 보스 조우 QA", func(): _debug_prepare_map_contact("NODE_N10"); SceneRouter.go("STAGE_SELECT"), false, Vector2(280, 72)))
	grid.add_child(_button("저장 내보내기(user://)", _export_save, false, Vector2(280, 72)))
	grid.add_child(_button("헤드리스 테스트 안내", func(): footer_status.text = "tools/powershell/RUN_HEADLESS_TESTS.ps1", false, Vector2(280, 72)))
	grid.add_child(_button("저장 초기화 " + ("확정" if debug_reset_armed else "(재확인 필요)"), _debug_reset, false, Vector2(280, 72)))
	box.add_child(_label("피해 상세식: ATK×skill×defense×level×affinity×critical×variance×outgoing×incoming, round_half_up, min 1.\n전투 이벤트/식 입력값은 결과 해시 및 reports에서 확인. 배속은 BattleSimulation tick 수에 영향을 주지 않습니다.", 18, Color("8da6c3")))

func _debug_unlock_roster() -> void:
	for character_id in AppState.profile.roster: AppState.profile.roster[character_id].unlocked = true

func _debug_prepare_premium_sd_battle_qa() -> void:
	# Local developer-only visual QA route: the five promoted adult-SD allies face
	# BOSS003 on a real battle timeline. This is never exposed in the release UI.
	if not SettingsService.is_developer_mode():
		return
	_debug_unlock_roster()
	var qa_party := ["CHR009", "CHR010", "CHR011", "CHR012", "CHR013"]
	for slot in range(qa_party.size()):
		var character_id := str(qa_party[slot])
		AppState.set_party_slot(slot, character_id)
		# This route exists to validate the promoted battle art through the boss
		# wave, not to measure progression. Give only this dev squad enough
		# authored power to reach that wave inside the normal time limit.
		var progress: Dictionary = AppState.profile.roster[character_id]
		progress.level = 100
		progress.breakthrough = 5
		progress.skills = {"normal": 10, "passive": 10, "ultimate": 5}
	_debug_unlock_chapter_hard()
	# H03 normally requires H01/H02 stars.  QA must enter the authored BOSS003
	# fight directly, while keeping the bypass confined to development authority.
	AppState.debug_options.unlock_all = true
	AppState.debug_options.invincible = true
	AppState.selected_stage_id = "CH01-H03"
	SceneRouter.go("STAGE_DETAIL")

func _debug_prepare_renewal_sd_battle_qa() -> void:
	# Development-only visual proof route for the latest adult-SD authority art.
	# The party deliberately spans assault, control, medic, and heavy silhouettes
	# so a single Web run catches both duplicate-face regressions and incorrect
	# runtime source fallback before any release build is considered.
	if not SettingsService.is_developer_mode():
		return
	_debug_unlock_roster()
	var qa_party := ["CHR014", "CHR027", "CHR037", "CHR040", "CHR043"]
	for slot in range(qa_party.size()):
		var character_id := str(qa_party[slot])
		AppState.set_party_slot(slot, character_id)
		var progress: Dictionary = AppState.profile.roster[character_id]
		progress.level = 100
		progress.breakthrough = 5
		progress.skills = {"normal": 10, "passive": 10, "ultimate": 5}
	_debug_unlock_chapter_hard()
	AppState.debug_options.unlock_all = true
	AppState.debug_options.invincible = true
	AppState.selected_stage_id = "CH01-H03"
	SceneRouter.go("STAGE_DETAIL")

func _debug_level_character(amount: int) -> void:
	var state: Dictionary = AppState.profile.roster[AppState.selected_character_id]
	state.level = mini(100, int(state.level) + amount)
	while int(state.level) > CharacterProgression.level_cap(state) and int(state.breakthrough) < 5: state.breakthrough += 1

func _debug_max_weapon() -> void:
	var weapon_id := str(AppState.profile.roster[AppState.selected_character_id].equipped_weapon_id)
	AppState.profile.weapons[weapon_id].level = 60
	AppState.profile.weapons[weapon_id].tier = 6

func _debug_unlock_chapter_hard() -> void:
	# This capability exists only in the development-authorized screen.  Keep an
	# independent guard here as well so a synthetic callback cannot mutate a
	# public Release save.  This creates a reward-free canonical NORMAL-complete
	# snapshot: every route blocker is removed and the squad is anchored at N20,
	# allowing an actual H01-H10 map/contact/battle/return browser run.
	if not SettingsService.is_developer_mode():
		return
	AppState.profile.chapter_progress.CH01.normal_highest = 20
	AppState.profile.chapter_progress.CH01.hard_unlocked = true
	var definition := ChapterMapLoaderScript.load_map("CH01_MAP")
	var map_state := AppState.chapter_map_state("CH01_MAP")
	for number in range(1, 21):
		var stage_id := "CH01-N%02d" % number
		var node := ChapterMapLoaderScript.node_for_stage(definition, stage_id)
		AppState.profile.stage_stars[stage_id] = 3
		AppState.profile.first_clear[stage_id] = true
		if not node.is_empty():
			MapExplorationServiceScript.mark_encounter_cleared(map_state, str(node.node_id))
			if not map_state.cleared_nodes.has(str(node.node_id)):
				map_state.cleared_nodes.append(str(node.node_id))
	var n20 := ChapterMapLoaderScript.node_for_stage(definition, "CH01-N20")
	if not n20.is_empty():
		AppState.set_chapter_map_position(Vector2i(int(n20.q), int(n20.r)), str(n20.node_id), "CH01_MAP")
	AppState.refresh_chapter_map_reveal()

func _debug_prepare_companion_event(node_id: String) -> void:
	_debug_prepare_map_contact(node_id)

func _debug_prepare_companion_card_visual_qa(node_id: String) -> void:
	if not SettingsService.is_developer_mode():
		return
	debug_companion_card_visual_hold = true
	_debug_prepare_map_contact(node_id)

func _debug_preview_companion_card() -> void:
	# A visual-only companion-card inspector.  It reuses the normal pending-map
	# payload and the production _play_map_battle_transition() renderer, but
	# starts at the already-authored contact transaction so a browser screenshot
	# need not race the short real transition.  Physical-contact E2E remains
	# covered by the neighbouring-hex fixture above.
	if not SettingsService.is_developer_mode():
		return
	_debug_prepare_map_contact("NODE_N04")
	var state := AppState.chapter_map_state("CH01_MAP")
	var return_coord := Vector2i(int(state.get("current_q", 0)), int(state.get("current_r", 0)))
	if not AppState.prepare_map_encounter("CH01-N04", "NODE_N04", return_coord, "CH01_MAP"):
		return
	debug_companion_card_visual_hold = true
	battle_transition_active = true
	SceneRouter.go("STAGE_SELECT")
	await get_tree().process_frame
	_play_map_battle_transition()

func _debug_prepare_map_contact(node_id: String) -> void:
	# Development-only visual/E2E fixture. It never exists in a Release shell and
	# changes no battle, reward, or recruitment formula: it simply places the
	# squad on a real neighbouring ground hex so the normal physical-contact
	# sequence (including companion cards or boss title cards) can be tested
	# without walking the full macro route every time.
	if not SettingsService.is_developer_mode():
		return
	var definition := ChapterMapLoaderScript.load_map("CH01_MAP")
	var node := ChapterMapLoaderScript.node_by_id(definition, node_id)
	if node.is_empty():
		return
	var grid := HexGridScript.new()
	grid.load_tiles(definition.get("tiles", []))
	var target := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
	var staging := Vector2i.ZERO
	var found_staging := false
	for candidate in HexCoordScript.neighbors(target):
		if grid.traversable(candidate):
			staging = candidate
			found_staging = true
			break
	if not found_staging:
		return
	AppState.debug_options.unlock_all = true
	var map_state := AppState.chapter_map_state("CH01_MAP")
	MapExplorationServiceScript.ensure_state(map_state, definition, grid)
	var stage_id := str(node.get("stage_id", ""))
	var stage_number := int(DataRegistry.stage(stage_id).get("stage_number", 0))
	# Establish only the canonical NORMAL history that precedes this authored
	# companion contact.  Without it, the map's ordinary next-node resolver
	# understandably focuses an uncleared N01-N07 node after the QA N08 win,
	# preventing the real deferred-recruitment N09 follow-up from being checked.
	# This is development-only fixture state: it grants no rewards and is never
	# callable from a Release shell.
	for number in range(1, stage_number):
		var prior_stage_id := "CH01-N%02d" % number
		var prior_node := ChapterMapLoaderScript.node_for_stage(definition, prior_stage_id)
		AppState.profile.stage_stars[prior_stage_id] = 3
		AppState.profile.first_clear[prior_stage_id] = true
		if not prior_node.is_empty():
			MapExplorationServiceScript.mark_encounter_cleared(map_state, str(prior_node.node_id))
			if not map_state.cleared_nodes.has(str(prior_node.node_id)):
				map_state.cleared_nodes.append(str(prior_node.node_id))
	if stage_number > 1:
		AppState.profile.chapter_progress.CH01.normal_highest = maxi(int(AppState.profile.chapter_progress.CH01.get("normal_highest", 0)), stage_number - 1)
	# Make the fixture idempotent without awarding, clearing, or unlocking a
	# stage. A genuine map click and one-hex move still own the battle entry.
	map_state.cleared_nodes.erase(node_id)
	map_state.cleared_encounters.erase(node_id)
	map_state.encounter_states[node_id] = "HOSTILE"
	var special_event := MapExplorationServiceScript.event_encounter_for_node(definition, node_id)
	var event_encounter_id := str(special_event.get("event_encounter_id", ""))
	var companion_id := str(special_event.get("character_id", ""))
	if not event_encounter_id.is_empty():
		map_state.event_encounter_states[event_encounter_id] = "AVAILABLE"
	if not companion_id.is_empty():
		map_state.recruitment_states[companion_id] = "LOCKED"
	AppState.profile.stage_stars[stage_id] = 0
	AppState.profile.first_clear[stage_id] = false
	AppState.set_chapter_map_position(staging, "", "CH01_MAP")
	map_state.movement_points = map_state.movement_points_max
	AppState.selected_stage_id = stage_id
	SaveService.save_game()

func _export_save() -> void:
	var file := FileAccess.open("user://exported_save_v1.json", FileAccess.WRITE)
	if file != null:
		file.store_string(SaveService.export_save_json())
		footer_status.text = "user://exported_save_v1.json 저장 완료"

func _debug_reset() -> void:
	if not debug_reset_armed:
		debug_reset_armed = true
		footer_status.text = "한 번 더 눌러 저장 초기화를 확정하세요."
		_show_screen("DEBUG")
		return
	SaveService.reset_save_files()
	debug_reset_armed = false
	SceneRouter.go("TITLE")

func _report_result(result: GameResult) -> void:
	footer_status.text = "OK: %s" % str(result.value) if result.ok else "ERROR: %s" % result.error
