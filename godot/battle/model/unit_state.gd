class_name UnitState
extends RefCounted

static func alive(unit: Dictionary) -> bool:
	return bool(unit.get("alive", false)) and int(unit.get("hp", 0)) > 0

static func hp_ratio(unit: Dictionary) -> float:
	return float(unit.get("hp", 0)) / maxf(1.0, float(unit.get("max_hp", 1)))

static func has_status(unit: Dictionary, status_id: String) -> bool:
	return unit.get("statuses", {}).has(status_id)

## Strength of an active status, or `fallback` when the status was applied
## without one. Fallbacks equal the former fixed values (HASTE .2, SLOW .3,
## DEF_DOWN .25) so existing effects keep their exact numbers.
static func status_strength(unit: Dictionary, status_id: String, fallback: float) -> float:
	var status: Dictionary = unit.get("statuses", {}).get(status_id, {})
	if status.is_empty():
		return 0.0
	var strength := float(status.get("strength", 0.0))
	return strength if strength > 0.0 else fallback

