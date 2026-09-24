extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not ProjectSettings.load_resource_pack(args[0]):
		push_error("PCK_INSPECTION_INPUT_INVALID")
		quit(1)
		return
	var rows: Array[Dictionary] = []
	_walk("res://", rows)
	rows.sort_custom(func(a, b): return int(a.bytes) > int(b.bytes))
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	output.store_string(JSON.stringify({"pack":args[0], "entries":rows}, "\t"))
	output.close()
	for row in rows.slice(0, 22): print(JSON.stringify(row))
	quit()

func _walk(path: String, rows: Array[Dictionary]) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	directory.include_hidden = true
	for filename in directory.get_files():
		var full := path.path_join(filename)
		var file := FileAccess.open(full, FileAccess.READ)
		if file != null:
			rows.append({"path":full,"bytes":file.get_length()})
	for name in directory.get_directories():
		if name not in [".",".."]: _walk(path.path_join(name), rows)
