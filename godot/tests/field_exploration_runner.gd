extends Node

var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error(label)

func _ready() -> void:
	var locations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../data_source/chapter_field_locations.json"))
	for number in range(2, 21):
		AppState.new_game()
		var cid := "CH%02d" % number
		var map_id := cid + "_MAP"
		var definition := ChapterMapLoader.load_map(map_id)
		check(ChapterMapLoader.validate(definition).is_empty(), cid + " complete content is reachable and valid")
		check(preload("res://chapter_map/view/natural_terrain_library.gd").tile_fingerprint(definition) == locations[cid].tile_fingerprint, cid + " existing Blender terrain fingerprint preserved")
		var grid := HexGrid.new()
		grid.load_tiles(definition.tiles)
		var state: Dictionary = AppState.chapter_map_state(map_id)
		var early: Dictionary = definition.map_events[0]
		var late: Dictionary = definition.map_events[1]
		var cache: Dictionary = definition.treasures[0]
		check(definition.map_events.size() == 2 and definition.treasures.size() == 1, cid + " two discoveries and one cache")
		for event in definition.map_events:
			check(LocalizationService.tr_key(event.title_key) != event.title_key and LocalizationService.tr_key(event.body_key) != event.body_key, cid + " localized field report")
		check(not MapExplorationService.resolve_event(state, definition, early.event_id, "RECOVER").ok, cid + " unfound event cannot pay")
		check(not MapExplorationService.discover_event(state, definition, late.event_id, grid), cid + " future story evidence is hidden")
		check(not MapExplorationService.resolve_event(state, definition, late.event_id, "RECOVER").ok, cid + " locked evidence cannot pay")
		MapExplorationService.update_proximity(state, definition, Vector2i(int(early.q), int(early.r)), grid)
		check(MapExplorationService.event_state(state, early.event_id) == "DISCOVERED", cid + " walking discovers report")
		var before := AppState.inventory_count("TRAINING_NOTE_S")
		check(not MapExplorationService.resolve_event(state, definition, early.event_id, "INVALID").ok and AppState.inventory_count("TRAINING_NOTE_S") == before, cid + " invalid choice preserves reward")
		check(MapExplorationService.resolve_event(state, definition, early.event_id, "RECOVER").ok and AppState.inventory_count("TRAINING_NOTE_S") == before + 2, cid + " supplies awarded exactly")
		check(not MapExplorationService.resolve_event(state, definition, early.event_id, "RECORD").ok, cid + " alternative choice cannot double award")
		AppState.profile.first_clear[cid + "-N04"] = true
		MapExplorationService.update_proximity(state, definition, Vector2i(int(late.q), int(late.r)), grid)
		check(MapExplorationService.resolve_event(state, definition, late.event_id, "RECORD").ok, cid + " earned evidence resolves")
		check(MapExplorationService.treasure_state(state, cache.treasure_id) == "HINTED", cid + " evidence marks cache")
		MapExplorationService.update_hidden_proximity(state, definition, Vector2i(int(cache.q), int(cache.r)), grid)
		var credit := AppState.inventory_count("CREDIT")
		check(MapExplorationService.claim_treasure(state, definition, cache.treasure_id).ok and AppState.inventory_count("CREDIT") == credit + int(cache.rewards.CREDIT), cid + " physical cache pays exact credit")
		check(SaveService.save_game().ok and SaveService.load_game().ok, cid + " actual save/load succeeds")
		state = AppState.chapter_map_state(map_id)
		check(MapExplorationService.event_state(state, early.event_id) == "RESOLVED" and not MapExplorationService.claim_treasure(state, definition, cache.treasure_id).ok, cid + " reload cannot duplicate discoveries or cache")
		check(not MapExplorationService.resolve_event(state, definition, late.event_id, "RECOVER").ok, cid + " reload preserves chosen evidence")
	print("FIELD_EXPLORATION total=%d pass=%d fail=%d regions=19" % [passed+failed, passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
