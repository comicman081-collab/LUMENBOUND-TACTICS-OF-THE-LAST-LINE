extends Node

const Direction := preload("res://battle/view/battle_wave_transition.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	AppState.new_game()
	_timeline()
	_contacts_and_hold()
	_boss_and_skip()
	print("BATTLE_WAVE_TRANSITION total=%d pass=%d failures=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _timeline() -> void:
	for boss in [false, true]:
		var end := Direction.duration(boss)
		var viewport := Vector2(1920, 1080)
		var enemy := Vector2(1500, 580)
		var ally := Vector2(340, 640)
		var previous := Direction.camera(0, boss, viewport, enemy, ally)
		var phases := {}
		for step in range(roundi(end * 120) + 1):
			var elapsed := step / 120.0
			var beat := Direction.sample(elapsed, boss)
			var camera := Direction.camera(elapsed, boss, viewport, enemy, ally)
			phases[beat.phase] = true
			var cover := viewport * .5 * (float(camera.zoom) - 1.0)
			check(absf((camera.offset as Vector2).x) <= cover.x + .001 and absf((camera.offset as Vector2).y) <= cover.y + .001,
				"camera keeps the environment covering the entire 1080p viewport")
			check((camera.offset as Vector2).distance_to(previous.offset) < 32.0 and absf(float(camera.zoom) - float(previous.zoom)) < .03,
				"camera remains continuous at 120Hz, boss=%s step=%d" % [boss, step])
			previous = camera
		check(phases.size() == 5, "wide/aperture/enemy/squad/return phases all exist")
		check(float(Direction.sample(.91, boss).mask) == 1.0, "environment cut is covered by opaque aperture")
		check(float(Direction.sample(2.3, boss).enemy_caption) > .95, "enemy cue has a readable hold")
		check(float(Direction.sample(3.9 if boss else 3.35, boss).ally_caption) > .95, "squad answers before camera returns")
		check(is_equal_approx(float(previous.zoom), 1.0) and (previous.offset as Vector2).length() < .01,
			"camera rejoins the exact gameplay transform")

func _contacts_and_hold() -> void:
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage("CH01-N05"), 5042, DataRegistry.data)
	var view := BattleView.new()
	view.size = Vector2(1920, 1080)
	view.setup(sim)
	view.assets_ready = true
	view.opening_elapsed = 2.0
	view._consume_events()
	for unit in sim.state.enemies:
		unit.hp = 0
		sim._down_unit(unit, str(sim.state.party[0].uid), "BASIC")
	sim._check_flow()
	view._consume_events()
	var tick := sim.state.tick
	var hash_before := sim.event_hash()
	check(not view._detect_wave_entrance() and not view.contact_events.is_empty(), "last-wave contacts settle before the camera owns the screen")
	check(view._waiting_for_wave_contact(), "spawn tick blocks new attacks while contacts drain")
	view.speed = 3
	for index in range(8): view._process(.1)
	check(view.wave_entry_elapsed >= 0.0 and view.wave_entry_wave == 2, "ordinary wave starts the authored scene after contact")
	check(sim.state.tick == tick and sim.event_hash() == hash_before, "spawn, contact drain and entrance never advance combat at 3x")
	var elapsed := view.wave_entry_elapsed
	view.paused = true
	view._process(.5)
	check(view.wave_entry_elapsed == elapsed, "pause freezes the entire ordinary wave scene")
	view.paused = false
	view._process(Direction.WAVE_DURATION - elapsed + .01)
	check(not view.scene_transition_active() and sim.state.tick == tick and view.accumulator == 0.0,
		"scene finishes without catch-up ticks or leftover accumulator")
	view._process(BattleSimulation.TICK_DELTA)
	check(sim.state.tick > tick, "real combat resumes after the pull-back")
	check(not view._detect_wave_entrance(), "same ordinary wave never replays its scene")
	view.setup(sim)
	check(view.wave_entry_elapsed < 0 and view.wave_entry_enemy_uid.is_empty(), "reusing the view clears transition state")
	view.free()

func _boss_and_skip() -> void:
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage("CH01-N20"), 5043, DataRegistry.data)
	var view := BattleView.new()
	view.size = Vector2(1920, 1080)
	view.setup(sim)
	while sim.wave_director.has_next(): sim._spawn_next_wave()
	view._consume_events()
	check(view._detect_wave_entrance(), "boss wave uses the same encounter scene flow")
	view.boss_entry_elapsed = .91
	check(view._boss_background_mix() > 0.0 and float(view.wave_scene_snapshot().mask) == 1.0,
		"boss background changes behind the aperture")
	view.boss_entry_elapsed = 2.3
	check(view._compute_battlefield_camera_zoom() > 1.3 and view._compute_battlefield_offset().length() > 100,
		"boss shot moves the camera to the actual SD actor")
	var finishes: Array = []
	view.battle_finished.connect(func(result): finishes.append(result))
	check(view.skip_to_result() and sim.state.ended, "skip settles the authoritative simulation during a scene")
	check(not view.scene_transition_active() and finishes.size() == 1 and not view.skip_to_result(),
		"skip clears both scene clocks and emits exactly one result")
	view.free()
