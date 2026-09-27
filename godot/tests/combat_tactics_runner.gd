extends Node

## Positional combat rules (BattleGrid): deployment, reach, lane blocking and
## breaches, player moves and focus, flank/cover/guard modifiers, telegraphed
## area attacks that can be dodged, growth sync, AUTO gauge reservation,
## target-checked ultimates, enemy role skills and deterministic replays.

var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS | " + label)
	else:
		failed += 1
		print("FAIL | " + label)
		push_error(label)

func _ready() -> void:
	AppState.new_game()
	_test_deployment()
	_test_reach()
	_test_lane_blocking()
	_test_player_moves()
	_test_positional_modifiers()
	_test_telegraphs()
	_test_growth_sync()
	_test_auto_reserve()
	_test_ultimate_target_resolution()
	_test_level_scaled_buffs()
	_test_boss_phase()
	_test_same_tick_victory()
	_test_enemy_role_skills()
	_test_tactical_policy()
	_test_determinism()
	print("COMBAT_TACTICS total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _simulation(stage_id := "CH01-N01", seed_value := 4242, options := {}) -> BattleSimulation:
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage(stage_id), seed_value, DataRegistry.data, options)
	return sim

func _unit_with_role(units: Array, role: String) -> Dictionary:
	for unit in units:
		if str(unit.role) == role: return unit
	return {}

## Keeps the first `count` enemies alive, removes the rest from the board.
func _keep_enemies(sim: BattleSimulation, count: int) -> void:
	for index in range(sim.state.enemies.size()):
		if index >= count:
			sim.state.enemies[index].alive = false
			sim.state.enemies[index].hp = 0
			sim.state.enemies[index].col = -5

func _place(unit: Dictionary, col: int, lane: int) -> void:
	unit.col = col
	unit.lane = lane
	unit.moving_ticks = 0

## Moves the whole party onto the given cells in party order.
func _place_party(sim: BattleSimulation, cells: Array) -> void:
	for index in range(sim.state.party.size()):
		_place(sim.state.party[index], int(cells[index][0]), int(cells[index][1]))

func _test_deployment() -> void:
	var sim := _simulation()
	var seen := {}
	var inside := true
	for unit in sim.state.party:
		seen[BattleGrid.key(int(unit.col), int(unit.lane))] = true
		inside = inside and BattleGrid.in_player_zone(int(unit.col), int(unit.lane))
	check(inside and seen.size() == sim.state.party.size(), "GRID_01 the party starts on distinct cells of its own three columns")
	var front_ok := true
	for unit in sim.state.party:
		if str(unit.preferred_position) == "FRONT": front_ok = front_ok and int(unit.col) == BattleGrid.PLAYER_FRONT
		if str(unit.preferred_position) == "BACK": front_ok = front_ok and int(unit.col) == 0
	check(front_ok, "GRID_02 the default formation follows each member's preferred row")
	var enemy_ok := true
	var enemy_seen := {}
	for enemy in sim.state.enemies:
		enemy_seen[BattleGrid.key(int(enemy.col), int(enemy.lane))] = true
		enemy_ok = enemy_ok and int(enemy.col) >= BattleGrid.ENEMY_FRONT and int(enemy.col) < BattleGrid.COLUMNS
	check(enemy_ok and enemy_seen.size() == sim.state.enemies.size(), "GRID_03 enemies spawn on distinct cells of the enemy side")
	var first: Dictionary = sim.state.party[0]
	var second: Dictionary = sim.state.party[1]
	var first_cell := [int(first.col), int(first.lane)]
	var second_cell := [int(second.col), int(second.lane)]
	check(sim.deploy_move(str(first.uid), int(second_cell[0]), int(second_cell[1])) and [int(first.col), int(first.lane)] == second_cell and [int(second.col), int(second.lane)] == first_cell, "GRID_04 deploying onto an ally's cell swaps the two")
	check(not sim.deploy_move(str(first.uid), 4, 1), "GRID_05 deployment cannot enter the enemy side")
	var replay := _simulation("CH01-N01", 4242, {"formation": sim.formation()})
	check(JSON.stringify(replay.formation()) == JSON.stringify(sim.formation()), "GRID_06 a saved formation reproduces the same placement")
	check(sim.set_formation({}) and JSON.stringify(sim.formation()) == JSON.stringify(_simulation().formation()), "GRID_07 an empty formation restores the default layout")
	sim.tick()
	check(not sim.deploy_move(str(first.uid), 0, 0) and not sim.set_formation({}), "GRID_08 deployment locks once the battle clock starts")
	check(BattleGrid.cover_cells(DataRegistry.stage("CH01-N01")).is_empty() and not BattleGrid.cover_cells(DataRegistry.stage("CH01-N05")).is_empty(), "GRID_09 the first operations are open ground; later ones have cover")
	check(JSON.stringify(BattleGrid.cover_cells(DataRegistry.stage("CH03-N07"))) == JSON.stringify(BattleGrid.cover_cells(DataRegistry.stage("CH03-N07"))), "GRID_10 cover positions are fixed per stage")

func _test_reach() -> void:
	var sim := _simulation()
	_keep_enemies(sim, 1)
	var enemy: Dictionary = sim.state.enemies[0]
	var guardian := _unit_with_role(sim.state.party, "GUARDIAN")
	check(not guardian.is_empty(), "REACH_00 fixture party has a guardian")
	_place(guardian, 2, 1)
	_place(enemy, 4, 1)
	check(TargetResolver.choose(guardian, sim.state.enemies).is_empty(), "REACH_01 a guardian (reach 1) cannot hit an enemy two columns away")
	_place(enemy, 3, 1)
	check(str(TargetResolver.choose(guardian, sim.state.enemies).get("uid", "")) == str(enemy.uid), "REACH_02 the guardian strikes the enemy directly in front of it")
	_place(enemy, 3, 0)
	var vanguard := _unit_with_role(sim.state.party, "VANGUARD")
	var vanguard_cell := [int(vanguard.col), int(vanguard.lane)]
	_place(vanguard, 2, 2)
	var guardian_blind := TargetResolver.choose(guardian, sim.state.enemies).is_empty()
	_place(vanguard, 2, 1)
	_place(guardian, 1, 1)
	check(guardian_blind and not TargetResolver.choose(vanguard, sim.state.enemies).is_empty(), "REACH_03 melee reach is counted in steps: a diagonal is out of the guardian's reach but inside the vanguard's")
	_place(guardian, 2, 1)
	_place(vanguard, int(vanguard_cell[0]), int(vanguard_cell[1]))
	var gunner: Dictionary = {}
	for unit in sim.state.party:
		if not bool(unit.melee) and int(unit.range) == 3: gunner = unit
	_place(gunner, 1, 2)
	_place(enemy, 4, 0)
	check(not TargetResolver.choose(gunner, sim.state.enemies).is_empty(), "REACH_04 ranged reach counts columns only: a reach-3 shooter hits any lane three columns ahead")
	_place(enemy, 5, 0)
	check(TargetResolver.choose(gunner, sim.state.enemies).is_empty(), "REACH_05 the same shooter cannot reach four columns")
	var hunter := {"team": "ENEMY", "role": "ARTILLERY", "rank": "NORMAL", "range": 5, "melee": false, "col": 5, "lane": 1, "statuses": {}}
	var deepest := TargetResolver.choose(hunter, sim.state.party)
	var min_col := 9
	for unit in sim.state.party: min_col = mini(min_col, int(unit.col))
	check(int(deepest.col) == min_col, "REACH_06 enemy artillery hunts the deepest ally in reach")
	var sim2 := _simulation("CH01-N05")
	var shooter := {}
	for unit in sim2.state.party:
		if not bool(unit.melee): shooter = unit
	_place(shooter, 1, 1)
	var targets := TargetResolver.in_range_targets(shooter, sim2.state.enemies)
	if targets.size() >= 2:
		var natural := TargetResolver.choose(shooter, sim2.state.enemies)
		var other: Dictionary = targets[0] if str(targets[0].uid) != str(natural.uid) else targets[1]
		check(str(TargetResolver.choose(shooter, sim2.state.enemies, str(other.uid)).uid) == str(other.uid), "REACH_07 a focus call overrides the nearest target when it is in reach")
	else:
		check(false, "REACH_07 fixture needs two enemies in reach")
	var far := {"uid": "FAR", "team": "ENEMY", "alive": true, "hp": 10, "max_hp": 10, "col": 5, "lane": 2, "rank": "NORMAL", "statuses": {}}
	var guardian2 := _unit_with_role(sim2.state.party, "GUARDIAN")
	_place(guardian2, 2, 1)
	check(TargetResolver.choose(guardian2, [far], "FAR").is_empty(), "REACH_08 a focus target out of reach is ignored instead of breaking reach")

func _test_lane_blocking() -> void:
	# Breach: a rusher in a lane nobody holds walks into the party's zone.
	var sim := _simulation("CH01-N05", 99)
	_keep_enemies(sim, 1)
	var rusher: Dictionary = sim.state.enemies[0]
	rusher.role = "MELEE_RUSH"
	rusher.melee = true
	rusher.range = 1
	rusher.step = .9
	_place(rusher, 3, 0)
	_place_party(sim, [[0, 1], [1, 1], [2, 1], [1, 2], [2, 2]])
	for unit in sim.state.party:
		unit.max_hp = 999999
		unit.hp = 999999
	rusher.max_hp = 999999
	rusher.hp = 999999
	var entered := false
	for _index in range(150):
		sim.tick()
		if int(rusher.col) <= BattleGrid.PLAYER_FRONT: entered = true
	check(entered, "LANE_01 an open lane lets a melee enemy break into the party's zone")
	# Blocked: the same rusher facing a guardian in its lane stops and fights.
	sim = _simulation("CH01-N05", 99)
	_keep_enemies(sim, 1)
	rusher = sim.state.enemies[0]
	rusher.role = "MELEE_RUSH"
	rusher.melee = true
	rusher.range = 1
	rusher.step = .9
	rusher.max_hp = 999999
	rusher.hp = 999999
	var guardian := _unit_with_role(sim.state.party, "GUARDIAN")
	var others: Array = []
	for unit in sim.state.party:
		unit.max_hp = 999999
		unit.hp = 999999
		if str(unit.uid) != str(guardian.uid): others.append(unit)
	_place(guardian, 2, 0)
	var spots := [[2, 1], [2, 2], [0, 1], [1, 1]]
	for index in range(others.size()): _place(others[index], int(spots[index][0]), int(spots[index][1]))
	_place(rusher, 4, 0)
	var hit_guardian := false
	var passed_guard := false
	for _index in range(150):
		var log_size := sim.event_log.size()
		sim.tick()
		if int(rusher.col) < BattleGrid.ENEMY_FRONT: passed_guard = true
		for event in sim.event_log.slice(log_size):
			if str(event.type) == BattleEvent.BASIC_ATTACK and str(event.source) == str(rusher.uid) and str(event.target) == str(guardian.uid): hit_guardian = true
	check(hit_guardian and not passed_guard, "LANE_02 with every lane held, the rusher stops at the guardian and takes its blows")
	var moved := false
	for event in sim.event_log:
		if str(event.type) == BattleEvent.MOVE and str(event.source) == str(rusher.uid) and str(event.extra.get("reason", "")) == "ADVANCE": moved = true
	check(moved, "LANE_03 enemies advance with MOVE events the view can animate")
	# Gap seeking: the same rusher facing a held lane next to an open one slips
	# into the open lane, then hunts the back row.
	sim = _simulation("CH01-N05", 99)
	_keep_enemies(sim, 1)
	rusher = sim.state.enemies[0]
	rusher.role = "MELEE_RUSH"
	rusher.melee = true
	rusher.range = 1
	rusher.step = .9
	rusher.max_hp = 999999
	rusher.hp = 999999
	guardian = _unit_with_role(sim.state.party, "GUARDIAN")
	others = []
	for unit in sim.state.party:
		unit.max_hp = 999999
		unit.hp = 999999
		if str(unit.uid) != str(guardian.uid): others.append(unit)
	_place(guardian, 2, 0)
	var gap_spots := [[2, 2], [0, 0], [0, 1], [1, 2]]
	for index in range(others.size()): _place(others[index], int(gap_spots[index][0]), int(gap_spots[index][1]))
	_place(rusher, 4, 0)
	var entered_lane := -1
	var hit_back := false
	for _index in range(240):
		var log_size := sim.event_log.size()
		sim.tick()
		if int(rusher.col) <= BattleGrid.PLAYER_FRONT and entered_lane < 0: entered_lane = int(rusher.lane)
		for event in sim.event_log.slice(log_size):
			if str(event.type) == BattleEvent.BASIC_ATTACK and str(event.source) == str(rusher.uid):
				var victim := sim.find_unit(str(event.target))
				if not victim.is_empty() and int(victim.col) < BattleGrid.PLAYER_FRONT: hit_back = true
	check(entered_lane == 1, "LANE_04 a rusher slips toward the lane nobody holds")
	check(hit_back, "LANE_05 once inside the party's zone the rusher goes for the back row")

func _test_player_moves() -> void:
	var sim := _simulation("CH01-N05", 5)
	var unit: Dictionary = sim.state.party[3]
	var free := []
	for col in BattleGrid.PLAYER_COLUMNS:
		for lane in range(BattleGrid.LANES):
			if sim.unit_at(int(col), lane).is_empty() and free.is_empty(): free = [int(col), lane]
	check(sim.move_block_reason(str(unit.uid), 4, 1) == "ZONE", "MOVE_01 allies cannot move onto the enemy side")
	check(sim.move_block_reason(str(unit.uid), int(unit.col), int(unit.lane)) == "SAME", "MOVE_02 moving onto the own cell is refused")
	sim.request_move(str(unit.uid), int(free[0]), int(free[1]))
	sim.tick()
	check([int(unit.col), int(unit.lane)] == free and int(unit.moving_ticks) > 0 and float(unit.move_cd) > 2.5, "MOVE_03 a move command relocates the ally, with transit time and a cooldown")
	var target_cell := [int(sim.state.party[0].col), int(sim.state.party[0].lane)]
	check(sim.move_block_reason(str(unit.uid), int(target_cell[0]), int(target_cell[1])) in ["MOVING", "COOLDOWN"], "MOVE_04 a second move waits for transit and cooldown")
	for _index in range(int(BattleSimulation.PLAYER_MOVE_COOLDOWN * 30.0) + 2): sim.tick()
	var partner: Dictionary = sim.state.party[0]
	var before := [int(unit.col), int(unit.lane)]
	if not sim.state.ended and UnitState.alive(unit) and UnitState.alive(partner):
		sim.request_move(str(unit.uid), int(partner.col), int(partner.lane))
		var partner_cell := [int(partner.col), int(partner.lane)]
		sim.tick()
		check([int(unit.col), int(unit.lane)] == partner_cell and [int(partner.col), int(partner.lane)] == before, "MOVE_05 moving onto an ally's cell swaps the two")
	else:
		check(false, "MOVE_05 fixture survived long enough to swap")
	check(int(sim.move_commands) == 2 and int(sim.result_snapshot().moves) == 2, "MOVE_06 the result records how many moves the player ordered")
	var focus_sim := _simulation("CH01-N05", 5)
	var focus_target: Dictionary = focus_sim.state.enemies[1]
	focus_sim.request_focus(str(focus_target.uid))
	focus_sim.tick()
	check(focus_sim.state.focus_uid == str(focus_target.uid), "MOVE_07 a focus call marks the enemy for the party")
	focus_target.hp = 0
	focus_sim._down_unit(focus_target, "", "TEST")
	check(focus_sim.state.focus_uid.is_empty(), "MOVE_08 the focus clears when the marked enemy falls")

func _test_positional_modifiers() -> void:
	var sim := _simulation("CH01-N05", 11)
	_keep_enemies(sim, 1)
	var enemy: Dictionary = sim.state.enemies[0]
	var melee_enemy := {"uid": "E:X", "team": "ENEMY", "role": "MELEE_RUSH", "melee": true, "range": 1, "col": 2, "lane": 0, "statuses": {}, "alive": true, "hp": 1}
	var victim: Dictionary = {}
	for unit in sim.state.party:
		if str(unit.role) != "GUARDIAN" and victim.is_empty(): victim = unit
	_place_party(sim, [[0, 0], [0, 1], [0, 2], [1, 0], [1, 2]])
	_place(victim, 2, 1)
	var flank := sim.positional_factor(melee_enemy, victim)
	check(is_equal_approx(float(flank.factor), BattleGrid.FLANK_DAMAGE) and (flank.tags as Array).has("FLANK"), "POS_01 a melee hit from the side lands as a flank (+30%)")
	var ranged_enemy := {"uid": "E:Y", "team": "ENEMY", "role": "RANGED", "melee": false, "range": 3, "col": 4, "lane": 1, "statuses": {}, "alive": true, "hp": 1}
	sim.state.cover_cells = [[2, 1]]
	var covered := sim.positional_factor(ranged_enemy, victim)
	check(is_equal_approx(float(covered.factor), BattleGrid.COVER_DAMAGE_TAKEN) and (covered.tags as Array).has("COVER"), "POS_02 cover cuts ranged damage by 30%")
	sim.state.cover_cells = []
	var guardian := _unit_with_role(sim.state.party, "GUARDIAN")
	var old_guardian := [int(guardian.col), int(guardian.lane)]
	_place(guardian, 1, 1)
	var guarded := sim.positional_factor(ranged_enemy, victim)
	check((guarded.tags as Array).has("GUARDED") and float(guarded.factor) < 1.0, "POS_03 an ally next to a guardian takes less damage")
	_place(guardian, int(old_guardian[0]), int(old_guardian[1]))
	var artillery := _unit_with_role(sim.state.party, "ARTILLERY")
	if not artillery.is_empty():
		_place(enemy, 3, 1)
		_place(artillery, 0, 1)
		var steady := sim.positional_factor(artillery, enemy)
		check((steady.tags as Array).has("STEADY") and float(steady.factor) >= BattleGrid.ARTILLERY_BACK_ROW_DAMAGE - .001, "POS_04 artillery firing from the back row hits harder")
	else:
		check(true, "POS_04 fixture party has no artillery")
	var medic := _unit_with_role(sim.state.party, "MEDIC")
	if not medic.is_empty():
		_place_party(sim, [[0, 0], [0, 2], [2, 0], [2, 2], [1, 0]])
		_place(medic, 1, 1)
		var near: Dictionary = {}
		var far: Dictionary = {}
		for unit in sim.state.party:
			if str(unit.uid) == str(medic.uid): continue
			if BattleGrid.adjacent(unit, medic) and near.is_empty(): near = unit
			if not BattleGrid.adjacent(unit, medic) and far.is_empty(): far = unit
		if near.is_empty():
			_place(sim.state.party[0] if str(sim.state.party[0].uid) != str(medic.uid) else sim.state.party[1], 1, 0)
			near = sim.state.party[0] if str(sim.state.party[0].uid) != str(medic.uid) else sim.state.party[1]
		near.hp = 1
		var log_size := sim.event_log.size()
		sim._heal(medic, near, 1.0)
		var adjacent_flag := false
		for event in sim.event_log.slice(log_size):
			if str(event.type) == BattleEvent.HEAL and bool(event.extra.get("adjacent", false)): adjacent_flag = true
		check(adjacent_flag, "POS_05 a medic heals the ally beside her more")
	else:
		check(true, "POS_05 fixture party has no medic")

func _boss_sim() -> BattleSimulation:
	var sim := _simulation("CH01-N20", 777)
	while sim.state.wave < sim.state.wave_count and not sim.state.ended and sim.state.tick < 6000:
		for enemy in sim.state.enemies:
			enemy.hp = 0
			enemy.alive = false
		sim.tick()
	for unit in sim.state.party:
		unit.max_hp = 999999
		unit.hp = 999999
	return sim

func _boss_of(sim: BattleSimulation) -> Dictionary:
	for enemy in sim.state.enemies:
		if str(enemy.rank) == "BOSS": return enemy
	return {}

func _test_telegraphs() -> void:
	var sim := _boss_sim()
	var boss := _boss_of(sim)
	check(not boss.is_empty() and [int(boss.col), int(boss.lane)] == [4, 1], "TEL_01 the boss holds the centre of the enemy side")
	if boss.is_empty(): return
	boss.patterns = []
	sim.pending_boss_casts.clear()
	var victim: Dictionary = sim.state.party[0]
	var cells := [[int(victim.col), int(victim.lane)]]
	sim._announce_area_cast(boss, "LOCK_ON", "CELL", cells, 1.0, .32, BattleSimulation.BOSS_WINDUP_TICKS, "", str(victim.uid))
	var announced := false
	for event in sim.event_log:
		if str(event.type) == BattleEvent.STATUS and str(event.extra.get("telegraph", "")) == "LOCK_ON" and (event.extra.get("cells", []) as Array).size() == 1: announced = true
	check(announced, "TEL_02 a telegraph announces the exact cells it will strike")
	var hp_before := int(victim.hp)
	for _index in range(BattleSimulation.BOSS_WINDUP_TICKS - 1): sim.tick()
	check(sim.pending_boss_casts.size() == 1, "TEL_03 the strike waits for its full wind-up")
	var hp_mid := int(victim.hp)
	for _index in range(3): sim.tick()
	var landed := false
	for event in sim.event_log:
		if str(event.type) == BattleEvent.DAMAGE and str(event.target) == str(victim.uid) and (event.extra.get("tags", []) as Array).has("AREA"): landed = true
	check(landed and sim.pending_boss_casts.is_empty(), "TEL_04 an ally still standing in the marked cell is hit")
	var area_damage := 0
	for event in sim.event_log:
		if str(event.type) == BattleEvent.DAMAGE and str(event.target) == str(victim.uid) and (event.extra.get("tags", []) as Array).has("AREA"): area_damage = int(event.value)
	check(area_damage >= int(float(victim.max_hp) * .32) and hp_before >= hp_mid, "TEL_05 a telegraphed hit never misses and adds a share of max HP")
	# Dodge: step out of the marked cell during the wind-up.
	var dodger: Dictionary = sim.state.party[1]
	var dodge_cells := [[int(dodger.col), int(dodger.lane)]]
	sim._announce_area_cast(boss, "LOCK_ON", "CELL", dodge_cells, 1.0, .32, BattleSimulation.BOSS_WINDUP_TICKS, "", str(dodger.uid))
	var free := []
	for col in BattleGrid.PLAYER_COLUMNS:
		for lane in range(BattleGrid.LANES):
			if free.is_empty() and sim.unit_at(int(col), lane).is_empty(): free = [int(col), lane]
	dodger.move_cd = 0.0
	sim.request_move(str(dodger.uid), int(free[0]), int(free[1]))
	var dodged_before := sim.dodged_hits
	var hit_after_move := false
	for _index in range(BattleSimulation.BOSS_WINDUP_TICKS + 2):
		var log_size := sim.event_log.size()
		sim.tick()
		for event in sim.event_log.slice(log_size):
			if str(event.type) == BattleEvent.DAMAGE and str(event.target) == str(dodger.uid) and (event.extra.get("tags", []) as Array).has("AREA"): hit_after_move = true
	check(not hit_after_move and sim.dodged_hits > dodged_before, "TEL_06 moving out of the marked cell dodges the strike")
	sim._announce_area_cast(boss, "IMPLODE", "PLUS", BattleGrid.shape_cells("PLUS", 1, 1, BattleGrid.PLAYER_COLUMNS), .72, .2, BattleSimulation.BOSS_WINDUP_TICKS)
	boss.statuses["STUN"] = {"remaining": 5.0, "source": "TEST", "strength": 0.0, "tick_left": 0.0, "tick_interval": 0.0, "stacks": 1, "dispellable": true}
	for _index in range(BattleSimulation.BOSS_WINDUP_TICKS + 1): sim.tick()
	var cancelled := false
	for event in sim.event_log:
		if str(event.type) == BattleEvent.STATUS and str(event.extra.get("telegraph_cancelled", "")) == "IMPLODE": cancelled = true
	check(cancelled and sim.pending_boss_casts.is_empty(), "TEL_07 stunning the caster cancels its wound-up strike")
	var shapes := {}
	for action in ["LOCK_ON", "IMPLODE", "RESONANCE", "OVERLOAD", "GATE_REVERSE", "RUPTURE", "CH03_SIGNATURE", "CH04_FINALE"]:
		shapes[BattleSimulation.boss_action_shape(action)] = true
	check(shapes.size() >= 6, "TEL_08 boss patterns use distinct area shapes to read and dodge")
	var placement := BattleGrid.best_shape_placement("LANE", BattleGrid.PLAYER_COLUMNS, sim.state.party)
	check(not placement.is_empty() and (placement.cells as Array).size() == 3, "TEL_09 a lane strike covers the three party columns of one lane")

func _test_growth_sync() -> void:
	var stage := DataRegistry.stage("CH02-N10")
	var profile := GrowthAdvisor.recommended_profile(stage)
	var party := AppState.create_party_snapshot()
	for member in party:
		member.progress.level = mini(100, int(profile.level) + 20)
	var synced := BattleSimulation.new()
	synced.setup(party, stage, 1, DataRegistry.data)
	var raw := BattleSimulation.new()
	raw.setup(party, stage, 1, DataRegistry.data, {"growth_sync": false})
	var base_party := AppState.create_party_snapshot()
	for member in base_party:
		member.progress.level = int(profile.level)
	var baseline := BattleSimulation.new()
	baseline.setup(base_party, stage, 1, DataRegistry.data)
	var synced_hp := float(synced.state.party[0].max_hp)
	var raw_hp := float(raw.state.party[0].max_hp)
	var base_hp := float(baseline.state.party[0].max_hp)
	check(synced_hp > base_hp and synced_hp < raw_hp, "SYNC_01 over-levelling still helps, but less than the raw stat gain")
	check(int(synced.state.party[0].level) < int(raw.state.party[0].level) and int(synced.state.party[0].true_level) == int(raw.state.party[0].level), "SYNC_02 the synced combat level sits between the recommendation and the real level")

func _test_auto_reserve() -> void:
	var sim := _simulation()
	var aoe_unit := {}
	var shield_unit := {}
	for unit in sim.state.party:
		var effect := str(DataRegistry.skill(str(unit.ultimate_skill_id)).get("effect", ""))
		if effect == "AOE_DAMAGE": aoe_unit = unit
		if effect == "SHIELD": shield_unit = unit
	check(not aoe_unit.is_empty() and not shield_unit.is_empty(), "AUTO_01 fixture party has an area and a shield ultimate")
	var aoe_cost := float(DataRegistry.skill(str(aoe_unit.ultimate_skill_id)).tactical_cost)
	var shield_cost := float(DataRegistry.skill(str(shield_unit.ultimate_skill_id)).tactical_cost)
	check(sim.alive_enemies().size() >= 2, "AUTO_02 fixture opens against a squad")
	# Pack the squad so one blast covers several enemies.
	var packed := [[3, 0], [3, 1], [4, 1], [4, 0], [3, 2]]
	for index in range(sim.state.enemies.size()):
		_place(sim.state.enemies[index], int(packed[index % packed.size()][0]), int(packed[index % packed.size()][1]))
	sim.state.tactical_gauge = aoe_cost + .1
	sim._auto_ultimate()
	check(int(aoe_unit.ultimate_uses) == 1, "AUTO_03 at full health the area ultimate still opens the fight at its cost")
	for unit in sim.state.party:
		unit.hp = int(unit.max_hp * .83)
	sim.state.party[4].hp = int(sim.state.party[4].max_hp * .5)
	for enemy in sim.state.enemies:
		enemy.hp = enemy.max_hp
		enemy.alive = true
	for index in range(sim.state.enemies.size()):
		if index >= 2:
			sim.state.enemies[index].alive = false
	sim.state.tactical_gauge = aoe_cost + .1
	sim._auto_ultimate()
	check(int(aoe_unit.ultimate_uses) == 1 and is_equal_approx(sim.state.tactical_gauge, aoe_cost + .1), "AUTO_03B once the party is hurt, the area ultimate keeps the shield's gauge in reserve")
	sim.state.tactical_gauge = aoe_cost + shield_cost + .1
	sim._auto_ultimate()
	check(int(shield_unit.ultimate_uses) == 1 and int(aoe_unit.ultimate_uses) == 1, "AUTO_04 a hurt, unshielded party gets the shield before more area damage")
	for unit in sim.state.party:
		unit.shields = {"TEST": 999999}
		unit.shield = 999999
	sim.state.tactical_gauge = aoe_cost + shield_cost + .1
	sim._auto_ultimate()
	check(int(aoe_unit.ultimate_uses) == 2 and sim.state.tactical_gauge >= shield_cost, "AUTO_04B once shielded, the area ultimate fires and still leaves the shield affordable")
	for unit in sim.state.party:
		unit.hp = unit.max_hp
		unit.shields = {}
		unit.shield = 0
	var shield_uses_before := int(shield_unit.ultimate_uses)
	sim.pending_boss_casts.append({"due_tick": sim.state.tick + 30, "boss_uid": str(sim.state.enemies[0].uid), "action": "LOCK_ON", "target_uid": "", "multiplier": 1.0, "cells": [[1, 1]], "hp_ratio": .3, "shape": "CELL", "label": "", "windup_ticks": 30})
	sim.state.tactical_gauge = shield_cost + .1
	sim._auto_ultimate()
	check(int(shield_unit.ultimate_uses) == shield_uses_before + 1, "AUTO_05 AUTO raises the shield against a telegraphed attack")

func _test_ultimate_target_resolution() -> void:
	var sim := _simulation()
	var caster := {}
	for unit in sim.state.party:
		if str(DataRegistry.skill(str(unit.ultimate_skill_id)).get("effect", "")) == "DAMAGE":
			caster = unit
			break
	var cost := float(DataRegistry.skill(str(caster.ultimate_skill_id)).tactical_cost)
	var dead_target: Dictionary = sim.state.enemies[0]
	dead_target.alive = false
	dead_target.hp = 0
	sim.state.tactical_gauge = 10.0
	check(sim._use_ultimate(caster, str(dead_target.uid)) and is_equal_approx(sim.state.tactical_gauge, 10.0 - cost), "ULT_01 a dead manual target falls back to a live enemy")
	var hit_live := false
	for event in sim.event_log:
		if str(event.type) == BattleEvent.DAMAGE and str(event.source) == str(caster.uid) and str(event.target) != str(dead_target.uid): hit_live = true
	check(hit_live, "ULT_02 the fallback cast damages a surviving enemy")
	var far_enemy: Dictionary = sim.state.enemies[1]
	_place(far_enemy, 5, 2)
	sim.state.tactical_gauge = 10.0
	var log_size := sim.event_log.size()
	sim._use_ultimate(caster, str(far_enemy.uid))
	var hit_far := false
	for event in sim.event_log.slice(log_size):
		if str(event.type) == BattleEvent.DAMAGE and str(event.target) == str(far_enemy.uid): hit_far = true
	check(hit_far, "ULT_03 ultimates reach any enemy on the field, whatever the caster's weapon reach")
	for enemy in sim.state.enemies:
		enemy.alive = false
		enemy.hp = 0
	var gauge_before := sim.state.tactical_gauge
	check(not sim._use_ultimate(caster, "") and is_equal_approx(sim.state.tactical_gauge, gauge_before), "ULT_04 with no valid target the cast is refused and no gauge is spent")
	var area := _simulation("CH01-N05")
	var packed := [[3, 0], [3, 1], [4, 1], [5, 2], [5, 0]]
	for index in range(area.state.enemies.size()):
		_place(area.state.enemies[index], int(packed[index % packed.size()][0]), int(packed[index % packed.size()][1]))
	var best := area.best_area_target()
	check(area._units_in_cells(area.state.enemies, BattleSimulation.ultimate_area_cells(best)).size() >= 2, "ULT_05 the suggested blast centre covers the packed enemies")

func _test_level_scaled_buffs() -> void:
	var skill := DataRegistry.skill("SK_CHR007_ULTIMATE")
	var ratio := SkillRuntime.value_at(skill, 5) / SkillRuntime.value_at(skill, 1)
	check(ratio > 1.5, "BUFF_01 the buff ultimate's level curve grows")
	var fast := {"statuses": {"HASTE": {"strength": .34}}}
	var legacy := {"statuses": {"HASTE": {"strength": 0.0}}}
	check(is_equal_approx(UnitState.status_strength(fast, "HASTE", .2), .34) and is_equal_approx(UnitState.status_strength(legacy, "HASTE", .2), .2), "BUFF_02 HASTE uses its strength, legacy strength-less statuses keep the old value")
	var attacker := {"stats": {"ATK": 1000, "ACC": 900, "CRIT": 0}, "level": 10, "attack_type": "PHYSICAL", "outgoing_modifier": 1.0, "statuses": {}}
	var armored := {"stats": {"DEF": 700, "EVA": 0, "CRIT_RES": 2000}, "level": 10, "defense_type": "ARMOR", "incoming_modifier": 1.0, "statuses": {"DEF_DOWN": {"strength": .25}}}
	var shredded := armored.duplicate(true)
	shredded.statuses.DEF_DOWN.strength = .4
	var weak := DamageResolver.calculate(attacker, armored, 1.0, DataRegistry.data.affinity_matrix, DeterministicRng.new(9))
	var strong := DamageResolver.calculate(attacker, shredded, 1.0, DataRegistry.data.affinity_matrix, DeterministicRng.new(9))
	check(bool(weak.hit) and bool(strong.hit) and float(strong.defense_factor) > float(weak.defense_factor), "BUFF_03 a stronger DEF_DOWN lowers defence further")
	var plain := DamageResolver.calculate(attacker, armored, 1.0, DataRegistry.data.affinity_matrix, DeterministicRng.new(9), 1.0)
	var flanked := DamageResolver.calculate(attacker, armored, 1.0, DataRegistry.data.affinity_matrix, DeterministicRng.new(9), 1.3)
	check(int(flanked.amount) > int(plain.amount), "BUFF_04 positional factors scale the resolved damage")

func _test_boss_phase() -> void:
	var sim := _boss_sim()
	var boss := _boss_of(sim)
	if boss.is_empty():
		check(false, "BOSS_01 fixture reaches the boss wave")
		return
	var phase_attack_interval := float(boss.attack_interval)
	boss.hp = int(boss.max_hp * .5)
	sim.tick()
	check(str(boss.phase) == "PHASE_2" and float(boss.outgoing_modifier) > 1.0 and float(boss.attack_interval) < phase_attack_interval, "BOSS_02 phase two raises boss damage and attack speed")
	var fresh := _boss_sim()
	var fresh_boss := _boss_of(fresh)
	fresh_boss.max_hp = 99999999
	fresh_boss.hp = 99999999
	var casts := 0
	for _index in range(int((18.0 + BattleSimulation.BOSS_PATTERN_REPEAT + 2.0) * 30.0)):
		var log_size := fresh.event_log.size()
		fresh.tick()
		for event in fresh.event_log.slice(log_size):
			if str(event.type) == BattleEvent.STATUS and not str(event.extra.get("telegraph", "")).is_empty() and str(event.source) == str(fresh_boss.uid): casts += 1
	check(casts >= 2, "BOSS_03 timed boss strikes repeat, so the dodge has to be read more than once")

func _test_same_tick_victory() -> void:
	var sim := _simulation()
	while sim.wave_director.has_next():
		for enemy in sim.state.enemies:
			enemy.hp = 0
			enemy.alive = false
		sim.tick()
	sim.state.tick = int(sim.state.time_limit / BattleSimulation.TICK_DELTA)
	sim.state.time_elapsed = sim.state.time_limit
	for enemy in sim.state.enemies:
		enemy.hp = 0
		enemy.alive = false
	sim._check_flow()
	check(sim.state.ended and sim.state.victory and str(sim.state.reason) == "ALL_WAVES_CLEARED", "FLOW_01 a final kill on the timeout tick is a victory")

const ROLE_STAGE := "CH02-N10"

func _role_unit(sim: BattleSimulation, role: String) -> Dictionary:
	var unit: Dictionary = sim.state.enemies[0]
	unit.role = role
	unit.rank = "NORMAL"
	return unit

func _test_enemy_role_skills() -> void:
	check(_simulation("CH01-N03").enemy_role_potency() == 0.0 and _simulation("CH01-N04").enemy_role_potency() > 0.0 and _simulation(ROLE_STAGE).enemy_role_potency() > 0.0, "ROLE_00 enemy role skills begin after the three tutorial operations")
	var sim := _simulation(ROLE_STAGE)
	var healer := _role_unit(sim, "HEALER")
	var patient: Dictionary = sim.state.enemies[1]
	patient.hp = int(patient.max_hp * .4)
	var before_hp := int(patient.hp)
	check(sim._use_enemy_role_skill(healer, {}) and int(patient.hp) > before_hp, "ROLE_01 an enemy healer mends its most wounded ally")
	patient.hp = patient.max_hp
	healer.hp = healer.max_hp
	check(not sim._use_enemy_role_skill(healer, {}) and float(healer.normal_cd) < 2.0, "ROLE_02 a healer with nobody hurt holds its skill and retries soon")
	sim = _simulation(ROLE_STAGE)
	var defender := _role_unit(sim, "DEFENDER")
	check(sim._use_enemy_role_skill(defender, {}) and int(defender.shield) > 0, "ROLE_03 an enemy defender raises a barrier")
	sim = _simulation(ROLE_STAGE)
	var buffer := _role_unit(sim, "BUFFER")
	sim._use_enemy_role_skill(buffer, {})
	check(UnitState.has_status(sim.state.enemies[1], "HASTE"), "ROLE_04 an enemy buffer hastes its allies")
	sim = _simulation(ROLE_STAGE)
	var debuffer := _role_unit(sim, "DEBUFFER")
	sim._use_enemy_role_skill(debuffer, sim.state.party[0])
	check(UnitState.has_status(sim.state.party[0], "ATK_DOWN"), "ROLE_05 an enemy debuffer weakens the ally it targets")
	check(not sim._use_enemy_role_skill(_role_unit(_simulation(ROLE_STAGE), "DEBUFFER"), {}), "ROLE_05B with nobody in reach the debuffer holds its skill")
	sim = _simulation(ROLE_STAGE)
	var area := _role_unit(sim, "AREA")
	_place(area, 3, 1)
	var log_size := sim.event_log.size()
	var hp_before := 0
	for unit in sim.state.party: hp_before += int(unit.hp)
	sim._use_enemy_role_skill(area, {})
	var telegraph := false
	var instant_hit := false
	for event in sim.event_log.slice(log_size):
		if str(event.type) == BattleEvent.STATUS and str(event.extra.get("shape", "")) == "PLUS": telegraph = true
		if str(event.type) == BattleEvent.DAMAGE and str(event.source) == str(area.uid): instant_hit = true
	check(telegraph and not instant_hit and sim.pending_boss_casts.size() == 1 and int(sim.pending_boss_casts[0].windup_ticks) == BattleSimulation.ENEMY_AREA_WINDUP_TICKS, "ROLE_06 an area enemy marks a cross of cells instead of hitting the whole party at once")
	var skill_event := false
	for event in sim.event_log.slice(log_size):
		if str(event.type) == BattleEvent.NORMAL_SKILL and not str(event.extra.get("label", "")).is_empty(): skill_event = true
	check(skill_event, "ROLE_07 role skills emit a named skill event for the battle view")
	sim = _simulation(ROLE_STAGE)
	var elite: Dictionary = sim.state.enemies[0]
	elite.rank = "ELITE"
	elite.strike_cd = 0.0
	sim.pending_boss_casts.clear()
	sim._tick_unit(elite)
	var strike: Dictionary = sim.pending_boss_casts[0] if not sim.pending_boss_casts.is_empty() else {}
	check(str(strike.get("action", "")) == "ENEMY_ELITE_STRIKE" and int(strike.get("windup_ticks", 0)) == BattleSimulation.ENEMY_AREA_WINDUP_TICKS and float(elite.strike_cd) > 5.0, "ROLE_08 an elite telegraphs a heavy strike on the party's side and then waits")
	var tutorial := _simulation("CH01-N02")
	var tutorial_elite: Dictionary = tutorial.state.enemies[0]
	tutorial_elite.rank = "ELITE"
	tutorial_elite.strike_cd = 0.0
	tutorial._tick_unit(tutorial_elite)
	check(tutorial.pending_boss_casts.is_empty(), "ROLE_09 the tutorial operations have no elite strikes")

func _test_tactical_policy() -> void:
	var stage := DataRegistry.stage("CH01-N20")
	var party := AppState.create_party_snapshot()
	var formation := TacticalPolicy.formation_for(party, stage, DataRegistry.data)
	var front_ok := true
	for member in party:
		if str(member.role) in ["GUARDIAN", "VANGUARD"]:
			front_ok = front_ok and int(formation[str(member.id)][0]) == BattleGrid.PLAYER_FRONT
	check(front_ok and formation.size() == party.size(), "TAC_01 the reference tactician puts guardians and vanguards on the front row")
	var sim := _boss_sim()
	var boss := _boss_of(sim)
	boss.patterns = []
	sim.pending_boss_casts.clear()
	var victim: Dictionary = sim.state.party[2]
	victim.move_cd = 0.0
	sim._announce_area_cast(boss, "LOCK_ON", "CELL", [[int(victim.col), int(victim.lane)]], 1.0, .32, BattleSimulation.BOSS_WINDUP_TICKS, "", str(victim.uid))
	var start := [int(victim.col), int(victim.lane)]
	for _index in range(TacticalPolicy.REACTION_TICKS + 3):
		TacticalPolicy.react(sim)
		sim.tick()
	check([int(victim.col), int(victim.lane)] != start, "TAC_02 the reference tactician steps out of a marked cell after its reaction delay")

func _test_determinism() -> void:
	var left := _simulation("CH01-N20", 20260924)
	var right := _simulation("CH01-N20", 20260924)
	for sim in [left, right]:
		while not sim.state.ended and sim.state.tick < 4000:
			if sim.state.tick == 45: sim.request_move(str(sim.state.party[4].uid), 0, 0)
			if sim.state.tick == 60: sim.request_focus(str(sim.state.enemies[0].uid))
			sim.tick()
	check(JSON.stringify(left.event_log).sha256_text() == JSON.stringify(right.event_log).sha256_text() and left.event_hash() == right.event_hash(), "DET_01 the same seed, party and commands replay identically")
