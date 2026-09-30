extends Node

## Field direction system (phase 3, 2026-09-30): the command script format, the
## timeline runtime, the authored library, the converters that turn the existing
## boss and event dialogue into scenes, the overlay layout on desktop and phone
## sizes, and both host adapters. Everything here is presentation only.

const FieldScriptScript := preload("res://field/field_script.gd")
const FieldSceneScript := preload("res://field/field_scene.gd")
const FieldSceneOverlayScript := preload("res://field/field_scene_overlay.gd")
const MapFieldStageScript := preload("res://field/map_field_stage.gd")

var checks := 0
var failures := 0


class FakeStage extends "res://field/field_stage.gd":
	var events: Array = []
	var poses := {}
	var camera := {"focus": "", "zoom": 1.0, "shake": 0.0}
	var anchors := {"leader": Vector2(400, 600), "foe": Vector2(900, 600)}
	var finished_calls := 0
	func resolve(actor: String) -> String:
		return {"leader": "leader", "ally": "leader", "foe": "foe", "boss": "foe", "event": "foe"}.get(actor, "")
	func actor_anchor(actor: String) -> Vector2:
		return anchors.get(actor, Vector2.INF)
	func actor_name(actor: String) -> String:
		return {"leader": "Lead", "foe": "Foe"}.get(actor, "")
	func actor_side(actor: String) -> String:
		return "foe" if actor == "foe" else "ally"
	func opponent_of(actor: String) -> String:
		return "foe" if actor == "leader" else "leader"
	func direction_between(actor: String, other: String) -> int:
		return 1 if anchors.get(actor, Vector2.ZERO).x < anchors.get(other, Vector2.ZERO).x else -1
	func apply_actor_pose(actor: String, offset: Vector2, hop: float, flip: int) -> void:
		poses[actor] = {"offset": offset, "hop": hop, "flip": flip}
	func apply_camera(focus: String, zoom: float, shake: float) -> void:
		camera = {"focus": focus, "zoom": zoom, "shake": shake}
	func play_sfx(sfx_id: String) -> void:
		events.append("sfx:" + sfx_id)
	func line_started(text_key: String) -> void:
		events.append("line:" + text_key)
	func scene_finished() -> void:
		finished_calls += 1


func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("%s %s" % [label, detail])


func _ready() -> void:
	AppState.new_game()
	_validation()
	_library()
	_runtime()
	_more_runtime()
	_converters()
	await _overlay_layout()
	_map_stage()
	await _battle_aftermath()
	_sources()
	print("FIELD_DIRECTION_TESTS total=%d pass=%d fail=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _run(steps: Array, stage: RefCounted = null, options := {}) -> Array:
	var host: RefCounted = stage if stage != null else FakeStage.new()
	var scene := FieldSceneScript.new()
	var started: bool = scene.start(steps, host, options)
	return [scene, host, started]


func _drain(scene: RefCounted, seconds: float, step := 0.05, tap_when_waiting := false) -> void:
	var elapsed := 0.0
	while elapsed < seconds and scene.is_running():
		scene.advance(step)
		if tap_when_waiting and scene.waiting_for_tap():
			scene.tap()
		elapsed += step


# -- format ----------------------------------------------------------------------

func _validation() -> void:
	check(not FieldScriptScript.validate([]).is_empty(), "an empty scene is rejected")
	check(not FieldScriptScript.validate([{"cmd": "dance", "actor": "leader"}]).is_empty(), "an unknown command is rejected")
	check(not FieldScriptScript.validate([{"cmd": "say", "text": "x"}]).is_empty(), "say needs an actor")
	check(not FieldScriptScript.validate([{"cmd": "say", "actor": "leader"}]).is_empty(), "say needs text")
	check(not FieldScriptScript.validate([{"cmd": "wait", "sec": 0.1, "with": true}]).is_empty(), "the first step cannot run with a previous step")
	check(not FieldScriptScript.validate([{"cmd": "emote", "actor": "leader", "kind": "love"}]).is_empty(), "an unknown emote is rejected")
	check(not FieldScriptScript.validate([{"cmd": "move", "actor": "leader"}]).is_empty(), "move needs a target")
	check(not FieldScriptScript.validate([{"cmd": "wait", "sec": -1.0}]).is_empty(), "a negative time is rejected")
	var long_scene: Array = []
	for _index in range(FieldScriptScript.MAX_STEPS + 1):
		long_scene.append({"cmd": "wait", "sec": 0.0})
	check(not FieldScriptScript.validate(long_scene).is_empty(), "a scene over the step cap is rejected")
	check(FieldScriptScript.validate([{"cmd": "say", "actor": "leader", "text": "ok"}, {"cmd": "emote", "actor": "leader", "kind": "alert", "with": true}]).is_empty(), "a plain scene is playable")
	var invalid: Array = _run([{"cmd": "dance", "actor": "x"}])
	check(not bool(invalid[2]) and (invalid[0] as RefCounted).done, "an invalid scene never starts and ends at once")


func _library() -> void:
	var library := FieldScriptScript.library(true)
	var scene_ids: Array = FieldScriptScript.scene_ids()
	check(scene_ids.size() >= 24, "the library holds the aftermath and demo scenes", str(scene_ids.size()))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/audio_manifest.json"))
	var sound_ids := {}
	for entry in manifest.get("entries", []):
		sound_ids[str(entry.get("asset_id", ""))] = true
		if str(entry.get("event", "")) != "":
			sound_ids[str(entry.get("event", ""))] = true
	var bad_scenes: Array = []
	var bad_sounds: Array = []
	var bad_text: Array = []
	for scene_id in scene_ids:
		var steps: Array = FieldScriptScript.steps_of(str(scene_id))
		if not FieldScriptScript.validate(steps).is_empty():
			bad_scenes.append(scene_id)
		for step in steps:
			if str(step.cmd) == "sfx" and not sound_ids.has(str(step.id)):
				bad_sounds.append("%s:%s" % [scene_id, step.id])
			if step.has("text"):
				for lang in ["ko", "en"]:
					if FieldScriptScript.text_of(step.text, lang).strip_edges().is_empty():
						bad_text.append("%s:%s" % [scene_id, lang])
	check(bad_scenes.is_empty(), "every library scene validates", str(bad_scenes))
	check(bad_sounds.is_empty(), "every sfx id is a shipped sound asset or event", str(bad_sounds))
	check(bad_text.is_empty(), "every authored line has Korean and English", str(bad_text))
	var demo_cmds := {}
	for step in FieldScriptScript.steps_of("demo_standoff"):
		demo_cmds[str(step.cmd)] = true
	var missing: Array = []
	for cmd in FieldScriptScript.COMMANDS:
		if not demo_cmds.has(cmd):
			missing.append(cmd)
	check(missing.is_empty(), "the demo scene uses every command", str(missing))

	var boss_stages: Array = []
	for stage in DataRegistry.data.get("stages", []):
		var has_boss := false
		for wave in stage.get("waves", []):
			for enemy_id in wave:
				if str(DataRegistry.enemy(str(enemy_id)).get("rank", "")) == "BOSS":
					has_boss = true
		if has_boss:
			boss_stages.append(str(stage.id))
	check(boss_stages.size() == 23, "the game has 23 boss stages", str(boss_stages.size()))
	var unbound: Array = []
	for stage_id in boss_stages:
		if not (library.bindings.boss_aftermath as Dictionary).has(stage_id):
			unbound.append(stage_id)
	check(unbound.is_empty(), "every boss stage has its own aftermath scene", str(unbound))
	check(FieldScriptScript.scene_id_for("boss_aftermath", "CH01-N20") == "aftermath_ch01_n20", "a bound stage finds its scene")
	check(FieldScriptScript.scene_id_for("boss_aftermath", "CH99-N20") == "aftermath_default", "an unknown boss stage falls back to the default scene")
	check(FieldScriptScript.scene_id_for("no_such_moment", "CH01-N20") == "", "an unknown moment has no scene")
	var filled: Array = FieldScriptScript.steps_for("boss_aftermath", "CH99-N20", {"boss": "시험체"})
	var joined := JSON.stringify(filled)
	check(joined.contains("시험체") and not joined.contains("{boss}"), "the default scene names the boss")
	var lines := {}
	for stage_id in boss_stages:
		for step in FieldScriptScript.steps_for("boss_aftermath", str(stage_id)):
			if str(step.cmd) == "say" and str(step.side) == "foe":
				lines[FieldScriptScript.text_of(step.text, "ko")] = true
	check(lines.size() == boss_stages.size(), "each boss has its own last words", "%d of %d" % [lines.size(), boss_stages.size()])


# -- timeline --------------------------------------------------------------------

func _runtime() -> void:
	# say: typing, tap to finish the line, tap to dismiss.
	var run := _run([{"cmd": "say", "actor": "leader", "text": "abcdefghij", "text_key": ""}])
	var scene: RefCounted = run[0]
	var stage: FakeStage = run[1]
	check(bool(run[2]) and scene.is_running(), "a valid scene starts running")
	check(scene.bubbles.size() == 1 and scene.bubbles[0].side == "ally" and scene.bubbles[0].name == "Lead", "an ally line is teal-side with the actor's name")
	scene.advance(0.1)
	var typed_now := int(scene.bubbles[0].typed)
	check(typed_now >= 3 and typed_now <= 5, "the typing effect runs at about 42 characters a second", str(typed_now))
	check(not scene.waiting_for_tap(), "a line still typing does not wait for a tap")
	scene.tap()
	check(int(scene.bubbles[0].typed) == 10, "a tap while typing completes the line")
	scene.advance(0.05)
	check(scene.waiting_for_tap(), "a fully typed line waits for the player")
	scene.tap()
	scene.advance(0.05)
	check(scene.done and not scene.skipped, "the second tap dismisses it and ends the scene")
	check(stage.finished_calls == 1, "the host is told once when the scene ends")

	# a foe line is red-side; an explicit side wins.
	var foe_run := _run([{"cmd": "say", "actor": "foe", "text": "hi"}, {"cmd": "say", "actor": "leader", "side": "event", "text": "yo"}])
	var foe_scene: RefCounted = foe_run[0]
	check(foe_scene.bubbles[0].side == "foe", "an enemy line uses the red plate")
	foe_scene.advance(0.2)
	foe_scene.advance(0.05)
	foe_scene.tap()
	foe_scene.advance(0.05)
	var sides: Array = foe_scene.bubbles.map(func(bubble): return str(bubble.side))
	check(sides.has("event"), "an explicit side overrides the speaker's side", str(sides))

	# hold: auto advance without a tap.
	var hold_run := _run([{"cmd": "say", "actor": "leader", "text": "ab", "hold": 0.3}])
	var hold_scene: RefCounted = hold_run[0]
	_drain(hold_scene, 0.25)
	check(hold_scene.is_running(), "a held line stays for its hold time")
	_drain(hold_scene, 0.6)
	check(hold_scene.done, "a held line closes by itself")

	# with-groups.
	var group_run := _run([
		{"cmd": "move", "actor": "leader", "dx": 1.0, "time": 0.4},
		{"cmd": "emote", "actor": "leader", "kind": "alert", "with": true},
		{"cmd": "sfx", "id": "BOSS_HIT", "with": true},
		{"cmd": "say", "actor": "foe", "text": "later", "hold": 0.1},
	])
	var group_scene: RefCounted = group_run[0]
	var group_stage: FakeStage = group_run[1]
	check(group_scene.cursor == 3 and group_scene.emotes.size() == 1 and group_stage.events.has("sfx:BOSS_HIT"), "a with-group starts together")
	check(group_scene.bubbles.is_empty(), "the next group waits for the move to end")
	group_scene.advance(0.5)
	check(group_scene.bubbles.size() == 1, "the next group starts once the previous one is done")
	check(is_equal_approx((group_stage.poses.leader.offset as Vector2).x, 1.0), "move reaches its offset", str(group_stage.poses.leader.offset))
	_drain(group_scene, 3.0)
	check(group_scene.done, "the scene ends after its last group")

	# move to front/back/home, face, jump.
	var move_run := _run([
		{"cmd": "move", "actor": "leader", "to": "front", "time": 0.2},
		{"cmd": "move", "actor": "foe", "to": "front", "time": 0.2},
		{"cmd": "face", "actor": "leader", "toward": "foe"},
		{"cmd": "face", "actor": "foe", "toward": "leader"},
		{"cmd": "jump", "actor": "leader", "height": 0.8, "time": 0.4},
		{"cmd": "move", "actor": "leader", "to": "home", "time": 0.2},
	])
	var move_scene: RefCounted = move_run[0]
	var move_stage: FakeStage = move_run[1]
	_drain(move_scene, 0.25)
	check(is_equal_approx((move_stage.poses.leader.offset as Vector2).x, FieldSceneScript.FRONT_STEP), "front steps toward the opponent", str(move_stage.poses.leader.offset))
	_drain(move_scene, 0.25)
	check(is_equal_approx((move_stage.poses.foe.offset as Vector2).x, -FieldSceneScript.FRONT_STEP), "the opposing side steps the other way")
	scene = move_scene
	scene.advance(0.01)
	check(int(move_stage.poses.leader.flip) == 1 and int(move_stage.poses.foe.flip) == -1, "face turns each actor towards the other")
	var peak := 0.0
	while scene.is_running() and scene.cursor <= 5 and scene.active.size() > 0:
		scene.advance(0.02)
		peak = maxf(peak, float(move_stage.poses.leader.hop))
		if scene.cursor >= 6:
			break
	check(peak > 0.7 and peak <= 0.81, "a jump peaks at its height", str(peak))
	_drain(move_scene, 1.0)
	check(is_zero_approx(float(move_stage.poses.leader.hop)) and (move_stage.poses.leader.offset as Vector2).length() < 0.001, "a jump lands and home restores the position", str(move_stage.poses.leader))
	check(move_scene.done, "the movement scene ends")


func _more_runtime() -> void:
	# emote lifetime, camera, banner, wait.
	var run := _run([
		{"cmd": "emote", "actor": "foe", "kind": "anger", "time": 0.4},
		{"cmd": "camera", "focus": "foe", "zoom": 1.5, "shake": 10.0, "time": 0.5},
		{"cmd": "banner", "text": "BANNER", "style": "boss", "time": 0.4},
		{"cmd": "wait", "sec": 0.2},
	])
	var scene: RefCounted = run[0]
	var stage: FakeStage = run[1]
	check(scene.emotes.size() == 1 and str(scene.emotes[0].kind) == "anger", "an emote is shown above the actor")
	scene.advance(0.5)
	check(scene.emotes.is_empty(), "an emote fades after its time")
	check(stage.camera.focus == "foe", "the camera resolves its focus to a host actor")
	scene.advance(0.3)
	check(float(stage.camera.zoom) > 1.0 and float(stage.camera.zoom) <= 1.5, "the camera zooms over time", str(stage.camera.zoom))
	check(float(stage.camera.shake) > 0.0, "the camera shake is passed to the host")
	_drain(scene, 1.0)
	var settled_shake := float(stage.camera.shake)
	check(scene.done and settled_shake < 0.5, "shake decays and the scene ends", str(settled_shake))

	var banner_run := _run([{"cmd": "banner", "text": "TAP ME", "style": "event", "time": 0.3, "tap": true}])
	var banner_scene: RefCounted = banner_run[0]
	check(str(banner_scene.banner.get("text", "")) == "TAP ME", "a banner shows its text")
	banner_scene.advance(1.0)
	check(banner_scene.waiting_for_tap() and banner_scene.is_running(), "a tap banner holds until tapped")
	banner_scene.tap()
	banner_scene.advance(0.05)
	check(banner_scene.done, "tapping the banner ends the scene")

	# an actor that is not on screen is ignored, never fatal.
	var ghost_run := _run([
		{"cmd": "move", "actor": "ghost", "dx": 2.0},
		{"cmd": "jump", "actor": "ghost"},
		{"cmd": "emote", "actor": "ghost", "kind": "alert"},
		{"cmd": "face", "actor": "ghost", "toward": "foe"},
		{"cmd": "wait", "sec": 0.1},
	])
	_drain(ghost_run[0], 1.0)
	check(ghost_run[0].done and (ghost_run[1] as FakeStage).poses.is_empty(), "commands on a missing actor are skipped")

	# a stalled frame (a hidden tab) never freezes the timeline machinery.
	var stall_run := _run([{"cmd": "wait", "sec": 0.2}, {"cmd": "wait", "sec": 0.2}])
	stall_run[0].advance(5.0)
	stall_run[0].advance(5.0)
	check(stall_run[0].done, "large frame gaps still finish a scene")

	# skip: lasting results are applied, the scene ends once, the host is told once.
	var skip_run := _run([
		{"cmd": "say", "actor": "leader", "text": "hello there"},
		{"cmd": "move", "actor": "leader", "dx": 2.0, "time": 1.0},
		{"cmd": "face", "actor": "leader", "toward": "foe"},
		{"cmd": "say", "actor": "foe", "text": "never shown"},
	])
	var skip_scene: RefCounted = skip_run[0]
	var skip_stage: FakeStage = skip_run[1]
	var skip_signals: Array = []
	skip_scene.finished.connect(func(was_skipped): skip_signals.append(was_skipped))
	skip_scene.advance(0.1)
	skip_scene.skip()
	skip_scene.skip()
	check(skip_scene.done and skip_scene.skipped and skip_signals == [true], "skip ends the scene exactly once")
	check(skip_stage.finished_calls == 1, "skip releases the host once")
	check(skip_scene.poses.has("leader") and is_equal_approx((skip_scene.poses.leader.offset as Vector2).x, 2.0) and int(skip_scene.poses.leader.flip) == 1, "skip lands every move and turn it passed over", str(skip_scene.poses))
	check(skip_scene.bubbles.is_empty() and skip_scene.emotes.is_empty() and skip_scene.banner.is_empty(), "skip clears every bubble, emote and banner")

	# a scene can be started again on the same object.
	var replay: RefCounted = FieldSceneScript.new()
	var replay_stage := FakeStage.new()
	replay.start([{"cmd": "wait", "sec": 0.1}], replay_stage)
	_drain(replay, 1.0)
	replay.start([{"cmd": "wait", "sec": 0.1}], replay_stage)
	check(replay.is_running() and not replay.done, "a finished scene object can be started again")
	check(FieldScriptScript.reading_seconds("a") >= 1.0 and FieldScriptScript.reading_seconds("가".repeat(200)) <= 6.5, "reading time stays between one and six and a half seconds")


# -- converters over the shipped data --------------------------------------------

func _converters() -> void:
	var maps := 0
	var boss_scenes := 0
	var event_scenes := 0
	var invalid: Array = []
	var page_mismatch: Array = []
	var missing_text: Array = []
	var side_errors: Array = []
	var longest := 0
	for chapter in range(1, 21):
		var map_id := "CH%02d_MAP" % chapter
		var map_json: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/compiled/chapter_maps/%s.json" % map_id))
		if not map_json is Dictionary:
			continue
		maps += 1
		var contacts: Array = []
		for node in (map_json as Dictionary).get("nodes", []):
			var presentation: Dictionary = node.get("presentation", {})
			if str(presentation.get("transition_style", "")) == "BOSS":
				contacts.append({"kind": "BOSS", "pages": presentation.get("pre_battle_dialogue", []), "title_key": str(presentation.get("event_title_key", "")), "id": map_id + ":boss"})
		for event in (map_json as Dictionary).get("event_encounters", []):
			var recruit_ids: Array = []
			for recruitment in event.get("recruitments", []):
				recruit_ids.append(str(recruitment.get("character_id", "")))
			contacts.append({"kind": "EVENT", "pages": event.get("pre_battle_dialogue", []), "title_key": str(event.get("title_key", "")), "outcome_key": str(event.get("contact_outcome_key", "")), "recruits": recruit_ids, "id": str(event.get("event_encounter_id", ""))})
		for contact in contacts:
			var pages: Array = contact.pages
			if pages.is_empty():
				continue
			var boss: bool = contact.kind == "BOSS"
			var options := {"kind": contact.kind, "event_ids": contact.get("recruits", []), "title_key": "" if boss else contact.title_key, "outcome_key": "" if boss else contact.get("outcome_key", "")}
			var steps: Array = FieldScriptScript.from_dialogue_pages(pages, options)
			if boss:
				boss_scenes += 1
			else:
				event_scenes += 1
			if not FieldScriptScript.validate(steps).is_empty():
				invalid.append(contact.id)
			longest = maxi(longest, steps.size())
			var says: Array = steps.filter(func(step): return str(step.cmd) == "say")
			if says.size() != pages.size():
				page_mismatch.append(contact.id)
			for index in range(mini(says.size(), pages.size())):
				var page: Dictionary = pages[index]
				var key := str(page.get("text_key", ""))
				var localized := LocalizationService.tr_key(key)
				if key.is_empty() or localized.is_empty() or localized == key or localized.begins_with("["):
					missing_text.append("%s:%s" % [contact.id, key])
				if str(page.get("speaker_kind", "")) == "ENEMY" and str(says[index].side) != "foe":
					side_errors.append("%s:%d" % [contact.id, index])
				if str(page.get("speaker_kind", "")) == "COMPANION" and str(says[index].side) == "foe":
					side_errors.append("%s:%d" % [contact.id, index])
	check(maps == 20, "all twenty chapter maps were read", str(maps))
	check(boss_scenes >= 20, "every boss standoff becomes a scene", str(boss_scenes))
	check(event_scenes >= 90, "every authored map event becomes a scene", str(event_scenes))
	check(invalid.is_empty(), "every converted scene validates", str(invalid.slice(0, 5)))
	check(longest <= FieldScriptScript.MAX_STEPS, "converted scenes stay under the step cap", str(longest))
	check(page_mismatch.is_empty(), "one bubble per authored page", str(page_mismatch.slice(0, 5)))
	check(missing_text.is_empty(), "every page text resolves in the localization table", str(missing_text.slice(0, 5)))
	check(side_errors.is_empty(), "enemy pages are red and companion pages are never red", str(side_errors.slice(0, 5)))
	var demo := FieldScriptScript.from_dialogue_pages([
		{"speaker_kind": "NARRATION", "text_key": "x"},
		{"speaker_kind": "COMPANION", "speaker_id": "CHR006", "text_key": "y"},
		{"speaker_kind": "COMPANION", "speaker_id": "CHR001", "text_key": "z"},
	], {"kind": "EVENT", "event_ids": ["CHR006"], "speaker_name": func(page): return "N:" + str(page.text_key)})
	var says: Array = demo.filter(func(step): return str(step.cmd) == "say")
	check(says[0].side == "event" and says[0].actor == "center", "narration is spoken from the middle in the gold plate")
	check(says[1].side == "event" and says[1].actor == "foe" and says[2].side == "ally" and says[2].actor == "leader", "the recruit candidate speaks gold from the encounter's side")
	check(says[0].speaker == "N:x", "a speaker resolver supplies the display name")
	check(str((demo[demo.size() - 1] as Dictionary).cmd) == "camera", "a converted scene hands the camera back at the end")


# -- overlay ---------------------------------------------------------------------

func _overlay_layout() -> void:
	for view_size in [Vector2(1600, 900), Vector2(390, 844)]:
		var holder := Control.new()
		holder.size = view_size
		add_child(holder)
		var overlay: Control = FieldSceneOverlayScript.new()
		holder.add_child(overlay)
		overlay.size = view_size
		var stage := FakeStage.new()
		stage.anchors = {"leader": Vector2(view_size.x * 0.02, view_size.y * 0.55), "foe": Vector2(view_size.x * 0.98, view_size.y * 0.5)}
		var steps: Array = FieldScriptScript.steps_of("demo_standoff")
		steps.append({"cmd": "say", "actor": "leader", "side": "ally", "text": "가나다라마바사아자차카타파하 ".repeat(6), "hold": 0.2})
		var finished_flags: Array = []
		overlay.finished.connect(func(was_skipped): finished_flags.append(was_skipped))
		check(overlay.play(steps, stage, {"letterbox": true}), "the overlay starts a valid scene at %s" % view_size)
		var out_of_bounds := 0
		var seen_bubbles := 0
		var frames := 0
		while overlay.is_active() and frames < 900:
			overlay.scene.advance(0.05)
			if overlay.scene.waiting_for_tap():
				overlay.scene.tap()
			overlay.queue_redraw()
			await get_tree().process_frame
			for rect in overlay.bubble_rects:
				seen_bubbles += 1
				if rect.position.x < -0.5 or rect.position.y < -0.5 or rect.end.x > view_size.x + 0.5 or rect.end.y > view_size.y + 0.5:
					out_of_bounds += 1
			frames += 1
		check(seen_bubbles > 0, "bubbles were drawn at %s" % view_size)
		check(out_of_bounds == 0, "every bubble stays on screen at %s (edge-hugging actors, long text)" % view_size, str(out_of_bounds))
		check(finished_flags == [false], "the overlay reports the end once at %s" % view_size, str(finished_flags))
		check(not (overlay.skip_button as Button).visible, "the skip button hides when the scene ends")
		holder.queue_free()

	# The skip button ends a scene mid-way.
	var skip_holder := Control.new()
	skip_holder.size = Vector2(1600, 900)
	add_child(skip_holder)
	var skip_overlay: Control = FieldSceneOverlayScript.new()
	skip_holder.add_child(skip_overlay)
	skip_overlay.size = Vector2(1600, 900)
	var skip_stage := FakeStage.new()
	var skip_flags: Array = []
	skip_overlay.finished.connect(func(was_skipped): skip_flags.append(was_skipped))
	skip_overlay.play(FieldScriptScript.steps_of("demo_standoff"), skip_stage)
	await get_tree().process_frame
	(skip_overlay.skip_button as Button).pressed.emit()
	check(skip_flags == [true] and not skip_overlay.is_active(), "the skip button ends the scene and reports a skip")
	skip_holder.queue_free()


# -- map adapter -----------------------------------------------------------------

class FakeMapScreen extends Node:
	var actors := {"leader": Vector3(0, 0, 0), "foe": Vector3(2, 0, 0)}
	var calls: Array = []
	func field_actor_world(role: String, _node_id: String) -> Vector3:
		return actors.get(role, Vector3.INF)
	func field_head_global(world: Vector3) -> Vector2:
		return Vector2.INF if world == Vector3.INF else Vector2(500.0 + world.x * 100.0, 300.0)
	func field_set_pawn_pose(offset: Vector2, hop: float, flip: int) -> void:
		calls.append(["pawn", offset, hop, flip])
	func field_set_enemy_pose(node_id: String, offset: Vector2, hop: float) -> void:
		calls.append(["enemy", node_id, offset, hop])
	func field_set_camera(focus_world: Vector3, zoom: float, shake: float) -> void:
		calls.append(["camera", focus_world, zoom, shake])
	func field_release() -> void:
		calls.append(["release"])


func _map_stage() -> void:
	var screen := FakeMapScreen.new()
	var holder := Control.new()
	holder.position = Vector2(100, 50)
	holder.size = Vector2(1000, 600)
	add_child(holder)
	add_child(screen)
	var stage = MapFieldStageScript.new(screen, holder, "NODE_X", {"leader": "Lead"}, func(_id): return null)
	check(stage.resolve("leader") == "leader" and stage.resolve("boss") == "foe" and stage.resolve("event") == "foe" and stage.resolve("stranger") == "", "the map resolves the squad and the encounter pawn")
	check(stage.actor_side("foe") == "foe" and stage.actor_side("leader") == "ally", "map sides")
	check(stage.opponent_of("leader") == "foe" and stage.opponent_of("foe") == "leader", "map opponents")
	check(stage.direction_between("leader", "foe") == 1 and stage.direction_between("foe", "leader") == -1, "the map reads left and right from screen positions")
	check(stage.actor_anchor("leader").is_equal_approx(Vector2(400.0, 250.0)), "anchors are converted into the overlay's own space", str(stage.actor_anchor("leader")))
	screen.actors.erase("foe")
	check(stage.actor_anchor("foe") == Vector2.INF and stage.direction_between("leader", "foe") == 0, "an actor that is not on screen has no anchor")
	screen.actors["foe"] = Vector3(2, 0, 0)
	stage.apply_actor_pose("leader", Vector2(1, 0), 0.4, 1)
	stage.apply_actor_pose("foe", Vector2(-1, 0), 0.0, -1)
	check(screen.calls[0][0] == "pawn" and screen.calls[1][0] == "enemy" and screen.calls[1][1] == "NODE_X", "poses reach the map pawn and the encounter pawn")
	stage.apply_camera("foe", 1.3, 4.0)
	var camera_call: Array = screen.calls[2]
	check(camera_call[0] == "camera" and (camera_call[1] as Vector3).x > 1.0 and (camera_call[1] as Vector3).x < 2.0, "a focus leans toward the actor but keeps the opponent in view", str(camera_call))
	stage.apply_camera("", 1.0, 0.0)
	check(screen.calls[3][1] == Vector3.INF, "an empty focus hands the view back")
	stage.scene_finished()
	check(screen.calls[screen.calls.size() - 1][0] == "release", "the map is released when the scene ends")
	holder.queue_free()
	screen.queue_free()


# -- battle aftermath -------------------------------------------------------------

func _boss_view(enabled: bool) -> Array:
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage("CH01-N20"), 7, DataRegistry.data)
	var view := BattleView.new()
	view.size = Vector2(1600, 900)
	add_child(view)
	view.setup(sim)
	# Bring the boss wave in, the way a real fight reaches it.
	sim._spawn_next_wave()
	sim._spawn_next_wave()
	view.field_aftermath_enabled = enabled
	view.field_portrait_source = func(_id): return null
	# The boss fell: a genuine terminal state without simulating the whole fight.
	for unit in sim.state.enemies:
		if str(unit.get("rank", "")) == "BOSS":
			unit["hp"] = 0
			unit["alive"] = false
	for unit in sim.state.enemies:
		unit["alive"] = false
		unit["hp"] = 0
	sim.state.ended = true
	sim.state.victory = true
	view.boss_arena_active = true
	view.consumed_events = sim.event_log.size()
	return [sim, view]


func _battle_aftermath() -> void:
	var finished_count := [0]
	# Off by default: the battle goes straight to its finale, exactly as before.
	var plain := _boss_view(false)
	var plain_view: BattleView = plain[1]
	plain_view.battle_finished.connect(func(_result): finished_count[0] += 1)
	plain_view._process(0.05)
	check(plain_view.boss_victory_elapsed >= 0.0 and plain_view.field_overlay == null, "without the host switch a boss victory starts its finale at once")
	for _frame in range(60):
		plain_view._process(0.05)
	check(finished_count[0] == 1, "the finale still hands off to the result exactly once")
	plain_view.queue_free()

	# On: the aftermath plays first, then the finale, then the hand-off.
	finished_count[0] = 0
	var played := _boss_view(true)
	var view: BattleView = played[1]
	view.battle_finished.connect(func(_result): finished_count[0] += 1)
	view._process(0.05)
	check(view.field_aftermath_state == "playing" and view.field_overlay != null, "a defeated boss opens its aftermath scene")
	check(view.boss_victory_elapsed < 0.0 and view.scene_transition_active(), "the finale card waits for the aftermath and the battle HUD hides")
	var boss_point := view.field_head_point("boss")
	var leader_point := view.field_head_point("leader")
	check(boss_point != Vector2.INF and leader_point != Vector2.INF and boss_point.x > leader_point.x, "the boss stands on the enemy side, the survivors on the ally side", "%s %s" % [boss_point, leader_point])
	var snapshot: Dictionary = view.field_overlay.snapshot()
	check(int(snapshot.get("steps", 0)) > 3 and not view.field_unit("boss").is_empty(), "the scene comes from the boss's own aftermath script")
	var zoom_before := view._battlefield_camera_zoom()
	var saw_offset := false
	var saw_zoom := false
	var guard := 0
	while view.field_aftermath_state == "playing" and guard < 800:
		view._process(0.05)
		var overlay: Control = view.field_overlay
		if overlay != null and is_instance_valid(overlay):
			overlay._process(0.05)
			if overlay.scene != null and overlay.scene.waiting_for_tap():
				overlay.scene.tap()
		if view._field_pose_offset(view.field_unit("leader")).length() > 1.0 or view._field_pose_offset(view.field_unit("ally")).length() > 1.0:
			saw_offset = true
		if view._battlefield_camera_zoom() > zoom_before + 0.05:
			saw_zoom = true
		guard += 1
	check(saw_offset, "a survivor steps forward on the battle floor")
	check(saw_zoom, "the camera pushes in during the aftermath")
	check(view.field_aftermath_state == "done" and view.field_overlay == null, "the aftermath ends and removes its overlay")
	check(view.field_poses.is_empty() and is_equal_approx(view.field_zoom, 1.0) and view.field_offset == Vector2.ZERO, "poses and camera are back to normal afterwards")
	check(view._field_pose_offset(view.field_unit("leader")) == Vector2.ZERO and is_zero_approx(view._field_hop_px(view.field_unit("leader"))), "no unit keeps a field offset or hop")
	for _frame in range(60):
		view._process(0.05)
	check(view.boss_victory_elapsed >= 0.0 and finished_count[0] == 1, "then the finale plays and the result is handed off once", str(finished_count))
	view.queue_free()

	# A player who skipped the fight never sits through the scene.
	var skipped := _boss_view(true)
	var skipped_view: BattleView = skipped[1]
	skipped_view.skip_in_progress = true
	skipped_view._process(0.05)
	check(skipped_view.field_aftermath_state == "done" and skipped_view.boss_victory_elapsed >= 0.0, "a skipped battle goes straight to its finale")
	skipped_view.queue_free()

	# Reduced motion does not get the scene either.
	var previous: Variant = SettingsService.values.get("map_reduced_transition", false)
	SettingsService.values["map_reduced_transition"] = true
	var reduced := _boss_view(true)
	var reduced_view: BattleView = reduced[1]
	reduced_view._process(0.05)
	check(reduced_view.field_aftermath_state == "done" and reduced_view.field_overlay == null, "reduced-motion players skip the field scene")
	SettingsService.values["map_reduced_transition"] = previous
	reduced_view.queue_free()

	# Resetting the view for the next battle clears a half-played scene.
	var reset := _boss_view(true)
	var reset_view: BattleView = reset[1]
	reset_view._process(0.05)
	reset_view.setup(reset[0])
	check(reset_view.field_aftermath_state == "idle" and reset_view.field_poses.is_empty(), "setup for a new battle clears the aftermath state")
	reset_view.queue_free()


# -- guards ----------------------------------------------------------------------

func _sources() -> void:
	var forbidden := ["AppState", "SaveService", "profile", "RewardService", "record_clear", "resolve_event_encounter_victory"]
	var offenders: Array = []
	for file_name in ["field_script.gd", "field_scene.gd", "field_scene_overlay.gd", "field_stage.gd", "map_field_stage.gd", "battle_field_stage.gd"]:
		var source := FileAccess.get_file_as_string("res://field/%s" % file_name)
		for word in forbidden:
			if source.contains(word):
				offenders.append("%s:%s" % [file_name, word])
	check(offenders.is_empty(), "field direction code never touches game state, saves or rewards", str(offenders))
	var shell := FileAccess.get_file_as_string("res://screens/app_shell.gd")
	check(shell.contains("_play_field_contact(veil, focus, special_event") and shell.contains("_play_special_event_dialogue(veil, special_event, focus)"), "map events try the field scene and keep the reading panel as fallback")
	check(shell.contains("_play_field_contact(veil, focus, boss_contact") and shell.contains("_play_special_event_dialogue(veil, boss_contact, focus)"), "boss standoffs try the field scene and keep the reading panel as fallback")
	check(shell.contains("battle_view.field_aftermath_enabled = true"), "the host turns the boss aftermath on for real battles")
