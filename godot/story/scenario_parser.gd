class_name ScenarioParser
extends RefCounted

const SUPPORTED := ["set_background", "set_cg", "show_portrait", "hide_portrait", "set_expression", "dialogue", "narration", "choice", "set_flag", "check_flag", "jump", "play_bgm", "stop_bgm", "play_sfx", "play_voice", "fade_in", "fade_out", "wait", "start_battle", "grant_reward", "end_scenario"]

static func validate(scenario: Dictionary) -> Array:
	var errors: Array = []
	var labels: Dictionary = {}
	for command in scenario.get("commands", []):
		if command.has("id"): labels[command.id] = true
	for index in range(scenario.get("commands", []).size()):
		var command: Dictionary = scenario.commands[index]
		if not str(command.get("command", "")) in SUPPORTED:
			errors.append("%s[%d] unsupported command" % [scenario.get("id", "?"), index])
		if command.command in ["jump", "check_flag"] and command.has("target") and not labels.has(command.target):
			errors.append("%s[%d] invalid jump target %s" % [scenario.get("id", "?"), index, command.target])
	return errors

