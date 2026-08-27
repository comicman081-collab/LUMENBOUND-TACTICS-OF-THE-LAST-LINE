extends Node

# Release-side portrait correction for the fixed 1920x1080 canvas. The main UI
# already distinguishes portrait from compact landscape, but a few story Labels
# were converted to logical pixels and then passed through the generic Label
# factory, applying the portrait scale twice. The chapter map also devoted too
# much of a phone viewport to shell copy + a 322 px contextual sheet. Keep the
# gameplay/runtime state untouched and correct only presentation geometry.

const DESIGN_VIEWPORT_SIZE := Vector2(1920.0, 1080.0)
const PROBE_INTERVAL := 0.08
const MAP_SUBTITLE_FULL := "탐색 경로를 따라 조우를 선택하고, 기존 실시간 전투에 진입합니다."
const MAP_SUBTITLE_COMPACT := "조우를 선택해 이동·전투를 진행하세요."

var _probe_left := 0.0
var _shell: Control
var _chapter_subtitle: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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

func _logical_px(css_px: float, runtime_size: Vector2) -> float:
	var canvas_scale := minf(runtime_size.x / DESIGN_VIEWPORT_SIZE.x, runtime_size.y / DESIGN_VIEWPORT_SIZE.y)
	return css_px / maxf(canvas_scale, 0.001)

func _set_label_css_size(label: Label, css_px: float, runtime_size: Vector2) -> void:
	if label != null:
		label.add_theme_font_size_override("font_size", roundi(_logical_px(css_px, runtime_size)))

func _fix_story_portrait(runtime_size: Vector2) -> void:
	# Prologue chapter labels are the visible double-scale regression: e.g. a
	# target 30 CSS px title became ~147 CSS px at 390 px wide.
	var chapter_plate := _shell.find_child("PrologueChapterPlate", true, false)
	if chapter_plate != null and chapter_plate.get_child_count() > 0:
		var chapter_copy := chapter_plate.get_child(0)
		if chapter_copy.get_child_count() >= 2:
			var eyebrow = chapter_copy.get_child(0)
			var chapter_title = chapter_copy.get_child(1)
			if eyebrow is Label:
				_set_label_css_size(eyebrow as Label, 13.0, runtime_size)
			if chapter_title is Label:
				_set_label_css_size(chapter_title as Label, 28.0, runtime_size)

	var speaker_eyebrow_value = _shell.get("story_speaker_eyebrow")
	if speaker_eyebrow_value is Label:
		_set_label_css_size(speaker_eyebrow_value as Label, 13.0, runtime_size)
	var speaker_value = _shell.get("scenario_speaker")
	if speaker_value is Label:
		_set_label_css_size(speaker_value as Label, 27.0, runtime_size)
	var click_hint_value = _shell.get("story_click_hint")
	if click_hint_value is Label:
		_set_label_css_size(click_hint_value as Label, 13.0, runtime_size)
	var page_indicator_value = _shell.get("story_page_indicator")
	if page_indicator_value is Label:
		_set_label_css_size(page_indicator_value as Label, 13.0, runtime_size)

	# The body was not double-scaled, but 24 CSS px gives the fixed lower card
	# enough room for 3-4 Korean lines while keeping tap targets at 56+ CSS px.
	var scenario_text_value = _shell.get("scenario_text")
	if scenario_text_value is RichTextLabel:
		var story_body := scenario_text_value as RichTextLabel
		var body_size := roundi(_logical_px(24.0, runtime_size))
		story_body.add_theme_font_size_override("normal_font_size", body_size)
		story_body.add_theme_font_size_override("bold_font_size", body_size)

	var prologue_margin := _shell.find_child("PrologueDialogueMargin", true, false)
	if prologue_margin is MarginContainer:
		var dialogue_margin := prologue_margin as MarginContainer
		dialogue_margin.offset_left = _logical_px(14.0, runtime_size)
		dialogue_margin.offset_right = -_logical_px(14.0, runtime_size)
		dialogue_margin.offset_top = -_logical_px(252.0, runtime_size)
		dialogue_margin.offset_bottom = -_logical_px(14.0, runtime_size)

func _fix_chapter_map_portrait(runtime_size: Vector2) -> void:
	var map_screen_value = _shell.get("active_chapter_map_screen")
	if not map_screen_value is Control:
		return
	var map_screen := map_screen_value as Control
	if not is_instance_valid(map_screen):
		return

	var content_value = _shell.get("content")
	if content_value is VBoxContainer:
		_fix_chapter_shell_header(content_value as VBoxContainer, map_screen, runtime_size)

	var detail_panel_value = map_screen.get("detail_panel")
	if detail_panel_value is PanelContainer:
		var detail_panel := detail_panel_value as PanelContainer
		# Existing ScrollContainer remains authoritative; make the contextual sheet
		# 242 physical px tall instead of 322 so the map remains playable above it.
		detail_panel.offset_left = _logical_px(8.0, runtime_size)
		detail_panel.offset_right = -_logical_px(8.0, runtime_size)
		detail_panel.offset_top = -_logical_px(252.0, runtime_size)
		detail_panel.offset_bottom = -_logical_px(10.0, runtime_size)

	var detail_title_value = map_screen.get("detail_title")
	if detail_title_value is Label:
		_set_label_css_size(detail_title_value as Label, 23.0, runtime_size)
	var detail_body_value = map_screen.get("detail_body")
	if detail_body_value is RichTextLabel:
		var detail_body := detail_body_value as RichTextLabel
		detail_body.custom_minimum_size = Vector2(0.0, _logical_px(62.0, runtime_size))
		detail_body.add_theme_font_size_override("normal_font_size", roundi(_logical_px(19.0, runtime_size)))

func _fix_chapter_shell_header(content: VBoxContainer, map_screen: Control, runtime_size: Vector2) -> void:
	if _chapter_subtitle == null or not is_instance_valid(_chapter_subtitle):
		_chapter_subtitle = _find_label_by_text(content, MAP_SUBTITLE_FULL, map_screen)
		if _chapter_subtitle == null:
			_chapter_subtitle = _find_label_by_text(content, MAP_SUBTITLE_COMPACT, map_screen)
	if _chapter_subtitle == null:
		return
	_chapter_subtitle.text = MAP_SUBTITLE_COMPACT
	_set_label_css_size(_chapter_subtitle, 17.0, runtime_size)
	var labels := _chapter_subtitle.get_parent()
	if labels != null and labels.get_child_count() > 0:
		var title_value = labels.get_child(0)
		if title_value is Label:
			_set_label_css_size(title_value as Label, 26.0, runtime_size)
		var header := labels.get_parent()
		if header != null:
			var back_button := _find_button_by_text(header, "‹ 뒤로")
			if back_button != null:
				back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				back_button.custom_minimum_size = Vector2(_logical_px(96.0, runtime_size), _logical_px(52.0, runtime_size))
				back_button.add_theme_font_size_override("font_size", roundi(_logical_px(17.0, runtime_size)))

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
