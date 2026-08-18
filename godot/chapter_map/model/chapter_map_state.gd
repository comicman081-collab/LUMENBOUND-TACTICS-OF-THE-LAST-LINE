class_name ChapterMapState
extends RefCounted

var current_coord := Vector2i.ZERO
var selected_node_id := ""
var preview_path: Array[Vector2i] = []
var moving := false

func reset_selection() -> void:
	selected_node_id = ""
	preview_path.clear()
