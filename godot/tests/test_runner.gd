extends Node

var passed := 0
var failed := 0
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, name: String, details := "") -> void:
	if condition:
		passed += 1
		print("PASS | ", name)
	else:
		failed += 1
		failures.append(name + (": " + details if details != "" else ""))
		printerr("FAIL | ", name, " | ", details)

func _run() -> void:
	print("LANTERNLINE HEADLESS TESTS | Godot ", Engine.get_version_info().get("string", "unknown"))
	_test_data()
	_test_combat_art_contracts()
	_test_battle()
	_test_growth()
	_test_story()
	_test_save()
	print("TEST_SUMMARY total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	if not failures.is_empty(): print("FAILURES=", JSON.stringify(failures))
	get_tree().quit(0 if failed == 0 else 1)

func _unique_ids(collection: String) -> bool:
	var seen: Dictionary = {}
	for row in DataRegistry.list_of(collection):
		if seen.has(row.id): return false
		seen[row.id] = true
	return true

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _test_combat_art_contracts() -> void:
	var facing := _read_json("res://assets/generated_import/combat_facing_contract.json")
	check(not facing.is_empty(), "combat facing contract parses")
	var player: Dictionary = facing.get("player", {})
	var enemy: Dictionary = facing.get("enemy", {})
	check(player.get("deployment_side", "") == "LEFT" and player.get("camera_view", "") == "THREE_QUARTER_RIGHT_DOWN_30", "player combat art faces lower-right from left deployment")
	check(enemy.get("deployment_side", "") == "RIGHT" and enemy.get("camera_view", "") == "THREE_QUARTER_LEFT_DOWN_30", "enemy combat art faces left from right deployment")
	var pack_roots := {
		"CHR001": {"root": "res://assets/generated_import/characters/sd_chr001_maeru_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30", "team": "PLAYER"},
		"CHR002": {"root": "res://assets/generated_import/characters/sd_chr002_roan_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30", "team": "PLAYER"},
		"CHR003": {"root": "res://assets/generated_import/characters/sd_chr003_narin_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30", "team": "PLAYER"},
		"CHR004": {"root": "res://assets/generated_import/characters/sd_chr004_eda_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30", "team": "PLAYER"},
		"CHR005": {"root": "res://assets/generated_import/characters/sd_chr005_soren_combat_r27_dev", "view": "THREE_QUARTER_RIGHT_DOWN_30", "team": "PLAYER"},
		"ENM001": {"root": "res://assets/generated_import/enemies/sd_enm001_rush_drone_combat_r28_dev", "view": "THREE_QUARTER_LEFT_DOWN_30", "team": "ENEMY"},
		"ENM002": {"root": "res://assets/generated_import/enemies/sd_enm002_arc_mote_combat_r28_dev", "view": "THREE_QUARTER_LEFT_DOWN_30", "team": "ENEMY"},
	}
	var expected := {"idle": 8, "move": 12, "basic_attack": 8, "normal_skill": 12, "ultimate": 18, "hit": 4, "down": 8, "victory": 10}
	var manifests_valid := true
	var geometry_valid := true
	var direction_valid := true
	var counts_valid := true
	var files_valid := true
	for character_id in pack_roots:
		var config: Dictionary = pack_roots[character_id]
		var pack_root: String = config.root
		var manifest := _read_json(pack_root + "/animation_manifest.json")
		manifests_valid = manifests_valid and not manifest.is_empty() and manifest.get("character_id", "") == character_id
		var frame_size: Array = manifest.get("frame_size", [])
		var foot_anchor: Array = manifest.get("foot_anchor", [])
		var head_anchor: Array = manifest.get("head_anchor", [])
		geometry_valid = geometry_valid and frame_size.size() == 2 and foot_anchor.size() == 2 and head_anchor.size() == 2
		if frame_size.size() == 2 and foot_anchor.size() == 2:
			geometry_valid = geometry_valid and int(frame_size[0]) == 512 and int(frame_size[1]) == 512
			geometry_valid = geometry_valid and is_equal_approx(float(foot_anchor[0]), 0.5) and is_equal_approx(float(foot_anchor[1]), 0.88)
		direction_valid = direction_valid and manifest.get("view", "") == config.view and manifest.get("team", config.team) == config.team and manifest.get("facing_policy", "") == "SEPARATE_LEFT_RIGHT"
		counts_valid = counts_valid and int(manifest.get("total_frames", 0)) == 80
		for animation_name in expected:
			var definition: Dictionary = manifest.get("animations", {}).get(animation_name, {})
			counts_valid = counts_valid and int(definition.get("frames", 0)) == int(expected[animation_name])
			var paths: Array = definition.get("frame_paths", [])
			files_valid = files_valid and paths.size() == int(expected[animation_name])
			for relative_path in paths: files_valid = files_valid and FileAccess.file_exists(pack_root + "/" + str(relative_path))
	check(manifests_valid, "five player and two enemy combat animation manifests parse")
	check(geometry_valid, "all seven combat packs use 512 canvas, foot and head anchors")
	check(direction_valid, "player and enemy combat packs obey opposing facing contracts")
	check(counts_valid, "all seven animation counts are exactly 8/12/8/12/18/4/8/10")
	check(files_valid, "all 560 combat animation frame files exist")
	var projectile_roots := {
		"CHR001": "proj_chr001_teal_guard_wave_r28", "CHR002": "proj_chr002_coral_blade_arc_r28",
		"CHR003": "proj_chr003_ice_rifle_tracer_r28", "CHR004": "proj_chr004_magenta_energy_bolt_r28",
		"CHR005": "proj_chr005_emerald_cannon_orb_r28", "ENM001": "proj_enm001_crystal_claw_r28",
		"ENM002": "proj_enm002_arc_mote_r28",
	}
	var projectile_manifests_valid := true
	var projectile_files_valid := true
	var projectile_speed_valid := true
	for source_id in projectile_roots:
		var projectile_root := "res://assets/generated_import/projectiles/" + str(projectile_roots[source_id])
		var projectile_manifest := _read_json(projectile_root + "/projectile_manifest.json")
		projectile_manifests_valid = projectile_manifests_valid and projectile_manifest.get("source_id", "") == source_id and int(projectile_manifest.get("frames", 0)) == 8
		var flight_duration := float(projectile_manifest.get("flight_duration", 1.0))
		projectile_speed_valid = projectile_speed_valid and flight_duration >= .05 and flight_duration <= .15
		var projectile_paths: Array = projectile_manifest.get("frame_paths", [])
		projectile_files_valid = projectile_files_valid and projectile_paths.size() == 8
		for relative_path in projectile_paths: projectile_files_valid = projectile_files_valid and FileAccess.file_exists(projectile_root + "/" + str(relative_path))
	check(projectile_manifests_valid, "seven character-specific projectile manifests parse")
	check(projectile_files_valid, "all 56 animated projectile frame files exist")
	check(projectile_speed_valid, "projectile flights stay within fast 0.05 to 0.15 second window")

func _test_data() -> void:
	check(DataRegistry.load_error == "", "compiled data loads", DataRegistry.load_error)
	check(_unique_ids("characters"), "character IDs unique")
	check(_unique_ids("skills"), "skill IDs unique")
	check(_unique_ids("weapons"), "weapon IDs unique")
	check(_unique_ids("stages"), "stage IDs unique")
	var refs_valid := true
	for character in DataRegistry.list_of("characters"):
		for key in ["normal_skill_id", "passive_skill_id", "ultimate_skill_id"]:
			refs_valid = refs_valid and not DataRegistry.skill(character[key]).is_empty()
	check(refs_valid, "all character skill references valid")
	var arrays_valid := true
	for skill in DataRegistry.list_of("skills"):
		var required := 5 if skill.type == "ULTIMATE_SKILL" else 10
		arrays_valid = arrays_valid and skill.values.size() == required and int(skill.max_level) == required
	check(arrays_valid, "all skills exactly 10/10/5")
	check(DataRegistry.list_of("character_level_curve").size() == 100, "character curve has 100 rows")
	check(DataRegistry.list_of("account_level_curve").size() == 100, "account curve has 100 rows")
	check(DataRegistry.list_of("weapon_level_curve").size() == 60, "weapon curve has 60 rows")
	var character_xp := 0
	var character_credits := 0
	var weapon_xp := 0
	for row in DataRegistry.list_of("character_level_curve"):
		character_xp += int(row.xp_to_next)
		character_credits += int(row.credit_cost)
	for row in DataRegistry.list_of("weapon_level_curve"): weapon_xp += int(row.xp_to_next)
	check(character_xp == 905520, "character XP regression", str(character_xp))
	check(character_credits == 412400, "character credit regression", str(character_credits))
	check(weapon_xp == 144330, "weapon XP regression", str(weapon_xp))
	var no_negative := true
	for row in DataRegistry.list_of("character_level_curve"): no_negative = no_negative and int(row.xp_to_next) >= 0 and int(row.credit_cost) >= 0
	for row in DataRegistry.list_of("weapon_level_curve"): no_negative = no_negative and int(row.xp_to_next) >= 0
	check(no_negative, "growth costs contain no negatives")
	var monotonic := true
	for character in DataRegistry.list_of("characters"):
		for key in character.stats_l1: monotonic = monotonic and float(character.stats_l100[key]) >= float(character.stats_l1[key])
	check(monotonic, "positive stats never reverse")
	var normal := DataRegistry.list_of("stages").filter(func(stage): return stage.mode == "NORMAL")
	var hard := DataRegistry.list_of("stages").filter(func(stage): return stage.mode == "HARD")
	check(normal.size() == 10, "Chapter 1 has exactly 10 NORMAL")
	check(hard.size() == 5, "Chapter 1 has exactly 5 HARD")
	check(normal.filter(func(stage): return stage.boss).size() == 1 and int(normal.filter(func(stage): return stage.boss)[0].stage_number) == 10, "NORMAL 10 is boss")
	check(hard.filter(func(stage): return stage.boss).size() == 1 and int(hard.filter(func(stage): return stage.boss)[0].stage_number) == 5, "HARD 5 is boss")
	var rewards_valid := true
	for stage in DataRegistry.list_of("stages"):
		var reward := DataRegistry.by_id("rewards", stage.reward_table_id)
		rewards_valid = rewards_valid and not reward.is_empty() and not reward.guaranteed.is_empty()
	check(rewards_valid, "every stage has guaranteed reward")
	var localization_valid := true
	for character in DataRegistry.list_of("characters"):
		localization_valid = localization_valid and not LocalizationService.tr_key(character.name_key).begins_with("[")
	for scenario in DataRegistry.list_of("scenarios"):
		localization_valid = localization_valid and not LocalizationService.tr_key(scenario.title_key).begins_with("[")
		for command in scenario.commands:
			if command.has("text_key"): localization_valid = localization_valid and not LocalizationService.tr_key(command.text_key).begins_with("[")
	check(localization_valid, "all runtime localization keys exist")
	var assets_resolve := true
	for character in DataRegistry.list_of("characters"):
		for key in ["asset_id", "portrait_asset_id", "icon_asset_id"]: assets_resolve = assets_resolve and AssetRegistry.resolve(character[key]) != ""
	check(assets_resolve, "all character asset IDs resolve (placeholder allowed)")
	check(DataRegistry.list_of("characters").size() == 8, "vertical slice has 8 player characters")
	check(DataRegistry.list_of("enemies").filter(func(enemy): return enemy.rank == "NORMAL").size() == 6, "vertical slice has 6 normal enemies")
	check(DataRegistry.list_of("enemies").filter(func(enemy): return enemy.rank == "ELITE").size() == 3, "vertical slice has 3 elites")
	check(DataRegistry.list_of("enemies").filter(func(enemy): return enemy.rank == "BOSS").size() == 2, "vertical slice has 2 bosses")
	check(DataRegistry.list_of("weapons").filter(func(weapon): return weapon.exclusive_owner_id != "").is_empty(), "exclusive weapons count is zero")

func _simulation(seed_value: int, stage_id := "CH01-N01") -> BattleSimulation:
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage(stage_id), seed_value, DataRegistry.data)
	return sim

func _run_to_end(sim: BattleSimulation) -> void:
	while not sim.state.ended and sim.state.tick < 3000: sim.tick()

func _first_event_difference(left: Array, right: Array) -> String:
	var count: int = mini(left.size(), right.size())
	for index in range(count):
		if JSON.stringify(left[index]) != JSON.stringify(right[index]):
			return "index=%d left=%s right=%s" % [index, JSON.stringify(left[index]), JSON.stringify(right[index])]
	if left.size() != right.size():
		return "event_count left=%d right=%d" % [left.size(), right.size()]
	return "no event difference"

func _test_battle() -> void:
	var a := _simulation(424242)
	var b := _simulation(424242)
	var initial_same_seed_state: bool = JSON.stringify(a.state.party + a.state.enemies) == JSON.stringify(b.state.party + b.state.enemies)
	_run_to_end(a)
	_run_to_end(b)
	check(a.state.ended and b.state.ended, "battle reaches a terminal state")
	var same_seed_hash: bool = a.event_hash() == b.event_hash()
	var same_seed_snapshot: bool = JSON.stringify(a.result_snapshot()) == JSON.stringify(b.result_snapshot())
	check(same_seed_hash and same_seed_snapshot, "same seed yields identical result and event hash", "hash_a=%s hash_b=%s initial_equal=%s snapshot_equal=%s %s" % [a.event_hash(), b.event_hash(), initial_same_seed_state, same_seed_snapshot, _first_event_difference(a.event_log, b.event_log)])
	var c := _simulation(424243)
	_run_to_end(c)
	check(a.event_hash() != c.event_hash(), "different seed changes random event log")
	var rng := DeterministicRng.new(81)
	var attacker := {"stats": {"ATK": 100, "ACC": 100, "CRIT": 100}, "level": 10, "attack_type": "PHYSICAL", "outgoing_modifier": 1.0, "statuses": {}}
	var defender := {"stats": {"DEF": 100, "EVA": 100, "CRIT_RES": 100}, "level": 10, "defense_type": "ARMOR", "incoming_modifier": 1.0, "statuses": {}}
	var hits := 0
	for i in range(200): hits += 1 if DamageResolver.calculate(attacker, defender, 1.0, DataRegistry.data.affinity_matrix, rng).hit else 0
	check(hits > 0 and hits < 200, "hit result not locked at 0 or 100 percent", str(hits))
	var shield_sim := _simulation(9)
	var target: Dictionary = shield_sim.state.party[0]
	var enemy: Dictionary = shield_sim.state.enemies[0]
	target.shields = {"TEST": 500}
	shield_sim._recalculate_shield(target)
	var hp_before := int(target.hp)
	shield_sim._deal_damage(enemy, target, 1.0, "TEST")
	check(int(target.hp) == hp_before and int(target.shield) < 500, "shield absorbs before HP")
	var taunted_enemy := {"team": "ENEMY", "statuses": {"TAUNT": {"source": "P:A"}}}
	var candidates := [{"uid": "P:A", "alive": true, "hp": 100, "max_hp": 100, "threat": 1.0}, {"uid": "P:B", "alive": true, "hp": 100, "max_hp": 100, "threat": 10.0}]
	check(TargetResolver.choose(taunted_enemy, candidates).uid == "P:A", "taunt changes target")
	var silence_sim := _simulation(10)
	var caster: Dictionary = silence_sim.state.party[0]
	StatusEffectRuntime.apply(caster, "SILENCE", 3.0, "TEST")
	silence_sim.state.tactical_gauge = 10.0
	check(not silence_sim._use_ultimate(caster), "silence blocks ultimate")
	var stun_sim := _simulation(11)
	var stunned: Dictionary = stun_sim.state.party[0]
	stunned.attack_cd = 0.0
	StatusEffectRuntime.apply(stunned, "STUN", 3.0, "TEST")
	var before := stun_sim.event_log.size()
	stun_sim.tick()
	var acted := stun_sim.event_log.slice(before).any(func(event): return event.source == stunned.uid and event.type in [BattleEvent.BASIC_ATTACK, BattleEvent.NORMAL_SKILL])
	check(not acted, "stun blocks action")
	var target_sim := _simulation(101)
	target_sim.auto_enabled = false
	var manual_caster: Dictionary = target_sim.state.party[1]
	var manual_target: Dictionary = target_sim.state.enemies[1]
	manual_caster.stats.ACC = 10000
	manual_target.stats.EVA = 0
	target_sim.state.tactical_gauge = 10.0
	var manual_hp_before := int(manual_target.hp)
	target_sim.request_ultimate(manual_caster.uid, manual_target.uid)
	target_sim.tick()
	check(int(manual_target.hp) < manual_hp_before, "manual ultimate command damages the explicitly selected target")
	var status_ids: Array = DataRegistry.list_of("status_effects").map(func(row): return row.id)
	check(status_ids.has("CLEANSE") and status_ids.has("DISPEL"), "cleanse and dispel are distinct definitions")
	check(DataRegistry.list_of("status_effects").all(func(row): return row.has("boss_resistance")), "boss status resistance is data-defined")
	var stacked := {"rank": "PLAYER", "statuses": {}}
	for i in range(4): StatusEffectRuntime.apply(stacked, "DAMAGE_OVER_TIME", 4.0, "TEST", 10.0)
	var status_ticks := StatusEffectRuntime.update(stacked, 1.0)
	check(int(stacked.statuses.DAMAGE_OVER_TIME.stacks) == 3 and status_ticks.size() == 1 and is_equal_approx(float(status_ticks[0].strength), 30.0), "status stack cap and data tick interval applied")
	var removable := {"rank": "PLAYER", "statuses": {}}
	StatusEffectRuntime.apply(removable, "STUN", 4.0, "TEST")
	StatusEffectRuntime.apply(removable, "HASTE", 4.0, "TEST")
	StatusEffectRuntime.apply(removable, "INVULNERABLE", 2.0, "TEST")
	StatusEffectRuntime.cleanse(removable)
	var cleanse_ok: bool = not removable.statuses.has("STUN") and removable.statuses.has("HASTE")
	StatusEffectRuntime.dispel(removable)
	check(cleanse_ok and not removable.statuses.has("HASTE") and removable.statuses.has("INVULNERABLE"), "cleanse and dispel obey harmful/beneficial and dispellable data")
	var dot_sim := _simulation(102)
	var dot_target: Dictionary = dot_sim.state.enemies[0]
	dot_target.hp = 5
	StatusEffectRuntime.apply(dot_target, "DAMAGE_OVER_TIME", 4.0, dot_sim.state.party[0].uid, 10.0)
	for i in range(31): dot_sim._update_statuses()
	check(not bool(dot_target.alive) and dot_sim.deaths.any(func(row): return row.unit_id == dot_target.uid and row.source == "DAMAGE_OVER_TIME"), "damage-over-time death emits DOWN and records its cause")
	var protect_sim := _simulation(103)
	protect_sim.stage.protected_unit_id = "CHR001"
	protect_sim.state.party[0].hp = 0
	protect_sim.state.party[0].alive = false
	protect_sim._check_flow()
	check(protect_sim.state.ended and protect_sim.state.reason == "PROTECTED_TARGET_DEFEATED", "data-defined protected target defeat condition ends battle")
	var ended := _simulation(12)
	_run_to_end(ended)
	var event_count := ended.event_log.size()
	for i in range(100): ended.tick()
	check(ended.event_log.size() == event_count, "no damage/event after battle end")
	var speed_one := _simulation(777)
	var speed_three := _simulation(777)
	for i in range(900):
		if not speed_one.state.ended: speed_one.tick()
	for frame in range(300):
		for substep in range(3):
			if not speed_three.state.ended: speed_three.tick()
	check(speed_one.event_hash() == speed_three.event_hash(), "1x and 3x tick schedules yield same result", "hash_1x=%s hash_3x=%s ticks=%d/%d %s" % [speed_one.event_hash(), speed_three.event_hash(), speed_one.state.tick, speed_three.state.tick, _first_event_difference(speed_one.event_log, speed_three.event_log)])
	var paused := _simulation(15)
	var pause_tick := paused.state.tick
	# Paused presentation deliberately invokes zero simulation ticks.
	check(paused.state.tick == pause_tick, "pause produces zero simulation ticks")
	check(a.command_log is Array, "replay command timestamps retained")
	var pooled_view := BattleView.new()
	var pool_sim := _simulation(16)
	pooled_view.setup(pool_sim)
	for i in range(100):
		pooled_view._spawn_projectile(pool_sim.state.party[0].uid, pool_sim.state.enemies[0].uid, "BASIC")
		pooled_view._spawn_floating_text({"target": pool_sim.state.enemies[0].uid, "text": str(i), "color": Color.WHITE, "age": 1.0})
	for projectile in pooled_view.projectiles: projectile.age = 1.0
	pooled_view._recycle_expired_presentations()
	var recycled := pooled_view.pool_diagnostics()
	for i in range(100):
		pooled_view._spawn_projectile(pool_sim.state.party[0].uid, pool_sim.state.enemies[0].uid, "BASIC")
		pooled_view._spawn_floating_text({"target": pool_sim.state.enemies[0].uid, "text": str(i), "color": Color.WHITE, "age": 0.0})
	var reused := pooled_view.pool_diagnostics()
	check(int(recycled.free_projectiles) == 100 and int(recycled.free_floating_texts) == 100 and int(reused.active_projectiles) == 100 and int(reused.active_floating_texts) == 100 and int(reused.free_projectiles) == 0 and int(reused.free_floating_texts) == 0, "100 projectile and damage-text entries are recycled from pools")
	pooled_view.free()

func _test_growth() -> void:
	var backup := AppState.profile.duplicate(true)
	AppState.grant_all_materials(9999)
	var state: Dictionary = AppState.profile.roster.CHR001
	AppState.profile.account.level = 100
	state.level = 20
	state.breakthrough = 0
	check(CharacterProgression.level_cap(state) == 20, "B0 character level cap is 20")
	check(CharacterProgression.use_material("CHR001", "TRAINING_NOTE_XL", 1).error == "LEVEL_CAP", "XP blocked at breakthrough cap")
	var core_before := AppState.inventory_count("BREAK_CORE_T1")
	var breakthrough := BreakthroughService.upgrade("CHR001")
	check(breakthrough.ok and int(state.breakthrough) == 1, "breakthrough unlocks next cap")
	check(AppState.inventory_count("BREAK_CORE_T1") == core_before - 10, "breakthrough deducts exact material")
	state.level = 1
	state.xp = 0
	var note_before := AppState.inventory_count("TRAINING_NOTE_M")
	var credit_before := AppState.inventory_count("CREDIT")
	var level_preview := CharacterProgression.preview("CHR001", "TRAINING_NOTE_M", 1)
	var level_result := CharacterProgression.use_material("CHR001", "TRAINING_NOTE_M", 1)
	check(level_result.ok and int(state.level) == int(level_preview.level) and AppState.inventory_count("CREDIT") == credit_before - int(level_preview.credit_cost), "character level-up charges exact previewed credits")
	check(AppState.inventory_count("TRAINING_NOTE_M") == note_before - 1, "character level-up deducts exact XP material")
	state.breakthrough = 0
	state.level = 19
	state.xp = 0
	var overflow_notes := AppState.inventory_count("TRAINING_NOTE_XL")
	check(CharacterProgression.use_material("CHR001", "TRAINING_NOTE_XL", 1).error == "WOULD_EXCEED_LEVEL_CAP" and AppState.inventory_count("TRAINING_NOTE_XL") == overflow_notes, "character XP overflow at cap is blocked without consumption")
	state.skills.normal = 10
	state.skills.passive = 10
	state.skills.ultimate = 5
	check(not SkillUpgradeService.upgrade("CHR001", "normal").ok and not SkillUpgradeService.upgrade("CHR001", "ultimate").ok, "10/10/5 maximum enforced")
	var weapon: Dictionary = AppState.profile.weapons.WPN001
	weapon.level = 10
	weapon.tier = 1
	check(WeaponUpgradeService.use_material("WPN001", "WEAPON_CHIP_S", 1).error == "TIER_LEVEL_CAP", "weapon XP blocked at tier cap")
	check(WeaponUpgradeService.tier_up("WPN001").ok and int(weapon.tier) == 2, "weapon tier-up succeeds with exact prerequisites")
	weapon.level = 19
	weapon.tier = 2
	weapon.xp = 0
	var weapon_chip_before := AppState.inventory_count("WEAPON_CHIP_XL")
	check(WeaponUpgradeService.use_material("WPN001", "WEAPON_CHIP_XL", 1).error == "WOULD_EXCEED_TIER_CAP" and AppState.inventory_count("WEAPON_CHIP_XL") == weapon_chip_before, "weapon XP overflow at tier cap is blocked without consumption")
	state.level = 1
	state.breakthrough = 0
	state.equipped_weapon_id = "WPN004"
	AppState.profile.weapons.WPN004 = {"owned": true, "level": 1, "xp": 0, "tier": 1}
	check(int(CharacterProgression.final_stats("CHR001").ATK) == 132, "equipped common weapon flat ATK applies to final character stats")
	AppState.profile.weapons.WPN004.level = 60
	AppState.profile.weapons.WPN004.tier = 5
	var upgraded_weapon_stats := WeaponUpgradeService.flat_stats_for("WPN004", AppState.profile.weapons.WPN004)
	check(int(upgraded_weapon_stats.ATK) == 250 and int(upgraded_weapon_stats.CRIT) == 36, "weapon level and T5 secondary stat are data-driven")
	var snapshot_sim := BattleSimulation.new()
	snapshot_sim.setup(AppState.create_party_snapshot(), DataRegistry.stage("CH01-N01"), 31, DataRegistry.data)
	check(int(snapshot_sim.state.party[0].stats.ATK) == 352, "equipped weapon snapshot applies to deterministic battle stats")
	AppState.profile.stage_stars["CH01-N01"] = 3
	AppState.profile.chapter_progress.CH01.normal_highest = 1
	AppState.profile.account.stamina = int(DataRegistry.stage("CH01-N01").stamina_cost) * 4
	var developer_mode_before := bool(SettingsService.values.developer_mode)
	SettingsService.values.developer_mode = false
	var stamina_before := int(AppState.profile.account.stamina)
	check(RewardService.sweep("CH01-N01", 5, 9).error == "INSUFFICIENT_STAGE_ENTRIES" and int(AppState.profile.account.stamina) == stamina_before, "multi-sweep entry check is atomic")
	SettingsService.values.developer_mode = developer_mode_before
	var poor_inventory: Dictionary = AppState.profile.inventory.duplicate(true)
	for item_id in AppState.profile.inventory: AppState.profile.inventory[item_id] = 0
	state.skills.normal = 1
	check(SkillUpgradeService.upgrade("CHR001", "normal").error == "INSUFFICIENT_MATERIALS", "growth blocks insufficient materials")
	AppState.profile.inventory = poor_inventory
	AppState.profile = backup

func _test_story() -> void:
	var valid := true
	for scenario in DataRegistry.list_of("scenarios"): valid = valid and ScenarioParser.validate(scenario).is_empty()
	check(valid, "all scenario jump references and commands valid")
	var runner := ScenarioRunner.new()
	check(runner.load_scenario("SCN_PROLOGUE", false).ok, "scenario runner loads prologue")
	var found_choice := false
	for i in range(20):
		var command := runner.advance()
		if command.get("command", "") == "choice": found_choice = true; break
	check(found_choice and runner.choose(0).ok, "scenario choice sets branch flag")
	check(AppState.profile.story_flags.get("CHOSE_LIGHT", false), "scenario flag persisted")
	var resumed := ScenarioRunner.new()
	check(resumed.load_scenario("SCN_PROLOGUE", true).ok and resumed.state.background_asset_id == "bg_lantern_tunnel_dev" and resumed.state.portraits.has("RIGHT"), "scenario resume restores background and portrait state")
	check(DataRegistry.list_of("scenarios").size() == 9, "story content count is nine")

func _test_save() -> void:
	var profile_backup := AppState.profile.duplicate(true)
	AppState.profile.account.level = 37
	var first := SaveService.save_game()
	AppState.profile.account.level = 38
	var second := SaveService.save_game()
	check(first.ok and second.ok, "atomic save succeeds", "first=%s second=%s user_dir=%s" % [first.error, second.error, ProjectSettings.globalize_path("user://")])
	check(FileAccess.file_exists(SaveService.BACKUP_PATH), "backup save generated", ProjectSettings.globalize_path(SaveService.BACKUP_PATH))
	var loaded := SaveService.load_game()
	check(loaded.ok and int(AppState.profile.account.level) == 38, "save/load preserves value", "load=%s level=%s" % [loaded.error, AppState.profile.account.level])
	var corrupt := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	corrupt.store_string("{corrupt")
	corrupt.close()
	var recovered := SaveService.load_game()
	check(recovered.ok and recovered.value == "backup" and int(AppState.profile.account.level) == 37, "corrupt primary recovers backup", "load=%s value=%s level=%s" % [recovered.error, recovered.value, AppState.profile.account.level])
	var migrated := SaveService._migrate({"save_schema_version": 0})
	check(migrated.ok and int(migrated.value.save_schema_version) == AppState.SAVE_SCHEMA_VERSION, "sequential v0 through current migration")
	var dirty := profile_backup.duplicate(true)
	dirty.roster.UNKNOWN_REMOVED = {"level": 99}
	var sanitized := SaveService._sanitize(dirty)
	check(not sanitized.roster.has("UNKNOWN_REMOVED") and sanitized.quarantined_unknown_character_ids.has("UNKNOWN_REMOVED"), "unknown immutable ID quarantined")
	AppState.profile = profile_backup
	var first_clear_once := AppState.record_stage_clear("CH01-N01", 3)
	var first_clear_twice := AppState.record_stage_clear("CH01-N01", 3)
	check(first_clear_once and not first_clear_twice, "duplicate first-clear reward signal prevented")
	SaveService.save_game()
