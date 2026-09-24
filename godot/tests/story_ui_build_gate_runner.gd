extends Node

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	var shell := preload("res://screens/app_shell.gd").new()
	var original := bool(SettingsService.values.developer_mode)
	for developer in [false, true]:
		SettingsService.values.developer_mode = developer
		for portrait in [false, true]:
			var controls := shell._build_story_secondary_controls(portrait)
			var labels: Array[String] = []
			for child in controls.get_children(): labels.append(child.text)
			check(labels.has("다음") and labels.has("로그"), "player reading controls stay available")
			check(labels.has("UI 숨기기") == developer, "UI hide follows developer authority")
			check(labels.has("DEV 전체 스킵") == developer, "developer skip follows developer authority")
			check(controls.get_child_count() == (4 if developer else 2), "player layout contains no empty developer row")
			check(str(shell.story_header_data("SCN_CH01_MID_B").subtitle).is_empty() != developer, "raw scenario ID follows developer authority")
			controls.free()
	SettingsService.values.developer_mode = false
	shell._toggle_story_ui()
	check(not shell.story_ui_hidden, "direct UI-hide invocation is rejected without developer authority")
	shell._dev_skip_story()
	check(not shell.story_navigation_pending, "direct developer skip cannot navigate in player mode")
	check(not SettingsService.developer_mode_for_capabilities(false, false), "release build cannot acquire developer authority")
	var config := ConfigFile.new()
	check(config.load("res://export_presets.cfg") == OK, "export configuration loads")
	check(str(config.get_value("preset.1", "name", "")) == "Web HTML Release" and str(config.get_value("preset.1", "custom_features", "")).is_empty(), "public export has no developer feature")
	SettingsService.values.developer_mode = original
	shell.free()
	print("STORY_UI_BUILD_GATE total=%d pass=%d fail=%d" % [checks, checks-failures, failures])
	get_tree().quit(0 if failures == 0 else 1)
