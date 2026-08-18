class_name ChapterMapSaveAdapter
extends RefCounted

static func snapshot(map_id := "CH01_MAP") -> Dictionary:
	return AppState.chapter_map_state(map_id).duplicate(true)

static func save_position(coord: Vector2i, node_id := "", map_id := "CH01_MAP") -> GameResult:
	AppState.set_chapter_map_position(coord, node_id, map_id)
	return SaveService.save_game()
