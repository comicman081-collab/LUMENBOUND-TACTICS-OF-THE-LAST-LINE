extends Control

## Draws and drives one `FieldScene` on top of a host screen (2026-09-30, phase 3):
## speech bubbles with a name tab and portrait chip, emotes, banners and letterbox
## bars, a tap-to-advance surface and a skip button. The host supplies a
## `FieldStage`; this overlay never reads or writes game state.

signal finished(skipped: bool)

const FieldSceneScript := preload("res://field/field_scene.gd")
const OrnamentDraw := preload("res://ui/ornament_draw.gd")
const MAX_FRAME_DELTA := 0.1

const SIDE_LOOK := {
	"ally": {"fill": Color(0.030, 0.105, 0.125, 0.95), "edge": Color(0.38, 0.94, 0.86), "tab": Color(0.05, 0.30, 0.33), "ink": Color(0.93, 1.0, 0.98)},
	"foe": {"fill": Color(0.135, 0.030, 0.045, 0.96), "edge": Color(1.0, 0.42, 0.38), "tab": Color(0.42, 0.07, 0.10), "ink": Color(1.0, 0.94, 0.92)},
	"event": {"fill": Color(0.125, 0.095, 0.035, 0.96), "edge": Color(0.91, 0.77, 0.46), "tab": Color(0.36, 0.26, 0.07), "ink": Color(1.0, 0.97, 0.88)},
}

var scene: RefCounted
var stage: RefCounted
var text_font: Font
var skip_button: Button
var clock := 0.0
var _styles: Dictionary = {}
var _portraits: Dictionary = {}
var _reported := false
## Rectangles of the bubbles drawn last frame (for layout tests and captures).
var bubble_rects: Array[Rect2] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	skip_button = Button.new()
	skip_button.name = "FieldSceneSkip"
	skip_button.text = "건너뛰기 ▸"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.pressed.connect(_on_skip_pressed)
	add_child(skip_button)
	_layout_skip()
	resized.connect(_layout_skip)


## Begin `steps` on `host_stage`; false when the script is invalid.
func play(steps: Array, host_stage: RefCounted, options := {}) -> bool:
	stage = host_stage
	scene = FieldSceneScript.new()
	scene.finished.connect(_on_scene_finished)
	_reported = false
	var ok: bool = scene.start(steps, host_stage, options)
	queue_redraw()
	return ok


func is_active() -> bool:
	return scene != null and scene.is_running()


func snapshot() -> Dictionary:
	return {} if scene == null else scene.snapshot()


func _on_skip_pressed() -> void:
	if is_active():
		scene.skip()


func _on_scene_finished(was_skipped: bool) -> void:
	if _reported:
		return
	_reported = true
	if skip_button != null:
		skip_button.visible = false
	queue_redraw()
	finished.emit(was_skipped)


func _gui_input(event: InputEvent) -> void:
	var pressed := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if pressed and is_active():
		scene.tap()
		accept_event()


func _input(event: InputEvent) -> void:
	if not is_active() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		scene.tap()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if scene == null or not scene.is_running():
		return
	clock += delta
	scene.advance(minf(delta, MAX_FRAME_DELTA))
	queue_redraw()


func _ui_scale() -> float:
	if size.y > size.x:
		return clampf(size.x / 520.0, 0.7, 4.0)
	return clampf(minf(size.x / 1600.0, size.y / 900.0), 0.55, 2.2)


func _layout_skip() -> void:
	if skip_button == null:
		return
	var s := _ui_scale()
	skip_button.add_theme_font_size_override("font_size", roundi(20.0 * s))
	var button_size := Vector2(150.0, 46.0) * s
	skip_button.size = button_size
	skip_button.position = Vector2(size.x - button_size.x - 18.0 * s, 18.0 * s)


func _font() -> Font:
	return text_font if text_font != null else get_theme_default_font()


func _style_for(side: String) -> StyleBoxFlat:
	if not _styles.has(side):
		var look: Dictionary = SIDE_LOOK.get(side, SIDE_LOOK.ally)
		var box := StyleBoxFlat.new()
		box.bg_color = look.fill
		box.border_color = look.edge
		box.set_border_width_all(2)
		box.set_corner_radius_all(14)
		box.shadow_color = Color(0, 0, 0, 0.45)
		box.shadow_size = 8
		_styles[side] = box
	return _styles[side]


func _draw() -> void:
	if scene == null:
		return
	var s := _ui_scale()
	bubble_rects.clear()
	var box_height := size.y * 0.075 * float(scene.letterbox)
	if box_height > 0.5:
		draw_rect(Rect2(0, 0, size.x, box_height), Color(0.006, 0.014, 0.026, 0.94))
		draw_rect(Rect2(0, size.y - box_height, size.x, box_height), Color(0.006, 0.014, 0.026, 0.94))
	for emote in scene.emotes:
		_draw_emote(emote, s)
	for bubble in scene.bubbles:
		_draw_bubble(bubble, s)
	if not scene.banner.is_empty():
		_draw_banner(scene.banner, s)


func _anchor(actor: String) -> Vector2:
	var point := Vector2.INF
	if stage != null and not actor.is_empty():
		point = stage.actor_anchor(actor)
	if point == Vector2.INF or not is_finite(point.x) or not is_finite(point.y):
		return Vector2(size.x * 0.5, size.y * 0.46)
	return point


func _portrait(asset_id: String) -> Texture2D:
	if asset_id.is_empty() or stage == null:
		return null
	if not _portraits.has(asset_id):
		_portraits[asset_id] = stage.portrait_for(asset_id)
	return _portraits[asset_id]


func _draw_bubble(bubble: Dictionary, s: float) -> void:
	var font := _font()
	var side := str(bubble.side)
	var look: Dictionary = SIDE_LOOK.get(side, SIDE_LOOK.ally)
	var closing := bool(bubble.closing)
	var fade := 1.0 - clampf(float(bubble.close_age) / FieldSceneScript.SAY_CLOSE, 0.0, 1.0) if closing else 1.0
	var pop := smoothstep(0.0, 0.16, float(bubble.age))
	var alpha := fade * pop
	if alpha <= 0.01:
		return
	var text_size := roundi(clampf(25.0 * s, 15.0, 44.0))
	var name_size := roundi(text_size * 0.72)
	var pad := 16.0 * s
	var margin := 14.0 * s
	var portrait_texture := _portrait(str(bubble.portrait))
	var chip := (58.0 * s) if portrait_texture != null else 0.0
	var max_width := minf(size.x - margin * 2.0, (size.x * 0.86) if size.y > size.x else minf(size.x * 0.46, 620.0 * s))
	var text_width := maxf(120.0 * s, max_width - pad * 2.0 - (chip + pad * 0.6 if chip > 0.0 else 0.0))
	var full_text := str(bubble.text)
	var lines := _wrap(font, full_text, text_width, text_size)
	var line_height := font.get_height(text_size)
	var widest := 0.0
	for line in lines:
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x)
	var body_width := minf(text_width, widest + 2.0)
	var body_height := maxf(line_height * float(lines.size()), chip)
	var box_size := Vector2(body_width + pad * 2.0 + (chip + pad * 0.6 if chip > 0.0 else 0.0), body_height + pad * 2.0 + name_size * 0.9)
	var anchor := _anchor(str(bubble.actor))
	var tail := 24.0 * s
	var lift := 58.0 * s * (0.85 + 0.15 * pop)
	var top_limit := size.y * 0.075 * float(scene.letterbox) + margin
	var box := Rect2(Vector2(anchor.x - box_size.x * 0.5, anchor.y - lift - tail - box_size.y), box_size)
	box.position.x = clampf(box.position.x, margin, maxf(margin, size.x - margin - box_size.x))
	box.position.y = clampf(box.position.y, top_limit + name_size * 0.6, maxf(top_limit, size.y - margin - box_size.y - tail))
	bubble_rects.append(box)
	var faded_box := _style_for(side).duplicate() as StyleBoxFlat
	faded_box.bg_color.a *= alpha
	faded_box.border_color.a *= alpha
	faded_box.shadow_color.a *= alpha
	draw_style_box(faded_box, box)
	# Tail from the box to the speaker's head.
	var tail_x := clampf(anchor.x, box.position.x + 26.0 * s, box.end.x - 26.0 * s)
	var tail_top := box.end.y - 1.0
	var tail_tip := Vector2(clampf(anchor.x, tail_x - 20.0 * s, tail_x + 20.0 * s), minf(anchor.y - 10.0 * s, box.end.y + tail))
	var edge_color: Color = look.edge
	edge_color.a *= alpha
	var fill_color: Color = look.fill
	fill_color.a = 0.97 * alpha
	var tail_polygon := PackedVector2Array([Vector2(tail_x - 14.0 * s, tail_top), Vector2(tail_x + 14.0 * s, tail_top), tail_tip])
	draw_colored_polygon(tail_polygon, fill_color)
	draw_line(tail_polygon[0], tail_polygon[2], edge_color, 2.0, true)
	draw_line(tail_polygon[1], tail_polygon[2], edge_color, 2.0, true)
	# Name tab.
	var speaker := str(bubble.name)
	if not speaker.is_empty():
		var tab_width := font.get_string_size(speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x + 22.0 * s
		var tab := Rect2(box.position + Vector2(16.0 * s, -name_size * 0.62), Vector2(tab_width, name_size * 1.25))
		var tab_color: Color = look.tab
		tab_color.a = 0.98 * alpha
		draw_rect(tab, tab_color)
		draw_rect(tab, edge_color, false, 1.5)
		var ink: Color = look.ink
		ink.a = alpha
		draw_string(font, tab.position + Vector2(11.0 * s, name_size * 0.98), speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, ink)
	var text_origin := box.position + Vector2(pad + (chip + pad * 0.6 if chip > 0.0 else 0.0), pad + name_size * 0.9)
	if portrait_texture != null:
		var chip_rect := Rect2(box.position + Vector2(pad, pad + name_size * 0.9), Vector2(chip, chip))
		var texture_size := portrait_texture.get_size()
		var crop := Rect2(0, texture_size.y * 0.02, texture_size.x, minf(texture_size.x, texture_size.y * 0.9))
		draw_texture_rect_region(portrait_texture, chip_rect, crop, Color(1, 1, 1, alpha))
		draw_rect(chip_rect, edge_color, false, 2.0)
	var typed := clampi(int(bubble.typed), 0, full_text.length())
	var shown := full_text.substr(0, typed)
	var ink_text: Color = look.ink
	ink_text.a = alpha
	var remaining := typed
	for index in range(lines.size()):
		if remaining <= 0:
			break
		var line: String = lines[index]
		draw_string(font, text_origin + Vector2(0, text_size * 0.92 + line_height * float(index)), line.substr(0, remaining), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, ink_text)
		remaining -= line.length() + 1
	if typed >= full_text.length() and scene.waiting_for_tap() and not closing:
		var pulse := 0.55 + 0.45 * sin(clock * 6.0)
		var hint := box.end - Vector2(24.0 * s, 20.0 * s)
		var triangle := PackedVector2Array([hint + Vector2(-8, -7) * s, hint + Vector2(8, -7) * s, hint + Vector2(0, 6) * s])
		var hint_color: Color = look.edge
		hint_color.a = pulse * alpha
		draw_colored_polygon(triangle, hint_color)


## Greedy word wrap: Korean lines break at spaces (never inside a word) unless a
## single word is wider than the box, then it breaks between characters.
func _wrap(font: Font, text: String, width: float, font_size: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var current := ""
	for word in text.split(" ", false):
		var candidate := word if current.is_empty() else current + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
			current = candidate
			continue
		if not current.is_empty():
			lines.append(current)
			current = ""
		var rest: String = word
		while font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and rest.length() > 1:
			var cut := rest.length() - 1
			while cut > 1 and font.get_string_size(rest.substr(0, cut), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
				cut -= 1
			lines.append(rest.substr(0, cut))
			rest = rest.substr(cut)
		current = rest
	if not current.is_empty() or lines.is_empty():
		lines.append(current)
	return lines


func _draw_emote(emote: Dictionary, s: float) -> void:
	var age := float(emote.age)
	var life := float(emote.life)
	var pop := 1.0 + 0.25 * sin(clampf(age / 0.20, 0.0, 1.0) * PI) if age < 0.2 else 1.0
	var grow := smoothstep(0.0, 0.14, age)
	var fade := 1.0 - smoothstep(life - 0.28, life, age)
	var alpha := fade * grow
	if alpha <= 0.01:
		return
	var anchor := _anchor(str(emote.actor))
	var radius := 24.0 * s * pop * grow
	var center := anchor + Vector2(30.0 * s, -46.0 * s - age * 10.0 * s)
	var kind := str(emote.kind)
	var colors := {"alert": Color(1.0, 0.86, 0.32), "question": Color(0.45, 0.93, 0.86), "sweat": Color(0.62, 0.86, 1.0), "anger": Color(1.0, 0.36, 0.32), "spark": Color(1.0, 0.95, 0.62)}
	var accent: Color = colors.get(kind, Color.WHITE)
	var back := Color(0.02, 0.05, 0.08, 0.88 * alpha)
	draw_circle(center, radius, back)
	draw_arc(center, radius, 0.0, TAU, 28, Color(accent.r, accent.g, accent.b, alpha), 2.5 * s, true)
	var glyph := Color(accent.r, accent.g, accent.b, alpha)
	var font := _font()
	match kind:
		"alert":
			_glyph_text(font, center + Vector2(0, radius * 0.34), "!", roundi(radius * 1.35), glyph)
		"question":
			_glyph_text(font, center + Vector2(0, radius * 0.34), "?", roundi(radius * 1.35), glyph)
		"sweat":
			var drop := PackedVector2Array([center + Vector2(0, -radius * 0.62), center + Vector2(radius * 0.36, radius * 0.10), center + Vector2(0, radius * 0.58), center + Vector2(-radius * 0.36, radius * 0.10)])
			draw_colored_polygon(drop, glyph)
		"anger":
			for arm in range(4):
				var angle := PI * 0.25 + float(arm) * PI * 0.5
				var inner := center + Vector2(cos(angle), sin(angle)) * radius * 0.22
				var outer := center + Vector2(cos(angle), sin(angle)) * radius * 0.66
				draw_line(inner, outer, glyph, 3.0 * s, true)
		"spark":
			var star := PackedVector2Array()
			for point in range(8):
				var angle := float(point) * PI * 0.25
				var length := radius * (0.72 if point % 2 == 0 else 0.26)
				star.append(center + Vector2(cos(angle), sin(angle)) * length)
			draw_colored_polygon(star, glyph)


func _glyph_text(font: Font, baseline_center: Vector2, text: String, font_size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, baseline_center - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_banner(banner: Dictionary, s: float) -> void:
	var age := float(banner.age)
	var life := float(banner.life)
	var open := smoothstep(0.0, 0.26, age)
	var fade := 1.0 - smoothstep(life, life + 0.3, age) if not scene.waiting_for_tap() else 1.0
	if fade <= 0.01:
		return
	var style := str(banner.style)
	var accent := OrnamentDraw.LUMEN
	var fill := OrnamentDraw.INK
	var ink := Color(1.0, 0.95, 0.80)
	match style:
		"boss":
			accent = OrnamentDraw.ALERT
			fill = OrnamentDraw.ALERT_DEEP
		"event":
			accent = OrnamentDraw.GOLD
			ink = Color(1.0, 0.97, 0.86)
	var portrait_layout := size.y > size.x
	var center_y := size.y * (0.80 if style == "event" else 0.36)
	var band_height := (150.0 if portrait_layout else 118.0) * s
	var band_width := size.x * open
	var band := Rect2(Vector2((size.x - band_width) * 0.5, center_y - band_height * 0.5), Vector2(band_width, band_height))
	OrnamentDraw.band(self, band, fade, s * 0.9, accent, fposmod(age * 0.9, 1.0), fill, size.x * 0.16)
	var text_size := roundi(clampf(34.0 * s, 18.0, 64.0))
	var text := str(banner.text)
	var font := _font()
	var fitted := text_size
	while fitted > 14 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > size.x * 0.84:
		fitted -= 2
	OrnamentDraw.centered_text(self, font, Vector2(size.x * 0.5, center_y + fitted * 0.32), text, fitted, Color(ink.r, ink.g, ink.b, fade), roundi(5.0 * s), Color(0.06, 0.04, 0.02, fade))
	if scene.waiting_for_tap():
		var pulse := 0.55 + 0.45 * sin(clock * 6.0)
		OrnamentDraw.centered_text(self, font, Vector2(size.x * 0.5, band.end.y - 12.0 * s), "탭하여 계속", roundi(16.0 * s), Color(accent.r, accent.g, accent.b, pulse * fade))
