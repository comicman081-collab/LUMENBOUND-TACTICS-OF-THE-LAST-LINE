extends Node

const DATA_PATH := "res://data/compiled/game_data.json"
var data: Dictionary = {}
var load_error := ""

func _ready() -> void:
	load_all()

func load_all() -> bool:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		load_error = "compiled data missing: %s" % DATA_PATH
		push_error(load_error)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		load_error = "compiled data is not a dictionary"
		push_error(load_error)
		return false
	data = parsed
	load_error = ""
	return true

func list_of(key: String) -> Array:
	return data.get(key, [])

func by_id(collection: String, id: String) -> Dictionary:
	for entry in list_of(collection):
		if entry.get("id", "") == id:
			return entry
	return {}

func stage(stage_id: String) -> Dictionary:
	return by_id("stages", stage_id)

func character(character_id: String) -> Dictionary:
	return by_id("characters", character_id)

func skill(skill_id: String) -> Dictionary:
	return by_id("skills", skill_id)

func enemy(enemy_id: String) -> Dictionary:
	return by_id("enemies", enemy_id)

func chapter(chapter_id: String) -> Dictionary:
	return by_id("chapters", chapter_id)

func chapter_for_stage(stage_id: String) -> Dictionary:
	var definition := stage(stage_id)
	return chapter(str(definition.get("chapter_id", "")))
