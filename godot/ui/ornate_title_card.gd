extends Control

## Procedural title card: chapter opening, map EVENT contact and the boss
## encounter band. Original ornament (metal rail, gold filigree, teal lumen)
## drawn with CanvasItem primitives. It only shows the strings it is given and
## owns no game state; closing it never changes a story, map or battle result.

signal finished

const Ornament := preload("res://ui/ornament_draw.gd")
const DISPLAY_FONT := preload("res://assets/fonts/LanternRounded-Black.ttf")

var kind := "CHAPTER" # CHAPTER | EVENT | BOSS
var eyebrow := ""
var title_text := ""
var subtitle := ""
var number_text := ""
var duration := 2.6
## Taps are ignored for this long so the tap that opened a screen cannot also
## dismiss its card.
var skip_after := .35
## A card inside a longer transition (the map boss band) is freed by its owner.
var auto_close := true
var text_font: Font
var elapsed := 0.0
var closing := false

func configure(kind_value: String, eyebrow_value: String, title_value: String, subtitle_value := "", duration_value := 2.6, number_value := "") -> Control:
	kind = kind_value
	eyebrow = eyebrow_value
	title_text = title_value
	subtitle = subtitle_value
	duration = maxf(.3, duration_value)
	number_text = number_value
	return self

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP if auto_close else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE

func _process(delta: float) -> void:
	if closing:
		return
	elapsed += delta
	queue_redraw()
	if auto_close and elapsed >= duration:
		_finish()

func _gui_input(event: InputEvent) -> void:
	var pressed := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if pressed and elapsed >= skip_after:
		accept_event()
		skip()

## Jumps to the closing fade; the card still emits `finished` exactly once.
func skip() -> void:
	if closing or not auto_close:
		return
	elapsed = maxf(elapsed, duration - .20)

func is_open() -> bool:
	return not closing and is_inside_tree()

func _finish() -> void:
	if closing:
		return
	closing = true
	finished.emit()
	queue_free()

func _unit() -> float:
	# Sizes are authored as rendered CSS pixels and converted back to this
	# canvas, so a 390px phone and a 1920px desktop read the same hierarchy.
	if not is_inside_tree():
		return 1.0
	var transform := get_viewport().get_screen_transform() * get_global_transform_with_canvas()
	return clampf(1.0 / maxf(.01, transform.y.length()), .5, 6.0)

func _font() -> Font:
	if text_font != null:
		return text_font
	var font := get_theme_default_font()
	return font if font != null else ThemeDB.fallback_font

func _fit(font: Font, text: String, font_size: float, max_width: float) -> int:
	var wanted := maxi(8, roundi(font_size))
	if font == null or text.is_empty():
		return wanted
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, wanted).x
	if width <= max_width or width <= 0.0:
		return wanted
	return maxi(8, int(floor(float(wanted) * max_width / width)))

func _draw() -> void:
	var open := smoothstep(0.0, .30, elapsed)
	var fade := 1.0 - smoothstep(duration - .20, duration, elapsed) if auto_close else 1.0
	match kind:
		"BOSS":
			_draw_boss(fade)
		"EVENT":
			_draw_event(open, fade)
		_:
			_draw_chapter(open, fade)

func _draw_chapter(open: float, fade: float) -> void:
	var s := _unit()
	var font := _font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(.008, .018, .035, .90 * minf(1.0, elapsed / .18) * fade))
	Ornament.speed_lines(self, Rect2(Vector2(0, size.y * .30), Vector2(size.x, size.y * .40)), elapsed * .35, Ornament.tint(Ornament.LUMEN, .10 * fade), 18, 11, .5)
	var frame_size := Vector2(minf(size.x * .88, 920.0 * s), minf(size.y * .58, 340.0 * s))
	var grow := .94 + .06 * open
	var rect := Rect2(size * .5 - frame_size * .5 * grow, frame_size * grow)
	Ornament.frame(self, rect, open * fade, s, Ornament.LUMEN, Ornament.INK, .80)
	var text_alpha := smoothstep(.16, .44, elapsed) * fade
	var center_x := size.x * .5
	var top := rect.position.y
	var height := rect.size.y
	Ornament.centered_text(self, DISPLAY_FONT, Vector2(center_x, top + height * .19), eyebrow, _fit(DISPLAY_FONT, eyebrow, 20.0 * s, rect.size.x * .7), Ornament.tint(Ornament.GOLD, text_alpha), roundi(3.0 * s), Color(0, 0, 0, .6 * text_alpha))
	Ornament.centered_text(self, font, Vector2(center_x, top + height * .34), number_text, _fit(font, number_text, 26.0 * s, rect.size.x * .7), Color(.72, .94, 1.0, text_alpha), roundi(3.0 * s), Color(0, 0, 0, .6 * text_alpha))
	var punch := 1.0 + .12 * (1.0 - smoothstep(.30, .60, elapsed))
	Ornament.centered_text(self, font, Vector2(center_x, top + height * .56), title_text, _fit(font, title_text, 54.0 * s * punch, rect.size.x * .86), Color(1.0, .96, .86, text_alpha), roundi(6.0 * s), Color(.10, .05, 0, text_alpha))
	var line_y := top + height * .73
	var half := rect.size.x * .30 * smoothstep(.30, .70, elapsed)
	if half > 2.0:
		Ornament.rail(self, Vector2(center_x - half, line_y), Vector2(center_x + half, line_y), text_alpha, s * .8, Ornament.LUMEN, fposmod(elapsed * .6, 1.0))
	Ornament.stud(self, Vector2(center_x, line_y), 5.0 * s, text_alpha)
	var sub_alpha := smoothstep(.45, .75, elapsed) * fade
	Ornament.centered_text(self, font, Vector2(center_x, top + height * .86), subtitle, _fit(font, subtitle, 21.0 * s, rect.size.x * .84), Color(.80, .90, .98, sub_alpha), roundi(2.0 * s), Color(0, 0, 0, .5 * sub_alpha))

func _draw_event(open: float, fade: float) -> void:
	var s := _unit()
	var font := _font()
	var center_y := size.y * .42
	var band_height := minf(size.y * .30, 196.0 * s)
	var width := size.x * open
	var band := Rect2(Vector2((size.x - width) * .5, center_y - band_height * .5), Vector2(width, band_height))
	Ornament.band(self, band, fade, s, Ornament.LUMEN, fposmod(elapsed * .9, 1.0), Ornament.INK, size.x * .12)
	Ornament.speed_lines(self, band.grow_individual(0, -band_height * .22, 0, -band_height * .22), elapsed, Ornament.tint(Ornament.LUMEN, .24 * fade), 12, 5, .8)
	var text_alpha := smoothstep(.10, .30, elapsed) * fade
	var punch := 1.0 + .30 * (1.0 - smoothstep(.10, .38, elapsed))
	Ornament.centered_text(self, DISPLAY_FONT, Vector2(size.x * .5, center_y - band_height * .12), "EVENT", _fit(DISPLAY_FONT, "EVENT", 72.0 * s * punch, size.x * .7), Color(1.0, .90, .55, text_alpha), roundi(7.0 * s), Color(.18, .10, 0, text_alpha))
	Ornament.centered_text(self, font, Vector2(size.x * .5, center_y + band_height * .30), title_text, _fit(font, title_text, 26.0 * s, size.x * .84), Color(.90, .97, 1.0, text_alpha), roundi(3.0 * s), Color(0, 0, 0, .7 * text_alpha))

func _draw_boss(fade: float) -> void:
	var s := _unit()
	var font := _font()
	var center_y := size.y * .5
	var height := minf(size.y * .36, 240.0 * s)
	var reveal_width := size.x * smoothstep(0.0, .18, elapsed)
	var reveal := Rect2(Vector2(size.x - reveal_width, center_y - height * .5), Vector2(reveal_width, height))
	var deep := Color(.42, .02, .05, .92 * fade)
	var dark := Color(.10, 0, .02, .92 * fade)
	Ornament.quad(self, reveal.position, reveal.position + Vector2(reveal.size.x, 0), reveal.end, reveal.position + Vector2(0, reveal.size.y), deep, deep, dark, dark)
	var strip := height * .08
	Ornament.hazard_stripes(self, Rect2(reveal.position, Vector2(reveal.size.x, strip)), elapsed, Color(1.0, .78, .25, .50 * fade), strip * 1.3)
	Ornament.hazard_stripes(self, Rect2(Vector2(reveal.position.x, reveal.end.y - strip), Vector2(reveal.size.x, strip)), -elapsed, Color(1.0, .78, .25, .50 * fade), strip * 1.3)
	var accent := Color("ff9a7a")
	Ornament.rail(self, reveal.position, Vector2(reveal.end.x, reveal.position.y), fade, s * .8, accent, fposmod(elapsed * .9, 1.0))
	Ornament.rail(self, reveal.end, Vector2(reveal.position.x, reveal.end.y), fade, s * .8, accent, fposmod(elapsed * .9, 1.0))
	var text_alpha := smoothstep(.10, .26, elapsed) * fade
	var shake := Vector2(sin(elapsed * 80.0), cos(elapsed * 67.0)) * 3.0 * s * (1.0 - smoothstep(.12, .45, elapsed))
	Ornament.centered_text(self, font, Vector2(size.x * .5, center_y - height * .30), eyebrow, _fit(font, eyebrow, 16.0 * s, size.x * .8), Color(1.0, .82, .56, text_alpha), roundi(2.0 * s), Color(.15, 0, 0, text_alpha))
	Ornament.centered_text(self, DISPLAY_FONT, Vector2(size.x * .5, center_y - height * .07) + shake, "BOSS ENCOUNTER", _fit(DISPLAY_FONT, "BOSS ENCOUNTER", 60.0 * s, size.x * .88), Color(1.0, .93, .86, text_alpha), roundi(5.0 * s), Color(.25, 0, .02, text_alpha))
	Ornament.centered_text(self, font, Vector2(size.x * .5, center_y + height * .20), title_text, _fit(font, title_text, 30.0 * s, size.x * .84), Color(1.0, .88, .62, text_alpha), roundi(3.0 * s), Color(.15, 0, 0, text_alpha))
	Ornament.centered_text(self, font, Vector2(size.x * .5, center_y + height * .36), subtitle, _fit(font, subtitle, 15.0 * s, size.x * .84), Color(.86, .90, .96, text_alpha), roundi(2.0 * s), Color(0, 0, 0, .6 * text_alpha))
