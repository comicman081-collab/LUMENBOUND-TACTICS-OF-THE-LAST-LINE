extends Node

# Final portrait presentation pass for the fixed 1920x1080 authored canvas.
# It never changes scenario/map/battle authority; it only repairs geometry,
# type sizes and touch targets after the normal screen has been constructed.

const DESIGN_VIEWPORT_SIZE := Vector2(1920.0, 1080.0)
const PROBE_INTERVAL := 0.10
const MAP_SUBTITLE_FULL := "탐색 경로를 따라 조우를 선택하고, 기존 실시간 전투에 진입합니다."
const MAP_SUBTITLE_COMPACT := "조우를 선택해 이동·전투를 진행하세요."
# Story, roster and recruit fallbacks must resolve the 8-head card family;
# SD art is reserved exclusively for battle and tactical-map pawns.
const FALLBACK_CARD := "res://assets/runtime_web/characters/CHR001/portrait.png"

var _shell: Control
var _probe_left := 0.0
var _last_screen := ""
var _fallback_portraits: Array[TextureRect] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 2000
	print("LUMENBOUND_MOBILE_PORTRAIT_V2_READY")
	call_deferred("_apply")

func _process(delta: float) -> void:
	_probe_left -= delta
	if _probe_left > 0.0:
		return
	_probe_left = PROBE_INTERVAL
	_apply()

func _apply() -> void:
	var runtime_size := _runtime_size()
	if runtime_size.y <= runtime_size.x:
		return
	if _shell == null or not is_instance_valid(_shell):
		_shell = _find_shell(get_tree().root)
	if _shell == null:
		return
	var screen := str(_shell.get("current_screen"))
	if screen != _last_screen:
		_last_screen = screen
		print("LUMENBOUND_MOBILE_PORTRAIT_V2_ACTIVE screen=%s size=%sx%s" % [screen, roundi(runtime_size.x), roundi(runtime_size.y)])
	match screen:
		"STORY":
			_fix_story(runtime_size)
		"STAGE_SELECT", "STAGE_DETAIL":
			_fix_map(runtime_size)
		"RESULT", "GROWTH", "INVENTORY", "ROSTER", "ARCHIVE", "SETTINGS", "DEBUG", "LICENSE":
			_fix_progression_scroll(runtime_size)
		_:
			pass

func _find_shell(node: Node) -> Control:
	if node is Control and node.has_method("responsive_ui_metrics_for_size") and node.has_method("_show_chapter_map"):
		return node as Control
	for child in node.get_children():
		if child is SubViewport:
			continue
		var found := _find_shell(child)
		if found != null:
			return found
	return null

func _runtime_size() -> Vector2:
	if OS.get_environment("LUMENBOUND_FORCE_PORTRAIT_QA") == "1":
		return Vector2(390.0, 844.0)
	var size := DisplayServer.window_get_size()
	var width := float(size.x)
	var height := float(size.y)
	if OS.has_feature("web"):
		var browser_width = JavaScriptBridge.eval("window.innerWidth", true)
		var browser_height = JavaScriptBridge.eval("window.innerHeight", true)
		if browser_width is int or browser_width is float:
			width = float(browser_width)
		if browser_height is int or browser_height is float:
			height = float(browser_height)
	return Vector2(maxf(width, 1.0), maxf(height, 1.0))

func _canvas_scale(size: Vector2) -> float:
	return maxf(minf(size.x / DESIGN_VIEWPORT_SIZE.x, size.y / DESIGN_VIEWPORT_SIZE.y), 0.001)

func _px(css_px: float, size: Vector2) -> float:
	return css_px / _canvas_scale(size)

func _font(css_px: float, size: Vector2) -> int:
	return maxi(1, roundi(_px(css_px, size)))

func _set_label(label: Label, css_px: float, size: Vector2) -> void:
	if label != null:
		label.add_theme_font_size_override("font_size", _font(css_px, size))

func _set_button(button: Button, width_css: float, height_css: float, font_css: float, size: Vector2) -> void:
	if button == null:
		return
	button.custom_minimum_size = Vector2(_px(width_css, size) if width_css > 0.0 else 0.0, _px(height_css, size))
	button.add_theme_font_size_override("font_size", _font(font_css, size))

func _safe_margin(size: Vector2, css_px := 8.0) -> void:
	var margin_value = _shell.get("safe_margin")
	if not margin_value is MarginContainer:
		return
	var margin := margin_value as MarginContainer
	var logical := roundi(_px(css_px, size))
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, logical)

func _fix_story(size: Vector2) -> void:
	_safe_margin(size, 8.0)
	var content_value = _shell.get("content")
	if content_value is VBoxContainer:
		(content_value as VBoxContainer).add_theme_constant_override("separation", roundi(_px(4.0, size)))

	# Controls own the first row. The chapter plate starts underneath them so a
	# 360-390 CSS-pixel phone can never put AUTO/SKIP on top of the title.
	var controls_value = _shell.get("story_controls")
	if controls_value is Control:
		var controls := controls_value as Control
		controls.anchor_left = 1.0
		controls.anchor_top = 0.0
		controls.anchor_right = 1.0
		controls.anchor_bottom = 0.0
		controls.offset_left = -_px(158.0, size)
		controls.offset_top = _px(8.0, size)
		controls.offset_right = -_px(8.0, size)
		controls.offset_bottom = _px(50.0, size)
		if controls is BoxContainer:
			(controls as BoxContainer).add_theme_constant_override("separation", roundi(_px(6.0, size)))
	var auto_value = _shell.get("story_auto_button")
	if auto_value is Button:
		_set_button(auto_value as Button, 72.0, 42.0, 14.0, size)
	var skip_value = _shell.get("story_skip_button")
	if skip_value is Button:
		_set_button(skip_value as Button, 76.0, 42.0, 14.0, size)

	var plate_value := _shell.find_child("PrologueChapterPlate", true, false)
	if plate_value is PanelContainer:
		var plate := plate_value as PanelContainer
		plate.anchor_left = 0.0
		plate.anchor_top = 0.0
		plate.anchor_right = 1.0
		plate.anchor_bottom = 0.0
		plate.offset_left = _px(8.0, size)
		plate.offset_top = _px(56.0, size)
		plate.offset_right = -_px(8.0, size)
		plate.offset_bottom = _px(124.0, size)
		var labels := plate.find_children("*", "Label", true, false)
		if labels.size() > 0 and labels[0] is Label:
			_set_label(labels[0] as Label, 10.0, size)
		if labels.size() > 1 and labels[1] is Label:
			var title := labels[1] as Label
			_set_label(title, 20.0, size)
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			title.clip_text = true

	var art_status_value = _shell.get("story_art_status")
	if art_status_value is Label:
		(art_status_value as Label).visible = false

	_fix_story_art(size)
	_fix_story_dialogue(size)

func _fix_story_art(size: Vector2) -> void:
	var layer_value = _shell.get("story_portrait_layer")
	if not layer_value is Control:
		return
	var layer := layer_value as Control
	var visible_art: Array[TextureRect] = []
	for child in layer.get_children():
		if not child is TextureRect:
			continue
		var art := child as TextureRect
		if art.texture == null or _is_placeholder(art.texture):
			art.visible = false
			continue
		art.visible = true
		visible_art.append(art)
	if visible_art.is_empty():
		_ensure_fallback_portrait(layer, visible_art)

	var dialogue_css := _dialogue_height_css()
	var count := visible_art.size()
	for index in range(count):
		var art := visible_art[index]
		art.anchor_top = 0.0
		art.anchor_bottom = 1.0
		art.offset_top = _px(132.0, size)
		art.offset_bottom = -_px(dialogue_css + 10.0, size)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if count <= 1:
			art.anchor_left = 0.06
			art.anchor_right = 0.94
		elif count == 2:
			art.anchor_left = 0.0 if index == 0 else 0.44
			art.anchor_right = 0.56 if index == 0 else 1.0
		else:
			var centers := [0.23, 0.5, 0.77]
			var center := float(centers[mini(index, 2)])
			art.anchor_left = center - 0.23
			art.anchor_right = center + 0.23
		art.offset_left = 0.0
		art.offset_right = 0.0

func _ensure_fallback_portrait(layer: Control, output: Array[TextureRect]) -> void:
	for old in _fallback_portraits:
		if is_instance_valid(old) and old.get_parent() == layer and old.texture != null:
			old.visible = true
			output.append(old)
	if not output.is_empty():
		return
	if not ResourceLoader.exists(FALLBACK_CARD):
		return
	var texture := load(FALLBACK_CARD) as Texture2D
	if texture == null:
		return
	var art := TextureRect.new()
	art.name = "MobilePortraitV2Fallback"
	art.texture = texture
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.add_child(art)
	_fallback_portraits.append(art)
	output.append(art)

func _is_placeholder(texture: Texture2D) -> bool:
	if texture == null:
		return true
	var path := texture.resource_path.to_lower()
	return path.contains("placeholder") or path.contains("dev_placeholder")

func _dialogue_height_css() -> float:
	var choices_value = _shell.get("scenario_choices")
	if choices_value is VBoxContainer and (choices_value as VBoxContainer).get_child_count() > 0:
		return 306.0
	return 214.0

func _fix_story_dialogue(size: Vector2) -> void:
	var choices_value = _shell.get("scenario_choices")
	var choice_mode := choices_value is VBoxContainer and (choices_value as VBoxContainer).get_child_count() > 0
	var dialogue_css := 306.0 if choice_mode else 214.0
	var margin_value := _shell.find_child("PrologueDialogueMargin", true, false)
	if margin_value is MarginContainer:
		var margin := margin_value as MarginContainer
		margin.anchor_left = 0.0
		margin.anchor_top = 1.0
		margin.anchor_right = 1.0
		margin.anchor_bottom = 1.0
		margin.offset_left = _px(8.0, size)
		margin.offset_right = -_px(8.0, size)
		margin.offset_top = -_px(dialogue_css, size)
		margin.offset_bottom = -_px(8.0, size)
	else:
		# Chapter-story scenes (including the N05 clear story) use the standard
		# VBox presentation rather than PrologueDialogueMargin.  The previous
		# portrait pass resized only its text children, leaving the actual touch
		# plate at an inherited/ambiguous height.  Give that plate a stable mobile
		# reading band before touching its typography.
		var standard_dialogue_value = _shell.get("story_dialogue_panel")
		if standard_dialogue_value is PanelContainer:
			var standard_dialogue := standard_dialogue_value as PanelContainer
			var standard_dialogue_css := 380.0 if choice_mode else 304.0
			standard_dialogue.custom_minimum_size.y = _px(standard_dialogue_css, size)
			standard_dialogue.mouse_filter = Control.MOUSE_FILTER_STOP
			standard_dialogue.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var eyebrow_value = _shell.get("story_speaker_eyebrow")
	if eyebrow_value is Label:
		_set_label(eyebrow_value as Label, 10.0, size)
	var speaker_value = _shell.get("scenario_speaker")
	if speaker_value is Label:
		var speaker := speaker_value as Label
		_set_label(speaker, 20.0, size)
		speaker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var text_value = _shell.get("scenario_text")
	if text_value is RichTextLabel:
		var body := text_value as RichTextLabel
		var font_size := _font(18.0 if choice_mode else 19.0, size)
		body.custom_minimum_size.y = _px(48.0 if choice_mode else 74.0, size)
		body.add_theme_font_size_override("normal_font_size", font_size)
		body.add_theme_font_size_override("bold_font_size", font_size)
		body.add_theme_constant_override("line_separation", roundi(_px(3.0, size)))
	if choices_value is VBoxContainer:
		var choices := choices_value as VBoxContainer
		choices.add_theme_constant_override("separation", roundi(_px(6.0, size)))
		for child in choices.get_children():
			if child is Button:
				var choice := child as Button
				choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_set_button(choice, 0.0, 44.0, 15.0, size)
	var hint_value = _shell.get("story_click_hint")
	if hint_value is Label:
		var hint := hint_value as Label
		_set_label(hint, 10.0, size)
		hint.visible = not choice_mode
	var page_value = _shell.get("story_page_indicator")
	if page_value is Label:
		var page := page_value as Label
		_set_label(page, 10.0, size)
		page.visible = not choice_mode

func _fix_progression_scroll(size: Vector2) -> void:
	# These screens share AppShell's named primary ScrollContainer.  Prior mobile
	# layouts scaled their controls but left the scrollbar in AUTO/default mode,
	# so a player who had just earned a level or weapon could easily miss that
	# there was more content below the fold.  Keep the vertical rail discoverable,
	# preserve horizontal lock, and make an intentional finger drag win over a
	# button press without turning a small tap into accidental scrolling.
	_safe_margin(size, 6.0)
	var scroll_value := _shell.find_child("PrimaryContentScroll", true, false)
	if not scroll_value is ScrollContainer:
		return
	var scroll := scroll_value as ScrollContainer
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.follow_focus = true
	scroll.scroll_deadzone = roundi(_px(12.0, size))
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	var rail := scroll.get_v_scroll_bar()
	if rail != null:
		rail.custom_minimum_size.x = _px(10.0, size)
		rail.add_theme_constant_override("grabber_min_size", roundi(_px(36.0, size)))
		if not rail.has_meta("mobile_progression_scroll_style"):
			rail.add_theme_color_override("font_color", Color("8fe9d9"))
			rail.set_meta("mobile_progression_scroll_style", true)

func _fix_map(size: Vector2) -> void:
	_safe_margin(size, 6.0)
	var map_value = _shell.get("active_chapter_map_screen")
	if not map_value is Control:
		return
	var map_screen := map_value as Control
	if not is_instance_valid(map_screen):
		return
	map_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_screen.custom_minimum_size.y = 0.0

	var content_value = _shell.get("content")
	if content_value is VBoxContainer:
		var content := content_value as VBoxContainer
		content.add_theme_constant_override("separation", roundi(_px(3.0, size)))
		_fix_map_shell_header(content, map_screen, size)

	var map_area_value = map_screen.get("map_area")
	if map_area_value is Control:
		var map_area := map_area_value as Control
		map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
		map_area.custom_minimum_size.y = 0.0

	_fix_map_toolbar(map_screen, size)
	_fix_map_overlay(map_screen, size)
	_fix_map_sheet(map_screen, size)
	_fix_map_nodes(map_screen, size)
	_fix_map_tutorial(map_screen, size)

func _fix_map_shell_header(content: VBoxContainer, map_screen: Control, size: Vector2) -> void:
	var back := _find_button_text(content, "‹ 뒤로", map_screen)
	if back != null:
		back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_set_button(back, 82.0, 40.0, 14.0, size)
	var subtitle := _find_label_text(content, MAP_SUBTITLE_FULL, map_screen)
	if subtitle == null:
		subtitle = _find_label_text(content, MAP_SUBTITLE_COMPACT, map_screen)
	if subtitle != null:
		subtitle.text = MAP_SUBTITLE_COMPACT
		_set_label(subtitle, 12.0, size)
		subtitle.visible = size.x > 410.0
		var parent := subtitle.get_parent()
		if parent != null and parent.get_child_count() > 0 and parent.get_child(0) is Label:
			var title := parent.get_child(0) as Label
			_set_label(title, 21.0, size)
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			title.clip_text = true

func _fix_map_toolbar(map_screen: Control, size: Vector2) -> void:
	var toolbar_value = map_screen.get("toolbar")
	if toolbar_value is HFlowContainer:
		var toolbar := toolbar_value as HFlowContainer
		# The six core controls are compact *named* actions, rather than a
		# multi-row desktop toolbar.  This reserves a single 48–56px rail and
		# gives the tactical map its height back on common 360–390px phones.
		toolbar.add_theme_constant_override("h_separation", roundi(_px(2.0, size)))
		toolbar.add_theme_constant_override("v_separation", 0)
	var width_css := clampf((size.x - 22.0) / 6.0, 48.0, 56.0)
	var compact_labels := ["일반", "위험", "부대", "개요", "스킵"]
	var buttons_value = map_screen.get("map_toolbar_buttons")
	if buttons_value is Array:
		var buttons := buttons_value as Array
		for index in range(buttons.size()):
			var button_value = buttons[index]
			if button_value is Button:
				var button := button_value as Button
				_set_button(button, width_css, 48.0, 14.0, size)
				if index < compact_labels.size():
					button.text = str(compact_labels[index])
	var wait_value = map_screen.get("wait_button")
	if wait_value is Button:
		var wait_button := wait_value as Button
		_set_button(wait_button, width_css, 48.0, 14.0, size)
		wait_button.text = "대기"

func _fix_map_overlay(map_screen: Control, size: Vector2) -> void:
	var status_value = map_screen.get("status_label")
	if status_value is Label:
		var status := status_value as Label
		status.position = Vector2(_px(6.0, size), _px(6.0, size))
		status.size = Vector2(_px(190.0, size), _px(34.0, size))
		status.custom_minimum_size = status.size
		status.add_theme_font_size_override("font_size", _font(12.0, size))
		status.autowrap_mode = TextServer.AUTOWRAP_OFF
		status.clip_text = true
	var next_value = map_screen.get("next_encounter_button")
	if next_value is Button:
		var next_button := next_value as Button
		next_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		next_button.offset_left = -_px(126.0, size)
		next_button.offset_top = _px(6.0, size)
		next_button.offset_right = -_px(6.0, size)
		next_button.offset_bottom = _px(44.0, size)
		next_button.custom_minimum_size = Vector2(_px(120.0, size), _px(38.0, size))
		next_button.add_theme_font_size_override("font_size", _font(13.0, size))
	var minimap_value = map_screen.get("route_minimap")
	if minimap_value is Control:
		(minimap_value as Control).visible = false
	var legend_value = map_screen.get("legend_card")
	if legend_value is Control:
		(legend_value as Control).visible = false

func _fix_map_sheet(map_screen: Control, size: Vector2) -> void:
	var panel_value = map_screen.get("detail_panel")
	if not panel_value is PanelContainer:
		return
	var panel := panel_value as PanelContainer
	# A selection is contextual, not an inspector.  Keep the card scrollable,
	# but cap it below a third of a portrait viewport.
	var sheet_css := clampf(size.y * 0.29, 222.0, 258.0)
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = _px(6.0, size)
	panel.offset_right = -_px(6.0, size)
	panel.offset_top = -_px(sheet_css, size)
	panel.offset_bottom = -_px(6.0, size)

	var scroll_value = map_screen.get("detail_scroll")
	if scroll_value is ScrollContainer:
		var scroll := scroll_value as ScrollContainer
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var title_value = map_screen.get("detail_title")
	if title_value is Label:
		var title := title_value as Label
		_set_label(title, 18.0, size)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var body_value = map_screen.get("detail_body")
	if body_value is RichTextLabel:
		var body := body_value as RichTextLabel
		body.custom_minimum_size.y = _px(58.0, size)
		body.add_theme_font_size_override("normal_font_size", _font(16.0, size))
		body.add_theme_font_size_override("bold_font_size", _font(16.0, size))
		body.add_theme_constant_override("line_separation", roundi(_px(3.0, size)))
	if scroll_value is ScrollContainer:
		for child in (scroll_value as ScrollContainer).find_children("*", "Button", true, false):
			if child is Button:
				var action := child as Button
				action.custom_minimum_size.y = _px(46.0, size)
				action.add_theme_font_size_override("font_size", _font(15.0, size))

func _fix_map_nodes(map_screen: Control, size: Vector2) -> void:
	var nodes_value = map_screen.get("node_buttons")
	if not nodes_value is Dictionary:
		return
	var nodes := nodes_value as Dictionary
	for key in nodes.keys():
		var value = nodes[key]
		if value is Button:
			var button := value as Button
			button.custom_minimum_size = Vector2(_px(54.0, size), _px(38.0, size))
			button.size = button.custom_minimum_size
			button.add_theme_font_size_override("font_size", _font(12.0, size))

func _fix_map_tutorial(map_screen: Control, size: Vector2) -> void:
	var dimmer_value = map_screen.get("tutorial_dimmer")
	if dimmer_value is ColorRect:
		# Preserve context: the player must be able to see the highlighted range
		# and target while reading the first-turn instructions.
		(dimmer_value as ColorRect).color = Color("01050b96")
	var panel_value = map_screen.get("tutorial_panel")
	if panel_value is PanelContainer:
		var panel := panel_value as PanelContainer
		# A lower sheet exposes more than half the map, unlike the earlier
		# 80%-height briefing modal that concealed the exact controls it named.
		panel.anchor_left = 0.06
		panel.anchor_top = 0.49
		panel.anchor_right = 0.94
		panel.anchor_bottom = 0.95
		panel.offset_left = 0.0
		panel.offset_top = 0.0
		panel.offset_right = 0.0
		panel.offset_bottom = 0.0
	var scroll_value = map_screen.get("tutorial_scroll")
	if scroll_value is ScrollContainer:
		(scroll_value as ScrollContainer).vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var title_value = map_screen.get("tutorial_title")
	if title_value is Label:
		_set_label(title_value as Label, 22.0, size)
	var body_value = map_screen.get("tutorial_body")
	if body_value is RichTextLabel:
		var body := body_value as RichTextLabel
		body.add_theme_font_size_override("normal_font_size", _font(17.0, size))
		body.add_theme_font_size_override("bold_font_size", _font(17.0, size))
		body.add_theme_constant_override("line_separation", roundi(_px(3.0, size)))
	var continue_value = map_screen.get("tutorial_continue_button")
	if continue_value is Button:
		_set_button(continue_value as Button, 0.0, 46.0, 16.0, size)
	var dismiss_value = map_screen.get("tutorial_dismiss_button")
	if dismiss_value is Button:
		_set_button(dismiss_value as Button, 0.0, 42.0, 13.0, size)

func _find_button_text(root: Node, text_value: String, skip: Node) -> Button:
	if root == skip:
		return null
	if root is Button and (root as Button).text == text_value:
		return root as Button
	for child in root.get_children():
		var found := _find_button_text(child, text_value, skip)
		if found != null:
			return found
	return null

func _find_label_text(root: Node, text_value: String, skip: Node) -> Label:
	if root == skip:
		return null
	if root is Label and (root as Label).text == text_value:
		return root as Label
	for child in root.get_children():
		var found := _find_label_text(child, text_value, skip)
		if found != null:
			return found
	return null
