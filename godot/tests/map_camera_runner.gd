extends Node

## Phase 4 / A4 (2026-09-30): the chapter map's slightly tilted perspective
## camera and its event moments. The rig's math is pure; the live map must keep
## the old framing at the orbit target, keep picking exact, keep zoom, drag and
## follow, and return to its resting pose after every moment.

const Rig := preload("res://chapter_map/view/map_camera_rig.gd")
const ChapterMapScreenScript := preload("res://chapter_map/runtime/chapter_map_screen.gd")

var checks := 0
var failures := 0

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("%s %s" % [label, detail])

func _ready() -> void:
	AppState.new_game()
	_rig_math()
	_moments()
	await _live_map(true)
	await _live_map(false)
	print("MAP_CAMERA_TESTS total=%d pass=%d fail=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _rig_math() -> void:
	check(absf(Rig.pitch_degrees() - 48.1) < .3, "the camera keeps the old tilt of about 48 degrees", str(Rig.pitch_degrees()))
	check(Rig.fov_degrees() > 30.0 and Rig.fov_degrees() < 45.0, "the lens is a moderate perspective", str(Rig.fov_degrees()))
	check(is_equal_approx(Rig.distance_for_size(Rig.BASE_SIZE), Rig.base_distance()), "at zoom 1 the perspective camera sits exactly where the orthographic one did")
	check(Rig.offset(Rig.BASE_SIZE, 0.0, true).is_equal_approx(Rig.BASE_OFFSET) and Rig.offset(Rig.BASE_SIZE, 0.0, false).is_equal_approx(Rig.BASE_OFFSET), "both projections share one resting pose at zoom 1")
	check(Rig.distance_for_size(Rig.view_size(1.5)) < Rig.distance_for_size(Rig.view_size(1.0)) and Rig.distance_for_size(Rig.view_size(.72)) > Rig.distance_for_size(Rig.view_size(1.0)), "zoom dollies the camera in and out")
	check(is_equal_approx(Rig.offset(Rig.view_size(1.4), 0.0, false).length(), Rig.base_distance()), "the orthographic offset never changes with zoom")
	var direction_before := Rig.offset(Rig.view_size(1.0), 0.0, true).normalized()
	var direction_after := Rig.offset(Rig.view_size(1.5), 0.0, true).normalized()
	check(direction_before.is_equal_approx(direction_after), "dollying keeps the viewing direction (and so the tilt)")
	var yawed := Rig.offset(Rig.BASE_SIZE, .2, true)
	check(is_equal_approx(yawed.y, Rig.BASE_OFFSET.y) and is_equal_approx(yawed.length(), Rig.base_distance()) and not yawed.is_equal_approx(Rig.BASE_OFFSET), "an orbit turns the camera around the target at constant height and distance")

func _moments() -> void:
	check(Rig.MOMENTS.size() == 4 and Rig.is_moment("treasure") and Rig.is_moment("relay") and Rig.is_moment("event") and Rig.is_moment("impact") and not Rig.is_moment("nope"), "four moment kinds exist")
	for kind in Rig.MOMENTS:
		var duration := Rig.moment_duration(kind)
		check(duration >= .5 and duration <= 1.5, "%s moment is short" % kind, str(duration))
		var peak_zoom := 1.0
		var peak_yaw := 0.0
		var peak_shake := 0.0
		for step in range(0, 101):
			var state := Rig.moment(kind, duration * float(step) / 100.0 * .999)
			peak_zoom = maxf(peak_zoom, float(state.zoom))
			peak_yaw = maxf(peak_yaw, absf(float(state.yaw)))
			peak_shake = maxf(peak_shake, (state.shake as Vector3).length())
		var preset: Dictionary = Rig.MOMENTS[kind]
		check(absf(peak_zoom - float(preset.zoom)) < .01, "%s pushes in to its preset" % kind, "%s vs %s" % [peak_zoom, preset.zoom])
		check(peak_yaw <= absf(float(preset.orbit)) + .001 and peak_yaw >= absf(float(preset.orbit)) * .95, "%s orbit stays within its swing" % kind, str(peak_yaw))
		check(peak_shake <= float(preset.shake) * 1.75 + .001, "%s shake stays small" % kind, str(peak_shake))
		var end := Rig.moment(kind, duration)
		var start := Rig.moment(kind, 0.0)
		check(not bool(end.active) and is_equal_approx(float(end.zoom), 1.0) and is_zero_approx(float(end.yaw)) and (end.shake as Vector3) == Vector3.ZERO, "%s ends at rest" % kind)
		check(is_equal_approx(float(start.zoom), 1.0) and is_zero_approx(float(start.yaw)), "%s starts from rest" % kind)
		var smooth := true
		var last_zoom := 1.0
		for step in range(1, 200):
			var state := Rig.moment(kind, duration * float(step) / 200.0)
			if absf(float(state.zoom) - last_zoom) > .02: smooth = false
			last_zoom = float(state.zoom)
		check(smooth, "%s push-in changes smoothly frame to frame" % kind)
	check(not bool(Rig.moment("nope", .1).active) and not bool(Rig.moment("relay", -1.0).active), "an unknown kind or a negative time is inactive")

func _live_map(perspective: bool) -> void:
	AppState.selected_stage_id = "CH01-N01"
	AppState.profile["tutorial_progress"] = {"map_basics_revision": 99, "map_basics_complete": true}
	SettingsService.values["map_camera_perspective"] = perspective
	SettingsService.values["map_reduced_transition"] = false
	var screen = ChapterMapScreenScript.new()
	screen.map_id = AppState.map_id_for_stage("CH01-N01")
	screen.size = Vector2(1600, 800)
	add_child(screen)
	for frame in 1200:
		await get_tree().process_frame
		if bool(screen.map_ready_complete): break
	var tag := "perspective" if perspective else "orthographic"
	check(bool(screen.map_ready_complete), "the chapter 1 map loads (%s)" % tag)
	if not bool(screen.map_ready_complete):
		screen.queue_free()
		return
	await get_tree().process_frame
	var camera: Camera3D = screen.camera
	check(bool(screen.camera_perspective) == perspective and (camera.projection == Camera3D.PROJECTION_PERSPECTIVE) == perspective, "the %s projection is in use" % tag)
	var offset: Vector3 = camera.global_position - screen.camera_target
	var expected := Rig.offset(Rig.view_size(screen.camera_zoom), 0.0, perspective)
	check(offset.distance_to(expected) < .01, "the camera rests %s from its target" % ("on the dollied pose" if perspective else "on the fixed offset"), "%s vs %s" % [offset, expected])
	var viewport_size := Vector2(screen.viewport.size)
	var centre := camera.unproject_position(screen.camera_target)
	check(centre.distance_to(viewport_size * .5) < 2.0, "the orbit target stays at the centre of the picture", "%s in %s" % [centre, viewport_size])
	# Scale at the target plane equals the old orthographic scale.
	var right := camera.global_transform.basis.x.normalized()
	var metres := camera.unproject_position(screen.camera_target + right).distance_to(centre)
	var old_scale := viewport_size.y / Rig.view_size(screen.camera_zoom)
	check(absf(metres / old_scale - 1.0) < .03, "at the target the picture has the old orthographic scale", "%s vs %s" % [metres, old_scale])
	var overlay_scale: float = screen._screen_pixels_per_world(screen.camera_target)
	var expected_overlay := float(screen.overlay.size.y) / Rig.view_size(screen.camera_zoom)
	check(absf(overlay_scale / expected_overlay - 1.0) < .03, "pixels per world unit at the target match the overlay estimate", "%s vs %s" % [overlay_scale, expected_overlay])
	if perspective:
		var near_scale: float = screen._screen_pixels_per_world(screen.camera_target + (camera.global_position - screen.camera_target).normalized() * 6.0)
		var far_scale: float = screen._screen_pixels_per_world(screen.camera_target - (camera.global_position - screen.camera_target).normalized() * 6.0)
		check(near_scale > overlay_scale * 1.2 and far_scale < overlay_scale * .85, "nearer ground is larger and farther ground smaller", "%s < %s < %s" % [far_scale, overlay_scale, near_scale])
	# Picking stays exact: clicking a tile's own centre selects that tile.
	var party := Vector2i(int(screen.map_state.current_q), int(screen.map_state.current_r))
	var exact := 0
	var tried := 0
	var radius := int(screen._player_vision_radius())
	for delta in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, -2), Vector2i(2, -1), Vector2i(-2, 2), Vector2i(3, 0), Vector2i(0, 3)]:
		var coord: Vector2i = party + delta
		if not screen.grid.has(coord): continue
		var elevation := float(screen.grid.tile(coord).get("elevation", 0))
		var world: Vector3 = screen.HexCoordScript.axial_to_world(coord, screen.TILE_SIZE, elevation * screen.ELEVATION_STEP + .14)
		var screen_position := camera.unproject_position(world)
		if screen_position.x < 4 or screen_position.y < 4 or screen_position.x > viewport_size.x - 4 or screen_position.y > viewport_size.y - 4: continue
		tried += 1
		var picked: Dictionary = screen._pick_ground_coord_from_screen(screen_position, Vector2.ONE, party, radius)
		if picked.get("coord", Vector2i(-99999, -99999)) == coord: exact += 1
	check(tried >= 4 and exact == tried, "clicking a tile's centre picks that tile (%s)" % tag, "%d/%d" % [exact, tried])
	# Zoom moves the camera and the picture size together and is clamped as before.
	var zoom_before: float = screen.camera_zoom
	screen.camera_zoom = 1.4
	await get_tree().process_frame
	await get_tree().process_frame
	var zoomed_offset: Vector3 = camera.global_position - screen.camera_target
	check(zoomed_offset.distance_to(Rig.offset(Rig.view_size(1.4), 0.0, perspective)) < .01 and is_equal_approx(camera.size, Rig.view_size(1.4)), "zooming in re-poses the %s camera" % tag, str(zoomed_offset))
	if perspective: check(zoomed_offset.length() < expected.length() * .8, "zooming in dollies the camera closer")
	screen.camera_zoom = zoom_before
	await get_tree().process_frame
	await get_tree().process_frame
	# Follow: moving the target moves the camera by the same amount.
	var before_target: Vector3 = screen.camera_target
	var before_position: Vector3 = camera.global_position
	screen.camera_target = before_target + Vector3(3.0, 0.0, -2.0)
	await get_tree().process_frame
	await get_tree().process_frame
	check(((camera.global_position - before_position) - Vector3(3.0, 0.0, -2.0)).length() < .02, "the camera follows its target (%s)" % tag)
	screen.camera_target = before_target
	await get_tree().process_frame
	# Moments: a relay moment orbits and pushes in, then returns to rest exactly.
	SettingsService.values["map_reduced_transition"] = true
	check(not screen.play_camera_moment("relay", screen.camera_target), "a moment is skipped under reduced motion")
	SettingsService.values["map_reduced_transition"] = false
	check(not screen.play_camera_moment("nope"), "an unknown moment does not start")
	var state_before: Dictionary = (screen.map_state as Dictionary).duplicate(true)
	check(screen.play_camera_moment("relay", screen.camera_target + Vector3(1.0, 0.0, 0.5)), "a relay moment starts")
	var saw_push := false
	var saw_orbit := false
	var elapsed := 0.0
	while elapsed < Rig.moment_duration("relay") + .3:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if camera.size < Rig.view_size(screen.camera_zoom) - .05: saw_push = true
		var flat := Vector2(camera.global_position.x - screen.camera_target.x, camera.global_position.z - screen.camera_target.z)
		var resting := Vector2(expected.x, expected.z)
		if absf(flat.angle_to(resting)) > .03: saw_orbit = true
	check(saw_push and saw_orbit, "the moment pushes in and orbits while it plays (%s)" % tag)
	await get_tree().process_frame
	await get_tree().process_frame
	var settled: Vector3 = camera.global_position - screen.camera_target
	check(screen.camera_moment_kind.is_empty() and settled.distance_to(expected) < .02 and is_equal_approx(camera.size, Rig.view_size(screen.camera_zoom)), "the camera is back at rest after the moment (%s)" % tag, "%s vs %s" % [settled, expected])
	check(screen.map_state == state_before, "a camera moment never changes map state")
	# A moment is dropped when the party starts to walk.
	screen.play_camera_moment("event", screen.camera_target)
	screen.moving = true
	await get_tree().process_frame
	screen.moving = false
	check(screen.camera_moment_kind.is_empty(), "a moment ends as soon as the party walks")
	SettingsService.values["map_camera_perspective"] = true
	screen.queue_free()
	await get_tree().process_frame
