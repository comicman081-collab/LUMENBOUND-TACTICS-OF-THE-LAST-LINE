extends Node

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	var minimap := preload("res://chapter_map/ui/chapter_route_minimap.gd").new()
	var definition := {"map_id": "FOG_TEST", "tiles": [], "nodes": [], "treasures": [
		{"treasure_id": "NEAR", "q": 1, "r": 0}, {"treasure_id": "FAR", "q": 20, "r": 0}],
		"relays": [{"relay_id": "SECRET", "q": 20, "r": 0}]}
	for q in range(-3, 24):
		for r in range(-3, 4): definition.tiles.append({"q": q, "r": r, "terrain_type": "FOREST"})
	var state := {"current_q": 0, "current_r": 0, "visited_tiles": ["0,0"],
		"revealed_tiles": ["20,0"], "discovered_tiles": [],
		"treasure_states": {"NEAR": "REVEALED", "FAR": "REVEALED"}}
	minimap.configure(definition, state, {}, false, 1)
	check(minimap.explored.has("0,0") and minimap.explored.size() == 7, "minimap shows actual local sight")
	check(not minimap.explored.has("20,0"), "an unlocked future corridor is not explored")
	check(minimap.markers.size() == 1, "unexplored treasures and relays do not leak")
	minimap.full_map = true
	minimap.configure(definition, state, {}, false, 1)
	check(not minimap.explored.has("20,0"), "expanded map preserves the same fog")
	state.treasure_states.NEAR = "CLAIMED"
	minimap.configure(definition, state, {}, false, 1)
	check(minimap.markers.is_empty(), "claim removes treasure marker immediately")
	state.visited_tiles.append("20,0")
	state.current_q = 20
	minimap.configure(definition, state, {}, false, 1)
	check(minimap.explored.has("20,0") and minimap.explored.has("0,0"), "travel reveals terrain and remembers earlier districts")
	check(minimap.markers.size() == 2, "newly explored district reveals its discovered objects")
	state.discovered_tiles.append("10,0")
	minimap.configure(definition, state, {}, false, 1)
	check(minimap.explored.has("10,0"), "relay survey remains available")
	minimap.free()
	var screen := preload("res://chapter_map/runtime/chapter_map_screen.gd").new()
	var treasure := {"treasure_id": "KEEP", "q": 2, "r": 3}
	screen.selected_treasure = treasure
	screen.map_state = {screen.POST_REWARD_TURN_PENDING_KEY: true, "movement_points": 0}
	# Exercise the actual selection reset through its shared operation.
	screen._reset_selected_objects()
	check(treasure == {"treasure_id": "KEEP", "q": 2, "r": 3}, "reset preserves aliased authored treasure data")
	check(screen.selected_treasure.is_empty(), "reset releases the selected treasure")
	screen.free()
	var battle := preload("res://battle/view/battle_view.gd").new()
	battle.size = Vector2(1920, 1080)
	var monster := {"def_id": "ENM002", "team": "ENEMY", "rank": "NORMAL"}
	battle.sprite_library.manifests.ENM002 = {"head_anchor": [0.5, 0.38]}
	var scale := battle._combat_sprite_scale(monster, "idle")
	# Normalized by the head/foot span: a regular enemy fills its grid cell
	# (175px of body on a 1080p field) however much canvas padding it has.
	check(scale >= 0.65, "short-canvas enemy has a threatening body scale")
	check(is_equal_approx(scale, battle._combat_sprite_scale(monster, "basic_attack")), "enemy scale stays stable across action changes")
	var grounding := preload("res://battle/view/battle_grounding.gd")
	var prior_y := 0.0
	for slot in range(5):
		var actor := {"def_id": "CHR001", "team": "PLAYER", "slot": slot}
		var point := grounding.formation_point(battle.size, true, slot, false)
		var half_width := 256.0 * battle._combat_sprite_scale(actor, "idle")
		check(point.x - half_width >= 0 and point.x + half_width <= battle.size.x * 0.5, "entire ally %d stays in left half" % slot)
		if slot > 0: check(point.y < prior_y if slot % 2 == 1 else point.y > prior_y, "ally %d alternates lower/upper rows" % slot)
		prior_y = point.y
	battle.free()
	# Reproduce the pause-menu lifetime across repeated HUD resize rebuilds.
	AppState.new_game()
	var shell := preload("res://screens/app_shell.gd").new()
	var pause_battle := preload("res://battle/view/battle_view.gd").new()
	pause_battle.simulation = BattleSimulation.new()
	pause_battle.simulation.setup(AppState.create_party_snapshot(), DataRegistry.stage("CH01-N01"), 31, DataRegistry.data)
	pause_battle.paused = true
	shell.battle_view = pause_battle
	shell.add_child(pause_battle)
	shell._build_battle_overlay()
	for rebuild in range(3): shell._rebuild_battle_overlay()
	var pause_centers := 0
	for child in pause_battle.get_children():
		if child is CenterContainer: pause_centers += 1
	check(pause_centers == 1, "resizing a paused battle retains exactly one pause menu")
	shell._toggle_battle_pause()
	check(not pause_battle.paused and not shell.battle_pause_center.visible, "rebuilt pause menu can resume combat")
	shell.free()
	print("PLAYER_FEEDBACK_TESTS total=%d pass=%d fail=%d" % [checks, checks-failures, failures])
	get_tree().quit(0 if failures == 0 else 1)
