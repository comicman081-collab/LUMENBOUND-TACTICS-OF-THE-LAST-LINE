class_name BattleSimulation
extends RefCounted

## Deterministic 30 Hz tactical battle on the BattleGrid.
##
## Placement is the main lever: every unit stands on a cell, reaches only what
## its range covers, blocks enemy melee in its lane and gains or loses from
## cover, flanks and neighbours. During the battle the player moves allies,
## names a focus target and aims ultimates, and dodges telegraphed area attacks
## whose damage is partly a share of max HP, so stats alone cannot absorb them.
## Growth still counts, but stats are synced toward the stage's recommended
## profile (GROWTH_SYNC_EXPONENT) so a level lead is worth about half of its
## raw stat gain.

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
var move_commands := 0
var dodged_hits := 0
var area_hits := 0
# Telegraphed area attacks (boss patterns and elite area skills). Each entry:
# due_tick, boss_uid (the caster), action, target_uid, multiplier, cells,
# hp_ratio, shape, label, windup_ticks.
var pending_boss_casts: Array = []
const BOSS_WINDUP_TICKS := 75
const ENEMY_AREA_WINDUP_TICKS := 54
const BOSS_PATTERN_REPEAT := 13.0
const MOVE_TICKS := 12
const PLAYER_MOVE_COOLDOWN := 3.0
const ENEMY_PUSH_FACTOR := 1.6
const TAUNT_RADIUS := 3
## Elite enemies telegraph a heavy strike on the party's side every few seconds
## (a lane for melee elites, a cross for ranged ones): standing still is costly.
const ELITE_STRIKE_INTERVAL := 9.0
const ELITE_STRIKE_FIRST := 4.0
const ELITE_STRIKE_COEFFICIENT := .9
const ELITE_STRIKE_HP_RATIO := .14
## 1.0 would use raw stats, 0.0 would ignore growth entirely.
const GROWTH_SYNC_EXPONENT := 0.5
const SYNCED_STATS := ["HP", "ATK", "DEF", "HEAL_POWER"]

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
	state.cover_cells = BattleGrid.cover_cells(stage)
	event_log.clear()
	command_log.clear()
	command_queue.clear()
	damage_by_character.clear()
	healing_by_character.clear()
	deaths.clear()
	pending_boss_casts.clear()
	move_commands = 0
	dodged_hits = 0
	area_hits = 0
	event_hash_cache = ""
	event_hasher = HashingContext.new()
	event_hasher.start(HashingContext.HASH_SHA256)
	wave_director.setup(stage.get("waves", []))
	var cells := BattleGrid.resolve_player_cells(party_snapshot, options.get("formation", {}))
	for i in range(party_snapshot.size()):
		state.party.append(_make_player(party_snapshot[i], i, cells[i]))
	_spawn_next_wave()

## Current party placement as {def_id: [col, lane]}.
func formation() -> Dictionary:
	var output: Dictionary = {}
	for unit in state.party:
		output[str(unit.def_id)] = [int(unit.col), int(unit.lane)]
	return output

## Pre-battle redeployment: only before the first tick, so the result equals a
## setup with the same formation option (no event is emitted for placement).
func set_formation(value: Dictionary) -> bool:
	if state.tick != 0:
		return false
	var party_defs: Array = []
	for unit in state.party:
		party_defs.append({"id": str(unit.def_id), "preferred_position": str(unit.get("preferred_position", "MIDDLE"))})
	var cells := BattleGrid.resolve_player_cells(party_defs, value)
	for index in range(state.party.size()):
		state.party[index].col = int(cells[index][0])
		state.party[index].lane = int(cells[index][1])
	options["formation"] = formation()
	return true

## Pre-battle move or swap of one ally (deployment screen).
func deploy_move(unit_id: String, col: int, lane: int) -> bool:
	if state.tick != 0 or not BattleGrid.in_player_zone(col, lane):
		return false
	var unit := find_unit(unit_id)
	if unit.is_empty() or str(unit.team) != "PLAYER":
		return false
	var occupant := unit_at(col, lane)
	if not occupant.is_empty():
		if str(occupant.team) != "PLAYER": return false
		occupant.col = int(unit.col)
		occupant.lane = int(unit.lane)
	unit.col = col
	unit.lane = lane
	options["formation"] = formation()
	return true

func _make_player(definition: Dictionary, slot: int, cell: Array) -> Dictionary:
	var progress: Dictionary = definition.get("progress", {})
	var level := int(progress.get("level", 1))
	var stats := _character_stats(definition, level, int(progress.get("breakthrough", 0)), progress.get("weapon_state", {}), int(progress.get("skills", {}).get("passive", 1)))
	var synced_level := level
	if bool(options.get("growth_sync", true)):
		var profile := GrowthAdvisor.recommended_profile(stage)
		var weapon_state := {"owned": bool(progress.get("weapon_state", {}).get("owned", false)), "level": int(profile.weapon_level), "tier": int(profile.weapon_tier)}
		var baseline := _character_stats(definition, int(profile.level), int(profile.breakthrough), weapon_state, int(profile.passive))
		for key in SYNCED_STATS:
			var base := float(baseline.get(key, 0))
			var actual := float(stats.get(key, 0))
			if base > 0.0 and actual > 0.0:
				stats[key] = MathUtil.round_half_up(base * pow(actual / base, GROWTH_SYNC_EXPONENT))
		synced_level = roundi(float(profile.level) + float(level - int(profile.level)) * GROWTH_SYNC_EXPONENT)
	var hp := int(stats.HP)
	var reach := BattleGrid.player_reach(str(definition.role))
	return {"uid": "P:%s" % definition.id, "def_id": definition.id, "team": "PLAYER", "rank": "PLAYER", "role": definition.role, "attack_type": definition.attack_type, "defense_type": definition.defense_type, "level": synced_level, "true_level": level, "stats": stats, "hp": hp, "max_hp": hp, "shield": 0, "shields": {}, "alive": true, "slot": slot, "col": int(cell[0]), "lane": int(cell[1]), "preferred_position": str(definition.get("preferred_position", "MIDDLE")), "range": int(reach.range), "melee": bool(reach.melee), "step": 0.0, "advance_timer": 0.0, "moving_ticks": 0, "move_cd": 0.0, "attack_cd": float(definition.attack_interval) * (0.85 + slot * .02), "normal_cd": 2.0 + slot * .6, "statuses": {}, "threat": float(definition.threat_modifier), "outgoing_modifier": 1.0, "incoming_modifier": 1.0, "healing_done_modifier": 1.0, "normal_skill_id": definition.normal_skill_id, "ultimate_skill_id": definition.ultimate_skill_id, "skill_levels": progress.get("skills", {"normal": 1, "passive": 1, "ultimate": 1}), "attack_interval": float(definition.attack_interval), "state": "IDLE", "ultimate_uses": 0}

## Level curve, breakthrough, weapon and passive in the order the growth
## screens apply them.
func _character_stats(definition: Dictionary, level: int, breakthrough: int, weapon_state: Dictionary, passive_level: int) -> Dictionary:
	var stats := _scaled_character_stats(definition, level, breakthrough)
	var weapon_id := str(definition.get("progress", {}).get("equipped_weapon_id", ""))
	var weapon_stats := WeaponUpgradeService.flat_stats_for(weapon_id, weapon_state)
	for key in weapon_stats:
		stats[key] = int(stats.get(key, 0)) + int(weapon_stats[key])
	var passive := _skill(str(definition.get("passive_skill_id", "")))
	var passive_bonus := SkillRuntime.value_at(passive, passive_level)
	if definition.role == "GUARDIAN":
		stats.HP = MathUtil.round_half_up(float(stats.HP) * (1.0 + passive_bonus))
	elif definition.role == "MEDIC":
		stats.HEAL_POWER = MathUtil.round_half_up(float(stats.HEAL_POWER) * (1.0 + passive_bonus))
	else:
		stats.ATK = MathUtil.round_half_up(float(stats.ATK) * (1.0 + passive_bonus))
	return stats

func _make_enemy(enemy_id: String, index: int, cell: Array, squad_factor: float) -> Dictionary:
	var definition := _enemy(enemy_id)
	var level := int(stage.get("recommended_level", 1))
	var base_stats: Dictionary = definition.get("stats", {}).duplicate(true)
	var scale := (1.0 + 0.065 * maxf(0, level - 1)) * float(stage.get("post_cap_scale", 1.0)) * float(options.get("enemy_multiplier", 1.0))
	var rank := str(definition.get("rank", "NORMAL"))
	if rank == "ELITE":
		scale *= 1.05
	for key in base_stats:
		var factor := scale
		if rank != "BOSS" and key in ["HP", "ATK"]:
			factor *= squad_factor
		base_stats[key] = MathUtil.round_half_up(float(base_stats[key]) * factor)
	var hp := int(base_stats.get("HP", 1))
	var reach := BattleGrid.enemy_reach(str(definition.get("role", "RANGED")), rank)
	return {"uid": "E:%d:%d:%s" % [state.wave, index, enemy_id], "def_id": enemy_id, "team": "ENEMY", "rank": rank, "role": definition.get("role", "RANGED"), "attack_type": definition.get("attack_type", "PHYSICAL"), "defense_type": definition.get("defense_type", "ARMOR"), "level": level, "stats": base_stats, "hp": hp, "max_hp": hp, "shield": 0, "shields": {}, "alive": true, "slot": index, "col": int(cell[0]), "lane": int(cell[1]), "range": int(reach.range), "melee": bool(reach.melee), "step": float(reach.get("step", 1.2)), "advance_timer": 0.0, "moving_ticks": 0, "move_cd": 0.0, "attack_cd": .8 + index * .12, "normal_cd": 5.0 + index * .4, "statuses": {}, "threat": 1.0, "outgoing_modifier": 1.0, "incoming_modifier": 1.0, "healing_done_modifier": 1.0, "attack_interval": float(definition.get("attack_interval", 1.45)), "state": "IDLE", "strike_cd": ELITE_STRIKE_FIRST + index * .6, "phase": "PHASE_1" if rank == "BOSS" else "", "patterns": definition.get("patterns", []).duplicate(true), "pattern_triggers": {}, "ultimate_uses": 0}

## More bodies per wave split the same threat: HP and attack of regular and
## elite enemies shrink as a wave grows past two.
static func squad_factor(regular_count: int) -> float:
	if regular_count <= 2:
		return 1.0
	return clampf(pow(2.5 / float(regular_count), .6), .62, 1.0)

func _scaled_character_stats(definition: Dictionary, level: int, breakthrough: int) -> Dictionary:
	var level_curve: Array = data.get("character_level_curve", [])
	var curve := float(level_curve[clampi(level - 1, 0, level_curve.size() - 1)].curve) if not level_curve.is_empty() else 0.0
	var multipliers := [1.0, 1.02, 1.04, 1.07, 1.10, 1.14]
	var stats: Dictionary = {}
	for key in definition.stats_l1:
		var base := float(definition.stats_l1[key]) + (float(definition.stats_l100.get(key, definition.stats_l1[key])) - float(definition.stats_l1[key])) * curve
		stats[key] = MathUtil.round_half_up(base * multipliers[clampi(breakthrough, 0, 5)])
	return stats

# --- Commands ----------------------------------------------------------------

func request_ultimate(unit_id: String, target_unit_id := "") -> void:
	var command := BattleCommand.ultimate(state.tick, unit_id, target_unit_id)
	command_queue.append(command)
	command_log.append(command.duplicate(true))

## Move an ally to a party cell; an occupied ally cell swaps the two.
func request_move(unit_id: String, col: int, lane: int) -> void:
	var command := BattleCommand.move(state.tick, unit_id, col, lane)
	command_queue.append(command)
	command_log.append(command.duplicate(true))

## Party-wide focus fire; an empty id clears it.
func request_focus(target_unit_id: String) -> void:
	var command := BattleCommand.focus(state.tick, target_unit_id)
	command_queue.append(command)
	command_log.append(command.duplicate(true))

## Why a move would be refused ("" when it is allowed). Used by the HUD before
## sending the command.
func move_block_reason(unit_id: String, col: int, lane: int) -> String:
	var unit := find_unit(unit_id)
	if unit.is_empty() or str(unit.team) != "PLAYER" or not UnitState.alive(unit): return "UNIT"
	if not BattleGrid.in_player_zone(col, lane): return "ZONE"
	if int(unit.col) == col and int(unit.lane) == lane: return "SAME"
	if UnitState.has_status(unit, "STUN"): return "STUNNED"
	if int(unit.moving_ticks) > 0: return "MOVING"
	if float(unit.move_cd) > 0.0: return "COOLDOWN"
	var occupant := unit_at(col, lane)
	if not occupant.is_empty() and str(occupant.team) != "PLAYER": return "ENEMY"
	return ""

func tick() -> void:
	if state.ended:
		return
	state.tick += 1
	state.time_elapsed = state.tick * TICK_DELTA
	state.tactical_gauge = minf(10.0, state.tactical_gauge + .40 * TICK_DELTA)
	_update_statuses()
	_process_commands()
	_resolve_boss_casts()
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
	var cooldown_rate := 1.0
	if UnitState.has_status(unit, "HASTE"): cooldown_rate = 1.0 + UnitState.status_strength(unit, "HASTE", .2)
	elif UnitState.has_status(unit, "SLOW"): cooldown_rate = 1.0 - clampf(UnitState.status_strength(unit, "SLOW", .3), 0.0, .8)
	unit.attack_cd = float(unit.attack_cd) - TICK_DELTA * cooldown_rate
	unit.normal_cd = float(unit.normal_cd) - TICK_DELTA
	unit.move_cd = maxf(0.0, float(unit.move_cd) - TICK_DELTA)
	if int(unit.moving_ticks) > 0:
		unit.moving_ticks = int(unit.moving_ticks) - 1
		return
	if unit.team == "ENEMY" and str(unit.rank) == "ELITE":
		unit.strike_cd = float(unit.get("strike_cd", ELITE_STRIKE_FIRST)) - TICK_DELTA
		if float(unit.strike_cd) <= 0.0 and _elite_strike(unit):
			return
	var opponents: Array = state.enemies if unit.team == "PLAYER" else state.party
	var focus := state.focus_uid if unit.team == "PLAYER" else ""
	var target := {}
	var target_known := false
	if unit.team == "ENEMY" and float(unit.get("step", 0.0)) > 0.0:
		unit.advance_timer = float(unit.advance_timer) + TICK_DELTA
		if float(unit.advance_timer) >= float(unit.step):
			target = TargetResolver.choose(unit, opponents)
			target_known = true
			var pushing := not target.is_empty()
			# A rusher that broke in keeps driving toward the back row while only
			# front-row allies are within its reach.
			if pushing and str(unit.role) == "MELEE_RUSH" and int(unit.col) <= BattleGrid.PLAYER_FRONT and int(unit.col) > 0 and int(target.col) >= int(unit.col) and _ally_behind(int(unit.col)):
				pushing = false
			_enemy_advance(unit, pushing)
			if int(unit.moving_ticks) > 0:
				return
	if float(unit.normal_cd) > 0 and float(unit.attack_cd) > 0:
		return
	if not target_known:
		target = TargetResolver.choose(unit, opponents, focus)
	if float(unit.normal_cd) <= 0 and unit.team == "PLAYER":
		if _use_normal(unit, target):
			return
	if float(unit.normal_cd) <= 0 and unit.team == "ENEMY" and unit.rank != "BOSS" and ENEMY_ROLE_SKILLS.has(str(unit.role)) and enemy_role_potency() > 0.0 and not has_boss():
		if _use_enemy_role_skill(unit, target):
			return
	if target.is_empty():
		unit.attack_cd = maxf(0.0, float(unit.attack_cd))
		return
	if float(unit.attack_cd) <= 0:
		_basic_attack(unit, target)
		unit.attack_cd = float(unit.attack_interval)

## Enemies close in: with nothing in reach they advance a column (entering the
## party's zone through an unblocked lane); with a target they still step up to
## their own front row, more slowly. Bosses hold their cell.
func _enemy_advance(unit: Dictionary, has_target: bool) -> void:
	var step := float(unit.get("step", 0.0))
	if step <= 0.0:
		return
	var needed := step * (ENEMY_PUSH_FACTOR if has_target else 1.0)
	if float(unit.advance_timer) < needed:
		return
	var col := int(unit.col)
	var lane := int(unit.lane)
	var options_cells: Array = []
	if has_target:
		if col <= BattleGrid.ENEMY_FRONT:
			unit.advance_timer = step * .5
			return
		options_cells.append([col - 1, lane])
	else:
		if col <= 0:
			unit.advance_timer = step * .5
			return
		options_cells.append([col - 1, lane])
		var toward := _lane_toward_party(lane)
		if toward != lane: options_cells.append([col - 1, toward])
		for other in [lane - 1, lane + 1]:
			if other != toward: options_cells.append([col - 1, other])
		# Rushers on their own side head for a lane nobody holds, so every
		# unblocked front cell is a breach point.
		if str(unit.role) == "MELEE_RUSH" and col > BattleGrid.PLAYER_FRONT:
			var open_first: Array = options_cells.filter(func(entry): return _lane_open(int(entry[1])))
			var rest: Array = options_cells.filter(func(entry): return not _lane_open(int(entry[1])))
			options_cells = open_first + rest
	for entry in options_cells:
		var to_col := int(entry[0])
		var to_lane := int(entry[1])
		if not BattleGrid.in_bounds(to_col, to_lane) or not unit_at(to_col, to_lane).is_empty():
			continue
		_move_unit(unit, to_col, to_lane, "ADVANCE")
		unit.advance_timer = 0.0
		return
	unit.advance_timer = step * .5

## True when a living ally stands on a column deeper than `col`.
func _ally_behind(col: int) -> bool:
	for ally in state.party:
		if UnitState.alive(ally) and int(ally.col) < col: return true
	return false

## True when no living ally stands on the party's front cell of `lane`.
func _lane_open(lane: int) -> bool:
	if lane < 0 or lane >= BattleGrid.LANES: return false
	var holder := unit_at(BattleGrid.PLAYER_FRONT, lane)
	return holder.is_empty() or str(holder.team) != "PLAYER"

func _lane_toward_party(lane: int) -> int:
	var best := lane
	var best_distance := 99
	for ally in state.party:
		if not UnitState.alive(ally): continue
		var distance := absi(int(ally.lane) - lane)
		if distance < best_distance:
			best_distance = distance
			best = int(ally.lane)
	if best == lane: return lane
	return lane + (1 if best > lane else -1)

func _move_unit(unit: Dictionary, col: int, lane: int, reason: String, partner_uid := "") -> void:
	var from := [int(unit.col), int(unit.lane)]
	unit.col = col
	unit.lane = lane
	unit.moving_ticks = MOVE_TICKS
	var extra := {"from": from, "to": [col, lane], "reason": reason}
	if not partner_uid.is_empty(): extra["swap_with"] = partner_uid
	_emit(BattleEvent.make(state.tick, BattleEvent.MOVE, str(unit.uid), "", 0, extra))

# Enemy roles act on their skill timer instead of every enemy only
# auto-attacking. Values are percentages of the enemy's own stats so they scale
# with stage level without new data columns. AREA and ARTILLERY announce their
# blast on the grid first so the party can step out of it.
const ENEMY_ROLE_SKILLS := {
	"HEALER": {"cooldown": 9.0, "label": "응급 수복"},
	"BUFFER": {"cooldown": 11.0, "label": "출력 증폭"},
	"DEBUFFER": {"cooldown": 8.5, "label": "간섭 신호"},
	"AREA": {"cooldown": 9.5, "coefficient": .55, "hp_ratio": .13, "shape": "PLUS", "label": "확산 방전"},
	"ARTILLERY": {"cooldown": 10.5, "coefficient": .60, "hp_ratio": .15, "shape": "BLAST", "label": "포격 지원"},
	"DEFENDER": {"cooldown": 12.0, "label": "방벽 전개"},
}

func _use_enemy_role_skill(unit: Dictionary, target: Dictionary) -> bool:
	var role := str(unit.role)
	var spec: Dictionary = ENEMY_ROLE_SKILLS[role]
	unit.normal_cd = float(spec.cooldown)
	var skill_id := "ENEMY_ROLE_" + role
	var potency := enemy_role_potency()
	match role:
		"HEALER":
			var wounded := TargetResolver.lowest_hp(state.enemies)
			if wounded.is_empty() or UnitState.hp_ratio(wounded) > .8:
				unit.normal_cd = 1.5
				return false
			_emit(BattleEvent.make(state.tick, BattleEvent.NORMAL_SKILL, unit.uid, wounded.uid, 0, {"skill_id": skill_id, "label": spec.label}))
			var amount := mini(roundi(float(wounded.max_hp) * .10 * potency), int(wounded.max_hp) - int(wounded.hp))
			wounded.hp = int(wounded.hp) + amount
			_emit(BattleEvent.make(state.tick, BattleEvent.HEAL, unit.uid, wounded.uid, amount))
		"BUFFER":
			_emit(BattleEvent.make(state.tick, BattleEvent.NORMAL_SKILL, unit.uid, "", 0, {"skill_id": skill_id, "label": spec.label}))
			for ally in state.enemies:
				if UnitState.alive(ally): _apply_status(ally, "HASTE", 5.0, unit.uid, .15 * potency)
		"DEBUFFER":
			if target.is_empty():
				unit.normal_cd = 1.0
				return false
			_emit(BattleEvent.make(state.tick, BattleEvent.NORMAL_SKILL, unit.uid, target.uid, 0, {"skill_id": skill_id, "label": spec.label}))
			_deal_damage(unit, target, .40 * potency, "NORMAL")
			_apply_status(target, "ATK_DOWN", 3.0 + 3.0 * potency, unit.uid)
		"AREA", "ARTILLERY":
			var zone: Array = BattleGrid.PLAYER_COLUMNS if role == "ARTILLERY" else _columns_in_reach(unit)
			var placement := BattleGrid.best_shape_placement(str(spec.shape), zone, state.party)
			if placement.is_empty() or _units_in_cells(state.party, placement.cells).is_empty():
				unit.normal_cd = 1.5
				return false
			_emit(BattleEvent.make(state.tick, BattleEvent.NORMAL_SKILL, unit.uid, "", 0, {"skill_id": skill_id, "label": spec.label}))
			_announce_area_cast(unit, skill_id, str(spec.shape), placement.cells, float(spec.coefficient) * potency, float(spec.hp_ratio) * potency, ENEMY_AREA_WINDUP_TICKS, str(spec.label))
		"DEFENDER":
			_emit(BattleEvent.make(state.tick, BattleEvent.NORMAL_SKILL, unit.uid, unit.uid, 0, {"skill_id": skill_id, "label": spec.label}))
			var barrier := roundi(float(unit.max_hp) * .08 * potency)
			unit.shields[unit.uid] = barrier
			_recalculate_shield(unit)
			_emit(BattleEvent.make(state.tick, BattleEvent.SHIELD, unit.uid, unit.uid, barrier))
	return true

func _columns_in_reach(unit: Dictionary) -> Array:
	var output: Array = []
	for col in BattleGrid.PLAYER_COLUMNS:
		if absi(int(unit.col) - int(col)) <= int(unit.range): output.append(col)
	return output

## The first three chapter 1 operations teach the grid with plain enemies.
## After them role skills start at 45% strength and reach full at level 40.
## Adds hold their role skills whenever a boss is alive, so the boss
## telegraphs stay the one pattern to read.
func enemy_role_potency() -> float:
	if _tutorial_stage():
		return 0.0
	var level := float(stage.get("recommended_level", 1))
	return clampf((level - 5.0) / 35.0, .45, 1.0)

func _tutorial_stage() -> bool:
	return str(stage.get("chapter_id", "")) == "CH01" and str(stage.get("mode", "NORMAL")) == "NORMAL" and int(stage.get("stage_number", 1)) <= 3

func _elite_strike(unit: Dictionary) -> bool:
	if _tutorial_stage() or has_boss():
		unit.strike_cd = 2.0
		return false
	var shape := "LANE" if bool(unit.get("melee", false)) else "PLUS"
	var placement := BattleGrid.best_shape_placement(shape, BattleGrid.PLAYER_COLUMNS, state.party)
	if placement.is_empty() or _units_in_cells(state.party, placement.cells).is_empty():
		unit.strike_cd = 1.5
		return false
	unit.strike_cd = ELITE_STRIKE_INTERVAL
	_emit(BattleEvent.make(state.tick, BattleEvent.NORMAL_SKILL, unit.uid, "", 0, {"skill_id": "ENEMY_ELITE_STRIKE", "label": "정예 강타"}))
	_announce_area_cast(unit, "ENEMY_ELITE_STRIKE", shape, placement.cells, ELITE_STRIKE_COEFFICIENT, ELITE_STRIKE_HP_RATIO, ENEMY_AREA_WINDUP_TICKS, "정예 강타")
	return true

func _basic_attack(attacker: Dictionary, target: Dictionary = {}) -> void:
	# The normal tick loop already filters downed units, but this method is also
	# used by deterministic probes.  Keep the combat authority defensive so a
	# dead enemy can never enqueue a late attack/cast through a direct path.
	if state.ended or not UnitState.alive(attacker):
		return
	if target.is_empty():
		var targets := state.enemies if attacker.team == "PLAYER" else state.party
		target = TargetResolver.choose(attacker, targets, state.focus_uid if attacker.team == "PLAYER" else "")
	if target.is_empty():
		return
	_emit(BattleEvent.make(state.tick, BattleEvent.BASIC_ATTACK, attacker.uid, target.uid))
	_deal_damage(attacker, target, 1.0, "BASIC")

## Returns false when a damage skill has nothing in reach; the skill then stays
## ready and the unit keeps its basic attack rhythm.
func _use_normal(caster: Dictionary, target: Dictionary = {}) -> bool:
	# A DOWN unit has no cast rights.  This explicit guard prevents stale
	# cooldown/animation callers from emitting a skill after death.
	if state.ended or not UnitState.alive(caster):
		return false
	var skill := _skill(caster.normal_skill_id)
	var level := int(caster.skill_levels.get("normal", 1))
	var coefficient := SkillRuntime.value_at(skill, level)
	var effect := str(skill.get("effect", "DAMAGE"))
	var support := effect in ["HEAL", "SHIELD", "TAUNT"]
	if not support:
		if target.is_empty():
			target = TargetResolver.choose(caster, state.enemies, state.focus_uid)
		if target.is_empty():
			caster.normal_cd = 0.0
			return false
	if effect == "TAUNT" and _enemies_within(caster, TAUNT_RADIUS).is_empty():
		caster.normal_cd = 0.5
		return false
	caster.normal_cd = float(skill.get("cooldown", 8.0))
	_emit(BattleEvent.make(state.tick, BattleEvent.NORMAL_SKILL, caster.uid, "", 0, {"skill_id": skill.id}))
	if effect == "HEAL":
		_heal(caster, TargetResolver.lowest_hp(state.party), coefficient)
	elif effect == "SHIELD":
		_apply_shield(caster, TargetResolver.lowest_hp(state.party), coefficient)
	elif effect == "TAUNT":
		_apply_shield(caster, caster, coefficient * .8)
		for enemy in _enemies_within(caster, TAUNT_RADIUS):
			_apply_status(enemy, "TAUNT", 4.0, caster.uid)
	elif effect == "AOE_DAMAGE":
		var cells := BattleGrid.shape_cells("PLUS", int(target.col), int(target.lane), range(BattleGrid.COLUMNS))
		for enemy in _units_in_cells(state.enemies, cells):
			_deal_damage(caster, enemy, coefficient * .75, "NORMAL")
	else:
		_deal_damage(caster, target, coefficient, "NORMAL")
		if effect == "SLOW": _apply_status(target, "SLOW", 3.0, caster.uid, .3)
		# DEBUFF normals used to fall through as plain damage.
		elif effect == "DEBUFF" and UnitState.alive(target): _apply_status(target, "DEF_DOWN", 4.0, caster.uid, .15)
	return true

func _enemies_within(unit: Dictionary, radius: int) -> Array:
	return state.enemies.filter(func(enemy): return UnitState.alive(enemy) and BattleGrid.manhattan(unit, enemy) <= radius)

func _units_in_cells(units: Array, cells: Array) -> Array:
	return units.filter(func(unit): return UnitState.alive(unit) and BattleGrid.has_cell(cells, int(unit.col), int(unit.lane)))

## Cells an area ultimate centred on `target` covers.
static func ultimate_area_cells(target: Dictionary) -> Array:
	return BattleGrid.shape_cells("BLAST", int(target.get("col", 0)), int(target.get("lane", 0)), range(BattleGrid.COLUMNS))

## The enemy whose blast would hit the most enemies (ties: the priority enemy).
func best_area_target() -> Dictionary:
	var best := {}
	var best_score := -1.0
	for enemy in alive_enemies():
		var score := 0.0
		for other in _units_in_cells(state.enemies, ultimate_area_cells(enemy)):
			score += 1.0 + (0.5 if str(other.rank) in ["BOSS", "ELITE"] else 0.0)
		if score > best_score:
			best_score = score
			best = enemy
	return best

func _use_ultimate(caster: Dictionary, target_unit_id := "") -> bool:
	if state.ended or not UnitState.alive(caster):
		return false
	var skill := _skill(caster.ultimate_skill_id)
	if not SkillRuntime.can_use_ultimate(caster, skill, state.tactical_gauge):
		return false
	var effect := str(skill.effect)
	# Resolve the target before paying. A manual pick that died (or belonged to
	# a previous wave) falls back to the automatic target instead of spending
	# the gauge on nothing; with no valid target the cast is refused.
	var target := {}
	var targeted: bool = not (effect in ["HEAL", "SHIELD", "BUFF"])
	if targeted:
		target = find_unit(target_unit_id) if not target_unit_id.is_empty() else {}
		if target.is_empty() or str(target.get("team", "")) != "ENEMY" or not UnitState.alive(target):
			target = best_area_target() if effect == "AOE_DAMAGE" else TargetResolver.priority_enemy(state.enemies)
		if target.is_empty():
			return false
	state.tactical_gauge -= float(skill.tactical_cost)
	caster.ultimate_uses = int(caster.ultimate_uses) + 1
	var coefficient := SkillRuntime.value_at(skill, int(caster.skill_levels.get("ultimate", 1)))
	# Buff/debuff strength grows with the ultimate's level like damage does
	# (1.0x at Lv.1, ~1.85x at Lv.5), capped to keep the effects bounded.
	var level_ratio := coefficient / maxf(.01, SkillRuntime.value_at(skill, 1))
	_emit(BattleEvent.make(state.tick, BattleEvent.ULTIMATE, caster.uid, str(target.get("uid", "")), int(skill.tactical_cost), {"skill_id": skill.id}))
	if effect == "HEAL":
		for ally in state.party:
			if UnitState.alive(ally): _heal(caster, ally, coefficient * .72)
	elif effect == "SHIELD":
		for ally in state.party:
			if UnitState.alive(ally): _apply_shield(caster, ally, coefficient)
	elif effect == "BUFF":
		for ally in state.party:
			if UnitState.alive(ally): _apply_status(ally, "HASTE", 7.0, caster.uid, minf(.36, .2 * level_ratio))
	elif effect == "DEBUFF":
		_apply_status(target, "DEF_DOWN", 7.0, caster.uid, minf(.4, .25 * level_ratio))
	elif effect == "AOE_DAMAGE":
		for enemy in _units_in_cells(state.enemies, ultimate_area_cells(target)):
			_deal_damage(caster, enemy, coefficient * .95, "ULTIMATE")
	else:
		_deal_damage(caster, target, coefficient, "ULTIMATE")
	return true

func _apply_status(unit: Dictionary, status_id: String, duration: float, source_uid: String, strength := 0.0) -> void:
	if unit.is_empty() or not UnitState.alive(unit): return
	StatusEffectRuntime.apply(unit, status_id, duration, source_uid, strength)
	# Emit so the view (and replays) can show who is buffed or weakened.
	if UnitState.has_status(unit, status_id):
		_emit(BattleEvent.make(state.tick, BattleEvent.STATUS, source_uid, str(unit.uid), 0, {"status": status_id, "strength": strength, "duration": duration}))

## Placement multipliers for one hit, with the tags the view prints.
func positional_factor(attacker: Dictionary, target: Dictionary, area := false) -> Dictionary:
	var factor := 1.0
	var tags: Array = []
	if str(attacker.get("team", "")) == "PLAYER":
		var role := str(attacker.get("role", ""))
		if role == "ARTILLERY" and int(attacker.col) == 0:
			factor *= BattleGrid.ARTILLERY_BACK_ROW_DAMAGE
			tags.append("STEADY")
		elif role == "VANGUARD" and int(attacker.col) == BattleGrid.PLAYER_FRONT:
			factor *= BattleGrid.VANGUARD_FRONT_ROW_DAMAGE
			tags.append("CHARGE")
		if _has_adjacent_role(attacker, state.party, "SPECIALIST"):
			factor *= BattleGrid.SPECIALIST_AURA_DAMAGE
			tags.append("SUPPORT")
	if not area:
		var melee := bool(attacker.get("melee", false))
		if melee and int(attacker.col) == int(target.col) and int(attacker.lane) != int(target.lane):
			factor *= BattleGrid.FLANK_DAMAGE
			tags.append("FLANK")
		elif melee and str(target.get("team", "")) == "PLAYER" and int(attacker.col) < int(target.col):
			factor *= BattleGrid.FLANK_DAMAGE
			tags.append("FLANK")
		elif melee and str(target.get("team", "")) == "ENEMY" and int(attacker.col) > int(target.col):
			factor *= BattleGrid.FLANK_DAMAGE
			tags.append("FLANK")
		if not melee and BattleGrid.has_cell(state.cover_cells, int(target.col), int(target.lane)):
			factor *= BattleGrid.COVER_DAMAGE_TAKEN
			tags.append("COVER")
		var guardians_role := "GUARDIAN" if str(target.get("team", "")) == "PLAYER" else "DEFENDER"
		var allies: Array = state.party if str(target.get("team", "")) == "PLAYER" else state.enemies
		if _has_adjacent_role(target, allies, guardians_role):
			factor *= BattleGrid.GUARDIAN_COVER_DAMAGE_TAKEN
			tags.append("GUARDED")
	return {"factor": factor, "tags": tags}

func _has_adjacent_role(unit: Dictionary, allies: Array, role: String) -> bool:
	for ally in allies:
		if str(ally.uid) == str(unit.uid) or not UnitState.alive(ally): continue
		if str(ally.get("role", "")) == role and BattleGrid.adjacent(unit, ally):
			return true
	return false

func _deal_damage(attacker: Dictionary, target: Dictionary, coefficient: float, source: String) -> void:
	# Damage, healing and shielding are sometimes reached by boss-pattern and
	# deterministic probe paths rather than only by _tick_unit.  The source must
	# be alive on every authority boundary: a DOWN unit cannot finish a stale
	# effect after its defeat.
	if not UnitState.alive(attacker) or not UnitState.alive(target) or state.ended:
		return
	if UnitState.has_status(target, "INVULNERABLE"):
		_emit(BattleEvent.make(state.tick, BattleEvent.DAMAGE, attacker.uid, target.uid, 0, {"invulnerable": true, "source": source}))
		return
	var positional := positional_factor(attacker, target)
	var resolved := DamageResolver.calculate(attacker, target, coefficient, data.affinity_matrix, rng, float(positional.factor))
	if not resolved.hit:
		_emit(BattleEvent.make(state.tick, BattleEvent.DAMAGE, attacker.uid, target.uid, 0, {"miss": true, "source": source}))
		return
	_apply_damage(attacker, target, int(resolved.amount), source, resolved, positional.tags)

## Telegraphed area hits always land on whoever is still in the marked cells
## and add a share of the target's max HP that defence does not reduce.
func _deal_area_damage(attacker: Dictionary, target: Dictionary, coefficient: float, hp_ratio: float, source: String) -> void:
	if not UnitState.alive(attacker) or not UnitState.alive(target) or state.ended:
		return
	if UnitState.has_status(target, "INVULNERABLE"):
		_emit(BattleEvent.make(state.tick, BattleEvent.DAMAGE, attacker.uid, target.uid, 0, {"invulnerable": true, "source": source}))
		return
	var positional := positional_factor(attacker, target, true)
	var resolved := DamageResolver.calculate(attacker, target, coefficient, data.affinity_matrix, rng, float(positional.factor), true)
	var amount := int(resolved.amount) + MathUtil.round_half_up(float(target.max_hp) * hp_ratio)
	area_hits += 1
	_apply_damage(attacker, target, amount, source, resolved, ["AREA"])

func _apply_damage(attacker: Dictionary, target: Dictionary, amount: int, source: String, resolved: Dictionary, tags: Array) -> void:
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
		"position_factor": resolved.get("position_factor", 1.0),
		"tags": tags,
		"attacker_atk": attacker.stats.get("ATK", 0),
		"defender_def": target.stats.get("DEF", 0),
		"rng_state": rng.snapshot()
	}))
	if int(target.hp) <= 0:
		_down_unit(target, attacker.uid, source)

func _heal(caster: Dictionary, target: Dictionary, coefficient: float) -> void:
	if caster.is_empty() or not UnitState.alive(caster) or target.is_empty() or not UnitState.alive(target): return
	var bonus := BattleGrid.MEDIC_ADJACENT_HEAL if str(caster.get("role", "")) == "MEDIC" and str(caster.uid) != str(target.uid) and BattleGrid.adjacent(caster, target) else 1.0
	var amount := mini(HealingResolver.calculate(caster, coefficient * bonus, rng), int(target.max_hp) - int(target.hp))
	target.hp += amount
	healing_by_character[caster.def_id] = int(healing_by_character.get(caster.def_id, 0)) + amount
	_emit(BattleEvent.make(state.tick, BattleEvent.HEAL, caster.uid, target.uid, amount, {"adjacent": bonus > 1.0}))

func _apply_shield(caster: Dictionary, target: Dictionary, coefficient: float) -> void:
	if caster.is_empty() or not UnitState.alive(caster) or target.is_empty() or not UnitState.alive(target): return
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
		match str(command.type):
			BattleCommand.USE_ULTIMATE:
				var unit := find_unit(command.unit_id)
				if not unit.is_empty(): _use_ultimate(unit, str(command.get("target_unit_id", "")))
			BattleCommand.MOVE:
				_command_move(str(command.unit_id), int(command.col), int(command.lane))
			BattleCommand.FOCUS:
				var focus_id := str(command.get("target_unit_id", ""))
				var focus := find_unit(focus_id)
				if focus_id.is_empty() or (not focus.is_empty() and str(focus.team) == "ENEMY" and UnitState.alive(focus)):
					state.focus_uid = focus_id
					_emit(BattleEvent.make(state.tick, BattleEvent.FOCUS, "", focus_id))

func _command_move(unit_id: String, col: int, lane: int) -> void:
	if not move_block_reason(unit_id, col, lane).is_empty():
		return
	var unit := find_unit(unit_id)
	var occupant := unit_at(col, lane)
	var from_col := int(unit.col)
	var from_lane := int(unit.lane)
	move_commands += 1
	unit.move_cd = PLAYER_MOVE_COOLDOWN
	if not occupant.is_empty():
		_move_unit(occupant, from_col, from_lane, "SWAP", str(unit.uid))
		_move_unit(unit, col, lane, "COMMAND", str(occupant.uid))
	else:
		_move_unit(unit, col, lane, "COMMAND")

func _auto_ultimate() -> void:
	var lowest := TargetResolver.lowest_hp(state.party)
	var allies := state.party.filter(func(candidate): return UnitState.alive(candidate))
	var enemies := alive_enemies()
	var average_hp := 1.0
	if not allies.is_empty():
		average_hp = allies.reduce(func(total, ally): return float(total) + UnitState.hp_ratio(ally), 0.0) / allies.size()
	var expected_incoming: float = float(enemies.reduce(func(total, enemy): return float(total) + float(enemy.stats.get("ATK", 0)), 0.0))
	var strong_enemy: Dictionary = TargetResolver.priority_enemy(enemies)
	# Keep enough gauge for the party's defensive ultimate. Evaluating in slot
	# order let a cheap area ultimate spend the gauge every time it reached 2,
	# so shield/heal/damage ultimates (cost 3-6) never fired while 2+ enemies lived.
	# The reserve only applies once the party is hurt or a boss is present; at
	# full health the area ultimate still opens fights as fast as before.
	var defensive_reserve := 0.0
	if average_hp < .85 or has_boss():
		for ally in allies:
			var ally_skill := _skill(ally.ultimate_skill_id)
			if str(ally_skill.get("effect", "")) in ["HEAL", "SHIELD"]:
				defensive_reserve = maxf(defensive_reserve, float(ally_skill.get("tactical_cost", 0)))
	var boss_cast_incoming := not pending_boss_casts.is_empty()
	var area_target := best_area_target()
	var area_count := _units_in_cells(state.enemies, ultimate_area_cells(area_target)).size() if not area_target.is_empty() else 0
	for unit in state.party:
		if not UnitState.alive(unit): continue
		var skill := _skill(unit.ultimate_skill_id)
		if not SkillRuntime.can_use_ultimate(unit, skill, state.tactical_gauge): continue
		var effect := str(skill.effect)
		if effect == "HEAL" and not lowest.is_empty() and (UnitState.hp_ratio(lowest) < .72 or average_hp < .82):
			_use_ultimate(unit); return
		# A telegraphed boss attack is the moment a shield is worth the most.
		# Re-shielding a unit whose shield is still up only replaced it and wasted
		# the gauge; shield when the weakest ally's barrier is actually thin.
		if effect == "SHIELD" and not lowest.is_empty() and (boss_cast_incoming or (UnitState.hp_ratio(lowest) < .95 and float(lowest.get("shield", 0)) < expected_incoming * .8)):
			_use_ultimate(unit); return
		if effect == "AOE_DAMAGE" and area_count >= 2 and (area_count >= 3 or state.tactical_gauge - float(skill.tactical_cost) >= defensive_reserve):
			_use_ultimate(unit, str(area_target.uid)); return
		if effect == "DEBUFF" and not strong_enemy.is_empty() and strong_enemy.rank in ["BOSS", "ELITE"]:
			_use_ultimate(unit, strong_enemy.uid); return
		if effect == "DAMAGE" and not strong_enemy.is_empty() and (strong_enemy.rank in ["BOSS", "ELITE"] or state.tactical_gauge > 8.0):
			_use_ultimate(unit, strong_enemy.uid); return
		if effect == "BUFF" and state.time_limit - state.time_elapsed > 10.0 and allies.size() >= 3:
			_use_ultimate(unit); return

func _tick_boss_patterns(boss: Dictionary) -> void:
	if state.ended or not UnitState.alive(boss):
		return
	for index in range(boss.patterns.size()):
		var key := str(index)
		var pattern: Dictionary = boss.patterns[index]
		var action := str(pattern.get("action", ""))
		var repeating: bool = pattern.condition == "TIME" and pattern.has("damage_multiplier")
		var fired := int(boss.pattern_triggers.get(key, 0))
		if fired > 0 and not repeating: continue
		var triggered := false
		if pattern.condition == "TIME": triggered = state.time_elapsed >= float(pattern.value) + float(fired) * BOSS_PATTERN_REPEAT
		elif pattern.condition == "HP_BELOW": triggered = UnitState.hp_ratio(boss) <= float(pattern.value)
		elif pattern.condition == "TIME_LEFT_BELOW": triggered = state.time_limit - state.time_elapsed <= float(pattern.value)
		if not triggered: continue
		boss.pattern_triggers[key] = fired + 1
		if action == "PHASE_2":
			boss.phase = "PHASE_2"
			# Phase two is a real escalation, not only a label: harder hits and a
			# faster attack rhythm (ENRAGE later replaces the damage multiplier).
			boss.outgoing_modifier = float(boss.get("outgoing_modifier", 1.0)) * 1.15
			boss.attack_interval = float(boss.attack_interval) * .88
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
		else:
			if state.party.filter(func(target): return UnitState.alive(target)).is_empty(): continue
			var shape := boss_action_shape(action)
			var cells: Array = []
			var target_uid := ""
			if shape == "CELL":
				var locked := TargetResolver.lowest_hp(state.party)
				if locked.is_empty(): continue
				cells = [[int(locked.col), int(locked.lane)]]
				target_uid = str(locked.uid)
			else:
				cells = BattleGrid.best_shape_placement(shape, BattleGrid.PLAYER_COLUMNS, state.party).get("cells", [])
			var default_multiplier := 1.0 if shape == "CELL" else .72
			_announce_area_cast(boss, action, shape, cells, float(pattern.get("damage_multiplier", default_multiplier)), boss_hp_ratio(action, shape), BOSS_WINDUP_TICKS, "", target_uid)

## Area shape of a boss pattern. Named patterns keep their identity; the
## chapter signature/finale patterns rotate through the shapes by chapter.
static func boss_action_shape(action: String) -> String:
	match action:
		"LOCK_ON": return "CELL"
		"IMPLODE": return "PLUS"
		"RESONANCE": return "X"
		"OVERLOAD": return "TWIN_COLUMNS"
		"GATE_REVERSE": return "LANE"
		"RUPTURE", "NETWORK_COLLAPSE": return "TWIN_LANES"
	var chapter := int(action.substr(2, 2)) if action.begins_with("CH") else 0
	if action.ends_with("_FINALE"):
		return ["TWIN_LANES", "TWIN_COLUMNS"][chapter % 2]
	if action.ends_with("_SIGNATURE"):
		return ["PLUS", "X", "LANE", "COLUMN"][chapter % 4]
	return "PLUS"

## Share of max HP a boss pattern adds on top of its attack-based damage.
static func boss_hp_ratio(action: String, shape: String) -> float:
	if shape == "CELL": return .32
	if shape in ["TWIN_LANES", "TWIN_COLUMNS"]: return .24
	if action.ends_with("_FINALE") or action in ["RUPTURE", "NETWORK_COLLAPSE"]: return .26
	return .20

# Damaging patterns mark their cells ahead of the hit. The view paints them,
# giving the player time to move out, shield or burst the caster down; a caster
# that dies or is stunned before the hit loses the cast.
func _announce_area_cast(caster: Dictionary, action: String, shape: String, cells: Array, multiplier: float, hp_ratio: float, windup: int, label := "", target_uid := "") -> void:
	if cells.is_empty(): return
	var due := state.tick + windup
	pending_boss_casts.append({"due_tick": due, "boss_uid": str(caster.uid), "action": action, "target_uid": target_uid, "multiplier": multiplier, "cells": cells.duplicate(true), "hp_ratio": hp_ratio, "shape": shape, "label": label, "windup_ticks": windup})
	_emit(BattleEvent.make(state.tick, BattleEvent.STATUS, str(caster.uid), target_uid, 0, {"telegraph": action, "due_tick": due, "party_wide": target_uid.is_empty(), "cells": cells.duplicate(true), "shape": shape}))

func _resolve_boss_casts() -> void:
	if pending_boss_casts.is_empty() or state.ended:
		return
	var remaining: Array = []
	for cast in pending_boss_casts:
		if int(cast.due_tick) > state.tick:
			remaining.append(cast)
			continue
		var caster := find_unit(str(cast.boss_uid))
		if caster.is_empty() or not UnitState.alive(caster) or UnitState.has_status(caster, "STUN"):
			_emit(BattleEvent.make(state.tick, BattleEvent.STATUS, str(cast.boss_uid), str(cast.target_uid), 0, {"telegraph_cancelled": str(cast.action)}))
			continue
		var cells: Array = cast.get("cells", [])
		var affected := _units_in_cells(state.party, cells)
		var alive_count := state.party.filter(func(unit): return UnitState.alive(unit)).size()
		dodged_hits += maxi(0, alive_count - affected.size())
		if str(caster.get("rank", "")) == "BOSS":
			var focus_target: Dictionary = affected[0] if not affected.is_empty() else caster
			_emit_boss_pattern_cast(caster, focus_target, str(cast.action))
		_emit(BattleEvent.make(state.tick, BattleEvent.STATUS, str(cast.boss_uid), "", 0, {"telegraph_resolved": str(cast.action), "cells": cells.duplicate(true), "hits": affected.size()}))
		for target in affected:
			_deal_area_damage(caster, target, float(cast.multiplier), float(cast.get("hp_ratio", 0.0)), "ULTIMATE" if str(caster.get("rank", "")) == "BOSS" else "NORMAL")
	pending_boss_casts = remaining

func _emit_boss_pattern_cast(boss: Dictionary, target: Dictionary, action: String) -> void:
	# A boss pattern is a real battle event, so it exercises the same runtime
	# ultimate VFX pathway as a player cast instead of being an invisible stat
	# mutation. The payload preserves the unique gameplay grammar for replays.
	if state.ended or not UnitState.alive(boss):
		return
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

## Enemy definitions and cells of a stage wave, exactly as the battle places
## them. The deployment screen uses the same call for its preview.
static func wave_layout(stage_definition: Dictionary, wave_index: int, all_data: Dictionary) -> Array:
	var waves: Array = stage_definition.get("waves", [])
	if wave_index < 0 or wave_index >= waves.size():
		return []
	var defs: Array = []
	for enemy_id in waves[wave_index]:
		var found := {}
		for item in all_data.get("enemies", []):
			if str(item.id) == str(enemy_id):
				found = item
				break
		defs.append(found if not found.is_empty() else {"id": str(enemy_id), "role": "RANGED", "rank": "NORMAL"})
	var cells := BattleGrid.enemy_cells(defs, str(stage_definition.get("id", "")), wave_index)
	var output: Array = []
	for index in range(defs.size()):
		output.append({"id": str(waves[wave_index][index]), "definition": defs[index], "cell": cells[index]})
	return output

func _spawn_next_wave() -> void:
	if not wave_director.has_next(): return
	var definitions := wave_director.next_wave()
	state.wave = wave_director.current_index + 1
	state.enemies = []
	state.focus_uid = ""
	var layout := wave_layout(stage, wave_director.current_index, data)
	var regular := 0
	for entry in layout:
		if str(entry.definition.get("rank", "")) != "BOSS": regular += 1
	var factor := squad_factor(regular)
	for i in range(definitions.size()):
		var cell: Array = layout[i].cell if i < layout.size() else [5, 1]
		var enemy := _make_enemy(definitions[i], i, cell, factor)
		state.enemies.append(enemy)
		_emit(BattleEvent.make(state.tick, BattleEvent.SPAWN, enemy.uid, "", 0, {"cell": cell.duplicate()}))
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
	# A final kill landing on the same tick the timer expires is still a win.
	if alive_enemies().is_empty() and not wave_director.has_next():
		_end(true, "ALL_WAVES_CLEARED")
		return
	if state.time_elapsed >= state.time_limit:
		_end(false, "TIMEOUT")
		return
	if alive_enemies().is_empty():
		pending_boss_casts.clear()
		_spawn_next_wave()

func _down_unit(target: Dictionary, source_uid: String, cause: String) -> void:
	if not bool(target.get("alive", false)): return
	target.alive = false
	target.state = "DOWN"
	if target.rank == "BOSS": target.phase = "DOWN"
	if str(target.uid) == state.focus_uid: state.focus_uid = ""
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

## The living unit standing on (or moving into) a cell.
func unit_at(col: int, lane: int) -> Dictionary:
	for unit in state.party + state.enemies:
		if UnitState.alive(unit) and int(unit.get("col", -9)) == col and int(unit.get("lane", -9)) == lane:
			return unit
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
	return {"victory": state.victory, "reason": state.reason, "ticks": state.tick, "time": state.time_elapsed, "survivors": state.party.filter(func(unit): return UnitState.alive(unit)).size(), "damage": damage_by_character.duplicate(true), "healing": healing_by_character.duplicate(true), "deaths": deaths.duplicate(true), "seed": seed, "event_hash": event_hash(), "ultimate_uses": state.party.reduce(func(total, unit): return total + int(unit.ultimate_uses), 0), "ultimate_uses_by_character": ultimate_by_character, "moves": move_commands, "dodged_hits": dodged_hits, "area_hits": area_hits, "formation": formation()}
