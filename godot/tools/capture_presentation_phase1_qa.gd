extends Node

## Captures the phase-1 battle presentation through the real shell: start band,
## nameplates/shout/combo, telegraph decals, long and short cut-ins, boss band,
## finale card, result stamp, chapter/EVENT title cards and the map boss band.
## Needs a rendering window (not --headless).
##   godot --path godot --resolution WxH res://tools/capture_presentation_phase1_qa.tscn -- <out_dir> <W> <H> [stage]

const OrnateTitleCard := preload("res://ui/ornate_title_card.gd")

var out_dir := ""
var tag := ""
var shell: Control
var report := {"shots": [], "notes": []}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = str(args[0])
	var width := int(args[1])
	var height := int(args[2])
	tag = "%dx%d" % [width, height]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().root.size = Vector2i(width, height)
	_run.call_deferred(str(args[3]) if args.size() > 3 else "CH01-N05")

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame

func _shot(name: String) -> void:
	await _frames(3)
	var path := out_dir.path_join("%s_%s.png" % [tag, name])
	get_tree().root.get_texture().get_image().save_png(path)
	report.shots.append(path.get_file())
	print("SHOT ", path.get_file())

func _run(stage_id: String) -> void:
	shell = load("res://screens/boot/boot.tscn").instantiate()
	get_tree().root.add_child(shell)
	await _frames(2)
	shell.call("_finish_intro_video")
	await _frames(2)
	SettingsService.values["battle_cutin_seen"] = []
	SettingsService.values["battle_cutin_mode"] = "SHORT"
	AppState.selected_stage_id = stage_id
	shell.call("_show_screen", "BATTLE")
	var view: BattleView = null
	for frame in 900:
		await get_tree().process_frame
		view = shell.get("battle_view") as BattleView
		if view != null and view.assets_ready and view.get_node_or_null("BattleOverlay") != null:
			break
	if view == null:
		print("CAPTURE_FAIL no battle view")
		get_tree().quit(1)
		return
	await _frames(60)
	shell.call("_start_deployed_battle")
	await _wait(0.45)
	report.notes.append("start_band_holding=%s tick=%d" % [view.start_band_holding(), view.simulation.state.tick])
	await _shot("01_start_band")
	# The first real ultimate plays its long first-use cut-in.
	var saw_cutin := false
	for frame in 900:
		await get_tree().process_frame
		if view.presentation_director.is_active() and bool(view.active_cutin.get("show", false)):
			saw_cutin = true
			break
	report.notes.append("real_cutin=%s %s" % [saw_cutin, JSON.stringify(view.cutin_snapshot())])
	if saw_cutin:
		await _wait(0.5)
		await _shot("01b_real_first_cutin")
	await _wait(2.4)
	# Let real combat produce nameplates, then hold the frame.
	view.simulation.options["invincible"] = true
	var saw_callout := false
	for frame in 900:
		await get_tree().process_frame
		if not view.skill_callouts.is_empty():
			saw_callout = true
			break
	report.notes.append("real_callout=%s" % saw_callout)
	view.paused = true
	var party: Array = view.simulation.state.party
	var foe: Dictionary = view.simulation.state.enemies[0] if not view.simulation.state.enemies.is_empty() else {}
	view._clear_active_presentation_effects()
	view._spawn_skill_callout(str(party[1].uid), view._action_label({"extra": {"skill_id": str(party[1].get("normal_skill_id", ""))}}), Color("79e8ff"), "normal")
	if not foe.is_empty():
		view._spawn_skill_callout(str(foe.uid), "파쇄 돌진", Color.WHITE, "normal")
	for callout in view.skill_callouts:
		callout.age = .5
	view.combo_count = 12
	view.combo_left = 1.6
	view.combo_pop = .5
	view.queue_redraw()
	await _shot("02_nameplate_shout_combo")
	# Telegraph decals: an area pattern and a single cell, part filled, plus a
	# landing flash on another cell.
	view._clear_active_presentation_effects()
	var caster_uid := str(foe.get("uid", party[0].uid))
	var tick := int(view.simulation.state.tick)
	view.simulation.pending_boss_casts.append({"due_tick": tick + 9, "boss_uid": caster_uid, "action": "IMPLODE", "target_uid": "", "multiplier": .7, "cells": [[1, 0], [1, 1], [1, 2], [0, 1], [2, 1]], "hp_ratio": .2, "shape": "PLUS", "label": "붕괴 파동", "windup_ticks": 24})
	view.simulation.pending_boss_casts.append({"due_tick": tick + 18, "boss_uid": caster_uid, "action": "LOCK_ON", "target_uid": "", "multiplier": 1.0, "cells": [[0, 2]], "hp_ratio": .3, "shape": "CELL", "label": "", "windup_ticks": 24})
	view.telegraph_flashes.append({"cells": [[0, 0]], "shape": "CELL", "age": .08})
	view.queue_redraw()
	await _shot("03_telegraph")
	view.simulation.pending_boss_casts.clear()
	view._clear_active_presentation_effects()
	# Long cut-in (first use), then the short one. Pending hit contacts would
	# hold an injected ultimate back, so they are dropped for the still frame.
	view.contact_events.clear()
	view._force_finish_active_presentation()
	var caster: Dictionary = party[0]
	view.cutin_mode = "SHORT"
	view.cutin_first_use_enabled = true
	view.cutin_seen_ids.clear()
	for mode in ["LONG", "SHORT"]:
		var target_uid := str(foe.get("uid", ""))
		view.simulation.event_log.append(BattleEvent.make(view.simulation.state.tick, BattleEvent.ULTIMATE, str(caster.uid), target_uid, 0, {"skill_id": str(caster.get("ultimate_skill_id", ""))}))
		view.consumed_events = view.simulation.event_log.size() - 1
		view.presentation_read_cursor = view.consumed_events
		view.presented_cursor = view.consumed_events
		view.paused = false
		view._consume_events()
		view.paused = true
		report.notes.append("%s active=%s cutin=%s" % [mode, view.presentation_director.is_active(), JSON.stringify(view.cutin_snapshot())])
		view.presentation_director.advance(.70 if mode == "LONG" else .40)
		view.queue_redraw()
		await _shot("04_cutin_long" if mode == "LONG" else "05_cutin_short")
		view._force_finish_active_presentation()
		view._clear_active_presentation_effects()
		view.contact_events.clear()
	# Boss band and end card, drawn from their real timelines.
	view.boss_entry_name = "침묵의 궤도 관제자"
	view.boss_entry_elapsed = 1.7
	view.queue_redraw()
	await _shot("06_boss_band")
	view.boss_entry_elapsed = -1.0
	view.finale_elapsed = .75
	view.queue_redraw()
	await _shot("07_finale")
	view.finale_elapsed = -1.0
	# Result stamp: finish the fight for real, then open the result.
	view.paused = false
	var simulation: BattleSimulation = view.simulation
	var safety := 0
	while not simulation.state.ended and safety < 20000:
		simulation.tick()
		safety += 1
	report.notes.append("victory=%s" % simulation.state.victory)
	shell.call("_battle_finished", simulation.result_snapshot())
	await _wait(1.6)
	await _shot("08_result")
	# Chapter opening card over the story.
	AppState.active_scenario_id = "SCN_CH01_INTRO"
	AppState.profile.last_scenario_position.erase("SCN_CH01_INTRO")
	shell.set("story_auto", false)
	shell.call("_show_screen", "STORY")
	await _wait(1.2)
	await _shot("09_chapter_card")
	await _wait(2.2)
	report.notes.append("story_card_open_after=%s" % shell.call("_story_title_card_open"))
	await _shot("10_story_after_card")
	# EVENT card through the real pre-battle event dialogue, fed the chapter 1
	# map's first authored event encounter (presentation only; no transaction).
	var definition: Dictionary = AppState.call("_chapter_map_definition", "CH01_MAP")
	var encounters: Array = definition.get("event_encounters", [])
	var authored: Dictionary = encounters[0] if not encounters.is_empty() else {}
	var recruitments: Array = authored.get("recruitments", [])
	var event_payload := {
		"event_kind": str(authored.get("event_kind", "COMPANION")),
		"enemy_id": str(authored.get("enemy_id", "")),
		"character_id": str(recruitments[0].get("character_id", authored.get("character_id", ""))) if not recruitments.is_empty() else str(authored.get("character_id", "")),
		"title_key": str(authored.get("title_key", "")),
		"body_key": str(authored.get("body_key", "")),
		"contact_outcome_key": str(authored.get("contact_outcome_key", "")),
		"pre_battle_dialogue": authored.get("pre_battle_dialogue", []).duplicate(true),
	}
	report.notes.append("event=%s" % JSON.stringify({"kind": event_payload.event_kind, "title": event_payload.title_key}))
	shell.call("_show_screen", "STAGE_SELECT")
	await _wait(0.4)
	var event_layer := CanvasLayer.new()
	event_layer.layer = 130
	get_tree().root.add_child(event_layer)
	var event_veil := ColorRect.new()
	event_veil.color = Color("06101ce0")
	event_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	event_veil.theme = shell.theme
	event_layer.add_child(event_veil)
	var focus := Label.new()
	shell.call("_play_special_event_dialogue", event_veil, event_payload, focus)
	await _wait(0.55)
	await _shot("11_event_card")
	await _wait(1.3)
	await _shot("12_event_dialog")
	event_layer.queue_free()
	# Map-side boss band (owner-managed card, same component as the transition).
	var layer := CanvasLayer.new()
	layer.layer = 140
	get_tree().root.add_child(layer)
	var veil := ColorRect.new()
	veil.color = Color("06101cf2")
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.theme = shell.theme
	layer.add_child(veil)
	var boss_card = OrnateTitleCard.new()
	boss_card.auto_close = false
	boss_card.configure("BOSS", "위협 신호 · 특이 개체 감지", "침묵의 궤도 관제자", "꺼진 노선 끝에서 거대한 신호가 깨어난다", 1.2)
	veil.add_child(boss_card)
	await _wait(0.5)
	await _shot("13_map_boss_band")
	print("PHASE1_CAPTURE ", JSON.stringify(report))
	get_tree().quit(0)
