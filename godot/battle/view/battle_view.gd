class_name BattleView
extends Control

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
var floating_texts: Array = []
var projectiles: Array = []
var free_floating_texts: Array = []
var free_projectiles: Array = []
var unit_flash: Dictionary = {}
var sprite_library := BattleSpriteLibrary.new()
var sprite_pack_ready := false
var projectile_library := ProjectileSpriteLibrary.new()
var projectile_pack_ready := false
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
var battle_font: Font
const MAX_PRESENTATION_SPEED := 1.35
const MAX_EVENTS_PER_FRAME := 48
const MAX_ACTIVE_PROJECTILES := 24
const MAX_ACTIVE_FLOATING_TEXTS := 40
const MAX_ACTIVE_VFX := 32
const BOSS_PATTERN_CARD_PREFIX := "BOSS_PATTERN"
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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Adding BattleView to the scene tree used to synchronously decode every wave's
	# combat, projectile and VFX atlas before the browser could paint even one
	# battlefield frame. Keep the deterministic simulation stopped, allow the
	# responsive shell to paint, then warm one entity at a time on later frames.
	assets_ready = false
	asset_warmup_phase = "SHELL"
	set_process(false)
	queue_redraw()
	call_deferred("_warm_battle_assets")

func _warm_battle_assets() -> void:
	if simulation == null or not is_inside_tree():
		_finish_asset_warmup()
		return
	var current_entity_ids := _current_wave_entity_ids()
	var reinforcement_entity_ids := _reinforcement_entity_ids(current_entity_ids)
	var active_entity_ids := _active_battle_entity_ids()
	_reset_battle_asset_state()

	# Chapter-map entry may have completed the exact same immutable pack already.
	# Reattach its manifests and atlas-backed frame views before scheduling any
	# ResourceLoader work, so a map-to-battle handoff never decodes a second copy.
	if _attach_stage_asset_cache_bundle(active_entity_ids):
		asset_warmup_phase = "CACHE_READY"
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
	_load_combat_preview_fallbacks(active_entity_ids)
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
	battle_font = load("res://assets/fonts/NotoSansKR-VF.ttf") as Font
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

	# No load occurs after this gate. All later SPAWN events only register motion
	# tracks, so reinforcement waves cannot reintroduce a synchronous Web hitch or
	# fall through to a grey code silhouette.
	asset_warmup_phase = "READY"
	_finish_asset_warmup()

func _reset_battle_asset_state() -> void:
	asset_cache_hit = false
	sprite_library.manifests.clear()
	sprite_library.frames.clear()
	sprite_library.load_error = ""
	projectile_library.manifests.clear()
	projectile_library.frames.clear()
	projectile_library.load_error = ""
	vfx_frames.clear()
	runtime_vfx_entries.clear()
	runtime_vfx_manifest_loaded = false
	fallback_combat_previews.clear()
	sprite_pack_ready = false
	projectile_pack_ready = false

func _finish_asset_warmup() -> void:
	assets_ready = true
	if asset_input_blocker != null:
		asset_input_blocker.queue_free()
		asset_input_blocker = null
	set_process(true)
	queue_redraw()
	battle_assets_ready.emit()

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
	return "전장 구성"

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
	accumulator = 0.0
	emitted_finish = false
	skip_in_progress = false
	consumed_events = 0
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
	animation_tracks.clear()
	entry_tracks.clear()
	for unit in simulation.state.party + simulation.state.enemies:
		animation_tracks[unit.uid] = {"name": "move", "elapsed": 0.0}
		entry_tracks[unit.uid] = 0.0
	queue_redraw()

func skip_to_result() -> bool:
	## Skip only presentation time.  The live simulation advances to its real
	## terminal result, then emits the ordinary finish signal exactly once so the
	## existing reward/map/save transaction remains the sole authority.
	if simulation == null or emitted_finish or skip_in_progress:
		return false
	skip_in_progress = true
	if not simulation.advance_to_terminal():
		skip_in_progress = false
		return false
	# Thousands of fast-forwarded events must not be replayed as a one-frame VFX
	# storm if the result screen transition is delayed by a frame.
	consumed_events = simulation.event_log.size()
	emitted_finish = true
	battle_finished.emit(simulation.result_snapshot())
	return true

func _process(delta: float) -> void:
	if simulation == null: return
	if not paused and not simulation.state.ended:
		accumulator += delta * speed
		var safety := 0
		while accumulator >= BattleSimulation.TICK_DELTA and safety < 30:
			simulation.tick()
			accumulator -= BattleSimulation.TICK_DELTA
			safety += 1
	if not paused:
		# Simulation remains exact at the selected 1x/2x/3x speed.  Presentation
		# deliberately has a readable upper speed so NORMAL/ULT events never become
		# a one-frame flash at 3x.
		var presentation_delta := delta * minf(float(speed), MAX_PRESENTATION_SPEED)
		_advance_animations(presentation_delta)
		_advance_entries(presentation_delta)
	_consume_events()
	for text in floating_texts:
		text.age = float(text.age) + delta
	if not paused:
		for projectile in projectiles:
			projectile.age = float(projectile.age) + delta * minf(float(speed), 1.8)
		for presentation in vfx_presentations:
			presentation.age = float(presentation.age) + delta * minf(float(speed), MAX_PRESENTATION_SPEED)
		for callout in skill_callouts:
			callout.age = float(callout.age) + delta * minf(float(speed), MAX_PRESENTATION_SPEED)
		for presentation in boss_phase_presentations:
			presentation.age = float(presentation.age) + delta * minf(float(speed), MAX_PRESENTATION_SPEED)
	_recycle_expired_presentations()
	for uid in unit_flash.keys():
		unit_flash[uid] = float(unit_flash[uid]) - delta
		if float(unit_flash[uid]) <= 0: unit_flash.erase(uid)
	queue_redraw()
	if simulation.state.ended and not emitted_finish:
		emitted_finish = true
		battle_finished.emit(simulation.result_snapshot())

func _consume_events() -> void:
	var processed_this_frame := 0
	while consumed_events < simulation.event_log.size() and processed_this_frame < MAX_EVENTS_PER_FRAME:
		var event: Dictionary = simulation.event_log[consumed_events]
		consumed_events += 1
		processed_this_frame += 1
		if event.type == BattleEvent.DAMAGE:
			_spawn_floating_text({"target": event.target, "text": "MISS" if int(event.value) == 0 else ("CRIT %d" % event.value if event.extra.get("crit", false) else str(event.value)), "color": Color("ffd166") if event.extra.get("crit", false) else Color.WHITE, "age": 0.0})
			unit_flash[event.target] = .14
			if damage_event_has_hit_sfx(event):
				var hit_unit := simulation.find_unit(str(event.target))
				if not hit_unit.is_empty():
					if str(hit_unit.team) == "PLAYER": AudioService.play_event("PLAYER_HIT", .06)
					elif str(hit_unit.get("rank", "NORMAL")) == "BOSS": AudioService.play_event("BOSS_HIT", .06)
					else: AudioService.play_event("ENEMY_HIT", .06)
			if int(event.value) > 0:
				var damage_source := str(event.extra.get("source", ""))
				# Presentation can consume a burst of events after simulation has
				# already advanced.  Never replay a cast projectile from a unit that
				# is now DOWN; otherwise a collapsed enemy visibly attacks from the
				# ground even though the model correctly killed it.
				if damage_source in ["NORMAL", "ULTIMATE"] and _action_source_is_presentable(str(event.source)):
					_spawn_projectile(str(event.source), str(event.target), damage_source)
					# Contact starts only after charge plus the complete projectile flight.
					_spawn_vfx(str(event.source), str(event.target), "impact_%s" % damage_source.to_lower(), .50 if damage_source == "NORMAL" else .72)
				var damaged := simulation.find_unit(str(event.target))
				if not damaged.is_empty() and UnitState.alive(damaged): _play_animation(str(event.target), "hit")
		elif event.type == BattleEvent.HEAL:
			_spawn_floating_text({"target": event.target, "text": "+%d" % event.value, "color": Color("76e6a5"), "age": 0.0})
			_spawn_vfx(str(event.source), str(event.target), "heal")
		elif event.type == BattleEvent.SHIELD:
			_spawn_floating_text({"target": event.target, "text": "SHIELD %d" % event.value, "color": Color("72d5ff"), "age": 0.0})
			_spawn_vfx(str(event.source), str(event.target), "shield")
		elif event.type == BattleEvent.BASIC_ATTACK:
			var basic_source := simulation.find_unit(str(event.source))
			if not _action_source_is_presentable(str(event.source)):
				continue
			if str(basic_source.team) == "PLAYER": AudioService.play_event("PLAYER_BASIC_ATTACK", .05)
			elif str(basic_source.get("rank", "NORMAL")) == "BOSS": AudioService.play_event("BOSS_BASIC_ATTACK", .05)
			else: AudioService.play_event("ENEMY_BASIC_ATTACK", .05)
			_spawn_projectile(str(event.source), str(event.target), "BASIC")
			_spawn_vfx(str(event.source), str(event.target), "basic")
			_play_animation(str(event.source), "basic_attack")
		elif event.type == BattleEvent.NORMAL_SKILL:
			var skill_source := simulation.find_unit(str(event.source))
			if not _action_source_is_presentable(str(event.source)):
				continue
			var skill_fallback_event := "PLAYER_NORMAL_SKILL" if str(skill_source.team) == "PLAYER" else ("BOSS_SKILL" if str(skill_source.get("rank", "NORMAL")) == "BOSS" else "ENEMY_SKILL")
			AudioService.play_card_start(card_start_id_for_event(event, skill_source), skill_fallback_event, .10)
			_spawn_skill_callout(str(event.source), "SKILL", Color("79e8ff"))
			_spawn_vfx(str(event.source), str(event.target), "normal")
			_play_animation(str(event.source), "normal_skill")
		elif event.type == BattleEvent.ULTIMATE:
			var ultimate_source := simulation.find_unit(str(event.source))
			if not _action_source_is_presentable(str(event.source)):
				continue
			var ultimate_fallback_event := "PLAYER_ULTIMATE" if str(ultimate_source.team) == "PLAYER" else ("BOSS_SKILL" if str(ultimate_source.get("rank", "NORMAL")) == "BOSS" else "ENEMY_SKILL")
			AudioService.play_card_start(card_start_id_for_event(event, ultimate_source), ultimate_fallback_event, .12)
			_spawn_skill_callout(str(event.source), "ULT", Color("ffd36f"))
			_spawn_vfx(str(event.source), str(event.target), "ultimate")
			_play_animation(str(event.source), "ultimate")
		elif event.type == BattleEvent.DOWN:
			_play_animation(str(event.target), "down")
		elif event.type == BattleEvent.SPAWN:
			animation_tracks[event.source] = {"name": "move", "elapsed": 0.0}
			entry_tracks[event.source] = 0.0
		elif event.type == BattleEvent.STATUS:
			var phase_id := str(event.extra.get("phase", ""))
			if BOSS_PHASE_PRESENTATION.has(phase_id):
				_spawn_boss_phase_presentation(str(event.source), phase_id)
		elif event.type == BattleEvent.BATTLE_END and int(event.value) == 1:
			for unit in simulation.state.party:
				if UnitState.alive(unit): _play_animation(str(unit.uid), "victory")

func _spawn_projectile(source_uid: String, target_uid: String, attack_kind: String) -> void:
	var source := simulation.find_unit(source_uid)
	if source.is_empty(): return
	var source_id := str(source.get("def_id", ""))
	var duration := projectile_library.duration(source_id) if projectile_pack_ready else .32
	# Asset projectile loops stay fast for basic fire, while skill shots remain
	# visible long enough to read their travel and endpoint impact.
	if attack_kind == "NORMAL": duration = maxf(duration, .28)
	elif attack_kind == "ULTIMATE": duration = maxf(duration, .42)
	var launch_delay := .18 if attack_kind == "NORMAL" else (.28 if attack_kind == "ULTIMATE" else .04)
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

func _spawn_floating_text(data: Dictionary) -> void:
	var item: Dictionary = free_floating_texts.pop_back() if not free_floating_texts.is_empty() else {}
	item.clear()
	item.merge(data)
	if floating_texts.size() >= MAX_ACTIVE_FLOATING_TEXTS:
		free_floating_texts.append(floating_texts.pop_front())
	floating_texts.append(item)

func _spawn_vfx(source_uid: String, target_uid: String, kind: String, delay := 0.0) -> void:
	var source := simulation.find_unit(source_uid)
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
	_append_vfx_presentation(source_uid, target_uid, kind, key, delay, profile, Color.WHITE, kind in ["normal", "ultimate"])

func _append_vfx_presentation(source_uid: String, target_uid: String, kind: String, key: String, delay: float, profile: Dictionary, tint: Color, draw_accent: bool) -> void:
	var presentation: Dictionary = free_vfx_presentations.pop_back() if not free_vfx_presentations.is_empty() else {}
	presentation.clear()
	var duration := 0.40
	if kind == "normal": duration = 0.24
	elif kind in ["ultimate", "ultimate_base"]: duration = .32
	elif kind == "impact_normal": duration = .34
	elif kind == "impact_ultimate": duration = .48
	elif kind in ["heal", "shield"]: duration = .56
	presentation.merge({"source": source_uid, "target": target_uid, "kind": kind, "key": key, "textured": vfx_frames.has(key), "age": 0.0, "delay": delay, "duration": duration, "profile": profile, "tint": tint, "draw_accent": draw_accent})
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

func _spawn_skill_callout(source_uid: String, label: String, color: Color) -> void:
	var item: Dictionary = free_skill_callouts.pop_back() if not free_skill_callouts.is_empty() else {}
	item.clear()
	item.merge({"source": source_uid, "label": label, "color": color, "age": 0.0, "duration": 0.78})
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
		if float(floating_texts[index].age) >= 1.0:
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

func pool_diagnostics() -> Dictionary:
	return {"active_projectiles": projectiles.size(), "free_projectiles": free_projectiles.size(), "active_floating_texts": floating_texts.size(), "free_floating_texts": free_floating_texts.size(), "active_vfx": vfx_presentations.size(), "free_vfx": free_vfx_presentations.size(), "active_skill_callouts": skill_callouts.size(), "free_skill_callouts": free_skill_callouts.size(), "active_boss_phase_presentations": boss_phase_presentations.size(), "free_boss_phase_presentations": free_boss_phase_presentations.size()}

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

func _play_animation(uid: String, animation_name: String) -> void:
	if animation_name not in ["down", "victory"] and not _action_source_is_presentable(uid):
		return
	animation_tracks[uid] = {"name": animation_name, "elapsed": 0.0}

func _action_source_is_presentable(uid: String) -> bool:
	if simulation == null or uid.is_empty():
		return false
	var source := simulation.find_unit(uid)
	return not source.is_empty() and UnitState.alive(source) and str(source.get("state", "")) != "DOWN"

func _advance_animations(delta: float) -> void:
	for uid in animation_tracks:
		var track: Dictionary = animation_tracks[uid]
		track.elapsed = float(track.get("elapsed", 0.0)) + delta
		var animation_name := str(track.get("name", "idle"))
		var unit := simulation.find_unit(str(uid))
		var character_id := str(unit.get("def_id", ""))
		if sprite_pack_ready and sprite_library.supports_character(character_id) and not sprite_library.is_looping(character_id, animation_name):
			var duration := sprite_library.duration(character_id, animation_name)
			if duration > 0.0 and float(track.elapsed) >= duration and animation_name not in ["down", "victory"]:
				track.name = "move" if float(entry_tracks.get(uid, 1.0)) < 1.0 else "idle"
				track.elapsed = 0.0
		animation_tracks[uid] = track

func _advance_entries(delta: float) -> void:
	for uid in entry_tracks:
		entry_tracks[uid] = minf(1.0, float(entry_tracks[uid]) + delta / 0.9)
		if float(entry_tracks[uid]) >= 1.0:
			var track: Dictionary = animation_tracks.get(uid, {})
			if str(track.get("name", "")) == "move": animation_tracks[uid] = {"name": "idle", "elapsed": 0.0}

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var background := boss_background if _boss_present() else normal_background
	if background != null: draw_texture_rect(background, rect, false)
	else: draw_rect(rect, Color("101b35"))
	draw_rect(rect, Color(0.02, 0.04, 0.09, 0.16))
	if not assets_ready:
		# Keep the first painted shell honest: actors are not drawn as temporary
		# silhouettes while their immutable atlases are still being registered.
		var warmup_font := battle_font if battle_font != null else ThemeDB.fallback_font
		var warmup_text := "LUMENBOUND · %s" % _asset_warmup_display_label()
		draw_string(warmup_font, Vector2(0, size.y * .54), warmup_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color("9ddfd4"))
		return
	if simulation == null:
		return
	for unit in simulation.state.party + simulation.state.enemies:
		_draw_unit(unit)
	for projectile in projectiles:
		var source := simulation.find_unit(projectile.source)
		var target := simulation.find_unit(projectile.target)
		if source.is_empty() or target.is_empty(): continue
		var launch_delay := float(projectile.get("delay", 0.0))
		if float(projectile.age) < launch_delay:
			continue
		var duration := float(projectile.get("duration", .4))
		var t := clampf((float(projectile.age) - launch_delay) / maxf(.01, duration), 0, 1)
		var source_position := _projectile_origin(source)
		var target_position := _projectile_target(target)
		var position := source_position.lerp(target_position, t) + Vector2(0, -24.0 * sin(t * PI))
		var source_id := str(projectile.get("source_id", ""))
		var texture := projectile_library.texture_at(source_id, float(projectile.age)) if projectile_pack_ready else null
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
			var travel_frames: Array = vfx_frames.get(travel_key, [])
			if not travel_frames.is_empty():
				var travel_frame := mini(travel_frames.size() - 1, 2 + int(floor(t * 7.0)))
				var travel_size := Vector2(112, 112) if attack_kind == "ULTIMATE" else Vector2(82, 82)
				draw_texture_rect(travel_frames[travel_frame], Rect2(position - travel_size * .5, travel_size), false, Color(1.0, 1.0, 1.0, .76))
		if texture != null:
			var projectile_size := projectile_library.runtime_size(source_id)
			if attack_kind == "ULTIMATE": projectile_size *= 1.24
			elif attack_kind == "NORMAL": projectile_size *= 1.10
			draw_texture_rect(texture, Rect2(position - projectile_size * .5, projectile_size), false)
		else:
			draw_circle(position, 8, Color("fff3a6") if source.team == "PLAYER" else Color("ff8c8c"))
	for presentation in vfx_presentations:
		var source := simulation.find_unit(str(presentation.source))
		var target := simulation.find_unit(str(presentation.get("target", "")))
		if source.is_empty(): continue
		var textures: Array = vfx_frames.get(str(presentation.key), [])
		var delay := float(presentation.get("delay", 0.0))
		if float(presentation.age) < delay: continue
		var progress := clampf((float(presentation.age) - delay) / maxf(0.01, float(presentation.duration)), 0.0, 0.999)
		var kind := str(presentation.get("kind", "basic"))
		var targets_contact := kind.begins_with("impact_") or kind in ["heal", "shield"]
		var anchor_unit := target if targets_contact and not target.is_empty() else source
		var position := _unit_pos(anchor_unit) + _entry_offset(anchor_unit) + Vector2(0, -72)
		if not targets_contact:
			# Cast light belongs to the weapon/ground of the acting unit; it must not
			# appear as a full-image sticker over the unit being attacked.
			var cast_direction := 1.0 if str(source.get("team", "")) == "PLAYER" else -1.0
			position = _unit_pos(source) + _entry_offset(source) + Vector2(cast_direction * 34.0, -38.0)
		if not textures.is_empty():
			var frame := mini(textures.size() - 1, int(floor(progress * textures.size())))
			if kind.begins_with("impact_"):
				frame = mini(textures.size() - 1, 6 + int(floor(progress * maxi(1, textures.size() - 6))))
			elif kind in ["normal", "ultimate", "ultimate_base"]:
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
			var tint: Color = presentation.get("tint", Color.WHITE)
			tint.a = minf(tint.a, .82)
			draw_texture_rect(textures[frame], Rect2(position - vfx_size * 0.5, vfx_size), false, tint)
			if bool(presentation.get("draw_accent", false)):
				_draw_vfx_signature_accent(position, kind, progress, presentation.get("profile", {}))
		else:
			# Pooled vector stages remain below the actor silhouette and connect the
			# cast, projectile trail, endpoint contact and hit reaction visibly.
			_draw_runtime_skill_vfx(position, source, kind, progress)
			if bool(presentation.get("draw_accent", false)):
				_draw_vfx_signature_accent(position, kind, progress, presentation.get("profile", {}))
	for callout in skill_callouts:
		var caster := simulation.find_unit(str(callout.source))
		if caster.is_empty(): continue
		var alpha := clampf(1.0 - float(callout.age) / maxf(.01, float(callout.duration)), 0.0, 1.0)
		var callout_position := _unit_pos(caster) + _entry_offset(caster) + Vector2(-30, -168 - float(callout.age) * 24.0)
		var callout_color: Color = callout.color
		callout_color.a = alpha
		draw_rect(Rect2(callout_position, Vector2(62, 24)), Color(0.03, 0.08, 0.15, alpha * .88), true)
		draw_rect(Rect2(callout_position, Vector2(62, 24)), callout_color, false, 1.5)
		var callout_font := battle_font if battle_font != null else ThemeDB.fallback_font
		draw_string(callout_font, callout_position + Vector2(8, 18), str(callout.label), HORIZONTAL_ALIGNMENT_CENTER, 46, 16, callout_color)
	for presentation in boss_phase_presentations:
		_draw_boss_phase_presentation(presentation)
	for text in floating_texts:
		var target := simulation.find_unit(text.target)
		if target.is_empty(): continue
		var position := _unit_pos(target) + Vector2(-34, -125 - float(text.age) * 40)
		var floating_font := battle_font if battle_font != null else ThemeDB.fallback_font
		draw_string(floating_font, position, text.text, HORIZONTAL_ALIGNMENT_CENTER, 72, 24, text.color)

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
	var boss := simulation.find_unit(str(presentation.source)) if simulation != null else {}
	if not boss.is_empty():
		var boss_position := _unit_pos(boss) + _entry_offset(boss) + Vector2(0, -92)
		var pulse := 56.0 + 34.0 * sin(clampf(progress / .44, 0.0, 1.0) * PI)
		draw_circle(boss_position, pulse, Color(accent.r, accent.g, accent.b, .10 * visibility))
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
		draw_circle(position, impact_radius, Color(color.r, color.g, color.b, .22 * fade))
		draw_arc(position, impact_radius, -progress * 2.6, TAU - progress * 2.6, 32, Color(color.r, color.g, color.b, .92 * fade), 4.0 if ultimate else 2.8, true)
		draw_arc(position, impact_radius * .56, progress * 4.1, TAU + progress * 4.1, 24, Color(1.0, .98, .84, .86 * fade), 2.0, true)
		var shards := 12 if ultimate else 8
		for index in range(shards):
			var angle := TAU * float(index) / float(shards) + progress * .55
			var origin := position + Vector2(cos(angle), sin(angle)) * impact_radius * .18
			var tip := position + Vector2(cos(angle), sin(angle)) * impact_radius * (1.08 + progress * .38)
			draw_line(origin, tip, Color(color.r, color.g, color.b, .86 * fade), 3.0 if ultimate else 2.0, true)
		draw_circle(position, 9.0 + impact * 10.0, Color(1.0, 1.0, 1.0, .90 * fade))
		return
	if kind == "heal":
		var heal_radius := 30.0 + impact * 24.0
		draw_circle(position, heal_radius, Color(.32, 1.0, .72, .16 * fade))
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
	draw_circle(position + Vector2(0, 18), radius * .84, glow)
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
					draw_circle(ember, 3.2, secondary)
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
					draw_circle(impact, 3.0, secondary)
		"distort", "dust", "void":
			for index in range(3):
				var local_radius := radius * (.42 + float(index) * .22)
				var angle := progress * TAU * (1.6 if shape != "void" else -2.3) + index * 1.2
				draw_arc(position, local_radius, angle, angle + PI * 1.45, 22, primary if index != 1 else secondary, 2.6, true)
			if shape == "void":
				draw_circle(position, radius * .24, Color(.04, .06, .14, .44 * fade))
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
			draw_circle(position, radius * (.12 + rupture_phase * .20), Color(.025, .04, .11, .78 * fade))
			if rupture_phase > .12:
				draw_circle(position, radius * (.10 + rupture_phase * .18), Color(1.0, 1.0, 1.0, .68 * fade))
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
			draw_circle(position, radius * (.07 + peak * .12), Color(1.0, 1.0, 1.0, .68 * fade))
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
				draw_circle(position, radius * (.10 + overload_phase * .15), Color(1.0, 1.0, 1.0, .74 * fade))
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
				draw_circle(node, 4.0 + form_phase * 3.4, Color(secondary.r, secondary.g, secondary.b, .76 * fade))
			draw_circle(position, radius * (.10 + form_phase * .18 - collapse_phase * .08), Color(primary.r, primary.g, primary.b, .34 * fade))
			draw_circle(position, radius * (.05 + form_phase * .08), Color(1.0, 1.0, 1.0, .72 * fade))
		"heal", "barrier_mend":
			for index in range(3):
				var heal_y := position.y + radius * .32 - float(index) * radius * .25 - progress * radius * .24
				draw_arc(Vector2(position.x, heal_y), radius * (.42 + index * .16), PI * .08, PI * .92, 20, primary, 2.7, true)
			draw_circle(position, radius * .18, secondary)
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
	if simulation == null: return false
	for enemy in simulation.state.enemies:
		if str(enemy.get("rank", "")) == "BOSS" and UnitState.alive(enemy): return true
	return false

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

func _draw_unit(unit: Dictionary) -> void:
	var p := _unit_pos(unit)
	var player: bool = str(unit.team) == "PLAYER"
	var alive := UnitState.alive(unit)
	var color := _character_color(unit.slot) if player else _enemy_color(unit.rank)
	if not alive: color = color.darkened(.65)
	if unit_flash.has(unit.uid): color = Color.WHITE
	p += _entry_offset(unit)
	if unit_flash.has(unit.uid):
		var hit_phase := clampf(float(unit_flash[unit.uid]) / .14, 0.0, 1.0)
		p.x += (-9.0 if player else 9.0) * sin(hit_phase * PI)
		p.y -= 3.0 * sin(hit_phase * PI)
	var generated_sprite := (sprite_pack_ready and sprite_library.supports_character(str(unit.def_id))) or fallback_combat_previews.has(str(unit.def_id))
	var bob := sin(Time.get_ticks_msec() / 180.0 + int(unit.slot)) * 3.0 if alive and not generated_sprite else 0.0
	p.y += bob
	# Generated CHR001 frames contain their own motion. Every remaining
	# code-native DEV placeholder receives the same event-driven directional
	# pose offset so all five allies and all enemies visibly animate.
	if not generated_sprite:
		p += _placeholder_pose_offset(unit)
	_draw_ellipse_polygon(p + Vector2(0, 12), Vector2(42, 12), Color(0, 0, 0, .35))
	if _draw_combat_sprite(unit, p, alive):
		pass
	elif player:
		_draw_player_sd(p, color, str(unit.role), alive)
	elif unit.rank == "BOSS":
		# Bosses deploy on the right and visibly face screen-left. The forward
		# sensor, jaw, and attack core all sit on the left side of the chassis.
		draw_circle(p + Vector2(8, -48), 62, color)
		draw_rect(Rect2(p + Vector2(-40, -35), Vector2(96, 70)), color.darkened(.15))
		var boss_jaw := PackedVector2Array([p + Vector2(-62, -67), p + Vector2(-28, -81), p + Vector2(-30, -45), p + Vector2(-66, -48)])
		draw_colored_polygon(boss_jaw, color.lightened(.08))
		draw_circle(p + Vector2(-29, -65), 9, Color("ffdf6b"))
		draw_circle(p + Vector2(-49, -57), 5, Color("ff7a70"))
	else:
		_draw_nonhuman_enemy(p, color, str(unit.role), alive)
	var bar_width := 96.0 if unit.rank != "BOSS" else 150.0
	var hp_ratio := UnitState.hp_ratio(unit)
	var head_position := _head_position(unit, p)
	var bar_origin := head_position + Vector2(-bar_width / 2.0, -18)
	draw_rect(Rect2(bar_origin, Vector2(bar_width, 9)), Color("351e2b"))
	draw_rect(Rect2(bar_origin, Vector2(bar_width * hp_ratio, 9)), Color("62e49b") if player else Color("ff6868"))
	if int(unit.shield) > 0:
		var shield_ratio := minf(1.0, float(unit.shield) / maxf(1.0, float(unit.max_hp)))
		draw_rect(Rect2(bar_origin + Vector2(0, 12), Vector2(bar_width * shield_ratio, 5)), Color("6ecfff"))
	var label := unit_display_name(unit)
	var label_font := battle_font if battle_font != null else ThemeDB.fallback_font
	draw_string(label_font, p + Vector2(-55, 46), label, HORIZONTAL_ALIGNMENT_CENTER, 110, 16, Color("dbe9ff"))

func _draw_combat_sprite(unit: Dictionary, p: Vector2, alive: bool) -> bool:
	var character_id := str(unit.def_id)
	var has_animation_pack := sprite_pack_ready and sprite_library.supports_character(character_id)
	if not has_animation_pack and not fallback_combat_previews.has(character_id):
		return false
	var track: Dictionary = animation_tracks.get(unit.uid, {"name": "idle", "elapsed": 0.0})
	var animation_name := "down" if not alive else str(track.get("name", "idle"))
	var texture: Texture2D = sprite_library.texture_at(character_id, animation_name, float(track.get("elapsed", 0.0))) if has_animation_pack else fallback_combat_previews.get(character_id)
	if texture == null:
		return false
	var scale := 0.44 if str(unit.team) == "PLAYER" else 0.42
	# Runtime atlases use a smaller canvas but retain the immutable 512px
	# gameplay anchor.  Scale from the authored canvas so Web compaction never
	# shrinks a real character back into a code-placeholder silhouette.
	var destination_size := Vector2(512.0, 512.0) * scale
	var top_left := p - Vector2(256.0 * scale, 512.0 * .88 * scale)
	var modulate := Color(1.0, .72, .72, 1.0) if unit_flash.has(unit.uid) else Color.WHITE
	var desired_faces_right := str(unit.team) == "PLAYER"
	var source_faces_right := sprite_library.source_faces_right(character_id) if has_animation_pack else character_id.begins_with("CHR")
	if desired_faces_right != source_faces_right:
		# Mirror around the immutable foot anchor, then immediately restore the
		# canvas transform so HP bars, labels and later units are never reversed.
		draw_set_transform(p, 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(texture, Rect2(Vector2(-256.0 * scale, -512.0 * .88 * scale), destination_size), false, modulate)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(texture, Rect2(top_left, destination_size), false, modulate)
	return true

func _draw_player_sd(p: Vector2, color: Color, role: String, alive: bool) -> void:
	# Code-native DEV_PLACEHOLDER. The player silhouette is explicitly an adult
	# woman: four-head proportions, long legs/hair, mature waist/hip line, bare
	# shoulders and midriff, with opaque chest/groin coverage.
	var skin := Color("f3c2ad") if alive else Color("806960")
	var hair := color.darkened(.38)
	var suit := color.darkened(.08)
	var trim := color.lightened(.34)
	# Long hair and ponytail behind the body.
	draw_circle(p + Vector2(11, -86), 29, hair)
	draw_line(p + Vector2(24, -82), p + Vector2(38, -18), hair, 18.0, true)
	draw_circle(p + Vector2(40, -14), 10, hair)
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
	draw_circle(p + Vector2(4, -101), 27, hair)
	draw_circle(p + Vector2(5, -96), 22, skin)
	draw_circle(p + Vector2(1, -99), 2.3, Color("17243b"))
	draw_circle(p + Vector2(14, -97), 3.7, Color("17243b"))
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
		draw_circle(p + Vector2(34, -55), 5.0, Color("f3c2ad"))
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
	draw_circle(p + Vector2(-40, -83), 4.0, Color("ffd166"))
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
	var points := PackedVector2Array()
	for i in range(24):
		var angle := TAU * i / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)

func _unit_pos(unit: Dictionary) -> Vector2:
	var slot := int(unit.slot)
	if str(unit.team) == "PLAYER":
		var player_columns := [0.14, 0.255, 0.37, 0.485, 0.60]
		var player_lanes := [0.68, 0.745, 0.785, 0.70, 0.755]
		return Vector2(size.x * float(player_columns[slot % player_columns.size()]), size.y * float(player_lanes[slot % player_lanes.size()]))
	var enemy_columns := [0.79, 0.91, 0.84]
	var enemy_column := float(enemy_columns[slot % enemy_columns.size()])
	var enemy_lane := 0.69 + (slot % 3) * 0.055
	return Vector2(size.x * enemy_column, size.y * enemy_lane)

func _projectile_origin(unit: Dictionary) -> Vector2:
	var foot := _unit_pos(unit) + _entry_offset(unit)
	if str(unit.team) == "PLAYER": return foot + Vector2(46, -82)
	return foot + Vector2(-46, -72)

func _projectile_target(unit: Dictionary) -> Vector2:
	var foot := _unit_pos(unit) + _entry_offset(unit)
	return foot + Vector2(0, -72)

func _entry_offset(unit: Dictionary) -> Vector2:
	var progress := clampf(float(entry_tracks.get(unit.uid, 1.0)), 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	var direction := -1.0 if str(unit.team) == "PLAYER" else 1.0
	return Vector2(direction * 150.0 * (1.0 - eased), -8.0 * sin(progress * PI))

func _head_position(unit: Dictionary, foot_position: Vector2) -> Vector2:
	var character_id := str(unit.get("def_id", ""))
	if sprite_pack_ready and sprite_library.supports_character(character_id):
		var anchor := sprite_library.head_anchor(character_id)
		var scale := 0.44 if str(unit.team) == "PLAYER" else 0.42
		return foot_position + Vector2((anchor.x - 0.5) * 512.0 * scale, -(0.88 - anchor.y) * 512.0 * scale)
	if str(unit.get("rank", "")) == "BOSS": return foot_position + Vector2(0, -158)
	return foot_position + Vector2(0, -128)

func _character_color(slot: int) -> Color:
	return [Color("5ed6c0"), Color("ff9b73"), Color("75a7ff"), Color("e788ff"), Color("ffd166")][slot % 5]

func _enemy_color(rank: String) -> Color:
	if rank == "BOSS": return Color("b54d67")
	if rank == "ELITE": return Color("a46bd4")
	return Color("6f7f98")
