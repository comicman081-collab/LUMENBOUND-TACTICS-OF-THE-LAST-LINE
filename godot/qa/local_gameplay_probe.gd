extends Node

## Opt-in, localhost-only developer QA. Never exposes a command bridge on a
## public Release or a real save. Inputs still use browser pointer/key events;
## prepare_contact only reuses the existing sandbox late-stage fixture.
var poll_left := 0.0
var ready_announced := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var allowed := OS.has_feature("web") and SettingsService.is_developer_mode() and SaveService.is_soak_sandbox_enabled()
	if allowed:
		allowed = str(JavaScriptBridge.eval("(['localhost','127.0.0.1'].includes(location.hostname) && new URLSearchParams(location.search).get('gameplay-qa') === '1') ? '1' : '0'", true)) == "1"
	set_process(allowed)
	if allowed:
		JavaScriptBridge.eval("window.__localGameplayQA = {request:'', response:null, ready:false}", true)

func _process(delta: float) -> void:
	# Startup now warms only title pipelines; map pipelines are lazy at entry.
	# Waiting for them here would prevent the QA command that enters the first map.
	if not WebSoakProbe.web_title_warmup_complete: return
	if not ready_announced:
		JavaScriptBridge.eval("if(window.__localGameplayQA) window.__localGameplayQA.ready = true", true)
		ready_announced = true
	poll_left -= delta
	if poll_left > 0.0:
		return
	poll_left = 0.25
	var raw := str(JavaScriptBridge.eval("window.__localGameplayQA.request || ''", true))
	if raw.is_empty():
		return
	JavaScriptBridge.eval("window.__localGameplayQA.request = ''", true)
	var request = JSON.parse_string(raw)
	if not request is Dictionary:
		return
	var shell := _find_shell(get_tree().root)
	var result: Dictionary = {"error": "shell unavailable"}
	if shell != null:
		match str(request.get("command", "snapshot")):
			"prepare_motion_stage":
				# Artwork inspection only, isolated from player saves by this probe.
				shell.call("_finish_intro_video")
				AppState.new_game()
				var party: Array = []
				for id in request.get("party", ["CHR001","CHR002","CHR003","CHR004","CHR005"]):
					if str(id) in ["CHR001","CHR002","CHR003","CHR004","CHR005","CHR006","CHR007","CHR008"] and not party.has(str(id)):
						party.append(str(id))
				if party.size() == 5:
					AppState.profile.parties[0] = party
					AppState.selected_stage_id = "CH01-N20"
					AppState.debug_options.invincible = true
					SceneRouter.go("BATTLE")
					result = {"fixture":"motion art only, not victory evidence"}
			"motion_frame_fixture":
				var view = shell.get("battle_view")
				var action := str(request.get("action", "basic_attack"))
				if view is BattleView and view.assets_ready and action in ["basic_attack","normal_skill","ultimate"]:
					view.paused = true
					view._force_finish_active_presentation()
					view._clear_active_presentation_effects()
					view.floating_texts.clear()
					view.unit_flash.clear()
					view.boss_entry_elapsed = -1.0
					var frame := clampi(int(request.get("frame",0)),0,5)
					for unit in view.simulation.state.party + view.simulation.state.enemies:
						var melee := str(unit.role) in BattleView.ActorChoreography.MELEE_ROLES
						var times: Array = [0.0,.10,.25,.43,.53,.66] if melee else [0.0,.04,.09,.14,.27,.56]
						if action == "ultimate": times = [0.0,.26,.64,1.10 if melee else .82,1.23,1.70]
						var opponents: Array = view.simulation.state.enemies if str(unit.team)=="PLAYER" else view.simulation.state.party
						view.entry_tracks[unit.uid] = 1.0
						view.animation_tracks[unit.uid] = {"name":action,"elapsed":float(times[frame])+.001,"target_uid":str(opponents[0].uid)}
					view._snapshot_display_units_from_simulation()
					view.queue_redraw()
					result = {"fixture":"held real action renderer", "action":action,"frame":frame}
			"restart_fixture":
				shell.call("_finish_intro_video")
				AppState.profile.stage_stars["CH01-N01"] = 3
				AppState.profile.first_clear["CH01-N01"] = true
				AppState.profile.story_flags["PROLOGUE_READ"] = true
				AppState.profile.roster.CHR001.level = 15
				AppState.selected_stage_id = "CH02-N01"
				SaveService.save_game()
				SceneRouter.go("TITLE")
				result = {"fixture":"sandbox saved progress for real title restart buttons"}
			"damage_fixture":
				var view = shell.get("battle_view")
				if view is BattleView and view.assets_ready:
					view.paused = true
					view._force_finish_active_presentation()
					view._clear_active_presentation_effects()
					var units: Array = [view.simulation.state.party[0],view.simulation.state.party[2]]
					units.append_array(view.simulation.state.enemies.slice(0,2))
					for index in units.size():
						var unit: Dictionary = units[index]
						view.entry_tracks[unit.uid] = 1.0
						view._spawn_damage_text({"target":unit.uid,"value":18790 if index%2 else 1234,"extra":{"crit":index%2==1}})
						view.floating_texts.back().age = float(request.get("age",.05))
					view.queue_redraw()
					result = {"fixture":"held real damage number renderer"}
			"presentation_screen":
				var requested_screen := str(request.get("screen", "HOME"))
				if requested_screen in ["HOME", "TITLE", "ROSTER", "GROWTH", "FORMATION", "INVENTORY", "SETTINGS", "ARCHIVE", "RELAY"]:
					shell.call("_finish_intro_video")
					AppState.profile.tutorial_progress["home_basics_complete"] = true
					SceneRouter.go(requested_screen)
					result = {"screen": requested_screen}
			"snapshot":
				result = _snapshot(shell)
			"resume_saved_map":
				shell.call("_finish_intro_video")
				SceneRouter.go("STAGE_SELECT")
				result = {"fixture":"resume loaded save without changing progress"}
			"defeat_fixture":
				# The same localhost + developer + disposable-save gate as the other
				# fixtures. Hold the real renderer for exported-resource inspection.
				var view = shell.get("battle_view")
				if view is BattleView and view.assets_ready:
					view.paused = true
					view._force_finish_active_presentation()
					view._clear_active_presentation_effects()
					view.enemy_defeat_bursts.clear()
					var ids: Array[String] = []
					for id in request.get("ids", []):
						if str(id) in ["CHR001","CHR002","CHR003","CHR004","CHR005","CHR006","CHR007","CHR008"]: ids.append(str(id))
					view.sprite_library.load_down_pose_pack(ids)
					for index in range(mini(ids.size(), view.simulation.state.party.size())):
						var unit: Dictionary = view.simulation.state.party[index]
						unit.def_id = ids[index]
						unit.hp = 0
						unit.alive = false
						unit.state = "DOWN"
						view.animation_tracks[unit.uid] = {"name":"down", "elapsed":2.0}
						view.entry_tracks[unit.uid] = 1.0
					view._snapshot_display_units_from_simulation()
					for index in range(view.simulation.state.enemies.size()):
						var unit: Dictionary = view.simulation.state.enemies[index]
						if index == 1: unit.rank = "BOSS"
						view._seed_display_unit(unit)
						unit.hp = 0
						unit.alive = false
						unit.state = "DOWN"
						view._apply_display_event(BattleEvent.make(0, BattleEvent.DOWN, "", str(unit.uid)))
					view._advance_defeat_presentations(float(request.get("elapsed", .30)))
					view.queue_redraw()
					result = {"fixture":"held real defeat renderer", "ids":ids}
			"layout_fixture":
				# Local sandbox only: hold real UI builders for deterministic geometry
				# inspection. These fixtures are not evidence of gameplay transitions.
				shell.call("_finish_intro_video")
				shell.call("_cancel_transition_loading", int(shell.get("transition_loading_active_token")))
				shell.call("_dispose_map_reward_overlay", false)
				var kind := str(request.get("kind", "REWARD"))
				if kind == "LOADING":
					var token: int = shell.call("_begin_transition_loading", str(request.get("loading_kind", "BATTLE_ENTRY")))
					shell.call("_set_transition_loading_phase", token, "fixture phase", 90.0, 0.01)
				elif kind in ["REWARD", "RESULT"]:
					shell.set("last_rewards", {"CREDIT":1200, "TRAINING_NOTE_M":3})
					shell.set("last_reward_report", {"source_type":"BATTLE" if kind == "RESULT" else "EXPLORATION", "source_id":"CH01-N01", "rewards":{"CREDIT":1200, "TRAINING_NOTE_M":3}, "growth":{}, "first_clear":true})
					if kind == "REWARD": shell.call("_show_map_reward_overlay")
					else:
						shell.set("last_battle_result", {"victory":true,"time":15.47,"survivors":5,"damage":{},"healing":{}})
						SceneRouter.go("RESULT")
				result = {"fixture":"isolated layout", "kind":kind}
			"prepare_prologue":
				shell.call("_finish_intro_video")
				AppState.new_game()
				shell.call("_start_title_flow")
				result = {"fixture": "isolated fresh prologue"}
			"prepare_treasure_contact":
				var map_screen = shell.get("active_chapter_map_screen")
				if map_screen is ChapterMapScreen and map_screen.map_ready_complete and not map_screen.moving and not map_screen.turn_transitioning:
					for treasure in map_screen.definition.get("treasures", []):
						var treasure_id := str(treasure.get("treasure_id", ""))
						if MapExplorationService.treasure_state(map_screen.map_state, treasure_id) == "CLAIMED": continue
						var destination := Vector2i(int(treasure.q), int(treasure.r))
						for neighbor in HexCoord.neighbors(destination):
							if not map_screen.grid.traversable(neighbor): continue
							map_screen.map_state.current_q = neighbor.x
							map_screen.map_state.current_r = neighbor.y
							map_screen.map_state.current_party_hex = [neighbor.x, neighbor.y]
							map_screen.map_state.visited_tiles.append(HexCoord.key(neighbor))
							map_screen.map_state.last_selected_node = ""
							AppState.selected_map_node_id = ""
							map_screen.map_state.treasure_states[treasure_id] = "REVEALED"
							MapExplorationService.refill_movement(map_screen.map_state, map_screen.definition, map_screen.grid)
							SaveService.save_game()
							SceneRouter.go("STAGE_SELECT")
							result = {"fixture": "isolated unclaimed treasure neighbour", "treasure_id": treasure_id}
							break
						break
			"prepare_home_tutorial":
				shell.call("_finish_intro_video")
				if bool(request.get("fresh", false)): AppState.new_game()
				AppState.profile.tutorial_progress["home_basics_complete"] = false
				SceneRouter.go("HOME")
				result = {"fixture": "isolated first-home tutorial"}
			"prepare_contact":
				var number := int(request.get("stage_number", 0))
				if number >= 1 and number <= 20:
					shell.call("_finish_intro_video")
					shell.call("_debug_prepare_map_contact", "NODE_N%02d" % number)
					AppState.debug_options.invincible = bool(request.get("invincible", false))
					SceneRouter.go("STAGE_SELECT")
					result = {"fixture": "reward-free CH01 neighbour", "stage": AppState.selected_stage_id}
			"prepare_stage_contact":
				result = _prepare_stage_contact(shell, request)
			"prepare_node_contact":
				var map_screen = shell.get("active_chapter_map_screen")
				if map_screen is ChapterMapScreen and map_screen.map_ready_complete:
					var node := ChapterMapLoader.node_by_id(map_screen.definition, str(request.get("node_id", "")))
					if not node.is_empty():
						var target := MapSimulation.coord_for(map_screen.map_state, str(node.node_id))
						for candidate in HexCoord.neighbors(target):
							if map_screen.grid.can_step(candidate, target):
								AppState.set_chapter_map_position(candidate, "", str(map_screen.map_id))
								MapExplorationService.refill_movement(map_screen.map_state, map_screen.definition, map_screen.grid)
								AppState.selected_stage_id = str(node.stage_id)
								SaveService.save_game()
								SceneRouter.go("STAGE_SELECT")
								result = {"fixture":"physical node neighbour; existing treasure and kill state preserved", "node_id":node.node_id}
								break
			"restore_contact_stamina":
				# Disposable-save fixture only; normal input still owns the retry.
				AppState.profile.account.stamina = AppState.account_max_stamina()
				AppState.profile.account.stamina_updated_at = int(Time.get_unix_time_from_system())
				var map = shell.get("active_chapter_map_screen")
				if is_instance_valid(map): map._refresh_state_visuals()
				result = {"fixture":"restore sandbox entry resource", "stamina":AppState.profile.account.stamina}
			"prepare_art_stage":
				# Actual authored encounter, isolated by this probe's localhost,
				# developer and disposable-save gates. No rewards are granted here.
				var stage_id := str(request.get("stage_id", ""))
				if not DataRegistry.stage(stage_id).is_empty():
					shell.call("_finish_intro_video")
					AppState.selected_stage_id = stage_id
					AppState.debug_options.invincible = true
					SceneRouter.go("BATTLE")
					result = {"fixture":"authored stage art verification", "stage":stage_id}
			"art_boss_wave":
				# Hold the real renderer at the existing final wave; this fixture
				# proves visual loading, not that the preceding waves were won.
				var view = shell.get("battle_view")
				if view is BattleView and view.assets_ready:
					view.paused = true
					view._force_finish_active_presentation()
					view._clear_active_presentation_effects()
					while view.simulation.wave_director.has_next():
						view.simulation._spawn_next_wave()
					view._snapshot_display_units_from_simulation()
					for unit in view.simulation.state.enemies:
						view.entry_tracks[unit.uid] = 1.0
					view.queue_redraw()
					result = {"fixture":"held authored final wave", "wave":view.simulation.state.wave}
			"prepare_fresh_first_map":
				# A separate, reward-free fixture for the real CH01 starting hex. Contact
				# fixtures deliberately stage beside an enemy and therefore cannot prove
				# the initial 3/3 movement contract.
				shell.call("_finish_intro_video")
				AppState.new_game()
				AppState.active_scenario_id = ""
				AppState.selected_stage_id = "CH01-N01"
				AppState.selected_map_node_id = ""
				SceneRouter.go("STAGE_SELECT")
				result = {"fixture": "isolated fresh CH01 start", "stage": AppState.selected_stage_id}
			"prepare_region":
				var number := int(request.get("chapter_number", 0))
				if number >= 1 and number <= 20:
					shell.call("_finish_intro_video")
					for index in range(1, number + 1):
						AppState.profile.chapter_progress["CH%02d" % index].unlocked = true
					AppState.selected_stage_id = "CH%02d-N01" % number
					AppState.selected_map_node_id = ""
					SceneRouter.go("STAGE_SELECT")
					result = {"fixture": "isolated region entry; original story triggers retained", "stage": AppState.selected_stage_id}
			"prepare_growth":
				shell.call("_finish_intro_video")
				var mode := str(request.get("mode", "funded"))
				if mode != "resume":
					AppState.new_game()
					AppState.profile.account.level = 30
					for id in AppState.profile.inventory: AppState.profile.inventory[id] = 0 if mode == "empty" else 5000
					AppState.profile.inventory.CREDIT = 0 if mode == "empty" else 500000
					AppState.selected_character_id = "CHR001"
					if mode == "cap": AppState.profile.roster.CHR001.level = 20
					if mode == "fixed":
						AppState.profile.roster.CHR007.unlocked = true
						AppState.selected_character_id = "CHR007"
					SaveService.save_game()
				SceneRouter.go("GROWTH")
				result = {"fixture": "isolated growth " + mode}
			"prepare_story_gap":
				var number := int(request.get("chapter_number", 0))
				if number in [1, 2]:
					shell.call("_finish_intro_video")
					AppState.new_game()
					var chapter_id := "CH%02d" % number
					var chapter := DataRegistry.chapter(chapter_id)
					AppState.profile.chapter_progress[chapter_id].unlocked = true
					AppState.queue_story_event("MAP_ENTER", "", chapter_id)
					AppState.complete_story_trigger_for_scenario("SCN_" + chapter_id + "_INTRO")
					for stage_id in chapter.required_stage_ids:
						if int(DataRegistry.stage(stage_id).stage_number) <= (8 if number == 1 else 4):
							AppState.profile.first_clear[stage_id] = true
							AppState.profile.stage_stars[stage_id] = 1
							AppState.profile.chapter_progress[chapter_id].normal_highest = int(DataRegistry.stage(stage_id).stage_number)
					AppState.selected_stage_id = chapter_id + ("-N08" if number == 1 else "-N04")
					SaveService.save_game()
					SceneRouter.go("STAGE_SELECT")
					result = {"fixture": "isolated mandatory route with interrupted story queue", "chapter": chapter_id}
	JavaScriptBridge.eval("window.__localGameplayQA.response = " + JSON.stringify({"id": request.get("id", 0), "result": result}), true)

func _prepare_stage_contact(shell: Control, request: Dictionary) -> Dictionary:
	var stage_id := str(request.get("stage_id", "CH01-N20"))
	var stage := DataRegistry.stage(stage_id)
	if stage.is_empty(): return {"error":"unknown authored stage"}
	SettingsService.values.developer_mode = true
	shell.call("_finish_intro_video")
	AppState.new_game()
	var chapter_id := str(stage.chapter_id)
	var map_id := AppState.map_id_for_stage(stage_id)
	var definition := ChapterMapLoader.load_map(map_id)
	var node := ChapterMapLoader.node_for_stage(definition, stage_id)
	var grid := HexGrid.new()
	grid.load_tiles(definition.tiles)
	var state := AppState.chapter_map_state(map_id)
	var hard: bool = str(stage.mode) == "HARD"
	var progress: Dictionary = AppState.profile.chapter_progress[chapter_id]
	progress.unlocked = true
	progress.hard_unlocked = hard
	progress.normal_highest = 20 if hard else int(stage.stage_number) - 1
	for candidate in definition.nodes:
		var candidate_id := str(candidate.get("stage_id", ""))
		if candidate_id.is_empty() or candidate_id == stage_id: continue
		var prior := DataRegistry.stage(candidate_id)
		if (str(prior.mode) == "NORMAL" and (hard or int(prior.stage_number) < int(stage.stage_number))) or (hard and str(prior.mode) == "HARD" and int(prior.stage_number) < int(stage.stage_number)):
			AppState.profile.stage_stars[candidate_id] = 3
			AppState.profile.first_clear[candidate_id] = true
			MapExplorationService.mark_encounter_cleared(state, str(candidate.node_id))
	MapExplorationService.ensure_state(state, definition, grid)
	var target := Vector2i(int(node.q), int(node.r))
	if not MapSimulation.patrol_definition(definition, str(node.node_id)).is_empty():
		target = MapSimulation.coord_for(state, str(node.node_id))
	var neighbour := target
	for candidate in HexCoord.neighbors(target):
		if grid.can_step(candidate, target):
			neighbour = candidate
			break
	if neighbour == target: return {"error":"no physical neighbour"}
	AppState.set_chapter_map_position(neighbour, "", map_id)
	state.movement_points = state.movement_points_max
	AppState.selected_stage_id = stage_id
	AppState.selected_map_node_id = str(node.node_id)
	AppState.profile.account.stamina = int(request.get("stamina", AppState.account_max_stamina()))
	AppState.profile.account.stamina_updated_at = int(Time.get_unix_time_from_system())
	if bool(request.get("daily_exhausted", false)):
		AppState.profile.hard_attempts.counts[stage_id] = int(stage.daily_attempts)
	for trigger in DataRegistry.list_of("chapter_story_triggers"):
		var flag := str(trigger.get("completion_flag", ""))
		if bool(request.get("campaign_flow", false)):
			var next_stage := AppState.next_chapter_entry(chapter_id)
			var next_chapter := str(DataRegistry.stage(next_stage).get("chapter_id", ""))
			if str(trigger.id) in ["TRIG_" + chapter_id + "_OUTRO", "TRIG_" + next_chapter + "_INTRO"]: continue
		if not flag.is_empty(): AppState.profile.story_flags[flag] = true
	if bool(request.get("campaign_flow", false)):
		# A geared, legal roster fixture; combat still runs ordinary damage,
		# AI, waves, timer, resource cost and the actual victory transaction.
		for id in AppState.get_party():
			AppState.profile.roster[id].level = 60
			AppState.profile.roster[id].breakthrough = 3
			AppState.profile.roster[id].skills = {"normal": 5, "passive": 5, "ultimate": 5}
		for weapon in AppState.profile.weapons.values(): weapon.level = 40
	AppState.profile.tutorial_progress.map_basics_revision = 999
	AppState.profile.tutorial_progress.home_basics_complete = true
	AppState.debug_options.invincible = false
	AppState.debug_options.unlock_all = false
	SaveService.save_game()
	# Exercise the same stamina/unlock/daily-ledger conditions as Release. The
	# bridge remains confined to the disposable localhost development session.
	SettingsService.values.developer_mode = false
	SceneRouter.go("STAGE_SELECT")
	return {"fixture":"real-rule authored neighbour", "stage":stage_id,"neighbour":[neighbour.x,neighbour.y],"target":[target.x,target.y]}

func _find_shell(node: Node) -> Control:
	if node is Control and node.has_method("_show_chapter_map"):
		return node as Control
	for child in node.get_children():
		if child is SubViewport:
			continue
		var found := _find_shell(child)
		if found != null:
			return found
	return null

func _snapshot(shell: Control) -> Dictionary:
	var result := {"screen": str(shell.get("current_screen")), "stage": AppState.selected_stage_id,
		"campaign_transition": AppState.profile.get("campaign_transition", {}).duplicate(),
		"chapter_progress": AppState.profile.chapter_progress.duplicate(true), "scenario": AppState.active_scenario_id,
		"region_resume_stage": shell.region_entry_stage(str(DataRegistry.stage(AppState.selected_stage_id).get("chapter_id", ""))),
		"transition_loading": {"active": int(shell.get("transition_loading_active_token")) > 0,
			"kind": str(shell.get("transition_loading_kind"))},
		"density_cache": preload("res://battle/view/density_texture_loader.gd").cache_snapshot(),
		"map_preload_msec": int(shell.get("last_stage_preload_elapsed_msec")),
		"pending_story": AppState.profile.get("pending_story_triggers", []).duplicate(),
		"story_shards": int(AppState.profile.get("inventory", {}).get("LANTERN_SHARD", 0)),
		"sandbox": SaveService.sandbox_audit_summary(), "party": AppState.get_party().duplicate(), "active_party": int(AppState.profile.active_party), "buttons": [], "scrolls": [],
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))}
	var logical := shell.get_viewport_rect().size
	result["restart_progress"] = {"stars":AppState.profile.stage_stars.duplicate(),"first_clear":AppState.profile.first_clear.duplicate(),"story_flags":AppState.profile.story_flags.duplicate(),"character_level":int(AppState.profile.roster.CHR001.level)}
	result["growth"] = {"character": AppState.selected_character_id, "state": AppState.profile.roster.get(AppState.selected_character_id, {}).duplicate(true), "target": shell.get("growth_target_level"), "inventory": AppState.profile.inventory.duplicate(true)}
	var layout: Vector2 = shell.call("_runtime_layout_size")
	result["layout"] = {"viewport": [logical.x, logical.y], "size": [layout.x, layout.y], "portrait": shell.call("_is_portrait_layout"), "rotation_prompt": shell.get_node_or_null("R6ViewportGate") != null, "paused": get_tree().paused}
	_collect_controls(shell, result.buttons, result.scrolls)
	result["labels"] = []
	_collect_reading_labels(shell, result.labels)
	result["panels"] = []
	for panel_name in ["TransitionLoadingPanel", "MapRewardPanel", "BattleOverlay", "GrowthStickyAction"]:
		var panel := shell.find_child(panel_name, true, false) as Control
		if panel != null and panel.is_visible_in_tree(): result.panels.append({"name":panel_name, "rect":_control_css_rect(panel)})
	result["modals"] = []
	for modal_name in ["PreBattleEventDialog", "HomeFirstOperationTutorial", "FirstMapTutorial", "BossEncounterTitleCard", "RegionTravelOverlay", "NewGameConfirmation"]:
		var modal := shell.find_child(modal_name, true, false) as Control
		if modal != null and modal.is_visible_in_tree():
			var labels: Array = []
			_collect_reading_labels(modal, labels)
			result.modals.append({"name": modal_name, "rect": _control_css_rect(modal), "labels": labels})
	if result.screen == "RESULT":
		result["result"] = shell.get("last_battle_result").duplicate(true)
	if result.screen == "GROWTH":
		var selected := AppState.selected_character_id
		var reading: Array = []
		_collect_reading_labels(shell, reading)
		result["growth"] = {"labels": reading, "tab": shell.get("growth_tab"), "feedback": shell.get("growth_feedback"), "character": selected, "progress": AppState.profile.roster[selected].duplicate(true), "inventory": AppState.profile.inventory.duplicate(true)}
	if result.screen == "STORY":
		var body := shell.get("scenario_text") as RichTextLabel
		if body != null:
			result["story"] = {"scenario": AppState.active_scenario_id, "text": body.get_parsed_text(), "content_height": body.get_content_height(), "visible_height": body.size.y, "visible_ratio": body.visible_ratio}
			var dialogue := shell.get("story_dialogue_panel") as Control
			if dialogue != null: result.story["dialogue_rect"] = _control_css_rect(dialogue)
			result.story["body_rect"] = _control_css_rect(body)
	var map_value = shell.get("active_chapter_map_screen")
	if map_value is ChapterMapScreen and is_instance_valid(map_value):
		var map_screen := map_value as ChapterMapScreen
		var next := map_screen._next_encounter_node()
		var preview: Array = []
		for coord in map_screen.preview_path:
			preview.append([coord.x, coord.y])
		result["map"] = {"ready": map_screen.map_ready_complete, "moving": map_screen.moving,
			"chapter": str(map_screen.definition.get("chapter_id", "")),
			"palette": preload("res://chapter_map/view/region_palette.gd").for_definition(map_screen.definition).family,
			"status": map_screen.status_label.text,
			"natural_terrain": not map_screen.natural_terrain_info.is_empty(),
			"natural_chunks": int(map_screen.get_meta("natural_terrain_chunks", 0)),
			"natural_river_chunks": int(map_screen.get_meta("natural_river_chunks", 0)),
			"persistent_grid_cells": map_screen.persistent_cell_grid.cells.size() if map_screen.persistent_cell_grid != null else 0,
			"persistent_grid_drawn": map_screen.persistent_cell_grid.drawn_cells if map_screen.persistent_cell_grid != null else 0,
			"natural_bridge_tiles": int(map_screen.get_meta("natural_bridge_tiles", 0)),
			"environment_meshes": preload("res://chapter_map/view/environment_mesh_library.gd").load_once().keys(),
			"paused": map_screen.map_simulation_paused,
			"turn_transitioning": map_screen.turn_transitioning,
			"position": [int(map_screen.map_state.current_q), int(map_screen.map_state.current_r)],
			"selected_node": str(map_screen.selected_node.get("node_id", "")),
			"selected_target": [map_screen._selected_target_coord().x, map_screen._selected_target_coord().y],
			"pending_encounter": map_screen.map_state.get("pending_encounter", {}).duplicate(true),
			"selected_can_enter": AppState.can_enter_stage(str(map_screen.selected_node.get("stage_id", ""))),
			"player_rules": not SettingsService.is_developer_mode(),
			"stamina": int(AppState.profile.account.stamina),
			"selected_unlocked": AppState.is_stage_unlocked(str(map_screen.selected_node.get("stage_id", ""))),
			"battle_transition_active": bool(shell.get("battle_transition_active")),
			"movement_points": int(map_screen.map_state.get("movement_points", 0)),
			"movement_points_max": int(map_screen.map_state.get("movement_points_max", 0)),
			"next": str(next.get("stage_id", "")), "preview": preview,
			"reachable": map_screen.movement_range_reachable.size(),
			"enemy_pawns": map_screen.enemy_pawns.size(), "grid_tiles": map_screen.definition.get("tiles", []).size(),
			"pawn_texture": _texture_snapshot(map_screen.pawn_sprite.texture) if map_screen.pawn_sprite != null else {},
			"camera_size": map_screen.camera.size if map_screen.camera != null else 0.0}
		result.map["terrain_samples"] = _terrain_samples(map_screen)
		if is_instance_valid(map_screen.tutorial_panel):
			var text_scale := map_screen.tutorial_body.get_viewport().get_screen_transform().get_scale().y
			result.map["tutorial"] = {"visible": map_screen.tutorial_panel.is_visible_in_tree(), "step": map_screen.tutorial_step, "panel": _control_css_rect(map_screen.tutorial_panel), "body": _control_css_rect(map_screen.tutorial_scroll), "content_height": map_screen.tutorial_body.get_content_height()*text_scale, "continue": _control_css_rect(map_screen.tutorial_continue_button), "title": map_screen.tutorial_title.text}
		result.map["camera_target"] = [map_screen.camera_target.x, map_screen.camera_target.y, map_screen.camera_target.z]
		result.map["enemy_camera_subject"] = map_screen.enemy_camera_subject
		result.map["enemy_camera_history"] = map_screen.enemy_camera_history.duplicate(true)
		result.map["minimap"] = map_screen.route_minimap.exploration_snapshot()
		result.map.minimap["rect"] = _control_css_rect(map_screen.route_minimap)
		result.map["full_map_open"] = is_instance_valid(map_screen.explored_map_view)
		if is_instance_valid(map_screen.explored_map_view): result.map["full_map"] = map_screen.explored_map_view.exploration_snapshot()
		result.map["treasures"] = []
		result.map["encounter_receipts"] = map_screen.map_state.get("encounter_clear_receipts", {}).duplicate()
		result.map["cleared_nodes"] = map_screen.map_state.get("cleared_nodes", []).duplicate()
		result.map["patrol_states"] = map_screen.map_state.get("patrol_states", {}).duplicate(true)
		result.map["terraced_terrain"] = map_screen.TERRACED_TACTICAL_TERRAIN
		var treasure_transform := map_screen.viewport_container.get_viewport().get_screen_transform() * map_screen.viewport_container.get_global_transform_with_canvas()
		result.map["enemies"] = []
		var enemy_surface_scale := map_screen.viewport_container.size / Vector2(map_screen.viewport.size)
		for node in map_screen.definition.nodes:
			var id := str(node.node_id)
			var root = map_screen.enemy_pawns.get(id)
			if root == null: continue
			var point: Vector2 = treasure_transform * (map_screen.camera.unproject_position(root.position) * enemy_surface_scale)
			result.map.enemies.append({"id":id,"stage":node.get("stage_id",""),"scout":node.get("forward_patrol",false),"visible":root.visible,"screen":[point.x,point.y]})
		var treasure_scale := map_screen.viewport_container.size / Vector2(map_screen.viewport.size)
		for treasure in map_screen.definition.get("treasures", []):
			var id := str(treasure.get("treasure_id", ""))
			var root: Node3D = map_screen.treasure_visuals.get(id)
			var point := treasure_transform * (map_screen.camera.unproject_position(root.position + Vector3(0, .25, 0)) * treasure_scale) if root != null else Vector2.ZERO
			result.map.treasures.append({"id": id, "state": MapExplorationService.treasure_state(map_screen.map_state, id), "visible": root != null and root.visible, "q": treasure.get("q"), "r": treasure.get("r"), "screen": [point.x, point.y]})
		result.map["field_events"] = []
		var event_transform := map_screen.viewport_container.get_viewport().get_screen_transform() * map_screen.viewport_container.get_global_transform_with_canvas()
		var event_scale := map_screen.viewport_container.size / Vector2(map_screen.viewport.size)
		for event in map_screen.definition.get("map_events", []):
			var root: Node3D = map_screen.event_visuals.get(str(event.event_id))
			if root == null: continue
			var point := event_transform * (map_screen.camera.unproject_position(root.position + Vector3(0, .62, 0)) * event_scale)
			result.map.field_events.append({"id": event.event_id, "state": MapExplorationService.event_state(map_screen.map_state, event.event_id), "visible": root.visible, "screen": [point.x, point.y]})
		result.map["training_notes"] = AppState.inventory_count("TRAINING_NOTE_S")

		result.map["instance_id"] = map_screen.get_instance_id()
		result.map["toolbar_rect"] = _control_css_rect(map_screen.toolbar)
		result.map["detail"] = {"visible": map_screen.detail_panel.visible,
			"rect": _control_css_rect(map_screen.detail_panel), "z": map_screen.detail_panel.z_index}
		var map_transform := map_screen.viewport_container.get_viewport().get_screen_transform() * map_screen.viewport_container.get_global_transform_with_canvas()
		var map_rect := map_transform * Rect2(Vector2.ZERO, map_screen.viewport_container.size)
		result.map["viewport_rect"] = [map_rect.position.x, map_rect.position.y, map_rect.size.x, map_rect.size.y]
		var backdrop := map_screen.find_child("ContinuousForestBackdrop", true, false)
		result.map["backdrop"] = {"present": backdrop != null, "instances": int(backdrop.get_meta("background_instance_count", 0)) if backdrop != null else 0}
	var battle_value = shell.get("battle_view")
	if battle_value is BattleView and is_instance_valid(battle_value):
		var battle := battle_value as BattleView
		if battle.simulation != null:
			var sim := battle.simulation
			var actors: Array = []
			for unit in sim.state.party + sim.state.enemies:
				var id := str(unit.def_id)
				var texture := battle.sprite_library.signature_texture_at(id, "idle", 0.2) if battle.signature_sprite_pack_ready else null
				var action_textures: Dictionary = {}
				for action in ["idle", "move", "basic_attack", "normal_skill", "ultimate", "hit", "down", "victory"]:
					action_textures[action] = _texture_snapshot(battle.sprite_library.texture_at(id, action, 0.2))
				actors.append({"id": id, "uid": str(unit.uid), "hp": int(unit.hp), "team": str(unit.team), "rank": str(unit.get("rank", "")), "body_scale": battle._combat_sprite_scale(unit, "idle"), "foot": [battle._unit_pos(unit).x, battle._unit_pos(unit).y], "texture": _texture_snapshot(texture), "action_textures": action_textures,
					"down_pose": _texture_snapshot(battle.sprite_library.down_pose_texture(id)),
					"source_asset_id": str(battle.sprite_library.manifests.get(id,{}).get("source_asset_id","")),
					"motion_track": battle.animation_tracks.get(str(unit.uid), {}).duplicate(true),
					"action_motion": battle.action_motion_snapshot(unit),
					"ground_contact": battle.ground_contact_snapshot(unit)})
			result["battle"] = {"ready": battle.assets_ready, "phase": battle.asset_warmup_phase,
				"boss_scene": battle.boss_scene_snapshot(),
				"wave_scene": battle.wave_scene_snapshot(),
				"contact_queue": battle.contact_events.size(), "contact_commits": battle.contact_commits,
				"combat_readout": battle.combat_readout,
				"enemy_defeat_bursts": battle.enemy_defeat_bursts.size(),
				"hd": battle.sprite_library.full_density_snapshot(),
				"action_frames": battle.action_frames.snapshot(),
				"time": sim.state.time_elapsed, "wave": sim.state.wave, "wave_count": sim.state.wave_count,
				"ended": sim.state.ended, "paused": battle.paused,
				"actors": actors, "projectiles": battle.projectiles.size(), "vfx": battle.vfx_presentations.size(),
				"actor_error": battle.sprite_library.load_error, "projectile_error": battle.projectile_library.load_error,
				"signature": battle.signature_runtime_residency_snapshot(), "presentation": battle.presentation_cursor_snapshot()}
			result.battle["damage_numbers"] = []
			var transform := battle.get_viewport().get_screen_transform()*battle.get_global_transform_with_canvas()
			for text in battle.floating_texts:
				var metrics := battle.damage_number_layout(text)
				var position: Vector2 = transform * (metrics.position as Vector2)
				var head: Vector2 = transform * (metrics.head as Vector2)
				result.battle.damage_numbers.append({"text":text.text,"target":text.target,"crit":metrics.crit,"font_css":metrics.font_css,"position":[position.x,position.y],"head":[head.x,head.y],"width_css":float(metrics.width)*float(metrics.pop)*float(metrics.screen_scale),"font":"Lantern Rounded Black","pop":metrics.pop})
	return result

func _control_css_rect(control: Control) -> Array:
	var transform := control.get_viewport().get_screen_transform() * control.get_global_transform_with_canvas()
	var bounds := transform * Rect2(Vector2.ZERO, control.size)
	return [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]

func _collect_reading_labels(node: Node, labels: Array) -> void:
	if node is SubViewport: return
	if node is Control and not node.is_visible_in_tree(): return
	if node is Label or node is RichTextLabel:
		var rect := _control_css_rect(node)
		var font_key := "font_size" if node is Label else "normal_font_size"
		labels.append({"name": str(node.name), "text": node.text, "rect": rect,
			"font_css": node.get_theme_font_size(font_key) * node.get_viewport().get_screen_transform().get_scale().y})
	for child in node.get_children(): _collect_reading_labels(child, labels)

func _terrain_samples(screen: ChapterMapScreen) -> Array:
	var samples: Array = []
	if not screen.map_ready_complete or screen.camera == null: return samples
	var transform := screen.viewport_container.get_viewport().get_screen_transform() * screen.viewport_container.get_global_transform_with_canvas()
	var scale_2d := screen.viewport_container.size / Vector2(screen.viewport.size)
	var counts := {}
	var coords: Array = screen.grid.tiles.keys()
	var player := Vector2i(int(screen.map_state.current_q), int(screen.map_state.current_r))
	coords.sort_custom(func(a, b): return HexCoord.distance(player, HexCoord.from_key(str(a))) < HexCoord.distance(player, HexCoord.from_key(str(b))))
	for key in coords:
		var coord := HexCoord.from_key(str(key))
		if not screen._coord_is_in_player_vision(coord): continue
		var tile: Dictionary = screen.grid.tile(coord)
		var kind := str(tile.get("terrain_type", ""))
		if kind not in ["SHALLOW_WATER", "BRIDGE", "RUINS"] or int(counts.get(kind, 0)) >= 5: continue
		var world := HexCoord.axial_to_world(coord, screen.TILE_SIZE, float(tile.get("elevation", 0)) * screen.ELEVATION_STEP + .14)
		var local := screen.camera.unproject_position(world) * scale_2d
		if not Rect2(Vector2.ZERO, screen.viewport_container.size).grow(-24).has_point(local): continue
		var css := transform * local
		samples.append({"coord": [coord.x, coord.y], "type": kind, "blocked": not screen.grid.traversable(coord), "reachable": screen.movement_range_reachable.has(str(key)), "screen": [snappedf(css.x, .1), snappedf(css.y, .1)]})
		counts[kind] = int(counts.get(kind, 0)) + 1
	return samples

func _texture_snapshot(texture: Texture2D) -> Dictionary:
	if texture == null:
		return {}
	var result := {"width": texture.get_width(), "height": texture.get_height(), "path": texture.resource_path}
	if texture is AtlasTexture:
		result["atlas_path"] = texture.atlas.resource_path
		result["atlas_size"] = [texture.atlas.get_width(), texture.atlas.get_height()]
	return result

func _collect_controls(node: Node, buttons: Array, scrolls: Array) -> void:
	if node is SubViewport:
		return
	if node is Control and node.is_visible_in_tree():
		var control := node as Control
		var transform := control.get_viewport().get_screen_transform() * control.get_global_transform_with_canvas()
		var bounds := transform * Rect2(Vector2.ZERO, control.size)
		var rect := [snappedf(bounds.position.x, .1), snappedf(bounds.position.y, .1), snappedf(bounds.size.x, .1), snappedf(bounds.size.y, .1)]
		if control is Button:
			var font := control.get_theme_font("font")
			var font_size := control.get_theme_font_size("font_size")
			var line_width := 0.0
			for line in control.text.split("\n"): line_width = maxf(line_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
			buttons.append({"text": control.text, "name": str(control.name), "disabled": control.disabled, "rect": rect,
				"font_css":font_size * transform.get_scale().y, "nowrap":control.autowrap_mode == TextServer.AUTOWRAP_OFF,
				"text_width":line_width * transform.get_scale().x, "content_width":(control.size.x - control.get_theme_stylebox("normal").get_minimum_size().x) * transform.get_scale().x})
		elif control is ScrollContainer:
			scrolls.append({"name": str(control.name), "rect": rect, "value": control.scroll_vertical,
				"max": control.get_v_scroll_bar().max_value, "page": control.get_v_scroll_bar().page})
	for child in node.get_children():
		_collect_controls(child, buttons, scrolls)
