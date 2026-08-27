class_name ScenarioRunner
extends RefCounted

var scenario: Dictionary = {}
var state := ScenarioState.new()
var labels: Dictionary = {}

func load_scenario(scenario_id: String, resume := true) -> GameResult:
	scenario = DataRegistry.by_id("scenarios", scenario_id)
	if scenario.is_empty(): return GameResult.failure("SCENARIO_NOT_FOUND")
	var errors := ScenarioParser.validate(scenario)
	if not errors.is_empty(): return GameResult.failure("; ".join(errors))
	state = ScenarioState.new()
	state.scenario_id = scenario_id
	labels.clear()
	for i in range(scenario.commands.size()):
		if scenario.commands[i].has("id"): labels[scenario.commands[i].id] = i
	if resume:
		var saved: Dictionary = AppState.profile.last_scenario_position.get(scenario_id, {})
		if not saved.is_empty():
			state.command_index = int(saved.get("command_index", 0))
			state.background_asset_id = str(saved.get("background_asset_id", ""))
			state.cg_asset_id = str(saved.get("cg_asset_id", ""))
			state.portraits = saved.get("portraits", {}).duplicate(true)
			state.current_line = saved.get("current_line", {}).duplicate(true)
			state.waiting_for_choice = bool(saved.get("waiting_for_choice", false))
	return GameResult.success()

func advance() -> Dictionary:
	if state.waiting_for_choice or state.finished: return state.current_line
	while state.command_index < scenario.get("commands", []).size():
		var command: Dictionary = scenario.commands[state.command_index]
		var current_index := state.command_index
		state.command_index += 1
		var type := str(command.command)
		if type == "set_background": state.background_asset_id = command.get("asset_id", "")
		elif type == "set_cg": state.cg_asset_id = command.get("asset_id", "")
		elif type == "show_portrait": state.portraits[command.get("slot", "CENTER")] = command.duplicate(true)
		elif type == "hide_portrait": state.portraits.erase(command.get("slot", "CENTER"))
		elif type == "set_expression":
			var slot: String = str(command.get("slot", "CENTER"))
			if state.portraits.has(slot): state.portraits[slot].expression = command.get("expression", "DEFAULT")
		elif type in ["dialogue", "narration"]:
			state.current_line = command.duplicate(true)
			state.current_line["command_index"] = current_index
			state.dialogue_log.append(state.current_line.duplicate(true))
			_mark_read(current_index)
			_save_checkpoint()
			return state.current_line
		elif type == "choice":
			state.waiting_for_choice = true
			state.current_line = command.duplicate(true)
			_save_checkpoint()
			return state.current_line
		elif type == "set_flag": AppState.profile.story_flags[command.flag] = command.get("value", true)
		elif type == "check_flag":
			if AppState.profile.story_flags.get(command.flag, false) != command.get("equals", true): _jump(command.get("target", ""))
		elif type == "jump": _jump(command.get("target", ""))
		elif type == "play_bgm": AudioService.play_bgm(command.get("asset_id", ""))
		elif type == "stop_bgm": AudioService.stop_bgm()
		elif type == "play_sfx": AudioService.play_sfx(command.get("asset_id", ""))
		elif type == "play_voice":
			AudioService.play_voice(command.get("asset_id", command.get("voice_path", "")))
			state.current_line = command.duplicate(true)
			return state.current_line
		elif type in ["fade_in", "fade_out", "wait"]:
			state.current_line = command.duplicate(true)
			return state.current_line
		elif type == "start_battle":
			state.current_line = command.duplicate(true)
			_save_checkpoint()
			return state.current_line
		elif type == "grant_reward": AppState.add_item(command.item_id, int(command.get("quantity", 1)))
		elif type == "end_scenario":
			AppState.complete_story_trigger_for_scenario(state.scenario_id)
			if state.scenario_id == "SCN_CH01_MID_B": AppState.profile.roster.CHR006.unlocked = true
			if state.scenario_id == "SCN_CH01_OUTRO": AppState.profile.roster.CHR007.unlocked = true
			state.finished = true
			AppState.profile.last_scenario_position.erase(state.scenario_id)
			return command
	state.finished = true
	return {"command": "end_scenario"}

func choose(choice_index: int) -> GameResult:
	if not state.waiting_for_choice: return GameResult.failure("NO_ACTIVE_CHOICE")
	var choices: Array = state.current_line.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size(): return GameResult.failure("INVALID_CHOICE")
	var choice: Dictionary = choices[choice_index]
	if choice.has("set_flag"): AppState.profile.story_flags[choice.set_flag] = true
	if choice.has("target"): _jump(choice.target)
	state.waiting_for_choice = false
	state.current_line = {}
	_save_checkpoint()
	return GameResult.success()

func is_read(command_index: int) -> bool:
	return AppState.profile.read_commands.get(state.scenario_id, []).has(command_index)

func can_skip_current() -> bool:
	return is_read(int(state.current_line.get("command_index", -1)))

func _mark_read(command_index: int) -> void:
	if not AppState.profile.read_commands.has(state.scenario_id): AppState.profile.read_commands[state.scenario_id] = []
	if not AppState.profile.read_commands[state.scenario_id].has(command_index): AppState.profile.read_commands[state.scenario_id].append(command_index)

func _jump(target: String) -> void:
	if labels.has(target): state.command_index = int(labels[target])

func _save_checkpoint() -> void:
	AppState.profile.last_scenario_position[state.scenario_id] = state.snapshot()
