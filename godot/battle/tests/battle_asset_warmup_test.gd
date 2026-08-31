extends Node

var failures: Array[String] = []
var passed := 0

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS | ", message)
	else:
		failures.append(message)
		printerr("FAIL | ", message)

func _simulation(stage_id: String) -> BattleSimulation:
	var simulation := BattleSimulation.new()
	simulation.setup(AppState.create_party_snapshot(), DataRegistry.stage(stage_id), 880031, DataRegistry.data)
	return simulation

func _wait_until_ready(view: BattleView, frame_budget := 240) -> bool:
	for _frame in range(frame_budget):
		if view.assets_ready:
			return true
		await get_tree().process_frame
	return view.assets_ready

func _run() -> void:
	var boss_simulation := _simulation("CH15-N20")
	var boss_view := BattleView.new()
	boss_view.setup(boss_simulation)
	boss_view.paused = true
	add_child(boss_view)
	_check(not boss_view.assets_ready and not boss_view.is_processing(), "battle shell starts before asset warmup and simulation processing")
	await get_tree().process_frame
	_check(int(boss_simulation.state.tick) == 0, "simulation remains at tick zero while the first shell frame paints")
	_check(await _wait_until_ready(boss_view), "four-wave battle asset warmup completes within its frame budget")
	_check(int(boss_simulation.state.tick) == 0, "paused simulation does not advance during sliced asset warmup")

	var active_ids := boss_view._active_battle_entity_ids()
	var every_actor_ready := true
	var every_projectile_ready := true
	var every_vfx_ready := true
	for entity_id in active_ids:
		every_actor_ready = every_actor_ready and boss_view.sprite_library.supports_character(entity_id)
		every_projectile_ready = every_projectile_ready and boss_view.projectile_library.supports_source(entity_id)
		for kind in ["basic", "normal", "ultimate"]:
			var key := "%s_%s" % [entity_id.to_lower(), kind]
			every_vfx_ready = every_vfx_ready and (boss_view.vfx_frames.get(key, []) as Array).size() == 12
	_check(every_actor_ready, "every reinforcement actor atlas is registered before battle processing unlocks")
	_check(every_projectile_ready, "every reinforcement projectile atlas is registered before battle processing unlocks")
	_check(every_vfx_ready, "every reinforcement VFX atlas is registered before battle processing unlocks")
	_check(boss_view.normal_background != null and boss_view.boss_background != null, "boss stage retains both normal-wave and boss-wave backgrounds")

	var actor_pack_count := boss_view.sprite_library.frames.size()
	var projectile_pack_count := boss_view.projectile_library.frames.size()
	var vfx_pack_count := boss_view.vfx_frames.size()
	boss_simulation._spawn_next_wave()
	await get_tree().process_frame
	_check(
		boss_view.sprite_library.frames.size() == actor_pack_count
		and boss_view.projectile_library.frames.size() == projectile_pack_count
		and boss_view.vfx_frames.size() == vfx_pack_count,
		"wave transition performs no presentation asset registration or synchronous load"
	)
	boss_view.queue_free()
	await get_tree().process_frame

	var normal_view := BattleView.new()
	normal_view.setup(_simulation("CH01-N01"))
	normal_view.paused = true
	add_child(normal_view)
	_check(await _wait_until_ready(normal_view), "normal-stage asset warmup completes")
	_check(normal_view.normal_background != null and normal_view.boss_background == null, "normal stage skips the unused boss background preload")
	normal_view.queue_free()
	await get_tree().process_frame

	print("BATTLE_ASSET_WARMUP_SUMMARY pass=%d fail=%d" % [passed, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
