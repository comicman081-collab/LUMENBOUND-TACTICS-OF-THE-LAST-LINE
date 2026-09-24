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
	var saturated := view.pool_diagnostics()
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
		"presentation_requests_per_burst": 100,
		"peak_projectiles": int(saturated.active_projectiles),
		"peak_damage_texts": int(saturated.active_floating_texts),
		"projectile_pool_recycled": _pool_reused(saturated, recycled, reused, "projectiles", BattleView.MAX_ACTIVE_PROJECTILES),
		"damage_text_pool_recycled": _pool_reused(saturated, recycled, reused, "floating_texts", BattleView.MAX_ACTIVE_FLOATING_TEXTS),
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

func _pool_reused(saturated: Dictionary, recycled: Dictionary, reused: Dictionary, kind: String, limit: int) -> bool:
	# Presentation has bounded on-screen budgets. A 100-event burst should reuse
	# that bounded pool, not create 100 concurrent sprites or damage labels.
	var active := "active_" + kind
	var available := "free_" + kind
	var allocated := int(saturated[active]) + int(saturated[available])
	return int(saturated[active]) == mini(100, limit) and allocated <= limit + 1 \
		and int(recycled[active]) == 0 and int(recycled[available]) == allocated \
		and int(reused[active]) == mini(100, limit) \
		and int(reused[active]) + int(reused[available]) == allocated
