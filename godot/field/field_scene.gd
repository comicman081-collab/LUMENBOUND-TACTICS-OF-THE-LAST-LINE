extends RefCounted

## Runs one field direction script (2026-09-30, phase 3). Time driven: the host
## (or a test) calls `advance(delta)`; nothing here reads a clock or the screen.
## The scene owns bubbles, emotes, the banner and actor poses; the `FieldStage`
## owns the actors and the camera and receives poses and camera requests.

signal finished(skipped: bool)

const FieldScriptScript := preload("res://field/field_script.gd")
const TYPE_CHARS_PER_SEC := 42.0
const EMOTE_LIFE := 1.15
const BANNER_LIFE := 1.6
const SAY_CLOSE := 0.18
const SHAKE_DECAY := 5.0
const LETTERBOX_SPEED := 3.2
const DEFAULT_JUMP_TIME := 0.42
const DEFAULT_MOVE_TIME := 0.45
const DEFAULT_CAMERA_TIME := 0.5
const FRONT_STEP := 0.6

var stage: RefCounted
var steps: Array = []
var cursor := 0
var active: Array = []
var done := false
var skipped := false
var elapsed := 0.0
var bubbles: Array = []
var emotes: Array = []
var banner: Dictionary = {}
var poses: Dictionary = {}
var camera := {"focus": "", "zoom": 1.0, "shake": 0.0}
var letterbox := 0.0
var letterbox_enabled := true
var language := ""


func start(script_steps: Array, host_stage: RefCounted, options := {}) -> bool:
	stage = host_stage
	steps = script_steps.duplicate(true)
	letterbox_enabled = bool(options.get("letterbox", true))
	language = str(options.get("language", ""))
	cursor = 0
	active.clear()
	bubbles.clear()
	emotes.clear()
	banner = {}
	poses.clear()
	camera = {"focus": "", "zoom": 1.0, "shake": 0.0}
	letterbox = 0.0
	elapsed = 0.0
	done = false
	skipped = false
	if not FieldScriptScript.validate(steps).is_empty():
		_finish(false)
		return false
	_pull_groups()
	_apply_to_stage()
	return true


func is_running() -> bool:
	return not done


## True while a line is fully typed and the scene is waiting for the player.
func waiting_for_tap() -> bool:
	for state in active:
		if state.cmd in ["say", "banner"] and bool(state.get("waiting", false)):
			return true
	return false


func advance(delta: float) -> void:
	if done:
		return
	elapsed += delta
	var target_box := 1.0 if letterbox_enabled else 0.0
	letterbox = move_toward(letterbox, target_box, delta * LETTERBOX_SPEED)
	_age_visuals(delta)
	_step_active(delta)
	# Groups made of instant commands (face, emote, sfx) and finished timed groups
	# hand over within the same frame so a script never idles between commands.
	var guard := steps.size() + 2
	while active.is_empty() and cursor < steps.size() and guard > 0:
		_pull_groups()
		_step_active(0.0)
		guard -= 1
	if active.is_empty() and cursor >= steps.size():
		_finish(false)
		return
	_apply_to_stage()


## One tap: finish typing the line, or dismiss a fully typed one.
func tap() -> void:
	if done:
		return
	for state in active:
		if state.cmd == "say":
			var bubble: Dictionary = state.bubble
			if int(bubble.typed) < String(bubble.text).length():
				bubble.typed = String(bubble.text).length()
				return
			if bool(state.get("waiting", false)):
				state.waiting = false
				state.finished = true
				return
		elif state.cmd == "banner" and bool(state.get("waiting", false)):
			state.waiting = false
			state.finished = true
			return


func skip() -> void:
	if done:
		return
	# Apply the lasting results of what is left (positions, facing), then end.
	for state in active.duplicate():
		_settle(state)
	for index in range(cursor, steps.size()):
		var state := _make_state(steps[index])
		_settle(state)
	cursor = steps.size()
	active.clear()
	_finish(true)


func snapshot() -> Dictionary:
	var typed_lines: Array = []
	for bubble in bubbles:
		typed_lines.append({"actor": bubble.actor, "side": bubble.side, "name": bubble.name, "text": bubble.text, "typed": bubble.typed, "closing": bubble.closing})
	return {
		"cursor": cursor, "steps": steps.size(), "active": active.size(), "done": done, "skipped": skipped,
		"bubbles": typed_lines, "emotes": emotes.size(), "banner": str(banner.get("text", "")),
		"waiting": waiting_for_tap(), "camera": camera.duplicate(), "poses": poses.duplicate(true), "letterbox": letterbox,
	}


# -- timeline ---------------------------------------------------------------

func _pull_groups() -> void:
	if cursor >= steps.size():
		return
	_begin(steps[cursor])
	cursor += 1
	while cursor < steps.size() and bool((steps[cursor] as Dictionary).get("with", false)):
		_begin(steps[cursor])
		cursor += 1


func _make_state(step: Dictionary) -> Dictionary:
	return {"cmd": str(step.get("cmd", "")), "step": step, "t": 0.0, "dur": 0.0, "finished": false, "waiting": false}


func _key(actor: String) -> String:
	return "" if stage == null else str(stage.resolve(actor))


func _begin(step: Dictionary) -> void:
	var state := _make_state(step)
	var key := _key(str(step.get("actor", "")))
	match state.cmd:
		"say":
			var text := FieldScriptScript.line_of(step, language)
			var side := str(step.get("side", ""))
			if side.is_empty():
				side = "ally" if key.is_empty() or stage.actor_side(key) != "foe" else "foe"
			var speaker := FieldScriptScript.speaker_of(step, language)
			if speaker.is_empty() and not key.is_empty():
				speaker = str(stage.actor_name(key))
			state.bubble = {"actor": key, "role": str(step.get("actor", "")), "side": side, "name": speaker, "text": text, "typed": 0, "age": 0.0, "closing": false, "close_age": 0.0, "portrait": str(step.get("portrait", ""))}
			state.hold = float(step.get("hold", -1.0))
			state.auto_hold = FieldScriptScript.reading_seconds(text)
			state.type_done = false
			bubbles.append(state.bubble)
			if stage != null:
				stage.line_started(str(step.get("text_key", "")))
		"wait":
			state.dur = maxf(0.0, float(step.get("sec", 0.0)))
		"move":
			if key.is_empty():
				state.finished = true
			else:
				var pose := _pose(key)
				state.from = pose.offset
				state.to = _move_target(step, key, pose)
				state.dur = maxf(0.05, float(step.get("time", DEFAULT_MOVE_TIME)))
		"face":
			if not key.is_empty():
				_pose(key).flip = _face_direction(step, key)
			state.finished = true
		"jump":
			if key.is_empty():
				state.finished = true
			else:
				state.dur = maxf(0.1, float(step.get("time", DEFAULT_JUMP_TIME)))
				state.height = clampf(float(step.get("height", 0.6)), 0.1, 1.5)
		"emote":
			if not key.is_empty():
				emotes.append({"actor": key, "kind": str(step.get("kind", "alert")), "age": 0.0, "life": float(step.get("time", EMOTE_LIFE))})
			state.finished = not bool(step.get("wait", false))
			state.dur = float(step.get("time", EMOTE_LIFE))
		"camera":
			state.dur = maxf(0.0, float(step.get("time", DEFAULT_CAMERA_TIME)))
			state.from_zoom = float(camera.zoom)
			state.to_zoom = clampf(float(step.get("zoom", camera.zoom)), 1.0, 2.0)
			if step.has("focus"):
				camera.focus = _key(str(step.focus)) if str(step.focus) != "center" else ""
			if step.has("shake"):
				camera.shake = maxf(float(camera.shake), float(step.shake))
		"banner":
			var text := FieldScriptScript.line_of(step, language)
			banner = {"text": text, "style": str(step.get("style", "info")), "age": 0.0, "life": float(step.get("time", BANNER_LIFE))}
			state.dur = float(banner.life)
			state.tap = bool(step.get("tap", false))
		"sfx":
			if stage != null:
				stage.play_sfx(str(step.get("id", "")))
			state.finished = true
	active.append(state)


func _pose(key: String) -> Dictionary:
	if not poses.has(key):
		poses[key] = {"offset": Vector2.ZERO, "hop": 0.0, "flip": 0}
	return poses[key]


func _move_target(step: Dictionary, key: String, pose: Dictionary) -> Vector2:
	var to := str(step.get("to", ""))
	if to == "home":
		return Vector2.ZERO
	if to == "front" or to == "back":
		var opponent := str(stage.opponent_of(key))
		var direction := float(stage.direction_between(key, opponent)) if not opponent.is_empty() else 1.0
		if direction == 0.0:
			direction = 1.0
		if to == "back":
			direction = -direction
		return Vector2(direction * float(step.get("dx", FRONT_STEP)), float(step.get("dy", 0.0)))
	return (pose.offset as Vector2) + Vector2(float(step.get("dx", 0.0)), float(step.get("dy", 0.0)))


func _face_direction(step: Dictionary, key: String) -> int:
	var toward := str(step.get("toward", ""))
	if toward == "left":
		return -1
	if toward == "right":
		return 1
	if toward == "opponent":
		toward = str(stage.opponent_of(key))
	var other := _key(toward)
	if other.is_empty():
		return 0
	return int(stage.direction_between(key, other))


func _step_active(delta: float) -> void:
	for state in active.duplicate():
		state.t = float(state.t) + delta
		match state.cmd if not bool(state.finished) else "":
			"say":
				_step_say(state, delta)
			"wait":
				state.finished = state.t >= state.dur
			"move":
				var progress := clampf(float(state.t) / float(state.dur), 0.0, 1.0)
				_pose(_key(str(state.step.get("actor", "")))).offset = (state.from as Vector2).lerp(state.to as Vector2, smoothstep(0.0, 1.0, progress))
				state.finished = progress >= 1.0
			"jump":
				var progress := clampf(float(state.t) / float(state.dur), 0.0, 1.0)
				_pose(_key(str(state.step.get("actor", "")))).hop = 4.0 * float(state.height) * progress * (1.0 - progress)
				state.finished = progress >= 1.0
			"emote":
				if not bool(state.finished):
					state.finished = state.t >= state.dur
			"camera":
				var progress := 1.0 if float(state.dur) <= 0.0 else clampf(float(state.t) / float(state.dur), 0.0, 1.0)
				camera.zoom = lerpf(float(state.from_zoom), float(state.to_zoom), smoothstep(0.0, 1.0, progress))
				state.finished = progress >= 1.0
			"banner":
				if bool(state.get("tap", false)):
					state.waiting = state.t >= minf(float(state.dur), 0.6)
				else:
					state.finished = state.t >= state.dur
			"face", "sfx":
				state.finished = true
		if bool(state.finished):
			if state.cmd == "jump" and not _key(str(state.step.get("actor", ""))).is_empty():
				_pose(_key(str(state.step.get("actor", "")))).hop = 0.0
			if state.cmd == "say":
				(state.bubble as Dictionary).closing = true
			active.erase(state)


func _step_say(state: Dictionary, delta: float) -> void:
	var bubble: Dictionary = state.bubble
	var text := String(bubble.text)
	bubble.age = float(bubble.age) + delta
	if int(bubble.typed) < text.length():
		bubble.typed = mini(text.length(), int(float(state.t) * TYPE_CHARS_PER_SEC))
		return
	if not bool(state.type_done):
		state.type_done = true
		state.done_at = float(state.t)
	var hold: float = float(state.hold)
	if hold >= 0.0:
		state.finished = float(state.t) - float(state.done_at) >= hold
	else:
		state.waiting = true


func _age_visuals(delta: float) -> void:
	for emote in emotes.duplicate():
		emote.age = float(emote.age) + delta
		if float(emote.age) >= float(emote.life):
			emotes.erase(emote)
	if not banner.is_empty():
		banner.age = float(banner.age) + delta
		var holding := false
		for state in active:
			if state.cmd == "banner" and bool(state.get("tap", false)):
				holding = true
		if float(banner.age) >= float(banner.life) + 0.3 and not holding:
			banner = {}
	for bubble in bubbles.duplicate():
		if bool(bubble.closing):
			bubble.close_age = float(bubble.close_age) + delta
			if float(bubble.close_age) >= SAY_CLOSE:
				bubbles.erase(bubble)
	camera.shake = maxf(0.0, float(camera.shake) * exp(-SHAKE_DECAY * delta) - 0.05)


func _apply_to_stage() -> void:
	if stage == null:
		return
	for key in poses.keys():
		var pose: Dictionary = poses[key]
		stage.apply_actor_pose(str(key), pose.offset, float(pose.hop), int(pose.flip))
	stage.apply_camera(str(camera.focus), float(camera.zoom), float(camera.shake))


## The lasting result of a command that has not run: used by `skip()`.
func _settle(state: Dictionary) -> void:
	var step: Dictionary = state.step
	var key := _key(str(step.get("actor", "")))
	match state.cmd:
		"move":
			if not key.is_empty():
				var pose := _pose(key)
				pose.offset = _move_target(step, key, pose)
		"face":
			if not key.is_empty():
				_pose(key).flip = _face_direction(step, key)


func _finish(was_skipped: bool) -> void:
	if done:
		return
	# The host sees the last pose before it is released, even when the final step
	# ended in the same frame.
	_apply_to_stage()
	done = true
	skipped = was_skipped
	active.clear()
	bubbles.clear()
	emotes.clear()
	banner = {}
	camera = {"focus": "", "zoom": 1.0, "shake": 0.0}
	if stage != null:
		stage.scene_finished()
	finished.emit(was_skipped)
