extends Node

## Phase 1 battle/event presentation (2026-09-30): nameplate priority, combo
## counter, cut-in modes and first-use record, the long cut-in lead-in, the
## victory end card, telegraph landing flashes, settings defaults and the
## chapter/event title cards. Everything checked here is view-only.

const BattlePresentationDirectorScript := preload("res://battle/view/battle_presentation_director.gd")
const OrnateTitleCard := preload("res://ui/ornate_title_card.gd")
const ResultStamp := preload("res://ui/result_stamp.gd")

var checks := 0
var failures := 0

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("%s %s" % [label, detail])

func _simulation(seed_value: int, stage_id := "CH01-N01") -> BattleSimulation:
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage(stage_id), seed_value, DataRegistry.data)
	return sim

func _ready() -> void:
	AppState.new_game()
	_callout_priority()
	_combo_counter()
	_cutin_plans()
	_director_lead_in()
	_view_lead_in()
	_finale_card()
	_start_band_hold()
	_telegraph_flash()
	_settings_defaults()
	_title_cards()
	print("BATTLE_PRESENTATION_PHASE1_TESTS total=%d pass=%d fail=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _callout_priority() -> void:
	var sim := _simulation(3101)
	var view := BattleView.new()
	view.setup(sim)
	var party: Array = sim.state.party
	view._spawn_skill_callout(str(party[0].uid), "스킬 A", Color.WHITE, "normal")
	view._spawn_skill_callout(str(party[1].uid), "스킬 B", Color.WHITE, "normal")
	view._spawn_skill_callout(str(party[2].uid), "스킬 C", Color.WHITE, "normal")
	var after_three := view.skill_callout_snapshot()
	check(after_three.size() == 2, "at most two nameplates are on screen", JSON.stringify(after_three))
	view._spawn_skill_callout(str(party[3].uid), "필살기", Color.WHITE, "ultimate")
	var with_ultimate := view.skill_callout_snapshot()
	var has_ultimate := with_ultimate.any(func(item): return int(item.priority) == 2)
	check(with_ultimate.size() == 2 and has_ultimate, "an ultimate replaces an ordinary nameplate", JSON.stringify(with_ultimate))
	view._spawn_skill_callout(str(party[4].uid), "필살기 2", Color.WHITE, "ultimate")
	view._spawn_skill_callout(str(party[0].uid), "스킬 D", Color.WHITE, "normal")
	var saturated := view.skill_callout_snapshot()
	check(saturated.size() == 2 and saturated.all(func(item): return int(item.priority) == 2), "an ordinary skill cannot push out two ultimates", JSON.stringify(saturated))
	view._spawn_skill_callout(str(party[4].uid), "필살기 3", Color.WHITE, "ultimate")
	var same_caster := view.skill_callout_snapshot().filter(func(item): return str(item.source) == str(party[4].uid))
	check(same_caster.size() == 1 and str(same_caster[0].label) == "필살기 3", "a caster keeps one nameplate; the newest cue wins")
	view._clear_active_presentation_effects()
	var enemy: Dictionary = sim.state.enemies[0]
	view._spawn_skill_callout(str(enemy.uid), "화염 분사", Color.WHITE, "normal")
	view._spawn_skill_callout(str(party[0].uid), "ULT", Color.WHITE)
	var styles := view.skill_callout_snapshot()
	var enemy_entry: Array = styles.filter(func(item): return str(item.source) == str(enemy.uid))
	var ally_entry: Array = styles.filter(func(item): return str(item.source) == str(party[0].uid))
	check(not enemy_entry.is_empty() and str(enemy_entry[0].style) == "shout" and str(enemy_entry[0].role) == "", "enemies shout in a bubble without a role chip")
	check(not ally_entry.is_empty() and str(ally_entry[0].style) == "plate" and not str(ally_entry[0].role).is_empty() and int(ally_entry[0].priority) == 2 and str(ally_entry[0].label) != "ULT", "allies get a role nameplate and the legacy ULT cue reads as an ultimate")
	view.free()

func _combo_counter() -> void:
	var sim := _simulation(3102)
	var view := BattleView.new()
	view.setup(sim)
	var ally := str(sim.state.party[2].uid)
	var foe := str(sim.state.enemies[0].uid)
	var log_before := sim.event_log.size()
	for index in range(4):
		view._register_combo_hit(BattleEvent.make(0, BattleEvent.DAMAGE, ally, foe, 120, {"source": "BASIC"}))
	view._register_combo_hit(BattleEvent.make(0, BattleEvent.DAMAGE, foe, ally, 80, {"source": "BASIC"}))
	view._register_combo_hit(BattleEvent.make(0, BattleEvent.DAMAGE, ally, foe, 0, {"source": "BASIC", "miss": true}))
	var combo := view.combo_snapshot()
	check(int(combo.count) == 4 and bool(combo.visible), "allied hits count; enemy hits and misses do not", JSON.stringify(combo))
	view._advance_combo(BattleView.COMBO_WINDOW * .5)
	check(int(view.combo_snapshot().count) == 4, "the combo survives inside its window")
	view._advance_combo(BattleView.COMBO_WINDOW)
	var expired := view.combo_snapshot()
	check(int(expired.count) == 0 and int(expired.peak) == 4 and not bool(expired.visible), "the combo resets after the window and keeps its peak", JSON.stringify(expired))
	check(sim.event_log.size() == log_before, "the combo counter never writes to the event log")
	view.free()

func _cutin_plans() -> void:
	var sim := _simulation(3103)
	var view := BattleView.new()
	view.setup(sim)
	var ally: Dictionary = sim.state.party[0]
	var foe: Dictionary = sim.state.enemies[0]
	var short_plan := view.cutin_plan_for(ally)
	check(view.cutin_mode == "SHORT" and bool(short_plan.show) and not bool(short_plan.long), "a bare view defaults to the short cut-in without a first-use record", JSON.stringify(short_plan))
	check(not bool(view.cutin_plan_for(foe).show), "enemy ultimates keep the compact pulse")
	view.cutin_mode = "OFF"
	check(not bool(view.cutin_plan_for(ally).show), "OFF disables the character cut-in")
	view.cutin_mode = "FULL"
	check(bool(view.cutin_plan_for(ally).long), "FULL always plays the long cut-in")
	view.cutin_mode = "SHORT"
	view.cutin_first_use_enabled = true
	var first := view.cutin_plan_for(ally)
	check(bool(first.long) and bool(first.first_use), "SHORT goes long on a character's first use", JSON.stringify(first))
	view._mark_cutin_seen(str(ally.def_id))
	var second := view.cutin_plan_for(ally)
	check(bool(second.show) and not bool(second.long), "after the first use the same character plays short", JSON.stringify(second))
	check(BattleView.normalized_cutin_mode("full") == "FULL" and BattleView.normalized_cutin_mode("banana") == "SHORT", "cut-in mode names are normalised")
	view.free()

func _director_lead_in() -> void:
	var director = BattlePresentationDirectorScript.new()
	director.begin_ultimate({"id": "ULT:test", "events": [], "lead_in": 1.0})
	var frozen: Dictionary = director.advance(.5)
	check(is_zero_approx(float(frozen.actor_delta)) and not bool(frozen.battlefield_prep) and director.in_lead_in(), "the lead-in freezes actors before the ordinary timeline")
	var snapshot: Dictionary = director.cinematic_snapshot()
	check(float(snapshot.cutin_visibility) > .9 and is_equal_approx(float(snapshot.cutin_clock), .5), "the long cut-in is fully open during the lead-in", JSON.stringify(snapshot))
	var straddle: Dictionary = director.advance(.6)
	check(not director.in_lead_in() and is_equal_approx(float(director.elapsed), .1) and is_equal_approx(float(straddle.actor_delta), .1), "a frame straddling the lead-in end carries only the remainder into the timeline", "elapsed=%f actor=%f" % [director.elapsed, float(straddle.actor_delta)])
	var prep: Dictionary = director.advance(.49)
	var impact: Dictionary = director.advance(.54)
	check(bool(prep.battlefield_prep) and bool(impact.impact_commit), "prep and impact keep their timeline offsets after the lead-in")
	var finished := false
	for _frame in range(20):
		if bool(director.advance(.1).finished):
			finished = true
			break
	check(finished, "the timeline still finishes after a lead-in")
	director.reset()
	check(is_zero_approx(director.lead_in_total) and is_zero_approx(director.lead_in_elapsed), "reset clears the lead-in")
	var plain = BattlePresentationDirectorScript.new()
	plain.begin_ultimate({"id": "ULT:plain", "events": []})
	check(bool(plain.advance(.59).battlefield_prep), "without a lead-in the ordinary timeline is unchanged")

func _ultimate_view(seed_value: int, mode: String) -> Dictionary:
	var sim := _simulation(seed_value)
	var source: Dictionary = sim.state.party[0]
	source.def_id = "CHR001"
	var target: Dictionary = sim.state.enemies[0]
	var view := BattleView.new()
	view.setup(sim)
	view.cutin_mode = mode
	sim.event_log.append(BattleEvent.make(sim.state.tick, BattleEvent.ULTIMATE, str(source.uid), str(target.uid), 0, {"skill_id": "SK001_U"}))
	sim.event_log.append(BattleEvent.make(sim.state.tick, BattleEvent.DAMAGE, str(source.uid), str(target.uid), 10, {"source": "ULTIMATE", "hp_damage": 10, "shield_damage": 0}))
	view._consume_events()
	return {"sim": sim, "view": view}

func _view_lead_in() -> void:
	var short_case := _ultimate_view(3104, "SHORT")
	var short_view: BattleView = short_case.view
	var short_impact: Dictionary = short_view.presentation_director.advance(1.13)
	check(bool(short_impact.impact_commit) and bool(short_view.cutin_snapshot().plan.get("show", false)), "the short cut-in keeps the ordinary impact time", JSON.stringify(short_view.cutin_snapshot()))
	check(short_view.skill_callout_snapshot().is_empty(), "the character cut-in replaces the ultimate nameplate")
	short_view._force_finish_active_presentation()
	short_view.free()
	var full_case := _ultimate_view(3105, "FULL")
	var full_view: BattleView = full_case.view
	check(is_equal_approx(float(full_view.cutin_snapshot().lead_in_total), BattleView.LONG_CUTIN_LEAD_IN), "FULL adds the long lead-in", JSON.stringify(full_view.cutin_snapshot()))
	var early: Dictionary = full_view.presentation_director.advance(1.13)
	var late: Dictionary = full_view.presentation_director.advance(BattleView.LONG_CUTIN_LEAD_IN)
	check(not bool(early.impact_commit) and bool(late.impact_commit), "the long cut-in delays impact by exactly its lead-in")
	full_view._force_finish_active_presentation()
	full_view.free()
	var off_case := _ultimate_view(3106, "OFF")
	var off_view: BattleView = off_case.view
	check(not bool(off_view.cutin_snapshot().plan.get("show", true)) and off_view.skill_callout_snapshot().size() == 1, "OFF falls back to the compact pulse plus an ultimate nameplate")
	off_view._force_finish_active_presentation()
	off_view.free()

func _finale_card() -> void:
	var sim := _simulation(3107)
	var view := BattleView.new()
	view.setup(sim)
	var results: Array = []
	view.battle_finished.connect(func(result: Dictionary): results.append(result))
	view.consumed_events = sim.event_log.size()
	view.presentation_read_cursor = sim.event_log.size()
	view.presented_cursor = sim.event_log.size()
	sim.state.ended = true
	sim.state.victory = true
	view._process(.1)
	check(results.is_empty() and view.finale_elapsed >= 0.0 and view.scene_transition_active(), "an ordinary victory holds the end card before the result")
	view._process(BattleView.FINALE_DURATION)
	view._process(.01)
	check(results.size() == 1 and view.emitted_finish, "the end card hands off to the result exactly once", "results=%d" % results.size())
	view._process(.5)
	check(results.size() == 1, "no second result after the end card")
	view.free()
	var defeat_sim := _simulation(3108)
	var defeat_view := BattleView.new()
	defeat_view.setup(defeat_sim)
	defeat_view.consumed_events = defeat_sim.event_log.size()
	defeat_view.presentation_read_cursor = defeat_sim.event_log.size()
	defeat_view.presented_cursor = defeat_sim.event_log.size()
	defeat_sim.state.ended = true
	defeat_sim.state.victory = false
	defeat_view._process(0.0)
	check(defeat_view.emitted_finish and defeat_view.finale_elapsed < 0.0, "a defeat goes straight to the result")
	defeat_view.setup(_simulation(3109))
	check(defeat_view.finale_elapsed < 0.0 and not defeat_view.scene_transition_active(), "setup resets the end card")
	defeat_view.free()

func _start_band_hold() -> void:
	var sim := _simulation(3120)
	var view := BattleView.new()
	view.setup(sim)
	view.deployment_active = true
	view._process(.05)
	view.opening_elapsed = 2.0
	view.deployment_active = false
	var start_tick := int(sim.state.tick)
	view._process(.30)
	view._process(.30)
	view._process(.25)
	check(view.wave_banner_title == BattleView.START_BAND_TITLE and view.start_band_holding() and int(sim.state.tick) == start_tick, "the start band holds the first tick after the deployment", "tick=%d banner=%.2f" % [sim.state.tick, view.wave_banner_left])
	view._process(.10)
	view._process(.10)
	check(not view.start_band_holding() and int(sim.state.tick) > start_tick, "the battle starts once the start band has been read", "tick=%d" % sim.state.tick)
	view.free()
	var direct := BattleView.new()
	direct.setup(_simulation(3121))
	direct._process(.05)
	check(not direct.start_band_holding(), "a battle without a deployment phase has no start hold")
	direct.free()

func _telegraph_flash() -> void:
	var sim := _simulation(3110)
	var view := BattleView.new()
	view.setup(sim)
	var caster: Dictionary = sim.state.enemies[0]
	var due := int(sim.state.tick) + 10
	var cast := {"due_tick": due, "boss_uid": str(caster.uid), "action": "IMPLODE", "target_uid": "", "multiplier": .7, "cells": [[1, 0], [1, 1], [1, 2], [0, 1], [2, 1]], "hp_ratio": .2, "shape": "PLUS", "label": "", "windup_ticks": 20}
	sim.pending_boss_casts.append(cast)
	view._track_telegraph_landings()
	var snapshot := view.telegraph_snapshot()
	var urgency := float((snapshot.casts as Array)[0].urgency)
	check(int(snapshot.tracked) == 1 and is_equal_approx(urgency, .5), "a pending cast is tracked with its fill progress", JSON.stringify(snapshot))
	sim.pending_boss_casts.clear()
	view._track_telegraph_landings()
	check(int(view.telegraph_snapshot().flashes) == 0, "a cast removed before its due tick does not flash")
	sim.pending_boss_casts.append(cast.duplicate(true))
	view._track_telegraph_landings()
	sim.state.tick = due
	sim.pending_boss_casts.clear()
	view._track_telegraph_landings()
	check(int(view.telegraph_snapshot().flashes) == 1, "a landed cast flashes its cells once")
	view._clear_active_presentation_effects()
	check(int(view.telegraph_snapshot().flashes) == 0 and int(view.presentation_residual_snapshot().active_effect_count) == 0, "skip/terminal cleanup clears landing flashes")
	view.free()

func _settings_defaults() -> void:
	var persisted := SettingsService.persisted_values()
	check(str(persisted.get("battle_cutin_mode", "")) == "SHORT" and persisted.get("battle_cutin_seen", null) is Array, "the cut-in setting defaults to SHORT and persists with the profile", JSON.stringify(persisted))
	var saved_mode := str(SettingsService.values.battle_cutin_mode)
	SettingsService.apply_saved({"battle_cutin_mode": "OFF", "battle_cutin_seen": ["CHR001"]})
	var view := BattleView.new()
	view._bind_cutin_settings()
	check(view.cutin_mode == "OFF" and view.cutin_seen_ids.has("CHR001") and view.cutin_first_use_enabled, "a bound view reads the saved mode and first-use record")
	view.cutin_mode = "SHORT"
	view._mark_cutin_seen("CHR003")
	check((SettingsService.values.battle_cutin_seen as Array).has("CHR003"), "a first long cut-in is recorded in the saved settings")
	view.free()
	SettingsService.apply_saved({"battle_cutin_mode": saved_mode, "battle_cutin_seen": []})

func _title_cards() -> void:
	var shell = preload("res://screens/app_shell.gd").new()
	var chapter: Dictionary = shell.chapter_title_card_data("SCN_CH01_INTRO")
	check(str(chapter.get("eyebrow", "")) == "CHAPTER 01" and str(chapter.get("number", "")) == "제1장" and str(chapter.get("title", "")) == "꺼진 노선의 신호" and not str(chapter.get("subtitle", "")).is_empty(), "chapter 1 opening card data", JSON.stringify(chapter))
	check(str(shell.chapter_title_card_data("SCN_CH02_HARD_INTRO").get("eyebrow", "")).contains("HARD"), "hard chapter openings are marked")
	check(shell.chapter_title_card_data("SCN_CH01_MID_A").is_empty() and shell.chapter_title_card_data("SCN_PROLOGUE").is_empty(), "only chapter openings get the card")
	shell.free()
	var card = OrnateTitleCard.new()
	card.configure("EVENT", "특별 신호 조우", "탐색 기록", "", 1.0)
	add_child(card)
	var closes := [0]
	card.finished.connect(func(): closes[0] += 1)
	card._process(.1)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	card._gui_input(tap)
	check(is_equal_approx(card.elapsed, .1) and card.is_open(), "an early tap is ignored until the card has settled")
	card._process(.3)
	card._gui_input(tap)
	check(card.elapsed >= card.duration - .21 and card.is_open(), "a settled tap jumps to the closing fade")
	card._process(.3)
	card._process(.3)
	check(closes[0] == 1 and not card.is_open(), "a skipped card closes exactly once", "closes=%d" % closes[0])
	var held = OrnateTitleCard.new()
	held.auto_close = false
	held.configure("BOSS", "위협 신호", "보스", "", .5)
	add_child(held)
	held._process(2.0)
	check(held.is_open(), "an owner-managed boss band never closes itself")
	held.queue_free()
	var stamp = ResultStamp.new()
	add_child(stamp)
	stamp._process(.2)
	var early := stamp.landed()
	stamp._process(.4)
	check(not early and stamp.landed(), "the result stamp lands after its delay")
	stamp.queue_free()
