extends Node

func _ready() -> void:
	AppState.new_game()
	SettingsService.values.developer_mode = false
	AppState.profile.chapter_progress.CH01.normal_highest = 19
	AppState.profile.account.stamina = 0
	AppState.profile.account.stamina_updated_at = int(Time.get_unix_time_from_system())
	AppState.selected_stage_id = "CH01-N20"
	var definition := ChapterMapLoader.load_map("CH01_MAP")
	var node := ChapterMapLoader.node_for_stage(definition, "CH01-N20")
	var target := Vector2i(int(node.q), int(node.r))
	# Real movement records the approach hex before crossing the contact tile.
	AppState.set_chapter_map_position(target + Vector2i.LEFT, "", "CH01_MAP")
	AppState.set_chapter_map_position(target, "NODE_N20", "CH01_MAP")
	var prepared := AppState.prepare_map_encounter("CH01-N20", "NODE_N20", target + Vector2i.LEFT, "CH01_MAP")
	var stalled_save := AppState.profile.duplicate(true)
	var map := ChapterMapScreen.new()
	map.map_id = "CH01_MAP"
	map.definition = definition
	map.map_state = AppState.chapter_map_state("CH01_MAP")
	map.turn_transitioning = true
	var shell := preload("res://screens/app_shell.gd").new()
	shell.footer_status = Label.new()
	shell.active_chapter_map_screen = map
	shell._map_battle_requested("CH01-N20")
	var stranded: bool = map.turn_transitioning and not map.map_state.pending_encounter.is_empty() and not shell.battle_transition_active
	var expect_stall := OS.get_cmdline_user_args().has("--expect-stall")
	var result := {"prepared":prepared,"zero_stamina":int(AppState.profile.account.stamina)==0,
		"stranded":stranded,"map_locked":map.turn_transitioning,"pending":map.map_state.pending_encounter,
		"transition_started":shell.battle_transition_active,"hidden_footer":shell.footer_status.text,
		"expected_stall":expect_stall,"passed":prepared and (stranded if expect_stall else not stranded)}
	if not expect_stall:
		AppState.apply_loaded(stalled_save)
		var recovered := AppState.chapter_map_state("CH01_MAP")
		result["old_stalled_save_recovers"] = recovered.pending_encounter.is_empty() and Vector2i(int(recovered.current_q),int(recovered.current_r)) == target + Vector2i.LEFT and int(AppState.profile.account.stamina)==0
		result.passed = result.passed and result.old_stalled_save_recovers
	var out := FileAccess.open("res://../reports/encounter_contact_fix_20260911/rejection_%s.json" % ("before" if expect_stall else "after"),FileAccess.WRITE)
	out.store_string(JSON.stringify(result,"\t"))
	out.close()
	print("ENCOUNTER_REJECTION ",JSON.stringify(result))
	shell.footer_status.free()
	shell.active_chapter_map_screen = null
	map.free()
	shell.free()
	get_tree().quit(0 if result.passed else 1)
