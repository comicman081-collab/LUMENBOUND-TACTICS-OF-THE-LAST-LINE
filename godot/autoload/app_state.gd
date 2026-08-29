extends Node

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const ChapterMapLoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const ChapterMapProgressScript := preload("res://chapter_map/model/chapter_map_progress.gd")
const MapExplorationServiceScript := preload("res://chapter_map/model/map_exploration_service.gd")
const MapSimulationScript := preload("res://chapter_map/model/map_simulation.gd")
const RelayServiceScript := preload("res://relay/relay_service.gd")

const SAVE_SCHEMA_VERSION := 8
var profile: Dictionary = {}
var route_payload: Dictionary = {}
var selected_stage_id := "CH01-N01"
var selected_map_node_id := "NODE_N01"
var pending_battle_token := ""
var selected_character_id := "CHR001"
var active_scenario_id := "SCN_PROLOGUE"
var battle_seed := 170817
var debug_options := {"unlock_all": false, "invincible": false, "enemy_multiplier": 1.0}

func _ready() -> void:
	new_game()

func new_game() -> void:
	pending_battle_token = ""
	var now := int(Time.get_unix_time_from_system())
	var roster: Dictionary = {}
	for character_value in DataRegistry.list_of("characters"):
		var character: Dictionary = character_value
		roster[character.id] = _default_roster_entry(character, str(character.get("id", "")) in ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005"])
	var weapons: Dictionary = {}
	for weapon in DataRegistry.list_of("weapons"):
		weapons[weapon.id] = {"owned": true, "level": 1, "xp": 0, "tier": 1}
	var inventory: Dictionary = {}
	for item in DataRegistry.list_of("items"):
		inventory[item.id] = 0
	inventory["CREDIT"] = 60000
	inventory["TRAINING_NOTE_M"] = 12
	inventory["TRAINING_NOTE_L"] = 3
	inventory["BREAK_CORE_T1"] = 10
	inventory["ROLE_TOKEN_T1"] = 5
	inventory["SKILL_BOOK_T1"] = 12
	inventory["SKILL_TOKEN_T1"] = 8
	inventory["ULT_BOOK_T1"] = 8
	inventory["WEAPON_CHIP_M"] = 10
	var initial_chapter_id := _initial_chapter_id()
	var initial_map_id := map_id_for_chapter(initial_chapter_id)
	var map_definition := ChapterMapLoaderScript.load_map(initial_map_id)
	var initial_map_state := ChapterMapProgressScript.create_default(map_definition)
	MapExplorationServiceScript.ensure_state(initial_map_state, map_definition)
	var chapter_progress: Dictionary = {}
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var chapter_id := str(chapter.get("id", ""))
		if not chapter_id.is_empty():
			chapter_progress[chapter_id] = {"normal_highest": 0, "hard_unlocked": false, "unlocked": chapter_id == initial_chapter_id}
	profile = {
		"save_schema_version": SAVE_SCHEMA_VERSION,
		"data_version": DataRegistry.data.get("data_version", "unknown"),
		"account": {"level": 20, "xp": 0, "stamina": 120, "stamina_updated_at": now},
		"roster": roster,
		"weapons": weapons,
		"inventory": inventory,
		"parties": [
			["CHR001", "CHR002", "CHR003", "CHR004", "CHR005"],
			["CHR001", "CHR002", "CHR003", "CHR006", "CHR008"],
			["CHR001", "CHR002", "CHR004", "CHR007", "CHR008"],
			["CHR001", "CHR002", "CHR003", "CHR005", "CHR008"],
			["CHR001", "CHR002", "CHR006", "CHR007", "CHR008"]
		],
		"active_party": 0,
		"chapter_progress": chapter_progress,
		"chapter_map": {initial_map_id: initial_map_state},
		"stage_stars": {},
		"first_clear": {},
		"story_flags": {},
		"pending_story_triggers": [],
		"read_commands": {},
		"relationship_levels": {},
		"hard_attempts": {"date": Time.get_date_string_from_system(), "counts": {}},
		"reward_pity_counters": {},
		"settings": SettingsService.persisted_values(),
		"tutorial_progress": {"title_seen": false, "map_basics_complete": false},
		"last_scenario_position": {},
		"claimed_rewards": [],
		"relay": RelayServiceScript.default_profile()
	}

func apply_loaded(loaded: Dictionary) -> void:
	profile = loaded
	if not profile.has("pending_story_triggers"): profile["pending_story_triggers"] = []
	if not profile.has("tutorial_progress") or not (profile.get("tutorial_progress") is Dictionary):
		profile["tutorial_progress"] = {}
	if not profile.tutorial_progress.has("title_seen"):
		profile.tutorial_progress["title_seen"] = false
	if not profile.tutorial_progress.has("map_basics_complete"):
		profile.tutorial_progress["map_basics_complete"] = false
	RelayServiceScript.ensure_profile(profile)
	pending_battle_token = ""
	_ensure_roster_entries()
	_ensure_chapter_progress_entries()
	if not profile.has("chapter_map"): profile["chapter_map"] = {}
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var chapter_id := str(chapter.get("id", ""))
		var map_id := map_id_for_chapter(chapter_id)
		if bool(_chapter_progress_state(chapter_id).get("unlocked", false)) and not profile.chapter_map.has(map_id):
			profile.chapter_map[map_id] = ChapterMapProgressScript.migrate_from_profile(profile, ChapterMapLoaderScript.load_map(map_id))
	for map_id_value in profile.chapter_map.keys():
		var map_id := str(map_id_value)
		var definition := ChapterMapLoaderScript.load_map(map_id)
		if definition.is_empty(): continue
		var map_state: Dictionary = profile.chapter_map[map_id]
		MapExplorationServiceScript.ensure_state(map_state, definition)
	# A reload cannot resume a live BattleSimulation.  Recover at the exact
	# pre-contact hex, leave the hostile pawn intact, and never mint rewards.
		if not map_state.get("pending_encounter", {}).is_empty():
			var pending: Dictionary = map_state.pending_encounter
			map_state.current_q = int(pending.get("return_q", map_state.current_q))
			map_state.current_r = int(pending.get("return_r", map_state.current_r))
			map_state.current_party_hex = [map_state.current_q, map_state.current_r]
			MapSimulationScript.disengage_after_battle(map_state, definition, str(pending.get("node_id", "")), Vector2i(int(map_state.current_q), int(map_state.current_r)))
			map_state.pending_encounter = {}
			pending_battle_token = ""
	SettingsService.apply_saved(profile.get("settings", {}))
	# Normalize legacy/tampered saves in memory immediately; the schema key is
	# retained, but build-only authority is never exported back as user data.
	profile["settings"] = SettingsService.persisted_values()
	refresh_stamina()
	reset_hard_attempts_if_needed()
	for map_id_value in profile.chapter_map.keys(): refresh_chapter_map_reveal(str(map_id_value))

func refresh_stamina() -> void:
	var account: Dictionary = profile.get("account", {})
	var updated := int(account.get("stamina_updated_at", Time.get_unix_time_from_system()))
	var now := int(Time.get_unix_time_from_system())
	var recovered := maxi(0, int((now - updated) / 360))
	var max_stamina := account_max_stamina()
	if recovered > 0:
		account.stamina = mini(max_stamina, int(account.get("stamina", 0)) + recovered)
		account.stamina_updated_at = updated + recovered * 360 if account.stamina < max_stamina else now

func account_max_stamina() -> int:
	var level := int(profile.get("account", {}).get("level", 1))
	var curve := DataRegistry.list_of("account_level_curve")
	if level > 0 and level <= curve.size():
		return int(curve[level - 1].get("max_stamina", 120))
	return 120

func reset_hard_attempts_if_needed() -> void:
	var today := Time.get_date_string_from_system()
	if profile.hard_attempts.get("date", "") != today:
		profile.hard_attempts = {"date": today, "counts": {}}

func inventory_count(item_id: String) -> int:
	return int(profile.get("inventory", {}).get(item_id, 0))

func add_item(item_id: String, amount: int) -> void:
	profile.inventory[item_id] = inventory_count(item_id) + amount
	EventBus.inventory_changed.emit()

func unlock_character(character_id: String) -> bool:
	if not profile.get("roster", {}).has(character_id):
		return false
	if bool(profile.roster[character_id].get("unlocked", false)):
		return false
	profile.roster[character_id].unlocked = true
	EventBus.inventory_changed.emit()
	return true

func can_pay(cost: Dictionary) -> bool:
	for item_id in cost:
		if inventory_count(item_id) < int(cost[item_id]):
			return false
	return true

func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		return false
	for item_id in cost:
		profile.inventory[item_id] = inventory_count(item_id) - int(cost[item_id])
	EventBus.inventory_changed.emit()
	return true

func get_party() -> Array:
	return profile.parties[int(profile.get("active_party", 0))]

func set_party_slot(slot: int, character_id: String) -> bool:
	if slot < 0 or slot >= 5 or not profile.roster.has(character_id) or not profile.roster[character_id].unlocked:
		return false
	var party: Array = get_party()
	var existing := party.find(character_id)
	if existing >= 0 and existing != slot:
		var previous = party[slot]
		party[slot] = character_id
		party[existing] = previous
	else:
		party[slot] = character_id
	return true

func create_party_snapshot() -> Array:
	return create_party_snapshot_for(get_party())

func create_party_snapshot_for(character_ids: Array) -> Array:
	var snapshot: Array = []
	for character_id_value in character_ids:
		var character_id := str(character_id_value)
		if character_id.is_empty() or not profile.get("roster", {}).has(character_id):
			continue
		var definition := DataRegistry.character(character_id).duplicate(true)
		if definition.is_empty():
			continue
		var progress: Dictionary = profile.roster[character_id].duplicate(true)
		var weapon_id := str(progress.get("equipped_weapon_id", ""))
		progress["weapon_state"] = profile.weapons.get(weapon_id, {}).duplicate(true)
		definition["progress"] = progress
		snapshot.append(definition)
	return snapshot

func relay_active() -> bool:
	return RelayServiceScript.is_active(profile)

func relay_current_stage_id() -> String:
	return RelayServiceScript.current_stage_id(profile)

func relay_current_squad() -> Array[String]:
	return RelayServiceScript.current_squad(profile)

func relay_party_snapshot() -> Array:
	return create_party_snapshot_for(relay_current_squad())

func is_stage_unlocked(stage_id: String) -> bool:
	if debug_unlock_all_enabled():
		return true
	var stage := DataRegistry.stage(stage_id)
	if stage.is_empty():
		return false
	var chapter_id := str(stage.get("chapter_id", ""))
	var chapter: Dictionary = DataRegistry.chapter(chapter_id)
	var progress := _chapter_progress_state(chapter_id)
	if chapter.is_empty() or not bool(progress.get("unlocked", false)): return false
	var route: Array = chapter.get("hard_stage_ids", []) if str(stage.get("mode", "")) == "HARD" else chapter.get("normal_stage_ids", [])
	var stage_index := route.find(stage_id)
	if stage_index < 0: return false
	if str(stage.get("mode", "")) == "HARD":
		return bool(progress.get("hard_unlocked", false)) and (stage_index == 0 or int(profile.stage_stars.get(str(route[stage_index - 1]), 0)) > 0)
	return stage_index == 0 or int(progress.get("normal_highest", 0)) >= stage_index

func debug_unlock_all_enabled() -> bool:
	return SettingsService.is_developer_mode() and bool(debug_options.get("unlock_all", false))

func effective_battle_debug_options() -> Dictionary:
	if not SettingsService.is_developer_mode():
		return {"invincible": false, "enemy_multiplier": 1.0}
	return {
		"invincible": bool(debug_options.get("invincible", false)),
		"enemy_multiplier": float(debug_options.get("enemy_multiplier", 1.0)),
	}

func can_enter_stage(stage_id: String) -> bool:
	return can_enter_stage_count(stage_id, 1)

func can_enter_stage_count(stage_id: String, count: int) -> bool:
	if count <= 0:
		return false
	refresh_stamina()
	reset_hard_attempts_if_needed()
	var stage := DataRegistry.stage(stage_id)
	if stage.is_empty() or not is_stage_unlocked(stage_id):
		return false
	if not SettingsService.is_developer_mode() and int(profile.account.stamina) < int(stage.stamina_cost) * count:
		return false
	if stage.mode == "HARD" and not SettingsService.is_developer_mode():
		return int(profile.hard_attempts.counts.get(stage_id, 0)) + count <= int(stage.daily_attempts)
	return true

func consume_stage_entry(stage_id: String) -> bool:
	return consume_stage_entries(stage_id, 1)

func consume_stage_entries(stage_id: String, count: int) -> bool:
	if not can_enter_stage_count(stage_id, count):
		return false
	var stage := DataRegistry.stage(stage_id)
	if not SettingsService.is_developer_mode():
		profile.account.stamina -= int(stage.stamina_cost) * count
	# Development-authorized builds may repeat HARD stages for QA without
	# mutating the player's daily-attempt ledger.  The public Release path keeps
	# the normal daily limit above and remains the only path that records usage.
	if stage.mode == "HARD" and not SettingsService.is_developer_mode():
		profile.hard_attempts.counts[stage_id] = int(profile.hard_attempts.counts.get(stage_id, 0)) + count
	return true

func begin_battle_transaction(stage_id: String) -> bool:
	if pending_battle_token != "": return false
	if not consume_stage_entry(stage_id): return false
	pending_battle_token = "%s:%d:%d" % [stage_id, int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	var map_state := chapter_map_state(map_id_for_stage(stage_id))
	if str(map_state.get("pending_encounter", {}).get("stage_id", "")) == stage_id:
		map_state.pending_encounter.token = pending_battle_token
	return true

func prepare_map_encounter(stage_id: String, node_id: String, return_coord: Vector2i, map_id := "CH01_MAP") -> bool:
	var state := chapter_map_state(map_id)
	var definition := ChapterMapLoaderScript.load_map(map_id)
	MapExplorationServiceScript.ensure_state(state, definition)
	if not state.get("pending_encounter", {}).is_empty(): return false
	var map_node := ChapterMapLoaderScript.node_by_id(definition, node_id)
	# Encounter presentation belongs to the existing pending-map transaction, but
	# is deliberately inert data: it supplies localized card/banner copy without
	# changing map, combat, reward, RNG, or save authority. It is consumed only
	# by the active contact transaction; the established reload-recovery policy
	# clears an unstarted contact, so it never replays a card or battle after a
	# browser refresh.
	var presentation_value: Variant = map_node.get("presentation", {})
	var presentation_payload: Dictionary = presentation_value.duplicate(true) if presentation_value is Dictionary else {}
	var contact_coord := Vector2i(int(state.get("current_q", 0)), int(state.get("current_r", 0)))
	var safe_return := _normalize_static_encounter_return(state, definition, node_id, return_coord, contact_coord)
	# A companion signal is presentation data attached to the same one-shot
	# encounter transaction as the battle.  It does not change combat, reward,
	# movement, or save authority; it merely lets the map transition and result
	# screen explain why this particular contact matters.
	var special_event: Dictionary = MapExplorationServiceScript.event_encounter_for_node(definition, node_id)
	var special_payload: Dictionary = {}
	if not special_event.is_empty():
		var recruitments: Array = MapExplorationServiceScript.recruitment_specs(special_event)
		var character_ids: Array[String] = []
		for recruitment_value in recruitments:
			character_ids.append(str(recruitment_value.get("character_id", "")))
		special_payload = {
			"event_encounter_id": str(special_event.get("event_encounter_id", "")),
			"event_kind": str(special_event.get("event_kind", "COMPANION")),
			"enemy_id": str(special_event.get("enemy_id", "")),
			"character_id": str(character_ids[0]) if not character_ids.is_empty() else "",
			"character_ids": character_ids,
			"title_key": str(special_event.get("title_key", "")),
			"body_key": str(special_event.get("body_key", "")),
			"contact_outcome_key": str(special_event.get("contact_outcome_key", "")),
			"pre_battle_dialogue": special_event.get("pre_battle_dialogue", []).duplicate(true),
			"recruitment_timing": str(special_event.get("recruitment_timing", "")),
			"recruit_after_stage_id": str(special_event.get("recruit_after_stage_id", "")),
		}
	state.pending_encounter = {
		"stage_id": stage_id,
		"node_id": node_id,
		"return_q": safe_return.x,
		"return_r": safe_return.y,
		"contact_q": contact_coord.x,
		"contact_r": contact_coord.y,
		"token": "",
		"presentation": presentation_payload,
		"special_event": special_payload,
	}
	return true

func pending_map_special_event(map_id := "CH01_MAP") -> Dictionary:
	var pending: Dictionary = chapter_map_state(map_id).get("pending_encounter", {})
	var special: Variant = pending.get("special_event", {})
	return special.duplicate(true) if special is Dictionary else {}

func pending_map_encounter_presentation(map_id := "CH01_MAP") -> Dictionary:
	var pending: Dictionary = chapter_map_state(map_id).get("pending_encounter", {})
	var presentation: Variant = pending.get("presentation", {})
	return presentation.duplicate(true) if presentation is Dictionary else {}

func _normalize_static_encounter_return(state: Dictionary, definition: Dictionary, node_id: String, requested: Vector2i, contact_coord: Vector2i) -> Vector2i:
	# The normal path passes the previous discrete hex and therefore needs no
	# repair.  Only a malformed/static-contact snapshot can equal the hostile
	# hex and strand the squad there after a defeat.
	if requested != contact_coord:
		return requested
	var patrol_enabled := false
	for patrol_value in definition.get("patrols", []):
		var patrol: Dictionary = patrol_value
		if str(patrol.get("encounter_id", "")) == node_id and bool(patrol.get("patrol_enabled", false)):
			patrol_enabled = true
			break
	# A live patrol can enter the stationary squad's hex; in that case the
	# requested coordinate really is the pre-contact party coordinate.
	if patrol_enabled:
		return requested
	var cached: Array = state.get("last_pre_contact_hex", [])
	if cached.size() >= 2:
		var candidate := Vector2i(int(cached[0]), int(cached[1]))
		if candidate != contact_coord and HexCoordScript.distance(candidate, contact_coord) == 1:
			return candidate
	# Additive-save compatibility: older saves have no cache. The visit log is
	# append ordered, so its latest adjacent non-hostile cell is the safest
	# deterministic recovery candidate.
	var visited: Array = state.get("visited_tiles", [])
	for index in range(visited.size() - 1, -1, -1):
		var parts := str(visited[index]).split(",")
		if parts.size() != 2:
			continue
		var candidate := Vector2i(int(parts[0]), int(parts[1]))
		if candidate != contact_coord and HexCoordScript.distance(candidate, contact_coord) == 1:
			return candidate
	return requested

func claim_pending_reward_once(stage_id: String, map_id := "CH01_MAP") -> bool:
	var state := chapter_map_state(map_id)
	var pending: Dictionary = state.get("pending_encounter", {})
	var token := pending_battle_token
	if not pending.is_empty() and str(pending.get("stage_id", "")) != stage_id: return false
	if token == "": return false
	if not state.has("processed_reward_tokens"): state.processed_reward_tokens = []
	if state.processed_reward_tokens.has(token): return false
	state.processed_reward_tokens.append(token)
	return true

func abandon_pending_map_encounter(map_id := "CH01_MAP") -> void:
	var state := chapter_map_state(map_id)
	var pending: Dictionary = state.get("pending_encounter", {})
	if not pending.is_empty():
		var return_coord := Vector2i(int(pending.get("return_q", state.current_q)), int(pending.get("return_r", state.current_r)))
		set_chapter_map_position(return_coord, "", map_id)
		MapSimulationScript.disengage_after_battle(state, ChapterMapLoaderScript.load_map(map_id), str(pending.get("node_id", "")), return_coord)
	state.pending_encounter = {}
	pending_battle_token = ""

func record_stage_clear(stage_id: String, stars: int) -> bool:
	var stage := DataRegistry.stage(stage_id)
	if stage.is_empty(): return false
	var chapter_id := str(stage.get("chapter_id", ""))
	var map_id := map_id_for_stage(stage_id)
	var map_state := chapter_map_state(map_id)
	var revealed_before: Array = map_state.get("revealed_tiles", []).duplicate()
	var unlocked_before := _canonical_unlocked_stage_ids()
	var first: bool = not bool(profile.first_clear.get(stage_id, false))
	profile.first_clear[stage_id] = true
	profile.stage_stars[stage_id] = maxi(int(profile.stage_stars.get(stage_id, 0)), stars)
	var chapter_progress := _chapter_progress_state(chapter_id)
	var chapter: Dictionary = DataRegistry.chapter(chapter_id)
	if str(stage.get("mode", "")) == "NORMAL":
		chapter_progress.normal_highest = maxi(int(chapter_progress.get("normal_highest", 0)), int(stage.get("stage_number", 0)))
		if int(stage.get("stage_number", 0)) == chapter.get("normal_stage_ids", []).size(): chapter_progress.hard_unlocked = true
	elif str(stage.get("mode", "")) == "HARD" and int(stage.get("stage_number", 0)) == chapter.get("hard_stage_ids", []).size():
		_unlock_next_chapter(chapter_id)
	refresh_chapter_map_reveal(map_id)
	for character_id in MapExplorationServiceScript.resolve_deferred_recruitments(map_state, ChapterMapLoaderScript.load_map(map_id), stage_id):
		unlock_character(character_id)
	# Canonical stage/reveal state is authoritative immediately.  The small
	# presentation payload is a persisted one-shot derived from that transition;
	# refresh/load can recompute the former without replaying the latter.
	if first and not pending_battle_token.is_empty():
		var newly_revealed: Array[String] = []
		for tile_key_value in map_state.get("revealed_tiles", []):
			var tile_key := str(tile_key_value)
			if not revealed_before.has(tile_key): newly_revealed.append(tile_key)
		var newly_unlocked: Array[String] = []
		for unlocked_stage_id in _canonical_unlocked_stage_ids():
			if not unlocked_before.has(unlocked_stage_id): newly_unlocked.append(unlocked_stage_id)
		ChapterMapProgressScript.queue_reveal_once(map_state, pending_battle_token, stage_id, newly_revealed, newly_unlocked)
	return first

func _canonical_unlocked_stage_ids() -> Array[String]:
	var unlocked: Array[String] = []
	for stage_value in DataRegistry.list_of("stages"):
		var stage_id := str(stage_value.get("id", ""))
		if not stage_id.is_empty() and is_stage_unlocked(stage_id): unlocked.append(stage_id)
	unlocked.sort()
	return unlocked

func queue_story_event(event_type: String, stage_id := "") -> bool:
	if not profile.has("pending_story_triggers"): profile["pending_story_triggers"] = []
	var queued := false
	for trigger_value in DataRegistry.list_of("chapter_story_triggers"):
		var trigger: Dictionary = trigger_value
		if str(trigger.get("event", "")) != event_type: continue
		if not stage_id.is_empty() and str(trigger.get("stage_id", "")) != stage_id: continue
		var trigger_id := str(trigger.get("id", ""))
		var completion_flag := str(trigger.get("completion_flag", ""))
		if trigger_id.is_empty() or (not completion_flag.is_empty() and bool(profile.story_flags.get(completion_flag, false))): continue
		if not profile.pending_story_triggers.has(trigger_id):
			profile.pending_story_triggers.append(trigger_id)
			queued = true
	profile.pending_story_triggers.sort_custom(func(a, b): return _story_trigger_priority(str(a)) < _story_trigger_priority(str(b)))
	return queued

func next_pending_story_trigger() -> Dictionary:
	for trigger_id_value in profile.get("pending_story_triggers", []):
		var trigger_id := str(trigger_id_value)
		for trigger_value in DataRegistry.list_of("chapter_story_triggers"):
			var trigger: Dictionary = trigger_value
			if str(trigger.get("id", "")) == trigger_id:
				var completion_flag := str(trigger.get("completion_flag", ""))
				if completion_flag.is_empty() or not bool(profile.story_flags.get(completion_flag, false)):
					return trigger
	return {}

func complete_story_trigger_for_scenario(scenario_id: String) -> void:
	var remaining: Array = []
	for trigger_id_value in profile.get("pending_story_triggers", []):
		var trigger_id := str(trigger_id_value)
		var completed := false
		for trigger_value in DataRegistry.list_of("chapter_story_triggers"):
			var trigger: Dictionary = trigger_value
			if str(trigger.get("id", "")) == trigger_id and str(trigger.get("scenario_id", "")) == scenario_id:
				var completion_flag := str(trigger.get("completion_flag", ""))
				if not completion_flag.is_empty(): profile.story_flags[completion_flag] = true
				completed = true
				break
		if not completed: remaining.append(trigger_id)
	profile.pending_story_triggers = remaining

func _initial_chapter_id() -> String:
	var initial_id := "CH01"
	var initial_number := 999999
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var number := int(chapter.get("number", initial_number))
		if number < initial_number:
			initial_number = number
			initial_id = str(chapter.get("id", initial_id))
	return initial_id

func map_id_for_chapter(chapter_id: String) -> String:
	var chapter: Dictionary = DataRegistry.chapter(chapter_id)
	return str(chapter.get("map_id", chapter_id + "_MAP"))

func map_id_for_stage(stage_id: String) -> String:
	var stage: Dictionary = DataRegistry.stage(stage_id)
	return map_id_for_chapter(str(stage.get("chapter_id", "CH01")))

func chapter_id_for_map(map_id: String) -> String:
	var definition: Dictionary = ChapterMapLoaderScript.load_map(map_id)
	if not definition.is_empty(): return str(definition.get("chapter_id", "CH01"))
	return map_id.trim_suffix("_MAP")

func _default_roster_entry(character: Dictionary, unlocked := false) -> Dictionary:
	var default_weapon := ""
	for weapon_value in DataRegistry.list_of("weapons"):
		var weapon: Dictionary = weapon_value
		if str(weapon.get("weapon_class", "")) == str(character.get("weapon_class", "")):
			default_weapon = str(weapon.get("id", ""))
			break
	return {
		"unlocked": unlocked,
		"level": 1,
		"xp": 0,
		"breakthrough": 0,
		"skills": {"normal": 1, "passive": 1, "ultimate": 1},
		"equipped_weapon_id": default_weapon,
		"relationship_level": 1,
		"relationship_xp": 0,
		"profile_unlocks": []
	}

func _ensure_roster_entries() -> void:
	if not profile.has("roster"): profile["roster"] = {}
	for character_value in DataRegistry.list_of("characters"):
		var character: Dictionary = character_value
		var character_id := str(character.get("id", ""))
		if character_id.is_empty() or profile.roster.has(character_id): continue
		# Additive content migration never grants new recruitment rewards.
		profile.roster[character_id] = _default_roster_entry(character, false)

func _ensure_chapter_progress_entries() -> void:
	if not profile.has("chapter_progress"): profile["chapter_progress"] = {}
	var initial_id := _initial_chapter_id()
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var chapter_id := str(chapter.get("id", ""))
		if chapter_id.is_empty(): continue
		if not profile.chapter_progress.has(chapter_id):
			profile.chapter_progress[chapter_id] = {"normal_highest": 0, "hard_unlocked": false, "unlocked": chapter_id == initial_id}
		var progress: Dictionary = profile.chapter_progress[chapter_id]
		if not progress.has("normal_highest"): progress["normal_highest"] = 0
		if not progress.has("hard_unlocked"): progress["hard_unlocked"] = false
		if not progress.has("unlocked"): progress["unlocked"] = chapter_id == initial_id

func _chapter_progress_state(chapter_id: String) -> Dictionary:
	_ensure_chapter_progress_entries()
	return profile.chapter_progress.get(chapter_id, {})

func _unlock_next_chapter(chapter_id: String) -> void:
	var current: Dictionary = DataRegistry.chapter(chapter_id)
	if current.is_empty(): return
	var current_number := int(current.get("number", 0))
	var next: Dictionary = {}
	for candidate_value in DataRegistry.list_of("chapters"):
		var candidate: Dictionary = candidate_value
		var candidate_number := int(candidate.get("number", 0))
		if candidate_number > current_number and (next.is_empty() or candidate_number < int(next.get("number", 999999))):
			next = candidate
	if next.is_empty(): return
	var next_id := str(next.get("id", ""))
	var next_progress := _chapter_progress_state(next_id)
	if bool(next_progress.get("unlocked", false)): return
	next_progress["unlocked"] = true
	var next_map_id := map_id_for_chapter(next_id)
	chapter_map_state(next_map_id)

func _story_trigger_priority(trigger_id: String) -> int:
	for trigger_value in DataRegistry.list_of("chapter_story_triggers"):
		var trigger: Dictionary = trigger_value
		if str(trigger.get("id", "")) == trigger_id: return int(trigger.get("priority", 9999))
	return 9999

func chapter_map_state(map_id := "CH01_MAP") -> Dictionary:
	if not profile.has("chapter_map"): profile["chapter_map"] = {}
	if not profile.chapter_map.has(map_id):
		profile.chapter_map[map_id] = ChapterMapProgressScript.migrate_from_profile(profile, ChapterMapLoaderScript.load_map(map_id))
	var state: Dictionary = profile.chapter_map[map_id]
	MapExplorationServiceScript.ensure_state(state, ChapterMapLoaderScript.load_map(map_id))
	return state

func refresh_chapter_map_reveal(map_id := "CH01_MAP") -> void:
	var state := chapter_map_state(map_id)
	var definition: Dictionary = ChapterMapLoaderScript.load_map(map_id)
	var chapter_id := str(definition.get("chapter_id", chapter_id_for_map(map_id)))
	var progress := _chapter_progress_state(chapter_id)
	var normal_highest := int(progress.get("normal_highest", 0))
	var hard_highest := 0
	for index in range(definition.get("hard_route", []).size()):
		if int(profile.stage_stars.get(str(definition.hard_route[index]), 0)) > 0: hard_highest = index + 1
	ChapterMapProgressScript.refresh_reveal(state, definition, normal_highest, hard_highest, bool(progress.get("hard_unlocked", false)))

func consume_chapter_map_pending_reveal(map_id := "CH01_MAP") -> Dictionary:
	return ChapterMapProgressScript.consume_pending_reveal(chapter_map_state(map_id))

func set_chapter_map_position(coord: Vector2i, node_id := "", map_id := "CH01_MAP") -> void:
	var state := chapter_map_state(map_id)
	state.current_q = coord.x
	state.current_r = coord.y
	state.current_party_hex = [coord.x, coord.y]
	state.last_map_camera_hex = [coord.x, coord.y]
	var key: String = HexCoordScript.key(coord)
	if not state.visited_tiles.has(key): state.visited_tiles.append(key)
	if node_id != "":
		state.last_selected_node = node_id
		selected_map_node_id = node_id

func apply_battle_result_to_map(stage_id: String, victory: bool, map_id := "CH01_MAP") -> bool:
	var definition: Dictionary = ChapterMapLoaderScript.load_map(map_id)
	var node: Dictionary = ChapterMapLoaderScript.node_for_stage(definition, stage_id)
	if node.is_empty(): return false
	var state := chapter_map_state(map_id)
	var pending: Dictionary = state.get("pending_encounter", {})
	# Result delivery is a one-shot transaction. A stale view callback after the
	# map has already consumed the token must not clear/unlock anything again.
	if pending.is_empty() and pending_battle_token == "": return false
	# A prepared map encounter is only a recoverable pre-contact snapshot.  It
	# does not become a victory authority until begin_battle_transaction minted
	# the live token.  Reject tokenless success so a stale/synthetic result cannot
	# remove the hostile pawn while canonical stage progress remains uncleared.
	if victory and pending_battle_token.is_empty(): return false
	if victory:
		set_chapter_map_position(Vector2i(int(node.q), int(node.r)), str(node.node_id), map_id)
	else:
		var return_coord := Vector2i(int(pending.get("return_q", state.current_q)), int(pending.get("return_r", state.current_r)))
		set_chapter_map_position(return_coord, "", map_id)
		MapSimulationScript.disengage_after_battle(state, definition, str(pending.get("node_id", "")), return_coord)
		state.pending_encounter = {}
		pending_battle_token = ""
		return true
	var token := pending_battle_token
	var applied: bool = ChapterMapProgressScript.record_clear_once(state, str(node.node_id), token)
	if applied:
		MapExplorationServiceScript.mark_encounter_cleared(state, str(node.node_id))
		var event_payload: Dictionary = pending.get("special_event", {})
		var recruitment := MapExplorationServiceScript.resolve_event_encounter_victory(
			state, definition, str(node.node_id), stage_id,
			str(event_payload.get("event_encounter_id", ""))
		)
		for character_id_value in recruitment.get("recruit_now_ids", []):
			unlock_character(str(character_id_value))
		# A contact may deliberately mark its second companion as "after this
		# stage" (for a boss aftermath). record_stage_clear ran before the
		# contact resolution, so consume that already-satisfied gate once here.
		# The recruitment state map keeps this idempotent across result callbacks.
		for character_id_value in MapExplorationServiceScript.resolve_deferred_recruitments(state, definition, stage_id):
			unlock_character(str(character_id_value))
	state.pending_encounter = {}
	pending_battle_token = ""
	refresh_chapter_map_reveal(map_id)
	return applied

func grant_all_materials(amount := 999) -> void:
	for item_id in profile.inventory:
		profile.inventory[item_id] = maxi(int(profile.inventory[item_id]), amount)
	profile.inventory.CREDIT = 9999999
	EventBus.inventory_changed.emit()
