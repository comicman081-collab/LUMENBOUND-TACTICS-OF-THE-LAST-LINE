extends Node

## Loading under a throttled browser (2026-09-30). First map entry failed twice in
## a hidden tab: the 12 s "no progress" watchdog counted wall time although the
## tab drew almost nothing, and the fixed 10 ms build slice needed hundreds of
## frames. Loading deadlines now count delivered frames (at most 250 ms each) and
## the work slice follows the measured frame interval.

const LoadingClockScript := preload("res://core/loading_clock.gd")
const AppShellScript := preload("res://screens/app_shell.gd")

var checks := 0
var failures := 0

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("%s %s" % [label, detail])

func _ready() -> void:
	_steps()
	_budget()
	_clock()
	_hidden_tab()
	_asset_cache()
	_sources()
	print("LOADING_PACING_TESTS total=%d pass=%d fail=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _steps() -> void:
	check(LoadingClockScript.capped_step(16) == 16, "an ordinary frame counts in full")
	check(LoadingClockScript.capped_step(30000) == LoadingClockScript.MAX_STEP_MSEC, "a 30 s gap counts as one capped step")
	check(LoadingClockScript.capped_step(-5) == 0, "a backwards clock never subtracts loading time")

func _budget() -> void:
	var base: int = LoadingClockScript.BASE_SLICE_USEC
	check(LoadingClockScript.slice_budget_usec(0) == base, "no measurement keeps the base slice")
	check(LoadingClockScript.slice_budget_usec(16700) == base, "60 fps keeps the base slice")
	check(LoadingClockScript.slice_budget_usec(33000) == base, "30 fps keeps the base slice")
	check(LoadingClockScript.slice_budget_usec(66000) == 33000, "15 fps spends at most half of each frame")
	check(LoadingClockScript.slice_budget_usec(250000) == 125000, "four frames a second allows 125 ms of work")
	check(LoadingClockScript.slice_budget_usec(5000000) == LoadingClockScript.MAX_SLICE_USEC, "the slice is capped at 250 ms")
	# The point of the change: the same 3 s of build work needs far fewer frames.
	var work_usec := 3000000
	var frames_old := ceili(float(work_usec) / 10000.0)
	var frames_base := ceili(float(work_usec) / float(base))
	var frames_adaptive := ceili(float(work_usec) / float(LoadingClockScript.slice_budget_usec(250000)))
	check(frames_old >= 300 and frames_base <= 150 and frames_adaptive <= 30, "the base slice halves the frames and a 4 fps tab needs about 24 instead of 300", "%d / %d / %d" % [frames_old, frames_base, frames_adaptive])

func _clock() -> void:
	var clock = LoadingClockScript.new()
	check(clock.elapsed_msec == 0 and clock.last_progress_msec == 0, "a new clock starts at zero")
	clock.elapsed_msec = 11900
	check(not clock.expired(AppShellScript.LOADING_HARD_TIMEOUT_MSEC, AppShellScript.LOADING_IDLE_TIMEOUT_MSEC), "just under the idle bound is still loading")
	clock.elapsed_msec = 12000
	check(clock.expired(AppShellScript.LOADING_HARD_TIMEOUT_MSEC, AppShellScript.LOADING_IDLE_TIMEOUT_MSEC), "the idle bound still ends a load that stopped")
	clock.mark_progress()
	check(not clock.expired(AppShellScript.LOADING_HARD_TIMEOUT_MSEC, AppShellScript.LOADING_IDLE_TIMEOUT_MSEC), "progress restarts the idle count")
	clock.elapsed_msec = 45000
	clock.last_progress_msec = 44999
	check(clock.expired(AppShellScript.LOADING_HARD_TIMEOUT_MSEC, AppShellScript.LOADING_IDLE_TIMEOUT_MSEC), "steady progress cannot pass the hard bound")

func _hidden_tab() -> void:
	var clock = LoadingClockScript.new()
	# The tab was hidden for 40 s and drew nothing; the next frame arrives now.
	clock._last_wall_msec = Time.get_ticks_msec() - 40000
	var elapsed: int = clock.tick()
	check(elapsed <= LoadingClockScript.MAX_STEP_MSEC + 50, "40 s without a frame adds one capped step", str(elapsed))
	check(not clock.expired(AppShellScript.LOADING_HARD_TIMEOUT_MSEC, AppShellScript.LOADING_IDLE_TIMEOUT_MSEC), "a hidden tab is not reported as a failed load")
	# Real progress at a low frame rate: 30 frames, none longer than the cap, still no failure.
	var throttled = LoadingClockScript.new()
	for _frame in range(30):
		throttled._last_wall_msec = Time.get_ticks_msec() - 900
		throttled.tick()
	check(throttled.elapsed_msec == 30 * LoadingClockScript.MAX_STEP_MSEC or throttled.elapsed_msec <= 30 * (LoadingClockScript.MAX_STEP_MSEC + 5), "30 slow frames count 250 ms each")
	check(not throttled.expired(AppShellScript.LOADING_HARD_TIMEOUT_MSEC, AppShellScript.LOADING_IDLE_TIMEOUT_MSEC + 30000), "the same 30 slow frames stay inside a 42 s idle bound")

func _asset_cache() -> void:
	StageAssetCache._begin_warm_clock()
	StageAssetCache._warm_clock._last_wall_msec = Time.get_ticks_msec() - 60000
	check(not StageAssetCache._warmup_deadline_exceeded(1), "a 60 s gap does not expire the asset warm-up")
	check(not StageAssetCache._warmup_deadline_exceeded(0), "a warm-up that is not running never expires")
	StageAssetCache._warm_clock.elapsed_msec = StageAssetCache.WARMUP_IDLE_TIMEOUT_MSEC
	check(StageAssetCache._warmup_deadline_exceeded(1), "a warm-up with no progress still expires")
	StageAssetCache._warm_clock.mark_progress()
	check(not StageAssetCache._warmup_deadline_exceeded(1), "asset progress restarts its idle count")
	check(StageAssetCache._warm_slice_usec() == LoadingClockScript.BASE_SLICE_USEC - 1000, "the asset warm-up keeps the base slice at normal frame rates")
	StageAssetCache._warm_frame_interval_usec = 400000
	check(StageAssetCache._warm_slice_usec() == 199000, "the asset warm-up widens its slice on slow frames", str(StageAssetCache._warm_slice_usec()))
	StageAssetCache._begin_warm_clock()

func _sources() -> void:
	var map_source := FileAccess.get_file_as_string("res://chapter_map/runtime/chapter_map_screen.gd")
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd")
	var probe_source := FileAccess.get_file_as_string("res://autoload/web_soak_probe.gd")
	check(map_source.contains("LoadingClockScript.slice_budget_usec(web_entry_frame_interval_usec)") and not map_source.contains("WEB_ENTRY_SLICE_BUDGET_USEC"), "the map build sizes its slice from the frame interval")
	check(map_source.contains("web_entry_frame_interval_usec = 0"), "the interval is reset when the build ends")
	check(shell_source.contains("map_load_clock.tick()") and shell_source.contains("clock.tick()") and not shell_source.contains("map_load_last_progress_msec"), "map and battle watchdogs run on the loading clock")
	check(probe_source.contains("MapAtmosphereShader") and probe_source.contains("atmosphere_rect"), "the boot warm-up links the map atmosphere shader")

	var slice_fn: String = map_source.substr(map_source.find("func _finish_web_build_slice"), 2600)
	check(map_source.contains("web_entry_progress_phase = phase"), "the map remembers its last reported milestone")
	check(slice_fn.contains("_emit_map_load_progress(web_entry_progress_value, web_entry_progress_phase)"), "a delivered frame after a build slice counts as progress")
	check(slice_fn.find("_emit_map_load_progress(web_entry_progress_value") > slice_fn.find("await get_tree().process_frame"), "the heartbeat follows the frame, not the slice start")
	check(slice_fn.contains("web_stage_entry_preload_active or not map_ready_complete"), "world construction before the detail build is paced and reports progress too")

	var wait_map: String = shell_source.substr(shell_source.find("func _wait_for_map_ready_with_deadline"), 900)
	check(wait_map.contains("loading_watchdog_expired(map_load_clock.tick()"), "the map wait asks the shared watchdog with loading-clock time")
