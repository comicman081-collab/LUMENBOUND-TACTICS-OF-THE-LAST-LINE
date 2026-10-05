extends Node

## Run without an import/export: Godot --headless --path godot res://tests/hud_layout_cache_runner.tscn
class LayoutProbe extends "res://screens/app_shell.gd":
	var sampled_size := Vector2(1920, 1080)
	var sample_count := 0
	var reflow_count := 0
	var reflow_compact := false

	func _refresh_runtime_layout_size_cache() -> void:
		sample_count += 1
		runtime_layout_size_cache = sampled_size
		runtime_layout_size_cache_valid = true

	func _queue_orientation_reflow_if_needed(portrait := _is_portrait_layout(), compact_landscape := _is_compact_landscape_layout()) -> void:
		reflow_count += 1
		reflow_compact = compact_landscape

class BossProbe extends BattleView:
	var shown_boss: Dictionary = {}

	func presentation_boss() -> Dictionary:
		return shown_boss

var checks := 0
var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(name)
	print("HUD_LAYOUT_CACHE ", "PASS " if ok else "FAIL ", name)

func _run() -> void:
	var shell := LayoutProbe.new()
	for _index in range(100):
		shell._runtime_layout_size()
	_check(shell.sample_count == 1, "repeated layout reads share one viewport sample")
	shell.sampled_size = Vector2(900, 506)
	shell._on_window_size_changed()
	_check(shell.sample_count == 2 and shell._runtime_layout_size() == shell.sampled_size and shell.reflow_compact,
		"resize invalidates immediately and reflow reads the refreshed compact metrics")
	shell.sampled_size = Vector2(1920, 1080)
	shell.orientation_probe_left = 0.0
	shell.compact_touch_probe_left = 1.0
	shell._process(0.01)
	_check(shell.sample_count == 3 and not shell.reflow_compact, "orientation fallback refreshes the viewport without a resize signal")
	for _index in range(10):
		shell._process(0.01)
		shell._runtime_layout_size()
	_check(shell.sample_count == 3, "ordinary frames do not requery viewport dimensions")

	var view := BossProbe.new()
	shell.battle_view = view
	shell.battle_hud = Label.new()
	var simulation := BattleSimulation.new()
	simulation.state.wave = 1
	simulation.state.wave_count = 3
	shell._update_battle_hud_text(simulation, 89.01, false)
	_check(shell.battle_hud.text.contains("89.0초"), "desktop HUD keeps the existing tenths display")
	shell.battle_hud_text_cache["reuse_probe"] = true
	shell._update_battle_hud_text(simulation, 89.02, false)
	_check(shell.battle_hud_text_cache.has("reuse_probe"), "unchanged displayed time reuses the HUD state")
	shell._update_battle_hud_text(simulation, 88.91, false)
	_check(shell.battle_hud.text.contains("88.9초") and not shell.battle_hud_text_cache.has("reuse_probe"),
		"crossing the displayed time bucket refreshes immediately")
	view.shown_boss = {"hp": 100, "max_hp": 200, "phase": "PHASE_1"}
	shell._update_battle_hud_text(simulation, 88.91, false)
	view.shown_boss.hp = 90
	shell._update_battle_hud_text(simulation, 88.91, false)
	_check(shell.battle_hud.text.contains("90/200"), "boss damage updates within the same time bucket")
	view.shown_boss.phase = "PHASE_2"
	shell._update_battle_hud_text(simulation, 88.91, false)
	_check(shell.battle_hud_text_cache.boss_phase == "PHASE_2", "boss phase updates within the same time bucket")
	simulation.state.wave = 2
	shell._update_battle_hud_text(simulation, 88.91, true)
	_check(shell.battle_hud.text == "웨이브 2/3  ·  89초", "compact HUD keeps integer seconds and its wave counter")
	var previous_hud := shell.battle_hud
	shell.battle_hud = Label.new()
	shell._update_battle_hud_text(simulation, 88.91, true)
	_check(shell.battle_hud.text == previous_hud.text, "a rebuilt HUD refreshes even when display state is unchanged")
	previous_hud.free()
	shell.battle_hud.free()
	shell.battle_hud = null
	shell.battle_view = null
	view.free()
	shell.free()
	print("HUD_LAYOUT_CACHE_RESULT ", checks - failures, "/", checks)
	get_tree().quit(0 if failures == 0 else 1)
