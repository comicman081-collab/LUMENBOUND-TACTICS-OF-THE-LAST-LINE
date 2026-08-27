class_name ScenarioState
extends RefCounted

var scenario_id := ""
var command_index := 0
var background_asset_id := ""
var cg_asset_id := ""
var portraits: Dictionary = {}
var current_line: Dictionary = {}
var dialogue_log: Array = []
var waiting_for_choice := false
var finished := false

func snapshot() -> Dictionary:
	# A scenario can be closed while a choice is visible.  Keep that transient
	# interaction state with the visual state so a Web tab reload resumes the
	# same decision instead of silently rewinding to the preceding line.
	return {
		"scenario_id": scenario_id,
		"command_index": command_index,
		"background_asset_id": background_asset_id,
		"cg_asset_id": cg_asset_id,
		"portraits": portraits.duplicate(true),
		"current_line": current_line.duplicate(true),
		"waiting_for_choice": waiting_for_choice,
	}
