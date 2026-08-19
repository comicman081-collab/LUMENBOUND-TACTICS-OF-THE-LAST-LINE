extends Node

var tables: Dictionary = {"ko": {}, "en": {}}
var language := "ko"

func _ready() -> void:
	load_compiled_table()

func load_compiled_table() -> void:
	var path := "res://data/compiled/localization.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Compiled localization table is missing: %s" % path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Compiled localization table is invalid: %s" % path)
		return
	for locale in ["ko", "en"]:
		var locale_table: Variant = parsed.get(locale, {})
		if locale_table is Dictionary:
			tables[locale] = locale_table

func tr_key(key: String) -> String:
	language = SettingsService.values.get("language", "ko")
	# Source data can retain a DEV suffix while naming is curated. It must never
	# leak into the player-facing Web Release UI.
	return str(tables.get(language, {}).get(key, "[%s]" % key)).replace(" (DEV)", "")
