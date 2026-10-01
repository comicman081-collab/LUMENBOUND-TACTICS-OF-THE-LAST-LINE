extends Control

## Map encounter transition (B4): speed lines close in while the map camera
## pushes toward the contact, a slanted speed-line wipe crosses the screen, and
## an enemy info panel (wave composition, recommended level) slides in from the
## side before the battle loads. Tap to skip. Presentation only.

signal finished

const OrnamentDraw := preload("res://ui/ornament_draw.gd")
const WIPE_START := .22
const WIPE_END := .58
const PANEL_IN := .40

var heading := "적군 조우"
var title := ""
var level_line := ""
var wave_lines: Array = []
var accent := OrnamentDraw.LUMEN
var duration := 1.3
var elapsed := 0.0
var text_font: Font
var done := false

func configure(data: Dictionary, total := 1.3) -> void:
	heading = str(data.get("heading", heading))
	title = str(data.get("title", ""))
	level_line = str(data.get("level_line", ""))
	wave_lines = data.get("waves", [])
	accent = data.get("accent", OrnamentDraw.LUMEN)
	duration = maxf(.3, total)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	var tap := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if tap and elapsed > PANEL_IN + .1:
		elapsed = duration
		accept_event()

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()
	if elapsed >= duration and not done:
		done = true
		finished.emit()

func snapshot() -> Dictionary:
	return {"elapsed": elapsed, "duration": duration, "title": title, "waves": wave_lines.size(), "done": done}

func _font() -> Font:
	return text_font if text_font != null else get_theme_default_font()

func _draw() -> void:
	var view := size
	var scale := clampf(minf(view.x / 1600.0, view.y / 900.0) * 1.0, .55, 2.2)
	if view.y > view.x: scale = clampf(view.x / 520.0, .7, 4.0)
	var t := elapsed
	var center := view * .5
	# 1. Closing speed lines and a darkening veil.
	var close := smoothstep(0.0, .45, t)
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.02, 0.04, 0.07, .10 + .35 * close))
	var line_color := Color(accent.r, accent.g, accent.b, .55 * (1.0 - smoothstep(.55, .85, t)))
	for index in range(36):
		var angle := TAU * float(index) / 36.0 + float(index % 3) * .05
		var outer := center + Vector2(cos(angle), sin(angle)) * view.length() * .62
		var inner_reach := lerpf(.60, .30, close) + .06 * sin(float(index) * 2.3 + t * 9.0)
		var inner := center + Vector2(cos(angle), sin(angle)) * view.length() * inner_reach
		draw_line(outer, inner, line_color, (2.0 + float(index % 4)) * scale, true)
	# 2. Slanted wipe band that crosses right to left and leaves the screen dark.
	var wipe := smoothstep(WIPE_START, WIPE_END, t)
	if wipe > 0.0:
		var slant := view.y * .35
		var lead := lerpf(view.x + slant, -slant, wipe)
		var cover := PackedVector2Array([Vector2(lead, 0), Vector2(view.x + slant, 0), Vector2(view.x + slant, view.y), Vector2(lead - slant, view.y)])
		draw_colored_polygon(cover, Color(0.024, 0.047, 0.082, .94))
		for streak in range(14):
			var y := view.y * (float(streak) + .5) / 14.0
			var x := lead - slant * (y / view.y) + float((streak * 37) % 90) * scale
			var length := (120.0 + float((streak * 53) % 160)) * scale
			draw_line(Vector2(x, y), Vector2(x + length, y), Color(accent.r, accent.g, accent.b, .45), 2.0 * scale, true)
		var edge := PackedVector2Array([Vector2(lead, 0), Vector2(lead + 10.0 * scale, 0), Vector2(lead - slant + 10.0 * scale, view.y), Vector2(lead - slant, view.y)])
		draw_colored_polygon(edge, Color(accent.r, accent.g, accent.b, .9))
	# 3. Enemy info panel slides in from the right.
	var slide := smoothstep(PANEL_IN, PANEL_IN + .22, t)
	if slide <= 0.0: return
	var ease := 1.0 - pow(1.0 - slide, 3.0)
	var panel_width := minf(view.x * .86, 620.0 * scale)
	var panel_height := (178.0 + 34.0 * float(wave_lines.size())) * scale
	var panel_x := lerpf(view.x + 20.0, view.x * .5 - panel_width * .5, ease)
	var panel := Rect2(Vector2(panel_x, center.y - panel_height * .5), Vector2(panel_width, panel_height))
	OrnamentDraw.frame(self, panel, ease, scale, accent)
	var font := _font()
	var x := panel.position.x + 30.0 * scale
	var y := panel.position.y + 46.0 * scale
	draw_string(font, Vector2(x, y), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(20.0 * scale), OrnamentDraw.tint(OrnamentDraw.GOLD, ease))
	y += 48.0 * scale
	draw_string(font, Vector2(x, y), title, HORIZONTAL_ALIGNMENT_LEFT, panel_width - 60.0 * scale, roundi(36.0 * scale), Color(1, 1, 1, ease))
	y += 38.0 * scale
	if not level_line.is_empty():
		draw_string(font, Vector2(x, y), level_line, HORIZONTAL_ALIGNMENT_LEFT, panel_width - 60.0 * scale, roundi(19.0 * scale), Color(.78, .88, .92, ease))
		y += 16.0 * scale
	for line in wave_lines:
		y += 34.0 * scale
		OrnamentDraw.diamond(self, Vector2(x + 6.0 * scale, y - 7.0 * scale), 5.0 * scale, OrnamentDraw.tint(accent, ease))
		draw_string(font, Vector2(x + 22.0 * scale, y), str(line), HORIZONTAL_ALIGNMENT_LEFT, panel_width - 80.0 * scale, roundi(20.0 * scale), Color(.93, .95, .97, ease))
