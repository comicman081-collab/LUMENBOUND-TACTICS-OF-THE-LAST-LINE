extends Node

var checks: Array = []
func check(value: bool, label: String) -> void:
	checks.append({"pass": value, "name": label})
	print("PASS | " if value else "FAIL | ", label)

func _ready() -> void:
	AppState.new_game()
	for chapter in DataRegistry.list_of("chapters"):
		var map_id := str(chapter.id) + "_MAP"
		var definition := ChapterMapLoader.load_map(map_id)
		var scouts: Array = definition.nodes.filter(func(n): return bool(n.get("forward_patrol", false)))
		if scouts.is_empty(): continue
		var scout: Dictionary = scouts[0]
		var canonical := ChapterMapLoader.node_for_stage(definition, str(scout.stage_id))
		var state := AppState.chapter_map_state(map_id)
		var contact := Vector2i(int(scout.q), int(scout.r))
		AppState.set_chapter_map_position(contact, str(scout.node_id), map_id)
		check(AppState.prepare_map_encounter(str(scout.stage_id), str(scout.node_id), contact, map_id), map_id + " prepares exact scout")
		var token := "identity-test:" + str(scout.node_id)
		AppState.pending_battle_token = token
		state.pending_encounter.token = token
		AppState.record_stage_clear(str(scout.stage_id), 3)
		check(AppState.apply_battle_result_to_map(str(scout.stage_id), true, map_id), map_id + " scout result commits")
		check(MapExplorationService.encounter_cleared(state, str(scout.node_id)) and not MapExplorationService.encounter_cleared(state, str(canonical.node_id)), map_id + " kill #2 leaves #1 alive")
		check(Vector2i(state.current_q, state.current_r) == contact, map_id + " victory preserves physical contact position")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(AppState.profile))
		AppState.apply_loaded(saved)
		state = AppState.chapter_map_state(map_id)
		check(not MapExplorationService.encounter_cleared(state, str(canonical.node_id)), map_id + " reload cannot group-clear survivors")
		check(not AppState.apply_battle_result_to_map(str(scout.stage_id), true, map_id), map_id + " duplicate result rejected")
	# Small traversable hex field: chase deliberately leaves its 2-cell route.
	var tiles: Array = []
	for q in range(-4, 10):
		for r in range(-4, 10): tiles.append({"q":q,"r":r,"elevation":0,"terrain_type":"ROAD"})
	var patrol := {"encounter_id":"mob1", "patrol_enabled":true, "patrol_mode":"PING_PONG", "patrol_route_hexes":[{"q":0,"r":0},{"q":1,"r":0}], "return_hex":{"q":0,"r":0},"patrol_speed_ticks":1,"engagement_radius":0}
	var definition := {"start_hex":{"q":5,"r":2},"tiles":tiles,"nodes":[],"patrols":[patrol]}
	var grid := HexGrid.new()
	grid.load_tiles(tiles)
	var state := ChapterMapProgress.create_default(definition)
	var party := Vector2i(5,2)
	state.visited_tiles.append(HexCoord.key(party))
	var prior_distance := 100
	for step in range(5):
		MapSimulation.advance_ticks(state, definition, grid, party)
		var coord := MapSimulation.coord_for(state, "mob1")
		var distance := HexCoord.distance(coord, party)
		check(distance < prior_distance, "Pursuit step %d approaches player" % step)
		prior_distance = distance
		var reloaded: Dictionary = JSON.parse_string(JSON.stringify(state))
		MapSimulation.ensure_state(reloaded, definition, grid)
		check(MapSimulation.coord_for(reloaded, "mob1") == coord, "Off-route chase survives reload step %d" % step)
		state = reloaded
	var other: Dictionary = patrol.duplicate(true)
	other.encounter_id = "mob2"
	other.return_hex = {"q":1,"r":1}
	other.patrol_route_hexes = [{"q":1,"r":1},{"q":2,"r":1}]
	definition.patrols.append(other)
	for step in range(5):
		MapSimulation.advance_ticks(state, definition, grid, Vector2i(7,3))
		check(MapSimulation.coord_for(state,"mob1") != MapSimulation.coord_for(state,"mob2"), "Movement reserves occupied cells %d" % step)
	for step in range(28): MapSimulation.advance_ticks(state, definition, grid, Vector2i(40,40))
	check(HexCoord.distance(MapSimulation.coord_for(state,"mob1"), Vector2i.ZERO) <= 1, "Lost player search expires and returns home")
	AppState.new_game()
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage("CH01-N01"), 129, DataRegistry.data)
	var view := BattleView.new()
	view.size = Vector2(1920,1080)
	view.setup(sim)
	view._consume_events()
	var target: Dictionary = TargetResolver.choose(sim.state.party[0], sim.state.enemies)
	var initial_hp := int(view.presentation_unit_for_uid(str(target.uid)).hp)
	sim._basic_attack(sim.state.party[0])
	view._consume_events()
	check(not view.contact_events.is_empty(), "Attack queues a visible contact")
	check(int(view.presentation_unit_for_uid(str(target.uid)).hp) == initial_hp, "HP never drops before strike arrives")
	view._advance_contacts(.43)
	check(int(view.presentation_unit_for_uid(str(target.uid)).hp) == initial_hp, "Windup and flight preserve target HP")
	view._advance_contacts(.02)
	check(int(view.presentation_unit_for_uid(str(target.uid)).hp) == int(target.hp), "Contact commits actual model damage exactly")
	var uid := str(sim.state.party[0].uid)
	var original := view._unit_pos(sim.state.party[0])
	view._advance_engagement(1.0)
	check(view._unit_pos(sim.state.party[0]).x > original.x and view._unit_pos(sim.state.party[0]).x < original.x + 80.0, "Opening preserves separated resting columns")
	var motion_ids: Array[String] = [str(sim.state.party[0].def_id)]
	check(await view.action_frames.warm(motion_ids,self), "Real melee motion available for contact travel")
	view.animation_tracks[uid] = {"name":"basic_attack","elapsed":0.0,"target_uid":str(target.uid)}
	var resting := view._ground_position(sim.state.party[0])
	view.animation_tracks[uid].elapsed = .44
	check(view._ground_position(sim.state.party[0]).x > resting.x + 250.0, "Authored melee strike closes the target gap")
	view.animation_tracks[uid].elapsed = .78
	check(view._ground_position(sim.state.party[0]).distance_to(resting)<.001, "Melee recovery returns to its reserved lane")
	sim._down_unit(target,uid,"BASIC")
	view._consume_events()
	check(bool(view.presentation_unit_for_uid(str(target.uid)).alive), "Death waits for the killing contact")
	view._advance_contacts(.45)
	check(not bool(view.presentation_unit_for_uid(str(target.uid)).alive) and view.enemy_defeat_bursts.has(str(target.uid)), "Killing contact creates enemy explosion")
	view.free()
	var failures := checks.filter(func(c): return not c.pass).size()
	var report_path := "res://../reports/combat_map_upgrade_20260913/model.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
	var output := FileAccess.open(report_path,FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	output.close()
	print("ENCOUNTER_COMBAT_UPGRADE checks=%d failures=%d" % [checks.size(), failures])
	get_tree().quit(0 if failures == 0 else 1)
