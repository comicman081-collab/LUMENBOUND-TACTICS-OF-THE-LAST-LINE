extends Node
func _ready() -> void:
	AppState.new_game()
	var definition := ChapterMapLoader.load_map("CH01_MAP")
	var grid := HexGrid.new()
	grid.load_tiles(definition.tiles)
	var state := AppState.chapter_map_state()
	var coord := MapSimulation.coord_for(state,"NODE_N01")
	ChapterMapProgress.mark_visited(state,[coord])
	AppState.prepare_map_encounter("CH01-N01","NODE_N01",coord)
	AppState.begin_battle_transaction("CH01-N01")
	AppState.apply_battle_result_to_map("CH01-N01",false)
	print("INITIAL ",JSON.stringify(state.patrol_states.NODE_N01))
	for tick in range(24):
		var result := MapSimulation.advance_ticks(state,definition,grid,coord)
		print(tick," ",JSON.stringify(state.patrol_states.NODE_N01)," CONTACTS ",JSON.stringify(result.contacts))
	get_tree().quit()
