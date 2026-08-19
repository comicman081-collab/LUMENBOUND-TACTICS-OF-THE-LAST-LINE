extends Node

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const ChapterMapLoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const ChapterMapProgressScript := preload("res://chapter_map/model/chapter_map_progress.gd")
const MapExplorationServiceScript := preload("res://chapter_map/model/map_exploration_service.gd")

const SAVE_SCHEMA_VERSION := 4
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
	for index in range(DataRegistry.list_of("characters").size()):
		var character: Dictionary = DataRegistry.list_of("characters")[index]
		var default_weapon := ""
		for weapon in DataRegistry.list_of("weapons"):
			if weapon.weapon_class == character.weapon_class:
				default_weapon = weapon.id
				break
		roster[character.id] = {
			"unlocked": index < 5,
			"level": 1,
			"xp": 0,
			"breakthrough": 0,
			"skills": {"normal": 1, "passive": 1, "ultimate": 1},
			"equipped_weapon_id": default_weapon,
			"relationship_level": 1,
			"relationship_xp": 0,
			"profile_unlocks": []
		}
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
	var map_definition := ChapterMapLoaderScript.load_map("CH01_MAP")
	var initial_map_state := ChapterMapProgressScript.create_default(map_definition)
	MapExplorationServiceScript.ensure_state(initial_map_state, map_definition)
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
		"chapter_progress": {"CH01": {"normal_highest": 0, "hard_unlocked": false}},
		"chapter_map": {"CH01_MAP": initial_map_state},
		"stage_stars": {},
		"first_clear": {},
		"story_flags": {},
		"read_commands": {},
		"relationship_levels": {},
		"hard_attempts": {"date": Time.get_date_string_from_system(), "counts": {}},
		"reward_pity_counters": {},
		"settings": SettingsService.values.duplicate(true),
		"tutorial_progress": {"title_seen": false},
		"last_scenario_position": {},
		"claimed_rewards": []
	}

func apply_loaded(loaded: Dictionary) -> void:
	profile = loaded
	pending_battle_token = ""
	if not profile.has("chapter_map") or not profile.chapter_map.has("CH01_MAP"):
		profile["chapter_map"] = {"CH01_MAP": ChapterMapProgressScript.migrate_from_profile(profile, ChapterMapLoaderScript.load_map("CH01_MAP"))}
	var map_state := chapter_map_state("CH01_MAP")
	MapExplorationServiceScript.ensure_state(map_state, ChapterMapLoaderScript.load_map("CH01_MAP"))
	# A reload cannot resume a live BattleSimulation.  Recover at the exact
	# pre-contact hex, leave the hostile pawn intact, and never mint rewards.
	if not map_state.get("pending_encounter", {}).is_empty():
		var pending: Dictionary = map_state.pending_encounter
		map_state.current_q = int(pending.get("return_q", map_state.current_q))
		map_state.current_r = int(pending.get("return_r", map_state.current_r))
		map_state.current_party_hex = [map_state.current_q, map_state.current_r]
		map_state.pending_encounter = {}
		pending_battle_token = ""
	SettingsService.apply_saved(profile.get("settings", {}))
	refresh_stamina()
	reset_hard_attempts_if_needed()
	refresh_chapter_map_reveal()

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
	var snapshot: Array = []
	for character_id in get_party():
		var definition := DataRegistry.character(character_id).duplicate(true)
		var progress: Dictionary = profile.roster[character_id].duplicate(true)
		var weapon_id := str(progress.get("equipped_weapon_id", ""))
		progress["weapon_state"] = profile.weapons.get(weapon_id, {}).duplicate(true)
		definition["progress"] = progress
		snapshot.append(definition)
	return snapshot

func is_stage_unlocked(stage_id: String) -> bool:
	if debug_options.unlock_all:
		return true
	var stage := DataRegistry.stage(stage_id)
	if stage.is_empty():
		return false
	if stage.mode == "HARD":
		if not bool(profile.chapter_progress.CH01.get("hard_unlocked", false)): return false
		var hard_number := int(stage.stage_number)
		return hard_number == 1 or int(profile.stage_stars.get("CH01-H%02d" % (hard_number - 1), 0)) > 0
	var number := int(stage.stage_number)
	return number == 1 or int(profile.chapter_progress.CH01.get("normal_highest", 0)) >= number - 1

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
	if not SettingsService.values.developer_mode and int(profile.account.stamina) < int(stage.stamina_cost) * count:
		return false
	if stage.mode == "HARD" and not SettingsService.values.developer_mode:
		return int(profile.hard_attempts.counts.get(stage_id, 0)) + count <= int(stage.daily_attempts)
	return true

func consume_stage_entry(stage_id: String) -> bool:
	return consume_stage_entries(stage_id, 1)

func consume_stage_entries(stage_id: String, count: int) -> bool:
	if not can_enter_stage_count(stage_id, count):
		return false
	var stage := DataRegistry.stage(stage_id)
	if not SettingsService.values.developer_mode:
		profile.account.stamina -= int(stage.stamina_cost) * count
	if stage.mode == "HARD":
		profile.hard_attempts.counts[stage_id] = int(profile.hard_attempts.counts.get(stage_id, 0)) + count
	return true

func begin_battle_transaction(stage_id: String) -> bool:
	if pending_battle_token != "": return false
	if not consume_stage_entry(stage_id): return false
	pending_battle_token = "%s:%d:%d" % [stage_id, int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	var map_state := chapter_map_state()
	if str(map_state.get("pending_encounter", {}).get("stage_id", "")) == stage_id:
		map_state.pending_encounter.token = pending_battle_token
	return true

func prepare_map_encounter(stage_id: String, node_id: String, return_coord: Vector2i, map_id := "CH01_MAP") -> bool:
	var state := chapter_map_state(map_id)
	MapExplorationServiceScript.ensure_state(state, ChapterMapLoaderScript.load_map(map_id))
	if not state.get("pending_encounter", {}).is_empty(): return false
	state.pending_encounter = {"stage_id": stage_id, "node_id": node_id, "return_q": return_coord.x, "return_r": return_coord.y, "token": ""}
	return true

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
		set_chapter_map_position(Vector2i(int(pending.get("return_q", state.current_q)), int(pending.get("return_r", state.current_r))), "", map_id)
	state.pending_encounter = {}
	pending_battle_token = ""

func record_stage_clear(stage_id: String, stars: int) -> bool:
	var first: bool = not bool(profile.first_clear.get(stage_id, false))
	profile.first_clear[stage_id] = true
	profile.stage_stars[stage_id] = maxi(int(profile.stage_stars.get(stage_id, 0)), stars)
	var stage := DataRegistry.stage(stage_id)
	if stage.mode == "NORMAL":
		profile.chapter_progress.CH01.normal_highest = maxi(int(profile.chapter_progress.CH01.normal_highest), int(stage.stage_number))
		if int(stage.stage_number) == 10:
			profile.chapter_progress.CH01.hard_unlocked = true
	refresh_chapter_map_reveal()
	return first

func chapter_map_state(map_id := "CH01_MAP") -> Dictionary:
	if not profile.has("chapter_map"): profile["chapter_map"] = {}
	if not profile.chapter_map.has(map_id):
		profile.chapter_map[map_id] = ChapterMapProgressScript.migrate_from_profile(profile, ChapterMapLoaderScript.load_map(map_id))
	var state: Dictionary = profile.chapter_map[map_id]
	MapExplorationServiceScript.ensure_state(state, ChapterMapLoaderScript.load_map(map_id))
	return state

func refresh_chapter_map_reveal(map_id := "CH01_MAP") -> void:
	var state := chapter_map_state(map_id)
	var normal_highest := int(profile.chapter_progress.CH01.get("normal_highest", 0))
	var hard_highest := 0
	for number in range(1, 6):
		if int(profile.stage_stars.get("CH01-H%02d" % number, 0)) > 0: hard_highest = number
	ChapterMapProgressScript.refresh_reveal(state, ChapterMapLoaderScript.load_map(map_id), normal_highest, hard_highest, bool(profile.chapter_progress.CH01.get("hard_unlocked", false)))

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
	if victory:
		set_chapter_map_position(Vector2i(int(node.q), int(node.r)), str(node.node_id), map_id)
	else:
		var return_coord := Vector2i(int(pending.get("return_q", state.current_q)), int(pending.get("return_r", state.current_r)))
		set_chapter_map_position(return_coord, "", map_id)
		state.pending_encounter = {}
		pending_battle_token = ""
		return true
	var token := pending_battle_token if pending_battle_token != "" else "%s:RECOVERED" % stage_id
	var applied: bool = ChapterMapProgressScript.record_clear_once(state, str(node.node_id), token)
	if applied: MapExplorationServiceScript.mark_encounter_cleared(state, str(node.node_id))
	state.pending_encounter = {}
	pending_battle_token = ""
	refresh_chapter_map_reveal(map_id)
	return applied

func grant_all_materials(amount := 999) -> void:
	for item_id in profile.inventory:
		profile.inventory[item_id] = maxi(int(profile.inventory[item_id]), amount)
	profile.inventory.CREDIT = 9999999
	EventBus.inventory_changed.emit()
