class_name TargetResolver
extends RefCounted

# Party slots are 전열 A/B, 중열 A/B, 후열. Melee enemies mostly reach the front
# row; ranged enemies and bosses spread further back. Formation therefore
# decides who takes the hits instead of only the opening cooldown order.
const ROW_WEIGHT_MELEE := [1.0, 1.0, .55, .55, .35]
const ROW_WEIGHT_RANGED := [1.0, 1.0, .85, .85, .72]
const MELEE_ENEMY_ROLES := ["MELEE_RUSH", "DEFENDER"]

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
		var weights: Array = ROW_WEIGHT_MELEE if str(attacker.get("role", "")) in MELEE_ENEMY_ROLES and str(attacker.get("rank", "")) != "BOSS" else ROW_WEIGHT_RANGED
		# Slot breaks ties so the order never depends on the unstable sort.
		alive.sort_custom(func(a, b):
			var left := enemy_priority(a, weights)
			var right := enemy_priority(b, weights)
			if not is_equal_approx(left, right): return left > right
			return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	else:
		alive.sort_custom(func(a, b):
			if a.rank == "BOSS" and b.rank != "BOSS": return true
			if b.rank == "BOSS" and a.rank != "BOSS": return false
			if not is_equal_approx(float(a.x), float(b.x)): return float(a.x) < float(b.x)
			return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	return alive[0]

## The original threat x HP-ratio rule, weighted by row. Healthy front-liners
## draw the attacks; as they weaken, pressure spreads to the next row instead
## of focusing one unit to death (which unbalanced the existing stage tuning).
static func enemy_priority(unit: Dictionary, weights: Array) -> float:
	var slot := clampi(int(unit.get("slot", 0)), 0, weights.size() - 1)
	return float(unit.get("threat", 1.0)) * UnitState.hp_ratio(unit) * float(weights[slot])

static func lowest_hp(candidates: Array) -> Dictionary:
	var alive: Array = candidates.filter(func(unit): return UnitState.alive(unit))
	if alive.is_empty():
		return {}
	alive.sort_custom(func(a, b):
		if not is_equal_approx(UnitState.hp_ratio(a), UnitState.hp_ratio(b)): return UnitState.hp_ratio(a) < UnitState.hp_ratio(b)
		return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	return alive[0]

