class_name BattleReturnAdapter
extends RefCounted

static func apply(stage_id: String, victory: bool) -> bool:
	return AppState.apply_battle_result_to_map(stage_id, victory, AppState.map_id_for_stage(stage_id))

static func return_screen() -> String:
	return "STAGE_SELECT"
