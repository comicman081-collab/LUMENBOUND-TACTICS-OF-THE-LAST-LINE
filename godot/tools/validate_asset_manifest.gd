extends SceneTree


func _init() -> void:
	var path := "res://assets/generated_import/import_manifest.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("asset manifest missing")
		quit(2)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.has("assets"):
		printerr("asset manifest invalid")
		quit(3)
		return
	var failures := 0
	for asset in parsed.assets:
		if not asset.has("asset_id") or not asset.has("sha256") or not asset.has("godot_path"):
			failures += 1
		elif not FileAccess.file_exists(asset.godot_path):
			failures += 1
	print("asset manifest entries=%d failures=%d" % [parsed.assets.size(), failures])
	quit(0 if failures == 0 else 4)
