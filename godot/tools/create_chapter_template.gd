extends SceneTree

func _init() -> void:
	var chapter_number := 2
	var template := {"id": "CH%02d" % chapter_number, "number": chapter_number, "name_key": "CHAPTER_%02d" % chapter_number, "normal_stage_ids": [], "hard_stage_ids": []}
	for i in range(1, 11): template.normal_stage_ids.append("CH%02d-N%02d" % [chapter_number, i])
	for i in range(1, 6): template.hard_stage_ids.append("CH%02d-H%02d" % [chapter_number, i])
	var output := FileAccess.open("user://chapter_template.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(template, "  "))
	print("wrote user://chapter_template.json")
	quit(0)

