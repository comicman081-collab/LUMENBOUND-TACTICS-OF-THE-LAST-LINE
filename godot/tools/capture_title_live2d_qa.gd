extends Node

## Offscreen visual QA for the live-2D title (ui/title_live2d.gd).
## Run with: --position 10000,10000 --resolution 1920x1080 res://tools/capture_title_live2d_qa.tscn -- --out=<dir> [--size=WxH] [--set=stills|blink|motion|masks|trace|movie|all]
## The puppet runs in manual mode here: time advances only through step(), so every frame is
## reproducible for a given LUMEN_TITLE_SEED.
## --set=movie leaves the puppet running on its own for --seconds=N (default 14) and takes no stills; record it with
## Godot's movie maker (`--write-movie <file>.avi --fixed-fps 60`, 60 so the quality tiers see a fast frame) and trim the
## lead-in with the frame count printed as TITLE_SHOWN.

const BOOT_SCENE := preload("res://screens/boot/boot.tscn")

var shell = null
var live = null
var output_dir := ""
var viewport_size := Vector2i(1920, 1080)
var which := "all"
var movie_seconds := 14.0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text.begins_with("--out="): output_dir = text.substr(6)
		elif text.begins_with("--size="):
			var parts := text.substr(7).split("x")
			if parts.size() == 2: viewport_size = Vector2i(int(parts[0]), int(parts[1]))
		elif text.begins_with("--set="): which = text.substr(6)
		elif text.begins_with("--seconds="): movie_seconds = float(text.substr(10))
	if output_dir.is_empty(): output_dir = ProjectSettings.globalize_path("user://title_live2d_qa")
	DirAccess.make_dir_recursive_absolute(output_dir)
	get_tree().root.size = viewport_size
	AppState.new_game()
	shell = BOOT_SCENE.instantiate()
	get_tree().root.add_child(shell)
	await _frames(3)
	shell._finish_intro_video()
	await _wait(0.4)
	print("TITLE_SHOWN frames=%d" % Engine.get_frames_drawn())
	shell._show_screen("TITLE")
	await _wait(1.8 if which != "movie" else 0.1)
	live = shell.find_child("TitleLive2D", true, false)
	if live == null:
		# what the player gets without the puppet (LUMEN_TITLE_LIVE2D=0, missing assets): the static title art
		await _save("fallback_title.png")
		print("TITLE_LIVE2D_QA_FAIL no TitleLive2D node (assets, renderer or LUMEN_TITLE_LIVE2D=0)")
		get_tree().quit(1)
		return
	if which == "movie":
		await _wait(movie_seconds)
		print("TITLE_LIVE2D_QA_DONE movie seconds=%.1f size=%s quality=%.0f frames=%d" % [movie_seconds, str(viewport_size), live.quality, Engine.get_frames_drawn()])
		shell.queue_free()
		shell = null
		await _frames(3)
		get_tree().quit(0)
		return
	live.manual = true
	live.adapt_quality = false
	live.time = 0.0
	live.active_time = 0.0
	await _frames(2)
	if which == "all" or which == "stills":
		await _stills()
	if which == "all" or which == "blink":
		await _blink()
	if which == "all" or which == "motion":
		await _motion()
	if which == "all" or which == "masks":
		await _masks()
	if which == "trace":
		_trace()
	print("TITLE_LIVE2D_QA_DONE path=%s size=%s quality=%.0f" % [output_dir, str(viewport_size), live.quality])
	shell.queue_free()
	shell = null
	await _frames(3)
	get_tree().quit(0)

func _advance(seconds: float, dt := 1.0 / 60.0) -> void:
	var left := seconds
	while left > 0.0:
		var slice := minf(dt, left)
		live.step(slice)
		left -= slice

func _stills() -> void:
	# entrance choreography
	for entry in [[0.35, "entry_a"], [0.9, "entry_b"], [1.5, "entry_c"], [2.2, "entry_d"]]:
		live.time = 0.0
		live.active_time = 0.0
		live.debug_over = {"no_idle": true}
		var target: float = entry[0]
		_advance(target)
		await _save("stills_%s.png" % entry[1])
	live.debug_over = {}
	_advance(3.0)
	await _save("stills_settled_a.png")
	_advance(2.6)
	await _save("stills_settled_b.png")
	live.debug_over = {"no_idle": true}
	_advance(0.05)
	await _save("stills_neutral.png")
	live.debug_over = {}

func _blink() -> void:
	live.active_time = 6.0
	live.time = 40.0
	for value in [0.0, 0.35, 0.7, 1.0]:
		live.debug_over = {"no_idle": true, "blink": value}
		_advance(0.05)
		await _save("blink_%03d.png" % int(value * 100.0))
	for gaze in [[-2.6, 0.0, "L"], [2.6, 0.0, "R"], [0.0, -1.5, "U"], [0.0, 1.5, "D"]]:
		live.debug_over = {"no_idle": true, "gaze_x": gaze[0], "gaze_y": gaze[1]}
		_advance(0.05)
		await _save("gaze_%s.png" % gaze[2])
	live.debug_over = {}

func _motion() -> void:
	live.active_time = 6.0
	live.debug_over = {}
	# natural idle: one frame every 0.55 s for a few seconds
	for index in range(8):
		_advance(0.55)
		await _save("motion_%02d.png" % index)
	# forced pendulum swings and head yaw / roll, everything else neutral
	for entry in [["pendL", {"no_idle": true, "pendulum": -0.07}], ["pendR", {"no_idle": true, "pendulum": 0.07}], ["yawL", {"no_idle": true, "yaw": -6.0}], ["yawR", {"no_idle": true, "yaw": 6.0}], ["rollL", {"no_idle": true, "roll": -0.04}], ["rollR", {"no_idle": true, "roll": 0.04}], ["swayL", {"no_idle": true, "psi1": -0.012, "psi2": 0.006}], ["swayR", {"no_idle": true, "psi1": 0.012, "psi2": -0.006}], ["hairL", {"no_idle": true, "hair": Vector2(-22.0, 0.0)}], ["hairR", {"no_idle": true, "hair": Vector2(22.0, 5.0)}], ["hairD", {"no_idle": true, "hair": Vector2(0.0, 16.0)}]]:
		live.debug_over = entry[1]
		_advance(0.05)
		await _save("pose_%s.png" % entry[0])
	live.debug_over = {}

func _trace() -> void:
	# natural idle for 40 s, no rendering: ranges of the simulated signals (what the player would see over time)
	live.active_time = 6.0
	live.debug_over = {}
	var stats := {}
	for index in range(40 * 60):
		live.step(1.0 / 60.0)
		for p in live.puppets:
			var values := {"phi": 0.0 if p.pendulum.is_empty() else float(p.pendulum.phi)}
			for key in ["head_dx", "head_dy", "roll", "yaw", "pitch", "gaze_x", "gaze_y", "psi1", "psi2", "breath"]:
				values[key] = float(p.sig.get(key, 0.0))
			for key in values:
				var name: String = "%s.%s" % [p.id, key]
				var entry: Dictionary = stats.get(name, {"min": 1.0e9, "max": -1.0e9, "sq": 0.0, "n": 0})
				entry.min = minf(float(entry.min), float(values[key]))
				entry.max = maxf(float(entry.max), float(values[key]))
				entry.sq = float(entry.sq) + float(values[key]) * float(values[key])
				entry.n = int(entry.n) + 1
				stats[name] = entry
	var names: Array = stats.keys()
	names.sort()
	for name in names:
		var entry: Dictionary = stats[name]
		print("TRACE %-16s min %8.4f max %8.4f rms %8.4f" % [name, entry.min, entry.max, sqrt(float(entry.sq) / float(entry.n))])


func _masks() -> void:
	live.active_time = 6.0
	live.debug_over = {"no_idle": true}
	for mode in [1, 2, 3]:
		live.debug_masks = mode
		_advance(0.05)
		await _save("masks_%d.png" % mode)
	live.debug_masks = 0
	live.debug_over = {}

func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame

func _save(filename: String) -> void:
	await _frames(2)
	var image := get_tree().root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("CAPTURE_EMPTY " + filename)
		return
	image.save_png(output_dir.path_join(filename))
	print("CAPTURED " + filename)
