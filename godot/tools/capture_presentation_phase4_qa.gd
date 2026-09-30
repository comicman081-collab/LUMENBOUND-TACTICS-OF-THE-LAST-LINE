extends Node

## Captures the phase-4 presentation through the real shell. Needs a rendering
## window (not --headless).
##   godot --path godot --resolution WxH res://tools/capture_presentation_phase4_qa.tscn -- <out_dir> <W> <H> hit [stage]
##   godot --path godot --resolution WxH res://tools/capture_presentation_phase4_qa.tscn -- <out_dir> <W> <H> floor <stage_id>
##   godot --path godot --resolution WxH res://tools/capture_presentation_phase4_qa.tscn -- <out_dir> <W> <H> map <chapter_id>
##   godot --path godot --resolution WxH res://tools/capture_presentation_phase4_qa.tscn -- <out_dir> <W> <H> landmarks <small|boss_a|boss_b|one:<chapter>>
## hit: white flash, the damage-number kinds, effect sets per weapon family,
## shake presets.
## floor: the per-region battle floor (normal and boss plate) for one stage.
## map: landmarks around the start and the chapter boss node.
## landmarks: a neutral 3D sheet of every landmark the builder produces.

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
	var mode := str(args[3]) if args.size() > 3 else "hit"
	var extra := str(args[4]) if args.size() > 4 else ""
	match mode:
		"fx": _run_fx.call_deferred()
		"flash": _run_flash.call_deferred(extra if not extra.is_empty() else "CH01-N05")
		"floor": _run_floor.call_deferred(extra if not extra.is_empty() else "CH01-N05")
		"map": _run_map.call_deferred(extra if not extra.is_empty() else "CH01")
		"landmarks": _run_landmarks.call_deferred(extra if not extra.is_empty() else "small")
		_: _run_hit.call_deferred(extra if not extra.is_empty() else "CH01-N05")

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame

func _save(name: String) -> void:
	var path := out_dir.path_join("%s_%s.png" % [tag, name])
	get_tree().root.get_texture().get_image().save_png(path)
	report.shots.append(path.get_file())
	print("SHOT ", path.get_file())

func _shot(name: String) -> void:
	await _frames(3)
	_save(name)

## Grab the frame that was just drawn, without waiting extra frames.
func _shot_now(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save(name)

func _boot() -> void:
	shell = load("res://screens/boot/boot.tscn").instantiate()
	get_tree().root.add_child(shell)
	await _frames(2)
	shell.call("_finish_intro_video")
	await _frames(2)

func _finish(label: String) -> void:
	print("%s %s" % [label, JSON.stringify(report)])
	get_tree().quit(0)

func _open_battle(stage_id: String) -> BattleView:
	await _boot()
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
		print("CAPTURE_FAIL no battle view")
		get_tree().quit(1)
		return null
	await _frames(60)
	shell.call("_start_deployed_battle")
	view.simulation.options["invincible"] = true
	await _wait(1.6)
	return view

func _damage(view: BattleView, source_uid: String, target_uid: String, percent: float, extra := {}) -> void:
	var target := view._actor_model(target_uid)
	var amount := maxi(1, int(float(target.get("max_hp", 100)) * percent))
	var payload := {"hp_damage": amount, "source": "NORMAL", "affinity_factor": 1.0}
	payload.merge(extra, true)
	view._present_regular_event(BattleEvent.make(view.simulation.state.tick, BattleEvent.DAMAGE, source_uid, target_uid, amount, payload))

func _run_hit(stage_id: String) -> void:
	var view := await _open_battle(stage_id)
	if view == null: return
	var allies: Array = view.simulation.state.party.filter(func(unit): return UnitState.alive(unit))
	var foes: Array = view.simulation.state.enemies.filter(func(unit): return UnitState.alive(unit))
	report.notes.append("allies=%d foes=%d" % [allies.size(), foes.size()])
	await _shot("41_battle_baseline")
	# Weapon-family action effects: every ally attacks at once.
	for ally in allies:
		view._play_animation(str(ally.uid), "basic_attack")
	await _wait(.20)
	await _shot_now("42_action_ranged_muzzle_tracer")
	await _wait(.22)
	await _shot_now("43_action_melee_slash_trail")
	await _wait(1.0)
	# White flash: one landed crit, grabbed on the very next frame.
	if not foes.is_empty():
		_damage(view, str(allies[0].uid), str(foes[0].uid), .35, {"crit": true})
		await _shot_now("44_hit_white_flash")
		await _wait(.14)
		await _shot_now("45_hit_after_flash")
	await _wait(1.0)
	# Four number kinds and a miss, on different victims, plus a heal.
	var kinds := [
		{"pct": .05, "extra": {}},
		{"pct": .22, "extra": {"crit": true}},
		{"pct": .12, "extra": {"affinity_factor": 1.25}},
		{"pct": .04, "extra": {"affinity_factor": .85}},
		{"pct": .3, "extra": {"crit": true, "source": "ULTIMATE"}},
	]
	for index in range(mini(kinds.size(), foes.size())):
		var source_uid := str(allies[index % allies.size()].uid)
		_damage(view, source_uid, str(foes[index].uid), float(kinds[index].pct), kinds[index].extra)
	if not allies.is_empty():
		var healed := str(allies[mini(1, allies.size() - 1)].uid)
		view._present_regular_event(BattleEvent.make(view.simulation.state.tick, BattleEvent.HEAL, str(allies[0].uid), healed, 140))
	await _wait(.10)
	await _shot_now("46_numbers_early")
	await _wait(.22)
	await _shot_now("47_numbers_settled")
	await _wait(.9)
	# Impact effect sets per weapon family, plain and with accents.
	for index in range(mini(allies.size(), foes.size())):
		var accent := {} if index % 3 == 0 else ({"crit": true} if index % 3 == 1 else {"affinity_factor": 1.25})
		_damage(view, str(allies[index].uid), str(foes[index].uid), .1, accent)
	await _wait(.05)
	await _shot_now("48_impacts_early")
	await _wait(.10)
	await _shot_now("49_impacts_mid")
	_finish("PHASE4_HIT_CAPTURE")

class FxSheet extends Control:
	## Every weapon family's action and impact at fixed times, drawn straight
	## from the effect library on a neutral floor (no battle noise).
	const Weapons := preload("res://battle/view/combat_weapon_effects.gd")
	var families := ["blade", "claw", "rifle", "burst", "mortar", "siege", "shield", "prism", "seal", "heal"]
	var action_times := [.30, .44, .52, .60]
	var impact_times := [.04, .15, .40, .70]
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(.10, .13, .16))
		var rows := families.size()
		var row_h := size.y / float(rows)
		var cols := action_times.size() + impact_times.size()
		var col_w := size.x / float(cols)
		for row in range(rows):
			var family: String = families[row]
			draw_string(ThemeDB.fallback_font, Vector2(6, row * row_h + 16), family, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(.8, .9, 1))
			for col in range(cols):
				var cell := Vector2(col * col_w, row * row_h)
				draw_rect(Rect2(cell, Vector2(col_w, row_h)), Color(1, 1, 1, .05), false, 1.0)
				var accent := "crit" if row % 3 == 1 else ("weak" if row % 3 == 2 else "")
				if col < action_times.size():
					var origin := cell + Vector2(col_w * .22, row_h * .55)
					var target := cell + Vector2(col_w * .85, row_h * .55)
					Weapons.action(self, origin, target, family, float(action_times[col]), "basic_attack", Color("7bdeed"), .8)
				else:
					var point := cell + Vector2(col_w * .5, row_h * .42)
					Weapons.impact(self, point, family, float(impact_times[col - action_times.size()]), Color("ff9464"), .8, accent)

func _run_fx() -> void:
	var sheet := FxSheet.new()
	sheet.size = Vector2(get_tree().root.size)
	add_child(sheet)
	await _frames(4)
	_save("71_fx_sheet")
	_finish("PHASE4_FX_CAPTURE")

func _run_flash(stage_id: String) -> void:
	# One victim, frame by frame: before, the hit frames and after.
	var view := await _open_battle(stage_id)
	if view == null: return
	view.paused = true
	await _frames(4)
	var allies: Array = view.simulation.state.party.filter(func(unit): return UnitState.alive(unit))
	var foes: Array = view.simulation.state.enemies.filter(func(unit): return UnitState.alive(unit))
	var victim: Dictionary = foes[0]
	var ally_victim: Dictionary = allies[0]
	report.notes.append("victim=%s %s" % [victim.def_id, view._unit_pos(victim)])
	for step in ["a_before", "b_hit1", "c_hit2", "d_after1", "e_after2"]:
		if step == "b_hit1":
			_damage(view, str(allies[1].uid), str(victim.uid), .2)
			_damage(view, str(foes[0].uid), str(ally_victim.uid), .2)
		await _shot_now("61_flash_%s" % step)
		report.notes.append("%s frames=%s flash=%s" % [step, JSON.stringify(view.hit_flash_frames), JSON.stringify(view.unit_flash)])
	_finish("PHASE4_FLASH_CAPTURE")

func _run_floor(stage_id: String) -> void:
	var view := await _open_battle(stage_id)
	if view == null: return
	report.notes.append("stage=%s" % stage_id)
	await _shot("51_floor_%s" % stage_id)
	_finish("PHASE4_FLOOR_CAPTURE")

func _map_screen() -> Node:
	return shell.content.get_node_or_null("ChapterMapScreen") if shell != null else null

## arg: "<CHnn>[:start|boss|elite|normal[:zoom[:nofog|ortho]]]" - the real chapter map with the
## party standing beside one node, framed on it.
func _run_map(arg: String) -> void:
	var parts := arg.split(":")
	var chapter := int(parts[0].trim_prefix("CH"))
	var kind := str(parts[1]) if parts.size() > 1 else "boss"
	var zoom_value := float(parts[2]) if parts.size() > 2 else 1.0
	var map_id := "CH%02d_MAP" % chapter
	await _boot()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/compiled/chapter_maps/%s.json" % map_id))
	var wanted := str({"start": "START", "boss": "NORMAL_BOSS", "elite": "NORMAL_ELITE", "normal": "NORMAL_BATTLE"}.get(kind, "NORMAL_BOSS"))
	var target: Dictionary = {}
	for node in data.get("nodes", []):
		if str(node.get("node_type", "")) == wanted:
			target = node
			break
	if target.is_empty():
		print("CAPTURE_FAIL no node of kind ", wanted)
		get_tree().quit(1)
		return
	AppState.profile["tutorial_progress"] = {"map_basics_revision": 99, "map_basics_complete": true}
	AppState.profile.pending_story_triggers.clear()
	for earlier in range(1, chapter + 1):
		var key := "CH%02d" % earlier
		AppState.profile.story_flags["story.trigger.TRIG_%s_INTRO" % key] = true
		var cleared := 19 if earlier == chapter else 20
		for number in range(1, cleared + 1):
			AppState.profile.stage_stars["%s-N%02d" % [key, number]] = 3
		var progress: Dictionary = AppState.profile.chapter_progress.get(key, {})
		progress["normal_highest"] = cleared
		AppState.profile.chapter_progress[key] = progress
	AppState.refresh_chapter_map_reveal(map_id)
	var beside := Vector2i(int(target.q), int(target.r)) if kind == "start" else Vector2i(int(target.q) - 1, int(target.r))
	AppState.set_chapter_map_position(beside, str(target.node_id), map_id)
	AppState.selected_stage_id = "CH%02d-N01" % chapter
	SettingsService.values["map_camera_perspective"] = not (parts.size() > 3 and str(parts[3]) == "ortho")
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
	var markers: Dictionary = map_screen.get("node_markers")
	var marker: Node3D = markers.get(str(target.node_id))
	if marker == null:
		print("CAPTURE_FAIL no marker for ", target.node_id)
		get_tree().quit(1)
		return
	map_screen.set("camera_target", map_screen.call("_clamp_camera_target_to_terrain", marker.global_position + Vector3(-.5, 0, -.5)))
	map_screen.set("camera_zoom", zoom_value)
	map_screen.set("web_entity_projection_dirty", true)
	if parts.size() > 3 and str(parts[3]) == "nofog":
		var overlay = map_screen.get("fog_screen_overlay")
		if overlay != null: (overlay as CanvasItem).visible = false
	await _wait(1.0)
	var roots: Array = map_screen.get("landmark_roots")
	var live := 0
	var visible_count := 0
	for root in roots:
		if is_instance_valid(root):
			live += 1
			if (root as Node3D).is_visible_in_tree():
				visible_count += 1
				var cam: Camera3D = map_screen.get("camera")
				var body := (root as Node3D).get_node_or_null("Body") as MeshInstance3D
				report.notes.append("visible %s world=%s screen=%s scale=%s parent=%s aabb=%s mat=%s" % [root.name, (root as Node3D).global_position, cam.unproject_position((root as Node3D).global_position), (root as Node3D).scale, root.get_parent().name, body.get_aabb() if body != null else "none", str(body.material_override) if body != null else "none"])
	report.notes.append("chapter=%d kind=%s node=%s landmarks=%d visible=%d markers=%d" % [chapter, kind, target.node_id, live, visible_count, markers.size()])
	await _shot("91_map_ch%02d_%s" % [chapter, kind])
	_finish("PHASE4_MAP_CAPTURE")

const Landmarks := preload("res://chapter_map/view/landmark_builder.gd")
const RegionFloor := preload("res://battle/view/battle_region_floor.gd")

func _landmark_stage(cells: Array, columns: int, spacing: Vector2) -> Dictionary:
	## cells: [{kind, variant, family, label}] laid out on a ground slab.
	var world := Node3D.new()
	add_child(world)
	var body_material := Landmarks.body_material()
	var glow_material := Landmarks.glow_material(Landmarks.LAMP_WARM)
	var rows := int(ceil(float(cells.size()) / float(columns)))
	var extent := Vector2(float(columns) * spacing.x, float(rows) * spacing.y)
	var slab := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = extent + Vector2(4, 4)
	slab.mesh = plane
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color("5d6b52")
	ground.roughness = 1.0
	slab.material_override = ground
	slab.position = Vector3(extent.x * .5 - spacing.x * .5, -.01, extent.y * .5 - spacing.y * .5)
	world.add_child(slab)
	var roots: Array = []
	for index in range(cells.size()):
		var cell: Dictionary = cells[index]
		var root := Landmarks.instantiate(str(cell.kind), str(cell.family), int(cell.variant), body_material, glow_material)
		if root == null:
			report.notes.append("missing %s" % cell.kind)
			continue
		root.position = Vector3(float(index % columns) * spacing.x, 0, float(index / columns) * spacing.y)
		world.add_child(root)
		roots.append(root)
		var label := Label3D.new()
		label.text = str(cell.label)
		label.font_size = 40
		label.pixel_size = .012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = root.position + Vector3(0, -.05, spacing.y * .48)
		world.add_child(label)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.25
	world.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("18212b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a9bccf")
	environment.environment.ambient_light_energy = .55
	world.add_child(environment)
	return {"world": world, "roots": roots, "extent": extent, "glow": glow_material}

func _landmark_camera(world: Node3D, center: Vector3, orthogonal_size: float) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = orthogonal_size
	camera.position = center + Vector3(9.2, 14.2, 8.8) * (orthogonal_size / 13.2) * .6
	world.add_child(camera)
	camera.look_at(center, Vector3.UP)
	camera.current = true
	return camera

func _run_landmarks(group: String) -> void:
	var cells: Array = []
	var columns := 5
	var spacing := Vector2(3.6, 3.4)
	var zoom_size := 13.0
	if group == "small":
		for family in ["FOREST", "ASH", "FROST"]:
			for kind in Landmarks.SMALL_KINDS:
				cells.append({"kind": kind, "variant": 0, "family": family, "label": "%s %s" % [kind, family]})
	elif group.begins_with("one:"):
		var chapter := int(group.substr(4))
		var spec := Landmarks.boss_spec(chapter)
		columns = 1
		spacing = Vector2(6.0, 6.0)
		zoom_size = 8.0
		cells.append({"kind": spec.kind, "variant": spec.variant, "family": RegionFloor.FAMILY_BY_CHAPTER[chapter], "label": "CH%02d %s" % [chapter, spec.kind]})
	else:
		var first := 1 if group == "boss_a" else 11
		spacing = Vector2(5.8, 5.6)
		zoom_size = 30.0
		for chapter in range(first, first + 10):
			var spec := Landmarks.boss_spec(chapter)
			cells.append({"kind": spec.kind, "variant": spec.variant, "family": RegionFloor.FAMILY_BY_CHAPTER[chapter], "label": "CH%02d %s/%d" % [chapter, spec.kind, spec.variant]})
	var stage := _landmark_stage(cells, columns, spacing)
	var extent: Vector2 = stage.extent
	var center := Vector3(extent.x * .5 - spacing.x * .5, 1.0, extent.y * .5 - spacing.y * .5)
	_landmark_camera(stage.world, center, zoom_size)
	var clock := 1.3
	for root in stage.roots: Landmarks.animate(root, clock)
	(stage.glow as StandardMaterial3D).emission_energy_multiplier = Landmarks.flicker(clock)
	await _frames(6)
	_save("81_landmarks_%s" % group.replace(":", "_"))
	report.notes.append("cells=%d triangles=%d" % [cells.size(), _sum_triangles(cells)])
	_finish("PHASE4_LANDMARK_CAPTURE")

func _sum_triangles(cells: Array) -> int:
	var total := 0
	for cell in cells: total += int(Landmarks.build(str(cell.kind), str(cell.family), int(cell.variant)).triangles)
	return total
