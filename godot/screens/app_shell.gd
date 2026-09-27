extends Control

const WEB_FRAME_RATE_CAP := 60

const BattleViewScene := preload("res://battle/scenes/battle_root.tscn")
const ChapterMapScene := preload("res://chapter_map/view/chapter_map_root.tscn")
const ChapterMapLoaderScript := preload("res://chapter_map/runtime/chapter_map_loader.gd")
const MapExplorationServiceScript := preload("res://chapter_map/model/map_exploration_service.gd")
const HexGridScript := preload("res://chapter_map/model/hex_grid.gd")
const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")
const GrowthAffordabilityAnalyzerScript := preload("res://progression/growth_affordability_analyzer.gd")
const GrowthPlanBuilderScript := preload("res://progression/growth_plan_builder.gd")
const GrowthAdvisorScript := preload("res://progression/growth_advisor.gd")
const ResultPresentation := preload("res://screens/result_presentation.gd")
const CinematicFx := preload("res://ui/cinematic_fx.gd")
const RelayServiceScript := preload("res://relay/relay_service.gd")
const GameUI := preload("res://ui/game_ui_tokens.gd")
const CommandPresentation := preload("res://screens/command_presentation.gd")
const GrowthMenu := preload("res://screens/growth_menu.gd")
const BattleUltimateOrbScript := preload("res://battle/view/battle_ultimate_orb.gd")
const DESIGN_VIEWPORT_SIZE := Vector2(1920.0, 1080.0)
const COMPACT_LANDSCAPE_MAX_WIDTH := 980.0
const MIN_TOUCH_CSS_PX := 56.0
const STORY_FIT_COMPACT_HEIGHT_CSS := 340.0
const STORY_FIT_WIDE_HEIGHT_CSS := 520.0
const STORY_MIN_FIT := 0.55
const SPECIAL_EVENT_CONTACT_DURATION := 1.85
const BOSS_ENCOUNTER_CARD_DURATION := 0.82
const INTRO_VIDEO_PATH := "res://assets/video/lumenbound_intro_full.ogv"
const INTRO_VIDEO_DURATION_SECONDS := 50.0
const INTRO_VIDEO_FINISH_GUARD_SECONDS := 0.75
const TRANSITION_LOADING_MAP_ENTRY := "MAP_ENTRY"
const TRANSITION_LOADING_BATTLE_ENTRY := "BATTLE_ENTRY"
const TRANSITION_LOADING_BATTLE_RESULT := "BATTLE_RESULT"
const TRANSITION_LOADING_MAX_PHASE_VALUE := 96.0
const STAGE_ENTRY_PRELOAD_TARGET_MSEC := 5000
const BATTLE_ENTRY_PRELOAD_TARGET_MSEC := 5000
const LOADING_IDLE_TIMEOUT_MSEC := 12000
const LOADING_HARD_TIMEOUT_MSEC := 45000
var map_load_last_progress_msec := 0
const TRANSITION_GPU_WARM_BATCH := 4
const TRANSITION_LOADING_ART_PATH := "res://assets/art/backgrounds/BG_STORY_RELAY/bg_story_relay_1920x1080.png"
const TRANSITION_LOADING_LOGO_PATH := "res://assets/art/title/title_logo_r1.png"
var content: VBoxContainer
var footer_status: Label
var status_toast: PanelContainer
var status_toast_label: Label
var status_toast_last_text := ""
var status_toast_left := 0.0
var safe_margin: MarginContainer
var current_screen := "TITLE"
var new_game_confirmation_layer: CanvasLayer
var save_protection_layer: CanvasLayer
var transition_loading_layer: CanvasLayer
var transition_loading_surface: Control
var transition_loading_panel: PanelContainer
var transition_loading_progress_bar: ProgressBar
var transition_loading_percent_label: Label
var transition_loading_phase_label: Label
var transition_loading_title_label: Label
var transition_loading_generation := 0
var last_stage_preload_elapsed_msec := 0
var last_stage_preload_texture_count := 0
var last_stage_preload_cache_hit := false
var transition_loading_active_token := 0
var transition_loading_kind := ""
var transition_loading_phase_start_value := 0.0
var transition_loading_phase_target_value := 0.0
var transition_loading_phase_started_msec := 0
var transition_loading_phase_duration_msec := 1
var transaction_save_failure_layer: CanvasLayer
var stage_mode := "NORMAL"
var formation_slot := 0
var scenario_runner: ScenarioRunner
var scenario_speaker: Label
var scenario_text: RichTextLabel
var scenario_choices: VBoxContainer
var story_background: TextureRect
var story_portrait: TextureRect
var story_portrait_layer: Control
var story_art_status: Label
var story_dialogue_panel: PanelContainer
var story_speaker_eyebrow: Label
var story_click_hint: Label
var story_page_indicator: Label
var story_auto_button: Button
var story_skip_button: Button
var story_is_prologue := false
# Authored campaign scenes share the prologue's full-bleed ensemble staging.
var story_is_cinematic := false
var active_chapter_map_screen: Control
var chapter_map_cache_host: Control
var cached_chapter_map_screen: Control
var cached_chapter_map_id := ""
var chapter_map_show_generation := 0
var story_auto := false
var story_auto_left := 0.0
var story_ui_hidden := false
var story_controls: Control
var story_typewriter_tween: Tween
var battle_view: BattleView
var battle_hud: Label
var battle_gauge: Control
var ultimate_buttons: Array[Button] = []
var party_status_labels: Array[Label] = []
var battle_auto_button: Button
var battle_skip_button: Button
var battle_speed_button: Button
var battle_pause_panel: PanelContainer
var battle_pause_center: CenterContainer
var battle_portrait_layout := false
var viewport_gate: ColorRect
var viewport_gate_label: Label
var interface_font: Font
var orientation_forced_pause := false
var last_portrait_layout := false
var last_compact_landscape_layout := false
var layout_refresh_queued := false
var orientation_probe_left := 0.0
var compact_touch_probe_left := 0.0
var last_battle_result: Dictionary = {}
var last_rewards: Dictionary = {}
var last_reward_report: Dictionary = {}
var map_reward_layer: CanvasLayer
var map_reward_surface: Control
var map_reward_panel: PanelContainer
var growth_tab := "레벨업"
var growth_material := "TRAINING_NOTE_S"
var growth_target_level := 0
var growth_feedback := ""
var growth_save_pending := false
var growth_menu_layer: CanvasLayer
var battle_party_ids: Array[String] = []
var relay_edit_squad := 0
var relay_edit_slot := 0
var debug_reset_armed := false
var battle_transition_active := false
# Pre-battle event modals run while the map is still the active scene. Keep a
# raw-input bridge so an embedded Web canvas cannot leave the event card
# without a responsive click, touch, Next, or Skip route.
var pre_battle_event_input_active := false
var pre_battle_event_input_panel: Control
var pre_battle_event_input_next: Button
var pre_battle_event_input_skip: Button
var pre_battle_event_advance: Callable
var pre_battle_event_resolve: Callable
# Development-only capture aid. It is armed only by the explicit DEBUG-menu
# fixture below, is consumed by the next companion contact, and never changes
# the short player-facing encounter transition in a normal or Release run.
var debug_companion_card_visual_hold := false
var transition_edge_blocked_until_msec := 0
var transition_edge_accept_count := 0
var transition_edge_reject_count := 0
var transition_edge_last_action := ""
var transition_edge_last_source := ""
var story_checkpoint_dirty := false
var story_checkpoint_save_scheduled := false
var story_navigation_pending := false
const TRANSITION_EDGE_DEBOUNCE_MSEC := 220
# The first visit to HQ is a guided handoff, not an unlabelled menu landing.
# Keep its presentation separate from map/tutorial ownership so a resize or
# route rebuild cannot change progress until the player deliberately launches.
var home_tutorial_layer: CanvasLayer
var home_tutorial_surface: Control
var home_tutorial_panel: PanelContainer
var home_tutorial_eyebrow: Label
var home_tutorial_title: Label
var home_tutorial_body: RichTextLabel
var home_tutorial_continue_button: Button
var home_tutorial_skip_button: Button
var home_tutorial_progress_label: Label
var home_tutorial_step := 0
# Presentation reflow may rebuild the HOME tree after the browser reports its
# final CSS viewport. Keep the player's logical tutorial progress outside that
# disposable tree so a valid button press can never be reset to step 1/4.
var home_tutorial_resume_step := 1
var home_tutorial_last_advance_msec := -100000
var home_first_operation_navigation_pending := false
var home_menu_buttons: Dictionary = {}
var intro_video_layer: CanvasLayer
var intro_video_player: VideoStreamPlayer
var intro_video_active := false
var intro_video_generation := 0
var intro_start_gate: Control
var intro_title_lockup: Control
var intro_still_backdrop: Control
# Keep the title-card tween owned by the intro lifecycle. Skipping the movie
# used to free its layer while this local-capture callback was still pending.
var intro_title_tween: Tween

func _ready() -> void:
	# Browser displays commonly report 100/120/144 Hz. Rendering the tactical
	# SubViewport at that rate doubled CPU/GPU work without adding authored
	# animation frames and made WebAudio underruns much more likely during map
	# streaming. Preserve any lower user/platform cap, otherwise use stable 60 Hz.
	if OS.has_feature("web") and (Engine.max_fps <= 0 or Engine.max_fps > WEB_FRAME_RATE_CAP):
		Engine.max_fps = WEB_FRAME_RATE_CAP
	_build_root()
	EventBus.screen_changed.connect(_show_screen)
	var load_result := SaveService.load_game()
	print("SAVE_LOAD_SOURCE source=%s sandbox=%s session=%s" % [str(load_result.value) if load_result.ok else "new", str(SaveService.is_soak_sandbox_enabled()), str(SaveService.soak_sandbox_session)])
	# SaveService restores the player's normal preference after autoloads have
	# entered the tree. Re-apply the URL-only visual-QA mute here so a saved
	# audio-enabled value cannot restart BGM in the explicitly silent preview.
	SettingsService.apply_web_preview_audio_override()
	if SettingsService.web_preview_audio_forced_muted():
		AudioService.set_enabled(false)
	# A persistent save diagnostic belonged to the development shell.  Saving is
	# still atomic and reported by its own action feedback, but Release screens
	# must not expose a bottom-right implementation status.
	footer_status.visible = false
	_show_intro_video()

func _show_intro_video() -> void:
	intro_video_active = true
	intro_video_generation += 1
	var active_generation := intro_video_generation
	intro_video_layer = CanvasLayer.new()
	intro_video_layer.name = "StartupIntroVideoLayer"
	intro_video_layer.layer = 500
	add_child(intro_video_layer)

	var surface := Control.new()
	surface.name = "StartupIntroVideoSurface"
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# CanvasLayer breaks the ordinary Control theme ancestry. Bind the project
	# Noto Sans KR theme here so the Web audio gate never falls back to missing
	# browser glyphs for its Korean label and action.
	surface.theme = theme
	intro_video_layer.add_child(surface)

	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.add_child(black)
	var video_frame := AspectRatioContainer.new()
	video_frame.name = "StartupIntroAspectFrame"
	video_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video_frame.ratio = 16.0 / 9.0
	video_frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
	video_frame.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	video_frame.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	video_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(video_frame)

	intro_video_player = VideoStreamPlayer.new()
	intro_video_player.name = "StartupIntroVideoPlayer"
	intro_video_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_video_player.expand = true
	intro_video_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro_video_player.volume_db = -80.0 if not bool(SettingsService.values.get("audio_enabled", true)) else linear_to_db(clampf(float(SettingsService.values.get("master_volume", 0.8)), 0.01, 1.0))
	intro_video_player.finished.connect(_on_native_intro_finished)
	video_frame.add_child(intro_video_player)
	# The WebAudio consent frame is part of the title experience.  A
	# VideoStreamPlayer has no decoded frame before a trusted click, and some
	# file:// Web launches leave that empty surface black.  Keep the actual
	# high-resolution title cast visible in that interval rather than presenting
	# an orphaned logo and start button.
	_build_intro_title_backdrop(surface)

	var title_center := CenterContainer.new()
	title_center.name = "StartupIntroTitleCenter"
	# The title and the WebAudio action need separate bands.  The former full
	# screen center container allowed a large title card to visually collide with
	# the start control on narrow desktop browser panes.
	title_center.anchor_left = 0.055
	title_center.anchor_right = 0.49
	title_center.anchor_top = 0.22
	title_center.anchor_bottom = 0.62
	title_center.offset_left = 0.0
	title_center.offset_right = 0.0
	title_center.offset_top = 0.0
	title_center.offset_bottom = 0.0
	title_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(title_center)
	var title_lockup := PanelContainer.new()
	title_lockup.name = "StartupIntroTitleLockup"
	intro_title_lockup = title_lockup
	var intro_ui_scale := _responsive_control_scale()
	var intro_portrait := _is_portrait_layout()
	title_lockup.custom_minimum_size = (Vector2(340.0, 128.0) * intro_ui_scale) if intro_portrait else Vector2(640.0, 340.0)
	title_lockup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_panel_style := GameUI.panel_style(
		Color("050a11b8"),
		Color("e7bf6899"),
		roundi(1.0 * intro_ui_scale),
		roundi(float(GameUI.RADIUS_PANEL) * intro_ui_scale),
		Vector4(30.0, 18.0, 30.0, 18.0) * intro_ui_scale,
		10
	)
	title_lockup.add_theme_stylebox_override("panel", title_panel_style)
	title_center.add_child(title_lockup)
	title_lockup.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var title_words := preload("res://screens/command_presentation.gd").label(self, "LUMEN\nBOUND", 106, Color("effaf7"))
	title_lockup.add_child(title_words)
	var skip := preload("res://screens/command_presentation.gd").button(self, "SKIP", _finish_intro_video, false, Vector2(190.0, 72.0))
	skip.name = "StartupIntroSkipButton"
	skip.tooltip_text = "인트로 영상 건너뛰기"
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -skip.custom_minimum_size.x - (24.0 * intro_ui_scale)
	skip.offset_top = 24.0 * intro_ui_scale
	skip.offset_right = -24.0 * intro_ui_scale
	skip.offset_bottom = skip.offset_top + skip.custom_minimum_size.y
	skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	surface.add_child(skip)

	# Public Web builds stream the reviewed 1080p MP4 from the Sites static
	# asset. Keep the native OGV fallback for desktop exports, but do not make
	# the browser startup depend on the duplicate 68 MiB embedded stream.
	if not OS.has_feature("web"):
		var stream := load(INTRO_VIDEO_PATH) as VideoStream
		if stream == null:
			push_error("Startup intro video could not be loaded: %s" % INTRO_VIDEO_PATH)
			_finish_intro_video()
			return
		intro_video_player.stream = stream
	var web_audio_needs_gesture := OS.has_feature("web") and bool(SettingsService.values.get("audio_enabled", true)) and not SettingsService.web_preview_audio_forced_muted()
	if web_audio_needs_gesture:
		_build_intro_audio_gate(active_generation, surface)
	else:
		_start_intro_video_playback(active_generation)

func _build_intro_audio_gate(active_generation: int, surface: Control) -> void:
	# Browsers intentionally block audible autoplay. Starting the movie muted and
	# trying to resume it later loses the opening soundtrack. Hold frame zero until
	# one trusted click/tap, unlock WebAudio in that callback, then start both video
	# and audio together from the beginning.
	intro_start_gate = PanelContainer.new()
	intro_start_gate.name = "StartupIntroAudioGate"
	intro_start_gate.anchor_left = 0.25
	intro_start_gate.anchor_right = 0.25
	intro_start_gate.anchor_top = 0.78
	intro_start_gate.anchor_bottom = 0.78
	intro_start_gate.offset_left = -220.0
	intro_start_gate.offset_right = 220.0
	intro_start_gate.offset_top = -76.0
	intro_start_gate.offset_bottom = 76.0
	intro_start_gate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	intro_start_gate.grow_vertical = Control.GROW_DIRECTION_BOTH
	intro_start_gate.mouse_filter = Control.MOUSE_FILTER_STOP
	intro_start_gate.add_theme_stylebox_override("panel", GameUI.panel_style(Color("071521ec"), Color("74e1d4c8"), 1, GameUI.RADIUS_MODAL, Vector4(20.0, 14.0, 20.0, 14.0), 12))
	surface.add_child(intro_start_gate)
	var gate_box := VBoxContainer.new()
	gate_box.alignment = BoxContainer.ALIGNMENT_CENTER
	gate_box.add_theme_constant_override("separation", 5)
	intro_start_gate.add_child(gate_box)
	var gate_label := Label.new()
	gate_label.name = "StartupIntroAudioGateLabel"
	gate_label.text = "꺼진 노선 위에서, 다시 빛을 잇다."
	gate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gate_label.add_theme_color_override("font_color", GameUI.TEXT)
	gate_label.add_theme_font_size_override("font_size", 25)
	gate_box.add_child(gate_label)
	var gate_hint := Label.new()
	gate_hint.name = "StartupIntroAudioGateHint"
	gate_hint.text = "50초의 프롤로그"
	gate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gate_hint.add_theme_color_override("font_color", GameUI.TEXT_MUTED)
	gate_hint.add_theme_font_size_override("font_size", 16)
	gate_box.add_child(gate_hint)
	var start_button := preload("res://screens/command_presentation.gd").button(self, "영상으로 시작  ›", _start_intro_video_playback.bind(active_generation), false, Vector2(350.0, 64.0))
	start_button.name = "StartupIntroAudioStartButton"
	GameUI.apply_button(start_button, "primary")
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	gate_box.add_child(start_button)
	start_button.grab_focus()

func _build_intro_title_backdrop(surface: Control) -> void:
	intro_still_backdrop = Control.new()
	intro_still_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_still_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(intro_still_backdrop)
	preload("res://screens/command_presentation.gd").title_backdrop(self, intro_still_backdrop)

func _start_intro_video_playback(active_generation: int) -> void:
	if not intro_video_active or active_generation != intro_video_generation or intro_video_player == null:
		return
	# The replacement movie already contains the original intro soundtrack.
	# Replaying it from the title must not layer lobby music over that track.
	AudioService.stop_bgm()
	AudioService.unlock_from_user_gesture()
	if intro_start_gate != null and is_instance_valid(intro_start_gate):
		intro_start_gate.queue_free()
	intro_start_gate = null
	if OS.has_feature("web"):
		JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/browser_intro.js"), true)
		var intro_volume := float(SettingsService.values.get("master_volume", 0.8)) if bool(SettingsService.values.get("audio_enabled", true)) else 0.0
		JavaScriptBridge.eval("window.__lumenIntro.start('/intro.mp4', %s)" % str(intro_volume), true)
		_watch_browser_intro(active_generation)
	else:
		intro_video_player.play()
		_watch_native_intro(active_generation)
	if intro_still_backdrop != null and is_instance_valid(intro_still_backdrop):
		var backdrop_to_release := intro_still_backdrop
		var backdrop_fade := create_tween()
		backdrop_fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		backdrop_fade.tween_property(backdrop_to_release, "modulate:a", 0.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		backdrop_fade.tween_callback(_queue_free_if_valid.bind(backdrop_to_release))
	intro_still_backdrop = null
	if intro_title_lockup != null and is_instance_valid(intro_title_lockup):
		var title_parent := intro_title_lockup.get_parent()
		intro_title_tween = create_tween()
		intro_title_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		intro_title_tween.tween_interval(0.0)
		intro_title_tween.tween_property(intro_title_lockup, "modulate:a", 0.0, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		intro_title_tween.tween_callback(_queue_free_if_valid.bind(title_parent))

func _watch_browser_intro(generation: int) -> void:
	while is_inside_tree() and intro_video_active and generation == intro_video_generation:
		await get_tree().create_timer(0.2).timeout
		if bool(JavaScriptBridge.eval("Boolean(window.__lumenIntro && window.__lumenIntro.done)", true)):
			_finish_intro_video()
			return

func _watch_native_intro(generation: int) -> void:
	while is_inside_tree() and intro_video_active and generation == intro_video_generation:
		await get_tree().create_timer(0.2).timeout
		if not is_instance_valid(intro_video_player): return
		# Elapsed wall time is not playback time (loading, pause, focus loss).
		if intro_video_player.stream_position >= INTRO_VIDEO_DURATION_SECONDS - 0.04:
			_finish_intro_video()
			return

func _on_native_intro_finished() -> void:
	# The stream's own end signal is authoritative; no wall-clock cutoff.
	_finish_intro_video()

func _finish_intro_video() -> void:
	if not intro_video_active:
		return
	intro_video_active = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.__lumenIntro) window.__lumenIntro.stop()", true)
	intro_video_generation += 1
	if intro_title_tween != null and intro_title_tween.is_valid():
		intro_title_tween.kill()
	intro_title_tween = null
	intro_title_lockup = null
	intro_start_gate = null
	intro_still_backdrop = null
	if intro_video_player != null:
		intro_video_player.stop()
	intro_video_player = null
	if intro_video_layer != null:
		intro_video_layer.queue_free()
	intro_video_layer = null
	_show_screen("TITLE")

# Untyped on purpose: a skipped intro can free the node before the fade's
# callback runs, and a typed Node argument rejects the freed instance.
func _queue_free_if_valid(node) -> void:
	if is_instance_valid(node):
		node.queue_free()

func _build_root() -> void:
	var background := ColorRect.new()
	background.color = Color("080b12")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var background_art := TextureRect.new()
	background_art.name = "R6BackgroundArt"
	background_art.texture = load("res://assets/art/backgrounds/BG_STORY_RELAY/bg_story_relay_1920x1080.png") as Texture2D
	background_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background_art.modulate = Color(0.34, 0.42, 0.52, 0.42)
	background_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background_art)
	var background_scrim := ColorRect.new()
	background_scrim.color = Color("080b1288")
	background_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background_scrim)
	safe_margin = MarginContainer.new()
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		safe_margin.add_theme_constant_override(side, 32)
	add_child(safe_margin)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	safe_margin.add_child(content)
	# Keep the expensive 3D chapter world alive while battle and reward UI are
	# shown.  The cache host is hidden and processing-disabled, so it costs no draw
	# work; returning to the map reuses the existing terrain/props instead of
	# destroying and reconstructing hundreds of Web nodes.
	chapter_map_cache_host = Control.new()
	chapter_map_cache_host.name = "ChapterMapCacheHost"
	chapter_map_cache_host.visible = false
	chapter_map_cache_host.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(chapter_map_cache_host)
	get_window().size_changed.connect(_on_window_size_changed)
	_apply_safe_area()
	# Browser viewport changes do not always emit Godot's window-size signal.
	# Establish the initial responsive state now; _process also probes at a small
	# cadence so a live battle presentation can reflow without restarting it.
	last_portrait_layout = _is_portrait_layout()
	last_compact_landscape_layout = _is_compact_landscape_layout()
	footer_status = Label.new()
	footer_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer_status.modulate = Color("88a4c9")
	footer_status.text = "오프라인 탐색 기록"
	footer_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer_status.position.y = -34
	add_child(footer_status)
	theme = _make_theme()
	_build_viewport_gate()

func _begin_transition_loading(kind_value: String) -> int:
	# This overlay belongs to screen-owner replacement only. ChapterMap never
	# calls it for pawn movement, enemy turns, or treasure presentation, so those
	# responsive interactions cannot accidentally acquire a loading gate.
	_dispose_transition_loading()
	transition_loading_generation += 1
	transition_loading_active_token = transition_loading_generation
	transition_loading_kind = kind_value
	transition_loading_phase_start_value = 0.0
	transition_loading_phase_target_value = 0.0
	transition_loading_phase_started_msec = Time.get_ticks_msec()
	transition_loading_phase_duration_msec = 1

	transition_loading_layer = CanvasLayer.new()
	transition_loading_layer.name = "TransitionLoadingLayer"
	transition_loading_layer.layer = 400
	add_child(transition_loading_layer)
	transition_loading_surface = Control.new()
	transition_loading_surface.name = "TransitionLoadingSurface"
	transition_loading_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_loading_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	# CanvasLayer does not inherit AppShell's project font/theme automatically.
	# Explicit inheritance keeps Korean status copy identical on desktop and Web.
	transition_loading_surface.theme = theme
	transition_loading_surface.set_meta("transition_kind", kind_value)
	transition_loading_surface.set_meta("transition_token", transition_loading_active_token)
	transition_loading_layer.add_child(transition_loading_surface)

	var art := TextureRect.new()
	art.name = "TransitionLoadingArtwork"
	art.texture = load(TRANSITION_LOADING_ART_PATH) as Texture2D
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(0.48, 0.63, 0.70, 0.88)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_loading_surface.add_child(art)
	var scrim := ColorRect.new()
	scrim.name = "TransitionLoadingScrim"
	# Map construction creates a live SubViewport underneath this owner. Keep the
	# map-entry scrim nearly opaque so an incomplete fog/terrain frame can never
	# leak through as a blank tactical map; battle/result retain their lighter
	# contextual artwork treatment.
	scrim.color = Color("020710f4") if kind_value == TRANSITION_LOADING_MAP_ENTRY else Color("030811c7")
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_loading_surface.add_child(scrim)

	transition_loading_panel = PanelContainer.new()
	transition_loading_panel.name = "TransitionLoadingPanel"
	transition_loading_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_loading_panel.add_theme_stylebox_override("panel", GameUI.panel_style(
		Color("07131fe8"),
		Color("79e7d5c8"),
		1,
		GameUI.RADIUS_MODAL,
		Vector4(30.0, 22.0, 30.0, 24.0),
		16
	))
	var loading_center := CenterContainer.new()
	loading_center.name = "TransitionLoadingCenter"
	loading_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_loading_surface.add_child(loading_center)
	loading_center.add_child(transition_loading_panel)
	var column := VBoxContainer.new()
	column.name = "LoadingColumn"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_loading_panel.add_child(column)

	var logo := TextureRect.new()
	logo.name = "BrandLogo"
	logo.texture = load(TRANSITION_LOADING_LOGO_PATH) as Texture2D
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(logo)
	transition_loading_title_label = Label.new()
	transition_loading_title_label.name = "TransitionLoadingTitle"
	transition_loading_title_label.text = _transition_loading_title(kind_value)
	transition_loading_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transition_loading_title_label.add_theme_color_override("font_color", GameUI.TEXT)
	var title_font := GameUI.weighted_font(interface_font, 720.0, 0.04)
	if title_font != null:
		transition_loading_title_label.add_theme_font_override("font", title_font)
	column.add_child(transition_loading_title_label)
	transition_loading_phase_label = Label.new()
	transition_loading_phase_label.name = "TransitionLoadingPhase"
	transition_loading_phase_label.text = _transition_loading_initial_phase(kind_value)
	transition_loading_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transition_loading_phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	transition_loading_phase_label.add_theme_color_override("font_color", GameUI.TEXT_MUTED)
	column.add_child(transition_loading_phase_label)

	transition_loading_progress_bar = ProgressBar.new()
	transition_loading_progress_bar.name = "TransitionLoadingProgressBar"
	transition_loading_progress_bar.min_value = 0.0
	transition_loading_progress_bar.max_value = 100.0
	transition_loading_progress_bar.value = 0.0
	transition_loading_progress_bar.show_percentage = false
	transition_loading_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_loading_progress_bar.tooltip_text = "Current transition progress"
	var bar_background := StyleBoxFlat.new()
	bar_background.bg_color = Color("020810")
	bar_background.border_color = Color("8aaabd55")
	bar_background.set_border_width_all(1)
	bar_background.set_corner_radius_all(GameUI.RADIUS_CONTROL)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = GameUI.SIGNAL
	bar_fill.border_color = Color("c9fff5")
	bar_fill.set_border_width_all(1)
	bar_fill.set_corner_radius_all(GameUI.RADIUS_CONTROL)
	transition_loading_progress_bar.add_theme_stylebox_override("background", bar_background)
	transition_loading_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	column.add_child(transition_loading_progress_bar)
	transition_loading_percent_label = Label.new()
	transition_loading_percent_label.name = "TransitionLoadingPercent"
	transition_loading_percent_label.text = "0%"
	transition_loading_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	transition_loading_percent_label.add_theme_color_override("font_color", GameUI.OBJECTIVE)
	var percent_font := GameUI.weighted_font(interface_font, 680.0, 0.03)
	if percent_font != null:
		transition_loading_percent_label.add_theme_font_override("font", percent_font)
	column.add_child(transition_loading_percent_label)
	_apply_transition_loading_layout()
	_set_transition_loading_display_value(0.0)
	return transition_loading_active_token

func _transition_loading_title(kind_value: String) -> String:
	match kind_value:
		TRANSITION_LOADING_BATTLE_ENTRY:
			return "전투 준비 중"
		TRANSITION_LOADING_BATTLE_RESULT:
			return "전투 결과 정리 중"
		_:
			return "전술 지도 준비 중"

func _transition_loading_initial_phase(kind_value: String) -> String:
	match kind_value:
		TRANSITION_LOADING_BATTLE_ENTRY:
			return "곧 전투가 시작됩니다"
		TRANSITION_LOADING_BATTLE_RESULT:
			return "전리품과 성장 결과를 확인하고 있습니다"
		_:
			return "작전 정보를 준비하고 있습니다"

func _apply_transition_loading_layout() -> void:
	if transition_loading_panel == null or not is_instance_valid(transition_loading_panel):
		return
	var ui_scale := GameUI.typography_scale(_runtime_layout_size())
	# The center container measures the content before placing the panel. A
	# lower-screen anchor allowed the minimum content height to escape the screen.
	transition_loading_panel.custom_minimum_size = Vector2(1120.0, 0.0)
	var column := transition_loading_panel.get_node_or_null("LoadingColumn") as VBoxContainer
	if column != null:
		column.add_theme_constant_override("separation", roundi(10.0 * ui_scale))
		var logo := column.get_node_or_null("BrandLogo") as TextureRect
		if logo != null:
			logo.custom_minimum_size = Vector2(270.0, 66.0) * ui_scale
	if transition_loading_title_label != null:
		transition_loading_title_label.add_theme_font_size_override("font_size", roundi(30.0 * ui_scale))
	if transition_loading_phase_label != null:
		transition_loading_phase_label.add_theme_font_size_override("font_size", roundi(18.0 * ui_scale))
	if transition_loading_progress_bar != null:
		transition_loading_progress_bar.custom_minimum_size = Vector2(0.0, 18.0 * ui_scale)
	if transition_loading_percent_label != null:
		transition_loading_percent_label.add_theme_font_size_override("font_size", roundi(17.0 * ui_scale))

func _transition_loading_token_for(kind_value: String) -> int:
	if transition_loading_kind != kind_value or not _transition_loading_token_is_valid(transition_loading_active_token):
		return 0
	return transition_loading_active_token

func _transition_loading_token_is_valid(token: int) -> bool:
	return token > 0 \
		and token == transition_loading_active_token \
		and transition_loading_layer != null \
		and is_instance_valid(transition_loading_layer) \
		and transition_loading_surface != null \
		and is_instance_valid(transition_loading_surface)

func _set_transition_loading_phase(token: int, phase_text: String, target_value: float, duration_seconds := 0.24) -> void:
	if not _transition_loading_token_is_valid(token):
		return
	# Reaching this call means the prior real setup phase completed. Commit its
	# target before opening the next timed segment; progress is therefore a true
	# sequence of completed work, with time-based fill only inside that segment.
	_set_transition_loading_display_value(transition_loading_phase_target_value)
	transition_loading_phase_start_value = transition_loading_phase_target_value
	transition_loading_phase_target_value = clampf(maxf(transition_loading_phase_start_value, target_value), 0.0, TRANSITION_LOADING_MAX_PHASE_VALUE)
	transition_loading_phase_started_msec = Time.get_ticks_msec()
	transition_loading_phase_duration_msec = maxi(1, roundi(duration_seconds * 1000.0))
	if transition_loading_phase_label != null and is_instance_valid(transition_loading_phase_label):
		transition_loading_phase_label.text = _transition_loading_initial_phase(transition_loading_kind)

func _update_transition_loading_progress() -> void:
	if not _transition_loading_token_is_valid(transition_loading_active_token) or transition_loading_progress_bar == null:
		return
	var elapsed_msec := maxi(0, Time.get_ticks_msec() - transition_loading_phase_started_msec)
	var phase_ratio := clampf(float(elapsed_msec) / float(transition_loading_phase_duration_msec), 0.0, 1.0)
	# Ease only the visual readout; targets are raised exclusively by completed
	# setup phases, so the bar never loops or pretends an unfinished phase passed.
	var eased_ratio := phase_ratio * phase_ratio * (3.0 - 2.0 * phase_ratio)
	_set_transition_loading_display_value(lerpf(transition_loading_phase_start_value, transition_loading_phase_target_value, eased_ratio))

func _set_transition_loading_display_value(value: float) -> void:
	if transition_loading_progress_bar == null or not is_instance_valid(transition_loading_progress_bar):
		return
	var clamped_value := clampf(value, 0.0, 100.0)
	transition_loading_progress_bar.value = clamped_value
	if transition_loading_percent_label != null and is_instance_valid(transition_loading_percent_label):
		transition_loading_percent_label.text = "%d%%" % roundi(clamped_value)

func _stage_asset_cache_phase_text(phase: String) -> String:
	if phase.begins_with("MAP_ACTOR_MANIFEST"):
		return "맵 캐릭터 정보를 확인하고 있습니다"
	if phase.begins_with("MAP_ACTOR_ATLAS"):
		return "맵 캐릭터 동작을 준비하고 있습니다"
	if phase == "MAP_READY":
		return "맵 캐릭터 준비를 마쳤습니다"
	if phase.begins_with("ACTOR_MANIFEST"):
		return "Reading character animation data"
	if phase.begins_with("ACTOR_ATLAS"):
		return "Caching character animations"
	if phase.begins_with("PROJECTILE_MANIFEST"):
		return "Reading skill projectile data"
	if phase.begins_with("PROJECTILE_ATLAS"):
		return "Caching skill projectiles"
	if phase.begins_with("PREVIEW"):
		return "Preparing combat fallback art"
	if phase.begins_with("VFX"):
		return "Caching cast, travel, and impact effects"
	if phase in ["BATTLE_BACKGROUND", "BOSS_BACKGROUND"]:
		return "Preparing battle environments"
	if phase == "BATTLE_FONT":
		return "Preparing battle interface type"
	if phase == "READY":
		return "Combat resource cache ready"
	return "작전 자원을 확인하고 있습니다"

func _on_stage_asset_cache_progress(value: float, phase: String, token: int) -> void:
	if not _transition_loading_token_is_valid(token):
		return
	var target := lerpf(14.0, 48.0, clampf(value, 0.0, 1.0))
	_set_transition_loading_phase(token, _stage_asset_cache_phase_text(phase), target, 0.08)

func _map_load_phase_text(phase: String) -> String:
	match phase:
		"map_data":
			return "탐색 기록을 불러오고 있습니다"
		"shell":
			return "전술 지도 화면을 준비하고 있습니다"
		"terrain":
			return "지형과 높낮이를 구성하고 있습니다"
		"terrain_dressing":
			return "숲과 길, 바위 지형을 배치하고 있습니다"
		"map_presentation":
			return "조우와 보급 지점을 배치하고 있습니다"
		"unlocked_enemies":
			return "공개된 적과 순찰을 배치하고 있습니다"
		"route_water":
			return "강과 경로를 마무리하고 있습니다"
		"ready":
			return "전술 지도 조작을 활성화하고 있습니다"
		_:
			return "전술 지도를 준비하고 있습니다"

func _on_chapter_map_load_progress(value: float, phase: String, token: int, show_generation: int) -> void:
	if current_screen != "STAGE_SELECT" or show_generation != chapter_map_show_generation:
		return
	if not _transition_loading_token_is_valid(token):
		return
	map_load_last_progress_msec = Time.get_ticks_msec()
	var target := lerpf(56.0, 96.0, clampf(value, 0.0, 1.0))
	_set_transition_loading_phase(token, _map_load_phase_text(phase), target, 0.10)

func _warm_transition_gpu_textures(token: int, textures: Array[Texture2D]) -> int:
	# ResourceLoader keeps decoded images alive, but WebGL performs the first GPU
	# upload only when a texture is actually drawn. Paint one tiny, non-interactive
	# sample per renderer frame under the already-visible loading layer so movement,
	# treasure pickup and combat never inherit that upload hitch later.
	if textures.is_empty() or not _transition_loading_token_is_valid(token):
		return 0
	# Submit a small texture batch in each draw instead of forcing one complete
	# renderer frame per backing image. The former 58-frame pass added a full
	# second of artificial loading even on an otherwise idle browser.
	var warm_rects: Array[TextureRect] = []
	for rect_index in range(mini(TRANSITION_GPU_WARM_BATCH, textures.size())):
		var warm_rect := TextureRect.new()
		warm_rect.name = "TransitionGpuWarmTexture_%02d" % rect_index
		warm_rect.position = Vector2(float(rect_index) * 2.0, 0.0)
		warm_rect.size = Vector2(2.0, 2.0)
		warm_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		warm_rect.stretch_mode = TextureRect.STRETCH_SCALE
		warm_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		warm_rect.modulate = Color(1.0, 1.0, 1.0, 0.015)
		transition_loading_surface.add_child(warm_rect)
		warm_rects.append(warm_rect)
	var warmed := 0
	for batch_start in range(0, textures.size(), TRANSITION_GPU_WARM_BATCH):
		if not _transition_loading_token_is_valid(token):
			break
		var batch_end := mini(batch_start + TRANSITION_GPU_WARM_BATCH, textures.size())
		for rect_index in range(warm_rects.size()):
			var texture_index := batch_start + rect_index
			warm_rects[rect_index].texture = textures[texture_index] if texture_index < batch_end else null
			warm_rects[rect_index].queue_redraw()
		await RenderingServer.frame_post_draw
		warmed = batch_end
		var ratio := float(warmed) / float(maxi(1, textures.size()))
		_set_transition_loading_phase(token, "맵 캐릭터 텍스처를 준비하고 있습니다", lerpf(48.0, 56.0, ratio), 0.04)
	for warm_rect in warm_rects:
		if is_instance_valid(warm_rect):
			warm_rect.queue_free()
	return warmed

func _finish_transition_loading(token: int, final_phase := "Ready") -> void:
	if not _transition_loading_token_is_valid(token):
		return
	if transition_loading_phase_label != null and is_instance_valid(transition_loading_phase_label):
		transition_loading_phase_label.text = final_phase
	transition_loading_phase_start_value = 100.0
	transition_loading_phase_target_value = 100.0
	_set_transition_loading_display_value(100.0)
	# Hold the completed state briefly so 100% is actually painted before the
	# owner layer closes. This delay occurs only after the new screen is ready.
	await get_tree().create_timer(0.10, true, false, true).timeout
	if _transition_loading_token_is_valid(token):
		_dispose_transition_loading()

func _cancel_transition_loading(token := 0) -> void:
	if token > 0 and token != transition_loading_active_token:
		return
	transition_loading_generation += 1
	_dispose_transition_loading()

func _dispose_transition_loading() -> void:
	if transition_loading_layer != null and is_instance_valid(transition_loading_layer):
		transition_loading_layer.visible = false
		transition_loading_layer.queue_free()
	transition_loading_layer = null
	transition_loading_surface = null
	transition_loading_panel = null
	transition_loading_progress_bar = null
	transition_loading_percent_label = null
	transition_loading_phase_label = null
	transition_loading_title_label = null
	transition_loading_active_token = 0
	transition_loading_kind = ""
	transition_loading_phase_start_value = 0.0
	transition_loading_phase_target_value = 0.0

static func loading_watchdog_expired(now_msec: int, started_msec: int, last_progress_msec: int) -> bool:
	return now_msec - started_msec >= LOADING_HARD_TIMEOUT_MSEC or now_msec - last_progress_msec >= LOADING_IDLE_TIMEOUT_MSEC

func _wait_for_map_ready_with_deadline(map_screen: Control, started_msec: int, show_generation: int) -> bool:
	# Five seconds is a measured target, not proof of failure on a slow phone.
	map_load_last_progress_msec = Time.get_ticks_msec()
	while map_screen != null and is_instance_valid(map_screen) \
		and current_screen == "STAGE_SELECT" and show_generation == chapter_map_show_generation:
		if bool(map_screen.get("map_ready_complete")):
			return true
		if loading_watchdog_expired(Time.get_ticks_msec(), started_msec, map_load_last_progress_msec):
			return false
		await get_tree().process_frame
	return false

func _wait_for_battle_assets_with_deadline(view: BattleView, started_msec: int) -> bool:
	var last_phase := ""
	var last_progress_msec := Time.get_ticks_msec()
	while view != null and is_instance_valid(view) and current_screen == "BATTLE":
		if view.assets_ready:
			return true
		if view.asset_warmup_phase != last_phase:
			last_phase = view.asset_warmup_phase
			last_progress_msec = Time.get_ticks_msec()
		if loading_watchdog_expired(Time.get_ticks_msec(), started_msec, last_progress_msec):
			return false
		await get_tree().process_frame
	return false

func _show_loading_failure_screen(title_text: String, detail_text: String, retry_screen: String, allow_safe_list := false) -> void:
	StageAssetCache.cancel_warmup()
	_cancel_transition_loading()
	_clear()
	_title(title_text, detail_text)
	var panel := PanelContainer.new()
	panel.name = "LoadingFailurePanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", GameUI.panel_style(Color("07131ff2"), Color("f1c75b"), 1, GameUI.RADIUS_MODAL, Vector4(28, 24, 28, 28), 14))
	content.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	column.add_child(_label("LOADING COULD NOT FINISH", 34, Color("f1c75b")))
	column.add_child(_label(detail_text, 22, GameUI.TEXT_MUTED))
	column.add_child(_button("RETRY", func(): _show_screen(retry_screen), false, Vector2(280, 68)))
	if allow_safe_list:
		column.add_child(_button("OPEN SAFE STAGE LIST", func(): SceneRouter.go("STAGE_LIST_FALLBACK"), false, Vector2(360, 68)))
	elif retry_screen == "BATTLE":
		column.add_child(_button("RETURN TO TACTICAL MAP", func(): SceneRouter.go("STAGE_SELECT"), false, Vector2(360, 68)))

func _dispose_transaction_save_failure() -> void:
	if transaction_save_failure_layer != null and is_instance_valid(transaction_save_failure_layer):
		transaction_save_failure_layer.queue_free()
	transaction_save_failure_layer = null

func _present_transaction_save_failure(title_text: String, error_text: String, after_saved: Callable) -> void:
	_dispose_transaction_save_failure()
	transaction_save_failure_layer = CanvasLayer.new()
	transaction_save_failure_layer.name = "TransactionSaveFailureLayer"
	transaction_save_failure_layer.layer = 430
	add_child(transaction_save_failure_layer)
	var surface := Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.theme = theme
	transaction_save_failure_layer.add_child(surface)
	var dimmer := ColorRect.new()
	dimmer.color = Color("020710e8")
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.add_child(dimmer)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.18
	panel.anchor_right = 0.82
	panel.anchor_top = 0.28
	panel.anchor_bottom = 0.72
	panel.add_theme_stylebox_override("panel", GameUI.panel_style(Color("081725fa"), Color("f1c75b"), 1, GameUI.RADIUS_MODAL, Vector4(30, 26, 30, 28), 16))
	surface.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	column.add_child(_label(title_text, 34, Color("f1c75b")))
	var detail := _label("Progress is still held in memory. Retry the save before leaving this screen.\n%s" % error_text, 20, GameUI.TEXT_MUTED)
	detail.name = "TransactionSaveFailureDetail"
	column.add_child(detail)
	column.add_child(_button("RETRY SAVE", func() -> void:
		var retry_result := SaveService.save_game()
		if retry_result.ok:
			_dispose_transaction_save_failure()
			if after_saved.is_valid():
				after_saved.call()
		else:
			detail.text = "Progress is still held in memory. Retry the save before leaving this screen.\n%s" % retry_result.error
	, false, Vector2(300, 70)))

func _should_show_map_transition_loading(previous_screen: String) -> bool:
	if previous_screen == "STAGE_SELECT":
		return false
	if previous_screen == "RESULT":
		# Treasure/result presentation is lightweight and intentionally continuous:
		# it must return to the map without ever constructing this blocking layer.
		var source_type := str(last_reward_report.get("source_type", "")).to_upper()
		if source_type in ["TREASURE", "EXPLORE"]:
			return false
	return true

func _prepare_transition_loading_for_screen(previous_screen: String, next_screen: String) -> void:
	match next_screen:
		"STAGE_SELECT":
			if _should_show_map_transition_loading(previous_screen):
				if _transition_loading_token_for(TRANSITION_LOADING_MAP_ENTRY) == 0:
					_begin_transition_loading(TRANSITION_LOADING_MAP_ENTRY)
			elif transition_loading_active_token > 0:
				_cancel_transition_loading()
		"BATTLE":
			if _transition_loading_token_for(TRANSITION_LOADING_BATTLE_ENTRY) == 0:
				_begin_transition_loading(TRANSITION_LOADING_BATTLE_ENTRY)
		"RESULT":
			# Only a finished live battle owns BATTLE_RESULT. Treasure and sweep
			# routes arrive without a token and therefore never instantiate an overlay.
			if _transition_loading_token_for(TRANSITION_LOADING_BATTLE_RESULT) == 0 and transition_loading_active_token > 0:
				_cancel_transition_loading()
		_:
			if transition_loading_active_token > 0:
				_cancel_transition_loading()

func _make_theme() -> Theme:
	var ui_scale := GameUI.typography_scale(_runtime_layout_size())
	# The earlier subset deliberately reduced the Web payload, but it omitted
	# glyphs introduced by localized reward names.  Use the project-owned OFL
	# variable font so every Korean runtime string remains readable.
	var bundled_font := load("res://assets/fonts/LanternSans-Medium.ttf") as Font
	if bundled_font != null:
		interface_font = bundled_font
	return GameUI.build_theme(bundled_font, ui_scale)

func _build_viewport_gate() -> void:
	# Landscape is shown at every window shape; no rotation overlay is created.
	pass

func _update_viewport_gate() -> void:
	if orientation_forced_pause:
		if battle_view != null: battle_view.paused = false
		orientation_forced_pause = false

func _on_window_size_changed() -> void:
	_refresh_responsive_shell_metrics()
	var portrait := _is_portrait_layout()
	_queue_orientation_reflow_if_needed(portrait, _is_compact_landscape_layout())

func _refresh_responsive_shell_metrics() -> void:
	_apply_safe_area()
	_apply_transition_loading_layout()
	if theme != null:
		var ui_scale := GameUI.typography_scale(_runtime_layout_size())
		theme.default_font_size = roundi(22.0 * ui_scale)
		theme.set_font_size("font_size", "Button", roundi(20.0 * ui_scale))
		theme.set_font_size("font_size", "Label", roundi(22.0 * ui_scale))
		theme.set_font_size("normal_font_size", "RichTextLabel", roundi(21.0 * ui_scale))
		theme.set_font_size("bold_font_size", "RichTextLabel", roundi(21.0 * ui_scale))

func _queue_orientation_reflow_if_needed(portrait := _is_portrait_layout(), compact_landscape := _is_compact_landscape_layout()) -> void:
	if (portrait == last_portrait_layout and compact_landscape == last_compact_landscape_layout) or layout_refresh_queued:
		return
	last_portrait_layout = portrait
	last_compact_landscape_layout = compact_landscape
	layout_refresh_queued = true
	call_deferred("_refresh_orientation_layout")

func _refresh_orientation_layout() -> void:
	layout_refresh_queued = false
	# Web browsers can change innerWidth/innerHeight before forwarding Godot's
	# resize signal. Refresh the shell metrics here as well, otherwise portrait
	# font overrides remain scaled after rotating back to landscape.
	_refresh_responsive_shell_metrics()
	# The live battle simulation must never be reconstructed merely because a
	# handset rotated. Rebuild only its presentation controls around the existing
	# BattleView/Simulation so ticks, RNG, and commands remain intact.
	if current_screen == "BATTLE" and battle_view != null and battle_view.simulation != null:
		_rebuild_battle_overlay()
		return
	# Unlike a static menu, story rotation can happen midway through an unread
	# line or while a choice is open.  Rebuild only the presentation tree while
	# retaining the live ScenarioRunner, so portrait gets its intended readable
	# metrics without advancing, replaying, or checkpointing the narrative.
	if current_screen == "STORY" and scenario_runner != null:
		_rebuild_story_presentation()
		return
	# ChapterMap owns a live SubViewport and streamed terrain. Rebuilding the whole
	# screen on a phone rotation caused a second map load and visible transition
	# hitch; its own responsive method can reflow the same instance safely.
	if current_screen == "STAGE_SELECT" and active_chapter_map_screen != null and is_instance_valid(active_chapter_map_screen):
		_rebuild_chapter_map_header()
		active_chapter_map_screen.call("_apply_responsive_layout")
		_apply_chapter_map_shell_overrides()
		return
	# The chapter map stores only stable map state in AppState/SaveService, so it
	# can be rebuilt on a rotation without changing traversal, rewards, or battle
	# state. Rebuilding clears portrait-only control overrides before landscape.
	if current_screen in ["HOME", "TITLE", "RESULT", "ROSTER", "GROWTH", "CHARACTER_DETAIL", "INVENTORY", "ARCHIVE", "SETTINGS", "DEBUG", "LICENSE", "STAGE_DETAIL", "FORMATION"]:
		_show_screen(current_screen)

func _rebuild_chapter_map_header() -> void:
	# Recreate only the two shell decorations. The terrain SubViewport, moving
	# squad, map selection and simulation remain the same live instances.
	for node_name in ["ScreenHeader", "ScreenHeaderAccent"]:
		var old := content.get_node_or_null(NodePath(node_name))
		if old != null:
			content.remove_child(old)
			old.queue_free()
	var stage := DataRegistry.stage(AppState.selected_stage_id)
	var chapter := DataRegistry.chapter(str(stage.get("chapter_id", "CH01")))
	content.add_theme_constant_override("separation", 16)
	_title(LocalizationService.tr_key(str(chapter.get("name_key", ""))), "탐색 경로를 따라 조우를 선택하고, 기존 실시간 전투에 진입합니다.")
	content.move_child(content.get_node("ScreenHeader"), 0)
	content.move_child(content.get_node("ScreenHeaderAccent"), 1)

func _is_portrait_layout() -> bool:
	var size := _runtime_layout_size()
	return size.y > size.x

func _runtime_layout_size() -> Vector2:
	var window_size := DisplayServer.window_get_size()
	var width := float(window_size.x)
	var height := float(window_size.y)
	if OS.has_feature("web"):
		var browser_width = JavaScriptBridge.eval("window.innerWidth", true)
		var browser_height = JavaScriptBridge.eval("window.innerHeight", true)
		if browser_width is int or browser_width is float: width = float(browser_width)
		if browser_height is int or browser_height is float: height = float(browser_height)
	return GameUI.landscape_layout_size(Vector2(width, height))

func responsive_ui_metrics_for_size(size: Vector2) -> Dictionary:
	# The landscape composition uses the smaller layout/design ratio.
	# Compact phones therefore need the inverse ratio applied to UI metrics or a
	# nominal 56 logical-pixel button can collapse to about 21 CSS px at 915x412.
	var safe_size := GameUI.landscape_layout_size(size)
	var portrait := safe_size.y > safe_size.x
	var compact_landscape := not portrait and safe_size.x <= COMPACT_LANDSCAPE_MAX_WIDTH
	var canvas_scale := minf(safe_size.x / DESIGN_VIEWPORT_SIZE.x, safe_size.y / DESIGN_VIEWPORT_SIZE.y)
	canvas_scale = maxf(canvas_scale, 0.001)
	var ui_scale := 1.0
	if portrait:
		ui_scale = clampf(1.0 / canvas_scale, 2.8, 4.9)
	elif compact_landscape:
		ui_scale = clampf(1.0 / canvas_scale, 1.0, 3.2)
	return {
		"portrait": portrait,
		"compact_landscape": compact_landscape,
		"canvas_scale": canvas_scale,
		"ui_scale": ui_scale,
	}

func responsive_button_minimum_for_size(minimum: Vector2, size: Vector2) -> Vector2:
	var metrics := responsive_ui_metrics_for_size(size)
	var ui_scale := float(metrics.ui_scale)
	if bool(metrics.portrait):
		return Vector2(
			minf(maxf(minimum.x, MIN_TOUCH_CSS_PX) * ui_scale, 840.0),
			maxf(minimum.y, MIN_TOUCH_CSS_PX) * ui_scale
		)
	if bool(metrics.compact_landscape):
		var minimum_touch_logical := MIN_TOUCH_CSS_PX / float(metrics.canvas_scale)
		return Vector2(maxf(minimum.x, minimum_touch_logical), maxf(minimum.y, minimum_touch_logical))
	return minimum

func story_font_size_for_size(target_css_px: float, size: Vector2) -> int:
	# Story type is specified in rendered pixels, while the project is authored on
	# a 1920x1080 canvas. Convert the requested reading size back to logical pixels
	# so 1280x720 Web, compact landscape and portrait all preserve the same visual
	# hierarchy instead of inheriting the canvas shrink factor.
	var metrics := responsive_ui_metrics_for_size(size)
	var canvas_scale := float(metrics.canvas_scale)
	return maxi(1, roundi(target_css_px * story_fit_for_size(size) / maxf(canvas_scale, 0.001)))

func story_fit_for_size(size: Vector2) -> float:
	# Story sizes are authored for a landscape phone (360+ CSS px tall) or a
	# 16:9 desktop frame (520+). A shorter frame, such as a thumbnail-sized
	# desktop pane, cannot stack the chapter plate, the AUTO/SKIP rail and the
	# reading plate at those sizes; the plate then grew over the rail. Shrink the
	# whole story composition with the frame height instead.
	var metrics := responsive_ui_metrics_for_size(size)
	var reference_height := STORY_FIT_COMPACT_HEIGHT_CSS if bool(metrics.compact_landscape) else STORY_FIT_WIDE_HEIGHT_CSS
	return clampf(GameUI.landscape_layout_size(size).y / reference_height, STORY_MIN_FIT, 1.0)

static func story_page_progress(commands: Array, current_command_index: int) -> Vector2i:
	# A "page" is a player-facing text card, not an internal art/audio command.
	# This keeps the footer stable when the runner consumes several presentation
	# commands between two pieces of readable copy.
	var current_page := 0
	var total_pages := 0
	for command_index in range(commands.size()):
		var command: Dictionary = commands[command_index]
		if str(command.get("command", "")) not in ["dialogue", "narration", "choice"]:
			continue
		total_pages += 1
		if command_index <= current_command_index:
			current_page = total_pages
	return Vector2i(current_page, total_pages)

func _story_logical_px(target_css_px: float) -> int:
	return story_font_size_for_size(target_css_px, _runtime_layout_size())

func _story_weighted_font(weight: float, embolden: float = 0.0) -> Font:
	return GameUI.weighted_font(interface_font, weight, embolden)

func _is_compact_landscape_layout() -> bool:
	return bool(responsive_ui_metrics_for_size(_runtime_layout_size()).compact_landscape)

func _portrait_ui_scale() -> float:
	var metrics := responsive_ui_metrics_for_size(_runtime_layout_size())
	return float(metrics.ui_scale) if bool(metrics.portrait) else 1.0

func _responsive_control_scale() -> float:
	return float(responsive_ui_metrics_for_size(_runtime_layout_size()).ui_scale)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveService.save_game()

func _unhandled_key_input(event: InputEvent) -> void:
	if current_screen != "STORY" or not _is_story_advance_key_event(event): return
	get_viewport().set_input_as_handled()
	AudioService.unlock_from_user_gesture()
	_request_story_advance("keyboard:%d" % int((event as InputEventKey).keycode))

func _input(event: InputEvent) -> void:
	# Pointer input belongs to ordinary Buttons and the scroll container. A
	# touch-down in the reading area must not advance before a drag can begin.
	if not pre_battle_event_input_active or not _is_story_advance_key_event(event): return
	AudioService.unlock_from_user_gesture()
	if pre_battle_event_advance.is_valid(): pre_battle_event_advance.call()
	get_viewport().set_input_as_handled()

func _handle_pre_battle_event_input(position: Vector2) -> bool:
	if not pre_battle_event_input_active or pre_battle_event_input_panel == null or not is_instance_valid(pre_battle_event_input_panel):
		return false
	if not pre_battle_event_input_panel.get_global_rect().has_point(position):
		return false
	if pre_battle_event_input_skip != null and is_instance_valid(pre_battle_event_input_skip) and pre_battle_event_input_skip.get_global_rect().has_point(position):
		if pre_battle_event_resolve.is_valid():
			pre_battle_event_resolve.call()
		return true
	if pre_battle_event_input_next != null and is_instance_valid(pre_battle_event_input_next) and pre_battle_event_input_next.get_global_rect().has_point(position):
		if pre_battle_event_advance.is_valid():
			pre_battle_event_advance.call()
		return true
	return false

func _is_story_advance_key_event(event: InputEvent) -> bool:
	if not event is InputEventKey: return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo: return false
	return key_event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]

func _consume_transition_edge(action: String, source: String, now_msec := -1) -> bool:
	var edge_time := Time.get_ticks_msec() if now_msec < 0 else now_msec
	if edge_time < transition_edge_blocked_until_msec:
		transition_edge_reject_count += 1
		return false
	transition_edge_blocked_until_msec = edge_time + TRANSITION_EDGE_DEBOUNCE_MSEC
	transition_edge_accept_count += 1
	transition_edge_last_action = action
	transition_edge_last_source = source
	return true

func transition_edge_diagnostics() -> Dictionary:
	return {
		"accepted": transition_edge_accept_count,
		"rejected": transition_edge_reject_count,
		"last_action": transition_edge_last_action,
		"last_source": transition_edge_last_source,
		"blocked_until_msec": transition_edge_blocked_until_msec,
		"debounce_msec": TRANSITION_EDGE_DEBOUNCE_MSEC,
	}

func _apply_safe_area() -> void:
	if safe_margin == null: return
	_update_viewport_gate()
	# The footer sits outside the content MarginContainer. Give it the same
	# portrait-safe clearance as the top/header area so it cannot overlap the
	# bottom action row or a device gesture zone.
	if footer_status != null:
		footer_status.position.y = -roundf(34.0 * _portrait_ui_scale()) if _is_portrait_layout() else -34.0
		footer_status.add_theme_font_size_override("font_size", roundi(16.0 * _portrait_ui_scale()))
	var window_size := DisplayServer.window_get_size()
	var area := DisplayServer.get_display_safe_area()
	var responsive_mobile := _is_portrait_layout() or _is_compact_landscape_layout()
	var base_margin := roundi(18.0 * _responsive_control_scale()) if responsive_mobile else 32
	if window_size.x <= 0 or window_size.y <= 0 or area.size.x <= 0 or area.size.y <= 0:
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]: safe_margin.add_theme_constant_override(side, base_margin)
		return
	var scale_x := 1920.0 / window_size.x
	var scale_y := 1080.0 / window_size.y
	safe_margin.add_theme_constant_override("margin_left", maxi(base_margin, int(area.position.x * scale_x)))
	safe_margin.add_theme_constant_override("margin_top", maxi(base_margin, int(area.position.y * scale_y)))
	safe_margin.add_theme_constant_override("margin_right", maxi(base_margin, int((window_size.x - area.end.x) * scale_x)))
	safe_margin.add_theme_constant_override("margin_bottom", maxi(base_margin, int((window_size.y - area.end.y) * scale_y)))

func _process(delta: float) -> void:
	_update_transition_loading_progress()
	# Some mobile Web engines update window.innerWidth/innerHeight without
	# forwarding a Godot resize event. Poll infrequently to avoid per-frame JS
	# bridge work while still preserving the current battle simulation.
	orientation_probe_left -= delta
	if orientation_probe_left <= 0.0:
		orientation_probe_left = 0.25
		_queue_orientation_reflow_if_needed()
	compact_touch_probe_left -= delta
	if compact_touch_probe_left <= 0.0:
		compact_touch_probe_left = 0.25
		# ChapterMapScreen owns its own button factory and can reapply compact
		# layout metrics after node selection. Reassert the shell-wide physical
		# touch contract without changing map gameplay or focus order.
		if _is_compact_landscape_layout() and content != null:
			_apply_compact_touch_targets(content)
		_apply_chapter_map_shell_overrides()
	if current_screen == "STORY" and story_auto and scenario_runner != null and not scenario_runner.state.waiting_for_choice and not AudioService.voice_is_playing():
		story_auto_left -= delta
		if story_auto_left <= 0:
			_advance_story()
	if current_screen == "BATTLE" and battle_view != null and battle_view.simulation != null:
		_update_battle_hud()
	_update_status_toast(delta)

# The footer bar is hidden by the layout, but many flows report failures and
# confirmations through `footer_status.text`. Surface each new message as a
# short toast so save errors, blocked battles and sweeps are never silent.
func _update_status_toast(delta: float) -> void:
	if footer_status == null:
		return
	var message := footer_status.text
	if message != status_toast_last_text:
		status_toast_last_text = message
		if not message.is_empty() and message != "오프라인 탐색 기록":
			_show_status_toast(message)
	if status_toast != null and status_toast.visible:
		status_toast_left -= delta
		if status_toast_left <= 0.0:
			status_toast.visible = false

func _notify(message: String) -> void:
	# Repeating the same message (e.g. pressing a blocked button twice) must
	# still show the toast again.
	if footer_status == null:
		return
	footer_status.text = message
	status_toast_last_text = message
	_show_status_toast(message)

func _show_status_toast(message: String) -> void:
	if not is_inside_tree():
		return
	if status_toast == null or not is_instance_valid(status_toast):
		status_toast = PanelContainer.new()
		status_toast.name = "StatusToast"
		status_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_toast.z_index = 90
		status_toast.add_theme_stylebox_override("panel", GameUI.panel_style(Color("07111bf0"), Color("e9c97999"), 1, GameUI.RADIUS_CONTROL, Vector4(18.0, 10.0, 18.0, 10.0), 0))
		status_toast_label = Label.new()
		status_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_toast_label.add_theme_color_override("font_color", Color("f3e6c4"))
		status_toast.add_child(status_toast_label)
		add_child(status_toast)
	status_toast_label.text = message
	status_toast_label.add_theme_font_size_override("font_size", roundi(20.0 * (_portrait_ui_scale() if _is_portrait_layout() else 1.0)))
	var width := minf(size.x - 48.0, 760.0)
	# A wrapping label measures its height at its current width; a new label is
	# 0 px wide, so the first toast grew hundreds of pixels tall (one line per
	# word) with the text pushed below the screen edge. Size the label first and
	# shrink the panel again once the label has re-measured.
	status_toast_label.custom_minimum_size = Vector2(maxf(0.0, width - 36.0), 0.0)
	status_toast_label.size = Vector2(maxf(0.0, width - 36.0), 0.0)
	status_toast.custom_minimum_size = Vector2(width, 0.0)
	status_toast.size = Vector2(width, 0.0)
	status_toast.set_deferred("size", Vector2(width, 0.0))
	status_toast.position = Vector2((size.x - width) * 0.5, size.y - 150.0)
	move_child(status_toast, get_child_count() - 1)
	status_toast.visible = true
	status_toast_left = 3.2

func _clear() -> void:
	_dispose_new_game_confirmation()
	# A Story screen can be left while its copy is still typing.  Tween owns a
	# property every frame, so it must be explicitly released before its old
	# RichTextLabel is removed or a rebuilt portrait plate can inherit a partial
	# visible_ratio on the next frame.
	_cancel_story_typewriter()
	chapter_map_show_generation += 1
	_dispose_transaction_save_failure()
	_dispose_map_reward_overlay(false)
	GrowthMenu.close(self)
	_free_home_tutorial()
	home_menu_buttons.clear()
	for child in content.get_children():
		content.remove_child(child)
		# Compatibility Web must not retain a live SubViewport under a hidden,
		# PROCESS_MODE_DISABLED parent. Release builds can leave its renderer callback
		# pointing at a freed object and return as a black canvas with audio still
		# playing. Native builds may keep the fast scene cache.
		if child == active_chapter_map_screen and is_instance_valid(child) and not OS.has_feature("web"):
			_cache_chapter_map_screen(child)
		else:
			child.queue_free()
	battle_view = null
	battle_hud = null
	ultimate_buttons.clear()
	party_status_labels.clear()
	battle_auto_button = null
	battle_skip_button = null
	battle_speed_button = null
	battle_pause_panel = null
	battle_pause_center = null
	battle_portrait_layout = false
	story_background = null
	story_portrait = null
	story_portrait_layer = null
	story_art_status = null
	story_dialogue_panel = null
	story_speaker_eyebrow = null
	story_click_hint = null
	story_page_indicator = null
	story_auto_button = null
	story_skip_button = null
	story_is_prologue = false
	story_is_cinematic = false
	active_chapter_map_screen = null

func _cache_chapter_map_screen(screen: Control) -> void:
	if screen == null or not is_instance_valid(screen) or chapter_map_cache_host == null:
		return
	if cached_chapter_map_screen != null and is_instance_valid(cached_chapter_map_screen) and cached_chapter_map_screen != screen:
		cached_chapter_map_screen.queue_free()
	cached_chapter_map_screen = screen
	cached_chapter_map_id = str(screen.get("map_id"))
	screen.visible = false
	screen.process_mode = Node.PROCESS_MODE_DISABLED
	chapter_map_cache_host.add_child(screen)

func _take_cached_chapter_map(map_id_value: String) -> Control:
	if OS.has_feature("web"):
		if cached_chapter_map_screen != null and is_instance_valid(cached_chapter_map_screen):
			cached_chapter_map_screen.queue_free()
		cached_chapter_map_screen = null
		cached_chapter_map_id = ""
		return null
	if cached_chapter_map_screen == null or not is_instance_valid(cached_chapter_map_screen):
		cached_chapter_map_screen = null
		cached_chapter_map_id = ""
		return null
	if cached_chapter_map_id != map_id_value:
		cached_chapter_map_screen.queue_free()
		cached_chapter_map_screen = null
		cached_chapter_map_id = ""
		return null
	var screen := cached_chapter_map_screen
	cached_chapter_map_screen = null
	cached_chapter_map_id = ""
	chapter_map_cache_host.remove_child(screen)
	screen.process_mode = Node.PROCESS_MODE_INHERIT
	screen.visible = true
	return screen

func _show_screen(screen_id: String) -> void:
	var previous_screen := current_screen
	if not SceneRouter.screen_allowed(screen_id, SettingsService.is_developer_mode()):
		screen_id = "HOME"
		SceneRouter.current_screen = "HOME"
		AppState.route_payload = {}
	# StageAssetCache is an autoload and therefore outlives the disposable map
	# screen.  Relinquish its work immediately when the owning screen is left;
	# otherwise a cancelled stage entry can keep decoding at full CPU in the
	# background while HOME or another screen is already visible.
	if previous_screen == "STAGE_SELECT" and screen_id != "STAGE_SELECT" and StageAssetCache.warming:
		StageAssetCache.cancel_warmup()
	# A story voice belongs to the line on screen; it never carries into another screen.
	if previous_screen == "STORY" and screen_id != "STORY":
		AudioService.stop_voice()
	_prepare_transition_loading_for_screen(previous_screen, screen_id)
	current_screen = screen_id
	_clear()
	match screen_id:
		"TITLE": _show_title()
		"HOME": _show_home()
		"STORY": _show_story()
		"FORMATION": _show_formation()
		"RELAY": _show_relay()
		"STAGE_SELECT": _show_chapter_map()
		"STAGE_LIST_FALLBACK": _show_stage_select()
		"STAGE_DETAIL": _show_stage_detail()
		"BATTLE": _show_battle()
		"RESULT": _show_result()
		"ROSTER": _show_roster()
		"GROWTH", "CHARACTER_DETAIL": _show_growth()
		"INVENTORY": _show_inventory()
		"ARCHIVE": _show_archive()
		"SETTINGS": _show_settings()
		"DEBUG": _show_debug()
		"LICENSE": _show_license()
		_: _show_home()
	_apply_compact_touch_targets(content)
	_apply_chapter_map_shell_overrides()
	_show_growth_economy_notice()

## Shown once after the v10 save migration granted the growth supply for
## operations cleared before it existed (SaveService._migrate).
func _show_growth_economy_notice() -> void:
	if current_screen not in ["HOME", "STAGE_SELECT"] or not AppState.profile.has("growth_economy_notice"):
		return
	var notice: Dictionary = AppState.profile.get("growth_economy_notice", {})
	AppState.profile.erase("growth_economy_notice")
	var parts: Array[String] = []
	if int(notice.get("account_to", 0)) > int(notice.get("account_from", 0)):
		parts.append("계정 레벨 %d → %d" % [int(notice.account_from), int(notice.account_to)])
	if not Dictionary(notice.get("items", {})).is_empty():
		parts.append("클리어한 작전의 성장 재료 지급")
	if parts.is_empty():
		return
	_notify("성장 보상 개편 · " + " · ".join(parts) + " · 메뉴의 권장 성장에서 바로 쓸 수 있습니다")

func _title(text_value: String, subtitle := "") -> void:
	var portrait := _is_portrait_layout()
	var ui_scale := minf(_responsive_control_scale(), 1.65)
	# In portrait, the back action gets its own top-bar row. A long Korean
	# chapter title must never be squeezed behind that control.
	var header: BoxContainer = VBoxContainer.new() if portrait and current_screen not in ["TITLE", "HOME"] else HBoxContainer.new()
	header.name = "ScreenHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(header)
	if current_screen not in ["TITLE", "HOME"]:
		# A RESULT screen is terminal for its Battle view.  Letting generic history
		# walk back into BATTLE would construct a fresh battle from an already
		# committed transaction after visiting Growth, which is both confusing and
		# outside the map -> battle -> result authority flow.  Result exits always
		# return to the canonical chapter map; other screens retain normal history.
		var back_button := CommandPresentation.button(self, "‹ 뒤로", _navigate_back_from_header, false, Vector2(220, 76))
		back_button.name = "ScreenBackButton"
		back_button.size_flags_horizontal = Control.SIZE_FILL
		header.add_child(back_button)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(labels)
	var title_label := Label.new()
	title_label.text = text_value
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.custom_minimum_size.x = 0.0
	title_label.add_theme_font_size_override("font_size", roundi((26.0 if _is_compact_landscape_layout() else (32.0 if portrait else 40.0)) * ui_scale))
	var title_font := GameUI.weighted_font(interface_font, 720.0, 0.05)
	if title_font != null: title_label.add_theme_font_override("font", title_font)
	title_label.add_theme_color_override("font_color", GameUI.TEXT)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels.add_child(title_label)
	if subtitle != "":
		var sub := Label.new()
		sub.text = subtitle
		sub.modulate = GameUI.TEXT_MUTED
		sub.add_theme_font_size_override("font_size", roundi((13.0 if _is_compact_landscape_layout() else (18.0 if portrait else 20.0)) * ui_scale))
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if portrait and current_screen in ["GROWTH", "CHARACTER_DETAIL"]:
			sub.name = "GrowthSectionHint"
			sub.add_theme_font_size_override("font_size", roundi(14.0 * ui_scale))
			sub.autowrap_mode = TextServer.AUTOWRAP_OFF
			sub.clip_text = true
		labels.add_child(sub)
	var accent := ColorRect.new()
	accent.name = "ScreenHeaderAccent"
	accent.color = GameUI.SIGNAL
	accent.custom_minimum_size = Vector2(0, 2)
	accent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(accent)

func _navigate_back_from_header() -> void:
	if current_screen == "RESULT":
		SceneRouter.go("STAGE_SELECT", {"result_return": true})
	else:
		SceneRouter.back("HOME")

func _button(text_value: String, callback: Callable, disabled := false, minimum := Vector2(190, 64)) -> Button:
	var button := Button.new()
	button.text = text_value
	var metrics := responsive_ui_metrics_for_size(_runtime_layout_size())
	# Menu controls share authored canvas geometry. The former second pass
	# inflated every item to 56 screen pixels, even inside dense five-slot rows.
	button.set_meta("composed_control", true)
	button.custom_minimum_size = Vector2(minimum.x, maxf(minimum.y, 88.0 if bool(metrics.compact_landscape) else 64.0))
	# A 390px phone must never expose a half-word action that cannot be read or
	# tapped with confidence. Explicit two-line labels retain their authored line
	# break, while long localized labels now wrap inside their real hit target.
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bool(metrics.portrait) or bool(metrics.compact_landscape):
		button.add_theme_font_size_override("font_size", roundi(22.0 * GameUI.typography_scale(_runtime_layout_size())))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = disabled
	GameUI.apply_button(button)
	# WebAudio must be resumed in the same call stack as a real button press.
	# Keeping this wrapper at the shared button factory covers title, map,
	# formation, growth and settings without duplicating platform branches.
	button.pressed.connect(func():
		AudioService.unlock_from_user_gesture()
		callback.call()
	)
	return button

func _apply_compact_touch_targets(root: Node) -> void:
	if root == null or not _is_compact_landscape_layout(): return
	# The tactical map owns its dense landscape controls. Applying a second
	# 56px global minimum here inflated every map button after its layout pass.
	if current_screen in ["STAGE_SELECT", "STAGE_DETAIL"]: return
	var metrics := responsive_ui_metrics_for_size(_runtime_layout_size())
	var minimum_touch_logical := MIN_TOUCH_CSS_PX / float(metrics.canvas_scale)
	# Touch accessibility is determined by the physical hit box, not oversized
	# lettering. This cap lets dense story controls stay secondary on compact Web
	# viewports while preserving the 56 CSS-pixel touch target.
	var minimum_font_logical := roundi(22.0 * GameUI.typography_scale(_runtime_layout_size()))
	_apply_compact_touch_targets_recursive(root, minimum_touch_logical, minimum_font_logical)

func _apply_compact_touch_targets_recursive(root: Node, minimum_touch_logical: float, minimum_font_logical: int) -> void:
	for child in root.get_children():
		# The 3D chapter world can contain hundreds of render nodes but no screen
		# controls. Avoid walking it every responsive probe; map overlay buttons are
		# siblings of the SubViewport and remain covered by this traversal.
		if child is SubViewport:
			continue
		if child is Button:
			if child.has_meta("composed_control"): continue
			var button := child as Button
			var current := button.custom_minimum_size
			var target := Vector2(maxf(current.x, minimum_touch_logical), maxf(current.y, minimum_touch_logical))
			if not current.is_equal_approx(target):
				button.custom_minimum_size = target
			# Story controls have their own deliberately quieter type scale.  Their
			# physical target is still enlarged above, so never re-inflate that type
			# just because the viewport happens to be a compact landscape one.
			if not button.has_meta("story_control") and not button.has_meta("compact_growth_control") and not button.has_meta("compact_reward_control"):
				var current_font := button.get_theme_font_size("font_size")
				if current_font < minimum_font_logical:
					button.add_theme_font_size_override("font_size", minimum_font_logical)
		_apply_compact_touch_targets_recursive(child, minimum_touch_logical, minimum_font_logical)

func _story_button(text_value: String, callback: Callable, disabled := false, minimum := Vector2(190, 58)) -> Button:
	var button := _button(text_value, callback, disabled, minimum)
	# Story controls are secondary navigation, not the line the player came to
	# read. Their generous physical hit area remains untouched, while the type
	# stays clearly subordinate to a Korean narration line on every canvas scale.
	button.set_meta("story_control", true)
	button.set_meta("composed_control", true)
	button.custom_minimum_size = Vector2(minimum.x, _story_logical_px(36.0))
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.add_theme_font_size_override("font_size", _story_logical_px(14.0))
	return button

func _apply_chapter_map_shell_overrides() -> void:
	if active_chapter_map_screen == null or not is_instance_valid(active_chapter_map_screen): return
	var status_value = active_chapter_map_screen.get("status_label")
	var next_value = active_chapter_map_screen.get("next_encounter_button")
	if not status_value is Label or not next_value is Button: return
	var status := status_value as Label
	var next_button := next_value as Button
	var metrics := responsive_ui_metrics_for_size(_runtime_layout_size())
	if bool(metrics.portrait):
		var ui_scale := float(metrics.ui_scale)
		var touch_height := MIN_TOUCH_CSS_PX * ui_scale
		next_button.offset_bottom = next_button.offset_top + touch_height
		next_button.custom_minimum_size.y = maxf(next_button.custom_minimum_size.y, touch_height)
		# Keep the chapter status on a separate visual line below the top-right
		# encounter shortcut. At 390px the former 350px status and 188px button
		# geometrically overlapped over most of their text.
		status.position.y = (14.0 + MIN_TOUCH_CSS_PX + 8.0) * ui_scale
		return
	if bool(metrics.compact_landscape):
		return # Final map layout owns its compact encounter shortcut.

func _make_primary_button(button: Button) -> void:
	GameUI.apply_button(button, "primary")

func _label(text_value: String, size_value := 21, color := Color("dcecff")) -> Label:
	var value := Label.new()
	value.text = text_value
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_font_size_override("font_size", roundi(float(size_value) * GameUI.typography_scale(_runtime_layout_size())))
	value.modulate = color
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return value

func _story_label(text_value: String, target_css_px: float, color := GameUI.TEXT) -> Label:
	# Story sizes are already converted from rendered CSS pixels to the retained
	# 1920x1080 logical canvas. Passing them through `_label()` multiplied them by
	# the portrait compensation a second time and produced clipped 100px+ type.
	var value := Label.new()
	value.text = text_value
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_font_size_override("font_size", _story_logical_px(target_css_px))
	value.modulate = color
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return value

func _panel() -> VBoxContainer:
	return _panel_box(content)

func _panel_box(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", GameUI.panel_style())
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box

func _asset_texture(asset_id: String) -> Texture2D:
	var path := AssetRegistry.resolve(asset_id)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func story_art_texture_for_state(cg_asset_id: String, background_asset_id: String) -> Texture2D:
	# A CG is the preferred story image, but a missing/import-failed CG must never
	# turn an authored story beat into an empty black presentation band.  The
	# scenario background is the deterministic visual fallback and does not alter
	# any scenario, save, or progression authority.
	var cg_texture := _asset_texture(cg_asset_id) if not cg_asset_id.is_empty() else null
	if cg_texture != null:
		return cg_texture
	return _asset_texture(background_asset_id)

func _apply_skill_icon(button: Button, skill: Dictionary, max_width: int) -> void:
	var icon_asset_id := str(skill.get("icon_asset_id", ""))
	var icon_texture := _asset_texture(icon_asset_id)
	if icon_texture == null:
		return
	button.icon = icon_texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", max_width)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = "%s · %s" % [LocalizationService.tr_key(str(skill.get("name_key", ""))), str(skill.get("effect", ""))]

func _character_art_frame_style() -> StyleBoxFlat:
	# The Web fallback-safe opaque CHR002 delivery derivative and all transparent
	# legacy art share this same presentation card.  This is deliberately a UI
	# contract, not a per-character backdrop, so the lineup cannot look like a
	# mixture of cutouts and temporary blue image tiles.
	return GameUI.panel_style(Color("08121f"), Color("6ce6d042"), 1, GameUI.RADIUS_CONTROL, Vector4(4.0, 4.0, 4.0, 4.0), 0)

func _art_rect(asset_id: String, minimum: Vector2, mode := TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = minimum * _portrait_ui_scale()
	frame.add_theme_stylebox_override("panel", _character_art_frame_style())
	var art := TextureRect.new()
	art.texture = _asset_texture(asset_id)
	# Art cards are content controls too. Without this scale a 260 px portrait
	# card collapses to roughly 50 physical pixels on the retained 1920 canvas.
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = mode
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)
	return frame

func _format_counts(values: Dictionary, bullet := true) -> String:
	if values.is_empty(): return "없음"
	var keys := values.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append(("• " if bullet else "") + "%s  ×%s" % [_display_runtime_name(str(key)), MathUtil.comma(int(values[key]))])
	return "\n".join(parts) if bullet else "   ".join(parts)

func _format_stats(values: Dictionary) -> String:
	var keys := ["HP", "ATK", "DEF", "ACC", "EVA", "CRIT", "HEAL_POWER", "HASTE"]
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s %s" % [key, MathUtil.comma(int(values.get(key, 0)))])
	return "   ".join(parts.slice(0, 4)) + "\n" + "   ".join(parts.slice(4, 8))

func _format_stage_waves(waves: Array) -> String:
	var lines: Array[String] = []
	for index in range(waves.size()):
		var counts: Dictionary = {}
		for enemy_id in waves[index]:
			counts[str(enemy_id)] = int(counts.get(str(enemy_id), 0)) + 1
		lines.append("WAVE %d   %s" % [index + 1, _format_counts(counts, false)])
	return "\n".join(lines)

func _format_reward_entries(entries: Array) -> String:
	if entries.is_empty(): return "없음"
	var lines: Array[String] = []
	for entry in entries:
		var amount := int(entry.get("quantity", entry.get("min", 1)))
		var amount_max := int(entry.get("max", amount))
		var amount_text := "×%d" % amount if amount == amount_max else "×%d~%d" % [amount, amount_max]
		var chance_text := ""
		if entry.has("chance"): chance_text = "  %d%%" % roundi(float(entry.chance) * 100.0)
		lines.append("• %s  %s%s" % [_display_item_name(str(entry.get("item_id", "UNKNOWN"))), amount_text, chance_text])
	return "\n".join(lines)

func _scroll_box() -> VBoxContainer:
	var scroll := preload("res://ui/touch_progression_scroll.gd").new()
	# Every menu below the header shares one explicit scroll contract.  The
	# portrait repair pass can therefore give a Web phone a visible scroll rail
	# and a real drag deadzone instead of relying on the desktop defaults.
	scroll.name = "PrimaryContentScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	content.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	return box

func _show_title() -> void:
	preload("res://screens/command_presentation.gd").title(self)
	if not SaveService.write_lock_reason.is_empty():
		_show_save_protection_notice()

# Shown when a save exists but this build cannot read it. Nothing is written
# until the player chooses to archive it; closing the tab keeps it untouched.
func _show_save_protection_notice() -> void:
	if is_instance_valid(save_protection_layer):
		return
	save_protection_layer = CanvasLayer.new()
	save_protection_layer.name = "SaveProtectionLayer"
	save_protection_layer.layer = 460
	add_child(save_protection_layer)
	var surface := ColorRect.new()
	surface.color = Color("030914ee")
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	save_protection_layer.add_child(surface)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(size.x - 64.0, 900.0), 380)
	panel.add_theme_stylebox_override("panel", GameUI.panel_style(GameUI.SURFACE, Color("f1c75b"), 2, 18, Vector4(40, 32, 40, 32), 12))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	panel.add_child(column)
	var presentation := preload("res://screens/command_presentation.gd")
	column.add_child(presentation.label(self, "저장 기록을 읽지 못했습니다", 34, Color("f1c75b")))
	var detail: Label = presentation.label(self, "기존 기록이 손상되었거나 더 새로운 버전의 게임에서 저장되었습니다.\n기록을 덮어쓰지 않도록 저장을 멈췄습니다. 최신 버전으로 열면 그대로 이어서 할 수 있습니다.\n여기서 새로 시작하면 기존 기록은 별도 파일로 보관됩니다.\n(%s)" % SaveService.write_lock_reason, 22, GameUI.TEXT_MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail)
	var confirm: Button = presentation.button(self, "기존 기록 보관 후 새로 시작", func():
		var archived := SaveService.archive_unreadable_save_and_unlock()
		if not archived.ok:
			detail.text = "기존 기록을 보관하지 못해 계속할 수 없습니다: %s" % archived.error
			return
		var started := SaveService.start_new_game()
		if not started.ok:
			detail.text = "새 기록을 저장하지 못했습니다: %s" % started.error
			return
		save_protection_layer.queue_free()
		save_protection_layer = null
		_start_title_flow()
	, false, Vector2(360, 68))
	GameUI.apply_button(confirm, "primary")
	column.add_child(confirm)

func _dispose_new_game_confirmation() -> void:
	if is_instance_valid(new_game_confirmation_layer): new_game_confirmation_layer.queue_free()
	new_game_confirmation_layer = null

func _request_new_game() -> void:
	if current_screen != "TITLE" or is_instance_valid(new_game_confirmation_layer): return
	new_game_confirmation_layer = CanvasLayer.new()
	new_game_confirmation_layer.layer = 450
	new_game_confirmation_layer.name = "NewGameConfirmationLayer"
	add_child(new_game_confirmation_layer)
	var surface := ColorRect.new()
	surface.name = "NewGameConfirmation"
	surface.color = Color("030914db")
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	new_game_confirmation_layer.add_child(surface)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "NewGamePanel"
	panel.custom_minimum_size = Vector2(820,360)
	panel.add_theme_stylebox_override("panel",GameUI.panel_style(GameUI.SURFACE,GameUI.BORDER_STRONG,2,18,Vector4(40,32,40,32),12))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",22)
	panel.add_child(column)
	var presentation := preload("res://screens/command_presentation.gd")
	column.add_child(presentation.label(self,"새로운 기록을 시작할까요?",34,GameUI.OBJECTIVE_SOFT))
	var detail: Label = presentation.label(self,"캐릭터 성장, 보상과 탐색 기록이 초기화됩니다.\n프롤로그부터 다시 시작합니다.",24,GameUI.TEXT_MUTED)
	detail.name = "NewGameDetail"
	column.add_child(detail)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation",18)
	column.add_child(actions)
	var cancel: Button = presentation.button(self,"취소",_dispose_new_game_confirmation,false,Vector2(220,68))
	cancel.name = "NewGameCancelButton"
	actions.add_child(cancel)
	var confirm: Button = presentation.button(self,"새 게임 시작",func():
		var result := SaveService.start_new_game()
		if not result.ok:
			detail.text = "새 기록을 저장하지 못했습니다. 기존 기록은 보관되어 있습니다.\n다시 시도해 주세요."
			return
		_dispose_new_game_confirmation()
		_start_title_flow()
	,false,Vector2(280,68))
	confirm.name = "NewGameConfirmButton"
	GameUI.apply_button(confirm,"primary")
	actions.add_child(confirm)
	cancel.grab_focus()

func _portrait_title_cast_member(node_name: String, texture_path: String, align_right: bool, portrait_scale: float) -> TextureRect:
	var cast_member := TextureRect.new()
	cast_member.name = node_name
	cast_member.texture = load(texture_path) as Texture2D
	cast_member.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cast_member.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# 126×252 CSS px intentionally fits an entire 2:3 character with a 12px
	# exterior safety inset. The CTA remains the central, unobstructed action.
	cast_member.size = Vector2(126.0, 252.0) * portrait_scale
	cast_member.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT if align_right else Control.PRESET_BOTTOM_LEFT)
	cast_member.position = Vector2(
		-(cast_member.size.x + 12.0 * portrait_scale) if align_right else 12.0 * portrait_scale,
		-(cast_member.size.y + 14.0 * portrait_scale)
	)
	cast_member.modulate = Color(1.0, 1.0, 1.0, 0.94)
	cast_member.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cast_member

func _start_title_flow() -> void:
	AppState.profile.tutorial_progress.title_seen = true
	# A completed prologue should not replay on every launch. An unfinished first
	# run resumes its saved line, while a fresh profile enters the authored
	# click-through prologue before the home screen.
	if bool(AppState.profile.story_flags.get("PROLOGUE_READ", false)):
		SceneRouter.go("HOME")
		return
	AppState.active_scenario_id = "SCN_PROLOGUE"
	SceneRouter.go("STORY", {"after": "HOME", "origin": "TITLE"})

func _make_title_start_button(button: Button) -> void:
	GameUI.apply_button(button, "objective")
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		style.content_margin_left = 28.0
		style.content_margin_right = 28.0
		style.content_margin_top = 16.0
		style.content_margin_bottom = 16.0
		if state == "normal":
			style.shadow_color = Color("00000080")
			style.shadow_size = 10
			style.shadow_offset = Vector2(0.0, 4.0)
		button.add_theme_stylebox_override(state, style)

func _home_tutorial_active() -> bool:
	var tutorial_value = AppState.profile.get("tutorial_progress", {})
	if not tutorial_value is Dictionary:
		return false
	var tutorial: Dictionary = tutorial_value
	return not bool(tutorial.get("home_basics_complete", false))

func _free_home_tutorial() -> void:
	if home_tutorial_layer != null and is_instance_valid(home_tutorial_layer):
		if home_tutorial_layer.get_parent() == self:
			remove_child(home_tutorial_layer)
		home_tutorial_layer.queue_free()
	home_tutorial_layer = null
	home_tutorial_surface = null
	home_tutorial_panel = null
	home_tutorial_eyebrow = null
	home_tutorial_title = null
	home_tutorial_body = null
	home_tutorial_continue_button = null
	home_tutorial_skip_button = null
	home_tutorial_progress_label = null
	home_tutorial_step = 0

func _build_home_tutorial() -> void:
	if not _home_tutorial_active(): return
	_free_home_tutorial()
	home_tutorial_layer = CanvasLayer.new()
	home_tutorial_layer.name = "HomeFirstOperationTutorialCanvas"
	home_tutorial_layer.layer = 120
	add_child(home_tutorial_layer)
	home_tutorial_surface = Control.new()
	home_tutorial_surface.name = "HomeFirstOperationTutorialSurface"
	home_tutorial_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home_tutorial_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home_tutorial_surface.theme = theme
	home_tutorial_layer.add_child(home_tutorial_surface)
	var dimmer := ColorRect.new()
	dimmer.color = Color("02060bba")
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home_tutorial_surface.add_child(dimmer)
	var briefing := preload("res://ui/bounded_briefing.gd").new()
	briefing.runtime_size_reader = _runtime_layout_size
	briefing.preferred_height_css = 420.0
	home_tutorial_panel = briefing
	home_tutorial_panel.name = "HomeFirstOperationTutorial"
	home_tutorial_surface.add_child(home_tutorial_panel)
	home_tutorial_eyebrow = Label.new()
	home_tutorial_eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_tutorial_eyebrow.add_theme_color_override("font_color", GameUI.SIGNAL)
	briefing.type_target(home_tutorial_eyebrow, 14.0)
	briefing.header.add_child(home_tutorial_eyebrow)
	home_tutorial_title = Label.new()
	home_tutorial_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	home_tutorial_title.add_theme_color_override("font_color", GameUI.OBJECTIVE_SOFT)
	briefing.type_target(home_tutorial_title, 22.0)
	briefing.body.add_child(home_tutorial_title)
	briefing.body_scroll.name = "HomeTutorialBodyScroll"
	home_tutorial_body = RichTextLabel.new()
	home_tutorial_body.bbcode_enabled = true
	home_tutorial_body.fit_content = true
	home_tutorial_body.scroll_active = false
	home_tutorial_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_tutorial_body.add_theme_color_override("default_color", GameUI.TEXT)
	briefing.type_target(home_tutorial_body, 18.0)
	briefing.body.add_child(home_tutorial_body)
	home_tutorial_progress_label = Label.new()
	home_tutorial_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	home_tutorial_progress_label.add_theme_color_override("font_color", GameUI.TEXT_MUTED)
	briefing.type_target(home_tutorial_progress_label, 13.0)
	briefing.body.add_child(home_tutorial_progress_label)
	home_tutorial_skip_button = _button("안내 건너뛰기", _complete_home_tutorial_and_launch)
	home_tutorial_skip_button.name = "HomeTutorialSkipButton"
	briefing.type_target(home_tutorial_skip_button, 15.0)
	briefing.footer.add_child(home_tutorial_skip_button)
	home_tutorial_continue_button = _button("다음 안내", _advance_home_tutorial)
	home_tutorial_continue_button.name = "HomeTutorialContinueButton"
	_make_primary_button(home_tutorial_continue_button)
	briefing.type_target(home_tutorial_continue_button, 16.0)
	briefing.footer.add_child(home_tutorial_continue_button)
	_set_home_tutorial_step(home_tutorial_resume_step)
	briefing.reflow()

func _start_home_tutorial() -> void:
	if current_screen != "HOME" or not _home_tutorial_active():
		return
	_build_home_tutorial()

func _set_home_tutorial_step(step: int) -> void:
	if home_tutorial_panel == null or not is_instance_valid(home_tutorial_panel):
		return
	if home_tutorial_panel.has_method("rewind"): home_tutorial_panel.call("rewind")
	home_tutorial_step = clampi(step, 1, 4)
	home_tutorial_resume_step = home_tutorial_step
	home_tutorial_eyebrow.text = "첫 방문 안내  ·  %d / 4" % home_tutorial_step
	home_tutorial_progress_label.text = "%d / 4  ·  하단 버튼을 눌러 계속" % home_tutorial_step
	match home_tutorial_step:
		1:
			home_tutorial_title.text = "본부에서는 ‘준비’와 ‘출동’을 고릅니다"
			home_tutorial_body.text = "오른쪽 [color=#ffe6a2][b]작전 출동[/b][/color]을 누르면 탐색과 전투를 이어갑니다. 아래의 [color=#8fe9d9][b]스토리 기록[/b][/color]에서는 이미 읽은 장면을 다시 볼 수 있습니다."
			home_tutorial_continue_button.text = "준비 메뉴 보기"
		2:
			home_tutorial_title.text = "전투 전에는 편성과 성장을 확인하세요"
			home_tutorial_body.text = "[color=#8fe9d9][b]파티 편성[/b][/color]에서 이번 전투의 5명을 정하고, [color=#8fe9d9][b]동료[/b][/color]에서 레벨과 장비를 강화합니다. 목표 레벨을 정하면 필요한 재료가 자동으로 선택됩니다. [color=#8fe9d9][b]인벤토리[/b][/color]에서는 작전으로 얻은 재료를 확인할 수 있습니다."
			home_tutorial_continue_button.text = "기록 메뉴 보기"
		3:
			home_tutorial_title.text = "이야기와 시스템 메뉴도 이곳에 있습니다"
			home_tutorial_body.text = "[color=#8fe9d9][b]릴레이 작전[/b][/color]은 해금 동료를 세 부대로 나누는 연속 전투입니다. [color=#8fe9d9][b]스토리 기록[/b][/color]은 읽은 장면을 모아두고, 오른쪽 위 [color=#8fe9d9][b]설정[/b][/color]에서는 언어와 사운드를 조절합니다."
			home_tutorial_continue_button.text = "첫 작전 안내 받기"
		4:
			home_tutorial_title.text = "자, 이제 제1장 탐색을 시작합니다"
			home_tutorial_body.text = "[color=#ffe6a2][b]작전 출동[/b][/color]으로 제1장의 육각 탐색 맵을 엽니다. 그곳에서 노란 이동 범위, 조우 이벤트, 보물, 전투 진입법을 순서대로 안내합니다."
			home_tutorial_continue_button.text = "제1장 탐색 시작  ›"
			var stage_button = home_menu_buttons.get("STAGE", null)
			if stage_button is Button and is_instance_valid(stage_button):
				_make_primary_button(stage_button as Button)

func _advance_home_tutorial() -> void:
	# A Web resize/reflow can replace the pressed Button between pointer-down and
	# pointer-up. Reject duplicate release events from that one physical gesture;
	# otherwise a single tap can consume several steps or launch the map directly.
	var now_msec := Time.get_ticks_msec()
	if now_msec - home_tutorial_last_advance_msec < 400:
		return
	home_tutorial_last_advance_msec = now_msec
	if home_tutorial_step >= 4:
		_complete_home_tutorial_and_launch()
		return
	_set_home_tutorial_step(home_tutorial_step + 1)

func _complete_home_tutorial_and_launch() -> void:
	if home_first_operation_navigation_pending:
		return
	if AppState.profile.get("tutorial_progress", null) is Dictionary:
		AppState.profile.tutorial_progress["home_basics_complete"] = true
	SaveService.save_game()
	home_tutorial_resume_step = 1
	home_tutorial_last_advance_msec = -100000
	_defer_first_operation_navigation()

func _launch_first_operation() -> void:
	if home_first_operation_navigation_pending:
		return
	if _home_tutorial_active():
		_complete_home_tutorial_and_launch()
		return
	_defer_first_operation_navigation()

func _defer_first_operation_navigation() -> void:
	if home_first_operation_navigation_pending or current_screen != "HOME":
		return
	home_first_operation_navigation_pending = true
	# The pressed HOME button/tutorial CanvasLayer is part of the active canvas
	# traversal. Clearing it synchronously from its own callback can return through
	# a freed Callable on Web Release and leave a black root with BGM still alive.
	call_deferred("_commit_first_operation_navigation")

func _commit_first_operation_navigation() -> void:
	if not home_first_operation_navigation_pending:
		return
	home_first_operation_navigation_pending = false
	if current_screen != "HOME":
		return
	SceneRouter.go("STAGE_SELECT")

func _show_home() -> void:
	preload("res://screens/command_presentation.gd").home(self)

func _show_relay() -> void:
	AudioService.play_bgm("audio_bgm_lobby")
	var specification := RelayServiceScript.first_spec()
	if specification.is_empty():
		_title("릴레이 작전", "계약 데이터가 없습니다.")
		content.add_child(_label("릴레이 계약 데이터 검증 실패", 24, Color("ff7f8a")))
		return
	var relay_id := str(specification.get("id", ""))
	var active := RelayServiceScript.active_run(AppState.profile)
	_title("삼중 노선 릴레이", str(specification.get("subtitle", "기존 전투를 연속 작전으로 재구성합니다.")))
	_add_header_growth_menu()
	var scroll := _scroll_box()
	if not active.is_empty():
		_show_relay_active_run(scroll, specification, active)
		return
	_show_relay_draft(scroll, specification)
	var completion := RelayServiceScript.completion_summary(AppState.profile, relay_id)
	if not completion.is_empty():
		var completed_box := _panel_box(scroll)
		completed_box.add_child(_label("완료 기록  ·  최고 등급 %s  ·  완주 %d회" % [str(completion.get("best_grade", "B")), int(completion.get("runs_completed", 0))], 22, Color("9cf2df")))
		completed_box.add_child(_label("첫 완주 보상은 한 번만 지급됩니다. 재도전은 편성·기록 갱신용입니다.", 17, Color("9fb2ca")))

func _show_relay_draft(parent: VBoxContainer, specification: Dictionary) -> void:
	var unlocked_count := RelayServiceScript.unlocked_character_ids(AppState.profile).size()
	var draft_box := _panel_box(parent)
	draft_box.add_child(_label("계약 편성  ·  해금 동료 %d / 15명 필요" % unlocked_count, 25, Color("f1d77a")))
	draft_box.add_child(_label("세 부대의 15명은 전부 달라야 합니다. 각 구간 승리 후 그 부대는 잠기며, 패배하면 현재 구간만 다시 도전합니다.", 18, Color("cdd9e9")))
	var quick_actions := HBoxContainer.new()
	draft_box.add_child(quick_actions)
	quick_actions.add_child(_button("15명 자동 편성", func():
		if RelayServiceScript.autofill_draft(AppState.profile):
			SaveService.save_game()
			_show_screen("RELAY")
		else:
			footer_status.text = "릴레이에는 해금 동료 15명이 필요합니다."
	, unlocked_count < 15, Vector2(230, 58)))
	quick_actions.add_child(_button("편성 초기화", func():
		AppState.profile.relay.draft_squads = [[], [], []]
		SaveService.save_game()
		_show_screen("RELAY")
	, false, Vector2(190, 58)))
	var squads := RelayServiceScript.draft_squads(AppState.profile)
	for squad_index in range(RelayServiceScript.SQUAD_COUNT):
		var squad_box := _panel_box(parent)
		var selected_mark := "  ◀ 선택" if relay_edit_squad == squad_index else ""
		squad_box.add_child(_label("%d부대%s" % [squad_index + 1, selected_mark], 23, Color("78e6d0") if relay_edit_squad == squad_index else Color("a8b7ff")))
		var slots := GridContainer.new()
		slots.columns = 1 if _is_portrait_layout() else 5
		squad_box.add_child(slots)
		var squad: Array = squads[squad_index]
		for slot_index in range(RelayServiceScript.SQUAD_SIZE):
			var character_id := str(squad[slot_index]) if slot_index < squad.size() else ""
			var character := DataRegistry.character(character_id)
			var slot_text := "SLOT %d\n%s" % [slot_index + 1, _display_character_name(character_id) if not character.is_empty() else "선택 필요"]
			var is_selected := relay_edit_squad == squad_index and relay_edit_slot == slot_index
			slots.add_child(_button(slot_text, func(s := squad_index, p := slot_index): relay_edit_squad = s; relay_edit_slot = p; _show_screen("RELAY"), false, Vector2(180, 76)))
	var roster_box := _panel_box(parent)
	roster_box.add_child(_label("%d부대 · 슬롯 %d 선택" % [relay_edit_squad + 1, relay_edit_slot + 1], 22, Color("f1d77a")))
	roster_box.add_child(_label("이미 다른 릴레이 부대에 있는 동료를 선택하면 그 기존 슬롯은 비워집니다.", 17, Color("9fb2ca")))
	var roster_grid := GridContainer.new()
	roster_grid.columns = 2 if _is_portrait_layout() else 5
	roster_box.add_child(roster_grid)
	for character_id in RelayServiceScript.unlocked_character_ids(AppState.profile):
		var character := DataRegistry.character(character_id)
		roster_grid.add_child(_button("%s\n%s · %s" % [_display_character_name(character_id), str(character.get("role", "")), str(character.get("preferred_position", ""))], func(value := character_id):
			RelayServiceScript.set_draft_member(AppState.profile, relay_edit_squad, relay_edit_slot, value)
			SaveService.save_game()
			_show_screen("RELAY")
		, false, Vector2(190, 74)))
	var validation := RelayServiceScript.validate_squads(AppState.profile, squads)
	var ready := validation.is_empty()
	var start_box := _panel_box(parent)
	start_box.add_child(_label("계약 보상  ·  " + _format_counts(specification.get("completion_rewards", {}), false), 20, Color("9cf2df")))
	if not ready:
		start_box.add_child(_label("시작 조건: " + ", ".join(validation), 17, Color("ffbd7a")))
	var start := _button("릴레이 시작  ·  3개 구간", func(): _start_relay_contract(str(specification.get("id", ""))), not ready, Vector2(340, 72))
	_make_primary_button(start)
	start_box.add_child(start)

func _show_relay_active_run(parent: VBoxContainer, specification: Dictionary, run: Dictionary) -> void:
	var segment_index := int(run.get("segment_index", 0))
	var stage_ids: Array = specification.get("stage_ids", [])
	var progress_box := _panel_box(parent)
	progress_box.add_child(_label("작전 진행  ·  구간 %d / %d" % [segment_index + 1, stage_ids.size()], 27, Color("f1d77a")))
	progress_box.add_child(_label("현재 구간은 %s입니다. 앞선 승리 부대는 고정되며 이 화면을 닫거나 새로고침해도 저장됩니다." % _stage_display_name(RelayServiceScript.current_stage_id(AppState.profile)), 19, Color("cdd9e9")))
	var squads: Array = run.get("squads", [])
	var results: Array = run.get("segment_results", [])
	for squad_index in range(RelayServiceScript.SQUAD_COUNT):
		var squad_box := _panel_box(parent)
		var status := "현재 출전" if squad_index == segment_index else ("구간 완료 · 잠김" if squad_index < results.size() else "대기")
		squad_box.add_child(_label("%d부대 · %s" % [squad_index + 1, status], 22, Color("78e6d0") if squad_index == segment_index else Color("a8b7ff")))
		var names: Array[String] = []
		if squad_index < squads.size() and squads[squad_index] is Array:
			for character_id_value in squads[squad_index]: names.append(_display_character_name(str(character_id_value)))
		squad_box.add_child(_label(" · ".join(names), 18, Color("e8f3ff")))
		if squad_index < results.size():
			var result: Dictionary = results[squad_index]
			squad_box.add_child(_label("승리 · %.1f초 · 생존 %d" % [float(result.get("time", 0.0)), int(result.get("survivors", 0))], 16, Color("9cf2df")))
	var actions := HBoxContainer.new()
	parent.add_child(actions)
	var begin := _button("현재 구간 전투 시작", _request_relay_battle_start, false, Vector2(300, 72))
	_make_primary_button(begin)
	actions.add_child(begin)
	actions.add_child(_button("계약 포기", func(): RelayServiceScript.cancel(AppState.profile); SaveService.save_game(); _show_screen("RELAY"), false, Vector2(190, 72)))

func _start_relay_contract(relay_id: String) -> void:
	var started := RelayServiceScript.start(AppState.profile, relay_id, AppState.battle_seed + Time.get_ticks_msec())
	if not bool(started.get("ok", false)):
		footer_status.text = "릴레이 시작 실패: %s" % str(started.get("error", "UNKNOWN"))
		return
	SaveService.save_game()
	_show_screen("RELAY")

func _request_relay_battle_start() -> void:
	if battle_transition_active or not AppState.relay_active():
		return
	var stage_id := AppState.relay_current_stage_id()
	if stage_id.is_empty() or AppState.relay_current_squad().size() != RelayServiceScript.SQUAD_SIZE:
		footer_status.text = "릴레이 저장 상태가 유효하지 않습니다."
		return
	AppState.selected_stage_id = stage_id
	battle_transition_active = true
	SceneRouter.go("BATTLE")

func _show_story(reuse_runtime_state := false) -> void:
	story_navigation_pending = false
	if not SettingsService.is_developer_mode(): story_ui_hidden = false
	AudioService.play_bgm("audio_bgm_story")
	var portrait := _is_portrait_layout()
	var ui_scale := _portrait_ui_scale()
	var story_header := story_header_data(AppState.active_scenario_id)
	story_is_prologue = AppState.active_scenario_id == "SCN_PROLOGUE"
	var story_definition := DataRegistry.by_id("scenarios", AppState.active_scenario_id)
	story_is_cinematic = story_is_prologue or str(story_definition.get("presentation", "")) == "CINEMATIC"
	if story_is_cinematic:
		_build_prologue_story_presentation(portrait, ui_scale, story_header)
	else:
		_title(str(story_header.title), str(story_header.subtitle))
		_build_standard_story_presentation(portrait, ui_scale)
	if reuse_runtime_state and scenario_runner != null:
		_refresh_story_art()
		_restore_story_view_after_reflow()
		_refresh_story_control_states()
		return
	scenario_runner = ScenarioRunner.new()
	scenario_runner.replay = _is_archive_replay(AppState.active_scenario_id)
	var loaded := scenario_runner.load_scenario(AppState.active_scenario_id, not scenario_runner.replay)
	if not loaded.ok:
		scenario_text.text = loaded.error
		return
	AudioService.prefetch_line_voices(scenario_runner.scenario.get("commands", []))
	_refresh_story_art()
	story_auto_left = 1.0
	_refresh_story_control_states()
	_advance_story()

func _build_standard_story_presentation(portrait: bool, ui_scale: float) -> void:
	var stage := PanelContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(stage)
	var compact := _is_compact_landscape_layout()
	var layer: BoxContainer = HBoxContainer.new() if compact else VBoxContainer.new()
	layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(layer)
	var art_space := Control.new()
	# Compact landscape gives priority to the reading panel and keeps just enough
	# art height for the fixed 56px AUTO/SKIP rail; wide and portrait layouts retain
	# the established character presentation band.
	art_space.custom_minimum_size.y = 0.0 if compact else (236.0 * ui_scale if portrait else 320.0)
	art_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if compact:
		art_space.custom_minimum_size.x = 400.0
		art_space.size_flags_stretch_ratio = 0.42
	layer.add_child(art_space)
	story_background = TextureRect.new()
	story_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	story_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	story_background.modulate = Color(.70, .78, .88, .86)
	story_background.material = CinematicFx.material(CinematicFx.DRIFT, {"zoom_base": 1.07, "tint": Color("a8c6ff"), "tint_strength": 0.14, "vignette": 0.45, "brightness": 1.2})
	art_space.add_child(story_background)
	CinematicFx.motes(art_space, {"intensity": 0.6, "density": 0.7})
	story_portrait = TextureRect.new()
	if portrait or compact:
		story_portrait.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		story_portrait.position = Vector2(-262.0 * ui_scale, -142.0 * ui_scale) if portrait else Vector2(-500, -245)
		story_portrait.size = Vector2(262.0 * ui_scale, 304.0 * ui_scale) if portrait else Vector2(500, 500)
	else:
		# Visual-novel staging: a large standing illustration planted at the
		# bottom right that the dialogue plate overlaps, instead of a small inset.
		story_portrait.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		story_portrait.position = Vector2(-720, -570)
		story_portrait.size = Vector2(660, 740)
	story_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	story_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	CinematicFx.live_portrait(story_portrait, "STORY_STANDARD", {"emphasis": 1.0, "rim_strength": 0.5})
	art_space.add_child(story_portrait)
	# Asset provenance is useful while authoring, but it is not player-facing
	# story UI.  Keep the label available only in the developer build.
	story_art_status = _label("", 16, Color("78e6d0"))
	story_art_status.visible = false
	story_art_status.position = Vector2(18.0 * ui_scale, 16.0 * ui_scale) if portrait else Vector2(24, 20)
	story_art_status.size = Vector2(900.0 * ui_scale, 40.0 * ui_scale) if portrait else Vector2(900, 40)
	art_space.add_child(story_art_status)
	_build_story_top_right_controls(art_space, portrait, false)
	var dialogue := PanelContainer.new()
	dialogue.add_theme_stylebox_override("panel", _story_dialogue_style(false))
	dialogue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer.add_child(dialogue)
	_build_story_dialogue_content(dialogue, portrait, false)

func _build_prologue_story_presentation(portrait: bool, ui_scale: float, story_header: Dictionary) -> void:
	var runtime_size := _runtime_layout_size()
	var narrow_portrait := portrait and runtime_size.x <= 480.0
	var compact := _is_compact_landscape_layout()
	var stage := PanelContainer.new()
	stage.name = "PrologueCinematicStage"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_stylebox_override("panel", _prologue_stage_style())
	content.add_child(stage)
	var canvas := Control.new()
	canvas.name = "PrologueCinematicCanvas"
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(canvas)

	story_background = TextureRect.new()
	story_background.name = "PrologueBackground"
	story_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	story_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	story_background.modulate = Color(0.80, 0.88, 0.98, 0.86)
	story_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Slow push-in and grade: the still backdrop reads as a living set.
	story_background.material = CinematicFx.material(CinematicFx.DRIFT, {"zoom_base": 1.07, "tint": Color("a8c6ff"), "tint_strength": 0.14, "vignette": 0.4, "brightness": 1.25})
	canvas.add_child(story_background)
	CinematicFx.light_rays(canvas, {"origin": Vector2(0.5, -0.12), "ray_color": Color("cfe6ff"), "intensity": 0.18})
	var cinematic_scrim := ColorRect.new()
	cinematic_scrim.name = "PrologueCinematicScrim"
	cinematic_scrim.color = Color(0.008, 0.016, 0.045, 0.38)
	cinematic_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cinematic_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(cinematic_scrim)
	var lower_scrim := ColorRect.new()
	lower_scrim.name = "PrologueLowerScrim"
	lower_scrim.color = Color(0.006, 0.014, 0.04, 0.48)
	lower_scrim.anchor_left = 0.0
	lower_scrim.anchor_top = 0.48
	lower_scrim.anchor_right = 1.0
	lower_scrim.anchor_bottom = 1.0
	lower_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(lower_scrim)

	story_portrait_layer = Control.new()
	story_portrait_layer.name = "PrologueCharacterIllustrations"
	story_portrait_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_portrait_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(story_portrait_layer)
	CinematicFx.fog(canvas, {"intensity": 0.26, "top": 0.58})
	CinematicFx.motes(canvas, {"intensity": 0.7, "density": 0.8})
	CinematicFx.letterbox(canvas, 0.045)

	var chapter_plate := PanelContainer.new()
	chapter_plate.name = "PrologueChapterPlate"
	chapter_plate.anchor_left = 0.0
	chapter_plate.anchor_top = 0.0
	chapter_plate.anchor_right = 0.0
	chapter_plate.anchor_bottom = 0.0
	chapter_plate.offset_left = float(_story_logical_px(20.0))
	chapter_plate.offset_top = float(_story_logical_px(18.0))
	# Use the available portrait width instead of pinning phones and tablets to the
	# same 324 CSS-pixel card.  The old fixed width wrapped the Korean title to two
	# lines and then clipped that second line inside a 98px-high plate.
	var chapter_plate_right_css := 340.0 if compact else (minf(506.0, maxf(300.0, runtime_size.x - 20.0)) if portrait else 506.0)
	chapter_plate.offset_right = float(_story_logical_px(chapter_plate_right_css))
	chapter_plate.offset_bottom = float(_story_logical_px(72.0 if compact else (124.0 if narrow_portrait else (116.0 if portrait else 88.0))))
	chapter_plate.add_theme_stylebox_override("panel", _prologue_plate_style(ui_scale))
	canvas.add_child(chapter_plate)
	var chapter_copy := VBoxContainer.new()
	chapter_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chapter_plate.add_child(chapter_copy)
	var eyebrow := _story_label(_story_eyebrow_text(), 10.0 if compact else 13.0, GameUI.SIGNAL)
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chapter_copy.add_child(eyebrow)
	var chapter_title := _story_label(str(story_header.title), 19.0 if compact else (24.0 if narrow_portrait else 30.0), GameUI.TEXT)
	# Godot can initially allocate an autowrapped Label zero vertical space inside
	# this anchored PanelContainer on narrow Web canvases.  The title is known to
	# fit on one line at the responsive sizes above, so reserve that line explicitly.
	chapter_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	chapter_title.custom_minimum_size.y = float(_story_logical_px(25.0 if compact else (34.0 if narrow_portrait else 40.0)))
	chapter_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chapter_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chapter_copy.add_child(chapter_title)

	story_art_status = _label("", 14, Color("78e6d0"))
	# The cinematic opening is itself the QA target; never stamp authoring jargon
	# over the composition, even in a Development export.
	story_art_status.visible = false
	story_art_status.anchor_left = 0.0
	story_art_status.anchor_top = 0.0
	story_art_status.anchor_right = 0.0
	story_art_status.anchor_bottom = 0.0
	story_art_status.offset_left = 32.0 * ui_scale
	story_art_status.offset_top = 144.0 * ui_scale
	story_art_status.offset_right = 800.0 * ui_scale
	story_art_status.offset_bottom = 188.0 * ui_scale
	story_art_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(story_art_status)

	var dialogue_margin := MarginContainer.new()
	dialogue_margin.name = "PrologueDialogueMargin"
	# Choice rows may exceed the initial height. Keep the lower edge anchored
	# inside the viewport and let the reading plate grow upward.
	dialogue_margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dialogue_margin.anchor_left = 0.0
	dialogue_margin.anchor_top = 1.0
	dialogue_margin.anchor_right = 1.0
	dialogue_margin.anchor_bottom = 1.0
	var dialogue_inset_css := 20.0 if compact else (12.0 if narrow_portrait else (18.0 if portrait else 100.0))
	dialogue_margin.offset_left = float(_story_logical_px(dialogue_inset_css))
	dialogue_margin.offset_top = -float(_story_logical_px(178.0 if compact else (348.0 if narrow_portrait else 282.0)))
	dialogue_margin.offset_right = -float(_story_logical_px(dialogue_inset_css))
	dialogue_margin.offset_bottom = -float(_story_logical_px(12.0 if compact else (30.0 if narrow_portrait else 18.0)))
	# On a short window (e.g. a narrow desktop pane) the fixed plate height used
	# to cover the chapter plate and the AUTO/SKIP rail. Cap it to the lower 58%.
	var plate_height_css := (178.0 if compact else (348.0 if narrow_portrait else 282.0)) * story_fit_for_size(runtime_size)
	if runtime_size.y > 0.0 and plate_height_css > runtime_size.y * 0.58:
		dialogue_margin.anchor_top = 0.42
		dialogue_margin.offset_top = 0.0
	canvas.add_child(dialogue_margin)
	var dialogue := PanelContainer.new()
	dialogue.add_theme_stylebox_override("panel", _story_dialogue_style(true))
	dialogue_margin.add_child(dialogue)
	_build_story_dialogue_content(dialogue, portrait, true)
	# Added last so AUTO/SKIP always sit above the reading plate and keep input.
	_build_story_top_right_controls(canvas, portrait, true)

func _story_eyebrow_text() -> String:
	if story_is_prologue:
		return "PROLOGUE · THE LAST LINE"
	var scenario := DataRegistry.by_id("scenarios", AppState.active_scenario_id)
	var chapter := DataRegistry.chapter(str(scenario.get("chapter_id", "")))
	if chapter.is_empty():
		return "LUMENBOUND · THE LAST LINE"
	return LocalizationService.tr_key(str(chapter.get("name_key", "")))

func _build_story_top_right_controls(parent: Control, portrait: bool, cinematic: bool) -> void:
	var runtime_size := _runtime_layout_size()
	var auto_width := float(_story_logical_px(60.0)) if _is_compact_landscape_layout() else 132.0
	var skip_width := float(_story_logical_px(68.0)) if _is_compact_landscape_layout() else 142.0
	var auto_minimum := Vector2(auto_width, _story_logical_px(36.0))
	var skip_minimum := Vector2(skip_width, _story_logical_px(36.0))
	var separation := float(_story_logical_px(6.0))
	var right_inset := float(_story_logical_px(8.0))
	var top_inset := float(_story_logical_px(126.0 if portrait and cinematic else 18.0))
	story_controls = HBoxContainer.new()
	story_controls.name = "PrologueTopRightControls" if story_is_prologue else "StoryTopRightControls"
	story_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_controls.anchor_left = 1.0
	story_controls.anchor_top = 0.0
	story_controls.anchor_right = 1.0
	story_controls.anchor_bottom = 0.0
	story_controls.offset_left = -(auto_minimum.x + skip_minimum.x + separation + right_inset)
	story_controls.offset_top = top_inset
	story_controls.offset_right = -right_inset
	story_controls.offset_bottom = top_inset + maxf(auto_minimum.y, skip_minimum.y)
	story_controls.add_theme_constant_override("separation", roundi(separation))
	parent.add_child(story_controls)
	story_auto_button = _story_button("AUTO", _toggle_story_auto, false, Vector2(auto_width, 64))
	story_auto_button.name = "PrologueAutoButton" if story_is_prologue else "StoryAutoButton"
	_style_story_overlay_button(story_auto_button, Color("58d8c6"))
	story_controls.add_child(story_auto_button)
	story_skip_button = _story_button("SKIP  ▶", _skip_story_from_control, false, Vector2(skip_width, 64))
	story_skip_button.name = "PrologueSkipButton" if story_is_prologue else "StorySkipButton"
	_style_story_overlay_button(story_skip_button, Color("e6bd68"))
	story_controls.add_child(story_skip_button)

func _build_story_dialogue_content(dialogue: PanelContainer, portrait: bool, cinematic: bool) -> void:
	story_dialogue_panel = dialogue
	dialogue.name = "ClickablePrologueTextBox" if story_is_prologue else "ClickableStoryTextBox"
	# The outer plate is the one deliberate non-button tap target.  Its internal
	# layout containers must not become opaque input sinks on touch devices.
	dialogue.mouse_filter = Control.MOUSE_FILTER_STOP
	dialogue.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	dialogue.gui_input.connect(_on_story_text_box_input)
	# AUTO/SKIP live in the fixed top-right rail. The reading surface retains only
	# the secondary navigation that is useful beside the current line.
	var compact := _is_compact_landscape_layout()
	var narrow_portrait := portrait and _runtime_layout_size().x <= 480.0
	dialogue.custom_minimum_size.y = float(_story_logical_px(304.0 if narrow_portrait else ((150.0 if compact else 244.0) if cinematic else (220.0 if compact else 284.0))))
	var dialogue_frame := HBoxContainer.new()
	dialogue_frame.name = "StoryDialogueFrame"
	dialogue_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_frame.add_theme_constant_override("separation", _story_logical_px(8.0 if compact else 18.0))
	dialogue.add_child(dialogue_frame)
	var signal_rail := ColorRect.new()
	signal_rail.name = "StoryMintSignalRail"
	signal_rail.color = Color("5cdbc9")
	signal_rail.custom_minimum_size.x = float(_story_logical_px(3.0))
	signal_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_frame.add_child(signal_rail)
	var dialogue_box := VBoxContainer.new()
	# Labels and reading copy are intentionally non-interactive.  Let a tap on
	# any non-button part of the text box bubble to `dialogue`; real choice and
	# navigation buttons still receive their own direct input.
	dialogue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_box.add_theme_constant_override("separation", _story_logical_px(5.0 if narrow_portrait else (4.0 if compact else 8.0)))
	dialogue_frame.add_child(dialogue_box)
	story_speaker_eyebrow = _story_label("LUMENBOUND · VOICE LINK", 10.0 if compact else 14.0, GameUI.SIGNAL_SOFT)
	story_speaker_eyebrow.name = "StorySpeakerEyebrow"
	story_speaker_eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_speaker_eyebrow.add_theme_color_override("font_outline_color", Color("01050a"))
	story_speaker_eyebrow.add_theme_constant_override("outline_size", _story_logical_px(1.0))
	var story_meta_font := _story_weighted_font(620.0, 0.04)
	var story_title_font := _story_weighted_font(700.0, 0.07)
	var story_body_font := _story_weighted_font(520.0, 0.0)
	if story_meta_font != null:
		story_speaker_eyebrow.add_theme_font_override("font", story_meta_font)
	dialogue_box.add_child(story_speaker_eyebrow)
	scenario_speaker = _story_label("", 16.0 if compact else (28.0 if narrow_portrait else 32.0), GameUI.OBJECTIVE_SOFT)
	scenario_speaker.add_theme_color_override("font_outline_color", Color("01050a"))
	scenario_speaker.add_theme_color_override("font_shadow_color", Color("000000b8"))
	scenario_speaker.add_theme_constant_override("outline_size", _story_logical_px(2.0))
	scenario_speaker.add_theme_constant_override("shadow_offset_x", _story_logical_px(1.0))
	scenario_speaker.add_theme_constant_override("shadow_offset_y", _story_logical_px(1.0))
	if story_title_font != null:
		scenario_speaker.add_theme_font_override("font", story_title_font)
	dialogue_box.add_child(scenario_speaker)
	scenario_text = RichTextLabel.new()
	scenario_text.bbcode_enabled = true
	scenario_text.fit_content = true
	scenario_text.scroll_active = false
	scenario_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scenario_text.custom_minimum_size.y = float(_story_logical_px(112.0 if narrow_portrait else (24.0 if compact else (96.0 if cinematic else 88.0))))
	scenario_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not cinematic: scenario_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Compact reading copy uses 16 rendered pixels. Full desktop retains its
	# larger reading band; navigation stays at the bottom of the dialogue plate.
	var story_body_css_px := 16.0 if compact else (24.0 if narrow_portrait else 28.0)
	scenario_text.add_theme_font_size_override("normal_font_size", _story_logical_px(story_body_css_px))
	scenario_text.add_theme_font_size_override("bold_font_size", _story_logical_px(story_body_css_px))
	scenario_text.add_theme_color_override("default_color", Color("fffaf0"))
	# The opaque dialogue plate already provides contrast. Preserve the full white
	# face of Korean glyphs instead of shrinking it with a dark pixel outline.
	scenario_text.add_theme_constant_override("outline_size", 0)
	scenario_text.add_theme_constant_override("shadow_offset_x", 0)
	scenario_text.add_theme_constant_override("shadow_offset_y", 0)
	scenario_text.add_theme_constant_override("line_separation", _story_logical_px(4.0 if compact else (5.0 if narrow_portrait else 8.0)))
	if story_body_font != null:
		scenario_text.add_theme_font_override("normal_font", story_body_font)
	if story_title_font != null:
		scenario_text.add_theme_font_override("bold_font", story_title_font)
	# Let the surrounding dialogue panel own click/touch progression. Choice and
	# control buttons keep their own input, so a click on a choice never advances
	# the scenario twice.
	scenario_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scenario_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_box.add_child(scenario_text)
	scenario_choices = VBoxContainer.new()
	scenario_choices.add_theme_constant_override("separation", _story_logical_px(8.0))
	dialogue_box.add_child(scenario_choices)
	var story_footer := HBoxContainer.new()
	story_footer.name = "StoryProgressFooter"
	story_footer.mouse_filter = Control.MOUSE_FILTER_PASS
	dialogue_box.add_child(story_footer)
	story_click_hint = _story_label("대화창 클릭 / 터치로 계속  >", 10.0 if compact else (14.0 if narrow_portrait else 16.0), GameUI.SIGNAL_SOFT)
	story_click_hint.name = "StoryClickAdvanceHint"
	story_click_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_click_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	story_click_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if story_meta_font != null:
		story_click_hint.add_theme_font_override("font", story_meta_font)
	story_footer.add_child(story_click_hint)
	if story_click_hint.is_inside_tree():
		var hint_pulse := story_click_hint.create_tween().set_loops()
		hint_pulse.tween_property(story_click_hint, "modulate:a", 0.35, 0.75).set_trans(Tween.TRANS_SINE)
		hint_pulse.tween_property(story_click_hint, "modulate:a", 1.0, 0.75).set_trans(Tween.TRANS_SINE)
	story_page_indicator = _story_label("PAGE · -- / --", 10.0 if compact else (14.0 if narrow_portrait else 16.0), GameUI.TEXT_MUTED)
	story_page_indicator.name = "StoryPageIndicator"
	story_page_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	story_page_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if story_meta_font != null:
		story_page_indicator.add_theme_font_override("font", story_meta_font)
	story_footer.add_child(story_page_indicator)
	if cinematic:
		return
	dialogue_box.add_child(_build_story_secondary_controls(portrait))

func _build_story_secondary_controls(portrait: bool) -> Control:
	var story_secondary_controls: Control = GridContainer.new() if portrait else HBoxContainer.new()
	story_secondary_controls.name = "StorySecondaryControls"
	if story_secondary_controls is GridContainer:
		(story_secondary_controls as GridContainer).columns = 2
	story_secondary_controls.add_child(_story_button("다음", func(): _request_story_advance("button:next"), false, Vector2(130, 58)))
	story_secondary_controls.add_child(_story_button("로그", _show_story_log, false, Vector2(110, 58)))
	if SettingsService.is_developer_mode():
		story_secondary_controls.add_child(_story_button("UI 숨기기", _toggle_story_ui, false, Vector2(_story_logical_px(100.0), 58)))
		story_secondary_controls.add_child(_story_button("DEV 전체 스킵", _dev_skip_story, false, Vector2(_story_logical_px(138.0), 58)))
	return story_secondary_controls

func _prologue_stage_style() -> StyleBoxFlat:
	return GameUI.panel_style(Color("050a11f5"), Color("526f8777"), 1, GameUI.RADIUS_MODAL, Vector4.ZERO, 8)

func _prologue_plate_style(ui_scale: float) -> StyleBoxFlat:
	return GameUI.panel_style(
		Color("0a1723d6"),
		GameUI.SIGNAL,
		maxi(1, roundi(ui_scale)),
		roundi(float(GameUI.RADIUS_PANEL) * ui_scale),
		Vector4(18.0, 10.0, 20.0, 10.0) * ui_scale,
		0
	)

func _story_dialogue_style(cinematic: bool) -> StyleBoxFlat:
	var border_width := maxi(1, _story_logical_px(1.25))
	var radius := _story_logical_px(14.0)
	var style := GameUI.panel_style(
		Color(0.012, 0.026, 0.060, 0.94 if cinematic else 0.92),
		Color("f0cd7ee6"),
		border_width,
		radius,
		Vector4(_story_logical_px(14.0),_story_logical_px(12.0),_story_logical_px(14.0),_story_logical_px(10.0)) if _is_compact_landscape_layout() else Vector4(float(_story_logical_px(22.0)), float(_story_logical_px(18.0)), float(_story_logical_px(24.0)), float(_story_logical_px(16.0))),
		_story_logical_px(8.0)
	)
	# A heavier gilt top edge and a warm halo frame the reading plate like a
	# cinematic subtitle card.
	style.border_width_top = maxi(2, _story_logical_px(3.0))
	style.shadow_color = Color(0.94, 0.78, 0.42, 0.22)
	style.shadow_size = _story_logical_px(16.0)
	style.shadow_offset = Vector2.ZERO
	return style

func _style_story_overlay_button(button: Button, accent: Color) -> void:
	var border_width := maxi(1, _story_logical_px(1.25))
	var radius := _story_logical_px(9.0)
	var side_padding := float(_story_logical_px(8.0 if _is_compact_landscape_layout() else 14.0))
	var margins := Vector4(side_padding, 0.0, side_padding, 0.0)
	var normal := GameUI.panel_style(Color("081522f2"), accent, border_width, radius, margins, 0)
	var hover := normal.duplicate()
	hover.bg_color = Color(accent.r * 0.16, accent.g * 0.16, accent.b * 0.16, 0.96)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(accent.r * 0.24, accent.g * 0.24, accent.b * 0.24, 0.98)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_font_size_override("font_size", _story_logical_px(14.0))
	button.add_theme_color_override("font_color", GameUI.TEXT)
	button.add_theme_color_override("font_hover_color", accent.lightened(0.28))

func _on_story_text_box_input(event: InputEvent) -> void:
	var pressed := false
	var source := ""
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		pressed = mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT
		source = "dialogue:mouse"
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
		source = "dialogue:touch"
	if not pressed:
		return
	AudioService.unlock_from_user_gesture()
	accept_event()
	_request_story_text_box_advance(source)

func _request_story_text_box_advance(source: String) -> bool:
	if current_screen != "STORY" or scenario_runner == null or scenario_runner.state.waiting_for_choice:
		return false
	# The first click completes a line that is still typing; the next click moves
	# to the following box. This keeps fast readers in control without skipping
	# an unread line accidentally.
	if scenario_text != null and scenario_text.visible_ratio < 0.999:
		# Do not merely assign `visible_ratio`: a still-running Tween would write
		# its older partial fraction back on the next frame, which made a phone
		# player see the beginning of an N05 line and then a clipped remainder.
		_complete_story_typewriter_reveal()
		story_auto_left = float(SettingsService.values.auto_delay)
		return true
	return _request_story_advance(source)

func _cancel_story_typewriter() -> void:
	if story_typewriter_tween != null and story_typewriter_tween.is_valid():
		story_typewriter_tween.kill()
	story_typewriter_tween = null

func _complete_story_typewriter_reveal() -> void:
	_cancel_story_typewriter()
	if scenario_text != null:
		scenario_text.visible_ratio = 1.0

func _refresh_story_dialogue_chrome(command_type: String) -> void:
	if story_speaker_eyebrow != null:
		match command_type:
			"narration": story_speaker_eyebrow.text = "LUMENBOUND · FIELD RECORD"
			"choice": story_speaker_eyebrow.text = "LUMENBOUND · RESPONSE"
			_: story_speaker_eyebrow.text = "LUMENBOUND · VOICE LINK"
	if story_click_hint != null:
		story_click_hint.text = "아래 응답을 선택해 계속" if command_type == "choice" else "대화창 클릭 / 터치로 계속  >"
	if story_page_indicator == null or scenario_runner == null:
		return
	var current_command_index := int(scenario_runner.state.current_line.get("command_index", scenario_runner.state.command_index - 1))
	var commands: Array = scenario_runner.scenario.get("commands", [])
	var progress := story_page_progress(commands, current_command_index)
	story_page_indicator.text = "PAGE · %02d / %02d" % [progress.x, progress.y] if progress.y > 0 else "PAGE · -- / --"

func _rebuild_story_presentation() -> void:
	_clear()
	_show_story(true)

func _restore_story_view_after_reflow() -> void:
	if scenario_runner == null:
		return
	var command := scenario_runner.state.current_line
	var type := str(command.get("command", ""))
	if type in ["dialogue", "narration"]:
		scenario_speaker.text = "나레이션" if type == "narration" else LocalizationService.tr_key(command.get("speaker_key", ""))
		scenario_text.text = LocalizationService.tr_key(command.get("text_key", ""))
		# A rotation is presentation-only: never restart the typewriter animation
		# or consume the remaining automatic-advance delay.  The rebuilt label
		# instead owns a stable fully revealed snapshot; the prior tween referenced
		# the discarded control and cannot be allowed to revive it.
		_complete_story_typewriter_reveal()
	elif type == "choice" or scenario_runner.state.waiting_for_choice:
		scenario_speaker.text = "선택"
		scenario_text.text = "아래 응답 중 하나를 선택해 기록을 시작하세요."
		for i in range(command.get("choices", []).size()):
			var choice: Dictionary = command.choices[i]
			var choice_button := _story_button(LocalizationService.tr_key(choice.text_key), func(index := i): _request_story_choice(index, "button:choice"), false, Vector2(0, 58) if _is_portrait_layout() else Vector2(400, 58))
			choice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scenario_choices.add_child(choice_button)
	else:
		scenario_text.text = ""
	_refresh_story_dialogue_chrome("choice" if scenario_runner.state.waiting_for_choice else type)
	if story_ui_hidden:
		scenario_text.visible = false
		scenario_speaker.visible = false
		scenario_choices.visible = false
		story_speaker_eyebrow.visible = false
		story_click_hint.visible = false
		story_page_indicator.visible = false

func story_header_data(scenario_id: String) -> Dictionary:
	var scenario := DataRegistry.by_id("scenarios", scenario_id)
	var title_key := str(scenario.get("title_key", ""))
	var localized_title := LocalizationService.tr_key(title_key) if not title_key.is_empty() else LocalizationService.tr_key("UI_STORY_TITLE")
	# Stable scenario IDs are useful diagnostics, but they are content-pipeline
	# identifiers rather than player-facing episode names. Keep them exclusively
	# behind the existing developer-mode gate.
	return {
		"title": localized_title,
		"subtitle": scenario_id if SettingsService.is_developer_mode() else "",
	}

func _stage_display_name(stage_id: String) -> String:
	var stage := DataRegistry.stage(stage_id)
	if stage.is_empty():
		return "작전 기록"
	var name_key := str(stage.get("name_key", ""))
	if name_key.is_empty():
		return "작전 기록"
	return LocalizationService.tr_key(name_key).replace(" (DEV)", "")

func result_header_data(report: Dictionary) -> Dictionary:
	var source_type := str(report.get("source_type", "BATTLE"))
	var source_id := str(report.get("source_id", ""))
	if source_id.is_empty() and source_type in ["BATTLE", "SWEEP"]:
		source_id = str(AppState.selected_stage_id)
	var title := "보상 결과"
	var subtitle := "보상 정산"
	match source_type:
		"BATTLE":
			title = "전투 결과"
			subtitle = _stage_display_name(source_id)
		"SWEEP":
			title = "소탕 결과"
			subtitle = _stage_display_name(source_id)
		"TREASURE":
			title = "탐색 보상"
			subtitle = "현장 보급품 회수"
		"MAP_EVENT":
			title = "탐색 결과"
			subtitle = "탐색 기록 완료"
		"RELAY":
			title = "릴레이 구간 결과"
			var relay: Dictionary = report.get("relay", {})
			if bool(relay.get("completed", false)):
				subtitle = "계약 완주 · 등급 %s" % str(relay.get("grade", "B"))
			elif bool(relay.get("retry", false)):
				subtitle = "현재 구간 재도전 가능"
			else:
				subtitle = "다음 구간으로 편성 잠금 유지"
	if SettingsService.is_developer_mode() and not source_id.is_empty():
		subtitle += " · [%s]" % source_id
	return {"title": title, "subtitle": subtitle}

func _advance_story() -> void:
	if scenario_runner == null: return
	# A new command always owns a new body label/value. Release an in-flight
	# typewriter first so a rapid tap, AUTO advance, skip, or orientation rebuild
	# can never let an earlier line alter the current one.
	_cancel_story_typewriter()
	# Advancing cuts the previous line's voice, as in a visual novel.
	AudioService.stop_voice()
	for choice in scenario_choices.get_children(): choice.queue_free()
	var guard := 0
	while guard < 20:
		guard += 1
		var command := scenario_runner.advance()
		_persist_story_checkpoint()
		_refresh_story_art()
		var type := str(command.get("command", ""))
		if type in ["dialogue", "narration"]:
			scenario_speaker.text = "나레이션" if type == "narration" else LocalizationService.tr_key(command.get("speaker_key", ""))
			scenario_text.text = LocalizationService.tr_key(command.get("text_key", ""))
			_refresh_story_dialogue_chrome(type)
			scenario_text.visible_ratio = 0.0
			var reveal_duration := maxf(.05, scenario_text.text.length() * float(SettingsService.values.text_speed))
			story_typewriter_tween = create_tween()
			story_typewriter_tween.tween_property(scenario_text, "visible_ratio", 1.0, reveal_duration)
			story_auto_left = float(SettingsService.values.auto_delay) + maxf(.5, scenario_text.text.length() * float(SettingsService.values.text_speed))
			# Korean text on screen, Japanese voice. AUTO already waits for the voice
			# to finish, so a voiced line only needs a short pause afterwards.
			if AudioService.play_line_voice(str(command.get("text_key", ""))):
				story_auto_left = maxf(.6, float(SettingsService.values.auto_delay) * .6)
			return
		if type == "choice":
			scenario_speaker.text = "선택"
			scenario_text.text = "아래 응답 중 하나를 선택해 기록을 시작하세요."
			_refresh_story_dialogue_chrome(type)
			for i in range(command.get("choices", []).size()):
				var choice: Dictionary = command.choices[i]
				var choice_button := _story_button(LocalizationService.tr_key(choice.text_key), func(index := i): _request_story_choice(index, "button:choice"), false, Vector2(0, 58) if _is_portrait_layout() else Vector2(400, 58))
				choice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				scenario_choices.add_child(choice_button)
			return
		if type == "start_battle":
			AppState.selected_stage_id = command.stage_id
			SceneRouter.go("FORMATION", {"after": "STAGE_DETAIL"})
			return
		if type == "end_scenario" or scenario_runner.state.finished:
			_finish_story_navigation()
			return
		if type in ["wait", "fade_in", "fade_out"]:
			continue
		if type == "play_voice":
			story_auto_left = 0.2
			return

func _request_story_advance(source: String) -> bool:
	if current_screen != "STORY" or scenario_runner == null or scenario_runner.state.waiting_for_choice: return false
	if not _consume_transition_edge("STORY_ADVANCE", source): return false
	_advance_story()
	return true

func _request_story_choice(index: int, source: String) -> bool:
	if current_screen != "STORY" or scenario_runner == null or not scenario_runner.state.waiting_for_choice: return false
	if not _consume_transition_edge("STORY_CHOICE", source): return false
	var chosen := scenario_runner.choose(index)
	if not chosen.ok: return false
	_persist_story_checkpoint()
	_advance_story()
	return true

func _persist_story_checkpoint() -> void:
	# ScenarioRunner owns the in-memory checkpoint.  The shell owns persistence:
	# Web tabs do not reliably deliver a close notification, so interactive lines
	# and choices must be written at their state boundary rather than only when a
	# screen is left intentionally.
	if scenario_runner == null or scenario_runner.state.scenario_id.is_empty():
		return
	if AppState.profile.last_scenario_position.has(scenario_runner.state.scenario_id):
		story_checkpoint_dirty = true
		if not story_checkpoint_save_scheduled:
			story_checkpoint_save_scheduled = true
			_flush_story_checkpoint_after_delay()

func _flush_story_checkpoint_after_delay() -> void:
	# Web file verification and atomic backup are intentionally off the physical
	# button edge. Coalesce rapid Next/SKIP presses, paint the new line first, and
	# persist one checkpoint after the short input burst.
	await get_tree().create_timer(0.24).timeout
	story_checkpoint_save_scheduled = false
	if not story_checkpoint_dirty:
		return
	story_checkpoint_dirty = false
	SaveService.save_game()

func _refresh_story_art() -> void:
	if scenario_runner == null: return
	if story_background != null:
		story_background.texture = story_art_texture_for_state(scenario_runner.state.cg_asset_id, scenario_runner.state.background_asset_id)
		story_background.visible = story_background.texture != null
	if story_is_cinematic and story_portrait_layer != null:
		_refresh_prologue_portrait_layer()
	var portrait_id := ""
	if not scenario_runner.state.portraits.is_empty():
		var slots := scenario_runner.state.portraits.keys()
		var portrait_data: Dictionary = scenario_runner.state.portraits[slots[slots.size() - 1]]
		portrait_id = str(portrait_data.get("asset_id", ""))
	var portrait_path := AssetRegistry.resolve(portrait_id)
	if story_portrait != null:
		story_portrait.texture = load(portrait_path) as Texture2D if not portrait_path.is_empty() else null
		story_portrait.visible = not portrait_id.is_empty()
	if story_art_status != null:
		if SettingsService.is_developer_mode():
			story_art_status.text = "CINEMATIC PROLOGUE PREVIEW" if story_is_prologue else "ART PREVIEW"

func _refresh_prologue_portrait_layer() -> void:
	for child in story_portrait_layer.get_children():
		story_portrait_layer.remove_child(child)
		child.queue_free()
	if scenario_runner == null or scenario_runner.state.portraits.is_empty():
		return
	var current_line: Dictionary = scenario_runner.state.current_line
	# Compiled lines name their speaker's art; legacy lines fall back to the key map.
	var active_asset_id := str(current_line.get("portrait_asset_id", _portrait_asset_for_speaker(str(current_line.get("speaker_key", "")))))
	var portrait_layout := _is_portrait_layout()
	var ui_scale := _portrait_ui_scale()
	var ordered_slots := ["LEFT", "CENTER", "RIGHT"]
	for slot in scenario_runner.state.portraits.keys():
		if str(slot) not in ordered_slots:
			ordered_slots.append(str(slot))
	for slot_index in range(ordered_slots.size()):
		var slot := str(ordered_slots[slot_index])
		if not scenario_runner.state.portraits.has(slot):
			continue
		var portrait_data: Dictionary = scenario_runner.state.portraits[slot]
		var asset_id := str(portrait_data.get("asset_id", ""))
		var texture := _asset_texture(asset_id)
		if texture == null:
			continue
		var art := TextureRect.new()
		art.name = "ProloguePortrait_%s" % slot
		art.texture = texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var is_active := active_asset_id.is_empty() or active_asset_id == asset_id
		# The speaker stands forward at full presence; listeners stay solid but
		# recede into shadow instead of turning into translucent ghosts.
		art.modulate = Color.WHITE if is_active else Color(0.60, 0.65, 0.76, 1.0)
		CinematicFx.live_portrait(art, "STORY_" + asset_id, {"emphasis": 1.0 if is_active else 0.0, "rim_strength": 0.55 if is_active else 0.18, "breath_amount": 0.012 if is_active else 0.008})
		_configure_prologue_portrait_rect(art, slot, portrait_layout, ui_scale)
		story_portrait_layer.add_child(art)

func _configure_prologue_portrait_rect(art: TextureRect, slot: String, portrait_layout: bool, ui_scale: float) -> void:
	art.anchor_top = 1.0
	art.anchor_bottom = 1.0
	if portrait_layout:
		match slot:
			"LEFT":
				art.anchor_left = 0.0
				art.anchor_right = 0.0
				art.offset_left = -92.0 * ui_scale
				art.offset_right = 390.0 * ui_scale
			"RIGHT":
				art.anchor_left = 1.0
				art.anchor_right = 1.0
				art.offset_left = -390.0 * ui_scale
				art.offset_right = 92.0 * ui_scale
			_:
				art.anchor_left = 0.5
				art.anchor_right = 0.5
				art.offset_left = -246.0 * ui_scale
				art.offset_right = 246.0 * ui_scale
		art.offset_top = -900.0 * ui_scale
		art.offset_bottom = -220.0 * ui_scale
		return
	match slot:
		"LEFT":
			art.anchor_left = 0.0
			art.anchor_right = 0.0
			art.offset_left = -70.0
			art.offset_right = 700.0
		"RIGHT":
			art.anchor_left = 1.0
			art.anchor_right = 1.0
			art.offset_left = -700.0
			art.offset_right = 70.0
		_:
			art.anchor_left = 0.5
			art.anchor_right = 0.5
			art.offset_left = -385.0
			art.offset_right = 385.0
	art.offset_top = -900.0
	art.offset_bottom = 36.0

func _portrait_asset_for_speaker(speaker_key: String) -> String:
	return str({
		"SPEAKER_MAERU": "portrait_chr001_dev",
		"SPEAKER_ROAN": "portrait_chr002_dev",
		"SPEAKER_NARIN": "portrait_chr003_dev",
		"SPEAKER_EDA": "portrait_chr004_dev",
		"SPEAKER_SOREN": "portrait_chr005_dev",
		"SPEAKER_IRI": "portrait_chr008_dev",
	}.get(speaker_key, ""))

func _toggle_story_auto() -> void:
	story_auto = not story_auto
	story_auto_left = 0.45
	_refresh_story_control_states()

func _refresh_story_control_states() -> void:
	if story_auto_button != null:
		story_auto_button.text = "AUTO  ON" if story_auto else "AUTO"
		story_auto_button.add_theme_color_override("font_color", Color("8ff3e3") if story_auto else Color("f4f7ff"))
	if story_skip_button != null:
		story_skip_button.tooltip_text = "프롤로그 전체 건너뛰기" if story_is_prologue else "현재 이야기 전체 건너뛰기"

func _skip_story_from_control() -> void:
	if story_is_prologue:
		_skip_prologue_to_end()
	else:
		_skip_story()

func _skip_prologue_to_end() -> void:
	if scenario_runner == null or not _consume_transition_edge("STORY_SKIP_ALL", "button:skip-all"):
		return
	var safety := 0
	while not scenario_runner.state.finished and safety < 1000:
		safety += 1
		var command := scenario_runner.advance()
		if str(command.get("command", "")) == "choice":
			scenario_runner.choose(0)
	_persist_story_checkpoint()
	_finish_story_navigation()

func _skip_story() -> void:
	if scenario_runner == null or not _consume_transition_edge("STORY_SKIP_ALL", "button:skip-story"):
		return
	var safety := 0
	while not scenario_runner.state.finished and safety < 1000:
		safety += 1
		var command := scenario_runner.advance()
		if str(command.get("command", "")) == "choice":
			scenario_runner.choose(0)
	_persist_story_checkpoint()
	_finish_story_navigation()

func _dev_skip_story() -> void:
	if not SettingsService.is_developer_mode() or scenario_runner == null: return
	var safety := 0
	while not scenario_runner.state.finished and safety < 1000:
		safety += 1
		var command := scenario_runner.advance()
		if command.get("command", "") == "choice": scenario_runner.choose(0)
		elif command.get("command", "") == "start_battle": continue
	_finish_story_navigation()

func _finish_story_navigation() -> void:
	if story_navigation_pending or current_screen != "STORY":
		return
	# STORY is entered from the home/archive as well as the chapter-map
	# progression queue. Preserve the caller's stable return contract so a
	# mandatory post-battle scene cannot strand the player in Formation.
	var destination := str(AppState.route_payload.get("after", "FORMATION"))
	if destination not in ["HOME", "ARCHIVE", "FORMATION", "STAGE_DETAIL", "STAGE_SELECT"]:
		destination = "FORMATION"
	story_checkpoint_dirty = false
	story_navigation_pending = true
	SaveService.save_game()
	# Do not clear the Story controls from inside their own pressed/gui_input
	# callback. On Web this could invalidate the active canvas-item traversal and
	# leave only the root background rendered while AudioService kept the BGM
	# alive. Commit the route on the following process frame, after the input edge
	# and pending story tweens have left the current callback stack.
	call_deferred("_commit_story_navigation", destination)

func _commit_story_navigation(destination: String) -> void:
	if not story_navigation_pending:
		return
	story_navigation_pending = false
	if current_screen != "STORY":
		return
	var region_stage := str(AppState.route_payload.get("region_destination", ""))
	var payload := {"story_return": true}
	if not region_stage.is_empty() and AppState.is_stage_unlocked(region_stage):
		var current_chapter := str(DataRegistry.stage(AppState.selected_stage_id).get("chapter_id", ""))
		if AppState.next_pending_story_trigger(current_chapter).is_empty():
			AppState.selected_stage_id = region_stage
			AppState.selected_map_node_id = ""
		else:
			payload["region_destination"] = region_stage
	scenario_runner = null
	SceneRouter.go(destination, payload)

func _show_story_log() -> void:
	if scenario_runner == null: return
	var dialog := AcceptDialog.new()
	dialog.title = "대사 로그"
	var lines: Array[String] = []
	for line in scenario_runner.state.dialogue_log:
		lines.append(LocalizationService.tr_key(line.get("speaker_key", "")) + ": " + LocalizationService.tr_key(line.get("text_key", "")))
	dialog.dialog_text = "\n\n".join(lines)
	add_child(dialog)
	dialog.popup_centered(Vector2i(980, 620))
	dialog.confirmed.connect(dialog.queue_free)

func _toggle_story_ui() -> void:
	if not SettingsService.is_developer_mode(): return
	story_ui_hidden = not story_ui_hidden
	scenario_text.visible = not story_ui_hidden
	scenario_speaker.visible = not story_ui_hidden
	scenario_choices.visible = not story_ui_hidden
	if story_speaker_eyebrow != null: story_speaker_eyebrow.visible = not story_ui_hidden
	if story_click_hint != null: story_click_hint.visible = not story_ui_hidden
	if story_page_indicator != null: story_page_indicator.visible = not story_ui_hidden
	if story_ui_hidden:
		footer_status.text = "UI 숨김 — 화면 하단 버튼으로 복구"

func _show_formation() -> void:
	CommandPresentation.formation(self)

func _show_stage_select() -> void:
	var selected_stage: Dictionary = DataRegistry.stage(AppState.selected_stage_id)
	var selected_chapter_id := str(selected_stage.get("chapter_id", "CH01"))
	_title("접근성 스테이지 목록", "챕터별 장거리 육각 맵의 목록형 보존 화면")
	var portrait := _is_portrait_layout()
	var chapter_row: Container = GridContainer.new() if portrait else HBoxContainer.new()
	if chapter_row is GridContainer:
		(chapter_row as GridContainer).columns = 1
	content.add_child(chapter_row)
	for chapter_value in DataRegistry.list_of("chapters"):
		var chapter: Dictionary = chapter_value
		var chapter_id := str(chapter.get("id", ""))
		var progress: Dictionary = AppState.profile.get("chapter_progress", {}).get(chapter_id, {})
		var chapter_name := LocalizationService.tr_key(str(chapter.get("name_key", "")))
		chapter_row.add_child(_button(chapter_name, func(id := chapter_id, first_stage := str(chapter.get("normal_stage_ids", [""])[0])): AppState.selected_stage_id = first_stage; stage_mode = "NORMAL"; _show_screen("STAGE_SELECT"), chapter_id.is_empty() or not bool(progress.get("unlocked", false)), Vector2(300 if portrait else 190, 58)))
	var mode_row: Container = GridContainer.new() if portrait else HBoxContainer.new()
	if mode_row is GridContainer:
		(mode_row as GridContainer).columns = 2
	content.add_child(mode_row)
	mode_row.add_child(_button("NORMAL", func(): stage_mode = "NORMAL"; _show_screen("STAGE_SELECT"), stage_mode == "NORMAL", Vector2(148 if portrait else 180, 60)))
	mode_row.add_child(_button("HARD", func(): stage_mode = "HARD"; _show_screen("STAGE_SELECT"), stage_mode == "HARD", Vector2(148 if portrait else 180, 60)))
	var selected_chapter: Dictionary = DataRegistry.chapter(selected_chapter_id)
	var selected_progress: Dictionary = AppState.profile.get("chapter_progress", {}).get(selected_chapter_id, {})
	if stage_mode == "HARD" and not bool(selected_progress.get("hard_unlocked", false)) and not AppState.debug_unlock_all_enabled():
		var normal_route: Array = selected_chapter.get("normal_stage_ids", [])
		var final_normal := str(normal_route.back()) if not normal_route.is_empty() else ""
		content.add_child(_label("HARD는 %s 클리어 후 해금됩니다." % _stage_display_name(final_normal), 24, Color("ffbd7a")))
	# The accessibility fallback can list an entire chapter. Keep it independently
	# scrollable so a one-column phone layout never pushes late-stage buttons
	# below the viewport with no route to reach them.
	var stage_scroll := ScrollContainer.new()
	stage_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stage_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(stage_scroll)
	var grid := GridContainer.new()
	grid.columns = 1 if portrait else 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_scroll.add_child(grid)
	for stage in DataRegistry.list_of("stages"):
		if stage.mode != stage_mode or str(stage.get("chapter_id", "")) != selected_chapter_id: continue
		var stars := int(AppState.profile.stage_stars.get(stage.id, 0))
		var unlocked := AppState.is_stage_unlocked(stage.id)
		var boss := " · 보스" if stage.boss else ""
		var stage_name := LocalizationService.tr_key(str(stage.name_key))
		grid.add_child(_button("%s%s\n권장 Lv.%d\n%s" % [stage_name, boss, stage.recommended_level, "★".repeat(stars) + "☆".repeat(3 - stars)], func(stage_id: String = str(stage.id)): AppState.selected_stage_id = stage_id; SceneRouter.go("STAGE_DETAIL"), not unlocked, Vector2(300 if portrait else 235, 120)))

func region_entry_stage(chapter_id: String) -> String:
	var chapter := DataRegistry.chapter(chapter_id)
	if chapter.is_empty(): return ""
	var progress: Dictionary = AppState.profile.get("chapter_progress", {}).get(chapter_id, {})
	if not bool(progress.get("unlocked", false)): return ""
	for route in ["required_stage_ids", "hard_stage_ids", "normal_stage_ids"]:
		for stage_id in chapter.get(route, []):
			if AppState.is_stage_unlocked(str(stage_id)) and not bool(AppState.profile.first_clear.get(stage_id, false)):
				return str(stage_id)
	var stages: Array = chapter.get("normal_stage_ids", [])
	return str(stages[0]) if not stages.is_empty() else ""

func _travel_to_region(chapter_id: String) -> void:
	var stage_id := region_entry_stage(chapter_id)
	if stage_id.is_empty(): return
	var current_chapter := str(DataRegistry.stage(AppState.selected_stage_id).get("chapter_id", ""))
	var pending := AppState.next_pending_story_trigger(current_chapter)
	if not pending.is_empty():
		# Finish the departing chapter before entering the new introduction. The
		# destination survives every queued story without granting rewards again.
		AppState.active_scenario_id = str(pending.scenario_id)
		SceneRouter.go("STORY", {"after": "STAGE_SELECT", "region_destination": stage_id})
		return
	AppState.selected_stage_id = stage_id
	AppState.selected_map_node_id = ""
	stage_mode = "NORMAL"
	SceneRouter.go("STAGE_SELECT")

func _open_region_selector() -> void:
	if get_node_or_null("RegionTravelOverlay") != null: return
	var overlay := ColorRect.new()
	overlay.name = "RegionTravelOverlay"
	overlay.z_index = 250
	overlay.color = Color("020810dd")
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var current_map = active_chapter_map_screen
	var was_paused := false
	if is_instance_valid(current_map):
		was_paused = current_map.map_simulation_paused
		current_map.map_simulation_paused = true
	var close := func():
		if is_instance_valid(current_map): current_map.map_simulation_paused = was_paused
		overlay.queue_free()
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = .06
	panel.anchor_right = .94
	panel.anchor_top = .08
	panel.anchor_bottom = .92
	panel.add_theme_stylebox_override("panel", GameUI.panel_style(Color("0b1728"), Color("7f969e"), 1, GameUI.RADIUS_PANEL, Vector4(20, 20, 20, 20), 0))
	overlay.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(_label("지역 이동", 28, Color("f1d77a")))
	box.add_child(_label("일반 작전의 마지막 보스를 격파하면 다음 지역이 열립니다. 위험 작전은 별도로 도전할 수 있습니다.", 17, Color("b3c2d2")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var entries := VBoxContainer.new()
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(entries)
	for chapter in DataRegistry.list_of("chapters"):
		var id := str(chapter.id)
		var unlocked := not region_entry_stage(id).is_empty()
		var title := LocalizationService.tr_key(str(chapter.name_key))
		var card := _panel_box(entries)
		card.name = "RegionCard_" + id
		var entry := _button(title + ("" if unlocked else " · 미개방"), func(target := id): close.call(); call_deferred("_travel_to_region", target), not unlocked, Vector2(300, 56))
		entry.name = "Travel_" + id
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(entry)
		var objective := LocalizationService.tr_key(str(chapter.get("objective_key", "")))
		if not objective.is_empty(): card.add_child(_label(objective, 16, GameUI.TEXT_MUTED))
		var cleared := 0
		for stage_id in chapter.normal_stage_ids + chapter.hard_stage_ids:
			if bool(AppState.profile.first_clear.get(stage_id, false)): cleared += 1
		var status := "작전 완료 %d / %d" % [cleared, chapter.normal_stage_ids.size() + chapter.hard_stage_ids.size()]
		if not unlocked:
			status += " · 제%d장 일반 작전 20 완료 시 개방" % (int(chapter.number) - 1)
		elif cleared < chapter.normal_stage_ids.size() + chapter.hard_stage_ids.size():
			status += " · 이어갈 작전 " + region_entry_stage(id).get_slice("-", 1)
		else:
			status += " · 탐험과 보급품 수집을 계속할 수 있습니다"
		card.add_child(_label(status, 14, GameUI.SIGNAL_SOFT))
	box.add_child(_button("목록형 접근성", func(): close.call(); SceneRouter.call_deferred("go", "STAGE_LIST_FALLBACK"), false, Vector2(260, 52)))
	box.add_child(_button("닫기", close, false, Vector2(260, 52)))

func _show_chapter_map() -> void:
	# A persisted handoff owns the normal campaign route after a chapter finale.
	# Finish the departing story first, then enter the next chapter exactly once.
	# This also repairs saves made by the older N20 -> idle-map result flow.
	var handoff: Dictionary = AppState.profile.get("campaign_transition", {})
	var destination := str(handoff.get("to_stage", ""))
	if not destination.is_empty() and AppState.is_stage_unlocked(destination):
		var from_stage := str(handoff.get("from_stage", ""))
		var from_chapter := str(DataRegistry.stage(from_stage).get("chapter_id", ""))
		AppState.queue_story_event("MAP_ENTER", "", from_chapter)
		var aftermath := AppState.next_pending_story_trigger(from_chapter)
		if not aftermath.is_empty():
			_cancel_transition_loading(_transition_loading_token_for(TRANSITION_LOADING_MAP_ENTRY))
			AppState.selected_stage_id = from_stage
			AppState.active_scenario_id = str(aftermath.scenario_id)
			SaveService.save_game()
			SceneRouter.go("STORY", {"after": "STAGE_SELECT", "region_destination": destination})
			return
		AppState.selected_stage_id = destination
		AppState.selected_map_node_id = ""
		AppState.profile.campaign_transition = {}
		stage_mode = "NORMAL"
		SaveService.save_game()
	var show_generation := chapter_map_show_generation
	var loading_token := _transition_loading_token_for(TRANSITION_LOADING_MAP_ENTRY)
	var stage_preload_started_msec := Time.get_ticks_msec()
	last_stage_preload_elapsed_msec = 0
	last_stage_preload_texture_count = 0
	last_stage_preload_cache_hit = false
	var selected_stage: Dictionary = DataRegistry.stage(AppState.selected_stage_id)
	var chapter_id := str(selected_stage.get("chapter_id", "CH01"))
	AppState.queue_story_event("MAP_ENTER", "", chapter_id)
	var pending_story := AppState.next_pending_story_trigger(chapter_id)
	if not pending_story.is_empty():
		_cancel_transition_loading(loading_token)
		AppState.active_scenario_id = str(pending_story.get("scenario_id", ""))
		SaveService.save_game()
		SceneRouter.go("STORY", {"after": "STAGE_SELECT", "origin": "CHAPTER_MAP", "region_destination": AppState.route_payload.get("region_destination", "")})
		return
	AudioService.play_bgm("audio_bgm_lobby")
	var chapter: Dictionary = DataRegistry.chapter(chapter_id)
	var map_id := AppState.map_id_for_chapter(chapter_id)
	_title(LocalizationService.tr_key(str(chapter.get("name_key", ""))), "탐색 경로를 따라 조우를 선택하고, 기존 실시간 전투에 진입합니다.")
	var loading_label := _label("전술 지도를 준비하고 있습니다…", 24, Color("8de7d1"))
	loading_label.name = "ChapterMapLoadingFeedback"
	content.add_child(loading_label)
	# Let Web paint immediate feedback before terrain meshes and map pawns are
	# constructed. Without this yield, a valid build looked like a crashed tab.
	await get_tree().process_frame
	_set_transition_loading_phase(loading_token, "작전 정보와 탐색 기록을 확인하고 있습니다", 12.0, 0.20)
	await get_tree().process_frame
	if current_screen != "STAGE_SELECT" or show_generation != chapter_map_show_generation:
		_cancel_transition_loading(loading_token)
		return
	# A preserved chapter-map already owns the validated definition and every
	# terrain/atlas batch. Reuse it before touching the macro loader: loading here
	# deep-copied and validated the entire expanded world on every battle/reward
	# return, even though the cached screen was used a few lines later.
	var map_screen: Control = _take_cached_chapter_map(map_id)
	if map_screen != null:
		_set_transition_loading_phase(loading_token, "보관된 전술 지도를 복원하고 있습니다", 88.0, 0.22)
		content.add_child(map_screen)
		active_chapter_map_screen = map_screen
		map_screen.call("resume_from_cache")
		if is_instance_valid(loading_label):
			loading_label.queue_free()
		_apply_chapter_map_shell_overrides()
		_finish_transition_loading(loading_token, "전술 지도 준비 완료")
		return
	_set_transition_loading_phase(loading_token, "지도 정보를 불러오고 있습니다", 28.0, 0.24)
	var definition: Dictionary = ChapterMapLoaderScript.load_map(map_id)
	_set_transition_loading_phase(loading_token, "경로와 조우 정보를 확인하고 있습니다", 44.0, 0.24)
	var errors: Array[String] = ChapterMapLoaderScript.validate(definition)
	if not errors.is_empty():
		content.add_child(_label("맵 데이터 검증 실패\n" + "\n".join(errors), 22, Color("ff7f8a")))
		content.add_child(_button("목록형 fail-safe 열기", func(): SceneRouter.go("STAGE_LIST_FALLBACK"), false, Vector2(260, 64)))
		_finish_transition_loading(loading_token, "Map validation needs attention")
		return
	# Web owns one explicit stage-entry preload boundary for the tactical world and
	# its visible character atlases. Projectile/VFX/background resources are kept
	# behind the separately permitted BATTLE loading boundary so map entry stays
	# within five seconds without pushing decode work into movement or treasure.
	if OS.has_feature("web"):
		var party_ids: Array = AppState.get_party()
		last_stage_preload_cache_hit = StageAssetCache.cache_hit_for_map_entry(map_id, definition, party_ids, AppState.selected_stage_id, [])
		var cache_progress_handler := Callable(self, "_on_stage_asset_cache_progress").bind(loading_token)
		if not StageAssetCache.warmup_progress_changed.is_connected(cache_progress_handler):
			StageAssetCache.warmup_progress_changed.connect(cache_progress_handler)
		var cache_warm_ok: bool = await StageAssetCache.warm_map_for_stage_select(map_id, definition, party_ids, AppState.selected_stage_id, [])
		if StageAssetCache.warmup_progress_changed.is_connected(cache_progress_handler):
			StageAssetCache.warmup_progress_changed.disconnect(cache_progress_handler)
		if current_screen != "STAGE_SELECT" or show_generation != chapter_map_show_generation:
			StageAssetCache.cancel_warmup()
			_cancel_transition_loading(loading_token)
			return
		if not cache_warm_ok:
			print("STAGE_ENTRY_PRELOAD_TIMEOUT map=%s phase=asset_cache elapsed_ms=%d" % [map_id, Time.get_ticks_msec() - stage_preload_started_msec])
			_show_loading_failure_screen("TACTICAL MAP UNAVAILABLE", "Stage asset loading stopped making progress.", "STAGE_SELECT", true)
			return
		elif not last_stage_preload_cache_hit:
			var gpu_textures: Array[Texture2D] = StageAssetCache.gpu_warm_textures()
			last_stage_preload_texture_count = await _warm_transition_gpu_textures(loading_token, gpu_textures)
	_set_transition_loading_phase(loading_token, "전술 지도 화면을 준비하고 있습니다", 56.0, 0.18)
	map_screen = ChapterMapScene.instantiate()
	map_screen.map_id = map_id
	# Pass the already validated definition into the screen. `_ready()` only
	# falls back to the loader when instantiated outside AppShell (tests/tools).
	map_screen.definition = definition
	map_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_screen.battle_requested.connect(_map_battle_requested)
	map_screen.formation_requested.connect(func(): SceneRouter.go("FORMATION"))
	map_screen.menu_requested.connect(func(): GrowthMenu.open(self))
	map_screen.fallback_requested.connect(func(): SceneRouter.go("STAGE_LIST_FALLBACK"))
	map_screen.region_requested.connect(_open_region_selector)
	map_screen.sweep_requested.connect(_map_sweep_requested)
	map_screen.treasure_reward_requested.connect(_map_treasure_reward_requested)
	var map_load_handler := Callable(self, "_on_chapter_map_load_progress").bind(loading_token, show_generation)
	map_screen.map_load_progress.connect(map_load_handler)
	# Never expose partially populated fog, an empty water plane, or a bare map
	# frame. The screen is made visible only after its complete input/terrain
	# boundary reports ready, then rendered once while the loading card still owns
	# the viewport so first interaction cannot inherit a cold WebGL upload.
	map_screen.visible = false
	content.add_child(map_screen)
	active_chapter_map_screen = map_screen
	_apply_chapter_map_shell_overrides()
	_set_transition_loading_phase(loading_token, "지형과 경로, 작전 목표를 배치하고 있습니다", 94.0, 1.65)
	# Keep explicit feedback visible until the cooperatively-built world confirms
	# that terrain, pawns and input authority are all ready. The map now yields
	# between build batches so this label and the interface remain paintable.
	var map_ready_ok := await _wait_for_map_ready_with_deadline(map_screen, stage_preload_started_msec, show_generation)
	if not map_ready_ok:
		if is_instance_valid(map_screen) and map_screen.map_load_progress.is_connected(map_load_handler):
			map_screen.map_load_progress.disconnect(map_load_handler)
		print("STAGE_ENTRY_PRELOAD_TIMEOUT map=%s phase=map_ready elapsed_ms=%d" % [map_id, Time.get_ticks_msec() - stage_preload_started_msec])
		_show_loading_failure_screen("TACTICAL MAP UNAVAILABLE", "Map loading stopped making progress. Retry or use the safe stage list.", "STAGE_SELECT", true)
		return
	if current_screen != "STAGE_SELECT" or show_generation != chapter_map_show_generation or not is_instance_valid(map_screen):
		_cancel_transition_loading(loading_token)
		return
	if map_screen.map_load_progress.is_connected(map_load_handler):
		map_screen.map_load_progress.disconnect(map_load_handler)
	if is_instance_valid(loading_label):
		loading_label.queue_free()
	map_screen.visible = true
	await get_tree().process_frame
	if OS.has_feature("web"):
		await RenderingServer.frame_post_draw
	_apply_chapter_map_shell_overrides()
	last_stage_preload_elapsed_msec = maxi(0, Time.get_ticks_msec() - stage_preload_started_msec)
	print("STAGE_ENTRY_PRELOAD_COMPLETE map=%s elapsed_ms=%d target_ms=%d within_target=%s cache_hit=%s gpu_textures=%d" % [map_id, last_stage_preload_elapsed_msec, STAGE_ENTRY_PRELOAD_TARGET_MSEC, str(last_stage_preload_elapsed_msec <= STAGE_ENTRY_PRELOAD_TARGET_MSEC), str(last_stage_preload_cache_hit), last_stage_preload_texture_count])
	_finish_transition_loading(loading_token, "전술 지도 준비 완료")

func _map_battle_requested(stage_id: String) -> void:
	# The map locks before emitting this signal. An entry rejection must return
	# ownership to that map instead of leaving an empty transaction and a hidden
	# footer behind a permanently disabled screen. Duplicate accepted requests
	# must never cancel the transition that already owns a paid battle token.
	if battle_transition_active:
		return
	if _request_battle_start("map:encounter", stage_id):
		return
	var reason := "" if AppState.relay_active() else AppState.party_block_reason()
	if reason.is_empty():
		reason = AppState.stage_entry_block_reason(stage_id)
	if reason.is_empty():
		reason = "전투 요청이 겹쳤습니다 · 다시 시도하세요"
	if is_instance_valid(active_chapter_map_screen):
		active_chapter_map_screen.recover_rejected_encounter(stage_id, reason)

func _map_sweep_requested(stage_id: String, count: int) -> void:
	AppState.selected_stage_id = stage_id
	_sweep(count)

func _map_treasure_reward_requested(report: Dictionary) -> void:
	last_rewards = report.get("rewards", {}).duplicate(true)
	last_reward_report = report.duplicate(true)
	last_battle_result = {"victory": true, "time": 0.0, "survivors": 5, "seed": AppState.battle_seed, "event_hash": "%s:%s" % [str(report.get("source_type", "EXPLORE")), str(report.get("source_id", ""))], "damage": {}, "healing": {}, "source_type": str(report.get("source_type", "TREASURE"))}
	# A treasure pickup is an in-map interaction, not a screen-owner transition.
	# Destroying and rebuilding the Web SubViewport here forced the complete macro
	# map through its entry path after every chest. Present the same authoritative
	# reward report over the live map, then resume the owed enemy phase in place.
	# No loading layer, resource warmup, terrain rebuild, or BGM switch is allowed.
	if current_screen == "STAGE_SELECT" and active_chapter_map_screen != null and is_instance_valid(active_chapter_map_screen):
		_show_map_reward_overlay()
		return
	# Defensive fallback for tools that emit a reward without an attached map.
	SceneRouter.go("RESULT")

func _show_map_reward_overlay() -> void:
	_dispose_map_reward_overlay(false)
	map_reward_layer = CanvasLayer.new()
	map_reward_layer.name = "MapRewardOverlayLayer"
	map_reward_layer.layer = 360
	add_child(map_reward_layer)
	map_reward_surface = Control.new()
	map_reward_surface.name = "MapRewardOverlaySurface"
	map_reward_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_reward_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	map_reward_surface.theme = theme
	map_reward_layer.add_child(map_reward_surface)
	var dimmer := ColorRect.new()
	dimmer.name = "MapRewardDimmer"
	dimmer.color = Color("020710d6")
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	map_reward_surface.add_child(dimmer)

	map_reward_panel = PanelContainer.new()
	map_reward_panel.name = "MapRewardPanel"
	map_reward_panel.add_theme_stylebox_override("panel", GameUI.panel_style(
		Color("081725f5"), Color("79e7d5c8"), 1, GameUI.RADIUS_MODAL,
		Vector4(32.0, 26.0, 32.0, 28.0), 18
	))
	map_reward_surface.add_child(map_reward_panel)
	var metrics := responsive_ui_metrics_for_size(_runtime_layout_size())
	var portrait := bool(metrics.portrait)
	var panel_size := Vector2(1660.0, 860.0) if portrait else Vector2(1040.0, 790.0)
	map_reward_panel.anchor_left = 0.5
	map_reward_panel.anchor_right = 0.5
	map_reward_panel.anchor_top = 0.5
	map_reward_panel.anchor_bottom = 0.5
	map_reward_panel.offset_left = -panel_size.x * 0.5
	map_reward_panel.offset_right = panel_size.x * 0.5
	map_reward_panel.offset_top = -panel_size.y * 0.5
	map_reward_panel.offset_bottom = panel_size.y * 0.5
	map_reward_panel.custom_minimum_size = panel_size

	var column := VBoxContainer.new()
	column.name = "MapRewardColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	map_reward_panel.add_child(column)
	var eyebrow := _label("FIELD SUPPLY", 18, GameUI.SIGNAL)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(eyebrow)
	var title := _label("탐색 보급품", 34, GameUI.OBJECTIVE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var separator := HSeparator.new()
	separator.modulate = Color("79e7d588")
	column.add_child(separator)
	var report_scroll := ScrollContainer.new()
	report_scroll.name = "MapRewardReportScroll"
	report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	report_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(report_scroll)
	var report_box := VBoxContainer.new()
	report_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_box.add_theme_constant_override("separation", 10)
	report_scroll.add_child(report_box)
	_add_reward_clarity(report_box, 19 if portrait else 21)
	var continue_button := preload("res://screens/command_presentation.gd").button(self, "확인 · 지도 계속", _close_map_reward_overlay, false, Vector2(560, 88))
	continue_button.name = "MapRewardContinueButton"
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_make_primary_button(continue_button)
	column.add_child(continue_button)
	continue_button.grab_focus()

func _close_map_reward_overlay() -> void:
	_dispose_map_reward_overlay(true)

func _dispose_map_reward_overlay(resume_map_turn: bool) -> void:
	if map_reward_layer != null and is_instance_valid(map_reward_layer):
		map_reward_layer.queue_free()
	map_reward_layer = null
	map_reward_surface = null
	map_reward_panel = null
	if resume_map_turn and current_screen == "STAGE_SELECT" and active_chapter_map_screen != null and is_instance_valid(active_chapter_map_screen):
		active_chapter_map_screen.call_deferred("_resume_post_reward_turn")

func _show_stage_detail() -> void:
	var stage := DataRegistry.stage(AppState.selected_stage_id)
	var skill_requirement := GrowthAdvisorScript.skill_requirement_text(stage)
	_title(LocalizationService.tr_key(str(stage.name_key)) + (" • 보스" if stage.boss else ""), "권장 Lv.%d • %d 작전력 • %d초" % [stage.recommended_level, stage.stamina_cost, stage.time_limit] + (" • " + skill_requirement if not skill_requirement.is_empty() else ""))
	var portrait := _is_portrait_layout()
	var compact_details := portrait or _is_compact_landscape_layout()
	var columns: BoxContainer = VBoxContainer.new() if compact_details else HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14 if compact_details else 18)
	content.add_child(columns)
	var wave_box := _panel_box(columns)
	wave_box.add_child(_label("적 편성 • %d 웨이브" % stage.waves.size(), 25, Color("a8b7ff")))
	wave_box.add_child(_label(_format_stage_waves(stage.waves), 21))
	var reward := DataRegistry.by_id("rewards", stage.reward_table_id)
	var reward_box := _panel_box(columns)
	reward_box.add_child(_label("획득 가능 보상", 25, Color("78e6d0")))
	reward_box.add_child(_label(_format_reward_entries(reward.get("guaranteed", [])), 21, Color("8fe0b6")))
	reward_box.add_child(_label("추가 보상\n" + _format_reward_entries(reward.get("bonus", [])), 18, Color("cdd5e3")))
	if not bool(AppState.profile.get("first_clear", {}).get(str(stage.id), false)):
		var first_clear_entries: Array = reward.get("first_clear", []) + reward.get("growth_first_clear", [])
		if not first_clear_entries.is_empty():
			reward_box.add_child(_label("첫 클리어 보상 · 성장 재료\n" + _format_reward_entries(first_clear_entries), 18, Color("f4d38a")))
	reward_box.add_child(_label("희귀 재료 8회 실패 후 다음 1회 보장\n소탕도 동일한 RewardResolver 사용", 17, Color("8e9aaf")))
	var attempts := "무제한"
	if stage.mode == "HARD":
		attempts = "무제한 (DEV)" if SettingsService.is_developer_mode() else "%d/%d" % [AppState.profile.hard_attempts.counts.get(stage.id, 0), stage.daily_attempts]
	wave_box.add_child(_label("입장 횟수 %s   현재 %s/3성" % [attempts, AppState.profile.stage_stars.get(stage.id, 0)], 20, Color("e9c979")))
	var actions: Container = GridContainer.new() if compact_details else HBoxContainer.new()
	if actions is GridContainer:
		(actions as GridContainer).columns = 2
	actions.add_theme_constant_override("separation", 10 if compact_details else 0)
	content.add_child(actions)
	var action_width := 154 if portrait else (172 if compact_details else 190)
	actions.add_child(_button("파티 편성", func(): SceneRouter.go("FORMATION"), false, Vector2(action_width, 66)))
	var start_button := _button("전투 시작", func(): _request_battle_start("button:battle_start"), not AppState.can_enter_stage(stage.id), Vector2(action_width, 66))
	_make_primary_button(start_button)
	actions.add_child(start_button)
	for count in [1, 5, 10]:
		var sweep_disabled: bool = int(AppState.profile.stage_stars.get(stage.id, 0)) < 3 or not AppState.can_enter_stage_count(stage.id, int(count))
		actions.add_child(_button("소탕 %d회" % count, func(value: int = int(count)): _sweep(value), sweep_disabled, Vector2(150 if compact_details else 160, 66)))

func _request_battle_start(source: String, stage_id := "") -> bool:
	if battle_transition_active: return false
	if not _consume_transition_edge("BATTLE_START", source): return false
	if not stage_id.is_empty(): AppState.selected_stage_id = stage_id
	return _start_battle()

func _start_battle() -> bool:
	if battle_transition_active: return false
	if not AppState.relay_active():
		var party_reason := AppState.party_block_reason()
		if not party_reason.is_empty():
			_notify(party_reason)
			return false
	if not AppState.begin_battle_transaction(AppState.selected_stage_id):
		var reason := AppState.stage_entry_block_reason(AppState.selected_stage_id)
		_notify(reason if not reason.is_empty() else "이미 처리 중인 전투가 있습니다")
		return false
	battle_transition_active = true
	_play_map_battle_transition()
	return true

func _route_to_battle_with_loading() -> void:
	# Authored contact/dialogue stays visible in `_play_map_battle_transition`.
	# Start the loading owner only after that interaction has resolved, exactly
	# where the map scene is about to be replaced by the realtime battle owner.
	var loading_token := _begin_transition_loading(TRANSITION_LOADING_BATTLE_ENTRY)
	await get_tree().process_frame
	if not battle_transition_active or current_screen not in ["STAGE_SELECT", "STAGE_DETAIL"]:
		_cancel_transition_loading(loading_token)
		return
	_set_transition_loading_phase(loading_token, "Connecting combat data", 10.0, 0.18)
	SceneRouter.go("BATTLE")

func _play_map_battle_transition() -> void:
	# Map pawns have their own CanvasLayer; a root Control veil sat behind them.
	# The briefing must occlude both the scene and every map input surface.
	var transition_layer := CanvasLayer.new()
	transition_layer.name = "EncounterBriefingCanvas"
	transition_layer.layer = 130
	add_child(transition_layer)
	var veil := ColorRect.new()
	veil.name = "R7HexSignalTransition"
	veil.theme = theme
	veil.color = Color("06101c00")
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	transition_layer.add_child(veil)
	veil.tree_exited.connect(transition_layer.queue_free)
	var encounter_map_id := AppState.map_id_for_stage(AppState.selected_stage_id)
	var special_event := AppState.pending_map_special_event(encounter_map_id)
	var encounter_presentation := AppState.pending_map_encounter_presentation(encounter_map_id)
	var focus := Label.new()
	var stage := DataRegistry.stage(AppState.selected_stage_id)
	var encounter_title := LocalizationService.tr_key(str(stage.get("name_key", AppState.selected_stage_id)))
	if not special_event.is_empty():
		encounter_title = LocalizationService.tr_key(str(special_event.get("title_key", "MAP_EVENT_DEFAULT_TITLE")))
	elif not str(encounter_presentation.get("event_title_key", "")).is_empty():
		encounter_title = LocalizationService.tr_key(str(encounter_presentation.get("event_title_key", "")))
	var encounter_heading := "적군 조우"
	if not special_event.is_empty():
		encounter_heading = LocalizationService.tr_key("MAP_EVENT_CONTACT_SIGNAL")
	elif str(encounter_presentation.get("transition_style", "")).to_upper() == "BOSS":
		encounter_heading = LocalizationService.tr_key("MAP_BOSS_CONTACT_CAPTION")
	focus.text = "%s\n%s" % [encounter_heading, encounter_title]
	focus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	focus.add_theme_font_size_override("font_size", 48)
	focus.add_theme_constant_override("outline_size", 8)
	focus.add_theme_color_override("font_outline_color", Color("06101c"))
	focus.modulate = Color("7cebd000")
	focus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(focus)
	# A ! contact is an authored event, not a decorative 1.85-second title card.
	# Its dialogue window owns input until the player chooses Next or Skip, then
	# hands off exactly once to the already-created battle transaction.  The
	# payload remains read-only presentation data: recruitment, rewards, and the
	# event-complete flag still belong exclusively to the victory resolver.
	if not special_event.is_empty():
		await _play_special_event_dialogue(veil, special_event, focus)
		veil.queue_free()
		await _route_to_battle_with_loading()
		return
	var boss_pages: Array = encounter_presentation.get("pre_battle_dialogue", [])
	if str(encounter_presentation.get("transition_style", "")) == "BOSS" and not boss_pages.is_empty():
		# The finale speaks first (station-announcement lines), then the boss
		# card reads out its name.  Presentation only: the battle transaction is
		# already owned by the pending map encounter.
		await _play_special_event_dialogue(veil, {
			"event_kind": "BOSS", "pre_battle_dialogue": boss_pages,
			"title_key": str(encounter_presentation.get("event_title_key", "MAP_EVENT_DEFAULT_TITLE")),
			"contact_outcome_key": str(encounter_presentation.get("boss_subtitle_key", "MAP_EVENT_DEFAULT_BODY")),
		}, focus)
		veil.color = Color("06101c00")
		focus.visible = true
	var boss_card: PanelContainer
	if str(encounter_presentation.get("transition_style", "")) == "BOSS":
		# This is an original signal-readout card, not a copied reference layout.
		# It only consumes map-authored localization keys and fades before the
		# unchanged realtime battle scene owns input and simulation.
		boss_card = PanelContainer.new()
		boss_card.name = "BossEncounterTitleCard"
		boss_card.set_anchors_preset(Control.PRESET_CENTER)
		var portrait_boss_layout := _is_portrait_layout()
		var boss_card_size := Vector2(1580, 620) if portrait_boss_layout else Vector2(660, 144)
		boss_card.position = -boss_card_size * 0.5 if portrait_boss_layout else Vector2(-330, 64)
		boss_card.size = boss_card_size
		boss_card.custom_minimum_size = boss_card_size
		boss_card.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var boss_style := GameUI.panel_style(Color("211a18ee"), GameUI.OBJECTIVE, 1, GameUI.RADIUS_MODAL, Vector4(24.0, 14.0, 24.0, 14.0), 12)
		boss_card.add_theme_stylebox_override("panel", boss_style)
		veil.add_child(boss_card)
		var boss_copy := VBoxContainer.new()
		boss_copy.alignment = BoxContainer.ALIGNMENT_CENTER
		boss_copy.add_theme_constant_override("separation", 3)
		boss_card.add_child(boss_copy)
		var boss_caption := _label(LocalizationService.tr_key("MAP_BOSS_CONTACT_CAPTION"), 15, Color("f3c884"))
		boss_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss_copy.add_child(boss_caption)
		var boss_name := _label(LocalizationService.tr_key(str(encounter_presentation.get("boss_name_key", "MAP_BOSS_UNKNOWN_NAME"))), 34, Color("fff0cf"))
		boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss_copy.add_child(boss_name)
		var boss_subtitle := _label(LocalizationService.tr_key(str(encounter_presentation.get("boss_subtitle_key", "MAP_BOSS_UNKNOWN_SUBTITLE"))), 17, Color("b9cfde"))
		boss_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss_copy.add_child(boss_subtitle)
	if not special_event.is_empty():
		var character := DataRegistry.character(str(special_event.get("character_id", "")))
		var contact_character_ids: Array[String] = []
		for character_id_value in special_event.get("character_ids", []):
			var contact_character_id := str(character_id_value)
			if not contact_character_id.is_empty() and not DataRegistry.character(contact_character_id).is_empty():
				contact_character_ids.append(contact_character_id)
		if contact_character_ids.is_empty() and not character.is_empty():
			contact_character_ids.append(str(character.get("id", "")))
		var event_panel := PanelContainer.new()
		event_panel.name = "CompanionEventContactCard"
		event_panel.set_anchors_preset(Control.PRESET_CENTER)
		# Every authored companion encounter uses this same card frame: the
		# recruitment outcome lives in a fixed bottom band instead of following
		# the variable-length body copy.  This is presentation-only; the
		# immutable outcome key is still owned by the map encounter payload.
		# AppShell uses a 1920-wide design canvas.  A narrow desktop card
		# became a narrow 192 physical px column in portrait Web, forcing Korean
		# copy and the recruitment result into unreadable fragments.  Portrait uses
		# the same card hierarchy but a deliberately wide, shallow frame so its
		# fixed result band has a single reliable reading line.
		var portrait_contact_layout := _is_portrait_layout()
		var event_card_size := Vector2(1680, 690) if portrait_contact_layout else Vector2(820, 300)
		event_panel.position = Vector2(-840, -330) if portrait_contact_layout else Vector2(-410, 60)
		event_panel.size = event_card_size
		event_panel.custom_minimum_size = event_card_size
		event_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var event_style := StyleBoxFlat.new()
		event_style.bg_color = Color("102638e8")
		event_style.border_color = Color("7cebd0")
		event_style.set_border_width_all(2)
		event_style.set_corner_radius_all(14)
		event_style.content_margin_left = 14
		event_style.content_margin_right = 18
		event_style.content_margin_top = 10
		event_style.content_margin_bottom = 10
		event_panel.add_theme_stylebox_override("panel", event_style)
		veil.add_child(event_panel)
		var event_layout := VBoxContainer.new()
		event_layout.add_theme_constant_override("separation", 8)
		event_panel.add_child(event_layout)
		var event_row := HBoxContainer.new()
		event_row.add_theme_constant_override("separation", 12)
		event_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		event_layout.add_child(event_row)
		if contact_character_ids.size() == 1 and not character.is_empty():
			event_row.add_child(_art_rect(str(character.get("portrait_asset_id", "")), Vector2(126, 176)))
		elif contact_character_ids.size() > 1:
			# Duo contact keeps the established card and result-band geometry, but
			# makes both faces and names independently readable before auto-battle.
			# It is presentation-only: recruitment ownership remains in AppState.
			var duo_portraits := HBoxContainer.new()
			duo_portraits.name = "DuoContactPortraits"
			duo_portraits.custom_minimum_size = Vector2(132, 132)
			duo_portraits.add_theme_constant_override("separation", 5)
			for contact_character_id in contact_character_ids.slice(0, 2):
				var contact_definition := DataRegistry.character(str(contact_character_id))
				var contact_column := VBoxContainer.new()
				contact_column.name = "DuoContactPortrait_%s" % str(contact_character_id)
				contact_column.custom_minimum_size = Vector2(63, 0)
				contact_column.alignment = BoxContainer.ALIGNMENT_CENTER
				contact_column.add_child(_art_rect(str(contact_definition.get("portrait_asset_id", "")), Vector2(62, 96)))
				var contact_name := _label(_display_character_name(str(contact_character_id)), 12, Color("f6fffe"))
				contact_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				contact_name.add_theme_constant_override("outline_size", 1)
				contact_name.add_theme_color_override("font_outline_color", Color("153e43"))
				contact_column.add_child(contact_name)
				duo_portraits.add_child(contact_column)
			event_row.add_child(duo_portraits)
		var event_copy := VBoxContainer.new()
		event_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		event_row.add_child(event_copy)
		event_copy.add_child(_label(LocalizationService.tr_key("MAP_EVENT_CONTACT_SIGNAL"), 21, Color("7cebd0")))
		event_copy.add_child(_label(_display_character_name(str(special_event.get("character_id", ""))), 34, Color("ffe28a")))
		var event_body := _label(LocalizationService.tr_key(str(special_event.get("body_key", "MAP_EVENT_DEFAULT_BODY"))), 22, Color("eef6ff"))
		event_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		event_copy.add_child(event_body)
		var outcome_key := str(special_event.get("contact_outcome_key", ""))
		if not outcome_key.is_empty():
			var outcome_panel := PanelContainer.new()
			outcome_panel.name = "CompanionOutcomePanel"
			outcome_panel.custom_minimum_size = Vector2(0, 62)
			var outcome_style := StyleBoxFlat.new()
			outcome_style.bg_color = Color("082f3ee8")
			outcome_style.border_color = Color("4fbfaa")
			outcome_style.set_border_width_all(1)
			outcome_style.set_corner_radius_all(8)
			outcome_style.content_margin_left = 12
			outcome_style.content_margin_right = 12
			outcome_panel.add_theme_stylebox_override("panel", outcome_style)
			event_layout.add_child(outcome_panel)
			var outcome_row := HBoxContainer.new()
			outcome_row.name = "CompanionOutcomeRow"
			outcome_row.add_theme_constant_override("separation", 10)
			outcome_panel.add_child(outcome_row)
			var outcome_caption := _label("조우 결과", 19, Color("b8fff2"))
			outcome_caption.custom_minimum_size = Vector2(102, 0)
			outcome_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			outcome_row.add_child(outcome_caption)
			# The caption stays quiet, while the actual recruitment rule is one
			# deliberate emphasis step brighter and thicker.  This is the only
			# readability polish suggested by the independent mobile-card review;
			# position, payload, timing and encounter authority remain unchanged.
			var outcome := _label(LocalizationService.tr_key(outcome_key), 24, Color("f5fffd"))
			outcome.name = "CompanionOutcomeText"
			outcome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			outcome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			outcome.add_theme_constant_override("outline_size", 2)
			outcome.add_theme_color_override("font_outline_color", Color("163f44"))
			outcome_row.add_child(outcome)
	var reduced := bool(SettingsService.values.get("map_reduced_transition", false))
	# A companion contact carries player-facing context, so hold it long enough
	# to be read before the existing battle scene takes ownership.  This remains
	# presentation-only and does not delay or mutate the battle transaction.
	# Event contacts are the only transitions that communicate a persistent
	# player-facing outcome.  Keep the card on screen long enough to read its
	# immediate/deferred recruitment result before battle begins.
	var duration := 0.12 if reduced else (SPECIAL_EVENT_CONTACT_DURATION if not special_event.is_empty() else (BOSS_ENCOUNTER_CARD_DURATION if boss_card != null else 0.46))
	if not special_event.is_empty() and debug_companion_card_visual_hold:
		# Visual QA uses the exact production card, then gives the browser capture
		# enough wall-clock time to sample it.  The flag is one-shot and can only
		# be armed from the Development build's explicit fixture.
		duration = 8.0
		debug_companion_card_visual_hold = false
	var intro_duration := minf(0.10, duration * 0.24)
	var outro_duration := minf(0.08, duration * 0.18)
	var hold_duration := maxf(0.02, duration - intro_duration - outro_duration)
	var tween := create_tween()
	tween.tween_property(veil, "color", Color("06101cf2"), intro_duration)
	tween.parallel().tween_property(focus, "modulate", Color("fff0c8"), intro_duration)
	if not special_event.is_empty():
		tween.parallel().tween_property(veil.get_node_or_null("CompanionEventContactCard"), "modulate", Color.WHITE, intro_duration)
	if boss_card != null:
		tween.parallel().tween_property(boss_card, "modulate", Color.WHITE, intro_duration)
	tween.tween_interval(hold_duration)
	tween.tween_property(focus, "modulate", Color("fff0c800"), outro_duration)
	if not special_event.is_empty():
		tween.parallel().tween_property(veil.get_node_or_null("CompanionEventContactCard"), "modulate", Color("ffffff00"), outro_duration)
	if boss_card != null:
		tween.parallel().tween_property(boss_card, "modulate", Color("ffffff00"), outro_duration)
	await tween.finished
	veil.queue_free()
	await _route_to_battle_with_loading()

func _event_dialogue_speaker_name(page: Dictionary) -> String:
	var speaker_kind := str(page.get("speaker_kind", "COMMAND"))
	var speaker_id := str(page.get("speaker_id", ""))
	if speaker_kind == "NARRATION":
		return LocalizationService.tr_key("MAP_EVENT_NARRATION_NAME")
	if speaker_kind in ["VOICE", "ENEMY"] and not str(page.get("speaker_key", "")).is_empty():
		return LocalizationService.tr_key(str(page.get("speaker_key", "")))
	if speaker_kind == "COMPANION":
		return _display_character_name(speaker_id)
	if speaker_kind == "ENEMY":
		var enemy := DataRegistry.enemy(speaker_id)
		return LocalizationService.tr_key(str(enemy.get("name_key", speaker_id))) if not enemy.is_empty() else LocalizationService.tr_key("MAP_EVENT_ENEMY_SIGNAL_NAME")
	return LocalizationService.tr_key("MAP_EVENT_COMMAND_NAME")

func _play_special_event_dialogue(veil: ColorRect, special_event: Dictionary, focus: Label) -> void:
	var dialogue: Array = special_event.get("pre_battle_dialogue", [])
	if dialogue.is_empty():
		dialogue = [
			{"speaker_kind": "COMMAND", "text_key": str(special_event.get("body_key", "MAP_EVENT_DEFAULT_BODY"))},
			{"speaker_kind": "COMMAND", "text_key": str(special_event.get("contact_outcome_key", "MAP_EVENT_DEFAULT_BODY"))},
		]
	var panel := preload("res://ui/bounded_briefing.gd").new()
	panel.name = "PreBattleEventDialog"
	panel.runtime_size_reader = _runtime_layout_size
	panel.modulate.a = 0.0
	veil.add_child(panel)
	var signal_label := _label(LocalizationService.tr_key("MAP_EVENT_CONTACT_SIGNAL"), 14, Color("9df5e4"))
	signal_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.type_target(signal_label, 14.0)
	panel.header.add_child(signal_label)
	var page_counter := _label("", 14, Color("cce6ec"))
	page_counter.name = "EventDialoguePage"
	page_counter.size_flags_horizontal = Control.SIZE_SHRINK_END
	page_counter.autowrap_mode = TextServer.AUTOWRAP_OFF
	panel.type_target(page_counter, 14.0)
	panel.header.add_child(page_counter)
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", _story_logical_px(12.0))
	panel.body.add_child(hero)
	var portrait_frame := PanelContainer.new()
	portrait_frame.name = "EventKeyVisual"
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.art_targets.append(portrait_frame)
	hero.add_child(portrait_frame)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_child(identity)
	var title := _label(LocalizationService.tr_key(str(special_event.get("title_key", "MAP_EVENT_DEFAULT_TITLE"))), 22, Color("ffe1a0"))
	title.name = "EventDialogueTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_override("font", _story_weighted_font(700, 0.25))
	panel.type_target(title, 22.0)
	identity.add_child(title)
	var speaker_label := _label("", 15, Color("91f5df"))
	speaker_label.name = "EventDialogueSpeaker"
	speaker_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.type_target(speaker_label, 15.0)
	identity.add_child(speaker_label)
	var dialogue_label := _label("", 18, Color("f7fbff"))
	dialogue_label.name = "EventDialogueBody"
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.add_theme_font_override("font", _story_weighted_font(510, 0.08))
	panel.type_target(dialogue_label, 18.0)
	panel.body.add_child(dialogue_label)
	var outcome_panel := PanelContainer.new()
	outcome_panel.name = "PreBattleEventOutcomeBand"
	outcome_panel.add_theme_stylebox_override("panel", GameUI.panel_style(Color("0b2b35"), Color("30685e"), 1, 8, Vector4.ZERO))
	panel.body.add_child(outcome_panel)
	var outcome := _label(LocalizationService.tr_key(str(special_event.get("contact_outcome_key", "MAP_EVENT_DEFAULT_BODY"))), 15, Color("c4e6dd"))
	outcome.name = "EventDialogueOutcome"
	outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.type_target(outcome, 15.0)
	outcome_panel.add_child(outcome)
	var hint := _label("다음 버튼으로 계속 · 긴 설명은 위로 밀어 읽기", 12, Color("9fb9c4"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.type_target(hint, 12.0)
	panel.body.add_child(hint)
	var skip_button := _button(LocalizationService.tr_key("MAP_EVENT_DIALOGUE_SKIP"), func() -> void: pass)
	skip_button.name = "EventDialogueSkip"
	panel.type_target(skip_button, 16.0)
	panel.footer.add_child(skip_button)
	var next_button := _button(LocalizationService.tr_key("MAP_EVENT_DIALOGUE_NEXT"), func() -> void: pass)
	next_button.name = "EventDialogueNext"
	_make_primary_button(next_button)
	panel.type_target(next_button, 17.0)
	panel.footer.add_child(next_button)
	# Resolve exactly the registered subject; never invent or recrop its identity.
	var art_id := ""
	if str(special_event.get("event_kind", "")) == "COMPANION":
		art_id = str(DataRegistry.character(str(special_event.get("character_id", ""))).get("portrait_asset_id", ""))
	elif str(special_event.get("event_kind", "")) == "SPECIAL_ENEMY":
		art_id = str(DataRegistry.enemy(str(special_event.get("enemy_id", ""))).get("asset_id", ""))
	elif str(special_event.get("event_kind", "")) == "BOSS" and not dialogue.is_empty():
		for boss_page_value in dialogue:
			var boss_page: Dictionary = boss_page_value if boss_page_value is Dictionary else {}
			if str(boss_page.get("speaker_kind", "")) == "ENEMY":
				art_id = str(boss_page.get("portrait_asset_id", ""))
				break
	var page_art: TextureRect = null
	if not art_id.is_empty():
		var art := _art_rect(art_id, Vector2.ZERO, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		art.name = "EventPageArt"
		art.custom_minimum_size = Vector2.ZERO
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_frame.add_child(art)
		page_art = art.get_child(0) as TextureRect
	else:
		var glyph := _label("!", 40, Color("79ecda"))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.type_target(glyph, 40.0)
		portrait_frame.add_child(glyph)
	# Lambdas capture scalar locals by value. Shared presentation state prevents
	# Next from updating only a captured copy while the await loop waits forever.
	var reading := {"page": 0, "resolved": false, "last_advance": -100000}
	var update_page := func() -> void:
		var page_index := int(reading.page)
		var page: Dictionary = dialogue[clampi(page_index, 0, dialogue.size() - 1)]
		speaker_label.text = _event_dialogue_speaker_name(page)
		dialogue_label.text = LocalizationService.tr_key(str(page.get("text_key", special_event.get("body_key", "MAP_EVENT_DEFAULT_BODY"))))
		# The speaker's own art leads each page; narration keeps the subject.
		var speaker_art := str(page.get("portrait_asset_id", ""))
		if page_art != null:
			page_art.texture = _asset_texture(speaker_art if not speaker_art.is_empty() else art_id)
		AudioService.stop_voice()
		AudioService.play_line_voice(str(page.get("text_key", "")))
		page_counter.text = "%d / %d" % [page_index + 1, dialogue.size()]
		next_button.text = LocalizationService.tr_key("MAP_EVENT_DIALOGUE_BATTLE") if page_index >= dialogue.size() - 1 else LocalizationService.tr_key("MAP_EVENT_DIALOGUE_NEXT")
		panel.rewind()
	var advance_page := func() -> void:
		var now := Time.get_ticks_msec()
		if bool(reading.resolved) or now - int(reading.last_advance) < 300: return
		reading.last_advance = now
		if int(reading.page) < dialogue.size() - 1:
			reading.page += 1
			update_page.call()
		else:
			reading.resolved = true
	skip_button.pressed.connect(func() -> void: reading.resolved = true)
	next_button.pressed.connect(advance_page)
	pre_battle_event_input_panel = panel
	pre_battle_event_input_next = next_button
	pre_battle_event_input_skip = skip_button
	pre_battle_event_advance = advance_page
	pre_battle_event_resolve = func() -> void: reading.resolved = true
	pre_battle_event_input_active = true
	update_page.call()
	panel.reflow()
	var intro := create_tween()
	intro.tween_property(veil, "color", Color("06101cf4"), 0.12)
	intro.parallel().tween_property(panel, "modulate", Color.WHITE, 0.12)
	await intro.finished
	focus.visible = false
	while not bool(reading.resolved):
		await get_tree().process_frame
	AudioService.stop_voice()
	pre_battle_event_input_active = false
	pre_battle_event_input_panel = null
	pre_battle_event_input_next = null
	pre_battle_event_input_skip = null
	pre_battle_event_advance = Callable()
	pre_battle_event_resolve = Callable()
	var outro := create_tween()
	outro.tween_property(panel, "modulate", Color("ffffff00"), 0.10)
	outro.parallel().tween_property(veil, "color", Color("06101c00"), 0.10)
	await outro.finished
	# A boss card follows on the same veil; never leave a spent dialog under it.
	panel.queue_free()

func _show_battle() -> void:
	battle_transition_active = false
	var battle_preload_started_msec := Time.get_ticks_msec()
	var loading_token := _transition_loading_token_for(TRANSITION_LOADING_BATTLE_ENTRY)
	if loading_token == 0:
		# Direct/debug battle routes still receive the same screen-owner loading
		# contract; ordinary map encounters have already created this token.
		loading_token = _begin_transition_loading(TRANSITION_LOADING_BATTLE_ENTRY)
	await get_tree().process_frame
	if current_screen != "BATTLE":
		_cancel_transition_loading(loading_token)
		return
	_set_transition_loading_phase(loading_token, "Connecting battle rules and audio", 22.0, 0.18)
	await get_tree().process_frame
	var stage := DataRegistry.stage(AppState.selected_stage_id)
	AudioService.play_bgm("audio_bgm_boss" if bool(stage.boss) else "audio_bgm_battle")
	var simulation := BattleSimulation.new()
	# Both party providers return an untyped Variant Array at runtime.  Assigning
	# that directly to the typed Array[String] fails in the Web/portrait battle
	# path before BattleView is instantiated, leaving only the background/BGM.
	# Normalize each stable ID explicitly so entry cannot blank the whole screen.
	battle_party_ids.clear()
	var selected_party_ids: Array = AppState.relay_current_squad() if AppState.relay_active() else AppState.get_party()
	for party_id_value in selected_party_ids:
		battle_party_ids.append(str(party_id_value))
	_set_transition_loading_phase(loading_token, "Checking party formation and enemy waves", 42.0, 0.20)
	await get_tree().process_frame
	var party_snapshot := AppState.relay_party_snapshot() if AppState.relay_active() else AppState.create_party_snapshot()
	if party_snapshot.size() != 5:
		AppState.abandon_battle_transaction(AppState.selected_stage_id)
		SaveService.save_game()
		_notify("전투 편성 데이터가 유효하지 않습니다. 입장 비용을 돌려드렸습니다.")
		_cancel_transition_loading(loading_token)
		SceneRouter.go("RELAY" if AppState.relay_active() else "FORMATION")
		return
	_set_transition_loading_phase(loading_token, "Initializing the real-time battle simulation", 64.0, 0.32)
	await get_tree().process_frame
	AppState.current_battle_seed = AppState.next_battle_seed()
	simulation.setup(party_snapshot, stage, AppState.current_battle_seed, DataRegistry.data, AppState.effective_battle_debug_options())
	simulation.auto_enabled = bool(SettingsService.values.battle_auto)
	_set_transition_loading_phase(loading_token, "Deploying combatants and effects", 82.0, 0.26)
	await get_tree().process_frame
	battle_view = BattleViewScene.instantiate()
	# BattleView is a canvas-drawn Control.  A VBoxContainer only grants it the
	# full combat width when it participates in the horizontal expand contract;
	# vertical expansion alone can collapse its draw rect to zero on a narrow Web
	# viewport, leaving only the lobby background and active BGM.  Keep it as one
	# full-width responsive battlefield on both desktop and portrait mobile.
	battle_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_view.custom_minimum_size = Vector2(0.0, 420.0)
	battle_view.setup(simulation)
	battle_view.speed = int(SettingsService.values.battle_speed)
	battle_view.battle_finished.connect(_battle_finished)
	battle_view.battle_assets_ready.connect(_refresh_battle_ultimate_orb_art)
	content.add_child(battle_view)
	_set_transition_loading_phase(loading_token, "Attaching the battle cache and graphics", 90.0, 0.18)
	_build_battle_overlay()
	# Cached bundles signal immediately on the deferred warmup turn; a direct/debug
	# route may use BattleView's sliced fallback. In both cases the blocking layer
	# remains authoritative until all waves, projectiles and VFX are attached.
	var battle_assets_ok := battle_view.assets_ready
	if not battle_assets_ok:
		battle_assets_ok = await _wait_for_battle_assets_with_deadline(battle_view, battle_preload_started_msec)
	if not battle_assets_ok:
		# Leaving BATTLE while assets load also ends the wait with `false`; that is
		# a normal exit handled by the new screen, not a loading failure.
		if current_screen != "BATTLE":
			_cancel_transition_loading(loading_token)
			return
		print("BATTLE_ENTRY_PRELOAD_TIMEOUT stage=%s elapsed_ms=%d" % [AppState.selected_stage_id, Time.get_ticks_msec() - battle_preload_started_msec])
		# The battle never started: release its token and entry cost so the map
		# and the next battle are not blocked until a browser reload.
		AppState.abandon_battle_transaction(AppState.selected_stage_id)
		SaveService.save_game()
		_show_loading_failure_screen("BATTLE UNAVAILABLE", "Battle asset loading stopped making progress.", "BATTLE")
		return
	if current_screen != "BATTLE" or battle_view == null or not is_instance_valid(battle_view):
		_cancel_transition_loading(loading_token)
		return
	_set_transition_loading_phase(loading_token, "Preparing battle controls", 96.0, 0.10)
	_finish_transition_loading(loading_token, "Battle ready")

func _rebuild_battle_overlay() -> void:
	if battle_view == null or battle_view.simulation == null: return
	var previous_overlay := battle_view.get_node_or_null("BattleOverlay")
	if previous_overlay != null:
		previous_overlay.free()
	# The pause center is a sibling of BattleOverlay. Rebuilding on resize must
	# retire it too, including while the battle is paused.
	if is_instance_valid(battle_pause_center):
		battle_pause_center.free()
	ultimate_buttons.clear()
	party_status_labels.clear()
	battle_hud = null
	battle_auto_button = null
	battle_speed_button = null
	battle_pause_panel = null
	battle_pause_center = null
	_build_battle_overlay()

func _build_battle_overlay() -> void:
	if battle_view == null or battle_view.simulation == null: return
	var overlay := VBoxContainer.new()
	overlay.name = "BattleOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 20
	overlay.offset_top = 20
	overlay.offset_right = -20
	overlay.offset_bottom = -24
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	var portrait := _is_portrait_layout()
	battle_portrait_layout = portrait
	var ui_scale := _portrait_ui_scale()
	overlay.add_theme_constant_override("separation", roundi(6.0 * ui_scale) if portrait else 8)
	battle_view.add_child(overlay)
	# A dark gilt-edged bar keeps wave/time and the controls legible over any
	# battlefield backdrop or effect.
	var top_bar := PanelContainer.new()
	top_bar.name = "BattleTopBar"
	top_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	var top_bar_style := GameUI.panel_style(Color(0.016, 0.035, 0.075, 0.78), Color(0.94, 0.80, 0.48, 0.55), 1, GameUI.RADIUS_PANEL, Vector4(16.0, 8.0, 12.0, 8.0), 10)
	top_bar_style.border_width_top = 0
	top_bar_style.border_width_left = 0
	top_bar_style.border_width_right = 0
	top_bar_style.border_width_bottom = 2
	top_bar.add_theme_stylebox_override("panel", top_bar_style)
	overlay.add_child(top_bar)
	var top: BoxContainer = VBoxContainer.new() if portrait else HBoxContainer.new()
	top.add_theme_constant_override("separation", roundi(5.0 * ui_scale) if portrait else 8)
	top_bar.add_child(top)
	battle_hud = _label("", 24, Color("fff4d8"))
	battle_hud.add_theme_color_override("font_outline_color", Color("050a12"))
	battle_hud.add_theme_constant_override("outline_size", 5)
	battle_hud.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	battle_hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_hud.autowrap_mode = TextServer.AUTOWRAP_OFF
	battle_hud.clip_text = true
	battle_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if portrait else HORIZONTAL_ALIGNMENT_LEFT
	battle_hud.custom_minimum_size = Vector2(0.0, 28.0 * ui_scale) if portrait else Vector2.ZERO
	top.add_child(battle_hud)
	# On a phone these are compact utility controls, not the dominant visual
	# block. Keeping them in one touch-safe row returns a full combat lane to the
	# actors instead of stacking four large text buttons above them.
	var battle_actions := HBoxContainer.new()
	battle_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	battle_actions.add_theme_constant_override("separation", roundi(5.0 * ui_scale) if portrait else 8)
	if portrait:
		battle_actions.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(battle_actions)
	battle_auto_button = CommandPresentation.button(self, "A·ON", _toggle_battle_auto, false, Vector2(160, 86))
	battle_auto_button.name = "BattleAutoButton"
	battle_auto_button.tooltip_text = "기본 공격·일반 스킬과 조건부 필살기를 자동 운용합니다."
	battle_actions.add_child(battle_auto_button)
	battle_speed_button = CommandPresentation.button(self, "×1", _cycle_battle_speed, false, Vector2(112, 86))
	battle_speed_button.name = "BattleSpeedButton"
	battle_actions.add_child(battle_speed_button)
	var pause_button := CommandPresentation.button(self, "Ⅱ", _toggle_battle_pause, false, Vector2(112, 86))
	pause_button.name = "BattlePauseButton"
	pause_button.tooltip_text = "전투를 일시정지합니다."
	battle_actions.add_child(pause_button)
	battle_skip_button = CommandPresentation.button(self, "SKIP", _skip_battle, false, Vector2(148, 86))
	battle_skip_button.name = "BattleSkipButton"
	battle_skip_button.tooltip_text = "현재 AUTO 설정과 전투 상태를 유지한 채 남은 전투를 즉시 계산합니다."
	battle_actions.add_child(battle_skip_button)
	# The shared tactical gauge is the resource every ultimate spends. A ten-cell
	# bar reads at a glance; the old "TACTICAL 0.24/10" text did not.
	battle_gauge = Control.new()
	battle_gauge.name = "BattleTacticalGauge"
	battle_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_gauge.custom_minimum_size = Vector2(0.0, 30.0 * ui_scale) if portrait else Vector2(520.0, 32.0)
	battle_gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_SHRINK_BEGIN
	battle_gauge.draw.connect(_draw_battle_gauge)
	overlay.add_child(battle_gauge)
	# Character health and shield are deliberately represented only at their
	# world positions. Repeating five HP/SH text cards over a portrait battle
	# hides the scene and competes with the head bars the player actually tracks.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay.add_child(spacer)
	var bottom: Container = GridContainer.new() if portrait else HBoxContainer.new()
	if bottom is GridContainer:
		# Face-cropped 64 CSS-pixel discs fit in one five-wide row on a 390px phone.
		# This preserves a 56px+ touch target while keeping the combat formation
		# visibly larger than the tactical controls.
		(bottom as GridContainer).columns = 5
		bottom.add_theme_constant_override("separation", roundi(5.0 * ui_scale))
	else:
		(bottom as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(bottom)
	for unit in battle_view.simulation.state.party:
		var definition := DataRegistry.character(unit.def_id)
		var skill := DataRegistry.skill(definition.ultimate_skill_id)
		var orb := BattleUltimateOrbScript.new() as Button
		orb.name = "BattleUltimateOrb_%s" % str(unit.def_id)
		orb.set_meta("composed_control", true)
		orb.custom_minimum_size = Vector2(126, 126)
		var display_name := LocalizationService.tr_key(str(definition.get("name_key", ""))).replace(" (DEV)", "")
		var fallback_portrait := _asset_texture(str(definition.get("portrait_asset_id", "")))
		(orb as BattleUltimateOrb).configure(battle_view.ultimate_orb_texture_for(str(unit.def_id), fallback_portrait), display_name, int(skill.get("tactical_cost", 10)), _battle_skill_orb_accent(definition))
		# Preserve the WebAudio trusted-gesture contract that `_button` normally
		# supplies before issuing the exact same simulation-side ultimate request.
		orb.pressed.connect(func(uid: String = str(unit.uid)):
			AudioService.unlock_from_user_gesture()
			_request_ultimate(uid)
		)
		ultimate_buttons.append(orb)
		bottom.add_child(orb)
	battle_pause_center = CenterContainer.new()
	battle_pause_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_pause_center.mouse_filter = Control.MOUSE_FILTER_STOP
	battle_pause_center.visible = battle_view.paused
	battle_view.add_child(battle_pause_center)
	battle_pause_panel = PanelContainer.new()
	battle_pause_panel.custom_minimum_size = Vector2(0 if portrait else 620, 410)
	if portrait:
		battle_pause_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	battle_pause_center.add_child(battle_pause_panel)
	var pause_box := VBoxContainer.new()
	pause_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_box.add_theme_constant_override("separation", 14)
	battle_pause_panel.add_child(pause_box)
	var pause_title := _label("전투 일시정지", 36, Color("f1d77a"))
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_box.add_child(pause_title)
	var pause_help := _label("전투를 계속하거나 설정을 변경하세요", 18, Color("91aac8"))
	pause_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_box.add_child(pause_help)
	pause_box.add_child(_button("계속", _toggle_battle_pause, false, Vector2(300, 62)))
	pause_box.add_child(_button("AUTO 전환", _toggle_battle_auto, false, Vector2(300, 62)))
	pause_box.add_child(_button("배속 변경", _cycle_battle_speed, false, Vector2(300, 62)))
	pause_box.add_child(_button("전투 SKIP", _skip_battle, false, Vector2(300, 62)))
	var pause_actions := HBoxContainer.new()
	pause_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_box.add_child(pause_actions)
	pause_actions.add_child(_button("재시작", func(): SceneRouter.go("BATTLE"), false, Vector2(190, 62)))
	pause_actions.add_child(_button("나가기", _abandon_battle, false, Vector2(190, 62)))
	_update_battle_hud()

func _update_battle_hud() -> void:
	var overlay := battle_view.get_node_or_null("BattleOverlay")
	if overlay != null: overlay.visible = not battle_view.scene_transition_active()
	var simulation := battle_view.simulation
	var remain := maxf(0, simulation.state.time_limit - simulation.state.time_elapsed)
	# On a phone the boss' world-head bar is the authoritative, immediately
	# local health read. Repeating HP, phase and shield prose in the top status
	# line made the header wrap to two rows and stole a meaningful slice of the
	# battlefield from the actors. Keep only global timing/resource context in a
	# deliberately single-line mobile rail; desktop retains the fuller encounter
	# read where it has the horizontal room.
	if battle_portrait_layout or _is_compact_landscape_layout():
		battle_hud.text = "웨이브 %d/%d  ·  %d초" % [simulation.state.wave, simulation.state.wave_count, roundi(remain)]
	else:
		var boss_text := ""
		var boss: Dictionary = battle_view.presentation_boss()
		if not boss.is_empty():
			boss_text = "   보스 %d/%d [%s]" % [boss.hp, boss.max_hp, _boss_phase_hud_label(str(boss.get("phase", "PHASE_1")))]
		battle_hud.text = "웨이브 %d/%d   남은 시간 %.1f초%s" % [simulation.state.wave, simulation.state.wave_count, remain, boss_text]
	if battle_gauge != null and is_instance_valid(battle_gauge):
		battle_gauge.queue_redraw()
	if battle_auto_button != null:
		battle_auto_button.text = "A·ON" if simulation.auto_enabled else "A·OFF"
		# AUTO on glows in the signal colour; restyle only when the state flips.
		if not battle_auto_button.has_meta("styled_auto") or bool(battle_auto_button.get_meta("styled_auto")) != simulation.auto_enabled:
			battle_auto_button.set_meta("styled_auto", simulation.auto_enabled)
			GameUI.apply_button(battle_auto_button, "primary" if simulation.auto_enabled else "secondary")
	if battle_speed_button != null:
		battle_speed_button.text = "×%d" % battle_view.speed
	for i in range(ultimate_buttons.size()):
		var unit: Dictionary = simulation.state.party[i]
		var skill := DataRegistry.skill(unit.ultimate_skill_id)
		var ready := SkillRuntime.can_use_ultimate(unit, skill, simulation.state.tactical_gauge)
		ultimate_buttons[i].disabled = not ready
		if ultimate_buttons[i] is BattleUltimateOrb:
			(ultimate_buttons[i] as BattleUltimateOrb).set_charge(simulation.state.tactical_gauge, float(skill.get("tactical_cost", 10)), ready)

func _draw_battle_gauge() -> void:
	if battle_gauge == null or battle_view == null or not is_instance_valid(battle_view) or battle_view.simulation == null:
		return
	var gauge := clampf(float(battle_view.simulation.state.tactical_gauge), 0.0, 10.0)
	var font := get_theme_default_font()
	var height := battle_gauge.size.y
	var font_size := roundi(height * .62)
	var label_width := height * 2.3
	var value_width := height * 3.6
	battle_gauge.draw_string(font, Vector2(0.0, height * .76), "전술", HORIZONTAL_ALIGNMENT_LEFT, label_width, font_size, Color("f1d77a"))
	var bar := Rect2(label_width, height * .18, maxf(40.0, battle_gauge.size.x - label_width - value_width - 8.0), height * .64)
	var gap := 3.0
	var cell_width := (bar.size.x - gap * 9.0) / 10.0
	for index in range(10):
		var cell := Rect2(bar.position + Vector2(index * (cell_width + gap), 0.0), Vector2(cell_width, bar.size.y))
		battle_gauge.draw_rect(cell, Color(0.03, 0.07, 0.12, .86))
		var fill := clampf(gauge - index, 0.0, 1.0)
		if fill > 0.0:
			battle_gauge.draw_rect(Rect2(cell.position, Vector2(cell.size.x * fill, cell.size.y)), Color("f1d77a") if fill >= 1.0 else Color("7fa9c9"))
		battle_gauge.draw_rect(cell, Color(0.95, 0.84, 0.48, .35), false, 1.0)
	battle_gauge.draw_string(font, Vector2(battle_gauge.size.x - value_width, height * .76), "%.1f / 10" % gauge, HORIZONTAL_ALIGNMENT_RIGHT, value_width, font_size, Color.WHITE)

func _battle_skill_orb_accent(definition: Dictionary) -> Color:
	# Role accents preserve quick visual recognition without creating a second
	# text-heavy HUD.  The exact portrait remains the primary identity signal.
	match str(definition.get("role", "")):
		"GUARDIAN": return Color("79e7ff")
		"MEDIC": return Color("b9ffcf")
		"VANGUARD": return Color("ffac8a")
		"STRIKER": return Color("ff91cb")
		"SNIPER": return Color("aabaff")
		"SPECIALIST": return Color("ffd58a")
		_: return Color("72dfff")

func _refresh_battle_ultimate_orb_art() -> void:
	if battle_view == null or battle_view.simulation == null:
		return
	for index in range(mini(ultimate_buttons.size(), battle_view.simulation.state.party.size())):
		if not ultimate_buttons[index] is BattleUltimateOrb:
			continue
		var unit: Dictionary = battle_view.simulation.state.party[index]
		var definition := DataRegistry.character(unit.def_id)
		var skill := DataRegistry.skill(unit.ultimate_skill_id)
		var fallback_portrait := _asset_texture(str(definition.get("portrait_asset_id", "")))
		var display_name := LocalizationService.tr_key(str(definition.get("name_key", ""))).replace(" (DEV)", "")
		(ultimate_buttons[index] as BattleUltimateOrb).configure(battle_view.ultimate_orb_texture_for(str(unit.def_id), fallback_portrait), display_name, int(skill.get("tactical_cost", 10)), _battle_skill_orb_accent(definition))

func _boss_phase_hud_label(phase_id: String) -> String:
	match phase_id:
		"PHASE_2": return LocalizationService.tr_key("BATTLE_BOSS_PHASE_2_HUD")
		"ENRAGE": return LocalizationService.tr_key("BATTLE_BOSS_ENRAGE_HUD")
		_: return LocalizationService.tr_key("BATTLE_BOSS_PHASE_1_HUD")

func _battle_party_status_style() -> StyleBoxFlat:
	return GameUI.panel_style(Color("071522d8"), Color("526f8799"), 1, GameUI.RADIUS_CONTROL, Vector4(8.0, 3.0, 8.0, 3.0), 0)

func _toggle_battle_auto() -> void:
	if battle_view == null or battle_view.simulation == null: return
	battle_view.simulation.auto_enabled = not battle_view.simulation.auto_enabled
	SettingsService.values.battle_auto = battle_view.simulation.auto_enabled
	_update_battle_hud()

func _skip_battle() -> void:
	if battle_view == null or battle_view.simulation == null or battle_view.emitted_finish or battle_view.skip_in_progress:
		return
	var skip_button := battle_skip_button
	if skip_button != null:
		skip_button.disabled = true
		skip_button.text = "계산 중…"
	var started := battle_view.skip_to_result()
	# A successful skip emits battle_finished synchronously and replaces this
	# screen.  Only restore the control when the simulation guard rejected it.
	if not started and skip_button != null and is_instance_valid(skip_button):
		skip_button.disabled = false
		skip_button.text = "▶▶" if battle_portrait_layout else "SKIP ▶"

func _request_ultimate(unit_id: String) -> void:
	if battle_view == null or battle_view.simulation == null: return
	var simulation := battle_view.simulation
	var unit := simulation.find_unit(unit_id)
	if unit.is_empty(): return
	var skill := DataRegistry.skill(unit.ultimate_skill_id)
	if str(skill.get("effect", "")) not in ["DAMAGE", "DEBUFF"]:
		simulation.request_ultimate(unit_id)
		return
	var targets := simulation.alive_enemies()
	if targets.size() <= 1:
		simulation.request_ultimate(unit_id, "" if targets.is_empty() else str(targets[0].uid))
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "필살기 대상 선택"
	dialog.dialog_text = "보스/엘리트/일반 적 중 대상을 지정하세요."
	var selector := OptionButton.new()
	selector.custom_minimum_size = Vector2(520, 64)
	for target in targets:
		selector.add_item("%s • %s • HP %s/%s" % [target.def_id, target.rank, _compact_number(int(target.hp)), _compact_number(int(target.max_hp))])
	dialog.add_child(selector)
	add_child(dialog)
	dialog.confirmed.connect(func(): simulation.request_ultimate(unit_id, str(targets[selector.selected].uid)); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(700, 300))

func _cycle_battle_speed() -> void:
	if battle_view == null: return
	battle_view.speed = battle_view.speed % 3 + 1
	SettingsService.values.battle_speed = battle_view.speed
	_update_battle_hud()

func _toggle_battle_pause() -> void:
	if battle_view == null: return
	battle_view.paused = not battle_view.paused
	if battle_pause_center != null: battle_pause_center.visible = battle_view.paused

func _compact_number(value: int) -> String:
	if absi(value) >= 1000000: return "%.1fM" % (value / 1000000.0)
	if absi(value) >= 1000: return "%.1fK" % (value / 1000.0)
	return str(value)

func _battle_finished(result: Dictionary) -> void:
	if AppState.relay_active():
		_relay_battle_finished(result)
		return
	var loading_token := 0
	# Frame yields exist only to paint the Web loader. The progression transaction
	# itself must also run deterministically when invoked by headless recovery and
	# save/refresh tests where this shell is deliberately not inside a SceneTree.
	if is_inside_tree():
		loading_token = _begin_transition_loading(TRANSITION_LOADING_BATTLE_RESULT)
		await get_tree().process_frame
		if current_screen != "BATTLE":
			_cancel_transition_loading(loading_token)
			return
	_set_transition_loading_phase(loading_token, "Finalizing battle and survivor records", 18.0, 0.20)
	last_battle_result = result
	last_rewards = {}
	last_reward_report = {}
	var pre_profile := _reward_profile_snapshot()
	var battle_map_id := AppState.map_id_for_stage(AppState.selected_stage_id)
	var pending_special_event := AppState.pending_map_special_event(battle_map_id)
	_set_transition_loading_phase(loading_token, "Checking rewards and campaign progress", 38.0, 0.24)
	if is_inside_tree():
		await get_tree().process_frame
	var first := false
	var story_queued := false
	var stage_chapter_id := ""
	if result.victory:
		var stage := DataRegistry.stage(AppState.selected_stage_id)
		stage_chapter_id = str(stage.get("chapter_id", ""))
		var stars := 1 + (1 if int(result.survivors) == 5 else 0) + (1 if float(result.time) <= float(stage.target_time) else 0)
		# A battle transaction receives one immutable token at entry.  Reloads,
		# duplicate callbacks, and result-screen revisits cannot mutate canonical
		# progression or grant it twice.  Claim is deliberately the commit gate:
		# tokenless/stale victory callbacks remain presentation-only no-ops.
		if AppState.claim_pending_reward_once(stage.id, battle_map_id):
			first = AppState.record_stage_clear(stage.id, stars)
			last_rewards = RewardService.resolve(stage.id, 1, AppState.current_battle_seed + int(result.ticks), first)
			AccountProgression.grant_stage_xp(int(stage.stamina_cost), 20 if first else 0)
			# Relationship XP goes to the members who actually fought (relay squads
			# included), not to whatever preset is active.
			for character_id in (battle_party_ids if not battle_party_ids.is_empty() else AppState.get_party()): RelationshipService.grant(character_id, 10)
			story_queued = AppState.queue_story_event("STAGE_CLEAR", str(stage.id))
	_set_transition_loading_phase(loading_token, "Applying rewards and growth updates", 68.0, 0.30)
	if is_inside_tree():
		await get_tree().process_frame
	AppState.apply_battle_result_to_map(AppState.selected_stage_id, bool(result.get("victory", false)), battle_map_id)
	var post_profile := _reward_profile_snapshot()
	var pending_story := AppState.next_pending_story_trigger() if story_queued else {}
	last_reward_report = {
		"source_type": "BATTLE",
		"source_id": AppState.selected_stage_id,
		"rewards": last_rewards.duplicate(true),
		"pre_inventory": pre_profile.get("inventory", {}).duplicate(true),
		"post_inventory": post_profile.get("inventory", {}).duplicate(true),
		"growth": GrowthAffordabilityAnalyzerScript.analyze(pre_profile, post_profile),
		"progress": {
			"first_clear": first,
			"newly_unlocked_stages": _newly_unlocked_stage_ids(pre_profile, post_profile),
			"hard_route_unlocked": not stage_chapter_id.is_empty() and not bool(pre_profile.get("chapter_progress", {}).get(stage_chapter_id, {}).get("hard_unlocked", false)) and bool(post_profile.get("chapter_progress", {}).get(stage_chapter_id, {}).get("hard_unlocked", false)),
			"pending_story_id": str(pending_story.get("scenario_id", "")),
			"event_encounter": _event_encounter_result_payload(pending_special_event, bool(result.get("victory", false))),
			"newly_recruited_characters": _newly_recruited_character_ids(pre_profile, post_profile),
		},
	}
	_set_transition_loading_phase(loading_token, "Saving the battle result", 92.0, 0.26)
	if is_inside_tree():
		await get_tree().process_frame
	var save_result := SaveService.save_game()
	if not save_result.ok:
		_cancel_transition_loading(loading_token)
		_present_transaction_save_failure("BATTLE RESULT NOT SAVED", save_result.error, func(): SceneRouter.go("RESULT"))
		return
	_set_transition_loading_phase(loading_token, "Opening the results screen", 96.0, 0.18)
	SceneRouter.go("RESULT")

func _relay_battle_finished(result: Dictionary) -> void:
	var loading_token := 0
	if is_inside_tree():
		loading_token = _begin_transition_loading(TRANSITION_LOADING_BATTLE_RESULT)
		await get_tree().process_frame
		if current_screen != "BATTLE":
			_cancel_transition_loading(loading_token)
			return
	_set_transition_loading_phase(loading_token, "Finalizing relay battle records", 20.0, 0.20)
	last_battle_result = result.duplicate(true)
	last_rewards = {}
	last_reward_report = {}
	var pre_profile := _reward_profile_snapshot()
	var relay_id := str(RelayServiceScript.active_run(AppState.profile).get("relay_id", ""))
	var outcome := RelayServiceScript.record_segment_result(AppState.profile, result)
	if not bool(outcome.get("ok", false)):
		footer_status.text = "릴레이 결과 반영 실패: %s" % str(outcome.get("error", "UNKNOWN"))
		_cancel_transition_loading(loading_token)
		SceneRouter.go("RELAY")
		return
	_set_transition_loading_phase(loading_token, "Applying relay rewards and next segment", 62.0, 0.30)
	if is_inside_tree():
		await get_tree().process_frame
	if bool(result.get("victory", false)):
		for character_id in battle_party_ids:
			RelationshipService.grant(character_id, 10)
	last_rewards = (outcome.get("rewards", {}) as Dictionary).duplicate(true)
	var post_profile := _reward_profile_snapshot()
	last_reward_report = {
		"source_type": "RELAY",
		"source_id": relay_id,
		"rewards": last_rewards.duplicate(true),
		"pre_inventory": pre_profile.get("inventory", {}).duplicate(true),
		"post_inventory": post_profile.get("inventory", {}).duplicate(true),
		"growth": GrowthAffordabilityAnalyzerScript.analyze(pre_profile, post_profile),
		"relay": {
			"victory": bool(result.get("victory", false)),
			"retry": bool(outcome.get("retry", false)),
			"advanced": bool(outcome.get("advanced", false)),
			"completed": bool(outcome.get("completed", false)),
			"first_completion": bool(outcome.get("first_completion", false)),
			"grade": str(outcome.get("grade", "")),
			"next_segment": int(outcome.get("segment_index", -1)) + 1,
		},
	}
	_set_transition_loading_phase(loading_token, "Saving the relay result", 92.0, 0.24)
	if is_inside_tree():
		await get_tree().process_frame
	var save_result := SaveService.save_game()
	if not save_result.ok:
		_cancel_transition_loading(loading_token)
		_present_transaction_save_failure("RELAY RESULT NOT SAVED", save_result.error, func(): SceneRouter.go("RESULT"))
		return
	_set_transition_loading_phase(loading_token, "Opening the results screen", 96.0, 0.18)
	SceneRouter.go("RESULT")

func _abandon_battle() -> void:
	if AppState.relay_active():
		SaveService.save_game()
		SceneRouter.go("RELAY")
		return
	AppState.abandon_pending_map_encounter(AppState.map_id_for_stage(AppState.selected_stage_id))
	SaveService.save_game()
	SceneRouter.go("STAGE_SELECT")

func _display_item_name(item_id: String) -> String:
	var item := DataRegistry.by_id("items", item_id)
	var fallback := item_id.replace("_", " ")
	return LocalizationService.tr_key(str(item.get("name_key", fallback))).replace(" (DEV)", "")

func _reward_profile_snapshot() -> Dictionary:
	# Reward/result analysis never reads live map traversal, patrol, fog, scenario
	# queues or settings. Copying the complete profile cloned those large nested
	# structures twice at battle completion and caused a visible/audio hitch.
	var source: Dictionary = AppState.profile
	return {
		"account": source.get("account", {}).duplicate(true),
		"inventory": source.get("inventory", {}).duplicate(true),
		"roster": source.get("roster", {}).duplicate(true),
		"weapons": source.get("weapons", {}).duplicate(true),
		"chapter_progress": source.get("chapter_progress", {}).duplicate(true),
		"stage_stars": source.get("stage_stars", {}).duplicate(true),
		"first_clear": source.get("first_clear", {}).duplicate(true),
	}

func _display_character_name(character_id: String) -> String:
	var definition := DataRegistry.character(character_id)
	return LocalizationService.tr_key(str(definition.get("name_key", character_id))).replace(" (DEV)", "")

func _newly_recruited_character_ids(pre_profile: Dictionary, post_profile: Dictionary) -> Array[String]:
	var recruited: Array[String] = []
	for character_value in DataRegistry.list_of("characters"):
		var character: Dictionary = character_value
		var character_id := str(character.get("id", ""))
		if character_id.is_empty():
			continue
		var before: Dictionary = pre_profile.get("roster", {}).get(character_id, {})
		var after: Dictionary = post_profile.get("roster", {}).get(character_id, {})
		if not bool(before.get("unlocked", false)) and bool(after.get("unlocked", false)):
			recruited.append(character_id)
	return recruited

func _event_encounter_result_payload(special_event: Dictionary, victory: bool, map_id := "") -> Dictionary:
	if special_event.is_empty() or not victory:
		return {}
	var character_id := str(special_event.get("character_id", ""))
	var resolved_map_id := map_id if not map_id.is_empty() else AppState.map_id_for_stage(AppState.selected_stage_id)
	var map_state := AppState.chapter_map_state(resolved_map_id)
	var recruitment_state := str(map_state.get("recruitment_states", {}).get(character_id, ""))
	var recruitment_progress: Dictionary = map_state.get("recruitment_progress", {}).get(character_id, {})
	var required_victories := int(recruitment_progress.get("required", special_event.get("battle_victories_required", 1)))
	var completed_victories := int(recruitment_progress.get("victories", 1 if victory else 0))
	return {
		"character_id": character_id,
		"recruitment_timing": str(special_event.get("recruitment_timing", "")),
		"recruit_after_stage_id": str(special_event.get("recruit_after_stage_id", "")),
		"recruitment_state": recruitment_state,
		"battle_victories_required": required_victories,
		"battle_victories_remaining": maxi(0, required_victories - completed_victories),
	}

func _display_runtime_name(runtime_id: String) -> String:
	# Runtime IDs are stable save/combat keys, not player-facing text. Every
	# result, reward, wave, and inventory view flows through this resolver so
	# CHR001 / TRAINING_NOTE_M-style implementation codes cannot leak into a
	# release build.
	var item := DataRegistry.by_id("items", runtime_id)
	if not item.is_empty():
		return LocalizationService.tr_key(str(item.get("name_key", runtime_id))).replace(" (DEV)", "")
	var character := DataRegistry.character(runtime_id)
	if not character.is_empty():
		return LocalizationService.tr_key(str(character.get("name_key", runtime_id))).replace(" (DEV)", "")
	var enemy := DataRegistry.enemy(runtime_id)
	if not enemy.is_empty():
		return LocalizationService.tr_key(str(enemy.get("name_key", runtime_id))).replace(" (DEV)", "")
	var weapon := DataRegistry.by_id("weapons", runtime_id)
	if not weapon.is_empty():
		return LocalizationService.tr_key(str(weapon.get("name_key", runtime_id))).replace(" (DEV)", "")
	return runtime_id.replace("_", " ")


func _mobile_equipment_option_text(weapon: Dictionary) -> String:
	# The data-localized full weapon title intentionally carries provenance-like
	# class and WPN identifiers for inventory diagnostics. It is much too long for
	# the 152px portrait equip cell, where it previously bled into its neighbour.
	# Keep the full name in the button tooltip, but use a player-facing compact
	# model name and explicit action inside the touch target.
	var weapon_class := str(weapon.get("weapon_class", ""))
	var ko_names := {
		"BLADE": "블레이드 코어",
		"COMPACT": "컴팩트 프레임",
		"RIFLE": "라이플 모듈",
		"HEAVY": "헤비 프레임",
		"FOCUS": "포커스 렌즈",
		"SUPPORT_DEVICE": "지원 장치",
	}
	var en_names := {
		"BLADE": "Blade Core",
		"COMPACT": "Compact Frame",
		"RIFLE": "Rifle Module",
		"HEAVY": "Heavy Frame",
		"FOCUS": "Focus Lens",
		"SUPPORT_DEVICE": "Support Device",
	}
	var model_name := str((en_names if LocalizationService.language == "en" else ko_names).get(weapon_class, _display_runtime_name(str(weapon.get("id", "")))))
	var name_key := str(weapon.get("name_key", ""))
	var marker := name_key.rfind("_V")
	var variant := 1
	if marker >= 0:
		var variant_text := name_key.substr(marker + 2)
		if variant_text.is_valid_int():
			variant = maxi(1, variant_text.to_int())
	var roman_variants := ["", "I", "II", "III", "IV", "V", "VI"]
	var variant_label := str(roman_variants[mini(variant, roman_variants.size() - 1)]) if variant < roman_variants.size() else str(variant)
	return "%s %s\n%s" % [model_name, variant_label, "EQUIP" if LocalizationService.language == "en" else "장착"]

func _growth_candidate_text(candidate: Dictionary) -> String:
	var kind := str(candidate.get("kind", ""))
	var character_id := str(candidate.get("character_id", ""))
	var character_name := _display_character_name(character_id)
	if kind == "LEVEL":
		return "%s\nLv.%d → Lv.%d 가능" % [character_name, int(candidate.get("from_level", 0)), int(candidate.get("to_level", 0))]
	if kind == "BREAKTHROUGH":
		return "%s\n돌파 B%d → B%d 가능" % [character_name, int(candidate.get("from_breakthrough", 0)), int(candidate.get("to_breakthrough", 0))]
	if kind == "SKILL":
		var definition := DataRegistry.character(character_id)
		var slot := str(candidate.get("slot", "normal"))
		var skill_id := str(definition.get(slot + "_skill_id", ""))
		var skill := DataRegistry.skill(skill_id)
		var skill_name := LocalizationService.tr_key(str(skill.get("name_key", slot.to_upper()))).replace(" (DEV)", "")
		return "%s\n%s  Lv.%d → Lv.%d 가능" % [character_name, skill_name, int(candidate.get("from_level", 0)), int(candidate.get("to_level", 0))]
	var weapon_id := str(candidate.get("weapon_id", ""))
	var weapon := DataRegistry.by_id("weapons", weapon_id)
	var weapon_name := LocalizationService.tr_key(str(weapon.get("name_key", weapon_id))).replace(" (DEV)", "")
	if kind == "WEAPON_TIER":
		return "%s\nT%d → T%d 티어업 가능" % [weapon_name, int(candidate.get("from_tier", 0)), int(candidate.get("to_tier", 0))]
	return "%s\nLv.%d → Lv.%d 가능" % [weapon_name, int(candidate.get("from_level", 0)), int(candidate.get("to_level", 0))]

func _goto_growth_candidate(candidate: Dictionary) -> void:
	growth_tab = "스킬업" if candidate.get("kind", "") == "SKILL" else ("레벨업" if candidate.get("kind", "") == "LEVEL" else "장비·돌파")
	if candidate.has("material_id"): growth_material = str(candidate.material_id)
	growth_feedback = ""
	var character_id := str(candidate.get("character_id", ""))
	if character_id.is_empty():
		var weapon_id := str(candidate.get("weapon_id", ""))
		for roster_id in AppState.profile.get("roster", {}):
			if str(AppState.profile.roster[roster_id].get("equipped_weapon_id", "")) == weapon_id:
				character_id = str(roster_id)
				break
	if character_id.is_empty(): character_id = str(AppState.get_party()[0])
	AppState.selected_character_id = character_id
	SceneRouter.go("GROWTH")

## One "권장 성장" press from the growth screen or the 메뉴: raise the party to
## the target operation's recommended profile and save. Returns the report and
## the player-facing line describing it.
func _run_recommended_growth() -> Dictionary:
	var report: Dictionary = GrowthPlanBuilderScript.execute_to_recommended(AppState.get_party())
	var summary := CommandPresentation.recommended_growth_summary(self, report)
	var message := ""
	if report.get("actions", []).is_empty():
		message = "지금 적용할 권장 성장이 없습니다" + (" · 부족: " + str(summary.shortage) if not str(summary.shortage).is_empty() else "")
	else:
		var saved := SaveService.save_game()
		growth_save_pending = not saved.ok
		message = ("권장 성장 완료" if bool(report.get("reached", false)) else "권장 성장 일부 적용") + " · " + str(summary.headline)
		if not str(summary.shortage).is_empty(): message += " · 부족: " + str(summary.shortage)
		if not saved.ok: message += " · 저장하지 못했습니다. 저장을 다시 시도하세요."
	footer_status.text = message
	return {"report": report, "message": message}

func _apply_recommended_growth() -> void:
	growth_feedback = str(_run_recommended_growth().message)
	_show_screen("GROWTH")

func _reward_item_card(parent: Node, item_name: String, amount: int, before: int, after: int, font_size: int) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, 92.0 * _portrait_ui_scale())
	var style := GameUI.panel_style(GameUI.SURFACE_RAISED, Color("6ce6d066"), 1, GameUI.RADIUS_CONTROL, Vector4(18.0, 9.0, 18.0, 9.0), 0)
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	card.add_child(body)
	var heading := HBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(heading)
	var name_label := _label(item_name, font_size + 1, Color("e7f7f4"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(name_label)
	var amount_label := _label("+%s" % MathUtil.comma(amount), font_size + 6, Color("76f1c9"))
	amount_label.name = "RewardAmount"
	amount_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	amount_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(amount_label)
	body.add_child(_label("보유량   %s  →  %s" % [MathUtil.comma(before), MathUtil.comma(after)], font_size - 1, Color("b8d8e5")))

func _reward_summary_card(parent: VBoxContainer, text_value: String, font_size: int) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := GameUI.panel_style(Color("2a251d"), Color("e7bf6877"), 1, GameUI.RADIUS_CONTROL, Vector4(18.0, 11.0, 18.0, 11.0), 0)
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	card.add_child(_label(text_value, font_size, Color("e6edf8")))

func _add_reward_clarity(parent: VBoxContainer, font_size: int, include_growth := true) -> void:
	var source_type := str(last_reward_report.get("source_type", "BATTLE"))
	parent.add_child(_label("보상 내역 · 탐색 보상" if source_type != "BATTLE" else "보상 내역 · 전투 보상", font_size + 5, Color("8fe0b6")))
	var rewards: Dictionary = last_reward_report.get("rewards", last_rewards)
	var before_inventory: Dictionary = last_reward_report.get("pre_inventory", {})
	var after_inventory: Dictionary = last_reward_report.get("post_inventory", AppState.profile.get("inventory", {}))
	if rewards.is_empty():
		parent.add_child(_label("획득 보상 없음", font_size, Color("91aac8")))
	else:
		# At the 1280×720 review size a single reward column pushes the NEW
		# affordance below the fold. Two compact cards preserve item diffs while
		# keeping the growth impact visible without a scroll on landscape screens.
		var reward_grid := GridContainer.new()
		reward_grid.columns = 1 if _is_portrait_layout() or _runtime_layout_size().x < 1000 or source_type != "BATTLE" else 2
		reward_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reward_grid.add_theme_constant_override("h_separation", 10)
		reward_grid.add_theme_constant_override("v_separation", 8)
		parent.add_child(reward_grid)
		var reward_keys: Array = rewards.keys()
		reward_keys.sort()
		for item_id in reward_keys:
			var before := int(before_inventory.get(item_id, 0))
			var after := int(after_inventory.get(item_id, before + int(rewards[item_id])))
			_reward_item_card(reward_grid, _display_item_name(str(item_id)), int(rewards[item_id]), before, after, font_size)
	if not include_growth:
		_add_progress_unlock_summary(parent, font_size)
		return
	var growth: Dictionary = last_reward_report.get("growth", {})
	var newly: Array = growth.get("newly_affordable", [])
	if source_type != "BATTLE" and newly.is_empty():
		parent.add_child(_label("획득한 보급품을 인벤토리에 보관했습니다.", font_size, GameUI.TEXT_MUTED))
		return
	parent.add_child(_label("이번 보상으로 새롭게 가능한 성장", font_size + 5, Color("f1d77a")))
	if newly.is_empty():
		_reward_summary_card(parent, "새로 열린 성장 없음\n이번 보상으로 새롭게 열린 성장 항목은 없습니다.", font_size - 1)
	else:
		for candidate in newly:
			var candidate_button := _button("NEW  ·  " + _growth_candidate_text(candidate), func(value: Dictionary = candidate.duplicate(true)): _goto_growth_candidate(value), false, Vector2(460, 76))
			_make_primary_button(candidate_button)
			parent.add_child(candidate_button)
	var summary: Dictionary = growth.get("summary", {})
	_reward_summary_card(parent, "현재 재료로 성장 가능한 후보\n레벨업 %d명 · 돌파 %d명 · 스킬 %d명 · 무기 강화 %d개 · 티어업 %d개" % [int(summary.get("level_characters", 0)), int(summary.get("breakthrough_characters", 0)), int(summary.get("skill_characters", 0)), int(summary.get("weapon_levels", 0)), int(summary.get("weapon_tiers", 0))], font_size)
	_add_progress_unlock_summary(parent, font_size)

func _unlocked_stage_ids_for_profile(profile_snapshot: Dictionary) -> Array[String]:
	var unlocked: Array[String] = []
	var stars: Dictionary = profile_snapshot.get("stage_stars", {})
	for stage_value in DataRegistry.list_of("stages"):
		var stage: Dictionary = stage_value
		var stage_id := str(stage.get("id", ""))
		var stage_number := int(stage.get("stage_number", 0))
		var chapter_id := str(stage.get("chapter_id", ""))
		var chapter_progress: Dictionary = profile_snapshot.get("chapter_progress", {}).get(chapter_id, {})
		var chapter_definition: Dictionary = DataRegistry.chapter(chapter_id)
		if not bool(chapter_progress.get("unlocked", false)):
			continue
		var is_unlocked := false
		if str(stage.get("mode", "NORMAL")) == "HARD":
			var hard_route: Array = chapter_definition.get("hard_stage_ids", [])
			var prior_hard_id := str(hard_route[stage_number - 2]) if stage_number > 1 and stage_number - 2 < hard_route.size() else ""
			is_unlocked = bool(chapter_progress.get("hard_unlocked", false)) and (stage_number == 1 or int(stars.get(prior_hard_id, 0)) > 0)
		else:
			is_unlocked = stage_number == 1 or int(chapter_progress.get("normal_highest", 0)) >= stage_number - 1
		if is_unlocked and not stage_id.is_empty():
			unlocked.append(stage_id)
	unlocked.sort()
	return unlocked

func _newly_unlocked_stage_ids(pre_profile: Dictionary, post_profile: Dictionary) -> Array[String]:
	var before := _unlocked_stage_ids_for_profile(pre_profile)
	var newly: Array[String] = []
	for stage_id in _unlocked_stage_ids_for_profile(post_profile):
		if not before.has(stage_id):
			newly.append(stage_id)
	return newly

func _add_progress_unlock_summary(parent: VBoxContainer, font_size: int) -> void:
	var progress: Dictionary = last_reward_report.get("progress", {})
	var lines: Array[String] = []
	if bool(progress.get("first_clear", false)):
		lines.append("첫 클리어 기록 완료")
	var newly: Array = progress.get("newly_unlocked_stages", [])
	for stage_id_value in newly:
		var stage := DataRegistry.stage(str(stage_id_value))
		lines.append("새 작전 해금 · %s" % LocalizationService.tr_key(str(stage.get("name_key", stage_id_value))))
	if bool(progress.get("hard_route_unlocked", false)):
		lines.append("HARD 탐색 경로가 열렸습니다.")
	var event_encounter: Dictionary = progress.get("event_encounter", {})
	if not event_encounter.is_empty():
		var event_name := _display_character_name(str(event_encounter.get("character_id", "")))
		if str(event_encounter.get("recruitment_state", "")) == "READY":
			lines.append(LocalizationService.tr_key("RESULT_EVENT_RECRUITED") % event_name)
		elif str(event_encounter.get("recruitment_state", "")) == "PENDING":
			var remaining_battles := int(event_encounter.get("battle_victories_remaining", 0))
			if remaining_battles > 0:
				lines.append(LocalizationService.tr_key("RESULT_EVENT_TRACKING_BATTLES") % [event_name, remaining_battles])
			else:
				var later_stage := DataRegistry.stage(str(event_encounter.get("recruit_after_stage_id", "")))
				var later_name := LocalizationService.tr_key(str(later_stage.get("name_key", "")))
				lines.append(LocalizationService.tr_key("RESULT_EVENT_TRACKING") % [event_name, later_name])
	for character_id_value in progress.get("newly_recruited_characters", []):
		var recruited_name := _display_character_name(str(character_id_value))
		var recruited_line := LocalizationService.tr_key("RESULT_EVENT_RECRUITED") % recruited_name
		if not lines.has(recruited_line):
			lines.append(recruited_line)
	var scenario_id := str(progress.get("pending_story_id", ""))
	if not scenario_id.is_empty():
		var scenario := DataRegistry.by_id("scenarios", scenario_id)
		var title_key := str(scenario.get("title_key", ""))
		lines.append("이어지는 이야기 · %s" % (LocalizationService.tr_key(title_key) if not title_key.is_empty() else LocalizationService.tr_key("UI_STORY_TITLE")))
	if not lines.is_empty():
		_reward_summary_card(parent, "진행 변화\n" + "\n".join(lines), font_size)
	var relay: Dictionary = last_reward_report.get("relay", {})
	if not relay.is_empty():
		var relay_lines: Array[String] = []
		if bool(relay.get("retry", false)):
			relay_lines.append("현재 구간 패배 · 앞선 구간 승리와 부대 잠금은 유지됩니다.")
		elif bool(relay.get("completed", false)):
			relay_lines.append("계약 완주 · 등급 %s" % str(relay.get("grade", "B")))
			relay_lines.append("첫 완주 보상 지급" if bool(relay.get("first_completion", false)) else "재도전 기록 갱신 · 첫 완주 보상은 이미 수령했습니다.")
		elif bool(relay.get("advanced", false)):
			relay_lines.append("%d구간 완료 · 다음 부대가 출전합니다." % int(relay.get("next_segment", 0)))
		if not relay_lines.is_empty():
			_reward_summary_card(parent, "릴레이 진행\n" + "\n".join(relay_lines), font_size)

func _result_feature_character() -> Dictionary:
	return result_feature_character_for_report(last_reward_report, battle_party_ids if not battle_party_ids.is_empty() else AppState.get_party())

func _reward_celebration_queue() -> Array[Dictionary]:
	# Result presentation reads the committed delta only. It cannot call a
	# reward/recruitment/progression service, so close/skip/rebuild/reload never
	# turns a visual acknowledgement into a second grant.
	var entries: Array[Dictionary] = []
	var progress: Dictionary = last_reward_report.get("progress", {})
	# The result header already says VICTORY. A card is only worth a tap when
	# something new happened: a first clear, a recruit or a key item.
	if bool(last_battle_result.get("victory", false)) and bool(progress.get("first_clear", false)):
		entries.append({
			"kind": "CLEAR",
			"eyebrow": "FIRST CLEAR" if bool(progress.get("first_clear", false)) else "OPERATION COMPLETE",
			"title": "첫 작전 클리어 기록" if bool(progress.get("first_clear", false)) else "작전 승리",
			"body": "승리 기록이 확정되었습니다. 이어지는 획득 보상을 확인하세요.",
			"character": _result_feature_character(),
			"accent": Color("9cb8ff"),
		})
	# New allies are individual cards and use the actual transition delta. A
	# deferred contact therefore appears only on the later victory where its
	# authored recruitment gate is really met.
	for character_id_value in progress.get("newly_recruited_characters", []):
		var character := DataRegistry.character(str(character_id_value))
		if not character.is_empty():
			entries.append({
				"kind": "ALLY",
				"eyebrow": "NEW ALLY JOINED",
				"title": "%s 합류" % _display_character_name(str(character.get("id", ""))),
				"body": "동료 계약이 확정되었습니다. 파티·성장 화면에서 바로 편성할 수 있습니다.",
				"character": character,
				"accent": Color("ffd77a"),
			})
	# Only data-authored RARE/MAJOR item deltas become individual celebration
	# pages; credit and ordinary consumables stay in the concise reward ledger.
	var rewards: Dictionary = last_reward_report.get("rewards", last_rewards)
	var reward_ids: Array = rewards.keys()
	reward_ids.sort()
	for item_id_value in reward_ids:
		var item_id := str(item_id_value)
		var item := DataRegistry.by_id("items", item_id)
		if str(item.get("presentation_tier", "STANDARD")) not in ["RARE", "MAJOR"]:
			continue
		entries.append({
			"kind": "KEY_ITEM",
			"eyebrow": "KEY ACQUISITION",
			"title": _display_item_name(item_id),
			"body": "%s 등급 전리품  +%s" % [str(item.get("presentation_tier", "RARE")), MathUtil.comma(int(rewards[item_id]))],
			"character": _result_feature_character(),
			"accent": Color("81e9d5") if str(item.get("presentation_tier", "")) == "RARE" else Color("ffd77a"),
		})
	return entries

func _add_reward_celebration(parent: Node, font_size: int, compact := false) -> void:
	var celebrations := _reward_celebration_queue()
	if celebrations.is_empty():
		return
	var card := PanelContainer.new()
	card.name = "RewardCelebrationQueue"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var card_style := GameUI.panel_style(Color("0a1d29f2"), GameUI.SIGNAL, 1, GameUI.RADIUS_MODAL, Vector4(14, 14, 14, 14), 8)
	card.add_theme_stylebox_override("panel", card_style)
	# Containers own the height. The former fixed-height Control let its bottom
	# buttons grow past the card when the mobile font/touch-size policy ran.
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	card.add_child(layout)
	var copy_row := HBoxContainer.new()
	layout.add_child(copy_row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 5)
	copy_row.add_child(copy)
	var art := TextureRect.new()
	art.name = "RewardCelebrationHalfBodyArt"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(140, 160) if not compact else Vector2.ZERO
	art.modulate = Color(1.0, 1.0, 1.0, 0.72)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy_row.add_child(art)
	var eyebrow := _label("", font_size - 1, Color("81e9d5"))
	copy.add_child(eyebrow)
	var title := _label("", font_size + (7 if compact else 10), Color("fff4d4"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_color_override("font_outline_color", Color("05111d"))
	copy.add_child(title)
	var body := _label("", font_size, Color("d8edf3"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(body)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	layout.add_child(controls)
	var page_counter := _label("", font_size - 2, Color("b8d8e5"))
	page_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls.add_child(page_counter)
	var skip_button := CommandPresentation.button(self, "접기", func() -> void: pass, false, Vector2(190, 72))
	skip_button.name = "RewardCelebrationSkip"
	skip_button.size_flags_horizontal = Control.SIZE_FILL
	controls.add_child(skip_button)
	var next_button := CommandPresentation.button(self, "다음", func() -> void: pass, false, Vector2(220, 72))
	next_button.name = "RewardCelebrationNext"
	next_button.size_flags_horizontal = Control.SIZE_FILL
	controls.add_child(next_button)
	if compact:
		for button in [skip_button, next_button]:
			button.set_meta("compact_reward_control", true)
			button.custom_minimum_size = Vector2(106, 52) * _portrait_ui_scale()
			button.add_theme_font_size_override("font_size", roundi(15.0 * _portrait_ui_scale()))
	var queue_index := 0
	var show_entry: Callable
	show_entry = func() -> void:
		var entry: Dictionary = celebrations[queue_index]
		var accent: Color = entry.get("accent", Color("81e9d5"))
		card_style.border_color = accent
		eyebrow.text = str(entry.get("eyebrow", "ACQUISITION"))
		eyebrow.add_theme_color_override("font_color", accent)
		title.text = str(entry.get("title", ""))
		body.text = str(entry.get("body", ""))
		page_counter.text = "%d / %d" % [queue_index + 1, celebrations.size()]
		next_button.text = "확인" if queue_index >= celebrations.size() - 1 else "다음"
		var entry_character: Dictionary = entry.get("character", {})
		art.texture = _asset_texture(str(entry_character.get("portrait_asset_id", ""))) if not entry_character.is_empty() else null
		art.visible = not compact and art.texture != null
		card.modulate = Color(1.0, 1.0, 1.0, 0.0)
		card.scale = Vector2(0.985, 0.985)
		var reveal := create_tween()
		reveal.set_parallel(true)
		reveal.tween_property(card, "modulate", Color.WHITE, 0.14)
		reveal.tween_property(card, "scale", Vector2.ONE, 0.18)
	show_entry.call()
	skip_button.pressed.connect(func() -> void: card.queue_free())
	next_button.pressed.connect(func() -> void:
		if queue_index >= celebrations.size() - 1:
			card.queue_free()
			return
		queue_index += 1
		show_entry.call()
	)

func result_feature_character_for_report(report: Dictionary, party: Array) -> Dictionary:
	# A companion-contact victory is a story result as well as a battle result.
	# The eventual N09-style recruitment has no pending special-event payload, so
	# newly committed recruits take precedence. This prevents a genuine delayed
	# join notice from being paired with an unrelated party-lead portrait.
	var progress: Dictionary = report.get("progress", {})
	for recruited_id_value in progress.get("newly_recruited_characters", []):
		var recruited_character := DataRegistry.character(str(recruited_id_value))
		if not recruited_character.is_empty():
			return recruited_character
	var event_encounter: Dictionary = progress.get("event_encounter", {})
	var event_character_id := str(event_encounter.get("character_id", ""))
	if not event_character_id.is_empty():
		var event_character := DataRegistry.character(event_character_id)
		if not event_character.is_empty():
			return event_character
	return DataRegistry.character(str(party[0])) if not party.is_empty() else {}

func _result_map_action_text() -> String:
	var target := str(AppState.profile.get("campaign_transition", {}).get("to_stage", ""))
	if target.is_empty(): return "지도로"
	var chapter := DataRegistry.chapter(str(DataRegistry.stage(target).get("chapter_id", "")))
	return "제%d장으로 ›" % int(chapter.get("number", 1))

func _show_result() -> void:
	var loading_token := _transition_loading_token_for(TRANSITION_LOADING_BATTLE_RESULT)
	var result_build_started_msec := Time.get_ticks_msec()
	print("RESULT_BUILD_TRACE step=start")
	_set_transition_loading_phase(loading_token, "Building the battle report", 97.0, 0.10)
	var result_header := result_header_data(last_reward_report)
	_title(str(result_header.title), str(result_header.subtitle))
	print("RESULT_BUILD_TRACE step=header")
	# `_show_screen()` is intentionally synchronous.  Suspending this owner at a
	# process-frame boundary lets the Web screen dispatcher return while RESULT
	# owns only its header; a later layout refresh can then clear that partial tree
	# and leave the canvas behind the 96% loader empty.  Result controls are cheap
	# and their textures are already in the retained battle cache, so construct the
	# complete tree in this call and release the loader asynchronously afterwards.
	# A desktop-side illustration/report split spills past a 390 px portrait
	# viewport.  Keep the complete report scrollable, but reserve a separate
	# bottom action rail inside the device safe area so map return is never
	# stranded below the fold.
	if _is_portrait_layout():
		_show_result_portrait()
		_set_transition_loading_phase(loading_token, "Finalizing result actions", 99.0, 0.08)
		AudioService.play_bgm("audio_bgm_lobby")
		print("RESULT_SCREEN_READY elapsed_ms=%d layout=portrait" % maxi(0, Time.get_ticks_msec() - result_build_started_msec))
		_finish_transition_loading(loading_token, "Battle results ready")
		return
	# Header (stars and missed conditions) → MVP and contribution → rewards.
	# Growth lives in the lobby / map "메뉴". The report scrolls independently from
	# the action rail so map return is never pushed below the safe area.
	ResultPresentation.build_landscape(self)
	print("RESULT_BUILD_TRACE step=report")
	var actions := HBoxContainer.new()
	content.add_child(actions)
	var result_is_relay := str(last_reward_report.get("source_type", "")) == "RELAY"
	# Growth is reached from the lobby / map "메뉴", not from the result.
	actions.add_child(CommandPresentation.button(self, "릴레이 작전" if result_is_relay else _result_map_action_text(), func(): SceneRouter.go("RELAY" if result_is_relay else "STAGE_SELECT", {"result_return": true}), false, Vector2(300, 84)))
	actions.add_child(CommandPresentation.button(self, "본부", func(): SceneRouter.go("HOME"), false, Vector2(200, 84)))
	print("RESULT_BUILD_TRACE step=actions")
	_set_transition_loading_phase(loading_token, "Finalizing result actions", 99.0, 0.08)
	AudioService.play_bgm("audio_bgm_lobby")
	print("RESULT_SCREEN_READY elapsed_ms=%d layout=landscape" % maxi(0, Time.get_ticks_msec() - result_build_started_msec))
	_finish_transition_loading(loading_token, "Battle results ready")

func _show_result_portrait() -> void:
	var ui_scale := _portrait_ui_scale()
	var report_scroll := preload("res://ui/touch_progression_scroll.gd").new()
	report_scroll.name = "PrimaryContentScroll"
	report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	report_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	report_scroll.follow_focus = true
	report_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	report_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(report_scroll)
	var report := VBoxContainer.new()
	report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report.add_theme_constant_override("separation", roundi(10.0 * ui_scale))
	report_scroll.add_child(report)
	ResultPresentation.build_portrait(self, report, ui_scale * .8)
	var box := _panel_box(report)
	_add_reward_celebration(box, 15, true)
	_add_reward_clarity(box, 16, false)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", roundi(7.0 * ui_scale))
	content.add_child(actions)
	var result_is_relay := str(last_reward_report.get("source_type", "")) == "RELAY"
	actions.add_child(_button("릴레이 작전으로" if result_is_relay else _result_map_action_text(), func(): SceneRouter.go("RELAY" if result_is_relay else "STAGE_SELECT", {"result_return": true}), false, Vector2(320, 52)))
	actions.add_child(_button("홈", func(): SceneRouter.go("HOME"), false, Vector2(320, 52)))

func _open_growth_menu_tab(tab: String) -> void:
	AppState.selected_character_id = GrowthMenu.member_for(tab)
	growth_tab = tab
	growth_target_level = 0
	growth_feedback = ""
	SceneRouter.go("GROWTH")

func _growth_menu_button(minimum := Vector2(128, 56)) -> Button:
	return GrowthMenu.button(self, minimum)

# The relay operation screen carries the growth "메뉴" at the right of its header.
func _add_header_growth_menu() -> void:
	var header := content.get_node_or_null("ScreenHeader") as BoxContainer
	if header == null: return
	var menu := _growth_menu_button(Vector2(160, 76))
	menu.size_flags_horizontal = Control.SIZE_SHRINK_END
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	GameUI.apply_button(menu, "objective")
	header.add_child(menu)

func _sweep(count: int) -> void:
	var pre_profile := _reward_profile_snapshot()
	var sweep_seed := AppState.next_battle_seed() + count
	var result := RewardService.sweep(AppState.selected_stage_id, count, sweep_seed)
	if result.ok:
		last_battle_result = {"victory": true, "time": 0.0, "survivors": 5, "seed": sweep_seed, "event_hash": "SWEEP_USES_REWARD_RESOLVER", "damage": {}, "healing": {}}
		last_rewards = result.value
		var post_profile := _reward_profile_snapshot()
		last_reward_report = {
			"source_type": "SWEEP", "source_id": AppState.selected_stage_id,
			"rewards": last_rewards.duplicate(true),
			"pre_inventory": pre_profile.get("inventory", {}).duplicate(true),
			"post_inventory": post_profile.get("inventory", {}).duplicate(true),
			"growth": GrowthAffordabilityAnalyzerScript.analyze(pre_profile, post_profile),
		}
		SaveService.save_game()
		SceneRouter.go("RESULT")
	else: footer_status.text = result.error

func _show_roster() -> void:
	preload("res://screens/command_presentation.gd").roster(self)

func _show_growth() -> void:
	preload("res://screens/command_presentation.gd").growth(self)

func _growth_cost_rows(parent: Node, cost: Dictionary) -> bool:
	var affordable := not cost.is_empty()
	for id_value in cost:
		var id := str(id_value)
		var need := int(cost[id])
		var have := AppState.inventory_count(id)
		var shortage := maxi(0, need - have)
		affordable = affordable and shortage == 0
		parent.add_child(_label("%s  ·  필요 %s / 보유 %s%s" % [_display_item_name(id), MathUtil.comma(need), MathUtil.comma(have), "  ·  %s 부족" % MathUtil.comma(shortage) if shortage > 0 else ""], 18, Color("f1b4a2") if shortage > 0 else Color("c7d9ed")))
		if shortage > 0:
			parent.add_child(_button("%s 획득처" % _display_item_name(id), func(value := id): _go_to_item_source(value), false, Vector2(1, 44)))
	return affordable

func _growth_level_reason(cid: String, preview: Dictionary) -> String:
	var state: Dictionary = AppState.profile.roster[cid]
	if int(state.level) >= int(preview.cap):
		if int(state.level) >= 100: return "최고 레벨입니다."
		if int(state.level) >= int(AppState.profile.account.level):
			return "계정 레벨 상한입니다. 작전을 완료해 계정 레벨을 먼저 올리세요."
		return "돌파가 필요합니다. 장비·돌파 탭에서 레벨 상한을 높이세요."
	if int(preview.unused_xp) > 0: return "이 재료는 현재 상한을 넘습니다. 더 작은 훈련 노트를 선택하세요."
	return ""

func _build_growth_level(parent: Node, cid: String) -> void:
	preload("res://screens/command_presentation.gd").level(self, parent, cid)

func _growth_skill_effect(cid: String, slot: String, value: float) -> String:
	var definition := DataRegistry.character(cid)
	var skill := DataRegistry.skill(str(definition[slot + "_skill_id"]))
	var effect := str(skill.get("effect", ""))
	if slot == "passive":
		var stat := "체력" if definition.role == "GUARDIAN" else ("회복력" if definition.role == "MEDIC" else "공격력")
		return "%s +%.1f%%" % [stat, value * 100.0]
	if slot == "ultimate" and effect == "BUFF": return "아군 전체 공격 속도 +20% · 7초"
	if slot == "ultimate" and effect == "DEBUFF": return "적 1명 방어력 -25% · 7초"
	if effect == "HEAL": return "%s · 회복력의 %.1f%% 회복" % ["아군 전체" if slot == "ultimate" else "체력이 가장 낮은 아군", value * (0.72 if slot == "ultimate" else 1.0) * 100.0]
	if effect in ["SHIELD", "TAUNT"]: return "%s · 회복력의 %.1f%% 보호막%s" % ["아군 전체" if slot == "ultimate" else ("자신" if effect == "TAUNT" else "체력이 가장 낮은 아군"), value * (0.8 if effect == "TAUNT" else 1.0) * 100.0, " · 도발 4초" if effect == "TAUNT" else ""]
	return "%s · 공격력의 %.1f%% 공격 계수%s" % ["적 전체" if effect == "AOE_DAMAGE" else "적 1명", value * ((0.82 if slot == "ultimate" else 0.62) if effect == "AOE_DAMAGE" else 1.0) * 100.0, " · 감속 3초" if slot == "normal" and effect == "SLOW" else ""]

func _build_growth_skills(parent: Node, cid: String) -> void:
	parent.add_child(_label("강화할 스킬을 선택하세요. 비용은 스킬마다 다릅니다.", 18))
	var cards := GridContainer.new()
	cards.columns = 1 if _is_portrait_layout() or _is_compact_landscape_layout() else 3
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(cards)
	var definition := DataRegistry.character(cid)
	for slot in ["normal", "passive", "ultimate"]:
		var box := _panel_box(cards)
		box.name = "GrowthSkill_" + slot
		var skill := DataRegistry.skill(str(definition[slot + "_skill_id"]))
		var level := int(AppState.profile.roster[cid].skills[slot])
		var comparison := SkillUpgradeService.comparison(cid, slot)
		var fixed := not SkillUpgradeService.supports_upgrade(cid, slot)
		box.add_child(_label("%s · Lv.%d\n%s" % [{"normal": "일반 스킬", "passive": "패시브", "ultimate": "궁극기"}[slot], level, LocalizationService.tr_key(str(skill.name_key)).replace(" (DEV)", "")], 21, Color("f1d77a")))
		box.add_child(_label("현재  " + _growth_skill_effect(cid, slot, float(comparison.current)), 18))
		var affordable := false
		if fixed:
			box.add_child(_label("효과가 고정된 스킬입니다. 추가 강화에 재화를 쓰지 않습니다.", 18))
		elif comparison.max:
			box.add_child(_label("최고 레벨에 도달했습니다.", 18, Color("8fe0b6")))
		else:
			box.add_child(_label("강화 후  " + _growth_skill_effect(cid, slot, float(comparison.next)), 18, Color("8fe0b6")))
			affordable = _growth_cost_rows(box, SkillUpgradeService.next_cost(cid, slot))
		var action := _button("추가 강화 불필요" if fixed else ("강화 완료" if comparison.max else "Lv.%d → %d 강화" % [level, level + 1]), func(value: String = slot, target := level + 1):
			_finish_growth_action(SkillUpgradeService.upgrade(cid, value), "%s 스킬 Lv.%d 강화 완료" % [{"normal": "일반", "passive": "패시브", "ultimate": "궁극기"}[value], target]), not affordable or growth_save_pending, Vector2(1, 52))
		_apply_skill_icon(action, skill, roundi(32 * _responsive_control_scale()))
		action.name = "GrowthSkillApply_" + slot
		_make_primary_button(action)
		box.add_child(action)
	parent.add_child(_label("공격 계수는 방어력·상성·치명타 적용 전 기준입니다. 회복과 보호막 수치는 회복력에 비례합니다.", 16, Color("91aac8")))

func _finish_growth_action(result: GameResult, message: String) -> void:
	if result.ok:
		var saved := SaveService.save_game()
		growth_save_pending = not saved.ok
		growth_feedback = message + (" · 저장 완료" if saved.ok else " · 적용됐지만 저장하지 못했습니다. 저장을 다시 시도하세요.")
	else:
		growth_feedback = "강화하지 않았습니다. 재료와 성장 조건을 다시 확인하세요."
	_show_screen("GROWTH")

func _retry_growth_save() -> void:
	var saved := SaveService.save_game()
	growth_save_pending = not saved.ok
	growth_feedback = "변경 내용 저장 완료" if saved.ok else "아직 저장하지 못했습니다. 화면을 유지하고 다시 시도하세요."
	_show_screen("GROWTH")

func _build_growth_equipment(parent: Node, cid: String) -> void:
	var state: Dictionary = AppState.profile.roster[cid]
	var box := _panel_box(parent)
	box.add_child(_label("돌파 · 레벨 상한 높이기", 21, Color("f1d77a")))
	var breakthrough := int(state.breakthrough)
	var cap := int([20, 40, 60, 80, 90, 100][breakthrough])
	box.add_child(_label("현재 돌파 %d · 돌파 상한 Lv.%d\n계정 레벨 %d도 함께 적용됩니다." % [breakthrough, cap, AppState.profile.account.level], 18))
	var cost := BreakthroughService.next_cost(cid)
	var affordable := _growth_cost_rows(box, cost)
	if int(state.level) < cap: box.add_child(_label("캐릭터 Lv.%d에 도달하면 돌파할 수 있습니다." % cap, 18))
	box.add_child(_button("최종 돌파 완료" if breakthrough >= 5 else "돌파 %d → %d" % [breakthrough, breakthrough + 1], func(): _finish_growth_action(BreakthroughService.upgrade(cid), "돌파 완료"), breakthrough >= 5 or int(state.level) < cap or not affordable or growth_save_pending, Vector2(1, 52)))
	var weapon_id := str(state.equipped_weapon_id)
	var weapon_state: Dictionary = AppState.profile.weapons[weapon_id]
	var equipment := _panel_box(parent)
	equipment.add_child(_label("장비 · %s Lv.%d / T%d" % [_display_runtime_name(weapon_id), weapon_state.level, weapon_state.tier], 21))
	var preview := WeaponUpgradeService.preview(weapon_id, "WEAPON_CHIP_M", 1)
	var can_level := _growth_cost_rows(equipment, {"WEAPON_CHIP_M": 1})
	equipment.add_child(_button("무기 강화 · 중급 칩 1개", func(): _finish_growth_action(WeaponUpgradeService.use_material(weapon_id, "WEAPON_CHIP_M", 1), "무기 강화 완료"), not can_level or not preview.ok or not WeaponUpgradeService.fits(preview.value) or growth_save_pending, Vector2(1, 52)))
	var tier_cost := WeaponUpgradeService.tier_up_cost(weapon_id)
	var can_tier := _growth_cost_rows(equipment, tier_cost)
	var tier_cap := int(WeaponUpgradeService.CAPS[int(weapon_state.tier) - 1])
	if int(weapon_state.level) < tier_cap: equipment.add_child(_label("무기 Lv.%d에 도달하면 티어업할 수 있습니다." % tier_cap, 18))
	equipment.add_child(_button("무기 티어업", func(): _finish_growth_action(WeaponUpgradeService.tier_up(weapon_id), "무기 티어업 완료"), not can_tier or int(weapon_state.level) < tier_cap or growth_save_pending, Vector2(1, 52)))
	for weapon in DataRegistry.list_of("weapons"):
		if weapon.weapon_class == DataRegistry.character(cid).weapon_class and bool(AppState.profile.weapons.get(str(weapon.id), {}).get("owned", false)):
			var choice := _button(_mobile_equipment_option_text(weapon), func(value: String = str(weapon.id)):
				state.equipped_weapon_id = value
				_finish_growth_action(GameResult.success(value), "장비 교체 완료"), weapon.id == weapon_id or growth_save_pending, Vector2(1, 48))
			choice.name = "MobileEquipmentOption_" + str(weapon.id)
			equipment.add_child(choice)

func _cost_detail(cost: Dictionary) -> String:
	if cost.is_empty(): return "MAX / 없음"
	var parts: Array[String] = []
	for item_id in cost:
		var stages := _source_stages_for_item(str(item_id))
		var source := "획득처 없음"
		if not stages.is_empty():
			source = ",".join(stages.slice(0, 3))
			if stages.size() > 3: source += " 외 %d" % (stages.size() - 3)
		parts.append("%s %s/%s [%s]" % [_display_item_name(str(item_id)), MathUtil.comma(AppState.inventory_count(str(item_id))), MathUtil.comma(int(cost[item_id])), source])
	return " · ".join(parts)

func _source_stages_for_item(item_id: String) -> Array[String]:
	var result: Array[String] = []
	for reward in DataRegistry.list_of("rewards"):
		var cleared := bool(AppState.profile.get("first_clear", {}).get(str(reward.stage_id), false))
		for bucket in ["guaranteed", "bonus", "first_clear", "growth_first_clear"]:
			# One-time first-clear buckets only point at operations not yet cleared.
			if cleared and bucket in ["first_clear", "growth_first_clear"]: continue
			for entry in reward.get(bucket, []):
				if str(entry.get("item_id", "")) == item_id and not result.has(str(reward.stage_id)):
					result.append(str(reward.stage_id))
	return result

func _go_to_item_source(item_id: String) -> void:
	var stages := _source_stages_for_item(item_id)
	for stage_id in stages:
		if AppState.is_stage_unlocked(stage_id):
			AppState.selected_stage_id = stage_id
			SceneRouter.go("STAGE_DETAIL")
			return
	var message := "%s: 아직 입장 가능한 획득처가 없습니다. 작전을 진행해 다음 지역을 여세요." % _display_item_name(item_id)
	if stages.is_empty(): message = "%s: 작전 보상 목록에 획득처가 없습니다." % _display_item_name(item_id)
	if current_screen == "GROWTH":
		growth_feedback = message
		_show_screen("GROWTH")
	else: footer_status.text = message

func _show_inventory() -> void:
	_title("인벤토리", "통화·경험치·돌파·스킬·무기·조각")
	var portrait := _is_portrait_layout()
	var grid := GridContainer.new()
	grid.columns = 1 if portrait else 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll_box := _scroll_box()
	scroll_box.add_child(grid)
	for item in DataRegistry.list_of("items"):
		var count := AppState.inventory_count(item.id)
		if count > 0:
			grid.add_child(_button("%s\n%s" % [_display_item_name(str(item.id)), MathUtil.comma(count)], func(): footer_status.text = "획득처: 스테이지 상세에서 확인", false, Vector2(300 if portrait else 260, 76)))

func _show_archive() -> void:
	_title("스토리 아카이브", "메인·챕터·개인 이야기 기록")
	var portrait := _is_portrait_layout()
	var archive_box := _scroll_box()
	var grid := GridContainer.new()
	grid.columns = 1 if portrait else 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	archive_box.add_child(grid)
	var scenarios := DataRegistry.list_of("scenarios")
	var available := 0
	for scenario in scenarios:
		var scenario_id := str(scenario.id)
		# Campaign scenes open only after they were reached in play, so the
		# archive neither spoils later chapters nor replays unearned rewards.
		# Personal stories open by relationship level and may be first seen here.
		if str(scenario.chapter_id) == "REL":
			if _relation_story_locked(scenario_id): continue
		elif not AppState.scenario_seen(scenario_id):
			continue
		available += 1
		grid.add_child(_button("%s\n%s" % [LocalizationService.tr_key(scenario.title_key), scenario.chapter_id], func(): AppState.active_scenario_id = scenario_id; AppState.profile.last_scenario_position.erase(scenario_id); SceneRouter.go("STORY", {"after": "ARCHIVE"}), false, Vector2(300 if portrait else 320, 90)))
	archive_box.add_child(_label("열람 가능한 기록 %d / %d · 진행하면 새 기록이 열립니다" % [available, scenarios.size()], 18, GameUI.TEXT_MUTED))
	archive_box.move_child(archive_box.get_child(archive_box.get_child_count() - 1), 0)

func _relation_story_locked(scenario_id: String) -> bool:
	return (scenario_id == "SCN_REL_MAERU" and int(AppState.profile.roster.CHR001.relationship_level) < 2) or (scenario_id == "SCN_REL_IRI" and int(AppState.profile.roster.CHR008.relationship_level) < 2)

func _is_archive_replay(scenario_id: String) -> bool:
	if str(AppState.route_payload.get("after", "")) != "ARCHIVE":
		return false
	# A personal story that was never finished grants its reward once.
	if str(DataRegistry.by_id("scenarios", scenario_id).get("chapter_id", "")) == "REL":
		return AppState.scenario_completed(scenario_id)
	return true

func _show_settings() -> void:
	_title("설정", "로컬 설정은 저장 파일에 보존")
	var box := _scroll_box()
	box.add_child(_button("언어: %s" % ("한국어" if SettingsService.values.language == "ko" else "English"), func(): SettingsService.values.language = "en" if SettingsService.values.language == "ko" else "ko"; _show_screen("SETTINGS"), false, Vector2(300, 64)))
	box.add_child(_button("배경음악·효과음: %s" % ("켜짐" if SettingsService.values.audio_enabled else "꺼짐"), func():
		AudioService.set_enabled(not bool(SettingsService.values.audio_enabled))
		SaveService.save_game()
		_show_screen("SETTINGS"), false, Vector2(300, 64)))
	box.add_child(_button("텍스트 속도: %.2fs" % SettingsService.values.text_speed, func(): SettingsService.values.text_speed = .01 if float(SettingsService.values.text_speed) >= .03 else float(SettingsService.values.text_speed) + .01; _show_screen("SETTINGS"), false, Vector2(300, 64)))
	box.add_child(_button("자동 전투: %s" % ("켜짐" if SettingsService.values.battle_auto else "꺼짐"), func(): SettingsService.values.battle_auto = not SettingsService.values.battle_auto; _show_screen("SETTINGS"), false, Vector2(300, 64)))
	box.add_child(_button("맵 카메라 추적: %d%%" % roundi(float(SettingsService.values.map_camera_follow_strength) * 100.0), func(): SettingsService.values.map_camera_follow_strength = 0.35 if float(SettingsService.values.map_camera_follow_strength) > 0.7 else float(SettingsService.values.map_camera_follow_strength) + 0.2; _show_screen("SETTINGS"), false, Vector2(360, 64)))
	box.add_child(_button("지도 이동 효과 줄이기: %s" % ("켜짐" if SettingsService.values.map_reduced_transition else "꺼짐"), func(): SettingsService.values.map_reduced_transition = not SettingsService.values.map_reduced_transition; _show_screen("SETTINGS"), false, Vector2(360, 64)))
	box.add_child(_button("지도 카메라 즉시 이동: %s" % ("켜짐" if SettingsService.values.map_instant_focus else "꺼짐"), func(): SettingsService.values.map_instant_focus = not SettingsService.values.map_instant_focus; _show_screen("SETTINGS"), false, Vector2(360, 64)))
	box.add_child(_button("오픈소스 / 제3자 라이선스", func(): SceneRouter.go("LICENSE"), false, Vector2(360, 64)))
	box.add_child(_button("설정 저장", func(): _report_result(SaveService.save_game()), false, Vector2(220, 64)))

func _show_license() -> void:
	_title("오픈소스 라이선스", "Godot와 제3자/공용 팩토리 출처 분리")
	var box := _scroll_box()
	box.add_child(_label("Godot Engine\nMIT License — Copyright Godot Engine contributors. 전체 라이선스는 배포본의 LICENSES 문서를 참조하십시오.\n\n공용 Asset Share Procedural Factory\nMIT / 버전 0.1.0. 동기화된 결과는 DEV_PLACEHOLDER이며 원본 manifest SHA-256과 출처를 보존합니다.\n\n현재 신규 코드 기반 도형 UI/SD placeholder는 프로젝트 자체 제작물입니다.\n\n일본어 스토리 음성\nAlibaba Cloud Model Studio Token Plan(싱가포르)의 qwen-audio-3.0-tts-plus로 제작 단계에서 미리 생성한 파일입니다. 게임은 실행 중 음성 합성이나 원격 API를 호출하지 않으며, 원격 에셋도 불러오지 않습니다.", 20))

func _show_debug() -> void:
	if not SettingsService.is_developer_mode():
		SceneRouter.go("HOME")
		return
	_title("개발자 디버그", "일반 저장 규칙과 분리된 로컬 개발 옵션")
	var box := _scroll_box()
	var grid := GridContainer.new()
	# Two portrait columns fit the 390px safe width; the creation order remains
	# untouched so keyboard QA keeps the established Tab sequence.
	grid.columns = 2 if _is_portrait_layout() else 3
	box.add_child(grid)
	grid.add_child(_button("모든 재료 999", func(): AppState.grant_all_materials(); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("전체 동료 해금", func(): _debug_unlock_roster(); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("스테이지 전체 해금: %s" % AppState.debug_options.unlock_all, func(): AppState.debug_options.unlock_all = not AppState.debug_options.unlock_all; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("선택 캐릭터 +10레벨", func(): _debug_level_character(10); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("선택 캐릭터 10/10/5", func(): AppState.profile.roster[AppState.selected_character_id].skills = {"normal": 10, "passive": 10, "ultimate": 5}; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("무적: %s" % AppState.debug_options.invincible, func(): AppState.debug_options.invincible = not AppState.debug_options.invincible; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("Seed +1 (%d)" % AppState.battle_seed, func(): AppState.battle_seed += 1; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("적 배율 %.1f×" % AppState.debug_options.enemy_multiplier, func(): AppState.debug_options.enemy_multiplier = 1.0 if float(AppState.debug_options.enemy_multiplier) >= 2.0 else float(AppState.debug_options.enemy_multiplier) + .25; _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("계정 Lv.100", func(): AppState.profile.account.level = 100; _show_screen("DEBUG"), int(AppState.profile.account.level) == 100, Vector2(280, 72)))
	grid.add_child(_button("선택 무기 Lv.60/T6", func(): _debug_max_weapon(); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("N20 즉시 선택", func(): AppState.selected_stage_id = "CH01-N20"; SceneRouter.go("STAGE_DETAIL"), false, Vector2(280, 72)))
	grid.add_child(_button("고급 SD 전투 QA (CHR009-013 / BOSS003)", _debug_prepare_premium_sd_battle_qa, false, Vector2(280, 72)))
	grid.add_child(_button("리뉴얼 SD 전투 QA (CHR014·027·037·040·043 / BOSS003)", _debug_prepare_renewal_sd_battle_qa, false, Vector2(280, 72)))
	grid.add_child(_button("CH01 NORMAL 완료 / HARD QA", func(): _debug_unlock_chapter_hard(); _show_screen("DEBUG"), false, Vector2(280, 72)))
	grid.add_child(_button("N04 특별 조우 QA", func(): _debug_prepare_companion_event("NODE_N04"); SceneRouter.go("STAGE_SELECT"), false, Vector2(280, 72)))
	grid.add_child(_button("N04 카드 시각 QA (8초 홀드)", func(): _debug_prepare_companion_card_visual_qa("NODE_N04"); SceneRouter.go("STAGE_SELECT"), false, Vector2(280, 72)))
	grid.add_child(_button("N04 카드 프리뷰 QA (8초 홀드)", _debug_preview_companion_card, false, Vector2(280, 72)))
	grid.add_child(_button("N08 지연 합류 QA", func(): _debug_prepare_companion_event("NODE_N08"); SceneRouter.go("STAGE_SELECT"), false, Vector2(280, 72)))
	grid.add_child(_button("N10 보스 조우 QA", func(): _debug_prepare_map_contact("NODE_N10"); SceneRouter.go("STAGE_SELECT"), false, Vector2(280, 72)))
	grid.add_child(_button("N20 최종 보스 접촉 QA", func(): _debug_prepare_map_contact("NODE_N20"); SceneRouter.go("STAGE_SELECT"), false, Vector2(280, 72)))
	grid.add_child(_button("저장 내보내기(user://)", _export_save, false, Vector2(280, 72)))
	grid.add_child(_button("헤드리스 테스트 안내", func(): footer_status.text = "tools/powershell/RUN_HEADLESS_TESTS.ps1", false, Vector2(280, 72)))
	grid.add_child(_button("저장 초기화 " + ("확정" if debug_reset_armed else "(재확인 필요)"), _debug_reset, false, Vector2(280, 72)))
	box.add_child(_label("피해 상세식: ATK×skill×defense×level×affinity×critical×variance×outgoing×incoming, round_half_up, min 1.\n전투 이벤트/식 입력값은 결과 해시 및 reports에서 확인. 배속은 BattleSimulation tick 수에 영향을 주지 않습니다.", 18, Color("8da6c3")))

func _debug_unlock_roster() -> void:
	for character_id in AppState.profile.roster: AppState.profile.roster[character_id].unlocked = true

func _debug_prepare_premium_sd_battle_qa() -> void:
	# Local developer-only visual QA route: the five promoted adult-SD allies face
	# BOSS003 on a real battle timeline. This is never exposed in the release UI.
	if not SettingsService.is_developer_mode():
		return
	_debug_unlock_roster()
	var qa_party := ["CHR009", "CHR010", "CHR011", "CHR012", "CHR013"]
	for slot in range(qa_party.size()):
		var character_id := str(qa_party[slot])
		AppState.set_party_slot(slot, character_id)
		# This route exists to validate the promoted battle art through the boss
		# wave, not to measure progression. Give only this dev squad enough
		# authored power to reach that wave inside the normal time limit.
		var progress: Dictionary = AppState.profile.roster[character_id]
		progress.level = 100
		progress.breakthrough = 5
		progress.skills = {"normal": 10, "passive": 10, "ultimate": 5}
	_debug_unlock_chapter_hard()
	# H03 normally requires H01/H02 stars.  QA must enter the authored BOSS003
	# fight directly, while keeping the bypass confined to development authority.
	AppState.debug_options.unlock_all = true
	AppState.debug_options.invincible = true
	AppState.selected_stage_id = "CH01-H03"
	SceneRouter.go("STAGE_DETAIL")

func _debug_prepare_renewal_sd_battle_qa() -> void:
	# Development-only visual proof route for the latest adult-SD authority art.
	# The party deliberately spans assault, control, medic, and heavy silhouettes
	# so a single Web run catches both duplicate-face regressions and incorrect
	# runtime source fallback before any release build is considered.
	if not SettingsService.is_developer_mode():
		return
	_debug_unlock_roster()
	var qa_party := ["CHR014", "CHR027", "CHR037", "CHR040", "CHR043"]
	for slot in range(qa_party.size()):
		var character_id := str(qa_party[slot])
		AppState.set_party_slot(slot, character_id)
		var progress: Dictionary = AppState.profile.roster[character_id]
		progress.level = 100
		progress.breakthrough = 5
		progress.skills = {"normal": 10, "passive": 10, "ultimate": 5}
	_debug_unlock_chapter_hard()
	AppState.debug_options.unlock_all = true
	AppState.debug_options.invincible = true
	AppState.selected_stage_id = "CH01-H03"
	SceneRouter.go("STAGE_DETAIL")

func _debug_level_character(amount: int) -> void:
	var state: Dictionary = AppState.profile.roster[AppState.selected_character_id]
	state.level = mini(100, int(state.level) + amount)
	while int(state.level) > CharacterProgression.level_cap(state) and int(state.breakthrough) < 5: state.breakthrough += 1

func _debug_max_weapon() -> void:
	var weapon_id := str(AppState.profile.roster[AppState.selected_character_id].equipped_weapon_id)
	AppState.profile.weapons[weapon_id].level = 60
	AppState.profile.weapons[weapon_id].tier = 6

func _debug_unlock_chapter_hard() -> void:
	# This capability exists only in the development-authorized screen.  Keep an
	# independent guard here as well so a synthetic callback cannot mutate a
	# public Release save.  This creates a reward-free canonical NORMAL-complete
	# snapshot: every route blocker is removed and the squad is anchored at N20,
	# allowing an actual H01-H10 map/contact/battle/return browser run.
	if not SettingsService.is_developer_mode():
		return
	AppState.profile.chapter_progress.CH01.normal_highest = 20
	AppState.profile.chapter_progress.CH01.hard_unlocked = true
	var definition := ChapterMapLoaderScript.load_map("CH01_MAP")
	var map_state := AppState.chapter_map_state("CH01_MAP")
	for number in range(1, 21):
		var stage_id := "CH01-N%02d" % number
		var node := ChapterMapLoaderScript.node_for_stage(definition, stage_id)
		AppState.profile.stage_stars[stage_id] = 3
		AppState.profile.first_clear[stage_id] = true
		if not node.is_empty():
			MapExplorationServiceScript.mark_encounter_cleared(map_state, str(node.node_id))
			if not map_state.cleared_nodes.has(str(node.node_id)):
				map_state.cleared_nodes.append(str(node.node_id))
	var n20 := ChapterMapLoaderScript.node_for_stage(definition, "CH01-N20")
	if not n20.is_empty():
		AppState.set_chapter_map_position(Vector2i(int(n20.q), int(n20.r)), str(n20.node_id), "CH01_MAP")
	AppState.refresh_chapter_map_reveal()

func _debug_prepare_companion_event(node_id: String) -> void:
	_debug_prepare_map_contact(node_id)

func _debug_prepare_companion_card_visual_qa(node_id: String) -> void:
	if not SettingsService.is_developer_mode():
		return
	debug_companion_card_visual_hold = true
	_debug_prepare_map_contact(node_id)

func _debug_preview_companion_card() -> void:
	# A visual-only companion-card inspector.  It reuses the normal pending-map
	# payload and the production _play_map_battle_transition() renderer, but
	# starts at the already-authored contact transaction so a browser screenshot
	# need not race the short real transition.  Physical-contact E2E remains
	# covered by the neighbouring-hex fixture above.
	if not SettingsService.is_developer_mode():
		return
	_debug_prepare_map_contact("NODE_N04")
	var state := AppState.chapter_map_state("CH01_MAP")
	var return_coord := Vector2i(int(state.get("current_q", 0)), int(state.get("current_r", 0)))
	if not AppState.prepare_map_encounter("CH01-N04", "NODE_N04", return_coord, "CH01_MAP"):
		return
	debug_companion_card_visual_hold = true
	battle_transition_active = true
	SceneRouter.go("STAGE_SELECT")
	await get_tree().process_frame
	_play_map_battle_transition()

func _debug_prepare_map_contact(node_id: String) -> void:
	# Development-only visual/E2E fixture. It never exists in a Release shell and
	# changes no battle, reward, or recruitment formula: it simply places the
	# squad on a real neighbouring ground hex so the normal physical-contact
	# sequence (including companion cards or boss title cards) can be tested
	# without walking the full macro route every time.
	if not SettingsService.is_developer_mode():
		return
	var definition := ChapterMapLoaderScript.load_map("CH01_MAP")
	var node := ChapterMapLoaderScript.node_by_id(definition, node_id)
	if node.is_empty():
		return
	var grid := HexGridScript.new()
	grid.load_tiles(definition.get("tiles", []))
	var target := Vector2i(int(node.get("q", 0)), int(node.get("r", 0)))
	var staging := Vector2i.ZERO
	var found_staging := false
	for candidate in HexCoordScript.neighbors(target):
		if grid.traversable(candidate):
			staging = candidate
			found_staging = true
			break
	if not found_staging:
		return
	AppState.debug_options.unlock_all = true
	var map_state := AppState.chapter_map_state("CH01_MAP")
	MapExplorationServiceScript.ensure_state(map_state, definition, grid)
	var stage_id := str(node.get("stage_id", ""))
	var stage_number := int(DataRegistry.stage(stage_id).get("stage_number", 0))
	# Establish only the canonical NORMAL history that precedes this authored
	# companion contact.  Without it, the map's ordinary next-node resolver
	# understandably focuses an uncleared N01-N07 node after the QA N08 win,
	# preventing the real deferred-recruitment N09 follow-up from being checked.
	# This is development-only fixture state: it grants no rewards and is never
	# callable from a Release shell.
	for number in range(1, stage_number):
		var prior_stage_id := "CH01-N%02d" % number
		var prior_node := ChapterMapLoaderScript.node_for_stage(definition, prior_stage_id)
		AppState.profile.stage_stars[prior_stage_id] = 3
		AppState.profile.first_clear[prior_stage_id] = true
		if not prior_node.is_empty():
			MapExplorationServiceScript.mark_encounter_cleared(map_state, str(prior_node.node_id))
			if not map_state.cleared_nodes.has(str(prior_node.node_id)):
				map_state.cleared_nodes.append(str(prior_node.node_id))
	if stage_number > 1:
		AppState.profile.chapter_progress.CH01.normal_highest = maxi(int(AppState.profile.chapter_progress.CH01.get("normal_highest", 0)), stage_number - 1)
	# Make the fixture idempotent without awarding, clearing, or unlocking a
	# stage. A genuine map click and one-hex move still own the battle entry.
	map_state.cleared_nodes.erase(node_id)
	map_state.cleared_encounters.erase(node_id)
	map_state.encounter_states[node_id] = "HOSTILE"
	var special_event := MapExplorationServiceScript.event_encounter_for_node(definition, node_id)
	var event_encounter_id := str(special_event.get("event_encounter_id", ""))
	var companion_id := str(special_event.get("character_id", ""))
	if not event_encounter_id.is_empty():
		map_state.event_encounter_states[event_encounter_id] = "AVAILABLE"
	if not companion_id.is_empty():
		map_state.recruitment_states[companion_id] = "LOCKED"
	AppState.profile.stage_stars[stage_id] = 0
	AppState.profile.first_clear[stage_id] = false
	AppState.set_chapter_map_position(staging, "", "CH01_MAP")
	map_state.movement_points = map_state.movement_points_max
	AppState.selected_stage_id = stage_id
	SaveService.save_game()

func _export_save() -> void:
	var file := FileAccess.open("user://exported_save_v1.json", FileAccess.WRITE)
	if file != null:
		file.store_string(SaveService.export_save_json())
		footer_status.text = "user://exported_save_v1.json 저장 완료"

func _debug_reset() -> void:
	if not debug_reset_armed:
		debug_reset_armed = true
		footer_status.text = "한 번 더 눌러 저장 초기화를 확정하세요."
		_show_screen("DEBUG")
		return
	SaveService.reset_save_files()
	debug_reset_armed = false
	SceneRouter.go("TITLE")

func _report_result(result: GameResult) -> void:
	footer_status.text = "OK: %s" % str(result.value) if result.ok else "ERROR: %s" % result.error
