extends Node

## Real-window QA for the bounded high-density combat group. This tool never
## exports, deploys, or changes game data; it stages the actual starting
## five-player R13 group (CHR001/002/003/004/005) against BOSS001 plus
## native-512px ENM001 in an in-memory paused battle view. Every staged member
## is captured through the actual CanvasItem draw path at a phone viewport
## before the candidate can advance beyond local QA.

const BOOT_SCENE := preload("res://screens/boot/boot.tscn")
## R13's immutable candidate inventory retains CHR008 for an alternate-party
## review, but this actual starting-five capture must never decode it. Keeping
## those two lists separate is part of the state-paging contract, not a report
## cosmetic: an available candidate is not an encounter resident page.
const SIGNATURE_CANDIDATE_IDS: Array[String] = ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005", "CHR008", "BOSS001", "ENM001"]
const PLAYER_SIGNATURE_IDS: Array[String] = ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005"]
const ACTIVE_RESIDENT_IDS: Array[String] = ["CHR001", "CHR002", "CHR003", "CHR004", "CHR005", "BOSS001", "ENM001"]
const CAPTURE_ULTIMATE_ENTITY_IDS: Array[String] = ACTIVE_RESIDENT_IDS

var shell: Control
var battle_view: BattleView
var output_dir := ""
var captures: Array[Dictionary] = []
var ultimate_page_checks: Dictionary = {}
var camera_motion_checks: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().root.size = Vector2i(390, 844)
	output_dir = ProjectSettings.globalize_path("res://../reports/art_qa/%s" % _run_id())
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		_finish(2, "SIGNATURE_QA_OUTPUT_DIR_FAILED")
		return
	shell = BOOT_SCENE.instantiate()
	get_tree().root.add_child(shell)
	await get_tree().process_frame
	await get_tree().process_frame
	# The normal boot scene owns a 53-second authored intro in a CanvasLayer.
	# This diagnostic enters the already-authorized local QA route directly, so
	# explicitly finish that overlay before creating a battle.  Waiting only for
	# BattleView.assets_ready would otherwise capture a valid battle behind the
	# still-visible intro layer and falsely certify the wrong pixels.
	shell.call("_finish_intro_video")
	await get_tree().process_frame
	await get_tree().process_frame
	AppState.selected_stage_id = "CH01-N20"
	shell.call("_show_screen", "BATTLE")
	if not await _await_battle_assets():
		_finish(3, "SIGNATURE_QA_BATTLE_ASSET_WARMUP_TIMEOUT")
		return
	battle_view.paused = true
	if not _stage_signature_party():
		_finish(5, "SIGNATURE_QA_PARTY_STAGING_FAILED")
		return
	# Explicitly warm only the bounded group this diagnostic stages, while leaving
	# game data, saves and the real stage definition unchanged. Match the runtime
	# entry contract exactly: the seven staged combatants keep
	# only idle/hit/down and their projectile pages. The real ULTIMATE event below
	# must acquire and later release one caster's high-density ultimate pair;
	# CHR008 remains an immutable candidate only and has zero runtime residency.
	battle_view.signature_sprite_pack_ready = battle_view.sprite_library.load_signature_core_pack(ACTIVE_RESIDENT_IDS)
	if not battle_view.signature_sprite_pack_ready:
		_finish(4, "SIGNATURE_QA_PACK_NOT_READY:%s" % battle_view.sprite_library.signature_load_error)
		return
	battle_view.effect_signature_pack_ready = battle_view.effect_signature_library.load_signature_core_pack(ACTIVE_RESIDENT_IDS)
	if not battle_view.effect_signature_pack_ready:
		_finish(10, "SIGNATURE_QA_EFFECT_PACK_NOT_READY:%s" % battle_view.effect_signature_library.signature_load_error)
		return
	battle_view.signature_residency_target_ids = ACTIVE_RESIDENT_IDS.duplicate()
	shell.call("_rebuild_battle_overlay")
	shell.call("_refresh_battle_ultimate_orb_art")
	var active_runtime_residency: Dictionary = battle_view.signature_runtime_residency_snapshot()
	var resident_actor_ids: Array = Array(active_runtime_residency.get("resident_actor_ids", []))
	var resident_effect_ids: Array = Array(active_runtime_residency.get("resident_effect_entity_ids", []))
	var resident_face_ids: Array = Array(active_runtime_residency.get("face_crop_entity_ids", []))
	var face_bytes_by_entity: Dictionary = active_runtime_residency.get("face_crop_resident_bytes_by_entity", {})
	var active_encounter_ids: Array = Array(active_runtime_residency.get("active_encounter_ids", []))
	# Simulation keeps enemies in their tactical slot order (ENM001 then BOSS001)
	# while the resident lease/report uses the stable canonical actor order above.
	# Ordering therefore must not disguise the actual negative assertion: CHR008
	# is absent from current actors, effects, and HUD face crops.
	var active_encounter_matches := active_encounter_ids.size() == ACTIVE_RESIDENT_IDS.size()
	for expected_entity_id in ACTIVE_RESIDENT_IDS:
		active_encounter_matches = active_encounter_matches and active_encounter_ids.has(expected_entity_id)
	var no_alternate_runtime_residency := resident_actor_ids == ACTIVE_RESIDENT_IDS and resident_effect_ids == ACTIVE_RESIDENT_IDS and active_encounter_matches and not active_encounter_ids.has("CHR008") and not resident_face_ids.has("CHR008") and int(face_bytes_by_entity.get("CHR008", 0)) == 0
	if not no_alternate_runtime_residency:
		_finish(12, "SIGNATURE_QA_ALTERNATE_RESIDENCY_CONTRACT_FAILED:%s" % JSON.stringify(active_runtime_residency))
		return
	var pause_center := shell.get("battle_pause_center") as Control
	if pause_center != null:
		pause_center.visible = false
	var guardian := _guardian()
	var roan := _player("CHR002")
	var narin := _player("CHR003")
	var eda := _player("CHR004")
	var soren := _player("CHR005")
	var boss := _boss()
	var rush_enemy := _rush_enemy()
	if guardian.is_empty() or roan.is_empty() or narin.is_empty() or eda.is_empty() or soren.is_empty() or boss.is_empty() or rush_enemy.is_empty():
		_finish(5, "SIGNATURE_QA_REFERENCE_GROUP_MISSING")
		return
	# The first frame proves ordinary on-screen idle uses the 384px signature
	# cell, not the compact 128px animation baseline.
	_set_track(str(guardian.uid), "idle", .22)
	_set_track(str(roan.uid), "idle", .25)
	_set_track(str(narin.uid), "idle", .28)
	_set_track(str(eda.uid), "idle", .30)
	_set_track(str(soren.uid), "idle", .31)
	_set_track(str(boss.uid), "idle", .31)
	_set_track(str(rush_enemy.uid), "idle", .31)
	battle_view.presentation_director.reset()
	await _capture("01_idle", "idle")
	# A full tactical gauge is staged only in the isolated QA simulation so the
	# circular HUD must render its small top READY badge as well as its partial
	# charge state in the first frame. This neither writes a save nor changes a
	# real roster or battle result.
	battle_view.simulation.state.tactical_gauge = 10.0
	shell.call("_update_battle_hud")

	# Drive each actual ULTIMATE event path rather than painting synthetic poses.
	# This exercises atomic one-caster state paging, charge VFX, high-density
	# ultimate/hit cells, and the view-only camera pulse on the genuine canvas.
	await _capture_player_ultimate(2, "CHR001", guardian, boss, false)

	# Down is a high-density presentation state as well.  It must remain legible
	# without leaving cinematic camera state alive after the test frame.
	battle_view._force_finish_active_presentation()
	_clear_capture_presentations()
	_set_track(str(guardian.uid), "idle", .54)
	_set_track(str(boss.uid), "down", .72)
	await _capture("05_boss_down", "boss_down")

	# Every remaining member stays in the same simultaneous five-person staging
	# group. No slot replacement is used: the captures prove actual occupancy,
	# small face-orb readability, and transient release between consecutive casts.
	await _capture_player_ultimate(6, "CHR002", roan, boss, false)
	await _capture_player_ultimate(9, "CHR003", narin, boss, false)
	await _capture_player_ultimate(12, "CHR004", eda, boss, false)
	await _capture_player_ultimate(15, "CHR005", soren, boss, false)

	# Verify the monster-side ultimate uses its own 224px signature rather than
	# inheriting a player effect.  Existing old presentations are cleared only
	# from this temporary QA canvas; no authored combat record is altered.
	battle_view._force_finish_active_presentation()
	_clear_capture_presentations()
	_start_boss_ultimate(boss, eda)
	_record_ultimate_page("BOSS001")
	var boss_windup_timeline: Dictionary = battle_view.presentation_director.advance(.62)
	battle_view._handle_presentation_timeline(boss_windup_timeline)
	_set_track(str(boss.uid), "ultimate", .62)
	_set_track(str(eda.uid), "idle", .46)
	_record_camera_motion("BOSS001", 1.0)
	_advance_vfx_for_capture(.12)
	await _capture("18_boss_ultimate_windup", "boss_ultimate_windup")
	var boss_impact_timeline: Dictionary = battle_view.presentation_director.advance(.51)
	battle_view._handle_presentation_timeline(boss_impact_timeline)
	_stage_projectiles(.50)
	_advance_vfx_for_capture(.14)
	await _capture("19_boss_ultimate_projectile_travel", "boss_ultimate_projectile_travel")
	_stage_projectiles(.70)
	_advance_vfx_for_capture(.12)
	await _capture("20_boss_ultimate_impact", "boss_ultimate_impact")

	# The common rush enemy is the first native-512px non-boss extension. Drive
	# its real ultimate event and movement/effect path explicitly so the mobile
	# screenshots prove it is not merely resident in the atlas manifest.
	battle_view._force_finish_active_presentation()
	_clear_capture_presentations()
	_start_enm001_ultimate(rush_enemy, guardian)
	_record_ultimate_page("ENM001")
	var rush_windup_timeline: Dictionary = battle_view.presentation_director.advance(.62)
	battle_view._handle_presentation_timeline(rush_windup_timeline)
	_set_track(str(rush_enemy.uid), "ultimate", .62)
	_set_track(str(guardian.uid), "idle", .46)
	_record_camera_motion("ENM001", 1.0)
	_advance_vfx_for_capture(.12)
	await _capture("21_enm001_ultimate_windup", "enm001_ultimate_windup")
	var rush_impact_timeline: Dictionary = battle_view.presentation_director.advance(.51)
	battle_view._handle_presentation_timeline(rush_impact_timeline)
	_set_track(str(rush_enemy.uid), "ultimate", 1.14)
	_set_track(str(guardian.uid), "hit", .38)
	_stage_projectiles(.50)
	_advance_vfx_for_capture(.14)
	await _capture("22_enm001_ultimate_projectile_travel", "enm001_ultimate_projectile_travel")
	_stage_projectiles(.70)
	_advance_vfx_for_capture(.12)
	await _capture("23_enm001_ultimate_impact", "enm001_ultimate_impact")
	battle_view._force_finish_active_presentation()
	var camera_motion_cleanup := is_equal_approx(battle_view.presentation_director.battlefield_zoom(), 1.0) and battle_view.presentation_director.battlefield_offset().length() <= .001
	var camera_motion_contract := camera_motion_cleanup and camera_motion_checks.size() == CAPTURE_ULTIMATE_ENTITY_IDS.size()
	for expected_entity_id in CAPTURE_ULTIMATE_ENTITY_IDS:
		camera_motion_contract = camera_motion_contract and bool((camera_motion_checks.get(expected_entity_id, {}) as Dictionary).get("passes", false))
	if not camera_motion_contract:
		_finish(13, "SIGNATURE_QA_CAMERA_MOTION_CONTRACT_FAILED:%s" % JSON.stringify(camera_motion_checks))
		return
	var transient_page_contract := true
	for expected_entity_id in CAPTURE_ULTIMATE_ENTITY_IDS:
		var page_record: Dictionary = ultimate_page_checks.get(expected_entity_id, {})
		transient_page_contract = transient_page_contract and bool(page_record.get("ready", false)) and str(page_record.get("actor_transient_entity_id", "")) == expected_entity_id and str(page_record.get("effect_transient_profile_id", "")) == battle_view.effect_signature_library.signature_profile_for(expected_entity_id) and int(page_record.get("actor_resident_atlas_bytes", 0)) <= int(page_record.get("actor_budget_bytes", 0)) and int(page_record.get("effect_resident_atlas_bytes", 0)) <= int(page_record.get("effect_budget_bytes", 0))
	if not transient_page_contract:
		_finish(11, "SIGNATURE_QA_TRANSIENT_PAGE_CONTRACT_FAILED:%s" % JSON.stringify(ultimate_page_checks))
		return
	var guardian_signature_size: Array = Array((ultimate_page_checks.get("CHR001", {}) as Dictionary).get("actor_texture_size", []))
	var roan_signature_size: Array = Array((ultimate_page_checks.get("CHR002", {}) as Dictionary).get("actor_texture_size", []))
	var narin_signature_size: Array = Array((ultimate_page_checks.get("CHR003", {}) as Dictionary).get("actor_texture_size", []))
	var eda_signature_size: Array = Array((ultimate_page_checks.get("CHR004", {}) as Dictionary).get("actor_texture_size", []))
	var soren_signature_size: Array = Array((ultimate_page_checks.get("CHR005", {}) as Dictionary).get("actor_texture_size", []))
	var boss_signature_size: Array = Array((ultimate_page_checks.get("BOSS001", {}) as Dictionary).get("actor_texture_size", []))
	var rush_enemy_signature_size: Array = Array((ultimate_page_checks.get("ENM001", {}) as Dictionary).get("actor_texture_size", []))
	var actor_technical_gate: Dictionary = battle_view.sprite_library.signature_approval.get("technical_gate", {})
	var effect_technical_gate: Dictionary = battle_view.effect_signature_library.signature_approval.get("technical_gate", {})
	var report := {
		"kind": "BATTLE_SIGNATURE_HD_LOCAL_VIEWPORT_QA",
		"approval_status": "LOCAL_QA_ONLY",
		"signature_revision": BattleSpriteLibrary.SIGNATURE_REVISION,
		"effect_signature_revision": EffectSignatureLibrary.SIGNATURE_REVISION,
		"viewport": [390, 844],
		"stage_source": "CH01-N20",
		"candidate_inventory_ids": SIGNATURE_CANDIDATE_IDS,
		"active_signature_units": _active_signature_units(),
		"active_core_resident_ids": ACTIVE_RESIDENT_IDS,
		"group_inventory_core_bytes": {
			"actor": int(actor_technical_gate.get("estimated_core_resident_atlas_bytes_for_all_selected", 0)),
			"effect": int(effect_technical_gate.get("estimated_core_resident_atlas_bytes_for_all_selected", 0)),
		},
		"active_runtime_residency": active_runtime_residency,
		"qa_staging": "Temporary in-memory actual starting five-player group (CHR001/002/003/004/005) plus BOSS001/ENM001. CHR008 is retained only in the immutable candidate inventory and is asserted absent from actor/effect/HUD-face runtime residency. No save, roster, reward, stage data, source asset, or quarantine record changed.",
		"signature_pack_ready": battle_view.signature_sprite_pack_ready,
		"signature_load_error": battle_view.sprite_library.signature_load_error,
		"effect_signature_pack_ready": battle_view.effect_signature_pack_ready,
		"effect_signature_load_error": battle_view.effect_signature_library.signature_load_error,
		"guardian_signature_size": guardian_signature_size,
		"roan_signature_size": roan_signature_size,
		"narin_signature_size": narin_signature_size,
		"eda_signature_size": eda_signature_size,
		"soren_signature_size": soren_signature_size,
		"boss_signature_size": boss_signature_size,
		"enm001_signature_size": rush_enemy_signature_size,
		"signature_resident_atlas_bytes": int(active_runtime_residency.get("actor_resident_atlas_bytes", 0)),
		"signature_core_resident_atlas_bytes": int(active_runtime_residency.get("actor_core_resident_atlas_bytes", 0)),
		"effect_signature_resident_atlas_bytes": int(active_runtime_residency.get("effect_resident_atlas_bytes", 0)),
		"effect_signature_core_resident_atlas_bytes": int(active_runtime_residency.get("effect_core_resident_atlas_bytes", 0)),
		"ultimate_page_checks": ultimate_page_checks.duplicate(true),
		"ui_orb_contract": {
			"control_count": shell.get("ultimate_buttons").size(),
			"full_tactical_gauge": battle_view.simulation.state.tactical_gauge,
			"ready_badges": _ready_badge_count(),
			"world_health_text_cards": shell.get("party_status_labels").size(),
			"face_crop_resident_bytes": int(active_runtime_residency.get("face_crop_resident_bytes", 0)),
			"face_crop_entity_ids": resident_face_ids,
			"chr008_face_crop_resident_bytes": int(face_bytes_by_entity.get("CHR008", 0)),
		},
		"captures": captures,
		"motion_contract": {
			"player_basic_windup_x": float(BattleView.combat_motion_snapshot("PLAYER", "basic_attack", .10, .75).get("offset", Vector2.ZERO).x),
			"player_basic_lunge_x": float(BattleView.combat_motion_snapshot("PLAYER", "basic_attack", .38, .75).get("offset", Vector2.ZERO).x),
			"enemy_hit_x": float(BattleView.combat_motion_snapshot("ENEMY", "hit", .38, .75).get("offset", Vector2.ZERO).x),
			"enemy_ultimate_lunge_x": float(BattleView.combat_motion_snapshot("ENEMY", "ultimate", .72, 1.24).get("offset", Vector2.ZERO).x)
		},
		"camera_motion_contract": {
			"per_ultimate": camera_motion_checks.duplicate(true),
			"clears_after_finish": camera_motion_cleanup,
			"camera_rule": "source-to-target bounded focus pan plus impact zoom/shake; all offsets reset on finish, skip, exit and re-entry"
		}
	}
	var report_file := FileAccess.open(output_dir.path_join("viewport_qa.json"), FileAccess.WRITE)
	if report_file == null:
		_finish(6, "SIGNATURE_QA_REPORT_OPEN_FAILED")
		return
	report_file.store_string(JSON.stringify(report, "  ") + "\n")
	report_file.close()
	print("BATTLE_SIGNATURE_VIEWPORT_QA %s" % JSON.stringify(report))
	await _finish(0, "")


func _await_battle_assets() -> bool:
	for _frame in range(600):
		await get_tree().process_frame
		battle_view = shell.get("battle_view") as BattleView
		if battle_view != null and battle_view.assets_ready:
			# AppShell deliberately holds a painted 100% loading layer for a short
			# real-time interval after the view says assets are ready.  Do not treat
			# the underlying canvas as visible until that owner layer is actually
			# disposed, otherwise early QA captures are not battle screenshots.
			if _battle_loading_layer_cleared():
				return true
			await get_tree().create_timer(.02, true, false, true).timeout
	return false


func _battle_loading_layer_cleared() -> bool:
	var layer = shell.get("transition_loading_layer")
	return layer == null or not is_instance_valid(layer)


func _stage_signature_party() -> bool:
	var simulation := battle_view.simulation
	if simulation == null:
		return false
	var staged_party: Array = []
	for slot in range(PLAYER_SIGNATURE_IDS.size()):
		var definition_id := PLAYER_SIGNATURE_IDS[slot]
		var definition := DataRegistry.character(definition_id)
		if definition.is_empty():
			return false
		staged_party.append(simulation._make_player(definition, slot))
	var rush_enemy := simulation._make_enemy("ENM001", 0)
	var boss := simulation._make_enemy("BOSS001", 0)
	simulation.state.wave = 3
	simulation.state.party = staged_party
	simulation.state.enemies = [rush_enemy, boss]
	battle_view._snapshot_display_units_from_simulation()
	for unit_value in simulation.state.party + simulation.state.enemies:
		var unit: Dictionary = unit_value
		battle_view.entry_tracks[str(unit.uid)] = 1.0
		battle_view.animation_tracks[str(unit.uid)] = {"name": "idle", "elapsed": 0.0}
	battle_view.queue_redraw()
	return true


func _guardian() -> Dictionary:
	return _player("CHR001")


func _player(definition_id: String) -> Dictionary:
	for unit_value in battle_view.simulation.state.party:
		var unit: Dictionary = unit_value
		if str(unit.get("def_id", "")) == definition_id:
			return unit
	return {}


func _boss() -> Dictionary:
	for unit_value in battle_view.simulation.state.enemies:
		var unit: Dictionary = unit_value
		if str(unit.get("def_id", "")) == "BOSS001":
			return unit
	return {}


func _rush_enemy() -> Dictionary:
	for unit_value in battle_view.simulation.state.enemies:
		var unit: Dictionary = unit_value
		if str(unit.get("def_id", "")) == "ENM001":
			return unit
	return {}


func _set_track(uid: String, animation_name: String, elapsed: float) -> void:
	battle_view.animation_tracks[uid] = {"name": animation_name, "elapsed": elapsed}
	battle_view.queue_redraw()


func _record_ultimate_page(entity_id: String) -> void:
	# Capture the residency evidence while the real ULTIMATE event owns the page.
	# The page is deliberately released at the next cinematic boundary, so looking
	# only at the final report snapshot would incorrectly make a successful
	# transient acquisition look absent.
	var actor_texture := battle_view.sprite_library.signature_texture_at(entity_id, "ultimate", .42)
	var effect_texture := battle_view.effect_signature_library.ultimate_texture_at(entity_id, .42)
	var actor_snapshot: Dictionary = battle_view.sprite_library.signature_residency_snapshot()
	var effect_snapshot: Dictionary = battle_view.effect_signature_library.signature_residency_snapshot()
	ultimate_page_checks[entity_id] = {
		"ready": actor_texture != null and effect_texture != null,
		"actor_texture_size": _texture_size(actor_texture),
		"effect_texture_size": _texture_size(effect_texture),
		"actor_transient_entity_id": str(actor_snapshot.get("transient_ultimate_entity_id", "")),
		"effect_transient_profile_id": str(effect_snapshot.get("transient_ultimate_profile_id", "")),
		"actor_resident_atlas_bytes": int(actor_snapshot.get("resident_atlas_bytes", 0)),
		"effect_resident_atlas_bytes": int(effect_snapshot.get("resident_atlas_bytes", 0)),
		"actor_budget_bytes": int(actor_snapshot.get("budget_bytes", 0)),
		"effect_budget_bytes": int(effect_snapshot.get("budget_bytes", 0)),
	}


func _capture_player_ultimate(capture_index: int, entity_id: String, caster: Dictionary, target: Dictionary, is_heal: bool) -> void:
	# Each player starts from a clean presentation boundary. This is the runtime
	# behavior after an ultimate completes, skips, exits, or is interrupted: the
	# previous caster's transient actor/effect pages must not stack with the next.
	battle_view._force_finish_active_presentation()
	_clear_capture_presentations()
	_start_player_ultimate(caster, target, is_heal)
	_record_ultimate_page(entity_id)
	var actor_label := entity_id.to_lower()
	var windup_timeline: Dictionary = battle_view.presentation_director.advance(.62)
	battle_view._handle_presentation_timeline(windup_timeline)
	_set_track(str(caster.uid), "ultimate", .62)
	_set_track(str(target.uid), "idle", .52)
	_record_camera_motion(entity_id, -1.0)
	_advance_vfx_for_capture(.12)
	await _capture("%02d_%s_ultimate_windup" % [capture_index, actor_label], "%s_ultimate_windup" % actor_label)
	var impact_timeline: Dictionary = battle_view.presentation_director.advance(.51)
	battle_view._handle_presentation_timeline(impact_timeline)
	_set_track(str(caster.uid), "ultimate", 1.14)
	_set_track(str(target.uid), "idle" if is_heal else "hit", .38)
	_stage_projectiles(.50)
	_advance_vfx_for_capture(.14)
	await _capture("%02d_%s_ultimate_projectile_travel" % [capture_index + 1, actor_label], "%s_ultimate_projectile_travel" % actor_label)
	_stage_projectiles(.70)
	# Capture the endpoint while the 224px burst and its crisp shock outline are
	# at the visible peak; the next caster begins only after this page is released.
	_advance_vfx_for_capture(.12)
	await _capture("%02d_%s_ultimate_impact" % [capture_index + 2, actor_label], "%s_ultimate_impact" % actor_label)


func _start_player_ultimate(caster: Dictionary, target: Dictionary, is_heal: bool) -> void:
	var simulation := battle_view.simulation
	# Existing SPAWN/WAVE records are not part of this isolated local shot.
	battle_view.consumed_events = simulation.event_log.size()
	battle_view.presentation_read_cursor = battle_view.consumed_events
	battle_view.presented_cursor = battle_view.consumed_events
	var tick := simulation.state.tick
	var skill_id := str(caster.get("ultimate_skill_id", ""))
	simulation.event_log.append(BattleEvent.make(tick, BattleEvent.ULTIMATE, str(caster.uid), str(target.uid), 0, {"skill_id": skill_id}))
	if is_heal:
		simulation.event_log.append(BattleEvent.make(tick, BattleEvent.HEAL, str(caster.uid), str(target.uid), 420, {"source": "ULTIMATE"}))
	else:
		simulation.event_log.append(BattleEvent.make(tick, BattleEvent.DAMAGE, str(caster.uid), str(target.uid), 420, {"source": "ULTIMATE", "hp_damage": 420, "shield_damage": 0, "crit": true}))
	battle_view._consume_events()


func _start_boss_ultimate(boss: Dictionary, target: Dictionary) -> void:
	var simulation := battle_view.simulation
	battle_view.consumed_events = simulation.event_log.size()
	battle_view.presentation_read_cursor = battle_view.consumed_events
	battle_view.presented_cursor = battle_view.consumed_events
	var tick := simulation.state.tick
	simulation.event_log.append(BattleEvent.make(tick, BattleEvent.ULTIMATE, str(boss.uid), str(target.uid), 0, {"skill_id": "BOSS001_ULTIMATE"}))
	simulation.event_log.append(BattleEvent.make(tick, BattleEvent.DAMAGE, str(boss.uid), str(target.uid), 420, {"source": "ULTIMATE", "hp_damage": 420, "shield_damage": 0, "crit": true}))
	battle_view._consume_events()


func _start_enm001_ultimate(rush_enemy: Dictionary, target: Dictionary) -> void:
	var simulation := battle_view.simulation
	battle_view.consumed_events = simulation.event_log.size()
	battle_view.presentation_read_cursor = battle_view.consumed_events
	battle_view.presented_cursor = battle_view.consumed_events
	var tick := simulation.state.tick
	simulation.event_log.append(BattleEvent.make(tick, BattleEvent.ULTIMATE, str(rush_enemy.uid), str(target.uid), 0, {"skill_id": "ENM001_ULTIMATE"}))
	simulation.event_log.append(BattleEvent.make(tick, BattleEvent.DAMAGE, str(rush_enemy.uid), str(target.uid), 420, {"source": "ULTIMATE", "hp_damage": 420, "shield_damage": 0, "crit": true}))
	battle_view._consume_events()


func _record_camera_motion(entity_id: String, expected_world_offset_sign: float) -> void:
	# This is sampled from the actual CanvasItem presentation timeline after the
	# genuine ULTIMATE cue, not from an isolated director unit test. A positive
	# source→target lane shifts the rendered world left (negative X) to center the
	# target; enemy lanes mirror it. The camera stays deliberately bounded so no
	# player/monster or world HP bar leaves the 390px safe frame.
	var offset := battle_view.presentation_director.battlefield_offset()
	var zoom := battle_view.presentation_director.battlefield_zoom()
	var cinematic: Dictionary = battle_view.presentation_director.cinematic_snapshot()
	var sign_passes := offset.x * expected_world_offset_sign > .50
	camera_motion_checks[entity_id] = {
		"world_offset_x": offset.x,
		"world_offset_y": offset.y,
		"zoom": zoom,
		"focus_strength": float(cinematic.get("combat_focus", 0.0)),
		"focus_direction": float(cinematic.get("combat_focus_direction", 0.0)),
		"expected_world_offset_sign": expected_world_offset_sign,
		"passes": sign_passes and zoom > 1.0 and absf(offset.x) <= 26.0
	}


func _stage_projectiles(age: float) -> void:
	for projectile_value in battle_view.projectiles:
		var projectile: Dictionary = projectile_value
		projectile["age"] = age
	battle_view.queue_redraw()


func _clear_capture_presentations() -> void:
	battle_view.projectiles.clear()
	battle_view.vfx_presentations.clear()
	battle_view.skill_callouts.clear()
	battle_view.floating_texts.clear()
	battle_view.queue_redraw()


func _ready_badge_count() -> int:
	var count := 0
	var buttons_value = shell.get("ultimate_buttons")
	if not buttons_value is Array:
		return count
	for button_value in buttons_value:
		var button := button_value as BattleUltimateOrb
		if button != null and button.is_ready:
			count += 1
	return count


func _advance_vfx_for_capture(delta: float) -> void:
	for presentation_value in battle_view.vfx_presentations:
		var presentation: Dictionary = presentation_value
		presentation["age"] = float(presentation.get("age", 0.0)) + delta
	for callout_value in battle_view.skill_callouts:
		var callout: Dictionary = callout_value
		callout["age"] = float(callout.get("age", 0.0)) + delta
	battle_view.queue_redraw()


func _capture(label: String, stage: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_tree().root.get_texture().get_image()
	if image == null or image.is_empty():
		_finish(7, "SIGNATURE_QA_EMPTY_CAPTURE:%s" % label)
		return
	var path := output_dir.path_join("%s.png" % label)
	if image.save_png(path) != OK:
		_finish(8, "SIGNATURE_QA_SAVE_FAILED:%s" % label)
		return
	captures.append({
		"stage": stage,
		"file": path.get_file(),
		"width": image.get_width(),
		"height": image.get_height(),
		"sha256": FileAccess.get_sha256(path)
	})


func _texture_size(texture: Texture2D) -> Array[int]:
	if texture == null:
		return []
	var size := texture.get_size()
	return [int(size.x), int(size.y)]


func _active_signature_units() -> Array[String]:
	var active: Array[String] = []
	if battle_view == null or battle_view.simulation == null:
		return active
	for unit_value in battle_view.simulation.state.party + battle_view.simulation.state.enemies:
		var unit: Dictionary = unit_value
		var definition_id := str(unit.get("def_id", ""))
		if definition_id in SIGNATURE_CANDIDATE_IDS and definition_id not in active:
			active.append(definition_id)
	return active


func _run_id() -> String:
	return "battle_signature_hd_%s_viewport_%s" % [BattleSpriteLibrary.SIGNATURE_REVISION, Time.get_datetime_string_from_system(true).replace(":", "-").replace(" ", "_")]


func _finish(exit_code: int, reason: String) -> void:
	if not reason.is_empty():
		push_error(reason)
	if shell != null and is_instance_valid(shell):
		shell.queue_free()
		shell = null
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)
