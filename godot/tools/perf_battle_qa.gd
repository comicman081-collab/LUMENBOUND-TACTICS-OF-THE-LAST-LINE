extends Node

## Frame-time A/B of the real battle view (needs a rendering window, not --headless).
##   godot --path godot --resolution 1280x720 --disable-vsync res://tools/perf_battle_qa.tscn -- <stage_id> [seconds] [variants]
## variants (comma separated, each run in turn on the same open battle):
##   base    - the battle exactly as shipped, waiting on the deployment panel
##   nowave  - without the next-wave silhouette preview
##   nofloor - without the regional floor dressing
##   fight   - the battle running (invincible allies), sampled after one second
## Prints one PERF line per variant: average and 95th percentile frame time in
## milliseconds. If the view carries a draw_prof dictionary (a local profiling
## patch), the per-section average per frame is printed too.

var shell: Control

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var stage_id := str(args[0]) if args.size() > 0 else "CH01-N05"
	var seconds := float(args[1]) if args.size() > 1 else 6.0
	var variants := str(args[2]).split(",") if args.size() > 2 else PackedStringArray(["base", "nowave", "nofloor"])
	_run.call_deferred(stage_id, seconds, variants)

func _run(stage_id: String, seconds: float, variants: PackedStringArray) -> void:
	shell = load("res://screens/boot/boot.tscn").instantiate()
	get_tree().root.add_child(shell)
	await _frames(2)
	shell.call("_finish_intro_video")
	await _frames(2)
	SettingsService.values["battle_cutin_mode"] = "OFF"
	AppState.selected_stage_id = stage_id
	shell.call("_show_screen", "BATTLE")
	var view: BattleView = null
	for frame in 900:
		await get_tree().process_frame
		view = shell.get("battle_view") as BattleView
		if view != null and view.assets_ready and view.get_node_or_null("BattleOverlay") != null:
			break
	if view == null:
		print("PERF_FAIL no battle view")
		get_tree().quit(1)
		return
	await _frames(90)
	for variant in variants:
		var restore := _apply(view, variant)
		await _frames(30)
		await _sample(view, variant, seconds)
		restore.call()
	get_tree().quit(0)

func _apply(view: BattleView, variant: String) -> Callable:
	if variant.begins_with("cut:"):
		view.set("prof_cut", variant.substr(4))
		return func(): view.set("prof_cut", "")
	match variant:
		"nowave":
			view.next_wave_cache = {"index": view.simulation.wave_director.current_index + 1, "layout": []}
			return func(): view.next_wave_cache = {}
		"nofloor":
			view.region_dressing_enabled = false
			return func(): view.region_dressing_enabled = true
		"fight":
			shell.call("_start_deployed_battle")
			view.simulation.options["invincible"] = true
			return func(): pass
	return func(): pass

func _sample(view: BattleView, variant: String, seconds: float) -> void:
	var prof = view.get("draw_prof")
	if prof is Dictionary: prof.clear()
	var calls_before := int(view.get("prof_sprite_calls")) if view.get("prof_sprite_calls") != null else 0
	var frames_before := int(view.get("prof_frames")) if view.get("prof_frames") != null else 0
	var times: Array[float] = []
	var draw_call_sum := 0.0
	var last := Time.get_ticks_usec()
	var end := last + int(seconds * 1000000.0)
	while last < end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		draw_call_sum += float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		last = now
	times.sort()
	var total := 0.0
	for value in times: total += value
	var line := "PERF %-8s frames=%d avg=%.2fms p95=%.2fms max=%.2fms draw_calls=%.0f" % [variant, times.size(), total / maxf(1.0, float(times.size())), times[int(float(times.size()) * .95)], times[times.size() - 1], draw_call_sum / maxf(1.0, float(times.size()))]
	if prof is Dictionary and not prof.is_empty():
		var drawn := maxi(1, int(view.get("prof_frames")) - frames_before)
		var parts: Array[String] = []
		for key in prof:
			parts.append("%s=%.2f" % [key, float(prof[key]) / 1000.0 / float(drawn)])
		line += "\n     draw ms/frame: " + " ".join(parts)
		line += "\n     sprite calls/frame: %.1f" % (float(int(view.get("prof_sprite_calls")) - calls_before) / float(drawn))
	print(line)
