class_name BattleReturnAdapter
extends RefCounted

static func apply(stage_id: String, victory: bool) -> bool:
	return AppState.apply_battle_result_to_map(stage_id, victory, "CH01_MAP")

static func return_screen() -> String:
	return "STAGE_SELECT"
