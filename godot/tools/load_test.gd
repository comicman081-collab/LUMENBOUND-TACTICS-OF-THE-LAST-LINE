extends Node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var party_snapshot := AppState.create_party_snapshot()
	for character in party_snapshot:
		character.progress.level = 100
		character.progress.breakthrough = 5
		character.progress.skills = {"normal": 10, "passive": 10, "ultimate": 5}
	var stage := DataRegistry.stage("CH01-H05").duplicate(true)
	stage.time_limit = 600
	var load_wave: Array = []
	for i in range(20): load_wave.append("ENM003")
	stage.waves = [load_wave]
	var simulation := BattleSimulation.new()
	simulation.setup(party_snapshot, stage, 817600, DataRegistry.data, {"invincible": true, "enemy_multiplier": 100.0, "retain_event_log": false})
	while not simulation.state.ended and simulation.state.tick < 9000:
		simulation.tick()
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	while not simulation.state.ended and simulation.state.tick < 18000:
		simulation.tick()
	var view := BattleView.new()
	view.setup(simulation)
	var source_uid := str(simulation.state.party[0].uid)
	var target_uid := str(simulation.state.enemies[0].uid)
	for i in range(100):
		view._spawn_projectile(source_uid, target_uid, "BASIC")
		view._spawn_floating_text({"target": target_uid, "text": str(i), "color": Color.WHITE, "age": 1.0})
	for projectile in view.projectiles: projectile.age = 1.0
	view._recycle_expired_presentations()
	var recycled := view.pool_diagnostics()
	for i in range(100):
		view._spawn_projectile(source_uid, target_uid, "BASIC")
		view._spawn_floating_text({"target": target_uid, "text": str(i), "color": Color.WHITE, "age": 0.0})
	var reused := view.pool_diagnostics()
	view.free()
	var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var memory_delta := memory_after - memory_before
	var report := {
		"kind": "HEADLESS_SIMULATED_LOAD_TEST",
		"actual_wall_clock_10_minute_visual_soak": false,
		"simulation_seconds": simulation.state.time_elapsed,
		"simulation_ticks": simulation.state.tick,
		"party_units": simulation.state.party.size(),
		"simultaneous_enemies": simulation.state.enemies.size(),
		"peak_projectiles": 100,
		"peak_damage_texts": 100,
		"projectile_pool_recycled": int(recycled.free_projectiles) == 100 and int(reused.active_projectiles) == 100 and int(reused.free_projectiles) == 0,
		"damage_text_pool_recycled": int(recycled.free_floating_texts) == 100 and int(reused.active_floating_texts) == 100 and int(reused.free_floating_texts) == 0,
		"memory_static_before": memory_before,
		"memory_static_after": memory_after,
		"memory_static_delta": memory_delta,
		"memory_growth_threshold_bytes": 16777216,
		"memory_growth_within_threshold": memory_delta <= 16777216,
		"battle_terminal_reason": simulation.state.reason,
		"event_log_retained": simulation.event_log.size(),
		"streaming_event_hash": simulation.event_hash(),
	}
	var report_path := ProjectSettings.globalize_path("res://").path_join("../reports/load_test.json").simplify_path()
	var output := FileAccess.open(report_path, FileAccess.WRITE)
	if output == null:
		printerr("could not write ", report_path)
		get_tree().quit(2)
		return
	output.store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	var passed: bool = simulation.state.tick == 18000 and simulation.state.enemies.size() == 20 and bool(report.projectile_pool_recycled) and bool(report.damage_text_pool_recycled) and bool(report.memory_growth_within_threshold)
	get_tree().quit(0 if passed else 1)
