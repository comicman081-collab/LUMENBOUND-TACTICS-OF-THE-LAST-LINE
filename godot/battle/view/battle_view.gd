class_name BattleView
extends Control

const BattlePresentationDirectorScript := preload("res://battle/view/battle_presentation_director.gd")
const FieldScriptScript := preload("res://field/field_script.gd")
const FieldSceneOverlayScript := preload("res://field/field_scene_overlay.gd")
const BattleFieldStageScript := preload("res://field/battle_field_stage.gd")
const ActorChoreography := preload("res://battle/view/battle_actor_choreography.gd")
const ActionFrames := preload("res://battle/view/combat_action_frames.gd")
const WeaponEffects := preload("res://battle/view/combat_weapon_effects.gd")
const Grounding := preload("res://battle/view/battle_grounding.gd")
const DAMAGE_FONT := preload("res://assets/fonts/LanternRounded-Black.ttf")
const Ornament := preload("res://ui/ornament_draw.gd")
const HitFeedback := preload("res://battle/view/combat_hit_feedback.gd")
const RegionFloor := preload("res://battle/view/battle_region_floor.gd")
const SoftSprites := preload("res://battle/view/battle_soft_sprites.gd")
const MeshKit := preload("res://battle/view/battle_mesh_kit.gd")
const CachedDraw := preload("res://battle/view/battle_cached_draw.gd")
const WaveTransition := preload("res://battle/view/battle_wave_transition.gd")

signal battle_finished(result: Dictionary)
## Emitted once every asset required for this battle is attached, whether the
## stage bundle was already warm or the sliced local fallback completed.
signal battle_assets_ready

var simulation: BattleSimulation
var accumulator := 0.0
var speed := 1
var paused := false
var emitted_finish := false
var skip_in_progress := false
var consumed_events := 0
## `consumed_events` stays as the public raw-log cursor for compatibility.
## The presentation cursors are separate so an ULTIMATE may claim its already
## calculated result events without applying their visual state until impact.
var presentation_read_cursor := 0
var presented_cursor := 0
var presentation_display_units: Dictionary = {}
## Retain the lightweight actor description across a wave replacement so the
## last enemy's destruction can finish after simulation advances to the next wave.
var presentation_actor_records: Dictionary = {}
var enemy_defeat_bursts: Dictionary = {}
var defeat_hold_left := 0.0
var active_presentation_batch: Dictionary = {}
var presentation_director = BattlePresentationDirectorScript.new()
var floating_texts: Array = []
var floating_serial := 0
var projectiles: Array = []
var free_floating_texts: Array = []
var free_projectiles: Array = []
var unit_flash: Dictionary = {}
## uid -> {duration, power} for the slide of a damage-scaled hit, and uid ->
## frames of white flash left (2 frames on every landed hit).
var unit_flash_span: Dictionary = {}
var hit_flash_frames: Dictionary = {}
## Regional floor (phase 4 / D1): theme of the stage's chapter, cached by stage id.
var region_theme: Dictionary = {}
var region_theme_stage := ""
var region_dressing_enabled := true
## QA only: pins the floor animation clock (seconds) so two captures match; < 0 = live.
var region_clock_override := -1.0
## r22 draw caches. The memos are only valid while one `_draw()` pass runs (the
## state they derive from cannot change inside a pass); every pass starts empty.
## A unit can be asked about twice with different alive flags in one pass (a
## squad body fading out after the simulation already marked it down), hence the
## separate down-pose memo.
var _draw_memo_active := false
var _pose_memo: Dictionary = {}
var _pose_memo_down: Dictionary = {}
var _scale_memo: Dictionary = {}
## Camera and actor anchors are invariant during one draw pass. A single attack
## used to recompute camera trigonometry and melee travel for its shadow, body,
## health bar, projectile and damage number separately.
var _position_memo: Dictionary = {}
var _ground_memo: Dictionary = {}
var _action_sample_memo: Dictionary = {}
var _actor_memo: Dictionary = {}
var _frame_memo: Dictionary = {}
var _frame_memo_down: Dictionary = {}
var _draw_zoom := 1.0
var _draw_offset := Vector2.ZERO
## Footing rings queued by _draw_contact_shadow, drawn together afterwards.
var _footing_rings: Array = []
## The tactical grid lattice, tessellated once per view size (see _grid_lattice).
var _grid_mesh: ArrayMesh = null
var _grid_mesh_size := Vector2.ZERO
var _cell_mesh_size := Vector2.ZERO
var _cell_meshes: Dictionary = {}
var _cell_bracket_meshes: Dictionary = {}
var _contact_divider_mesh: ArrayMesh = null
var _boss_floor_mesh: ArrayMesh = null
var _boss_floor_mesh_size := Vector2.ZERO
var _ellipse_mesh: ArrayMesh = null
var _readout_style: StyleBoxFlat = null
var sprite_library := BattleSpriteLibrary.new()
var action_frames := ActionFrames.new()
var sprite_pack_ready := false
var signature_sprite_pack_ready := false
var projectile_library := ProjectileSpriteLibrary.new()
var projectile_pack_ready := false
var effect_signature_library := EffectSignatureLibrary.new()
var full_density_effects = preload("res://battle/view/full_density_effects.gd").new()
var effect_signature_pack_ready := false
## Signature pages rotate only when the authoritative visible encounter
## changes. Future waves remain compact until the replacement page has been
## acquired as one complete pack, so they cannot leak texture residency or
## flash a partly loaded high-density frame.
var signature_residency_target_ids: Array[String] = []
## A rejected optional pack is a settled compact outcome for this encounter,
## not an unfinished load. Retrying it every frame used to starve Web playback.
var signature_fallback_target_ids: Array[String] = []
var signature_fallback_error := ""
var signature_rollover_active := false
var signature_rollover_requested := false
var animation_tracks: Dictionary = {}
var entry_tracks: Dictionary = {}
var vfx_presentations: Array = []
var free_vfx_presentations: Array = []
var skill_callouts: Array = []
var free_skill_callouts: Array = []
var boss_phase_presentations: Array = []
var free_boss_phase_presentations: Array = []
var vfx_frames: Dictionary = {}
var runtime_vfx_entries: Array = []
var runtime_vfx_manifest_loaded := false
var fallback_combat_previews: Dictionary = {}
var assets_ready := false
var asset_cache_hit := false
var asset_warmup_phase := ""
var asset_input_blocker: Control
var normal_background: Texture2D
var boss_background: Texture2D
## Arena ownership outlives the boss. HP never chooses the environment.
var boss_arena_active := false
var boss_entry_wave := -1
var boss_entry_elapsed := -1.0
var boss_entry_uids: Array[String] = []
var boss_entry_name := ""
var boss_entry_from_arena := false
var boss_victory_elapsed := -1.0
var wave_entry_wave := 1
var wave_entry_elapsed := -1.0
var wave_entry_enemy_uid := ""
var wave_entry_ally_uid := ""
# Field direction (phase 3). The host turns the boss aftermath on; tests and tools keep
# the default so a battle still ends without waiting for a tap.
var field_aftermath_enabled := false
var field_portrait_source := Callable()
var field_aftermath_state := "idle"
var field_overlay: Control
var field_poses: Dictionary = {}
var field_zoom := 1.0
var field_offset := Vector2.ZERO
const BOSS_ENTRY_DURATION := WaveTransition.BOSS_DURATION
const BOSS_VICTORY_DURATION := 1.8
var battle_font: Font
var ultimate_portraits: Dictionary = {}
## HUD face crops are transient battle textures. They are derived from the
## already-loaded approved source cells and never write, replace or promote an
## art file. 192px gives a three-times source-density margin for a 64px phone
## disc while staying far below the signature-atlas memory budget.
var ultimate_orb_face_textures: Dictionary = {}
var ultimate_orb_face_resident_bytes := 0
const ULTIMATE_ORB_FACE_TEXTURE_SIZE := 192
const MAX_PRESENTATION_SPEED := 1.35
const MAX_EVENTS_PER_FRAME := 48
const MAX_ACTIVE_PROJECTILES := 24
const MAX_ACTIVE_FLOATING_TEXTS := 40
const MAX_ACTIVE_VFX := 32
const BOSS_PATTERN_CARD_PREFIX := "BOSS_PATTERN"
## Each ID has an independently hashed high-density source pack. These are
## candidate IDs, not a global preload list: only the present encounter leases
## the pages it needs, and the sprite library refuses an over-budget lease
## before allocating decoded browser textures.
## R13 covers the actual starting five-player squad (CHR001 through CHR005),
## the reviewed CHR008 alternate-party slice, and the current boss/common-enemy
## group. Every listed source has a pinned 384px logical signature atlas;
## runtime holds core motion plus only the current caster ultimate, never a
## full-party ultimate preload.
const SIGNATURE_ENTITY_IDS := ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005", "CHR008", "BOSS001", "ENM001"]
const SIGNATURE_SCALE_MULTIPLIERS := {
	"CHR001": 1.30,
	"CHR002": 1.30,
	"CHR003": 1.28,
	"CHR004": 1.28,
	"CHR005": 1.28,
	"CHR008": 1.28,
	"BOSS001": 1.44,
	"ENM001": 1.30,
}
const SIGNATURE_ULTIMATE_PORTRAIT_IDS := ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005", "CHR008"]
## The reviewed high-density reference group uses the same animated combat
## authority in its cinematic cut-in. This keeps player and boss shots equally
## sharp and avoids mixing a 384px battle pose with an unrelated legacy card.
const CINEMATIC_SIGNATURE_POSE_IDS := ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005", "CHR008", "BOSS001"]
## CHR008's legacy 8-head card depicts a different visual identity from its
## reviewed R6P2 combat authority.  Use the exact combat pose for its orb and
## cut-in until a separately reviewed matching portrait exists; never place the
## unrelated card beside the silver-lavender SD medic in active battle.
const IDENTITY_LOCKED_SPRITE_CUTIN_IDS := ["CHR008"]
const EFFECT_SIGNATURE_ENTITY_IDS := EffectSignatureLibrary.SIGNATURE_ENTITY_IDS
const BOSS_PHASE_PRESENTATION := {
	"PHASE_2": {
		"title_key": "BATTLE_BOSS_PHASE_2_TITLE",
		"subtitle_key": "BATTLE_BOSS_PHASE_2_SUBTITLE",
		"color": "71e7ff",
		"duration": 2.35,
	},
	"ENRAGE": {
		"title_key": "BATTLE_BOSS_ENRAGE_TITLE",
		"subtitle_key": "BATTLE_BOSS_ENRAGE_SUBTITLE",
		"color": "ff6178",
		"duration": 2.60,
	},
}

static func card_start_id_for_event(event: Dictionary, source: Dictionary) -> String:
	var extra: Dictionary = event.get("extra", {})
	var boss_pattern := str(extra.get("boss_pattern", "")).strip_edges()
	if not boss_pattern.is_empty():
		var source_id := str(source.get("def_id", "")).strip_edges()
		if source_id.is_empty():
			source_id = str(event.get("source", "")).trim_prefix("E:").trim_prefix("P:")
		return "%s:%s:%s" % [BOSS_PATTERN_CARD_PREFIX, source_id, boss_pattern]
	return str(extra.get("skill_id", "")).strip_edges()

static func damage_event_has_hit_sfx(event: Dictionary) -> bool:
	var extra: Dictionary = event.get("extra", {})
	if bool(extra.get("miss", false)) or bool(extra.get("invulnerable", false)):
		return false
	return int(event.get("value", 0)) > 0 or int(extra.get("hp_damage", 0)) > 0 or int(extra.get("shield_damage", 0)) > 0
# In-app GPT review approved this Base + Signature + Accent profile split for
# the actual Chapter 1 roster.  A profile expresses motion language as well as
# colour, so an ally heal, an enemy curse and a boss void cast do not collapse
# into the same generic radial burst.  The atlas builder owns the signature
# pixels; this table chooses the lightweight shared base and draw-time accent.
const VFX_UNIT_PROFILES := {
	"CHR001": {"primary": "79e7ff", "secondary": "ffd36a", "normal": "shield", "ultimate": "shield"},
	"CHR002": {"primary": "b8c7d9", "secondary": "ff9b54", "normal": "rush", "ultimate": "rush"},
	"CHR003": {"primary": "7fd8ff", "secondary": "ff6ea8", "normal": "tracer", "ultimate": "artillery"},
	"CHR004": {"primary": "43d7ff", "secondary": "fff16a", "normal": "lightning", "ultimate": "lightning"},
	"CHR005": {"primary": "a58cff", "secondary": "ffd36a", "normal": "artillery", "ultimate": "artillery"},
	"CHR006": {"primary": "d6f4ff", "secondary": "6d7bff", "normal": "distort", "ultimate": "distort"},
	"CHR007": {"primary": "8cfff0", "secondary": "7bb3ff", "normal": "shield", "ultimate": "shield"},
	"CHR008": {"primary": "b9ffcf", "secondary": "ffd98a", "normal": "heal", "ultimate": "heal"},
	"ENM001": {"primary": "ff6a2a", "secondary": "ffd05a", "normal": "flame", "ultimate": "flame_split"},
	"ENM002": {"primary": "5be5ff", "secondary": "8c79ff", "normal": "tracer", "ultimate": "lightning"},
	"ENM003": {"primary": "7e8a98", "secondary": "ffd36a", "normal": "heavy", "ultimate": "plate_rupture"},
	"ENM004": {"primary": "83ffc7", "secondary": "72c7ff", "normal": "heal", "ultimate": "barrier_mend"},
	"ENM005": {"primary": "ffd36a", "secondary": "ff8fd2", "normal": "chorus", "ultimate": "harmonic_bars"},
	"ENM006": {"primary": "b9a47a", "secondary": "7c8c5a", "normal": "dust", "ultimate": "dust_shear"},
	"ENM007": {"primary": "e5e0d6", "secondary": "8a6cff", "normal": "summon", "ultimate": "ward_gate"},
	"ENM008": {"primary": "ff57d1", "secondary": "48e7ff", "normal": "broadcast_glitch", "ultimate": "broadcast_tear"},
	"ENM009": {"primary": "aab7c8", "secondary": "ffd36a", "normal": "iron_vibration", "ultimate": "slab_resonance"},
	# Bosses deliberately use motion grammars which no character or regular enemy
	# shares.  A boss must remain identifiable by its ultimate silhouette even
	# with palette information removed in a busy 5v5 Web battle.
	"BOSS001": {"primary": "35e0ff", "secondary": "7a2bff", "normal": "void", "ultimate": "implode"},
	"BOSS002": {"primary": "a7b8ff", "secondary": "ffd36a", "normal": "chorus", "ultimate": "resonance"},
	"ENM010": {"primary": "38e5ff", "secondary": "447cff", "normal": "rush_cut", "ultimate": "rush_cut"},
	"ENM011": {"primary": "a9f7ff", "secondary": "6e91ff", "normal": "glass_tracer", "ultimate": "glass_tracer"},
	"ENM012": {"primary": "ffa46e", "secondary": "ba6eff", "normal": "barrier_fracture", "ultimate": "barrier_fracture"},
	"BOSS003": {"primary": "e9fbff", "secondary": "79dfff", "normal": "orbital_scan", "ultimate": "lockon"},
	"ENM013": {"primary": "ff59cf", "secondary": "5be7ff", "normal": "reverse_arc", "ultimate": "reverse_arc"},
	"ENM014": {"primary": "ffb543", "secondary": "54e2ff", "normal": "artillery", "ultimate": "battery_barrage"},
	"ENM015": {"primary": "ce7cff", "secondary": "65f5dd", "normal": "chorus", "ultimate": "chorus_collapse"},
	"BOSS004": {"primary": "72e7ff", "secondary": "ffbb63", "normal": "heavy", "ultimate": "gate_reverse"},
	"BOSS005": {"primary": "62f1dd", "secondary": "f6c65d", "normal": "summon", "ultimate": "network"},
}
const SIGNAL_BREAKER_ULTIMATE_BASE_KEY := "base_signal_breaker_ultimate"

# Damage and defeat commit on contact, using the same clock as the projectile.
const CONTACT_DELAY := .44
var contact_events: Array[Dictionary] = []
var engagement_positions: Dictionary = {}
var engagement_targets: Dictionary = {}
var opening_elapsed := 0.0
var combat_readout := ""
var combat_readout_left := 0.0
const WAVE_BANNER_DURATION := 1.7
var wave_banner_left := 0.0
var wave_banner_title := ""
var wave_banner_subtitle := ""
var contact_commits := 0
## Tactical layer. The shell owns the interaction; the view freezes the
## simulation clock while the player deploys, holds an ally selected or aims an
## ultimate, and draws the grid, reach, danger cells and previews.
var deployment_active := false
var tactical_hold := false
var tactical_selected_uid := ""
var tactical_aim_uid := ""
var tactical_preview_uid := ""
## Phase 1 presentation (2026-09-30). Every field below is view-only: it reads
## the event log and the simulation state and never writes back to either.
## Skill nameplates (allies) and shout bubbles (enemies): at most two on screen,
## ultimates and boss cues win over ordinary skills.
const MAX_SKILL_CALLOUTS := 2
## "N연속" counts allied hits that land within this window of each other.
const COMBO_WINDOW := 2.0
const COMBO_MIN_DISPLAY := 3
var combo_count := 0
var combo_peak := 0
var combo_left := 0.0
var combo_pop := 0.0
## Victory end card ("결착 · 작전 완료") held before the result hand-off.
const FINALE_DURATION := 1.45
var finale_elapsed := -1.0
## "작전 개시!" owns the screen for a moment after the deployment ends: the
## simulation starts after this hold, so an automatic opening ultimate cannot
## cover the start band. Wall-clock only; the tick sequence is unchanged.
const START_BAND_TITLE := "작전 개시!"
const START_BAND_HOLD := .9
var start_band_armed := false
## Scale read (D7). A regular enemy is drawn as a three-body squad around the
## authoritative unit. The two extra bodies are presentation only: they share
## its HP bar and drop out once the shown HP falls below 2/3 and 1/3. Offset x
## is in sprite-canvas widths (toward the enemy rear), y in lane steps.
const SWARM_COMPANIONS := [
	{"offset": Vector2(.36, -.22), "scale": .76, "phase": 1.9, "threshold": 2.0 / 3.0},
	{"offset": Vector2(-.26, -.34), "scale": .70, "phase": 3.7, "threshold": 1.0 / 3.0},
]
const SWARM_DROP_DURATION := .5
var swarm_members: Dictionary = {}
var swarm_drops: Array = []
## The next wave waits as dark silhouettes on the far walkway behind the enemy
## side until it spawns. Its layout comes from the same call the deployment
## preview uses, cached per wave.
const NEXT_WAVE_FADE := .8
const SILHOUETTE_SCALE := .6
## Footing ring: semi-axes at width factor 1 (ally .8, enemy 1.35, boss 1.8) and
## a fixed stroke; the original breathing stroke (2.2-3.0 px) is its mid value.
const FOOTING_RING_RADIUS := Vector2(45.0, 10.0)
const FOOTING_RING_STROKE := 2.6
const FOOTING_RING_WIDTHS := [0.8, 1.35, 1.8]
const SILHOUETTE_RIM_OFFSETS := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
const INTENT_ARC_STEPS := 32
var _intent_arcs: Dictionary = {}
var next_wave_cache := {"index": -2, "layout": []}
var next_wave_age := 0.0
## Per-draw overrides for `_draw_combat_sprite`, set only around squad bodies
## and silhouettes and always restored.
var sprite_draw_scale := 1.0
var sprite_draw_tint := Color.WHITE
var sprite_live_phase := 0.0
## Telegraph landing flash: a cast that leaves the pending list on its due tick
## with a living caster flashes its cells once.
const TELEGRAPH_FLASH_DURATION := .42
var telegraph_keys: Dictionary = {}
var telegraph_flashes: Array = []
## Ultimate cut-in. SHORT (default) plays inside the ordinary 2.10s timeline and
## runs long once per character; FULL is always long; OFF keeps the compact
## caster pulse. The long version adds a lead-in before the unchanged timeline.
const CUTIN_MODES := ["SHORT", "FULL", "OFF"]
const LONG_CUTIN_LEAD_IN := 1.05
var cutin_mode := "SHORT"
var cutin_seen_ids: Dictionary = {}
var cutin_first_use_enabled := false
var cutin_settings_bound := false
var active_cutin: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bind_cutin_settings()
	# Adding BattleView to the scene tree used to synchronously decode every wave's
	# combat, projectile and VFX atlas before the browser could paint even one
	# battlefield frame. Keep the deterministic simulation stopped, allow the
	# responsive shell to paint, then warm one entity at a time on later frames.
	assets_ready = false
	asset_warmup_phase = "SHELL"
	set_process(false)
	queue_redraw()
	call_deferred("_warm_battle_assets")

func _exit_tree() -> void:
	# A BattleView owns its high-density encounter lease. Releasing its direct
	# references here prevents an ended encounter from retaining actor/effect
	# atlases or HUD face crops while another battle is entered.
	_clear_active_presentation_effects()
	_release_signature_residency()

func _warm_battle_assets() -> void:
	if simulation == null or not is_inside_tree():
		_finish_asset_warmup()
		return
	# Parse contact metadata inside the existing asset gate, never lazily on the
	# first visible attack frame. The shared registry is read-only afterward.
	Grounding.contacts("compact", "CHR001", "idle", 0.0)
	var current_entity_ids := _current_wave_entity_ids()
	var reinforcement_entity_ids := _reinforcement_entity_ids(current_entity_ids)
	var active_entity_ids := _active_battle_entity_ids()
	var signature_residency_ids: Array[String] = []
	_reset_battle_asset_state()

	# Chapter-map entry may have completed the exact same immutable pack already.
	# Reattach its manifests and atlas-backed frame views before scheduling any
	# ResourceLoader work, so a map-to-battle handoff never decodes a second copy.
	if _attach_stage_asset_cache_bundle(active_entity_ids):
		# The stage cache predates the reviewed SD defeat-pose lease. Attach those
		# small static textures after the immutable animation bundle is restored.
		sprite_library.load_down_pose_pack(active_entity_ids)
		asset_warmup_phase = "CACHE_READY"
		asset_warmup_phase = "FULL_DENSITY_ACTORS"
		await sprite_library.warm_full_density(active_entity_ids, self)
		await action_frames.warm(active_entity_ids, self)
		if not is_inside_tree(): return
		signature_residency_ids = _signature_residency_entity_ids()
		await _warm_full_density_effects(active_entity_ids)
		await _warm_signature_sprite_pack(signature_residency_ids)
		await _warm_effect_signature_pack(signature_residency_ids)
		_commit_signature_residency_or_fallback(signature_residency_ids)
		await _warm_ultimate_portraits(current_entity_ids)
		_finish_asset_warmup()
		return

	asset_input_blocker = Control.new()
	asset_input_blocker.name = "BattleAssetWarmupInputBlocker"
	asset_input_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	asset_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(asset_input_blocker)

	# The first await is the important Web entry boundary: app_shell has already
	# attached the HUD, so the user sees a stable battle shell instead of a frozen
	# previous screen while PNG/WebP resources decode.
	await _yield_asset_warmup("SHELL")
	for entity_id in current_entity_ids:
		_append_sprite_pack(entity_id)
		await _yield_asset_warmup("CURRENT_ACTOR:%s" % entity_id)
	for entity_id in reinforcement_entity_ids:
		_append_sprite_pack(entity_id)
		await _yield_asset_warmup("REINFORCEMENT_ACTOR:%s" % entity_id)
	# Player-only prone poses are loaded once per encounter. Enemy and boss IDs
	# have no down-pose files and therefore continue through the explosion path.
	sprite_library.load_down_pose_pack(active_entity_ids)
	_load_combat_preview_fallbacks(active_entity_ids)
	asset_warmup_phase = "FULL_DENSITY_ACTORS"
	await sprite_library.warm_full_density(active_entity_ids, self)
	await action_frames.warm(active_entity_ids, self)
	if not is_inside_tree(): return
	signature_residency_ids = _signature_residency_entity_ids()
	await _warm_signature_sprite_pack(signature_residency_ids)
	if not sprite_library.load_error.is_empty():
		push_warning("Battle sprite pack unavailable: %s" % sprite_library.load_error)

	# A normal stage can never transition to the boss background. Avoid decoding
	# that second 1920x1080 texture for all such battles. Every stage with a BOSS
	# wave carries the canonical `boss` flag and retains both backgrounds.
	normal_background = load("res://assets/art/backgrounds/BG_BATTLE_GLASS_RAIL/bg_battle_glass_rail_1920x1080.png")
	if bool(simulation.stage.get("boss", false)):
		boss_background = load("res://assets/art/backgrounds/BG_BOSS_SIGNAL_CATHEDRAL/bg_boss_signal_cathedral_1920x1080.png")
	else:
		boss_background = null
	battle_font = load("res://assets/fonts/LanternSans-Medium.ttf") as Font
	_bind_damage_font_fallback()
	await _yield_asset_warmup("BATTLE_SHELL")

	for entity_id in current_entity_ids:
		_append_projectile_pack(entity_id)
		await _yield_asset_warmup("CURRENT_PROJECTILE:%s" % entity_id)
	for entity_id in reinforcement_entity_ids:
		_append_projectile_pack(entity_id)
		await _yield_asset_warmup("REINFORCEMENT_PROJECTILE:%s" % entity_id)
	if not projectile_library.load_error.is_empty():
		push_warning("Projectile sprite pack unavailable: %s" % projectile_library.load_error)

	var reset_vfx := true
	for entity_id in current_entity_ids:
		var current_vfx_ids: Array[String] = [entity_id]
		_load_runtime_vfx(current_vfx_ids, reset_vfx)
		reset_vfx = false
		await _yield_asset_warmup("CURRENT_VFX:%s" % entity_id)
	for entity_id in reinforcement_entity_ids:
		var reinforcement_vfx_ids: Array[String] = [entity_id]
		_load_runtime_vfx(reinforcement_vfx_ids, reset_vfx)
		reset_vfx = false
		await _yield_asset_warmup("REINFORCEMENT_VFX:%s" % entity_id)
	await _warm_full_density_effects(active_entity_ids)
	await _warm_effect_signature_pack(signature_residency_ids)
	_commit_signature_residency_or_fallback(signature_residency_ids)
	await _warm_ultimate_portraits(current_entity_ids)

	# Later SPAWN events may rotate only the bounded signature lease through its
	# deferred release-before-acquire path. All compact actor/projectile/VFX packs
	# are already resident, so a failed or pending rollover never shows a blank
	# silhouette or a partial high-density presentation.
	asset_warmup_phase = "READY"
	_finish_asset_warmup()

func _density_page_ready(relative_path: String) -> void:
	asset_warmup_phase = "HD_PAGE:" + relative_path

func _warm_full_density_effects(entity_ids: Array[String]) -> void:
	asset_warmup_phase = "FULL_DENSITY_EFFECTS"
	if await full_density_effects.warm(entity_ids, self):
		vfx_frames.merge(full_density_effects.effects, true)
	elif not full_density_effects.error.is_empty():
		push_warning("Full-density effect pack unavailable: %s" % full_density_effects.error)

func _reset_battle_asset_state() -> void:
	full_density_effects = preload("res://battle/view/full_density_effects.gd").new()
	asset_cache_hit = false
	sprite_library.manifests.clear()
	sprite_library.frames.clear()
	sprite_library.full_density_bytes_by_entity.clear()
	sprite_library.full_density_error = ""
	sprite_library.clear_down_pose_pack()
	action_frames.clear()
	sprite_library.load_error = ""
	projectile_library.manifests.clear()
	projectile_library.frames.clear()
	projectile_library.load_error = ""
	_release_signature_residency()
	vfx_frames.clear()
	runtime_vfx_entries.clear()
	runtime_vfx_manifest_loaded = false
	fallback_combat_previews.clear()
	sprite_pack_ready = false
	projectile_pack_ready = false

func _release_signature_residency() -> void:
	sprite_library.clear_signature_pack()
	effect_signature_library.clear_signature_pack()
	ultimate_orb_face_textures.clear()
	ultimate_orb_face_resident_bytes = 0
	signature_sprite_pack_ready = false
	effect_signature_pack_ready = false
	signature_residency_target_ids.clear()
	signature_fallback_target_ids.clear()
	signature_fallback_error = ""
	signature_rollover_requested = false


func signature_runtime_residency_snapshot() -> Dictionary:
	## Keep the decoded encounter lease distinct from the immutable candidate
	## inventory.  The latter can contain an approved alternate (CHR008), but a
	## current battle must report only the actor/effect/face resources it actually
	## owns.  This snapshot is intentionally scalar/JSON-safe so phone QA and
	## release-gate tooling cannot mistake an available asset for a resident one.
	var actor_snapshot: Dictionary = sprite_library.signature_residency_snapshot()
	var effect_snapshot: Dictionary = effect_signature_library.signature_residency_snapshot()
	var face_entity_ids: Array[String] = []
	var face_crop_resident_bytes_by_entity: Dictionary = {}
	for cache_key_value in ultimate_orb_face_textures:
		var cache_key := str(cache_key_value)
		var separator := cache_key.find(":")
		var entity_id := cache_key.left(separator) if separator >= 0 else cache_key
		if not entity_id.is_empty() and not face_entity_ids.has(entity_id):
			face_entity_ids.append(entity_id)
		if not entity_id.is_empty():
			face_crop_resident_bytes_by_entity[entity_id] = int(face_crop_resident_bytes_by_entity.get(entity_id, 0)) + ULTIMATE_ORB_FACE_TEXTURE_SIZE * ULTIMATE_ORB_FACE_TEXTURE_SIZE * 4
	var active_encounter_ids := _signature_residency_entity_ids()
	var inactive_candidate_ids: Array[String] = []
	for entity_id in SIGNATURE_ENTITY_IDS:
		if entity_id not in active_encounter_ids:
			inactive_candidate_ids.append(entity_id)
	return {
		"candidate_signature_entity_ids": SIGNATURE_ENTITY_IDS.duplicate(),
		"full_density_effects": full_density_effects.snapshot(),
		"full_density": sprite_library.full_density_snapshot(),
		"action_frames": action_frames.snapshot(),
		"active_encounter_ids": active_encounter_ids,
		"fallback_target_ids": signature_fallback_target_ids.duplicate(),
		"fallback_error": signature_fallback_error,
		"rollover_active": signature_rollover_active,
		"inactive_candidate_ids": inactive_candidate_ids,
		"resident_actor_ids": Array(actor_snapshot.get("entity_ids", [])).duplicate(),
		"resident_effect_entity_ids": Array(effect_snapshot.get("entity_ids", [])).duplicate(),
		"resident_effect_profile_ids": Array(effect_snapshot.get("profile_ids", [])).duplicate(),
		"actor_core_resident_atlas_bytes": int(actor_snapshot.get("core_resident_atlas_bytes", 0)),
		"actor_resident_atlas_bytes": int(actor_snapshot.get("resident_atlas_bytes", 0)),
		"effect_core_resident_atlas_bytes": int(effect_snapshot.get("core_resident_atlas_bytes", 0)),
		"effect_resident_atlas_bytes": int(effect_snapshot.get("resident_atlas_bytes", 0)),
		"face_crop_entity_ids": face_entity_ids,
		"face_crop_resident_bytes": ultimate_orb_face_resident_bytes,
		"face_crop_resident_bytes_by_entity": face_crop_resident_bytes_by_entity,
	}

func _finish_asset_warmup() -> void:
	assets_ready = true
	if asset_input_blocker != null:
		asset_input_blocker.queue_free()
		asset_input_blocker = null
	set_process(true)
	queue_redraw()
	battle_assets_ready.emit()

func _warm_ultimate_portraits(entity_ids: Array[String]) -> void:
	# Decode each approved player cut-in behind the same incremental warm-up gate
	# as combat sprites so an ultimate never adds a synchronous Web texture load.
	ultimate_portraits.clear()
	for entity_id in SIGNATURE_ULTIMATE_PORTRAIT_IDS:
		if not entity_ids.has(entity_id):
			continue
		if entity_id in CINEMATIC_SIGNATURE_POSE_IDS:
			# Existing runtime cards remain untouched for provenance, but this combat
			# slice deliberately renders the reviewed animated authority instead of
			# decoding a second visual family into the active battle memory budget.
			continue
		var portrait := _load_runtime_texture("res://assets/runtime_web/characters/%s/portrait.png" % entity_id)
		if portrait != null:
			ultimate_portraits[entity_id] = portrait
		await _yield_asset_warmup("ULTIMATE_PORTRAIT:%s" % entity_id)

func ultimate_orb_texture_for(entity_id: String, fallback: Texture2D) -> Texture2D:
	# HUD portraits need the same identity continuity contract as cinematic
	# cut-ins. The high-density idle pose is preferred when the local candidate is
	# active; the compact combat idle is a truthful release fallback, not a swap
	# back to a mismatched 8-head card.
	var source_texture := fallback
	var source_key := "fallback"
	var signature_frame_info: Dictionary = {}
	if signature_sprite_pack_ready and sprite_library.has_signature_animation(entity_id, "idle"):
		signature_frame_info = sprite_library.signature_frame_info_at(entity_id, "idle", .24)
		var signature_texture = signature_frame_info.get("texture", null)
		if signature_texture is Texture2D:
			source_texture = signature_texture as Texture2D
			source_key = "signature"
	elif entity_id in IDENTITY_LOCKED_SPRITE_CUTIN_IDS and sprite_pack_ready and sprite_library.has_animation(entity_id, "idle"):
		var compact_texture := sprite_library.texture_at(entity_id, "idle", .24)
		if compact_texture != null:
			source_texture = compact_texture
			source_key = "combat"
	if source_texture == null:
		return null
	var cache_key := "%s:%s" % [entity_id, source_key]
	if ultimate_orb_face_textures.has(cache_key):
		return ultimate_orb_face_textures[cache_key] as Texture2D
	var face_crop := _build_ultimate_orb_face_crop(source_texture, ultimate_orb_face_focus_for(entity_id), signature_frame_info)
	if face_crop != null:
		ultimate_orb_face_textures[cache_key] = face_crop
		ultimate_orb_face_resident_bytes += ULTIMATE_ORB_FACE_TEXTURE_SIZE * ULTIMATE_ORB_FACE_TEXTURE_SIZE * 4
		return face_crop
	# If a future platform cannot read a texture image at runtime, retain the
	# legitimate source portrait rather than showing a blank tactical control.
	return source_texture


func ultimate_orb_face_focus_for(entity_id: String) -> Vector2:
	# Full-body profile illustrations and transparent SD combat cells have
	# different facial centers. Keep the HUD face crop explicit so the circular
	# tactical control never regresses to a miniature whole-body card.
	if entity_id == "CHR008":
		return Vector2(.43, .23)
	if entity_id == "CHR001":
		return Vector2(.49, .25)
	if entity_id == "CHR002":
		return Vector2(.49, .25)
	return Vector2(.50, .25)


func _build_ultimate_orb_face_crop(texture: Texture2D, focus: Vector2, signature_frame_info: Dictionary = {}) -> Texture2D:
	var source_image: Image
	if texture is AtlasTexture:
		var atlas_texture := texture as AtlasTexture
		if atlas_texture.atlas == null:
			return null
		var atlas_image := atlas_texture.atlas.get_image()
		if atlas_image == null or atlas_image.is_empty():
			return null
		var source_region := atlas_texture.region
		var region := Rect2i(roundi(source_region.position.x), roundi(source_region.position.y), roundi(source_region.size.x), roundi(source_region.size.y))
		if region.size.x <= 0 or region.size.y <= 0:
			return null
		source_image = atlas_image.get_region(region)
		if signature_frame_info.is_empty() and atlas_texture.margin.size != Vector2.ZERO:
			var logical_image := Image.create(texture.get_width(), texture.get_height(), false, Image.FORMAT_RGBA8)
			logical_image.fill(Color.TRANSPARENT)
			logical_image.blit_rect(source_image, Rect2i(Vector2i.ZERO, source_image.get_size()), Vector2i(atlas_texture.margin.position))
			source_image = logical_image
	else:
		source_image = texture.get_image()
	if source_image == null or source_image.is_empty():
		return null
	# An alpha-tight R5 frame is physically cropped but has an immutable logical
	# 384px placement. Recompose only this one tiny transient Image before making
	# the cached 192px face crop; do not materialize full canvases for every
	# animation frame or reintroduce the atlas residency we just removed.
	if not signature_frame_info.is_empty():
		var logical_rect_value = signature_frame_info.get("logical_rect", null)
		var logical_canvas_value = signature_frame_info.get("logical_canvas_size", null)
		if logical_rect_value is Rect2 and logical_canvas_value is Vector2:
			var logical_rect: Rect2 = logical_rect_value
			var logical_canvas: Vector2 = logical_canvas_value
			var logical_size := Vector2i(roundi(logical_canvas.x), roundi(logical_canvas.y))
			var logical_origin := Vector2i(roundi(logical_rect.position.x), roundi(logical_rect.position.y))
			if logical_size.x > 0 and logical_size.y > 0 and source_image.get_width() == roundi(logical_rect.size.x) and source_image.get_height() == roundi(logical_rect.size.y):
				var reconstructed := Image.create(logical_size.x, logical_size.y, false, Image.FORMAT_RGBA8)
				reconstructed.fill(Color(0, 0, 0, 0))
				reconstructed.blit_rect(source_image, Rect2i(Vector2i.ZERO, source_image.get_size()), logical_origin)
				source_image = reconstructed
	var source_size := Vector2i(source_image.get_width(), source_image.get_height())
	var crop_side := maxi(1, roundi(float(mini(source_size.x, source_size.y)) / 2.45))
	if crop_side < 2:
		return null
	var safe_focus := focus.clamp(Vector2(.06, .06), Vector2(.94, .94))
	var center := Vector2(float(source_size.x) * safe_focus.x, float(source_size.y) * safe_focus.y)
	var origin := Vector2i(roundi(center.x - crop_side * .5), roundi(center.y - crop_side * .5))
	origin.x = clampi(origin.x, 0, source_size.x - crop_side)
	origin.y = clampi(origin.y, 0, source_size.y - crop_side)
	var face_image := source_image.get_region(Rect2i(origin, Vector2i(crop_side, crop_side)))
	if face_image == null or face_image.is_empty():
		return null
	face_image.resize(ULTIMATE_ORB_FACE_TEXTURE_SIZE, ULTIMATE_ORB_FACE_TEXTURE_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(face_image)

func _signature_cutin_pose_texture(source_id: String, elapsed: float) -> Texture2D:
	if source_id not in CINEMATIC_SIGNATURE_POSE_IDS:
		return null
	if signature_sprite_pack_ready and sprite_library.has_signature_animation(source_id, "ultimate"):
		var signature_texture := sprite_library.signature_texture_at(source_id, "ultimate", elapsed)
		if signature_texture != null:
			return signature_texture
	if sprite_pack_ready and sprite_library.has_animation(source_id, "ultimate"):
		return sprite_library.texture_at(source_id, "ultimate", elapsed)
	return null

func _attach_stage_asset_cache_bundle(active_entity_ids: Array[String]) -> bool:
	if simulation == null:
		return false
	# Resolve dynamically so the direct/debug path stays parser-safe in editor
	# contexts that intentionally omit the optional StageAssetCache autoload.
	var cache := get_tree().root.get_node_or_null("StageAssetCache")
	if cache == null or not cache.has_method("has_battle_assets") or not cache.has_method("battle_bundle"):
		return false
	var require_boss := bool(simulation.stage.get("boss", false))
	if not bool(cache.call("has_battle_assets", active_entity_ids, require_boss)):
		return false
	var bundle_value = cache.call("battle_bundle", active_entity_ids, require_boss)
	if not bundle_value is Dictionary:
		return false
	var bundle: Dictionary = bundle_value
	if not _attach_cached_actor_frames(bundle.get("actor_manifests", {}), bundle.get("actor_frames", {}), active_entity_ids):
		_reset_battle_asset_state()
		return false
	if not _attach_cached_projectile_frames(bundle.get("projectile_manifests", {}), bundle.get("projectile_frames", {}), active_entity_ids):
		_reset_battle_asset_state()
		return false
	if not _attach_cached_vfx_frames(bundle.get("vfx_frames", {}), active_entity_ids):
		_reset_battle_asset_state()
		return false
	var normal_value = bundle.get("normal_background")
	var font_value = bundle.get("battle_font")
	if not normal_value is Texture2D or not font_value is Font:
		_reset_battle_asset_state()
		return false
	var cached_boss_background = bundle.get("boss_background")
	if require_boss and not cached_boss_background is Texture2D:
		_reset_battle_asset_state()
		return false
	normal_background = normal_value
	boss_background = cached_boss_background if cached_boss_background is Texture2D else null
	battle_font = font_value
	_bind_damage_font_fallback()
	var cached_fallbacks = bundle.get("fallback_previews", {})
	if cached_fallbacks is Dictionary:
		for entity_id in cached_fallbacks:
			var preview = cached_fallbacks[entity_id]
			if preview is Texture2D:
				fallback_combat_previews[str(entity_id)] = preview
	runtime_vfx_manifest_loaded = true
	asset_cache_hit = true
	return true

func _attach_cached_actor_frames(manifests_value, frames_value, active_entity_ids: Array[String]) -> bool:
	if not manifests_value is Dictionary or not frames_value is Dictionary:
		return false
	var staged_manifests: Dictionary = {}
	var staged_frames: Dictionary = {}
	for entity_id in active_entity_ids:
		var manifest_value = manifests_value.get(entity_id, {})
		var character_frames_value = frames_value.get(entity_id, {})
		if not manifest_value is Dictionary or not character_frames_value is Dictionary:
			return false
		var manifest: Dictionary = manifest_value
		var character_frames: Dictionary = character_frames_value
		var animations_value = manifest.get("animations", {})
		if not animations_value is Dictionary or animations_value.is_empty():
			return false
		for animation_name_value in animations_value:
			var textures_value = character_frames.get(str(animation_name_value), [])
			if not textures_value is Array or textures_value.is_empty():
				return false
			for texture_value in textures_value:
				if not texture_value is Texture2D:
					return false
		staged_manifests[entity_id] = manifest.duplicate(true)
		# AtlasTexture resources are immutable cached inputs. Copy the containers,
		# retain those already-built frame resources, and never decode another atlas.
		staged_frames[entity_id] = character_frames.duplicate(true)
	sprite_library.manifests = staged_manifests
	sprite_library.frames = staged_frames
	sprite_pack_ready = not staged_manifests.is_empty()
	return sprite_pack_ready

func _attach_cached_projectile_frames(manifests_value, frames_value, active_entity_ids: Array[String]) -> bool:
	if not manifests_value is Dictionary or not frames_value is Dictionary:
		return false
	var staged_manifests: Dictionary = {}
	var staged_frames: Dictionary = {}
	for entity_id in active_entity_ids:
		var manifest_value = manifests_value.get(entity_id, {})
		var textures_value = frames_value.get(entity_id, [])
		if not manifest_value is Dictionary or not textures_value is Array or textures_value.size() != 8:
			return false
		for texture_value in textures_value:
			if not texture_value is Texture2D:
				return false
		staged_manifests[entity_id] = (manifest_value as Dictionary).duplicate(true)
		staged_frames[entity_id] = (textures_value as Array).duplicate(true)
	projectile_library.manifests = staged_manifests
	projectile_library.frames = staged_frames
	projectile_pack_ready = not staged_manifests.is_empty()
	return projectile_pack_ready

func _attach_cached_vfx_frames(frames_value, active_entity_ids: Array[String]) -> bool:
	if not frames_value is Dictionary:
		return false
	var staged_frames: Dictionary = {}
	for key_value in frames_value:
		var textures_value = frames_value[key_value]
		if not textures_value is Array or textures_value.size() != 12:
			return false
		for texture_value in textures_value:
			if not texture_value is Texture2D:
				return false
		staged_frames[str(key_value)] = (textures_value as Array).duplicate(true)
	if not staged_frames.has(SIGNAL_BREAKER_ULTIMATE_BASE_KEY):
		return false
	for entity_id in active_entity_ids:
		for kind in ["basic", "normal", "ultimate"]:
			if not staged_frames.has("%s_%s" % [entity_id.to_lower(), kind]):
				return false
	vfx_frames = staged_frames
	return true

func _yield_asset_warmup(phase: String) -> void:
	asset_warmup_phase = phase
	queue_redraw()
	await get_tree().process_frame

func _asset_warmup_display_label() -> String:
	if asset_warmup_phase.begins_with("CURRENT_ACTOR"):
		return "선발 부대 배치"
	if asset_warmup_phase.begins_with("REINFORCEMENT_ACTOR"):
		return "증원 경로 계산"
	if asset_warmup_phase.contains("PROJECTILE"):
		return "탄도 데이터 준비"
	if asset_warmup_phase.contains("VFX"):
		return "전술 효과 준비"
	if asset_warmup_phase.begins_with("EFFECT_SIGNATURE"):
		return "발사체·필살기 이펙트 해상도 준비"
	if asset_warmup_phase.begins_with("SIGNATURE"):
		return "필살기 해상도 준비"
	return "전장 구성"

func _warm_signature_sprite_pack(entity_ids: Array[String]) -> void:
	var signature_ids: Array[String] = []
	for entity_id_value in entity_ids:
		var entity_id := str(entity_id_value)
		if entity_id in SIGNATURE_ENTITY_IDS and not sprite_library.is_reviewed_roster_redraw(entity_id) and not signature_ids.has(entity_id):
			signature_ids.append(entity_id)
	if signature_ids.is_empty():
		signature_sprite_pack_ready = false
		signature_residency_target_ids.clear()
		return
	# Only the states that can remain visible throughout a battle are resident at
	# entry. The currently casting signature unit acquires its ultimate page as a
	# bounded transient lease immediately before the cinematic begins.
	signature_sprite_pack_ready = await sprite_library.load_signature_core_pack_sliced(signature_ids, self) if OS.has_feature("web") else sprite_library.load_signature_core_pack(signature_ids)
	signature_residency_target_ids = signature_ids.duplicate() if signature_sprite_pack_ready else []
	if not sprite_library.signature_load_error.is_empty():
		push_warning("Battle signature sprite pack unavailable: %s" % sprite_library.signature_load_error)
	for entity_id in signature_ids:
		if sprite_library.signature_manifests.has(entity_id):
			await _yield_asset_warmup("SIGNATURE:%s" % entity_id)

func _warm_effect_signature_pack(entity_ids: Array[String]) -> void:
	# Effects use a separate approval and memory budget from actor atlases.  The
	# baseline projectile/VFX packs remain attached first, so a missing candidate
	# can only fall back to the exact authored compact asset, never to a blank or
	# foreign effect.
	var signature_ids: Array[String] = []
	for entity_id_value in entity_ids:
		var entity_id := str(entity_id_value)
		if entity_id in EFFECT_SIGNATURE_ENTITY_IDS and not signature_ids.has(entity_id):
			signature_ids.append(entity_id)
	if signature_ids.is_empty():
		effect_signature_pack_ready = false
		return
	# Projectiles are used by regular attacks throughout the encounter, while the
	# heavier ultimate cell sheet is leased only for the current caster.
	effect_signature_pack_ready = await effect_signature_library.load_signature_core_pack_sliced(signature_ids, self) if OS.has_feature("web") else effect_signature_library.load_signature_core_pack(signature_ids)
	if not effect_signature_library.signature_load_error.is_empty():
		push_warning("Battle signature effect pack unavailable: %s" % effect_signature_library.signature_load_error)
	for entity_id in signature_ids:
		if effect_signature_library.supports_source(entity_id):
			await _yield_asset_warmup("EFFECT_SIGNATURE:%s" % entity_id)


func _commit_signature_residency_or_fallback(target_ids: Array[String]) -> bool:
	## An actor page and its projectile/ultimate page are one visual contract.
	## Do not expose a sharp character with a missing/mismatched VFX family (or
	## the inverse) merely because one loader finished.  Compact 128px sprites
	## remain continuously available beneath this lease, so clearing both on an
	## error is a safe, non-blank fallback rather than a broken partial promotion.
	if target_ids.is_empty():
		_release_signature_residency()
		return false
	var actor_snapshot: Dictionary = sprite_library.signature_residency_snapshot()
	var effect_snapshot: Dictionary = effect_signature_library.signature_residency_snapshot()
	var actor_ready := signature_sprite_pack_ready and Array(actor_snapshot.get("entity_ids", [])) == target_ids
	var effect_ready := effect_signature_pack_ready and Array(effect_snapshot.get("entity_ids", [])) == target_ids
	if actor_ready and effect_ready:
		signature_residency_target_ids = target_ids.duplicate()
		signature_fallback_target_ids.clear()
		signature_fallback_error = ""
		return true
	var actor_error := sprite_library.signature_load_error
	var effect_error := effect_signature_library.signature_load_error
	_release_signature_residency()
	signature_fallback_target_ids = target_ids.duplicate()
	signature_fallback_error = "actor=%s effect=%s" % [actor_error, effect_error]
	if not actor_error.is_empty() or not effect_error.is_empty():
		push_warning("Battle signature acquire fell back to compact assets: actor=%s effect=%s" % [actor_error, effect_error])
	return false


func _ensure_signature_ultimate_pair(entity_id: String) -> bool:
	## Actor ultimate frames and their high-density effect frames form one atomic
	## optional enhancement. The compact actor/projectile/VFX packs stay alive
	## beneath it, so failure is a complete, deterministic fallback rather than a
	## sharp actor paired with a missing effect (or the inverse).
	var normalized_id := entity_id.strip_edges()
	if normalized_id.is_empty() or normalized_id not in SIGNATURE_ENTITY_IDS:
		return false
	if not signature_sprite_pack_ready or not effect_signature_pack_ready:
		return false
	if not signature_residency_target_ids.has(normalized_id):
		return false
	if not sprite_library.ensure_signature_ultimate_loaded(normalized_id):
		return false
	if effect_signature_library.ensure_signature_ultimate_loaded(normalized_id):
		return true
	# The actor page may have loaded before the effect validation failed. Remove
	# every runtime-transient page so this cast uses the already-loaded compact
	# family as one coherent fallback. Full artifact-QA pages are not marked
	# transient and therefore remain untouched by these calls.
	sprite_library.release_signature_transient_ultimate()
	effect_signature_library.release_signature_transient_ultimate()
	return false


func _release_signature_transient_ultimate_pages() -> void:
	# This is intentionally idempotent. It covers normal cinematic recovery,
	# skip, terminal completion, tree exit and the next caster without leaving a
	# stale ultimate page or an invisible second high-resolution effect resident.
	sprite_library.release_signature_transient_ultimate()
	effect_signature_library.release_signature_transient_ultimate()

func _append_sprite_pack(entity_id: String) -> void:
	var batch := BattleSpriteLibrary.new()
	var required_ids: Array[String] = [entity_id]
	batch.load_pack(required_ids)
	for loaded_id in batch.manifests:
		sprite_library.manifests[loaded_id] = batch.manifests[loaded_id]
	for loaded_id in batch.frames:
		sprite_library.frames[loaded_id] = batch.frames[loaded_id]
	if not batch.load_error.is_empty():
		sprite_library.load_error = _join_load_error(sprite_library.load_error, batch.load_error)
	sprite_pack_ready = not sprite_library.manifests.is_empty()

func _append_projectile_pack(entity_id: String) -> void:
	var batch := ProjectileSpriteLibrary.new()
	var required_ids: Array[String] = [entity_id]
	batch.load_pack(required_ids)
	for loaded_id in batch.manifests:
		projectile_library.manifests[loaded_id] = batch.manifests[loaded_id]
	for loaded_id in batch.frames:
		projectile_library.frames[loaded_id] = batch.frames[loaded_id]
	if not batch.load_error.is_empty():
		projectile_library.load_error = _join_load_error(projectile_library.load_error, batch.load_error)
	projectile_pack_ready = not projectile_library.manifests.is_empty()

func _join_load_error(existing: String, incoming: String) -> String:
	if existing.is_empty():
		return incoming
	if incoming.is_empty():
		return existing
	return "%s;%s" % [existing, incoming]

func _current_wave_entity_ids() -> Array[String]:
	var result: Array[String] = []
	if simulation == null:
		return result
	for unit_value in simulation.state.party + simulation.state.enemies:
		var unit: Dictionary = unit_value
		var entity_id := str(unit.get("def_id", ""))
		if not entity_id.is_empty() and not result.has(entity_id):
			result.append(entity_id)
	return result

func _signature_residency_entity_ids() -> Array[String]:
	# High-density pages are leased only to the currently visible encounter
	# formation. `_active_battle_entity_ids()` deliberately includes future waves
	# to avoid compact-atlas hitching, but using it here would turn each future
	# signature candidate into a global resident allocation.
	var result: Array[String] = []
	for entity_id in _current_wave_entity_ids():
		if entity_id in SIGNATURE_ENTITY_IDS and not sprite_library.is_reviewed_roster_redraw(entity_id) and not result.has(entity_id):
			result.append(entity_id)
	return result


func _signature_residency_matches(target_ids: Array[String]) -> bool:
	if signature_residency_target_ids != target_ids:
		return false
	var actor_snapshot: Dictionary = sprite_library.signature_residency_snapshot()
	var effect_snapshot: Dictionary = effect_signature_library.signature_residency_snapshot()
	return Array(actor_snapshot.get("entity_ids", [])) == target_ids and Array(effect_snapshot.get("entity_ids", [])) == target_ids


func _signature_residency_resolved(target_ids: Array[String]) -> bool:
	return _signature_residency_matches(target_ids) or (not signature_fallback_error.is_empty() and signature_fallback_target_ids == target_ids)


func _request_signature_residency_rollover() -> void:
	## A SPAWN replaces an encounter wave. Do not preload its high-density page
	## before it exists; retain the compact 128px actor until this request has
	## atomically acquired the entire next signature family.
	if simulation == null or not assets_ready or simulation.state.ended:
		return
	var requested_ids := _signature_residency_entity_ids()
	if not signature_rollover_active and _signature_residency_resolved(requested_ids):
		return
	signature_rollover_requested = true
	if signature_rollover_active:
		return
	signature_rollover_active = true
	call_deferred("_run_signature_residency_rollover")


func _run_signature_residency_rollover() -> void:
	## This is intentionally a release-before-acquire handoff. Staging the old
	## and next actor pages together would temporarily exceed the 72MiB mobile
	## ceiling. One render frame of the already-resident compact atlas is safe;
	## a mixed or partly decoded high-density set is not.
	while simulation != null and is_inside_tree() and not simulation.state.ended:
		signature_rollover_requested = false
		var target_ids := _signature_residency_entity_ids()
		if _signature_residency_resolved(target_ids):
			break
		signature_sprite_pack_ready = false
		effect_signature_pack_ready = false
		sprite_library.clear_signature_pack()
		effect_signature_library.clear_signature_pack()
		# HUD buttons still own these independent 192px face crops across waves.
		# Keep the accounting/cache until battle teardown, not falsely zero bytes
		# while visible orbs retain the textures. Actor atlases are still released.
		signature_residency_target_ids.clear()
		asset_warmup_phase = "SIGNATURE_ROLLOVER_FALLBACK"
		await _yield_asset_warmup("SIGNATURE_ROLLOVER_RELEASE")
		if simulation == null or not is_inside_tree() or simulation.state.ended:
			break
		# Re-read after yielding: rapid simulation may have advanced through more
		# than one spawn, but only the currently visible formation gets a lease.
		target_ids = _signature_residency_entity_ids()
		if not target_ids.is_empty():
			await _warm_signature_sprite_pack(target_ids)
			if simulation == null or not is_inside_tree(): break
			await _warm_effect_signature_pack(target_ids)
			if not sprite_library.signature_load_error.is_empty():
				push_warning("Battle signature rollover actor pack unavailable: %s" % sprite_library.signature_load_error)
			if not effect_signature_library.signature_load_error.is_empty():
				push_warning("Battle signature rollover effect pack unavailable: %s" % effect_signature_library.signature_load_error)
			if _commit_signature_residency_or_fallback(target_ids):
				await _yield_asset_warmup("SIGNATURE_ROLLOVER_ACQUIRE")
		else:
			_release_signature_residency()
		asset_warmup_phase = "READY"
		queue_redraw()
		if not signature_rollover_requested and _signature_residency_resolved(_signature_residency_entity_ids()):
			break
	signature_rollover_active = false
	if simulation != null and is_inside_tree() and not simulation.state.ended and not _signature_residency_resolved(_signature_residency_entity_ids()):
		_request_signature_residency_rollover()

func _reinforcement_entity_ids(current_entity_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for entity_id in _active_battle_entity_ids():
		if not current_entity_ids.has(entity_id):
			result.append(entity_id)
	return result

func _active_battle_entity_ids() -> Array[String]:
	var result: Array[String] = []
	if simulation == null:
		return result
	for unit_value in simulation.state.party + simulation.state.enemies:
		var unit: Dictionary = unit_value
		var entity_id := str(unit.get("def_id", ""))
		if not entity_id.is_empty() and not result.has(entity_id):
			result.append(entity_id)
	# state.enemies contains only the currently active wave.  Loading from that
	# list alone made wave 2+ enemies fall through to the grey code silhouette
	# even though their authored atlases were present in the Web package.  A stage
	# battle owns every enemy declared by all of its waves, so register those few
	# IDs before the first simulation frame.  This also removes the mid-battle
	# decode hitch that used to occur when reinforcements arrived.
	for wave_value in simulation.stage.get("waves", []):
		if not wave_value is Array:
			continue
		var wave: Array = wave_value
		for entity_id_value in wave:
			var entity_id := str(entity_id_value)
			if not entity_id.is_empty() and not result.has(entity_id):
				result.append(entity_id)
	return result

func setup(value: BattleSimulation) -> void:
	simulation = value
	contact_events.clear()
	engagement_positions.clear()
	engagement_targets.clear()
	opening_elapsed = 0.0
	contact_commits = 0
	combat_readout = ""
	finale_elapsed = -1.0
	start_band_armed = false
	swarm_members.clear()
	swarm_drops.clear()
	next_wave_cache = {"index": -2, "layout": []}
	next_wave_age = 0.0
	combo_count = 0
	combo_peak = 0
	combo_left = 0.0
	combo_pop = 0.0
	telegraph_keys.clear()
	telegraph_flashes.clear()
	active_cutin.clear()
	boss_arena_active = false
	boss_entry_wave = -1
	boss_entry_elapsed = -1.0
	boss_victory_elapsed = -1.0
	wave_entry_wave = simulation.state.wave
	wave_entry_elapsed = -1.0
	wave_entry_enemy_uid = ""
	wave_entry_ally_uid = ""
	_reset_field_direction()
	boss_entry_uids.clear()
	accumulator = 0.0
	emitted_finish = false
	skip_in_progress = false
	consumed_events = 0
	presentation_read_cursor = 0
	presented_cursor = 0
	active_presentation_batch.clear()
	presentation_director.reset()
	presentation_display_units.clear()
	_clear_active_presentation_effects()
	enemy_defeat_bursts.clear()
	defeat_hold_left = 0.0
	animation_tracks.clear()
	entry_tracks.clear()
	for unit in simulation.state.party + simulation.state.enemies:
		animation_tracks[unit.uid] = {"name": "move", "elapsed": 0.0}
		entry_tracks[unit.uid] = 0.0
	_snapshot_display_units_from_simulation()
	queue_redraw()

func skip_to_result() -> bool:
	contact_events.clear()
	## Skip only presentation time.  The live simulation advances to its real
	## terminal result, then emits the ordinary finish signal exactly once so the
	## existing reward/map/save transaction remains the sole authority.
	if simulation == null or emitted_finish or skip_in_progress:
		return false
	skip_in_progress = true
	if not simulation.advance_to_terminal():
		skip_in_progress = false
		return false
	boss_entry_elapsed = -1.0
	wave_entry_elapsed = -1.0
	boss_victory_elapsed = -1.0
	_reset_field_direction()
	field_aftermath_state = "done"
	for enemy in simulation.state.enemies:
		if str(enemy.get("rank", "")) == "BOSS": boss_arena_active = true
	# A skip commits any held ULTIMATE presentation before replacing the visual
	# snapshot with the authoritative terminal state. It never rewrites the raw
	# event log, so replay hashes and results stay identical to ordinary play.
	_force_finish_active_presentation()
	_snapshot_display_units_from_simulation()
	_clear_active_presentation_effects()
	enemy_defeat_bursts.clear()
	defeat_hold_left = 0.0
	_settle_terminal_actor_tracks()
	_release_signature_residency()
	# Thousands of fast-forwarded events must not be replayed as a one-frame VFX
	# storm if the result screen transition is delayed by a frame.
	consumed_events = simulation.event_log.size()
	presentation_read_cursor = consumed_events
	presented_cursor = consumed_events
	emitted_finish = true
	battle_finished.emit(simulation.result_snapshot())
	return true

func _process(delta: float) -> void:
	if simulation == null: return
	# A layout rebuild of the shell adds the tactical input layer again, on top of the boss aftermath
	# scene: a full-rect STOP control that swallows every tap the scene waits for. Keep the scene on top.
	if field_aftermath_state == "playing" and field_overlay != null and is_instance_valid(field_overlay) and field_overlay.get_index() != get_child_count() - 1:
		move_child(field_overlay, get_child_count() - 1)
	for flash_uid in hit_flash_frames.keys():
		hit_flash_frames[flash_uid] = int(hit_flash_frames[flash_uid]) - 1
		if int(hit_flash_frames[flash_uid]) <= 0: hit_flash_frames.erase(flash_uid)
	if deployment_active: start_band_armed = true
	if assets_ready: _detect_wave_entrance()
	if _wave_scene_elapsed() >= 0.0:
		if not paused:
			if boss_entry_elapsed >= 0.0:
				boss_entry_elapsed += delta
			else:
				wave_entry_elapsed += delta
			_advance_defeat_presentations(delta)
			_advance_animations(delta)
			var elapsed := _wave_scene_elapsed()
			for unit in simulation.state.enemies:
				var uid := str(unit.uid)
				animation_tracks[uid].name = "move" if elapsed < 1.90 and not boss_entry_uids.has(uid) else "idle"
			if elapsed >= WaveTransition.duration(boss_entry_elapsed >= 0.0):
				boss_entry_elapsed = -1.0
				wave_entry_elapsed = -1.0
		accumulator = 0.0
		queue_redraw()
		return
	if boss_victory_elapsed >= 0.0:
		if not paused: boss_victory_elapsed += delta
		queue_redraw()
		if boss_victory_elapsed >= BOSS_VICTORY_DURATION and not emitted_finish:
			_finalize_terminal_presentation()
			emitted_finish = true
			battle_finished.emit(simulation.result_snapshot())
		return
	if not paused and not deployment_active and not tactical_hold and not simulation.state.ended and opening_elapsed >= .85 and not presentation_director.is_active() and not _waiting_for_wave_contact() and not start_band_holding():
		accumulator += delta * speed
		var safety := 0
		while accumulator >= BattleSimulation.TICK_DELTA and safety < 30:
			simulation.tick()
			_consume_events()
			accumulator -= BattleSimulation.TICK_DELTA
			safety += 1
			# Stop on every spawn tick, including 3x/slow-frame catch-up. Incoming
			# enemies cannot attack before the camera releases their entrance.
			if assets_ready and _detect_wave_entrance():
				accumulator = 0.0
				queue_redraw()
				return
			if presentation_director.is_active() or _waiting_for_wave_contact():
				accumulator = 0.0
				break
	var presentation_delta := 0.0
	var actor_delta := 0.0
	if not paused:
		# Simulation remains exact at the selected 1x/2x/3x speed.  Presentation
		# deliberately has a readable upper speed so NORMAL/ULT events never become
		# a one-frame flash at 3x.
		presentation_delta = delta * minf(float(speed), MAX_PRESENTATION_SPEED)
		_advance_defeat_presentations(presentation_delta)
		var timeline: Dictionary = presentation_director.advance(presentation_delta)
		_handle_presentation_timeline(timeline)
		actor_delta = float(timeline.get("actor_delta", presentation_delta))
		_advance_animations(actor_delta)
		_advance_entries(actor_delta)
		opening_elapsed += actor_delta
		_advance_engagement(actor_delta)
		_advance_contacts(actor_delta)
		combat_readout_left = maxf(0.0, combat_readout_left - presentation_delta)
		# The opening banner waits for the deployment to end ("작전 개시").
		if not deployment_active: wave_banner_left = maxf(0.0, wave_banner_left - presentation_delta)
		_advance_combo(presentation_delta)
		if finale_elapsed >= 0.0: finale_elapsed += delta
		_consume_events()
	for text in floating_texts:
		text.age = float(text.age) + presentation_delta
	if not paused:
		for projectile in projectiles:
			# actor_delta already contains the bounded presentation speed. Applying
			# speed twice made shots outrun the weapon pose and impact VFX at 2x/3x.
			projectile.age = float(projectile.age) + actor_delta
		for presentation in vfx_presentations:
			presentation.age = float(presentation.age) + actor_delta
		for callout in skill_callouts:
			callout.age = float(callout.age) + presentation_delta
		for presentation in boss_phase_presentations:
			presentation.age = float(presentation.age) + presentation_delta
		for flash in telegraph_flashes:
			flash.age = float(flash.age) + presentation_delta
		for drop in swarm_drops:
			drop.age = float(drop.age) + presentation_delta
		next_wave_age += presentation_delta
	_recycle_expired_presentations()
	_track_telegraph_landings()
	_track_swarm_members()
	for uid in unit_flash.keys():
		unit_flash[uid] = float(unit_flash[uid]) - actor_delta
		if float(unit_flash[uid]) <= 0:
			unit_flash.erase(uid)
			unit_flash_span.erase(uid)
	queue_redraw()
	if simulation.state.ended and contact_events.is_empty() and not emitted_finish and not presentation_director.is_active() and consumed_events >= simulation.event_log.size() and enemy_defeat_bursts.is_empty() and defeat_hold_left <= 0.0:
		if boss_arena_active and simulation.state.victory:
			if _field_aftermath_holds():
				return
			boss_victory_elapsed = 0.0
			return
		# An ordinary victory holds a short end card before the result hand-off.
		if simulation.state.victory and finale_elapsed < 0.0:
			finale_elapsed = 0.0
		if finale_elapsed >= 0.0 and finale_elapsed < FINALE_DURATION:
			return
		_finalize_terminal_presentation()
		emitted_finish = true
		battle_finished.emit(simulation.result_snapshot())

func start_band_holding() -> bool:
	return start_band_armed and wave_banner_title == START_BAND_TITLE and wave_banner_left > WAVE_BANNER_DURATION - START_BAND_HOLD

func scene_transition_active() -> bool:
	return _wave_scene_elapsed() >= 0.0 or boss_victory_elapsed >= 0.0 or finale_elapsed >= 0.0 or field_aftermath_state == "playing"

func _wave_scene_elapsed() -> float:
	return boss_entry_elapsed if boss_entry_elapsed >= 0.0 else wave_entry_elapsed

func _detect_wave_entrance() -> bool:
	if simulation == null or simulation.state.ended or _wave_scene_elapsed() >= 0.0: return false
	if not contact_events.is_empty() or presentation_director.is_active() or consumed_events < simulation.event_log.size(): return false
	if simulation.has_boss(): return _detect_boss_entrance()
	if simulation.state.wave <= wave_entry_wave or not contact_events.is_empty() or presentation_director.is_active(): return false
	# Finish every preceding contact/cut-in before changing the camera. The
	# simulation stops on the spawn tick while this presentation queue drains.
	if consumed_events < simulation.event_log.size(): return false
	wave_entry_wave = simulation.state.wave
	wave_entry_elapsed = 0.0
	_prepare_wave_entrance()
	return true

func _prepare_wave_entrance() -> void:
	wave_banner_left = 0.0
	combat_readout = ""
	combat_readout_left = 0.0
	_clear_active_presentation_effects()
	_snapshot_display_units_from_simulation()
	wave_entry_enemy_uid = ""
	wave_entry_ally_uid = ""
	for unit in simulation.state.enemies:
		if not UnitState.alive(unit): continue
		if wave_entry_enemy_uid.is_empty() or str(unit.rank) == "BOSS": wave_entry_enemy_uid = str(unit.uid)
	for unit in simulation.state.party:
		if UnitState.alive(unit):
			wave_entry_ally_uid = str(unit.uid)
			break
	for unit in simulation.state.party + simulation.state.enemies:
		animation_tracks[unit.uid] = {"name": "idle" if UnitState.alive(unit) else "down", "elapsed": 0.0}
		entry_tracks[unit.uid] = 1.0
	_request_signature_residency_rollover()

func _detect_boss_entrance() -> bool:
	if not contact_events.is_empty(): return false
	if simulation == null or simulation.state.ended or boss_entry_wave == simulation.state.wave: return false
	var bosses: Array = simulation.state.enemies.filter(func(unit): return str(unit.get("rank", "")) == "BOSS" and UnitState.alive(unit))
	if bosses.is_empty(): return false
	boss_entry_wave = simulation.state.wave
	boss_entry_from_arena = boss_arena_active
	boss_arena_active = true
	boss_entry_elapsed = 0.0
	boss_entry_name = unit_display_name(bosses[0])
	wave_entry_wave = simulation.state.wave
	combat_readout = ""
	combat_readout_left = 0.0
	boss_entry_uids.clear()
	for unit in bosses: boss_entry_uids.append(str(unit.uid))
	# Commit the prior wave's outstanding impacts before opening the chamber.
	# The simulation/event log and resource transaction are unchanged.
	_force_finish_active_presentation()
	# The final kill and next-wave spawn can share one simulation tick. Preserve
	# its destruction before seeking past that wave's remaining presentation.
	for event_index in range(consumed_events, simulation.event_log.size()):
		var event: Dictionary = simulation.event_log[event_index]
		if str(event.get("type", "")) == BattleEvent.DOWN:
			_start_defeat_presentation(str(event.get("target", "")))
	_prepare_wave_entrance()
	consumed_events = simulation.event_log.size()
	presentation_read_cursor = consumed_events
	presented_cursor = consumed_events
	return true

func wave_scene_snapshot() -> Dictionary:
	var elapsed := _wave_scene_elapsed()
	var boss := boss_entry_elapsed >= 0.0
	var beat := WaveTransition.sample(elapsed, boss) if elapsed >= 0.0 else {}
	return {"wave": wave_entry_wave, "active": elapsed >= 0.0, "elapsed": elapsed,
		"phase": str(beat.get("phase", "idle")), "boss": boss, "duration": WaveTransition.duration(boss),
		"enemy_uid": wave_entry_enemy_uid, "ally_uid": wave_entry_ally_uid,
		"camera_zoom": _compute_battlefield_camera_zoom(), "mask": float(beat.get("mask", 0.0)),
		"enemy_caption": float(beat.get("enemy_caption", 0.0)), "ally_caption": float(beat.get("ally_caption", 0.0)),
		"banner": float(beat.get("banner", 0.0)), "combat_held": scene_transition_active()}

func boss_scene_snapshot() -> Dictionary:
	return {"arena": boss_arena_active, "entry_wave": boss_entry_wave, "entry_elapsed": boss_entry_elapsed,
		"entry_duration": BOSS_ENTRY_DURATION, "victory_elapsed": boss_victory_elapsed,
		"name": boss_entry_name, "combat_held": scene_transition_active(), "background_mix": _boss_background_mix()}

func _boss_background_mix() -> float:
	if not boss_arena_active: return 0.0
	if boss_entry_elapsed < 0.0 or boss_entry_from_arena: return 1.0
	# Crossfade the environment entirely inside the opaque aperture, then reveal
	# the boss's descent. The arena stays owned after the boss falls.
	return smoothstep(.85, 1.0, boss_entry_elapsed)

func _draw_boss_scene() -> void:
	if _wave_scene_elapsed() >= 0.0:
		_draw_wave_scene()
		return
	if boss_victory_elapsed < 0.0: return
	var band := size.y * .105
	draw_rect(Rect2(0, 0, size.x, band), Color(.008, .018, .03, .94))
	draw_rect(Rect2(0, size.y - band, size.x, band), Color(.008, .018, .03, .94))
	_draw_finale_card(boss_victory_elapsed, BOSS_VICTORY_DURATION, "위협 제거", "작전 완료", "적의 신호가 소멸했습니다" if size.x >= size.y else "다음 노선 확보")

func _draw_wave_scene() -> void:
	var t := _wave_scene_elapsed()
	var boss := boss_entry_elapsed >= 0.0
	var beat := WaveTransition.sample(t, boss)
	var visibility := float(beat.visibility)
	# The shell has a 24px safe margin around BattleView. Extend the cinematic
	# matte through that margin; otherwise strips of the lobby leak around it.
	var canvas := get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	var ink := Color(.006, .010, .02, visibility)
	var bar_height := canvas.size.y * .11 * visibility
	draw_rect(Rect2(canvas.position, Vector2(canvas.size.x, bar_height)), ink)
	draw_rect(Rect2(Vector2(canvas.position.x, canvas.end.y - bar_height), Vector2(canvas.size.x, bar_height)), ink)
	if canvas.position.x < 0:
		draw_rect(Rect2(canvas.position, Vector2(-canvas.position.x, canvas.size.y)), ink)
	if canvas.end.x > size.x:
		draw_rect(Rect2(Vector2(size.x, canvas.position.y), Vector2(canvas.end.x - size.x, canvas.size.y)), ink)
	if boss and t >= 1.95 and t < 2.65:
		var landing := (t - 1.95) / .70
		var enemy := _actor_model(wave_entry_enemy_uid)
		var center := _unit_pos(enemy)
		_draw_ellipse_polygon(center, Vector2(size.x * (.025 + .13 * landing), size.y * .025), Color(.46, .87, 1, (1.0 - landing) * .48))
	var enemy_line := "새로운 적 무리가 전방을 봉쇄합니다."
	if boss: enemy_line = "거대 신호가 내려옵니다. 노선 전체가 흔들립니다."
	_draw_wave_dialogue(wave_entry_enemy_uid, "거대 신호 접근" if boss else "적 증원 확인", enemy_line, float(beat.enemy_caption), true)
	_draw_wave_dialogue(wave_entry_ally_uid, unit_display_name(_actor_model(wave_entry_ally_uid)),
		"전열 유지. 저 반응을 끊고 길을 열자!" if boss else "아직 끝나지 않았어. 다음 무리도 함께 돌파하자!", float(beat.ally_caption), false)
	var alpha := float(beat.banner)
	if alpha > 0.0:
		var font := battle_font if battle_font != null else ThemeDB.fallback_font
		var accent := Color("ff806f") if boss else Color("72e4d0")
		var strip := Rect2(0, size.y * .73, size.x, size.y * .14)
		Ornament.quad(self, strip.position, Vector2(size.x, strip.position.y), strip.end, Vector2(0, strip.end.y),
			Color(.20 if boss else .025, .035, .045, .96 * alpha), Color(.08, .025, .04, .92 * alpha),
			Color(.08, .025, .04, .92 * alpha), Color(.20 if boss else .025, .035, .045, .96 * alpha))
		draw_rect(Rect2(strip.position, Vector2(size.x, 2)), Ornament.tint(accent, alpha))
		draw_rect(Rect2(Vector2(0, strip.end.y - 2), Vector2(size.x, 2)), Ornament.tint(accent, alpha))
		var title := boss_entry_name if boss else "WAVE %d / %d · 적 증원" % [simulation.state.wave, simulation.state.wave_count]
		var css := _damage_screen_scale()
		var title_size := _fit_font_size(font, title, roundi(clampf(36.0 / css, 36, 76)), size.x * .88)
		Ornament.centered_text(self, font, Vector2(size.x * .5, strip.position.y + strip.size.y * .65), title, title_size, Color(1, .94, .84, alpha), 3, Color(.02, .01, .02, alpha))
		Ornament.centered_text(self, font, Vector2(size.x * .5, strip.position.y + strip.size.y * .25),
			"BOSS ENCOUNTER" if boss else "NEXT ENCOUNTER", roundi(clampf(15.0 / css, 15, 32)), Ornament.tint(accent, alpha))
	# Draw last: the environment and incoming bodies are never revealed across
	# an uncovered cut. Music continues on its existing stream throughout.
	if float(beat.mask) > 0.0:
		draw_rect(canvas, Color(.006, .010, .02, float(beat.mask)))

func _draw_wave_dialogue(uid: String, speaker: String, line: String, alpha: float, enemy: bool) -> void:
	if alpha <= 0.0 or uid.is_empty(): return
	var unit := _actor_model(uid)
	if unit.is_empty(): return
	var font := battle_font if battle_font != null else ThemeDB.fallback_font
	var css := _damage_screen_scale()
	var font_size := _fit_font_size(font, line, roundi(clampf(24.0 / css, 24, 54)), size.x * .80 - 48)
	var name_size := maxi(18, roundi(font_size * .68))
	var width := minf(size.x * .84, float(Ornament.text_metrics(font, line, font_size).width) + 52.0)
	var height := font_size * 1.65 + name_size + 20.0
	var head := _head_position(unit, _ground_position(unit))
	var left := clampf(head.x - width * .5, size.x * .06, size.x * .94 - width)
	var top := clampf(head.y - height - 26.0, size.y * .12, size.y * .54)
	var rect := Rect2(left, top, width, height)
	var accent := Color("ff927e") if enemy else Color("72e4d0")
	draw_rect(rect, Color(.09 if enemy else .018, .035, .05, .94 * alpha))
	_outline_rect(rect, Ornament.tint(accent, .8 * alpha), 1.5)
	CachedDraw.fill(self, PackedVector2Array([Vector2(clampf(head.x, left + 18, rect.end.x - 18) - 9, rect.end.y),
		Vector2(clampf(head.x, left + 18, rect.end.x - 18) + 9, rect.end.y), Vector2(clampf(head.x, left + 18, rect.end.x - 18), rect.end.y + 12)]), Ornament.tint(accent, .8 * alpha))
	draw_string(font, rect.position + Vector2(24, name_size + 10), speaker, HORIZONTAL_ALIGNMENT_LEFT, width - 48, name_size, Ornament.tint(accent, alpha))
	draw_string(font, rect.position + Vector2(24, height - font_size * .35), line, HORIZONTAL_ALIGNMENT_LEFT, width - 48, font_size, Color(.98, .98, .94, alpha))

func _consume_events() -> void:
	if simulation == null or presentation_director.is_active():
		return
	# Tests and debug tools historically set consumed_events directly. Treat such
	# writes as a deliberate raw-log seek while keeping the committed display
	# cursor in step outside of an active cinematic batch.
	if presentation_read_cursor != consumed_events:
		presentation_read_cursor = consumed_events
		presented_cursor = maxi(presented_cursor, consumed_events)
	var processed_this_frame := 0
	while consumed_events < simulation.event_log.size() and processed_this_frame < MAX_EVENTS_PER_FRAME:
		var event: Dictionary = simulation.event_log[consumed_events]
		if event.type == BattleEvent.NORMAL_SKILL and str(event.get("target", "")).is_empty():
			event = event.duplicate(true)
			for next_index in range(consumed_events + 1, mini(consumed_events + 12, simulation.event_log.size())):
				var next_event: Dictionary = simulation.event_log[next_index]
				if int(next_event.tick) != int(event.tick): break
				if str(next_event.get("source", "")) == str(event.source) and str(next_event.get("type", "")) in [BattleEvent.DAMAGE, BattleEvent.HEAL, BattleEvent.SHIELD]:
					event.target = next_event.target
					break
		if event.type in [BattleEvent.ULTIMATE, BattleEvent.BATTLE_END] and not contact_events.is_empty(): break
		if event.type == BattleEvent.ULTIMATE and _supports_cinematic_ultimate(event):
			var batch := _collect_ultimate_presentation_batch(consumed_events)
			var batch_end := int(batch.get("end_index", consumed_events + 1))
			consumed_events = batch_end
			presentation_read_cursor = batch_end
			var batch_events: Array = batch.get("events", [])
			processed_this_frame += maxi(1, batch_events.size())
			if _begin_ultimate_presentation(batch):
				# Later actions remain in the immutable simulation log, but they do
				# not visually overtake this action until recovery completes.
				break
			_apply_ultimate_batch(batch)
			presented_cursor = batch_end
			continue
		consumed_events += 1
		presentation_read_cursor = consumed_events
		presented_cursor = consumed_events
		processed_this_frame += 1
		if event.type in [BattleEvent.DAMAGE, BattleEvent.HEAL, BattleEvent.SHIELD, BattleEvent.DOWN]:
			contact_events.append({"event": event.duplicate(true), "remaining": CONTACT_DELAY})
			if event.type == BattleEvent.DAMAGE and str(event.get("extra", {}).get("source", "")) == "NORMAL":
				_spawn_projectile(str(event.source), str(event.target), "NORMAL")
		else:
			_present_regular_event(event)

func _present_regular_event(event: Dictionary) -> void:
	_apply_display_event(event)
	if event.type == BattleEvent.DAMAGE:
		_spawn_damage_text(event)
		_register_combo_hit(event)
		_register_hit_reaction(event)
		if damage_event_has_hit_sfx(event):
			_request_damage_camera_impulse(event)
		if damage_event_has_hit_sfx(event):
			var hit_unit := _actor_model(str(event.target))
			if not hit_unit.is_empty():
				if str(hit_unit.team) == "PLAYER": AudioService.play_event("PLAYER_HIT", .06)
				elif str(hit_unit.get("rank", "NORMAL")) == "BOSS": AudioService.play_event("BOSS_HIT", .06)
				else: AudioService.play_event("ENEMY_HIT", .06)
		if int(event.value) > 0:
			var damage_kind := str(event.get("extra", {}).get("source", "BASIC")).to_lower()
			_spawn_vfx(str(event.source), str(event.target), "impact_%s" % damage_kind, 0.0, HitFeedback.impact_accent(HitFeedback.damage_style(event)))
			var damaged := presentation_unit_for_uid(str(event.target))
			if not damaged.is_empty() and UnitState.alive(damaged): _play_animation(str(event.target), "hit")
	elif event.type == BattleEvent.HEAL:
		_spawn_floating_text({"target": event.target, "text": "+%d" % event.value, "color": Color("76e6a5"), "style": "heal", "age": 0.0})
		_spawn_vfx(str(event.source), str(event.target), "heal")
	elif event.type == BattleEvent.SHIELD:
		_spawn_floating_text({"target": event.target, "text": "SHIELD %d" % event.value, "color": Color("72d5ff"), "style": "shield", "age": 0.0})
		_spawn_vfx(str(event.source), str(event.target), "shield")
	elif event.type == BattleEvent.BASIC_ATTACK:
		var basic_source := _actor_model(str(event.source))
		if not _action_source_is_presentable(str(event.source)):
			return
		if str(basic_source.team) == "PLAYER": AudioService.play_event("PLAYER_BASIC_ATTACK", .05)
		elif str(basic_source.get("rank", "NORMAL")) == "BOSS": AudioService.play_event("BOSS_BASIC_ATTACK", .05)
		else: AudioService.play_event("ENEMY_BASIC_ATTACK", .05)
		_spawn_projectile(str(event.source), str(event.target), "BASIC")
		_spawn_vfx(str(event.source), str(event.target), "basic")
		_play_animation(str(event.source), "basic_attack", str(event.target))
		_request_action_camera_focus(str(event.source), str(event.target), .24, .30)
	elif event.type == BattleEvent.NORMAL_SKILL:
		var skill_source := _actor_model(str(event.source))
		if not _action_source_is_presentable(str(event.source)):
			return
		var skill_fallback_event := "PLAYER_NORMAL_SKILL" if str(skill_source.team) == "PLAYER" else ("BOSS_SKILL" if str(skill_source.get("rank", "NORMAL")) == "BOSS" else "ENEMY_SKILL")
		AudioService.play_card_start(card_start_id_for_event(event, skill_source), skill_fallback_event, .10)
		_spawn_skill_callout(str(event.source), _action_label(event), Color("79e8ff"), "normal")
		_spawn_vfx(str(event.source), str(event.target), "normal")
		_play_animation(str(event.source), "normal_skill", str(event.target))
		_request_action_camera_focus(str(event.source), str(event.target), .42, .48)
	elif event.type == BattleEvent.ULTIMATE:
		var ultimate_source := _actor_model(str(event.source))
		if not _action_source_is_presentable(str(event.source)):
			return
		var ultimate_fallback_event := "PLAYER_ULTIMATE" if str(ultimate_source.team) == "PLAYER" else ("BOSS_SKILL" if str(ultimate_source.get("rank", "NORMAL")) == "BOSS" else "ENEMY_SKILL")
		AudioService.play_card_start(card_start_id_for_event(event, ultimate_source), ultimate_fallback_event, .12)
		_spawn_skill_callout(str(event.source), _action_label(event), Color("ffd36f"), "ultimate")
		_spawn_vfx(str(event.source), str(event.target), "ultimate")
		_play_animation(str(event.source), "ultimate", str(event.target))
	elif event.type == BattleEvent.DOWN:
		_play_animation(str(event.target), "down")
		combat_readout = "%s → %s %s" % [unit_display_name(_actor_model(str(event.source))), unit_display_name(_actor_model(str(event.target))), "전투불능" if str(_actor_model(str(event.target)).get("team", "")) == "PLAYER" else "격파"]
		combat_readout_left = 2.2
		presentation_director.request_combat_impact(.60)
	elif event.type == BattleEvent.SPAWN:
		animation_tracks[event.source] = {"name": "move", "elapsed": 0.0}
		entry_tracks[event.source] = 0.0
		_request_signature_residency_rollover()
	elif event.type == BattleEvent.STATUS:
		var phase_id := str(event.extra.get("phase", ""))
		if BOSS_PHASE_PRESENTATION.has(phase_id):
			_spawn_boss_phase_presentation(str(event.source), phase_id)
	elif event.type == BattleEvent.WAVE:
		# The boss wave owns its own descent cinematic; other waves get a banner.
		if not simulation.has_boss():
			var wave_number := int(event.value)
			wave_banner_title = START_BAND_TITLE if wave_number <= 1 else "WAVE %d" % wave_number
			wave_banner_subtitle = "WAVE %d / %d" % [wave_number, simulation.state.wave_count] if wave_number <= 1 else "남은 웨이브 %d" % maxi(0, simulation.state.wave_count - wave_number)
			wave_banner_left = WAVE_BANNER_DURATION
		next_wave_age = 0.0
	elif event.type == BattleEvent.BATTLE_END and int(event.value) == 1:
		for unit in simulation.state.party:
			if UnitState.alive(unit): _play_animation(str(unit.uid), "victory")

func _supports_cinematic_ultimate(event: Dictionary) -> bool:
	if simulation == null:
		return false
	var source := _actor_model(str(event.get("source", "")))
	if source.is_empty():
		return false
	# This bounded path includes only signature entities with an authored motion
	# recipe. Other units retain the quick readable presentation until their own
	# high-density source and camera recipe are reviewed.
	return str(source.get("def_id", "")) in SIGNATURE_ENTITY_IDS and _action_source_is_presentable(str(event.get("source", "")))

func _collect_ultimate_presentation_batch(start_index: int) -> Dictionary:
	var cue: Dictionary = simulation.event_log[start_index]
	var cue_extra: Dictionary = cue.get("extra", {})
	var ability_id := str(cue_extra.get("skill_id", cue_extra.get("boss_pattern", "")))
	var batch_events: Array = [cue.duplicate(true)]
	var affected_targets: Dictionary = {}
	var index := start_index + 1
	while index < simulation.event_log.size():
		var candidate: Dictionary = simulation.event_log[index]
		if not _is_related_ultimate_effect(cue, candidate, affected_targets):
			break
		batch_events.append(candidate.duplicate(true))
		if str(candidate.get("type", "")) != BattleEvent.DOWN:
			affected_targets[str(candidate.get("target", ""))] = true
		index += 1
	# The model has no presentation action ID, so this receive-side identity is
	# intentionally derived from immutable sequence, tick, source, and ability.
	return {
		"id": "ULT:%d:%s:%s:%d" % [int(cue.get("tick", 0)), str(cue.get("source", "")), ability_id, start_index],
		"cue": cue.duplicate(true),
		"events": batch_events,
		"start_index": start_index,
		"end_index": index,
		"source": str(cue.get("source", "")),
		"ability_id": ability_id,
	}

func _is_related_ultimate_effect(cue: Dictionary, candidate: Dictionary, affected_targets: Dictionary) -> bool:
	if int(candidate.get("tick", -1)) != int(cue.get("tick", -2)):
		return false
	if str(candidate.get("source", "")) != str(cue.get("source", "")):
		return false
	var candidate_type := str(candidate.get("type", ""))
	var extra: Dictionary = candidate.get("extra", {})
	if candidate_type == BattleEvent.DAMAGE:
		return str(extra.get("source", "")) == "ULTIMATE"
	if candidate_type in [BattleEvent.HEAL, BattleEvent.SHIELD]:
		return true
	if candidate_type == BattleEvent.DOWN:
		return str(extra.get("cause", "")) == "ULTIMATE" and affected_targets.has(str(candidate.get("target", "")))
	return false

func _begin_ultimate_presentation(batch: Dictionary) -> bool:
	var cutin_plan := cutin_plan_for(_actor_model(str(batch.get("source", ""))))
	if bool(cutin_plan.get("long", false)):
		batch["lead_in"] = LONG_CUTIN_LEAD_IN
	if not presentation_director.begin_ultimate(batch):
		return false
	active_presentation_batch = batch.duplicate(true)
	var cue: Dictionary = active_presentation_batch.get("cue", {})
	if str(cue.get("target", "")).is_empty():
		for effect in active_presentation_batch.get("events", []):
			if str(effect.get("type", "")) in [BattleEvent.DAMAGE,BattleEvent.HEAL,BattleEvent.SHIELD] and not str(effect.get("target", "")).is_empty():
				cue.target = effect.target
				break
	var source := _actor_model(str(cue.get("source", "")))
	if source.is_empty():
		presentation_director.reset()
		active_presentation_batch.clear()
		return false
	# Loading occurs before the cast track or VFX is scheduled, so a successful
	# transient lease can cover both the actor motion and its matching effect
	# from the very first rendered cinematic frame. A false return deliberately
	# keeps the compact visual path; it never cancels the real battle action.
	_ensure_signature_ultimate_pair(str(source.get("def_id", "")))
	_request_action_camera_focus(str(cue.get("source", "")), str(cue.get("target", "")), .82, 1.18)
	var fallback_event := "PLAYER_ULTIMATE" if str(source.get("team", "")) == "PLAYER" else ("BOSS_SKILL" if str(source.get("rank", "NORMAL")) == "BOSS" else "ENEMY_SKILL")
	AudioService.play_card_start(card_start_id_for_event(cue, source), fallback_event, .12)
	active_cutin = cutin_plan.duplicate()
	active_cutin["source"] = str(cue.get("source", ""))
	active_cutin["skill_name"] = _action_label(cue)
	if bool(cutin_plan.get("first_use", false)):
		_mark_cutin_seen(str(cutin_plan.get("def_id", "")))
	# The character cut-in already names the skill; others get a nameplate/shout.
	if not bool(cutin_plan.get("show", false)):
		_spawn_skill_callout(str(cue.get("source", "")), str(active_cutin.skill_name), Color("ffd36f"), "ultimate")
	_play_animation(str(cue.get("source", "")), "ultimate", str(cue.get("target", "")))
	return true

func _handle_presentation_timeline(timeline: Dictionary) -> void:
	if bool(timeline.get("battlefield_prep", false)) and not active_presentation_batch.is_empty():
		var cue: Dictionary = active_presentation_batch.get("cue", {})
		_spawn_vfx(str(cue.get("source", "")), str(cue.get("target", "")), "ultimate")
		var launched: Dictionary = {}
		for event in active_presentation_batch.get("events", []):
			if str(event.get("type", "")) != BattleEvent.DAMAGE: continue
			var target_uid := str(event.get("target", ""))
			if launched.has(target_uid): continue
			launched[target_uid] = true
			_spawn_projectile(str(cue.get("source", "")), target_uid, "ULTIMATE", .24)
	if bool(timeline.get("impact_commit", false)):
		_commit_active_ultimate_batch()
	if bool(timeline.get("finished", false)):
		active_presentation_batch.clear()
		active_cutin.clear()
		# The final impact VFX has expired before the 2.10s recovery timeline
		# completes. Releasing here guarantees that no previous caster remains
		# resident between actions, while the core idle/hit/down + projectile lease
		# continues to render without a visual gap.
		_release_signature_transient_ultimate_pages()

func _commit_active_ultimate_batch() -> void:
	if active_presentation_batch.is_empty():
		return
	_apply_ultimate_batch(active_presentation_batch)
	presented_cursor = maxi(presented_cursor, int(active_presentation_batch.get("end_index", presented_cursor)))

func _apply_ultimate_batch(batch: Dictionary) -> void:
	var batch_events: Array = batch.get("events", [])
	# Apply every result first, in a single draw-frame transaction. A lethal hit
	# therefore cannot briefly render as HP 0 while the actor is still alive.
	for event_value in batch_events:
		var event: Dictionary = event_value
		if str(event.get("type", "")) != BattleEvent.ULTIMATE:
			_apply_display_event(event)
	for event_value in batch_events:
		var event: Dictionary = event_value
		_present_ultimate_batch_event(event)

func _present_ultimate_batch_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	if event_type == BattleEvent.DAMAGE:
		var extra: Dictionary = event.get("extra", {})
		var value := int(event.get("value", 0))
		_spawn_damage_text(event)
		_register_combo_hit(event)
		_register_hit_reaction(event)
		if damage_event_has_hit_sfx(event):
			_request_damage_camera_impulse(event)
		if damage_event_has_hit_sfx(event):
			var hit_unit := _actor_model(str(event.get("target", "")))
			if not hit_unit.is_empty():
				if str(hit_unit.get("team", "")) == "PLAYER": AudioService.play_event("PLAYER_HIT", .06)
				elif str(hit_unit.get("rank", "NORMAL")) == "BOSS": AudioService.play_event("BOSS_HIT", .06)
				else: AudioService.play_event("ENEMY_HIT", .06)
		if value > 0:
			_spawn_vfx(str(event.get("source", "")), str(event.get("target", "")), "impact_ultimate", 0.0, HitFeedback.impact_accent(HitFeedback.damage_style(event)))
	elif event_type == BattleEvent.HEAL:
		_spawn_floating_text({"target": event.get("target", ""), "text": "+%d" % int(event.get("value", 0)), "color": Color("76e6a5"), "style": "heal", "age": 0.0})
		_spawn_vfx(str(event.get("source", "")), str(event.get("target", "")), "heal")
	elif event_type == BattleEvent.SHIELD:
		_spawn_floating_text({"target": event.get("target", ""), "text": "SHIELD %d" % int(event.get("value", 0)), "color": Color("72d5ff"), "style": "shield", "age": 0.0})
		_spawn_vfx(str(event.get("source", "")), str(event.get("target", "")), "shield")
	elif event_type == BattleEvent.DOWN:
		_play_animation(str(event.get("target", "")), "down")
		presentation_director.request_combat_impact(.60)

func _register_hit_reaction(event: Dictionary) -> void:
	## Victim feedback for one damage event: pink tint and slide (length and
	## distance follow the damage share) plus a 2-frame white flash when it landed.
	var uid := str(event.get("target", ""))
	var target := _actor_model(uid) if simulation != null else {}
	var style := HitFeedback.damage_style(event)
	var span := HitFeedback.reaction_span(style, HitFeedback.damage_weight(event, target))
	unit_flash[uid] = float(span.duration)
	unit_flash_span[uid] = span
	if style != "miss" and damage_event_has_hit_sfx(event):
		hit_flash_frames[uid] = HitFeedback.WHITE_FLASH_FRAMES

func _request_damage_camera_impulse(event: Dictionary) -> void:
	var extra: Dictionary = event.get("extra", {})
	if bool(extra.get("miss", false)) or bool(extra.get("invulnerable", false)):
		return
	var target := _actor_model(str(event.get("target", ""))) if simulation != null else {}
	var source := _actor_model(str(event.get("source", ""))) if simulation != null else {}
	var style := HitFeedback.damage_style(event)
	var weight := HitFeedback.damage_weight(event, target)
	var source_kind := str(extra.get("source", ""))
	var boss_involved := (not target.is_empty() and str(target.get("rank", "")) == "BOSS") or (not source.is_empty() and str(source.get("rank", "")) == "BOSS")
	# Damage-scaled: hit-stop (capped at 55 ms by the director), shake shape and
	# camera focus all follow the share of the victim's HP the hit removed.
	var strength := HitFeedback.impact_strength(style, weight, source_kind, boss_involved)
	presentation_director.request_combat_impact(strength, HitFeedback.shake_preset(style, weight, source_kind))
	_request_action_camera_focus(str(event.get("source", "")), str(event.get("target", "")), minf(1.0, strength), .48 if str(extra.get("source", "")) == "ULTIMATE" else .32)


func _request_action_camera_focus(source_uid: String, target_uid: String, strength: float, duration: float) -> void:
	# Keep camera focus coupled to a concrete source→target combat lane.  Heals,
	# self-buffs, stale event targets, and unseen entities never introduce a
	# disorienting pan; impact shake can still communicate those events.
	if simulation == null or source_uid.is_empty() or target_uid.is_empty() or source_uid == target_uid:
		return
	var source := _actor_model(source_uid)
	var target := _actor_model(target_uid)
	if source.is_empty() or target.is_empty():
		return
	var world_direction := _unit_pos(target).x - _unit_pos(source).x
	if is_zero_approx(world_direction):
		return
	presentation_director.request_combat_focus(world_direction, strength, duration)

func _force_finish_active_presentation() -> void:
	var forced := presentation_director.force_finish()
	if bool(forced.get("needs_impact_commit", false)) and not active_presentation_batch.is_empty():
		_commit_active_ultimate_batch()
	active_presentation_batch.clear()
	active_cutin.clear()
	_release_signature_transient_ultimate_pages()
	presentation_director.reset()

func _finalize_terminal_presentation() -> void:
	# Result transition is a hard visual terminal. Nothing from the last cast is
	# allowed to leak into a result screen or a newly entered battle: the pooled
	# records stay reusable, while all active travel/cast/impact instances and
	# camera/motion offsets are reset to their canonical terminal state.
	_force_finish_active_presentation()
	_clear_active_presentation_effects()
	_settle_terminal_actor_tracks()
	_release_signature_residency()

func _settle_terminal_actor_tracks() -> void:
	if simulation == null:
		return
	var active_uids: Dictionary = {}
	for unit_value in simulation.state.party + simulation.state.enemies:
		var unit: Dictionary = unit_value
		var uid := str(unit.get("uid", ""))
		if uid.is_empty():
			continue
		active_uids[uid] = true
		var visual := presentation_unit_for_uid(uid)
		var terminal_animation := "idle" if bool(visual.get("alive", UnitState.alive(unit))) else "down"
		animation_tracks[uid] = {"name": terminal_animation, "elapsed": 0.0}
		# Entry translation is another visible world HP/SH anchor offset. At a
		# terminal boundary every actor is already planted on its reference point.
		entry_tracks[uid] = 1.0
	# Defeated or replaced wave units may no longer be in the authoritative
	# state array. Their old tracks cannot draw a valid actor, but retaining their
	# lunge/hit record would make cleanup diagnostics lie and risks a stale anchor
	# if a future renderer starts caching it. Drop those terminally absent tracks.
	for uid_value in animation_tracks.keys():
		var tracked_uid := str(uid_value)
		if not active_uids.has(tracked_uid):
			animation_tracks.erase(tracked_uid)
			entry_tracks.erase(tracked_uid)

func _snapshot_display_units_from_simulation() -> void:
	presentation_display_units.clear()
	presentation_actor_records.clear()
	if simulation == null:
		return
	for unit in simulation.state.party + simulation.state.enemies:
		_seed_display_unit(unit)

func _seed_display_unit(unit: Dictionary) -> void:
	var uid := str(unit.get("uid", ""))
	if uid.is_empty():
		return
	presentation_actor_records[uid] = unit.duplicate(true)
	presentation_display_units[uid] = {
		"hp": int(unit.get("hp", 0)),
		"max_hp": int(unit.get("max_hp", 0)),
		"shield": int(unit.get("shield", 0)),
		"shield_sources": unit.get("shields", {}).duplicate(true),
		"alive": bool(unit.get("alive", false)),
		"state": str(unit.get("state", "")),
		"phase": str(unit.get("phase", "")),
	}

func _mutable_display_snapshot(uid: String) -> Dictionary:
	var snapshot: Dictionary = presentation_display_units.get(uid, {})
	if snapshot.is_empty() and simulation != null:
		var model := _actor_model(uid)
		if not model.is_empty():
			_seed_display_unit(model)
			snapshot = presentation_display_units.get(uid, {})
	return snapshot.duplicate(true)

func _apply_display_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	if event_type == BattleEvent.SPAWN:
		if simulation != null:
			var spawned := _actor_model(str(event.get("source", "")))
			if not spawned.is_empty():
				_seed_display_unit(spawned)
		return
	var target_uid := str(event.get("target", ""))
	if target_uid.is_empty():
		return
	var snapshot := _mutable_display_snapshot(target_uid)
	if snapshot.is_empty():
		return
	if event_type == BattleEvent.DAMAGE:
		var extra: Dictionary = event.get("extra", {})
		if not bool(extra.get("miss", false)) and not bool(extra.get("invulnerable", false)):
			var shield_damage := maxi(0, int(extra.get("shield_damage", 0)))
			var hp_damage := maxi(0, int(extra.get("hp_damage", event.get("value", 0))))
			_consume_display_shield(snapshot, shield_damage)
			snapshot.hp = maxi(0, int(snapshot.get("hp", 0)) - hp_damage)
	elif event_type == BattleEvent.HEAL:
		snapshot.hp = mini(int(snapshot.get("max_hp", 0)), int(snapshot.get("hp", 0)) + maxi(0, int(event.get("value", 0))))
	elif event_type == BattleEvent.SHIELD:
		# The simulation replaces each caster's shield on recast; adding here made
		# the Guardian's repeated shield inflate the bar every 8 seconds.
		var sources: Dictionary = snapshot.get("shield_sources", {})
		sources[str(event.get("source", ""))] = maxi(0, int(event.get("value", 0)))
		snapshot.shield_sources = sources
		snapshot.shield = _display_shield_total(sources)
	elif event_type == BattleEvent.DOWN:
		snapshot.hp = 0
		snapshot.alive = false
		snapshot.state = "DOWN"
		_start_defeat_presentation(target_uid)
	presentation_display_units[target_uid] = snapshot

func _display_shield_total(sources: Dictionary) -> int:
	var total := 0
	for value in sources.values(): total += int(value)
	return total

# Same order as BattleSimulation._consume_shield: sources sorted by caster uid.
func _consume_display_shield(snapshot: Dictionary, amount: int) -> void:
	var sources: Dictionary = snapshot.get("shield_sources", {})
	if sources.is_empty():
		snapshot.shield = maxi(0, int(snapshot.get("shield", 0)) - amount)
		return
	var left := amount
	var keys: Array = sources.keys()
	keys.sort()
	for key in keys:
		if left <= 0: break
		var used := mini(left, int(sources[key]))
		sources[key] = int(sources[key]) - used
		left -= used
		if int(sources[key]) <= 0: sources.erase(key)
	snapshot.shield_sources = sources
	snapshot.shield = _display_shield_total(sources)

func _start_defeat_presentation(uid: String) -> void:
	var actor: Dictionary = presentation_actor_records.get(uid, {})
	if actor.is_empty() and simulation != null:
		actor = _actor_model(uid)
	if actor.is_empty(): return
	if str(actor.get("team", "")) == "PLAYER":
		defeat_hold_left = maxf(defeat_hold_left, .75)
		return
	if enemy_defeat_bursts.has(uid): return
	var body := actor.duplicate(true)
	body.alive = false
	body.hp = 0
	body.state = "DOWN"
	enemy_defeat_bursts[uid] = {"unit": body, "elapsed": 0.0,
		"duration": 1.05 if str(body.get("rank", "")) == "BOSS" else .78}

func _advance_defeat_presentations(delta: float) -> void:
	defeat_hold_left = maxf(0.0, defeat_hold_left - delta)
	for uid in enemy_defeat_bursts.keys():
		var burst: Dictionary = enemy_defeat_bursts[uid]
		burst.elapsed = float(burst.elapsed) + delta
		if float(burst.elapsed) >= float(burst.duration):
			enemy_defeat_bursts.erase(uid)

func presentation_unit_for_uid(uid: String) -> Dictionary:
	if simulation == null:
		return {}
	return _presentation_unit(_actor_model(uid))

func presentation_boss() -> Dictionary:
	if simulation == null:
		return {}
	for enemy in simulation.state.enemies:
		if str(enemy.get("rank", "")) == "BOSS":
			var visual := _presentation_unit(enemy)
			if bool(visual.get("alive", false)):
				return visual
	return {}

func presentation_cursor_snapshot() -> Dictionary:
	return {"read_cursor": presentation_read_cursor, "presented_cursor": presented_cursor, "active_batch": active_presentation_batch.duplicate(true), "director": presentation_director.cinematic_snapshot()}

## A shallow copy is enough: the five fields below are replaced on the copy, and
## every consumer only reads the nested dictionaries (statuses, stats). The deep
## copy ran for every actor on every frame.
func _presentation_unit(unit: Dictionary) -> Dictionary:
	if unit.is_empty():
		return {}
	var visual := unit.duplicate()
	var snapshot: Dictionary = presentation_display_units.get(str(unit.get("uid", "")), {})
	for field in ["hp", "shield", "alive", "state", "phase"]:
		if snapshot.has(field):
			visual[field] = snapshot[field]
	return visual

## UnitState.alive() of the presented copy, without building the copy.
func _presentation_alive(unit: Dictionary) -> bool:
	var snapshot: Dictionary = presentation_display_units.get(str(unit.get("uid", "")), {})
	return bool(snapshot.get("alive", unit.get("alive", false))) and int(snapshot.get("hp", unit.get("hp", 0))) > 0

func _spawn_projectile(source_uid: String, target_uid: String, attack_kind: String, launch_delay := .14) -> void:
	var source := _actor_model(source_uid)
	if source.is_empty(): return
	var source_id := str(source.get("def_id", ""))
	if str(source.get("role", "")) in ActorChoreography.MELEE_ROLES: return
	var duration := .30
	var projectile: Dictionary = free_projectiles.pop_back() if not free_projectiles.is_empty() else {}
	projectile.clear()
	projectile.merge({
		"source": source_uid,
		"target": target_uid,
		"source_id": source_id,
		"attack_kind": attack_kind,
		"age": 0.0,
		"delay": launch_delay,
		"duration": maxf(.05, duration),
	})
	if projectiles.size() >= MAX_ACTIVE_PROJECTILES:
		free_projectiles.append(projectiles.pop_front())
	projectiles.append(projectile)

func _spawn_damage_text(event: Dictionary) -> void:
	var value := int(event.get("value",0))
	var style := HitFeedback.damage_style(event)
	var critical := style == "crit"
	var target := _actor_model(str(event.get("target","")))
	var tint := Color("ffb7ad") if str(target.get("team","")) == "PLAYER" else Color("fffaf0")
	if critical: tint = Color("ffd66b")
	var tags: Array = event.get("extra",{}).get("tags",[])
	var prefix := ""
	if tags.has("FLANK"): prefix = "측면 "
	elif tags.has("COVER"): prefix = "엄폐 "
	elif tags.has("AREA"): prefix = "직격 "
	_spawn_floating_text({"target":str(event.get("target","")),"text":"MISS" if value == 0 else prefix + MathUtil.comma(value),"crit":critical,"style":style,"weight":HitFeedback.damage_weight(event,target),"color":tint,"age":0.0})

## DAMAGE_FONT (a rounded Latin face) has no Hangul, and the web export has no system font to fall
## back to: the flank / cover / area prefixes ("측면 156") would draw as hex boxes. The battle font
## stands behind it for every glyph it lacks.
func _bind_damage_font_fallback() -> void:
	if battle_font == null:
		return
	# through a variable: GDScript refuses to assign a property of a preloaded constant
	var damage_font: Font = DAMAGE_FONT
	var current: Array[Font] = damage_font.fallbacks
	if current.size() == 1 and current[0] == battle_font:
		return
	var fallbacks: Array[Font] = [battle_font]
	damage_font.fallbacks = fallbacks

func _damage_screen_scale() -> float:
	if not is_inside_tree(): return 1.0
	var transform := get_viewport().get_screen_transform() * get_global_transform_with_canvas()
	return maxf(.01,transform.y.length())

func _damage_head_anchor(target: Dictionary) -> Vector2:
	# A lethal event has already marked the simulation unit down. Its number
	# still belongs above the standing head at impact, never under the corpse.
	var upright := target.duplicate()
	upright.alive = true
	upright.hp = maxi(1,int(target.get("hp",1)))
	return _head_position(upright,_ground_position(upright))

func _spawn_floating_text(data: Dictionary) -> void:
	var item: Dictionary = free_floating_texts.pop_back() if not free_floating_texts.is_empty() else {}
	item.clear()
	item.merge(data)
	item["duration"] = float(HitFeedback.number_style(_damage_number_style_name(item)).duration)
	item["stack"] = 0.0
	# Scatter successive numbers sideways so rapid hits form a readable cluster
	# instead of one tall column climbing into the backdrop.
	floating_serial += 1
	item["jitter"] = float((floating_serial * 5) % 7 - 3) * 22.0 / _damage_screen_scale()
	var target := _actor_model(str(item.get("target","")))
	item["anchor"] = _damage_head_anchor(target) if not target.is_empty() else size * .5
	for previous in floating_texts:
		if previous.target == item.target and float(previous.age) < .65:
			previous.stack = float(previous.get("stack",0.0)) + 15.0 / _damage_screen_scale()
	if floating_texts.size() >= MAX_ACTIVE_FLOATING_TEXTS:
		free_floating_texts.append(floating_texts.pop_front())
	floating_texts.append(item)

func _spawn_vfx(source_uid: String, target_uid: String, kind: String, delay := 0.0, accent := "") -> void:
	var source := _actor_model(source_uid)
	if source.is_empty(): return
	var profile := _vfx_profile_for(source)
	# The Signal Breaker sheet belongs to the player-side visual language.  Using
	# it below every enemy/boss ultimate made their supposedly unique signatures
	# read as the same oversized ring and obscured the enemy silhouette.
	if kind == "ultimate" and str(source.get("team", "")) == "PLAYER" and vfx_frames.has(SIGNAL_BREAKER_ULTIMATE_BASE_KEY):
		var primary := Color(str(profile.get("primary", "70e7ff")))
		var base_tint := primary.lerp(Color.WHITE, .46)
		base_tint.a = .82
		_append_vfx_presentation(source_uid, target_uid, "ultimate_base", SIGNAL_BREAKER_ULTIMATE_BASE_KEY, delay, profile, base_tint, false)
	var asset_kind := kind.trim_prefix("impact_") if kind.begins_with("impact_") else kind
	var key := "%s_%s" % [str(source.get("def_id", "")).to_lower(), asset_kind]
	_append_vfx_presentation(source_uid, target_uid, kind, key, delay, profile, Color.WHITE, kind in ["normal", "ultimate"], accent)

func _append_vfx_presentation(source_uid: String, target_uid: String, kind: String, key: String, delay: float, profile: Dictionary, tint: Color, draw_accent: bool, accent := "") -> void:
	var presentation: Dictionary = free_vfx_presentations.pop_back() if not free_vfx_presentations.is_empty() else {}
	presentation.clear()
	var duration := 0.40
	if kind == "normal": duration = 0.24
	elif kind in ["ultimate", "ultimate_base"]: duration = .32
	elif kind == "impact_normal": duration = .34
	elif kind == "impact_ultimate": duration = .48
	elif kind in ["heal", "shield"]: duration = .56
	presentation.merge({"source": source_uid, "target": target_uid, "kind": kind, "key": key, "textured": vfx_frames.has(key), "age": 0.0, "delay": delay, "duration": duration, "profile": profile, "tint": tint, "draw_accent": draw_accent, "accent": accent})
	if vfx_presentations.size() >= MAX_ACTIVE_VFX:
		free_vfx_presentations.append(vfx_presentations.pop_front())
	vfx_presentations.append(presentation)

func _vfx_profile_for(source: Dictionary) -> Dictionary:
	var def_id := str(source.get("def_id", ""))
	if VFX_UNIT_PROFILES.has(def_id):
		return VFX_UNIT_PROFILES[def_id]
	var definition := DataRegistry.character(def_id)
	if definition.is_empty():
		definition = DataRegistry.enemy(def_id)
	var role := str(definition.get("role", ""))
	var normal_shapes := {"GUARDIAN": "shield", "VANGUARD": "rush", "ASSAULT": "tracer", "ARTILLERY": "artillery", "SPECIALIST": "distort", "MEDIC": "heal", "MELEE_RUSH": "flame", "RANGED": "tracer", "DEFENDER": "heavy", "HEALER": "heal", "BUFFER": "chorus", "DEBUFFER": "dust", "SUMMONER": "summon", "AREA": "lightning"}
	var seed := absi(def_id.hash())
	var primary := Color.from_hsv(float(seed % 360) / 360.0, 0.70, 0.96).to_html(false)
	var secondary := Color.from_hsv(float((int(seed / 11)) % 360) / 360.0, 0.54, 1.0).to_html(false)
	var normal := str(normal_shapes.get(role, "tracer"))
	var ultimate: String = "void" if str(definition.get("rank", "")) == "BOSS" else str(["shield", "rush", "lightning", "artillery", "distort", "heal", "chorus", "summon"][seed % 8])
	return {"primary": primary, "secondary": secondary, "normal": normal, "ultimate": ultimate}

func _spawn_skill_callout(source_uid: String, label: String, color: Color, kind := "") -> void:
	var source := _actor_model(source_uid)
	var team := str(source.get("team", "PLAYER"))
	var boss := str(source.get("rank", "")) == "BOSS"
	if kind.is_empty(): kind = "ultimate" if label == "ULT" else "normal"
	var priority := 2 if kind == "ultimate" or boss else 1
	# One cue per caster: a newer cue replaces that caster's previous plate.
	for index in range(skill_callouts.size() - 1, -1, -1):
		if str(skill_callouts[index].source) == source_uid:
			free_skill_callouts.append(skill_callouts[index])
			skill_callouts.remove_at(index)
	if skill_callouts.size() >= MAX_SKILL_CALLOUTS:
		var weakest := 0
		for index in range(1, skill_callouts.size()):
			var candidate: Dictionary = skill_callouts[index]
			var current: Dictionary = skill_callouts[weakest]
			if int(candidate.priority) < int(current.priority) or (int(candidate.priority) == int(current.priority) and float(candidate.age) > float(current.age)):
				weakest = index
		if int(skill_callouts[weakest].priority) > priority:
			return
		free_skill_callouts.append(skill_callouts[weakest])
		skill_callouts.remove_at(weakest)
	var item: Dictionary = free_skill_callouts.pop_back() if not free_skill_callouts.is_empty() else {}
	item.clear()
	var display_label := label
	if display_label == "ULT" or display_label.is_empty(): display_label = "필살"
	item.merge({
		"source": source_uid,
		"label": display_label,
		"color": color if team == "PLAYER" else (Color("ff5a4a") if boss else Color("ff8a6a")),
		"age": 0.0,
		"duration": 1.30 if priority > 1 else 1.05,
		"priority": priority,
		"kind": kind,
		"style": "plate" if team == "PLAYER" else "shout",
		"role": BattleGrid.role_label(str(source.get("role", "")), team) if team == "PLAYER" and not str(source.get("role", "")).is_empty() else "",
	})
	skill_callouts.append(item)

func _spawn_boss_phase_presentation(source_uid: String, phase_id: String) -> void:
	if not BOSS_PHASE_PRESENTATION.has(phase_id): return
	var definition: Dictionary = BOSS_PHASE_PRESENTATION[phase_id]
	var item: Dictionary = free_boss_phase_presentations.pop_back() if not free_boss_phase_presentations.is_empty() else {}
	item.clear()
	item.merge({
		"source": source_uid,
		"phase_id": phase_id,
		"title_key": str(definition.title_key),
		"subtitle_key": str(definition.subtitle_key),
		"color": Color(str(definition.color)),
		"age": 0.0,
		"duration": float(definition.duration),
	})
	boss_phase_presentations.append(item)
	unit_flash[source_uid] = .24
	_play_animation(source_uid, "ultimate" if phase_id == "ENRAGE" else "normal_skill")

func _recycle_expired_presentations() -> void:
	for index in range(floating_texts.size() - 1, -1, -1):
		if float(floating_texts[index].age) >= float(floating_texts[index].get("duration",1.15)):
			free_floating_texts.append(floating_texts[index])
			floating_texts.remove_at(index)
	for index in range(projectiles.size() - 1, -1, -1):
		if float(projectiles[index].age) >= float(projectiles[index].get("delay", 0.0)) + float(projectiles[index].get("duration", .4)):
			free_projectiles.append(projectiles[index])
			projectiles.remove_at(index)
	for index in range(vfx_presentations.size() - 1, -1, -1):
		if float(vfx_presentations[index].age) >= float(vfx_presentations[index].get("delay", 0.0)) + float(vfx_presentations[index].duration):
			free_vfx_presentations.append(vfx_presentations[index])
			vfx_presentations.remove_at(index)
	for index in range(skill_callouts.size() - 1, -1, -1):
		if float(skill_callouts[index].age) >= float(skill_callouts[index].duration):
			free_skill_callouts.append(skill_callouts[index])
			skill_callouts.remove_at(index)
	for index in range(boss_phase_presentations.size() - 1, -1, -1):
		if float(boss_phase_presentations[index].age) >= float(boss_phase_presentations[index].duration):
			free_boss_phase_presentations.append(boss_phase_presentations[index])
			boss_phase_presentations.remove_at(index)
	for index in range(telegraph_flashes.size() - 1, -1, -1):
		if float(telegraph_flashes[index].age) >= TELEGRAPH_FLASH_DURATION:
			telegraph_flashes.remove_at(index)

func _clear_active_presentation_effects() -> void:
	# Keep the dictionaries in their dedicated pools, but remove every active
	# visual instance in one deterministic place. This is used by skip, terminal
	# result, scene exit and re-entry so new high-density R1 layers cannot escape
	# one of those paths.
	free_floating_texts.append_array(floating_texts)
	free_projectiles.append_array(projectiles)
	free_vfx_presentations.append_array(vfx_presentations)
	free_skill_callouts.append_array(skill_callouts)
	free_boss_phase_presentations.append_array(boss_phase_presentations)
	floating_texts.clear()
	projectiles.clear()
	vfx_presentations.clear()
	skill_callouts.clear()
	boss_phase_presentations.clear()
	unit_flash.clear()
	unit_flash_span.clear()
	hit_flash_frames.clear()
	telegraph_flashes.clear()
	telegraph_keys.clear()
	swarm_drops.clear()
	combo_count = 0
	combo_left = 0.0
	combo_pop = 0.0

func pool_diagnostics() -> Dictionary:
	return {"active_projectiles": projectiles.size(), "free_projectiles": free_projectiles.size(), "active_floating_texts": floating_texts.size(), "free_floating_texts": free_floating_texts.size(), "active_vfx": vfx_presentations.size(), "free_vfx": free_vfx_presentations.size(), "active_skill_callouts": skill_callouts.size(), "free_skill_callouts": free_skill_callouts.size(), "active_boss_phase_presentations": boss_phase_presentations.size(), "free_boss_phase_presentations": free_boss_phase_presentations.size()}

func presentation_residual_snapshot() -> Dictionary:
	# This snapshot is intentionally data-only so headless tests and device QA can
	# prove cleanup without inspecting renderer internals. The anchor residual is
	# derived from the same non-idle tracks used by `_head_position`.
	var transient_actor_count := 0
	for track_value in animation_tracks.values():
		var track: Dictionary = track_value
		if str(track.get("name", "idle")) in ["move", "basic_attack", "normal_skill", "ultimate", "hit"]:
			transient_actor_count += 1
	var active_effect_count := projectiles.size() + vfx_presentations.size() + floating_texts.size() + skill_callouts.size() + boss_phase_presentations.size() + telegraph_flashes.size()
	var camera_at_baseline := is_equal_approx(presentation_director.battlefield_zoom(), 1.0) and presentation_director.battlefield_offset().length() <= .001
	return {
		"active_effect_count": active_effect_count,
		"active_projectiles": projectiles.size(),
		"active_vfx": vfx_presentations.size(),
		"active_overlays": floating_texts.size() + skill_callouts.size() + boss_phase_presentations.size(),
		"director_active": presentation_director.is_active(),
		"camera_at_baseline": camera_at_baseline,
		"transient_actor_count": transient_actor_count,
		"world_health_anchor_transient_count": transient_actor_count,
		"signature_residency": sprite_library.signature_residency_snapshot(),
		"effect_signature_residency": effect_signature_library.signature_residency_snapshot(),
		"signature_residency_target_ids": signature_residency_target_ids.duplicate(),
		"signature_rollover_active": signature_rollover_active,
	}

func presentation_residuals_are_clear() -> bool:
	var snapshot := presentation_residual_snapshot()
	return int(snapshot.get("active_effect_count", -1)) == 0 and not bool(snapshot.get("director_active", true)) and bool(snapshot.get("camera_at_baseline", false)) and int(snapshot.get("transient_actor_count", -1)) == 0 and int(snapshot.get("world_health_anchor_transient_count", -1)) == 0

func boss_phase_presentation_snapshot() -> Array:
	var result: Array = []
	for presentation in boss_phase_presentations:
		result.append({
			"source": str(presentation.source),
			"phase_id": str(presentation.phase_id),
			"title_key": str(presentation.title_key),
			"subtitle_key": str(presentation.subtitle_key),
			"title": LocalizationService.tr_key(str(presentation.title_key)),
			"subtitle": LocalizationService.tr_key(str(presentation.subtitle_key)),
		})
	return result

func _load_runtime_vfx(active_entity_ids: Array[String] = [], reset_frames := true) -> void:
	if reset_frames:
		vfx_frames.clear()
	if not runtime_vfx_manifest_loaded:
		runtime_vfx_manifest_loaded = true
		var manifest_path := "res://assets/runtime_web/runtime_combat_manifest.json"
		if FileAccess.file_exists(manifest_path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
			if parsed is Dictionary:
				runtime_vfx_entries = parsed.get("vfx", [])
	for entry in runtime_vfx_entries:
		var folder := str(entry.get("folder", ""))
		if not folder.begins_with("vfx_"): continue
		var key := folder.trim_prefix("vfx_")
		if vfx_frames.has(key):
			continue
		if not active_entity_ids.is_empty() and not key.begins_with("base_"):
			var belongs_to_active_unit := false
			for entity_id in active_entity_ids:
				if key.begins_with(entity_id.to_lower() + "_"):
					belongs_to_active_unit = true
					break
			if not belongs_to_active_unit:
				continue
		var textures: Array[Texture2D] = []
		var atlas := _load_runtime_texture("res://assets/runtime_web/vfx/%s/atlas.png" % folder)
		if atlas is Texture2D:
			for frame in range(12):
				var texture := AtlasTexture.new()
				texture.atlas = atlas
				texture.region = Rect2(float(frame % 4) * 112.0, float(frame / 4) * 112.0, 112.0, 112.0)
				textures.append(texture)
		if textures.size() == 12: vfx_frames[key] = textures

func _load_combat_preview_fallbacks(active_entity_ids: Array[String]) -> void:
	# A partially loaded pack used to count as success and silently sent every
	# failed ENM/BOSS to the grey code placeholder. Keep the exact authored entity
	# preview as a last-resort Web render and report a hard asset error if neither
	# the animation atlas nor its preview can be decoded.
	fallback_combat_previews.clear()
	for entity_id in active_entity_ids:
		if sprite_library.supports_character(entity_id):
			continue
		var preview_path := "res://assets/runtime_web/combat/%s/preview.png" % entity_id
		var preview := _load_runtime_texture(preview_path)
		if preview != null:
			fallback_combat_previews[entity_id] = preview
		else:
			push_error("COMBAT_ART_MISSING:%s" % entity_id)

func _load_runtime_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var imported = load(path)
		if imported is Texture2D: return imported
	var image := Image.load_from_file(path)
	if image == null or image.is_empty(): return null
	return ImageTexture.create_from_image(image)

func _play_animation(uid: String, animation_name: String, target_uid := "") -> void:
	if animation_name not in ["down", "victory"] and not _action_source_is_presentable(uid):
		return
	if animation_name == "hit":
		var current_name := str((animation_tracks.get(uid, {}) as Dictionary).get("name", "idle"))
		# Damage already supplies additive flash and bounded foot recoil in
		# _draw_unit. Do not cancel a real strike/cast or repeatedly pin HIT at
		# its first frame when five attackers focus one monster.
		if current_name in ["basic_attack", "normal_skill", "ultimate", "hit", "down", "victory"]:
			return
	if not target_uid.is_empty(): engagement_targets[uid] = target_uid
	animation_tracks[uid] = {"name": animation_name, "elapsed": 0.0, "target_uid": target_uid}

func _action_source_is_presentable(uid: String) -> bool:
	if simulation == null or uid.is_empty():
		return false
	# This checks the committed presentation snapshot, not the simulation's later
	# state. A valid cast that happened before its caster was defeated can finish
	# visually, while an actually downed initial source remains suppressed.
	var source := presentation_unit_for_uid(uid)
	return not source.is_empty() and bool(source.get("alive", false)) and str(source.get("state", "")) != "DOWN"

func _advance_animations(delta: float) -> void:
	for uid in animation_tracks:
		var track: Dictionary = animation_tracks[uid]
		track.elapsed = float(track.get("elapsed", 0.0)) + delta
		var animation_name := str(track.get("name", "idle"))
		var unit := _actor_model(str(uid))
		var character_id := str(unit.get("def_id", ""))
		# The high-density signature path can render without a compact pack (the
		# CHR008 QA case). Its non-looping ultimate/hit states must therefore use
		# their own duration instead of leaving an actor transform and world HP/SH
		# anchor offset alive indefinitely after the effect has finished.
		var duration := 0.0
		var is_looping := false
		if action_frames.has_action(character_id, animation_name):
			duration = ActionFrames.duration(animation_name)
		elif signature_sprite_pack_ready and sprite_library.has_signature_animation(character_id, animation_name):
			duration = sprite_library.signature_duration(character_id, animation_name)
			is_looping = sprite_library.signature_is_looping(character_id, animation_name)
		elif sprite_pack_ready and sprite_library.supports_character(character_id):
			duration = sprite_library.duration(character_id, animation_name)
			is_looping = sprite_library.is_looping(character_id, animation_name)
		if not is_looping and duration > 0.0 and float(track.elapsed) >= duration and animation_name not in ["down", "victory"]:
			track.name = "move" if float(entry_tracks.get(uid, 1.0)) < 1.0 else "idle"
			track.elapsed = 0.0
		animation_tracks[uid] = track

func _advance_entries(delta: float) -> void:
	for uid in entry_tracks:
		entry_tracks[uid] = minf(1.0, float(entry_tracks[uid]) + delta / 0.9)
		if float(entry_tracks[uid]) >= 1.0:
			var track: Dictionary = animation_tracks.get(uid, {})
			if str(track.get("name", "")) == "move": animation_tracks[uid] = {"name": "idle", "elapsed": 0.0}

func _region_theme() -> Dictionary:
	## Chapter -> biome family, grade, ornament. Empty for stages without a chapter.
	if not region_dressing_enabled or simulation == null: return {}
	var stage_id := str(simulation.stage.get("id", ""))
	if stage_id != region_theme_stage:
		region_theme_stage = stage_id
		region_theme = RegionFloor.theme_for_stage(simulation.stage)
	return region_theme

func _region_clock() -> float:
	if region_clock_override >= 0.0: return region_clock_override
	return float(Time.get_ticks_msec()) / 1000.0

func _battlefield_transform() -> Transform2D:
	return RegionFloor.battlefield_transform(size, _battlefield_camera_zoom(), _battlefield_offset())

func _begin_draw_memos() -> void:
	_pose_memo.clear()
	_pose_memo_down.clear()
	_scale_memo.clear()
	_position_memo.clear()
	_ground_memo.clear()
	_action_sample_memo.clear()
	_actor_memo.clear()
	_frame_memo.clear()
	_frame_memo_down.clear()
	_footing_rings.clear()
	_draw_zoom = _compute_battlefield_camera_zoom()
	_draw_offset = _compute_battlefield_offset()
	_draw_memo_active = true

func _draw() -> void:
	_begin_draw_memos()
	_draw_scene()
	_draw_memo_active = false

func _draw_scene() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var theme := _region_theme()
	var grade := RegionFloor.background_grade(theme)
	if normal_background != null: draw_texture_rect(normal_background, _battlefield_rect(rect), false, grade)
	else: draw_rect(rect, Color("101b35"))
	var arena_mix := _boss_background_mix()
	if arena_mix > 0.0 and boss_background != null:
		draw_texture_rect(boss_background, _battlefield_rect(rect), false, Color(grade.r, grade.g, grade.b, arena_mix))
		if normal_background != null: _draw_connected_boss_floor(arena_mix, grade)
	draw_rect(rect, Color(0.02, 0.04, 0.09, 0.16))
	if not theme.is_empty(): RegionFloor.draw_far(self, theme, size, _region_clock(), 1.0 - .4 * arena_mix)
	if not assets_ready:
		# Keep the first painted shell honest: actors are not drawn as temporary
		# silhouettes while their immutable atlases are still being registered.
		var warmup_font := battle_font if battle_font != null else ThemeDB.fallback_font
		var warmup_text := "LUMENBOUND · %s" % _asset_warmup_display_label()
		draw_string(warmup_font, Vector2(0, size.y * .54), warmup_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color("9ddfd4"))
		return
	if simulation == null:
		return
	var visible_units: Array = []
	var current_ids: Dictionary = {}
	for unit in simulation.state.party + simulation.state.enemies:
		# A spawn is authoritative immediately, but its body waits for the
		# aperture. Otherwise it pops into the old wave's last impact frame.
		if str(unit.team) == "ENEMY" and UnitState.alive(unit) and _waiting_for_wave_contact(): continue
		if str(unit.team) == "ENEMY" and _wave_scene_elapsed() >= 0.0 and _wave_scene_elapsed() < 1.0: continue
		visible_units.append(_presentation_unit(unit))
		current_ids[str(unit.uid)] = true
	for uid in presentation_actor_records:
		if current_ids.has(uid): continue
		# Records of earlier waves stay forever; only copy the ones still standing.
		var record: Dictionary = presentation_actor_records[uid]
		if _presentation_alive(record): visible_units.append(_presentation_unit(record))
	visible_units.sort_custom(func(a, b): return _unit_pos(a).y < _unit_pos(b).y)
	# All ground shadows precede all bodies; a front unit's shadow must not
	# paint over a rear unit's boots while formation lanes change.
	if not theme.is_empty(): RegionFloor.draw_floor(self, theme, _battlefield_transform(), size, _region_clock(), 1.0 - .45 * arena_mix)
	_draw_tactical_grid()
	_draw_next_wave_preview()
	for unit in visible_units: _draw_contact_shadow(unit)
	_draw_footing_rings()
	for unit in visible_units: _draw_weapon_action(unit, true)
	for unit in visible_units: _draw_unit(unit)
	for unit in visible_units: _draw_weapon_action(unit, false)
	if not theme.is_empty(): RegionFloor.draw_front(self, theme, _battlefield_transform(), size, 1.0 - .3 * arena_mix)
	for drop in swarm_drops: _draw_swarm_drop(drop)
	_draw_combat_readout()
	for burst in enemy_defeat_bursts.values():
		_draw_enemy_defeat_explosion(burst.unit, _ground_position(burst.unit), float(burst.elapsed))
	for projectile in projectiles:
		var source := _actor_model(projectile.source)
		var target := _actor_model(projectile.target)
		if source.is_empty() or target.is_empty(): continue
		var launch_delay := float(projectile.get("delay", 0.0))
		if float(projectile.age) < launch_delay:
			continue
		var duration := float(projectile.get("duration", .4))
		var t := clampf((float(projectile.age) - launch_delay) / maxf(.01, duration), 0, 1)
		var source_position := _projectile_origin(source)
		var target_position := _projectile_target(target)
		var weapon_family := WeaponEffects.family(str(source.get("def_id", "")), str(source.get("role", "")))
		var arc_height := 130.0 if weapon_family in ["mortar", "siege"] else 0.0
		var position := source_position.lerp(target_position, t) + Vector2(0, -arc_height * _battlefield_camera_zoom() * sin(t * PI))
		var source_id := str(projectile.get("source_id", ""))
		var signature_projectile: Texture2D = effect_signature_library.projectile_texture_at(source_id, float(projectile.age)) if effect_signature_pack_ready else null
		var own_hd_projectile: Texture2D = full_density_effects.projectile_at(source_id, t)
		var signature_profile_tint := Color.WHITE
		if own_hd_projectile == null and signature_projectile != null and effect_signature_library.uses_borrowed_profile(source_id):
			var borrowed_profile := _vfx_profile_for(source)
			signature_profile_tint = Color.WHITE.lerp(Color(str(borrowed_profile.get("primary", "ffffff"))), .46)
		var texture := signature_projectile if signature_projectile != null else (projectile_library.texture_at(source_id, float(projectile.age)) if projectile_pack_ready else null)
		if own_hd_projectile != null: texture = own_hd_projectile
		var attack_kind := str(projectile.get("attack_kind", "BASIC"))
		if attack_kind in ["NORMAL", "ULTIMATE"]:
			var trail_color := _skill_color(source, "ultimate" if attack_kind == "ULTIMATE" else "normal")
			trail_color.a = .82
			draw_line(source_position, position, trail_color.darkened(.20), 8.0 if attack_kind == "ULTIMATE" else 5.0, true)
			draw_line(source_position, position, Color(0.92, 1.0, 1.0, .88), 2.0 if attack_kind == "ULTIMATE" else 1.2, true)
			# The authored skill signature now travels with the projectile. Frames 2-9
			# carry the active energy body; charge frames stay at the caster and the
			# final frames are reserved for the contact burst below.
			var travel_key := "%s_%s" % [source_id.to_lower(), attack_kind.to_lower()]
			var signature_travel: Texture2D = effect_signature_library.ultimate_texture_at(source_id, .16 + t * .58) if effect_signature_pack_ready and attack_kind == "ULTIMATE" else null
			if attack_kind == "ULTIMATE":
				var own_hd_travel: Texture2D = full_density_effects.ultimate_at(source_id, .16 + t * .58)
				if own_hd_travel != null: signature_travel = own_hd_travel
			var travel_frames: Array = vfx_frames.get(travel_key, [])
			if signature_travel != null:
				# High-density VFX cells are intentionally drawn larger than the old
				# 112px travel stamp.  The bounded candidate is 2× source density, and
				# the thin vector trail below keeps the trajectory readable in motion.
				# The 2× source density is used for a visibly meaningful travel body on a
				# phone, not merely as an invisible sharper replacement for the old stamp.
				var signature_travel_size := Vector2(260, 260)
				var travel_tint := signature_profile_tint
				travel_tint.a = .88
				draw_texture_rect(signature_travel, Rect2(position - signature_travel_size * .5, signature_travel_size), false, travel_tint)
			elif not travel_frames.is_empty():
				var travel_frame := mini(travel_frames.size() - 1, 2 + int(floor(t * 7.0)))
				var travel_size := Vector2(112, 112) if attack_kind == "ULTIMATE" else Vector2(82, 82)
				draw_texture_rect(travel_frames[travel_frame], Rect2(position - travel_size * .5, travel_size), false, Color(1.0, 1.0, 1.0, .76))
		if texture != null:
			var projectile_size := effect_signature_library.projectile_draw_size(source_id) if signature_projectile != null else projectile_library.runtime_size(source_id)
			if signature_projectile != null:
				if attack_kind == "ULTIMATE": projectile_size *= 1.18
				elif attack_kind == "NORMAL": projectile_size *= 1.10
			else:
				if attack_kind == "ULTIMATE": projectile_size *= 1.24
				elif attack_kind == "NORMAL": projectile_size *= 1.10
			var projectile_tint := signature_profile_tint if signature_projectile != null else Color.WHITE
			draw_texture_rect(texture, Rect2(position - projectile_size * .5, projectile_size), false, projectile_tint)
		else:
			CachedDraw.disc(self, position, 8, Color("fff3a6") if source.team == "PLAYER" else Color("ff8c8c"))
	for presentation in vfx_presentations:
		var source := _actor_model(str(presentation.source))
		var target := _actor_model(str(presentation.get("target", "")))
		if source.is_empty(): continue
		var textures: Array = vfx_frames.get(str(presentation.key), [])
		var delay := float(presentation.get("delay", 0.0))
		if float(presentation.age) < delay: continue
		var progress := clampf((float(presentation.age) - delay) / maxf(0.01, float(presentation.duration)), 0.0, 0.999)
		var kind := str(presentation.get("kind", "basic"))
		var targets_contact := kind.begins_with("impact_") or kind in ["heal", "shield"]
		var anchor_unit := target if targets_contact and not target.is_empty() else source
		var position := _unit_pos(anchor_unit) + _entry_offset(anchor_unit) + _actor_travel_offset(anchor_unit) + Vector2(0, -72)
		if not targets_contact:
			# Cast light belongs to the weapon/ground of the acting unit; it must not
			# appear as a full-image sticker over the unit being attacked.
			var cast_direction := 1.0 if str(source.get("team", "")) == "PLAYER" else -1.0
			position = _unit_pos(source) + _entry_offset(source) + _actor_travel_offset(source) + Vector2(cast_direction * 34.0, -38.0)
		var source_id := str(source.get("def_id", ""))
		# The source sheet reserves its later cells for the endpoint burst. Start
		if kind.begins_with("impact_"):
			WeaponEffects.impact(self, position, WeaponEffects.family(source_id, str(source.get("role", ""))), progress, _skill_color(source, kind), _battlefield_camera_zoom() * (1.35 if kind == "impact_ultimate" else 1.0), str(presentation.get("accent", "")))
		# an impact at that authored burst range rather than replaying cast-frame
		# one at the victim, while ordinary cast VFX still use the full timeline.
		var signature_effect_progress := .50 + progress * .499 if kind == "impact_ultimate" else progress
		var signature_effect: Texture2D = effect_signature_library.ultimate_texture_at(source_id, signature_effect_progress) if effect_signature_pack_ready and kind in ["ultimate", "impact_ultimate"] else null
		var own_hd_effect: Texture2D = full_density_effects.ultimate_at(source_id, signature_effect_progress) if kind in ["ultimate", "impact_ultimate"] else null
		if own_hd_effect != null: signature_effect = own_hd_effect
		if signature_effect != null or not textures.is_empty():
			var frame := mini(textures.size() - 1, int(floor(progress * textures.size())))
			if signature_effect == null and kind.begins_with("impact_"):
				frame = mini(textures.size() - 1, 6 + int(floor(progress * maxi(1, textures.size() - 6))))
			elif signature_effect == null and kind in ["normal", "ultimate", "ultimate_base"]:
				frame = mini(textures.size() - 1, int(floor(progress * min(6, textures.size()))))
			var vfx_size := Vector2(104, 104)
			# Premium signatures put their energy in the outer third of the atlas.
			# Keep enough scale for bloom and directional streaks while preserving at
			# least half of the actor/weapon or boss core at the peak frame.
			if kind == "normal": vfx_size = Vector2(118, 118)
			elif kind == "ultimate": vfx_size = Vector2(154, 154)
			elif kind == "ultimate_base": vfx_size = Vector2(166, 166)
			elif kind == "impact_ultimate": vfx_size = Vector2(144, 144)
			elif kind == "impact_normal": vfx_size = Vector2(112, 112)
			if signature_effect != null:
				# The 224px candidate cells carry the same authored frame sequence but
				# have enough source density to support a bigger mobile-ready read.
				vfx_size = Vector2(320, 320) if kind == "ultimate" else Vector2(300, 300)
			var tint: Color = presentation.get("tint", Color.WHITE)
			if own_hd_effect == null and signature_effect != null and effect_signature_library.uses_borrowed_profile(source_id):
				var borrowed_profile: Dictionary = presentation.get("profile", {})
				var borrowed_primary := Color(str(borrowed_profile.get("primary", "ffffff")))
				tint = tint.lerp(borrowed_primary, .46)
			tint.a = minf(tint.a, .92 if signature_effect != null else .82)
			var texture_to_draw: Texture2D = signature_effect if signature_effect != null else textures[frame]
			draw_texture_rect(texture_to_draw, Rect2(position - vfx_size * 0.5, vfx_size), false, tint)
			if signature_effect != null and kind == "impact_ultimate":
				# A small procedural shock layer gives the dense sprite a sharp contact
				# edge on a bright or dark battlefield without allocating particles.
				_draw_runtime_skill_vfx(position, source, kind, progress)
			if bool(presentation.get("draw_accent", false)):
				_draw_vfx_signature_accent(position, kind, progress, presentation.get("profile", {}))
		else:
			# Pooled vector stages remain below the actor silhouette and connect the
			# cast, projectile trail, endpoint contact and hit reaction visibly.
			_draw_runtime_skill_vfx(position, source, kind, progress)
			if bool(presentation.get("draw_accent", false)):
				_draw_vfx_signature_accent(position, kind, progress, presentation.get("profile", {}))
	for presentation in boss_phase_presentations:
		_draw_boss_phase_presentation(presentation)
	_draw_tactical_markers()
	for unit in visible_units: _draw_unit_status(unit)
	_draw_enemy_intents()
	# Nameplates and shouts sit above HP bars but under the damage numbers.
	for callout in skill_callouts:
		_draw_skill_callout(callout)
	# Misses are secondary information: drawn first, so real numbers stay on top of them.
	var number_anchors := {}
	for text in floating_texts:
		if _damage_number_style_name(text) == "miss":
			_draw_damage_number(text, number_anchors)
	for text in floating_texts:
		if _damage_number_style_name(text) != "miss":
			_draw_damage_number(text, number_anchors)
	_draw_combo_counter()
	# Warnings sit above the damage numbers so the countdown stays readable.
	_draw_boss_telegraph_warnings()
	_draw_wave_banner()
	_draw_ultimate_cutin()
	_draw_boss_scene()
	if finale_elapsed >= 0.0:
		_draw_finale_card(finale_elapsed, FINALE_DURATION, "결착", "작전 완료", "모든 적 신호 소멸")

func _damage_number_style_name(text: Dictionary) -> String:
	var style := str(text.get("style", ""))
	if style.is_empty():
		if bool(text.get("crit", false)): return "crit"
		if str(text.get("text", "")) == "MISS": return "miss"
		return "normal"
	return style

## anchors caches the head position per target for one frame (numbers share targets); an entry of
## null means the target is gone or down and the number keeps the anchor it spawned with.
func damage_number_layout(text: Dictionary, anchors: Dictionary = {}) -> Dictionary:
	var screen_scale := _damage_screen_scale()
	var css_size := clampf(size.x * screen_scale * .023,21.0,34.0)
	var style := _damage_number_style_name(text)
	var spec := HitFeedback.number_style(style)
	var critical := style == "crit"
	# Bigger hits read bigger: a hit worth a third of the victim's HP gets a
	# small size bonus. Misses stay secondary information.
	var weight_bonus := 1.0 + .14 * float(text.get("weight",0.0)) if style in ["normal","weak","resist"] else 1.0
	var font_size := roundi(css_size * float(spec.size) * weight_bonus / screen_scale)
	var age := float(text.get("age",0.0))
	var pop := 1.0 + float(spec.pop) * pow(1.0-clampf(age/.22,0.0,1.0),2.0)
	var anchor: Vector2 = text.get("anchor",size*.5)
	if simulation != null:
		var target_uid := str(text.get("target",""))
		if not anchors.has(target_uid):
			var target := _actor_model(target_uid)
			anchors[target_uid] = _damage_head_anchor(target) if not target.is_empty() and UnitState.alive(target) else null
		if anchors[target_uid] != null:
			anchor = anchors[target_uid]
	var width := DAMAGE_FONT.get_string_size(str(text.text),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var ascent := DAMAGE_FONT.get_ascent(font_size)
	var descent := DAMAGE_FONT.get_descent(font_size)
	var position := anchor + Vector2(float(text.get("jitter",0.0)),-(12.0+age*float(spec.rise))/screen_scale-float(text.get("stack",0.0)))
	position.x = clampf(position.x,width*pop*.5+8.0/screen_scale,size.x-width*pop*.5-8.0/screen_scale)
	position.y = maxf(position.y,(50.0/screen_scale)+ascent*pop)
	var duration := float(text.get("duration",1.15))
	var alpha := 1.0-clampf((age-duration*.65)/(duration*.35),0.0,1.0)
	return {"position":position,"head":anchor,"font_size":font_size,"font_css":font_size*screen_scale*pop,"width":width,"ascent":ascent,"descent":descent,"pop":pop,"alpha":alpha,"crit":critical,"style":style,"screen_scale":screen_scale}

func _draw_damage_number(text: Dictionary, anchors: Dictionary = {}) -> void:
	var metrics := damage_number_layout(text, anchors)
	var style := str(metrics.style)
	var spec := HitFeedback.number_style(style)
	var position: Vector2 = metrics.position
	var screen_scale := float(metrics.screen_scale)
	# Plain hits keep the side tint (ally damage is warm, enemy damage is white).
	var ink: Color = text.color if style == "normal" else spec.ink
	ink.a = float(metrics.alpha) * (.8 if style == "miss" else 1.0)
	var font_size := int(metrics.font_size)
	var tag := str(spec.tag)
	if not tag.is_empty():
		var tag_size := maxi(roundi(9.0 / screen_scale), roundi(float(font_size) * .42))
		var tag_width := DAMAGE_FONT.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size).x
		var tag_base := position + Vector2(-tag_width * .5, -float(metrics.ascent) * float(metrics.pop) - 4.0 / screen_scale)
		var tag_ink: Color = spec.tag_ink
		tag_ink.a = ink.a
		draw_string_outline(DAMAGE_FONT, tag_base, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size, maxi(2, roundi(2.0 / screen_scale)), Color(.12, .06, .04, ink.a))
		draw_string(DAMAGE_FONT, tag_base, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size, tag_ink)
	var baseline := Vector2(-float(metrics.width)*.5,-float(metrics.descent))
	draw_set_transform(position,0.0,Vector2.ONE*float(metrics.pop))
	_draw_damage_number_badge(style, metrics, ink, float(text.get("age",0.0)))
	var outline := maxi(2,roundi(2.4/screen_scale))
	draw_string_outline(DAMAGE_FONT,baseline+Vector2(0,2.0/screen_scale),str(text.text),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,outline+1,Color(0,0,0,ink.a*.7))
	draw_string_outline(DAMAGE_FONT,baseline,str(text.text),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,outline,Color(.10,.065,.065,ink.a))
	draw_string(DAMAGE_FONT,baseline,str(text.text),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,ink)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _draw_damage_number_badge(style: String, metrics: Dictionary, ink: Color, age: float) -> void:
	## Vector shapes that make the four main number kinds readable without
	## reading the digits: a gold burst (crit), an up chevron (weak), a down
	## chevron (resist) and a plus cross with a soft glow (heal).
	var width := float(metrics.width)
	var ascent := float(metrics.ascent)
	var centre := Vector2(0.0, -ascent * .36)
	var alpha := ink.a
	if style == "crit":
		var burst := 1.0 - clampf(age / .42, 0.0, 1.0)
		if burst <= 0.0: return
		var outer := width * .5 + ascent * .72
		var points := PackedVector2Array()
		for index in range(16):
			var radius := outer if index % 2 == 0 else outer * .58
			var angle := TAU * float(index) / 16.0 + .2
			points.append(centre + Vector2(cos(angle) * radius * 1.12, sin(angle) * radius * .62))
		draw_colored_polygon(points, Color(1.0, .78, .22, .30 * burst * alpha))
	elif style == "weak" or style == "resist":
		var up := style == "weak"
		var half := ascent * .28
		var base_x := -width * .5 - ascent * .42
		var tint: Color = HitFeedback.number_style(style).tag_ink
		tint.a = alpha
		for step in range(2 if up else 1):
			var shift := -float(step) * ascent * .30 if up else 0.0
			var tip_y := (-half if up else half) + centre.y + shift
			var base_y := (half if up else -half) + centre.y + shift
			draw_colored_polygon(PackedVector2Array([Vector2(base_x, tip_y), Vector2(base_x - half, base_y), Vector2(base_x + half, base_y)]), tint)
	elif style == "heal":
		var glow := .30 * alpha * (1.0 - clampf(age / .7, 0.0, 1.0))
		if glow > 0.0:
			CachedDraw.disc(self, centre, width * .5 + ascent * .5, Color(.46, .92, .66, glow))
		var arm := ascent * .30
		var thick := maxf(2.0, ascent * .13)
		var cross := Vector2(-width * .5 - ascent * .46, centre.y)
		var cross_ink := Color(.80, 1.0, .88, alpha)
		draw_line(cross - Vector2(arm, 0), cross + Vector2(arm, 0), cross_ink, thick, true)
		draw_line(cross - Vector2(0, arm), cross + Vector2(0, arm), cross_ink, thick, true)

func _draw_ultimate_cutin() -> void:
	var cinematic := presentation_director.cinematic_snapshot()
	if not bool(cinematic.get("active", false)) or simulation == null:
		return
	var visibility := float(cinematic.get("cutin_visibility", 0.0))
	if visibility <= 0.0:
		return
	var batch: Dictionary = cinematic.get("batch", {})
	var cue: Dictionary = batch.get("cue", {})
	var source := _actor_model(str(cue.get("source", "")))
	if source.is_empty():
		return
	if bool(active_cutin.get("show", false)) and str(active_cutin.get("source", "")) == str(cue.get("source", "")):
		_draw_character_cutin(source, cinematic, visibility)
		return
	_draw_compact_ultimate_pulse(source, cinematic, visibility)

func _draw_compact_ultimate_pulse(source: Dictionary, cinematic: Dictionary, visibility: float) -> void:
	var accent := _skill_color(source, "ultimate")
	# The former tilted hero panel was a text-heavy opaque blocker on 390px
	# phones, and fell back to an empty slab for non-human enemies. Keep the
	# timing/camera contract, but render a compact caster-anchored tactical pulse
	# instead. Character identity and charge live permanently in the face-only
	# circular HUD orb; the battle field remains visible through every ultimate.
	var focus := _unit_pos(source) + _entry_offset(source) + Vector2(0, -26)
	var progress := clampf(float(cinematic.get("progress", 0.0)), 0.0, 1.0)
	var pulse := sin(progress * PI) * 8.0
	var radius := clampf(minf(size.x, size.y) * .105 + pulse, 38.0, 54.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(.005, .015, .04, .16 * visibility), true)
	CachedDraw.disc(self, focus, radius * 1.72, Color(accent.r, accent.g, accent.b, .055 * visibility))
	CachedDraw.disc(self, focus, radius * 1.16, Color(.015, .035, .075, .18 * visibility))
	draw_arc(focus, radius, -PI * .5, -PI * .5 + TAU * (.32 + .68 * progress), 36, Color(accent.r, accent.g, accent.b, .94 * visibility), 2.8, true)
	draw_arc(focus, radius * .72, PI * .18, PI * 1.42, 24, Color(1.0, 1.0, 1.0, .60 * visibility), 1.2, true)
	for ray_index in range(4):
		var angle := -PI * .5 + TAU * (float(ray_index) / 4.0) + progress * .38
		var ray_start := focus + Vector2(cos(angle), sin(angle)) * (radius * 1.16)
		var ray_end := focus + Vector2(cos(angle), sin(angle)) * (radius * 1.48)
		draw_line(ray_start, ray_end, Color(accent.r, accent.g, accent.b, .72 * visibility), 1.4, true)

func _draw_boss_phase_presentation(presentation: Dictionary) -> void:
	var duration := maxf(.01, float(presentation.duration))
	var progress := clampf(float(presentation.age) / duration, 0.0, 1.0)
	var enter := clampf(progress / .18, 0.0, 1.0)
	var exit := clampf((1.0 - progress) / .20, 0.0, 1.0)
	var visibility := sin(enter * PI * .5) * sin(exit * PI * .5)
	var accent: Color = presentation.color
	var font := battle_font if battle_font != null else ThemeDB.fallback_font
	var center := Vector2(size.x * .5, size.y * .245)
	var band_width := minf(size.x * .62, 880.0)
	var band_height := clampf(size.y * .115, 96.0, 132.0)
	var slide := (1.0 - enter) * 42.0
	var band_rect := Rect2(center - Vector2(band_width * .5, band_height * .5 + slide), Vector2(band_width, band_height))
	# Low-cost screen response: dark focus wash, luminous edge rails and a boss-
	# anchored pulse. It is view-only and never feeds back into simulation state.
	draw_rect(Rect2(Vector2.ZERO, size), Color(accent.r * .10, accent.g * .08, accent.b * .12, .18 * visibility), true)
	draw_rect(band_rect.grow(8.0), Color(accent.r, accent.g, accent.b, .09 * visibility), true)
	draw_rect(band_rect, Color(.018, .035, .075, .91 * visibility), true)
	draw_line(band_rect.position, band_rect.position + Vector2(band_width, 0), Color(accent.r, accent.g, accent.b, .94 * visibility), 3.0, true)
	draw_line(band_rect.end - Vector2(band_width, 0), band_rect.end, Color(accent.r, accent.g, accent.b, .72 * visibility), 2.0, true)
	var rail_length := band_width * (.32 + .20 * sin(progress * PI))
	draw_line(center + Vector2(-rail_length, -band_height * .32 - slide), center + Vector2(-band_width * .12, -band_height * .32 - slide), Color(1.0, 1.0, 1.0, .55 * visibility), 1.5, true)
	draw_line(center + Vector2(band_width * .12, band_height * .32 - slide), center + Vector2(rail_length, band_height * .32 - slide), Color(1.0, 1.0, 1.0, .42 * visibility), 1.5, true)
	var title := LocalizationService.tr_key(str(presentation.title_key))
	var subtitle := LocalizationService.tr_key(str(presentation.subtitle_key))
	var title_size := clampi(roundi(size.y * .040), 30, 46)
	var subtitle_size := clampi(roundi(size.y * .020), 17, 24)
	draw_string(font, center + Vector2(-band_width * .43, -2.0 - slide), title, HORIZONTAL_ALIGNMENT_CENTER, band_width * .86, title_size, Color(1.0, 1.0, 1.0, visibility))
	draw_string(font, center + Vector2(-band_width * .43, 31.0 - slide), subtitle, HORIZONTAL_ALIGNMENT_CENTER, band_width * .86, subtitle_size, Color(accent.r, accent.g, accent.b, .92 * visibility))
	var boss := _actor_model(str(presentation.source)) if simulation != null else {}
	if not boss.is_empty():
		var boss_position := _unit_pos(boss) + _entry_offset(boss) + Vector2(0, -92)
		var pulse := 56.0 + 34.0 * sin(clampf(progress / .44, 0.0, 1.0) * PI)
		CachedDraw.disc(self, boss_position, pulse, Color(accent.r, accent.g, accent.b, .10 * visibility))
		draw_arc(boss_position, pulse, -progress * TAU, TAU - progress * TAU, 36, Color(accent.r, accent.g, accent.b, .82 * visibility), 4.0, true)

func _draw_runtime_skill_vfx(position: Vector2, source: Dictionary, kind: String, progress: float) -> void:
	var color := _skill_color(source, kind)
	var impact := sin(progress * PI)
	var ultimate := kind in ["ultimate", "impact_ultimate"]
	var fade := 1.0 - progress * .38
	if kind.begins_with("impact_"):
		# Endpoint: shock disk, starburst debris and a crisp white core. This is
		# delayed to the visible projectile arrival instead of being a caster ring.
		var impact_radius := (56.0 if ultimate else 38.0) * (0.55 + impact * .65)
		CachedDraw.disc(self, position, impact_radius, Color(color.r, color.g, color.b, .22 * fade))
		draw_arc(position, impact_radius, -progress * 2.6, TAU - progress * 2.6, 32, Color(color.r, color.g, color.b, .92 * fade), 4.0 if ultimate else 2.8, true)
		draw_arc(position, impact_radius * .56, progress * 4.1, TAU + progress * 4.1, 24, Color(1.0, .98, .84, .86 * fade), 2.0, true)
		var shards := 12 if ultimate else 8
		for index in range(shards):
			var angle := TAU * float(index) / float(shards) + progress * .55
			var origin := position + Vector2(cos(angle), sin(angle)) * impact_radius * .18
			var tip := position + Vector2(cos(angle), sin(angle)) * impact_radius * (1.08 + progress * .38)
			draw_line(origin, tip, Color(color.r, color.g, color.b, .86 * fade), 3.0 if ultimate else 2.0, true)
		CachedDraw.disc(self, position, 9.0 + impact * 10.0, Color(1.0, 1.0, 1.0, .90 * fade))
		return
	if kind == "heal":
		var heal_radius := 30.0 + impact * 24.0
		CachedDraw.disc(self, position, heal_radius, Color(.32, 1.0, .72, .16 * fade))
		draw_arc(position, heal_radius, -progress * TAU, TAU - progress * TAU, 28, Color(.48, 1.0, .76, .92 * fade), 3.2, true)
		draw_line(position + Vector2(-heal_radius * .38, 0), position + Vector2(heal_radius * .38, 0), Color(1, 1, 1, .94 * fade), 4.0, true)
		draw_line(position + Vector2(0, -heal_radius * .38), position + Vector2(0, heal_radius * .38), Color(1, 1, 1, .94 * fade), 4.0, true)
		return
	if kind == "shield":
		var shield_radius := 38.0 + impact * 22.0
		var hex := PackedVector2Array()
		for index in range(6):
			var angle := TAU * float(index) / 6.0 - PI / 2.0
			hex.append(position + Vector2(cos(angle), sin(angle)) * shield_radius)
		draw_colored_polygon(hex, Color(.25, .78, 1.0, .16 * fade))
		draw_polyline(hex + PackedVector2Array([hex[0]]), Color(.50, .90, 1.0, .96 * fade), 3.4, true)
		return
	# Cast phase: a role-coloured ground seal, rotating glyph and energy spikes.
	var radius := 30.0 + 22.0 * impact + (20.0 if ultimate else 0.0)
	var glow := Color(color.r, color.g, color.b, (.26 if ultimate else .19) * fade)
	var core := Color(color.r, color.g, color.b, .92 * fade)
	CachedDraw.disc(self, position + Vector2(0, 18), radius * .84, glow)
	draw_arc(position, radius, 0.0, TAU, 32, core, 4.4 if ultimate else 3.0, true)
	draw_arc(position, radius * .60, -progress * TAU * 1.6, TAU - progress * TAU * 1.6, 20, Color(.94, 1.0, 1.0, .80 * fade), 1.8, true)
	var spokes := 12 if ultimate else 8
	for index in range(spokes):
		var angle := TAU * float(index) / float(spokes) + progress * 1.7
		var inner := position + Vector2(cos(angle), sin(angle)) * radius * .24
		var outer := position + Vector2(cos(angle), sin(angle)) * radius * (1.04 + .18 * impact)
		draw_line(inner, outer, Color(color.r, color.g, color.b, .84 * fade), 3.2 if ultimate else 2.0, true)
	var diamond := PackedVector2Array([
		position + Vector2(0, -radius * .24), position + Vector2(radius * .24, 0),
		position + Vector2(0, radius * .24), position + Vector2(-radius * .24, 0),
	])
	draw_colored_polygon(diamond, Color(1.0, 1.0, 1.0, .82 * fade))

func _draw_vfx_signature_accent(position: Vector2, kind: String, progress: float, profile: Dictionary) -> void:
	# The signature sheet provides the dense pixels; this one pooled draw-time
	# accent supplies a crisp silhouette that remains readable against any battle
	# backdrop.  It is intentionally bounded to one small accent, never another
	# particle system or full-screen overlay.
	if kind not in ["normal", "ultimate"]:
		return
	var shape := str(profile.get(kind, profile.get("normal", "tracer")))
	var primary := Color(str(profile.get("primary", "70e7ff")))
	var secondary := Color(str(profile.get("secondary", "f1d77a")))
	var fade := maxf(.12, 1.0 - progress * .48)
	var peak := sin(progress * PI)
	var radius := (82.0 if kind == "ultimate" else 54.0) * (.58 + peak * .54)
	primary.a = .72 * fade
	secondary.a = .84 * fade
	# Keep the shared readability stack in the outer band.  An opaque center made
	# every hostile cast look like the same radial burst and hid the defining
	# actor/weapon silhouette at the exact moment it should be most readable.
	var bloom_radius := radius * (1.12 + .16 * peak)
	draw_arc(position, bloom_radius, -progress * TAU * 1.3, PI * .28 - progress * TAU * 1.3, 12, Color(secondary.r, secondary.g, secondary.b, .58 * fade), 2.4 if kind == "ultimate" else 1.7, true)
	draw_arc(position, bloom_radius, PI * 1.05 + progress * TAU * 1.1, PI * 1.33 + progress * TAU * 1.1, 12, Color(primary.r, primary.g, primary.b, .52 * fade), 2.0, true)
	if kind == "ultimate":
		for burst_index in range(10):
			var burst_angle := TAU * float(burst_index) / 10.0 - progress * 1.7
			var burst_inner := position + Vector2(cos(burst_angle), sin(burst_angle)) * radius * .62
			var burst_outer := position + Vector2(cos(burst_angle), sin(burst_angle)) * radius * (1.20 + .20 * peak)
			draw_line(burst_inner, burst_outer, Color(primary.r, primary.g, primary.b, .58 * fade), 2.6, true)
	match shape:
		"shield", "barrier_fracture", "plate_rupture":
			var outer := PackedVector2Array()
			for index in range(6):
				var angle := TAU * float(index) / 6.0 - PI * .5 + progress * .75
				outer.append(position + Vector2(cos(angle), sin(angle)) * radius)
			outer.append(outer[0])
			draw_polyline(outer, primary, 2.8, true)
			draw_arc(position, radius * .58, -progress * TAU, TAU - progress * TAU, 20, secondary, 1.8, true)
		"rush", "flame", "rush_cut", "flame_split", "dust_shear":
			for index in range(4):
				var offset := Vector2(-9.0, float(index - 1) * 9.0)
				draw_line(position + Vector2(-radius * 1.16, radius * .64) + offset, position + Vector2(radius * 1.20, -radius * .68) + offset, primary if index < 3 else secondary, 3.0 - index * .42, true)
			if shape == "flame":
				for index in range(6):
					var ember_angle := float(index) * TAU / 6.0 + progress * 3.0
					var ember := position + Vector2(cos(ember_angle), sin(ember_angle)) * radius * (.72 + .16 * sin(progress * 9.0 + index))
					CachedDraw.disc(self, ember, 3.2, secondary)
		"tracer", "lightning", "glass_tracer", "reverse_arc", "orbital_scan", "broadcast_glitch", "broadcast_tear":
			if shape != "lightning":
				draw_arc(position, radius * .48, 0.0, TAU, 24, secondary, 1.8, true)
				for offset in [-.22, 0.0, .22]:
					draw_line(position + Vector2(-radius * 1.18, radius * offset), position + Vector2(radius * 1.30, radius * (offset - .14)), primary, 2.0, true)
			else:
				for branch in range(4 if kind == "ultimate" else 2):
					var points := PackedVector2Array([position])
					for step in range(1, 6):
						var branch_angle := -PI * .5 + (branch - 1.5) * .34 + sin(float(step * 3 + branch) + progress * 8.0) * .16
						points.append(position + Vector2(cos(branch_angle), sin(branch_angle)) * radius * float(step) / 5.0)
					draw_polyline(points, primary, 3.0, true)
					draw_polyline(points, secondary, 1.0, true)
		"artillery", "chorus", "battery_barrage", "chorus_collapse", "harmonic_bars", "iron_vibration", "slab_resonance":
			var rings := 4 if shape in ["chorus", "chorus_collapse"] else 2
			for index in range(rings):
				var local_radius := radius * (.35 + float(index) * .19)
				draw_arc(position, local_radius, progress * TAU + index * .72, progress * TAU + index * .72 + PI * 1.35, 24, primary if index % 2 == 0 else secondary, 2.4, true)
			if shape in ["artillery", "battery_barrage"]:
				for index in range(5):
					var impact_angle := -2.3 + float(index) * 1.15
					var impact := position + Vector2(cos(impact_angle), sin(impact_angle)) * radius * .92
					draw_line(position + Vector2(0, radius * .22), impact, primary, 1.7, true)
					CachedDraw.disc(self, impact, 3.0, secondary)
		"distort", "dust", "void":
			for index in range(3):
				var local_radius := radius * (.42 + float(index) * .22)
				var angle := progress * TAU * (1.6 if shape != "void" else -2.3) + index * 1.2
				draw_arc(position, local_radius, angle, angle + PI * 1.45, 22, primary if index != 1 else secondary, 2.6, true)
			if shape == "void":
				CachedDraw.disc(self, position, radius * .24, Color(.04, .06, .14, .44 * fade))
		"implode":
			# BOSS001, Void Engine: particles are drawn inward until the peak,
			# then the same rays reverse into a compact rupture.  This is visibly
			# different from the generic radial burst used by ordinary attacks.
			var implode_phase := clampf(progress / .56, 0.0, 1.0)
			var rupture_phase := clampf((progress - .56) / .44, 0.0, 1.0)
			for index in range(12):
				var implode_angle := TAU * float(index) / 12.0 - progress * 2.4
				var outer_radius := radius * (1.30 - implode_phase * .88 + rupture_phase * .54)
				var inner_radius := radius * (.18 + implode_phase * .10 + rupture_phase * .25)
				var outer_point := position + Vector2(cos(implode_angle), sin(implode_angle)) * outer_radius
				var inner_point := position + Vector2(cos(implode_angle + .20), sin(implode_angle + .20)) * inner_radius
				draw_line(outer_point, inner_point, primary if index % 2 == 0 else secondary, 3.2, true)
			draw_arc(position, radius * (1.08 - implode_phase * .72 + rupture_phase * .44), -progress * 7.0, TAU - progress * 7.0, 32, secondary, 3.4, true)
			CachedDraw.disc(self, position, radius * (.12 + rupture_phase * .20), Color(.025, .04, .11, .78 * fade))
			if rupture_phase > .12:
				CachedDraw.disc(self, position, radius * (.10 + rupture_phase * .18), Color(1.0, 1.0, 1.0, .68 * fade))
		"resonance":
			# BOSS002, Midnight Bell: the impact is three delayed ring pulses,
			# intentionally leaving a brief readable gap before the largest ring.
			for index in range(3):
				var ring_start := float(index) * .18
				var ring_progress := clampf((progress - ring_start) / .64, 0.0, 1.0)
				if ring_progress <= .0:
					continue
				var ring_radius := radius * (.24 + ring_progress * (.55 + float(index) * .22))
				var ring_alpha := (1.0 - ring_progress) * (.38 + float(index) * .16) * fade
				draw_arc(position, ring_radius, PI * .12 + index * .28, TAU + PI * .12 + index * .28, 40, Color(primary.r, primary.g, primary.b, ring_alpha), 2.2 + index * 1.15, true)
				draw_arc(position, ring_radius * .72, -ring_progress * TAU, TAU - ring_progress * TAU, 26, Color(secondary.r, secondary.g, secondary.b, ring_alpha * .82), 1.2, true)
			CachedDraw.disc(self, position, radius * (.07 + peak * .12), Color(1.0, 1.0, 1.0, .68 * fade))
		"lockon":
			# BOSS003, White Night Observer: narrow targeting axis, reticle lock,
			# then a snapped wide beam.  Its linear grammar avoids ring reuse.
			var lock_phase := clampf(progress / .52, 0.0, 1.0)
			var overload_phase := clampf((progress - .52) / .48, 0.0, 1.0)
			var reticle := radius * (.72 - lock_phase * .38 + overload_phase * .44)
			draw_rect(Rect2(position - Vector2(reticle, reticle) * .5, Vector2(reticle, reticle)), secondary, false, 2.6, true)
			draw_line(position + Vector2(-radius * 1.42, 0), position + Vector2(radius * 1.42, 0), Color(primary.r, primary.g, primary.b, .52 * fade), 2.0 + overload_phase * 8.0, true)
			draw_line(position + Vector2(0, -radius * 1.20), position + Vector2(0, radius * 1.20), Color(secondary.r, secondary.g, secondary.b, .34 * fade), 1.5, true)
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var corner_origin: Vector2 = position + corner * reticle * .50
				draw_line(corner_origin, corner_origin - corner * reticle * (.24 + overload_phase * .14), primary, 3.0, true)
			if overload_phase > .10:
				CachedDraw.disc(self, position, radius * (.10 + overload_phase * .15), Color(1.0, 1.0, 1.0, .74 * fade))
		"gate_reverse":
			# BOSS004, Reverse Gatekeeper: paired plates close, counter-rotate and
			# snap apart.  The panel geometry is unique to this boss.
			var close_phase := clampf(progress / .46, 0.0, 1.0)
			var reopen_phase := clampf((progress - .46) / .54, 0.0, 1.0)
			var panel_gap := radius * (.98 - close_phase * .75 + reopen_phase * 1.10)
			var panel_size := Vector2(radius * .46, radius * 1.04)
			for side in [-1.0, 1.0]:
				var panel_center := position + Vector2(side * panel_gap, 0)
				var panel_rotation: float = side * (progress * 1.9 - reopen_phase * 4.2)
				var panel_points := PackedVector2Array()
				for base_point in [Vector2(-.5, -.5), Vector2(.5, -.5), Vector2(.5, .5), Vector2(-.5, .5)]:
					panel_points.append(panel_center + (base_point * panel_size).rotated(panel_rotation))
				panel_points.append(panel_points[0])
				draw_polyline(panel_points, primary if side < 0.0 else secondary, 3.4, true)
				draw_line(panel_center + Vector2(0, -panel_size.y * .36).rotated(panel_rotation), panel_center + Vector2(0, panel_size.y * .36).rotated(panel_rotation), Color(1.0, 1.0, 1.0, .62 * fade), 1.5, true)
			if reopen_phase > .08:
				draw_line(position + Vector2(-radius * 1.38, 0), position + Vector2(radius * 1.38, 0), Color(1.0, 1.0, 1.0, .62 * fade), 3.2, true)
		"network":
			# BOSS005, Return Formation Core: empty slots link to a central core,
			# form a network, then collapse.  It must never read as a recoloured ring.
			var form_phase := clampf(progress / .62, 0.0, 1.0)
			var collapse_phase := clampf((progress - .62) / .38, 0.0, 1.0)
			var nodes := PackedVector2Array()
			for index in range(6):
				var node_angle := TAU * float(index) / 6.0 - PI * .5 + progress * .54
				var node_radius := radius * (1.04 - form_phase * .46 + collapse_phase * .26)
				nodes.append(position + Vector2(cos(node_angle), sin(node_angle)) * node_radius)
			for index in range(nodes.size()):
				var node := nodes[index]
				var next_node := nodes[(index + 1) % nodes.size()]
				var link_alpha := (.18 + form_phase * .58) * (1.0 - collapse_phase * .34) * fade
				draw_line(node, next_node, Color(primary.r, primary.g, primary.b, link_alpha), 2.4, true)
				draw_line(node, position, Color(secondary.r, secondary.g, secondary.b, link_alpha * .72), 1.7, true)
				CachedDraw.disc(self, node, 4.0 + form_phase * 3.4, Color(secondary.r, secondary.g, secondary.b, .76 * fade))
			CachedDraw.disc(self, position, radius * (.10 + form_phase * .18 - collapse_phase * .08), Color(primary.r, primary.g, primary.b, .34 * fade))
			CachedDraw.disc(self, position, radius * (.05 + form_phase * .08), Color(1.0, 1.0, 1.0, .72 * fade))
		"heal", "barrier_mend":
			for index in range(3):
				var heal_y := position.y + radius * .32 - float(index) * radius * .25 - progress * radius * .24
				draw_arc(Vector2(position.x, heal_y), radius * (.42 + index * .16), PI * .08, PI * .92, 20, primary, 2.7, true)
			CachedDraw.disc(self, position, radius * .18, secondary)
		"heavy", "summon", "ward_gate":
			var vertices := 5 if shape == "summon" else 4
			var polygon := PackedVector2Array()
			for index in range(vertices):
				var angle := TAU * float(index) / float(vertices) - PI * .5 + progress * .46
				polygon.append(position + Vector2(cos(angle), sin(angle)) * radius * .84)
			polygon.append(polygon[0])
			draw_polyline(polygon, secondary, 3.0, true)
			for index in range(vertices):
				var tip := position + Vector2(cos(TAU * float(index) / float(vertices)), sin(TAU * float(index) / float(vertices))) * radius * 1.15
				draw_line(position, tip, primary, 2.0, true)
		_:
			for index in range(8):
				var spoke_angle := TAU * float(index) / 8.0 + progress * .8
				draw_line(position + Vector2(cos(spoke_angle), sin(spoke_angle)) * radius * .18, position + Vector2(cos(spoke_angle), sin(spoke_angle)) * radius, primary, 2.0, true)

func _skill_color(source: Dictionary, kind: String) -> Color:
	var role := str(source.get("role", ""))
	var base := Color("70e7ff")
	match role:
		"GUARDIAN": base = Color("64dfc0")
		"VANGUARD": base = Color("ffb36a")
		"ASSAULT": base = Color("ff7f9d")
		"ARTILLERY": base = Color("8e9dff")
		"SPECIALIST": base = Color("c785ff")
		"MEDIC": base = Color("75f4be")
	if kind == "ultimate": return base.lightened(.22)
	return base

func _boss_present() -> bool:
	return boss_arena_active or not presentation_boss().is_empty()

static func unit_display_name(unit: Dictionary) -> String:
	var definition_id := str(unit.get("def_id", ""))
	var definition := DataRegistry.character(definition_id)
	if definition.is_empty():
		definition = DataRegistry.enemy(definition_id)
	var name_key := str(definition.get("name_key", ""))
	if not name_key.is_empty():
		var localized := LocalizationService.tr_key(name_key).replace(" (DEV)", "")
		if not localized.is_empty() and not localized.begins_with("["):
			return localized
	# Release combat must never expose ENMxxx/CHRxxx database identifiers. Keep a
	# readable localized fallback if a future data row is temporarily incomplete.
	return "아군" if str(unit.get("team", "")) == "PLAYER" else "적 유닛"

func _draw_connected_boss_floor(visibility := 1.0, grade := Color.WHITE) -> void:
	# The original cathedral image's middle moat cannot be a combat floor.
	# Composite the existing scene-matched, high-resolution stone foreground
	# in Canvas (no altered bitmap, download or texture allocation). The boss
	# chamber remains behind it; the party gains a real full-width battle lane.
	if _boss_floor_mesh == null or _boss_floor_mesh_size != size:
		var bands := [.615, .665, .93, 1.02]
		var source_rows := [.605, .645, .93, 1.0]
		var colors := [Color(.63, .56, .44, 0), Color(.72, .64, .51, 1), Color(.65, .57, .45, 1), Color(.22, .25, .25, 1)]
		var vertices := PackedVector2Array()
		var uv := PackedVector2Array()
		var vertex_colors := PackedColorArray()
		var indices := PackedInt32Array()
		for index in range(bands.size() - 1):
			var base := vertices.size()
			vertices.append_array(PackedVector2Array([Vector2(0, size.y * bands[index]), Vector2(size.x, size.y * bands[index]), Vector2(size.x, size.y * bands[index + 1]), Vector2(0, size.y * bands[index + 1])]))
			uv.append_array(PackedVector2Array([Vector2(0, source_rows[index]), Vector2(1, source_rows[index]), Vector2(1, source_rows[index + 1]), Vector2(0, source_rows[index + 1])]))
			vertex_colors.append_array(PackedColorArray([colors[index], colors[index], colors[index + 1], colors[index + 1]]))
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_COLOR] = vertex_colors
		arrays[Mesh.ARRAY_INDEX] = indices
		_boss_floor_mesh = ArrayMesh.new()
		_boss_floor_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_boss_floor_mesh_size = size
	draw_mesh(_boss_floor_mesh, normal_background, _battlefield_pixel_transform(), Color(grade.r, grade.g, grade.b, visibility))

func _ground_position(unit: Dictionary) -> Vector2:
	var uid := str(unit.get("uid", ""))
	if _draw_memo_active and not uid.is_empty() and _ground_memo.has(uid): return _ground_memo[uid]
	var point := _unit_pos(unit) + _entry_offset(unit) + _actor_travel_offset(unit) + _field_pose_offset(unit)
	if _draw_memo_active and not uid.is_empty(): _ground_memo[uid] = point
	return point

func _draw_contact_shadow(unit: Dictionary) -> void:
	if boss_entry_elapsed >= 0.0 and boss_entry_uids.has(str(unit.uid)) and boss_entry_elapsed < 1.95: return
	if str(unit.get("team", "")) != "PLAYER" and not UnitState.alive(unit): return
	var p := _ground_position(unit)
	var pose := _registered_sprite_pose(unit)
	p.x += (pose.get("offset", Vector2.ZERO) as Vector2).x
	var width := 1.8 if str(unit.get("rank", "")) == "BOSS" else (0.8 if str(unit.get("team", "")) == "PLAYER" else 1.35)
	var zoom := _battlefield_camera_zoom()
	# Soft ellipses are cached textures (see battle_soft_sprites.gd): the polygon
	# versions rebuilt GPU buffers for every unit on every Web frame.
	SoftSprites.draw_ellipse(self, p, Vector2(88 * width, 15) * zoom, Color(0, 0, 0, .12))
	SoftSprites.draw_ellipse(self, p, Vector2(65 * width, 9) * zoom, Color(0, 0, 0, .25))
	SoftSprites.draw_ellipse(self, p + Vector2(float(pose.get("contact_x", 0)), 0), Vector2(21, 4) * zoom, Color(0, 0, 0, .46))
	if UnitState.alive(unit):
		# Team-coloured footing: a soft glow pool plus a breathing ring, so allies
		# (cyan) and enemies (red) separate at a glance even in busy effects.
		var team_color := Color(.27, .88, .84) if str(unit.team) == "PLAYER" else Color(1, .30, .22)
		var pulse := .5 + .5 * sin(float(Time.get_ticks_msec()) / 1000.0 * TAU * .6 + float(absi(hash(str(unit.uid))) % 100))
		SoftSprites.draw_ellipse(self, p, Vector2(52 * width, 12) * zoom, Color(team_color.r, team_color.g, team_color.b, .10 + .06 * pulse))
		_footing_rings.append([p, width, Color(team_color.r, team_color.g, team_color.b, .58 + .3 * pulse)])

## The breathing rings of every footing, drawn after all the shadows so the three
## ring textures (ally / enemy / boss width) batch instead of alternating with the
## ellipse texture once per unit.
func _draw_footing_rings() -> void:
	if _footing_rings.is_empty(): return
	var zoom := _battlefield_camera_zoom()
	for ring_width in FOOTING_RING_WIDTHS:
		var texture: Texture2D = null
		for entry in _footing_rings:
			if not is_equal_approx(float(entry[1]), ring_width): continue
			if texture == null: texture = SoftSprites.ring(FOOTING_RING_RADIUS.x * ring_width, FOOTING_RING_RADIUS.y, FOOTING_RING_STROKE)
			draw_texture_rect(texture, SoftSprites.ring_rect(entry[0], FOOTING_RING_RADIUS.x * ring_width, FOOTING_RING_RADIUS.y, FOOTING_RING_STROKE, zoom), false, entry[2])
	_footing_rings.clear()

func _draw_weapon_action(unit: Dictionary, ground_layer: bool) -> void:
	if not UnitState.alive(unit): return
	var track: Dictionary = animation_tracks.get(str(unit.get("uid", "")), {})
	var action := str(track.get("name", "idle"))
	if action not in ["basic_attack", "normal_skill", "ultimate"]: return
	var target := _actor_model(str(track.get("target_uid", "")))
	if target.is_empty(): return
	var style := WeaponEffects.family(str(unit.get("def_id", "")), str(unit.get("role", "")))
	var elapsed := float(track.get("elapsed", 0.0))
	var zoom := _battlefield_camera_zoom()
	if ground_layer:
		if str(unit.get("team", "")) != str(target.get("team", "")):
			WeaponEffects.telegraph(self, _ground_position(target), style, elapsed, 1.12 if action == "ultimate" else CONTACT_DELAY, str(unit.get("team", "")) != "PLAYER", zoom)
	else:
		WeaponEffects.action(self, _projectile_origin(unit), _projectile_target(target), style, elapsed, action, _skill_color(unit, "ultimate" if action == "ultimate" else "normal"), zoom)

func _draw_unit(unit: Dictionary) -> void:
	if boss_entry_elapsed >= 0.0 and str(unit.team) != "PLAYER" and boss_entry_elapsed < .95: return
	var p := _ground_position(unit)
	p.y -= _field_hop_px(unit)
	var player: bool = str(unit.team) == "PLAYER"
	var alive := UnitState.alive(unit)
	if not player and not alive:
		# Enemies and bosses use a short destruction burst. Their down atlases are
		# intentionally not shown; only player characters receive authored prone art.
		return
	var color := _character_color(unit.slot) if player else _enemy_color(unit.rank)
	if not alive: color = color.darkened(.65)
	if unit_flash.has(unit.uid) or hit_flash_frames.has(unit.uid): color = Color.WHITE
	var generated_sprite := (sprite_pack_ready and sprite_library.supports_character(str(unit.def_id))) or fallback_combat_previews.has(str(unit.def_id))
	# Generated CHR001 frames contain their own motion. Every remaining
	# code-native DEV placeholder receives the same event-driven directional
	# pose offset so all five allies and all enemies visibly animate.
	if not generated_sprite:
		p += _placeholder_pose_offset(unit)
	elif swarm_unit(unit):
		_draw_swarm_companions(unit, p, swarm_member_count(UnitState.hp_ratio(unit)))
	if _draw_combat_sprite(unit, p, alive):
		pass
	elif player:
		_draw_player_sd(p, color, str(unit.role), alive)
	elif unit.rank == "BOSS":
		# Bosses deploy on the right and visibly face screen-left. The forward
		# sensor, jaw, and attack core all sit on the left side of the chassis.
		CachedDraw.disc(self, p + Vector2(8, -48), 62, color)
		draw_rect(Rect2(p + Vector2(-40, -35), Vector2(96, 70)), color.darkened(.15))
		var boss_jaw := PackedVector2Array([p + Vector2(-62, -67), p + Vector2(-28, -81), p + Vector2(-30, -45), p + Vector2(-66, -48)])
		draw_colored_polygon(boss_jaw, color.lightened(.08))
		CachedDraw.disc(self, p + Vector2(-29, -65), 9, Color("ffdf6b"))
		CachedDraw.disc(self, p + Vector2(-49, -57), 5, Color("ff7a70"))
	else:
		_draw_nonhuman_enemy(p, color, str(unit.role), alive)

## Full-width wave banner: a gilt band sweeps open, the title punches in, then
## both fade. Timed in presentation seconds, so pause and speed are respected.
func _draw_wave_banner() -> void:
	if wave_banner_left <= 0.0 or wave_banner_title.is_empty() or deployment_active or _wave_scene_elapsed() >= 0.0 or _waiting_for_wave_contact(): return
	var elapsed := WAVE_BANNER_DURATION - wave_banner_left
	var open := smoothstep(0.0, .26, elapsed)
	var fade := 1.0 - smoothstep(WAVE_BANNER_DURATION - .45, WAVE_BANNER_DURATION, elapsed)
	var readout := _readout_scale()
	var center_y := size.y * .36
	var band_height := 124.0 * readout
	var band_width := size.x * open
	var band := Rect2(Vector2((size.x - band_width) * .5, center_y - band_height * .5), Vector2(band_width, band_height))
	Ornament.band(self, band, fade, readout * .9, Ornament.LUMEN, fposmod(elapsed * .9, 1.0), Ornament.INK, size.x * .16)
	# Speed streaks run through the band while it opens, then thin out.
	var streak_alpha := .30 * fade * (1.0 - smoothstep(.5, 1.1, elapsed))
	Ornament.speed_lines(self, band.grow_individual(0, -band_height * .20, 0, -band_height * .20), elapsed, Ornament.tint(Ornament.LUMEN, streak_alpha), 14, 3, .8)
	var font := battle_font if battle_font != null else ThemeDB.fallback_font
	var punch := 1.0 + .35 * (1.0 - smoothstep(.12, .40, elapsed))
	var title_size := _fit_font_size(font, wave_banner_title, roundi(60.0 * readout * punch), size.x * .86)
	Ornament.centered_text(self, font, Vector2(size.x * .5, center_y - band_height * .05), wave_banner_title, title_size, Color(1.0, .95, .80, fade), roundi(8.0 * readout), Color(.12, .06, .01, fade))
	var sub_size := roundi(20.0 * readout)
	Ornament.centered_text(self, font, Vector2(size.x * .5, center_y + band_height * .33), wave_banner_subtitle, sub_size, Color(.72, .92, 1.0, .9 * fade))

func _readout_scale() -> float:
	return clampf(.62 / _damage_screen_scale(), 1.0, 2.6)

func _draw_boss_telegraph_warnings() -> void:
	if simulation == null or simulation.pending_boss_casts.is_empty() or scene_transition_active(): return
	var font := battle_font if battle_font != null else ThemeDB.fallback_font
	var readout := _readout_scale()
	var font_size := clampi(roundi(20.0 * readout), 20, 50)
	var count_size := clampi(roundi(34.0 * readout), 26, 92)
	for cast in simulation.pending_boss_casts:
		var remaining := _telegraph_remaining(cast)
		var urgency := _telegraph_urgency(cast)
		# The countdown sits on the marked floor, drawn above the actors.
		var cells: Array = cast.get("cells", [])
		if not cells.is_empty():
			var centroid := Vector2.ZERO
			for cell in cells:
				centroid += cell_screen_center(int(cell[0]), int(cell[1]))
			centroid /= float(cells.size())
			var beat := 1.0 + .18 * pow(1.0 - fposmod(remaining, 1.0), 3.0)
			Ornament.centered_text(self, DAMAGE_FONT, centroid, "%.1f" % remaining, roundi(count_size * beat), Color(1.0, .95, .88, .90), maxi(4, roundi(5.0 * readout)), Color(.45, .02, .02, .92))
		var boss := presentation_unit_for_uid(str(cast.boss_uid))
		if boss.is_empty() or not UnitState.alive(boss): continue
		var label := str(cast.get("label", ""))
		if label.is_empty(): label = "집중 조준" if str(cast.get("shape", "")) == "CELL" else "광역 공격"
		var text := "경고 · %s" % label
		var head := _head_position(boss, _ground_position(boss))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 48.0 * readout
		var height := font_size + 16.0 * readout
		var box := Rect2(head + Vector2(-width * .5, -58.0 * readout - height), Vector2(width, height))
		box.position.x = clampf(box.position.x, 14.0 * readout, size.x - width - 14.0 * readout)
		box.position.y = maxf(box.position.y, 8.0)
		Ornament.band(self, box, 1.0, readout * .62, Color("ff7a5a"), urgency, Color(.30, .03, .05))
		Ornament.centered_text(self, font, box.get_center(), text, font_size, Color("ffe2d8"), maxi(3, roundi(3.0 * readout)), Color(.2, 0, 0, .9))

# Each enemy shows how close its next attack is; right before it fires, a thin
# line points at the ally it will hit, so front/back placement can be read live.
func _draw_enemy_intents() -> void:
	if simulation == null or scene_transition_active(): return
	var readout := _readout_scale()
	for model in simulation.state.enemies:
		if not UnitState.alive(model): continue
		var enemy := _presentation_unit(model)
		var interval := maxf(.1, float(model.get("attack_interval", 1.45)))
		var left := clampf(float(model.get("attack_cd", interval)), 0.0, interval)
		var charge := 1.0 - left / interval
		var head := _head_position(enemy, _ground_position(enemy))
		var bar_width := (96.0 if str(enemy.get("rank", "")) != "BOSS" else 150.0) * readout
		var center := head + Vector2(-bar_width / 2.0 - 14.0 * readout, -14.0 * readout)
		var radius := 8.0 * readout
		var imminent := left <= .45
		var color := Color("ff6b5e") if imminent else Color("f1d77a")
		SoftSprites.draw_disc(self, center, radius + 2.0, Color(.02, .04, .08, .8))
		# The charge arc comes from a small set of prebuilt meshes (1/32 turn apart,
		# about one simulation tick of an attack interval) instead of a polyline.
		var arc_steps := clampi(roundi(charge * INTENT_ARC_STEPS), 0, INTENT_ARC_STEPS)
		if arc_steps > 0: draw_mesh(_intent_arc(arc_steps), null, Transform2D(Vector2(readout, 0.0), Vector2(0.0, readout), center), color)
		if imminent:
			var target := TargetResolver.choose(model, simulation.state.party)
			if target.is_empty(): continue
			var target_view := presentation_unit_for_uid(str(target.uid))
			if target_view.is_empty(): continue
			var target_head := _head_position(target_view, _ground_position(target_view))
			draw_line(head, target_head, Color(1.0, .42, .36, .55), 2.0 * readout, true)
			CachedDraw.disc(self, target_head + Vector2(0, -10.0 * readout), 5.0 * readout, Color(1.0, .42, .36, .85))

## Charge arc of the intent dial at `steps`/INTENT_ARC_STEPS of a turn, radius 8
## and stroke 3 (the dial's size at readout 1; the caller scales it). White, so the
## draw's modulate carries the colour.
func _intent_arc(steps: int) -> ArrayMesh:
	if _intent_arcs.has(steps): return _intent_arcs[steps]
	var kit := MeshKit.new()
	var segments := maxi(2, ceili(float(steps) * 24.0 / float(INTENT_ARC_STEPS)))
	var points := PackedVector2Array()
	for index in range(segments + 1):
		var angle := -PI * .5 + TAU * float(steps) / float(INTENT_ARC_STEPS) * float(index) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * 8.0)
	kit.stroke(points, 3.0, Color.WHITE, false)
	var mesh := kit.build()
	_intent_arcs[steps] = mesh
	return mesh

const STATUS_PIPS := {
	"HASTE": ["가속", "7ee8a8"], "SLOW": ["감속", "ffb46b"], "TAUNT": ["도발", "ffd36a"],
	"DEF_DOWN": ["방↓", "ff7a8a"], "ATK_DOWN": ["공↓", "ff9a7a"], "STUN": ["기절", "f5f07a"],
	"SILENCE": ["침묵", "c6a8ff"], "INVULNERABLE": ["무적", "9fe8ff"],
}

# HP, shield, status and name are drawn after every body, projectile and VFX so
# large effects never hide them. On a phone the canvas is shown at ~0.2-0.4x;
# scale the readout back up so bars stay a few screen pixels tall and names legible.
## Squad eligibility: regular enemies only. Elites and bosses stay single.
static func swarm_unit(unit: Dictionary) -> bool:
	return str(unit.get("team", "")) != "PLAYER" and str(unit.get("rank", "NORMAL")) == "NORMAL"

## Bodies standing for a squad at this HP ratio (1..3). Presentation only.
static func swarm_member_count(hp_ratio: float) -> int:
	var count := 1
	for companion in SWARM_COMPANIONS:
		if hp_ratio > float(companion.threshold) + .0001: count += 1
	return count

func _swarm_companion_offset(unit: Dictionary, index: int) -> Vector2:
	var offset: Vector2 = SWARM_COMPANIONS[index].offset
	var canvas := 512.0 * _combat_sprite_scale(unit, "idle")
	var lane_step := (float(Grounding.LANE_Y[1]) - float(Grounding.LANE_Y[0])) * size.y * _battlefield_camera_zoom()
	return Vector2(offset.x * canvas, offset.y * lane_step)

## Rear squad bodies, drawn before the main body so it overlaps them.
func _draw_swarm_companions(unit: Dictionary, p: Vector2, members: int) -> void:
	var zoom := _battlefield_camera_zoom()
	for index in range(members - 1):
		var companion: Dictionary = SWARM_COMPANIONS[index]
		var foot := p + _swarm_companion_offset(unit, index)
		SoftSprites.draw_ellipse(self, foot, Vector2(46, 8) * zoom * float(companion.scale), Color(0, 0, 0, .26))
		_draw_squad_body(unit, foot, float(companion.scale), Color(.86, .86, .92, 1.0), float(companion.phase))

func _draw_squad_body(unit: Dictionary, foot: Vector2, body_scale: float, tint: Color, phase: float) -> void:
	sprite_draw_scale = body_scale
	sprite_draw_tint = tint
	sprite_live_phase = phase
	_draw_combat_sprite(unit, foot, true)
	sprite_draw_scale = 1.0
	sprite_draw_tint = Color.WHITE
	sprite_live_phase = 0.0

## Squad bookkeeping from the shown HP: a body that drops out leaves a short
## fading burst. A kill that removes the whole squad drops the rear bodies too.
func _track_swarm_members() -> void:
	if simulation == null: return
	for unit_value in simulation.state.enemies:
		var unit := _presentation_unit(unit_value)
		if not swarm_unit(unit): continue
		var uid := str(unit.get("uid", ""))
		var alive := UnitState.alive(unit)
		var members := swarm_member_count(UnitState.hp_ratio(unit)) if alive else 1
		var previous := int(swarm_members.get(uid, members))
		for index in range(members - 1, previous - 1):
			swarm_drops.append({"uid": uid, "index": index, "age": 0.0})
		swarm_members[uid] = members
	swarm_drops = swarm_drops.filter(func(drop): return float(drop.age) < SWARM_DROP_DURATION)

func swarm_snapshot() -> Dictionary:
	return {"members": swarm_members.duplicate(), "drops": swarm_drops.size()}

func _draw_swarm_drop(drop: Dictionary) -> void:
	var unit := _actor_model(str(drop.get("uid", "")))
	if unit.is_empty(): return
	var t := clampf(float(drop.get("age", 0.0)) / SWARM_DROP_DURATION, 0.0, 1.0)
	var index := clampi(int(drop.get("index", 0)), 0, SWARM_COMPANIONS.size() - 1)
	var companion: Dictionary = SWARM_COMPANIONS[index]
	var foot := _ground_position(_presentation_unit(unit)) + _swarm_companion_offset(unit, index)
	var zoom := _battlefield_camera_zoom()
	var flash := 1.0 - smoothstep(0.0, .35, t)
	_draw_squad_body(unit, foot + Vector2(0, 10.0 * zoom * t), float(companion.scale) * (1.0 - .12 * t), Color(1.0, .55 + .45 * flash, .45 + .55 * flash, 1.0 - t), float(companion.phase))
	var center := foot + Vector2(0, -512.0 * _combat_sprite_scale(unit, "idle") * float(companion.scale) * .3)
	draw_arc(center, (18.0 + 46.0 * t) * zoom, 0.0, TAU, 28, Color(1.0, .74, .42, .8 * (1.0 - t)), 3.0 * zoom, true)
	for shard in range(6):
		var angle := TAU * float(shard) / 6.0 + float(index) * .5
		var from := center + Vector2(cos(angle), sin(angle)) * (10.0 + 40.0 * t) * zoom
		draw_line(from, from + Vector2(cos(angle), sin(angle)) * 10.0 * zoom, Color(1.0, .86, .6, 1.0 - t), 2.0 * zoom, true)

## The next wave's layout, or [] on the last wave.
func next_wave_layout() -> Array:
	if simulation == null: return []
	var index := simulation.wave_director.current_index + 1
	if int(next_wave_cache.get("index", -2)) != index:
		var layout: Array = BattleSimulation.wave_layout(simulation.stage, index, simulation.data) if simulation.wave_director.has_next() else []
		next_wave_cache = {"index": index, "layout": layout}
	return next_wave_cache.layout

## Waiting silhouettes stand on the walkway behind the enemy columns, a
## staggered crowd from the right edge inward.
func next_wave_silhouette_points(count: int) -> Array:
	var points: Array = []
	for index in range(count):
		var t := float(index) / maxf(1.0, float(count - 1))
		var x := lerpf(.975, .80, t) if count > 1 else .93
		var y := float(Grounding.LANE_Y[0]) - .058 + float(index % 2) * .02
		points.append(_battlefield_point(Vector2(x, y) * size))
	return points

func _draw_next_wave_preview() -> void:
	if deployment_active or simulation.state.ended or scene_transition_active() or _waiting_for_wave_contact() or _boss_present(): return
	var layout := next_wave_layout()
	if layout.is_empty(): return
	var fade := smoothstep(0.0, NEXT_WAVE_FADE, next_wave_age)
	if fade <= 0.0: return
	var points := next_wave_silhouette_points(layout.size())
	var zoom := _battlefield_camera_zoom()
	var t := float(Time.get_ticks_msec()) / 1000.0
	# A dim red haze on the walkway ties the crowd together.
	var first: Vector2 = points[0]
	var last: Vector2 = points[points.size() - 1]
	var haze_center := (first + last) * .5 + Vector2(0, 4.0 * zoom)
	var haze_width := absf(first.x - last.x) * .5 + 60.0 * zoom
	SoftSprites.draw_ellipse(self, haze_center, Vector2(haze_width * 1.15, 20.0 * zoom), Color(.55, .08, .10, .07 * fade))
	SoftSprites.draw_ellipse(self, haze_center, Vector2(haze_width, 12.0 * zoom), Color(.60, .10, .12, .10 * fade))
	var top := INF
	for index in range(layout.size() - 1, -1, -1):
		var entry: Dictionary = layout[index]
		var definition: Dictionary = entry.get("definition", {})
		var body := {"uid": "next:%d:%d" % [int(next_wave_cache.index), index], "def_id": str(entry.get("id", "")), "team": "ENEMY", "rank": str(definition.get("rank", "NORMAL")), "role": str(definition.get("role", "")), "alive": true, "hp": 1, "max_hp": 1}
		var foot: Vector2 = points[index] + Vector2(0, sin(t * 1.3 + float(index)) * 2.0 * zoom)
		# The silhouette is the idle frame of the unit, so its texture, rect and pose
		# are resolved once per entry and reused for every rim and body copy (they
		# used to go through the full sprite path five times per body).
		var frame := _combat_sprite_frame(body, true)
		if not frame.is_empty():
			var motion := _registered_sprite_pose(body)
			if swarm_unit(body):
				for companion_index in range(SWARM_COMPANIONS.size()):
					var companion: Dictionary = SWARM_COMPANIONS[companion_index]
					_draw_silhouette_body(body, frame, motion, foot + _swarm_companion_offset(body, companion_index) * SILHOUETTE_SCALE, SILHOUETTE_SCALE * float(companion.scale), float(companion.phase), fade, zoom)
			_draw_silhouette_body(body, frame, motion, foot, SILHOUETTE_SCALE, 0.0, fade, zoom)
		top = minf(top, foot.y - 512.0 * _combat_sprite_scale(body, "idle") * SILHOUETTE_SCALE * .62)
	var font := battle_font if battle_font != null else ThemeDB.fallback_font
	var readout := _readout_scale()
	# at least 9 css px, however small the screen
	var font_size := roundi(maxf(12.0 * readout, 9.0 / _damage_screen_scale()))
	var label := "NEXT WAVE ×%d" % layout.size()
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 14.0
	var center_x := minf((first.x + last.x) * .5, size.x - width * .5 - 8.0)
	var tag := Rect2(Vector2(center_x - width * .5, top - font_size - 16.0), Vector2(width, font_size + 8.0))
	var pulse := .5 + .5 * sin(t * TAU * .8)
	draw_rect(tag, Color(0.03, 0.02, 0.05, .72 * fade))
	_outline_rect(tag, Color(1.0, .38, .32, (.45 + .35 * pulse) * fade), 1.2)
	draw_string(font, tag.position + Vector2(7.0, font_size + 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, .78, .72, .9 * fade))

## One waiting body: a red rim (the idle frame drawn four times, nudged a couple
## of pixels each way) under a dark copy. `frame` is the unit's idle frame at
## scale 1; its rect scales linearly, so each squad body only rescales it.
func _draw_silhouette_body(body: Dictionary, frame: Dictionary, motion: Dictionary, foot: Vector2, body_scale: float, phase: float, fade: float, zoom: float) -> void:
	sprite_live_phase = phase
	var live := _live_motion(body, "idle")
	sprite_live_phase = 0.0
	var texture: Texture2D = frame.texture
	var base_rect: Rect2 = frame.rect
	var rect := Rect2(base_rect.position * body_scale, base_rect.size * body_scale)
	var basis_scale: Vector2 = (motion.get("scale", Vector2.ONE) as Vector2) * (live.scale as Vector2)
	var rotation := float(motion.get("rotation", 0.0))
	var skew := float(live.skew)
	var origin: Vector2 = foot + (motion.get("offset", Vector2.ZERO) as Vector2) + (live.offset as Vector2)
	var rim := 2.0 * zoom
	var rim_tint := Color(1.0, .22, .18, .34 * fade)
	for rim_offset in SILHOUETTE_RIM_OFFSETS:
		draw_set_transform_matrix(Transform2D(rotation, basis_scale, skew, origin + (rim_offset as Vector2) * rim))
		draw_texture_rect(texture, rect, false, rim_tint)
	draw_set_transform_matrix(Transform2D(rotation, basis_scale, skew, origin))
	draw_texture_rect(texture, rect, false, Color(.07, .08, .13, .9 * fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Hollow rectangle from four filled rects, stroke centred on the edge like
## `draw_rect(rect, color, false, width)`. The unfilled form is a polyline
## command, which costs the Web renderer a GPU buffer every frame.
func _outline_rect(rect: Rect2, color: Color, width: float) -> void:
	var half := width * .5
	draw_rect(Rect2(rect.position.x - half, rect.position.y - half, rect.size.x + width, width), color)
	draw_rect(Rect2(rect.position.x - half, rect.end.y - half, rect.size.x + width, width), color)
	draw_rect(Rect2(rect.position.x - half, rect.position.y + half, width, rect.size.y - width), color)
	draw_rect(Rect2(rect.end.x - half, rect.position.y + half, width, rect.size.y - width), color)

func _draw_unit_status(unit: Dictionary) -> void:
	if _wave_scene_elapsed() >= 0.0: return
	if boss_entry_elapsed >= 0.0 and str(unit.team) != "PLAYER" and boss_entry_elapsed < .95: return
	var player: bool = str(unit.team) == "PLAYER"
	var alive := UnitState.alive(unit)
	if not player and not alive: return
	var p := _ground_position(unit)
	var readout_scale := _readout_scale()
	var bar_width := (96.0 if unit.rank != "BOSS" else 150.0) * readout_scale
	var bar_height := maxf(9.0 * readout_scale, 6.0 / _damage_screen_scale())
	var head_position := _head_position(unit, p)
	var bar_origin := head_position + Vector2(-bar_width / 2.0, -18.0 * readout_scale)
	draw_rect(Rect2(bar_origin - Vector2(2, 2), Vector2(bar_width + 4, bar_height + 4)), Color(0.01, 0.02, 0.05, .72))
	draw_rect(Rect2(bar_origin, Vector2(bar_width, bar_height)), Color("351e2b"))
	draw_rect(Rect2(bar_origin, Vector2(bar_width * UnitState.hp_ratio(unit), bar_height)), Color("62e49b") if player else Color("ff6868"))
	if swarm_unit(unit):
		# One bar, three bodies: thirds mark where a body drops out, and a small
		# chip counts the bodies still standing.
		for third in [1.0 / 3.0, 2.0 / 3.0]:
			draw_line(bar_origin + Vector2(bar_width * third, 0), bar_origin + Vector2(bar_width * third, bar_height), Color(0.01, 0.02, 0.05, .85), maxf(1.5, 2.0 * readout_scale))
		var count_font := battle_font if battle_font != null else ThemeDB.fallback_font
		var count_size := roundi(maxf(11.0 * readout_scale, 8.0 / _damage_screen_scale()))
		var count_text := "×%d" % swarm_member_count(UnitState.hp_ratio(unit))
		var count_width := count_font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, count_size).x + 6.0
		var chip := Rect2(bar_origin + Vector2(bar_width + 5.0, (bar_height - count_size - 3.0) * .5), Vector2(count_width, count_size + 3.0))
		draw_rect(chip, Color(0.02, 0.03, 0.07, .86))
		_outline_rect(chip, Color("ff8a7a"), 1.0)
		draw_string(count_font, chip.position + Vector2(3.0, count_size * .92), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, count_size, Color("ffd2c8"))
	if int(unit.shield) > 0:
		var shield_ratio := minf(1.0, float(unit.shield) / maxf(1.0, float(unit.max_hp)))
		draw_rect(Rect2(bar_origin + Vector2(0, bar_height + 3.0), Vector2(bar_width * shield_ratio, bar_height * .55)), Color("6ecfff"))
	var label_font := battle_font if battle_font != null else ThemeDB.fallback_font
	var pip_size := roundi(13.0 * readout_scale)
	var pip_x := bar_origin.x
	for status_id in unit.get("statuses", {}).keys():
		if not STATUS_PIPS.has(str(status_id)): continue
		var pip: Array = STATUS_PIPS[str(status_id)]
		var text_width := label_font.get_string_size(str(pip[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, pip_size).x
		var pip_rect := Rect2(Vector2(pip_x, bar_origin.y - pip_size - 8.0), Vector2(text_width + 8.0, pip_size + 4.0))
		draw_rect(pip_rect, Color(0.02, 0.04, 0.08, .82))
		_outline_rect(pip_rect, Color(str(pip[1])), 1.5)
		draw_string(label_font, pip_rect.position + Vector2(4.0, pip_size), str(pip[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, pip_size, Color(str(pip[1])))
		pip_x += pip_rect.size.x + 4.0
	var name_size := clampi(roundi(16.0 * readout_scale), 16, 40)
	var name_width := 110.0 * readout_scale
	var name_text := unit_display_name(unit)
	var name_base := p + Vector2(-name_width / 2.0, 30.0 + name_size)
	# a dark outline keeps the name readable on the pale walkway tiles
	draw_string_outline(label_font, name_base, name_text, HORIZONTAL_ALIGNMENT_CENTER, name_width, name_size, maxi(3, roundi(3.0 * readout_scale)), Color(.02, .03, .07, .85))
	draw_string(label_font, name_base, name_text, HORIZONTAL_ALIGNMENT_CENTER, name_width, name_size, Color("dbe9ff"))

func _draw_enemy_defeat_explosion(unit: Dictionary, p: Vector2, elapsed: float) -> void:
	var duration := 1.05 if str(unit.get("rank", "")) == "BOSS" else .78
	if elapsed >= duration: return
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	var fade := 1.0 - smoothstep(.62, 1.0, progress)
	var boss := str(unit.get("rank", "")) == "BOSS"
	var center := p + Vector2(0.0, -62.0 if boss else -54.0)
	var radius := (38.0 if boss else 24.0) + (88.0 if boss else 60.0) * progress
	var primary := Color("65e7ff") if boss else Color("ff713d")
	var secondary := Color("c18cff") if boss else Color("ffd166")
	# Layered flash, ring and shards keep the death readable without a temporary
	# silhouette or an enemy-specific bitmap.
	CachedDraw.disc(self, center, radius * .56, Color(primary.r, primary.g, primary.b, .16 * fade))
	CachedDraw.disc(self, center, radius * .28, Color(1.0, .94, .72, .82 * fade))
	draw_arc(center, radius * .72, -PI, PI, 28, Color(primary.r, primary.g, primary.b, .88 * fade), 4.0 if boss else 3.0, true)
	draw_arc(center, radius, -PI * .72, PI * .84, 28, Color(secondary.r, secondary.g, secondary.b, .64 * fade), 2.2, true)
	for index in range(12 if boss else 9):
		var angle := TAU * float(index) / float(12 if boss else 9) + progress * 1.8
		var inner := center + Vector2(cos(angle), sin(angle)) * radius * .34
		var outer := center + Vector2(cos(angle), sin(angle)) * (radius * (1.08 + .20 * sin(float(index))))
		draw_line(inner, outer, Color(secondary.r, secondary.g, secondary.b, .86 * fade), 3.0 if boss else 2.2, true)
		if index % 2 == 0:
			CachedDraw.disc(self, outer, 3.0 if boss else 2.0, Color(primary.r, primary.g, primary.b, .78 * fade))
	# A dim floor ember remains briefly, then vanishes with the burst.
	_draw_ellipse_polygon(p + Vector2(0, 1), Vector2(42.0 if boss else 28.0, 7.0), Color(secondary.r, secondary.g, secondary.b, .22 * fade))

## Which texture a unit shows right now and where it lands, relative to the
## planted foot: {texture, rect, animation, elapsed, down}, or {} when the unit
## has no authored art. The rect scales linearly with `sprite_draw_scale`, so a
## caller drawing the same unit several times can resolve it once.
func _combat_sprite_frame(unit: Dictionary, alive: bool) -> Dictionary:
	var uid := str(unit.get("uid", ""))
	var memo := _frame_memo if alive else _frame_memo_down
	var frame: Dictionary
	if _draw_memo_active and not uid.is_empty() and memo.has(uid):
		frame = memo[uid]
	else:
		frame = _compute_combat_sprite_frame(unit, alive)
		if _draw_memo_active and not uid.is_empty(): memo[uid] = frame
	if frame.is_empty() or sprite_draw_scale == 1.0: return frame
	# Companions and their fading copies share the authored frame. Only the
	# rectangle varies; each copy keeps its own tint and live motion phase.
	var scaled := frame.duplicate()
	var rect: Rect2 = frame.rect
	scaled.rect = Rect2(rect.position * sprite_draw_scale, rect.size * sprite_draw_scale)
	return scaled

func _compute_combat_sprite_frame(unit: Dictionary, alive: bool) -> Dictionary:
	var character_id := str(unit.def_id)
	var has_animation_pack := sprite_pack_ready and sprite_library.supports_character(character_id)
	var track: Dictionary = animation_tracks.get(unit.uid, {"name": "idle", "elapsed": 0.0})
	var animation_name := "down" if not alive else str(track.get("name", "idle"))
	var animation_elapsed := float(track.get("elapsed", 0.0))
	var has_down_pose := not alive and str(unit.get("team", "")) == "PLAYER" and sprite_library.has_down_pose(character_id)
	var has_signature_animation := not has_down_pose and signature_sprite_pack_ready and sprite_library.has_signature_animation(character_id, animation_name)
	# A high-density candidate is independently complete. It must not silently
	# fall through to a tiny code placeholder merely because an isolated QA shot
	# (or a future selective preloader) did not also attach the compact baseline.
	if not has_down_pose and not has_animation_pack and not has_signature_animation and not fallback_combat_previews.has(character_id):
		return {}
	var texture: Texture2D = sprite_library.down_pose_texture(character_id) if has_down_pose else (sprite_library.texture_at(character_id, animation_name, animation_elapsed) if has_animation_pack else fallback_combat_previews.get(character_id))
	var action_sample := _action_frame_sample(unit)
	if not action_sample.is_empty(): texture = action_sample.texture
	var signature_frame_info: Dictionary = {}
	# Use the 384px candidate only for the reference pair's always-visible idle
	# and high-impact action states. This keeps the on-screen silhouette crisp at
	# 1.25x camera zoom without loading an expensive 512px atlas for every unit.
	if has_signature_animation and action_sample.is_empty():
		signature_frame_info = sprite_library.signature_frame_info_at(character_id, animation_name, animation_elapsed)
		var signature_texture = signature_frame_info.get("texture", null)
		if signature_texture != null:
			texture = signature_texture as Texture2D
	if texture == null:
		return {}
	var scale := _combat_sprite_scale(unit, animation_name)
	# Runtime atlases use a smaller canvas but retain the immutable 512px
	# gameplay anchor.  Scale from the authored canvas so Web compaction never
	# shrinks a real character back into a code-placeholder silhouette.
	var destination_size := Vector2(512.0, 512.0) * scale
	var destination_rect := Rect2(Vector2(-256.0 * scale, -512.0 * .88 * scale), destination_size)
	if not action_sample.is_empty():
		var action_rect: Array = action_sample.logical_rect
		destination_rect.position += Vector2(float(action_rect[0]),float(action_rect[1])) * 2.0 * scale
		destination_rect.size = Vector2(float(action_rect[2]),float(action_rect[3])) * 2.0 * scale
	if not signature_frame_info.is_empty():
		# R5's atlas pages hold alpha-tight crops, not a blank 384px rectangle for
		# every frame. Reconstruct the crop in its immutable logical canvas here;
		# this retains the original planted foot, head bar and mirrored motion while
		# removing otherwise permanent transparent GPU pages.
		var logical_rect_value = signature_frame_info.get("logical_rect", Rect2(Vector2.ZERO, Vector2(384.0, 384.0)))
		var logical_canvas_value = signature_frame_info.get("logical_canvas_size", Vector2(384.0, 384.0))
		if logical_rect_value is Rect2 and logical_canvas_value is Vector2:
			var logical_rect: Rect2 = logical_rect_value
			var logical_canvas: Vector2 = logical_canvas_value
			if logical_canvas.x > 0.0 and logical_canvas.y > 0.0:
				var canvas_scale := Vector2(destination_size.x / logical_canvas.x, destination_size.y / logical_canvas.y)
				destination_rect.position += logical_rect.position * canvas_scale
				destination_rect.size = logical_rect.size * canvas_scale
	return {"texture": texture, "rect": destination_rect, "animation": animation_name, "elapsed": animation_elapsed, "down": has_down_pose}

func _draw_combat_sprite(unit: Dictionary, p: Vector2, alive: bool) -> bool:
	var frame := _combat_sprite_frame(unit, alive)
	if frame.is_empty(): return false
	var texture: Texture2D = frame.texture
	var destination_rect: Rect2 = frame.rect
	var animation_name: String = frame.animation
	var animation_elapsed: float = frame.elapsed
	var has_down_pose: bool = frame.down
	var character_id := str(unit.def_id)
	var flash_tint := Color.WHITE
	if hit_flash_frames.has(unit.uid): flash_tint = HitFeedback.WHITE_FLASH_TINT
	elif unit_flash.has(unit.uid): flash_tint = Color(1.0, .72, .72, 1.0)
	var modulate := flash_tint * sprite_draw_tint
	if has_down_pose:
		# The keyed SD pose is already planted on the fixed logical 512px canvas.
		# Bypass attack/down rotations and afterimages so the final prone drawing
		# remains stable for the rest of the encounter.
		draw_set_transform(p, 0.0, Vector2.ONE)
		draw_texture_rect(texture, destination_rect, false, modulate)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return true
	var motion := _registered_sprite_pose(unit)
	var motion_offset: Vector2 = motion.get("offset", Vector2.ZERO)
	var motion_scale: Vector2 = motion.get("scale", Vector2.ONE)
	var duration := _action_duration(character_id, animation_name)
	var progress := clampf(animation_elapsed / maxf(.01, duration), 0.0, 1.0)
	var afterimages := ActorChoreography.afterimage_samples(str(unit.get("role", "")), animation_name, str(unit.get("team", "")), progress)
	# Squad bodies and silhouettes skip afterimages; the main body carries them.
	if sprite_draw_scale < 1.0: afterimages = []
	var ghost_tint := _skill_color(unit, "ultimate" if animation_name == "ultimate" else "normal")
	for sample_value in afterimages:
		var sample: Dictionary = sample_value
		var ghost_offset: Vector2 = sample.get("offset", Vector2.ZERO) * _battlefield_camera_zoom()
		ghost_tint.a = float(sample.get("alpha", 0.0))
		draw_set_transform(p + motion_offset + ghost_offset, float(motion.get("rotation", 0.0)) + float(sample.get("rotation", 0.0)), motion_scale)
		draw_texture_rect(texture, destination_rect, false, ghost_tint)
	# Transform around the planted foot. It makes existing authored key poses
	# read as anticipation → lunge → recoil instead of a static atlas flip; the
	# model and event log remain untouched. The live layer adds breathing and a
	# foot-pinned sway on top (Live2D-style idle), so no unit stands frozen.
	var live := _live_motion(unit, animation_name)
	draw_set_transform_matrix(Transform2D(float(motion.get("rotation", 0.0)), motion_scale * (live.scale as Vector2), float(live.skew), p + motion_offset + (live.offset as Vector2)))
	draw_texture_rect(texture, destination_rect, false, modulate)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true

## Presentation-only idle life for every combat sprite. Breathing stretches the
## body upward from the feet, a skew sways the upper body while the feet stay
## planted, and bosses hover with a slower, heavier rhythm. Each unit has its
## own phase; the layer fades to a third during authored action poses.
func _live_motion(unit: Dictionary, animation_name: String) -> Dictionary:
	var t := float(Time.get_ticks_msec()) / 1000.0
	var phase := float(absi(hash(str(unit.get("uid", "")))) % 1000) / 1000.0 * TAU + sprite_live_phase
	var boss := str(unit.get("rank", "")) == "BOSS"
	var facing := 1.0 if str(unit.get("team", "")) == "PLAYER" else -1.0
	var weight := 1.0 if animation_name in ["idle", "move", "victory"] else .35
	var breath := sin(t * TAU * (.34 if boss else .52) + phase)
	var sway := sin(t * TAU * (.19 if boss else .31) + phase * 1.7)
	var hover := sin(t * TAU * .42 + phase) * -7.0 * _battlefield_camera_zoom() if boss else 0.0
	return {
		"scale": Vector2(1.0 - breath * .007 * weight, 1.0 + breath * (.022 if boss else .017) * weight),
		"skew": sway * (.020 if boss else .034) * weight * facing,
		"offset": Vector2(0.0, hover),
	}

static func combat_motion_snapshot(team: String, animation_name: String, elapsed: float, duration: float, role := "") -> Dictionary:
	## The source packs preserve the silhouette; this local pose layer supplies
	## the readable weight transfer that a 12fps key-pose set needs on mobile.
	## Values are anchored at the foot and never affect collision, targeting, or
	## the authoritative simulation clock.
	var forward := 1.0 if team == "PLAYER" else -1.0
	var safe_duration := maxf(.01, duration)
	var t := clampf(elapsed / safe_duration, 0.0, 1.0)
	var result := {"offset": Vector2.ZERO, "rotation": 0.0, "scale": Vector2.ONE}
	match animation_name:
		"idle":
			var idle_wave := sin(elapsed * TAU * .78)
			result.offset = Vector2(0.0, -1.5 + idle_wave * 1.7)
			result.rotation = idle_wave * .012 * forward
			result.scale = Vector2(1.0 + idle_wave * .006, 1.0 - idle_wave * .004)
		"move":
			var stride := sin(elapsed * TAU * 2.0)
			result.offset = Vector2(forward * stride * 5.0, -absf(stride) * 7.0)
			result.rotation = forward * stride * .048
			result.scale = Vector2(1.015, .985)
		"basic_attack":
			var windup := clampf(t / .42, 0.0, 1.0)
			var strike := clampf((t - .34) / .22, 0.0, 1.0)
			var recoil := clampf((t - .56) / .34, 0.0, 1.0)
			var lunge := sin(strike * PI) * (1.0 - recoil * .28)
			result.offset = Vector2(forward * (-16.0 * windup * (1.0 - strike) + 36.0 * lunge), -5.5 * lunge)
			result.rotation = forward * (-.098 * windup * (1.0 - strike) + .145 * lunge - .060 * recoil)
			result.scale = Vector2(1.0 + .048 * lunge, 1.0 - .036 * lunge)
		"normal_skill":
			var charge := clampf(t / .50, 0.0, 1.0)
			var release := clampf((t - .43) / .30, 0.0, 1.0)
			var burst := sin(release * PI)
			result.offset = Vector2(forward * (-20.0 * charge * (1.0 - release) + 31.0 * burst), -16.0 * sin(t * PI))
			result.rotation = forward * (-.125 * charge * (1.0 - release) + .140 * burst)
			result.scale = Vector2(1.0 + .078 * sin(t * PI), 1.0 + .034 * sin(t * PI))
		"ultimate":
			var preparation := clampf(t / .36, 0.0, 1.0)
			var drive := clampf((t - .30) / .34, 0.0, 1.0)
			var release := sin(drive * PI)
			var settle := clampf((t - .68) / .32, 0.0, 1.0)
			result.offset = Vector2(forward * (-32.0 * preparation * (1.0 - drive) + 48.0 * release * (1.0 - settle * .58)), -23.0 * sin(t * PI))
			result.rotation = forward * (-.180 * preparation * (1.0 - drive) + .220 * release - .070 * settle)
			result.scale = Vector2(1.0 + .120 * sin(t * PI), 1.0 - .040 * preparation + .030 * release)
		"hit":
			var kick := sin(t * PI)
			result.offset = Vector2(-forward * 25.0 * kick, 3.5 * kick)
			result.rotation = -forward * .135 * kick
			result.scale = Vector2(1.0 - .070 * kick, 1.0 + .040 * kick)
		"down":
			var fall := clampf(t, 0.0, 1.0)
			result.offset = Vector2(-forward * 6.0 * fall, 3.0 * fall)
			result.rotation = -forward * .050 * fall
		"victory":
			var lift := absf(sin(elapsed * PI * 2.0))
			result.offset = Vector2(0.0, -10.0 * lift)
			result.rotation = forward * sin(elapsed * PI * 2.0) * .05
	result = ActorChoreography.adapt_pose(result, team, role, animation_name, t)
	if animation_name in ["basic_attack", "normal_skill", "ultimate", "hit"]:
		# Late recoil must settle before the track returns to idle, not retain
		# a rotation/squash until the final frame and snap upright in one tick.
		var recovery := smoothstep(.78, 1.0, t)
		result.offset = (result.offset as Vector2).lerp(Vector2.ZERO, recovery)
		result.rotation = lerpf(float(result.rotation), 0.0, recovery)
		result.scale = (result.scale as Vector2).lerp(Vector2.ONE, recovery)
	return result

func _draw_player_sd(p: Vector2, color: Color, role: String, alive: bool) -> void:
	# Code-native DEV_PLACEHOLDER. The player silhouette is explicitly an adult
	# woman: four-head proportions, long legs/hair, mature waist/hip line, bare
	# shoulders and midriff, with opaque chest/groin coverage.
	var skin := Color("f3c2ad") if alive else Color("806960")
	var hair := color.darkened(.38)
	var suit := color.darkened(.08)
	var trim := color.lightened(.34)
	# Long hair and ponytail behind the body.
	CachedDraw.disc(self, p + Vector2(11, -86), 29, hair)
	draw_line(p + Vector2(24, -82), p + Vector2(38, -18), hair, 18.0, true)
	CachedDraw.disc(self, p + Vector2(40, -14), 10, hair)
	# Long legs and opaque thigh boots.
	draw_line(p + Vector2(-13, -25), p + Vector2(-15, 15), skin, 13.0, true)
	draw_line(p + Vector2(13, -25), p + Vector2(15, 15), skin, 13.0, true)
	draw_rect(Rect2(p + Vector2(-24, -8), Vector2(16, 31)), suit)
	draw_rect(Rect2(p + Vector2(8, -8), Vector2(16, 31)), suit)
	# Opaque high-cut hip armor, narrow exposed waist, opaque chest panel.
	var hips := PackedVector2Array([p + Vector2(-27, -34), p + Vector2(27, -34), p + Vector2(18, -10), p + Vector2(-18, -10)])
	draw_colored_polygon(hips, suit)
	draw_rect(Rect2(p + Vector2(-14, -49), Vector2(28, 17)), skin)
	var torso := PackedVector2Array([p + Vector2(-25, -74), p + Vector2(25, -74), p + Vector2(15, -49), p + Vector2(-15, -49)])
	draw_colored_polygon(torso, suit)
	draw_line(p + Vector2(-22, -68), p + Vector2(-31, -40), skin, 9.0, true)
	draw_line(p + Vector2(22, -68), p + Vector2(31, -40), skin, 9.0, true)
	draw_line(p + Vector2(-20, -71), p + Vector2(0, -54), trim, 3.0, true)
	draw_line(p + Vector2(20, -71), p + Vector2(0, -54), trim, 3.0, true)
	# Player units deploy left and look toward lower-right in a readable 3/4
	# view: the near/right eye is larger and the nose/chin project rightward.
	CachedDraw.disc(self, p + Vector2(4, -101), 27, hair)
	CachedDraw.disc(self, p + Vector2(5, -96), 22, skin)
	CachedDraw.disc(self, p + Vector2(1, -99), 2.3, Color("17243b"))
	CachedDraw.disc(self, p + Vector2(14, -97), 3.7, Color("17243b"))
	draw_line(p + Vector2(21, -94), p + Vector2(25, -91), skin.darkened(.28), 2.0, true)
	draw_line(p + Vector2(9, -86), p + Vector2(18, -88), Color("a65b67"), 2.0, true)
	draw_line(p + Vector2(-17, -112), p + Vector2(23, -117), hair.lightened(.18), 7.0, true)
	# Readable role prop at combat scale.
	if role == "GUARDIAN":
		# The shield is forward/right toward the enemy and overlaps the hand;
		# no detached or independently floating prop is permitted.
		draw_line(p + Vector2(20, -66), p + Vector2(35, -54), skin, 10.0, true)
		var shield := PackedVector2Array([p + Vector2(28, -79), p + Vector2(51, -87), p + Vector2(67, -70), p + Vector2(64, -23), p + Vector2(45, -7), p + Vector2(25, -29)])
		draw_colored_polygon(shield, Color("246f79"))
		draw_polyline(shield + PackedVector2Array([shield[0]]), Color("8de4d5"), 4.0, true)
		CachedDraw.disc(self, p + Vector2(34, -55), 5.0, Color("f3c2ad"))
	elif role == "MEDIC":
		draw_arc(p + Vector2(37, -50), 18, 0, TAU, 24, Color("8ff5df"), 5.0, true)
	elif role == "ARTILLERY":
		draw_rect(Rect2(p + Vector2(26, -59), Vector2(42, 10)), Color("d9e7ee"))
	elif role == "VANGUARD":
		draw_line(p + Vector2(27, -50), p + Vector2(55, -82), Color("f4d27c"), 7.0, true)
	elif role == "SPECIALIST":
		draw_arc(p + Vector2(0, -114), 34, PI, TAU, 20, trim, 4.0, true)

func _draw_nonhuman_enemy(p: Vector2, color: Color, role: String, alive: bool) -> void:
	# Genderless nonhuman machine silhouette. Enemies deploy right and face
	# screen-left: the snout, visor focus, weapon, and leading arm all point left.
	var metal := color if alive else color.darkened(.6)
	var body := PackedVector2Array([p + Vector2(-37, -56), p + Vector2(25, -61), p + Vector2(31, 17), p + Vector2(-25, 20)])
	draw_colored_polygon(body, metal.darkened(.12))
	var head := PackedVector2Array([p + Vector2(-48, -83), p + Vector2(-22, -105), p + Vector2(20, -99), p + Vector2(30, -72), p + Vector2(12, -61), p + Vector2(-29, -65)])
	draw_colored_polygon(head, metal)
	draw_rect(Rect2(p + Vector2(-38, -87), Vector2(31, 8)), Color("ff666f"))
	CachedDraw.disc(self, p + Vector2(-40, -83), 4.0, Color("ffd166"))
	draw_line(p + Vector2(-27, -37), p + Vector2(-55, -2), metal.lightened(.15), 12.0, true)
	draw_line(p + Vector2(22, -35), p + Vector2(45, 8), metal.lightened(.15), 11.0, true)
	if role in ["RANGED", "AREA", "DEBUFFER"]:
		draw_rect(Rect2(p + Vector2(-82, -51), Vector2(54, 13)), Color("aebed1"))
		draw_rect(Rect2(p + Vector2(-88, -48), Vector2(8, 7)), Color("ffad66"))

func _placeholder_pose_offset(unit: Dictionary) -> Vector2:
	var track: Dictionary = animation_tracks.get(unit.uid, {"name": "idle", "elapsed": 0.0})
	var animation_name := str(track.get("name", "idle"))
	var elapsed := float(track.get("elapsed", 0.0))
	var direction := 1.0 if str(unit.team) == "PLAYER" else -1.0
	var duration := sprite_library.duration(str(unit.get("def_id", "")), animation_name) if sprite_pack_ready else 0.75
	var progress := clampf(elapsed / maxf(duration, 0.01), 0.0, 1.0)
	var pulse := sin(progress * PI)
	match animation_name:
		"basic_attack":
			return Vector2(direction * 18.0 * pulse, -4.0 * pulse)
		"normal_skill":
			return Vector2(direction * 11.0 * pulse, -12.0 * pulse)
		"ultimate":
			return Vector2(direction * 27.0 * pulse, -16.0 * pulse)
		"hit":
			return Vector2(-direction * 13.0 * pulse, 2.0 * pulse)
		"victory":
			return Vector2(0.0, -10.0 * absf(sin(elapsed * PI * 3.0)))
		_:
			return Vector2.ZERO

func _draw_ellipse_polygon(center: Vector2, radii: Vector2, color: Color) -> void:
	if _ellipse_mesh == null:
		var points := PackedVector2Array()
		for i in range(24):
			var angle := TAU * i / 24.0
			points.append(Vector2(cos(angle), sin(angle)))
		var kit := MeshKit.new()
		kit.fill(points, Color.WHITE)
		_ellipse_mesh = kit.build()
	draw_mesh(_ellipse_mesh, null, Transform2D(Vector2(radii.x, 0), Vector2(0, radii.y), center), color)

func _unit_pos(unit: Dictionary) -> Vector2:
	var uid := str(unit.get("uid", ""))
	if _draw_memo_active and not uid.is_empty() and _position_memo.has(uid): return _position_memo[uid]
	var point := _battlefield_point((engagement_positions[uid] as Vector2) * size) if engagement_positions.has(uid) else _battlefield_point(Grounding.cell_point(float(unit.get("col", 0)), float(unit.get("lane", 1))) * size)
	if _draw_memo_active and not uid.is_empty(): _position_memo[uid] = point
	return point

func _projectile_origin(unit: Dictionary) -> Vector2:
	var track: Dictionary = animation_tracks.get(str(unit.get("uid", "")), {"name": "idle", "elapsed": 0.0})
	var action := str(track.get("name", "idle"))
	var entity_id := str(unit.get("def_id", ""))
	var duration := _action_duration(entity_id, action)
	var progress := clampf(float(track.get("elapsed", 0.0)) / maxf(.01, duration), 0.0, 1.0)
	return _posed_actor_anchor(unit, ActorChoreography.action_anchor(str(unit.get("role", "")), str(unit.get("team", "")), action, progress))

func _projectile_target(unit: Dictionary) -> Vector2:
	return _posed_actor_anchor(unit, Vector2(0, -72))

func _posed_actor_anchor(unit: Dictionary, local_anchor: Vector2) -> Vector2:
	var foot := _ground_position(unit)
	var motion := _registered_sprite_pose(unit)
	# `motion.scale.x` may contain source mirroring. The supplied local anchor is
	# already expressed in desired world-facing direction, so only its magnitude
	# participates in the attachment transform.
	var anchor_scale: Vector2 = motion.get("scale", Vector2.ONE)
	anchor_scale.x = absf(anchor_scale.x)
	return foot + (motion.get("offset", Vector2.ZERO) as Vector2) + (local_anchor * anchor_scale).rotated(float(motion.get("rotation", 0.0)))

func _actor_travel_offset(unit: Dictionary) -> Vector2:
	var track: Dictionary = animation_tracks.get(str(unit.get("uid", "")), {})
	var target_uid := str(track.get("target_uid", ""))
	if target_uid.is_empty() or simulation == null: return Vector2.ZERO
	var target := _actor_model(target_uid)
	if target.is_empty() or str(target.get("team", "")) == str(unit.get("team", "")): return Vector2.ZERO
	var action := str(track.get("name", "idle"))
	var entity_id := str(unit.get("def_id", ""))
	var duration := _action_duration(entity_id, action)
	if action_frames.has_action(entity_id, action) and str(unit.get("role", "")) in ActorChoreography.MELEE_ROLES:
		# Keep each actor's readable formation between attacks. Only the attacker
		# closes the gap during its authored strike, then returns to its own lane.
		var elapsed := float(track.get("elapsed", 0.0))
		var contact := 1.10 if action == "ultimate" else .43
		var approach := smoothstep(contact-.26, contact-.015, elapsed)
		var recovery := 1.0-smoothstep(contact+.10, duration, elapsed)
		# Melee reach is one or two grid steps, so the strike closes on the
		# target's own cell (diagonals included) and stops a body-width short.
		var start := _unit_pos(unit)
		var finish := _unit_pos(target)
		var delta := finish - start
		var distance := delta.length()
		if distance < 1.0: return Vector2.ZERO
		var gap := 72.0*_battlefield_camera_zoom()
		var reach := maxf(0.0, distance-gap)
		return delta/distance*reach*approach*recovery
	var travel := ActorChoreography.step_offset(str(unit.get("role", "")), action, float(track.get("elapsed", 0.0)), duration, _unit_pos(target) - _unit_pos(unit)) * _battlefield_camera_zoom()
	# A backdrop platform/moat is not a traversable diagonal plane. Keep each
	# side's approach on its own stone elevation instead of sliding over the gap.
	if _boss_present(): travel.y = 0.0
	return travel

func _entry_offset(unit: Dictionary) -> Vector2:
	if boss_entry_elapsed >= 0.0 and boss_entry_uids.has(str(unit.uid)):
		return Vector2(0, -size.y * 1.1 * (1.0 - smoothstep(.95, 1.95, boss_entry_elapsed)))
	if _wave_scene_elapsed() >= 0.0 and str(unit.team) == "ENEMY":
		return Vector2(size.x * .28 * (1.0 - smoothstep(1.0, 1.90, _wave_scene_elapsed())), 0)
	var progress := clampf(float(entry_tracks.get(unit.uid, 1.0)), 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	var direction := -1.0 if str(unit.team) == "PLAYER" else 1.0
	return Vector2(direction * 150.0 * (1.0 - eased), 0.0)

## The registered pose is read by shadows, the body, the head/HUD anchors and the
## effects, five or more times per unit per frame; inside one `_draw()` pass the
## inputs cannot change, so the first answer is reused (callers never mutate it).
func _registered_sprite_pose(unit: Dictionary) -> Dictionary:
	if not _draw_memo_active: return _compute_registered_sprite_pose(unit)
	var uid := str(unit.get("uid", ""))
	if uid.is_empty(): return _compute_registered_sprite_pose(unit)
	var memo := _pose_memo if UnitState.alive(unit) else _pose_memo_down
	if memo.has(uid): return memo[uid]
	var pose := _compute_registered_sprite_pose(unit)
	memo[uid] = pose
	return pose

func _compute_registered_sprite_pose(unit: Dictionary) -> Dictionary:
	var id := str(unit.get("def_id", ""))
	if not UnitState.alive(unit) and str(unit.get("team", "")) == "PLAYER" and sprite_library.has_down_pose(id):
		# Static keyed prone art owns its own planted bottom edge. Returning an
		# identity pose avoids applying the legacy down-frame rotation/contact data.
		return {"offset": Vector2.ZERO, "scale": Vector2.ONE, "rotation": 0.0, "contact_x": 0.0, "bottom_y": 0.0}
	var track: Dictionary = animation_tracks.get(str(unit.get("uid", "")), {"name": "idle", "elapsed": 0.0})
	var action := "down" if not UnitState.alive(unit) else str(track.get("name", "idle"))
	var elapsed := float(track.get("elapsed", 0.0))
	var signature := signature_sprite_pack_ready and sprite_library.has_signature_animation(id, action)
	var has_ordinary := sprite_pack_ready and sprite_library.supports_character(id)
	var duration := sprite_library.duration(id, action) if has_ordinary else (sprite_library.signature_duration(id, action) if signature else .75)
	var source_right := sprite_library.signature_source_faces_right(id) if signature else sprite_library.source_faces_right(id)
	var mirrored := (str(unit.get("team", "")) == "PLAYER") != source_right
	# HD boss pages have 512px canvases but share the same normalized contacts.
	# Pixel density must not switch an actor back to compact grounding metadata.
	var kind := "signature" if signature else ("full" if sprite_library.full_density_bytes_by_entity.has(id) else "compact")
	var points := Grounding.contacts(kind, id, action, elapsed)
	var motion := combat_motion_snapshot(str(unit.get("team", "")), action, elapsed, duration, str(unit.get("role", "")))
	var action_sample := _action_frame_sample(unit)
	if not action_sample.is_empty():
		# These frames contain actual joint/weapon motion. Do not squash or rotate
		# them as if they were the previous single-pose surrogate animation.
		points = action_sample.contacts
		mirrored = false # New rows already face each team's opponent.
		motion = {"offset": Vector2.ZERO, "scale": Vector2.ONE, "rotation": 0.0}
	if unit_flash.has(str(unit.get("uid", ""))):
		var reaction_span: Dictionary = unit_flash_span.get(str(unit.get("uid", "")), {})
		motion = ActorChoreography.add_hit_reaction(motion, str(unit.get("team", "")), float(unit_flash.get(str(unit.get("uid", "")), 0.0)), float(reaction_span.get("duration", .14)), float(reaction_span.get("power", 1.0)))
	motion.offset = (motion.offset as Vector2) * _battlefield_camera_zoom()
	return Grounding.register_pose(motion, points, _combat_sprite_scale(unit, action), mirrored)

func _action_duration(id: String, action: String) -> float:
	if action_frames.has_action(id, action): return ActionFrames.duration(action)
	if sprite_library.supports_character(id): return sprite_library.duration(id, action)
	if sprite_library.has_signature_animation(id, action): return sprite_library.signature_duration(id, action)
	return .75

func _action_frame_sample(unit: Dictionary) -> Dictionary:
	if not UnitState.alive(unit): return {}
	var uid := str(unit.get("uid", ""))
	if _draw_memo_active and not uid.is_empty() and _action_sample_memo.has(uid): return _action_sample_memo[uid]
	var track: Dictionary = animation_tracks.get(uid, {})
	var sample := action_frames.sample(str(unit.get("def_id", "")), str(track.get("name", "idle")), float(track.get("elapsed", 0.0)), str(unit.get("role", "")) in ActorChoreography.MELEE_ROLES)
	if _draw_memo_active and not uid.is_empty(): _action_sample_memo[uid] = sample
	return sample

func action_motion_snapshot(unit: Dictionary) -> Dictionary:
	var sample := _action_frame_sample(unit)
	var track: Dictionary = animation_tracks.get(str(unit.get("uid", "")), {})
	return {"redrawn": not sample.is_empty(), "frame": int(sample.get("frame_index", -1)), "action": str(track.get("name", "idle")), "elapsed": float(track.get("elapsed", 0.0))}

func ground_contact_snapshot(unit: Dictionary) -> Dictionary:
	var pose := _registered_sprite_pose(unit)
	var foot := _ground_position(unit)
	return {"floor_position": [foot.x, foot.y], "contact_error": float(pose.get("bottom_y", INF)),
		"body_scale": _combat_sprite_scale(unit, "idle"), "backdrop": "boss" if _boss_present() else "normal",
		"shadow_ground_y": foot.y, "opaque_contact_ground_y": foot.y + float(pose.get("bottom_y", INF))}

func _head_position(unit: Dictionary, foot_position: Vector2) -> Vector2:
	var character_id := str(unit.get("def_id", ""))
	var track: Dictionary = animation_tracks.get(str(unit.get("uid", "")), {"name": "idle", "elapsed": 0.0})
	var action := "down" if not UnitState.alive(unit) else str(track.get("name", "idle"))
	if not UnitState.alive(unit) and str(unit.get("team", "")) == "PLAYER" and sprite_library.has_down_pose(character_id):
		var down_anchor := sprite_library.down_pose_head_anchor(character_id)
		var down_local := (down_anchor - Vector2(.5, .88)) * 512.0 * _combat_sprite_scale(unit, "down")
		return foot_position + down_local
	var signature := signature_sprite_pack_ready and sprite_library.has_signature_animation(character_id, action)
	if signature or (sprite_pack_ready and sprite_library.supports_character(character_id)):
		var anchor := sprite_library.signature_head_anchor(character_id) if signature else sprite_library.head_anchor(character_id)
		var action_sample := _action_frame_sample(unit)
		if not action_sample.is_empty(): anchor = Vector2(float(action_sample.head[0]), float(action_sample.head[1]))
		var motion := _registered_sprite_pose(unit)
		var local := (anchor - Vector2(.5, .88)) * 512.0 * _combat_sprite_scale(unit, action)
		return foot_position + (motion.offset as Vector2) + (local * (motion.scale as Vector2)).rotated(float(motion.rotation))
	if str(unit.get("rank", "")) == "BOSS": return foot_position + Vector2(0, -158)
	return foot_position + Vector2(0, -128)

func _combat_sprite_scale(unit: Dictionary, _animation_name: String) -> float:
	if not _draw_memo_active: return _compute_combat_sprite_scale(unit)
	var uid := str(unit.get("uid", ""))
	if uid.is_empty(): return _compute_combat_sprite_scale(unit)
	if _scale_memo.has(uid): return _scale_memo[uid]
	var body_scale := _compute_combat_sprite_scale(unit)
	_scale_memo[uid] = body_scale
	return body_scale

func _compute_combat_sprite_scale(unit: Dictionary) -> float:
	var character_id := str(unit.get("def_id", ""))
	# Portrait combat needs a materially larger actor read than the old desktop
	# baseline. The value is still bounded by the five-unit formation above and
	# applies to source-derived sprites only; simulation geometry never changes.
	var portrait := size.y > size.x
	var scale := (0.76 if portrait else 0.44) if str(unit.get("team", "")) == "PLAYER" else (0.74 if portrait else 0.42)
	# The signature group's transparent 384px cells preserve more authored detail
	# than the compact 128px atlas, so grant each reviewed unit a mobile-safe stage
	# increase. The same helper drives the body and head/HUD anchor, keeping
	# readable encounter scale without changing a simulation position or target.
	# Density and residency must never change physical body size. The old
	# action-dependent branch shrank ordinary attacks by 23 percent, then popped
	# back to the larger signature idle pose.
	if SIGNATURE_SCALE_MULTIPLIERS.has(character_id):
		var multiplier := float(SIGNATURE_SCALE_MULTIPLIERS.get(character_id, 1.0))
		# R4 source cells are denser, not an excuse to overwhelm the formation. A
		# portrait-specific cap keeps the actor visibly dominant over the 64px HUD.
		if portrait:
			multiplier = minf(multiplier, 1.35)
		scale *= multiplier
	if str(unit.get("team", "")) != "PLAYER":
		# Horizontal beasts occupied barely half their logical canvas. Normalize
		# by the authored head/foot span so padding cannot make them toy-sized.
		var head := sprite_library.head_anchor(character_id)
		var body_span := clampf(0.88 - head.y, 0.48, 0.85)
		var rank := str(unit.get("rank", "NORMAL"))
		# Squads share one grid cell each, so regular bodies stay inside a cell
		# instead of burying the next lane; the boss keeps its arena presence.
		var height := 175.0 if rank == "NORMAL" else (400.0 if rank == "BOSS" else 215.0)
		if portrait: height *= 1.45
		scale = maxf(scale if rank == "BOSS" else scale * .78, height / (512.0 * body_span))
		scale = minf(scale, size.x * (0.38 if rank == "BOSS" else 0.185) / 512.0)
	else:
		scale = minf(scale * 0.82, size.x * 0.125 / 512.0)
	return scale * _battlefield_camera_zoom()

func _battlefield_camera_zoom() -> float:
	return _draw_zoom if _draw_memo_active else _compute_battlefield_camera_zoom()

func _compute_battlefield_camera_zoom() -> float:
	if _wave_scene_elapsed() >= 0.0:
		return float(WaveTransition.sample(_wave_scene_elapsed(), boss_entry_elapsed >= 0.0).zoom)
	return presentation_director.battlefield_zoom() * field_zoom

func _battlefield_offset() -> Vector2:
	return _draw_offset if _draw_memo_active else _compute_battlefield_offset()

func _wave_focus_anchor(uid: String, fallback: Vector2) -> Vector2:
	var unit := _actor_model(uid)
	if unit.is_empty(): return fallback
	var ground: Vector2 = engagement_positions.get(uid, Grounding.cell_point(float(unit.get("col", 0)), float(unit.get("lane", 1))))
	return ground * size + Vector2(0, -200.0 if str(unit.get("rank", "")) == "BOSS" else -95.0)

func _compute_battlefield_offset() -> Vector2:
	if _wave_scene_elapsed() >= 0.0:
		var camera := WaveTransition.camera(_wave_scene_elapsed(), boss_entry_elapsed >= 0.0, size,
			_wave_focus_anchor(wave_entry_enemy_uid, size * Vector2(.75, .6)),
			_wave_focus_anchor(wave_entry_ally_uid, size * Vector2(.25, .6)))
		return camera.offset
	return presentation_director.battlefield_offset() + field_offset

func _battlefield_point(point: Vector2) -> Vector2:
	var center := size * 0.5
	return center + (point - center) * _battlefield_camera_zoom() + _battlefield_offset()

func _battlefield_rect(rect: Rect2) -> Rect2:
	var zoom := _battlefield_camera_zoom()
	var center := size * 0.5
	return Rect2(center + (rect.position - center) * zoom + _battlefield_offset(), rect.size * zoom)

# -- Field direction hooks (phase 3) ------------------------------------------------
# Presentation only: a BattleFieldStage reads positions and writes poses and camera
# here. The simulation, its events and the result snapshot are never touched.

func _reset_field_direction() -> void:
	field_aftermath_state = "idle"
	if field_overlay != null and is_instance_valid(field_overlay):
		field_overlay.queue_free()
	field_overlay = null
	field_release()

func _field_aftermath_holds() -> bool:
	if field_aftermath_state == "done":
		return false
	if field_aftermath_state == "playing":
		return true
	field_aftermath_state = "done"
	if not field_aftermath_enabled or skip_in_progress or simulation == null:
		return false
	if bool(SettingsService.values.get("map_reduced_transition", false)):
		return false
	var boss := field_unit("boss")
	var steps: Array = FieldScriptScript.steps_for("boss_aftermath", str(simulation.stage.get("id", "")), {"boss": unit_display_name(boss)})
	if steps.is_empty() or field_unit("leader").is_empty():
		return false
	field_overlay = FieldSceneOverlayScript.new()
	field_overlay.name = "BossAftermathField"
	field_overlay.text_font = battle_font
	add_child(field_overlay)
	var stage = BattleFieldStageScript.new(self, field_overlay, {}, field_portrait_source)
	field_overlay.finished.connect(_on_field_aftermath_finished)
	if not field_overlay.play(steps, stage, {"letterbox": true}):
		_reset_field_direction()
		field_aftermath_state = "done"
		return false
	field_aftermath_state = "playing"
	return true

func _on_field_aftermath_finished(_skipped: bool) -> void:
	field_aftermath_state = "done"
	field_release()
	if field_overlay != null and is_instance_valid(field_overlay):
		field_overlay.queue_free()
	field_overlay = null
	queue_redraw()

## The unit a script role stands for: boss is the defeated boss (its last record),
## leader and ally the first two surviving party members by slot.
func field_unit(role: String) -> Dictionary:
	if simulation == null:
		return {}
	if role == "boss":
		for unit in simulation.state.enemies:
			if str(unit.get("rank", "")) == "BOSS":
				return unit
		for uid in presentation_actor_records:
			var record: Dictionary = presentation_actor_records[uid]
			if str(record.get("rank", "")) == "BOSS":
				return record
		return {}
	var alive: Array = simulation.state.party.filter(func(unit): return UnitState.alive(unit))
	alive.sort_custom(func(a, b): return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	if alive.is_empty():
		return {}
	if role == "ally" and alive.size() > 1:
		return alive[1]
	return alive[0]

## Asset id of a role's portrait art (the boss's or a survivor's own).
func field_portrait_id(role: String) -> String:
	var unit := field_unit(role)
	if unit.is_empty():
		return ""
	var definition_id := str(unit.get("def_id", ""))
	var character := DataRegistry.character(definition_id)
	if not character.is_empty():
		return str(character.get("portrait_asset_id", ""))
	return str(DataRegistry.enemy(definition_id).get("asset_id", ""))

func field_actor_name(role: String) -> String:
	var unit := field_unit(role)
	return "" if unit.is_empty() else unit_display_name(unit)

func field_layout_point(role: String) -> Vector2:
	var unit := field_unit(role)
	if unit.is_empty():
		return Vector2.INF
	var uid := str(unit.get("uid", ""))
	if engagement_positions.has(uid):
		return (engagement_positions[uid] as Vector2) * size
	return Grounding.cell_point(float(unit.get("col", 0)), float(unit.get("lane", 1))) * size

func field_head_point(role: String) -> Vector2:
	var unit := field_unit(role)
	if unit.is_empty():
		return Vector2.INF
	var ground := _ground_position(unit)
	if role == "boss":
		return ground + Vector2(0.0, -130.0 * _battlefield_camera_zoom())
	return _head_position(unit, ground) - Vector2(0.0, _field_hop_px(unit))

func field_move_unit_px() -> float:
	return Grounding.COLUMN_STEP * size.x

func field_set_pose(role: String, offset: Vector2, hop: float) -> void:
	var unit := field_unit(role)
	if unit.is_empty() or role == "boss":
		return
	field_poses[str(unit.get("uid", ""))] = {"offset": Vector2(offset.x * field_move_unit_px(), offset.y * size.y * 0.08), "hop": hop * size.y * 0.12}

func _field_pose_offset(unit: Dictionary) -> Vector2:
	if field_poses.is_empty():
		return Vector2.ZERO
	var pose: Dictionary = field_poses.get(str(unit.get("uid", "")), {})
	return pose.get("offset", Vector2.ZERO)

func _field_hop_px(unit: Dictionary) -> float:
	if field_poses.is_empty():
		return 0.0
	var pose: Dictionary = field_poses.get(str(unit.get("uid", "")), {})
	return float(pose.get("hop", 0.0))

## Push the battle floor in around focus_point (layout pixels, INF for the middle).
func field_set_camera(focus_point: Vector2, zoom: float, shake: float) -> void:
	field_zoom = clampf(zoom, 1.0, 2.0)
	var target := Vector2.ZERO
	if focus_point != Vector2.INF:
		target = -(focus_point - size * 0.5) * field_zoom
	var limit := (field_zoom - 1.0) * size * 0.5
	target = Vector2(clampf(target.x, -limit.x, limit.x), clampf(target.y, -limit.y, limit.y))
	var moment := float(Time.get_ticks_msec())
	field_offset = field_offset.lerp(target, 0.18) + Vector2(sin(moment * 0.09), cos(moment * 0.113)) * shake
	queue_redraw()

func field_release() -> void:
	field_poses.clear()
	field_zoom = 1.0
	field_offset = Vector2.ZERO
	queue_redraw()

func _character_color(slot: int) -> Color:
	return [Color("5ed6c0"), Color("ff9b73"), Color("75a7ff"), Color("e788ff"), Color("ffd166")][slot % 5]

func _enemy_color(rank: String) -> Color:
	if rank == "BOSS": return Color("b54d67")
	if rank == "ELITE": return Color("a46bd4")
	return Color("6f7f98")

func _actor_model(uid: String) -> Dictionary:
	if simulation == null: return {}
	if _draw_memo_active and _actor_memo.has(uid): return _actor_memo[uid]
	var live := simulation.find_unit(uid)
	var actor: Dictionary = live if not live.is_empty() else presentation_actor_records.get(uid, {})
	if _draw_memo_active: _actor_memo[uid] = actor
	return actor

func _waiting_for_wave_contact() -> bool:
	if simulation == null or simulation.state.ended: return false
	return simulation.state.wave > wave_entry_wave or (simulation.has_boss() and simulation.state.wave != boss_entry_wave)

func _advance_contacts(delta: float) -> void:
	for item in contact_events: item.remaining = float(item.remaining) - delta
	while not contact_events.is_empty() and float(contact_events[0].remaining) <= 0.0:
		var item: Dictionary = contact_events.pop_front()
		_present_regular_event(item.event)
		contact_commits += 1

func _action_label(event: Dictionary) -> String:
	var authored_label := str(event.get("extra", {}).get("label", ""))
	if not authored_label.is_empty(): return authored_label
	var skill_id := str(event.get("extra", {}).get("skill_id", ""))
	for skill in simulation.data.get("skills", []):
		if str(skill.get("id", "")) == skill_id:
			var key := str(skill.get("name_key", ""))
			if not key.is_empty(): return LocalizationService.tr_key(key)
	return "집중 공격"

func _advance_engagement(delta: float) -> void:
	## Actors glide to the cell the simulation placed them on (a command move,
	## an enemy advance or a pre-battle swap). Melee strikes add their own lunge
	## through _actor_travel_offset and return to the cell afterwards.
	if simulation == null: return
	for model in simulation.state.party + simulation.state.enemies:
		var uid := str(model.uid)
		var goal := Grounding.cell_point(float(model.get("col", 0)), float(model.get("lane", 1)))
		if not engagement_positions.has(uid):
			engagement_positions[uid] = goal
		if not UnitState.alive(_presentation_unit(model)): continue
		var current: Vector2 = engagement_positions[uid]
		var moving := current.distance_to(goal) > .004
		engagement_positions[uid] = current.move_toward(goal, delta * (.75 if deployment_active else .42))
		var track: Dictionary = animation_tracks.get(uid, {})
		if str(track.get("name", "idle")) in ["idle", "move"]:
			track.name = "move" if moving else "idle"
			animation_tracks[uid] = track

## Hit test for the shell's tactical input, in this control's local space.
## Returns {"unit": uid} for a living actor or {"cell": [col, lane]} for the
## floor. With `prefer_cells` (an ally is being moved) the floor wins so a tall
## neighbour's body cannot swallow the tap on the cell behind it.
func pick_at(point: Vector2, prefer_cells := false) -> Dictionary:
	if simulation == null: return {}
	var cell := cell_at(point)
	if prefer_cells and not cell.is_empty():
		return {"cell": cell}
	var best_uid := ""
	var best_distance := INF
	for unit in simulation.state.party + simulation.state.enemies:
		if not UnitState.alive(unit): continue
		var view_unit := _presentation_unit(unit)
		var foot := _ground_position(view_unit)
		var head := _head_position(view_unit, foot)
		var height := maxf(60.0, foot.y - head.y)
		var half_width := maxf(30.0, height * .26)
		var body := Rect2(Vector2(foot.x - half_width, head.y - 12.0), Vector2(half_width * 2.0, height + 30.0))
		if not body.has_point(point): continue
		var distance := point.distance_to(Vector2(foot.x, foot.y - height * .45))
		if distance < best_distance:
			best_distance = distance
			best_uid = str(unit.uid)
	if not best_uid.is_empty():
		return {"unit": best_uid}
	if not cell.is_empty():
		return {"cell": cell}
	return {}

func cell_at(point: Vector2) -> Array:
	for col in range(BattleGrid.COLUMNS):
		for lane in range(BattleGrid.LANES):
			if Geometry2D.is_point_in_polygon(point, _cell_screen_polygon(col, lane, 0.0)):
				return [col, lane]
	return []

func cell_screen_center(col: int, lane: int) -> Vector2:
	return _battlefield_point(Grounding.cell_point(col, lane) * size)

## `_battlefield_point` as a transform, for geometry authored in view pixels at
## camera zoom 1 (zoom about the view centre, then the director and field offsets).
func _battlefield_pixel_transform() -> Transform2D:
	var zoom := _battlefield_camera_zoom()
	return Transform2D(Vector2(zoom, 0.0), Vector2(0.0, zoom), size * .5 * (1.0 - zoom) + _battlefield_offset())

## All floor cells as one mesh in view pixels at zoom 1, rebuilt only when the
## view size changes. Colours are the base alphas; the caller applies emphasis.
func _grid_lattice() -> ArrayMesh:
	if _grid_mesh != null and _grid_mesh_size == size: return _grid_mesh
	var kit := MeshKit.new()
	for col in range(BattleGrid.COLUMNS):
		for lane in range(BattleGrid.LANES):
			var cell := PackedVector2Array()
			for point in Grounding.cell_polygon(col, lane, .006):
				cell.append(point * size)
			var player_side := col <= BattleGrid.PLAYER_FRONT
			kit.fill(cell, Color(.30, .85, .95, .075) if player_side else Color(1.0, .40, .34, .055))
			kit.stroke(cell, 1.6, Color(.78, .96, 1.0, .30) if player_side else Color(1.0, .74, .64, .20), true)
	_grid_mesh = kit.build()
	_grid_mesh_size = size
	return _grid_mesh

func _cell_screen_polygon(col: int, lane: int, inset := .006) -> PackedVector2Array:
	var output := PackedVector2Array()
	for point in Grounding.cell_polygon(col, lane, inset):
		output.append(_battlefield_point(point * size))
	return output

func _cell_pixel_polygon(col: int, lane: int, inset: float) -> PackedVector2Array:
	var output := PackedVector2Array()
	for point in Grounding.cell_polygon(col, lane, inset): output.append(point * size)
	return output

func _prepare_cell_meshes() -> void:
	if _cell_mesh_size == size: return
	_cell_mesh_size = size
	_cell_meshes.clear()
	_cell_bracket_meshes.clear()
	_contact_divider_mesh = null

## Tint and camera animation do not invalidate cell geometry. The same fill or
## range outline is reused for deployment, aim previews, cast windup and landing.
func _cell_mesh(col: int, lane: int, inset: float, width := 0.0) -> ArrayMesh:
	_prepare_cell_meshes()
	var key := "%d|%d|%s|%s" % [col, lane, str(inset), str(width)]
	if not _cell_meshes.has(key):
		var kit := MeshKit.new()
		var points := _cell_pixel_polygon(col, lane, inset)
		if width > 0.0: kit.stroke(points, width, Color.WHITE, true)
		else: kit.fill(points, Color.WHITE)
		_cell_meshes[key] = kit.build()
	return _cell_meshes[key]

func _draw_cell_fill(col: int, lane: int, inset: float, color: Color) -> void:
	draw_mesh(_cell_mesh(col, lane, inset), null, _battlefield_pixel_transform(), color)

func _draw_cell_outline(col: int, lane: int, inset: float, width: float, color: Color) -> void:
	draw_mesh(_cell_mesh(col, lane, inset, width), null, _battlefield_pixel_transform(), color)

func _draw_danger_brackets(col: int, lane: int, color: Color) -> void:
	_prepare_cell_meshes()
	var key := Vector2i(col, lane)
	if not _cell_bracket_meshes.has(key):
		var kit := MeshKit.new()
		var poly := _cell_pixel_polygon(col, lane, .003)
		for index in range(poly.size()):
			var corner := poly[index]
			kit.stroke(PackedVector2Array([corner, corner.lerp(poly[(index - 1 + poly.size()) % poly.size()], .22)]), 2.4, Color.WHITE)
			kit.stroke(PackedVector2Array([corner, corner.lerp(poly[(index + 1) % poly.size()], .22)]), 2.4, Color.WHITE)
		_cell_bracket_meshes[key] = kit.build()
	draw_mesh(_cell_bracket_meshes[key], null, _battlefield_pixel_transform(), color)

func _draw_contact_divider(color: Color) -> void:
	_prepare_cell_meshes()
	if _contact_divider_mesh == null:
		var kit := MeshKit.new()
		kit.stroke(PackedVector2Array([Grounding.cell_polygon(2, 0, 0.0)[1] * size, Grounding.cell_polygon(2, 2, 0.0)[2] * size]), 2.4, Color.WHITE)
		_contact_divider_mesh = kit.build()
	draw_mesh(_contact_divider_mesh, null, _battlefield_pixel_transform(), color)

func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var output := points.duplicate()
	if not output.is_empty(): output.append(output[0])
	return output

func _shrunk(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var center := Vector2.ZERO
	for point in points: center += point
	center /= maxf(1.0, float(points.size()))
	var output := PackedVector2Array()
	for point in points: output.append(center + (point - center) * amount)
	return output

## Floor grid, cover, move/reach highlights, aim preview and danger cells.
## Drawn under the actors; the grid fades back once the battle is running and
## nothing is selected, while cover and danger always stay readable.
func _draw_tactical_grid() -> void:
	if simulation == null or scene_transition_active(): return
	var focused := deployment_active or not tactical_selected_uid.is_empty() or not tactical_aim_uid.is_empty()
	var emphasis := 1.0 if focused else .42
	# The eighteen cells never change shape: one cached mesh, the camera applied as
	# its draw transform (so stroke width follows the zoom exactly as before) and
	# the emphasis as its alpha.
	var lattice := _grid_lattice()
	if lattice != null: draw_mesh(lattice, null, _battlefield_pixel_transform(), Color(1, 1, 1, emphasis))
	# The contact line between the two zones.
	_draw_contact_divider(Color(.96, .84, .52, .34 * emphasis + .12))
	for cell in simulation.state.cover_cells:
		_draw_cover_marker(int(cell[0]), int(cell[1]))
	var selected := simulation.find_unit(tactical_selected_uid)
	if not selected.is_empty() and UnitState.alive(selected):
		var pulse := .5 + .5 * sin(float(Time.get_ticks_msec()) / 170.0)
		for col in BattleGrid.PLAYER_COLUMNS:
			for lane in range(BattleGrid.LANES):
				if int(col) == int(selected.col) and lane == int(selected.lane):
					_draw_cell_fill(int(col), lane, .006, Color(.45, 1.0, .72, .24 + .12 * pulse))
					continue
				var occupant := simulation.unit_at(int(col), lane)
				var allowed := deployment_active or simulation.move_block_reason(str(selected.uid), int(col), lane).is_empty()
				if not allowed or (not occupant.is_empty() and str(occupant.team) != "PLAYER"): continue
				var tint := Color(.98, .82, .40, .20) if not occupant.is_empty() else Color(.45, 1.0, .72, .16)
				_draw_cell_fill(int(col), lane, .012, tint)
		# Cells the selected ally reaches from where it stands.
		for col in range(BattleGrid.COLUMNS):
			for lane in range(BattleGrid.LANES):
				if col <= BattleGrid.PLAYER_FRONT and str(simulation.unit_at(col, lane).get("team", "")) != "ENEMY": continue
				if not TargetResolver.in_range(selected, {"col": col, "lane": lane}): continue
				_draw_cell_outline(col, lane, .016, 2.2, Color(1.0, .66, .30, .70))
	var aim := simulation.find_unit(tactical_aim_uid)
	if not aim.is_empty():
		var skill := simulation._skill(str(aim.ultimate_skill_id))
		var preview := simulation.find_unit(tactical_preview_uid)
		if str(skill.get("effect", "")) == "AOE_DAMAGE" and not preview.is_empty() and UnitState.alive(preview):
			for cell in BattleSimulation.ultimate_area_cells(preview):
				_draw_cell_fill(int(cell[0]), int(cell[1]), .008, Color(1.0, .72, .26, .26))
	_draw_danger_cells()
	_draw_telegraph_flashes()

## A low sandbag barricade at the back edge of a cover cell.
func _draw_cover_marker(col: int, lane: int) -> void:
	var zoom := _battlefield_camera_zoom()
	var facing := 1.0 if col <= BattleGrid.PLAYER_FRONT else -1.0
	var center := _battlefield_point(Grounding.cell_point(col, lane) * size) + Vector2(facing * 30.0, -8.0) * zoom
	var width := size.x * Grounding.COLUMN_STEP * .30 * zoom
	var bag := Vector2(width * .36, 9.0 * zoom)
	var fill := Color(.62, .56, .42, .92)
	var edge := Color(.20, .16, .10, .85)
	# Each sandbag is two cached ellipses: the dark edge colour a stroke-width
	# larger underneath, the fill a stroke-width smaller on top. That replaces a
	# polygon plus a polyline per bag.
	var half_stroke := Vector2(.7, .7) * zoom
	for row in range(2):
		for index in range(3 - row):
			var offset := Vector2((float(index) - (2.0 - row) * .5) * bag.x * 1.55, -float(row) * bag.y * 1.35)
			SoftSprites.draw_ellipse(self, center + offset, bag + half_stroke, edge)
			SoftSprites.draw_ellipse(self, center + offset, bag - half_stroke, fill.darkened(.08 * row))
	if deployment_active:
		var font := battle_font if battle_font != null else ThemeDB.fallback_font
		var font_size := clampi(roundi(13.0 * _readout_scale()), 13, 30)
		var anchor := center + Vector2(-40.0, -bag.y * 3.0)
		draw_string_outline(font, anchor, "엄폐", HORIZONTAL_ALIGNMENT_CENTER, 80.0, font_size, 4, Color(0, 0, 0, .8))
		draw_string(font, anchor, "엄폐", HORIZONTAL_ALIGNMENT_CENTER, 80.0, font_size, Color("e8d7a6"))

func _telegraph_remaining(cast: Dictionary) -> float:
	return maxf(0.0, float(int(cast.due_tick) - int(simulation.state.tick)) * BattleSimulation.TICK_DELTA)

func _telegraph_urgency(cast: Dictionary) -> float:
	var windup := maxf(.1, float(cast.get("windup_ticks", BattleSimulation.BOSS_WINDUP_TICKS)) * BattleSimulation.TICK_DELTA)
	return 1.0 - clampf(_telegraph_remaining(cast) / windup, 0.0, 1.0)

## Cells a telegraphed attack will hit: a floor decal that fills from the rim
## toward the centre as the hit approaches, with a glowing edge and corner
## brackets. Area patterns add an ornate ring that closes in. Shapes, cells and
## timing come unchanged from the simulation.
func _draw_danger_cells() -> void:
	if simulation == null or simulation.pending_boss_casts.is_empty(): return
	var clock := float(Time.get_ticks_msec()) / 1000.0
	var pulse := .5 + .5 * sin(clock * 9.0)
	var zoom := _battlefield_camera_zoom()
	for cast in simulation.pending_boss_casts:
		var urgency := _telegraph_urgency(cast)
		var cells: Array = cast.get("cells", [])
		for cell in cells:
			var poly := _cell_screen_polygon(int(cell[0]), int(cell[1]), .003)
			_draw_cell_fill(int(cell[0]), int(cell[1]), .003, Color(1.0, .10, .08, .08 + .06 * pulse))
			var front := _shrunk(poly, 1.0 - urgency)
			if urgency >= .98:
				_draw_cell_fill(int(cell[0]), int(cell[1]), .003, Color(1.0, .26, .14, .52))
			elif urgency > .02:
				_draw_polygon_band(poly, front, Color(1.0, .26, .14, .30 + .22 * urgency))
			draw_polyline(_closed(poly), Color(1.0, .22, .14, .18 + .10 * pulse), (8.0 + 4.0 * urgency) * zoom, true)
			draw_polyline(_closed(poly), Color(1.0, .48, .32, .80 + .20 * pulse), (2.0 + 1.4 * urgency) * zoom, true)
			if urgency > .02 and urgency < .97:
				draw_polyline(_closed(front), Color(1.0, .86, .62, .55 + .35 * urgency), 1.5 * zoom, true)
			_draw_danger_brackets(int(cell[0]), int(cell[1]), Color(1.0, .80, .55, .70 + .25 * urgency))
		if str(cast.get("shape", "CELL")) != "CELL" and cells.size() > 1:
			_draw_aoe_rings(cells, urgency, clock, zoom)

## Fills the ring between two polygons with the same vertex order.
func _draw_polygon_band(outer: PackedVector2Array, inner: PackedVector2Array, color: Color) -> void:
	var count := mini(outer.size(), inner.size())
	for index in range(count):
		var next := (index + 1) % count
		# A convex four-vertex strip uses the renderer's streamed quad batch.
		# Its two triangles have exactly the same vertices and order as before.
		draw_primitive(PackedVector2Array([outer[index], outer[next], inner[next], inner[index]]), PackedColorArray([color, color, color, color]), PackedVector2Array())

func _draw_cell_brackets(poly: PackedVector2Array, color: Color, zoom: float) -> void:
	var count := poly.size()
	for index in range(count):
		var corner := poly[index]
		draw_line(corner, corner.lerp(poly[(index - 1 + count) % count], .22), color, 2.4 * zoom, true)
		draw_line(corner, corner.lerp(poly[(index + 1) % count], .22), color, 2.4 * zoom, true)

## Ornate ring around an area pattern: glowing rim, rotating rune ticks, four
## studs and an inner ring that closes toward the centre as the hit nears.
func _draw_aoe_rings(cells: Array, urgency: float, clock: float, zoom: float) -> void:
	var bounds := Rect2()
	var first := true
	for cell in cells:
		for point in _cell_screen_polygon(int(cell[0]), int(cell[1]), 0.0):
			if first:
				bounds = Rect2(point, Vector2.ZERO)
				first = false
			else:
				bounds = bounds.expand(point)
	var center := bounds.get_center()
	var radii := bounds.size * .5 * 1.04
	var gold := Color(1.0, .80, .46, .78)
	_draw_floor_ring(center, radii, Color(1.0, .25, .18, .22), 9.0 * zoom)
	_draw_floor_ring(center, radii, Color(1.0, .34, .24, .88), 2.4 * zoom)
	_draw_floor_ring(center, radii * .90, gold, 1.2 * zoom)
	var ticks := 28
	for index in range(ticks):
		var angle := TAU * float(index) / float(ticks) + clock * .55
		var direction := Vector2(cos(angle), sin(angle))
		var reach := 1.0 if index % 4 == 0 else .96
		draw_line(center + direction * radii * .90, center + direction * radii * reach, gold, 1.5 * zoom, true)
	_draw_floor_ring(center, radii * .88 * maxf(.04, 1.0 - urgency), Color(1.0, .86, .60, .45 + .45 * urgency), 2.0 * zoom)
	for quarter in range(4):
		var angle := PI * .5 * float(quarter) + clock * .55
		Ornament.stud(self, center + Vector2(cos(angle), sin(angle)) * radii, 4.5 * zoom, .9, Color(1.0, .5, .35))

## Records pending casts and flashes their cells when one lands.
func _track_telegraph_landings() -> void:
	if simulation == null:
		return
	var live: Dictionary = {}
	for cast in simulation.pending_boss_casts:
		var key := "%s:%d" % [str(cast.boss_uid), int(cast.due_tick)]
		live[key] = true
		if not telegraph_keys.has(key):
			telegraph_keys[key] = {"cells": (cast.get("cells", []) as Array).duplicate(true), "shape": str(cast.get("shape", "CELL")), "boss_uid": str(cast.boss_uid), "due_tick": int(cast.due_tick)}
	for key in telegraph_keys.keys():
		if live.has(key):
			continue
		var record: Dictionary = telegraph_keys[key]
		telegraph_keys.erase(key)
		# A cancelled cast (caster down or stunned) does not flash.
		var caster := simulation.find_unit(str(record.boss_uid))
		if int(simulation.state.tick) >= int(record.due_tick) and not caster.is_empty() and UnitState.alive(caster) and not UnitState.has_status(caster, "STUN"):
			telegraph_flashes.append({"cells": record.cells, "shape": record.shape, "age": 0.0})

func _draw_telegraph_flashes() -> void:
	if telegraph_flashes.is_empty():
		return
	var zoom := _battlefield_camera_zoom()
	for flash in telegraph_flashes:
		var progress := clampf(float(flash.age) / TELEGRAPH_FLASH_DURATION, 0.0, 1.0)
		var heat := pow(1.0 - progress, 2.0)
		for cell in flash.cells:
			var poly := _cell_screen_polygon(int(cell[0]), int(cell[1]), .003)
			_draw_cell_fill(int(cell[0]), int(cell[1]), .003, Color(1.0, .92, .78, .70 * heat))
			draw_polyline(_closed(_shrunk(poly, 1.0 + .30 * progress)), Color(1.0, .55, .30, 1.0 - progress), (3.0 + 5.0 * (1.0 - progress)) * zoom, true)

func telegraph_snapshot() -> Dictionary:
	var casts: Array = []
	if simulation != null:
		for cast in simulation.pending_boss_casts:
			casts.append({"urgency": _telegraph_urgency(cast), "remaining": _telegraph_remaining(cast), "shape": str(cast.get("shape", "CELL")), "cells": (cast.get("cells", []) as Array).size()})
	return {"casts": casts, "tracked": telegraph_keys.size(), "flashes": telegraph_flashes.size()}

## Focus reticle, aim rings, selection ring and (while deploying) role/reach
## tags. Drawn above the actors so a crowd cannot hide them.
func _draw_tactical_markers() -> void:
	if simulation == null or scene_transition_active(): return
	var zoom := _battlefield_camera_zoom()
	var spin := float(Time.get_ticks_msec()) / 1000.0
	var focus := simulation.find_unit(simulation.state.focus_uid)
	if not focus.is_empty() and UnitState.alive(focus):
		var view_focus := _presentation_unit(focus)
		var foot := _ground_position(view_focus)
		var head := _head_position(view_focus, foot)
		var center := Vector2(foot.x, lerpf(head.y, foot.y, .45))
		var radius := maxf(26.0, (foot.y - head.y) * .32)
		for index in range(4):
			var angle := spin * 1.4 + TAU * float(index) / 4.0
			draw_arc(center, radius, angle, angle + .9, 10, Color("ffd36a"), 3.0 * zoom, true)
		CachedDraw.disc(self, center, 4.0 * zoom, Color("ffd36a"))
	var aim := simulation.find_unit(tactical_aim_uid)
	if not aim.is_empty():
		for enemy in simulation.alive_enemies():
			var foot := _ground_position(_presentation_unit(enemy))
			var hot := str(enemy.uid) == tactical_preview_uid
			_draw_floor_ring(foot, Vector2(58.0, 14.0) * zoom, Color(1.0, .78, .30, .95 if hot else .55), (4.0 if hot else 2.4) * zoom)
	var selected := simulation.find_unit(tactical_selected_uid)
	if not selected.is_empty():
		_draw_floor_ring(_ground_position(_presentation_unit(selected)), Vector2(62.0, 15.0) * zoom, Color(.55, 1.0, .78, .95), 4.0 * zoom)
	if deployment_active:
		var font := battle_font if battle_font != null else ThemeDB.fallback_font
		var font_size := clampi(roundi(13.0 * _readout_scale()), 13, 30)
		for unit in simulation.state.party + simulation.state.enemies:
			if not UnitState.alive(unit): continue
			var foot := _ground_position(_presentation_unit(unit))
			var text := BattleGrid.role_label(str(unit.role), str(unit.team))
			if str(unit.team) == "PLAYER":
				text += " · 사거리 %d" % int(unit.range)
			var anchor := foot + Vector2(-70.0, 12.0 * zoom + font_size)
			draw_string_outline(font, anchor, text, HORIZONTAL_ALIGNMENT_CENTER, 140.0, font_size, 4, Color(0, 0, 0, .85))
			draw_string(font, anchor, text, HORIZONTAL_ALIGNMENT_CENTER, 140.0, font_size, Color("bff3ff") if str(unit.team) == "PLAYER" else Color("ffc2b6"))

func _draw_floor_ring(center: Vector2, radii: Vector2, color: Color, width: float) -> void:
	var ring := PackedVector2Array()
	for step in range(33):
		var angle := TAU * float(step) / 32.0
		ring.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_polyline(ring, color, width, true)

func _draw_combat_readout() -> void:
	if scene_transition_active(): return
	var font := battle_font if battle_font != null else ThemeDB.fallback_font
	var text_size := clampi(roundi(14.0 / _damage_screen_scale()), 20, 44)
	var boss := presentation_boss()
	if not boss.is_empty():
		var health_box := Rect2(Vector2(size.x * .27, size.y * .17), Vector2(size.x * .46, float(text_size) * 1.85))
		draw_style_box(_combat_readout_style(), health_box)
		var text := "%s  %d%%" % [unit_display_name(boss), roundi(UnitState.hp_ratio(boss) * 100)]
		draw_string(font, health_box.position + Vector2(12, text_size + 2), text, HORIZONTAL_ALIGNMENT_CENTER, health_box.size.x - 24, text_size, Color("ffe1bc"))
		var bar := Rect2(health_box.position + Vector2(12, text_size * 1.35), Vector2(health_box.size.x - 24, text_size * .22))
		draw_rect(bar, Color("462c37"))
		bar.size.x *= UnitState.hp_ratio(boss)
		draw_rect(bar, Color("f47957"))
	if combat_readout_left <= 0.0 or combat_readout.is_empty(): return
	var box := Rect2(Vector2(size.x * .24, size.y * (.30 if not boss.is_empty() else .16)), Vector2(size.x * .52, text_size * 1.55))
	draw_style_box(_combat_readout_style(), box)
	draw_string(font, box.position + Vector2(10, text_size * 1.12), combat_readout, HORIZONTAL_ALIGNMENT_CENTER, box.size.x - 20, text_size, Color("f6e5bd"))

func _combat_readout_style() -> StyleBoxFlat:
	if _readout_style == null:
		_readout_style = StyleBoxFlat.new()
		_readout_style.bg_color = Color(.025, .055, .085, .9)
		_readout_style.set_corner_radius_all(8)
	return _readout_style

# --- Phase 1 presentation (2026-09-30) ---------------------------------------
# Nameplates, shouts, combo counter, boss band, end card and the character
# cut-in. All of it is drawn from view state; none of it writes to the
# simulation, the event log or the RNG.

static func normalized_cutin_mode(value: String) -> String:
	var mode := value.strip_edges().to_upper()
	return mode if mode in CUTIN_MODES else "SHORT"

func _bind_cutin_settings() -> void:
	# The shell's battle view is in the tree and follows the saved setting. Bare
	# views in headless tests keep the SHORT default without a first-use record,
	# so the ordinary presentation timing stays deterministic there.
	cutin_mode = normalized_cutin_mode(str(SettingsService.values.get("battle_cutin_mode", "SHORT")))
	cutin_seen_ids.clear()
	var seen_value = SettingsService.values.get("battle_cutin_seen", [])
	if seen_value is Array:
		for id_value in seen_value:
			cutin_seen_ids[str(id_value)] = true
	cutin_first_use_enabled = true
	cutin_settings_bound = true

## How an ULTIMATE cut-in plays. Only allied casters get the character cut-in.
func cutin_plan_for(source: Dictionary) -> Dictionary:
	var def_id := str(source.get("def_id", ""))
	var plan := {"show": false, "long": false, "first_use": false, "def_id": def_id, "mode": cutin_mode}
	if source.is_empty() or str(source.get("team", "")) != "PLAYER" or cutin_mode == "OFF":
		return plan
	plan.show = true
	if cutin_mode == "FULL":
		plan.long = true
	elif cutin_first_use_enabled and not def_id.is_empty() and not cutin_seen_ids.has(def_id):
		plan.long = true
		plan.first_use = true
	return plan

func _mark_cutin_seen(def_id: String) -> void:
	if def_id.is_empty() or cutin_seen_ids.has(def_id):
		return
	cutin_seen_ids[def_id] = true
	if cutin_settings_bound:
		var ids: Array = cutin_seen_ids.keys()
		ids.sort()
		# Saved with the profile settings on the next save (the result saves).
		SettingsService.values["battle_cutin_seen"] = ids

func cutin_snapshot() -> Dictionary:
	var cinematic := presentation_director.cinematic_snapshot()
	var seen: Array = cutin_seen_ids.keys()
	seen.sort()
	return {"mode": cutin_mode, "plan": active_cutin.duplicate(true), "lead_in_total": float(cinematic.get("lead_in_total", 0.0)), "seen": seen}

func _register_combo_hit(event: Dictionary) -> void:
	if int(event.get("value", 0)) <= 0:
		return
	var source := _actor_model(str(event.get("source", "")))
	if str(source.get("team", "")) != "PLAYER":
		return
	combo_count += 1
	combo_peak = maxi(combo_peak, combo_count)
	combo_left = COMBO_WINDOW
	combo_pop = 1.0

func _advance_combo(delta: float) -> void:
	combo_pop = maxf(0.0, combo_pop - delta * 5.0)
	if combo_count <= 0:
		return
	combo_left = maxf(0.0, combo_left - delta)
	if combo_left <= 0.0:
		combo_count = 0

func combo_snapshot() -> Dictionary:
	return {"count": combo_count, "peak": combo_peak, "left": combo_left, "visible": combo_count >= COMBO_MIN_DISPLAY}

func skill_callout_snapshot() -> Array:
	var result: Array = []
	for callout in skill_callouts:
		result.append({"source": str(callout.source), "label": str(callout.label), "priority": int(callout.get("priority", 1)), "style": str(callout.get("style", "plate")), "role": str(callout.get("role", ""))})
	return result

func _fit_font_size(font: Font, text: String, font_size: int, max_width: float) -> int:
	if font == null or text.is_empty():
		return font_size
	var width := float(Ornament.text_metrics(font, text, font_size).width)
	if width <= max_width or width <= 0.0:
		return font_size
	return maxi(10, int(floor(float(font_size) * max_width / width)))

## Ally nameplate: [role] + skill name on an ornamented band above the head.
## Enemies and bosses shout the same name in a jagged bubble instead.
func _draw_skill_callout(callout: Dictionary) -> void:
	var caster := _actor_model(str(callout.source))
	if caster.is_empty():
		return
	var duration := maxf(.01, float(callout.duration))
	var age := float(callout.age)
	var enter := clampf(age / .14, 0.0, 1.0)
	var alpha := clampf((duration - age) / .28, 0.0, 1.0) * enter
	if alpha <= 0.0:
		return
	var readout := _readout_scale()
	var font := battle_font if battle_font != null else ThemeDB.fallback_font
	var strong := int(callout.get("priority", 1)) > 1
	var font_size := clampi(roundi((25.0 if strong else 21.0) * readout), 18, 52)
	var text := str(callout.label)
	var head := _head_position(caster, _ground_position(caster))
	var rise := (1.0 - enter) * 10.0 * readout + age * 6.0 * readout
	var accent: Color = callout.color
	if str(callout.get("style", "plate")) == "shout":
		_draw_shout_bubble(head, text, font, font_size, accent, alpha, readout, rise, strong)
		return
	var role_text := str(callout.get("role", ""))
	var chip_size := maxi(11, roundi(font_size * .66))
	var chip_width := 0.0 if role_text.is_empty() else font.get_string_size(role_text, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size).x + 14.0 * readout
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var height := font_size + 14.0 * readout
	var width := chip_width + text_width + height * .5 + 23.0 * readout
	var center := head + Vector2(0, -58.0 * readout - rise)
	var rect := Rect2(center - Vector2(width, height) * .5, Vector2(width, height))
	var edge_gap := 18.0 * readout + height * .5
	rect.position.x = clampf(rect.position.x, edge_gap, maxf(edge_gap, size.x - width - 18.0 * readout))
	rect.position.y = maxf(rect.position.y, 8.0)
	Ornament.band(self, rect, alpha, readout * (.72 if strong else .60), accent, fposmod(age * 1.4, 1.0) if strong else -1.0)
	# Circular origin cue on the plate's leading end keeps the old round skill
	# marker readable at a glance while the plate carries the name.
	var callout_position := Vector2(rect.position.x, rect.get_center().y)
	var callout_radius := height * (.50 if strong else .44)
	CachedDraw.disc(self, callout_position, callout_radius + 4.0 * readout, Color(accent.r, accent.g, accent.b, alpha * .16))
	CachedDraw.disc(self, callout_position, callout_radius, Color(.015, .035, .075, alpha * .92))
	draw_arc(callout_position, callout_radius, -PI * .62, PI * 1.15, 24, Color(accent.r, accent.g, accent.b, alpha), 2.0 * readout, true)
	CachedDraw.disc(self, callout_position, callout_radius * .24, Color(1.0, 1.0, 1.0, alpha * .9))
	var cursor := rect.position.x + callout_radius + 8.0 * readout
	if chip_width > 0.0:
		var chip := Rect2(Vector2(cursor, rect.position.y + height * .18), Vector2(chip_width - 6.0 * readout, height * .64))
		draw_rect(chip, Ornament.tint(Ornament.GOLD_SHADOW, alpha * .9))
		draw_rect(chip, Ornament.tint(Ornament.GOLD, alpha), false, 1.2 * readout)
		Ornament.centered_text(self, font, chip.get_center(), role_text, chip_size, Ornament.tint(Ornament.GOLD_LIGHT, alpha))
		cursor += chip_width
	Ornament.centered_text(self, font, Vector2(cursor + text_width * .5, rect.get_center().y), text, font_size, Color(1, 1, 1, alpha), maxi(3, roundi(3.0 * readout)), Color(.02, .04, .08, alpha * .9))

func _draw_shout_bubble(head: Vector2, text: String, font: Font, font_size: int, accent: Color, alpha: float, readout: float, rise: float, strong: bool) -> void:
	var label := text if text.ends_with("!") else text + "!"
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var half := Vector2(text_width * .5 + 20.0 * readout, font_size * .5 + 11.0 * readout)
	var center := head + Vector2(0, -60.0 * readout - rise)
	center.x = clampf(center.x, half.x + 16.0 * readout, maxf(half.x + 16.0 * readout, size.x - half.x - 16.0 * readout))
	center.y = maxf(center.y, half.y + 10.0)
	var points := PackedVector2Array()
	var spikes := 18
	for index in range(spikes * 2):
		var angle := TAU * float(index) / float(spikes * 2)
		var jag := 1.0 if index % 2 == 0 else (.80 if strong else .87)
		points.append(center + Vector2(cos(angle) * (half.x + 8.0 * readout) * jag, sin(angle) * (half.y + 7.0 * readout) * jag))
	var fill := Color(.34, .03, .06, .92 * alpha) if strong else Color(.12, .03, .05, .88 * alpha)
	var tail := PackedVector2Array([center + Vector2(-10.0 * readout, half.y * .6), center + Vector2(10.0 * readout, half.y * .6), head + Vector2(0, -24.0 * readout)])
	draw_colored_polygon(tail, fill)
	draw_colored_polygon(points, fill)
	var edge := Ornament.tint(Ornament.GOLD, alpha) if strong else Color(accent.r, accent.g, accent.b, alpha)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, edge, 2.0 * readout, true)
	Ornament.centered_text(self, font, center, label, font_size, Color(1.0, .95, .90, alpha), maxi(3, roundi(3.0 * readout)), Color(.20, 0, .02, alpha))

## "N연속": allied hits inside the combo window. Display only.
func _draw_combo_counter() -> void:
	if combo_count < COMBO_MIN_DISPLAY or scene_transition_active() or deployment_active:
		return
	var alpha := clampf(combo_left / .45, 0.0, 1.0)
	if alpha <= 0.0:
		return
	var readout := _readout_scale()
	var font := battle_font if battle_font != null else ThemeDB.fallback_font
	var portrait := size.x < size.y
	var anchor := Vector2(size.x * (.80 if portrait else .87), size.y * (.19 if portrait else .25))
	var pop := 1.0 + .34 * combo_pop
	var number := str(combo_count)
	var number_size := clampi(roundi(46.0 * readout * pop), 30, 132)
	var number_width := DAMAGE_FONT.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, number_size).x
	var label := "연속"
	var label_size := clampi(roundi(20.0 * readout), 15, 54)
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
	var gap := 6.0 * readout
	var total := number_width + gap + label_width
	var left := minf(anchor.x - total * .5, size.x - total - 16.0 * readout)
	var baseline := Vector2(left, anchor.y)
	draw_string_outline(DAMAGE_FONT, baseline, number, HORIZONTAL_ALIGNMENT_LEFT, -1, number_size, maxi(4, roundi(5.0 * readout)), Color(.16, .07, 0, alpha))
	draw_string(DAMAGE_FONT, baseline, number, HORIZONTAL_ALIGNMENT_LEFT, -1, number_size, Color(1.0, .86, .42, alpha))
	var label_base := baseline + Vector2(number_width + gap, 0)
	draw_string_outline(font, label_base, label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, maxi(3, roundi(4.0 * readout)), Color(0, 0, 0, .85 * alpha))
	draw_string(font, label_base, label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(1.0, .96, .86, alpha))
	var rail_from := Vector2(left - 6.0 * readout, anchor.y + 10.0 * readout)
	var rail_width := (total + 12.0 * readout) * clampf(combo_left / COMBO_WINDOW, 0.0, 1.0)
	if rail_width > 2.0:
		Ornament.rail(self, rail_from, rail_from + Vector2(rail_width, 0), alpha, readout * .7)
	Ornament.stud(self, rail_from, 3.5 * readout, alpha)

## Full-width red boss band: hazard stripes, rails, "BOSS ENCOUNTER" and name.
func _draw_boss_encounter_band(t: float) -> void:
	var enter := smoothstep(.80, 1.10, t)
	var leave := 1.0 - smoothstep(3.10, 3.55, t)
	if enter * leave <= 0.0:
		return
	var readout := _readout_scale()
	var portrait := size.x < size.y
	var font := battle_font if battle_font != null else ThemeDB.fallback_font
	var center_y := size.y * (.28 if portrait else .30)
	var height := clampf(size.y * (.13 if portrait else .19), 110.0, 420.0)
	var reveal_width := size.x * enter
	var reveal := Rect2(Vector2(size.x - reveal_width, center_y - height * .5), Vector2(reveal_width, height))
	var deep := Color(.40, .02, .05, .90 * leave)
	var dark := Color(.10, .0, .02, .90 * leave)
	Ornament.quad(self, reveal.position, reveal.position + Vector2(reveal.size.x, 0), reveal.end, reveal.position + Vector2(0, reveal.size.y), deep, deep, dark, dark)
	var strip := height * .12
	Ornament.hazard_stripes(self, Rect2(reveal.position, Vector2(reveal.size.x, strip)), t, Color(1.0, .78, .25, .50 * leave), strip * 1.2)
	Ornament.hazard_stripes(self, Rect2(Vector2(reveal.position.x, reveal.end.y - strip), Vector2(reveal.size.x, strip)), -t, Color(1.0, .78, .25, .50 * leave), strip * 1.2)
	var accent := Color("ff9a7a")
	Ornament.rail(self, reveal.position, Vector2(reveal.end.x, reveal.position.y), leave, readout * .8, accent, fposmod(t * .7, 1.0))
	Ornament.rail(self, reveal.end, Vector2(reveal.position.x, reveal.end.y), leave, readout * .8, accent, fposmod(t * .7, 1.0))
	var text_alpha := smoothstep(1.0, 1.25, t) * leave
	var punch := 1.0 + .25 * (1.0 - smoothstep(1.0, 1.3, t))
	var shake := Vector2(sin(t * 80.0), cos(t * 67.0)) * 4.0 * readout * (1.0 - smoothstep(1.0, 1.5, t))
	var title := "BOSS ENCOUNTER"
	var title_size := _fit_font_size(DAMAGE_FONT, title, roundi(clampf(height * .36 * punch, 30.0, 170.0)), size.x * .90)
	Ornament.centered_text(self, DAMAGE_FONT, Vector2(size.x * .5, center_y - height * .09) + shake, title, title_size, Color(1.0, .93, .86, text_alpha), maxi(5, roundi(title_size * .08)), Color(.25, 0, .02, text_alpha))
	var name_size := _fit_font_size(font, boss_entry_name, roundi(clampf(height * .16, 18.0, 70.0)), size.x * .86)
	Ornament.centered_text(self, font, Vector2(size.x * .5, center_y + height * .27), boss_entry_name, name_size, Color(1.0, .84, .55, text_alpha), maxi(3, roundi(4.0 * readout)), Color(.15, 0, 0, text_alpha))

## Victory end card: eyebrow, punched title and caption on an ornate band,
## then a short fade into the result hand-off.
func _draw_finale_card(elapsed: float, duration: float, eyebrow: String, title: String, caption: String) -> void:
	var open := smoothstep(0.0, .26, elapsed)
	var fade_out := smoothstep(duration - .30, duration, elapsed)
	var readout := _readout_scale()
	var font := battle_font if battle_font != null else ThemeDB.fallback_font
	var center_y := size.y * .40
	var height := clampf(150.0 * readout, 120.0, size.y * .34)
	var width := size.x * open
	var rect := Rect2(Vector2((size.x - width) * .5, center_y - height * .5), Vector2(width, height))
	draw_rect(Rect2(Vector2.ZERO, size), Color(.01, .02, .04, .30 * open))
	Ornament.band(self, rect, 1.0, readout * .9, Ornament.LUMEN, fposmod(elapsed * .8, 1.0), Ornament.INK, size.x * .14)
	var text_alpha := smoothstep(.08, .22, elapsed)
	var punch := 1.0 + .30 * (1.0 - smoothstep(.10, .36, elapsed))
	var title_size := _fit_font_size(font, title, clampi(roundi(64.0 * readout * punch), 40, 190), size.x * .80)
	Ornament.centered_text(self, font, Vector2(size.x * .5, center_y + height * .04), title, title_size, Color(1.0, .95, .80, text_alpha), maxi(6, roundi(8.0 * readout)), Color(.12, .06, .01, text_alpha))
	var small := clampi(roundi(20.0 * readout), 15, 56)
	Ornament.centered_text(self, font, Vector2(size.x * .5, center_y - height * .33), "— %s —" % eyebrow, small, Ornament.tint(Ornament.GOLD, text_alpha), 3, Color(0, 0, 0, .7 * text_alpha))
	Ornament.centered_text(self, font, Vector2(size.x * .5, center_y + height * .36), caption, small, Color(.72, .94, 1.0, .9 * text_alpha), 3, Color(0, 0, 0, .7 * text_alpha))
	if fade_out > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(.008, .018, .03, fade_out))

## Character cut-in: a band wipes in over the dimmed field, speed lines run
## through it, the caster's reviewed combat pose slides across and the skill
## name reads on the right. Portrait uses a flat horizontal band.
func _draw_character_cutin(source: Dictionary, cinematic: Dictionary, visibility: float) -> void:
	var def_id := str(source.get("def_id", ""))
	var profile := _vfx_profile_for(source)
	var accent := Color(str(profile.get("primary", "79e7ff")))
	var secondary := Color(str(profile.get("secondary", "ffd36a")))
	var clock := float(cinematic.get("cutin_clock", 0.0))
	var long := float(cinematic.get("lead_in_total", 0.0)) > 0.0
	var portrait := size.x < size.y
	var readout := _readout_scale()
	var font := battle_font if battle_font != null else ThemeDB.fallback_font
	var enter := clampf(clock / (.22 if long else .12), 0.0, 1.0)
	var ease_in := 1.0 - pow(1.0 - enter, 3.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(.004, .012, .03, (.52 if long else .30) * visibility))
	var band_height := clampf(size.y * (.22 if portrait else .34), 150.0, size.y * .42) * (1.14 if long else 1.0)
	var center_y := size.y * (.36 if portrait else .44)
	var slant := 0.0 if portrait else band_height * .30
	var top := center_y - band_height * .5
	var bottom := center_y + band_height * .5
	var reach := -slant + (size.x + slant * 2.0) * ease_in
	if long:
		# First use: a counter-slanted accent band sweeps in from the right
		# behind the main band, so the full version reads as a bigger moment.
		var back_top := top - band_height * .16
		var back_bottom := bottom + band_height * .10
		var back_left := size.x - (size.x + slant * 2.0) * ease_in
		var back := Color(accent.r, accent.g, accent.b, .30 * visibility)
		CachedDraw.fill(self, PackedVector2Array([Vector2(back_left + slant, back_top), Vector2(size.x + slant, back_top), Vector2(size.x - slant, back_bottom), Vector2(back_left - slant, back_bottom)]), back)
		Ornament.rail(self, Vector2(back_left + slant, back_top), Vector2(size.x + slant, back_top), visibility * .8, readout * .7, secondary, -1.0)
	var band_poly := PackedVector2Array([Vector2(-slant, top), Vector2(reach + slant, top), Vector2(reach - slant, bottom), Vector2(-slant * 2.0, bottom)])
	var ink := Color(.02, .035, .07, .94 * visibility)
	var deep := accent.darkened(.62)
	deep.a = .94 * visibility
	# Keep the original polygon's triangulation for this tapered gradient: the
	# two diagonals do not interpolate identically on a non-parallelogram.
	var band_colors := PackedColorArray([deep, ink, ink, deep])
	var band_indices := Geometry2D.triangulate_polygon(band_poly)
	for triangle in range(0, band_indices.size(), 3):
		draw_primitive(PackedVector2Array([band_poly[band_indices[triangle]], band_poly[band_indices[triangle + 1]], band_poly[band_indices[triangle + 2]]]), PackedColorArray([band_colors[band_indices[triangle]], band_colors[band_indices[triangle + 1]], band_colors[band_indices[triangle + 2]]]), PackedVector2Array())
	var band_rect := Rect2(Vector2(0, top), Vector2(clampf(reach, 0.0, size.x), band_height))
	Ornament.speed_lines(self, band_rect.grow_individual(0, -6.0, 0, -6.0), clock, Color(secondary.r, secondary.g, secondary.b, .50 * visibility), 26, absi(def_id.hash()) % 97, 1.6)
	Ornament.speed_lines(self, band_rect, clock * 1.3, Color(1, 1, 1, .26 * visibility), 12, 7, 2.2)
	Ornament.rail(self, Vector2(-slant, top), Vector2(reach + slant, top), visibility, readout * .9, accent, fposmod(clock * 1.1, 1.0))
	Ornament.rail(self, Vector2(reach - slant, bottom), Vector2(-slant * 2.0, bottom), visibility, readout * .9, accent, fposmod(clock * 1.1, 1.0))
	var pose: Texture2D = _signature_cutin_pose_texture(def_id, .20 + clock * .55)
	if pose == null:
		pose = ultimate_orb_texture_for(def_id, null)
	if pose != null:
		var art_height := band_height * (1.36 if portrait else 1.75) * (1.06 if long else 1.0)
		var art_size := Vector2(art_height * float(pose.get_width()) / maxf(1.0, float(pose.get_height())), art_height)
		var art_center_x := size.x * (.22 if portrait else .30) - (1.0 - ease_in) * size.x * .30 + clock * 14.0 * readout
		var art_rect := Rect2(Vector2(art_center_x - art_size.x * .5, bottom - art_size.y * .92), art_size)
		draw_texture_rect(pose, Rect2(art_rect.position + Vector2(-18.0 * readout, 0), art_rect.size), false, Color(accent.r, accent.g, accent.b, .40 * visibility))
		draw_texture_rect(pose, art_rect, false, Color(1, 1, 1, visibility))
	var text_alpha := clampf((clock - .05) / .12, 0.0, 1.0) * visibility
	var skill_name := str(active_cutin.get("skill_name", ""))
	var text_center := Vector2(size.x * (.73 if portrait else .66) + (1.0 - ease_in) * size.x * .20, center_y - band_height * .02)
	var name_size := _fit_font_size(font, skill_name, clampi(roundi(band_height * .24), 22, 150), size.x * (.46 if portrait else .56))
	var outline_ink := accent.darkened(.72)
	Ornament.centered_text(self, font, text_center, skill_name, name_size, Color(1.0, .96, .86, text_alpha), maxi(5, roundi(name_size * .10)), Color(outline_ink.r, outline_ink.g, outline_ink.b, text_alpha))
	var small := clampi(roundi(band_height * .10), 14, 60)
	Ornament.centered_text(self, font, text_center + Vector2(0, -band_height * .27), "ULTIMATE", small, Ornament.tint(Ornament.GOLD, text_alpha), 3, Color(0, 0, 0, .7 * text_alpha))
	var name_ink := accent.lightened(.35)
	Ornament.centered_text(self, font, text_center + Vector2(0, band_height * .26), unit_display_name(source), small, Color(name_ink.r, name_ink.g, name_ink.b, text_alpha), 3, Color(0, 0, 0, .7 * text_alpha))
	if long and clock < .16:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, (1.0 - clock / .16) * .55))
