extends Node

## Captures the phase-3 field direction through the real shell. Needs a rendering
## window (not --headless).
##   godot --path godot --resolution WxH res://tools/capture_presentation_phase3_qa.tscn -- <out_dir> <W> <H> map [event|boss]
##   godot --path godot --resolution WxH res://tools/capture_presentation_phase3_qa.tscn -- <out_dir> <W> <H> battle
## map: a map event contact and a boss standoff, played on the chapter 1 map with
## the production transition path (title banner, alert, bubbles, camera push).
## battle: the boss aftermath on the battle floor, before the finale card.

var out_dir := ""
var tag := ""
var shell: Control
var report := {"shots": [], "notes": []}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = str(args[0])
	var width := int(args[1])
	var height := int(args[2])
	tag = "%dx%d" % [width, height]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().root.size = Vector2i(width, height)
	var mode := str(args[3]) if args.size() > 3 else "map"
	if mode == "battle":
		_run_battle.call_deferred()
	else:
		_run_map.call_deferred(str(args[4]) if args.size() > 4 else "event")

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame

func _shot(name: String) -> void:
	await _frames(3)
	var path := out_dir.path_join("%s_%s.png" % [tag, name])
	get_tree().root.get_texture().get_image().save_png(path)
	report.shots.append(path.get_file())
	print("SHOT ", path.get_file())

func _boot() -> void:
	shell = load("res://screens/boot/boot.tscn").instantiate()
	get_tree().root.add_child(shell)
	await _frames(2)
	shell.call("_finish_intro_video")
	await _frames(2)

func _finish(label: String) -> void:
	print("%s %s" % [label, JSON.stringify(report)])
	get_tree().quit(0)

func _map_screen() -> Node:
	return shell.content.get_node_or_null("ChapterMapScreen") if shell != null else null

func _field_overlay() -> Control:
	return shell.find_child("FieldContactScene", true, false) as Control

func _wait_for_overlay(limit_frames := 300) -> Control:
	for frame in limit_frames:
		await get_tree().process_frame
		var overlay := _field_overlay()
		if overlay != null and overlay.has_method("is_active") and overlay.is_active():
			return overlay
	return null

func _wait_for_bubbles(overlay: Control, count: int, limit_frames := 600) -> bool:
	for frame in limit_frames:
		await get_tree().process_frame
		if not is_instance_valid(overlay) or not overlay.is_active():
			return false
		var snapshot: Dictionary = overlay.snapshot()
		var lines: Array = snapshot.get("bubbles", [])
		if snapshot.get("waiting", false) and lines.size() >= 1:
			count -= 1
			if count <= 0:
				return true
	return false

## Where the party is put before the map is built: the cell beside the node, as a
## saved game restored there would have it.
func _cell_beside(node_id: String) -> Vector2i:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/compiled/chapter_maps/CH01_MAP.json"))
	for node in data.get("nodes", []):
		if str(node.get("node_id", "")) == node_id:
			return Vector2i(int(node.get("q", 0)) - 1, int(node.get("r", 0)))
	return Vector2i(-9999, -9999)

func _face_encounter(map_screen: Node, node_id: String) -> bool:
	var definition: Dictionary = map_screen.get("definition")
	var node: Dictionary = {}
	for candidate in definition.get("nodes", []):
		if str(candidate.get("node_id", "")) == node_id:
			node = candidate
	if node.is_empty():
		return false
	var pawn: Node3D = map_screen.get("pawn")
	map_screen.set("camera_target", map_screen.call("_clamp_camera_target_to_terrain", pawn.global_position))
	map_screen.set("web_entity_projection_dirty", true)
	if not map_screen.get("enemy_pawns").has(node_id):
		map_screen.call("_create_enemy_pawn", node)
	report.notes.append("beside %s enemy_pawn=%s pawn=%s" % [node_id, str(map_screen.get("enemy_pawns").has(node_id)), pawn.global_position])
	return true

func _run_contact(node_id: String, stage_id: String, label: String) -> void:
	var map_screen := _map_screen()
	if not _face_encounter(map_screen, node_id):
		print("CAPTURE_FAIL no node ", node_id)
		get_tree().quit(1)
		return
	await _wait(0.8)
	AppState.selected_stage_id = stage_id
	AppState.chapter_map_state("CH01_MAP")["pending_encounter"] = {}
	var prepared := AppState.prepare_map_encounter(stage_id, node_id, Vector2i(int(map_screen.get("map_state").get("current_q", 0)) - 1, int(map_screen.get("map_state").get("current_r", 0))), "CH01_MAP")
	report.notes.append("prepared=%s" % str(prepared))
	SettingsService.values["map_reduced_transition"] = false
	shell.call("_play_map_battle_transition")
	var overlay := await _wait_for_overlay()
	if overlay == null:
		print("CAPTURE_FAIL no field overlay for ", label)
		get_tree().quit(1)
		return
	await _wait(0.35)
	var probe: RefCounted = overlay.stage
	var cam: Camera3D = map_screen.get("camera")
	var leader_world: Vector3 = map_screen.call("field_actor_world", "leader", node_id)
	var foe_world: Vector3 = map_screen.call("field_actor_world", "foe", node_id)
	report.notes.append("anchors leader=%s foe=%s worlds=%s %s behind=%s/%s cam=%s size=%s" % [probe.actor_anchor("leader"), probe.actor_anchor("foe"), leader_world, foe_world, cam.is_position_behind(leader_world), cam.is_position_behind(foe_world), cam.global_position, cam.size])
	await _shot("%s_1_alert" % label)
	var index := 2
	for bubble_number in range(1, 4):
		if not await _wait_for_bubbles(overlay, 1):
			break
		report.notes.append("%s bubble %d = %s" % [label, bubble_number, JSON.stringify(overlay.snapshot().get("bubbles", []))])
		await _wait(0.35)
		await _shot("%s_%d_bubble" % [label, index])
		index += 1
		overlay.scene.tap()
		await _wait(0.1)
		overlay.scene.tap()
		await _wait(0.25)
	if is_instance_valid(overlay) and overlay.is_active():
		overlay.scene.skip()
	await _wait(0.4)

func _run_map(kind: String) -> void:
	await _boot()
	AppState.profile.story_flags["story.trigger.TRIG_CH01_INTRO"] = true
	AppState.profile.pending_story_triggers.clear()
	AppState.profile["tutorial_progress"] = {"map_basics_revision": 99, "map_basics_complete": true}
	var contact_node := "NODE_N20" if kind == "boss" else "NODE_N08"
	var beside := _cell_beside(contact_node)
	# A save that has cleared everything before the contact, standing beside it.
	var cleared_through := 19 if kind == "boss" else 7
	for number in range(1, cleared_through + 1):
		AppState.profile.stage_stars["CH01-N%02d" % number] = 3
	AppState.profile.chapter_progress["CH01"]["normal_highest"] = cleared_through
	AppState.refresh_chapter_map_reveal("CH01_MAP")
	AppState.set_chapter_map_position(beside, contact_node, "CH01_MAP")
	AppState.selected_stage_id = "CH01-N01"
	shell.call("_show_screen", "STAGE_SELECT")
	var map_screen: Node = null
	for frame in 1800:
		await get_tree().process_frame
		map_screen = _map_screen()
		if map_screen != null and bool(map_screen.get("map_ready_complete")) and (map_screen as Control).visible:
			break
	if map_screen == null:
		print("CAPTURE_FAIL no map")
		get_tree().quit(1)
		return
	await _wait(1.6)
	var contact_stage := ""
	for node in map_screen.get("definition").get("nodes", []):
		if str(node.get("node_id", "")) == contact_node:
			contact_stage = str(node.get("stage_id", ""))
	report.notes.append("%s node=%s stage=%s" % [kind, contact_node, contact_stage])
	await _run_contact(contact_node, contact_stage, "b" if kind == "boss" else "e")
	_finish("PHASE3_MAP_CAPTURE")

func _run_battle() -> void:
	await _boot()
	SettingsService.values["battle_cutin_mode"] = "OFF"
	AppState.selected_stage_id = "CH01-N20"
	shell.call("_show_screen", "BATTLE")
	var view: BattleView = null
	for frame in 900:
		await get_tree().process_frame
		view = shell.get("battle_view") as BattleView
		if view != null and view.assets_ready and view.get_node_or_null("BattleOverlay") != null:
			break
	if view == null:
		print("CAPTURE_FAIL no battle view")
		get_tree().quit(1)
		return
	await _frames(60)
	shell.call("_start_deployed_battle")
	await _wait(1.0)
	var sim: BattleSimulation = view.simulation
	# Every wave is on the floor, so no next-wave silhouettes are left waiting.
	var spawned := 0
	while sim.wave_director.has_next() and spawned < 40:
		sim._spawn_next_wave()
		spawned += 1
	for unit in sim.state.enemies:
		unit["hp"] = 0
		unit["alive"] = false
	sim.state.ended = true
	sim.state.victory = true
	# The kills above carry no death events, so the view's display snapshots and the
	# records of the replaced waves would still show the enemies standing: drop them
	# and the view reads the sim's state.
	view.presentation_display_units.clear()
	view.presentation_actor_records.clear()
	view.boss_arena_active = true
	view.consumed_events = sim.event_log.size()
	report.notes.append("aftermath_enabled=%s" % str(view.field_aftermath_enabled))
	var overlay: Control = null
	for frame in 300:
		await get_tree().process_frame
		overlay = view.field_overlay
		if overlay != null and is_instance_valid(overlay):
			break
	if overlay == null:
		print("CAPTURE_FAIL no aftermath overlay state=", view.field_aftermath_state)
		get_tree().quit(1)
		return
	await _wait(0.9)
	await _shot("61_aftermath_push_in")
	var index := 62
	for bubble_number in range(2):
		if not await _wait_for_bubbles(overlay, 1):
			break
		report.notes.append("bubble %d = %s" % [bubble_number, JSON.stringify(overlay.snapshot().get("bubbles", []))])
		await _wait(0.4)
		await _shot("%d_aftermath_bubble" % index)
		index += 1
		overlay.scene.tap()
		await _wait(0.1)
		overlay.scene.tap()
		await _wait(0.3)
	await _wait(1.0)
	await _shot("%d_aftermath_finale" % index)
	_finish("PHASE3_BATTLE_CAPTURE")
