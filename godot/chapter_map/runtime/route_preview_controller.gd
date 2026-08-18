class_name RoutePreviewController
extends RefCounted

var path: Array[Vector2i] = []

func calculate(grid, start: Vector2i, goal: Vector2i, revealed: Dictionary) -> Array[Vector2i]:
	path = preload("res://chapter_map/model/hex_pathfinder.gd").find_path(grid, start, goal, revealed)
	return path

func clear() -> void:
	path.clear()
