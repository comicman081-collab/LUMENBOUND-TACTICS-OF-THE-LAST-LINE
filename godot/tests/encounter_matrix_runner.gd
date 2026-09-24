extends Node
var checks: Array[Dictionary] = []
func check(ok: bool, name: String) -> void:
	checks.append({"pass":ok,"name":name})
	if not ok: push_error(name)

func _ready() -> void:
	AppState.new_game()
	SettingsService.values.developer_mode = false
	var shell := preload("res://screens/app_shell.gd").new()
	shell.footer_status = Label.new()
	var tested := 0
	var stages: Dictionary = {}
	for chapter_number in range(1, 21):
		var chapter_id := "CH%02d" % chapter_number
		var map_id := chapter_id + "_MAP"
		# Every chapter is an independent disposable-save case. Retaining all
		# previous map payloads only measures repeated JSON IO, not this boundary.
		AppState.profile.chapter_map.clear()
		var definition := ChapterMapLoader.load_map(map_id)
		var map := ChapterMapScreen.new()
		map.map_id = map_id
		map.definition = definition
		map.grid = HexGrid.new()
		map.grid.load_tiles(definition.tiles)
		map.map_state = AppState.chapter_map_state(map_id)
		shell.active_chapter_map_screen = map
		var progress: Dictionary = AppState.profile.chapter_progress[chapter_id]
		progress.unlocked = true
		progress.normal_highest = 20
		progress.hard_unlocked = true
		for node in definition.nodes:
			var stage_id := str(node.get("stage_id", ""))
			if stage_id.is_empty(): continue
			var stage := DataRegistry.stage(stage_id)
			stages[stage_id] = true
			AppState.profile.stage_stars.clear()
			if str(stage.mode) == "HARD" and int(stage.stage_number) > 1:
				AppState.profile.stage_stars["%s-H%02d" % [chapter_id,int(stage.stage_number)-1]] = 3
			map.map_state.cleared_encounters.erase(str(node.node_id))
			map.map_state.cleared_nodes.erase(str(node.node_id))
			map.map_state.encounter_states[str(node.node_id)] = "HOSTILE"
			var target := Vector2i(int(node.q),int(node.r))
			if not MapSimulation.patrol_definition(definition,str(node.node_id)).is_empty():
				target = MapSimulation.coord_for(map.map_state,str(node.node_id))
			var neighbour := target
			for candidate in HexCoord.neighbors(target):
				if map.grid.can_step(candidate,target):
					neighbour = candidate
					break
			check(neighbour != target,stage_id+" has physical contact approach")
			AppState.set_chapter_map_position(target,str(node.node_id),map_id)
			check(map._contact_node_ids_at(target).has(str(node.node_id)),stage_id+" physical contact includes patrol/static actor")
			AppState.profile.account.stamina = 100
			AppState.profile.account.stamina_updated_at = int(Time.get_unix_time_from_system())
			AppState.profile.hard_attempts.counts[stage_id] = 0
			check(AppState.prepare_map_encounter(stage_id,str(node.node_id),neighbour,map_id) and AppState.begin_battle_transaction(stage_id),stage_id+" real entry accepted")
			var charged := int(AppState.profile.account.stamina)
			check(charged == 100-int(stage.stamina_cost) and not AppState.begin_battle_transaction(stage_id) and int(AppState.profile.account.stamina)==charged,stage_id+" charges exactly once")
			if str(stage.mode)=="HARD":
				check(int(AppState.profile.hard_attempts.counts[stage_id])==1,stage_id+" daily entry counted exactly once")
			shell.battle_transition_active = true
			var accepted_token: String = AppState.pending_battle_token
			shell._map_battle_requested(stage_id)
			check(AppState.pending_battle_token == accepted_token and not accepted_token.is_empty(),stage_id+" duplicate signal preserves accepted entry")
			shell.battle_transition_active = false
			AppState.abandon_pending_map_encounter(map_id)
			for failure in (["stamina","daily"] if str(stage.mode)=="HARD" else ["stamina"]):
				AppState.set_chapter_map_position(target,str(node.node_id),map_id)
				AppState.profile.account.stamina = 0 if failure=="stamina" else 100
				AppState.profile.account.stamina_updated_at = int(Time.get_unix_time_from_system())
				AppState.profile.hard_attempts.counts[stage_id] = int(stage.daily_attempts) if failure=="daily" else 0
				AppState.prepare_map_encounter(stage_id,str(node.node_id),neighbour,map_id)
				map.turn_transitioning = true
				shell.transition_edge_blocked_until_msec = 0
				shell._map_battle_requested(stage_id)
				check(not map.turn_transitioning and map.map_state.pending_encounter.is_empty() and AppState.pending_battle_token.is_empty(),stage_id+" "+failure+" rejection unlocks map")
				check(Vector2i(int(map.map_state.current_q),int(map.map_state.current_r))==neighbour and int(AppState.profile.account.stamina)==(0 if failure=="stamina" else 100),stage_id+" "+failure+" rejection restores tile without charge")
			tested += 1
		map.free()
		shell.active_chapter_map_screen = null
		print("ENCOUNTER_MATRIX ",chapter_id," stages=",tested)
		await get_tree().process_frame
	check(stages.size()==500,"all 500 authored stages covered including generated roaming contacts")
	shell.footer_status.free()
	shell.free()
	var failed := checks.filter(func(c):return not c.pass)
	var output := FileAccess.open("res://../reports/encounter_contact_fix_20260911/encounter_matrix.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed":failed.is_empty(),"stages":stages.size(),"physical_contacts":tested,"checks":checks},"\t"))
	output.close()
	print("ENCOUNTER_MATRIX_SUMMARY ",checks.size()-failed.size(),"/",checks.size())
	get_tree().quit(0 if failed.is_empty() else 1)
