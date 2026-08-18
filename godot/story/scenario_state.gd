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
	return {"scenario_id": scenario_id, "command_index": command_index, "background_asset_id": background_asset_id, "cg_asset_id": cg_asset_id, "portraits": portraits.duplicate(true)}

