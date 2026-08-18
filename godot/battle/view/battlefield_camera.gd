class_name BattlefieldCamera
extends Camera2D

func focus_boss(position_value: Vector2) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", position_value, .2)
	tween.tween_property(self, "position", Vector2.ZERO, .35)

