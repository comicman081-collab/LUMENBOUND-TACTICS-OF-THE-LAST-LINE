extends Node

var checks: Array = []

func check(value: bool, label: String) -> void:
	checks.append({"pass": value, "name": label})
	print("PASS | " if value else "FAIL | ", label)

func _ready() -> void:
	SettingsService.values.developer_mode = false
	AppState.new_game()
	for chapter in DataRegistry.list_of("chapters"):
		var id := str(chapter.id)
		var final_id := str(chapter.normal_stage_ids.back())
		AppState.profile.chapter_progress[id].unlocked = true
		AppState.profile.chapter_progress[id].normal_highest = 19
		AppState.profile.campaign_transition = {}
		check(AppState.record_stage_clear(final_id, 3), final_id + " first clear")
		check(AppState.profile.chapter_progress[id].hard_unlocked, id + " optional hard unlocked")
		var target := AppState.next_chapter_entry(id)
		if target.is_empty():
			check(AppState.profile.campaign_transition.is_empty(), "Final chapter has no nonexistent next region")
		else:
			check(AppState.is_stage_unlocked(target), final_id + " opens " + target)
			check(str(AppState.profile.campaign_transition.to_stage) == target, final_id + " persists destination")
		var handoff: Dictionary = AppState.profile.campaign_transition.duplicate()
		check(not AppState.record_stage_clear(final_id, 3) and AppState.profile.campaign_transition == handoff, final_id + " duplicate does not replace handoff")
		AppState.profile.campaign_transition = {}
		AppState.record_stage_clear(final_id, 3)
		check(AppState.profile.campaign_transition.is_empty(), final_id + " replay never forces travel")
		AppState.queue_story_event("STAGE_CLEAR", final_id)
		check(AppState.profile.pending_story_triggers.has("TRIG_" + id + "_OUTRO"), final_id + " queues aftermath")
	AppState.new_game()
	AppState.profile.first_clear["CH01-N20"] = true
	AppState.profile.stage_stars["CH01-N20"] = 3
	AppState.profile.chapter_progress.CH01.normal_highest = 20
	AppState.profile.erase("campaign_transition")
	var old_inventory: Dictionary = AppState.profile.inventory.duplicate(true)
	AppState.apply_loaded(AppState.profile.duplicate(true))
	check(AppState.is_stage_unlocked("CH02-N01") and str(AppState.profile.campaign_transition.get("to_stage", "")) == "CH02-N01", "Old N20 save recovers next region and handoff")
	check(AppState.profile.inventory == old_inventory, "Migration never regrants rewards")
	AppState.profile.campaign_transition = {}
	AppState.apply_loaded(AppState.profile.duplicate(true))
	check(AppState.profile.campaign_transition.is_empty(), "Acknowledged handoff remains cleared after reload")
	AppState.new_game()
	AppState.apply_loaded(AppState.profile.duplicate(true))
	check(not AppState.is_stage_unlocked("CH02-N01"), "Fresh save cannot bypass chapter 1")
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage("CH01-N20"), 129, DataRegistry.data)
	var view := BattleView.new()
	view.setup(sim)
	check(not view._detect_boss_entrance(), "Ordinary opening waves have no boss entrance")
	var last_enemy_uid := str(sim.state.enemies[0].uid)
	sim._down_unit(sim.state.enemies[0], str(sim.state.party[0].uid), "BASIC")
	while sim.wave_director.has_next(): sim._spawn_next_wave()
	var event_hash := sim.event_hash()
	check(view._detect_boss_entrance(), "Authored boss spawn starts entrance")
	check(view.enemy_defeat_bursts.has(last_enemy_uid), "Spawn-tick enemy destruction survives the cinematic boundary")
	var tick_before := sim.state.tick
	view.speed = 3
	view._process(.8)
	check(sim.state.tick == tick_before, "Entrance freezes combat even at 3x")
	var elapsed := view.boss_entry_elapsed
	view.paused = true
	view._process(.3)
	check(view.boss_entry_elapsed == elapsed, "Pause freezes entrance without consuming timer")
	view.paused = false
	view._process(3.1)
	check(not view.scene_transition_active() and sim.state.tick == tick_before, "Entrance finishes without catch-up ticks")
	check(sim.event_hash() == event_hash, "Cinematic does not alter deterministic event log")
	check(not view._detect_boss_entrance(), "Same wave never restarts cinematic")
	for unit in sim.state.enemies:
		unit.hp = 0
		unit.alive = false
	view._snapshot_display_units_from_simulation()
	check(view._boss_present() and view._boss_background_mix() == 1.0, "Dead boss retains arena and formation")
	view.setup(sim)
	check(not view.boss_arena_active and not view.scene_transition_active(), "Reused view resets all cinematic state")
	view.free()
	var failures := checks.filter(func(c): return not c.pass).size()
	var output := FileAccess.open("res://../reports/chapter_boss_flow_20260912/model.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	output.close()
	print("CHAPTER_BOSS_FLOW checks=%d failures=%d" % [checks.size(), failures])
	get_tree().quit(0 if failures == 0 else 1)
