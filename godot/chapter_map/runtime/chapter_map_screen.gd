class_name ChapterMapScreen
extends Control

signal battle_requested(stage_id: String)
signal formation_requested
signal fallback_requested
signal sweep_requested(stage_id: String, count: int)
signal treasure_reward_requested(report: Dictionary)
signal map_ready
# Stage entry is a real preload boundary on Web.  The shell can keep its loader
# paintable from this signal without ever presenting an interactive map whose
# later movement will synchronously construct resources.
signal map_load_progress(value: float, phase: String)

const DEFAULT_MAP_ID := "CH01_MAP"
const TILE_SIZE := 1.08
const ELEVATION_STEP := 0.86
const VIEWPORT_SIZE := Vector2i(1280, 720)
# The panel-aware orthographic framing can expose almost eighteen axial cells
# along its long diagonal.  A radius of fourteen still showed the edge of the
# streamed terrain when the camera offset a HARD encounter away from the side
# panel, making a valid marker read as if it floated over the ocean.  Twenty
# retains a bounded slice of the 96-hex world while covering the full visible
# neighbourhood at every supported zoom and aspect ratio.
# Gameplay sight is squad-centred, never camera-centred. A fresh squad clears
# eight rings. Each permanent +1 movement-capacity gain clears one extra ring,
# up to thirteen at the global eight-step movement cap. The same live radius
# gates fog, enemies, loot, route previews, camera panning and click targets.
const BASE_PLAYER_VISION_RADIUS := 8
const MAX_PLAYER_VISION_RADIUS := 13
const FOG_COVER_RADIUS := 20
const STREAM_RADIUS := MAX_PLAYER_VISION_RADIUS + 1
const WEB_STREAM_PREFETCH_MARGIN := 4
const WEB_STREAM_BUILD_BATCH := 24
# SurfaceTool commits and MultiMesh uploads are both synchronous on WebGL. Keep
# each frame's upload bounded, while retaining only one persistent MultiMesh draw
# per prop family after construction.
const WEB_INFILL_TILE_BATCH := 16
const WEB_DRESSING_TRANSFORM_SLICE := 24
# Entry builds cover the entire campaign map once.  They deliberately use
# larger *spatial* chunks than the small fallback stream, keeping a 3,600-tile
# map under the five-second target without making every later movement frame
# submit a world-sized mesh or MultiMesh.
const WEB_ENTRY_TERRAIN_TILE_BATCH := 72
const WEB_ENTRY_TERRAIN_CHUNK_SPAN := 12
const WEB_ENTRY_DRESSING_CHUNK_SPAN := 14
const WEB_ENTRY_DRESSING_TRANSFORM_SLICE := 128
const WEB_ENTRY_SLICE_BUDGET_USEC := 10000
const OCEAN_SURFACE_Y := -1.55
const CAMERA_TERRAIN_MARGIN := 2.8
const CAMERA_TERRAIN_SEARCH_RADIUS := 16
const PAWN_VISUAL_BASE_Y := 0.18
const PAWN_STEP_DURATION := 0.28
const PAWN_CAMERA_SETTLE_DURATION := 0.20
const PAWN_ARRIVE_HOLD_DURATION := 0.16
const WEB_LAYOUT_PROBE_INTERVAL_MSEC := 250
const DIRECT_DOUBLE_CLICK_WINDOW_MSEC := 460
const MAP_TUTORIAL_REVISION := 2
# A moving patrol may leave its authored node while the squad is walking toward
# it.  Re-route a bounded number of times so contact still happens at the live
# enemy coordinate, without ever turning a node click into an instant battle.
const MAX_LIVE_ENCOUNTER_REPLANS := 3
const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const HexGridScript := preload("res://chapter_map/model/hex_grid.gd")
const HexPathfinderScript := preload("res://chapter_map/model/hex_pathfinder.gd")
const ChapterMapLoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const ChapterMapProgressScript := preload("res://chapter_map/model/chapter_map_progress.gd")
const ChapterRouteMinimapScript := preload("res://chapter_map/ui/chapter_route_minimap.gd")
const MapExplorationServiceScript := preload("res://chapter_map/model/map_exploration_service.gd")
const MapSimulationScript := preload("res://chapter_map/model/map_simulation.gd")
const MacroWorldGeneratorScript := preload("res://chapter_map/model/macro_world_generator.gd")
const EnvironmentFXControllerScript := preload("res://chapter_map/presentation/environment_fx_controller.gd")
const WebMovementOverlayScript := preload("res://chapter_map/runtime/web_movement_overlay.gd")
const EnvironmentWaterShader := preload("res://chapter_map/shaders/water_environment.gdshader")
const FogOfWarShader := preload("res://chapter_map/shaders/fog_of_war.gdshader")
const FogOfWarScreenShader := preload("res://chapter_map/shaders/fog_of_war_screen.gdshader")
const GameUI := preload("res://ui/game_ui_tokens.gd")

var definition: Dictionary
var grid = HexGridScript.new()
var map_state: Dictionary
var viewport: SubViewport
var viewport_container: SubViewportContainer
var presentation_layer: Control
var fog_screen_overlay: ColorRect
var fog_screen_material: ShaderMaterial
var overlay: Control
var map_area: Control
var map_frame: PanelContainer
var camera: Camera3D
var camera_target := Vector3.ZERO
var camera_zoom := 1.0
var world_root: Node3D
var pawn: Node3D
var pawn_visual: Node3D
var pawn_grounding_terrace: MeshInstance3D
var pawn_banner: MeshInstance3D
var pawn_sprite: Sprite3D
var pawn_occlusion_silhouette: Sprite3D
var pawn_front_overlay: TextureRect
var pawn_animation_pack: Dictionary = {}
var pawn_motion_state := "IDLE"
var pawn_motion_epoch_msec := 0
var pawn_motion_phase := 0.0
var pawn_last_atlas_frame := -1
var pawn_last_position := Vector3.ZERO
var pawn_facing_right := true
var node_buttons: Dictionary = {}
var node_markers: Dictionary = {}
var enemy_pawns: Dictionary = {}
var enemy_animation_packs: Dictionary = {}
var treasure_visuals: Dictionary = {}
var relay_visuals: Dictionary = {}
var event_visuals: Dictionary = {}
var landmark_visuals: Dictionary = {}
var tile_meshes: Dictionary = {}
var tile_dressing_roots: Dictionary = {}
var active_dressing_root: Node3D
var pending_dressing_tiles: Array[Dictionary] = []
# Browser builds use the single streamed infill mesh as their terrain authority.
# Keep the live keys separately so UI/encounter visibility never needs hundreds
# of one-MeshInstance hex caps just to answer a ground-presence query.
var streamed_ground_keys: Dictionary = {}
var pending_dressing_keys: Dictionary = {}
var web_detail_assets_ready := true
var web_detail_build_started := false
var web_detail_build_complete := false
var web_stage_entry_preload_active := false
var web_content_build_active := false
var web_enemy_stream_active := false
var web_stage_entry_preload_complete := false
## Authoritative shell-facing completion state.  Signals are edge notifications;
## this level state lets the owner enforce a real deadline without risking a
## missed `map_ready` edge between frames.
var map_ready_complete := false
var web_entry_last_yield_usec := 0
var terrain_surface: MeshInstance3D
var terrain_material: StandardMaterial3D
var terrain_cap_material_cache: Dictionary = {}
var runtime_material_cache: Dictionary = {}
var movement_overlay_material_cache: Dictionary = {}
var route_overlay_material_cache: Dictionary = {}
var node_style_cache: Dictionary = {}
var responsive_layout_signature := ""
var path_reveal_cache_signature := ""
var path_reveal_cache: Dictionary = {}
var fog_of_war_material: ShaderMaterial
var fog_cover_instance: MeshInstance3D
var streamed_infill_instance: MeshInstance3D
var streamed_infill_root: Node3D
var streamed_infill_material: StandardMaterial3D
var web_tactical_dressing_root: Node3D
var web_render_retire_queue: Array[Dictionary] = []
var web_dressing_mesh_cache: Dictionary = {}
var web_dressing_anchor := Vector2i(999999, 999999)
var web_pending_dressing_wanted: Dictionary = {}
var web_pending_dressing_anchor := Vector2i(999999, 999999)
var web_stream_in_progress := false
var map_world_environment: Environment
var map_water_material: ShaderMaterial
var map_sun: DirectionalLight3D
var map_fill: DirectionalLight3D
var environment_fx: EnvironmentFXController
var stream_anchor := Vector2i(999999, 999999)
var web_stream_geometry_center := Vector2i(999999, 999999)
var web_stream_geometry_radius := -1
var environment_context_coord := Vector2i(999999, 999999)
var environment_context_hard := false
var blender_mesh_library: Dictionary = {}
var movement_range_fill: MeshInstance3D
var movement_range_grid: MeshInstance3D
var movement_range_boundary: MeshInstance3D
var movement_range_reachable: Dictionary = {}
var movement_range_render_generation := 0
var web_movement_overlay
var web_movement_visible_keys: Array[String] = []
var web_movement_projection_camera := Vector3(1.0e20, 1.0e20, 1.0e20)
var web_movement_projection_size := Vector2(-1.0, -1.0)
var web_movement_projection_camera_size := -1.0
var web_movement_projection_origin_screen := Vector2.ZERO
var route_mesh: MeshInstance3D
var web_route_overlay: Control
var web_route_rects: Array[ColorRect] = []
var web_route_projection_camera := Vector3(1.0e20, 1.0e20, 1.0e20)
var web_route_projection_size := Vector2(-1.0, -1.0)
var web_route_projection_camera_size := -1.0
var web_route_projection_origin_screen := Vector2(1.0e20, 1.0e20)
var web_selected_overlay: Control
var web_selected_rects: Array[ColorRect] = []
var web_selected_projection_camera := Vector3(1.0e20, 1.0e20, 1.0e20)
var web_selected_projection_size := Vector2(-1.0, -1.0)
var web_selected_projection_camera_size := -1.0
var web_selected_projection_origin_screen := Vector2(1.0e20, 1.0e20)
var web_entity_projection_dirty := true
var web_entity_projection_size := Vector2(-1.0, -1.0)
var runtime_layout_cached_size := Vector2.ZERO
var runtime_layout_cache_msec := -100000
var route_segments: Array[MeshInstance3D] = []
var route_nodes: Array[MeshInstance3D] = []
var selected_ring: MeshInstance3D
var selected_node: Dictionary = {}
var selected_treasure: Dictionary = {}
var selected_relay: Dictionary = {}
var selected_event: Dictionary = {}
var preview_path: Array[Vector2i] = []
var preview_risk := "SAFE"
var detail_title: Label
var detail_body: RichTextLabel
var move_button: Button
var battle_button: Button
var fast_travel_button: Button
var sweep_buttons: Array[Button] = []
var status_label: Label
var status_backplate: PanelContainer
var next_encounter_button: Button
var legend_card: PanelContainer
var legend_label: Label
var route_minimap: ChapterRouteMinimap
var moving := false
var movement_generation := 0
var live_encounter_replans := 0
var active_movement_path: Array[Vector2i] = []
var pawn_step_trails: Array[MeshInstance3D] = []
var pawn_step_trail_mesh: CylinderMesh
var movement_camera_goal := Vector3.ZERO
var movement_camera_follow_active := false
var movement_camera_settle_active := false
var movement_camera_settle_from := Vector3.ZERO
var movement_camera_settle_goal := Vector3.ZERO
var movement_camera_settle_elapsed := 0.0
var preview_camera_tween: Tween
var movement_skip_requested := false
var turn_transitioning := false
var pending_turn_completion := false
var pending_turn_label := ""
const POST_REWARD_TURN_PENDING_KEY := "post_reward_turn_pending"
var direct_move_pending := false
var last_node_pointer_id := ""
var last_node_pointer_msec := -100000
var node_touch_pointer_id := ""
var node_touch_origin := Vector2.ZERO
var node_touch_tap_valid := false
var last_map_pointer_click_valid := false
var last_map_pointer_click_msec := -100000
var last_map_pointer_click_position := Vector2.ZERO
var dragging := false
var drag_origin := Vector2.ZERO
var camera_origin := Vector3.ZERO
var hard_overlay := false
var toolbar: HFlowContainer
var toolbar_spacer: Control
var map_toolbar_buttons: Array[Button] = []
var detail_panel: PanelContainer
var detail_scroll: ScrollContainer
var compact_optional_buttons: Array[Control] = []
var wait_button: Button
var map_simulation_paused := false
var map_notice := ""
var map_notice_until_msec := 0
var map_id := ""
var tutorial_canvas_layer: CanvasLayer
var tutorial_surface: Control
var tutorial_dimmer: ColorRect
var tutorial_panel: PanelContainer
var tutorial_inner_frame: PanelContainer
var tutorial_scroll: ScrollContainer
var tutorial_eyebrow: Label
var tutorial_title: Label
var tutorial_body: RichTextLabel
var tutorial_continue_button: Button
var tutorial_progress_label: Label
var tutorial_dismiss_button: Button
var tutorial_step := 0
var tutorial_pointer_active := false
var tutorial_pointer_tap_valid := false
var tutorial_pointer_origin := Vector2.ZERO
var tutorial_pointer_started_msec := -100000
var leader_selector_layer: Control
var treasure_save_failure_layer: CanvasLayer

func _web_async_owner_alive() -> bool:
	# Web builders yield across many browser frames. Once navigation removes this
	# screen, no resumed continuation may touch its retired SubViewport children.
	return not OS.has_feature("web") or is_inside_tree()

func _finish_web_build_slice(tag: String, started_usec: int) -> void:
	var before_yield_usec := Time.get_ticks_usec()
	if OS.has_feature("web") and SettingsService.is_developer_mode():
		var synchronous_msec := float(before_yield_usec - started_usec) / 1000.0
		if synchronous_msec >= 16.0:
			print("WEB_SYNC_TASK %s %.2fms" % [tag, synchronous_msec])
	# Entry construction has many tiny chunks. Yielding a complete renderer frame
	# after every one turned inexpensive work into hundreds of mandatory 16.7 ms
	# waits. Keep each synchronous slice below a ten-millisecond budget instead.
	if OS.has_feature("web") and web_stage_entry_preload_active \
		and web_entry_last_yield_usec > 0 \
		and before_yield_usec - web_entry_last_yield_usec < WEB_ENTRY_SLICE_BUDGET_USEC:
		return
	await get_tree().process_frame
	web_entry_last_yield_usec = Time.get_ticks_usec()
	if not _web_async_owner_alive():
		return
	if not OS.has_feature("web") or not SettingsService.is_developer_mode():
		return
	var elapsed_msec := float(Time.get_ticks_usec() - started_usec) / 1000.0
	if elapsed_msec >= 33.0:
		print("WEB_FRAME_GAP %s %.2fms" % [tag, elapsed_msec])

func _retire_web_render_root(root: Node3D) -> void:
	if root == null or not is_instance_valid(root):
		return
	root.visible = false
	# Never leave a detached coroutine removing renderer-owned children over
	# several Web frames. A screen transition can invalidate that continuation;
	# the resulting ClassDB p_object=null failure kills the canvas while audio
	# keeps playing. Retire whole hidden roots from `_process()` after the renderer
	# has observed a few complete frames, with no captured child Callables.
	for entry in web_render_retire_queue:
		if entry.get("root") == root:
			return
	web_render_retire_queue.append({"root": root, "frames": 3})

func _process_web_render_retire_queue() -> void:
	if web_render_retire_queue.is_empty():
		return
	var entry: Dictionary = web_render_retire_queue[0]
	var root: Node3D = entry.get("root")
	if root == null or not is_instance_valid(root):
		web_render_retire_queue.pop_front()
		return
	var frames_left := int(entry.get("frames", 0))
	if frames_left > 0:
		entry["frames"] = frames_left - 1
		web_render_retire_queue[0] = entry
		return
	root.queue_free()
	web_render_retire_queue.pop_front()

func _ready() -> void:
	map_ready_complete = false
	map_simulation_paused = true
	_emit_map_load_progress(0.0, "map_data")
	if map_id.is_empty():
		map_id = AppState.map_id_for_stage(AppState.selected_stage_id)
	var loaded_definition: Dictionary = definition
	if loaded_definition.is_empty():
		loaded_definition = ChapterMapLoaderScript.load_map(map_id)
	if loaded_definition.is_empty():
		map_id = DEFAULT_MAP_ID
		loaded_definition = ChapterMapLoaderScript.load_map(map_id)
	definition = loaded_definition
	grid.load_tiles(definition.get("tiles", []))
	map_state = AppState.chapter_map_state(map_id)
	# A battle return creates a fresh map screen. Restore the route layer from the
	# canonical node/axial state before any HUD labels are built; otherwise an H01
	# victory reopens the NORMAL overlay and "next encounter" incorrectly points
	# back to N01 even though H02 was just unlocked.
	hard_overlay = _hard_overlay_from_state(map_state, definition)
	var repaired_map_state := MapExplorationServiceScript.ensure_state(map_state, definition, grid)
	MapExplorationServiceScript.update_proximity(map_state, definition, Vector2i(int(map_state.current_q), int(map_state.current_r)), grid)
	# Persist a one-time legacy patrol repair before the player can navigate or
	# refresh.  This is map state migration, not a view-side fallback.
	if repaired_map_state:
		SaveService.save_game()
	camera_zoom = clampf(float(map_state.get("camera_zoom", 1.0)), 0.72, 1.55)
	_build_interface()
	_emit_map_load_progress(0.06, "shell")
	# Web must be allowed to present the shell before any terrain work begins.
	# This also turns map construction into a cooperative coroutine instead of a
	# single long main-thread task that browsers report as a frozen/crashed tab.
	await get_tree().process_frame
	if not _web_async_owner_alive():
		return
	await _build_world()
	if not _web_async_owner_alive():
		return
	# Web must finish the static stage footprint before exposing input.  In
	# particular, do not defer `_build_web_map_detail`: ordinary movement and the
	# enemy phase are transform/fog work only after this boundary.
	if OS.has_feature("web"):
		await _build_web_map_detail()
		if not _web_async_owner_alive():
			return
	_refresh_state_visuals()
	_focus_current(true)
	map_simulation_paused = false
	_emit_map_load_progress(1.0, "ready")
	map_ready_complete = true
	map_ready.emit()
	# Treasure rewards temporarily leave the map for the result presentation.
	# Persist the unfinished player-turn edge so returning to a freshly-created
	# map screen can never strand the squad at movement 0/max with every action
	# disabled.  The same deferred call is also a fail-safe when an external
	# result listener elects to keep this map instance alive.
	if bool(map_state.get(POST_REWARD_TURN_PENDING_KEY, false)) or MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0:
		call_deferred("_resume_post_reward_turn")
	if _first_map_tutorial_active():
		call_deferred("_start_first_map_tutorial")
	call_deferred("_present_pending_reveal_once")

func resume_from_cache() -> void:
	# Battle/result mutate the canonical dictionary while this preserved view is
	# hidden. Rebind and repaint only stateful overlays/pawns; do not rebuild the
	# 3D world, terrain batches or imported art on every reward return.
	map_simulation_paused = true
	map_state = AppState.chapter_map_state(map_id)
	var repaired_map_state := MapExplorationServiceScript.ensure_state(map_state, definition, grid)
	hard_overlay = _hard_overlay_from_state(map_state, definition)
	MapExplorationServiceScript.update_proximity(map_state, definition, _player_map_coord(), grid)
	moving = false
	movement_camera_follow_active = false
	turn_transitioning = false
	movement_skip_requested = false
	active_movement_path.clear()
	preview_path.clear()
	selected_node.clear()
	selected_treasure.clear()
	selected_relay.clear()
	selected_event.clear()
	_prune_cleared_enemy_pawns()
	var current := _player_map_coord()
	if stream_anchor != current:
		_focus_current(true)
	else:
		var current_world := HexCoordScript.axial_to_world(current, TILE_SIZE, float(grid.tile(current).get("elevation", 0)) * ELEVATION_STEP)
		camera_target = _clamp_camera_target_to_terrain(current_world)
	_refresh_state_visuals()
	_apply_responsive_layout()
	map_simulation_paused = false
	if repaired_map_state:
		SaveService.save_game()
	if OS.has_feature("web") and not web_detail_build_complete and not web_detail_build_started:
		call_deferred("_build_web_map_detail")
	if bool(map_state.get(POST_REWARD_TURN_PENDING_KEY, false)) or MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0:
		call_deferred("_resume_post_reward_turn")
	call_deferred("_present_pending_reveal_once")

func _emit_map_load_progress(value: float, phase: String) -> void:
	map_load_progress.emit(clampf(value, 0.0, 1.0), phase)

func _all_map_tile_coverage() -> Dictionary:
	# A single immutable coverage set is deliberately wider than the current
	# vision disk.  It covers every authored destination the grid can later make
	# legal, so movement never asks the renderer to build a new district.
	var coverage: Dictionary = {}
	for tile_value in definition.get("tiles", []):
		var tile: Dictionary = tile_value
		coverage[HexCoordScript.key(Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0))))] = tile
	return coverage

func _web_stage_render_coverage() -> Dictionary:
	# The generated chapter definition contains thousands of blocked interior
	# forest cells whose only purpose is to give the campaign a broad silhouette.
	# Uploading geometry for all of them before the first playable frame made the
	# Web stage-entry loader exceed fifteen seconds. Every legal squad/enemy/
	# treasure coordinate is traversable, so preload that complete gameplay
	# footprint plus one blocked neighbour ring for real forest, ruin, wall and
	# elevation boundaries. The whole definition stays resident as gameplay data;
	# only renderer work outside every possible route is omitted.
	var tile_lookup := _all_map_tile_coverage()
	var coverage: Dictionary = {}
	for key_value in tile_lookup.keys():
		var key := str(key_value)
		var tile: Dictionary = tile_lookup[key]
		var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		if not grid.traversable(coord):
			continue
		coverage[key] = tile
		for neighbor_coord in HexCoordScript.neighbors(coord):
			var neighbor_key := HexCoordScript.key(neighbor_coord)
			if tile_lookup.has(neighbor_key):
				coverage[neighbor_key] = tile_lookup[neighbor_key]
	return coverage

static func _web_spatial_chunk_key(coord: Vector2i, span: int) -> String:
	return "%d,%d" % [floori(float(coord.x) / float(span)), floori(float(coord.y) / float(span))]

func _append_web_dressing_chunk_transform(
		batches: Dictionary,
		family: String,
		coord: Vector2i,
		position: Vector3,
		scale_value: Vector3,
		rotation_y: float
	) -> void:
	var chunk_key := _web_spatial_chunk_key(coord, WEB_ENTRY_DRESSING_CHUNK_SPAN)
	if not batches.has(chunk_key):
		batches[chunk_key] = {}
	var chunk_batches: Dictionary = batches[chunk_key]
	if not chunk_batches.has(family):
		# An untyped [] cannot be assigned back to Array[Transform3D] in exported
		# GDScript. The failure left every family present but empty, which explains
		# the Web log `chunks>0 instances=0` and the missing forest/rocks/walls.
		var first_transforms: Array[Transform3D] = []
		chunk_batches[family] = first_transforms
	var transforms: Array[Transform3D] = chunk_batches[family]
	# Do not route this through a second typed-Array parameter. In the Web export
	# that extra boundary retained the newly-created family key but lost the first
	# appended transform, producing valid chunks with zero visible instances.
	var basis := Basis.IDENTITY.rotated(Vector3.UP, rotation_y).scaled(scale_value)
	transforms.append(Transform3D(basis, position))
	chunk_batches[family] = transforms
	batches[chunk_key] = chunk_batches

func _build_web_map_detail() -> void:
	# This is intentionally inside the stage-entry preload boundary.  Work is
	# cooperatively sliced so browser frames remain paintable, but completion means
	# all static presentation and future movement terrain are already resident.
	if not OS.has_feature("web") or web_detail_build_complete or web_detail_build_started or not is_inside_tree():
		return
	web_detail_build_started = true
	web_stage_entry_preload_active = true
	web_entry_last_yield_usec = Time.get_ticks_usec()
	_emit_map_load_progress(0.20, "terrain")
	await get_tree().process_frame
	if not is_inside_tree():
		web_detail_build_started = false
		web_stage_entry_preload_active = false
		return
	var all_tiles := _all_map_tile_coverage()
	var render_tiles := _web_stage_render_coverage()
	if SettingsService.is_developer_mode():
		print("WEB_STAGE_RENDER_COVERAGE render=%d total=%d" % [render_tiles.size(), all_tiles.size()])
	# Terrain is spatially chunked (bounded SurfaceTool uploads) and dressing is
	# one compact MultiMesh draw per prop family. Every legal route is resident,
	# while blocked presentation-only forest beyond its boundary ring stays data-
	# resident without wasting WebGL upload time or draw-list memory.
	await _refresh_clear_ground_infill(Vector2i.ZERO, -1, true, true, render_tiles)
	if not is_inside_tree():
		web_detail_build_started = false
		web_stage_entry_preload_active = false
		return
	streamed_ground_keys.clear()
	for key_value in render_tiles.keys():
		var coverage_tile: Dictionary = render_tiles[key_value]
		if str(coverage_tile.get("terrain_type", "")) not in ["SHALLOW_WATER", "DEEP_WATER"]:
			streamed_ground_keys[str(key_value)] = true
	web_stream_geometry_center = _player_map_coord()
	web_stream_geometry_radius = 1000000
	stream_anchor = _player_map_coord()
	_emit_map_load_progress(0.47, "terrain_dressing")
	await _rebuild_web_tactical_dressing(render_tiles)
	if not is_inside_tree():
		web_detail_build_started = false
		web_stage_entry_preload_active = false
		return
	web_dressing_anchor = _player_map_coord()
	web_pending_dressing_wanted.clear()
	_emit_map_load_progress(0.64, "map_presentation")
	await _build_map_content_visuals()
	if not is_inside_tree():
		web_detail_build_started = false
		web_stage_entry_preload_active = false
		return
	_emit_map_load_progress(0.77, "unlocked_enemies")
	await _build_web_unlocked_enemy_pawns()
	if not is_inside_tree():
		web_detail_build_started = false
		web_stage_entry_preload_active = false
		return
	_emit_map_load_progress(0.88, "route_water")
	await _create_boundary_coastline()
	if not is_inside_tree():
		web_detail_build_started = false
		web_stage_entry_preload_active = false
		return
	await get_tree().process_frame
	if not is_inside_tree():
		web_detail_build_started = false
		web_stage_entry_preload_active = false
		return
	await _create_signal_causeways()
	if not is_inside_tree():
		web_detail_build_started = false
		web_stage_entry_preload_active = false
		return
	await _create_signal_waterway()
	if not is_inside_tree():
		web_detail_build_started = false
		web_stage_entry_preload_active = false
		return
	web_detail_assets_ready = true
	web_detail_build_complete = true
	web_stage_entry_preload_complete = true
	web_stage_entry_preload_active = false
	web_entry_last_yield_usec = 0
	web_detail_build_started = false
	_refresh_state_visuals()

static func _hard_overlay_from_state(state: Dictionary, map_definition: Dictionary) -> bool:
	var last_node_id := str(state.get("last_selected_node", ""))
	if not last_node_id.is_empty():
		var last_node := ChapterMapLoaderScript.node_by_id(map_definition, last_node_id)
		var last_stage_id := str(last_node.get("stage_id", ""))
		if not last_stage_id.is_empty():
			return last_stage_id.contains("-H")
	# Legacy or repaired saves can retain a canonical axial position without a
	# selected-node ID. Resolve that position deterministically rather than
	# falling back to the NORMAL layer.
	var current_q := int(state.get("current_q", 0))
	var current_r := int(state.get("current_r", 0))
	for node_value in map_definition.get("nodes", []):
		var node: Dictionary = node_value
		if int(node.get("q", 0)) != current_q or int(node.get("r", 0)) != current_r:
			continue
		var stage_id := str(node.get("stage_id", ""))
		if not stage_id.is_empty():
			return stage_id.contains("-H")
	return false

func _present_pending_reveal_once() -> void:
	var reveal := AppState.consume_chapter_map_pending_reveal(map_id)
	if reveal.is_empty():
		return
	# Persist consumption before showing the transient notice.  A browser refresh
	# during the presentation must restore canonical unlocks without replaying it.
	SaveService.save_game()
	_show_map_notice(reveal_notice_text(reveal, SettingsService.is_developer_mode()))
	# Battle return should immediately frame and display the newly unlocked route.
	# Keeping the cleared node selected left a stale yellow range until another
	# explicit "next encounter" action.
	_select_next_encounter()

func stage_display_text(stage_id: String, compact := false, include_internal_id := false) -> String:
	var stage := DataRegistry.stage(stage_id)
	var label := "새 조우" if compact else "새 작전"
	if not stage.is_empty():
		if compact:
			label = "%s %d" % ["위험" if str(stage.get("mode", "NORMAL")) == "HARD" else "일반", int(stage.get("stage_number", 0))]
		else:
			var name_key := str(stage.get("name_key", ""))
			label = LocalizationService.tr_key(name_key).replace(" (DEV)", "") if not name_key.is_empty() else "새 작전"
	if include_internal_id and not stage_id.is_empty():
		label += " [%s]" % stage_id
	return label

func reveal_notice_text(reveal: Dictionary, include_internal_ids := false) -> String:
	var stage_ids: Array = reveal.get("unlocked_stage_ids", [])
	if stage_ids.is_empty():
		var source_stage_id := str(reveal.get("source_stage_id", ""))
		if not source_stage_id.is_empty():
			stage_ids.append(source_stage_id)
	var labels: Array[String] = []
	for stage_id_value in stage_ids:
		labels.append(stage_display_text(str(stage_id_value), false, include_internal_ids))
	return "새 탐색 경로 공개" + (" · " + ", ".join(labels) if not labels.is_empty() else "")

func relay_status_display(status_id: String) -> String:
	return "신호 연결됨" if status_id == "ACTIVE" else "신호 복구 필요"

func _build_interface() -> void:
	# This screen lives inside AppShell's content VBox.  Viewport-wide anchors
	# make it cover the shell header on compact portrait displays, so the parent
	# container owns our bounds instead.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	# The root may fill ChapterMapScreen; ChapterMapScreen itself is constrained
	# by AppShell's content container above.
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.custom_minimum_size = Vector2(0.0, 280.0)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	# A flow container preserves the single desktop row while giving portrait
	# phones a real two-row touch toolbar.  A fixed HBox clipped WAIT outside the
	# 390 px canvas even though the rest of the map reflowed correctly.
	toolbar = HFlowContainer.new()
	toolbar.alignment = FlowContainer.ALIGNMENT_BEGIN
	root.add_child(toolbar)
	var normal_button := _button("일반 작전", func(): hard_overlay = false; _refresh_state_visuals(), Vector2(128, 56))
	var hard_button := _button("위험 작전", func(): hard_overlay = true; _refresh_state_visuals(), Vector2(128, 56))
	var current_button := _button("맵 대표", _open_map_leader_selector, Vector2(116, 56))
	current_button.tooltip_text = "2번째 작전부터 현재 파티원 중 맵에 표시할 캐릭터를 선택합니다."
	var overview_button := _button("구역 개요", _focus_full_map, Vector2(116, 56))
	var skip_button := _button("이동 건너뛰기", skip_movement, Vector2(132, 56))
	for action_button in [normal_button, hard_button, current_button, overview_button, skip_button]:
		toolbar.add_child(action_button)
		map_toolbar_buttons.append(action_button)
	wait_button = _button("대기", _wait_pulse, Vector2(86, 56))
	wait_button.tooltip_text = "이동하지 않고 턴을 종료합니다. 적 턴 뒤 다음 아군 턴이 자동으로 시작됩니다."
	toolbar.add_child(wait_button)
	var formation := _button("파티 편성", func(): formation_requested.emit(), Vector2(116, 56))
	toolbar.add_child(formation)
	compact_optional_buttons.append(formation)
	toolbar_spacer = Control.new()
	toolbar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(toolbar_spacer)
	var fallback := _button("목록형 접근성", func(): fallback_requested.emit(), Vector2(150, 56))
	toolbar.add_child(fallback)
	compact_optional_buttons.append(fallback)
	if SettingsService.is_developer_mode():
		var fx_tuning := _button("FX 조정", func(): environment_fx.toggle_development_panel(map_area), Vector2(112, 56))
		fx_tuning.tooltip_text = "환경 프리셋과 날씨 표현 조정 · 개발 전용"
		toolbar.add_child(fx_tuning)
	map_area = Control.new()
	map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(map_area)
	map_frame = PanelContainer.new()
	map_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_frame.clip_contents = true
	# The map is the primary product surface, not a developer canvas.  Keep the
	# frame as a dark vignette without a persistent cyan debug-outline.
	map_frame.add_theme_stylebox_override("panel", GameUI.panel_style(Color("07111bf2"), Color("2f485b"), 1, GameUI.RADIUS_PANEL, Vector4(6.0, 6.0, 6.0, 6.0), 6))
	map_area.add_child(map_frame)
	presentation_layer = Control.new()
	presentation_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_frame.add_child(presentation_layer)
	viewport_container = SubViewportContainer.new()
	# The container owns presentation sizing so the 3D map fills both desktop and
	# portrait layouts.  Do not manually resize its SubViewport while this is on:
	# Godot rejects that combination and emits a warning on each reflow.
	viewport_container.stretch = true
	viewport_container.tooltip_text = "한 번 클릭: 경로 확인 · 더블클릭/터치: 노란 범위 안에서 즉시 이동"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.gui_input.connect(_on_map_input)
	presentation_layer.add_child(viewport_container)
	viewport = SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport_container.add_child(viewport)
	fog_screen_overlay = ColorRect.new()
	fog_screen_overlay.name = "SquadVisionScreenFog"
	fog_screen_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog_screen_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_screen_overlay.color = Color.WHITE
	fog_screen_material = ShaderMaterial.new()
	fog_screen_material.shader = FogOfWarScreenShader
	fog_screen_overlay.material = fog_screen_material
	presentation_layer.add_child(fog_screen_overlay)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The overlay carries actual stage buttons. PASS keeps transparent space
	# available for map pan while allowing those children to receive a tap.
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	# A PASS control is above the SubViewportContainer, so route its transparent
	# tap/drag area explicitly. Without this, portrait taps can visually land on
	# a marker yet never reach the mathematical nearest-node selector.
	overlay.gui_input.connect(_on_map_input)
	presentation_layer.add_child(overlay)
	if OS.has_feature("web"):
		web_movement_overlay = WebMovementOverlayScript.new()
		web_movement_overlay.name = "WebMovementAuthorityOverlay"
		web_movement_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		web_movement_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		web_movement_overlay.visible = false
		overlay.add_child(web_movement_overlay)
		# Both a new 3D ribbon and Godot's first Line2D draw compile a browser-only
		# pipeline on the selection frame. Reuse the already-live ColorRect canvas
		# pipeline instead, and pre-pool enough segments for normal macro routes so
		# clicking a destination creates no nodes, shaders or draw resource types.
		web_route_overlay = Control.new()
		web_route_overlay.name = "WebRoutePreview"
		web_route_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		web_route_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		web_route_overlay.visible = false
		overlay.add_child(web_route_overlay)
		for _segment_index in range(48):
			var segment := ColorRect.new()
			segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
			segment.visible = false
			web_route_overlay.add_child(segment)
			web_route_rects.append(segment)
		web_selected_overlay = Control.new()
		web_selected_overlay.name = "WebSelectedTargetRing"
		web_selected_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		web_selected_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		web_selected_overlay.visible = false
		overlay.add_child(web_selected_overlay)
		for _edge_index in range(6):
			var edge := ColorRect.new()
			edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			edge.visible = false
			web_selected_overlay.add_child(edge)
			web_selected_rects.append(edge)
	# Environment FX is inserted between the SubViewport and actual map controls.
	# It affects only world presentation and can never tint/map-block HUD input.
	environment_fx = EnvironmentFXControllerScript.new()
	environment_fx.name = "EnvironmentFXController"
	environment_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	environment_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presentation_layer.add_child(environment_fx)
	presentation_layer.move_child(environment_fx, presentation_layer.get_children().find(overlay))
	environment_fx.attach_canvas(presentation_layer)
	status_label = Label.new()
	status_label.position = Vector2(22, 18)
	status_label.custom_minimum_size = Vector2(520, 34)
	status_label.size = Vector2(520, 34)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.clip_text = false
	status_label.add_theme_font_size_override("font_size", 28)
	status_label.add_theme_color_override("font_color", GameUI.TEXT)
	status_label.add_theme_color_override("font_outline_color", Color("02080f"))
	status_label.add_theme_constant_override("outline_size", 2)
	status_label.add_theme_color_override("font_shadow_color", Color("031018"))
	status_label.add_theme_constant_override("shadow_offset_x", 3)
	status_label.add_theme_constant_override("shadow_offset_y", 3)
	status_label.modulate = Color.WHITE
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The status is live tactical information drawn over a visually busy 3D map.
	# A single low-profile backplate preserves the existing HUD language while
	# preventing forest highlights from erasing the movement/turn readout.
	status_backplate = PanelContainer.new()
	status_backplate.name = "MapStatusBackplate"
	status_backplate.show_behind_parent = true
	status_backplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_backplate.position = Vector2(-8, -5)
	status_backplate.size = status_label.size + Vector2(16, 10)
	status_backplate.add_theme_stylebox_override("panel", GameUI.panel_style(Color("07111bea"), Color("526d83aa"), 1, GameUI.RADIUS_CONTROL, Vector4(10.0, 6.0, 10.0, 6.0), 0))
	status_label.add_child(status_backplate)
	overlay.add_child(status_label)
	# A macro chapter map deliberately places upcoming encounters outside the
	# current camera window.  This is a player-facing navigation aid, not a
	# debug warp: it selects the next real stage node so route preview, movement
	# confirmation, stamina transaction, and battle entry remain unchanged.
	next_encounter_button = _button("다음 조우", _select_next_encounter, Vector2(248, 52))
	next_encounter_button.tooltip_text = "현재 공개된 다음 조우로 카메라 이동"
	GameUI.apply_button(next_encounter_button, "objective")
	overlay.add_child(next_encounter_button)
	legend_card = PanelContainer.new()
	legend_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	legend_card.position = Vector2(18, -58)
	legend_card.add_theme_stylebox_override("panel", GameUI.panel_style(Color("07111bd9"), Color("3b566c99"), 1, GameUI.RADIUS_CONTROL, Vector4(12.0, 8.0, 12.0, 8.0), 0))
	overlay.add_child(legend_card)
	legend_label = Label.new()
	legend_label.text = "◆ 현재 부대   ▰ 반투명 노랑: 이번 턴 이동 가능   더블클릭/터치: 즉시 이동   ✓ 클리어   ★ 완전 클리어   🔒 잠김"
	legend_label.add_theme_font_size_override("font_size", 20)
	legend_label.modulate = GameUI.TEXT_MUTED
	legend_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend_card.add_child(legend_label)
	route_minimap = ChapterRouteMinimapScript.new()
	route_minimap.name = "ChapterRouteMinimap"
	route_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	route_minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	overlay.add_child(route_minimap)
	detail_panel = PanelContainer.new()
	var detail_panel_style := GameUI.panel_style(GameUI.SURFACE, Color("6ce6d0a6"), 1, GameUI.RADIUS_PANEL, Vector4(20.0, 18.0, 20.0, 18.0), 10)
	detail_panel_style.content_margin_bottom = 20.0
	detail_panel.add_theme_stylebox_override("panel", detail_panel_style)
	map_area.add_child(detail_panel)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_child(detail_scroll)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 9)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail_box)
	detail_title = Label.new()
	detail_title.add_theme_font_size_override("font_size", 34)
	detail_title.add_theme_color_override("font_color", GameUI.TEXT)
	var detail_title_font := GameUI.weighted_font(get_theme_default_font(), 700.0, 0.04)
	if detail_title_font != null: detail_title.add_theme_font_override("font", detail_title_font)
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(detail_title)
	detail_body = RichTextLabel.new()
	detail_body.bbcode_enabled = true
	detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_body.add_theme_font_size_override("normal_font_size", 24)
	detail_body.add_theme_color_override("default_color", GameUI.TEXT)
	detail_body.custom_minimum_size = Vector2(350, 278)
	detail_box.add_child(detail_body)
	move_button = _button("경로를 따라 이동", _confirm_move)
	GameUI.apply_button(move_button, "objective")
	detail_box.add_child(move_button)
	fast_travel_button = _button("클리어 지점 빠른 이동", _fast_travel)
	detail_box.add_child(fast_travel_button)
	battle_button = _button("기존 실시간 전투 시작", _request_battle)
	GameUI.apply_button(battle_button, "primary")
	detail_box.add_child(battle_button)
	var sweep_row := HBoxContainer.new()
	detail_box.add_child(sweep_row)
	for raw_count in [1, 5, 10]:
		var count: int = int(raw_count)
		var sweep := _button("소탕 %d" % count, func(value: int = count): _request_sweep(value), Vector2(112, 58))
		sweep_buttons.append(sweep)
		sweep_row.add_child(sweep)
	detail_box.add_child(_button("선택 취소", _clear_selection))
	_build_first_map_tutorial()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_update_panel()

func _first_map_tutorial_active() -> bool:
	if map_id != "CH01_MAP":
		return false
	var progress_value = AppState.profile.get("tutorial_progress", {})
	if not (progress_value is Dictionary):
		return false
	# Show revised guidance once to existing saves as well. Tying this to N01
	# stars permanently hid the tutorial from players returning after battle one.
	return int((progress_value as Dictionary).get("map_basics_revision", 0)) < MAP_TUTORIAL_REVISION

func _build_first_map_tutorial() -> void:
	if not _first_map_tutorial_active():
		return
	# CanvasLayer deliberately escapes the AppShell content slot, but that also
	# breaks Control-theme inheritance. Bind the bundled full Korean variable font
	# to every briefing text role so Web never falls back to tofu glyphs.
	var briefing_font := load("res://assets/fonts/NotoSansKR-VF.ttf") as Font
	var briefing_meta_font := _tutorial_weighted_font(briefing_font, 620.0, 0.04)
	var briefing_title_font := _tutorial_weighted_font(briefing_font, 720.0, 0.08)
	var briefing_body_font := _tutorial_weighted_font(briefing_font, 650.0, 0.08)
	# ChapterMapScreen is constrained to AppShell's content slot.  A dedicated
	# CanvasLayer makes FULL_RECT mean the actual viewport, so the shell header and
	# every map control receive the same briefing dim instead of leaving a bright
	# interactive strip above the modal.
	tutorial_canvas_layer = CanvasLayer.new()
	tutorial_canvas_layer.name = "FirstMapTutorialCanvas"
	tutorial_canvas_layer.layer = 90
	add_child(tutorial_canvas_layer)
	tutorial_surface = Control.new()
	tutorial_surface.name = "FirstMapTutorialSurface"
	tutorial_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_canvas_layer.add_child(tutorial_surface)
	tutorial_dimmer = ColorRect.new()
	tutorial_dimmer.name = "FirstMapTutorialDimmer"
	tutorial_dimmer.color = Color("03070db8")
	tutorial_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	tutorial_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_dimmer.z_index = 90
	tutorial_surface.add_child(tutorial_dimmer)
	tutorial_panel = PanelContainer.new()
	tutorial_panel.name = "FirstMapTutorial"
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	tutorial_panel.z_index = 91
	var outer_style := GameUI.panel_style(Color("07111bfc"), Color("e7bf68d9"), 1, GameUI.RADIUS_MODAL, Vector4(5.0, 5.0, 5.0, 5.0), 14)
	outer_style.content_margin_left = 6.0
	outer_style.content_margin_right = 6.0
	outer_style.content_margin_top = 6.0
	outer_style.content_margin_bottom = 6.0
	tutorial_panel.add_theme_stylebox_override("panel", outer_style)
	tutorial_surface.add_child(tutorial_panel)
	tutorial_inner_frame = PanelContainer.new()
	var inner_style := GameUI.panel_style(GameUI.SURFACE, Color("8aa2b633"), 1, GameUI.RADIUS_PANEL, Vector4.ZERO, 0)
	inner_style.content_margin_left = 0.0
	inner_style.content_margin_right = 0.0
	inner_style.content_margin_top = 0.0
	inner_style.content_margin_bottom = 0.0
	tutorial_inner_frame.add_theme_stylebox_override("panel", inner_style)
	tutorial_panel.add_child(tutorial_inner_frame)
	var content_margin := MarginContainer.new()
	tutorial_inner_frame.add_child(content_margin)
	var tutorial_box := VBoxContainer.new()
	tutorial_box.add_theme_constant_override("separation", 12)
	content_margin.add_child(tutorial_box)
	var tutorial_header := HBoxContainer.new()
	tutorial_header.alignment = BoxContainer.ALIGNMENT_BEGIN
	tutorial_box.add_child(tutorial_header)
	tutorial_eyebrow = Label.new()
	tutorial_eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_eyebrow.add_theme_font_size_override("font_size", 22)
	tutorial_eyebrow.add_theme_color_override("font_color", GameUI.SIGNAL)
	tutorial_eyebrow.add_theme_color_override("font_outline_color", Color("02070c"))
	tutorial_eyebrow.add_theme_constant_override("outline_size", 3)
	if briefing_meta_font != null:
		tutorial_eyebrow.add_theme_font_override("font", briefing_meta_font)
	tutorial_header.add_child(tutorial_eyebrow)
	tutorial_dismiss_button = Button.new()
	tutorial_dismiss_button.text = "안내 건너뛰기"
	tutorial_dismiss_button.tooltip_text = "첫 작전 안내를 마치고 바로 지도를 조작합니다"
	tutorial_dismiss_button.custom_minimum_size = Vector2(138, 44)
	tutorial_dismiss_button.add_theme_font_size_override("font_size", 19)
	if briefing_meta_font != null:
		tutorial_dismiss_button.add_theme_font_override("font", briefing_meta_font)
	GameUI.apply_button(tutorial_dismiss_button)
	tutorial_dismiss_button.add_theme_color_override("font_color", GameUI.TEXT_MUTED)
	tutorial_dismiss_button.add_theme_color_override("font_hover_color", GameUI.TEXT)
	tutorial_dismiss_button.pressed.connect(_complete_first_map_tutorial)
	tutorial_header.add_child(tutorial_dismiss_button)
	tutorial_title = Label.new()
	tutorial_title.add_theme_font_size_override("font_size", 38)
	tutorial_title.add_theme_color_override("font_color", GameUI.OBJECTIVE_SOFT)
	tutorial_title.add_theme_color_override("font_outline_color", Color("02070c"))
	tutorial_title.add_theme_constant_override("outline_size", 4)
	if briefing_title_font != null:
		tutorial_title.add_theme_font_override("font", briefing_title_font)
	tutorial_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_box.add_child(tutorial_title)
	var divider := HSeparator.new()
	divider.modulate = Color("71899f70")
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_box.add_child(divider)
	tutorial_scroll = ScrollContainer.new()
	tutorial_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tutorial_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tutorial_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_box.add_child(tutorial_scroll)
	tutorial_body = RichTextLabel.new()
	tutorial_body.bbcode_enabled = true
	tutorial_body.fit_content = true
	tutorial_body.scroll_active = false
	tutorial_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_body.add_theme_font_size_override("normal_font_size", 25)
	tutorial_body.add_theme_font_size_override("bold_font_size", 25)
	tutorial_body.add_theme_constant_override("line_separation", 10)
	tutorial_body.add_theme_color_override("default_color", GameUI.TEXT)
	# The body sits on an opaque navy reading surface. A black outline reduced the
	# visible white stroke area at 1280x720 and made the copy look gray; keep the
	# semibold glyph face clean and reserve outlines for the gold display title.
	tutorial_body.add_theme_constant_override("outline_size", 0)
	tutorial_body.add_theme_constant_override("shadow_offset_x", 0)
	tutorial_body.add_theme_constant_override("shadow_offset_y", 0)
	if briefing_body_font != null:
		tutorial_body.add_theme_font_override("normal_font", briefing_body_font)
	if briefing_title_font != null:
		tutorial_body.add_theme_font_override("bold_font", briefing_title_font)
	tutorial_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_scroll.add_child(tutorial_body)
	var tutorial_footer := VBoxContainer.new()
	tutorial_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	tutorial_footer.add_theme_constant_override("separation", 2)
	tutorial_box.add_child(tutorial_footer)
	tutorial_continue_button = Button.new()
	tutorial_continue_button.flat = false
	tutorial_continue_button.custom_minimum_size = Vector2(420, 46)
	tutorial_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tutorial_continue_button.add_theme_font_size_override("font_size", 23)
	GameUI.apply_button(tutorial_continue_button, "primary")
	if briefing_meta_font != null:
		tutorial_continue_button.add_theme_font_override("font", briefing_meta_font)
	tutorial_continue_button.pressed.connect(_advance_first_map_tutorial)
	tutorial_footer.add_child(tutorial_continue_button)
	tutorial_progress_label = Label.new()
	tutorial_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_progress_label.add_theme_font_size_override("font_size", 19)
	tutorial_progress_label.add_theme_color_override("font_color", GameUI.TEXT_FAINT)
	tutorial_progress_label.add_theme_color_override("font_outline_color", Color("02070c"))
	tutorial_progress_label.add_theme_constant_override("outline_size", 2)
	if briefing_meta_font != null:
		tutorial_progress_label.add_theme_font_override("font", briefing_meta_font)
	tutorial_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_footer.add_child(tutorial_progress_label)
	_set_tutorial_step(1)

func _input(event: InputEvent) -> void:
	# The briefing promises that any short click/tap progresses the current step,
	# including its title and body. Track this at screen level so a RichTextLabel
	# or ScrollContainer cannot create dead zones. A drag remains a scroll gesture.
	# The explicit skip control is exempted so it can finish the guide immediately.
	if tutorial_panel == null or not tutorial_panel.visible:
		return
	var threshold := 18.0 * _portrait_ui_scale(_runtime_layout_size())
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _tutorial_control_contains(event.position):
				_reset_tutorial_pointer()
				return
			tutorial_pointer_active = true
			tutorial_pointer_tap_valid = true
			tutorial_pointer_origin = event.position
			tutorial_pointer_started_msec = Time.get_ticks_msec()
		elif tutorial_pointer_active:
			var short_click: bool = tutorial_pointer_tap_valid and tutorial_short_tap_policy(tutorial_pointer_origin, event.position, Time.get_ticks_msec() - tutorial_pointer_started_msec, false, threshold, 800)
			_reset_tutorial_pointer()
			if short_click:
				_advance_first_map_tutorial()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and tutorial_pointer_active:
		if event.position.distance_to(tutorial_pointer_origin) > threshold:
			tutorial_pointer_tap_valid = false
	elif event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			if _tutorial_control_contains(event.position):
				_reset_tutorial_pointer()
				return
			tutorial_pointer_active = true
			tutorial_pointer_tap_valid = not event.canceled
			tutorial_pointer_origin = event.position
			tutorial_pointer_started_msec = Time.get_ticks_msec()
		elif tutorial_pointer_active:
			var short_tap: bool = tutorial_pointer_tap_valid and tutorial_short_tap_policy(tutorial_pointer_origin, event.position, Time.get_ticks_msec() - tutorial_pointer_started_msec, event.canceled, 24.0 * _portrait_ui_scale(_runtime_layout_size()), 900)
			_reset_tutorial_pointer()
			if short_tap:
				_advance_first_map_tutorial()
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == 0 and tutorial_pointer_active:
		if event.position.distance_to(tutorial_pointer_origin) > 24.0 * _portrait_ui_scale(_runtime_layout_size()):
			tutorial_pointer_tap_valid = false

static func tutorial_short_tap_policy(origin: Vector2, released_at: Vector2, elapsed_msec: int, canceled: bool, movement_threshold: float, duration_limit_msec: int) -> bool:
	return not canceled and elapsed_msec >= 0 and elapsed_msec <= duration_limit_msec and released_at.distance_to(origin) <= movement_threshold

func _tutorial_control_contains(point: Vector2) -> bool:
	# Buttons already own their pressed edge. Letting the full-screen pointer
	# bridge consume the same release advanced two pages at once and could leave
	# the guide apparently frozen on page 2 while delayed map work ran behind it.
	for control in [tutorial_dismiss_button, tutorial_continue_button]:
		if control != null and control.visible and control.get_global_rect().has_point(point):
			return true
	return false

func _reset_tutorial_pointer() -> void:
	tutorial_pointer_active = false
	tutorial_pointer_tap_valid = false
	tutorial_pointer_started_msec = -100000

func _hide_first_map_tutorial_modal() -> void:
	_reset_tutorial_pointer()
	if tutorial_surface != null:
		tutorial_surface.visible = false
	if tutorial_dimmer != null:
		tutorial_dimmer.visible = false
	if tutorial_panel != null:
		tutorial_panel.visible = false

func _advance_first_map_tutorial() -> void:
	if not _first_map_tutorial_active():
		return
	if tutorial_step >= 3:
		_complete_first_map_tutorial()
		return
	_set_tutorial_step(tutorial_step + 1)

func _start_first_map_tutorial() -> void:
	if not _first_map_tutorial_active() or tutorial_panel == null:
		return
	# The first route is selected for the player once so the connection between
	# an encounter marker, its route, and the right-side confirmation is visible
	# before any input is required.
	_select_next_encounter()
	_set_tutorial_step(1)
	_show_map_notice("첫 작전 안내 · 반투명 노란 칸이 이번 턴의 정확한 이동 범위입니다")

func _set_tutorial_step(step: int) -> void:
	if tutorial_panel == null:
		return
	tutorial_step = clampi(step, 1, 3)
	tutorial_eyebrow.text = "첫 작전 안내  ·  %d / 3" % tutorial_step
	tutorial_progress_label.text = "%d / 3" % tutorial_step
	if tutorial_dimmer != null:
		tutorial_dimmer.visible = true
	if tutorial_surface != null:
		tutorial_surface.visible = true
	tutorial_panel.visible = true
	_reset_tutorial_pointer()
	match tutorial_step:
		1:
			tutorial_title.text = "황금빛 이동 범위를 읽으세요"
			tutorial_body.text = "지도 위 [color=#f1cf7a][b]! 조우[/b][/color], 보물, 또는 노란 칸을 한 번 선택하면 실제 이동 경로가 표시됩니다. 같은 노란 칸을 한 번 더 클릭하면 이동합니다. 오른쪽 위 [color=#8de7d1][b]다음 조우[/b][/color]로도 다음 적을 바로 고를 수 있습니다.\n\n반투명 황금색 칸과 굵은 외곽선은 이번 아군 턴에 도달할 수 있는 정확한 범위입니다."
			tutorial_continue_button.text = "클릭 / 터치하여 지도를 확인"
		2:
			tutorial_title.text = "목적지를 바로 확정하세요"
			tutorial_body.text = "선택한 목적지를 [color=#f1cf7a][b]더블클릭[/b][/color]하거나 [color=#8de7d1][b]한 번 터치[/b][/color]하면 별도의 이동 버튼 없이 출발합니다.\n\n먼 조우는 이동력만큼 전진한 뒤 안전하게 중간 정지하며, 기존 이동 버튼도 그대로 사용할 수 있습니다."
			tutorial_continue_button.text = "클릭 / 터치하여 이동 준비"
		_:
			tutorial_title.text = "적 턴 뒤 다음 행동이 이어집니다"
			tutorial_body.text = "이동이 끝나면 아군 턴이 즉시 종료되고 적 부대가 한 번 행동합니다. 이어서 이동력이 보충된 다음 아군 턴이 자동으로 시작됩니다.\n\n적과 접촉하면 조우 이벤트 카드 뒤 전투로 전환되며, 보물과 현장 이벤트는 도착한 칸에서 바로 처리됩니다."
			tutorial_continue_button.text = "클릭 / 터치하여 작전 계속"

func _complete_first_map_tutorial() -> void:
	if not _first_map_tutorial_active():
		return
	AppState.profile.tutorial_progress["map_basics_complete"] = true
	AppState.profile.tutorial_progress["map_basics_revision"] = MAP_TUTORIAL_REVISION
	_hide_first_map_tutorial_modal()
	SaveService.save_game()
	_queue_web_enemy_pawn_stream()

func _apply_tutorial_layout(size: Vector2, portrait: bool, compact: bool, ui_scale: float) -> void:
	if tutorial_panel == null:
		return
	if tutorial_dimmer != null:
		tutorial_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Keep the tutorial's focus, but let the player read the real map beneath
		# it on a phone instead of turning the first interaction into a dark wall.
		tutorial_dimmer.color = Color("03070d8f") if portrait else Color("03070db8")
	# Landscape keeps the broad briefing card.  On portrait phones this becomes a
	# compact lower instruction sheet: the map, reachable yellow cells and the
	# highlighted encounter must remain visible while the tutorial explains them.
	# Long copy stays scrollable instead of claiming the entire viewport.
	if portrait:
		tutorial_panel.anchor_left = 0.04
		tutorial_panel.anchor_right = 0.96
		tutorial_panel.anchor_top = 0.46
		tutorial_panel.anchor_bottom = 0.97
	elif compact:
		tutorial_panel.anchor_left = 0.08
		tutorial_panel.anchor_right = 0.92
		tutorial_panel.anchor_top = 0.15
		tutorial_panel.anchor_bottom = 0.88
	else:
		tutorial_panel.anchor_left = 0.16
		tutorial_panel.anchor_right = 0.84
		tutorial_panel.anchor_top = 0.20
		tutorial_panel.anchor_bottom = 0.80
	tutorial_panel.offset_left = 0.0
	tutorial_panel.offset_right = 0.0
	tutorial_panel.offset_top = 0.0
	tutorial_panel.offset_bottom = 0.0
	tutorial_panel.custom_minimum_size = Vector2.ZERO
	var padding := roundi((36.0 if compact else 42.0) * ui_scale)
	if portrait:
		padding = roundi(20.0 * ui_scale)
	var content_margin := tutorial_inner_frame.get_child(0) as MarginContainer
	content_margin.add_theme_constant_override("margin_left", padding)
	content_margin.add_theme_constant_override("margin_right", padding)
	content_margin.add_theme_constant_override("margin_top", padding)
	content_margin.add_theme_constant_override("margin_bottom", padding)
	# Font targets are specified in rendered CSS pixels, not logical 1920x1080
	# pixels.  Without this conversion a nominal 25 px body becomes only 16-17 px
	# in the standard 1280x720 Web view and loses the reference's authority.
	tutorial_eyebrow.add_theme_font_size_override("font_size", _tutorial_logical_px(16.0 if portrait else (18.0 if compact else 20.0), size))
	tutorial_title.add_theme_font_size_override("font_size", _tutorial_logical_px(25.0 if portrait else (29.0 if compact else 32.0), size))
	var tutorial_body_size := _tutorial_logical_px(20.0 if portrait else (23.0 if compact else 24.0), size)
	tutorial_body.add_theme_font_size_override("normal_font_size", tutorial_body_size)
	tutorial_body.add_theme_font_size_override("bold_font_size", tutorial_body_size)
	tutorial_body.add_theme_constant_override("line_separation", _tutorial_logical_px(7.0, size))
	# `_runtime_layout_size()` is reported in CSS-like pixels while this Control
	# still lives on the fixed logical canvas.  Mixing `size.x` into the minimum
	# width makes the prompt collapse on a 390 px portrait viewport.  Scale one
	# authored physical target instead; the portrait value remains inside the
	# 80%-wide modal after its 36 px safety margins are applied.
	var continue_width := (228.0 if portrait else 420.0) * ui_scale
	tutorial_continue_button.custom_minimum_size = Vector2(continue_width, 46.0 * ui_scale)
	tutorial_continue_button.add_theme_font_size_override("font_size", _tutorial_logical_px(17.0 if portrait else (18.0 if compact else 20.0), size))
	tutorial_progress_label.add_theme_font_size_override("font_size", _tutorial_logical_px(14.0 if portrait else (15.0 if compact else 17.0), size))
	# Keep the explicit skip control in every viewport. The prior portrait-only
	# hiding left phone players with no visible way to decline a first-run guide.
	# A compact 102 px control still fits beside the eyebrow in the 320 px class.
	tutorial_dismiss_button.custom_minimum_size = Vector2((102.0 if portrait else 132.0) * ui_scale, 44.0 * ui_scale)
	tutorial_dismiss_button.add_theme_font_size_override("font_size", _tutorial_logical_px(13.0 if portrait else 18.0, size))
	tutorial_dismiss_button.visible = true

func _tutorial_logical_px(target_css_px: float, runtime_size: Vector2) -> int:
	var safe_size := Vector2(maxf(1.0, runtime_size.x), maxf(1.0, runtime_size.y))
	var canvas_scale := minf(safe_size.x / 1920.0, safe_size.y / 1080.0)
	return maxi(1, roundi(target_css_px / maxf(canvas_scale, 0.001)))

func _tutorial_weighted_font(base_font: Font, weight: float, embolden: float) -> Font:
	if base_font == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base_font
	variation.variation_opentype = {"wght": weight}
	variation.variation_embolden = embolden
	return variation

func _apply_responsive_layout() -> void:
	if detail_panel == null or map_frame == null: return
	# A real viewport resize must bypass the short Web bridge cache immediately.
	# Ordinary moving-frame readers reuse the cache and never synchronously query
	# window.innerWidth/innerHeight dozens of times per second.
	runtime_layout_cache_msec = -100000
	var size := _runtime_layout_size()
	var portrait := size.y > size.x
	var compact := portrait or size.x <= 980.0
	var has_selection := not selected_node.is_empty() or not selected_treasure.is_empty() or not selected_relay.is_empty() or not selected_event.is_empty()
	# This routine walks every encounter button and descendant action control.
	# State refreshes used to repeat the exact same theme/layout assignments two
	# or three times per move. Re-run only when viewport class, selection drawer,
	# node population or tutorial visibility actually changes.
	var next_layout_signature := "%d:%d:%d:%d:%d:%d" % [
		roundi(size.x), roundi(size.y), int(compact), int(has_selection),
		node_buttons.size(), int(_first_map_tutorial_active())
	]
	if responsive_layout_signature == next_layout_signature:
		return
	responsive_layout_signature = next_layout_signature
	# The project keeps a 1920x1080 logical canvas.  On a 915x412 phone the
	# canvas scale is only about 0.38, so a 56-logical-pixel control would become
	# a 21 CSS-pixel target.  Compact landscape needs the same physical touch
	# compensation as portrait instead of inheriting the desktop dimensions.
	var ui_scale := _compact_ui_scale(size) if compact else 1.0
	# Six core tactical actions fit in one 56px portrait rail.  This replaces the
	# previous two/three-row toolbar, which obscured too much of the actual map
	# before the player could see their move range or target.
	toolbar.add_theme_constant_override("h_separation", roundi((2.0 if portrait else 10.0) * ui_scale))
	toolbar.add_theme_constant_override("v_separation", roundi(6.0 * ui_scale) if portrait else 0)
	for index in range(map_toolbar_buttons.size()):
		var action_button := map_toolbar_buttons[index]
		if compact:
			action_button.custom_minimum_size = Vector2((56.0 if portrait else 112.0) * ui_scale, 56.0 * ui_scale)
			action_button.add_theme_font_size_override("font_size", roundi((17.0 if portrait else 18.0) * ui_scale))
			action_button.text = ["일반", "위험", "대표", "개요", "스킵"][index]
		else:
			action_button.custom_minimum_size = [Vector2(128, 56), Vector2(128, 56), Vector2(116, 56), Vector2(116, 56), Vector2(132, 56)][index]
			action_button.add_theme_font_size_override("font_size", 24)
			action_button.text = ["일반 작전", "위험 작전", "맵 대표", "구역 개요", "이동 건너뛰기"][index]
	if wait_button != null:
		wait_button.custom_minimum_size = Vector2((56.0 if portrait else 112.0) * ui_scale, 56.0 * ui_scale) if compact else Vector2(86, 56)
		wait_button.add_theme_font_size_override("font_size", roundi((17.0 if portrait else 18.0) * ui_scale) if compact else 24)
		wait_button.text = "대기"
	if toolbar_spacer != null:
		toolbar_spacer.visible = not compact
	if status_label != null:
		# Portrait reserves the first row for the objective shortcut. Keeping the
		# operation/movement readout on a real second row prevents address-bar resize
		# events from reintroducing the old status/button overlap.
		var status_top := 14.0 + (56.0 + 8.0 if portrait else 0.0)
		status_label.position = Vector2(14.0, status_top) * ui_scale if compact else Vector2(22, 18)
		status_label.size = Vector2((360.0 if portrait else 430.0) * ui_scale, 36.0 * ui_scale) if compact else Vector2(560, 38)
		status_label.add_theme_font_size_override("font_size", roundi((21.0 if portrait else 24.0) * ui_scale) if compact else 29)
		if status_backplate != null:
			status_backplate.position = Vector2(-8.0, -5.0) * ui_scale if compact else Vector2(-8, -5)
			status_backplate.size = status_label.size + (Vector2(16.0, 10.0) * ui_scale if compact else Vector2(16, 10))
	if next_encounter_button != null:
		var next_width := (188.0 if portrait else 248.0) * ui_scale
		var next_height := (56.0 if compact else 52.0) * ui_scale
		next_encounter_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		next_encounter_button.offset_left = -next_width - (12.0 * ui_scale if compact else 18.0)
		next_encounter_button.offset_right = -(12.0 * ui_scale if compact else 18.0)
		# Portrait uses a second status row.  Keeping both controls on the same row
		# made the operation title and `next encounter` button overlap by ~180 px.
		next_encounter_button.offset_top = (10.0 if portrait else 14.0) * ui_scale if compact else 18.0
		next_encounter_button.offset_bottom = next_encounter_button.offset_top + next_height
		next_encounter_button.add_theme_font_size_override("font_size", roundi(20.0 * ui_scale) if compact else 23)
	if legend_card != null:
		# The minimap already carries the compact Korean legend. Hiding this
		# secondary card prevents a clipped narrow label from reading as release
		# debug residue on constrained embedded Web viewports.
		legend_card.visible = false
		legend_card.position = Vector2(12.0 * ui_scale, -112.0 * ui_scale) if portrait else Vector2(18, -58)
		legend_card.custom_minimum_size = Vector2(0.0, 76.0 * ui_scale) if portrait else Vector2.ZERO
	if legend_label != null:
		legend_label.add_theme_font_size_override("font_size", roundi(17.0 * ui_scale) if portrait else 20)
	if route_minimap != null:
		if portrait:
			var map_width := clampf(size.x * 0.52, 176.0, 244.0)
			route_minimap.custom_minimum_size = Vector2(map_width, 132.0)
			route_minimap.position = Vector2(12.0, -154.0)
		elif compact:
			route_minimap.custom_minimum_size = Vector2(230.0 * ui_scale, 150.0 * ui_scale)
			route_minimap.position = Vector2(18.0 * ui_scale, -224.0 * ui_scale)
		else:
			route_minimap.custom_minimum_size = Vector2(230.0, 150.0)
			route_minimap.position = Vector2(18.0, -224.0)
	# Node labels are actual stage-selection controls. They must retain an
	# explicit phone-sized hit region instead of shrinking with the 1920 canvas.
	for node_id in node_buttons:
		var node_button: Button = node_buttons[node_id]
		if compact:
			node_button.custom_minimum_size = Vector2(72.0 * ui_scale, 56.0 * ui_scale)
			node_button.size = node_button.custom_minimum_size
			node_button.add_theme_font_size_override("font_size", roundi(20.0 * ui_scale))
		else:
			node_button.custom_minimum_size = Vector2(92.0, 42.0)
			node_button.size = Vector2(92.0, 42.0)
			node_button.add_theme_font_size_override("font_size", 21)
	if compact:
		# A real mobile bottom sheet reserves the top status strip and bottom safe
		# area before it takes map space. It is not a desktop right panel scaled down.
		map_frame.offset_right = 0.0
		detail_panel.anchor_left = 0.0
		detail_panel.anchor_right = 1.0
		detail_panel.anchor_top = 1.0
		detail_panel.anchor_bottom = 1.0
		detail_panel.offset_left = (8.0 if portrait else 16.0) * ui_scale
		detail_panel.offset_right = -(8.0 if portrait else 16.0) * ui_scale
		var bottom_safe_margin := 20.0 if portrait else 26.0
		# The contextual card remains scrollable; it does not need to reserve a
		# desktop inspector's height on a phone.  This returns roughly 42px of
		# vertical map visibility on the common 390×844 portrait viewport.
		var sheet_height := 280.0 if portrait else 230.0
		detail_panel.offset_top = -(sheet_height + bottom_safe_margin) * ui_scale
		detail_panel.offset_bottom = -bottom_safe_margin * ui_scale
		detail_panel.visible = has_selection
		detail_title.add_theme_font_size_override("font_size", roundi(28.0 * ui_scale))
		detail_body.custom_minimum_size = Vector2(0.0, (70.0 if portrait else 102.0) * ui_scale)
		detail_body.add_theme_font_size_override("normal_font_size", roundi((21.0 if portrait else 23.0) * ui_scale))
		# Every contextual action remains finger-sized after canvas_items scales the
		# 1920x1080 surface down to a compact browser viewport.
		for child in detail_scroll.find_children("*", "Button", true, false):
			var detail_action := child as Button
			detail_action.custom_minimum_size.y = 56.0 * ui_scale
			detail_action.add_theme_font_size_override("font_size", roundi(19.0 * ui_scale))
	else:
		var show_detail := has_selection
		map_frame.offset_right = -414.0 if show_detail else 0.0
		detail_panel.anchor_left = 1.0
		detail_panel.anchor_right = 1.0
		detail_panel.anchor_top = 0.0
		detail_panel.anchor_bottom = 0.0
		detail_panel.offset_left = -400.0
		detail_panel.offset_right = -12.0
		# Desktop detail is a contextual stage card, not a permanently tall
		# inspector. Preserve scrolling for long rewards but return visual space to
		# the map when the current selection only needs a short decision.
		detail_panel.offset_top = 14.0
		detail_panel.offset_bottom = 560.0
		detail_panel.visible = show_detail
		detail_title.add_theme_font_size_override("font_size", 34)
		detail_body.custom_minimum_size = Vector2(350.0, 246.0)
		detail_body.add_theme_font_size_override("normal_font_size", 24)
	_apply_tutorial_layout(size, portrait, compact, ui_scale)
	if compact_optional_buttons.size() >= 2:
		compact_optional_buttons[0].visible = not compact
		compact_optional_buttons[1].visible = not compact

func _runtime_layout_width() -> float:
	return _runtime_layout_size().x

func _runtime_layout_size() -> Vector2:
	var now_msec := Time.get_ticks_msec()
	if OS.has_feature("web") and runtime_layout_cached_size.x > 0.0 \
			and now_msec - runtime_layout_cache_msec < WEB_LAYOUT_PROBE_INTERVAL_MSEC:
		return runtime_layout_cached_size
	var window_size := DisplayServer.window_get_size()
	var width := float(window_size.x)
	var height := float(window_size.y)
	# Web exports keep the logical Godot width while CSS scales the canvas.
	# Read browser dimensions explicitly so portrait phones get a true mobile
	# sheet and correctly proportioned 3D render target.
	if OS.has_feature("web"):
		var browser_width = JavaScriptBridge.eval("window.innerWidth", true)
		var browser_height = JavaScriptBridge.eval("window.innerHeight", true)
		if browser_width is int or browser_width is float:
			width = float(browser_width)
		if browser_height is int or browser_height is float:
			height = float(browser_height)
	runtime_layout_cached_size = Vector2(width, height)
	runtime_layout_cache_msec = now_msec
	return runtime_layout_cached_size

func _portrait_ui_scale(runtime_size: Vector2) -> float:
	if runtime_size.y <= runtime_size.x: return 1.0
	return clampf(1920.0 / maxf(320.0, runtime_size.x), 2.8, 4.9)

func _compact_ui_scale(runtime_size: Vector2) -> float:
	if runtime_size.y > runtime_size.x:
		return _portrait_ui_scale(runtime_size)
	if runtime_size.x <= 980.0:
		return clampf(1080.0 / maxf(360.0, runtime_size.y), 1.0, 3.0)
	return 1.0

func _panel_style(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var normalized_radius := GameUI.RADIUS_CONTROL if radius <= 10 else (GameUI.RADIUS_PANEL if radius <= 16 else GameUI.RADIUS_MODAL)
	return GameUI.panel_style(fill, border, border_width, normalized_radius, Vector4(16.0, 13.0, 16.0, 13.0), 0)

func _button(text_value: String, callback: Callable, minimum := Vector2(350, 58)) -> Button:
	var button := Button.new()
	button.text = text_value
	var runtime_size := _runtime_layout_size()
	var ui_scale := _portrait_ui_scale(runtime_size)
	button.custom_minimum_size = Vector2(minf(minimum.x * ui_scale, 840.0), minimum.y * ui_scale) if runtime_size.y > runtime_size.x else minimum
	button.add_theme_font_size_override("font_size", roundi(21.0 * ui_scale))
	GameUI.apply_button(button)
	button.pressed.connect(callback)
	return button

func _add_occlusion_silhouette(source: Sprite3D, parent: Node3D, silhouette_name: String, color: Color) -> Sprite3D:
	if source == null or source.texture == null:
		return null
	var silhouette := Sprite3D.new()
	silhouette.name = silhouette_name
	# This low-opacity duplicate is deliberately no-depth. The normal pawn still
	# participates in terrain depth; only its exact animated contour survives
	# when a dam wall or tall plateau hides it from the camera.
	silhouette.texture = source.texture
	silhouette.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	silhouette.pixel_size = source.pixel_size
	silhouette.position = source.position
	silhouette.scale = Vector3(1.14, 1.14, 1.14)
	silhouette.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	silhouette.no_depth_test = true
	silhouette.shaded = false
	# This is an accessibility locator, not a decorative ghost. The old 0.28
	# alpha copy disappeared under the Chapter 1 viaduct after battle return.
	silhouette.modulate = Color(color.r, color.g, color.b, 0.78)
	silhouette.render_priority = 110
	silhouette.set_meta("occlusion_silhouette", true)
	parent.add_child(silhouette)
	return silhouette

func _build_world() -> void:
	world_root = Node3D.new()
	world_root.name = "ChapterMapWorld"
	viewport.add_child(world_root)
	var world_environment := WorldEnvironment.new()
	map_world_environment = Environment.new()
	map_world_environment.background_mode = Environment.BG_COLOR
	map_world_environment.background_color = Color("0a2634")
	map_world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	map_world_environment.ambient_light_color = Color("9cb59d")
	# Compatibility/Web maps need enough bounce light that elevation reads as
	# moss, stone, and layered earth—not as a field of near-black hex walls.
	map_world_environment.ambient_light_energy = 0.74
	# The map uses a restrained filmic pass and a very low fog density to make
	# elevation, coast and distant route sections recede. This is visual depth,
	# not a gameplay fog-of-war substitute.
	map_world_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	map_world_environment.tonemap_exposure = 0.96
	map_world_environment.adjustment_enabled = true
	map_world_environment.adjustment_brightness = 0.94
	map_world_environment.adjustment_contrast = 1.23
	map_world_environment.adjustment_saturation = 1.02
	map_world_environment.fog_enabled = true
	map_world_environment.fog_light_color = Color("315f66")
	map_world_environment.fog_light_energy = 0.34
	map_world_environment.fog_density = 0.0022
	map_world_environment.fog_sky_affect = 0.42
	world_environment.environment = map_world_environment
	world_root.add_child(world_environment)
	# A complete source kit import can take several seconds in a single-threaded
	# browser. It is scenery, not input authority: show the actual playable map
	# first, then hydrate authored trees/relief/causeways after map_ready.
	web_detail_assets_ready = not OS.has_feature("web")
	if web_detail_assets_ready:
		_load_blender_kit()
		_load_terrain_relief()
	await get_tree().process_frame
	if not _web_async_owner_alive():
		return
	_create_world_backdrop()
	_create_world_island_shelf()
	await get_tree().process_frame
	if not _web_async_owner_alive():
		return
	# Streamed Blender caps are the Web ground authority. Building a second
	# full-map SurfaceTool mesh synchronously traversed the entire macro world
	# before a local tile appeared and caused the reported 20-second blank map.
	if not OS.has_feature("web"):
		_create_connected_terrain_surface()
	await get_tree().process_frame
	if not _web_async_owner_alive():
		return
	if not OS.has_feature("web"):
		await _create_boundary_coastline()
		if not _web_async_owner_alive():
			return
	await get_tree().process_frame
	if not _web_async_owner_alive():
		return
	if not OS.has_feature("web"):
		await _create_signal_causeways()
		if not _web_async_owner_alive():
			return
	await get_tree().process_frame
	if not _web_async_owner_alive():
		return
	map_sun = DirectionalLight3D.new()
	map_sun.rotation_degrees = Vector3(-42, -38, 0)
	map_sun.light_color = Color("ffeac4")
	map_sun.light_energy = 0.98
	# Keep the authored light, normals, cliff faces and contact sockets on every
	# target. Directional shadow maps are native-only: on single-threaded WebGL
	# they are redrawn while the orthographic camera follows every hex, which was
	# the remaining 50-75ms movement spike and starved the WebAudio pump.
	map_sun.shadow_enabled = not OS.has_feature("web")
	map_sun.directional_shadow_max_distance = 34.0
	map_sun.directional_shadow_fade_start = 0.72
	map_sun.light_angular_distance = 1.8
	world_root.add_child(map_sun)
	map_fill = DirectionalLight3D.new()
	map_fill.rotation_degrees = Vector3(-48, 136, 0)
	map_fill.light_color = Color("8fd8de")
	map_fill.light_energy = 0.48
	map_fill.shadow_enabled = false
	world_root.add_child(map_fill)
	# Make the gameplay camera current before cooperative terrain construction.
	# Creating it after every chunk was ready deferred shader/buffer preparation
	# until the first visible map frame, producing three 100ms+ frames and an
	# audible BGM underrun even though the CPU builder itself yielded correctly.
	camera_target = HexCoordScript.axial_to_world(
		Vector2i(int(map_state.current_q), int(map_state.current_r)),
		TILE_SIZE,
		float(grid.tile(Vector2i(int(map_state.current_q), int(map_state.current_r))).get("elevation", 0)) * ELEVATION_STEP
	)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.2 / camera_zoom
	camera.near = 0.1
	camera.far = 100.0
	camera.position = camera_target + Vector3(9.2, 14.2, 8.8)
	world_root.add_child(camera)
	# Node3D.look_at requires an in-tree transform. Doing this before add_child
	# emitted a Web runtime error on every fresh stage-to-map transition.
	camera.look_at(camera_target, Vector3.UP)
	camera.make_current()
	await _stream_visible_tiles(Vector2i(int(map_state.current_q), int(map_state.current_r)), true, true)
	if not _web_async_owner_alive():
		return
	movement_range_fill = MeshInstance3D.new()
	movement_range_fill.name = "MovementRangeYellowFill"
	movement_range_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(movement_range_fill)
	movement_range_grid = MeshInstance3D.new()
	movement_range_grid.name = "MovementRangeYellowCellGrid"
	movement_range_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(movement_range_grid)
	movement_range_boundary = MeshInstance3D.new()
	movement_range_boundary.name = "MovementRangeYellowBoundary"
	movement_range_boundary.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(movement_range_boundary)
	route_mesh = MeshInstance3D.new()
	world_root.add_child(route_mesh)
	selected_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.54
	ring_mesh.outer_radius = 0.66
	ring_mesh.rings = 8
	ring_mesh.ring_segments = 24
	selected_ring.mesh = ring_mesh
	selected_ring.material_override = _route_overlay_material(Color("6ff6dddc"), Color("28d7bd"))
	selected_ring.visible = false
	world_root.add_child(selected_ring)
	# The camera and squad must exist before optional encounter presentation.
	# Otherwise the SubViewport stays black while Web builds every enemy atlas and
	# stage button, which is exactly the long blank "deploying tactical map"
	# frame reported in QA.
	_create_pawn()
	_create_web_pawn_front_overlay()
	if environment_fx != null:
		environment_fx.bind_world(map_world_environment, terrain_material, map_water_material, map_sun, map_fill)
		_refresh_environment_presentation()
	if OS.has_feature("web"):
		return
	await _build_map_content_visuals()
	if not _web_async_owner_alive():
		return

func _build_map_content_visuals() -> void:
	# This is part of the Web entry boundary as well as the desktop build.  Never
	# hydrate a marker/treasure/landmark in response to a later movement step.
	if not OS.has_feature("web") and not node_markers.is_empty():
		return
	if OS.has_feature("web") and web_content_build_active:
		return
	if OS.has_feature("web"):
		web_content_build_active = true
	var node_build_index := 0
	for node in definition.get("nodes", []):
		if node_markers.has(str(node.get("node_id", ""))):
			continue
		var node_started_usec := Time.get_ticks_usec()
		_create_node_marker(node)
		_create_node_button(node)
		# Browser builds present the playable map and tutorial first. Combat atlas
		# decoding is streamed after that trusted input boundary so one enemy image
		# can never stall the entire stage transition or the tutorial's audio.
		if not OS.has_feature("web") and str(node.get("stage_id", "")) != "":
			_create_enemy_pawn(node)
		node_build_index += 1
		# Web is single-threaded.  Creating several enemy portraits, labels and
		# materials in one frame made the lobby -> map transition look frozen even
		# though loading eventually completed. Keep each browser frame bounded.
		if OS.has_feature("web"):
			await _finish_web_build_slice("map_node_%02d" % node_build_index, node_started_usec)
		elif node_build_index % 4 == 0:
			await get_tree().process_frame
		if not _web_async_owner_alive():
			web_content_build_active = false
			return
	for treasure in definition.get("treasures", []):
		var treasure_id := str(treasure.get("treasure_id", ""))
		if treasure_visuals.has(treasure_id):
			continue
		var treasure_started_usec := Time.get_ticks_usec()
		_create_treasure_visual(treasure)
		if OS.has_feature("web"):
			await _finish_web_build_slice("map_treasure", treasure_started_usec)
			if not _web_async_owner_alive():
				web_content_build_active = false
				return
	for relay in definition.get("relays", []):
		var relay_id := str(relay.get("relay_id", ""))
		if relay_visuals.has(relay_id):
			continue
		var relay_started_usec := Time.get_ticks_usec()
		_create_relay_visual(relay)
		if OS.has_feature("web"):
			await _finish_web_build_slice("map_relay", relay_started_usec)
			if not _web_async_owner_alive():
				web_content_build_active = false
				return
	for event in definition.get("map_events", []):
		var event_id := str(event.get("event_id", ""))
		if event_visuals.has(event_id):
			continue
		var event_started_usec := Time.get_ticks_usec()
		_create_event_visual(event)
		if OS.has_feature("web"):
			await _finish_web_build_slice("map_event", event_started_usec)
			if not _web_async_owner_alive():
				web_content_build_active = false
				return
	for landmark in definition.get("landmarks", []):
		var landmark_id := str(landmark.get("landmark_id", ""))
		if landmark_visuals.has(landmark_id):
			continue
		var landmark_started_usec := Time.get_ticks_usec()
		_create_landmark_visual(landmark)
		if OS.has_feature("web"):
			await _finish_web_build_slice("map_landmark", landmark_started_usec)
			if not _web_async_owner_alive():
				web_content_build_active = false
				return
	await get_tree().process_frame
	if not _web_async_owner_alive():
		web_content_build_active = false
		return
	if not OS.has_feature("web"):
		_queue_web_enemy_pawn_stream()
	web_entity_projection_dirty = true
	if OS.has_feature("web"):
		web_content_build_active = false
	# Nodes are created after the initial interface reflow. Apply the active
	# viewport profile once more so first-load portrait controls are touch-sized.
	_apply_responsive_layout()

func _build_web_unlocked_enemy_pawns() -> void:
	# Decode every currently unlocked encounter atlas before map_ready.  A later
	# turn only changes root transforms/visibility; it never reads packaged art.
	if not OS.has_feature("web"):
		return
	var built_count := 0
	for node_value in definition.get("nodes", []):
		var node: Dictionary = node_value
		var node_id := str(node.get("node_id", ""))
		var stage_id := str(node.get("stage_id", ""))
		if node_id.is_empty() or stage_id.is_empty() or enemy_pawns.has(node_id):
			continue
		if not AppState.is_stage_unlocked(stage_id) or _node_encounter_cleared(node):
			continue
		var enemy_started_usec := Time.get_ticks_usec()
		_create_enemy_pawn(node)
		built_count += 1
		await _finish_web_build_slice("map_enemy_%02d" % built_count, enemy_started_usec)
		if not _web_async_owner_alive():
			return

func _material(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	# Ground, road and encounter-terrace meshes deliberately rely on their
	# upward-facing production triangles.  Keep back-face culling explicit so a
	# future material default cannot hide a reversed-winding regression behind a
	# two-sided workaround.
	material.cull_mode = BaseMaterial3D.CULL_BACK
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.4
	return material

func _cached_material(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
	# Runtime state refreshes reuse a very small, immutable palette. Creating a
	# fresh StandardMaterial3D for every pawn ring/step made Compatibility Web
	# compile and upload the same shader state during ordinary movement.
	var key := "%s|%s" % [color.to_html(true), emission.to_html(true)]
	if runtime_material_cache.has(key):
		return runtime_material_cache[key]
	if OS.has_feature("web") and WebSoakProbe.has_method("web_render_resource"):
		var warmed_material = WebSoakProbe.web_render_resource("runtime_material:%s" % key)
		if warmed_material is StandardMaterial3D:
			runtime_material_cache[key] = warmed_material
			return warmed_material
	var material := _material(color, emission)
	runtime_material_cache[key] = material
	return material

func _add_route_accent_light(parent: Node3D, local_position: Vector3, energy: float) -> void:
	# Small unshadowed amber pools give route/encounter landmarks a visual focal
	# hierarchy without spending a Compatibility-Web shadow budget. They are
	# presentation only and deliberately do not alter node selection or discovery.
	var accent := OmniLight3D.new()
	accent.name = "RouteAmberAccent"
	accent.light_color = Color("ffc77a")
	accent.light_energy = energy
	accent.omni_range = 3.35
	accent.omni_attenuation = 1.75
	accent.shadow_enabled = false
	accent.position = local_position
	parent.add_child(accent)

func _create_world_backdrop() -> void:
	# A low-cost water field makes hidden territory read as a real coastline rather
	# than a black prototype board. It has no gameplay or tile-selection role.
	var water := MeshInstance3D.new()
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(360.0, 220.0)
	water.mesh = water_mesh
	# The long-map ocean is a real world backdrop, not a foreground occluder.
	# Keep it well below the lowest generated terrain socket so the production
	# depth pass can correctly show a grounded squad, hostile, shadow and ring.
	water.position = Vector3(1.8, OCEAN_SURFACE_Y, -1.8)
	var water_material: ShaderMaterial = null
	if OS.has_feature("web") and WebSoakProbe.has_method("web_render_resource"):
		var warmed_water = WebSoakProbe.web_render_resource("water_material")
		if warmed_water is ShaderMaterial:
			water_material = warmed_water
	if water_material == null:
		water_material = ShaderMaterial.new()
		water_material.shader = EnvironmentWaterShader
	# Water is a backdrop. Draw it before all physical terrain, route and pawn
	# meshes so it contributes only where the map has no nearer world surface.
	water_material.render_priority = -127
	water.material_override = water_material
	map_water_material = water_material
	water.set_meta("water_material", water_material)
	world_root.add_child(water)
	# Do not place an opaque, fixed world-space horizon plane behind this macro
	# map.  The chapter spans far beyond the origin; once the camera reached the
	# HARD branch, the old finite plane crossed in front of H02 and hid valid
	# terrain/pawns while their screen-space labels remained visible.  The
	# Environment background, low fog and ocean plane already provide the distant
	# backdrop without introducing an occluding edge into the traversable world.

func _terrain_surface_color(tile: Dictionary) -> Color:
	# R10 gives each world role a durable hue family before lighting is applied.
	# This is intentionally a restrained terrain palette, not rainbow navigation:
	# moss/olive land, burnished route, cool slate ruins and blue water must still
	# survive mist and rain without collapsing back into the old teal board.
	var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
	var phase: int = abs(coord.x * 13 + coord.y * 19) % 5
	# Per-hex colour jumps made the continuous mesh read like a painted board.
	# Keep only a very small deterministic value drift inside each terrain family;
	# cliffs, vegetation masses, roads and water now carry the visual structure.
	var noise := (float(phase) - 2.0) * 0.004
	var base := Color("354a3e")
	match str(tile.get("terrain_type", "FOREST")):
		"FOREST": base = Color("354a3e")
		"ROAD": base = Color("735f40")
		"RUINS": base = Color("4b545e")
		"SHALLOW_WATER": base = Color("2d6970")
	return Color(clampf(base.r + noise, 0.0, 1.0), clampf(base.g + noise, 0.0, 1.0), clampf(base.b + noise, 0.0, 1.0), 1.0)

func _terrain_corner_key(point: Vector3) -> String:
	return "%d:%d" % [roundi(point.x * 1000.0), roundi(point.z * 1000.0)]

func _create_connected_terrain_surface() -> void:
	# Navigation continues to use individual axial cells, but the visible ground
	# is a single shared-vertex landscape. This makes gentle slopes, ridges and
	# clearings read as a world surface instead of a field of isolated hex slabs.
	var corner_totals: Dictionary = {}
	var corner_counts: Dictionary = {}
	var terrain_tiles: Array = []
	for raw_tile in definition.get("tiles", []):
		var tile: Dictionary = raw_tile
		if bool(tile.get("movement_blocked", false)) or str(tile.get("terrain_type", "")) == "DEEP_WATER":
			continue
		terrain_tiles.append(tile)
		var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		var center := HexCoordScript.axial_to_world(coord, TILE_SIZE)
		var height := float(tile.get("elevation", 0)) * ELEVATION_STEP
		for corner_index in range(6):
			var angle := PI / 6.0 + float(corner_index) * PI / 3.0
			var corner := center + Vector3(cos(angle) * TILE_SIZE, 0.0, sin(angle) * TILE_SIZE)
			var key := _terrain_corner_key(corner)
			corner_totals[key] = float(corner_totals.get(key, 0.0)) + height
			corner_counts[key] = int(corner_counts.get(key, 0)) + 1
	if terrain_tiles.is_empty():
		return
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tile in terrain_tiles:
		var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		var center := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(tile.get("elevation", 0)) * ELEVATION_STEP + 0.006)
		var tint := _terrain_surface_color(tile)
		for corner_index in range(6):
			var next_index := (corner_index + 1) % 6
			var angle_a := PI / 6.0 + float(corner_index) * PI / 3.0
			var angle_b := PI / 6.0 + float(next_index) * PI / 3.0
			var point_a := HexCoordScript.axial_to_world(coord, TILE_SIZE) + Vector3(cos(angle_a) * TILE_SIZE * 1.003, 0.0, sin(angle_a) * TILE_SIZE * 1.003)
			var point_b := HexCoordScript.axial_to_world(coord, TILE_SIZE) + Vector3(cos(angle_b) * TILE_SIZE * 1.003, 0.0, sin(angle_b) * TILE_SIZE * 1.003)
			point_a.y = float(corner_totals.get(_terrain_corner_key(point_a), 0.0)) / maxf(1.0, float(corner_counts.get(_terrain_corner_key(point_a), 1))) + 0.004
			point_b.y = float(corner_totals.get(_terrain_corner_key(point_b), 0.0)) / maxf(1.0, float(corner_counts.get(_terrain_corner_key(point_b), 1))) + 0.004
			var normal := Plane(center, point_a, point_b).normal
			if normal.y < 0.0: normal = -normal
			# Godot considers clockwise triangles front-facing for this X/Z map mesh.
			# Keep that engine-facing order while CULL_BACK remains enabled: using the
			# mathematically positive-Y order here silently culled the real ground and
			# left a valid pawn looking as if it stood over ocean.
			for vertex in [center, point_a, point_b]:
				surface_tool.set_color(tint)
				surface_tool.set_normal(normal)
				surface_tool.add_vertex(vertex)
	var mesh := surface_tool.commit()
	if mesh == null:
		return
	terrain_surface = MeshInstance3D.new()
	terrain_surface.name = "ConnectedTerrainSurface"
	terrain_surface.mesh = mesh
	terrain_material = StandardMaterial3D.new()
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 0.92
	terrain_material.metallic = 0.0
	terrain_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# The generated continuous mesh uses Godot's clockwise front-face contract.
	# Keep production back-face culling active; the controlled N04 coverage probe
	# confirmed that disabling culling does not resolve the missing-root defect.
	terrain_material.cull_mode = BaseMaterial3D.CULL_BACK
	terrain_surface.material_override = terrain_material
	world_root.add_child(terrain_surface)

func _create_boundary_coastline() -> void:
	# Boundary-aware reef placement follows the actual macro-map shoreline, so
	# the ocean has a readable coast at every streamed district instead of only a
	# few fixed showcase props near the starting area.
	# This is one continuous low-poly shallow-water ribbon, not a sea of water
	# hexes. At game scale it gives the coast a pale wet edge before the deep tide
	# begins, which makes a long land/water diagonal read as shoreline rather
	# than the edge of a prototype board.
	var shallow_mesh := ImmediateMesh.new()
	var shallow_material := _material(Color("2a8f91"), Color("0f6a70"))
	shallow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shallow_material.albedo_color.a = 0.82
	shallow_material.emission_energy_multiplier = 0.34
	var shallow_started := false
	var coastline_tile_count := 0
	for raw_tile in definition.get("tiles", []):
		coastline_tile_count += 1
		if OS.has_feature("web") and coastline_tile_count % WEB_STREAM_BUILD_BATCH == 0:
			await _finish_web_build_slice("coastline_scan", Time.get_ticks_usec())
			if not _web_async_owner_alive():
				return
		var tile: Dictionary = raw_tile
		if bool(tile.get("movement_blocked", false)):
			continue
		var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		for direction_index in range(HexCoordScript.DIRECTIONS.size()):
			var direction: Vector2i = HexCoordScript.DIRECTIONS[direction_index]
			if grid.has(coord + direction):
				continue
			var center := HexCoordScript.axial_to_world(coord, TILE_SIZE)
			var neighbor := HexCoordScript.axial_to_world(coord + direction, TILE_SIZE)
			var normal := (neighbor - center).normalized()
			var tangent := Vector3(-normal.z, 0.0, normal.x)
			var inner_center := center + normal * TILE_SIZE * 0.56
			var outer_center := center + normal * TILE_SIZE * 1.74
			# Keep this only a hair below the land surface.  The former ribbon sat
			# at the deep-ocean plane, where its colour was swallowed by the large
			# dark water backdrop at gameplay camera distance.
			inner_center.y = -0.022
			outer_center.y = -0.045
			var inner_left := inner_center - tangent * TILE_SIZE * 0.60
			var inner_right := inner_center + tangent * TILE_SIZE * 0.60
			var outer_left := outer_center - tangent * TILE_SIZE * 0.74
			var outer_right := outer_center + tangent * TILE_SIZE * 0.74
			if not shallow_started:
				shallow_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, shallow_material)
				shallow_started = true
			for vertex in [inner_left, outer_left, outer_right, inner_left, outer_right, inner_right]:
				shallow_mesh.surface_add_vertex(vertex)
			# The continuous ribbon is the Web coastline authority. Hundreds of
			# individual foam/cliff nodes added no gameplay information and made the
			# deferred detail pass interrupt movement and audio.
			if OS.has_feature("web"):
				continue
			# Sparse, deterministic selection avoids a repeated once-per-hex foam
			# ring while ensuring every route district gets some coastal structure.
			var signature: int = absi(coord.x * 31 + coord.y * 17 + direction_index * 7)
			if signature % 5 != 0:
				continue
			var edge := center.lerp(neighbor, 0.58)
			edge.y = -0.018
			var yaw := atan2(neighbor.z - center.z, neighbor.x - center.x)
			_spawn_kit_components("PROP_COAST_FOAM", edge, 0.70 + float(signature % 3) * 0.13, yaw)
			if signature % 10 == 0:
				_spawn_kit_component("PROP_CLIFF_FACET_B", edge + Vector3(0.10, 0.10, -0.08), 0.38, yaw)
	if shallow_started:
		shallow_mesh.surface_end()
	if shallow_mesh.get_surface_count() > 0:
		var shallow_instance := MeshInstance3D.new()
		shallow_instance.name = "ContinuousShallowCoastline"
		shallow_instance.mesh = shallow_mesh
		world_root.add_child(shallow_instance)

func _create_signal_causeways() -> void:
	# Stage coordinates are intentionally far apart.  This subdued stone-and-
	# signal causeway makes the route a physical part of the world even across a
	# broad valley or coast, without reverting to isolated hex podiums.  It also
	# gives every encounter a reliable visual ground contact at map scale.
	var shoulder_mesh := ImmediateMesh.new()
	var landing_mesh := ImmediateMesh.new()
	var landing_edge_mesh := ImmediateMesh.new()
	var base_mesh := ImmediateMesh.new()
	var inlay_mesh := ImmediateMesh.new()
	# The shoulder follows the *same deterministic greedy route* used to create
	# macro-map traversable terrain.  A cube-interpolated visual line could cut
	# across a different equal-cost corridor, which made late-chapter squad
	# positions look as if they stood in open water even though pathfinding had
	# correctly kept them on a valid tile.
	# This is the navigable expedition spine, not a thin UI trace.  It remains
	# legible where the macro route crosses a coastal cut, so a squad is never
	# visually stranded on a featureless water field while its logical hex is
	# correctly traversable.
	shoulder_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("5b4c35")))
	# Encounter clearings are deliberately larger, organic terrain terraces. They
	# give a moving hostile a readable ground contact even while it patrols one
	# cell away from its authored stage node; this avoids the visual impression of
	# a pawn hovering over the ocean between two macro districts.
	landing_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("3f7057")))
	landing_edge_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("1d3e35")))
	base_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("8a724b"), Color("382a19")))
	inlay_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("d0ac61"), Color("5c4724")))
	var landing_cells: Dictionary = {}
	var route_sets: Array = [definition.get("normal_route", []), definition.get("hard_route", [])]
	var causeway_segment_count := 0
	for route_index in range(route_sets.size()):
		var route: Array = route_sets[route_index]
		var previous := Vector2i(int(definition.get("start_hex", {}).get("q", 0)), int(definition.get("start_hex", {}).get("r", 0)))
		if route_index == 1:
			var normal_route: Array = definition.get("normal_route", [])
			var branch_node := ChapterMapLoaderScript.node_for_stage(definition, str(normal_route.back())) if not normal_route.is_empty() else {}
			if not branch_node.is_empty():
				previous = Vector2i(int(branch_node.get("q", 0)), int(branch_node.get("r", 0)))
		for stage_id in route:
			var node := ChapterMapLoaderScript.node_for_stage(definition, str(stage_id))
			if node.is_empty():
				continue
			var target := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
			var path := MacroWorldGeneratorScript.route_line(previous, target)
			for point_index in range(maxi(0, path.size() - 1)):
				var from_coord: Vector2i = path[point_index]
				var to_coord: Vector2i = path[point_index + 1]
				var from := HexCoordScript.axial_to_world(from_coord, TILE_SIZE, float(grid.tile(from_coord).get("elevation", 0)) * ELEVATION_STEP + 0.032)
				var to := HexCoordScript.axial_to_world(to_coord, TILE_SIZE, float(grid.tile(to_coord).get("elevation", 0)) * ELEVATION_STEP + 0.032)
				var direction := (to - from).normalized()
				var tangent := Vector3(-direction.z, 0.0, direction.x)
				_add_causeway_segment(shoulder_mesh, from + Vector3(0.0, 0.034, 0.0), to + Vector3(0.0, 0.034, 0.0), tangent, 0.48)
				_add_causeway_segment(base_mesh, from, to, tangent, 0.36)
				_add_causeway_segment(inlay_mesh, from + Vector3(0.0, 0.012, 0.0), to + Vector3(0.0, 0.012, 0.0), tangent, 0.055)
				causeway_segment_count += 1
				if OS.has_feature("web") and causeway_segment_count % WEB_STREAM_BUILD_BATCH == 0:
					await _finish_web_build_slice("causeway_segments", Time.get_ticks_usec())
					if not _web_async_owner_alive():
						return
			landing_cells[HexCoordScript.key(target)] = target
			previous = target
	# Selected encounter coordinates can move along their authored patrol route.
	# Treat those few cells as part of the same landmark clearing rather than
	# forcing the squad/enemy visual to depend on a single static node center.
	for patrol_value in definition.get("patrols", []):
		var patrol: Dictionary = patrol_value
		for route_value in patrol.get("patrol_route_hexes", []):
			var route_coord := Vector2i(int(route_value.get("q", 0)), int(route_value.get("r", 0)))
			if grid.traversable(route_coord):
				landing_cells[HexCoordScript.key(route_coord)] = route_coord
	var landing_keys: Array = landing_cells.keys()
	landing_keys.sort()
	for landing_key in landing_keys:
		var landing_coord: Vector2i = landing_cells[landing_key]
		var platform_center := HexCoordScript.axial_to_world(landing_coord, TILE_SIZE, float(grid.tile(landing_coord).get("elevation", 0)) * ELEVATION_STEP + 0.047)
		_add_route_landing(landing_mesh, platform_center, 1.38)
		_add_route_landing_edge(landing_edge_mesh, platform_center, 1.38, 0.20)
	shoulder_mesh.surface_end()
	landing_mesh.surface_end()
	landing_edge_mesh.surface_end()
	base_mesh.surface_end()
	inlay_mesh.surface_end()
	if shoulder_mesh.get_surface_count() > 0:
		var shoulder_instance := MeshInstance3D.new()
		shoulder_instance.name = "SignalRouteGroundShoulder"
		shoulder_instance.mesh = shoulder_mesh
		world_root.add_child(shoulder_instance)
	if landing_mesh.get_surface_count() > 0:
		var landing_instance := MeshInstance3D.new()
		landing_instance.name = "SignalRouteLandingTerraces"
		landing_instance.mesh = landing_mesh
		world_root.add_child(landing_instance)
	if landing_edge_mesh.get_surface_count() > 0:
		var landing_edge_instance := MeshInstance3D.new()
		landing_edge_instance.name = "SignalRouteLandingEdges"
		landing_edge_instance.mesh = landing_edge_mesh
		world_root.add_child(landing_edge_instance)
	if base_mesh.get_surface_count() > 0:
		var base_instance := MeshInstance3D.new()
		base_instance.name = "SignalRouteCauseway"
		base_instance.mesh = base_mesh
		world_root.add_child(base_instance)
	if inlay_mesh.get_surface_count() > 0:
		var inlay_instance := MeshInstance3D.new()
		inlay_instance.name = "SignalRouteInlay"
		inlay_instance.mesh = inlay_mesh
		world_root.add_child(inlay_instance)

func _normal_route_polyline() -> Array[Vector2i]:
	var route_points: Array[Vector2i] = []
	var previous := Vector2i(int(definition.get("start_hex", {}).get("q", 0)), int(definition.get("start_hex", {}).get("r", 0)))
	route_points.append(previous)
	for stage_id_value in definition.get("normal_route", []):
		var node := ChapterMapLoaderScript.node_for_stage(definition, str(stage_id_value))
		if node.is_empty():
			continue
		var target := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
		var segment: Array[Vector2i] = MacroWorldGeneratorScript.route_line(previous, target)
		# Consecutive authored stage segments share one endpoint. Keep it once so the
		# visual river has one continuous vertex authority across stage boundaries.
		for segment_index in range(1, segment.size()):
			var coord: Vector2i = segment[segment_index]
			if route_points.back() != coord:
				route_points.append(coord)
		previous = target
	return route_points

func _waterway_surface_y(world_position: Vector3) -> float:
	var coord := HexCoordScript.world_to_axial(world_position, TILE_SIZE)
	var tile: Dictionary = grid.tile(coord)
	# Web's exact-footprint terrain sits at elevation + 0.018.  A 0.052 offset
	# leaves the water at least 0.034 above that surface, preventing the former
	# presentation strip from being buried while leaving movement data untouched.
	return float(tile.get("elevation", 0)) * ELEVATION_STEP + 0.052

func _create_signal_waterway() -> void:
	# This is presentation-only: it follows the complete NORMAL route beside the
	# expedition spine but never adds, removes or changes a traversable tile.  The
	# old strip sat at y=-0.24 inside the four-cell land corridor, so almost all of
	# it was hidden below terrain and only a cyan fragment survived at screen edge.
	var water_mesh := ImmediateMesh.new()
	var bank_mesh := ImmediateMesh.new()
	var glint_mesh := ImmediateMesh.new()
	water_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("287f88"), Color("13565f")))
	bank_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("59604a"), Color("2b352d")))
	var glint_started := false
	var route_coords := _normal_route_polyline()
	var route_world: Array[Vector3] = []
	for coord in route_coords:
		route_world.append(HexCoordScript.axial_to_world(coord, TILE_SIZE))
	var river_points: Array[Vector3] = []
	var river_sides: Array[Vector3] = []
	var previous_side := Vector3.ZERO
	for point_index in range(route_world.size()):
		var current: Vector3 = route_world[point_index]
		var incoming: Vector3 = (route_world[point_index] - route_world[point_index - 1]) if point_index > 0 else (route_world[mini(1, route_world.size() - 1)] - current)
		var outgoing: Vector3 = (route_world[point_index + 1] - current) if point_index < route_world.size() - 1 else incoming
		incoming.y = 0.0
		outgoing.y = 0.0
		if incoming.length_squared() <= 0.0001:
			incoming = outgoing
		if outgoing.length_squared() <= 0.0001:
			outgoing = incoming
		incoming = incoming.normalized()
		outgoing = outgoing.normalized()
		var incoming_side := Vector3(-incoming.z, 0.0, incoming.x)
		var outgoing_side := Vector3(-outgoing.z, 0.0, outgoing.x)
		# Preserve one bank side through every greedy-route turn. Without this sign
		# continuity, a local tangent can flip and jump the river across the route.
		if previous_side != Vector3.ZERO:
			if incoming_side.dot(previous_side) < 0.0:
				incoming_side = -incoming_side
			if outgoing_side.dot(previous_side) < 0.0:
				outgoing_side = -outgoing_side
		var side := incoming_side + outgoing_side
		if side.length_squared() <= 0.0001:
			side = previous_side if previous_side != Vector3.ZERO else incoming_side
		side = side.normalized()
		if previous_side != Vector3.ZERO and side.dot(previous_side) < 0.0:
			side = -side
		previous_side = side
		var alignment := maxf(0.78, minf(absf(side.dot(incoming_side)), absf(side.dot(outgoing_side))))
		var meander := sin(float(point_index) * 0.41 + float(route_coords[point_index].x) * 0.071 - float(route_coords[point_index].y) * 0.113) * 0.26
		var lateral_offset := clampf((2.72 + meander) / alignment, 2.45, 3.35)
		var river_point := current + side * lateral_offset
		river_point.y = _waterway_surface_y(river_point)
		river_points.append(river_point)
		river_sides.append(side)
	var water_half_width := 0.74
	var bank_half_width := 0.12
	var bank_offset := water_half_width + bank_half_width + 0.02
	for point_index in range(maxi(0, river_points.size() - 1)):
		var river_from: Vector3 = river_points[point_index]
		var river_to: Vector3 = river_points[point_index + 1]
		var horizontal_direction := river_to - river_from
		horizontal_direction.y = 0.0
		if horizontal_direction.length_squared() <= 0.0001:
			continue
		horizontal_direction = horizontal_direction.normalized()
		var tangent := Vector3(-horizontal_direction.z, 0.0, horizontal_direction.x)
		_add_causeway_segment(water_mesh, river_from, river_to, tangent, water_half_width)
		_add_causeway_segment(bank_mesh, river_from + tangent * bank_offset + Vector3(0.0, .028, 0.0), river_to + tangent * bank_offset + Vector3(0.0, .028, 0.0), tangent, bank_half_width)
		_add_causeway_segment(bank_mesh, river_from - tangent * bank_offset + Vector3(0.0, .028, 0.0), river_to - tangent * bank_offset + Vector3(0.0, .028, 0.0), tangent, bank_half_width)
		if OS.has_feature("web") and point_index > 0 and point_index % WEB_STREAM_BUILD_BATCH == 0:
			await _finish_web_build_slice("waterway_segments", Time.get_ticks_usec())
			if not _web_async_owner_alive():
				return
		if point_index % 4 == 1:
			if not glint_started:
				glint_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material(Color("6fc7c4"), Color("236f73")))
				glint_started = true
			_add_causeway_segment(glint_mesh, river_from + Vector3(0.0, .012, 0.0), river_to + Vector3(0.0, .012, 0.0), tangent, .042)
		if point_index <= 0 or point_index >= river_points.size() - 1:
			continue
		var previous_direction := river_points[point_index] - river_points[point_index - 1]
		var next_direction := river_points[point_index + 1] - river_points[point_index]
		previous_direction.y = 0.0
		next_direction.y = 0.0
		if previous_direction.normalized().dot(next_direction.normalized()) >= 0.998:
			continue
		# Caps live in the existing three batches, so bends close without adding a
		# MeshInstance or draw call and the strip reads as one river rather than tiles.
		_add_route_landing(water_mesh, river_points[point_index] + Vector3(0.0, .001, 0.0), water_half_width)
		_add_route_landing(bank_mesh, river_points[point_index] + river_sides[point_index] * bank_offset + Vector3(0.0, .028, 0.0), bank_half_width)
		_add_route_landing(bank_mesh, river_points[point_index] - river_sides[point_index] * bank_offset + Vector3(0.0, .028, 0.0), bank_half_width)
	water_mesh.surface_end()
	bank_mesh.surface_end()
	if glint_started:
		glint_mesh.surface_end()
	for entry in [
		{"name": "ContinuousRouteRiver", "mesh": water_mesh},
		{"name": "ContinuousRiverBanks", "mesh": bank_mesh},
		{"name": "RiverCurrentGlints", "mesh": glint_mesh},
	]:
		var mesh: ImmediateMesh = entry.mesh
		if mesh.get_surface_count() <= 0:
			continue
		var instance := MeshInstance3D.new()
		instance.name = str(entry.name)
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(instance)

func _add_causeway_segment(mesh: ImmediateMesh, from: Vector3, to: Vector3, tangent: Vector3, half_width: float) -> void:
	var from_left := from - tangent * half_width
	var from_right := from + tangent * half_width
	var to_left := to - tangent * half_width
	var to_right := to + tangent * half_width
	# Match Godot's clockwise front-face convention used by the connected terrain.
	# CULL_BACK stays on; this is the real visual surface rather than a two-sided
	# safety mask.
	for vertex in [from_left, to_left, to_right, from_left, to_right, from_right]:
		mesh.surface_add_vertex(vertex)

func _add_route_landing(mesh: ImmediateMesh, center: Vector3, radius: float) -> void:
	# Softened twelve-sided terraces are encounter clearings and signal docks,
	# deliberately distinct from the mathematical six-sided selection grid.
	var points: Array[Vector3] = []
	for index in range(12):
		var angle := float(index) * TAU / 12.0 + PI / 12.0
		var irregularity := 0.92 if index % 2 == 0 else 1.0
		points.append(center + Vector3(cos(angle) * radius * irregularity, 0.0, sin(angle) * radius * irregularity))
	for index in range(points.size()):
		mesh.surface_add_vertex(center)
		mesh.surface_add_vertex(points[index])
		mesh.surface_add_vertex(points[(index + 1) % points.size()])

func _add_route_landing_edge(mesh: ImmediateMesh, center: Vector3, radius: float, depth: float) -> void:
	# A shallow irregular skirt gives each encounter clearing a readable height
	# break without reintroducing a field of isolated hex columns.
	var top_points: Array[Vector3] = []
	var bottom_points: Array[Vector3] = []
	for index in range(12):
		var angle := float(index) * TAU / 12.0 + PI / 12.0
		var irregularity := 0.92 if index % 2 == 0 else 1.0
		var top := center + Vector3(cos(angle) * radius * irregularity, 0.0, sin(angle) * radius * irregularity)
		top_points.append(top)
		bottom_points.append(top - Vector3(0.0, depth, 0.0))
	for index in range(top_points.size()):
		var next_index := (index + 1) % top_points.size()
		for vertex in [top_points[index], bottom_points[index], bottom_points[next_index], top_points[index], bottom_points[next_index], top_points[next_index]]:
			mesh.surface_add_vertex(vertex)

func _create_world_island_shelf() -> void:
	# The tactical grid remains mathematical, but its visual support is an
	# authored coastline.  This is deliberately sized from the complete route,
	# not the first streamed screen: a long chapter must not turn back into a
	# sequence of detached island-board pieces as the squad walks away from start.
	var route_points: Array[Vector3] = []
	for node in definition.get("nodes", []):
		if str(node.get("node_type", "")) == "START" or str(node.get("stage_id", "")) != "":
			route_points.append(HexCoordScript.axial_to_world(Vector2i(int(node.get("q", 0)), int(node.get("r", 0))), TILE_SIZE))
	if route_points.is_empty():
		route_points.append(Vector3.ZERO)
	var min_x := route_points[0].x
	var max_x := route_points[0].x
	var min_z := route_points[0].z
	var max_z := route_points[0].z
	for point in route_points:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
	var shelf_center := Vector3((min_x + max_x) * 0.5, -0.95, (min_z + max_z) * 0.5)
	# A broad tapered shelf sits beneath the entire authored route.  The edge is
	# intentionally well outside the local stream radius, so it reads as a coast
	# at chapter scale rather than as an artificial blue hex perimeter.
	var shelf_radius := maxf(max_x - min_x, max_z - min_z * 1.2) * 0.58 + 14.0
	var shelf_aspect := Vector3(1.18, 1.0, 0.62)
	var deep_shelf := MeshInstance3D.new()
	var deep_mesh := CylinderMesh.new()
	deep_mesh.top_radius = shelf_radius
	deep_mesh.bottom_radius = shelf_radius + 2.8
	deep_mesh.height = 0.82
	deep_mesh.radial_segments = 36
	deep_shelf.mesh = deep_mesh
	deep_shelf.position = shelf_center
	deep_shelf.scale = shelf_aspect
	deep_shelf.material_override = _material(Color("12322f"), Color("082c2b"))
	world_root.add_child(deep_shelf)
	var moss_shelf := MeshInstance3D.new()
	var moss_mesh := CylinderMesh.new()
	moss_mesh.top_radius = shelf_radius - 2.2
	moss_mesh.bottom_radius = shelf_radius - 0.9
	moss_mesh.height = 0.34
	moss_mesh.radial_segments = 36
	moss_shelf.mesh = moss_mesh
	moss_shelf.position = shelf_center + Vector3(0.0, 0.48, 0.0)
	moss_shelf.scale = shelf_aspect
	moss_shelf.material_override = _material(Color("234e43"), Color("103b38"))
	world_root.add_child(moss_shelf)
	_create_landmass_formations(route_points)
	_create_coastal_landmarks(route_points, shelf_center, shelf_radius, shelf_aspect)
	_create_deep_water_reef_silhouettes(route_points, shelf_center, shelf_radius, shelf_aspect)

func _create_coastal_landmarks(route_points: Array[Vector3], shelf_center: Vector3, shelf_radius: float, shelf_aspect: Vector3) -> void:
	# The coast needs its own silhouette and small points of interest. These are
	# sparse Blender-kit reefs, foam arcs and abandoned signal pieces—not a
	# blanket of decorative particles—so open water reads as an explorable shore
	# instead of an empty teal board boundary.
	if route_points.is_empty():
		return
	var coast_anchors: Array[Dictionary] = [
		{"point": route_points[mini(1, route_points.size() - 1)] + Vector3(4.2, -0.49, 1.4), "scale": 1.40, "yaw": 0.20},
		{"point": route_points[mini(3, route_points.size() - 1)] + Vector3(4.6, -0.49, 0.8), "scale": 1.64, "yaw": -0.18},
		{"point": route_points[mini(4, route_points.size() - 1)] + Vector3(4.1, -0.49, -1.7), "scale": 1.36, "yaw": 0.46},
		{"point": route_points[route_points.size() / 2] + Vector3(3.4, -0.49, -2.5), "scale": 1.12, "yaw": -0.52},
		{"point": route_points[mini(7, route_points.size() - 1)] + Vector3(4.3, -0.49, 1.5), "scale": 1.42, "yaw": 0.08},
		{"point": route_points[route_points.size() - 2] + Vector3(4.8, -0.49, 1.0), "scale": 1.55, "yaw": 0.72}
	]
	for coast in coast_anchors:
		var point: Vector3 = coast.point
		var scale_factor := float(coast.scale)
		var yaw := float(coast.yaw)
		_spawn_kit_components("PROP_COAST_FOAM", point, scale_factor, yaw)
		_spawn_kit_component("PROP_CLIFF_FACET_A", point + Vector3(-0.42, 0.10, 0.24), scale_factor * 0.72, yaw)
		_spawn_kit_component("PROP_CLIFF_FACET_B", point + Vector3(0.36, 0.06, -0.22), scale_factor * 0.56, yaw + 0.44)
		if int(absf(point.x)) % 2 == 0:
			_spawn_kit_components("PROP_SIGNAL_BEACON", point + Vector3(-0.34, 0.08, 0.38), scale_factor * 0.44, yaw - 0.24)
	# A few low, broad reflected bands give the water a shoreline rhythm at the
	# wide zoom without adding a texture atlas or a continuous particle cost.
	for band_index in range(4):
		var band := MeshInstance3D.new()
		var band_mesh := TorusMesh.new()
		band_mesh.inner_radius = 1.25 + float(band_index) * 0.52
		band_mesh.outer_radius = band_mesh.inner_radius + 0.026
		band_mesh.rings = 24
		band_mesh.ring_segments = 8
		band.mesh = band_mesh
		band.position = shelf_center + Vector3(shelf_radius * shelf_aspect.x * 0.36 + float(band_index) * 2.4, -0.535, -shelf_radius * shelf_aspect.z * 0.34 + float(band_index % 2) * 3.8)
		band.scale = Vector3(1.85, 0.18, 0.62)
		band.rotation_degrees = Vector3(0.0, 18.0 + float(band_index) * 11.0, 0.0)
		var water_line := _material(Color("3d8f98"), Color("116c76"))
		water_line.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_line.albedo_color.a = 0.44
		water_line.emission_energy_multiplier = 0.42
		band.material_override = water_line
		world_root.add_child(band)

func _create_deep_water_reef_silhouettes(route_points: Array[Vector3], shelf_center: Vector3, shelf_radius: float, shelf_aspect: Vector3) -> void:
	# Two or three broad silhouettes are much more useful at overview scale than
	# dozens of tiny foam marks.  They intentionally sit well away from routes so
	# they add deep-water identity without suggesting a traversable side path.
	if route_points.is_empty():
		return
	var reef_anchors: Array[Dictionary] = [
		{"point": shelf_center + Vector3(shelf_radius * shelf_aspect.x * 0.34, -0.46, -shelf_radius * shelf_aspect.z * 0.23), "scale": 2.25, "yaw": 0.42},
		{"point": shelf_center + Vector3(shelf_radius * shelf_aspect.x * 0.18, -0.48, shelf_radius * shelf_aspect.z * 0.38), "scale": 1.72, "yaw": -0.24},
		{"point": shelf_center + Vector3(-shelf_radius * shelf_aspect.x * 0.28, -0.49, shelf_radius * shelf_aspect.z * 0.20), "scale": 1.48, "yaw": 0.74},
	]
	for reef in reef_anchors:
		var point: Vector3 = reef.point
		var scale_factor := float(reef.scale)
		var yaw := float(reef.yaw)
		_spawn_kit_component("PROP_CLIFF_FACET_A", point, scale_factor, yaw)
		_spawn_kit_component("PROP_CLIFF_FACET_B", point + Vector3(0.48, 0.08, -0.34), scale_factor * 0.66, yaw + 0.38)
		_spawn_kit_components("PROP_COAST_FOAM", point + Vector3(-0.22, -0.045, 0.20), scale_factor * 0.82, yaw - 0.16)

func _create_landmass_formations(route_points: Array[Vector3]) -> void:
	# Three deliberately broad relief shelves bind local hex cells into memorable
	# terrain districts. They sit under, never over, walkable cells: gameplay
	# still reads mathematical axial tiles while the map stops looking like an
	# isolated collection of identical columns.
	if route_points.size() < 3:
		return
	for formation_definition in [
		{"index": 1, "prefix": "RELIEF_FOREST_MESA_A", "radius": 8.8, "aspect": Vector3(1.55, 1.0, 0.68), "color": Color("1b4a41"), "height": 0.42},
		{"index": route_points.size() / 2, "prefix": "RELIEF_RUIN_TERRACE_B", "radius": 10.5, "aspect": Vector3(1.42, 1.0, 0.72), "color": Color("24463d"), "height": 0.58},
		{"index": route_points.size() - 2, "prefix": "RELIEF_COAST_SHELF_C", "radius": 9.4, "aspect": Vector3(1.36, 1.0, 0.70), "color": Color("244b49"), "height": 0.48}
	]:
		var anchor: Vector3 = route_points[int(formation_definition.index)]
		var anchor_coord := HexCoordScript.world_to_axial(anchor, TILE_SIZE)
		var anchor_surface := float(grid.tile(anchor_coord).get("elevation", 0)) * ELEVATION_STEP
		# The authored relief becomes the large continuous district floor. A very
		# small offset keeps it above the individual mathematical cells, visually
		# breaking up the old disconnected-hex-column silhouette without changing
		# pathing, collision, or the source axial coordinates.
		var relief_parts := _spawn_kit_components(str(formation_definition.prefix), anchor + Vector3(0.0, anchor_surface + 0.02, 0.0), 1.0, 0.0)
		if not relief_parts.is_empty():
			# Source meshes are authored at a compact reusable scale. Expand only
			# X/Z here so they become a connected district floor while preserving
			# the shallow strata height under the gameplay tile caps.
			var lateral_scale := float(formation_definition.radius) / 3.4
			for relief_part in relief_parts:
				relief_part.scale.x *= lateral_scale * float(formation_definition.aspect.x)
				relief_part.scale.z *= lateral_scale * float(formation_definition.aspect.z)
			var ridge_parts := _spawn_kit_components("RELIEF_RIDGE_A", anchor + Vector3(0.0, anchor_surface + 0.16, 0.0), 0.90, float(int(formation_definition.index) % 3) * 0.48)
			for ridge_part in ridge_parts:
				ridge_part.scale.x *= lateral_scale * 0.85
				ridge_part.scale.z *= lateral_scale * 0.58
			continue
		var formation := MeshInstance3D.new()
		formation.name = "TerrainLandmassFormation"
		var formation_mesh := CylinderMesh.new()
		formation_mesh.top_radius = float(formation_definition.radius)
		formation_mesh.bottom_radius = float(formation_definition.radius) + 1.2
		formation_mesh.height = float(formation_definition.height)
		formation_mesh.radial_segments = 9
		formation.mesh = formation_mesh
		formation.scale = formation_definition.aspect
		formation.rotation_degrees.y = 18.0 + float(int(formation_definition.index) % 3) * 14.0
		formation.position = anchor + Vector3(0.0, -0.52, 0.0)
		formation.material_override = _material(formation_definition.color, formation_definition.color.darkened(0.58))
		world_root.add_child(formation)

func _load_blender_kit() -> void:
	var kit_path := "res://assets/art/chapter_map/R11/CH01_MAP_KIT_R11.glb"
	if not ResourceLoader.exists(kit_path): return
	var packed := load(kit_path) as PackedScene
	if packed == null: return
	var kit := packed.instantiate()
	_collect_kit_meshes(kit)
	kit.free()

func _load_terrain_relief() -> void:
	# This project-owned source is built headlessly by tools/blender and is kept
	# separate from asset_share so shared generator originals are never mutated.
	var relief_path := "res://assets/art/chapter_map/R7/CH01_TERRAIN_RELIEF_R7.glb"
	if not ResourceLoader.exists(relief_path): return
	var packed := load(relief_path) as PackedScene
	if packed == null: return
	var relief := packed.instantiate()
	_collect_kit_meshes(relief)
	relief.free()

func _collect_kit_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		blender_mesh_library[str(node.name)] = {
			"mesh": mesh_node.mesh,
			"scale": mesh_node.scale,
			"rotation": mesh_node.rotation
		}
	for child in node.get_children(): _collect_kit_meshes(child)

func _kit_mesh_for(terrain: String) -> Mesh:
	var prefix: String = str({
		"FOREST": "HEX_FOREST_",
		"ROAD": "HEX_ROAD_",
		"RUINS": "HEX_RUIN_",
		"SHALLOW_WATER": "HEX_WATER_",
		"DEEP_WATER": "HEX_DEEP_"
	}.get(terrain, "HEX_FOREST_"))
	for key in blender_mesh_library:
		if str(key).begins_with(prefix): return blender_mesh_library[key].mesh
	return null

func _terrain_cap_top_material(terrain: String, coord: Vector2i) -> StandardMaterial3D:
	# Imported cap meshes preserve their bevel and separate side surface, while
	# this small palette cache prevents every streamed forest hex from sharing one
	# chalky top colour.  Four stable, low-chroma families read as weathered land
	# rather than painted tabletop tokens.
	var phase: int = abs(coord.x * 7 + coord.y * 11) % 4
	var key := "%s_%d" % [terrain, phase]
	if terrain_cap_material_cache.has(key):
		return terrain_cap_material_cache[key]
	var colors: Array[Color] = [Color("30463b"), Color("354c40"), Color("3a5143"), Color("2d4339")]
	match terrain:
		"ROAD": colors = [Color("6d5b3d"), Color("786544"), Color("625239"), Color("806c49")]
		"RUINS": colors = [Color("464f5b"), Color("505864"), Color("3f4955"), Color("59616b")]
	var material := _material(colors[phase])
	material.roughness = 0.88
	terrain_cap_material_cache[key] = material
	return material

func _player_map_coord() -> Vector2i:
	return Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))

func _player_vision_radius() -> int:
	return clampi(MapExplorationServiceScript.player_vision_radius(AppState.profile, definition), BASE_PLAYER_VISION_RADIUS, MAX_PLAYER_VISION_RADIUS)

func _coord_is_in_player_vision(coord: Vector2i) -> bool:
	return HexCoordScript.distance(_player_map_coord(), coord) <= _player_vision_radius()

func _player_vision_allowlist() -> Dictionary:
	var allowed: Dictionary = {}
	var center := _player_map_coord()
	for tile_value in definition.get("tiles", []):
		var tile: Dictionary = tile_value
		var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		if HexCoordScript.distance(center, coord) <= _player_vision_radius():
			allowed[HexCoordScript.key(coord)] = true
	return allowed

func _fog_material() -> ShaderMaterial:
	if fog_of_war_material == null:
		fog_of_war_material = ShaderMaterial.new()
		fog_of_war_material.shader = FogOfWarShader
		fog_of_war_material.render_priority = 96
	return fog_of_war_material

func _streamed_infill_material() -> StandardMaterial3D:
	if streamed_infill_material == null:
		if OS.has_feature("web") and WebSoakProbe.has_method("web_render_resource"):
			var warmed_terrain = WebSoakProbe.web_render_resource("terrain_material")
			if warmed_terrain is StandardMaterial3D:
				streamed_infill_material = warmed_terrain
		if streamed_infill_material == null:
			streamed_infill_material = StandardMaterial3D.new()
			streamed_infill_material.vertex_color_use_as_albedo = true
			streamed_infill_material.roughness = 0.94
			# Compatibility/Web can disagree on generated X/Z fan winding. This mesh is
			# a ground-only seam seal, so render both faces and never expose black holes.
			streamed_infill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return streamed_infill_material

func _update_screen_fog_overlay() -> void:
	if fog_screen_overlay == null or not is_instance_valid(fog_screen_overlay) or fog_screen_material == null or camera == null or not is_instance_valid(camera) or viewport == null or not is_instance_valid(viewport):
		return
	var overlay_size := fog_screen_overlay.size
	if overlay_size.x <= 1.0 or overlay_size.y <= 1.0:
		return
	var viewport_size := Vector2(viewport.size)
	var surface_scale := overlay_size / viewport_size
	# Follow the actual tweened pawn instead of the discrete saved hex. The old
	# logical projection made the circular vision mask jump once per cell even
	# while the character and camera moved continuously.
	var squad_world := pawn.global_position if pawn != null and is_instance_valid(pawn) else _pawn_world_position()
	var sight_edge_world := squad_world + Vector3(sqrt(3.0) * TILE_SIZE * float(_player_vision_radius()), 0.0, 0.0)
	var squad_px := camera.unproject_position(squad_world) * surface_scale
	var edge_px := camera.unproject_position(sight_edge_world) * surface_scale
	fog_screen_material.set_shader_parameter("reveal_center_px", squad_px)
	fog_screen_material.set_shader_parameter("overlay_size_px", overlay_size)
	fog_screen_material.set_shader_parameter("reveal_radius_px", maxf(42.0, squad_px.distance_to(edge_px)))
	fog_screen_material.set_shader_parameter("feather_px", clampf(overlay_size.x * 0.035, 24.0, 64.0))

func _append_clear_ground_infill_tile(surface_tool: SurfaceTool, tile: Dictionary, visible_land: Dictionary) -> void:
	var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
	var surface_y := float(tile.get("elevation", 0)) * ELEVATION_STEP + 0.018
	var hex_center := HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y)
	var tint := _terrain_surface_color(tile)
	# Exact pointy-top hex fan. Neighbouring top faces meet on the same edge;
	# no enlarged cap is allowed to overlap another height level.
	for corner_index in range(6):
		var next_index := (corner_index + 1) % 6
		var angle_a := PI / 6.0 + float(corner_index) * PI / 3.0
		var angle_b := PI / 6.0 + float(next_index) * PI / 3.0
		var point_a := hex_center + Vector3(cos(angle_a) * TILE_SIZE, 0.0, sin(angle_a) * TILE_SIZE)
		var point_b := hex_center + Vector3(cos(angle_b) * TILE_SIZE, 0.0, sin(angle_b) * TILE_SIZE)
		for vertex in [hex_center, point_a, point_b]:
			surface_tool.set_color(tint)
			surface_tool.set_normal(Vector3.UP)
			surface_tool.add_vertex(vertex)
	# Only the higher tile authors a shared cliff. Coast/vision edges receive a
	# deeper skirt down towards the ocean, producing an island silhouette rather
	# than black holes or stacks of disconnected cylinders.
	for neighbor_coord in HexCoordScript.neighbors(coord):
		var neighbor_key := HexCoordScript.key(neighbor_coord)
		var neighbor_tile: Dictionary = visible_land.get(neighbor_key, {})
		var neighbor_is_land := not neighbor_tile.is_empty()
		var neighbor_y := float(neighbor_tile.get("elevation", 0)) * ELEVATION_STEP + 0.018 if neighbor_is_land else maxf(OCEAN_SURFACE_Y + 0.16, surface_y - 1.05)
		if neighbor_is_land and surface_y <= neighbor_y + 0.001:
			continue
		var neighbor_center := HexCoordScript.axial_to_world(neighbor_coord, TILE_SIZE, surface_y)
		var outward := Vector3(neighbor_center.x - hex_center.x, 0.0, neighbor_center.z - hex_center.z).normalized()
		var tangent := Vector3(-outward.z, 0.0, outward.x)
		var edge_center := (hex_center + neighbor_center) * 0.5
		var edge_a_top := edge_center + tangent * (TILE_SIZE * 0.5)
		var edge_b_top := edge_center - tangent * (TILE_SIZE * 0.5)
		var edge_a_bottom := Vector3(edge_a_top.x, neighbor_y, edge_a_top.z)
		var edge_b_bottom := Vector3(edge_b_top.x, neighbor_y, edge_b_top.z)
		var cliff_tint := tint.darkened(0.30 if neighbor_is_land else 0.42)
		for vertex in [edge_a_top, edge_b_bottom, edge_b_top, edge_a_top, edge_a_bottom, edge_b_bottom]:
			surface_tool.set_color(cliff_tint)
			surface_tool.set_normal(outward)
			surface_tool.add_vertex(vertex)

func _refresh_clear_ground_infill(center: Vector2i, radius_override := -1, cooperative := false, full_map := false, coverage_override := {}) -> void:
	# Web owns one continuous, exact-footprint terrain mesh. The former 1.10x fan
	# overlapped neighbouring cells and visually flattened every ridge into a
	# checkerboard. Exact shared edges plus vertical cliff faces preserve the real
	# authored elevation while retaining a single draw call and grid-authoritative
	# movement/collision.
	var vision_radius := radius_override if radius_override >= 0 else _player_vision_radius()
	var visible_land: Dictionary = {}
	var scanned_count := 0
	var source_tiles: Array = coverage_override.values() if not coverage_override.is_empty() else definition.get("tiles", [])
	for tile_value in source_tiles:
		scanned_count += 1
		if cooperative and scanned_count % (WEB_STREAM_BUILD_BATCH * 4) == 0:
			await _finish_web_build_slice("infill_scan", Time.get_ticks_usec())
			if not _web_async_owner_alive():
				return
		var tile: Dictionary = tile_value
		var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		if not full_map and HexCoordScript.distance(center, coord) > vision_radius:
			continue
		if str(tile.get("terrain_type", "")) in ["SHALLOW_WATER", "DEEP_WATER"]:
			continue
		visible_land[HexCoordScript.key(coord)] = tile
	# On Web, committing one 250+ tile SurfaceTool and assigning it to the renderer
	# still formed one 100ms+ frame even though vertex generation itself yielded.
	# Register bounded mesh chunks while the replacement root is hidden and already
	# inside the scene tree; the browser can upload each chunk on a separate frame.
	if cooperative and OS.has_feature("web"):
		var next_root := Node3D.new()
		next_root.name = "StreamedContinuousTerrainNext"
		# Keep it render-active a hair below the previous surface. Hidden/off-camera
		# geometry was uploaded lazily on the final reveal; visible in-tree chunks are
		# prepared as they arrive while the old surface prevents any partial-map gap.
		next_root.position = Vector3(0.0, -0.002, 0.0)
		world_root.add_child(next_root)
		# Full entry coverage must remain spatial for frustum culling.  Dictionary
		# order would mix opposite ends of the campaign into every mesh, making a
		# supposedly chunked map behave like one giant always-visible draw.
		var spatial_chunks: Dictionary = {}
		for visible_key_value in visible_land.keys():
			var visible_key := str(visible_key_value)
			var visible_coord := HexCoordScript.from_key(visible_key)
			var spatial_key := _web_spatial_chunk_key(visible_coord, WEB_ENTRY_TERRAIN_CHUNK_SPAN) if full_map else "local"
			if not spatial_chunks.has(spatial_key):
				spatial_chunks[spatial_key] = []
			var chunk_keys: Array = spatial_chunks[spatial_key]
			chunk_keys.append(visible_key)
			spatial_chunks[spatial_key] = chunk_keys
		var spatial_chunk_keys: Array = spatial_chunks.keys()
		spatial_chunk_keys.sort()
		var first_instance: MeshInstance3D
		var chunk_index := 0
		var tile_batch_size := WEB_ENTRY_TERRAIN_TILE_BATCH if full_map else WEB_INFILL_TILE_BATCH
		for spatial_key_value in spatial_chunk_keys:
			var spatial_key := str(spatial_key_value)
			var visible_keys: Array = spatial_chunks[spatial_key]
			visible_keys.sort()
			for chunk_start in range(0, visible_keys.size(), tile_batch_size):
				var chunk_started_usec := Time.get_ticks_usec()
				var surface_tool := SurfaceTool.new()
				surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				var chunk_end := mini(chunk_start + tile_batch_size, visible_keys.size())
				for tile_index in range(chunk_start, chunk_end):
					_append_clear_ground_infill_tile(surface_tool, visible_land[visible_keys[tile_index]], visible_land)
				var infill_mesh := surface_tool.commit()
				var chunk_instance := MeshInstance3D.new()
				chunk_instance.name = "StreamedContinuousTerrain_%s_%02d" % [spatial_key.replace(",", "_"), chunk_index]
				chunk_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				chunk_instance.material_override = _streamed_infill_material()
				chunk_instance.mesh = infill_mesh
				next_root.add_child(chunk_instance)
				if first_instance == null:
					first_instance = chunk_instance
				chunk_index += 1
				await _finish_web_build_slice("infill_chunk_%02d" % (chunk_index - 1), chunk_started_usec)
				if not _web_async_owner_alive():
					return
		var previous_root := streamed_infill_root
		var previous_instance := streamed_infill_instance
		streamed_infill_root = next_root
		streamed_infill_root.name = "StreamedContinuousTerrain"
		streamed_infill_instance = first_instance
		streamed_infill_root.position = Vector3.ZERO
		if previous_root != null and is_instance_valid(previous_root):
			_retire_web_render_root(previous_root)
		elif previous_instance != null and is_instance_valid(previous_instance) and previous_instance != first_instance:
			previous_instance.queue_free()
		return
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for key_value in visible_land.keys():
		_append_clear_ground_infill_tile(surface_tool, visible_land[key_value], visible_land)
	var infill_mesh := surface_tool.commit()
	if streamed_infill_instance == null or not is_instance_valid(streamed_infill_instance):
		streamed_infill_instance = MeshInstance3D.new()
		streamed_infill_instance.name = "StreamedContinuousTerrain"
		streamed_infill_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		streamed_infill_instance.material_override = _streamed_infill_material()
		world_root.add_child(streamed_infill_instance)
	streamed_infill_instance.mesh = infill_mesh

func _refresh_fog_cover(center: Vector2i) -> void:
	if OS.has_feature("web"):
		# Web already owns the squad-centred screen shader and gates every pawn,
		# marker and click target with the same vision radius. Rebuilding an ~20-ring
		# 3D annulus (tens of thousands of vertices) after each move was redundant
		# and caused the long single-frame stalls reported on mobile browsers.
		if fog_cover_instance != null and is_instance_valid(fog_cover_instance):
			fog_cover_instance.visible = false
		return
	# One mesh covers the complete 11..18 hex annulus. This is both more legible
	# and cheaper than hundreds of individual fog nodes: the player sees a real
	# mist boundary even when the orthographic viewport extends well past ring 11.
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fog_ring_radius := _player_vision_radius() + 1
	for dq in range(-FOG_COVER_RADIUS, FOG_COVER_RADIUS + 1):
		for dr in range(-FOG_COVER_RADIUS, FOG_COVER_RADIUS + 1):
			var coord := center + Vector2i(dq, dr)
			var distance := HexCoordScript.distance(center, coord)
			if distance < fog_ring_radius or distance > FOG_COVER_RADIUS:
				continue
			var tile: Dictionary = grid.tile(coord)
			var cover_y := maxf(0.42, float(tile.get("elevation", 0)) * ELEVATION_STEP + 0.42)
			var hex_center := HexCoordScript.axial_to_world(coord, TILE_SIZE, cover_y)
			for corner_index in range(6):
				var next_index := (corner_index + 1) % 6
				var angle_a := PI / 6.0 + float(corner_index) * PI / 3.0
				var angle_b := PI / 6.0 + float(next_index) * PI / 3.0
				var point_a := hex_center + Vector3(cos(angle_a) * TILE_SIZE * 1.035, 0.0, sin(angle_a) * TILE_SIZE * 1.035)
				var point_b := hex_center + Vector3(cos(angle_b) * TILE_SIZE * 1.035, 0.0, sin(angle_b) * TILE_SIZE * 1.035)
				for vertex in [hex_center, point_a, point_b]:
					surface_tool.set_normal(Vector3.UP)
					surface_tool.set_uv(Vector2(vertex.x * 0.07, vertex.z * 0.07))
					surface_tool.add_vertex(vertex)
	var fog_mesh := surface_tool.commit()
	if fog_cover_instance == null or not is_instance_valid(fog_cover_instance):
		fog_cover_instance = MeshInstance3D.new()
		fog_cover_instance.name = "SquadVisionFogCurtain"
		fog_cover_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fog_cover_instance.material_override = _fog_material()
		fog_cover_instance.set_meta("fog_shell", true)
		world_root.add_child(fog_cover_instance)
	fog_cover_instance.mesh = fog_mesh

func _create_tile(tile: Dictionary) -> void:
	var coord := Vector2i(int(tile.q), int(tile.r))
	var terrain_type := str(tile.terrain_type)
	var surface_y := float(tile.elevation) * ELEVATION_STEP
	if not _coord_is_in_player_vision(coord):
		# Radius 11 is not terrain information. It is a depth-writing mist seal, so
		# distant elevation, props, enemies and loot cannot leak through the edge of
		# the clear ten-cell neighbourhood on either Web or desktop renderers.
		var fog_instance := MeshInstance3D.new()
		var fog_mesh := CylinderMesh.new()
		fog_mesh.top_radius = TILE_SIZE * 1.02
		fog_mesh.bottom_radius = TILE_SIZE * 1.04
		fog_mesh.height = 0.20
		fog_mesh.radial_segments = 6
		fog_instance.mesh = fog_mesh
		fog_instance.rotation_degrees.y = 30.0
		fog_instance.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, maxf(surface_y, 0.0) + 0.12)
		fog_instance.material_override = _fog_material()
		fog_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fog_instance.set_meta("tile", tile)
		fog_instance.set_meta("fog_shell", true)
		world_root.add_child(fog_instance)
		tile_meshes[HexCoordScript.key(coord)] = fog_instance
		return
	# Water is represented by the continuous tide field and island coastline.
	# It stays fully present in Grid data for pathing/reveal, without rendering a
	# literal hex-board sea around the land.
	if terrain_type in ["SHALLOW_WATER", "DEEP_WATER"]:
		return
	var instance := MeshInstance3D.new()
	# Prefer the authored Blender low-poly kit. It carries bevelled edge normals,
	# layered terrain materials, and avoids the old uniform runtime cylinder slab
	# impression. The small procedural cap remains only as a safe import fallback.
	var kit_prefix := str({"FOREST": "HEX_FOREST_", "ROAD": "HEX_ROAD_", "RUINS": "HEX_RUIN_"}.get(terrain_type, "HEX_FOREST_"))
	var kit_info := _kit_component(kit_prefix)
	if not kit_info.is_empty() and kit_info.get("mesh") is Mesh:
		var kit_mesh: Mesh = kit_info.get("mesh")
		instance.mesh = kit_mesh
		instance.scale = kit_info.get("scale", Vector3.ONE)
		# The authored cap intentionally had a presentation bevel, but its former
		# footprint left repeated black diamond holes where three map hexes meet.
		# A small X/Z overlap keeps the bevel while making the district read as one
		# continuous landmass. Collision and axial movement remain grid-authored.
		instance.scale.x *= 1.10
		instance.scale.z *= 1.10
		# The authored hex is now a thin readable surface accent, not the whole
		# landmass. Broad Blender relief carries the district silhouette below it;
		# this prevents the old black-walled column field while retaining precise
		# selectable hex locations for map input and accessibility.
		# Retain a substantial, dark-sided cap.  At the lower R7 scale a 2/3-height
		# terrace lost its vertical face at the gameplay camera distance.
		instance.scale.y *= 0.62
		instance.rotation = kit_info.get("rotation", Vector3.ZERO)
		# Blender add_hex exports material slot 0 as walkable top and slot 1 as its
		# separately-authored cliff wall. Do not flatten both with material_override:
		# only vary the top, retaining the darker height-reading side surface.
		instance.set_surface_override_material(0, _terrain_cap_top_material(terrain_type, coord))
		var kit_height := maxf(0.18, kit_mesh.get_aabb().size.y * instance.scale.y)
		instance.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y - kit_height * .5)
		instance.set_meta("blender_kit", true)
	else:
		var elevation := int(tile.elevation)
		var cap := CylinderMesh.new()
		cap.top_radius = TILE_SIZE * 1.03
		cap.bottom_radius = TILE_SIZE * (1.01 + minf(float(elevation), 3.0) * .025)
		cap.height = .10 + float(elevation) * .07
		cap.radial_segments = 6
		instance.mesh = cap
		instance.rotation_degrees.y = 30.0
		instance.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y - cap.height * .5)
		instance.set_meta("blender_kit", false)
	instance.set_meta("tile", tile)
	instance.set_meta("fog_shell", false)
	# The Blender-authored cap is the final local ground authority for streamed
	# macro districts. It is deliberately thin and bevelled—not the former tall
	# prototype prism—so it closes any continuous-surface seam while preserving
	# readable terrain, contact shadows and grounded pawns at every live hex.
	instance.visible = true
	world_root.add_child(instance)
	tile_meshes[HexCoordScript.key(coord)] = instance
	active_dressing_root = Node3D.new()
	active_dressing_root.name = "TerrainDressing_%s" % HexCoordScript.key(coord)
	world_root.add_child(active_dressing_root)
	tile_dressing_roots[HexCoordScript.key(coord)] = active_dressing_root
	var dressing_position := HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y)
	if OS.has_feature("web"):
		# Imported prop clusters are by far the most expensive part of Web map
		# construction.  Queue them after the playable ground is visible instead
		# of blocking stage entry on hundreds of tree/rail child meshes.
		pending_dressing_tiles.append({"tile": tile, "position": dressing_position, "coord": coord, "root": active_dressing_root})
	else:
		_create_terrain_dressing(tile, dressing_position, coord)
	active_dressing_root = null

func _process_pending_dressing() -> void:
	if pending_dressing_tiles.is_empty() or moving or turn_transitioning or not web_detail_assets_ready:
		return
	# Web deliberately avoids instantiating the desktop Blender prop kit at run
	# time. Do not keep executing empty authoring-cluster searches every frame;
	# the combined terrain, route, fog, encounter art and landmarks are already
	# sufficient gameplay presentation and remain smooth on mobile browsers.
	if OS.has_feature("web") and blender_mesh_library.is_empty():
		return
	# One authored cluster per frame keeps input/camera responsive on single-
	# threaded Web builds while the surrounding detail settles in naturally.
	var entry: Dictionary = pending_dressing_tiles.pop_front()
	var key := str(entry.get("key", ""))
	if not key.is_empty():
		pending_dressing_keys.erase(key)
		if OS.has_feature("web") and not streamed_ground_keys.has(key):
			return
	var root: Node3D = entry.get("root")
	if root == null and OS.has_feature("web"):
		root = tile_dressing_roots.get(key)
		if root == null or not is_instance_valid(root):
			root = Node3D.new()
			root.name = "TerrainDressing_%s" % key
			world_root.add_child(root)
			tile_dressing_roots[key] = root
	if root == null or not is_instance_valid(root) or root.is_queued_for_deletion():
		return
	active_dressing_root = root
	_create_terrain_dressing(entry.get("tile", {}), entry.get("position", Vector3.ZERO), entry.get("coord", Vector2i.ZERO))
	active_dressing_root = null

func _stream_web_visible_ground(wanted: Dictionary, requested_anchor: Vector2i) -> void:
	# The old Web path created one bevelled MeshInstance per clear hex, then a
	# second combined surface below it. That doubled draw/node work on every
	# stage entry and reward return. The combined infill already closes and tints
	# every live hex, so on Web it is the only required ground geometry.
	for key in tile_meshes.keys():
		var obsolete: MeshInstance3D = tile_meshes[key]
		if is_instance_valid(obsolete):
			obsolete.queue_free()
	tile_meshes.clear()
	# The browser never hydrates the heavyweight Blender dressing queue. Keeping
	# one dead entry per visible hex caused needless allocation on every move and
	# made long sessions progressively rougher, so Web owns one compact MultiMesh
	# presentation instead.
	pending_dressing_tiles.clear()
	pending_dressing_keys.clear()
	for key in tile_dressing_roots.keys():
		var stale_root: Node3D = tile_dressing_roots[key]
		if is_instance_valid(stale_root):
			stale_root.queue_free()
	tile_dressing_roots.clear()
	streamed_ground_keys.clear()
	for key_value in wanted.keys():
		var key := str(key_value)
		var tile: Dictionary = wanted[key]
		if str(tile.get("terrain_type", "")) in ["SHALLOW_WATER", "DEEP_WATER"]:
			continue
		streamed_ground_keys[key] = true
	web_pending_dressing_wanted = wanted.duplicate(true)
	web_pending_dressing_anchor = requested_anchor
	if not web_detail_assets_ready:
		return
	# Terrain/fog follows the squad immediately, while decorative MultiMeshes use
	# a three-cell hysteresis window. Rebuilding hundreds of tree transforms both
	# at move start and move end was a visible main-thread hitch on Web.
	if web_tactical_dressing_root == null or not is_instance_valid(web_tactical_dressing_root) or HexCoordScript.distance(web_dressing_anchor, requested_anchor) >= 3:
		await _rebuild_web_tactical_dressing(wanted)
		if not _web_async_owner_alive():
			return
		web_dressing_anchor = requested_anchor
		if web_pending_dressing_anchor == requested_anchor:
			web_pending_dressing_wanted.clear()

func _append_web_dressing_transform(
		transforms: Array[Transform3D],
		position: Vector3,
		scale_value: Vector3,
		rotation_y: float
	) -> void:
	var basis := Basis.IDENTITY.rotated(Vector3.UP, rotation_y).scaled(scale_value)
	transforms.append(Transform3D(basis, position))

func _web_dressing_transform_aabb(mesh: Mesh, transforms: Array[Transform3D]) -> AABB:
	# WebGL can retain the tiny source-mesh bounds after MultiMesh transforms are
	# uploaded in slices.  Supply the actual chunk-local bounds explicitly; this
	# fixes false frustum culling without falling back to one world-sized batch.
	var source_bounds := mesh.get_aabb()
	var bounds := AABB()
	var has_bounds := false
	for transform in transforms:
		for x in [source_bounds.position.x, source_bounds.end.x]:
			for y in [source_bounds.position.y, source_bounds.end.y]:
				for z in [source_bounds.position.z, source_bounds.end.z]:
					var point := transform * Vector3(x, y, z)
					if not has_bounds:
						bounds = AABB(point, Vector3.ZERO)
						has_bounds = true
					else:
						bounds = bounds.expand(point)
	return bounds.grow(0.18) if has_bounds else AABB(Vector3.ZERO, Vector3.ONE)

func _add_web_dressing_batch(name_value: String, mesh: Mesh, material: Material, transforms: Array[Transform3D], parent_root: Node3D = null) -> void:
	var target_root := parent_root if parent_root != null else web_tactical_dressing_root
	if transforms.is_empty() or target_root == null:
		return
	# Allocate one persistent draw per prop family *inside one spatial chunk*.
	# This keeps its AABB cullable; creating one MultiMesh per upload slice would
	# instead leave hundreds of permanent draw calls. Entry-only slices are larger
	# than fallback streaming, but still bounded to keep Web frames paintable.
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	multimesh.visible_instance_count = 0
	# Do this before the first visible slice.  A chunk keeps its own compact AABB,
	# so near-map foliage/ruins cannot disappear while distant chunks remain
	# culled instead of becoming a world-wide draw.
	multimesh.custom_aabb = _web_dressing_transform_aabb(mesh, transforms)
	var instance := MultiMeshInstance3D.new()
	instance.name = name_value
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 1.5
	target_root.add_child(instance)
	var slice_index := 0
	var transform_slice := WEB_ENTRY_DRESSING_TRANSFORM_SLICE if web_stage_entry_preload_active else WEB_DRESSING_TRANSFORM_SLICE
	for slice_start in range(0, transforms.size(), transform_slice):
		var slice_started_usec := Time.get_ticks_usec()
		var slice_end := mini(slice_start + transform_slice, transforms.size())
		for transform_index in range(slice_start, slice_end):
			multimesh.set_instance_transform(transform_index, transforms[transform_index])
		multimesh.visible_instance_count = slice_end
		await _finish_web_build_slice("dressing_%s_%02d" % [name_value, slice_index], slice_started_usec)
		if not _web_async_owner_alive():
			return
		slice_index += 1

static func _web_grove_field(coord: Vector2i) -> float:
	# Low-frequency deterministic waves make several neighbouring hexes agree on
	# grove versus clearing. A per-cell modulo produced evenly scattered holes and
	# made every remaining forest cell read as an independent round prop marker.
	return (
		sin(float(coord.x) * 0.48 + float(coord.y) * 0.21) * 0.72
		+ cos(float(coord.x) * 0.18 - float(coord.y) * 0.43) * 0.58
		+ sin(float(coord.x + coord.y) * 0.13) * 0.18
	)

func _web_road_axis(coord: Vector2i, fallback_angle: float) -> Vector3:
	var center := HexCoordScript.axial_to_world(coord, TILE_SIZE)
	var neighbor_directions: Array[Vector3] = []
	for neighbor_coord in HexCoordScript.neighbors(coord):
		var neighbor_tile: Dictionary = grid.tile(neighbor_coord)
		if str(neighbor_tile.get("terrain_type", "")) != "ROAD":
			continue
		var direction := HexCoordScript.axial_to_world(neighbor_coord, TILE_SIZE) - center
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			neighbor_directions.append(direction.normalized())
	if neighbor_directions.is_empty():
		return Vector3(cos(fallback_angle), 0.0, sin(fallback_angle))
	if neighbor_directions.size() == 1:
		return neighbor_directions[0]
	# At a bend or junction, the most opposed neighbour pair describes the route
	# through the cell. This keeps sleepers aligned even at the streamed boundary.
	var best_axis: Vector3 = neighbor_directions[0]
	var best_dot := 2.0
	for left_index in range(neighbor_directions.size() - 1):
		for right_index in range(left_index + 1, neighbor_directions.size()):
			var pair_dot := neighbor_directions[left_index].dot(neighbor_directions[right_index])
			if pair_dot >= best_dot:
				continue
			best_dot = pair_dot
			best_axis = (neighbor_directions[right_index] - neighbor_directions[left_index]).normalized()
	return best_axis

func _ensure_web_dressing_mesh_cache() -> void:
	# Primitive meshes are immutable presentation templates. Recreating all eight
	# RIDs on every three-cell dressing refresh forced Compatibility/Web to upload
	# and validate the same vertex formats while the squad was moving.
	if not web_dressing_mesh_cache.is_empty():
		return
	var trunk_mesh: CylinderMesh = null
	var sleeper_mesh: BoxMesh = null
	if OS.has_feature("web") and WebSoakProbe.has_method("web_render_resource"):
		var warmed_trunk = WebSoakProbe.web_render_resource("dressing_mesh:trunk")
		var warmed_sleeper = WebSoakProbe.web_render_resource("dressing_mesh:sleeper")
		if warmed_trunk is CylinderMesh:
			trunk_mesh = warmed_trunk
		if warmed_sleeper is BoxMesh:
			sleeper_mesh = warmed_sleeper
	if trunk_mesh == null:
		trunk_mesh = CylinderMesh.new()
		trunk_mesh.top_radius = 0.055
		trunk_mesh.bottom_radius = 0.075
		trunk_mesh.height = 0.28
		trunk_mesh.radial_segments = 5
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 0.25
	canopy_mesh.height = 0.44
	canopy_mesh.radial_segments = 6
	canopy_mesh.rings = 4
	if sleeper_mesh == null:
		sleeper_mesh = BoxMesh.new()
		sleeper_mesh.size = Vector3(0.54, 0.055, 0.10)
	var ruin_mesh := BoxMesh.new()
	ruin_mesh.size = Vector3(0.20, 0.44, 0.20)
	var grass_mesh := CylinderMesh.new()
	grass_mesh.top_radius = 0.012
	grass_mesh.bottom_radius = 0.052
	grass_mesh.height = 0.22
	grass_mesh.radial_segments = 3
	var boulder_mesh := SphereMesh.new()
	boulder_mesh.radius = 0.17
	boulder_mesh.height = 0.25
	boulder_mesh.radial_segments = 6
	boulder_mesh.rings = 4
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(0.72, 0.43, 0.15)
	web_dressing_mesh_cache = {
		"trunk": trunk_mesh,
		"canopy": canopy_mesh,
		"sleeper": sleeper_mesh,
		"ruin": ruin_mesh,
		"grass": grass_mesh,
		"boulder": boulder_mesh,
		"wall": wall_mesh,
	}

func _rebuild_web_tactical_dressing(wanted: Dictionary) -> void:
	# Deterministic MultiMesh batches restore terrain identity without
	# importing the authored GLB kit or creating hundreds of scene nodes during
	# stage entry. Gameplay, movement and fog remain data/grid-authoritative.
	# Keep the replacement render-active a hair below the previous dressing while
	# it is built. Visibility=false caused lazy GPU upload on the final reveal;
	# visible in-tree batches register on their own frames instead.
	var next_root := Node3D.new()
	next_root.name = "WebTacticalTerrainDressingNext"
	next_root.position = Vector3(0.0, -0.02, 0.0)
	world_root.add_child(next_root)
	# One world-sized MultiMesh has a world-sized AABB and therefore keeps every
	# off-camera tree alive in the Web draw list.  Partition stable axial regions
	# first, then prop family, so renderer frustum culling works before drawing.
	var spatial_dressing_batches: Dictionary = {}
	var dressing_tile_count := 0
	for key_value in wanted.keys():
		var tile: Dictionary = wanted[key_value]
		var terrain := str(tile.get("terrain_type", "FOREST"))
		if terrain in ["SHALLOW_WATER", "DEEP_WATER"]:
			continue
		var coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
		var phase: int = absi(coord.x * 17 + coord.y * 29)
		var angle := float(phase % 12) * TAU / 12.0
		var movement_blocked := bool(tile.get("movement_blocked", false))
		var surface_y := float(tile.get("elevation", 0)) * ELEVATION_STEP + 0.035
		var center := HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y)
		match terrain:
			"FOREST":
				var grove_field := _web_grove_field(coord)
				var grove_thinning := grove_field < -0.42
				var adjacent_to_road := false
				var away_from_road := Vector3.ZERO
				for neighbor_coord in HexCoordScript.neighbors(coord):
					if str(grid.tile(neighbor_coord).get("terrain_type", "")) == "ROAD":
						adjacent_to_road = true
						var road_delta := center - HexCoordScript.axial_to_world(neighbor_coord, TILE_SIZE)
						road_delta.y = 0.0
						away_from_road += road_delta.normalized()
				if not away_from_road.is_zero_approx():
					away_from_road = away_from_road.normalized()
				# The generator owns collision authority: blocked FOREST is the broad grove
				# wall, while passable FOREST is part of the continuous route clearing. A
				# low-frequency field only thins the wall, so neighbouring cells agree on
				# grove/open rhythm without ever making a blocked tile look traversable.
				var tree_count := 0
				if movement_blocked:
					# Two broad, overlapping canopy masses read as a dense continuous
					# forest wall at gameplay scale without uploading fourteen meshes per
					# blocked cell during the stage-entry boundary.
					tree_count = 1 if grove_thinning else 2
				elif adjacent_to_road:
					tree_count = 1
				else:
					tree_count = 1
				for tree_index in range(tree_count):
					var tree_angle := angle + float(tree_index) * 2.17 + float(tree_index % 2) * .37
					var forest_radius := 0.30 + float((phase + tree_index * 2) % 5) * 0.14
					var tree_scale := 0.80 + float((phase + tree_index * 3) % 4) * 0.08
					if not movement_blocked:
						# A lone shoulder tree stays near the edge; the hex centre remains an
						# unmistakable open lane for both pointer targeting and route reading.
						forest_radius = 0.74 + float((phase + tree_index) % 3) * 0.06
						tree_scale = 0.58 + float((phase + tree_index) % 3) * 0.04
					var forest_offset := Vector3(cos(tree_angle), 0.0, sin(tree_angle)) * forest_radius
					if movement_blocked and adjacent_to_road:
						forest_offset += away_from_road * 0.18
					_append_web_dressing_chunk_transform(spatial_dressing_batches, "ForestTrunks", coord, center + forest_offset + Vector3(0.0, 0.15 * tree_scale, 0.0), Vector3(tree_scale * .62, tree_scale, tree_scale * .62), tree_angle)
					var canopy_family := "ForestCanopiesLight" if (phase + tree_index) % 4 == 0 else "ForestCanopies"
					var canopy_x := (2.12 + float((phase + tree_index) % 3) * 0.12) if movement_blocked else 1.12
					var canopy_z := (1.52 + float((phase + tree_index * 2) % 3) * 0.10) if movement_blocked else 0.98
					_append_web_dressing_chunk_transform(spatial_dressing_batches, canopy_family, coord, center + forest_offset + Vector3(0.0, 0.47 * tree_scale, 0.0), Vector3(tree_scale * canopy_x, tree_scale * .78, tree_scale * canopy_z), tree_angle)
				var grass_count := 2
				for grass_index in range(grass_count):
					var grass_angle := angle + float(grass_index) * 2.12 + .8
					var grass_offset := Vector3(cos(grass_angle), 0.0, sin(grass_angle)) * (0.28 + float(grass_index) * .11)
					var grass_scale := 0.76 if movement_blocked else 0.66
					_append_web_dressing_chunk_transform(spatial_dressing_batches, "GroundGrassTufts", coord, center + grass_offset + Vector3(0.0, .07, 0.0), Vector3(grass_scale, .84, grass_scale), grass_angle)
				# Every real blocked/open boundary receives a low earth/stone retaining
				# ridge. This makes the pathfinder boundary readable as terrain rather
				# than an arbitrary missing yellow hex while keeping the walk lane clear.
				if movement_blocked:
					for neighbor_coord in HexCoordScript.neighbors(coord):
						if not grid.traversable(neighbor_coord):
							continue
						var neighbor_center := HexCoordScript.axial_to_world(neighbor_coord, TILE_SIZE, surface_y)
						var open_direction := neighbor_center - center
						open_direction.y = 0.0
						if open_direction.is_zero_approx():
							continue
						open_direction = open_direction.normalized()
						var ridge_tangent := Vector3(-open_direction.z, 0.0, open_direction.x)
						var ridge_angle := atan2(ridge_tangent.z, ridge_tangent.x)
						_append_web_dressing_chunk_transform(spatial_dressing_batches, "ForestBoundaryRidges", coord, center + open_direction * (TILE_SIZE * .57) + Vector3(0.0, .18, 0.0), Vector3(1.34, .86, 1.0), ridge_angle)
			"ROAD":
				# Sleepers follow actual neighbouring ROAD cells, never a per-tile hash
				# angle. The long mesh axis is perpendicular to the route like a real tie.
				var road_axis := _web_road_axis(coord, angle)
				var road_angle := atan2(road_axis.z, road_axis.x)
				var sleeper_angle := road_angle + PI * .5
				for sleeper_index in range(2):
					var along := road_axis * (-.24 if sleeper_index == 0 else .24)
					_append_web_dressing_chunk_transform(spatial_dressing_batches, "RoadSignalSleepers", coord, center + along + Vector3(0.0, 0.045, 0.0), Vector3(0.74, 1.0, 1.0), sleeper_angle)
				if phase % 3 == 0:
					var roadside := Vector3(-road_axis.z, 0.0, road_axis.x) * .50
					_append_web_dressing_chunk_transform(spatial_dressing_batches, "GroundGrassTufts", coord, center + roadside + Vector3(0.0, .07, 0.0), Vector3(.62, .74, .62), road_angle)
			"RUINS":
				if movement_blocked:
					var ruin_offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.26
					_append_web_dressing_chunk_transform(spatial_dressing_batches, "RuinSignalMarkers", coord, center + ruin_offset + Vector3(0.0, 0.25, 0.0), Vector3(0.90, 1.0 + float(phase % 3) * 0.18, 0.90), angle)
					# Broken L/U walls are reserved for authored blocked RUINS. Their visible
					# footprint now agrees with the pathfinder instead of sealing an open lane.
					for wall_index in range(2 + phase % 2):
						var wall_angle := angle + float(wall_index) * (PI * .47)
						var wall_offset := Vector3(cos(wall_angle), 0.0, sin(wall_angle)) * (.30 + float(wall_index % 2) * .08)
						_append_web_dressing_chunk_transform(spatial_dressing_batches, "BrokenRuinWalls", coord, center + wall_offset + Vector3(0.0, .22, 0.0), Vector3(1.12 + float((phase + wall_index) % 2) * .30, 1.05, .90), wall_angle)
					if phase % 2 == 0:
						_append_web_dressing_chunk_transform(spatial_dressing_batches, "RidgeBoulders", coord, center + Vector3(cos(angle + 1.3), .10, sin(angle + 1.3)) * .34, Vector3(.82, .66, .94), angle)
				else:
					# Passable ruins keep one low edge fragment as identity, never a wall or
					# central boulder. The clear centre matches its movement metadata.
					var rubble_offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.68
					_append_web_dressing_chunk_transform(spatial_dressing_batches, "RuinSignalMarkers", coord, center + rubble_offset + Vector3(0.0, 0.11, 0.0), Vector3(0.56, 0.42, 0.56), angle)
		if movement_blocked and int(tile.get("elevation", 0)) > 0 and phase % 3 == 1:
			var ridge_offset := Vector3(cos(angle + .45), 0.0, sin(angle + .45)) * .46
			_append_web_dressing_chunk_transform(spatial_dressing_batches, "RidgeBoulders", coord, center + ridge_offset + Vector3(0.0, .11, 0.0), Vector3(.86, .70, 1.02), angle)
		dressing_tile_count += 1
		var dressing_scan_batch := WEB_ENTRY_TERRAIN_TILE_BATCH if web_stage_entry_preload_active else WEB_STREAM_BUILD_BATCH
		if dressing_tile_count % dressing_scan_batch == 0:
			await _finish_web_build_slice("dressing_scan", Time.get_ticks_usec())
			if not _web_async_owner_alive():
				return
	_ensure_web_dressing_mesh_cache()
	var trunk_mesh: Mesh = web_dressing_mesh_cache.trunk
	var canopy_mesh: Mesh = web_dressing_mesh_cache.canopy
	var sleeper_mesh: Mesh = web_dressing_mesh_cache.sleeper
	var ruin_mesh: Mesh = web_dressing_mesh_cache.ruin
	var grass_mesh: Mesh = web_dressing_mesh_cache.grass
	var boulder_mesh: Mesh = web_dressing_mesh_cache.boulder
	var wall_mesh: Mesh = web_dressing_mesh_cache.wall
	var family_resources: Dictionary = {
		"ForestTrunks": [trunk_mesh, _cached_material(Color("4a3a2d"))],
		"ForestCanopies": [canopy_mesh, _cached_material(Color("315b46"))],
		"ForestCanopiesLight": [canopy_mesh, _cached_material(Color("52765a"))],
		"RoadSignalSleepers": [sleeper_mesh, _cached_material(Color("c9a45d"), Color("302714"))],
		"RuinSignalMarkers": [ruin_mesh, _cached_material(Color("7b8791"))],
		"GroundGrassTufts": [grass_mesh, _cached_material(Color("617c48"))],
		"RidgeBoulders": [boulder_mesh, _cached_material(Color("68727a"))],
		"BrokenRuinWalls": [wall_mesh, _cached_material(Color("737c84"))],
		"ForestBoundaryRidges": [wall_mesh, _cached_material(Color("4d4938"), Color("171b12"))],
	}
	var spatial_chunk_keys: Array = spatial_dressing_batches.keys()
	spatial_chunk_keys.sort()
	var dressing_instance_count := 0
	for chunk_key_value in spatial_chunk_keys:
		var chunk_key := str(chunk_key_value)
		var chunk_root := Node3D.new()
		chunk_root.name = "WebDressingChunk_%s" % chunk_key.replace(",", "_")
		next_root.add_child(chunk_root)
		var chunk_batches: Dictionary = spatial_dressing_batches[chunk_key]
		var family_names: Array = chunk_batches.keys()
		family_names.sort()
		for family_name_value in family_names:
			var family_name := str(family_name_value)
			var resource_pair: Array = family_resources[family_name]
			dressing_instance_count += (chunk_batches[family_name] as Array).size()
			await _add_web_dressing_batch("%s_%s" % [family_name, chunk_key.replace(",", "_")], resource_pair[0], resource_pair[1], chunk_batches[family_name], chunk_root)
			if not _web_async_owner_alive():
				return
			await _finish_web_build_slice("dressing_family_%s" % family_name, Time.get_ticks_usec())
			if not _web_async_owner_alive():
				return
	var previous_root := web_tactical_dressing_root
	web_tactical_dressing_root = next_root
	web_tactical_dressing_root.name = "WebTacticalTerrainDressing"
	web_tactical_dressing_root.position = Vector3.ZERO
	if previous_root != null and is_instance_valid(previous_root):
		_retire_web_render_root(previous_root)
	if OS.has_feature("web"):
		print("WEB_MAP_DRESSING_READY tiles=%d chunks=%d instances=%d" % [dressing_tile_count, spatial_chunk_keys.size(), dressing_instance_count])

func _web_stream_covers(center: Vector2i, radius: int) -> bool:
	if streamed_infill_instance == null or not is_instance_valid(streamed_infill_instance):
		return false
	# The previous implementation scanned every authored tile after every pawn
	# step just to prove that the prefetched disk still covered the new sight
	# disk. On the macro map that O(world-size) check produced the reported
	# rhythmic hitch once per hex. Hex disks obey the triangle inequality, so one
	# exact centre/radius containment check is the same authority in constant time.
	if web_stream_geometry_radius < radius:
		return false
	return HexCoordScript.distance(web_stream_geometry_center, center) + radius <= web_stream_geometry_radius

func _stream_visible_tiles(_requested_center: Vector2i, force := false, incremental := false) -> void:
	# Camera panning must never become a scouting exploit. Rendering follows the
	# logical squad hex exclusively; the camera may only inspect this clear area.
	var center := _player_map_coord()
	if OS.has_feature("web") and web_stage_entry_preload_complete:
		# The Web entry preload owns an all-map terrain/dressing coverage set.  Do
		# not turn an ordinary step, enemy turn or treasure result into resource IO
		# or a SurfaceTool/MultiMesh rebuild; fog/visibility refresh is sufficient.
		stream_anchor = center
		_refresh_fog_cover(center)
		return
	if not force and stream_anchor == center:
		return
	var vision_radius := _player_vision_radius()
	if OS.has_feature("web") and not force and _web_stream_covers(center, vision_radius):
		# The prefetched mesh already contains the complete new sight circle. Advance
		# the logical anchor so `_process()` does not rescan the macro definition on
		# every subsequent frame merely because the squad crossed one hex.
		stream_anchor = center
		return
	if OS.has_feature("web") and web_stream_in_progress:
		# Per-frame camera probes may coalesce, but an awaited arrival/build request
		# must not pretend that terrain is ready while an older district is still
		# uploading. Wait, then verify coverage for the latest logical pawn hex.
		if incremental:
			while web_stream_in_progress and is_inside_tree():
				await get_tree().process_frame
			if not is_inside_tree():
				return
			if _web_stream_covers(center, vision_radius):
				stream_anchor = center
				return
			await _stream_visible_tiles(center, force, true)
			if not _web_async_owner_alive():
				web_stream_in_progress = false
				return
		return
	if OS.has_feature("web"):
		web_stream_in_progress = true
	var stream_started_usec := Time.get_ticks_usec()
	_refresh_fog_cover(center)
	var wanted: Dictionary = {}
	var build_radius := vision_radius + WEB_STREAM_PREFETCH_MARGIN if OS.has_feature("web") else vision_radius
	var wanted_scan_count := 0
	for tile in definition.get("tiles", []):
		var coord := Vector2i(int(tile.q), int(tile.r))
		if HexCoordScript.distance(center, coord) <= build_radius:
			wanted[HexCoordScript.key(coord)] = tile
		wanted_scan_count += 1
		# This full macro scan happens only when the four-cell prefetched disk no
		# longer covers the requested squad position (normally initial/re-entry
		# loading). Bound it cooperatively on Web; ordinary 3-4 cell pawn movement
		# keeps the constant-time coverage fast path above and never reaches this.
		if OS.has_feature("web") and incremental and wanted_scan_count % (WEB_STREAM_BUILD_BATCH * 8) == 0:
			await get_tree().process_frame
			if not _web_async_owner_alive():
				web_stream_in_progress = false
				return
	await _refresh_clear_ground_infill(center, build_radius, OS.has_feature("web"))
	if not _web_async_owner_alive():
		if OS.has_feature("web"):
			web_stream_in_progress = false
		return
	if OS.has_feature("web"):
		await _stream_web_visible_ground(wanted, center)
		if not _web_async_owner_alive():
			web_stream_in_progress = false
			return
		web_stream_geometry_center = center
		web_stream_geometry_radius = build_radius
		stream_anchor = center
		web_stream_in_progress = false
		if SettingsService.is_developer_mode():
			var elapsed_msec := float(Time.get_ticks_usec() - stream_started_usec) / 1000.0
			print("WEB_COOPERATIVE_TASK terrain_stream %.2fms frames_yielded=true tiles=%d" % [elapsed_msec, wanted.size()])
		return
	for key in tile_meshes.keys():
		var stale: MeshInstance3D = tile_meshes[key]
		var keep := wanted.has(str(key))
		if keep and is_instance_valid(stale):
			var wanted_coord := HexCoordScript.from_key(str(key))
			var wanted_fogged := not _coord_is_in_player_vision(wanted_coord)
			keep = bool(stale.get_meta("fog_shell", false)) == wanted_fogged
		if keep:
			continue
		if is_instance_valid(stale):
			stale.queue_free()
		var dressing: Node3D = tile_dressing_roots.get(key)
		if is_instance_valid(dressing):
			dressing.queue_free()
		tile_meshes.erase(key)
		tile_dressing_roots.erase(key)
	var created_count := 0
	for key in wanted:
		if not tile_meshes.has(key):
			_create_tile(wanted[key])
			created_count += 1
			# Terrain dressing is the expensive part of a streamed tile.  Eighteen
			# dressed cells per Web frame could monopolise the main thread for many
			# seconds on mobile. Yield every four cells while keeping desktop batches
			# large enough for fast editor iteration.
			var stream_batch_size := 4 if OS.has_feature("web") else 18
			if incremental and created_count % stream_batch_size == 0:
				await get_tree().process_frame
				if not _web_async_owner_alive():
					return

func _kit_component(prefix: String) -> Dictionary:
	for key in blender_mesh_library:
		if str(key).begins_with(prefix): return blender_mesh_library[key]
	return {}

func _spawn_kit_component(prefix: String, location: Vector3, scale_factor := 1.0, yaw := 0.0, parent: Node3D = null) -> MeshInstance3D:
	var info := _kit_component(prefix)
	var mesh: Mesh = info.get("mesh")
	if mesh == null: return null
	var part := MeshInstance3D.new()
	part.name = prefix
	part.mesh = mesh
	part.position = location
	part.scale = info.get("scale", Vector3.ONE) * scale_factor
	part.rotation = info.get("rotation", Vector3.ZERO)
	part.rotation.y += yaw
	if parent != null:
		parent.add_child(part)
	elif active_dressing_root != null:
		active_dressing_root.add_child(part)
	else:
		world_root.add_child(part)
	return part

func _spawn_kit_components(prefix: String, location: Vector3, scale_factor := 1.0, yaw := 0.0, parent: Node3D = null) -> Array[MeshInstance3D]:
	var spawned: Array[MeshInstance3D] = []
	for key in blender_mesh_library:
		if not str(key).begins_with(prefix):
			continue
		var info: Dictionary = blender_mesh_library[key]
		var mesh: Mesh = info.get("mesh")
		if mesh == null:
			continue
		var part := MeshInstance3D.new()
		part.name = str(key)
		part.mesh = mesh
		part.position = location
		part.scale = info.get("scale", Vector3.ONE) * scale_factor
		part.rotation = info.get("rotation", Vector3.ZERO)
		part.rotation.y += yaw
		if parent != null:
			parent.add_child(part)
		elif active_dressing_root != null:
			active_dressing_root.add_child(part)
		else:
			world_root.add_child(part)
		spawned.append(part)
	return spawned

func _has_node_at(coord: Vector2i) -> bool:
	for node in definition.get("nodes", []):
		if int(node.q) == coord.x and int(node.r) == coord.y: return true
	return false

func _create_terrain_dressing(tile: Dictionary, tile_position: Vector3, coord: Vector2i) -> void:
	var terrain := str(tile.terrain_type)
	var variant := int(tile.visual_variant)
	var yaw := float(tile.rotation_step) * PI / 3.0
	var elevated := int(tile.elevation) > 0
	# R7's old component clusters each carried their own hex-sized support
	# platform. They made even a connected world surface look like stacked game
	# pieces. Keep only sparse asymmetric rock outcrops; the broad shared terrain
	# mesh now owns every slope, terrace and cliff silhouette.
	var outcrop := elevated and not _has_node_at(coord) and (variant == 7 or (terrain == "RUINS" and variant == 5))
	if outcrop:
		var height_scale := 0.72 + float(int(tile.elevation)) * 0.10
		_spawn_kit_component("PROP_CLIFF_FACET_A", tile_position + Vector3(-0.42, 0.00, 0.12), height_scale, yaw)
		_spawn_kit_component("PROP_CLIFF_FACET_B", tile_position + Vector3(0.28, 0.02, -0.26), height_scale * .64, yaw + 0.8)
	var terrain_cluster := false
	if terrain == "FOREST" and not _has_node_at(coord):
		# Place silhouette props on selected seeded variants rather than every
		# forest hex.  The cleared gaps make the long route readable and avoid a
		# synthetic grid of identical tree crowns.  Coordinate-derived phase adds
		# five stable scale/lean families, so streaming never makes the forest pop
		# into a new layout while adjacent tiles still avoid clone-like silhouettes.
		if not terrain_cluster and variant in [0, 3, 5, 7]:
			var tree_phase: int = abs(coord.x * 17 + coord.y * 31 + variant * 13) % 5
			var prop_offset := Vector3(-0.37, 0.42, 0.26) if tree_phase % 2 == 0 else Vector3(0.38, 0.42, -0.30)
			var tree_prefix := "PROP_TREE_A" if tree_phase % 2 == 0 else "PROP_TREE_B"
			var tree_scale := 0.84 + float(tree_phase) * 0.12
			var tree_yaw := yaw + float(tree_phase - 2) * 0.13
			_spawn_kit_component(tree_prefix + "_TRUNK", tile_position + prop_offset, tree_scale, tree_yaw)
			_spawn_kit_component(tree_prefix + "_CROWN_0", tile_position + prop_offset + Vector3(0.0, 0.58, 0.0), tree_scale, tree_yaw)
			_spawn_kit_component(tree_prefix + "_CROWN_1", tile_position + prop_offset + Vector3(0.15, 0.70, -0.10), tree_scale, tree_yaw)
			_spawn_kit_component(tree_prefix + "_CROWN_2", tile_position + prop_offset + Vector3(-0.15, 0.75, 0.10), tree_scale, tree_yaw)
			if tree_phase >= 3:
				var companion_prefix := "PROP_TREE_B" if tree_prefix == "PROP_TREE_A" else "PROP_TREE_A"
				var companion_offset := Vector3(0.36, 0.42, -0.22) if tree_phase == 3 else Vector3(-0.17, 0.42, -0.42)
				var companion_scale := tree_scale * (0.52 if tree_phase == 3 else 0.64)
				_spawn_kit_component(companion_prefix + "_TRUNK", tile_position + companion_offset, companion_scale, tree_yaw + 0.58)
				_spawn_kit_component(companion_prefix + "_CROWN_0", tile_position + companion_offset + Vector3(0.0, 0.48, 0.0), companion_scale, tree_yaw + 0.58)
				_spawn_kit_component(companion_prefix + "_CROWN_1", tile_position + companion_offset + Vector3(0.12, 0.60, -0.08), companion_scale, tree_yaw + 0.58)
		elif variant in [1, 4]:
			_spawn_kit_component("PROP_CRYSTAL_SHARD_1", tile_position + Vector3(0.34, 0.13, 0.18), 0.72, yaw)
	elif terrain == "RUINS":
		_spawn_kit_component("PROP_RUIN_RELAY_0", tile_position + Vector3(0.34, 0.23, -0.20), 0.86, yaw)
		_spawn_kit_component("PROP_RUIN_RELAY_1", tile_position + Vector3(0.34, 0.18, -0.20), 0.86, yaw)
		_spawn_kit_component("PROP_RUIN_RELAY_ARCH", tile_position + Vector3(0.30, 0.38, -0.20), 0.86, yaw)
		if variant != 0:
			_spawn_kit_component("PROP_RELAY_LAMP_LANTERN", tile_position + Vector3(-0.28, 0.60, 0.25), 0.72, yaw)
	elif terrain == "ROAD":
		# The route is a real severed signal rail.  It is visible independently of
		# the mathematical tile beneath it, so this cannot read as coloured hexes.
		_spawn_kit_components("PROP_DORMANT_RAIL", tile_position + Vector3(0.0, 0.24, 0.0), 0.82, yaw)
		if variant in [0, 3, 6]:
			_spawn_kit_component("PROP_ROUTE_PLINTH_BASE", tile_position + Vector3(0.0, 0.16, 0.0), 0.82, yaw)
			_spawn_kit_component("PROP_ROUTE_PLINTH_TRIM", tile_position + Vector3(0.0, 0.20, 0.0), 0.82, yaw)
			_spawn_kit_component("PROP_SIGNAL_SPINE_RAIL", tile_position + Vector3(0.0, 0.25, 0.0), 0.82, yaw)
			for relay_index in range(3):
				_spawn_kit_component("PROP_SIGNAL_SPINE_RELAY_%d" % relay_index, tile_position + Vector3(0.0, 0.31, 0.0), 0.82, yaw)
			_spawn_kit_component("PROP_SIGNAL_SPINE_RIB_L", tile_position + Vector3(0.0, 0.28, 0.0), 0.82, yaw)
			_spawn_kit_component("PROP_SIGNAL_SPINE_RIB_R", tile_position + Vector3(0.0, 0.28, 0.0), 0.82, yaw)
		if variant in [2, 5, 8]:
			_spawn_kit_component("PROP_RELAY_LAMP_STEM", tile_position + Vector3(0.34, 0.31, -0.28), 0.60, yaw)
			_spawn_kit_component("PROP_RELAY_LAMP_LANTERN", tile_position + Vector3(0.34, 0.67, -0.28), 0.60, yaw)
	elif terrain in ["SHALLOW_WATER", "DEEP_WATER"] and variant != 0:
		_spawn_kit_component("PROP_COAST_FOAM_ARC_0", tile_position + Vector3(-0.18, 0.08, -0.20), 0.76, yaw)
		_spawn_kit_component("PROP_COAST_FOAM_ARC_1", tile_position + Vector3(0.16, 0.08, 0.18), 0.76, yaw)

func _terrain_color(terrain: String, revealed: bool) -> Color:
	if not revealed:
		match terrain:
			"ROAD": return Color("4c4939")
			"RUINS": return Color("464553")
			"SHALLOW_WATER": return Color("1d5365")
			"DEEP_WATER": return Color("123d60")
			_: return Color("294b43")
	match terrain:
		"ROAD": return Color("9b865c")
		"RUINS": return Color("746873")
		"SHALLOW_WATER": return Color("2d7891")
		"DEEP_WATER": return Color("123b66")
		_: return Color("356f58")

func _create_node_button(node: Dictionary) -> void:
	var button := Button.new()
	# Web map construction is cooperative. Keep a newly-created control out of
	# layout/draw until the final state refresh has assigned its real text,
	# position and reachability; otherwise every placeholder button is submitted
	# once while the builder yields between nodes.
	button.visible = false
	button.custom_minimum_size = Vector2(92, 42)
	button.size = Vector2(92, 42)
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", Color("f4fffd"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("fff1ba"))
	button.add_theme_color_override("font_disabled_color", Color("c6d4dc"))
	button.add_theme_color_override("font_outline_color", Color("02080f"))
	button.add_theme_constant_override("outline_size", 6)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	# Bind an owned snapshot instead of retaining the temporary loop dictionary in
	# a lambda. Web can dispatch a queued pointer event after the map-content
	# builder yields; a freed lambda capture there emitted an engine error during
	# otherwise valid direct movement.
	var node_snapshot := node.duplicate(true)
	button.pressed.connect(_select_node.bind(node_snapshot))
	button.gui_input.connect(_on_node_button_input.bind(node_snapshot))
	overlay.add_child(button)
	node_buttons[str(node.node_id)] = button
	web_entity_projection_dirty = true

func _on_node_button_input(event: InputEvent, node: Dictionary) -> void:
	if moving or turn_transitioning or map_simulation_paused:
		return
	var node_id := str(node.get("node_id", ""))
	var touch_tap_valid := true
	if event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			node_touch_pointer_id = node_id
			node_touch_origin = event.position
			node_touch_tap_valid = not event.canceled
			return
		touch_tap_valid = node_touch_tap_valid and node_touch_pointer_id == node_id and not event.canceled and event.position.distance_to(node_touch_origin) <= 24.0 * _portrait_ui_scale(_runtime_layout_size())
		node_touch_pointer_id = ""
		node_touch_tap_valid = false
	elif event is InputEventScreenDrag and event.index == 0:
		if node_touch_pointer_id == node_id and event.position.distance_to(node_touch_origin) > 24.0 * _portrait_ui_scale(_runtime_layout_size()):
			node_touch_tap_valid = false
		return
	var repeated_pointer_click := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var now_msec := Time.get_ticks_msec()
		repeated_pointer_click = node_id == last_node_pointer_id and now_msec - last_node_pointer_msec >= 0 and now_msec - last_node_pointer_msec <= DIRECT_DOUBLE_CLICK_WINDOW_MSEC
		if event.double_click or repeated_pointer_click:
			last_node_pointer_id = ""
			last_node_pointer_msec = -100000
		else:
			last_node_pointer_id = node_id
			last_node_pointer_msec = now_msec
	if direct_move_gesture_policy(event, repeated_pointer_click, touch_tap_valid):
		_select_node(node)
		_activate_selected_route_from_pointer()

func _create_node_marker(node: Dictionary) -> void:
	var marker_root := Node3D.new()
	marker_root.name = "EncounterMarker_%s" % str(node.node_id)
	# The marker becomes visible from _refresh_state_visuals once its semantic
	# state is known. This avoids compiling/drawing all encounter variants during
	# the streamed construction frames, including nodes still outside fog.
	marker_root.visible = false
	var coord := Vector2i(int(node.q), int(node.r))
	marker_root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.18)
	# A thin locally-authored signal socket gives the encounter beacon and its
	# pawn a shared physical contact point. On the long streamed macro map this
	# is also a real low-profile clearing: it prevents a valid encounter from
	# ever reading as a sprite suspended over a seam between terrain districts.
	# It is not a stage-select card; the terrain material, shallow bevel, route
	# inlay, and local props keep it part of the world surface.
	var socket := MeshInstance3D.new()
	socket.name = "SignalSocketGround"
	var socket_mesh: CylinderMesh = null
	if OS.has_feature("web") and WebSoakProbe.has_method("web_render_resource"):
		var warmed_socket = WebSoakProbe.web_render_resource("signal_socket_mesh")
		if warmed_socket is CylinderMesh:
			socket_mesh = warmed_socket
	if socket_mesh == null:
		socket_mesh = CylinderMesh.new()
		socket_mesh.top_radius = 1.18
		socket_mesh.bottom_radius = 1.28
		socket_mesh.height = 0.085
		socket_mesh.radial_segments = 12
	socket.mesh = socket_mesh
	socket.position.y = -0.138
	socket.rotation_degrees.y = 15.0
	var socket_tile: Dictionary = grid.tile(coord)
	socket.material_override = _cached_material(_terrain_surface_color(socket_tile).lightened(0.08))
	marker_root.add_child(socket)
	var hard_stage := str(node.get("stage_id", "")).contains("-H")
	var stage_id := str(node.get("stage_id", ""))
	var node_type := str(node.get("node_type", ""))
	var marker_prefix := "MARKER_NORMAL"
	if node_type == "START":
		marker_prefix = "MARKER_NORMAL"
	elif hard_stage:
		marker_prefix = "MARKER_HARD_GATE"
	elif node_type.contains("BOSS") or bool(DataRegistry.stage(stage_id).get("boss", false)):
		marker_prefix = "MARKER_BOSS"
	elif node_type.contains("ELITE"):
		marker_prefix = "MARKER_ELITE"
	var marker_parts := _spawn_kit_components(marker_prefix, Vector3.ZERO, 1.04, 0.0, marker_root)
	if marker_parts.is_empty():
		var fallback := MeshInstance3D.new()
		var fallback_mesh: CylinderMesh = null
		if OS.has_feature("web") and WebSoakProbe.has_method("web_render_resource"):
			var warmed_marker = WebSoakProbe.web_render_resource("fallback_marker_mesh")
			if warmed_marker is CylinderMesh:
				fallback_mesh = warmed_marker
		if fallback_mesh == null:
			fallback_mesh = CylinderMesh.new()
			fallback_mesh.top_radius = 0.42
			fallback_mesh.bottom_radius = 0.54
			fallback_mesh.height = 0.15
			fallback_mesh.radial_segments = 6
		fallback.mesh = fallback_mesh
		fallback.name = "FallbackMarkerSymbol"
		fallback.material_override = _cached_material(Color("78eed9"), Color("319f92"))
		marker_root.add_child(fallback)
	# Three persistent visual anchors make it clear this is a long broken relay
	# route, even when the streamed local terrain hides far-away node labels.
	if stage_id.ends_with("N03") or stage_id.ends_with("N07") or stage_id.ends_with("N10") or stage_id.ends_with("N15") or stage_id.ends_with("N20"):
		_spawn_kit_components("PROP_SIGNAL_TOWER", Vector3(0.62, 0.06, -0.30), 0.76 if stage_id.ends_with("N03") else 1.0, 0.18, marker_root)
	elif stage_id.ends_with("H05") or stage_id.ends_with("H10"):
		_spawn_kit_components("PROP_SIGNAL_BEACON", Vector3(0.56, 0.05, -0.30), 0.92, -0.30, marker_root)
	if not hard_stage and not OS.has_feature("web"):
		# Compatibility/Web rebuilt its clustered-light buffers when the first two
		# encounter roots registered their decorative OmniLights. Those two uploads
		# produced repeatable 110-150ms frames and audible BGM starvation on every
		# first map entry. Web markers already own an emissive symbol and readable
		# socket; reserve per-marker point lights for native builds.
		_add_route_accent_light(marker_root, Vector3(0.0, 0.72, 0.0), 1.05 if stage_id.ends_with("N20") else 0.48)
	world_root.add_child(marker_root)
	node_markers[str(node.node_id)] = marker_root
	web_entity_projection_dirty = true

func _node_overlay_anchor(node: Dictionary) -> Vector3:
	# Stage UI must follow the actual world marker that was instantiated for this
	# encounter, not a second copy of the axial/elevation formula.  The map is
	# rendered into a fixed SubViewport and its Control overlay is stretched by a
	# sibling container, so this preserves one real 3D anchor while the required
	# SubViewport-to-overlay scale conversion happens only at projection time.
	var marker: Node3D = node_markers.get(str(node.get("node_id", "")))
	if marker != null and is_instance_valid(marker):
		return marker.global_position + Vector3(0.0, 0.58, 0.0)
	var coord := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
	return HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.76)

func _overlay_position_from_world(world_position: Vector3) -> Vector2:
	# Camera3D returns pixels in its 1280×720 SubViewport. The sibling overlay
	# lives in the stretched parent map frame, so this single conversion is
	# necessary and must not be repeated by individual label call sites.
	if camera == null or not is_instance_valid(camera) or viewport == null or not is_instance_valid(viewport) or overlay == null or not is_instance_valid(overlay):
		return Vector2.ZERO
	var viewport_size := Vector2(viewport.size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector2.ZERO
	return camera.unproject_position(world_position) * (overlay.size / viewport_size)

func _overlay_anchor_is_visible(world_position: Vector3, control_size: Vector2) -> bool:
	# Camera3D.unproject_position() still yields a numeric coordinate for an
	# anchor behind the camera.  Treating that number as an on-screen label put
	# distant stage UI over the ocean while its actual 3D marker was outside the
	# view frustum.  The map never turns hidden/offscreen markers into floating
	# overlay targets: the actual 3D marker remains the source of truth and the
	# `next encounter` navigation action can deliberately focus it.
	if camera == null or not is_instance_valid(camera) or overlay == null or not is_instance_valid(overlay) or camera.is_position_behind(world_position):
		return false
	var projected := _overlay_position_from_world(world_position)
	var padding := control_size * 0.68
	return Rect2(-padding, overlay.size + padding * 2.0).has_point(projected)

func _has_streamed_ground(coord: Vector2i) -> bool:
	if OS.has_feature("web"):
		return streamed_ground_keys.has(HexCoordScript.key(coord)) and streamed_infill_instance != null and is_instance_valid(streamed_infill_instance) and streamed_infill_instance.visible
	var ground: MeshInstance3D = tile_meshes.get(HexCoordScript.key(coord))
	return ground != null and is_instance_valid(ground) and ground.visible

func _map_entity_is_locally_renderable(coord: Vector2i, camera_coord: Vector2i, radius: int) -> bool:
	return _has_streamed_ground(coord) and MapSimulationScript.should_render_pawn(coord, camera_coord, radius)

func _enemy_for_node(node: Dictionary) -> Dictionary:
	var stage := DataRegistry.stage(str(node.get("stage_id", "")))
	var first_enemy_id := ""
	var boss_enemy_id := ""
	for wave in stage.get("waves", []):
		for enemy_id in wave:
			var enemy := DataRegistry.enemy(str(enemy_id))
			if str(enemy.get("rank", "")) == "BOSS": boss_enemy_id = str(enemy_id)
			elif first_enemy_id == "": first_enemy_id = str(enemy_id)
	var selected_id := boss_enemy_id if not boss_enemy_id.is_empty() else first_enemy_id
	return DataRegistry.enemy(selected_id)

func _event_encounter_for_node(node_id: String) -> Dictionary:
	return MapExplorationServiceScript.event_encounter_for_node(definition, node_id)

func _map_idle_texture(enemy_id: String) -> Dictionary:
	# AppShell warms the same immutable combat atlas before this screen enters the
	# tree. Reuse its already-built idle pack so constructing map pawns performs no
	# manifest read, raw PNG fallback, or AtlasTexture slicing of its own.
	var tree := get_tree() if is_inside_tree() else null
	var stage_cache := tree.root.get_node_or_null("StageAssetCache") if tree != null else null
	if stage_cache != null and stage_cache.has_method("map_idle_pack"):
		var cached_pack_value = stage_cache.call("map_idle_pack", enemy_id)
		if cached_pack_value is Dictionary and not cached_pack_value.is_empty():
			return cached_pack_value
	var manifest_path := "res://assets/runtime_web/combat/%s/animation_manifest.json" % enemy_id
	if not FileAccess.file_exists(manifest_path): return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary: return {}
	var atlas_path := "res://assets/runtime_web/combat/%s/%s" % [enemy_id, str(parsed.get("atlas_path", "atlas.png"))]
	var atlas := _load_runtime_map_texture(atlas_path)
	if atlas == null: return {}
	var frame_size: Array = parsed.get("frame_size", [104, 104])
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	var animations: Dictionary = parsed.get("animations", {})
	var idle_animation: Dictionary = animations.get("idle", {})
	var idle_indices: Array = idle_animation.get("frame_indices", [])
	if idle_indices.is_empty(): idle_indices = [0]
	var first_frame := int(idle_indices[0])
	var columns := maxi(1, int(parsed.get("atlas_columns", 1)))
	texture.region = Rect2(float(first_frame % columns) * float(frame_size[0]), float(first_frame / columns) * float(frame_size[1]), float(frame_size[0]), float(frame_size[1]))
	var foot_anchor: Array = parsed.get("foot_anchor", [0.5, 0.88])
	return {
		# Preserve the immutable asset owner alongside the texture.  Event
		# companions must be auditable as their own CharacterDef SD pack, never
		# merely as a visually plausible generic map pawn.
		"source_id": enemy_id,
		"texture": texture,
		"frame_size": Vector2(float(frame_size[0]), float(frame_size[1])),
		"columns": columns,
		"animations": animations,
		"idle_frame_indices": idle_indices.slice(0, mini(8, idle_indices.size())),
		"idle_fps": float(idle_animation.get("fps", 12.0)),
		"foot_anchor": Vector2(float(foot_anchor[0]), float(foot_anchor[1])),
	}

static func _sprite_center_y_for_foot(contact_y: float, parent_base_y: float, frame_height: float, pixel_size: float, foot_anchor_y: float) -> float:
	# Sprite3D is centred on its frame. Reconstruct the centre from the authored
	# normalized foot anchor so every frame keeps the same physical contact point.
	return contact_y - parent_base_y + (foot_anchor_y - 0.5) * frame_height * pixel_size

func _node_encounter_cleared(node: Dictionary) -> bool:
	var node_id := str(node.get("node_id", ""))
	var stage_id := str(node.get("stage_id", ""))
	return (not node_id.is_empty() and MapExplorationServiceScript.encounter_cleared(map_state, node_id)) \
		or (not stage_id.is_empty() and int(AppState.profile.get("stage_stars", {}).get(stage_id, 0)) > 0)

func _prune_cleared_enemy_pawns() -> void:
	# Cached map views retain Node3Ds while a battle/result screen is visible.
	# Remove the defeated instance itself before visibility streaming resumes;
	# merely hiding it allowed a later Web stream to reuse stale pawn ownership.
	for node_id_value in enemy_pawns.keys():
		var node_id := str(node_id_value)
		var node := ChapterMapLoaderScript.node_by_id(definition, node_id)
		if node.is_empty() or not _node_encounter_cleared(node):
			continue
		var root: Node3D = enemy_pawns.get(node_id)
		if root != null and is_instance_valid(root):
			root.queue_free()
		enemy_pawns.erase(node_id)
		enemy_animation_packs.erase(node_id)

func _web_enemy_pawn_should_exist(node: Dictionary) -> bool:
	var stage_id := str(node.get("stage_id", ""))
	if stage_id.is_empty() or not AppState.is_stage_unlocked(stage_id):
		return false
	var node_id := str(node.get("node_id", ""))
	if node_id.is_empty() or _node_encounter_cleared(node):
		return false
	return _coord_is_in_player_vision(_encounter_coord(node))

func _queue_web_enemy_pawn_stream() -> void:
	# All currently unlocked roots are decoded during `_build_web_map_detail`.
	# A fresh Web map is created after battle/reward return, so there is no legal
	# in-place unlock that needs movement-time atlas IO.
	if not OS.has_feature("web") or web_stage_entry_preload_complete or web_enemy_stream_active or not is_inside_tree():
		return
	var missing_visible_pawn := false
	for node_value in definition.get("nodes", []):
		var node: Dictionary = node_value
		if not enemy_pawns.has(str(node.get("node_id", ""))) and _web_enemy_pawn_should_exist(node):
			missing_visible_pawn = true
			break
	if not missing_visible_pawn:
		return
	web_enemy_stream_active = true
	call_deferred("_stream_web_enemy_pawns")

func _stream_web_enemy_pawns() -> void:
	# One locally relevant authored enemy atlas per browser frame. This keeps map
	# input, BGM and tutorial animation responsive while preserving exact ENM/BOSS
	# ownership; no generic or grey placeholder is inserted in this path.
	await get_tree().process_frame
	if not _web_async_owner_alive():
		web_enemy_stream_active = false
		return
	for node_value in definition.get("nodes", []):
		var node: Dictionary = node_value
		var node_id := str(node.get("node_id", ""))
		if enemy_pawns.has(node_id) or not _web_enemy_pawn_should_exist(node):
			continue
		_create_enemy_pawn(node)
		await get_tree().process_frame
		if not _web_async_owner_alive():
			web_enemy_stream_active = false
			return
	if is_inside_tree():
		_refresh_state_visuals()
	web_enemy_stream_active = false

static func _animation_indices(pack: Dictionary, animation_name: String) -> Array:
	var animation: Dictionary = pack.get("animations", {}).get(animation_name, {})
	var indices: Array = animation.get("frame_indices", [])
	if indices.is_empty():
		indices = pack.get("idle_frame_indices", [0])
	return indices

static func _animation_fps(pack: Dictionary, animation_name: String) -> float:
	var animation: Dictionary = pack.get("animations", {}).get(animation_name, {})
	return maxf(1.0, float(animation.get("fps", pack.get("idle_fps", 12.0))))

static func _animation_frame(pack: Dictionary, animation_name: String, elapsed_msec: int) -> int:
	var indices := _animation_indices(pack, animation_name)
	var frame_cursor := int(floor(float(elapsed_msec) * _animation_fps(pack, animation_name) / 1000.0)) % maxi(1, indices.size())
	return int(indices[frame_cursor])

func _load_runtime_map_texture(path: String) -> Texture2D:
	## Runtime map pawns share the exact packaged combat art. A raw-PNG load
	## keeps a newly synced map pawn visible until the editor cache catches up.
	if ResourceLoader.exists(path):
		var imported = load(path)
		if imported is Texture2D: return imported
	var image := Image.load_from_file(path)
	if image == null or image.is_empty(): return null
	return ImageTexture.create_from_image(image)

func _create_enemy_pawn(node: Dictionary) -> void:
	var node_id := str(node.get("node_id", ""))
	var special_event := _event_encounter_for_node(node_id)
	var enemy := _enemy_for_node(node)
	# A SPECIAL_ENEMY contact is authored around one identifiable monster.  The
	# map pawn must therefore use that event identity instead of the stage wave's
	# first generic enemy; otherwise the ! dialogue names one creature while the
	# world visibly presents another.
	if str(special_event.get("event_kind", "")) == "SPECIAL_ENEMY":
		var event_enemy := DataRegistry.enemy(str(special_event.get("enemy_id", "")))
		if not event_enemy.is_empty(): enemy = event_enemy
	if enemy.is_empty(): return
	var companion_ids: Array[String] = []
	if not special_event.is_empty():
		for recruitment_value in MapExplorationServiceScript.recruitment_specs(special_event):
			companion_ids.append(str(recruitment_value.get("character_id", "")))
	var companion: Dictionary = DataRegistry.character(companion_ids[0]) if not companion_ids.is_empty() else {}
	var is_event_contact := not special_event.is_empty()
	var is_companion_event := not companion.is_empty()
	var is_companion_duo := companion_ids.size() == 2
	var root := Node3D.new()
	root.name = ("CompanionEventMapPawn_" if is_companion_event else "EnemyMapPawn_") + node_id
	# Static encounters do not have patrol state.  Asking MapSimulation for all
	# enemies silently returned its default (0, 0), which could place a valid
	# stage pawn over open water.  Use the authored node coordinate unless this
	# encounter explicitly owns a live patrol route.
	var coord := _encounter_coord(node)
	root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.18)
	var rank := "EVENT" if is_companion_event else str(enemy.get("rank", "NORMAL"))
	var scale_factor := 1.12 if is_companion_event else (1.0 if rank == "NORMAL" else (1.28 if rank == "ELITE" else 1.72))
	# Hostile pawns can travel along a patrol route whose logical coordinate is
	# valid but lies at the seam between two streamed macro districts.  Give
	# every hostile the same physical terrain socket used by the squad and the
	# encounter marker.  It follows the real pawn transform, so it cannot drift
	# from the patrol simulation or become a screen-only placement workaround.
	var grounding_patch := MeshInstance3D.new()
	grounding_patch.name = "EnemyGroundingTerrace"
	var grounding_mesh := CylinderMesh.new()
	grounding_mesh.top_radius = 1.08 * scale_factor
	grounding_mesh.bottom_radius = 1.20 * scale_factor
	grounding_mesh.height = 0.078
	grounding_mesh.radial_segments = 12
	grounding_patch.mesh = grounding_mesh
	grounding_patch.position.y = -0.108
	grounding_patch.rotation_degrees.y = 15.0
	var enemy_tile: Dictionary = grid.tile(coord)
	grounding_patch.material_override = _material(_terrain_surface_color(enemy_tile).lightened(0.035))
	root.add_child(grounding_patch)
	var shadow := MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.38 * scale_factor
	shadow_mesh.bottom_radius = 0.50 * scale_factor
	shadow_mesh.height = 0.025
	shadow_mesh.radial_segments = 12
	shadow.mesh = shadow_mesh
	shadow.position.y = 0.02
	shadow.material_override = _material(Color("061019"))
	root.add_child(shadow)
	var danger_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.34 * scale_factor
	ring_mesh.outer_radius = 0.42 * scale_factor
	ring_mesh.rings = 8
	ring_mesh.ring_segments = 18
	danger_ring.mesh = ring_mesh
	var threat_color := Color("7ee7d5") if is_companion_event else (Color("ff8d70") if is_event_contact else (Color("d85d67") if rank == "NORMAL" else (Color("ef9a47") if rank == "ELITE" else Color("dc5dcc"))))
	danger_ring.material_override = _material(threat_color, threat_color.darkened(0.1))
	danger_ring.position.y = 0.06
	root.add_child(danger_ring)
	var sprite := Sprite3D.new()
	sprite.name = "EnemyIdleSprite"
	var pack := _map_idle_texture(str(companion.get("id", enemy.get("id", ""))))
	if not pack.is_empty():
		sprite.texture = pack.texture
		enemy_animation_packs[node_id] = pack
	else:
		var fallback := QuadMesh.new()
		fallback.size = Vector2(0.72 * scale_factor, 0.72 * scale_factor)
		var fallback_mesh := MeshInstance3D.new()
		fallback_mesh.mesh = fallback
		fallback_mesh.material_override = _material(threat_color, threat_color)
		fallback_mesh.position.y = 0.62 * scale_factor
		root.add_child(fallback_mesh)
	# Combat atlases use 104px frames while the squad leader is rendered from a
	# 512px icon.  The previous 0.007 world-pixel value made hostile pawns read
	# as decoration at the edge of a route.  Keep the actual combat art, but give
	# it a deliberate map-pawn scale and use the manifest foot anchor so it sits
	# on its hostile ring rather than sinking into the terrain.
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.0165 * scale_factor
	# A hostile is a physical world pawn, not a HUD marker.  It must participate
	# in the same depth pass as its terrain socket, shadow, ring and road; a
	# no-depth sprite could remain visible after the true root had disappeared
	# behind the ocean or a bad terrain seam.
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.no_depth_test = false
	var enemy_frame_size: Vector2 = pack.get("frame_size", Vector2(104.0, 104.0))
	var enemy_anchor: Vector2 = pack.get("foot_anchor", Vector2(0.5, 0.88))
	var sprite_world_height := enemy_frame_size.y * sprite.pixel_size
	sprite.position.y = _sprite_center_y_for_foot(0.08, 0.0, enemy_frame_size.y, sprite.pixel_size, enemy_anchor.y)
	if is_companion_duo:
		sprite.position.x = -0.34
	sprite.render_priority = 12
	root.add_child(sprite)
	_add_occlusion_silhouette(sprite, root, "EnemyOcclusionSilhouette", Color("ff746e") if not is_companion_event else Color("75f3dc"))
	if is_companion_duo:
		# A duo remains one map contact and one battle transaction, but both
		# recruitable people must be visibly represented by their own SD art.
		# Keep the primary animation registry stable for patrol processing and
		# animate the second companion from its own immutable combat pack below.
		var second_sprite := Sprite3D.new()
		second_sprite.name = "CompanionEventSecondaryIdleSprite"
		var second_pack := _map_idle_texture(companion_ids[1])
		if not second_pack.is_empty():
			second_sprite.texture = second_pack.texture
			second_sprite.set_meta("animation_pack", second_pack)
			second_sprite.set_meta("animation_phase_msec", 190)
		second_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		second_sprite.pixel_size = sprite.pixel_size
		second_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		second_sprite.no_depth_test = false
		var second_frame_size: Vector2 = second_pack.get("frame_size", enemy_frame_size)
		var second_anchor: Vector2 = second_pack.get("foot_anchor", enemy_anchor)
		second_sprite.position = Vector3(0.34, _sprite_center_y_for_foot(0.08, 0.0, second_frame_size.y, second_sprite.pixel_size, second_anchor.y), 0.0)
		second_sprite.render_priority = 12
		root.add_child(second_sprite)
		_add_occlusion_silhouette(second_sprite, root, "CompanionSecondaryOcclusionSilhouette", Color("75f3dc"))
	var threat := Label3D.new()
	threat.text = "!" if is_event_contact else ("위협" if rank == "NORMAL" else ("정예" if rank == "ELITE" else "보스"))
	threat.font_size = 56 if is_event_contact else (46 if rank == "BOSS" else 38)
	threat.outline_size = 8
	threat.modulate = threat_color.lightened(0.16)
	threat.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	threat.no_depth_test = true
	threat.position.y = sprite.position.y + sprite_world_height * 0.48 + 0.10
	root.add_child(threat)
	var awareness := Label3D.new()
	awareness.name = "AwarenessCue"
	awareness.text = ""
	awareness.font_size = 50
	awareness.outline_size = 9
	awareness.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	awareness.no_depth_test = true
	awareness.position.y = threat.position.y + 0.40
	root.add_child(awareness)
	root.set_meta("threat_ring", danger_ring)
	root.set_meta("awareness_label", awareness)
	root.set_meta("node_id", node_id)
	root.set_meta("companion_event", is_companion_event)
	root.set_meta("event_contact", is_event_contact)
	if is_event_contact:
		root.set_meta("event_marker", threat)
		root.set_meta("event_marker_base_y", threat.position.y)
		root.set_meta("event_marker_phase", float(node_id.hash() % 19) * 0.31)
	if is_companion_event:
		root.set_meta("event_companion_ids", companion_ids)
		# Event contacts deliberately use the companion's own SD art, not an
		# enemy fallback.  Keep the authored ! above the pawn on a small diegetic
		# pulse so it survives dense terrain and remains legible at map scale.
	world_root.add_child(root)
	enemy_pawns[node_id] = root

func _create_treasure_visual(treasure: Dictionary) -> void:
	var treasure_id := str(treasure.get("treasure_id", ""))
	if treasure_id.is_empty(): return
	var root := Node3D.new()
	root.name = "Treasure_%s" % treasure_id
	var coord := Vector2i(int(treasure.get("q", 0)), int(treasure.get("r", 0)))
	root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.16)
	var shadow := MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.34
	shadow_mesh.bottom_radius = 0.46
	shadow_mesh.height = 0.02
	shadow_mesh.radial_segments = 12
	shadow.mesh = shadow_mesh
	shadow.material_override = _material(Color("061019"))
	shadow.position.y = 0.01
	root.add_child(shadow)
	var crate := MeshInstance3D.new()
	var crate_mesh := BoxMesh.new()
	crate_mesh.size = Vector3(0.56, 0.34, 0.40)
	crate.mesh = crate_mesh
	crate.material_override = _material(Color("875a2f"), Color("6f3c1f"))
	crate.position.y = 0.22
	root.add_child(crate)
	var lid := MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(0.61, 0.11, 0.45)
	lid.mesh = lid_mesh
	lid.material_override = _material(Color("e2a853"), Color("b97830"))
	lid.position.y = 0.43
	root.add_child(lid)
	var seal := MeshInstance3D.new()
	var seal_mesh := SphereMesh.new()
	seal_mesh.radius = 0.09
	seal_mesh.height = 0.18
	seal.mesh = seal_mesh
	seal.material_override = _material(Color("b9fff2"), Color("6af8d4"))
	seal.position = Vector3(0, 0.50, 0.22)
	root.add_child(seal)
	var glow := MeshInstance3D.new()
	var glow_mesh := TorusMesh.new()
	glow_mesh.inner_radius = 0.38
	glow_mesh.outer_radius = 0.46
	glow_mesh.rings = 8
	glow_mesh.ring_segments = 18
	glow.mesh = glow_mesh
	glow.material_override = _material(Color("edcc76"), Color("f7d76f"))
	glow.position.y = 0.065
	root.add_child(glow)
	if str(treasure.get("visibility", "VISIBLE")) == "HIDDEN":
		crate.visible = false
		lid.visible = false
		seal.visible = false
		glow.visible = false
		_spawn_kit_component("PROP_CRYSTAL_SHARD_1", Vector3(0.20, 0.12, -0.10), 0.76, 0.0, root)
	root.set_meta("crate", crate)
	root.set_meta("lid", lid)
	root.set_meta("seal", seal)
	root.set_meta("glow", glow)
	world_root.add_child(root)
	treasure_visuals[treasure_id] = root

func _create_relay_visual(relay: Dictionary) -> void:
	var relay_id := str(relay.get("relay_id", ""))
	if relay_id.is_empty(): return
	var root := Node3D.new()
	root.name = "MapRelay_%s" % relay_id
	var coord := Vector2i(int(relay.get("q", 0)), int(relay.get("r", 0)))
	root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.18)
	var parts := _spawn_kit_components("PROP_SIGNAL_TOWER", Vector3.ZERO, 0.78, 0.0, root)
	if parts.is_empty():
		var mast := MeshInstance3D.new()
		var mast_mesh := CylinderMesh.new()
		mast_mesh.top_radius = 0.12
		mast_mesh.bottom_radius = 0.22
		mast_mesh.height = 1.25
		mast_mesh.radial_segments = 6
		mast.mesh = mast_mesh
		mast.position.y = 0.62
		mast.material_override = _material(Color("1e5361"), Color("15535c"))
		root.add_child(mast)
	var signal_ring := MeshInstance3D.new()
	var signal_mesh := TorusMesh.new()
	signal_mesh.inner_radius = 0.26
	signal_mesh.outer_radius = 0.34
	signal_mesh.rings = 8
	signal_mesh.ring_segments = 16
	signal_ring.mesh = signal_mesh
	signal_ring.position.y = 1.10
	signal_ring.material_override = _material(Color("5b8090"), Color("224552"))
	root.add_child(signal_ring)
	var label := Label3D.new()
	label.text = "릴레이"
	label.font_size = 34
	label.outline_size = 7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 1.48
	label.modulate = Color("a7d4de")
	root.add_child(label)
	root.set_meta("signal", signal_ring)
	root.set_meta("label", label)
	world_root.add_child(root)
	relay_visuals[relay_id] = root

func _create_event_visual(event: Dictionary) -> void:
	var event_id := str(event.get("event_id", ""))
	if event_id.is_empty(): return
	var root := Node3D.new()
	root.name = "MapEvent_%s" % event_id
	var coord := Vector2i(int(event.get("q", 0)), int(event.get("r", 0)))
	root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.16)
	_spawn_kit_component("PROP_CRYSTAL_SHARD_1", Vector3(0.0, 0.06, 0.0), 0.95, 0.0, root)
	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.11
	beacon_mesh.height = 0.22
	beacon.mesh = beacon_mesh
	beacon.position.y = 0.62
	beacon.material_override = _material(Color("78d9d0"), Color("6effd5"))
	root.add_child(beacon)
	root.set_meta("beacon", beacon)
	world_root.add_child(root)
	event_visuals[event_id] = root

func _create_landmark_visual(landmark: Dictionary) -> void:
	var landmark_id := str(landmark.get("landmark_id", ""))
	if landmark_id.is_empty(): return
	var root := Node3D.new()
	root.name = "Landmark_%s" % landmark_id
	var coord := Vector2i(int(landmark.get("q", 0)), int(landmark.get("r", 0)))
	root.position = HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.16)
	var is_major := str(landmark.get("kind", "MINOR")) == "MAJOR"
	_spawn_kit_components(str(landmark.get("prop", "PROP_CRYSTAL_SHARD_1")), Vector3.ZERO, 1.05 if is_major else 0.70, 0.0, root)
	if is_major:
		var label := Label3D.new()
		label.text = str(landmark.get("name", "지형 표식"))
		label.font_size = 32
		label.outline_size = 7
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position.y = 1.35
		label.modulate = Color("c9e9e4")
		root.add_child(label)
	world_root.add_child(root)
	landmark_visuals[landmark_id] = root

func _node_style(fill: Color, border: Color) -> StyleBoxFlat:
	var cache_key := "%s:%s" % [fill.to_html(true), border.to_html(true)]
	if node_style_cache.has(cache_key):
		return node_style_cache[cache_key]
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.68)
	style.shadow_size = 7
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	node_style_cache[cache_key] = style
	return style

func _create_pawn() -> void:
	pawn = Node3D.new()
	pawn.name = "SquadPawn"
	pawn.position = _pawn_world_position()
	world_root.add_child(pawn)
	# This shared, shallow squad clearing follows the logical pawn one hex at a
	# time. It provides a visible physical ground socket at the map's streaming
	# boundary rather than allowing a valid save coordinate to look like it is
	# floating over the ocean while its surrounding terrain chunk wakes up.
	var grounding_patch := MeshInstance3D.new()
	grounding_patch.name = "SquadGroundingTerrace"
	var grounding_mesh := CylinderMesh.new()
	grounding_mesh.top_radius = 1.10
	grounding_mesh.bottom_radius = 1.20
	grounding_mesh.height = 0.075
	grounding_mesh.radial_segments = 12
	grounding_patch.mesh = grounding_mesh
	grounding_patch.position.y = -0.104
	grounding_patch.rotation_degrees.y = 15.0
	var party_coord := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	var party_tile: Dictionary = grid.tile(party_coord)
	grounding_patch.material_override = _material(_terrain_surface_color(party_tile).lightened(0.05))
	pawn.add_child(grounding_patch)
	pawn_grounding_terrace = grounding_patch
	var contact_shadow := MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.54
	shadow_mesh.bottom_radius = 0.64
	shadow_mesh.height = 0.025
	shadow_mesh.radial_segments = 16
	contact_shadow.mesh = shadow_mesh
	contact_shadow.position.y = 0.015
	contact_shadow.material_override = _material(Color("061019"))
	pawn.add_child(contact_shadow)
	var pedestal := MeshInstance3D.new()
	var pedestal_mesh := CylinderMesh.new()
	pedestal_mesh.top_radius = 0.43
	pedestal_mesh.bottom_radius = 0.54
	pedestal_mesh.height = 0.16
	pedestal_mesh.radial_segments = 8
	pedestal.mesh = pedestal_mesh
	pedestal.material_override = _material(Color("18485a"), Color("196b71"))
	pedestal.position.y = 0.07
	pawn.add_child(pedestal)
	var crest := MeshInstance3D.new()
	var crest_mesh := TorusMesh.new()
	crest_mesh.inner_radius = 0.28
	crest_mesh.outer_radius = 0.36
	crest_mesh.rings = 8
	crest_mesh.ring_segments = 16
	crest.mesh = crest_mesh
	crest.material_override = _material(Color("e8b45d"), Color("d88c32"))
	crest.position.y = 0.17
	pawn.add_child(crest)
	pawn_visual = Node3D.new()
	pawn_visual.name = "PawnVisual"
	# The map pawn is its own small SD token, not a large profile-card cutout.
	# Keep the same combat-atlas rendering contract as hostile pawns so both
	# sides share a coherent map scale, shadow, and light direction.
	pawn_visual.position.y = 0.18
	pawn.add_child(pawn_visual)
	_spawn_kit_components("SQUAD_STANDARD", Vector3(0.0, 0.02, 0.0), 1.48, 0.0, pawn_visual)
	var lead_id := _map_leader_id()
	pawn_animation_pack = _map_idle_texture(lead_id)
	if not pawn_animation_pack.is_empty():
		pawn_sprite = Sprite3D.new()
		pawn_sprite.name = "SquadIdleSprite"
		pawn_sprite.texture = pawn_animation_pack.texture
		pawn_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		pawn_sprite.pixel_size = 0.0152
		# Keep the squad in the production world depth pass for the same reason as
		# hostile pawns: a map pawn cannot claim grounded placement while bypassing
		# the terrain, water and encounter-socket depth relationships.
		# The selected squad is map interaction UI as well as world art. Render the
		# actual cutout itself above range/fog presentation so a translucent ground
		# layer can never wash out its body or face.
		pawn_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		pawn_sprite.no_depth_test = true
		pawn_sprite.shaded = false
		pawn_sprite.modulate = Color.WHITE
		var leader_frame_size: Vector2 = pawn_animation_pack.get("frame_size", Vector2(104.0, 104.0))
		var leader_anchor: Vector2 = pawn_animation_pack.get("foot_anchor", Vector2(0.5, 0.88))
		pawn_sprite.position.y = _sprite_center_y_for_foot(0.15, PAWN_VISUAL_BASE_Y, leader_frame_size.y, pawn_sprite.pixel_size, leader_anchor.y)
		pawn_sprite.render_priority = 127
		pawn_visual.add_child(pawn_sprite)
		pawn_occlusion_silhouette = _add_occlusion_silhouette(pawn_sprite, pawn_visual, "SquadOcclusionSilhouette", Color("69f4e2"))
		if pawn_occlusion_silhouette != null:
			# The former enlarged duplicate caused a visible translucent after-image.
			# The real pawn now owns top-layer visibility, so retire the duplicate.
			pawn_occlusion_silhouette.visible = false
			pawn_occlusion_silhouette.set_meta("squad_visibility_authority", true)
	else:
		# The Blender-made standard remains legible for leaders without a map-pawn
		# portrait instead of falling back to a grey capsule or generic primitive.
		pawn_visual.position.y += 0.08
	pawn_banner = MeshInstance3D.new()
	var signal_mesh := PrismMesh.new()
	signal_mesh.left_to_right = 0.52
	signal_mesh.size = Vector3(0.30, 0.46, 0.12)
	pawn_banner.mesh = signal_mesh
	pawn_banner.material_override = _material(Color("f1b864"), Color("dc8f39"))
	pawn_banner.position = Vector3(0.0, 1.05, 0.0)
	pawn_visual.add_child(pawn_banner)
	_set_pawn_motion_state("IDLE")
	pawn_last_position = pawn.position

func _create_web_pawn_front_overlay() -> void:
	# Compatibility Web can sort an alpha Sprite3D below a depth-tested terrain
	# overlay even when render_priority/no_depth_test are requested. Mirror the
	# selected squad's *same atlas frame* into the UI layer on Web. This keeps the
	# pawn entirely above yellow movement cells and fog without inventing a second
	# character image or changing hit/map coordinates.
	if not OS.has_feature("web") or overlay == null or pawn_sprite == null or pawn_sprite.texture == null:
		return
	pawn_front_overlay = TextureRect.new()
	pawn_front_overlay.name = "SquadPawnTopLayer"
	if pawn_front_overlay.texture != pawn_sprite.texture:
		pawn_front_overlay.texture = pawn_sprite.texture
	pawn_front_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pawn_front_overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pawn_front_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pawn_front_overlay.z_index = 48
	pawn_front_overlay.show_behind_parent = false
	overlay.add_child(pawn_front_overlay)
	_apply_pawn_facing()
	# The UI copy is the Web presentation authority. Keep the physical base,
	# contact shadow and socket in 3D, but avoid a translucent double cutout.
	pawn_sprite.visible = false
	_sync_web_pawn_front_overlay()

func _sync_web_pawn_front_overlay() -> void:
	if pawn_front_overlay == null or not is_instance_valid(pawn_front_overlay) \
		or pawn_sprite == null or not is_instance_valid(pawn_sprite) \
		or camera == null or not is_instance_valid(camera) \
		or overlay == null or not is_instance_valid(overlay) \
		or pawn == null or not is_instance_valid(pawn):
		return
	if pawn_sprite.texture == null or overlay.size.y <= 1.0:
		pawn_front_overlay.visible = false
		return
	pawn_front_overlay.texture = pawn_sprite.texture
	var frame_size: Vector2 = pawn_animation_pack.get("frame_size", Vector2(104.0, 104.0))
	var foot_anchor: Vector2 = pawn_animation_pack.get("foot_anchor", Vector2(0.5, 0.88))
	var screen_pixels_per_world := overlay.size.y / maxf(0.001, camera.size)
	var token_size := frame_size * pawn_sprite.pixel_size * screen_pixels_per_world
	# Web hides the world Sprite3D and presents this UI copy instead. Project the
	# actual tweened pawn transform; projecting the logical map hex made the only
	# visible character stay still for the whole tween and snap at cell arrival.
	var contact := _overlay_position_from_world(pawn.global_position + Vector3(0.0, 0.15, 0.0))
	pawn_front_overlay.size = token_size
	pawn_front_overlay.position = contact - Vector2(token_size.x * foot_anchor.x, token_size.y * foot_anchor.y)
	pawn_front_overlay.flip_h = not pawn_facing_right
	pawn_front_overlay.visible = _coord_is_in_player_vision(_player_map_coord())

func _map_leader_selection_unlocked() -> bool:
	# Stage 1 teaches the authored lead automatically.  The first victory unlocks
	# player choice permanently, including immediately before the next battle and
	# after returning from any battle result.
	return int(AppState.profile.get("stage_stars", {}).get("CH01-N01", 0)) > 0

func _map_leader_id() -> String:
	var party: Array = AppState.get_party()
	if party.is_empty():
		return ""
	if not _map_leader_selection_unlocked():
		return str(party[0])
	var saved_id := str(map_state.get("map_leader_id", ""))
	return saved_id if party.has(saved_id) else str(party[0])

func _character_display_name(character_id: String) -> String:
	var character := DataRegistry.character(character_id)
	if character.is_empty():
		return character_id
	return LocalizationService.tr_key(str(character.get("name_key", character_id))).replace(" (DEV)", "")

func _open_map_leader_selector() -> void:
	if not _map_leader_selection_unlocked():
		_focus_current(false)
		_show_map_notice("첫 작전은 마에루로 진행합니다 · 일반 1 클리어 후 맵 대표 선택 해금")
		return
	if leader_selector_layer != null and is_instance_valid(leader_selector_layer):
		leader_selector_layer.queue_free()
	leader_selector_layer = Control.new()
	leader_selector_layer.name = "MapLeaderSelector"
	leader_selector_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	leader_selector_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	leader_selector_layer.z_index = 220
	add_child(leader_selector_layer)
	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color("02070dcc")
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed or event is InputEventScreenTouch and event.pressed:
			_close_map_leader_selector()
	)
	leader_selector_layer.add_child(dimmer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var runtime_size := _runtime_layout_size()
	var portrait := runtime_size.y > runtime_size.x
	var panel_size := Vector2(minf(runtime_size.x * 0.90, 660.0), minf(runtime_size.y * 0.82, 600.0))
	panel.position = -panel_size * 0.5
	panel.size = panel_size
	panel.add_theme_stylebox_override("panel", _panel_style(Color("07111cf5"), Color("76e2d0"), 2, 18))
	leader_selector_layer.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	var title := Label.new()
	title.text = "맵 대표 캐릭터"
	title.add_theme_font_size_override("font_size", 30 if not portrait else 25)
	title.add_theme_color_override("font_color", Color("f4d88d"))
	content.add_child(title)
	var guide := Label.new()
	guide.text = "현재 파티에서 선택 · 선택한 캐릭터는 전투 진입 전·복귀 후 맵에 계속 표시됩니다."
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.add_theme_font_size_override("font_size", 19)
	guide.add_theme_color_override("font_color", Color("b9cbd3"))
	content.add_child(guide)
	for character_id_value in AppState.get_party():
		var character_id := str(character_id_value)
		var character := DataRegistry.character(character_id)
		var role := str(character.get("role", ""))
		var selected := character_id == _map_leader_id()
		var option := _button(("◆ " if selected else "") + _character_display_name(character_id) + ("  ·  " + role if not role.is_empty() else ""), _select_map_leader.bind(character_id), Vector2(panel_size.x - 40.0, 58.0))
		option.disabled = selected
		content.add_child(option)
	var close_button := _button("닫기", _close_map_leader_selector, Vector2(panel_size.x - 40.0, 54.0))
	content.add_child(close_button)

func _close_map_leader_selector() -> void:
	if leader_selector_layer != null and is_instance_valid(leader_selector_layer):
		leader_selector_layer.queue_free()
	leader_selector_layer = null

func _select_map_leader(character_id: String) -> void:
	if not AppState.get_party().has(character_id):
		return
	var next_pack := _map_idle_texture(character_id)
	if next_pack.is_empty():
		_show_map_notice("해당 캐릭터의 맵 SD 에셋을 불러오지 못했습니다")
		return
	map_state.map_leader_id = character_id
	pawn_animation_pack = next_pack
	if pawn_sprite != null:
		pawn_sprite.texture = next_pack.get("texture")
		var frame_size: Vector2 = next_pack.get("frame_size", Vector2(104.0, 104.0))
		var anchor: Vector2 = next_pack.get("foot_anchor", Vector2(0.5, 0.88))
		pawn_sprite.position.y = _sprite_center_y_for_foot(0.15, PAWN_VISUAL_BASE_Y, frame_size.y, pawn_sprite.pixel_size, anchor.y)
	if pawn_occlusion_silhouette != null:
		pawn_occlusion_silhouette.texture = pawn_sprite.texture
		pawn_occlusion_silhouette.position = pawn_sprite.position
	SaveService.save_game()
	_close_map_leader_selector()
	_show_map_notice("맵 대표 변경 · %s" % _character_display_name(character_id))

func _pawn_world_position() -> Vector3:
	var coord := Vector2i(int(map_state.current_q), int(map_state.current_r))
	return HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.14)

func _movement_overlay_material(color: Color, emission := Color.BLACK, always_on_top := false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(true), emission.to_html(true), str(always_on_top)]
	if movement_overlay_material_cache.has(key):
		return movement_overlay_material_cache[key]
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Fill and cell seams belong on the physical ground and therefore sit behind
	# pawns/props. Only the outer boundary may request no-depth presentation.
	material.no_depth_test = always_on_top
	material.render_priority = 90 if always_on_top else 0
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.0
	movement_overlay_material_cache[key] = material
	return material

func _route_overlay_material(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(true), emission.to_html(true)]
	if route_overlay_material_cache.has(key):
		return route_overlay_material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 92
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.4
	route_overlay_material_cache[key] = material
	return material

func _movement_hex_corners(coord: Vector2i, surface_y: float) -> Array[Vector3]:
	var center := HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y)
	var corners: Array[Vector3] = []
	var radius := TILE_SIZE * 0.92
	for index in range(6):
		var angle := deg_to_rad(30.0 + float(index) * 60.0)
		corners.append(center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	return corners

static func _movement_boundary_corner_indices(direction_index: int) -> Vector2i:
	return Vector2i(posmod(5 - direction_index, 6), posmod(6 - direction_index, 6))

func _unresolved_encounter_stop_hexes() -> Dictionary:
	var stop_hexes: Dictionary = {}
	for node_value in definition.get("nodes", []):
		var node: Dictionary = node_value
		var stage_id := str(node.get("stage_id", ""))
		var node_id := str(node.get("node_id", ""))
		# Locked future operations and cleared markers are not physical blockers.
		# Only an active hostile owns a terminal contact hex.
		if stage_id.is_empty() or not AppState.is_stage_unlocked(stage_id) or MapExplorationServiceScript.encounter_cleared(map_state, node_id) or int(AppState.profile.stage_stars.get(stage_id, 0)) > 0:
			continue
		stop_hexes[HexCoordScript.key(_encounter_coord(node))] = true
	return stop_hexes

func _movement_range_allowlist() -> Dictionary:
	# Fog/reveal is presentation authority, never traversal authority.  The prior
	# implementation intersected the walk graph with persisted revealed_tiles.
	# A route-selected cell could therefore be legal for one pulse, then become
	# the party's *excluded start cell* on the next pulse and soft-lock both the
	# yellow range and every objective route.  Movement remains naturally bounded
	# by movement points and can_step; the eight-plus-cell sight radius controls
	# what can be selected and rendered separately.
	return _traversal_allowlist()

func _traversal_allowlist() -> Dictionary:
	# An empty allowlist is HexPathfinder's explicit "all authored traversable
	# tiles" contract.  The generated grid now carries the actual road/clearing
	# lanes and blocked dense-forest/cliff barriers, so fog never becomes movement
	# authority and decorative terrain never becomes globally walkable.
	return {}

func _find_player_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	return HexPathfinderScript.find_path(grid, start, goal, _traversal_allowlist(), _unresolved_encounter_stop_hexes())

func _append_range_triangle(vertices: Array[Vector3], a: Vector3, b: Vector3, c: Vector3) -> void:
	# ImmediateMesh reports an engine error when surface_end closes a surface that
	# received no vertices. Keep zero-area geometry out as well: a collapsed edge
	# should behave like no highlight, not create an invalid GPU triangle.
	if (b - a).cross(c - a).length_squared() <= 0.00000001:
		return
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)

func _movement_triangle_mesh(vertices: Array[Vector3], material: Material) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	if vertices.size() < 3:
		return mesh
	var valid_vertices: Array[Vector3] = []
	for index in range(0, vertices.size() - 2, 3):
		var a := vertices[index]
		var b := vertices[index + 1]
		var c := vertices[index + 2]
		if (b - a).cross(c - a).length_squared() <= 0.00000001:
			continue
		valid_vertices.append(a)
		valid_vertices.append(b)
		valid_vertices.append(c)
	if valid_vertices.is_empty():
		return mesh
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for vertex in valid_vertices:
		mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	return mesh

func _append_range_edge_ribbon(vertices: Array[Vector3], from: Vector3, to: Vector3, half_width: float) -> void:
	if half_width <= 0.0 or from.distance_squared_to(to) <= 0.00000001:
		return
	var tangent := (to - from).normalized()
	var side := Vector3(-tangent.z, 0.0, tangent.x) * half_width
	var a := from - side
	var b := from + side
	var c := to + side
	var d := to - side
	_append_range_triangle(vertices, a, b, c)
	_append_range_triangle(vertices, a, c, d)

func _clear_movement_range_overlay() -> void:
	movement_range_render_generation += 1
	movement_range_reachable.clear()
	web_movement_visible_keys.clear()
	web_movement_projection_camera = Vector3(1.0e20, 1.0e20, 1.0e20)
	web_movement_projection_size = Vector2(-1.0, -1.0)
	web_movement_projection_camera_size = -1.0
	web_movement_projection_origin_screen = Vector2.ZERO
	if web_movement_overlay != null:
		web_movement_overlay.position = Vector2.ZERO
		web_movement_overlay.clear_geometry()
	movement_range_fill.mesh = null
	movement_range_grid.mesh = null
	movement_range_boundary.mesh = null
	movement_range_grid.visible = true
	movement_range_boundary.visible = true

func _apply_web_movement_range_details(generation: int, cell_grid_mesh: ImmediateMesh, boundary_mesh: ImmediateMesh) -> void:
	# Assigning three dynamic 3D buffers in the same browser frame caused the
	# post-step 50-70ms pause. The gold fill is immediate authority; its internal
	# seams and outer edge arrive on the next two frames, each below one frame's
	# upload budget. A generation token prevents stale turn geometry from landing.
	await get_tree().process_frame
	if not _web_async_owner_alive() or movement_range_grid == null or not is_instance_valid(movement_range_grid) or generation != movement_range_render_generation:
		return
	movement_range_grid.mesh = cell_grid_mesh if cell_grid_mesh.get_surface_count() > 0 else null
	movement_range_grid.visible = true
	await get_tree().process_frame
	if not _web_async_owner_alive() or movement_range_boundary == null or not is_instance_valid(movement_range_boundary) or generation != movement_range_render_generation:
		return
	movement_range_boundary.mesh = boundary_mesh if boundary_mesh.get_surface_count() > 0 else null
	movement_range_boundary.visible = true

func _update_web_movement_range_projection(force_projection := false) -> void:
	if not OS.has_feature("web") or web_movement_overlay == null or not is_instance_valid(web_movement_overlay):
		return
	if web_movement_visible_keys.is_empty() \
		or camera == null or not is_instance_valid(camera) \
		or viewport == null or not is_instance_valid(viewport) \
		or overlay == null or not is_instance_valid(overlay):
		web_movement_overlay.clear_geometry()
		return
	if not force_projection \
		and camera_target.distance_squared_to(web_movement_projection_camera) <= 0.000001 \
		and overlay.size.is_equal_approx(web_movement_projection_size) \
		and is_equal_approx(camera.size, web_movement_projection_camera_size):
		return
	if not force_projection \
		and web_movement_projection_camera.x < 1.0e19 \
		and overlay.size.is_equal_approx(web_movement_projection_size) \
		and is_equal_approx(camera.size, web_movement_projection_camera_size):
		# With a fixed orthographic angle and zoom, camera translation applies one
		# common screen delta to every highlighted hex. Move the overlay Control as
		# a unit instead of rebuilding every polygon and edge on every walk frame.
		var current_origin_screen := _overlay_position_from_world(Vector3.ZERO)
		web_movement_overlay.position = current_origin_screen - web_movement_projection_origin_screen
		web_movement_projection_camera = camera_target
		return
	web_movement_overlay.position = Vector2.ZERO
	var cells: Array[PackedVector2Array] = []
	var grid_segments := PackedVector2Array()
	var boundary_segments := PackedVector2Array()
	var emitted_edges: Dictionary = {}
	for key in web_movement_visible_keys:
		var coord := HexCoordScript.from_key(key)
		var surface_y := float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.105
		var world_corners := _movement_hex_corners(coord, surface_y)
		var polygon := PackedVector2Array()
		for corner in world_corners:
			polygon.append(_overlay_position_from_world(corner))
		cells.append(polygon)
		for direction_index in range(HexCoordScript.DIRECTIONS.size()):
			var neighbour := coord + HexCoordScript.DIRECTIONS[direction_index]
			var neighbour_key := HexCoordScript.key(neighbour)
			var edge_parts := [key, neighbour_key]
			edge_parts.sort()
			var edge_key := "%s|%s" % [edge_parts[0], edge_parts[1]]
			if emitted_edges.has(edge_key):
				continue
			emitted_edges[edge_key] = true
			var edge_indices := _movement_boundary_corner_indices(direction_index)
			var from := polygon[edge_indices.x]
			var to := polygon[edge_indices.y]
			grid_segments.append(from)
			grid_segments.append(to)
			if not movement_range_reachable.has(neighbour_key):
				boundary_segments.append(from)
				boundary_segments.append(to)
	web_movement_overlay.set_geometry(cells, grid_segments, boundary_segments)
	web_movement_projection_camera = camera_target
	web_movement_projection_size = overlay.size
	web_movement_projection_camera_size = camera.size
	web_movement_projection_origin_screen = _overlay_position_from_world(Vector3.ZERO)

func _update_movement_range_overlay() -> void:
	if movement_range_fill == null or movement_range_grid == null or movement_range_boundary == null:
		return
	movement_range_render_generation += 1
	var render_generation := movement_range_render_generation
	var movement_points := MapExplorationServiceScript.movement_remaining(map_state, definition)
	# During a pawn tween the starting range remains the player's movement
	# authority and route context. Do not erase it between pointer confirmation
	# and arrival; input is already locked by `moving`.
	if moving:
		return
	if turn_transitioning or movement_points <= 0:
		_clear_movement_range_overlay()
		return
	var current := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	movement_range_reachable = HexPathfinderScript.reachable_within(grid, current, movement_points, _movement_range_allowlist(), _unresolved_encounter_stop_hexes())
	# Keep the visual/input authority explicitly bounded even if a migrated or
	# externally authored pathfinder payload is ever contaminated. Account growth
	# may raise 3 -> 4, but neither the gold overlay nor direct movement can expand
	# to seven cells from a four-point turn.
	var bounded_reachable: Dictionary = {}
	for key_value in movement_range_reachable.keys():
		var key := str(key_value)
		var coord := HexCoordScript.from_key(key)
		var required_steps := int(movement_range_reachable[key_value])
		if required_steps <= movement_points and HexCoordScript.distance(current, coord) <= movement_points:
			bounded_reachable[key] = required_steps
	movement_range_reachable = bounded_reachable
	var reachable_keys: Array = movement_range_reachable.keys()
	reachable_keys.sort()
	if reachable_keys.is_empty():
		_clear_movement_range_overlay()
		return
	# Keep the occupied socket visually clean. The current coordinate remains in
	# movement_range_reachable for path/input authority, but it is not a movement
	# destination and must not tint the squad art yellow.
	var visible_range_keys: Array = reachable_keys.filter(func(key_value): return HexCoordScript.from_key(str(key_value)) != current)
	if visible_range_keys.is_empty():
		web_movement_visible_keys.clear()
		if web_movement_overlay != null:
			web_movement_overlay.clear_geometry()
		movement_range_fill.mesh = null
		movement_range_grid.mesh = null
		movement_range_boundary.mesh = null
		return
	if OS.has_feature("web"):
		web_movement_visible_keys.clear()
		for key_value in visible_range_keys:
			web_movement_visible_keys.append(str(key_value))
		movement_range_fill.mesh = null
		movement_range_grid.mesh = null
		movement_range_boundary.mesh = null
		movement_range_fill.visible = false
		movement_range_grid.visible = false
		movement_range_boundary.visible = false
		_update_web_movement_range_projection(true)
		return
	var fill_vertices: Array[Vector3] = []
	for key_value in visible_range_keys:
		var coord := HexCoordScript.from_key(str(key_value))
		var surface_y := float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.105
		var center := HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y)
		var corners := _movement_hex_corners(coord, surface_y)
		for corner_index in range(6):
			# Match the Compatibility renderer's clockwise top-face authority.
			_append_range_triangle(fill_vertices, center, corners[corner_index], corners[(corner_index + 1) % 6])
	var fill_mesh := _movement_triangle_mesh(fill_vertices, _movement_overlay_material(Color("f6b93f68"), Color("9a5f12")))
	# Every reachable cell keeps a subtle translucent seam. Shared edges are
	# emitted once so adjacent highlights remain individually countable without
	# becoming brighter than the rest of the grid.
	var cell_grid_vertices: Array[Vector3] = []
	var emitted_edges: Dictionary = {}
	for key_value in visible_range_keys:
		var coord := HexCoordScript.from_key(str(key_value))
		var surface_y := float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.125
		var corners := _movement_hex_corners(coord, surface_y)
		for direction_index in range(HexCoordScript.DIRECTIONS.size()):
			var neighbour := coord + HexCoordScript.DIRECTIONS[direction_index]
			var neighbour_key := HexCoordScript.key(neighbour)
			var edge_parts := [str(key_value), neighbour_key]
			edge_parts.sort()
			var edge_key := "%s|%s" % [edge_parts[0], edge_parts[1]]
			if emitted_edges.has(edge_key):
				continue
			emitted_edges[edge_key] = true
			var edge_indices := _movement_boundary_corner_indices(direction_index)
			_append_range_edge_ribbon(cell_grid_vertices, corners[edge_indices.x], corners[edge_indices.y], 0.030)
	var cell_grid_mesh := _movement_triangle_mesh(cell_grid_vertices, _movement_overlay_material(Color("ffd36ba8"), Color("b57618")))
	var boundary_vertices: Array[Vector3] = []
	for key_value in visible_range_keys:
		var coord := HexCoordScript.from_key(str(key_value))
		var surface_y := float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.135
		var corners := _movement_hex_corners(coord, surface_y)
		for direction_index in range(HexCoordScript.DIRECTIONS.size()):
			var neighbour := coord + HexCoordScript.DIRECTIONS[direction_index]
			if movement_range_reachable.has(HexCoordScript.key(neighbour)):
				continue
			# DIRECTIONS rotate clockwise in axial/world space while corner indices
			# rotate counter-clockwise. Map each outward direction to its actual edge.
			var edge_indices := _movement_boundary_corner_indices(direction_index)
			var from: Vector3 = corners[edge_indices.x]
			var to: Vector3 = corners[edge_indices.y]
			_append_range_edge_ribbon(boundary_vertices, from, to, 0.070)
	var boundary_mesh := _movement_triangle_mesh(boundary_vertices, _movement_overlay_material(Color("fff0a6f5"), Color("ffb52b"), true))
	movement_range_fill.mesh = fill_mesh if fill_mesh.get_surface_count() > 0 else null
	if OS.has_feature("web"):
		movement_range_grid.visible = false
		movement_range_boundary.visible = false
		call_deferred("_apply_web_movement_range_details", render_generation, cell_grid_mesh, boundary_mesh)
	else:
		movement_range_grid.mesh = cell_grid_mesh if cell_grid_mesh.get_surface_count() > 0 else null
		movement_range_boundary.mesh = boundary_mesh if boundary_mesh.get_surface_count() > 0 else null

func _place_web_overlay_segment(segment: ColorRect, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	var delta := to - from
	var length := delta.length()
	if length <= 0.01:
		segment.visible = false
		return
	segment.color = color
	segment.size = Vector2(length, width)
	segment.position = (from + to) * 0.5 - segment.size * 0.5
	segment.pivot_offset = segment.size * 0.5
	segment.rotation = delta.angle()
	segment.visible = true

func _ensure_web_route_rect_count(required_count: int) -> void:
	while web_route_rects.size() < required_count:
		var segment := ColorRect.new()
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.visible = false
		web_route_overlay.add_child(segment)
		web_route_rects.append(segment)

func _update_web_route_line(force_projection := false) -> void:
	if not OS.has_feature("web") or web_route_overlay == null or not is_instance_valid(web_route_overlay):
		return
	if preview_path.size() < 2 \
		or camera == null or not is_instance_valid(camera) \
		or viewport == null or not is_instance_valid(viewport) \
		or overlay == null or not is_instance_valid(overlay):
		web_route_overlay.visible = false
		web_route_overlay.position = Vector2.ZERO
		web_route_projection_camera = Vector3(1.0e20, 1.0e20, 1.0e20)
		web_route_projection_size = Vector2(-1.0, -1.0)
		web_route_projection_camera_size = -1.0
		web_route_projection_origin_screen = Vector2(1.0e20, 1.0e20)
		return
	var geometry_changed := force_projection \
		or not overlay.size.is_equal_approx(web_route_projection_size) \
		or not is_equal_approx(camera.size, web_route_projection_camera_size)
	if not geometry_changed and web_route_projection_origin_screen.x < 1.0e19:
		# Orthographic camera panning is a common screen-space translation. Move the
		# pooled Control once instead of reprojecting every route point and querying
		# browser layout on every movement frame.
		var current_origin_screen := _overlay_position_from_world(Vector3.ZERO)
		web_route_overlay.position = current_origin_screen - web_route_projection_origin_screen
		web_route_projection_camera = camera_target
		return
	web_route_overlay.position = Vector2.ZERO
	var route_color := Color("4fd3c2") if preview_risk == "SAFE" else (Color("e7bd63") if preview_risk == "WATCHED" else Color("e87972"))
	var movement_points := MapExplorationServiceScript.movement_remaining(map_state, definition)
	_ensure_web_route_rect_count(preview_path.size() - 1)
	var projected_points := PackedVector2Array()
	for coord in preview_path:
		var surface_y := float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.57
		projected_points.append(_overlay_position_from_world(HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y)))
	var segment_width := 7.0 * _portrait_ui_scale(_runtime_layout_size())
	for segment_index in range(web_route_rects.size()):
		var segment := web_route_rects[segment_index]
		if segment_index >= projected_points.size() - 1:
			segment.visible = false
			continue
		var segment_color := route_color.lightened(0.18) if segment_index < movement_points else Color("657989")
		_place_web_overlay_segment(segment, projected_points[segment_index], projected_points[segment_index + 1], segment_width, segment_color)
	web_route_overlay.visible = true
	web_route_projection_camera = camera_target
	web_route_projection_size = overlay.size
	web_route_projection_camera_size = camera.size
	web_route_projection_origin_screen = _overlay_position_from_world(Vector3.ZERO)

func _update_web_selected_ring(force_projection := false) -> void:
	if not OS.has_feature("web") or web_selected_overlay == null or not is_instance_valid(web_selected_overlay):
		return
	var selected_target: Dictionary = selected_node if not selected_node.is_empty() else (selected_treasure if not selected_treasure.is_empty() else (selected_relay if not selected_relay.is_empty() else selected_event))
	if selected_target.is_empty() \
		or camera == null or not is_instance_valid(camera) \
		or viewport == null or not is_instance_valid(viewport) \
		or overlay == null or not is_instance_valid(overlay):
		web_selected_overlay.visible = false
		web_selected_overlay.position = Vector2.ZERO
		web_selected_projection_camera = Vector3(1.0e20, 1.0e20, 1.0e20)
		web_selected_projection_size = Vector2(-1.0, -1.0)
		web_selected_projection_camera_size = -1.0
		web_selected_projection_origin_screen = Vector2(1.0e20, 1.0e20)
		return
	var geometry_changed := force_projection \
		or not overlay.size.is_equal_approx(web_selected_projection_size) \
		or not is_equal_approx(camera.size, web_selected_projection_camera_size)
	if not geometry_changed and web_selected_projection_origin_screen.x < 1.0e19:
		var current_origin_screen := _overlay_position_from_world(Vector3.ZERO)
		web_selected_overlay.position = current_origin_screen - web_selected_projection_origin_screen
		web_selected_projection_camera = camera_target
		return
	web_selected_overlay.position = Vector2.ZERO
	var selected_coord := Vector2i(int(selected_target.get("q", 0)), int(selected_target.get("r", 0)))
	var surface_y := float(grid.tile(selected_coord).get("elevation", 0)) * ELEVATION_STEP + 0.18
	var ring_center := HexCoordScript.axial_to_world(selected_coord, TILE_SIZE, surface_y)
	var projected_points := PackedVector2Array()
	for point_index in range(6):
		var angle := PI / 6.0 + TAU * float(point_index) / 6.0
		var world_point := ring_center + Vector3(cos(angle) * 0.66, 0.0, sin(angle) * 0.66)
		projected_points.append(_overlay_position_from_world(world_point))
	var edge_width := 4.0 * _portrait_ui_scale(_runtime_layout_size())
	for edge_index in range(6):
		_place_web_overlay_segment(web_selected_rects[edge_index], projected_points[edge_index], projected_points[(edge_index + 1) % 6], edge_width, Color("fff0a6f0"))
	web_selected_overlay.visible = true
	web_selected_projection_camera = camera_target
	web_selected_projection_size = overlay.size
	web_selected_projection_camera_size = camera.size
	web_selected_projection_origin_screen = _overlay_position_from_world(Vector3.ZERO)

func _update_route_mesh() -> void:
	for segment in route_segments: segment.queue_free()
	for node in route_nodes: node.queue_free()
	route_segments.clear()
	route_nodes.clear()
	selected_ring.visible = false
	var immediate: ImmediateMesh = null
	if not OS.has_feature("web"):
		immediate = ImmediateMesh.new()
	var route_color := Color("4fd3c2") if preview_risk == "SAFE" else (Color("e7bd63") if preview_risk == "WATCHED" else Color("e87972"))
	var movement_points := MapExplorationServiceScript.movement_remaining(map_state, definition)
	var route_exceeds_pulse := preview_path.size() - 1 > movement_points
	if preview_path.size() >= 2:
		var guide_color := Color("657989") if route_exceeds_pulse else route_color.lightened(0.18)
		if OS.has_feature("web"):
			_update_web_route_line(true)
		else:
			immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _route_overlay_material(guide_color, guide_color.darkened(0.18)))
			for coord in preview_path:
				immediate.surface_add_vertex(HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.54))
			immediate.surface_end()
			for index in range(preview_path.size() - 1):
				var segment_color := route_color if index < movement_points else Color("516471")
				var from := HexCoordScript.axial_to_world(preview_path[index], TILE_SIZE, float(grid.tile(preview_path[index]).get("elevation", 0)) * ELEVATION_STEP + 0.57)
				var to := HexCoordScript.axial_to_world(preview_path[index + 1], TILE_SIZE, float(grid.tile(preview_path[index + 1]).get("elevation", 0)) * ELEVATION_STEP + 0.57)
				var ribbon := MeshInstance3D.new()
				var ribbon_mesh := BoxMesh.new()
				ribbon_mesh.size = Vector3(0.18, 0.045, from.distance_to(to))
				ribbon.mesh = ribbon_mesh
				ribbon.material_override = _route_overlay_material(segment_color, segment_color.darkened(0.05))
				ribbon.position = (from + to) * 0.5
				world_root.add_child(ribbon)
				ribbon.look_at(to, Vector3.UP)
				route_segments.append(ribbon)
				var pulse := MeshInstance3D.new()
				var pulse_mesh := CylinderMesh.new()
				pulse_mesh.top_radius = 0.12
				pulse_mesh.bottom_radius = 0.15
				pulse_mesh.height = 0.055
				pulse_mesh.radial_segments = 6
				pulse.mesh = pulse_mesh
				pulse.material_override = _route_overlay_material(Color("f5bc62") if index < movement_points else Color("667580"), Color("f3a83e") if index < movement_points else Color("34424c"))
				pulse.position = to + Vector3(0.0, 0.035, 0.0)
				world_root.add_child(pulse)
				route_nodes.append(pulse)
	var selected_target: Dictionary = selected_node if not selected_node.is_empty() else (selected_treasure if not selected_treasure.is_empty() else (selected_relay if not selected_relay.is_empty() else selected_event))
	if not selected_target.is_empty():
		if OS.has_feature("web"):
			_update_web_selected_ring(true)
		else:
			var selected_coord := Vector2i(int(selected_target.get("q", 0)), int(selected_target.get("r", 0)))
			selected_ring.position = HexCoordScript.axial_to_world(selected_coord, TILE_SIZE, float(grid.tile(selected_coord).get("elevation", 0)) * ELEVATION_STEP + 0.18)
			selected_ring.visible = true
	elif OS.has_feature("web"):
		_update_web_selected_ring(true)
	if OS.has_feature("web"):
		if preview_path.size() < 2:
			_update_web_route_line(true)
		route_mesh.mesh = null
	else:
		route_mesh.mesh = immediate
	# Route selection does not change the party coordinate or movement budget.
	# Rebuilding all three yellow authority meshes here made a double-click create
	# and upload them twice (selection, then turn completion), producing a 130ms
	# WebGL stall before the pawn even started walking. State/turn refreshes own
	# the movement overlay exactly once.

func _refresh_state_visuals(refresh_movement_range := true) -> void:
	if definition.is_empty(): return
	web_entity_projection_dirty = true
	# Canonical route reveal changes at progression boundaries, not while painting
	# a frame. Recomputing it here nested every revealed node against every macro
	# tile and sorted the result on ordinary movement, selection and turn refreshes.
	var revealed := _path_reveal_allowlist()
	if refresh_movement_range:
		_update_movement_range_overlay()
	for key in tile_meshes:
		var instance: MeshInstance3D = tile_meshes[key]
		var tile: Dictionary = instance.get_meta("tile")
		# Keep the thin authored terrain cap visible. It is the streamed local
		# surface that guarantees an actual renderable ground under map pawns when
		# the broad continuous landscape crosses a long-map district boundary.
		instance.visible = true
	for node in definition.get("nodes", []):
		var node_id := str(node.get("node_id", ""))
		var button_value = node_buttons.get(node_id, null)
		# Web presents the playable terrain one frame before deferred encounter
		# markers are built. The initial refresh must tolerate that intentional gap;
		# `_build_web_map_detail()` refreshes again as soon as every marker exists.
		if not button_value is Button:
			continue
		var button := button_value as Button
		var marker_root: Node3D = node_markers.get(node_id)
		var stage_id := str(node.get("stage_id", ""))
		var is_hard := stage_id.contains("-H")
		var key := "%d,%d" % [int(node.q), int(node.r)]
		var node_coord := _encounter_coord(node)
		var unlocked := stage_id == "" or AppState.is_stage_unlocked(stage_id)
		button.visible = _coord_is_in_player_vision(node_coord) and (revealed.has(key) or (not stage_id.is_empty() and unlocked)) and (stage_id == "" or hard_overlay == is_hard)
		if marker_root != null: marker_root.visible = button.visible
		if not button.visible: continue
		var stars := int(AppState.profile.stage_stars.get(stage_id, 0)) if stage_id != "" else 0
		var special_event := _event_encounter_for_node(str(node.get("node_id", "")))
		var marker := "◆" if stage_id == "" else ("★" if stars == 3 else ("✓" if stars > 0 else ("!" if not special_event.is_empty() and unlocked else ("◇" if unlocked else "🔒"))))
		var display_label := stage_display_text(stage_id, true, SettingsService.is_developer_mode()) if stage_id != "" else "탐색 거점"
		button.text = "%s %s" % [marker, display_label]
		button.tooltip_text = stage_display_text(stage_id, false, SettingsService.is_developer_mode()) if stage_id != "" else "릴레이 캠프"
		var fill := Color("081b2a") if not unlocked else Color("0b3040")
		var border := Color("71889a") if not unlocked else Color("80f3dc")
		if stars > 0:
			fill = Color("123b39")
			border = Color("ffd477")
		if stage_id == "":
			fill = Color("10364a")
			border = Color("ffd477")
		button.add_theme_stylebox_override("normal", _node_style(fill, border))
		button.add_theme_stylebox_override("hover", _node_style(fill.lightened(0.16), Color("fff1b5")))
		button.add_theme_stylebox_override("pressed", _node_style(fill.darkened(0.12), Color("ffffff")))
		button.disabled = moving or turn_transitioning or map_simulation_paused
		if marker_root != null:
			var marker_color := Color("78eed9") if unlocked else Color("5a7083")
			if stars > 0: marker_color = Color("f0c56e")
			if stage_id == "": marker_color = Color("f0c56e")
			for marker_child in marker_root.get_children():
				if marker_child is MeshInstance3D and (str(marker_child.name).contains("SYMBOL") or str(marker_child.name).contains("FallbackMarker")):
					(marker_child as MeshInstance3D).material_override = _cached_material(marker_color, marker_color.darkened(0.18))
		var enemy_root: Node3D = enemy_pawns.get(str(node.node_id))
		if enemy_root != null:
			var cleared := _node_encounter_cleared(node)
			var encounter_coord := _encounter_coord(node)
			var camera_coord := HexCoordScript.world_to_axial(camera_target, TILE_SIZE)
			enemy_root.visible = button.visible and _coord_is_in_player_vision(encounter_coord) and not cleared and unlocked and _map_entity_is_locally_renderable(encounter_coord, camera_coord, STREAM_RADIUS + 2)
			# A cleared relay stays in the map as a quiet visual anchor, but the
			# hostile pawn is gone.  This keeps the encounter readable before text.
			if marker_root != null and cleared:
				marker_root.visible = button.visible
	for treasure in definition.get("treasures", []):
		var treasure_id := str(treasure.get("treasure_id", ""))
		var root: Node3D = treasure_visuals.get(treasure_id)
		if root == null: continue
		var state := MapExplorationServiceScript.treasure_state(map_state, treasure_id)
		var revealed_treasure := state == "REVEALED"
		# HIDDEN/HINTED keeps only the authored crystal/ruin dressing created
		# above.  Do not expose the cache ring, chest, route, or exact target
		# before proximity has actually revealed it.
		var treasure_coord := Vector2i(int(treasure.get("q", 0)), int(treasure.get("r", 0)))
		root.visible = _coord_is_in_player_vision(treasure_coord) and state != "UNDISCOVERED" and state != "CLAIMED"
		for visual_name in ["crate", "lid", "seal", "glow"]:
			var visual = root.get_meta(visual_name, null)
			if visual == null: continue
			visual.visible = revealed_treasure
			if visual_name == "glow" and revealed_treasure:
				visual.scale = Vector3.ONE
	for relay in definition.get("relays", []):
		var relay_id := str(relay.get("relay_id", ""))
		var relay_root: Node3D = relay_visuals.get(relay_id)
		if relay_root == null: continue
		var relay_key := "%d,%d" % [int(relay.get("q", 0)), int(relay.get("r", 0))]
		var relay_active := MapExplorationServiceScript.relay_state(map_state, relay_id) == "ACTIVE"
		var relay_coord := Vector2i(int(relay.get("q", 0)), int(relay.get("r", 0)))
		relay_root.visible = _coord_is_in_player_vision(relay_coord) and (relay_active or revealed.has(relay_key))
		var relay_signal = relay_root.get_meta("signal", null)
		if relay_signal is MeshInstance3D:
			(relay_signal as MeshInstance3D).material_override = _cached_material(Color("71f7d3") if relay_active else Color("4c6876"), Color("48f4d1") if relay_active else Color("183744"))
		var relay_label = relay_root.get_meta("label", null)
		if relay_label is Label3D:
			(relay_label as Label3D).text = "활성 릴레이" if relay_active else "고장 난 릴레이"
	for event in definition.get("map_events", []):
		var event_id := str(event.get("event_id", ""))
		var event_root: Node3D = event_visuals.get(event_id)
		if event_root == null: continue
		var event_status := MapExplorationServiceScript.event_state(map_state, event_id)
		var event_coord := Vector2i(int(event.get("q", 0)), int(event.get("r", 0)))
		event_root.visible = _coord_is_in_player_vision(event_coord) and event_status == "DISCOVERED"
	for landmark in definition.get("landmarks", []):
		var landmark_id := str(landmark.get("landmark_id", ""))
		var landmark_root: Node3D = landmark_visuals.get(landmark_id)
		if landmark_root == null:
			continue
		var landmark_coord := Vector2i(int(landmark.get("q", 0)), int(landmark.get("r", 0)))
		landmark_root.visible = _coord_is_in_player_vision(landmark_coord)
	for node_id in enemy_pawns:
		_update_enemy_pawn_from_simulation(str(node_id))
	var completion := MapExplorationServiceScript.completion(map_state, definition)
	if Time.get_ticks_msec() >= map_notice_until_msec:
		var status_runtime_size := _runtime_layout_size()
		var compact_status := status_runtime_size.y > status_runtime_size.x or status_runtime_size.x <= 980.0
		var status_template := "제1장 · %s · 이동 %d/%d · 탐험 %d%%" if compact_status else "제1장  ·  꺼진 노선의 신호  ·  %s  ·  이동 %d/%d  ·  탐험 %d%%"
		var status_mode := ("위험" if hard_overlay else "일반") if compact_status else ("위험 작전" if hard_overlay else "일반 작전")
		status_label.text = status_template % [status_mode, int(map_state.get("movement_points", 0)), int(map_state.get("movement_points_max", 0)), int(completion.get("percent", 0))]
	if wait_button != null: wait_button.disabled = moving or turn_transitioning or map_simulation_paused
	_update_next_encounter_button()
	# `_update_panel()` owns responsive layout and minimap configuration. Calling
	# the minimap here as well duplicated a full route traversal every refresh.
	_update_panel()
	_queue_web_enemy_pawn_stream()

func _update_route_minimap() -> void:
	if route_minimap == null: return
	route_minimap.configure(definition, map_state, selected_node, hard_overlay)

func _next_encounter_node() -> Dictionary:
	var route: Array = definition.get("hard_route", []) if hard_overlay else definition.get("normal_route", [])
	var cleared_candidate: Dictionary = {}
	for stage_value in route:
		var stage_id := str(stage_value)
		if not AppState.is_stage_unlocked(stage_id): continue
		var node := ChapterMapLoaderScript.node_for_stage(definition, stage_id)
		if node.is_empty(): continue
		var stars := int(AppState.profile.stage_stars.get(stage_id, 0))
		if stars <= 0: return node
		if cleared_candidate.is_empty(): cleared_candidate = node
	return cleared_candidate

func _update_next_encounter_button() -> void:
	if next_encounter_button == null: return
	var next_node := _next_encounter_node()
	var next_visible := not next_node.is_empty() and _coord_is_in_player_vision(_encounter_coord(next_node))
	next_encounter_button.visible = next_visible
	next_encounter_button.disabled = moving or turn_transitioning or next_node.is_empty()
	if not next_visible: return
	var stage_id := str(next_node.get("stage_id", ""))
	next_encounter_button.text = "다음 조우  ·  %s" % stage_display_text(stage_id, true, SettingsService.is_developer_mode())

func _select_next_encounter() -> void:
	var next_node := _next_encounter_node()
	if next_node.is_empty(): return
	if not _coord_is_in_player_vision(_encounter_coord(next_node)):
		_show_map_notice("다음 조우는 안개 너머에 있습니다 · 노란 이동 범위로 전진하세요")
		return
	_select_node(next_node)

func _select_node(node: Dictionary) -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	var node_id := str(node.get("node_id", ""))
	var stage_id := str(node.get("stage_id", ""))
	# A completed encounter remains as a route-history badge, but it is never a
	# new destination.  Letting it take focus again made a nearby yellow hex look
	# unclickable after a battle return because the stale marker stole the tap.
	if not stage_id.is_empty() and (MapExplorationServiceScript.encounter_cleared(map_state, node_id) or int(AppState.profile.stage_stars.get(stage_id, 0)) > 0):
		_show_map_notice("완료한 작전입니다 · 노란 이동 가능 칸이나 다음 조우를 선택하세요")
		return
	if not _coord_is_in_player_vision(_encounter_coord(node)):
		_show_map_notice("시야 밖의 조우입니다 · 현재 시야 안으로 접근하세요")
		return
	selected_treasure = {}
	selected_relay = {}
	selected_event = {}
	selected_node = node
	live_encounter_replans = 0
	AppState.selected_map_node_id = str(node.node_id)
	map_state.last_selected_node = str(node.node_id)
	var allowed := _traversal_allowlist()
	preview_path = HexPathfinderScript.find_path(grid, Vector2i(int(map_state.current_q), int(map_state.current_r)), _encounter_coord(node), allowed, _unresolved_encounter_stop_hexes())
	# Selection proves visibility; the shared physical grid proves reachability.
	# Fog must never delete an intermediate step from that grid.
	preview_path = _truncate_at_first_unresolved_encounter(preview_path)
	if not preview_path.is_empty() and preview_path[-1] != _encounter_coord(node):
		selected_node = _node_at_coord(preview_path[-1])
		AppState.selected_map_node_id = str(selected_node.get("node_id", ""))
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, preview_path, _player_vision_radius())
	_update_route_mesh()
	# Frame both the squad and the hostile pawn while retaining enough route
	# context to make movement legible.  This keeps a selected N01 from being
	# clipped behind the panel on a wide Chapter 1 map.
	_focus_preview_route()
	_update_panel()
	if _first_map_tutorial_active() and tutorial_step > 0:
		_set_tutorial_step(2)

func _select_treasure(treasure: Dictionary) -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	var treasure_coord := Vector2i(int(treasure.get("q", 0)), int(treasure.get("r", 0)))
	if not _coord_is_in_player_vision(treasure_coord):
		return
	var treasure_id := str(treasure.get("treasure_id", ""))
	# A hint is an environmental observation, not a navigable treasure marker.
	# The player may discover it while traversing the map; only REVEALED opens
	# an exact collection route and the reward panel.
	if MapExplorationServiceScript.treasure_state(map_state, treasure_id) != "REVEALED":
		return
	selected_node = {}
	selected_relay = {}
	selected_event = {}
	selected_treasure = treasure
	# Treasure selection is the explicit opt-in for a short exploratory detour.
	# Do not restrict this route to currently revealed tiles: otherwise a hinted
	# side branch can be visible but unreachable. Unresolved encounters still
	# cut the route below, so this never lets a treasure selection bypass battle.
	preview_path = _find_player_path(Vector2i(int(map_state.current_q), int(map_state.current_r)), treasure_coord)
	preview_path = _truncate_at_first_unresolved_encounter(preview_path)
	_retarget_truncated_path_to_encounter(Vector2i(int(treasure.q), int(treasure.r)))
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, preview_path, _player_vision_radius())
	_update_route_mesh()
	_focus_preview_route()
	_update_panel()

func _select_relay(relay: Dictionary) -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	var relay_coord := Vector2i(int(relay.get("q", 0)), int(relay.get("r", 0)))
	if not _coord_is_in_player_vision(relay_coord):
		return
	selected_node = {}
	selected_treasure = {}
	selected_event = {}
	selected_relay = relay
	preview_path = _find_player_path(Vector2i(int(map_state.current_q), int(map_state.current_r)), relay_coord)
	preview_path = _truncate_at_first_unresolved_encounter(preview_path)
	_retarget_truncated_path_to_encounter(relay_coord)
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, preview_path, _player_vision_radius())
	_update_route_mesh()
	_focus_preview_route()
	_update_panel()

func _select_event(event: Dictionary) -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	var event_coord := Vector2i(int(event.get("q", 0)), int(event.get("r", 0)))
	if not _coord_is_in_player_vision(event_coord):
		return
	selected_node = {}
	selected_treasure = {}
	selected_relay = {}
	selected_event = event
	preview_path = _find_player_path(Vector2i(int(map_state.current_q), int(map_state.current_r)), event_coord)
	preview_path = _truncate_at_first_unresolved_encounter(preview_path)
	_retarget_truncated_path_to_encounter(event_coord)
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, preview_path, _player_vision_radius())
	_update_route_mesh()
	_focus_preview_route()
	_update_panel()

func _focus_preview_route() -> void:
	if preview_path.size() <= 1:
		_focus_current(false)
		return
	var pulse_path := _path_for_current_pulse(preview_path)
	var focus_path := pulse_path if pulse_path.size() > 1 else preview_path
	var midpoint_index := clampi(int(round(float(focus_path.size() - 1) * 0.62)), 1, focus_path.size() - 1)
	_focus_coord(focus_path[midpoint_index], false)

func _truncate_at_first_unresolved_encounter(path: Array[Vector2i]) -> Array[Vector2i]:
	if path.size() <= 1: return path
	var active_hostile_hexes := _unresolved_encounter_stop_hexes()
	for index in range(1, path.size()):
		var coord := path[index]
		if not active_hostile_hexes.has(HexCoordScript.key(coord)):
			continue
		for node in definition.get("nodes", []):
			if str(node.get("stage_id", "")).is_empty(): continue
			if _encounter_coord(node) != coord: continue
			var truncated: Array[Vector2i] = []
			truncated.assign(path.slice(0, index + 1))
			return truncated
	return path

func _node_at_coord(coord: Vector2i) -> Dictionary:
	for node in definition.get("nodes", []):
		var node_coord := _encounter_coord(node)
		if node_coord == coord:
			return node
	return {}

func _retarget_truncated_path_to_encounter(requested_target: Vector2i) -> bool:
	if preview_path.is_empty() or preview_path[-1] == requested_target:
		return false
	var blocking_node := _node_at_coord(preview_path[-1])
	if blocking_node.is_empty():
		return false
	selected_treasure = {}
	selected_relay = {}
	selected_event = {}
	selected_node = blocking_node
	AppState.selected_map_node_id = str(blocking_node.get("node_id", ""))
	map_state.last_selected_node = str(blocking_node.get("node_id", ""))
	return true

func _encounter_coord(node: Dictionary) -> Vector2i:
	var node_id := str(node.get("node_id", ""))
	var authored_coord := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
	if not MapSimulationScript.patrol_definition(definition, node_id).is_empty() and not _node_encounter_cleared(node):
		return MapSimulationScript.render_coord_or_authored(map_state, definition, grid, node_id, authored_coord)
	return authored_coord

func _update_enemy_pawn_from_simulation(node_id: String, animate := false) -> void:
	var root: Node3D = enemy_pawns.get(node_id)
	if root == null: return
	var node := ChapterMapLoaderScript.node_by_id(definition, node_id)
	if node.is_empty(): return
	var coord := _encounter_coord(node)
	var target := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.18)
	var prior := root.position
	var moving_until := int(root.get_meta("patrol_motion_until_msec", 0))
	if animate and prior.distance_to(target) > 0.08:
		var motion := create_tween()
		motion.set_trans(Tween.TRANS_SINE)
		motion.set_ease(Tween.EASE_IN_OUT)
		motion.tween_property(root, "position", target, 0.22)
		_spawn_patrol_step_cue(prior, target)
		root.set_meta("patrol_motion_until_msec", Time.get_ticks_msec() + 240)
	elif Time.get_ticks_msec() >= moving_until:
		root.position = target
	var runtime: Dictionary = map_state.get("patrol_states", {}).get(node_id, {})
	var awareness_state := str(runtime.get("awareness", MapSimulationScript.UNAWARE))
	var awareness_label = root.get_meta("awareness_label", null)
	if awareness_label is Label3D:
		(awareness_label as Label3D).text = "!" if awareness_state == MapSimulationScript.ALERT else ("?" if awareness_state == MapSimulationScript.SUSPICIOUS else "")
		(awareness_label as Label3D).modulate = Color("ff766f") if awareness_state == MapSimulationScript.ALERT else Color("f4d77c")
	var ring = root.get_meta("threat_ring", null)
	if ring is MeshInstance3D:
		var warning := Color("e96871") if awareness_state == MapSimulationScript.ALERT else (Color("e4bd62") if awareness_state == MapSimulationScript.SUSPICIOUS else Color("a95762"))
		(ring as MeshInstance3D).material_override = _cached_material(warning, warning.darkened(0.14))
	# Enemy-turn presentation changes several roots in one synchronous batch.
	# Mark the shared Web label projection once; `_process()` consumes this dirty
	# bit instead of reprojecting every encounter on every transition frame.
	web_entity_projection_dirty = true

func _spawn_patrol_step_cue(from: Vector3, to: Vector3) -> void:
	# A concise, diegetic after-signal makes WAIT visibly causal without drawing
	# a permanent debug patrol line across the release map.
	# Compatibility Web owns an UPDATE_ALWAYS SubViewport. Creating a temporary
	# TorusMesh/Tween here and queue-freeing its render object from the callback
	# occasionally leaves the single-threaded renderer with a stale property
	# target (ClassDB p_object=null). The hostile pawn already moves and advances
	# its authored atlas, so this disposable cue adds no gameplay information on
	# Web and must not trade stability for a third transient animation layer.
	if OS.has_feature("web"):
		return
	var cue := MeshInstance3D.new()
	var cue_mesh := TorusMesh.new()
	cue_mesh.inner_radius = 0.18
	cue_mesh.outer_radius = 0.23
	cue_mesh.rings = 6
	cue_mesh.ring_segments = 14
	cue.mesh = cue_mesh
	cue.position = from + Vector3(0.0, 0.12, 0.0)
	cue.material_override = _cached_material(Color("e5ba65"), Color("e0953f"))
	world_root.add_child(cue)
	var cue_tween := create_tween()
	cue_tween.set_parallel(true)
	cue_tween.tween_property(cue, "scale", Vector3(2.1, 1.0, 2.1), 0.34)
	cue_tween.tween_property(cue, "position", to + Vector3(0.0, 0.10, 0.0), 0.34)
	cue_tween.chain().tween_callback(cue.queue_free)

func _show_map_notice(text_value: String) -> void:
	map_notice = text_value
	# Keep exploration feedback visible long enough to survive a mobile tap and
	# the short pawn-motion tween; otherwise a completed Wait can look inert.
	map_notice_until_msec = Time.get_ticks_msec() + 3200
	if status_label != null:
		status_label.text = map_notice

func _wait_pulse() -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	_complete_player_turn("대기")

func _resume_post_reward_turn() -> void:
	if not is_inside_tree():
		return
	var persisted_reward_edge := bool(map_state.get(POST_REWARD_TURN_PENDING_KEY, false))
	var pending_encounter: Dictionary = map_state.get("pending_encounter", {})
	var exhausted_legacy_edge: bool = MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0 and pending_encounter.is_empty()
	if not persisted_reward_edge and not exhausted_legacy_edge:
		return
	# Treasure arrival deliberately locks the map before AppShell presents the
	# in-place reward overlay. Closing that overlay is the owner hand-off that
	# releases this exact transition; treating its own lock as an unrelated busy
	# state deferred forever and left the visible map unable to accept input until
	# a full page reload. Keep real movement/pause guards, then release the owned
	# transition immediately before running the owed enemy phase.
	if moving or map_simulation_paused:
		# Initial world construction and a browser focus hand-off both pause map
		# authority briefly. Retry on the next process frame instead of dropping the
		# persisted turn edge and leaving movement at zero forever.
		await get_tree().process_frame
		if is_inside_tree():
			call_deferred("_resume_post_reward_turn")
		return
	# The reward overlay is presented in-place, so this screen can still own the
	# treasure route that has just been claimed.  Keeping that now-invalid
	# selection leaves the details drawer focused on a missing treasure and can
	# keep the next-encounter affordance visually stale until a full reload.
	# Release every route-selection field before the owed enemy phase repaints the
	# map, exactly as a freshly-created map screen would.
	selected_node.clear()
	selected_treasure.clear()
	selected_relay.clear()
	selected_event.clear()
	preview_path.clear()
	preview_risk = "SAFE"
	turn_transitioning = false
	map_state[POST_REWARD_TURN_PENDING_KEY] = false
	await _complete_player_turn("보물 획득")

func _complete_player_turn(action_label: String) -> void:
	if map_simulation_paused:
		pending_turn_completion = true
		pending_turn_label = action_label
		turn_transitioning = true
		moving = false
		return
	if turn_transitioning:
		return
	turn_transitioning = true
	moving = false
	web_entity_projection_dirty = true
	movement_skip_requested = false
	active_movement_path.clear()
	_show_map_notice("%s · 적 턴 진행 중" % action_label)
	# Transition entry only needs to remove the yellow authority mesh and lock
	# controls. A full repaint here was immediately discarded by the final turn
	# repaint and doubled minimap, style and movement-mesh work.
	_clear_movement_range_overlay()
	if move_button != null: move_button.disabled = true
	if wait_button != null: wait_button.disabled = true
	if next_encounter_button != null: next_encounter_button.disabled = true
	for node_button_value in node_buttons.values():
		if node_button_value is Button:
			(node_button_value as Button).disabled = true
	var party_coord := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	var update := MapExplorationServiceScript.complete_player_move_turn(map_state, definition, grid, party_coord)
	# The simulation advances every ordinary patrol once per player action, but a
	# Web map only animates the roots already inside the player's live sight. This
	# makes the exchanged turn readable without rebuilding or tweening a distant
	# macro district, which was the source of the previous map/BGM hitches.
	var presented_moves: Array = []
	for move_value in update.get("moves", []):
		var move: Dictionary = move_value
		var move_node_id := str(move.get("encounter_id", ""))
		var destination_value: Array = move.get("to", [])
		if destination_value.size() != 2 or not enemy_pawns.has(move_node_id):
			continue
		var destination := Vector2i(int(destination_value[0]), int(destination_value[1]))
		if _coord_is_in_player_vision(destination):
			presented_moves.append(move)
	if not presented_moves.is_empty():
		_show_map_notice("적 턴 · 시야 내 순찰 %d체 이동" % presented_moves.size())
	for move_value in presented_moves:
		var move: Dictionary = move_value
		var node_id := str(move.get("encounter_id", ""))
		var destination_value: Array = move.get("to", [])
		if destination_value.size() == 2:
			_update_enemy_pawn_from_simulation(node_id, true)
	if not presented_moves.is_empty():
		await get_tree().create_timer(0.24).timeout
		if not is_inside_tree():
			return
	for node_id_value in update.get("awareness", {}).keys():
		var awareness_node_id := str(node_id_value)
		if not enemy_pawns.has(awareness_node_id):
			continue
		var node := ChapterMapLoaderScript.node_by_id(definition, awareness_node_id)
		if not node.is_empty() and _coord_is_in_player_vision(_encounter_coord(node)):
			_update_enemy_pawn_from_simulation(awareness_node_id)
	if not is_inside_tree():
		return
	# The camera never left the squad during the simultaneous enemy phase.
	_focus_current(false)
	SaveService.request_save_game()
	pending_turn_completion = false
	pending_turn_label = ""
	if not update.get("contacts", []).is_empty():
		turn_transitioning = false
		_start_patrol_contact(str(update.contacts[0]), party_coord, true)
		return
	turn_transitioning = false
	_rebuild_selected_preview()
	_refresh_state_visuals()
	_show_map_notice("적 턴 완료 · 다음 아군 턴 · 이동 %d/%d · 순찰 %d체 이동" % [int(map_state.get("movement_points", 0)), int(map_state.get("movement_points_max", 0)), int(update.get("changed", []).size())])
	if OS.has_feature("web"):
		print("MAP_TURN_READY movement=%d/%d moving=%s transitioning=%s paused=%s" % [int(map_state.get("movement_points", 0)), int(map_state.get("movement_points_max", 0)), str(moving), str(turn_transitioning), str(map_simulation_paused)])

func _start_patrol_contact(node_id: String, return_coord: Vector2i, movement_refilled := false) -> void:
	if not map_state.get("pending_encounter", {}).is_empty(): return
	var node := ChapterMapLoaderScript.node_by_id(definition, node_id)
	if node.is_empty() or not AppState.is_stage_unlocked(str(node.get("stage_id", ""))): return
	if MapExplorationServiceScript.encounter_cleared(map_state, node_id): return
	_begin_movement_camera_settle(pawn.global_position)
	_set_pawn_motion_state("ARRIVE")
	movement_generation += 1
	moving = false
	movement_camera_follow_active = false
	turn_transitioning = false
	movement_skip_requested = false
	live_encounter_replans = 0
	active_movement_path.clear()
	if not movement_refilled:
		MapExplorationServiceScript.refill_movement(map_state, definition, grid)
	if map_state.get("patrol_states", {}).has(node_id):
		map_state.patrol_states[node_id].patrol_state = MapSimulationScript.PATROL_ENGAGED
	if AppState.prepare_map_encounter(str(node.get("stage_id", "")), node_id, return_coord, map_id):
		_complete_first_map_tutorial()
		var encounter_save_result := SaveService.save_game()
		if not encounter_save_result.ok:
			# Never enter combat from a state the browser failed to persist. Restore
			# the exact pre-contact hex and patrol state so the player can retry.
			AppState.abandon_pending_map_encounter(map_id)
			pawn.position = _pawn_world_position()
			_set_pawn_motion_state("IDLE")
			turn_transitioning = false
			_focus_current(false)
			_refresh_state_visuals()
			_show_map_notice("전투 진입 저장 실패 · 다시 시도하세요")
			push_error("Map encounter save failed before battle entry: %s" % encounter_save_result.error)
			return
		turn_transitioning = true
		call_deferred("_emit_battle_request_after_map_callback", str(node.get("stage_id", "")))

func _emit_battle_request_after_map_callback(stage_id: String) -> void:
	if not is_inside_tree():
		return
	battle_requested.emit(stage_id)

func _update_panel() -> void:
	if detail_title == null: return
	_apply_responsive_layout()
	_update_route_minimap()
	if selected_node.is_empty() and selected_treasure.is_empty() and selected_relay.is_empty() and selected_event.is_empty():
		detail_title.text = "조우 타일을 선택하세요"
		detail_body.text = "[color=#91aac8]한 번 클릭하면 경로 확인 · 더블클릭 또는 터치하면 노란 범위 안에서 즉시 이동합니다.[/color]\n\n이동 완료: 적 턴 자동 진행 → 다음 아군 턴\n클리어 타일: 빠른 이동\n3성 타일: 원격 소탕\n맵 이동: 작전력 소비 없음"
		move_button.visible = false
		fast_travel_button.visible = false
		battle_button.visible = false
		for button in sweep_buttons: button.visible = false
		_set_action_states(true, true, true)
		return
	if not selected_relay.is_empty():
		var relay_id := str(selected_relay.get("relay_id", ""))
		var relay_status := MapExplorationServiceScript.relay_state(map_state, relay_id)
		var relay_coord := Vector2i(int(selected_relay.get("q", 0)), int(selected_relay.get("r", 0)))
		var at_relay := Vector2i(int(map_state.current_q), int(map_state.current_r)) == relay_coord
		detail_title.text = str(selected_relay.get("name", "지역 릴레이"))
		detail_body.text = "[color=#78e6d0][b]%s[/b][/color]\n%s\n\n예상 이동  [color=#85e8ff]%d 구간[/color]  ·  %s\n\n복구하면 주변 지도 정보와 탐색 단서를 복원합니다. 성장 재료는 소비하지 않습니다." % [relay_status_display(relay_status), "연결된 활성 릴레이 사이를 빠르게 이동할 수 있습니다." if relay_status == "ACTIVE" else "현장 접근 후 신호를 복구할 수 있습니다.", maxi(0, preview_path.size() - 1), _risk_text()]
		move_button.visible = true
		move_button.text = "릴레이 복구" if at_relay and relay_status != "ACTIVE" else "릴레이로 이동"
		if not at_relay: move_button.text = _movement_action_text(move_button.text)
		move_button.disabled = (at_relay and relay_status == "ACTIVE") or (not at_relay and (preview_path.size() <= 1 or MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0))
		fast_travel_button.visible = relay_status == "ACTIVE" and not at_relay and not _active_relay_at_party().is_empty()
		fast_travel_button.text = "활성 릴레이로 빠른 이동"
		fast_travel_button.disabled = not MapExplorationServiceScript.can_fast_travel_between(map_state, definition, str(_active_relay_at_party().get("relay_id", "")), relay_id)
		battle_button.visible = false
		for button in sweep_buttons: button.visible = false
		return
	if not selected_event.is_empty():
		var event_id := str(selected_event.get("event_id", ""))
		var event_coord := Vector2i(int(selected_event.get("q", 0)), int(selected_event.get("r", 0)))
		var at_event := Vector2i(int(map_state.current_q), int(map_state.current_r)) == event_coord
		var choices: Array = selected_event.get("choices", [])
		var resolved := MapExplorationServiceScript.event_state(map_state, event_id) == "RESOLVED"
		detail_title.text = LocalizationService.tr_key(str(selected_event.get("title_key", "MAP_EVENT_DEFAULT_TITLE")))
		detail_body.text = "%s\n\n예상 이동  [color=#85e8ff]%d 구간[/color]  ·  %s" % [LocalizationService.tr_key(str(selected_event.get("body_key", "MAP_EVENT_DEFAULT_BODY"))), maxi(0, preview_path.size() - 1), _risk_text()]
		move_button.visible = not resolved
		move_button.text = LocalizationService.tr_key(str(choices[0].get("label_key", "MAP_EVENT_DEFAULT_CHOICE_PRIMARY"))) if at_event and not choices.is_empty() else LocalizationService.tr_key("MAP_EVENT_MOVE_TO")
		if not at_event: move_button.text = _movement_action_text(move_button.text)
		move_button.disabled = resolved or (not at_event and (preview_path.size() <= 1 or MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0))
		fast_travel_button.visible = at_event and not resolved and choices.size() > 1
		fast_travel_button.text = LocalizationService.tr_key(str(choices[1].get("label_key", "MAP_EVENT_DEFAULT_CHOICE_SECONDARY"))) if choices.size() > 1 else ""
		fast_travel_button.disabled = resolved
		battle_button.visible = false
		for button in sweep_buttons: button.visible = false
		return
	if not selected_treasure.is_empty():
		var landmark_key := str(selected_treasure.get("landmark_key", ""))
		var landmark_name := LocalizationService.tr_key(landmark_key) if not landmark_key.is_empty() else LocalizationService.tr_key("MAP_TREASURE_DETAIL_TITLE")
		detail_title.text = LocalizationService.tr_key("MAP_TREASURE_DETAIL_TITLE")
		detail_body.text = LocalizationService.tr_key("MAP_TREASURE_DETAIL_BODY") % [landmark_name, maxi(0, preview_path.size() - 1), _risk_text()]
		move_button.visible = true
		move_button.text = _movement_action_text(LocalizationService.tr_key("MAP_TREASURE_MOVE"))
		move_button.disabled = preview_path.size() <= 1 or MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0
		fast_travel_button.visible = false
		battle_button.visible = false
		for button in sweep_buttons: button.visible = false
		return
	var stage_id := str(selected_node.get("stage_id", ""))
	if stage_id == "":
		detail_title.text = "기점 • 릴레이 캠프"
		detail_body.text = "[color=#78e6d0]출발 거점[/color]\n부대의 탐색 기준점입니다."
		move_button.visible = false
		fast_travel_button.visible = false
		battle_button.visible = false
		for button in sweep_buttons: button.visible = false
		_set_action_states(preview_path.size() <= 1, true, true)
		return
	var stage := DataRegistry.stage(stage_id)
	var reward := DataRegistry.by_id("rewards", stage.reward_table_id)
	var stars := int(AppState.profile.stage_stars.get(stage_id, 0))
	var unlocked := AppState.is_stage_unlocked(stage_id)
	# Uncleared patrol encounters are selected at their live simulation hex, not
	# permanently at the authored marker. Keep the action state aligned with the
	# same coordinate that pathfinding and physical contact use.
	var at_node := Vector2i(int(map_state.current_q), int(map_state.current_r)) == _encounter_coord(selected_node)
	var attempts := "무제한"
	if stage.mode == "HARD":
		attempts = "무제한 (DEV)" if SettingsService.is_developer_mode() else "%d/%d 사용" % [int(AppState.profile.hard_attempts.counts.get(stage_id, 0)), int(stage.daily_attempts)]
	var lock_reason := "" if unlocked else ("최종 일반 작전 클리어 필요" if stage.mode == "HARD" else "직전 일반 작전 클리어 필요")
	var operation_type := "위험 작전" if stage.mode == "HARD" else "일반 작전"
	var special_event := _event_encounter_for_node(str(selected_node.get("node_id", "")))
	var title_override := LocalizationService.tr_key(str(special_event.get("title_key", ""))) if not special_event.is_empty() and stars <= 0 else ""
	detail_title.text = title_override if not title_override.is_empty() else "%s%s" % [LocalizationService.tr_key(stage.name_key), " · 대형 조우" if stage.boss else ""]
	var event_brief := "\n\n[color=#7ee7d5][b]! 특별 조우[/b][/color]\n%s" % LocalizationService.tr_key(str(special_event.get("body_key", ""))) if not special_event.is_empty() and stars <= 0 else ""
	detail_body.text = "[color=#7cf1dc][b]%s[/b][/color]\n[color=#f1d77a]권장 Lv.%d[/color]     작전력 [b]%d[/b]     제한 %d초\n완료 등급  %s\n입장 횟수  %s\n예상 이동  [color=#85e8ff]%d 구간[/color]  ·  %s\n%s%s\n\n[color=#9cc5dc][b]3성 조건[/b][/color]\n클리어 · 전투불능 0 · %d초 내\n\n[color=#9cc5dc][b]획득 가능 보상[/b][/color]\n%s%s" % [operation_type, int(stage.recommended_level), int(stage.stamina_cost), int(stage.time_limit), "★".repeat(stars) + "☆".repeat(3-stars), attempts, maxi(0, preview_path.size()-1), _risk_text(), _movement_summary(), event_brief, int(stage.target_time), _reward_text(reward), "\n\n[color=#ffbd7a][b]잠금[/b]  " + lock_reason + "[/color]" if not unlocked else ""]
	# Reaching an encounter and paying its battle-entry cost are separate actions.
	# Never strand the party on the map just because the later battle transaction
	# is currently unavailable; explain the entry condition without disabling
	# traversal toward the pawn.
	if unlocked and not at_node and not AppState.can_enter_stage(stage_id):
		var entry_reason := ""
		if int(AppState.profile.account.get("stamina", 0)) < int(stage.stamina_cost):
			entry_reason = "작전력이 부족합니다 · 전투 시작 시에만 작전력이 차감됩니다"
		elif stage.mode == "HARD" and int(AppState.profile.hard_attempts.counts.get(stage_id, 0)) >= int(stage.daily_attempts):
			entry_reason = "오늘의 HARD 입장 횟수를 모두 사용했습니다"
		else:
			entry_reason = "현재 입장 조건을 다시 확인 중입니다 · 이동과 전투는 차감되지 않았습니다"
		detail_body.text += "\n\n[color=#ffbd7a][b]전투 진입 조건[/b]  %s[/color]" % entry_reason
	# Keep the primary map actions above the portrait bottom edge. Remote farming
	# tools appear only after their real unlock condition, rather than occupying
	# the first-visit encounter sheet as disabled controls.
	move_button.visible = not at_node
	move_button.text = _movement_action_text("! 구조 신호 방향" if not special_event.is_empty() and stars <= 0 else "조우 방향")
	fast_travel_button.visible = stars > 0
	var uncleared_encounter := not MapExplorationServiceScript.encounter_cleared(map_state, str(selected_node.get("node_id", ""))) and stars <= 0
	# An uncleared hostile starts combat by physical contact only.  Cleared
	# stages retain their normal repeat-battle action without an enemy pawn.
	battle_button.visible = not uncleared_encounter
	battle_button.text = "기존 실시간 전투 재도전"
	for button in sweep_buttons: button.visible = stars >= 3
	move_button.disabled = not unlocked or preview_path.size() <= 1 or MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0
	fast_travel_button.disabled = stars <= 0 or at_node or not bool(selected_node.get("fast_travel_allowed", false))
	battle_button.disabled = not at_node or not AppState.can_enter_stage(stage_id)
	for index in range(sweep_buttons.size()):
		var count: int = int([1, 5, 10][index])
		sweep_buttons[index].disabled = stars < 3 or not AppState.can_enter_stage_count(stage_id, count)

func _set_action_states(move_disabled: bool, fast_disabled: bool, battle_disabled: bool) -> void:
	move_button.disabled = move_disabled
	fast_travel_button.disabled = fast_disabled
	battle_button.disabled = battle_disabled
	for button in sweep_buttons: button.disabled = true

func _reward_text(reward: Dictionary) -> String:
	var lines: Array[String] = []
	for entry in reward.get("guaranteed", []): lines.append("• %s ×%d" % [_display_item_name(str(entry.get("item_id", "?"))), int(entry.get("quantity", entry.get("min", 1)))])
	for entry in reward.get("bonus", []): lines.append("• %s %.0f%%" % [_display_item_name(str(entry.get("item_id", "?"))), float(entry.get("chance", 0.0))*100.0])
	return "\n".join(lines)

func _display_item_name(item_id: String) -> String:
	var item := DataRegistry.by_id("items", item_id)
	return LocalizationService.tr_key(str(item.get("name_key", item_id.replace("_", " ")))).replace(" (DEV)", "")

func _risk_text() -> String:
	return "[color=#71e6c7]안전 경로[/color]" if preview_risk == "SAFE" else ("[color=#f0c46b]경계 구간 가능[/color]" if preview_risk == "WATCHED" else "[color=#f07f79]적 접촉 예상[/color]")

func _movement_action_text(destination_label: String) -> String:
	var full_steps := maxi(0, preview_path.size() - 1)
	if full_steps <= 0:
		return destination_label
	var pulse_steps := mini(full_steps, MapExplorationServiceScript.movement_remaining(map_state, definition))
	if pulse_steps < full_steps:
		return "%s · %d칸 후 중간 정지" % [destination_label, pulse_steps]
	return "%s · %d칸 이동" % [destination_label, pulse_steps]

func _movement_summary() -> String:
	var rules: Dictionary = definition.get("exploration_rules", {})
	var account_level := int(AppState.profile.get("account", {}).get("level", 1))
	var level_bonus := 0
	for milestone_value in rules.get("account_level_milestones", []):
		var milestone: Dictionary = milestone_value
		if account_level >= int(milestone.get("level", 9999)):
			level_bonus += maxi(0, int(milestone.get("bonus", 0)))
	var module_bonus := 0
	var inventory: Dictionary = AppState.profile.get("inventory", {})
	for module_value in rules.get("mobility_items", []):
		var module: Dictionary = module_value
		if int(inventory.get(str(module.get("item_id", "")), 0)) > 0:
			module_bonus += maxi(0, int(module.get("bonus", 0)))
	var base_points := maxi(1, int(rules.get("base_move_points", 3)))
	var max_points := maxi(1, int(rules.get("max_move_points", 8)))
	return "이번 턴 [color=#ffd66d]%d/%d칸[/color] · 노란 영역 안에서만 이동\n[color=#91aac8]기본 %d · 계정 Lv.%d +%d · 노선 모듈 +%d · 최종 상한 %d[/color]" % [int(map_state.get("movement_points", 0)), int(map_state.get("movement_points_max", 0)), base_points, account_level, level_bonus, module_bonus, max_points]

func _active_relay_at_party() -> Dictionary:
	var current := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	for relay in definition.get("relays", []):
		if MapExplorationServiceScript.relay_state(map_state, str(relay.get("relay_id", ""))) == "ACTIVE" and current == Vector2i(int(relay.get("q", 0)), int(relay.get("r", 0))):
			return relay
	return {}

static func direct_move_gesture_policy(event: InputEvent, repeated_pointer_click := false, touch_tap_valid := true) -> bool:
	## Desktop keeps single-click as preview and promotes the second click to a
	## confirmed route. Godot Web normally supplies `double_click`, but browsers
	## and automation bridges can deliver the same physical gesture as two plain
	## presses; the caller-provided repeat flag preserves the same user contract.
	## Touch has no hover/double-click convention, so a short released tap confirms
	## while drag/cancel gestures remain camera controls.
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and event.pressed and (event.double_click or repeated_pointer_click)
	if event is InputEventScreenTouch:
		return event.index == 0 and not event.pressed and not event.canceled and touch_tap_valid
	return false

func _can_begin_selected_route() -> bool:
	if moving or turn_transitioning or map_simulation_paused or preview_path.size() <= 1:
		return false
	var pulse_path := _path_for_current_pulse(preview_path)
	if pulse_path.size() <= 1 or not movement_range_reachable.has(HexCoordScript.key(pulse_path[-1])):
		return false
	# Direct map input must use gameplay authority, never whether a responsive
	# details drawer happens to expose its Move button. The old UI dependency made
	# all double-click/touch movement inert in compact landscape layouts.
	if not selected_node.is_empty():
		var stage_id := str(selected_node.get("stage_id", ""))
		if not stage_id.is_empty():
			return AppState.is_stage_unlocked(stage_id)
	if not selected_treasure.is_empty():
		return MapExplorationServiceScript.treasure_state(map_state, str(selected_treasure.get("treasure_id", ""))) == "REVEALED"
	return true

func _activate_selected_route_from_pointer() -> void:
	if _can_begin_selected_route():
		_confirm_move()
		return
	if preview_path.size() > 1 or (selected_node.is_empty() and selected_treasure.is_empty() and selected_relay.is_empty() and selected_event.is_empty()):
		return
	var current := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	var target := _selected_target_coord()
	_show_map_notice("현재 위치입니다 · 다른 노란 칸을 선택하세요" if current == target else "통행 가능한 경로가 없습니다 · 노란 이동 가능 칸을 선택하세요")

func _confirm_move() -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	if not selected_relay.is_empty() and preview_path.size() <= 1:
		_activate_selected_relay()
		return
	if not selected_event.is_empty() and preview_path.size() <= 1:
		_resolve_selected_event(0)
		return
	if preview_path.size() <= 1: return
	var pulse_path := _path_for_current_pulse(preview_path)
	if pulse_path.size() <= 1:
		_show_map_notice("이동 범위를 모두 사용했습니다 · 대기로 다음 탐색 펄스를 시작하세요")
		_update_panel()
		return
	if _first_map_tutorial_active() and tutorial_step > 0:
		_set_tutorial_step(3)
	_move_along(pulse_path)

func _set_direct_hex_route(coord: Vector2i) -> bool:
	var key := HexCoordScript.key(coord)
	var current := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	if coord == current or not movement_range_reachable.has(key):
		return false
	if _unresolved_encounter_stop_hexes().has(key):
		for node_value in definition.get("nodes", []):
			var node: Dictionary = node_value
			if _encounter_coord(node) == coord:
				_select_node(node)
				return preview_path.size() > 1
	var path := _find_player_path(current, coord)
	if path.size() <= 1:
		return false
	selected_node = {}
	selected_treasure = {}
	selected_relay = {}
	selected_event = {}
	preview_path = path
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, preview_path, _player_vision_radius())
	_update_route_mesh()
	_focus_preview_route()
	_update_panel()
	return true

func _path_for_current_pulse(path: Array[Vector2i]) -> Array[Vector2i]:
	var steps := maxi(0, MapExplorationServiceScript.movement_remaining(map_state, definition))
	if path.size() <= 1 or steps <= 0:
		var stationary_path: Array[Vector2i] = []
		if not path.is_empty():
			stationary_path.append(path[0])
		return stationary_path
	var bounded_path: Array[Vector2i] = []
	bounded_path.assign(path.slice(0, mini(path.size(), steps + 1)))
	return bounded_path

func _selected_target_coord() -> Vector2i:
	if not selected_node.is_empty(): return _encounter_coord(selected_node)
	if not selected_treasure.is_empty(): return Vector2i(int(selected_treasure.get("q", 0)), int(selected_treasure.get("r", 0)))
	if not selected_relay.is_empty(): return Vector2i(int(selected_relay.get("q", 0)), int(selected_relay.get("r", 0)))
	if not selected_event.is_empty(): return Vector2i(int(selected_event.get("q", 0)), int(selected_event.get("r", 0)))
	return Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))

func _path_reveal_allowlist() -> Dictionary:
	# Presentation-only visibility list. Never pass this to movement/pathfinding.
	# "스테이지 전체 해금" is a Development-only navigation aid.  It must
	# not mutate canonical fog/reveal data or a player save, but debug encounters
	# still need a real traversable route to exercise the existing battle loop.
	# Release builds continue to use only the persisted reveal authority.
	var center := _player_map_coord()
	var revealed_tiles: Array = map_state.get("revealed_tiles", [])
	var next_signature := "%d,%d:%d:%s" % [center.x, center.y, hash(revealed_tiles), str(AppState.debug_unlock_all_enabled())]
	if next_signature == path_reveal_cache_signature:
		return path_reveal_cache
	var allowed: Dictionary = {}
	if AppState.debug_unlock_all_enabled():
		for tile in definition.get("tiles", []):
			var debug_coord := Vector2i(int(tile.get("q", 0)), int(tile.get("r", 0)))
			if _coord_is_in_player_vision(debug_coord):
				allowed[HexCoordScript.key(debug_coord)] = true
		path_reveal_cache_signature = next_signature
		path_reveal_cache = allowed
		return path_reveal_cache
	for key in revealed_tiles:
		var coord := HexCoordScript.from_key(str(key))
		if _coord_is_in_player_vision(coord):
			allowed[str(key)] = true
	path_reveal_cache_signature = next_signature
	path_reveal_cache = allowed
	return path_reveal_cache

func _rebuild_selected_preview() -> void:
	var current := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	var target := _selected_target_coord()
	if current == target:
		preview_path = [current]
	else:
		preview_path = _find_player_path(current, target)
		preview_path = _truncate_at_first_unresolved_encounter(preview_path)
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, preview_path, _player_vision_radius())
	_update_route_mesh()

func _activate_selected_relay() -> void:
	if selected_relay.is_empty(): return
	var result := MapExplorationServiceScript.activate_relay(map_state, definition, str(selected_relay.get("relay_id", "")))
	if result.ok:
		SaveService.save_game()
		_refresh_state_visuals()

func _resolve_selected_event(choice_index: int) -> void:
	if selected_event.is_empty(): return
	var choices: Array = selected_event.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size(): return
	var result := MapExplorationServiceScript.resolve_event(map_state, definition, str(selected_event.get("event_id", "")), str(choices[choice_index].get("choice_id", "")))
	if result.ok:
		SaveService.save_game()
		_refresh_state_visuals()
		if not result.value.get("rewards", {}).is_empty(): treasure_reward_requested.emit(result.value)

func _move_along(path: Array[Vector2i]) -> void:
	if path.size() <= 1 or moving or turn_transitioning or map_simulation_paused:
		return
	moving = true
	movement_camera_follow_active = true
	movement_camera_settle_active = false
	movement_camera_goal = _pawn_camera_goal(pawn.global_position)
	movement_skip_requested = false
	_set_pawn_motion_state("WALK")
	movement_generation += 1
	var generation := movement_generation
	active_movement_path = path.duplicate()
	var traveled_path: Array[Vector2i] = [Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))]
	if preview_camera_tween != null and preview_camera_tween.is_valid():
		preview_camera_tween.kill()
	# Preserve the yellow authority range while the pawn walks so the player can
	# still read the selected route and its remaining local context. Input is
	# locked by `moving`; the overlay is rebuilt once on arrival/turn completion.
	if move_button != null: move_button.disabled = true
	if wait_button != null: wait_button.disabled = true
	if next_encounter_button != null: next_encounter_button.disabled = true
	if OS.has_feature("web"):
		# Projected encounter labels are world annotations, not movement authority.
		# Hide them once during transit; otherwise every camera sub-step performs a
		# full label/visibility projection pass and synchronous browser-size reads.
		for button_value in node_buttons.values():
			if button_value is Button and is_instance_valid(button_value):
				(button_value as Button).visible = false
	for index in range(1, path.size()):
		if generation != movement_generation:
			return
		if not MapExplorationServiceScript.spend_movement(map_state, definition, 1, grid):
			break
		var coord := path[index]
		var prior_coord := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
		map_state.last_pre_contact_hex = [prior_coord.x, prior_coord.y]
		var target := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.14)
		_set_pawn_facing(pawn.position, target)
		_spawn_pawn_step_trail(pawn.position)
		# Start the camera glide with the pawn, not after it has already crossed the
		# cell. Updating every cell retains velocity continuity and avoids the old
		# one-cell-late camera snap.
		_follow_moving_pawn(target)
		if movement_skip_requested:
			pawn.position = target
		else:
			# Per-cell sine easing forced velocity to zero at every hex boundary. The
			# atlas owns foot cadence, so constant spatial velocity reads as one walk
			# instead of three separate starts and stops.
			var tween := create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
			# Preserve one world-space walking speed on slopes. Elevation adds a small,
			# proportional amount of time instead of making an uphill cell visibly snap.
			tween.tween_property(pawn, "position", target, _pawn_step_duration(pawn.position, target))
			await tween.finished
		if generation != movement_generation: return
		pawn_last_position = target
		traveled_path.append(coord)
		# Logical party position advances on the same discrete hex boundary that
		# the pawn animation reaches.  The map simulation may then interrupt this
		# route, but never reads tween progress or rendered Node3D coordinates.
		ChapterMapProgressScript.mark_visited(map_state, [coord])
		web_entity_projection_dirty = true
		# Proximity state is authoritative immediately; its presentation is painted
		# once at arrival instead of rebuilding every UI/mesh layer between footsteps.
		MapExplorationServiceScript.update_proximity(map_state, definition, coord, grid)
		var contacts := MapSimulationScript.contacts_at_party_coord(map_state, definition, grid, coord, _player_vision_radius())
		if not contacts.is_empty():
			_start_patrol_contact(str(contacts[0]), prior_coord)
			return
	var arrival := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	# Rebuild fog, infill and streamed terrain once at the final hex. Rebuilding
	# the whole visible district on every intermediate step caused the repeated
	# freezes reported during ordinary three-cell movement.
	await _stream_visible_tiles(arrival, false, true)
	map_state.last_selected_node = str(selected_node.get("node_id", ""))
	moving = false
	movement_camera_follow_active = false
	_begin_movement_camera_settle(pawn.global_position)
	_set_pawn_motion_state("ARRIVE")
	await get_tree().create_timer(PAWN_ARRIVE_HOLD_DURATION).timeout
	_set_pawn_motion_state("IDLE")
	active_movement_path.clear()
	movement_skip_requested = false
	var arrival_outcome := _resolve_arrival(traveled_path)
	if arrival_outcome == "STAY" and is_inside_tree():
		if OS.has_feature("web") and not web_stage_entry_preload_complete:
			# Schedule local marker hydration only when this screen actually remains
			# the map owner. A treasure/battle arrival destroys the Web screen; the
			# old ordering left a deferred builder targeting that retired SubViewport.
			call_deferred("_build_map_content_visuals")
		await _complete_player_turn("이동 완료")
	# Do not snap to the destination after walking: the stepped follow camera has
	# already kept the squad in view and retains surrounding terrain context.

func _follow_moving_pawn(position: Vector3) -> void:
	# The camera follows one persistent goal in `_process()`. Killing and creating
	# a SINE tween for every hex forced its velocity back to zero at every boundary
	# and also pulled the look target below raised terrain.
	movement_camera_goal = _pawn_camera_goal(position)
	movement_camera_follow_active = true

func _pawn_step_duration(from: Vector3, to: Vector3) -> float:
	# Adjacent flat hexes are sqrt(3) * TILE_SIZE apart. Scaling the authored
	# cadence by the actual 3D segment length keeps speed constant across cliffs.
	var nominal_step_distance := maxf(0.001, sqrt(3.0) * TILE_SIZE)
	var duration := PAWN_STEP_DURATION * from.distance_to(to) / nominal_step_distance
	return clampf(duration, PAWN_STEP_DURATION * 0.82, PAWN_STEP_DURATION * 1.55)

func _pawn_camera_goal(position: Vector3) -> Vector3:
	# Pawn positions include the 0.14 contact lift. Track the underlying terrain
	# height so the camera rises and falls with shelves without looking above feet.
	return Vector3(position.x, position.y - 0.14, position.z)

func _begin_movement_camera_settle(position: Vector3) -> void:
	movement_camera_settle_from = camera_target
	movement_camera_settle_goal = _clamp_camera_target_to_terrain(_pawn_camera_goal(position))
	movement_camera_settle_elapsed = 0.0
	movement_camera_settle_active = not movement_camera_settle_from.is_equal_approx(movement_camera_settle_goal)

func _spawn_pawn_step_trail(position: Vector3) -> void:
	# Creating and freeing a MeshInstance plus two Tweens for every crossed cell
	# adds allocator/GC spikes in Web builds. The authored pawn atlas already
	# communicates motion; keep this cosmetic trail on native targets only.
	if OS.has_feature("web"):
		return
	var marker := MeshInstance3D.new()
	if pawn_step_trail_mesh == null:
		pawn_step_trail_mesh = CylinderMesh.new()
		pawn_step_trail_mesh.top_radius = 0.13
		pawn_step_trail_mesh.bottom_radius = 0.20
		pawn_step_trail_mesh.height = 0.025
		pawn_step_trail_mesh.radial_segments = 6
	marker.mesh = pawn_step_trail_mesh
	marker.material_override = _cached_material(Color("4cd9d0"), Color("64fff0"))
	marker.position = position + Vector3(0.0, 0.035, 0.0)
	world_root.add_child(marker)
	pawn_step_trails.append(marker)
	if pawn_step_trails.size() > 7:
		var oldest = pawn_step_trails.pop_front()
		if is_instance_valid(oldest): oldest.queue_free()
	var fade := create_tween()
	fade.tween_property(marker, "scale", Vector3(1.75, 1.0, 1.75), 0.30)
	fade.parallel().tween_property(marker, "position:y", marker.position.y + 0.10, 0.30)
	fade.tween_callback(marker.queue_free)

func skip_movement() -> void:
	if not moving or active_movement_path.is_empty(): return
	# The authoritative coroutine still spends and resolves each crossed tile once;
	# this flag only removes the remaining visual waits.
	movement_skip_requested = true

func _resolve_arrival(path: Array[Vector2i]) -> String:
	if path.is_empty(): return "STAY"
	var arrival := path[-1]
	# Every crossed coordinate, including this final one, was resolved immediately
	# in `_move_along()`. Repeating proximity here performed the same treasure/event
	# scan twice on every successful route without changing authoritative state.
	if not selected_treasure.is_empty() and arrival == Vector2i(int(selected_treasure.q), int(selected_treasure.r)):
		var report := MapExplorationServiceScript.claim_treasure(map_state, definition, str(selected_treasure.treasure_id))
		if report.ok:
			# The reward presentation temporarily destroys this map screen. Record
			# that the player action still owes an enemy phase before changing screens;
			# the returning map consumes it exactly once.
			map_state[POST_REWARD_TURN_PENDING_KEY] = true
			var save_result := SaveService.save_game()
			if not save_result.ok:
				_present_treasure_save_failure(report.value, save_result.error)
				return "TRANSITION"
			turn_transitioning = true
			call_deferred("_emit_treasure_reward_after_map_callback", report.value)
			return "TRANSITION"
	if not selected_relay.is_empty() and arrival == Vector2i(int(selected_relay.get("q", 0)), int(selected_relay.get("r", 0))):
		_activate_selected_relay()
		return "STAY"
	if not selected_event.is_empty() and arrival == Vector2i(int(selected_event.get("q", 0)), int(selected_event.get("r", 0))):
		_update_panel()
		return "STAY"
	if selected_node.is_empty() or str(selected_node.get("stage_id", "")).is_empty(): return "STAY"
	var node_id := str(selected_node.get("node_id", ""))
	if MapExplorationServiceScript.encounter_cleared(map_state, node_id) or int(AppState.profile.stage_stars.get(str(selected_node.stage_id), 0)) > 0:
		return "STAY"
	var live_enemy_coord := _encounter_coord(selected_node)
	if arrival != live_enemy_coord:
		if MapExplorationServiceScript.movement_remaining(map_state, definition) <= 0:
			return "STAY"
		# Patrol simulation advances only at discrete map ticks.  Do not pretend the
		# old preview endpoint is still hostile after the enemy moved; deterministically
		# re-plan to the current pawn position, then require real contact.
		if _continue_live_encounter_pursuit(arrival, live_enemy_coord):
			return "REPLAN"
		_show_map_notice("순찰 적이 경로를 벗어났습니다 · 다시 선택하여 추적")
		return "STAY"
	var return_coord := path[path.size() - 2] if path.size() >= 2 else Vector2i(int(map_state.current_q), int(map_state.current_r))
	map_state.last_pre_contact_hex = [return_coord.x, return_coord.y]
	_start_patrol_contact(node_id, return_coord)
	return "TRANSITION"

func _emit_treasure_reward_after_map_callback(report: Dictionary) -> void:
	if not is_inside_tree():
		return
	treasure_reward_requested.emit(report)

func _present_treasure_save_failure(report: Dictionary, error_text: String) -> void:
	turn_transitioning = true
	map_simulation_paused = true
	if treasure_save_failure_layer != null and is_instance_valid(treasure_save_failure_layer):
		treasure_save_failure_layer.queue_free()
	treasure_save_failure_layer = CanvasLayer.new()
	treasure_save_failure_layer.name = "TreasureSaveFailureLayer"
	treasure_save_failure_layer.layer = 450
	add_child(treasure_save_failure_layer)
	var surface := Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.theme = theme
	treasure_save_failure_layer.add_child(surface)
	var dimmer := ColorRect.new()
	dimmer.color = Color("020710e8")
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.add_child(dimmer)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.16
	panel.anchor_right = 0.84
	panel.anchor_top = 0.28
	panel.anchor_bottom = 0.72
	panel.add_theme_stylebox_override("panel", GameUI.panel_style(Color("081725fa"), Color("f1c75b"), 1, GameUI.RADIUS_MODAL, Vector4(30, 26, 30, 28), 16))
	surface.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	var title := Label.new()
	title.text = "TREASURE PROGRESS NOT SAVED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("f1c75b"))
	column.add_child(title)
	var detail := Label.new()
	detail.text = "The reward is held in memory. Retry the save before continuing.\n%s" % error_text
	detail.name = "TreasureSaveFailureDetail"
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 20)
	detail.add_theme_color_override("font_color", GameUI.TEXT_MUTED)
	column.add_child(detail)
	column.add_child(_button("RETRY SAVE", func() -> void:
		var retry_result := SaveService.save_game()
		if retry_result.ok:
			if treasure_save_failure_layer != null and is_instance_valid(treasure_save_failure_layer):
				treasure_save_failure_layer.queue_free()
			treasure_save_failure_layer = null
			call_deferred("_emit_treasure_reward_after_map_callback", report)
		else:
			detail.text = "The reward is held in memory. Retry the save before continuing.\n%s" % retry_result.error
	, Vector2(320, 70)))

func _arrival_resolution_owns_save(arrival: Vector2i) -> bool:
	# Avoid two complete Web filesystem transactions at the same destination.
	# Treasure/relay claims and a real encounter each persist their atomic result;
	# the movement layer only saves arrivals with no immediate transaction.
	if not selected_treasure.is_empty() and arrival == Vector2i(int(selected_treasure.get("q", 0)), int(selected_treasure.get("r", 0))):
		return true
	if not selected_relay.is_empty() and arrival == Vector2i(int(selected_relay.get("q", 0)), int(selected_relay.get("r", 0))):
		return true
	if not selected_node.is_empty() and arrival == _encounter_coord(selected_node):
		var node_id := str(selected_node.get("node_id", ""))
		var stage_id := str(selected_node.get("stage_id", ""))
		return not MapExplorationServiceScript.encounter_cleared(map_state, node_id) and int(AppState.profile.stage_stars.get(stage_id, 0)) <= 0
	return false

func _continue_live_encounter_pursuit(arrival: Vector2i, live_enemy_coord: Vector2i) -> bool:
	var node_id := str(selected_node.get("node_id", ""))
	# Static encounters always retain their authored coordinate.  Only actual
	# patrols may change their target after the user confirmed movement.
	if MapSimulationScript.patrol_definition(definition, node_id).is_empty():
		return false
	if live_encounter_replans >= MAX_LIVE_ENCOUNTER_REPLANS:
		return false
	var allowed := _traversal_allowlist()
	var pursuit_path := MapSimulationScript.pursuit_path(map_state, definition, grid, arrival, node_id, allowed)
	pursuit_path = _truncate_at_first_unresolved_encounter(pursuit_path)
	if pursuit_path.size() <= 1 or pursuit_path[-1] != live_enemy_coord:
		return false
	live_encounter_replans += 1
	preview_path = pursuit_path
	preview_risk = MapSimulationScript.risk_for_path(map_state, definition, grid, pursuit_path, _player_vision_radius())
	_update_route_mesh()
	_refresh_state_visuals()
	_show_map_notice("순찰 적 재포착 · 경로 갱신 %d/%d" % [live_encounter_replans, MAX_LIVE_ENCOUNTER_REPLANS])
	# The prior movement coroutine has fully reached its discrete arrival point.
	# Defer the next segment so it cannot overlap a stale tween or create two
	# encounter transactions in one frame.
	call_deferred("_move_along", pursuit_path)
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		map_simulation_paused = true
		map_state.map_simulation_state.paused = true
		if moving: skip_movement()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		map_simulation_paused = false
		map_state.map_simulation_state.paused = false
		if pending_turn_completion:
			var resume_label := pending_turn_label
			pending_turn_completion = false
			pending_turn_label = ""
			turn_transitioning = false
			call_deferred("_complete_player_turn", resume_label)

func _fast_travel() -> void:
	if moving or turn_transitioning or map_simulation_paused: return
	if not selected_event.is_empty():
		_resolve_selected_event(1)
		return
	if not selected_relay.is_empty():
		var origin := _active_relay_at_party()
		var destination_id := str(selected_relay.get("relay_id", ""))
		if origin.is_empty() or not MapExplorationServiceScript.can_fast_travel_between(map_state, definition, str(origin.get("relay_id", "")), destination_id): return
		AppState.set_chapter_map_position(Vector2i(int(selected_relay.get("q", 0)), int(selected_relay.get("r", 0))), "", map_id)
		pawn.position = _pawn_world_position()
		_focus_current(false)
		SaveService.save_game()
		preview_path = [Vector2i(int(selected_relay.get("q", 0)), int(selected_relay.get("r", 0)))]
		_update_route_mesh()
		_update_movement_range_overlay()
		_update_panel()
		return
	if selected_node.is_empty(): return
	var stage_id := str(selected_node.get("stage_id", ""))
	if int(AppState.profile.stage_stars.get(stage_id, 0)) <= 0: return
	AppState.set_chapter_map_position(Vector2i(int(selected_node.q), int(selected_node.r)), str(selected_node.node_id), map_id)
	pawn.position = _pawn_world_position()
	_begin_movement_camera_settle(pawn.global_position)
	_set_pawn_motion_state("ARRIVE")
	await get_tree().create_timer(0.04).timeout
	_set_pawn_motion_state("IDLE")
	SaveService.save_game()
	preview_path = [Vector2i(int(selected_node.q), int(selected_node.r))]
	_update_route_mesh()
	_update_movement_range_overlay()
	_update_panel()

func _request_battle() -> void:
	if selected_node.is_empty() or battle_button.disabled: return
	battle_requested.emit(str(selected_node.get("stage_id", "")))

func _request_sweep(count: int) -> void:
	if not selected_node.is_empty(): sweep_requested.emit(str(selected_node.get("stage_id", "")), count)

func _clear_selection() -> void:
	selected_node = {}
	live_encounter_replans = 0
	selected_treasure = {}
	selected_relay = {}
	selected_event = {}
	preview_path.clear()
	preview_risk = "SAFE"
	_update_route_mesh()
	_update_panel()

func _set_pawn_facing(from: Vector3, to: Vector3) -> void:
	var direction := to - from
	direction.y = 0.0
	if direction.length_squared() < 0.0001: return
	pawn.rotation.y = atan2(direction.x, direction.z)
	# Billboard rotation cannot communicate left/right. Resolve facing in screen
	# space and retain the previous side for near-vertical motion to prevent a
	# distracting one-frame flip on steep/diagonal routes.
	var horizontal_delta := direction.x
	var vertical_threshold := maxf(0.06, direction.length() * 0.12)
	if camera != null and is_instance_valid(camera) \
			and not camera.is_position_behind(from) and not camera.is_position_behind(to):
		var screen_delta := camera.unproject_position(to) - camera.unproject_position(from)
		horizontal_delta = screen_delta.x
		vertical_threshold = maxf(2.0, screen_delta.length() * 0.12)
	if absf(horizontal_delta) <= vertical_threshold:
		return
	pawn_facing_right = horizontal_delta > 0.0
	_apply_pawn_facing()

func _apply_pawn_facing() -> void:
	if pawn_sprite != null and is_instance_valid(pawn_sprite):
		pawn_sprite.flip_h = not pawn_facing_right
	if pawn_front_overlay != null and is_instance_valid(pawn_front_overlay):
		pawn_front_overlay.flip_h = not pawn_facing_right

func _set_pawn_motion_state(next_state: String) -> void:
	# Each state owns a fresh epoch. Using raw process uptime as the atlas phase
	# made every click begin on an arbitrary walk/victory frame.
	pawn_motion_state = next_state
	pawn_motion_epoch_msec = Time.get_ticks_msec()
	pawn_motion_phase = 0.0
	pawn_last_atlas_frame = -1
	_set_pawn_grounding_terrace_walking(next_state == "WALK")

func _set_pawn_grounding_terrace_walking(is_walking: bool) -> void:
	if pawn_grounding_terrace == null or not is_instance_valid(pawn_grounding_terrace):
		return
	if is_walking:
		# The socket belongs to a settled hex; carrying it between elevations reads
		# as a floating platform. Keep the shadow/pedestal, hide only this terrace.
		pawn_grounding_terrace.visible = false
		return
	var coord := _player_map_coord()
	if grid.has(coord):
		pawn_grounding_terrace.material_override = _material(_terrain_surface_color(grid.tile(coord)).lightened(0.05))
	pawn_grounding_terrace.visible = true

func _focus_current(immediate: bool) -> void:
	_focus_coord(Vector2i(int(map_state.current_q), int(map_state.current_r)), immediate)

func _focus_coord(coord: Vector2i, immediate: bool) -> void:
	var next_target := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP)
	if immediate or bool(SettingsService.values.get("map_instant_focus", false)):
		# An immediate focus changes districts in one frame, so its local detail
		# terrain must be ready before the camera is moved.
		_stream_visible_tiles(coord, stream_anchor != coord)
		camera_target = _clamp_camera_target_to_terrain(next_target)
	else:
		# Do not evict the current district before this tween begins. _process()
		# advances the stream anchor along the focus path, keeping real terrain
		# under the camera for the entire transition instead of flashing ocean.
		if preview_camera_tween != null and preview_camera_tween.is_valid():
			preview_camera_tween.kill()
		preview_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		preview_camera_tween.tween_method(func(value: Vector3): camera_target = _clamp_camera_target_to_terrain(value), camera_target, next_target, 0.35)

func _focus_full_map() -> void:
	var normal_route: Array = definition.get("normal_route", [])
	var overview_index := mini(4, normal_route.size() - 1)
	var overview_node := ChapterMapLoaderScript.node_for_stage(definition, str(normal_route[overview_index])) if overview_index >= 0 else {}
	var overview_coord := Vector2i(int(overview_node.get("q", 0)), int(overview_node.get("r", 0)))
	camera_target = _clamp_camera_target_to_terrain(HexCoordScript.axial_to_world(overview_coord, TILE_SIZE))
	camera_zoom = 0.72
	map_state.camera_zoom = camera_zoom
	_stream_visible_tiles(HexCoordScript.world_to_axial(camera_target, TILE_SIZE))

func _clamp_camera_candidate_to_vision(candidate: Vector3) -> Vector3:
	var requested_coord := HexCoordScript.world_to_axial(candidate, TILE_SIZE)
	if _coord_is_in_player_vision(requested_coord):
		return candidate
	var center := _player_map_coord()
	var closest := HexCoordScript.axial_to_world(center, TILE_SIZE)
	var closest_distance := INF
	var vision_radius := _player_vision_radius()
	for dq in range(-vision_radius, vision_radius + 1):
		for dr in range(-vision_radius, vision_radius + 1):
			var coord := center + Vector2i(dq, dr)
			if HexCoordScript.distance(center, coord) > vision_radius or not grid.traversable(coord):
				continue
			var world := HexCoordScript.axial_to_world(coord, TILE_SIZE)
			var distance := Vector2(world.x, world.z).distance_squared_to(Vector2(candidate.x, candidate.z))
			if distance < closest_distance:
				closest_distance = distance
				closest = world
	return Vector3(closest.x, candidate.y, closest.z)

func _clamp_camera_target_to_terrain(candidate: Vector3) -> Vector3:
	# Camera navigation is constrained by the generated traversable land itself,
	# not by the former broad hard-coded world rectangle. This preserves smooth
	# pan along the 96-hex route while preventing a drag or legacy camera value
	# from centring the viewport in empty ocean where a pawn can look detached.
	candidate = _clamp_camera_candidate_to_vision(candidate)
	if grid.traversable(HexCoordScript.world_to_axial(candidate, TILE_SIZE)):
		return candidate
	var origin := HexCoordScript.world_to_axial(candidate, TILE_SIZE)
	var closest_world := Vector3.ZERO
	var closest_distance := INF
	for dq in range(-CAMERA_TERRAIN_SEARCH_RADIUS, CAMERA_TERRAIN_SEARCH_RADIUS + 1):
		for dr in range(-CAMERA_TERRAIN_SEARCH_RADIUS, CAMERA_TERRAIN_SEARCH_RADIUS + 1):
			var coord := origin + Vector2i(dq, dr)
			if HexCoordScript.distance(origin, coord) > CAMERA_TERRAIN_SEARCH_RADIUS or not grid.traversable(coord):
				continue
			var world := HexCoordScript.axial_to_world(coord, TILE_SIZE)
			var distance := Vector2(candidate.x - world.x, candidate.z - world.z).length()
			if distance < closest_distance:
				closest_distance = distance
				closest_world = world
	if is_inf(closest_distance):
		var start: Dictionary = definition.get("start_hex", {"q": 0, "r": 0})
		closest_world = HexCoordScript.axial_to_world(Vector2i(int(start.get("q", 0)), int(start.get("r", 0))), TILE_SIZE)
		closest_distance = Vector2(candidate.x - closest_world.x, candidate.z - closest_world.z).length()
	if closest_distance <= CAMERA_TERRAIN_MARGIN:
		return candidate
	var offset := Vector2(candidate.x - closest_world.x, candidate.z - closest_world.z).normalized() * CAMERA_TERRAIN_MARGIN
	return Vector3(closest_world.x + offset.x, candidate.y, closest_world.z + offset.y)

func _on_map_input(event: InputEvent) -> void:
	# The SubViewport receives direct pointer events, bypassing AppShell's
	# shared Button wrapper.  Unlock deferred WebAudio on the first map gesture.
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		AudioService.unlock_from_user_gesture()
	if moving or turn_transitioning or map_simulation_paused: return
	if event is InputEventScreenTouch:
		# Mobile Web sends screen touch events instead of mouse buttons on some
		# browsers. Keep the same tap-vs-drag threshold as desktop and never let a
		# touch pan accidentally confirm a long route.
		if event.pressed:
			dragging = true
			drag_origin = event.position
			camera_origin = camera_target
		else:
			if dragging and event.position.distance_to(drag_origin) <= 24.0 * _portrait_ui_scale(_runtime_layout_size()):
				_select_node_near_screen(event.position, direct_move_gesture_policy(event))
			dragging = false
	elif event is InputEventScreenDrag:
		if not dragging: return
		var touch_delta: Vector2 = event.position - drag_origin
		camera_target = _clamp_camera_target_to_terrain(camera_origin + Vector3(-touch_delta.x * 0.012 / camera_zoom, 0, -touch_delta.y * 0.012 / camera_zoom))
		map_state.camera_center = [camera_target.x, camera_target.z]
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var pointer_threshold := 18.0 * _portrait_ui_scale(_runtime_layout_size())
				var now_msec := Time.get_ticks_msec()
				var repeated_pointer_click: bool = last_map_pointer_click_valid and now_msec - last_map_pointer_click_msec >= 0 and now_msec - last_map_pointer_click_msec <= DIRECT_DOUBLE_CLICK_WINDOW_MSEC and event.position.distance_to(last_map_pointer_click_position) <= pointer_threshold
				direct_move_pending = direct_move_gesture_policy(event, repeated_pointer_click)
				if direct_move_pending:
					last_map_pointer_click_valid = false
				dragging = true
				drag_origin = event.position
				camera_origin = camera_target
			else:
				# A tap selects the nearest visible encounter in screen space. Map
				# traversal remains based on stable axial node data, not physics picks.
				var completed_click: bool = dragging and event.position.distance_to(drag_origin) <= 18.0 * _portrait_ui_scale(_runtime_layout_size())
				var activate_route := direct_move_pending
				if completed_click:
					# Repeating a preview must activate the exact route that was just
					# shown, rather than re-picking the screen after the focus camera
					# has shifted its projection.  The old re-pick made a visible route
					# look blocked because the second click could resolve to a different
					# hex or nothing at all.
					if activate_route and preview_path.size() > 1:
						_activate_selected_route_from_pointer()
					else:
						_select_node_near_screen(event.position, activate_route)
					if not activate_route:
						last_map_pointer_click_valid = true
						last_map_pointer_click_msec = Time.get_ticks_msec()
						last_map_pointer_click_position = event.position
				else:
					last_map_pointer_click_valid = false
				dragging = false
				direct_move_pending = false
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera_zoom = clampf(camera_zoom + (0.08 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.08), 0.72, 1.55)
			map_state.camera_zoom = camera_zoom
	elif event is InputEventMouseMotion and dragging:
		var delta: Vector2 = event.position - drag_origin
		camera_target = _clamp_camera_target_to_terrain(camera_origin + Vector3(-delta.x * 0.012 / camera_zoom, 0, -delta.y * 0.012 / camera_zoom))
		map_state.camera_center = [camera_target.x, camera_target.z]

func _select_node_near_screen(screen_position: Vector2, activate_route := false) -> bool:
	if camera == null or viewport == null or viewport_container == null: return false
	var viewport_size := Vector2(viewport.size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0: return false
	var surface_scale := viewport_container.size / viewport_size
	var runtime_size := _runtime_layout_size()
	var hit_radius := 72.0 * _portrait_ui_scale(runtime_size) if runtime_size.y > runtime_size.x else 46.0
	var closest: Dictionary = {}
	var closest_kind := ""
	var closest_distance := INF
	# Hostile pawns take priority over their authored stage marker: selecting one
	# previews a route but cannot start combat before the squad really reaches it.
	for node_id in enemy_pawns:
		var hostile_root: Node3D = enemy_pawns[node_id]
		if hostile_root == null or not hostile_root.visible: continue
		var hostile_projected := camera.unproject_position(hostile_root.position + Vector3(0.0, 0.68, 0.0)) * surface_scale
		var hostile_distance := hostile_projected.distance_to(screen_position)
		if hostile_distance < closest_distance:
			closest_distance = hostile_distance
			closest = ChapterMapLoaderScript.node_by_id(definition, str(node_id))
			closest_kind = "NODE"
	for node in definition.get("nodes", []):
		var node_id := str(node.get("node_id", ""))
		var stage_id := str(node.get("stage_id", ""))
		# The checkmark badge is informational only.  It must not win the hit test
		# over an adjacent reachable hex after the operation has been cleared.
		if not stage_id.is_empty() and (MapExplorationServiceScript.encounter_cleared(map_state, node_id) or int(AppState.profile.stage_stars.get(stage_id, 0)) > 0):
			continue
		var node_button: Button = node_buttons.get(str(node.get("node_id", "")))
		if node_button == null or not node_button.visible: continue
		var projected := _overlay_position_from_world(_node_overlay_anchor(node))
		var distance := projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = node
			closest_kind = "NODE"
	for treasure in definition.get("treasures", []):
		var treasure_id := str(treasure.get("treasure_id", ""))
		var treasure_state := MapExplorationServiceScript.treasure_state(map_state, treasure_id)
		# HINTED caches intentionally have no exact selectable target. The map
		# keeps their authored environmental clue visible but routing stays hidden
		# until the party reaches the area and the cache becomes REVEALED.
		if treasure_state != "REVEALED": continue
		var root: Node3D = treasure_visuals.get(treasure_id)
		if root == null or not root.visible: continue
		var coord := Vector2i(int(treasure.get("q", 0)), int(treasure.get("r", 0)))
		var world_position := HexCoordScript.axial_to_world(coord, TILE_SIZE, float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.62)
		var projected := camera.unproject_position(world_position) * surface_scale
		var distance := projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = treasure
			closest_kind = "TREASURE"
	for relay in definition.get("relays", []):
		var relay_id := str(relay.get("relay_id", ""))
		var relay_root: Node3D = relay_visuals.get(relay_id)
		if relay_root == null or not relay_root.visible: continue
		var relay_projected := camera.unproject_position(relay_root.position + Vector3(0.0, 0.82, 0.0)) * surface_scale
		var relay_distance := relay_projected.distance_to(screen_position)
		if relay_distance < closest_distance:
			closest_distance = relay_distance
			closest = relay
			closest_kind = "RELAY"
	for event in definition.get("map_events", []):
		var event_id := str(event.get("event_id", ""))
		var event_root: Node3D = event_visuals.get(event_id)
		if event_root == null or not event_root.visible: continue
		var event_projected := camera.unproject_position(event_root.position + Vector3(0.0, 0.62, 0.0)) * surface_scale
		var event_distance := event_projected.distance_to(screen_position)
		if event_distance < closest_distance:
			closest_distance = event_distance
			closest = event
			closest_kind = "EVENT"
	if not closest.is_empty() and closest_distance <= hit_radius:
		if closest_kind == "TREASURE": _select_treasure(closest)
		elif closest_kind == "RELAY": _select_relay(closest)
		elif closest_kind == "EVENT": _select_event(closest)
		else: _select_node(closest)
		if activate_route:
			_activate_selected_route_from_pointer()
		return true
	# Pick the actual visible ground cell first, including blocked cells. Looking
	# only through reachable cells snapped a click on a wall/river to the nearest
	# yellow neighbour and made decorative barriers behave as walkable terrain.
	var current := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	var vision_radius := _player_vision_radius()
	var ground_pick := _pick_ground_coord_from_screen(screen_position, surface_scale, current, vision_radius)
	var ground_coord: Vector2i = ground_pick.get("coord", Vector2i(999999, 999999))
	var ground_distance := float(ground_pick.get("distance", INF))
	# The visible yellow hex is wider than the old desktop label hit radius.
	# Keep portrait touch targets unchanged, while accepting the actual body of a
	# desktop hex instead of requiring an artificial centre-pixel click.
	var ground_hit_radius := maxf(hit_radius, 58.0)
	if ground_distance <= ground_hit_radius:
		var ground_key := HexCoordScript.key(ground_coord)
		if ground_coord == current or not movement_range_reachable.has(ground_key):
			_show_map_notice("통행 불가 지형입니다 · 길과 열린 지형으로 이동하세요")
			return true
		if not _set_direct_hex_route(ground_coord):
			return true
		if activate_route:
			_activate_selected_route_from_pointer()
		else:
			_show_map_notice("경로 미리보기 · 같은 노란 칸을 한 번 더 클릭하면 이동합니다")
		return true
	return false

func _pick_ground_coord_from_screen(screen_position: Vector2, surface_scale: Vector2, current: Vector2i, vision_radius: int) -> Dictionary:
	# The old picker projected every visible cell on every press/release. At a
	# ten-cell sight radius that meant up to 441 Camera3D projections per pointer
	# event and produced a repeatable ~80ms Web frame before movement even began.
	# Invert the projection instead: intersect the camera ray with each possible
	# terrain-height plane, then compare only the guessed hex and its six neighbours.
	# This still sees blocked river/wall cells first, so it never snaps an invalid
	# click onto a nearby yellow tile.
	if is_zero_approx(surface_scale.x) or is_zero_approx(surface_scale.y):
		return {}
	var viewport_position := screen_position / surface_scale
	var ray_origin := camera.project_ray_origin(viewport_position)
	var ray_direction := camera.project_ray_normal(viewport_position)
	if is_zero_approx(ray_direction.y):
		return {}
	var candidate_keys: Dictionary = {}
	# Macro terrain currently occupies elevation levels 0..4. Include one plane
	# below and above that authored range so legacy/repaired edge tiles remain
	# selectable without falling back to a world-size scan.
	for elevation_index in range(-1, 6):
		var plane_y := float(elevation_index) * ELEVATION_STEP + 0.14
		var ray_distance := (plane_y - ray_origin.y) / ray_direction.y
		if ray_distance <= 0.0:
			continue
		var world_hit := ray_origin + ray_direction * ray_distance
		var guessed := HexCoordScript.world_to_axial(world_hit, TILE_SIZE)
		candidate_keys[HexCoordScript.key(guessed)] = guessed
		for neighbor in HexCoordScript.neighbors(guessed):
			candidate_keys[HexCoordScript.key(neighbor)] = neighbor
	var closest_coord := Vector2i(999999, 999999)
	var closest_distance := INF
	for candidate_value in candidate_keys.values():
		var coord: Vector2i = candidate_value
		if HexCoordScript.distance(current, coord) > vision_radius or not grid.has(coord):
			continue
		var surface_y := float(grid.tile(coord).get("elevation", 0)) * ELEVATION_STEP + 0.14
		var world_position := HexCoordScript.axial_to_world(coord, TILE_SIZE, surface_y)
		if camera.is_position_behind(world_position):
			continue
		var projected := camera.unproject_position(world_position) * surface_scale
		var distance := projected.distance_to(screen_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_coord = coord
	return {"coord": closest_coord, "distance": closest_distance}

func _process(delta: float) -> void:
	if camera == null or not is_instance_valid(camera) or viewport == null or not is_instance_valid(viewport):
		return
	_process_web_render_retire_queue()
	# Never print one console line per slow Web frame. A single hitch used to start
	# a feedback loop where DevTools transport and string formatting caused the
	# following frame to miss its budget as well. WebSoakProbe already reports a
	# bounded five-second aggregate with max/33/50/100 ms counters.
	_process_pending_dressing()
	if environment_fx != null and is_instance_valid(environment_fx):
		_refresh_environment_presentation()
	if moving and movement_camera_follow_active and pawn != null and is_instance_valid(pawn):
		# Follow the pawn's continuous transform with a frame-rate-independent
		# exponential response. This preserves velocity across hex boundaries and
		# avoids allocating/interrupting a camera Tween for every single step.
		movement_camera_goal = _pawn_camera_goal(pawn.global_position)
		var follow_strength := clampf(float(SettingsService.values.get("map_camera_follow_strength", 0.72)), 0.0, 1.0)
		var follow_rate := lerpf(5.5, 11.0, follow_strength)
		var follow_weight := 1.0 - exp(-follow_rate * maxf(delta, 0.0))
		camera_target = _clamp_camera_target_to_terrain(camera_target.lerp(movement_camera_goal, follow_weight))
	elif movement_camera_settle_active:
		# One bounded, allocation-free settle absorbs the follow lag after the final
		# cell. It always reaches the exact elevated pawn target within 0.20 seconds.
		movement_camera_settle_elapsed = minf(PAWN_CAMERA_SETTLE_DURATION, movement_camera_settle_elapsed + maxf(delta, 0.0))
		var settle_ratio := movement_camera_settle_elapsed / PAWN_CAMERA_SETTLE_DURATION
		var settle_weight := settle_ratio * settle_ratio * (3.0 - 2.0 * settle_ratio)
		camera_target = _clamp_camera_target_to_terrain(movement_camera_settle_from.lerp(movement_camera_settle_goal, settle_weight))
		if movement_camera_settle_elapsed >= PAWN_CAMERA_SETTLE_DURATION:
			camera_target = movement_camera_settle_goal
			movement_camera_settle_active = false
	pawn_motion_phase += delta * (8.5 if pawn_motion_state == "WALK" else 3.0)
	if pawn_visual != null and is_instance_valid(pawn_visual):
		# Motion is authored in the atlas. Moving/scaling the entire cutout would
		# lift its foot anchor from the terrace and make the pawn look airborne.
		pawn_visual.position.y = PAWN_VISUAL_BASE_Y
		pawn_visual.scale = Vector3.ONE
	if pawn_banner != null and is_instance_valid(pawn_banner):
		pawn_banner.rotation.y = sin(pawn_motion_phase * 0.5) * 0.14
	if selected_ring != null and is_instance_valid(selected_ring) and selected_ring.visible:
		var pulse := 1.0 + sin(pawn_motion_phase * 1.4) * 0.08
		selected_ring.scale = Vector3(pulse, 1.0, pulse)
	var animation_now_msec := Time.get_ticks_msec()
	for node_id in enemy_animation_packs:
		var root: Node3D = enemy_pawns.get(node_id)
		if root == null or not is_instance_valid(root) or not root.visible: continue
		var pack: Dictionary = enemy_animation_packs[node_id]
		var sprite: Sprite3D = null
		for child in root.get_children():
			if child is Sprite3D:
				sprite = child
				break
		if sprite == null or not sprite.texture is AtlasTexture: continue
		var atlas_texture := sprite.texture as AtlasTexture
		var frame_size: Vector2 = pack.get("frame_size", Vector2(104, 104))
		var animation_name := "move" if animation_now_msec < int(root.get_meta("patrol_motion_until_msec", 0)) else "idle"
		var frame := _animation_frame(pack, animation_name, animation_now_msec)
		var frame_token := "%s:%d" % [animation_name, frame]
		if str(root.get_meta("last_atlas_frame_token", "")) != frame_token:
			atlas_texture.region = Rect2(float(frame % int(pack.get("columns", 1))) * frame_size.x, float(frame / int(pack.get("columns", 1))) * frame_size.y, frame_size.x, frame_size.y)
			root.set_meta("last_atlas_frame_token", frame_token)
		for child in root.get_children():
			if not child is Sprite3D or child == sprite:
				continue
			var secondary_pack_value = child.get_meta("animation_pack", {})
			if not secondary_pack_value is Dictionary or not (child as Sprite3D).texture is AtlasTexture:
				continue
			var secondary_pack: Dictionary = secondary_pack_value
			var secondary_texture := (child as Sprite3D).texture as AtlasTexture
			var secondary_size: Vector2 = secondary_pack.get("frame_size", Vector2(104, 104))
			var secondary_frame := _animation_frame(secondary_pack, "idle", animation_now_msec + int(child.get_meta("animation_phase_msec", 0)))
			if int(child.get_meta("last_atlas_frame", -1)) != secondary_frame:
				secondary_texture.region = Rect2(float(secondary_frame % int(secondary_pack.get("columns", 1))) * secondary_size.x, float(secondary_frame / int(secondary_pack.get("columns", 1))) * secondary_size.y, secondary_size.x, secondary_size.y)
				child.set_meta("last_atlas_frame", secondary_frame)
		if bool(root.get_meta("event_contact", false)):
			var marker_phase := float(root.get_meta("event_marker_phase", 0.0))
			var event_marker = root.get_meta("event_marker", null)
			if event_marker is Label3D and is_instance_valid(event_marker):
				(event_marker as Label3D).position.y = float(root.get_meta("event_marker_base_y", 1.0)) + sin(pawn_motion_phase * 1.7 + marker_phase) * 0.09
			var event_ring = root.get_meta("threat_ring", null)
			if event_ring is MeshInstance3D and is_instance_valid(event_ring):
				var marker_pulse := 1.0 + sin(pawn_motion_phase * 1.35 + marker_phase) * 0.07
				(event_ring as MeshInstance3D).scale = Vector3(marker_pulse, 1.0, marker_pulse)
	if pawn_sprite != null and is_instance_valid(pawn_sprite) and pawn_sprite.texture is AtlasTexture and not pawn_animation_pack.is_empty():
		var leader_atlas := pawn_sprite.texture as AtlasTexture
		var leader_frame_size: Vector2 = pawn_animation_pack.get("frame_size", Vector2(104, 104))
		var leader_columns := maxi(1, int(pawn_animation_pack.get("columns", 1)))
		var leader_animation := "move" if pawn_motion_state == "WALK" else ("victory" if pawn_motion_state == "ARRIVE" else "idle")
		var leader_elapsed_msec := maxi(0, animation_now_msec - pawn_motion_epoch_msec)
		var leader_frame := _animation_frame(pawn_animation_pack, leader_animation, leader_elapsed_msec)
		var leader_frame_token := leader_frame + (["idle", "move", "victory"].find(leader_animation) + 1) * 10000
		if pawn_last_atlas_frame != leader_frame_token:
			leader_atlas.region = Rect2(float(leader_frame % leader_columns) * leader_frame_size.x, float(leader_frame / leader_columns) * leader_frame_size.y, leader_frame_size.x, leader_frame_size.y)
			pawn_last_atlas_frame = leader_frame_token
	for treasure_id in treasure_visuals:
		var root: Node3D = treasure_visuals[treasure_id]
		if root == null or not is_instance_valid(root) or not root.visible: continue
		var glow = root.get_meta("glow", null)
		if glow != null and is_instance_valid(glow) and glow.visible:
			var pulse := 1.0 + sin(pawn_motion_phase * 1.5 + float(treasure_id.hash() % 9)) * 0.08
			glow.scale = Vector3(pulse, 1.0, pulse)
	var desired_camera_size := 13.2 / camera_zoom
	var desired_camera_position := camera_target + Vector3(9.2, 14.2, 8.8)
	var camera_changed := not is_equal_approx(camera.size, desired_camera_size) or not camera.position.is_equal_approx(desired_camera_position)
	if camera_changed:
		camera.size = desired_camera_size
	# A higher orthographic angle keeps a distant shelf or ridge from visually
	# covering a valid route pawn while preserving the 2.5D chapter-map read.
	# The simulation still owns X/Z; this only improves the production camera's
	# depth separation of terrain, sockets and map pawns.
	# The R8 camera is intentionally lower than the old tactical-board angle so
	# cliff faces occupy enough screen space to communicate elevation.
		camera.position = desired_camera_position
		camera.look_at(camera_target, Vector3.UP)
	var projection_size_changed := overlay != null and is_instance_valid(overlay) and web_entity_projection_size != overlay.size
	if camera_changed or moving or web_entity_projection_dirty or projection_size_changed:
		_sync_web_pawn_front_overlay()
	if OS.has_feature("web") and web_route_overlay != null and is_instance_valid(web_route_overlay) and web_route_overlay.visible:
		_update_web_route_line()
	if OS.has_feature("web") and web_selected_overlay != null and is_instance_valid(web_selected_overlay) and web_selected_overlay.visible:
		_update_web_selected_ring()
	if OS.has_feature("web") and web_movement_overlay != null and is_instance_valid(web_movement_overlay) and web_movement_overlay.visible:
		_update_web_movement_range_projection()
	if camera_changed or moving or web_entity_projection_dirty or projection_size_changed:
		_update_screen_fog_overlay()
	if environment_fx != null and is_instance_valid(environment_fx) and camera_changed:
		environment_fx.set_camera_phase(camera_target)
	var camera_coord := HexCoordScript.world_to_axial(camera_target, TILE_SIZE)
	if not moving and not turn_transitioning:
		_stream_visible_tiles(camera_coord)
	# Rendering is streamed, but patrol state never is: offscreen hostiles retain
	# only their tiny logical state and wake visually when the camera returns.
	# Web transit keeps labels hidden and refreshes them once on arrival. Repeating
	# the whole node projection loop for every camera sub-step was one of the last
	# sources of movement-frame spikes and made BGM underruns more noticeable.
	var entity_projection_changed := not OS.has_feature("web") \
		or projection_size_changed \
		or (not moving and (camera_changed or web_entity_projection_dirty))
	if entity_projection_changed:
		_refresh_projected_map_entities(camera_coord)
		web_entity_projection_dirty = false
		if overlay != null and is_instance_valid(overlay):
			web_entity_projection_size = overlay.size

func _refresh_projected_map_entities(camera_coord: Vector2i) -> void:
	# Visibility and label projection depend on camera/player/layout state, not on
	# every idle frame. Compatibility Web previously repeated these world-to-screen
	# conversions for every authored operation even while absolutely nothing moved.
	if camera == null or not is_instance_valid(camera) or overlay == null or not is_instance_valid(overlay):
		return
	for node_id in enemy_pawns:
		var root: Node3D = enemy_pawns[node_id]
		var node := ChapterMapLoaderScript.node_by_id(definition, str(node_id))
		if root == null or not is_instance_valid(root) or node.is_empty(): continue
		var stage_id := str(node.get("stage_id", ""))
		var unlocked := stage_id != "" and AppState.is_stage_unlocked(stage_id)
		var cleared := _node_encounter_cleared(node)
		var encounter_coord := _encounter_coord(node)
		root.visible = unlocked and not cleared and _coord_is_in_player_vision(encounter_coord) and _map_entity_is_locally_renderable(encounter_coord, camera_coord, STREAM_RADIUS + 2) and (not stage_id.contains("-H") or hard_overlay)
	var runtime_size := _runtime_layout_size()
	var portrait := runtime_size.y > runtime_size.x
	var ui_scale := _portrait_ui_scale(runtime_size)
	var navigation_reveal := _path_reveal_allowlist()
	for node in definition.get("nodes", []):
		var button: Button = node_buttons.get(str(node.node_id))
		if button == null or not is_instance_valid(button): continue
		var stage_id := str(node.get("stage_id", ""))
		var revealed: bool = navigation_reveal.has("%d,%d" % [int(node.get("q", 0)), int(node.get("r", 0))])
		var unlocked := stage_id == "" or AppState.is_stage_unlocked(stage_id)
		var node_coord := _encounter_coord(node)
		var semantic_visible: bool = bool(_coord_is_in_player_vision(node_coord) and (revealed or (not stage_id.is_empty() and unlocked)) and (stage_id == "" or hard_overlay == stage_id.contains("-H")))
		var label_in_local_stream: bool = HexCoordScript.distance(node_coord, camera_coord) <= STREAM_RADIUS - 2
		var anchor := _node_overlay_anchor(node)
		button.visible = semantic_visible and label_in_local_stream and _has_streamed_ground(node_coord) and _overlay_anchor_is_visible(anchor, button.size)
		var stage_marker: Node3D = node_markers.get(str(node.get("node_id", "")))
		if stage_marker != null and is_instance_valid(stage_marker):
			stage_marker.visible = button.visible
		if not button.visible: continue
		var projected := _overlay_position_from_world(anchor)
		var label_offset := Vector2(0, (-78.0 if str(node.get("node_type", "")) == "START" else -62.0) * ui_scale) if portrait else Vector2(0, -126 if str(node.get("node_type", "")) == "START" else -86)
		button.position = projected - button.size * 0.5 + label_offset

func _refresh_environment_presentation() -> void:
	if environment_fx == null or not is_instance_valid(environment_fx):
		return
	# Environment is a derived, transient grade based on canonical axial
	# position. It never writes that coordinate, its save payload or simulation.
	var current_coord := Vector2i(int(map_state.get("current_q", 0)), int(map_state.get("current_r", 0)))
	if current_coord == environment_context_coord and hard_overlay == environment_context_hard:
		return
	environment_context_coord = current_coord
	environment_context_hard = hard_overlay
	environment_fx.set_transient_map_context(current_coord, hard_overlay)
