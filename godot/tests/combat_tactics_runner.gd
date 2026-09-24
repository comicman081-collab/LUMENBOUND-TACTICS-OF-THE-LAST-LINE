extends Node

## Combat rules that make formation and timing matter: row-weighted enemy
## targeting, AUTO gauge reservation, target-checked ultimates, level-scaled
## buffs, boss wind-ups, phase escalation and same-tick victory.

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
	_test_row_targeting()
	_test_auto_reserve()
	_test_ultimate_target_resolution()
	_test_level_scaled_buffs()
	_test_boss_windup()
	_test_same_tick_victory()
	_test_enemy_role_skills()
	_test_determinism()
	print("COMBAT_TACTICS total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _simulation(stage_id := "CH01-N01", seed_value := 4242) -> BattleSimulation:
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage(stage_id), seed_value, DataRegistry.data)
	return sim

func _even_party(sim: BattleSimulation) -> void:
	for unit in sim.state.party:
		unit.threat = 1.0
		unit.hp = unit.max_hp

func _test_row_targeting() -> void:
	var sim := _simulation()
	_even_party(sim)
	var melee := {"team": "ENEMY", "role": "MELEE_RUSH", "rank": "NORMAL", "statuses": {}}
	var ranged := {"team": "ENEMY", "role": "RANGED", "rank": "NORMAL", "statuses": {}}
	check(int(TargetResolver.choose(melee, sim.state.party).slot) == 0, "ROW_01 melee enemies strike the front row when threat and HP are equal")
	sim.state.party[0].alive = false
	sim.state.party[1].alive = false
	check(int(TargetResolver.choose(melee, sim.state.party).slot) in [2, 3], "ROW_02 with the front row down, melee enemies reach the middle row next")
	sim.state.party[0].alive = true
	sim.state.party[1].alive = true
	var melee_back := TargetResolver.enemy_priority(sim.state.party[4], TargetResolver.ROW_WEIGHT_MELEE) / TargetResolver.enemy_priority(sim.state.party[0], TargetResolver.ROW_WEIGHT_MELEE)
	var ranged_back := TargetResolver.enemy_priority(sim.state.party[4], TargetResolver.ROW_WEIGHT_RANGED) / TargetResolver.enemy_priority(sim.state.party[0], TargetResolver.ROW_WEIGHT_RANGED)
	check(ranged_back > melee_back and melee_back < .5, "ROW_03 ranged enemies threaten the back row far more than melee enemies")
	sim.state.party[0].hp = int(sim.state.party[0].max_hp * .7)
	sim.state.party[1].alive = false
	check(int(TargetResolver.choose(melee, sim.state.party).slot) == 0, "ROW_04 a lightly wounded front-liner keeps melee aggro over healthy rear rows")
	sim.state.party[0].hp = int(sim.state.party[0].max_hp * .3)
	check(int(TargetResolver.choose(melee, sim.state.party).slot) in [2, 3], "ROW_04B a badly wounded front-liner hands pressure to the middle row, not the back")
	var tie_a := TargetResolver.choose(ranged, sim.state.party)
	var tie_b := TargetResolver.choose(ranged, sim.state.party.duplicate())
	check(str(tie_a.uid) == str(tie_b.uid), "ROW_05 targeting ties resolve by slot, independent of array order")

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
	check(sim.alive_enemies().size() == 2, "AUTO_02 fixture opens against two enemies")
	sim.state.tactical_gauge = aoe_cost + .1
	sim._auto_ultimate()
	check(int(aoe_unit.ultimate_uses) == 1, "AUTO_03 at full health the area ultimate still opens the fight at its cost")
	# Wounded party (average ~76%, nobody low enough for the shield rule).
	for unit in sim.state.party:
		unit.hp = int(unit.max_hp * .83)
	sim.state.party[4].hp = int(sim.state.party[4].max_hp * .5)
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
	sim.pending_boss_casts.append({"due_tick": sim.state.tick + 30, "boss_uid": str(sim.state.enemies[0].uid), "action": "LOCK_ON", "target_uid": "", "multiplier": 1.0})
	sim.state.tactical_gauge = shield_cost + .1
	sim._auto_ultimate()
	check(int(shield_unit.ultimate_uses) == shield_uses_before + 1, "AUTO_05 AUTO raises the shield against a telegraphed boss attack")

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
		if str(event.type) == BattleEvent.DAMAGE and str(event.source) == str(caster.uid) and str(event.target) == str(sim.state.enemies[1].uid): hit_live = true
	check(hit_live, "ULT_02 the fallback cast damages the surviving enemy")
	for enemy in sim.state.enemies:
		enemy.alive = false
		enemy.hp = 0
	var gauge_before := sim.state.tactical_gauge
	check(not sim._use_ultimate(caster, "") and is_equal_approx(sim.state.tactical_gauge, gauge_before), "ULT_03 with no valid target the cast is refused and no gauge is spent")

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

func _test_boss_windup() -> void:
	var sim := _simulation("CH01-N20", 777)
	while sim.state.wave < 3 and not sim.state.ended and sim.state.tick < 6000:
		for enemy in sim.state.enemies:
			enemy.hp = 0
			enemy.alive = false
		sim.tick()
	var boss := {}
	for enemy in sim.state.enemies:
		if str(enemy.rank) == "BOSS": boss = enemy
	check(not boss.is_empty(), "BOSS_01 fixture reaches the boss wave")
	if boss.is_empty(): return
	for unit in sim.state.party:
		unit.max_hp = 999999
		unit.hp = 999999
	var phase_attack_interval := float(boss.attack_interval)
	boss.hp = int(boss.max_hp * .5)
	sim.tick()
	check(str(boss.phase) == "PHASE_2" and float(boss.outgoing_modifier) > 1.0 and float(boss.attack_interval) < phase_attack_interval, "BOSS_02 phase two raises boss damage and attack speed")
	sim.pending_boss_casts.clear()
	sim._announce_boss_cast(boss, "IMPLODE", "", .72)
	var party_hp_before := 0
	for unit in sim.state.party: party_hp_before += int(unit.hp)
	var announced_tick := sim.state.tick
	var hit_early := false
	for _index in range(BattleSimulation.BOSS_WINDUP_TICKS - 1):
		var log_size := sim.event_log.size()
		sim.tick()
		for event in sim.event_log.slice(log_size):
			if str(event.type) == BattleEvent.ULTIMATE and str(event.extra.get("boss_pattern", "")) == "IMPLODE": hit_early = true
	check(not hit_early and sim.pending_boss_casts.size() == 1, "BOSS_03 a telegraphed attack waits for its two-second wind-up")
	var landed := false
	for _index in range(3):
		var log_size := sim.event_log.size()
		sim.tick()
		for event in sim.event_log.slice(log_size):
			if str(event.type) == BattleEvent.ULTIMATE and str(event.extra.get("boss_pattern", "")) == "IMPLODE": landed = true
	check(landed and sim.pending_boss_casts.is_empty() and sim.state.tick >= announced_tick + BattleSimulation.BOSS_WINDUP_TICKS, "BOSS_04 the attack lands when the wind-up ends")
	sim._announce_boss_cast(boss, "IMPLODE", "", .72)
	boss.statuses["STUN"] = {"remaining": 5.0, "source": "TEST", "strength": 0.0, "tick_left": 0.0, "tick_interval": 0.0, "stacks": 1, "dispellable": true}
	for _index in range(BattleSimulation.BOSS_WINDUP_TICKS + 1): sim.tick()
	var cancelled := false
	for event in sim.event_log:
		if str(event.type) == BattleEvent.STATUS and str(event.extra.get("telegraph_cancelled", "")) == "IMPLODE": cancelled = true
	check(cancelled and sim.pending_boss_casts.is_empty(), "BOSS_05 stunning the boss cancels its wound-up attack")

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
	# Role skills start in chapter 2; chapter 1 keeps the introductory behaviour.
	check(_simulation("CH01-N06").enemy_role_potency() == 0.0 and _simulation(ROLE_STAGE).enemy_role_potency() > 0.0, "ROLE_00 enemy role skills begin after the chapter 1 introduction")
	var sim := _simulation(ROLE_STAGE)
	var healer := _role_unit(sim, "HEALER")
	var patient: Dictionary = sim.state.enemies[1]
	patient.hp = int(patient.max_hp * .4)
	var before_hp := int(patient.hp)
	check(sim._use_enemy_role_skill(healer) and int(patient.hp) > before_hp, "ROLE_01 an enemy healer mends its most wounded ally")
	patient.hp = patient.max_hp
	healer.hp = healer.max_hp
	check(not sim._use_enemy_role_skill(healer) and float(healer.normal_cd) < 2.0, "ROLE_02 a healer with nobody hurt holds its skill and retries soon")
	sim = _simulation(ROLE_STAGE)
	var defender := _role_unit(sim, "DEFENDER")
	check(sim._use_enemy_role_skill(defender) and int(defender.shield) > 0, "ROLE_03 an enemy defender raises a barrier")
	sim = _simulation(ROLE_STAGE)
	var buffer := _role_unit(sim, "BUFFER")
	sim._use_enemy_role_skill(buffer)
	check(UnitState.has_status(sim.state.enemies[1], "HASTE"), "ROLE_04 an enemy buffer hastes its allies")
	sim = _simulation(ROLE_STAGE)
	var debuffer := _role_unit(sim, "DEBUFFER")
	sim._use_enemy_role_skill(debuffer)
	var weakened := false
	for unit in sim.state.party:
		if UnitState.has_status(unit, "ATK_DOWN"): weakened = true
	check(weakened, "ROLE_05 an enemy debuffer weakens the ally it targets")
	sim = _simulation(ROLE_STAGE)
	var area := _role_unit(sim, "AREA")
	var log_size := sim.event_log.size()
	sim._use_enemy_role_skill(area)
	var hit := {}
	for event in sim.event_log.slice(log_size):
		if str(event.type) == BattleEvent.DAMAGE and str(event.source) == str(area.uid): hit[str(event.target)] = true
	check(hit.size() == sim.state.party.size(), "ROLE_06 an area enemy strikes the whole party")
	var skill_event := false
	for event in sim.event_log.slice(log_size):
		if str(event.type) == BattleEvent.NORMAL_SKILL and not str(event.extra.get("label", "")).is_empty(): skill_event = true
	check(skill_event, "ROLE_07 role skills emit a named skill event for the battle view")

func _test_determinism() -> void:
	var left := _simulation("CH01-N20", 20260924)
	var right := _simulation("CH01-N20", 20260924)
	while not left.state.ended and left.state.tick < 4000: left.tick()
	while not right.state.ended and right.state.tick < 4000: right.tick()
	check(JSON.stringify(left.event_log).sha256_text() == JSON.stringify(right.event_log).sha256_text(), "DET_01 the same seed and party still replay identically")
