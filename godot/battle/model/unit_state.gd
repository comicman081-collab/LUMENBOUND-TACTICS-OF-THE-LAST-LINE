class_name UnitState
extends RefCounted

static func alive(unit: Dictionary) -> bool:
	return bool(unit.get("alive", false)) and int(unit.get("hp", 0)) > 0

static func hp_ratio(unit: Dictionary) -> float:
	return float(unit.get("hp", 0)) / maxf(1.0, float(unit.get("max_hp", 1)))

static func has_status(unit: Dictionary, status_id: String) -> bool:
	return unit.get("statuses", {}).has(status_id)

