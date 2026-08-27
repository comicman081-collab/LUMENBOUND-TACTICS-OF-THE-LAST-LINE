class_name BattleSimulation
extends RefCounted

const TICK_DELTA := 1.0 / 30.0
var state := BattleState.new()
var rng := DeterministicRng.new(1)
var data: Dictionary = {}
var stage: Dictionary = {}
var wave_director := WaveDirector.new()
var event_log: Array = []
var command_log: Array = []
var command_queue: Array = []
var seed := 1
var auto_enabled := true
var auto_decision_tick := 0
var damage_by_character: Dictionary = {}
var healing_by_character: Dictionary = {}
var deaths: Array = []
var options: Dictionary = {}
var event_hasher := HashingContext.new()
var event_hash_cache := ""

func setup(party_snapshot: Array, stage_definition: Dictionary, seed_value: int, all_data: Dictionary, setup_options: Dictionary = {}) -> void:
	seed = seed_value
	rng = DeterministicRng.new(seed)
	data = all_data
	stage = stage_definition.duplicate(true)
	options = setup_options.duplicate(true)
	state = BattleState.new()
	state.time_limit = float(stage.get("time_limit", 90))
	state.wave_count = stage.get("waves", []).size()
	state.party = []
	state.enemies = []
	event_log.clear()
	command_log.clear()
	command_queue.clear()
	damage_by_character.clear()
	healing_by_character.clear()
	deaths.clear()
	event_hash_cache = ""
	event_hasher = HashingContext.new()
	event_hasher.start(HashingContext.HASH_SHA256)
	wave_director.setup(stage.get("waves", []))
	for i in range(party_snapshot.size()):
		state.party.append(_make_player(party_snapshot[i], i))
	_spawn_next_wave()

func _make_player(definition: Dictionary, slot: int) -> Dictionary:
	var progress: Dictionary = definition.get("progress", {})
	var level := int(progress.get("level", 1))
	var stats := _scaled_character_stats(definition, level, int(progress.get("breakthrough", 0)))
	var weapon_id := str(progress.get("equipped_weapon_id", ""))
	var weapon_stats := WeaponUpgradeService.flat_stats_for(weapon_id, progress.get("weapon_state", {}))
	for key in weapon_stats:
		stats[key] = int(stats.get(key, 0)) + int(weapon_stats[key])
	var passive := _skill(definition.passive_skill_id)
	var passive_level := int(progress.get("skills", {}).get("passive", 1))
	var passive_bonus := SkillRuntime.value_at(passive, passive_level)
	if definition.role == "GUARDIAN":
		stats.HP = MathUtil.round_half_up(float(stats.HP) * (1.0 + passive_bonus))
	elif definition.role == "MEDIC":
		stats.HEAL_POWER = MathUtil.round_half_up(float(stats.HEAL_POWER) * (1.0 + passive_bonus))
	else:
		stats.ATK = MathUtil.round_half_up(float(stats.ATK) * (1.0 + passive_bonus))
	var hp := int(stats.HP)
	return {"uid": "P:%s" % definition.id, "def_id": definition.id, "team": "PLAYER", "rank": "PLAYER", "role": definition.role, "attack_type": definition.attack_type, "defense_type": definition.defense_type, "level": level, "stats": stats, "hp": hp, "max_hp": hp, "shield": 0, "shields": {}, "alive": true, "x": [2.0, 2.5, 4.3, 4.8, 6.6][slot], "slot": slot, "attack_cd": float(definition.attack_interval) * (0.85 + slot * .02), "normal_cd": 2.0 + slot * .6, "statuses": {}, "threat": float(definition.threat_modifier), "outgoing_modifier": 1.0, "incoming_modifier": 1.0, "healing_done_modifier": 1.0, "normal_skill_id": definition.normal_skill_id, "ultimate_skill_id": definition.ultimate_skill_id, "skill_levels": progress.get("skills", {"normal": 1, "passive": 1, "ultimate": 1}), "attack_interval": float(definition.attack_interval), "state": "IDLE", "ultimate_uses": 0}

func _make_enemy(enemy_id: String, index: int) -> Dictionary:
	var definition := _enemy(enemy_id)
	var level := int(stage.get("recommended_level", 1))
	var base_stats: Dictionary = definition.get("stats", {}).duplicate(true)
	var scale := (1.0 + 0.065 * maxf(0, level - 1)) * float(stage.get("post_cap_scale", 1.0)) * float(options.get("enemy_multiplier", 1.0))
	if definition.get("rank", "NORMAL") == "ELITE":
		scale *= 1.05
	for key in base_stats:
		base_stats[key] = MathUtil.round_half_up(float(base_stats[key]) * scale)
	var hp := int(base_stats.get("HP", 1))
	return {"uid": "E:%d:%d:%s" % [state.wave, index, enemy_id], "def_id": enemy_id, "team": "ENEMY", "rank": definition.get("rank", "NORMAL"), "role": definition.get("role", "RANGED"), "attack_type": definition.get("attack_type", "PHYSICAL"), "defense_type": definition.get("defense_type", "ARMOR"), "level": level, "stats": base_stats, "hp": hp, "max_hp": hp, "shield": 0, "shields": {}, "alive": true, "x": 12.0 + index * .55, "slot": index, "attack_cd": .8 + index * .12, "normal_cd": 5.0 + index * .4, "statuses": {}, "threat": 1.0, "outgoing_modifier": 1.0, "incoming_modifier": 1.0, "healing_done_modifier": 1.0, "attack_interval": float(definition.get("attack_interval", 1.45)), "state": "IDLE", "phase": "PHASE_1" if definition.get("rank", "NORMAL") == "BOSS" else "", "patterns": definition.get("patterns", []).duplicate(true), "pattern_triggers": {}, "ultimate_uses": 0}

func _scaled_character_stats(definition: Dictionary, level: int, breakthrough: int) -> Dictionary:
	var level_curve: Array = data.get("character_level_curve", [])
	var curve := float(level_curve[clampi(level - 1, 0, level_curve.size() - 1)].curve) if not level_curve.is_empty() else 0.0
	var multipliers := [1.0, 1.02, 1.04, 1.07, 1.10, 1.14]
	var stats: Dictionary = {}
	for key in definition.stats_l1:
		var base := float(definition.stats_l1[key]) + (float(definition.stats_l100.get(key, definition.stats_l1[key])) - float(definition.stats_l1[key])) * curve
		stats[key] = MathUtil.round_half_up(base * multipliers[clampi(breakthrough, 0, 5)])
	return stats

func request_ultimate(unit_id: String, target_unit_id := "") -> void:
	var command := BattleCommand.ultimate(state.tick, unit_id, target_unit_id)
	command_queue.append(command)
	command_log.append(command.duplicate(true))

func tick() -> void:
	if state.ended:
		return
	state.tick += 1
	state.time_elapsed = state.tick * TICK_DELTA
	state.tactical_gauge = minf(10.0, state.tactical_gauge + .40 * TICK_DELTA)
	_update_statuses()
	_process_commands()
	if auto_enabled and state.tick >= auto_decision_tick:
		auto_decision_tick = state.tick + 30
		_auto_ultimate()
	for unit in state.party + state.enemies:
		_tick_unit(unit)
	_check_flow()

func advance_to_terminal(max_additional_ticks := -1) -> bool:
	## Resolve the remaining live battle through the exact same deterministic
	## 30 Hz simulation used by normal play.  This is presentation skip, not a
	## fabricated victory: current HP, RNG, queued commands and AUTO policy stay
	## authoritative, so defeat and timeout remain possible.
	if state.ended:
		return true
	var remaining_limit_ticks := ceili(maxf(0.0, state.time_limit - state.time_elapsed) / TICK_DELTA) + 2
	var budget := remaining_limit_ticks if max_additional_ticks < 0 else maxi(0, max_additional_ticks)
	for _index in range(budget):
		if state.ended:
			break
		tick()
	return state.ended

func _tick_unit(unit: Dictionary) -> void:
	if not UnitState.alive(unit) or UnitState.has_status(unit, "STUN"):
		return
	if unit.rank == "BOSS": _tick_boss_patterns(unit)
	unit.attack_cd = float(unit.attack_cd) - TICK_DELTA * (1.2 if UnitState.has_status(unit, "HASTE") else (0.7 if UnitState.has_status(unit, "SLOW") else 1.0))
	unit.normal_cd = float(unit.normal_cd) - TICK_DELTA
	if float(unit.normal_cd) <= 0 and unit.team == "PLAYER":
		_use_normal(unit)
		return
	if float(unit.attack_cd) <= 0:
		_basic_attack(unit)
		unit.attack_cd = float(unit.attack_interval)

func _basic_attack(attacker: Dictionary) -> void:
	var targets := state.enemies if attacker.team == "PLAYER" else state.party
	var target := TargetResolver.choose(attacker, targets)
	if target.is_empty():
		return
	_emit(BattleEvent.make(state.tick, BattleEvent.BASIC_ATTACK, attacker.uid, target.uid))
	_deal_damage(attacker, target, 1.0, "BASIC")

func _use_normal(caster: Dictionary) -> void:
	var skill := _skill(caster.normal_skill_id)
	var level := int(caster.skill_levels.get("normal", 1))
	var coefficient := SkillRuntime.value_at(skill, level)
	var effect := str(skill.get("effect", "DAMAGE"))
	caster.normal_cd = float(skill.get("cooldown", 8.0))
	_emit(BattleEvent.make(state.tick, BattleEvent.NORMAL_SKILL, caster.uid, "", 0, {"skill_id": skill.id}))
	if effect == "HEAL":
		_heal(caster, TargetResolver.lowest_hp(state.party), coefficient)
	elif effect == "SHIELD":
		_apply_shield(caster, TargetResolver.lowest_hp(state.party), coefficient)
	elif effect == "TAUNT":
		_apply_shield(caster, caster, coefficient * .8)
		for enemy in state.enemies:
			if UnitState.alive(enemy): StatusEffectRuntime.apply(enemy, "TAUNT", 4.0, caster.uid)
	elif effect == "AOE_DAMAGE":
		for enemy in state.enemies:
			if UnitState.alive(enemy): _deal_damage(caster, enemy, coefficient * .62, "NORMAL")
	else:
		var target := TargetResolver.choose(caster, state.enemies)
		if not target.is_empty():
			_deal_damage(caster, target, coefficient, "NORMAL")
			if effect == "SLOW": StatusEffectRuntime.apply(target, "SLOW", 3.0, caster.uid, .3)

func _use_ultimate(caster: Dictionary, target_unit_id := "") -> bool:
	var skill := _skill(caster.ultimate_skill_id)
	if not SkillRuntime.can_use_ultimate(caster, skill, state.tactical_gauge):
		return false
	state.tactical_gauge -= float(skill.tactical_cost)
	caster.ultimate_uses = int(caster.ultimate_uses) + 1
	var coefficient := SkillRuntime.value_at(skill, int(caster.skill_levels.get("ultimate", 1)))
	var effect := str(skill.effect)
	_emit(BattleEvent.make(state.tick, BattleEvent.ULTIMATE, caster.uid, "", int(skill.tactical_cost), {"skill_id": skill.id}))
	if effect == "HEAL":
		for ally in state.party:
			if UnitState.alive(ally): _heal(caster, ally, coefficient * .72)
	elif effect == "SHIELD":
		for ally in state.party:
			if UnitState.alive(ally): _apply_shield(caster, ally, coefficient)
	elif effect == "BUFF":
		for ally in state.party:
			if UnitState.alive(ally): StatusEffectRuntime.apply(ally, "HASTE", 7.0, caster.uid, .2)
	elif effect == "DEBUFF":
		var debuff_target := find_unit(target_unit_id) if not target_unit_id.is_empty() else TargetResolver.choose(caster, state.enemies)
		if not debuff_target.is_empty() and UnitState.alive(debuff_target): StatusEffectRuntime.apply(debuff_target, "DEF_DOWN", 7.0, caster.uid, .25)
	elif effect == "AOE_DAMAGE":
		for enemy in state.enemies:
			if UnitState.alive(enemy): _deal_damage(caster, enemy, coefficient * .82, "ULTIMATE")
	else:
		var target := find_unit(target_unit_id) if not target_unit_id.is_empty() else TargetResolver.choose(caster, state.enemies)
		if not target.is_empty() and (target.team != "ENEMY" or not UnitState.alive(target)): target = {}
		if not target.is_empty(): _deal_damage(caster, target, coefficient, "ULTIMATE")
	return true

func _deal_damage(attacker: Dictionary, target: Dictionary, coefficient: float, source: String) -> void:
	if not UnitState.alive(target) or state.ended:
		return
	if UnitState.has_status(target, "INVULNERABLE"):
		_emit(BattleEvent.make(state.tick, BattleEvent.DAMAGE, attacker.uid, target.uid, 0, {"invulnerable": true, "source": source}))
		return
	var resolved := DamageResolver.calculate(attacker, target, coefficient, data.affinity_matrix, rng)
	if not resolved.hit:
		_emit(BattleEvent.make(state.tick, BattleEvent.DAMAGE, attacker.uid, target.uid, 0, {"miss": true, "source": source}))
		return
	var amount := int(resolved.amount)
	if options.get("invincible", false) and target.team == "PLAYER": amount = 0
	var shield_damage := mini(amount, int(target.shield))
	if shield_damage > 0:
		_consume_shield(target, shield_damage)
	amount -= shield_damage
	target.hp = maxi(0, int(target.hp) - amount)
	var total := amount + shield_damage
	if attacker.team == "PLAYER": damage_by_character[attacker.def_id] = int(damage_by_character.get(attacker.def_id, 0)) + total
	_emit(BattleEvent.make(state.tick, BattleEvent.DAMAGE, attacker.uid, target.uid, total, {
		"hp_damage": amount,
		"shield_damage": shield_damage,
		"crit": resolved.crit,
		"source": source,
		"random_variance": resolved.random_variance,
		"defense_factor": resolved.defense_factor,
		"level_factor": resolved.level_factor,
		"affinity_factor": resolved.affinity_factor,
		"attacker_atk": attacker.stats.get("ATK", 0),
		"defender_def": target.stats.get("DEF", 0),
		"rng_state": rng.snapshot()
	}))
	if int(target.hp) <= 0:
		_down_unit(target, attacker.uid, source)

func _heal(caster: Dictionary, target: Dictionary, coefficient: float) -> void:
	if target.is_empty() or not UnitState.alive(target): return
	var amount := mini(HealingResolver.calculate(caster, coefficient, rng), int(target.max_hp) - int(target.hp))
	target.hp += amount
	healing_by_character[caster.def_id] = int(healing_by_character.get(caster.def_id, 0)) + amount
	_emit(BattleEvent.make(state.tick, BattleEvent.HEAL, caster.uid, target.uid, amount))

func _apply_shield(caster: Dictionary, target: Dictionary, coefficient: float) -> void:
	if target.is_empty() or not UnitState.alive(target): return
	var amount := HealingResolver.calculate(caster, coefficient, rng)
	target.shields[caster.uid] = amount
	_recalculate_shield(target)
	_emit(BattleEvent.make(state.tick, BattleEvent.SHIELD, caster.uid, target.uid, amount))

func _consume_shield(target: Dictionary, amount: int) -> void:
	var left := amount
	var sources: Array = target.shields.keys()
	sources.sort()
	for source in sources:
		var used := mini(left, int(target.shields[source]))
		target.shields[source] = int(target.shields[source]) - used
		left -= used
		if int(target.shields[source]) <= 0: target.shields.erase(source)
		if left <= 0: break
	_recalculate_shield(target)

func _recalculate_shield(target: Dictionary) -> void:
	var total := 0
	for value in target.shields.values(): total += int(value)
	target.shield = total

func _process_commands() -> void:
	var pending := command_queue.duplicate()
	command_queue.clear()
	for command in pending:
		if command.type == BattleCommand.USE_ULTIMATE:
			var unit := find_unit(command.unit_id)
			if not unit.is_empty(): _use_ultimate(unit, str(command.get("target_unit_id", "")))

func _auto_ultimate() -> void:
	var lowest := TargetResolver.lowest_hp(state.party)
	var allies := state.party.filter(func(candidate): return UnitState.alive(candidate))
	var enemies := alive_enemies()
	var average_hp := 1.0
	if not allies.is_empty():
		average_hp = allies.reduce(func(total, ally): return float(total) + UnitState.hp_ratio(ally), 0.0) / allies.size()
	var expected_incoming: float = float(enemies.reduce(func(total, enemy): return float(total) + float(enemy.stats.get("ATK", 0)), 0.0))
	var strong_enemy: Dictionary = TargetResolver.choose({"team": "PLAYER", "statuses": {}}, enemies)
	for unit in state.party:
		if not UnitState.alive(unit): continue
		var skill := _skill(unit.ultimate_skill_id)
		if not SkillRuntime.can_use_ultimate(unit, skill, state.tactical_gauge): continue
		var effect := str(skill.effect)
		if effect == "HEAL" and not lowest.is_empty() and (UnitState.hp_ratio(lowest) < .72 or average_hp < .82):
			_use_ultimate(unit); return
		if effect == "SHIELD" and not lowest.is_empty() and (UnitState.hp_ratio(lowest) < .82 or (UnitState.hp_ratio(lowest) < .95 and float(lowest.get("shield", 0)) < expected_incoming * .8)):
			_use_ultimate(unit); return
		# Chapter 1 often opens with two enemies.  Requiring three hid the party's
		# area ultimate through most first encounters even when the tactical gauge
		# was already sufficient.  Two is still an area-value threshold.
		if effect == "AOE_DAMAGE" and enemies.size() >= 2:
			_use_ultimate(unit); return
		if effect == "DEBUFF" and not strong_enemy.is_empty() and strong_enemy.rank in ["BOSS", "ELITE"]:
			_use_ultimate(unit, strong_enemy.uid); return
		if effect == "DAMAGE" and not strong_enemy.is_empty() and (strong_enemy.rank in ["BOSS", "ELITE"] or state.tactical_gauge > 8.0):
			_use_ultimate(unit, strong_enemy.uid); return
		if effect == "BUFF" and state.time_limit - state.time_elapsed > 10.0 and allies.size() >= 3:
			_use_ultimate(unit); return

func _tick_boss_patterns(boss: Dictionary) -> void:
	for index in range(boss.patterns.size()):
		var key := str(index)
		if boss.pattern_triggers.has(key): continue
		var pattern: Dictionary = boss.patterns[index]
		var triggered := false
		if pattern.condition == "TIME": triggered = state.time_elapsed >= float(pattern.value)
		elif pattern.condition == "HP_BELOW": triggered = UnitState.hp_ratio(boss) <= float(pattern.value)
		elif pattern.condition == "TIME_LEFT_BELOW": triggered = state.time_limit - state.time_elapsed <= float(pattern.value)
		if not triggered: continue
		boss.pattern_triggers[key] = true
		var action := str(pattern.get("action", ""))
		if action == "PHASE_2":
			boss.phase = "PHASE_2"
			_emit(BattleEvent.make(state.tick, BattleEvent.STATUS, boss.uid, boss.uid, 0, {"phase": "PHASE_2"}))
		elif action == "ENRAGE":
			boss.phase = "ENRAGE"
			boss.outgoing_modifier = float(pattern.get("outgoing_multiplier", 1.35))
			_emit(BattleEvent.make(state.tick, BattleEvent.STATUS, boss.uid, boss.uid, 0, {"phase": "ENRAGE"}))
		elif action == "GATE_CLOSE":
			_emit_boss_pattern_cast(boss, boss, action)
			_apply_shield(boss, boss, float(pattern.get("shield_multiplier", .5)))
		elif action == "NETWORK_FORM":
			_emit_boss_pattern_cast(boss, boss, action)
			_heal(boss, boss, float(pattern.get("heal_multiplier", .15)))
		elif action == "LOCK_ON":
			var locked_target := TargetResolver.choose(boss, state.party)
			if not locked_target.is_empty():
				_emit_boss_pattern_cast(boss, locked_target, action)
				_deal_damage(boss, locked_target, float(pattern.get("damage_multiplier", 1.0)), "ULTIMATE")
		else:
			var affected_targets: Array = state.party.filter(func(target): return UnitState.alive(target))
			if affected_targets.is_empty(): continue
			_emit_boss_pattern_cast(boss, affected_targets[0], action)
			for target in affected_targets:
				_deal_damage(boss, target, float(pattern.get("damage_multiplier", .72)), "ULTIMATE")

func _emit_boss_pattern_cast(boss: Dictionary, target: Dictionary, action: String) -> void:
	# A boss pattern is a real battle event, so it exercises the same runtime
	# ultimate VFX pathway as a player cast instead of being an invisible stat
	# mutation. The payload preserves the unique gameplay grammar for replays.
	_emit(BattleEvent.make(state.tick, BattleEvent.ULTIMATE, str(boss.uid), str(target.get("uid", "")), 0, {"boss_pattern": action}))

func _update_statuses() -> void:
	for unit in state.party + state.enemies:
		if not UnitState.alive(unit): continue
		for ticked in StatusEffectRuntime.update(unit, TICK_DELTA):
			if ticked.id == "DAMAGE_OVER_TIME":
				var amount := MathUtil.round_half_up(ticked.strength)
				unit.hp = maxi(0, int(unit.hp) - amount)
				_emit(BattleEvent.make(state.tick, BattleEvent.DAMAGE, str(ticked.source), unit.uid, amount, {"source": "DAMAGE_OVER_TIME", "hp_damage": amount}))
				if int(unit.hp) <= 0: _down_unit(unit, str(ticked.source), "DAMAGE_OVER_TIME")
			elif ticked.id == "HEAL_OVER_TIME":
				unit.hp = mini(int(unit.max_hp), int(unit.hp) + MathUtil.round_half_up(ticked.strength))

func _spawn_next_wave() -> void:
	if not wave_director.has_next(): return
	var definitions := wave_director.next_wave()
	state.wave = wave_director.current_index + 1
	state.enemies = []
	for i in range(definitions.size()):
		var enemy := _make_enemy(definitions[i], i)
		state.enemies.append(enemy)
		_emit(BattleEvent.make(state.tick, BattleEvent.SPAWN, enemy.uid))
	_emit(BattleEvent.make(state.tick, BattleEvent.WAVE, "", "", state.wave))

func _check_flow() -> void:
	var protected_id := str(stage.get("protected_unit_id", ""))
	if not protected_id.is_empty():
		var protected := state.party.filter(func(unit): return unit.uid == protected_id or unit.def_id == protected_id)
		if protected.is_empty() or not UnitState.alive(protected[0]):
			_end(false, "PROTECTED_TARGET_DEFEATED")
			return
	if state.party.filter(func(unit): return UnitState.alive(unit)).is_empty():
		_end(false, "PARTY_DEFEATED")
		return
	if state.time_elapsed >= state.time_limit:
		_end(false, "TIMEOUT")
		return
	if alive_enemies().is_empty():
		if wave_director.has_next(): _spawn_next_wave()
		else: _end(true, "ALL_WAVES_CLEARED")

func _down_unit(target: Dictionary, source_uid: String, cause: String) -> void:
	if not bool(target.get("alive", false)): return
	target.alive = false
	target.state = "DOWN"
	if target.rank == "BOSS": target.phase = "DOWN"
	deaths.append({"tick": state.tick, "unit_id": target.uid, "source": cause, "source_uid": source_uid})
	_emit(BattleEvent.make(state.tick, BattleEvent.DOWN, source_uid, target.uid, 0, {"cause": cause}))

func _end(victory: bool, reason: String) -> void:
	state.ended = true
	state.victory = victory
	state.reason = reason
	_emit(BattleEvent.make(state.tick, BattleEvent.BATTLE_END, "", "", 1 if victory else 0, {"reason": reason}))

func alive_enemies() -> Array:
	return state.enemies.filter(func(unit): return UnitState.alive(unit))

func has_boss() -> bool:
	return state.enemies.any(func(unit): return UnitState.alive(unit) and unit.rank == "BOSS")

func find_unit(uid: String) -> Dictionary:
	for unit in state.party + state.enemies:
		if unit.uid == uid: return unit
	return {}

func _skill(skill_id: String) -> Dictionary:
	for item in data.get("skills", []):
		if item.id == skill_id: return item
	return {}

func _enemy(enemy_id: String) -> Dictionary:
	for item in data.get("enemies", []):
		if item.id == enemy_id: return item
	return {}

func _emit(event: Dictionary) -> void:
	# Long-running economy/progression simulations need the real battle rules but
	# do not consume an event hash.  Keep hashing on by default so gameplay and
	# deterministic regression tests preserve their existing contract.
	if bool(options.get("retain_event_hash", true)):
		event_hasher.update((JSON.stringify(event) + "\n").to_utf8_buffer())
	if bool(options.get("retain_event_log", true)):
		event_log.append(event)

func event_hash() -> String:
	if not event_hash_cache.is_empty(): return event_hash_cache
	if not state.ended: return JSON.stringify(event_log).sha256_text()
	event_hash_cache = event_hasher.finish().hex_encode()
	return event_hash_cache

func result_snapshot() -> Dictionary:
	var ultimate_by_character: Dictionary = {}
	for unit in state.party: ultimate_by_character[unit.def_id] = int(unit.ultimate_uses)
	return {"victory": state.victory, "reason": state.reason, "ticks": state.tick, "time": state.time_elapsed, "survivors": state.party.filter(func(unit): return UnitState.alive(unit)).size(), "damage": damage_by_character.duplicate(true), "healing": healing_by_character.duplicate(true), "deaths": deaths.duplicate(true), "seed": seed, "event_hash": event_hash(), "ultimate_uses": state.party.reduce(func(total, unit): return total + int(unit.ultimate_uses), 0), "ultimate_uses_by_character": ultimate_by_character}
