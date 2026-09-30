extends Node

## Phase 4 / A2 (2026-09-30): the procedural landmarks on the live chapter 1
## map. Each node kind gets its landmark, treasures and relays keep the metas
## the screen reads, the ruin arch that used to render nothing now exists, and
## everything shares the terrain's material.

const Landmarks := preload("res://chapter_map/view/landmark_builder.gd")
const ChapterMapScreenScript := preload("res://chapter_map/runtime/chapter_map_screen.gd")

var checks := 0
var failures := 0
var reference_roots := 0
var reference_children := 0

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("%s %s" % [label, detail])

func _ready() -> void:
	AppState.new_game()
	_animation()
	await _live_map(true)
	await _live_map(false)
	await _deferred_map()
	print("LANDMARK_MAP_TESTS total=%d pass=%d fail=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _animation() -> void:
	var body := Landmarks.body_material()
	var glow := Landmarks.glow_material(Landmarks.LAMP_WARM)
	var root := Landmarks.instantiate("camp", "FOREST", 0, body, glow)
	check(root != null and root.get_child_count() >= 6, "a camp instances body, glow, a flag and smoke puffs", str(root.get_child_count() if root != null else -1))
	var animated: Array = root.get_meta("animated")
	var flags := animated.filter(func(entry): return entry.type == "flag")
	var puffs := animated.filter(func(entry): return entry.type == "smoke")
	check(flags.size() == 1 and puffs.size() == Landmarks.PUFFS_PER_SMOKE, "the camp has one waving flag and one smoke column")
	var flag: Node3D = flags[0].node
	Landmarks.animate(root, 0.4)
	var first_yaw := flag.rotation.y
	Landmarks.animate(root, 1.1)
	check(not is_equal_approx(first_yaw, flag.rotation.y) and absf(flag.rotation.y) <= Landmarks.FLAG_WAVE_SWING + .001, "the flag waves within its swing", "%s %s" % [first_yaw, flag.rotation.y])
	var rise := true
	var bounded := true
	for step in range(0, 40):
		Landmarks.animate(root, float(step) * .17)
		for entry in puffs:
			var puff: Node3D = entry.node
			var origin: Vector3 = entry.origin
			if puff.position.y < origin.y - .001 or puff.position.y > origin.y + Landmarks.PUFF_RISE + .001: rise = false
			if puff.scale.x < .04 or puff.scale.x > .4: bounded = false
	check(rise and bounded, "smoke puffs rise by a bounded height and stay small")
	var swing := 0.0
	for index in range(200): swing = maxf(swing, absf(Landmarks.flicker(float(index) * .05) - 1.25))
	check(swing <= .40 + .001 and Landmarks.flicker(0.0) > .8, "lamp flicker swings at most 0.4 around its mean", str(swing))
	root.free()
	Landmarks.animate(null, 1.0)
	check(true, "animating nothing is harmless")

func _landmark_kind_of(holder: Node) -> String:
	for child in holder.get_children():
		if str(child.name).begins_with("ProcLandmark_"): return str(child.name).trim_prefix("ProcLandmark_")
	return ""

## The web path: roots are placed during the entry, the meshes are built afterwards,
## nearest to the camera first, and the result equals the immediate fill.
func _deferred_map() -> void:
	AppState.selected_stage_id = "CH01-N01"
	AppState.profile["tutorial_progress"] = {"map_basics_revision": 99, "map_basics_complete": true}
	var screen = ChapterMapScreenScript.new()
	screen.landmark_force_defer = true
	screen.landmark_fill_budget_usec = 1
	screen.map_id = AppState.map_id_for_stage("CH01-N01")
	screen.size = Vector2(1600, 800)
	add_child(screen)
	for frame in 1200:
		await get_tree().process_frame
		if bool(screen.map_ready_complete): break
	check(bool(screen.map_ready_complete), "the chapter 1 map loads (deferred landmark fill)")
	if not bool(screen.map_ready_complete):
		screen.queue_free()
		return
	screen.set_process(false)
	var total: int = screen.landmark_roots.size()
	var empty := 0
	for root in screen.landmark_roots:
		if not (root as Node3D).has_meta("animated"): empty += 1
	check(total == reference_roots and total > 40, "deferring places the same landmark roots", "%d vs %d" % [total, reference_roots])
	check(empty >= total - 4 and screen.landmark_fill_queue.size() == empty, "the roots are placed empty and queued for filling", "%d empty, %d queued of %d" % [empty, screen.landmark_fill_queue.size(), total])
	var focus: Vector3 = screen.camera_target
	var nearest_distance := INF
	var nearest_root: Node3D = null
	for entry in screen.landmark_fill_queue:
		var candidate: Node3D = entry.root
		var distance := candidate.global_position.distance_squared_to(focus)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_root = candidate
	var queued_before: int = screen.landmark_fill_queue.size()
	screen._drain_landmark_fill_queue(1)
	check(screen.landmark_fill_queue.size() == queued_before - 1 and nearest_root != null and nearest_root.has_meta("animated"), "a one-microsecond budget still fills one landmark, the nearest to the camera")
	screen.flush_landmark_fill_queue()
	check(screen.landmark_fill_queue.is_empty(), "flushing empties the queue")
	var children := 0
	var unfilled := 0
	for root in screen.landmark_roots:
		children += (root as Node3D).get_child_count()
		if not (root as Node3D).has_meta("animated"): unfilled += 1
	check(unfilled == 0 and children == reference_children, "a deferred map ends with exactly the immediate map's landmark nodes", "%d vs %d, %d unfilled" % [children, reference_children, unfilled])
	var boss_spec := Landmarks.boss_spec(1)
	var boss_fits := false
	for root in screen.landmark_roots:
		if str(root.get_meta("landmark_kind", "")) == str(boss_spec.kind):
			var expected := clampf(screen.LANDMARK_BOSS_HEIGHT / maxf(float(root.get_meta("landmark_height")), .1), .5, 1.0)
			boss_fits = is_equal_approx((root as Node3D).scale.x, expected)
	check(boss_fits, "the boss landmark is scaled to its target height once it is built")
	var extra := Landmarks.create_root("camp", "FOREST", 0)
	check(not extra.has_meta("animated") and extra.get_child_count() == 0, "a fresh landmark root is empty")
	check(Landmarks.populate(extra, Landmarks.body_material(), Landmarks.glow_material(Landmarks.LAMP_WARM)) and extra.has_meta("animated"), "populating fills it")
	check(not Landmarks.populate(extra, Landmarks.body_material(), Landmarks.glow_material(Landmarks.LAMP_WARM)), "a filled root is never filled twice")
	extra.free()
	screen.queue_free()
	await get_tree().process_frame

func _live_map(enabled: bool) -> void:
	AppState.selected_stage_id = "CH01-N01"
	AppState.profile["tutorial_progress"] = {"map_basics_revision": 99, "map_basics_complete": true}
	var screen = ChapterMapScreenScript.new()
	screen.landmarks_enabled = enabled
	screen.map_id = AppState.map_id_for_stage("CH01-N01")
	screen.size = Vector2(1600, 800)
	add_child(screen)
	for frame in 1200:
		await get_tree().process_frame
		if bool(screen.map_ready_complete): break
	var tag := "landmarks on" if enabled else "landmarks off"
	check(bool(screen.map_ready_complete), "the chapter 1 map loads (%s)" % tag)
	if not bool(screen.map_ready_complete):
		screen.queue_free()
		return
	var definition: Dictionary = screen.definition
	if not enabled:
		check(screen.landmark_roots.is_empty(), "with landmarks off nothing procedural is added")
		var plain := 0
		for treasure_id in screen.treasure_visuals:
			var treasure_root: Node3D = screen.treasure_visuals[treasure_id]
			if treasure_root.has_meta("lid") and _landmark_kind_of(treasure_root) == "": plain += 1
		check(plain == screen.treasure_visuals.size() and plain > 0, "the plain crate and lid return when landmarks are off", "%d/%d" % [plain, screen.treasure_visuals.size()])
		screen.queue_free()
		await get_tree().process_frame
		return
	check(screen.landmark_roots.size() > 40, "the map instances many landmarks", str(screen.landmark_roots.size()))
	check(screen.landmark_fill_queue.is_empty(), "outside the web landmarks are filled at once, nothing is queued")
	reference_roots = screen.landmark_roots.size()
	for root in screen.landmark_roots:
		reference_children += (root as Node3D).get_child_count()
	# Every encounter marker carries exactly the landmark its node kind calls for.
	var by_kind := {}
	var wrong: Array = []
	var boss_spec := Landmarks.boss_spec(1)
	for node in definition.nodes:
		var marker: Node3D = screen.node_markers.get(str(node.node_id))
		if marker == null: continue
		var kinds: Array = []
		for child in marker.get_children():
			if str(child.name).begins_with("ProcLandmark_"): kinds.append(str(child.name).trim_prefix("ProcLandmark_"))
		var node_type := str(node.get("node_type", ""))
		var expected := "camp" if node_type == "START" else (str(boss_spec.kind) if node_type.contains("BOSS") else ("tent" if node_type.contains("ELITE") else "barricade"))
		var stage_id := str(node.get("stage_id", ""))
		var extra := ""
		if stage_id.ends_with("N03") or stage_id.ends_with("N07") or stage_id.ends_with("N10") or stage_id.ends_with("N15"): extra = "tower"
		elif stage_id.ends_with("H05") or stage_id.ends_with("H10"): extra = "beacon"
		if node_type.contains("BOSS"): extra = ""
		var want: Array = [expected]
		if extra != "": want.append(extra)
		kinds.sort()
		want.sort()
		if kinds != want: wrong.append("%s %s got=%s want=%s" % [node.node_id, node_type, kinds, want])
		by_kind[expected] = int(by_kind.get(expected, 0)) + 1
	check(wrong.is_empty(), "every encounter marker has the landmark its node kind calls for", JSON.stringify(wrong.slice(0, 6)))
	check(by_kind.has("camp") and by_kind.has("barricade") and by_kind.has("tent") and by_kind.has(str(boss_spec.kind)), "the map has a camp, barricades, tents and its boss landmark", JSON.stringify(by_kind))
	# Nothing the screen reads by name was disturbed.
	var symbols_fine := true
	for marker_id in screen.node_markers:
		for child in screen.node_markers[marker_id].get_children():
			if str(child.name).begins_with("ProcLandmark_") and (str(child.name).contains("SYMBOL") or str(child.name).contains("FallbackMarker")): symbols_fine = false
	check(symbols_fine, "landmark names stay clear of the marker-state material overrides")
	# Treasures: the crate stack is the revealed visual, the ring and seal remain.
	var crates := 0
	for treasure_id in screen.treasure_visuals:
		var treasure_root: Node3D = screen.treasure_visuals[treasure_id]
		var crate = treasure_root.get_meta("crate")
		if crate is Node3D and str((crate as Node3D).name) == "ProcLandmark_crate": crates += 1
		check(treasure_root.has_meta("glow") and treasure_root.has_meta("seal") and not treasure_root.has_meta("lid"), "treasure %s keeps its glow and seal metas" % treasure_id)
	check(crates == screen.treasure_visuals.size() and crates > 0, "every treasure shows the procedural supply crate", "%d/%d" % [crates, screen.treasure_visuals.size()])
	# Relays: a signal tower with the ring and label still wired.
	var towers := 0
	for relay_id in screen.relay_visuals:
		var relay_root: Node3D = screen.relay_visuals[relay_id]
		if _landmark_kind_of(relay_root) == "tower": towers += 1
		check(relay_root.get_meta("signal") is MeshInstance3D and relay_root.get_meta("label") is Label3D, "relay %s keeps its signal ring and label" % relay_id)
	check(towers == screen.relay_visuals.size() and towers > 0, "every relay is a signal tower", "%d/%d" % [towers, screen.relay_visuals.size()])
	# Map landmarks: the ruin arch has no kit mesh and used to render nothing.
	var arches := 0
	var arch_props := 0
	for landmark in definition.landmarks:
		var holder: Node3D = screen.landmark_visuals.get(str(landmark.landmark_id))
		if str(landmark.get("prop", "")) == "PROP_RUIN_ARCH":
			arch_props += 1
			if holder != null and _landmark_kind_of(holder) == "arch": arches += 1
	check(arch_props > 0 and arches == arch_props, "the ruin arch landmarks are built procedurally", "%d/%d" % [arches, arch_props])
	# Shared materials: one body material, a handful of emissive ones.
	check(screen.landmark_glow_materials.size() >= 1 and screen.landmark_glow_materials.size() <= 4, "landmarks share a handful of emissive materials", str(screen.landmark_glow_materials.size()))
	var body_materials := {}
	for root in screen.landmark_roots:
		var body := (root as Node3D).get_node_or_null("Body") as MeshInstance3D
		if body != null: body_materials[body.material_override] = true
	var shared_material = screen.terrain_material if screen.terrain_material != null else screen._landmark_body_material()
	check(body_materials.size() == 1 and body_materials.keys()[0] == shared_material and (shared_material as StandardMaterial3D).vertex_color_use_as_albedo, "every landmark body shares one vertex-colour material, the terrain's when it exists")
	# Animation runs without touching state.
	var state_before: Dictionary = (screen.map_state as Dictionary).duplicate(true)
	screen._animate_landmarks()
	await get_tree().process_frame
	check(screen.map_state == state_before, "animating landmarks never changes map state")
	check(is_zero_approx(screen._landmark_ground_delta(Vector3.ZERO, Vector3.ZERO)), "a landmark on its own tile has no ground delta")
	var yaw: float = screen._landmark_yaw("a")
	check(yaw >= PI * .25 - .26 and yaw <= PI * .25 + .26 and yaw == screen._landmark_yaw("a"), "landmark yaw is stable and faces the camera within a spread")
	screen.queue_free()
	await get_tree().process_frame
