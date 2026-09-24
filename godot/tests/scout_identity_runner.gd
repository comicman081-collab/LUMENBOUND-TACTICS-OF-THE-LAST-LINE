extends Node

var checks: Array = []

func check(value: bool, label: String) -> void:
	checks.append({"pass":value,"name":label})
	print("PASS | " if value else "FAIL | ",label)

func _ready() -> void:
	for chapter in DataRegistry.list_of("chapters"):
		var map_id := str(chapter.id) + "_MAP"
		var definition := ChapterMapLoader.load_map(map_id)
		var scouts: Array = definition.nodes.filter(func(n): return bool(n.get("forward_patrol", false)))
		if scouts.size() < 2: continue
		var siblings: Array = scouts.filter(func(n): return str(n.stage_id) == str(scouts[0].stage_id))
		if siblings.size() < 2: continue
		for first in range(2):
			AppState.new_game()
			AppState.profile.chapter_progress[str(chapter.id)].unlocked = true
			var killed: Dictionary = siblings[first]
			var survivor: Dictionary = siblings[1-first]
			var canonical := ChapterMapLoader.node_for_stage(definition,str(killed.stage_id))
			var state := AppState.chapter_map_state(map_id)
			var contact := Vector2i(int(killed.q),int(killed.r))
			AppState.set_chapter_map_position(contact,"",map_id)
			AppState.prepare_map_encounter(str(killed.stage_id),str(killed.node_id),contact,map_id)
			var token := "sibling-test:"+map_id+":"+str(killed.node_id)
			AppState.pending_battle_token = token
			state.pending_encounter.token = token
			AppState.record_stage_clear(str(killed.stage_id),3)
			check(AppState.apply_battle_result_to_map(str(killed.stage_id),true,map_id),token+" commits")
			for reload_index in range(2):
				if reload_index == 1:
					AppState.apply_loaded(JSON.parse_string(JSON.stringify(AppState.profile)))
					state = AppState.chapter_map_state(map_id)
				var label := token+" reload=%d" % reload_index
				check(MapExplorationService.encounter_cleared(state,str(killed.node_id)),label+" defeated scout stays cleared")
				check(not MapExplorationService.encounter_cleared(state,str(survivor.node_id)),label+" sibling stays logically alive")
				var view := ChapterMapScreen.new()
				view.map_state = state
				view.definition = definition
				view.grid = HexGrid.new()
				view.grid.load_tiles(definition.tiles)
				check(view._node_encounter_cleared(killed),label+" defeated pawn removed")
				check(not view._node_encounter_cleared(survivor),label+" sibling remains renderable after shared stage clear")
				check(not view._node_encounter_cleared(canonical),label+" canonical pawn remains renderable")
				check(str(view._next_encounter_node().get("node_id", "")) == str(canonical.node_id),label+" guide retains the undefeated main encounter")
				view.selected_node = survivor
				check(view._arrival_resolution_owns_save(view._encounter_coord(survivor)),label+" sibling contact owns battle transaction")
				check(view._unresolved_encounter_stop_hexes().has(HexCoord.key(view._encounter_coord(survivor))),label+" sibling blocks movement at its physical hex")
				view.free()
	var failures := checks.filter(func(c): return not c.pass).size()
	var report := "res://../reports/combat_motion_20260913/scout_identity.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report = argument.trim_prefix("--report=")
	var file := FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	file.close()
	print("SCOUT_IDENTITY checks=%d failures=%d" % [checks.size(),failures])
	get_tree().quit(0 if failures == 0 else 1)
