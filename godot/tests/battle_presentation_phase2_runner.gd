extends Node

## Phase 2 battle scale read (D7, 2026-09-30): regular enemies read as
## three-body squads sharing one HP bar, and the next wave waits as silhouettes
## behind the enemy side. Everything checked here is view-only.

var checks := 0
var failures := 0

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("%s %s" % [label, detail])

func _simulation(seed_value: int, stage_id: String) -> BattleSimulation:
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage(stage_id), seed_value, DataRegistry.data)
	return sim

func _multi_wave_stage() -> String:
	for stage in DataRegistry.data.get("stages", []):
		var waves: Array = stage.get("waves", [])
		if waves.size() < 2 or str(stage.get("boss_id", "")) != "": continue
		var regular := false
		for enemy_id in waves[0]:
			if str(DataRegistry.enemy(str(enemy_id)).get("rank", "NORMAL")) == "NORMAL": regular = true
		if regular: return str(stage.id)
	return "CH01-N01"

func _ready() -> void:
	AppState.new_game()
	_member_counts()
	_eligibility()
	_squad_drops()
	_next_wave()
	print("BATTLE_PRESENTATION_PHASE2_TESTS total=%d pass=%d fail=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _member_counts() -> void:
	var samples := {1.0: 3, .67: 3, .66: 2, .5: 2, .34: 2, .33: 1, .1: 1, 0.0: 1}
	var wrong: Array = []
	for ratio in samples:
		if BattleView.swarm_member_count(float(ratio)) != int(samples[ratio]):
			wrong.append("%s->%d" % [ratio, BattleView.swarm_member_count(float(ratio))])
	check(wrong.is_empty(), "a squad shows 3 bodies above 2/3 HP, 2 above 1/3, then 1", JSON.stringify(wrong))
	check(BattleView.swarm_member_count(2.0 / 3.0) == 2 and BattleView.swarm_member_count(1.0 / 3.0) == 1, "a body drops exactly at its third")

func _eligibility() -> void:
	check(BattleView.swarm_unit({"team": "ENEMY", "rank": "NORMAL"}), "regular enemies are squads")
	check(not BattleView.swarm_unit({"team": "ENEMY", "rank": "ELITE"}) and not BattleView.swarm_unit({"team": "ENEMY", "rank": "BOSS"}), "elites and bosses stay single")
	check(not BattleView.swarm_unit({"team": "PLAYER", "rank": "NORMAL"}), "allies are never squads")

func _squad_drops() -> void:
	var stage_id := _multi_wave_stage()
	var sim := _simulation(4201, stage_id)
	var view := BattleView.new()
	view.setup(sim)
	var target: Dictionary = {}
	for enemy in sim.state.enemies:
		if BattleView.swarm_unit(enemy):
			target = enemy
			break
	check(not target.is_empty(), "the test stage has a regular enemy", stage_id)
	if target.is_empty():
		view.free()
		return
	var uid := str(target.uid)
	view._track_swarm_members()
	check(int(view.swarm_snapshot().members.get(uid, 0)) == 3 and int(view.swarm_snapshot().drops) == 0, "a fresh squad has three bodies and no drops", JSON.stringify(view.swarm_snapshot()))
	# Squads follow the shown HP, which moves when a hit is presented.
	var max_hp := int(target.max_hp)
	var live_hp := int(target.hp)
	var half := int(max_hp * .5)
	view._apply_display_event(BattleEvent.make(sim.state.tick, BattleEvent.DAMAGE, "", uid, half, {"hp_damage": half}))
	view._track_swarm_members()
	check(int(view.swarm_snapshot().members.get(uid, 0)) == 2 and int(view.swarm_snapshot().drops) == 1, "losing a third drops one body with a burst", JSON.stringify(view.swarm_snapshot()))
	view._track_swarm_members()
	check(int(view.swarm_snapshot().drops) == 1, "a drop is recorded once")
	view._apply_display_event(BattleEvent.make(sim.state.tick, BattleEvent.DOWN, "", uid, 0))
	view._track_swarm_members()
	check(int(view.swarm_snapshot().members.get(uid, 0)) == 1 and int(view.swarm_snapshot().drops) == 2, "a kill drops the remaining rear body", JSON.stringify(view.swarm_snapshot()))
	check(int(target.hp) == live_hp and int(target.max_hp) == max_hp and bool(target.alive), "squad bookkeeping never touches the simulated unit")
	for drop in view.swarm_drops: drop.age = BattleView.SWARM_DROP_DURATION + .01
	view._track_swarm_members()
	check(int(view.swarm_snapshot().drops) == 0, "finished drop bursts are recycled")
	view.swarm_drops.append({"uid": uid, "index": 0, "age": 0.0})
	view._clear_active_presentation_effects()
	check(view.swarm_drops.is_empty(), "clearing presentation effects clears drop bursts")
	view.free()

func _next_wave() -> void:
	var stage_id := _multi_wave_stage()
	var stage := DataRegistry.stage(stage_id)
	var sim := _simulation(4202, stage_id)
	var view := BattleView.new()
	view.size = Vector2(1600, 900)
	view.setup(sim)
	var expected := BattleSimulation.wave_layout(stage, 1, DataRegistry.data)
	var layout := view.next_wave_layout()
	check(layout.size() == expected.size() and not layout.is_empty(), "the first wave previews the second wave's layout", "%s %d/%d" % [stage_id, layout.size(), expected.size()])
	var ids_match := true
	for index in range(mini(layout.size(), expected.size())):
		if str(layout[index].id) != str(expected[index].id): ids_match = false
	check(ids_match, "preview ids follow the deployment layout order")
	check(view.next_wave_layout() == layout and int(view.next_wave_cache.index) == 1, "the preview is cached per wave")
	var points := view.next_wave_silhouette_points(maxi(1, layout.size()))
	var back_lane_y := view.cell_screen_center(5, 0).y
	var enemy_side_x := view.cell_screen_center(4, 0).x
	var placed := true
	for point in points:
		if point.y >= back_lane_y or point.x < enemy_side_x or point.x > view.size.x: placed = false
	check(placed, "silhouettes stand behind the far lane on the enemy side", JSON.stringify(points))
	var portrait := BattleView.new()
	portrait.size = Vector2(390, 844)
	portrait.setup(_simulation(4203, stage_id))
	var portrait_points := portrait.next_wave_silhouette_points(4)
	var portrait_ok := true
	for point in portrait_points:
		if point.x > portrait.size.x or point.y >= portrait.cell_screen_center(5, 0).y: portrait_ok = false
	check(portrait_ok, "portrait silhouettes stay on screen behind the far lane", JSON.stringify(portrait_points))
	portrait.free()
	# Advance to the last wave: nothing waits behind it.
	var safety := 0
	while sim.wave_director.has_next() and safety < 40000 and not sim.state.ended:
		sim.options["invincible"] = true
		sim.tick()
		safety += 1
	check(not sim.wave_director.has_next() and view.next_wave_layout().is_empty(), "the last wave has no silhouettes", "wave=%d ended=%s" % [sim.state.wave, sim.state.ended])
	view.free()
