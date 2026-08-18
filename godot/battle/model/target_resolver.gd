class_name TargetResolver
extends RefCounted

static func choose(attacker: Dictionary, candidates: Array) -> Dictionary:
	var alive: Array = candidates.filter(func(unit): return UnitState.alive(unit))
	if alive.is_empty():
		return {}
	if attacker.team == "ENEMY" and attacker.statuses.has("TAUNT"):
		var source_id := str(attacker.statuses.TAUNT.get("source", ""))
		for unit in alive:
			if unit.uid == source_id:
				return unit
	if attacker.team == "ENEMY":
		alive.sort_custom(func(a, b): return float(a.threat) * UnitState.hp_ratio(a) > float(b.threat) * UnitState.hp_ratio(b))
	else:
		alive.sort_custom(func(a, b):
			if a.rank == "BOSS" and b.rank != "BOSS": return true
			if b.rank == "BOSS" and a.rank != "BOSS": return false
			return float(a.x) < float(b.x))
	return alive[0]

static func lowest_hp(candidates: Array) -> Dictionary:
	var alive: Array = candidates.filter(func(unit): return UnitState.alive(unit))
	if alive.is_empty():
		return {}
	alive.sort_custom(func(a, b): return UnitState.hp_ratio(a) < UnitState.hp_ratio(b))
	return alive[0]

