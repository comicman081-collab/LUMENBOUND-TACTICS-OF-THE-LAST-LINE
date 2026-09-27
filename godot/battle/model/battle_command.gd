class_name BattleCommand
extends RefCounted

const USE_ULTIMATE := "USE_ULTIMATE"
const MOVE := "MOVE"
const FOCUS := "FOCUS"

static func ultimate(tick: int, unit_id: String, target_unit_id := "") -> Dictionary:
	return {"tick": tick, "type": USE_ULTIMATE, "unit_id": unit_id, "target_unit_id": target_unit_id}

static func move(tick: int, unit_id: String, col: int, lane: int) -> Dictionary:
	return {"tick": tick, "type": MOVE, "unit_id": unit_id, "col": col, "lane": lane}

static func focus(tick: int, target_unit_id: String) -> Dictionary:
	return {"tick": tick, "type": FOCUS, "unit_id": "", "target_unit_id": target_unit_id}
