class_name TacticalPolicy
extends RefCounted

## A careful player's decisions, used by balance tools and tests to measure how
## much placement and reaction matter (the game itself never plays for the
## player beyond AUTO ultimates).
##   formation_for(party, stage, data)  reads the enemy squads and cover
##   react(sim)                          steps out of telegraphed cells and
##                                       calls a focus target
## Reaction starts REACTION_TICKS after a telegraph appears, roughly a person
## noticing the warning and dragging an ally.

const REACTION_TICKS := 18
const FRONT_ROLES := ["GUARDIAN", "VANGUARD"]

## Best-scoring placement of the party against every wave of the stage.
static func formation_for(party: Array, stage: Dictionary, data: Dictionary) -> Dictionary:
	var threat := _lane_threat(stage, data)
	var cover: Array = BattleGrid.cover_cells(stage)
	var cells: Array = []
	for col in BattleGrid.PLAYER_COLUMNS:
		for lane in range(BattleGrid.LANES):
			cells.append([int(col), lane])
	var roles: Array = []
	for member in party:
		roles.append(str(member.get("role", "")))
	var best_score := -INF
	var best: Array = []
	var chosen: Array = []
	var used: Dictionary = {}
	_search(roles, cells, 0, chosen, used, threat, cover, best_score, best)
	var output: Dictionary = {}
	if best.is_empty() or (best[0] as Array).is_empty():
		return BattleGrid.default_formation(party)
	for index in range(party.size()):
		output[str(party[index].get("id", party[index].get("def_id", "")))] = best[0][index]
	return output

## Depth-first over all distinct placements (9P5 = 15120), keeping the best in
## `best[0]`. `best_score` is passed through `best[1]`.
static func _search(roles: Array, cells: Array, index: int, chosen: Array, used: Dictionary, threat: Array, cover: Array, _unused: float, best: Array) -> void:
	if best.is_empty():
		best.append([])
		best.append(-INF)
	if index >= roles.size():
		var score := score_formation(roles, chosen, threat, cover)
		if score > float(best[1]):
			best[0] = chosen.duplicate(true)
			best[1] = score
		return
	for cell in cells:
		var key := BattleGrid.key(int(cell[0]), int(cell[1]))
		if used.has(key): continue
		used[key] = true
		chosen.append(cell)
		_search(roles, cells, index + 1, chosen, used, threat, cover, 0.0, best)
		chosen.pop_back()
		used.erase(key)

## Enemy melee pressure per lane and ranged pressure overall, from every wave.
static func _lane_threat(stage: Dictionary, data: Dictionary) -> Array:
	var melee := [0.0, 0.0, 0.0]
	var ranged := 0.0
	var boss := false
	var waves: Array = stage.get("waves", [])
	for wave_index in range(waves.size()):
		for entry in BattleSimulation.wave_layout(stage, wave_index, data):
			var definition: Dictionary = entry.definition
			var reach := BattleGrid.enemy_reach(str(definition.get("role", "")), str(definition.get("rank", "")))
			var weight := 2.0 if str(definition.get("rank", "")) == "ELITE" else 1.0
			if str(definition.get("rank", "")) == "BOSS": boss = true
			if bool(reach.melee): melee[int(entry.cell[1])] += weight
			else: ranged += weight
	return [melee, ranged, boss]

## Heuristic value of one placement (higher is better).
static func score_formation(roles: Array, placement: Array, threat: Array, cover: Array) -> float:
	var melee: Array = threat[0]
	var boss: bool = threat[2]
	var score := 0.0
	var blocked := [false, false, false]
	for index in range(roles.size()):
		var role := str(roles[index])
		var col := int(placement[index][0])
		var lane := int(placement[index][1])
		var reach := BattleGrid.player_reach(role)
		if role in FRONT_ROLES:
			if col == BattleGrid.PLAYER_FRONT:
				score += 4.0 + float(melee[lane]) * 3.0
				blocked[lane] = true
			else:
				score -= 6.0
			if role == "VANGUARD" and boss and lane == 1 and col == BattleGrid.PLAYER_FRONT: score += 2.0
		else:
			# Ranged roles want to reach column 4 (the boss and the enemy's second
			# row) without standing in the front row.
			var reach_cols := int(reach.range) - (4 - col)
			if col == BattleGrid.PLAYER_FRONT: score -= 5.0
			if role == "MEDIC":
				score += 2.0 if col <= 1 else 0.0
			elif role == "ARTILLERY":
				score += 3.0 if col == 0 else 1.0
			elif reach_cols >= 0:
				score += 3.0
			if BattleGrid.has_cell(cover, col, lane): score += 2.5
		# Neighbour synergies.
		for other in range(roles.size()):
			if other == index: continue
			var dc := absi(col - int(placement[other][0]))
			var dl := absi(lane - int(placement[other][1]))
			if dc + dl != 1: continue
			if role == "GUARDIAN": score += 1.2
			if role == "SPECIALIST" and not (str(roles[other]) in ["MEDIC"]): score += 1.0
			if role == "MEDIC": score += .6
	var total_melee := float(melee[0]) + float(melee[1]) + float(melee[2])
	for lane in range(BattleGrid.LANES):
		if not bool(blocked[lane]):
			# Rushers from the other lanes also head for an open lane.
			score -= float(melee[lane]) * 4.0 + (total_melee - float(melee[lane])) * 1.5
			# Something must stand behind an open lane or the breach walks free.
			for index in range(roles.size()):
				if int(placement[index][1]) == lane and str(roles[index]) in ["MEDIC", "ARTILLERY"]:
					score -= float(melee[lane]) * 1.5
	return score

## Step allies out of telegraphed cells and keep a sensible focus target.
static func react(sim: BattleSimulation) -> void:
	if sim.state.ended:
		return
	var danger: Dictionary = {}
	for cast in sim.pending_boss_casts:
		var age := int(cast.get("windup_ticks", BattleSimulation.BOSS_WINDUP_TICKS)) - (int(cast.due_tick) - sim.state.tick)
		if age < REACTION_TICKS: continue
		for cell in cast.get("cells", []):
			danger[BattleGrid.key(int(cell[0]), int(cell[1]))] = true
	if not danger.is_empty():
		for unit in sim.state.party:
			if not UnitState.alive(unit): continue
			if not danger.has(BattleGrid.key(int(unit.col), int(unit.lane))): continue
			var destination := _safe_cell(sim, unit, danger)
			if destination.is_empty(): continue
			if sim.move_block_reason(str(unit.uid), int(destination[0]), int(destination[1])).is_empty():
				sim.request_move(str(unit.uid), int(destination[0]), int(destination[1]))
	if sim.state.tick % 15 == 0:
		_update_focus(sim)

static func _safe_cell(sim: BattleSimulation, unit: Dictionary, danger: Dictionary) -> Array:
	var best: Array = []
	var best_score := -INF
	for col in BattleGrid.PLAYER_COLUMNS:
		for lane in range(BattleGrid.LANES):
			if danger.has(BattleGrid.key(int(col), lane)): continue
			if not sim.unit_at(int(col), lane).is_empty(): continue
			var score := -float(absi(int(col) - int(unit.col)) + absi(lane - int(unit.lane)))
			if str(unit.role) in FRONT_ROLES and int(col) == BattleGrid.PLAYER_FRONT: score += 2.0
			if not (str(unit.role) in FRONT_ROLES) and int(col) < BattleGrid.PLAYER_FRONT: score += 1.0
			if score > best_score:
				best_score = score
				best = [int(col), lane]
	return best

static func _update_focus(sim: BattleSimulation) -> void:
	var enemies := sim.alive_enemies()
	if enemies.is_empty(): return
	var pick := {}
	# A rusher inside the party's zone is the first thing to shoot down.
	for enemy in enemies:
		if int(enemy.col) <= BattleGrid.PLAYER_FRONT:
			pick = enemy
			break
	for enemy in enemies:
		if not pick.is_empty(): break
		if str(enemy.role) in ["HEALER", "ARTILLERY", "AREA"] and str(enemy.rank) != "BOSS":
			var reachers := 0
			for ally in sim.state.party:
				if UnitState.alive(ally) and TargetResolver.in_range(ally, enemy): reachers += 1
			if reachers >= 2:
				pick = enemy
				break
	var focus_id := str(pick.get("uid", ""))
	if focus_id != sim.state.focus_uid:
		sim.request_focus(focus_id)
