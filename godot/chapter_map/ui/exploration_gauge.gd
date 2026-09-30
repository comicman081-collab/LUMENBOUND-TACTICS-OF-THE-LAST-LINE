extends Control

## "탐사율" widget (A5): one ring gauge with the chapter's exploration percent.
## The value comes from MapExplorationService.completion(); display only.

var percent := 0
var ui_scale := 1.0
var shown := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_percent(value: int) -> void:
	percent = clampi(value, 0, 100)
	set_process(true)

func _process(delta: float) -> void:
	shown = move_toward(shown, float(percent), delta * 60.0)
	queue_redraw()
	if is_equal_approx(shown, float(percent)): set_process(false)

func _draw() -> void:
	var s := ui_scale
	var rect := Rect2(Vector2.ZERO, size)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("07111bdd")
	style.border_color = Color("e8c47699")
	style.set_border_width_all(maxi(1, roundi(1.0 * s)))
	style.set_corner_radius_all(roundi(size.y * .5))
	draw_style_box(style, rect)
	var ring_center := Vector2(size.y * .5 + 2.0 * s, size.y * .5)
	var ring_radius := size.y * .32
	draw_arc(ring_center, ring_radius, 0.0, TAU, 40, Color("22323f"), 5.0 * s, true)
	var sweep := TAU * shown / 100.0
	if sweep > .01:
		draw_arc(ring_center, ring_radius, -PI * .5, -PI * .5 + sweep, 40, Color("f2cf7a"), 5.0 * s, true)
	var font := get_theme_default_font()
	var label_size := roundi(13.0 * s)
	var value_size := roundi(22.0 * s)
	var text_x := ring_center.x + ring_radius + 10.0 * s
	draw_string(font, Vector2(text_x, size.y * .5 - 3.0 * s), "탐사율", HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color("a9c3c9"))
	draw_string(font, Vector2(text_x, size.y * .5 + value_size * .78), "%d%%" % roundi(shown), HORIZONTAL_ALIGNMENT_LEFT, -1, value_size, Color("fff1c4"))
