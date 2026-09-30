extends Control

## Ornate frame drawn around its parent's rect (portrait frames, cards).
## Fill-less; it sits above the framed content and ignores input.

const Ornament := preload("res://ui/ornament_draw.gd")

var accent := Ornament.LUMEN
var outset := 6.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	var scale := clampf(size.y / 160.0, .6, 2.4)
	Ornament.frame(self, Rect2(Vector2.ZERO, size).grow(outset * scale), 1.0, scale * .8, accent, Ornament.INK, 0.0)
