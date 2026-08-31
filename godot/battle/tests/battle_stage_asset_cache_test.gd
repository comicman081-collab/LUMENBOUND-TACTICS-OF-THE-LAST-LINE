extends Node

var failures: Array[String] = []
var passed := 0
var ready_signal_count := 0

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS | ", message)
	else:
		failures.append(message)
		printerr("FAIL | ", message)

func _run() -> void:
	var party_ids: Array = ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005"]
	var map_definition := AppState._chapter_map_definition("CH01_MAP")
	var cache_ready := await StageAssetCache.warm_for_stage_select(
		"CH01_MAP", map_definition, party_ids, "CH01-N01", ["CH01-N01"]
	)
	_check(cache_ready, "stage-select cache completes for the selected normal battle")

	var simulation := BattleSimulation.new()
	simulation.setup(AppState.create_party_snapshot(), DataRegistry.stage("CH01-N01"), 880031, DataRegistry.data)
	var view := BattleView.new()
	view.setup(simulation)
	view.paused = true
	ready_signal_count = 0
	view.battle_assets_ready.connect(func() -> void: ready_signal_count += 1)
	get_tree().root.add_child(view)
	for _frame in range(8):
		if view.assets_ready:
			break
		await get_tree().process_frame
	_check(view.assets_ready and view.asset_cache_hit, "BattleView attaches the complete StageAssetCache bundle before direct warmup")
	_check(ready_signal_count == 1, "battle_assets_ready emits exactly once after cache attachment")
	_check(view.sprite_pack_ready and view.projectile_pack_ready and not view.vfx_frames.is_empty(), "cached actor, projectile, and VFX frame packs remain presentation-ready")
	_check(view.normal_background != null and view.boss_background == null and view.battle_font != null, "cached normal battle background and font attach without a boss texture")
	view.queue_free()
	await get_tree().process_frame
	print("BATTLE_STAGE_ASSET_CACHE_SUMMARY pass=%d fail=%d" % [passed, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
