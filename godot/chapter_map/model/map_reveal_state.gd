class_name MapRevealState
extends RefCounted

var revealed: Dictionary = {}

func set_from_keys(keys: Array) -> void:
	revealed.clear()
	for key in keys: revealed[str(key)] = true

func contains(coord: Vector2i) -> bool:
	return revealed.has("%d,%d" % [coord.x, coord.y])
