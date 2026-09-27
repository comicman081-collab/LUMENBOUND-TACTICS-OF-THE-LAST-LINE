class_name TargetResolver
extends RefCounted

## Grid targeting. A unit only attacks what its reach covers (see BattleGrid):
## melee reach counts orthogonal steps, ranged reach counts columns. Among the
## targets in reach the nearest one is chosen, same lane first, so a front row
## shields the lane behind it. A taunt, the party's focus target and enemy
## back-row hunters override the nearest rule; a rusher that broke into the
## party's zone hunts the back row too.
const LANE_WEIGHT := .6
const BACKLINE_HUNTER_ROLES := ["ARTILLERY"]

static func in_range(attacker: Dictionary, target: Dictionary) -> bool:
	var dcol := absi(int(attacker.get("col", 0)) - int(target.get("col", 0)))
	var dlane := absi(int(attacker.get("lane", 0)) - int(target.get("lane", 0)))
	if bool(attacker.get("melee", false)):
		return dcol + dlane <= int(attacker.get("range", 1))
	return dcol <= int(attacker.get("range", 3))

static func distance_score(attacker: Dictionary, target: Dictionary) -> float:
	var dcol := absi(int(attacker.get("col", 0)) - int(target.get("col", 0)))
	var dlane := absi(int(attacker.get("lane", 0)) - int(target.get("lane", 0)))
	return float(dcol) + LANE_WEIGHT * float(dlane)

static func in_range_targets(attacker: Dictionary, candidates: Array) -> Array:
	return candidates.filter(func(unit): return UnitState.alive(unit) and in_range(attacker, unit))

## Target for a basic attack or single-target skill, or {} when nothing is in
## reach. `focus_uid` is the party's focus-fire order (players only).
static func choose(attacker: Dictionary, candidates: Array, focus_uid := "") -> Dictionary:
	var reachable := in_range_targets(attacker, candidates)
	if reachable.is_empty():
		return {}
	var team := str(attacker.get("team", ""))
	if team == "ENEMY" and attacker.get("statuses", {}).has("TAUNT"):
		var source_id := str(attacker.statuses.TAUNT.get("source", ""))
		for unit in reachable:
			if str(unit.uid) == source_id:
				return unit
	if team == "PLAYER" and not focus_uid.is_empty():
		for unit in reachable:
			if str(unit.uid) == focus_uid:
				return unit
	var breached: bool = team == "ENEMY" and str(attacker.get("role", "")) == "MELEE_RUSH" and int(attacker.get("col", 9)) <= BattleGrid.PLAYER_FRONT
	if team == "ENEMY" and (breached or str(attacker.get("role", "")) in BACKLINE_HUNTER_ROLES) and str(attacker.get("rank", "")) != "BOSS":
		# Rear hunters pick the deepest ally in reach, then the weakest.
		reachable.sort_custom(func(a, b):
			if int(a.col) != int(b.col): return int(a.col) < int(b.col)
			if not is_equal_approx(UnitState.hp_ratio(a), UnitState.hp_ratio(b)): return UnitState.hp_ratio(a) < UnitState.hp_ratio(b)
			return int(a.get("slot", 0)) < int(b.get("slot", 0)))
		return reachable[0]
	reachable.sort_custom(func(a, b):
		var left := distance_score(attacker, a)
		var right := distance_score(attacker, b)
		if not is_equal_approx(left, right): return left < right
		if team == "ENEMY":
			# Guardians draw attention among equally near allies.
			if not is_equal_approx(float(a.get("threat", 1.0)), float(b.get("threat", 1.0))):
				return float(a.get("threat", 1.0)) > float(b.get("threat", 1.0))
		else:
			if str(a.get("rank", "")) == "BOSS" and str(b.get("rank", "")) != "BOSS": return true
			if str(b.get("rank", "")) == "BOSS" and str(a.get("rank", "")) != "BOSS": return false
			if not is_equal_approx(UnitState.hp_ratio(a), UnitState.hp_ratio(b)): return UnitState.hp_ratio(a) < UnitState.hp_ratio(b)
		return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	return reachable[0]

## Nearest living candidate regardless of reach (ultimates are battlefield-wide).
static func nearest(attacker: Dictionary, candidates: Array) -> Dictionary:
	var alive: Array = candidates.filter(func(unit): return UnitState.alive(unit))
	if alive.is_empty():
		return {}
	alive.sort_custom(func(a, b):
		var left := distance_score(attacker, a)
		var right := distance_score(attacker, b)
		if not is_equal_approx(left, right): return left < right
		return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	return alive[0]

## The enemy an ultimate should go for: a boss, then an elite, then the most
## wounded.
static func priority_enemy(candidates: Array) -> Dictionary:
	var alive: Array = candidates.filter(func(unit): return UnitState.alive(unit))
	if alive.is_empty():
		return {}
	alive.sort_custom(func(a, b):
		var rank_a: int = {"BOSS": 0, "ELITE": 1}.get(str(a.get("rank", "")), 2)
		var rank_b: int = {"BOSS": 0, "ELITE": 1}.get(str(b.get("rank", "")), 2)
		if rank_a != rank_b: return rank_a < rank_b
		if not is_equal_approx(UnitState.hp_ratio(a), UnitState.hp_ratio(b)): return UnitState.hp_ratio(a) < UnitState.hp_ratio(b)
		return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	return alive[0]

static func lowest_hp(candidates: Array) -> Dictionary:
	var alive: Array = candidates.filter(func(unit): return UnitState.alive(unit))
	if alive.is_empty():
		return {}
	alive.sort_custom(func(a, b):
		if not is_equal_approx(UnitState.hp_ratio(a), UnitState.hp_ratio(b)): return UnitState.hp_ratio(a) < UnitState.hp_ratio(b)
		return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	return alive[0]
