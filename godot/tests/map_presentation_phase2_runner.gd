extends Node

## Phase 2 map presentation (2026-09-30): region surface looks, the marker /
## route / rim / dust overlay, the party hop, the encounter wipe and the map UI
## cleanup (bottom action bar, notice toast, exploration gauge, collapsible
## minimap). Everything checked here is presentation; map state is compared
## before and after to prove it.

const ChapterMapScreenScript := preload("res://chapter_map/runtime/chapter_map_screen.gd")
const OverlayScript := preload("res://chapter_map/ui/map_presentation_overlay.gd")
const RegionPalette := preload("res://chapter_map/view/region_palette.gd")
const EncounterWipe := preload("res://ui/encounter_wipe.gd")
const AppShellScript := preload("res://screens/app_shell.gd")

var checks := 0
var failures := 0

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("%s %s" % [label, detail])

func _ready() -> void:
	AppState.new_game()
	_surface_looks()
	_overlay()
	_hop()
	await _encounter_wipe()
	_sources()
	await _live_map()
	print("MAP_PRESENTATION_PHASE2_TESTS total=%d pass=%d fail=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _surface_looks() -> void:
	var forest := RegionPalette.surface_look({"visual_set_id": "CH01_FOREST_SIGNAL"})
	var frost := RegionPalette.surface_look({"visual_set_id": "CH05_FROST_LINE"})
	var keys_ok := true
	for key in ["ground", "patch", "patch_amount", "wear", "lip", "haze"]:
		keys_ok = keys_ok and forest.has(key) and frost.has(key)
	check(keys_ok, "every region look carries patch, wear, lip and haze values")
	check((forest.patch as Color).g > (forest.patch as Color).r and (frost.patch as Color).v > .8, "forest patches are moss, frost patches are snow", "%s %s" % [forest.patch, frost.patch])
	var ground: Color = RegionPalette.for_definition({"visual_set_id": "CH01_FOREST_SIGNAL"}).ground
	check((forest.ground as Color).is_equal_approx(ground.lightened(.10)), "the shader's ground match uses the same tint as the terrain vertex colour")

func _overlay() -> void:
	var overlay := OverlayScript.new()
	overlay.projector = func(world: Vector3) -> Vector2: return Vector2(world.x * 10.0, world.z * 10.0)
	overlay.set_route([Vector3.ZERO, Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)], 2, Color.CYAN)
	check(int(overlay.snapshot().route) == 4 and int(overlay.snapshot().reach) == 2, "the route keeps every cell and this turn's reach")
	overlay.set_rim([[Vector3.ZERO, Vector3(1, 0, 0)]], Vector3.ZERO)
	check(int(overlay.snapshot().rim) == 1, "the move range rim is handed to the overlay")
	overlay.spawn_dust(Vector3.ZERO, 1.0)
	overlay._process(.2)
	check(int(overlay.snapshot().dust) == 1, "landing dust lives for its short puff")
	overlay._process(OverlayScript.DUST_DURATION)
	check(int(overlay.snapshot().dust) == 0, "landing dust is recycled")
	overlay.markers = [{"kind": "BOSS", "world": Vector3.ZERO}]
	overlay.extra_markers = [{"kind": "TREASURE", "world": Vector3.ONE}]
	check(overlay.snapshot().markers == ["BOSS"], "the snapshot lists synced markers only")
	overlay.set_route([], 0, Color.CYAN)
	check(int(overlay.snapshot().route) == 0, "clearing the route empties it")
	overlay.free()

func _hop() -> void:
	var screen := ChapterMapScreenScript.new()
	screen._set_pawn_hop(0.0, .4)
	var start := screen.pawn_hop_offset
	screen._set_pawn_hop(.5, .4)
	var peak := screen.pawn_hop_offset
	screen._set_pawn_hop(1.0, .4)
	check(is_zero_approx(start) and is_equal_approx(peak, .4) and is_zero_approx(screen.pawn_hop_offset), "the hop is a parabola that peaks at its height and lands at zero", "%s %s %s" % [start, peak, screen.pawn_hop_offset])
	var level_hop: float = ChapterMapScreenScript.PAWN_HOP_BASE + ChapterMapScreenScript.PAWN_HOP_PER_LEVEL
	check(level_hop > ChapterMapScreenScript.PAWN_HOP_BASE * 3.0, "a terrace change jumps well above the flat-ground bob")
	screen.free()

func _encounter_wipe() -> void:
	var stage := DataRegistry.stage("CH01-N01")
	var data: Dictionary = AppShellScript.encounter_wipe_data(stage, "정찰", "적군 조우")
	check((data.waves as Array).size() == mini(4, (stage.get("waves", []) as Array).size()) and str(data.level_line).begins_with("권장 Lv.%d" % int(stage.get("recommended_level", 1))), "the info panel lists each wave and the recommended level", JSON.stringify(data))
	var named := true
	for line in data.waves:
		named = named and str(line).begins_with("웨이브 ") and not str(line).contains("ENM")
	check(named, "wave lines use enemy names, never database ids", JSON.stringify(data.waves))
	var wipe := EncounterWipe.new()
	add_child(wipe)
	wipe.configure(data, .5)
	var finished_count := [0]
	wipe.finished.connect(func(): finished_count[0] += 1)
	var early := InputEventMouseButton.new()
	early.pressed = true
	wipe._gui_input(early)
	check(wipe.elapsed < wipe.duration, "an early tap cannot skip before the panel is in")
	for index in range(60):
		await get_tree().process_frame
		if finished_count[0] > 0: break
	await get_tree().create_timer(.6).timeout
	check(finished_count[0] == 1 and bool(wipe.snapshot().done), "the wipe finishes exactly once", str(finished_count[0]))
	var skip := EncounterWipe.new()
	add_child(skip)
	skip.configure(data, 5.0)
	skip.elapsed = EncounterWipe.PANEL_IN + .2
	skip._gui_input(early)
	check(is_equal_approx(skip.elapsed, skip.duration), "a tap after the panel lands skips to the battle")
	wipe.queue_free()
	skip.queue_free()

func _sources() -> void:
	var map_source := FileAccess.get_file_as_string("res://chapter_map/runtime/chapter_map_screen.gd").replace("\r\n", "\n")
	check(map_source.find("presentation_layer.add_child(atmosphere_overlay)") < map_source.find("presentation_layer.add_child(fog_screen_overlay)") and map_source.contains("presentation_layer.add_child(atmosphere_overlay)"), "the atmosphere pass reads the screen before the fog overlay")
	var shader := FileAccess.get_file_as_string("res://chapter_map/shaders/terrain_surface.gdshader")
	check(shader.contains("float hex_edge(") and shader.contains("uniform vec4 patch_color") and not shader.contains("patch_color : source_color"), "terrain shader has hex-edge wear and raw region colours")
	var shell_source := FileAccess.get_file_as_string("res://screens/app_shell.gd").replace("\r\n", "\n")
	check(shell_source.contains("if special_event.is_empty() and not reduced:") and shell_source.contains("await wipe.finished"), "regular encounters play the wipe; reduced transitions and events keep their paths")

func _live_map() -> void:
	AppState.selected_stage_id = "CH01-N01"
	AppState.profile["tutorial_progress"] = {"map_basics_revision": 99, "map_basics_complete": true}
	var screen = ChapterMapScreenScript.new()
	screen.map_id = AppState.map_id_for_stage("CH01-N01")
	screen.size = Vector2(1600, 800)
	add_child(screen)
	for frame in 1200:
		await get_tree().process_frame
		if bool(screen.map_ready_complete): break
	check(bool(screen.map_ready_complete), "the chapter 1 map finishes loading")
	if not bool(screen.map_ready_complete):
		screen.queue_free()
		return
	await get_tree().process_frame
	var before: Dictionary = (screen.map_state as Dictionary).duplicate(true)
	var snapshot: Dictionary = screen.presentation_phase2_snapshot()
	var compact: bool = screen._runtime_layout_size().y > screen._runtime_layout_size().x or screen._runtime_layout_size().x <= 980.0
	var root: Node = screen.toolbar.get_parent()
	check(int(snapshot.toolbar_index) == (0 if compact else root.get_child_count() - 1), "desktop actions sit in a bottom bar, compact keeps the top rail", "compact=%s index=%d" % [compact, int(snapshot.toolbar_index)])
	var completion: Dictionary = MapExplorationService.completion(screen.map_state, screen.definition)
	check(int(snapshot.gauge) == int(completion.get("percent", 0)) and not str(snapshot.status).contains("탐험"), "the exploration percent moved from the status line to its gauge")
	var status_before := str(screen.status_label.text)
	screen._show_map_notice("시험 알림")
	screen._update_map_notice_toast()
	snapshot = screen.presentation_phase2_snapshot()
	check(bool(snapshot.toast_visible) and str(snapshot.toast_text) == "시험 알림" and str(screen.status_label.text) == status_before, "a notice is a toast; the status line keeps its readout")
	screen.map_notice_until_msec = Time.get_ticks_msec() - 1
	screen._update_map_notice_toast()
	check(not screen.map_notice_toast.visible, "the toast hides after its deadline")
	screen._toggle_minimap()
	check(bool(screen.minimap_collapsed) and not screen.route_minimap.visible and screen.minimap_toggle.text.contains("미니맵"), "the minimap collapses to a tab")
	screen._toggle_minimap()
	check(not bool(screen.minimap_collapsed) and screen.route_minimap.visible, "the minimap expands again")
	check(int(screen.map_fx_overlay.snapshot().rim) > 0, "the move range rim reaches the overlay", JSON.stringify(screen.map_fx_overlay.snapshot()))
	screen._select_next_encounter()
	await get_tree().process_frame
	var fx: Dictionary = screen.map_fx_overlay.snapshot()
	check(int(fx.route) == (screen.preview_path as Array).size() and int(fx.route) >= 2, "the route preview reaches the overlay", JSON.stringify(fx))
	screen._clear_selection()
	await get_tree().process_frame
	check(int(screen.map_fx_overlay.snapshot().route) == 0, "clearing the selection clears the dotted route")
	var zoom_before: float = screen.camera_zoom
	screen.play_encounter_push_in(.1)
	await get_tree().create_timer(.2).timeout
	check(screen.camera_zoom > zoom_before * 1.3, "the encounter push-in closes the camera", "%s -> %s" % [zoom_before, screen.camera_zoom])
	await get_tree().create_timer(.9).timeout
	check(is_equal_approx(screen.camera_zoom, zoom_before), "the saved zoom returns after the push-in")
	var after: Dictionary = screen.map_state
	var same := true
	for key in ["current_q", "current_r", "movement_points", "turn", "camera_zoom"]:
		same = same and str(before.get(key, "")) == str(after.get(key, ""))
	check(same, "presentation never changes the map state", "%s / %s" % [JSON.stringify(before.get("movement_points")), JSON.stringify(after.get("movement_points"))])
	screen.queue_free()
	await get_tree().process_frame
