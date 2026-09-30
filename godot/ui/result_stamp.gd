extends Control

## Result stamp ("완수" / "승인") that slams onto the result header. Drawn
## procedurally; it reads the committed result only through the text it is
## given and never grants or records anything.

const Ornament := preload("res://ui/ornament_draw.gd")
const DISPLAY_FONT := preload("res://assets/fonts/LanternRounded-Black.ttf")

var text := "완수"
var caption := "OPERATION"
var ink := Color("d8453c")
## Colour of the card behind the stamp, used for the worn-ink specks.
var paper := Color("0b1a28")
var delay := .35
var elapsed := 0.0
var text_font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()
	if elapsed > delay + .8:
		set_process(false)

func landed() -> bool:
	return elapsed >= delay + .16

func _font() -> Font:
	if text_font != null:
		return text_font
	var base := get_theme_default_font()
	if base == null:
		base = ThemeDB.fallback_font
	var heavy := FontVariation.new()
	heavy.base_font = base
	heavy.variation_embolden = .9
	text_font = heavy
	return text_font

func _draw() -> void:
	var t := elapsed - delay
	if t < 0.0:
		return
	var slam := clampf(t / .16, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - slam, 3.0)
	var stamp_scale := lerpf(2.3, 1.0, eased)
	var alpha := slam
	var center := size * .5
	var radius := minf(size.x, size.y) * .42
	if radius < 8.0:
		return
	var color := Color(ink.r, ink.g, ink.b, ink.a * alpha * .92)
	if t < .40:
		var ring := t / .40
		draw_arc(center, radius * (1.0 + ring * .7), 0.0, TAU, 48, Color(ink.r, ink.g, ink.b, (1.0 - ring) * .45), radius * .05, true)
	draw_set_transform(center, deg_to_rad(-12.0), Vector2.ONE * stamp_scale)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 56, color, radius * .085, true)
	draw_arc(Vector2.ZERO, radius * .80, 0.0, TAU, 56, color, radius * .035, true)
	for index in range(8):
		var angle := TAU * float(index) / 8.0 + PI / 8.0
		Ornament.diamond(self, Vector2(cos(angle), sin(angle)) * radius * .90, radius * .035, color)
	var font := _font()
	Ornament.centered_text(self, font, Vector2(0, radius * .06), text, roundi(radius * .60), color)
	Ornament.centered_text(self, DISPLAY_FONT, Vector2(0, -radius * .52), caption, roundi(radius * .15), color)
	draw_line(Vector2(-radius * .46, radius * .42), Vector2(radius * .46, radius * .42), color, radius * .03, true)
	# Worn ink: a few paper-coloured specks break the print like a real stamp.
	for index in range(11):
		var h := float((index * 7919 + 17) % 997) / 997.0
		var h2 := float((index * 3571 + 101) % 991) / 991.0
		var speck := Vector2(cos(h * TAU), sin(h * TAU)) * radius * (.25 + .75 * h2)
		draw_circle(speck, radius * (.018 + .03 * h2), Color(paper.r, paper.g, paper.b, alpha * .85))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
