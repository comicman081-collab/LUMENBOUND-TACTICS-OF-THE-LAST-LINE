extends Node

var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error(label)

func _ready() -> void:
	var fallback_count := 0
	var outro_fallback_count := 0
	var scenes := 0
	var shell := preload("res://screens/app_shell.gd").new()
	for chapter in DataRegistry.list_of("chapters"):
		AppState.new_game()
		var id := str(chapter.id)
		AppState.profile.chapter_progress[id].unlocked = true
		var map_definition := ChapterMapLoader.load_map(id + "_MAP")
		for contact in map_definition.get("event_encounters", []):
			if str(contact.get("event_kind", "")) != "COMPANION": continue
			var contact_node := map_definition.nodes.filter(func(n): return n.node_id == contact.node_id)[0] as Dictionary
			check(chapter.required_stage_ids.has(str(contact_node.stage_id)), id + " canonical companion contact is mandatory")
			if int(chapter.number) >= 3:
				var middle := DataRegistry.by_id("chapter_story_triggers", "TRIG_" + id + "_MID_B")
				check(int(DataRegistry.stage(str(middle.stage_id)).stage_number) >= int(DataRegistry.stage(str(contact_node.stage_id)).stage_number), id + " ally action follows first contact")
		var grid := HexGrid.new()
		grid.load_tiles(map_definition.tiles)
		var positions: Dictionary = {}
		var occupied: Dictionary = {}
		for node in map_definition.nodes:
			if str(node.get("stage_id", "")).is_empty(): continue
			var coord := Vector2i(int(node.q), int(node.r))
			positions[str(node.stage_id)] = coord
			occupied[HexCoord.key(coord)] = true
		for index in range(1, chapter.required_stage_ids.size()):
			var from: Vector2i = positions[chapter.required_stage_ids[index-1]]
			var to: Vector2i = positions[chapter.required_stage_ids[index]]
			check(not HexPathfinder.find_path(grid, from, to, {}, occupied).is_empty(), id + " main route can physically bypass optional contacts")
		# Take only mandatory normal operations, followed by the five hard
		# operations that unlock the following region. Optional branches stay clear.
		for stage_id in chapter.required_stage_ids + chapter.hard_stage_ids:
			var stage := DataRegistry.stage(stage_id)
			if str(stage.mode) == "NORMAL":
				check(AppState.is_stage_unlocked(stage_id), stage_id + " opens without clearing optional predecessors")
				AppState.profile.chapter_progress[id].normal_highest = int(stage.stage_number)
			AppState.profile.first_clear[stage_id] = true
		AppState.profile.chapter_progress[id].hard_unlocked = true
		AppState.profile.first_clear.erase(chapter.hard_stage_ids[0])
		check(shell.region_entry_stage(id) == chapter.hard_stage_ids[0], id + " region entry prefers onward progress over skipped optional branches")
		AppState.profile.first_clear[chapter.hard_stage_ids[0]] = true
		var expected: Array[String] = []
		for trigger in DataRegistry.list_of("chapter_story_triggers"):
			if DataRegistry.by_id("scenarios", str(trigger.scenario_id)).chapter_id != id: continue
			expected.append(str(trigger.id))
			for fallback in trigger.get("fallback_stage_ids", []):
				# Optional-branch scenes fall back to the next mandatory stage.
				# Chapter outros authored on H05 fall back to the final normal
				# stage so the "next chapter" flow keeps the epilogue.
				if str(DataRegistry.stage(str(trigger.stage_id)).mode) == "HARD":
					outro_fallback_count += 1
					check(str(fallback) == str(chapter.required_stage_ids.back()), str(trigger.id) + " outro fallback is the final normal stage")
				else:
					fallback_count += 1
				check(chapter.required_stage_ids.has(fallback), str(trigger.id) + " fallback is mandatory")
				check(int(DataRegistry.stage(fallback).stage_number) > int(DataRegistry.stage(trigger.stage_id).stage_number), str(trigger.id) + " fallback follows its original encounter")
		# Simulate a saved first-clear record with a missing pending queue.
		AppState.profile = JSON.parse_string(JSON.stringify(AppState.profile))
		check(AppState.queue_story_event("MAP_ENTER", "", id), id + " recovers earned scenes")
		check(AppState.profile.pending_story_triggers.size() == expected.size(), id + " mandatory route retains every main story beat")
		var priority := -1
		for trigger_id in expected:
			var pending := AppState.next_pending_story_trigger(id)
			check(not pending.is_empty(), id + " pending scene exists")
			if pending.is_empty(): break
			check(int(pending.priority) > priority and expected.has(str(pending.id)), id + " scenes follow canonical order")
			priority = int(pending.priority)
			AppState.complete_story_trigger_for_scenario(str(pending.scenario_id))
			scenes += 1
		check(not AppState.queue_story_event("MAP_ENTER", "", id), id + " completed scenes do not replay")
		check(AppState.next_pending_story_trigger(id).is_empty(), id + " completed queue is empty")
	AppState.new_game()
	AppState.queue_story_event("MAP_ENTER", "", "CH01")
	check(AppState.profile.pending_story_triggers.size() == 1, "fresh save receives only the first introduction")
	AppState.complete_story_trigger_for_scenario("SCN_CH01_INTRO")
	AppState.profile.chapter_progress.CH01.normal_highest = 2
	check(AppState.is_stage_unlocked("CH01-N03") and AppState.is_stage_unlocked("CH01-N04"), "N02 opens optional N03 and mandatory N04 together")
	check(not AppState.is_stage_unlocked("CH01-N05") and not AppState.is_stage_unlocked("CH01-N06"), "future branches remain gated by N04")
	check(shell.region_entry_stage("CH02").is_empty(), "branch change never opens a locked region")
	check(AppState.queue_story_event("STAGE_CLEAR", "CH01-N04", "CH01"), "mandatory fallback fires at actual clear")
	check(AppState.next_pending_story_trigger("CH01").scenario_id == "SCN_CH01_MID_A", "fallback selects the skipped branch story")
	AppState.complete_story_trigger_for_scenario("SCN_CH01_MID_A")
	check(not AppState.queue_story_event("STAGE_CLEAR", "CH01-N03", "CH01"), "later optional clear cannot replay completed fallback")
	check(AppState.next_pending_story_trigger("CH02").is_empty(), "recovery never queues another region")
	check(fallback_count == 4, "four optional-branch fallbacks are authored")
	check(outro_fallback_count == 2, "CH01/CH02 H05 outros fall back to their final normal stage")
	shell.free()
	print("CAMPAIGN_STORY_CONTINUITY total=%d pass=%d fail=%d chapters=20 scenes=%d fallbacks=%d outro_fallbacks=%d" % [passed+failed, passed, failed, scenes, fallback_count, outro_fallback_count])
	get_tree().quit(0 if failed == 0 else 1)
