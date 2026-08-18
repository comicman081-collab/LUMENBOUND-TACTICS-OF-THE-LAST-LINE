class_name ProjectileView
extends Node2D

var active := false
func launch(from: Vector2, to: Vector2) -> void:
	position = from
	active = true
	var tween := create_tween()
	tween.tween_property(self, "position", to, .25)
	tween.finished.connect(func(): active = false; visible = false)

