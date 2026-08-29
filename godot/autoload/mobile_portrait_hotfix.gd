extends Node

# Mobile portrait presentation override for the fixed 1920x1080 Godot canvas.
# The desktop/landscape layouts remain authoritative.  This autoload runs late
# and touches presentation geometry only, so scenario/map/battle/save authority
# is never reconstructed by the phone layout pass.

const DESIGN_VIEWPORT_SIZE := Vector2(1920.0, 1080.0)
const PROBE_INTERVAL := 0.08
const MAP_SUBTITLE_FULL := "탐색 경로를 따라 조우를 선택하고, 기존 실시간 전투에 진입합니다."
const MAP_SUBTITLE_COMPACT := "조우를 선택해 이동·전투를 진행하세요."
const PROLOGUE_FALLBACK_CG := "res://assets/runtime_web/story/cg_ch01_pilot_teamwork_1280x720.png"
# Non-combat surfaces use only the approved 8-head runtime portrait.  The
# legacy compact `*_card_384x576` family contains early SD placeholders for
# several members and must never be selected by a story/mobile fallback.
const PROLOGUE_FALLBACK_CARD := "res://assets/runtime_web/characters/CHR001/portrait.png"

var _probe_left := 0.0
var _shell: Control
var _chapter_subtitle: Label
var _texture_cache: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# AppShell has its own compact probes. Run after normal scene processing so
	# this portrait-only pass wins when both update geometry in the same frame.
	process_priority = 1000
	call_deferred("_apply_portrait_fixes")

func _process(delta: float) -> void:
	_probe_left -= delta
	if _probe_left > 0.0:
		return
	_probe_left = PROBE_INTERVAL
	_apply_portrait_fixes()

func _apply_portrait_fixes() -> void:
	var runtime_size := _runtime_layout_size()
	if runtime_size.y <= runtime_size.x:
		return
	if _shell == null or not is_instance_valid(_shell):
		_shell = _find_app_shell(get_tree().root)
	if _shell == null:
		return
	var current_screen := str(_shell.get("current_screen"))
	if current_screen == "STORY":
		_fix_story_portrait(runtime_size)
	elif current_screen == "STAGE_SELECT":
		_fix_chapter_map_portrait(runtime_size)

func _find_app_shell(node: Node) -> Control:
	if node is Control and node.has_method("responsive_ui_metrics_for_size") and node.has_method("_show_chapter_map"):
		return node as Control
	for child in node.get_children():
		if child is SubViewport:
			continue
		var found := _find_app_shell(child)
		if found != null:
			return found
	return null

func _runtime_layout_size() -> Vector2:
	var window_size := DisplayServer.window_get_size()
	var width := float(window_size.x)
	var height := float(window_size.y)
	if OS.has_feature("web"):
		var browser_width = JavaScriptBridge.eval("window.innerWidth", true)
		var browser_height = JavaScriptBridge.eval("window.innerHeight", true)
		if browser_width is int or browser_width is float:
			width = float(browser_width)
		if browser_height is int or browser_height is float:
			height = float(browser_height)
	return Vector2(maxf(1.0, width), maxf(1.0, height))

func _canvas_scale(runtime_size: Vector2) -> float:
	return maxf(minf(runtime_size.x / DESIGN_VIEWPORT_SIZE.x, runtime_size.y / DESIGN_VIEWPORT_SIZE.y), 0.001)

func _logical_px(css_px: float, runtime_size: Vector2) -> float:
	return css_px / _canvas_scale(runtime_size)

func _font_px(css_px: float, runtime_size: Vector2) -> int:
	return maxi(1, roundi(_logical_px(css_px, runtime_size)))

func _set_label_css_size(label: Label, css_px: float, runtime_size: Vector2) -> void:
	if label != null:
		label.add_theme_font_size_override("font_size", _font_px(css_px, runtime_size))

func _set_button_css(button: Button, width_css: float, height_css: float, font_css: float, runtime_size: Vector2) -> void:
	if button == null:
		return
	button.custom_minimum_size = Vector2(_logical_px(width_css, runtime_size), _logical_px(height_css, runtime_size))
	button.add_theme_font_size_override("font_size", _font_px(font_css, runtime_size))

func _set_safe_margin(css_px: float, runtime_size: Vector2) -> void:
	var safe_margin_value = _shell.get("safe_margin")
	if not safe_margin_value is MarginContainer:
		return
	var safe_margin := safe_margin_value as MarginContainer
	var margin := roundi(_logical_px(css_px, runtime_size))
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		safe_margin.add_theme_constant_override(side, margin)

func _fix_story_portrait(runtime_size: Vector2) -> void:
	_set_safe_margin(8.0, runtime_size)
	var content_value = _shell.get("content")
	if content_value is VBoxContainer:
		(content_value as VBoxContainer).add_theme_constant_override("separation", roundi(_logical_px(4.0, runtime_size)))

	var chapter_plate_value := _shell.find_child("PrologueChapterPlate", true, false)
	if chapter_plate_value is PanelContainer:
		var chapter_plate := chapter_plate_value as PanelContainer
		chapter_plate.offset_left = _logical_px(8.0, runtime_size)
		chapter_plate.offset_top = _logical_px(8.0, runtime_size)
		chapter_plate.offset_right = _logical_px(220.0, runtime_size)
		chapter_plate.offset_bottom = _logical_px(72.0, runtime_size)
		var plate_labels := chapter_plate.find_children("*", "Label", true, false)
		if plate_labels.size() >= 1 and plate_labels[0] is Label:
			_set_label_css_size(plate_labels[0] as Label, 11.0, runtime_size)
		if plate_labels.size() >= 2 and plate_labels[1] is Label:
			var title := plate_labels[1] as Label
			_set_label_css_size(title, 22.0, runtime_size)
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_fix_story_top_controls(runtime_size)
	_fix_story_art(runtime_size)
	_fix_story_dialogue(runtime_size)

func _fix_story_top_controls(runtime_size: Vector2) -> void:
	var controls_value = _shell.get("story_controls")
	if not controls_value is HBoxContainer:
		return
	var controls := controls_value as HBoxContainer
	controls.anchor_left = 1.0
	controls.anchor_top = 0.0
	controls.anchor_right = 1.0
	controls.anchor_bottom = 0.0
	controls.offset_left = -_logical_px(158.0, runtime_size)
	controls.offset_top = _logical_px(10.0, runtime_size)
	controls.offset_right = -_logical_px(8.0, runtime_size)
	controls.offset_bottom = _logical_px(50.0, runtime_size)
	controls.add_theme_constant_override("separation", roundi(_logical_px(6.0, runtime_size)))
	var auto_value = _shell.get("story_auto_button")
	if auto_value is Button:
		_set_button_css(auto_value as Button, 72.0, 40.0, 14.0, runtime_size)
	var skip_value = _shell.get("story_skip_button")
	if skip_value is Button:
		_set_button_css(skip_value as Button, 76.0, 40.0, 14.0, runtime_size)

func _fix_story_art(runtime_size: Vector2) -> void:
	var background_value = _shell.get("story_background")
	if background_value is TextureRect:
		var background := background_value as TextureRect
		if background.texture == null or _is_placeholder_texture(background.texture):
			var fallback_cg := _load_texture(PROLOGUE_FALLBACK_CG)
			if fallback_cg != null:
				background.texture = fallback_cg
				background.visible = true
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		background.modulate = Color(0.78, 0.86, 0.96, 0.72)

	var layer_value = _shell.get("story_portrait_layer")
	if not layer_value is Control:
		return
	var layer := layer_value as Control
	var real_portraits: Array[TextureRect] = []
	for child in layer.get_children():
		if not child is TextureRect:
			continue
		var art := child as TextureRect
		if art.texture == null or _is_placeholder_texture(art.texture):
			art.visible = false
			continue
		art.visible = true
		real_portraits.append(art)

	if real_portraits.is_empty():
		_add_runtime_portrait_fallbacks(layer, real_portraits)

	var dialogue_height_css := _story_dialogue_height_css()
	var count := real_portraits.size()
	for index in range(count):
		var art := real_portraits[index]
		art.anchor_top = 0.0
		art.anchor_bottom = 1.0
		art.offset_top = _logical_px(78.0, runtime_size)
		art.offset_bottom = -_logical_px(dialogue_height_css + 8.0, runtime_size)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if count <= 1:
			art.anchor_left = 0.08
			art.anchor_right = 0.92
			art.offset_left = 0.0
			art.offset_right = 0.0
		elif count == 2:
			art.anchor_left = 0.0 if index == 0 else 0.44
			art.anchor_right = 0.56 if index == 0 else 1.0
			art.offset_left = 0.0
			art.offset_right = 0.0
		else:
			var slot_width := 0.46
			var centers := [0.25, 0.5, 0.75]
			var center := float(centers[mini(index, 2)])
			art.anchor_left = center - slot_width * 0.5
			art.anchor_right = center + slot_width * 0.5
			art.offset_left = 0.0
			art.offset_right = 0.0

func _add_runtime_portrait_fallbacks(layer: Control, output: Array[TextureRect]) -> void:
	var asset_ids := _story_portrait_asset_ids()
	if asset_ids.is_empty():
		asset_ids.append("portrait_chr001_dev")
	for asset_id_value in asset_ids:
		var path := _runtime_card_path(str(asset_id_value))
		if path.is_empty():
			continue
		var texture := _load_texture(path)
		if texture == null:
			continue
		var art := TextureRect.new()
		art.name = "MobilePortraitFallback_%s" % str(asset_id_value)
		art.texture = texture
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.modulate = Color(0.96, 0.98, 1.0, 0.92)
		layer.add_child(art)
		output.append(art)
	if output.is_empty():
		var texture := _load_texture(PROLOGUE_FALLBACK_CARD)
		if texture != null:
			var art := TextureRect.new()
			art.name = "MobilePortraitFallback_CHR001"
			art.texture = texture
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			layer.add_child(art)
			output.append(art)

func _story_portrait_asset_ids() -> Array[String]:
	var result: Array[String] = []
	var runner = _shell.get("scenario_runner")
	if runner == null:
		return result
	var state = runner.get("state")
	if state == null:
		return result
	var portraits_value = state.get("portraits")
	if not portraits_value is Dictionary:
		return result
	var portraits := portraits_value as Dictionary
	for slot in ["LEFT", "CENTER", "RIGHT"]:
		if not portraits.has(slot):
			continue
		var portrait_value = portraits[slot]
		if portrait_value is Dictionary:
			var asset_id := str((portrait_value as Dictionary).get("asset_id", ""))
			if not asset_id.is_empty() and asset_id not in result:
				result.append(asset_id)
	for slot in portraits.keys():
		var portrait_value = portraits[slot]
		if portrait_value is Dictionary:
			var asset_id := str((portrait_value as Dictionary).get("asset_id", ""))
			if not asset_id.is_empty() and asset_id not in result:
				result.append(asset_id)
	return result

func _runtime_card_path(asset_id: String) -> String:
	var normalized := asset_id.to_lower()
	const MARKER := "portrait_chr"
	var marker_index := normalized.find(MARKER)
	if marker_index < 0:
		return ""
	var suffix := normalized.substr(marker_index + MARKER.length())
	if suffix.length() < 3:
		return ""
	var digits := suffix.substr(0, 3)
	return "res://assets/runtime_web/characters/CHR%s/portrait.png" % digits

func _is_placeholder_texture(texture: Texture2D) -> bool:
	if texture == null:
		return true
	var path := texture.resource_path.to_lower()
	return path.contains("placeholder") or path.contains("dev_placeholder")

func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _texture_cache.has(path) and _texture_cache[path] is Texture2D:
		return _texture_cache[path] as Texture2D
	var texture := load(path) as Texture2D
	if texture != null:
		_texture_cache[path] = texture
	return texture

func _story_dialogue_height_css() -> float:
	var choices_value = _shell.get("scenario_choices")
	if choices_value is VBoxContainer and (choices_value as VBoxContainer).get_child_count() > 0:
		return 286.0
	return 202.0

func _fix_story_dialogue(runtime_size: Vector2) -> void:
	var choice_mode := false
	var choices_value = _shell.get("scenario_choices")
	if choices_value is VBoxContainer:
		var choices := choices_value as VBoxContainer
		choice_mode = choices.get_child_count() > 0
		choices.add_theme_constant_override("separation", roundi(_logical_px(6.0, runtime_size)))
		for child in choices.get_children():
			if child is Button:
				var choice := child as Button
				choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_set_button_css(choice, 0.0, 44.0, 16.0, runtime_size)
				choice.custom_minimum_size.x = 0.0

	var dialogue_height_css := 286.0 if choice_mode else 202.0
	var prologue_margin := _shell.find_child("PrologueDialogueMargin", true, false)
	if prologue_margin is MarginContainer:
		var dialogue_margin := prologue_margin as MarginContainer
		dialogue_margin.anchor_left = 0.0
		dialogue_margin.anchor_top = 1.0
		dialogue_margin.anchor_right = 1.0
		dialogue_margin.anchor_bottom = 1.0
		dialogue_margin.offset_left = _logical_px(8.0, runtime_size)
		dialogue_margin.offset_right = -_logical_px(8.0, runtime_size)
		dialogue_margin.offset_top = -_logical_px(dialogue_height_css, runtime_size)
		dialogue_margin.offset_bottom = -_logical_px(8.0, runtime_size)

	var eyebrow_value = _shell.get("story_speaker_eyebrow")
	if eyebrow_value is Label:
		_set_label_css_size(eyebrow_value as Label, 11.0, runtime_size)
	var speaker_value = _shell.get("scenario_speaker")
	if speaker_value is Label:
		_set_label_css_size(speaker_value as Label, 21.0, runtime_size)
	var scenario_text_value = _shell.get("scenario_text")
	if scenario_text_value is RichTextLabel:
		var story_body := scenario_text_value as RichTextLabel
		var body_size := _font_px(19.0 if choice_mode else 20.0, runtime_size)
		story_body.custom_minimum_size.y = _logical_px(46.0 if choice_mode else 72.0, runtime_size)
		story_body.add_theme_font_size_override("normal_font_size", body_size)
		story_body.add_theme_font_size_override("bold_font_size", body_size)
		story_body.add_theme_constant_override("line_separation", roundi(_logical_px(4.0, runtime_size)))
	var click_hint_value = _shell.get("story_click_hint")
	if click_hint_value is Label:
		var hint := click_hint_value as Label
		_set_label_css_size(hint, 11.0, runtime_size)
		hint.visible = not choice_mode
	var page_indicator_value = _shell.get("story_page_indicator")
	if page_indicator_value is Label:
		var page := page_indicator_value as Label
		_set_label_css_size(page, 11.0, runtime_size)
		page.visible = not choice_mode
	var footer := _shell.find_child("StoryProgressFooter", true, false)
	if footer is Control:
		(footer as Control).visible = not choice_mode

func _fix_chapter_map_portrait(runtime_size: Vector2) -> void:
	_set_safe_margin(8.0, runtime_size)
	var map_screen_value = _shell.get("active_chapter_map_screen")
	if not map_screen_value is Control:
		return
	var map_screen := map_screen_value as Control
	if not is_instance_valid(map_screen):
		return

	var content_value = _shell.get("content")
	if content_value is VBoxContainer:
		var content := content_value as VBoxContainer
		content.add_theme_constant_override("separation", roundi(_logical_px(4.0, runtime_size)))
		_fix_chapter_shell_header(content, map_screen, runtime_size)

	_fix_map_toolbar(map_screen, runtime_size)
	_fix_map_overlay(map_screen, runtime_size)
	_fix_map_detail_sheet(map_screen, runtime_size)
	_fix_map_node_buttons(map_screen, runtime_size)

func _fix_chapter_shell_header(content: VBoxContainer, map_screen: Control, runtime_size: Vector2) -> void:
	if _chapter_subtitle == null or not is_instance_valid(_chapter_subtitle):
		_chapter_subtitle = _find_label_by_text(content, MAP_SUBTITLE_FULL, map_screen)
		if _chapter_subtitle == null:
			_chapter_subtitle = _find_label_by_text(content, MAP_SUBTITLE_COMPACT, map_screen)
	if _chapter_subtitle != null:
		_chapter_subtitle.text = MAP_SUBTITLE_COMPACT
		_set_label_css_size(_chapter_subtitle, 13.0, runtime_size)
		var labels := _chapter_subtitle.get_parent()
		if labels != null and labels.get_child_count() > 0:
			var title_value = labels.get_child(0)
			if title_value is Label:
				var title := title_value as Label
				_set_label_css_size(title, 23.0, runtime_size)
				title.autowrap_mode = TextServer.AUTOWRAP_OFF
			var header := labels.get_parent()
			if header != null:
				var back_button := _find_button_by_text(header, "‹ 뒤로")
				if back_button != null:
					back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
					_set_button_css(back_button, 84.0, 40.0, 15.0, runtime_size)

func _fix_map_toolbar(map_screen: Control, runtime_size: Vector2) -> void:
	var toolbar_value = map_screen.get("toolbar")
	if toolbar_value is HFlowContainer:
		var toolbar := toolbar_value as HFlowContainer
		toolbar.add_theme_constant_override("h_separation", roundi(_logical_px(4.0, runtime_size)))
		toolbar.add_theme_constant_override("v_separation", roundi(_logical_px(4.0, runtime_size)))
	var button_width_css := clampf((runtime_size.x - 36.0) / 3.0, 96.0, 112.0)
	var toolbar_buttons_value = map_screen.get("map_toolbar_buttons")
	if toolbar_buttons_value is Array:
		var toolbar_buttons := toolbar_buttons_value as Array
		for index in range(toolbar_buttons.size()):
			if toolbar_buttons[index] is Button:
				var button := toolbar_buttons[index] as Button
				_set_button_css(button, button_width_css, 42.0, 15.0, runtime_size)
				if index < 5:
					button.text = ["일반", "위험", "부대", "개요", "스킵"][index]
	var wait_value = map_screen.get("wait_button")
	if wait_value is Button:
		_set_button_css(wait_value as Button, button_width_css, 42.0, 15.0, runtime_size)

func _fix_map_overlay(map_screen: Control, runtime_size: Vector2) -> void:
	var status_value = map_screen.get("status_label")
	var status_backplate_value = map_screen.get("status_backplate")
	if status_value is Label:
		var status := status_value as Label
		status.position = Vector2(_logical_px(8.0, runtime_size), _logical_px(8.0, runtime_size))
		status.size = Vector2(_logical_px(194.0, runtime_size), _logical_px(34.0, runtime_size))
		status.custom_minimum_size = status.size
		status.add_theme_font_size_override("font_size", _font_px(13.0, runtime_size))
		status.autowrap_mode = TextServer.AUTOWRAP_OFF
		status.clip_text = true
		if status_backplate_value is PanelContainer:
			var backplate := status_backplate_value as PanelContainer
			backplate.position = Vector2(-_logical_px(4.0, runtime_size), -_logical_px(3.0, runtime_size))
			backplate.size = status.size + Vector2(_logical_px(8.0, runtime_size), _logical_px(6.0, runtime_size))
	var next_value = map_screen.get("next_encounter_button")
	if next_value is Button:
		var next_button := next_value as Button
		next_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		next_button.offset_left = -_logical_px(132.0, runtime_size)
		next_button.offset_right = -_logical_px(8.0, runtime_size)
		next_button.offset_top = _logical_px(8.0, runtime_size)
		next_button.offset_bottom = _logical_px(46.0, runtime_size)
		next_button.custom_minimum_size = Vector2(_logical_px(124.0, runtime_size), _logical_px(38.0, runtime_size))
		next_button.add_theme_font_size_override("font_size", _font_px(14.0, runtime_size))
	var minimap_value = map_screen.get("route_minimap")
	if minimap_value is Control:
		# The full 3D map is already the primary spatial aid. On a 390 px phone the
		# extra route minimap only creates a third overlay layer above the sheet.
		(minimap_value as Control).visible = false
	var legend_value = map_screen.get("legend_card")
	if legend_value is Control:
		(legend_value as Control).visible = false

func _fix_map_detail_sheet(map_screen: Control, runtime_size: Vector2) -> void:
	var detail_panel_value = map_screen.get("detail_panel")
	if not detail_panel_value is PanelContainer:
		return
	var detail_panel := detail_panel_value as PanelContainer
	detail_panel.anchor_left = 0.0
	detail_panel.anchor_right = 1.0
	detail_panel.anchor_top = 1.0
	detail_panel.anchor_bottom = 1.0
	detail_panel.offset_left = _logical_px(6.0, runtime_size)
	detail_panel.offset_right = -_logical_px(6.0, runtime_size)
	detail_panel.offset_top = -_logical_px(230.0, runtime_size)
	detail_panel.offset_bottom = -_logical_px(6.0, runtime_size)

	var detail_scroll_value = map_screen.get("detail_scroll")
	if detail_scroll_value is ScrollContainer:
		var scroll := detail_scroll_value as ScrollContainer
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var detail_title_value = map_screen.get("detail_title")
	if detail_title_value is Label:
		var title := detail_title_value as Label
		_set_label_css_size(title, 18.0, runtime_size)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var detail_body_value = map_screen.get("detail_body")
	if detail_body_value is RichTextLabel:
		var detail_body := detail_body_value as RichTextLabel
		detail_body.custom_minimum_size = Vector2(0.0, _logical_px(56.0, runtime_size))
		detail_body.add_theme_font_size_override("normal_font_size", _font_px(15.0, runtime_size))
		detail_body.add_theme_font_size_override("bold_font_size", _font_px(15.0, runtime_size))
		detail_body.add_theme_constant_override("line_separation", roundi(_logical_px(3.0, runtime_size)))
	if detail_scroll_value is ScrollContainer:
		for child in (detail_scroll_value as ScrollContainer).find_children("*", "Button", true, false):
			if child is Button:
				var action := child as Button
				action.custom_minimum_size.y = _logical_px(42.0, runtime_size)
				action.add_theme_font_size_override("font_size", _font_px(15.0, runtime_size))

func _fix_map_node_buttons(map_screen: Control, runtime_size: Vector2) -> void:
	var node_buttons_value = map_screen.get("node_buttons")
	if not node_buttons_value is Dictionary:
		return
	var node_buttons := node_buttons_value as Dictionary
	for node_id in node_buttons.keys():
		var button_value = node_buttons[node_id]
		if not button_value is Button:
			continue
		var button := button_value as Button
		button.custom_minimum_size = Vector2(_logical_px(58.0, runtime_size), _logical_px(38.0, runtime_size))
		button.size = button.custom_minimum_size
		button.add_theme_font_size_override("font_size", _font_px(13.0, runtime_size))

func _find_label_by_text(root: Node, text_value: String, skip: Node) -> Label:
	if root == skip:
		return null
	if root is Label and (root as Label).text == text_value:
		return root as Label
	for child in root.get_children():
		var found := _find_label_by_text(child, text_value, skip)
		if found != null:
			return found
	return null

func _find_button_by_text(root: Node, text_value: String) -> Button:
	if root is Button and (root as Button).text == text_value:
		return root as Button
	for child in root.get_children():
		var found := _find_button_by_text(child, text_value)
		if found != null:
			return found
	return null
