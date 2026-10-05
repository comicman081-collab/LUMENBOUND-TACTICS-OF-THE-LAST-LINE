extends Node

## Local paired-build instrumentation only. Never register in project.godot.
## JS: window.__fpsEngine.command('start', label), then command('stop').
## Results contain [elapsed_msec, frame_msec, previous_frame_tag] per frame.
const MAX_FRAMES := 100000
const SHELL_RETRY_SECONDS := 0.25

var recording := false
var label := ""
var frames: Array = []
var limit_reached := false
var _allowed := false
var _callback: JavaScriptObject
var _shell: Node
var _shell_retry_left := 0.0
var _started_usec := 0
var _last_usec := 0
var _previous_tag := "NO_SHELL"

func _ready() -> void:
	set_process(false)
	if not OS.has_feature("web"):
		return
	var save_service := get_tree().root.get_node_or_null("SaveService")
	if save_service == null or not save_service.has_method("is_soak_sandbox_enabled"):
		return
	if not bool(save_service.call("is_soak_sandbox_enabled")):
		return
	_allowed = str(JavaScriptBridge.eval("(['localhost','127.0.0.1','[::1]'].includes(location.hostname) && new URLSearchParams(location.search).get('gameplay-qa') === '1') ? '1' : '0'", true)) == "1"
	if not _allowed:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Sample after the gameplay/UI nodes; the next interval belongs to this tag.
	process_priority = 10000
	_callback = JavaScriptBridge.create_callback(_on_command)
	JavaScriptBridge.eval("window.__fpsEngine = {ready:true, result:null, command:null}", true)
	var browser_window = JavaScriptBridge.get_interface("window")
	browser_window.__fpsEngine.command = _callback

func _on_command(arguments: Array) -> void:
	if not _allowed or arguments.is_empty():
		return
	match str(arguments[0]):
		"start":
			recording = false
			frames = []
			limit_reached = false
			label = str(arguments[1]) if arguments.size() > 1 else "unnamed"
			_shell_retry_left = 0.0
			_refresh_shell_if_needed(0.0)
			_previous_tag = _frame_tag()
			_started_usec = Time.get_ticks_usec()
			_last_usec = _started_usec
			JavaScriptBridge.eval("window.__fpsEngine.result = null", true)
			recording = true
			set_process(true)
		"stop":
			# Serialization and the browser bridge happen after the scored interval.
			recording = false
			set_process(false)
			var result := {"label": label, "frames": frames, "count": frames.size(),
				"limit_reached": limit_reached, "max_frames": MAX_FRAMES,
				"columns": ["elapsed_msec", "frame_msec", "previous_frame_tag"]}
			JavaScriptBridge.eval("window.__fpsEngine.result = " + JSON.stringify(result), true)

func _process(delta: float) -> void:
	if not recording:
		return
	if frames.size() >= MAX_FRAMES:
		limit_reached = true
		recording = false
		set_process(false)
		return # stop still publishes the bounded sample; no frame-path JS call.
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		frames.append([float(now - _started_usec) / 1000.0,
			float(now - _last_usec) / 1000.0, _previous_tag])
	_last_usec = now
	_refresh_shell_if_needed(delta)
	_previous_tag = _frame_tag()

func _refresh_shell_if_needed(delta: float) -> void:
	if is_instance_valid(_shell):
		return
	_shell_retry_left -= delta
	if _shell_retry_left > 0.0:
		return
	_shell_retry_left = SHELL_RETRY_SECONDS
	_shell = _find_shell(get_tree().root)

func _find_shell(node: Node) -> Node:
	if node.has_method("_show_battle") and node.has_method("_runtime_layout_size"):
		return node
	for child in node.get_children():
		if child is SubViewport:
			continue
		var found := _find_shell(child)
		if found != null:
			return found
	return null

func _frame_tag() -> String:
	if not is_instance_valid(_shell):
		return "NO_SHELL"
	var screen := str(_shell.get("current_screen"))
	var tag := screen
	if int(_shell.get("transition_loading_active_token")) > 0:
		tag += "|LOADING(" + str(_shell.get("transition_loading_kind")) + ")"
	if screen == "BATTLE":
		var view = _shell.get("battle_view")
		if not is_instance_valid(view):
			return tag + "|NO_VIEW"
		tag += "|READY" if bool(view.get("assets_ready")) else "|NOT_READY"
		var simulation = view.get("simulation")
		if is_instance_valid(simulation):
			var state = simulation.get("state")
			if is_instance_valid(state):
				tag += "|WAVE:" + str(state.get("wave"))
		if float(view.get("boss_entry_elapsed")) >= 0.0:
			tag += "|BOSS_ENTRY"
		elif float(view.get("wave_entry_elapsed")) >= 0.0:
			tag += "|WAVE_TRANSITION"
		if float(view.get("boss_victory_elapsed")) >= 0.0:
			tag += "|BOSS_VICTORY"
		if str(view.get("field_aftermath_state")) == "playing":
			tag += "|AFTERMATH_DIALOGUE"
		var cutin = view.get("active_cutin")
		if cutin is Dictionary and not cutin.is_empty():
			tag += "|CUTIN"
		if bool(view.get("paused")):
			tag += "|PAUSED"
		if bool(view.get("deployment_active")):
			tag += "|DEPLOYMENT"
	elif screen in ["STAGE_SELECT", "STAGE_DETAIL"]:
		var map_screen = _shell.get("active_chapter_map_screen")
		if not is_instance_valid(map_screen):
			return tag + "|NO_MAP"
		if not bool(map_screen.get("map_ready_complete")):
			tag += "|NOT_READY"
		if bool(map_screen.get("moving")):
			tag += "|MOVING"
		elif bool(map_screen.get("turn_transitioning")):
			tag += "|ENEMY_TURN"
		else:
			tag += "|IDLE"
		if bool(map_screen.get("map_simulation_paused")):
			tag += "|PAUSED"
	return tag
