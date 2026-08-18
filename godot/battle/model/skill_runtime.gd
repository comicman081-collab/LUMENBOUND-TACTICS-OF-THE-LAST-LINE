class_name SkillRuntime
extends RefCounted

static func value_at(skill: Dictionary, level: int) -> float:
	var values: Array = skill.get("values", [])
	if values.is_empty():
		return 1.0
	return float(values[clampi(level - 1, 0, values.size() - 1)])

static func can_use_ultimate(unit: Dictionary, skill: Dictionary, gauge: float) -> bool:
	return UnitState.alive(unit) and not UnitState.has_status(unit, "SILENCE") and gauge >= float(skill.get("tactical_cost", 99))

