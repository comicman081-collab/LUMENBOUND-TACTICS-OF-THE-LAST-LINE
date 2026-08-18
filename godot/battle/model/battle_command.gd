class_name BattleCommand
extends RefCounted

const USE_ULTIMATE := "USE_ULTIMATE"

static func ultimate(tick: int, unit_id: String, target_unit_id := "") -> Dictionary:
	return {"tick": tick, "type": USE_ULTIMATE, "unit_id": unit_id, "target_unit_id": target_unit_id}
