extends Control

const BattleViewScene := preload("res://battle/scenes/battle_root.tscn")
const ChapterMapScene := preload("res://chapter_map/view/chapter_map_root.tscn")
const ChapterMapLoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const GrowthAffordabilityAnalyzerScript := preload("res://progression/growth_affordability_analyzer.gd")
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
var story_art_status: Label
var story_auto := false
var story_auto_left := 0.0
var story_ui_hidden := false
var story_controls: Control
var battle_view: BattleView
var battle_hud: Label
var ultimate_buttons: Array[Button] = []
var party_status_labels: Array[Label] = []
var battle_auto_button: Button
var battle_speed_button: Button
var battle_pause_panel: PanelContainer
var battle_pause_center: CenterContainer
var battle_portrait_layout := false
var viewport_gate: ColorRect
var viewport_gate_label: Label
var interface_font: Font
var orientation_forced_pause := false
var last_portrait_layout := false
var layout_refresh_queued := false
var orientation_probe_left := 0.0
var last_battle_result: Dictionary = {}
var last_rewards: Dictionary = {}
var last_reward_report: Dictionary = {}
var debug_reset_armed := false
var battle_transition_active := false

func _ready() -> void:
	_build_root()
	EventBus.screen_changed.connect(_show_screen)
	SaveService.load_game()
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
	var ui_scale := _portrait_ui_scale()
	# The earlier subset deliberately reduced the Web payload, but it omitted
	# glyphs introduced by localized reward names.  Use the project-owned OFL
	# variable font so every Korean runtime string remains readable.
	var bundled_font := load("res://assets/fonts/NotoSansKR-VF.ttf") as Font
	if bundled_font != null:
		interface_font = bundled_font
		value.default_font = bundled_font
	value.default_font_size = roundi(20.0 * ui_scale)
	value.set_font_size("font_size", "Button", roundi(20.0 * ui_scale))
	value.set_font_size("font_size", "Label", roundi(20.0 * ui_scale))
	value.set_color("font_color", "Label", Color("f4f7fb"))
	value.set_color("font_color", "Button", Color("f4f7fb"))
	value.set_color("font_hover_color", "Button", Color("f4f7fb"))
	value.set_color("font_pressed_color", "Button", Color("f4f7fb"))
	value.set_color("font_disabled_color", "Button", Color("596578"))
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
	_queue_orientation_reflow_if_needed(portrait)

func _refresh_responsive_shell_metrics() -> void:
	_apply_safe_area()
	if theme != null:
		var ui_scale := _portrait_ui_scale()
		theme.default_font_size = roundi(20.0 * ui_scale)
		theme.set_font_size("font_size", "Button", roundi(20.0 * ui_scale))
		theme.set_font_size("font_size", "Label", roundi(20.0 * ui_scale))

func _queue_orientation_reflow_if_needed(portrait := _is_portrait_layout()) -> void:
	if portrait == last_portrait_layout or layout_refresh_queued:
		return
	last_portrait_layout = portrait
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
	# The chapter map stores only stable map state in AppState/SaveService, so it
	# can be rebuilt on a rotation without changing traversal, rewards, or battle
	# state. Rebuilding clears portrait-only control overrides before landscape.
	if current_screen in ["HOME", "TITLE", "RESULT", "ROSTER", "GROWTH", "CHARACTER_DETAIL", "INVENTORY", "ARCHIVE", "SETTINGS", "DEBUG", "LICENSE", "STAGE_SELECT", "STAGE_DETAIL", "FORMATION"]:
		_show_screen(current_screen)

func _is_portrait_layout() -> bool:
	var size := DisplayServer.window_get_size()
	var width := float(size.x)
	var height := float(size.y)
	if OS.has_feature("web"):
		var browser_width = JavaScriptBridge.eval("window.innerWidth", true)
		var browser_height = JavaScriptBridge.eval("window.innerHeight", true)
		if browser_width is int or browser_width is float: width = float(browser_width)
		if browser_height is int or browser_height is float: height = float(browser_height)
	return height > width

func _portrait_ui_scale() -> float:
	if not _is_portrait_layout(): return 1.0
	var width := float(DisplayServer.window_get_size().x)
	if OS.has_feature("web"):
		var browser_width = JavaScriptBridge.eval("window.innerWidth", true)
		if browser_width is int or browser_width is float:
			width = float(browser_width)
	# The project retains a 1920-wide logical canvas for desktop.  On a portrait
	# phone, scale control metrics back up to physical touch/readability size.
	return clampf(1920.0 / maxf(320.0, width), 2.8, 4.9)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveService.save_game()

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
	var base_margin := roundi(18.0 * _portrait_ui_scale()) if _is_portrait_layout() else 32
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
	battle_speed_button = null
	battle_pause_panel = null
	battle_pause_center = null
	battle_portrait_layout = false
	story_background = null
	story_portrait = null
	story_art_status = null

func _show_screen(screen_id: String) -> void:
	current_screen = screen_id
	_clear()
	match screen_id:
		"TITLE": _show_title()
		"HOME": _show_home()
		"STORY": _show_story()
		"FORMATION": _show_formation()
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

func _title(text_value: String, subtitle := "") -> void:
	var portrait := _is_portrait_layout()
	var ui_scale := _portrait_ui_scale()
	# In portrait, the back action gets its own top-bar row. A long Korean
	# chapter title must never be squeezed behind that control.
	var header: BoxContainer = VBoxContainer.new() if portrait and current_screen not in ["TITLE", "HOME"] else HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(header)
	if current_screen not in ["TITLE", "HOME"]:
		header.add_child(_button("‹ 뒤로", func(): SceneRouter.back("HOME"), false, Vector2(104 if portrait else 120, 54 if portrait else 60)))
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(labels)
	var title_label := Label.new()
	title_label.text = text_value
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.custom_minimum_size.x = 0.0
	title_label.add_theme_font_size_override("font_size", roundi((28.0 if portrait else 36.0) * ui_scale))
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

func _button(text_value: String, callback: Callable, disabled := false, minimum := Vector2(190, 64)) -> Button:
	var button := Button.new()
	button.text = text_value
	if _is_portrait_layout():
		var ui_scale := _portrait_ui_scale()
		button.custom_minimum_size = Vector2(minf(minimum.x * ui_scale, 840.0), maxf(52.0 * ui_scale, minimum.y * ui_scale))
		button.add_theme_font_size_override("font_size", roundi(18.0 * ui_scale))
	else:
		button.custom_minimum_size = minimum
	button.disabled = disabled
	# WebAudio must be resumed in the same call stack as a real button press.
	# Keeping this wrapper at the shared button factory covers title, map,
	# formation, growth and settings without duplicating platform branches.
	button.pressed.connect(func():
		AudioService.unlock_from_user_gesture()
		callback.call()
	)
	return button

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
	value.add_theme_font_size_override("font_size", roundi(float(size_value) * _portrait_ui_scale()))
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

func _art_rect(asset_id: String, minimum: Vector2, mode := TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> TextureRect:
	var art := TextureRect.new()
	art.texture = _asset_texture(asset_id)
	# Art cards are content controls too. Without this scale a 260 px portrait
	# card collapses to roughly 50 physical pixels on the retained 1920 canvas.
	art.custom_minimum_size = minimum * _portrait_ui_scale()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = mode
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art

func _format_counts(values: Dictionary, bullet := true) -> String:
	if values.is_empty(): return "없음"
	var keys := values.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append(("• " if bullet else "") + "%s  ×%s" % [str(key).replace("_", " "), MathUtil.comma(int(values[key]))])
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
		lines.append("• %s  %s%s" % [str(entry.get("item_id", "UNKNOWN")).replace("_", " "), amount_text, chance_text])
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
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 170.0 * _portrait_ui_scale()
	content.add_child(spacer)
	var hero := _panel()
	var game_title := _label(LocalizationService.tr_key("GAME_TITLE"), 58, Color("f4f7fb"))
	game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(game_title)
	var subtitle := _label(LocalizationService.tr_key("GAME_SUBTITLE"), 26, Color("a8b7ff"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(subtitle)
	var notice := _label("오프라인 싱글플레이 · 제1장 탐색 가능", 18, Color("8e9aaf"))
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(notice)
	var start := _button("등불을 켠다", func(): AppState.profile.tutorial_progress.title_seen = true; SceneRouter.go("HOME"), false, Vector2(360, 76))
	_make_primary_button(start)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hero.add_child(start)

func _show_home() -> void:
	AudioService.play_bgm("audio_bgm_lobby")
	AppState.refresh_stamina()
	_title("랜턴라인 본부", "오프라인 싱글플레이 버티컬 슬라이스")
	var resource_bar := _panel()
	resource_bar.add_child(_label("계정 Lv.%d   작전력 %d/%d   크레딧 %s" % [AppState.profile.account.level, AppState.profile.account.stamina, AppState.account_max_stamina(), MathUtil.comma(AppState.inventory_count("CREDIT"))], 24, Color("f1d77a")))
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
	menu.add_child(_button("메인 스토리", func(): AppState.active_scenario_id = "SCN_PROLOGUE"; SceneRouter.go("STORY"), false, Vector2(235, menu_height)))
	menu.add_child(_button("챕터 / 스테이지", func(): SceneRouter.go("STAGE_SELECT"), false, Vector2(235, menu_height)))
	menu.add_child(_button("파티 편성", func(): SceneRouter.go("FORMATION"), false, Vector2(235, menu_height)))
	menu.add_child(_button("캐릭터 / 성장", func(): SceneRouter.go("ROSTER"), false, Vector2(235, menu_height)))
	menu.add_child(_button("인벤토리", func(): SceneRouter.go("INVENTORY"), false, Vector2(235, menu_height)))
	menu.add_child(_button("스토리 아카이브", func(): SceneRouter.go("ARCHIVE"), false, Vector2(235, menu_height)))
	menu.add_child(_button("설정 / 라이선스", func(): SceneRouter.go("SETTINGS"), false, Vector2(235, menu_height)))
	menu.add_child(_button("개발자 도구", func(): SceneRouter.go("DEBUG"), not SettingsService.values.developer_mode, Vector2(235, menu_height)))
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
	row.add_child(_label("현재 파티: " + ", ".join(AppState.get_party()), 18, Color("8ba8c8")))

func _show_story() -> void:
	AudioService.play_bgm("audio_bgm_story")
	var portrait := _is_portrait_layout()
	var ui_scale := _portrait_ui_scale()
	_title("정적 일러스트 스토리", AppState.active_scenario_id)
	var stage := PanelContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(stage)
	var layer := VBoxContainer.new()
	layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(layer)
	var art_space := Control.new()
	# Portrait reserves a readable art band, a dialogue band, and three rows of
	# bottom controls. Those three regions must fit above the safe-area footer.
	art_space.custom_minimum_size.y = 236.0 * ui_scale if portrait else 320.0
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
	story_art_status = _label("STATIC ART", 16, Color("78e6d0"))
	story_art_status.position = Vector2(18.0 * ui_scale, 16.0 * ui_scale) if portrait else Vector2(24, 20)
	story_art_status.size = Vector2(900.0 * ui_scale, 40.0 * ui_scale) if portrait else Vector2(900, 40)
	art_space.add_child(story_art_status)
	var dialogue := PanelContainer.new()
	dialogue.custom_minimum_size.y = 264.0 * ui_scale if portrait else 250.0
	layer.add_child(dialogue)
	var dialogue_box := VBoxContainer.new()
	dialogue.add_child(dialogue_box)
	scenario_speaker = _label("", 23, Color("f1d77a"))
	dialogue_box.add_child(scenario_speaker)
	scenario_text = RichTextLabel.new()
	scenario_text.bbcode_enabled = true
	scenario_text.fit_content = true
	scenario_text.custom_minimum_size.y = 82.0 * ui_scale if portrait else 100.0
	scenario_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scenario_text.add_theme_font_size_override("normal_font_size", roundi(21.0 * ui_scale) if portrait else 25)
	dialogue_box.add_child(scenario_text)
	scenario_choices = VBoxContainer.new()
	dialogue_box.add_child(scenario_choices)
	story_controls = GridContainer.new() if portrait else HBoxContainer.new()
	if story_controls is GridContainer:
		(story_controls as GridContainer).columns = 2
	dialogue_box.add_child(story_controls)
	story_controls.add_child(_button("다음", _advance_story, false, Vector2(130, 58)))
	story_controls.add_child(_button("AUTO", func(): story_auto = not story_auto; story_auto_left = 0.5, false, Vector2(120, 58)))
	story_controls.add_child(_button("읽은 대사 SKIP", _skip_story, false, Vector2(190, 58)))
	story_controls.add_child(_button("로그", _show_story_log, false, Vector2(110, 58)))
	story_controls.add_child(_button("UI 숨기기", _toggle_story_ui, false, Vector2(140, 58)))
	if SettingsService.values.developer_mode: story_controls.add_child(_button("DEV 전체 스킵", _dev_skip_story, false, Vector2(160, 58)))
	scenario_runner = ScenarioRunner.new()
	var loaded := scenario_runner.load_scenario(AppState.active_scenario_id, true)
	if not loaded.ok:
		scenario_text.text = loaded.error
		return
	_refresh_story_art()
	story_auto_left = 1.0
	_advance_story()

func _advance_story() -> void:
	if scenario_runner == null: return
	for choice in scenario_choices.get_children(): choice.queue_free()
	var guard := 0
	while guard < 20:
		guard += 1
		var command := scenario_runner.advance()
		_refresh_story_art()
		var type := str(command.get("command", ""))
		if type in ["dialogue", "narration"]:
			scenario_speaker.text = "나레이션" if type == "narration" else LocalizationService.tr_key(command.get("speaker_key", ""))
			scenario_text.text = LocalizationService.tr_key(command.get("text_key", ""))
			scenario_text.visible_ratio = 0.0
			var reveal_duration := maxf(.05, scenario_text.text.length() * float(SettingsService.values.text_speed))
			create_tween().tween_property(scenario_text, "visible_ratio", 1.0, reveal_duration)
			story_auto_left = float(SettingsService.values.auto_delay) + maxf(.5, scenario_text.text.length() * float(SettingsService.values.text_speed))
			return
		if type == "choice":
			scenario_speaker.text = "선택"
			scenario_text.text = "당신의 기록 방식을 선택하세요."
			for i in range(command.get("choices", []).size()):
				var choice: Dictionary = command.choices[i]
				scenario_choices.add_child(_button(LocalizationService.tr_key(choice.text_key), func(index := i): scenario_runner.choose(index); _advance_story(), false, Vector2(400, 58)))
			return
		if type == "start_battle":
			AppState.selected_stage_id = command.stage_id
			SceneRouter.go("FORMATION", {"then": "STAGE_DETAIL"})
			return
		if type == "end_scenario" or scenario_runner.state.finished:
			SaveService.save_game()
			SceneRouter.go("FORMATION", {"then": "STAGE_SELECT"})
			return
		if type in ["wait", "fade_in", "fade_out"]:
			continue
		if type == "play_voice":
			story_auto_left = 0.2
			return

func _refresh_story_art() -> void:
	if scenario_runner == null: return
	var background_id := scenario_runner.state.cg_asset_id if not scenario_runner.state.cg_asset_id.is_empty() else scenario_runner.state.background_asset_id
	var background_path := AssetRegistry.resolve(background_id)
	if story_background != null:
		story_background.texture = load(background_path) as Texture2D if not background_path.is_empty() else null
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
		story_art_status.text = "STATIC ART • LOCAL ASSET"

func _skip_story() -> void:
	if scenario_runner != null and scenario_runner.can_skip_current(): _advance_story()
	else: footer_status.text = "읽은 대사만 건너뛸 수 있습니다."

func _dev_skip_story() -> void:
	if not SettingsService.values.developer_mode or scenario_runner == null: return
	var safety := 0
	while not scenario_runner.state.finished and safety < 1000:
		safety += 1
		var command := scenario_runner.advance()
		if command.get("command", "") == "choice": scenario_runner.choose(0)
		elif command.get("command", "") == "start_battle": continue
	SaveService.save_game()
	SceneRouter.go("FORMATION")

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
	actions.add_child(_button("스테이지 선택으로", func(): SceneRouter.go("STAGE_SELECT"), false, Vector2(240, 64)))
	actions.add_child(_button("저장", func(): _report_result(SaveService.save_game()), false, Vector2(140, 64)))

func _show_stage_select() -> void:
	_title("접근성 스테이지 목록", "R7 육각 맵 데이터 오류 또는 목록형 조작이 필요한 경우 사용하는 보존 화면")
	var mode_row := HBoxContainer.new()
	content.add_child(mode_row)
	mode_row.add_child(_button("NORMAL", func(): stage_mode = "NORMAL"; _show_screen("STAGE_SELECT"), stage_mode == "NORMAL", Vector2(180, 60)))
	mode_row.add_child(_button("HARD", func(): stage_mode = "HARD"; _show_screen("STAGE_SELECT"), stage_mode == "HARD", Vector2(180, 60)))
	if stage_mode == "HARD" and not AppState.profile.chapter_progress.CH01.hard_unlocked and not AppState.debug_options.unlock_all:
		content.add_child(_label("HARD는 CH01-N10 클리어 후 해금됩니다.", 24, Color("ffbd7a")))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(grid)
	for stage in DataRegistry.list_of("stages"):
		if stage.mode != stage_mode: continue
		var stars := int(AppState.profile.stage_stars.get(stage.id, 0))
		var unlocked := AppState.is_stage_unlocked(stage.id)
		var boss := " BOSS" if stage.boss else ""
		grid.add_child(_button("%s%s\n권장 Lv.%d\n%s" % [stage.id, boss, stage.recommended_level, "★".repeat(stars) + "☆".repeat(3 - stars)], func(stage_id: String = str(stage.id)): AppState.selected_stage_id = stage_id; SceneRouter.go("STAGE_DETAIL"), not unlocked, Vector2(235, 120)))

func _show_chapter_map() -> void:
	AudioService.play_bgm("audio_bgm_lobby")
	_title("제1장 — 꺼진 노선의 신호", "탐색 경로를 따라 조우를 선택하고, 기존 실시간 전투에 진입합니다.")
	var definition: Dictionary = ChapterMapLoaderScript.load_map("CH01_MAP")
	var errors: Array[String] = ChapterMapLoaderScript.validate(definition)
	if not errors.is_empty():
		content.add_child(_label("맵 데이터 검증 실패\n" + "\n".join(errors), 22, Color("ff7f8a")))
		content.add_child(_button("목록형 fail-safe 열기", func(): SceneRouter.go("STAGE_LIST_FALLBACK"), false, Vector2(260, 64)))
		return
	var map_screen = ChapterMapScene.instantiate()
	map_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_screen.battle_requested.connect(_map_battle_requested)
	map_screen.formation_requested.connect(func(): SceneRouter.go("FORMATION"))
	map_screen.fallback_requested.connect(func(): SceneRouter.go("STAGE_LIST_FALLBACK"))
	map_screen.sweep_requested.connect(_map_sweep_requested)
	map_screen.treasure_reward_requested.connect(_map_treasure_reward_requested)
	content.add_child(map_screen)

func _map_battle_requested(stage_id: String) -> void:
	AppState.selected_stage_id = stage_id
	_start_battle()

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
	_title(stage.id + (" • BOSS" if stage.boss else ""), "권장 Lv.%d • %d 작전력 • %d초" % [stage.recommended_level, stage.stamina_cost, stage.time_limit])
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
	if stage.mode == "HARD": attempts = "%d/%d" % [AppState.profile.hard_attempts.counts.get(stage.id, 0), stage.daily_attempts]
	wave_box.add_child(_label("입장 횟수 %s   현재 %s/3성" % [attempts, AppState.profile.stage_stars.get(stage.id, 0)], 20, Color("e9c979")))
	var actions := HBoxContainer.new()
	content.add_child(actions)
	actions.add_child(_button("파티 편성", func(): SceneRouter.go("FORMATION"), false, Vector2(190, 66)))
	actions.add_child(_button("전투 시작", _start_battle, not AppState.can_enter_stage(stage.id), Vector2(210, 66)))
	for count in [1, 5, 10]:
		var sweep_disabled: bool = int(AppState.profile.stage_stars.get(stage.id, 0)) < 3 or not AppState.can_enter_stage_count(stage.id, int(count))
		actions.add_child(_button("소탕 %d회" % count, func(value: int = int(count)): _sweep(value), sweep_disabled, Vector2(160, 66)))

func _start_battle() -> void:
	if battle_transition_active: return
	if not AppState.begin_battle_transaction(AppState.selected_stage_id):
		footer_status.text = "입장 조건/작전력/일일 횟수를 확인하세요."
		return
	battle_transition_active = true
	_play_map_battle_transition()

func _play_map_battle_transition() -> void:
	var veil := ColorRect.new()
	veil.name = "R7HexSignalTransition"
	veil.color = Color("06101c00")
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)
	var focus := Label.new()
	focus.text = "◇  SIGNAL LOCK  ◇"
	focus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	focus.add_theme_font_size_override("font_size", 42)
	focus.modulate = Color("7cebd000")
	focus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(focus)
	var reduced := bool(SettingsService.values.get("map_reduced_transition", false))
	var duration := 0.18 if reduced else 0.62
	var tween := create_tween().set_parallel(true)
	tween.tween_property(veil, "color", Color("06101cf2"), duration)
	tween.tween_property(focus, "modulate", Color("a3fff0"), duration * 0.72)
	await tween.finished
	veil.queue_free()
	SceneRouter.go("BATTLE")

func _show_battle() -> void:
	battle_transition_active = false
	var stage := DataRegistry.stage(AppState.selected_stage_id)
	AudioService.play_bgm("audio_bgm_boss" if bool(stage.boss) else "audio_bgm_battle")
	var simulation := BattleSimulation.new()
	simulation.setup(AppState.create_party_snapshot(), stage, AppState.battle_seed, DataRegistry.data, {"invincible": AppState.debug_options.invincible, "enemy_multiplier": AppState.debug_options.enemy_multiplier})
	simulation.auto_enabled = bool(SettingsService.values.battle_auto)
	battle_view = BattleViewScene.instantiate()
	battle_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	battle_actions.add_child(battle_auto_button)
	battle_speed_button = _button("×1", _cycle_battle_speed, false, Vector2(110, 56))
	battle_actions.add_child(battle_speed_button)
	battle_actions.add_child(_button("일시정지", _toggle_battle_pause, false, Vector2(140, 56)))
	battle_actions.add_child(_button("나가기", _abandon_battle, false, Vector2(120, 56)))
	var party_row: Container = GridContainer.new() if portrait else HBoxContainer.new()
	party_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if party_row is GridContainer:
		# Two wide party readouts are more legible than three narrow columns. The
		# old three-column layout wrapped character names into the action grid.
		(party_row as GridContainer).columns = 2
	party_row.add_theme_constant_override("separation", 8)
	overlay.add_child(party_row)
	for unit in battle_view.simulation.state.party:
		var status_label := _label("", 15, Color("cfe6ff"))
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if portrait else HORIZONTAL_ALIGNMENT_CENTER
		status_label.custom_minimum_size = Vector2(0.0, 46.0 * ui_scale) if portrait else Vector2(0, 58)
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
		(bottom as GridContainer).columns = 2
	else:
		(bottom as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(bottom)
	for unit in battle_view.simulation.state.party:
		var definition := DataRegistry.character(unit.def_id)
		var skill := DataRegistry.skill(definition.ultimate_skill_id)
		var button := _button("%s\nULT %d" % [LocalizationService.tr_key(definition.name_key), skill.tactical_cost], func(uid: String = str(unit.uid)): _request_ultimate(uid), false, Vector2(190 if portrait else 220, 72 if portrait else 78))
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
		boss_text = "  BOSS %d/%d [%s]" % [boss.hp, boss.max_hp, boss.get("phase", "PHASE_1")]
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
	last_battle_result = result
	last_rewards = {}
	last_reward_report = {}
	var pre_profile := AppState.profile.duplicate(true)
	if result.victory:
		var stage := DataRegistry.stage(AppState.selected_stage_id)
		var stars := 1 + (1 if int(result.survivors) == 5 else 0) + (1 if float(result.time) <= float(stage.target_time) else 0)
		var first := AppState.record_stage_clear(stage.id, stars)
		# A battle transaction receives one immutable token at entry.  Reloads,
		# duplicate callbacks, and result-screen revisits cannot grant it twice.
		if AppState.claim_pending_reward_once(stage.id):
			last_rewards = RewardService.resolve(stage.id, 1, AppState.battle_seed + int(result.ticks), first)
			AccountProgression.grant_stage_xp(int(stage.stamina_cost), 20 if first else 0)
			for character_id in AppState.get_party(): RelationshipService.grant(character_id, 10)
	AppState.apply_battle_result_to_map(AppState.selected_stage_id, bool(result.get("victory", false)))
	var post_profile := AppState.profile.duplicate(true)
	last_reward_report = {
		"source_type": "BATTLE",
		"source_id": AppState.selected_stage_id,
		"rewards": last_rewards.duplicate(true),
		"pre_inventory": pre_profile.get("inventory", {}).duplicate(true),
		"post_inventory": post_profile.get("inventory", {}).duplicate(true),
		"growth": GrowthAffordabilityAnalyzerScript.analyze(pre_profile, post_profile),
	}
	SaveService.save_game()
	SceneRouter.go("RESULT")

func _abandon_battle() -> void:
	AppState.abandon_pending_map_encounter()
	SaveService.save_game()
	SceneRouter.go("STAGE_SELECT")

func _display_item_name(item_id: String) -> String:
	var item := DataRegistry.by_id("items", item_id)
	var fallback := item_id.replace("_", " ")
	return LocalizationService.tr_key(str(item.get("name_key", fallback))).replace(" (DEV)", "")

func _display_character_name(character_id: String) -> String:
	var definition := DataRegistry.character(character_id)
	return LocalizationService.tr_key(str(definition.get("name_key", character_id))).replace(" (DEV)", "")

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
		_reward_summary_card(parent, "NEW 0\n이번 보상으로 새롭게 열린 성장 항목은 없습니다.", font_size - 1)
	else:
		for candidate in newly:
			var candidate_button := _button("NEW  ·  " + _growth_candidate_text(candidate), func(value: Dictionary = candidate.duplicate(true)): _goto_growth_candidate(value), false, Vector2(460, 76))
			_make_primary_button(candidate_button)
			parent.add_child(candidate_button)
	var summary: Dictionary = growth.get("summary", {})
	_reward_summary_card(parent, "현재 재료로 성장 가능한 후보\n레벨업 %d명 · 돌파 %d명 · 스킬 %d명 · 무기 강화 %d개 · 티어업 %d개" % [int(summary.get("level_characters", 0)), int(summary.get("breakthrough_characters", 0)), int(summary.get("skill_characters", 0)), int(summary.get("weapon_levels", 0)), int(summary.get("weapon_tiers", 0))], font_size)

func _show_result() -> void:
	AudioService.play_bgm("audio_bgm_lobby")
	_title("탐색 보상" if str(last_reward_report.get("source_type", "")) != "BATTLE" else "전투 결과", str(last_reward_report.get("source_id", AppState.selected_stage_id)))
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
	var hero := HBoxContainer.new()
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.custom_minimum_size = Vector2(0.0, 500.0)
	hero.add_theme_constant_override("separation", 18)
	report_scroll.add_child(hero)
	var lead := DataRegistry.character(AppState.get_party()[0])
	var art_panel := PanelContainer.new()
	art_panel.custom_minimum_size = Vector2(260, 500)
	hero.add_child(art_panel)
	art_panel.add_child(_art_rect(str(lead.portrait_asset_id), Vector2(240, 470)))
	var box := _panel_box(hero)
	box.add_child(_label("VICTORY" if last_battle_result.get("victory", false) else "DEFEAT", 52, Color("f1d77a") if last_battle_result.get("victory", false) else Color("ff7f8a")))
	box.add_child(_label("시간 %.2fs  ·  생존 %d" % [last_battle_result.get("time", 0), last_battle_result.get("survivors", 0)], 26))
	_add_reward_clarity(box, 23)
	box.add_child(_label("가한 피해\n%s\n\n회복\n%s" % [_format_counts(last_battle_result.get("damage", {})), _format_counts(last_battle_result.get("healing", {}))], 19, Color("cdd5e3")))
	var actions := HBoxContainer.new()
	content.add_child(actions)
	actions.add_child(_button("캐릭터 성장", func(): AppState.selected_character_id = AppState.get_party()[0]; SceneRouter.go("GROWTH"), false, Vector2(220, 66)))
	actions.add_child(_button("챕터 맵으로", func(): SceneRouter.go("STAGE_SELECT"), false, Vector2(220, 66)))
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
	var lead := DataRegistry.character(AppState.get_party()[0])
	var art_panel := PanelContainer.new()
	art_panel.custom_minimum_size = Vector2(0.0, 224.0 * ui_scale)
	report.add_child(art_panel)
	art_panel.add_child(_art_rect(str(lead.portrait_asset_id), Vector2(310, 218)))
	var box := _panel_box(report)
	box.add_child(_label("VICTORY" if last_battle_result.get("victory", false) else "DEFEAT", 40, Color("f1d77a") if last_battle_result.get("victory", false) else Color("ff7f8a")))
	box.add_child(_label("시간 %.2fs  ·  생존 %d" % [last_battle_result.get("time", 0), last_battle_result.get("survivors", 0)], 20))
	box.add_child(_label("결정론 기록  %s" % str(last_battle_result.get("event_hash", "")).left(16), 14, Color("7e9dbd")))
	_add_reward_clarity(box, 16)
	box.add_child(_label("가한 피해\n%s\n\n회복\n%s" % [_format_counts(last_battle_result.get("damage", {})), _format_counts(last_battle_result.get("healing", {}))], 15, Color("cdd5e3")))
	var actions := VBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", roundi(7.0 * ui_scale))
	content.add_child(actions)
	actions.add_child(_button("캐릭터 성장", func(): AppState.selected_character_id = AppState.get_party()[0]; SceneRouter.go("GROWTH"), false, Vector2(320, 52)))
	actions.add_child(_button("챕터 맵으로", func(): SceneRouter.go("STAGE_SELECT"), false, Vector2(320, 52)))
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
	_title("캐릭터 목록", "8명 • 역할/위치/공격/방어 계통 검증")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(grid)
	for character in DataRegistry.list_of("characters"):
		var progress: Dictionary = AppState.profile.roster[character.id]
		grid.add_child(_button("%s\n%s • %s\nLv.%d B%d • 관계 %d" % [LocalizationService.tr_key(character.name_key), character.role, character.preferred_position, progress.level, progress.breakthrough, progress.relationship_level], func(character_id: String = str(character.id)): AppState.selected_character_id = character_id; SceneRouter.go("CHARACTER_DETAIL"), not progress.unlocked, Vector2(290, 130)))

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
	portrait_panel.custom_minimum_size = Vector2(270, 330)
	hero.add_child(portrait_panel)
	portrait_panel.add_child(_art_rect(str(definition.portrait_asset_id), Vector2(250, 310)))
	var summary := _panel_box(hero)
	summary.add_child(_label("%s / %s / %s→%s" % [definition.role, definition.preferred_position, definition.attack_type, definition.defense_type], 23, Color("91d8d0")))
	summary.add_child(_label("Lv.%d (상한 %d)  EXP %d   B%d   관계 Lv.%d" % [progress.level, CharacterProgression.level_cap(progress), progress.xp, progress.breakthrough, progress.relationship_level], 25))
	summary.add_child(_label("상세 능력치\n%s" % _format_stats(CharacterProgression.final_stats(cid)), 19, Color("a8bed8")))
	var level_preview := CharacterProgression.preview(cid, "TRAINING_NOTE_L", 1)
	summary.add_child(_label("레벨업 예상: Lv.%d / EXP %d • 크레딧 %s • 잉여 EXP %d" % [level_preview.level, level_preview.xp, MathUtil.comma(int(level_preview.credit_cost)), level_preview.unused_xp], 18, Color("f1d77a") if int(level_preview.unused_xp) > 0 else Color("8fe0b6")))
	var grid := GridContainer.new()
	grid.columns = 3
	content.add_child(grid)
	var level_disabled: bool = AppState.inventory_count("TRAINING_NOTE_L") < 1 or AppState.inventory_count("CREDIT") < int(level_preview.credit_cost) or int(level_preview.unused_xp) > 0 or int(progress.level) >= CharacterProgression.level_cap(progress)
	grid.add_child(_button("레벨업\nNOTE_L %d개" % AppState.inventory_count("TRAINING_NOTE_L"), func(): _report_result(CharacterProgression.use_material(cid, "TRAINING_NOTE_L", 1)); _show_screen("GROWTH"), level_disabled, Vector2(290, 86)))
	grid.add_child(_button("돌파 B%d→B%d" % [progress.breakthrough, mini(5, int(progress.breakthrough) + 1)], func(): _report_result(BreakthroughService.upgrade(cid)); _show_screen("GROWTH"), int(progress.breakthrough) >= 5, Vector2(290, 86)))
	grid.add_child(_button("관계 경험 +50 (DEV 선물)", func(): RelationshipService.grant(cid, 50); _show_screen("GROWTH"), int(progress.relationship_level) >= 20, Vector2(290, 86)))
	for slot in ["normal", "passive", "ultimate"]:
		var comparison := SkillUpgradeService.comparison(cid, slot)
		var max_level := 5 if slot == "ultimate" else 10
		var next_text := "MAX" if comparison.max else "%.3f→%.3f (+%.3f)" % [comparison.current, comparison.next, comparison.increase]
		grid.add_child(_button("%s Lv.%d/%d\n%s" % [slot.to_upper(), progress.skills[slot], max_level, next_text], func(value: String = str(slot)): _report_result(SkillUpgradeService.upgrade(cid, value)); _show_screen("GROWTH"), comparison.max, Vector2(290, 98)))
	var weapon_id := str(progress.equipped_weapon_id)
	var weapon_state: Dictionary = AppState.profile.weapons[weapon_id]
	var weapon_preview := WeaponUpgradeService.preview(weapon_id, "WEAPON_CHIP_M", 1)
	var weapon_level_disabled: bool = AppState.inventory_count("WEAPON_CHIP_M") < 1 or not weapon_preview.ok or int(weapon_preview.value.get("unused_xp", 0)) > 0
	grid.add_child(_button("%s 강화\nLv.%d T%d" % [weapon_id, weapon_state.level, weapon_state.tier], func(): _report_result(WeaponUpgradeService.use_material(weapon_id, "WEAPON_CHIP_M", 1)); _show_screen("GROWTH"), weapon_level_disabled, Vector2(290, 86)))
	grid.add_child(_button("%s 티어업" % weapon_id, func(): _report_result(WeaponUpgradeService.tier_up(weapon_id)); _show_screen("GROWTH"), int(weapon_state.tier) >= 6, Vector2(290, 86)))
	var detail_box := _panel()
	var detail_lines: Array[String] = []
	detail_lines.append("레벨업 재료: TRAINING_NOTE_L 1/%d • CREDIT %s/%s" % [AppState.inventory_count("TRAINING_NOTE_L"), MathUtil.comma(AppState.inventory_count("CREDIT")), MathUtil.comma(int(level_preview.credit_cost))])
	detail_lines.append("돌파 요구: %s" % _cost_detail(BreakthroughService.next_cost(cid)))
	for slot in ["normal", "passive", "ultimate"]:
		var comparison := SkillUpgradeService.comparison(cid, slot)
		var value_text := "MAX" if comparison.max else "%.3f → %.3f / 실제 +%.3f" % [comparison.current, comparison.next, comparison.increase]
		detail_lines.append("%s: %s • 요구 %s" % [slot.to_upper(), value_text, _cost_detail(SkillUpgradeService.next_cost(cid, slot))])
	detail_lines.append("무기 강화: WEAPON CHIP M 1/%d • 현재 추가 %s" % [AppState.inventory_count("WEAPON_CHIP_M"), _format_counts(WeaponUpgradeService.flat_stats_for(weapon_id, weapon_state), false)])
	detail_lines.append("무기 티어업 요구: %s" % _cost_detail(WeaponUpgradeService.tier_up_cost(weapon_id)))
	detail_box.add_child(_label("\n".join(detail_lines), 17, Color("b8cae0")))
	var compatible := HBoxContainer.new()
	content.add_child(compatible)
	compatible.add_child(_label("호환 %s:" % definition.weapon_class, 19, Color("91aac8")))
	for weapon in DataRegistry.list_of("weapons"):
		if weapon.weapon_class == definition.weapon_class:
			compatible.add_child(_button("%s 장착" % weapon.id, func(value: String = str(weapon.id)): progress.equipped_weapon_id = value; SaveService.save_game(); _show_screen("GROWTH"), weapon.id == weapon_id, Vector2(150, 58)))
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
			footer.add_child(_button("%s 획득처" % item_id, func(value: String = str(item_id)): _go_to_item_source(value), false, Vector2(230, 60)))
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
		parts.append("%s %s/%s [%s]" % [item_id, MathUtil.comma(AppState.inventory_count(str(item_id))), MathUtil.comma(int(cost[item_id])), source])
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
		footer_status.text = "%s: 현재 Chapter 1 반복 획득처 없음" % item_id
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
			grid.add_child(_button("%s\n%s" % [item.id, MathUtil.comma(count)], func(): footer_status.text = "획득처: Chapter 1 스테이지 상세에서 확인", false, Vector2(260, 76)))

func _show_archive() -> void:
	_title("스토리 아카이브", "메인 7편 + 캐릭터 개인 스토리 2편")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(grid)
	for scenario in DataRegistry.list_of("scenarios"):
		var relation_locked: bool = str(scenario.chapter_id) == "REL" and ((str(scenario.id) == "SCN_REL_MAERU" and int(AppState.profile.roster.CHR001.relationship_level) < 2) or (str(scenario.id) == "SCN_REL_IRI" and int(AppState.profile.roster.CHR008.relationship_level) < 2))
		grid.add_child(_button("%s\n%s" % [LocalizationService.tr_key(scenario.title_key), scenario.chapter_id], func(scenario_id: String = str(scenario.id)): AppState.active_scenario_id = scenario_id; AppState.profile.last_scenario_position.erase(scenario_id); SceneRouter.go("STORY"), relation_locked, Vector2(320, 90)))

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
	_title("개발자 디버그", "일반 저장 규칙과 분리된 로컬 개발 옵션")
	var box := _scroll_box()
	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	grid.add_child(_button("모든 재료 999", func(): AppState.grant_all_materials(); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("8명 모두 해금", func(): _debug_unlock_roster(); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("스테이지 전체 해금: %s" % AppState.debug_options.unlock_all, func(): AppState.debug_options.unlock_all = not AppState.debug_options.unlock_all; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("선택 캐릭터 +10레벨", func(): _debug_level_character(10); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("선택 캐릭터 10/10/5", func(): AppState.profile.roster[AppState.selected_character_id].skills = {"normal": 10, "passive": 10, "ultimate": 5}; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("무적: %s" % AppState.debug_options.invincible, func(): AppState.debug_options.invincible = not AppState.debug_options.invincible; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("Seed +1 (%d)" % AppState.battle_seed, func(): AppState.battle_seed += 1; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("적 배율 %.1f×" % AppState.debug_options.enemy_multiplier, func(): AppState.debug_options.enemy_multiplier = 1.0 if float(AppState.debug_options.enemy_multiplier) >= 2.0 else float(AppState.debug_options.enemy_multiplier) + .25; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("계정 Lv.100", func(): AppState.profile.account.level = 100; _show_screen("DEBUG"), int(AppState.profile.account.level) == 100, Vector2(280, 72)))
	grid.add_child(_button("선택 무기 Lv.60/T6", func(): _debug_max_weapon(); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("N10 즉시 선택", func(): AppState.selected_stage_id = "CH01-N10"; SceneRouter.go("STAGE_DETAIL"), false, Vector2(280, 72)))
	grid.add_child(_button("저장 내보내기(user://)", _export_save, false, Vector2(280, 72)))
	grid.add_child(_button("헤드리스 테스트 안내", func(): footer_status.text = "tools/powershell/RUN_HEADLESS_TESTS.ps1", false, Vector2(280, 72)))
	grid.add_child(_button("저장 초기화 " + ("확정" if debug_reset_armed else "(재확인 필요)"), _debug_reset, false, Vector2(280, 72)))
	box.add_child(_label("피해 상세식: ATK×skill×defense×level×affinity×critical×variance×outgoing×incoming, round_half_up, min 1.\n전투 이벤트/식 입력값은 결과 해시 및 reports에서 확인. 배속은 BattleSimulation tick 수에 영향을 주지 않습니다.", 18, Color("8da6c3")))

func _debug_unlock_roster() -> void:
	for character_id in AppState.profile.roster: AppState.profile.roster[character_id].unlocked = true

func _debug_level_character(amount: int) -> void:
	var state: Dictionary = AppState.profile.roster[AppState.selected_character_id]
	state.level = mini(100, int(state.level) + amount)
	while int(state.level) > CharacterProgression.level_cap(state) and int(state.breakthrough) < 5: state.breakthrough += 1

func _debug_max_weapon() -> void:
	var weapon_id := str(AppState.profile.roster[AppState.selected_character_id].equipped_weapon_id)
	AppState.profile.weapons[weapon_id].level = 60
	AppState.profile.weapons[weapon_id].tier = 6

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
