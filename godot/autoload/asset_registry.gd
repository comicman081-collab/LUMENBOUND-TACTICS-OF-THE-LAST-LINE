extends Node

const PREMIUM_MANIFEST_PATH := "res://assets/art/asset_manifest.json"
const LEGACY_MANIFEST_PATH := "res://assets/generated_import/import_manifest.json"
var assets: Dictionary = {}

func _ready() -> void:
	_load_manifest(LEGACY_MANIFEST_PATH)
	# Premium entries intentionally load last so stable asset IDs can supersede
	# legacy placeholders without retaining duplicate runtime paths.
	_load_manifest(PREMIUM_MANIFEST_PATH)

func _load_manifest(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			for entry in parsed.get("assets", []):
				var key: String = entry.get("asset_id", "")
				if key != "":
					assets[key] = entry

func resolve(asset_id: String) -> String:
	if assets.has(asset_id):
		return assets[asset_id].get("godot_path", "")
	# Every data ID remains resolvable while final art is absent. The fallback is
	# deliberately labelled and never reported as production art.
	return "res://assets/placeholders/code_native/dev_placeholder.svg" if asset_id != "" else ""

func is_placeholder(asset_id: String) -> bool:
	return not assets.has(asset_id) or assets[asset_id].get("status", "DEV_PLACEHOLDER") == "DEV_PLACEHOLDER"

func status_of(asset_id: String) -> String:
	if not assets.has(asset_id):
		return "DEV_PLACEHOLDER"
	return assets[asset_id].get("status", "DEV_PLACEHOLDER")
