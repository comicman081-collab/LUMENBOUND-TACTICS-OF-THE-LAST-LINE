extends Node

const PHASE_AUDIO_ENABLED := true
const AUDIO_MANIFEST_PATH := "res://assets/audio/audio_manifest.json"
const SFX_POOL_SIZE := 8
const START_VERIFY_DELAY_SECONDS := 0.35
const BGM_WATCHDOG_INTERVAL_SECONDS := 1.0
const BGM_ATTEMPT_MIN_INTERVAL_MSEC := 500
const BGM_CIRCUIT_FAILURE_THRESHOLD := 4
const BGM_CIRCUIT_COOLDOWN_MSEC := 5000
# Desktop may bridge compact source excerpts with a second local player. Web
# uses the stream's native loop: swapping AudioStreamPlayers near the boundary
# can suspend WebAudio during a busy single-threaded map/battle frame.
const BGM_LOOP_CROSSFADE_SECONDS := 1.8
const BGM_CROSSFADE_SILENCE_DB := -80.0

var music_player: AudioStreamPlayer
var music_crossfade_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var voice_player: AudioStreamPlayer
var manifest: Dictionary = {}
var entries_by_id: Dictionary = {}
var entries_by_event: Dictionary = {}
var card_start_profiles: Dictionary = {}
var current_bgm_id := ""
var requested_bgm_id := ""
# Browsers reject WebAudio that starts during boot.  Title/home code may still
# request BGM at boot, but it is held until an actual button/touch gesture
# reaches unlock_from_user_gesture(). Desktop starts unlocked as before.
var browser_audio_unlocked := not OS.has_feature("web")
var sfx_cursor := 0
var last_event_at: Dictionary = {}
var last_card_start_at: Dictionary = {}
var sfx_asset_by_player: Dictionary = {}
# playback_counts is retained as the verified-start compatibility field. An
# attempted play() call is not evidence that the browser audio backend started.
var playback_counts: Dictionary = {}
var playback_attempt_counts: Dictionary = {}
var playback_failed_counts: Dictionary = {}
var last_playback_id := ""
var last_attempted_playback_id := ""
var last_failed_playback_id := ""
var start_sequence := 0
var start_token_by_player: Dictionary = {}
var bgm_watchdog_left := BGM_WATCHDOG_INTERVAL_SECONDS
var last_bgm_attempt_msec := -1000000
var last_bgm_attempt_by_asset: Dictionary = {}
var bgm_suppressed_attempt_counts: Dictionary = {}
var bgm_consecutive_failures_by_asset: Dictionary = {}
var bgm_circuit_open_until_by_asset: Dictionary = {}
var bgm_recovery_pending := false
var bgm_recovery_counts: Dictionary = {}
var bgm_crossfade_active := false
var bgm_crossfade_asset_id := ""
var music_target_volume_db := 0.0

func _ready() -> void:
	_load_manifest()
	_ensure_players()

func _ensure_players() -> void:
	if not _interactive_display():
		return
	if music_player != null:
		return
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_crossfade_player = AudioStreamPlayer.new()
	music_crossfade_player.name = "MusicCrossfadePlayer"
	voice_player = AudioStreamPlayer.new()
	voice_player.name = "VoicePlayer"
	# Godot's Web audio driver does not provide the sample-playback backend.
	# Force authored local WAV/MP3 streams through the streaming path so a
	# trusted browser gesture yields actual playback instead of driver warnings.
	music_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	music_crossfade_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	voice_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(music_player)
	add_child(music_crossfade_player)
	add_child(voice_player)
	music_player.finished.connect(_on_music_finished)
	music_crossfade_player.finished.connect(_on_music_finished)
	for index in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer%02d" % index
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(player)
		sfx_players.append(player)

func _exit_tree() -> void:
	# Explicitly release browser/desktop playback resources so headless QA and
	# scene reloads do not report leaked AudioStreamPlayback objects.
	if music_player != null:
		music_player.stop()
		music_player.stream = null
	if music_crossfade_player != null:
		music_crossfade_player.stop()
		music_crossfade_player.stream = null
	for player in sfx_players:
		player.stop()
		player.stream = null
	if voice_player != null:
		voice_player.stop()
		voice_player.stream = null

func _process(delta: float) -> void:
	_update_bgm_loop_crossfade()
	# Web builds have historically failed to repeat otherwise valid looping
	# streams. Recover only the requested BGM, with a bounded cadence, and never
	# use this presentation watchdog to alter simulation state.
	bgm_watchdog_left -= delta
	if bgm_watchdog_left > 0.0:
		return
	bgm_watchdog_left = BGM_WATCHDOG_INTERVAL_SECONDS
	if not _can_play_now() or requested_bgm_id.is_empty() or music_player == null:
		return
	if _music_has_active_playback():
		return
	if not _bgm_attempt_is_eligible(requested_bgm_id, Time.get_ticks_msec()):
		return
	_queue_bgm_recovery("watchdog")

func _audio_enabled() -> bool:
	# Headless QA validates manifests and hooks without creating a playback
	# device; browser and interactive desktop builds keep the real audio path.
	return _interactive_display() and bool(SettingsService.values.get("audio_enabled", false))

func _interactive_display() -> bool:
	# Godot's Web display backend has reported both "web" and a transient
	# fallback name during first-frame initialization on different browsers.
	# Web is always an interactive target here, so do not let that transient
	# name suppress the local audio players before the first trusted tap.
	if OS.has_feature("web"):
		return PHASE_AUDIO_ENABLED
	var display_name := DisplayServer.get_name().to_lower()
	return PHASE_AUDIO_ENABLED and display_name not in ["headless", "dummy", "null"]

func _can_play_now() -> bool:
	return _audio_enabled() and browser_audio_unlocked

func unlock_from_user_gesture() -> void:
	# Call this only from a real Control/input callback.  It is deliberately
	# idempotent so a tap on any screen safely activates deferred title BGM.
	browser_audio_unlocked = true
	_ensure_players()
	if _audio_enabled() and not requested_bgm_id.is_empty():
		_start_bgm(requested_bgm_id)

func set_enabled(enabled: bool) -> void:
	SettingsService.values.audio_enabled = enabled
	_ensure_players()
	if not enabled:
		if music_player != null:
			_invalidate_start_verification(music_player)
			music_player.stop()
		if music_crossfade_player != null:
			_invalidate_start_verification(music_crossfade_player)
			music_crossfade_player.stop()
		bgm_crossfade_active = false
		current_bgm_id = ""
		return
	if browser_audio_unlocked and not requested_bgm_id.is_empty():
		_start_bgm(requested_bgm_id)

func _load_manifest() -> void:
	manifest = {}
	entries_by_id.clear()
	entries_by_event.clear()
	card_start_profiles.clear()
	var file := FileAccess.open(AUDIO_MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_warning("Local audio manifest missing; audio hooks remain safe no-ops (R7 local pack)")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("Local audio manifest could not be parsed")
		return
	manifest = parsed
	for entry_value in manifest.get("entries", []):
		if not entry_value is Dictionary: continue
		var entry: Dictionary = entry_value
		var asset_id := str(entry.get("asset_id", ""))
		if asset_id == "": continue
		entries_by_id[asset_id] = entry
		var event_id := str(entry.get("event", ""))
		if event_id != "":
			if not entries_by_event.has(event_id): entries_by_event[event_id] = []
			entries_by_event[event_id].append(asset_id)
	var raw_card_profiles = manifest.get("card_start_profiles", {})
	if raw_card_profiles is Dictionary:
		for card_id_value in raw_card_profiles:
			var card_id := str(card_id_value).strip_edges()
			var raw_asset_ids = raw_card_profiles[card_id_value]
			if card_id.is_empty() or not raw_asset_ids is Array:
				continue
			var asset_ids: Array = []
			for asset_id_value in raw_asset_ids:
				var asset_id := str(asset_id_value).strip_edges()
				if not asset_id.is_empty():
					asset_ids.append(asset_id)
			if not asset_ids.is_empty():
				card_start_profiles[card_id] = asset_ids

func _entry_path(asset_id: String) -> String:
	if not entries_by_id.has(asset_id): return ""
	return str(entries_by_id[asset_id].get("runtime_path", ""))

func _stream_for(asset_id: String) -> AudioStream:
	var path := _entry_path(asset_id)
	if path == "" or not ResourceLoader.exists(path): return null
	var resource = load(path)
	return resource if resource is AudioStream else null

func _configure_music_loop(resource: AudioStream, enabled: bool) -> void:
	if not enabled:
		return
	if resource is AudioStreamWAV:
		# AudioStreamWAV defaults loop_end to zero. Enabling LOOP_FORWARD without
		# an explicit positive endpoint can finish/re-enter immediately on Web,
		# causing a finished-signal recovery storm instead of audible playback.
		var wav := resource as AudioStreamWAV
		var frame_count := maxi(1, roundi(wav.get_length() * float(wav.mix_rate)))
		wav.loop_begin = 0
		wav.loop_end = frame_count
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif resource is AudioStreamMP3:
		resource.loop = true
	elif resource is AudioStreamOggVorbis:
		resource.loop = true

func _prepare_music_crossfade(resource: AudioStream) -> void:
	# Native stream loops restart at the exact source boundary before we can
	# bridge them. Disable the native loop for BGM only; _process schedules the
	# next local instance slightly before this one finishes.
	if resource is AudioStreamWAV:
		(resource as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif resource is AudioStreamMP3:
		resource.loop = false
	elif resource is AudioStreamOggVorbis:
		resource.loop = false

func _apply_mix() -> void:
	var master := clampf(float(SettingsService.values.get("master_volume", 0.8)), 0.0, 1.0)
	var bgm := clampf(float(SettingsService.values.get("bgm_volume", 0.7)), 0.0, 1.0)
	var sfx := clampf(float(SettingsService.values.get("sfx_volume", 0.8)), 0.0, 1.0)
	if music_player != null:
		music_target_volume_db = linear_to_db(maxf(0.001, master * bgm))
		if not bgm_crossfade_active:
			music_player.volume_db = music_target_volume_db
		if music_crossfade_player != null and not bgm_crossfade_active:
			music_crossfade_player.volume_db = BGM_CROSSFADE_SILENCE_DB
	if voice_player != null:
		voice_player.volume_db = linear_to_db(maxf(0.001, master * sfx))
	for player in sfx_players:
		var active_asset_id := str(sfx_asset_by_player.get(player.get_instance_id(), ""))
		var active_entry: Dictionary = entries_by_id.get(active_asset_id, {})
		player.volume_db = linear_to_db(maxf(0.001, master * sfx)) + float(active_entry.get("gain_db", 0.0))

func _increment_counter(counter: Dictionary, asset_id: String) -> void:
	counter[asset_id] = int(counter.get(asset_id, 0)) + 1

func _bgm_attempt_is_eligible(asset_id: String, now_msec: int) -> bool:
	if asset_id.is_empty():
		return false
	var circuit_open_until := int(bgm_circuit_open_until_by_asset.get(asset_id, 0))
	if circuit_open_until > now_msec:
		return false
	var last_attempt := int(last_bgm_attempt_by_asset.get(asset_id, -1000000))
	return now_msec - last_attempt >= BGM_ATTEMPT_MIN_INTERVAL_MSEC

func _reserve_bgm_attempt(asset_id: String, now_msec := -1) -> bool:
	# This is the single gate for every BGM start path: direct requests, browser
	# unlock, finished recovery, verification recovery and watchdog recovery.
	# It guarantees that no signal storm can issue more than one play attempt for
	# the same asset within 500 ms.
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	var circuit_open_until := int(bgm_circuit_open_until_by_asset.get(asset_id, 0))
	if circuit_open_until > 0 and now >= circuit_open_until:
		bgm_circuit_open_until_by_asset.erase(asset_id)
		bgm_consecutive_failures_by_asset.erase(asset_id)
	if not _bgm_attempt_is_eligible(asset_id, now):
		_increment_counter(bgm_suppressed_attempt_counts, asset_id)
		return false
	last_bgm_attempt_by_asset[asset_id] = now
	last_bgm_attempt_msec = now
	return true

func _note_bgm_failure(asset_id: String, now_msec := -1) -> void:
	var failures := int(bgm_consecutive_failures_by_asset.get(asset_id, 0)) + 1
	bgm_consecutive_failures_by_asset[asset_id] = failures
	if failures >= BGM_CIRCUIT_FAILURE_THRESHOLD:
		var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
		bgm_circuit_open_until_by_asset[asset_id] = now + BGM_CIRCUIT_COOLDOWN_MSEC

func _note_bgm_success(asset_id: String) -> void:
	bgm_consecutive_failures_by_asset.erase(asset_id)
	bgm_circuit_open_until_by_asset.erase(asset_id)

func _record_attempt(player: AudioStreamPlayer, asset_id: String, resource: AudioStream, kind: String) -> void:
	start_sequence += 1
	start_token_by_player[player.get_instance_id()] = start_sequence
	last_attempted_playback_id = asset_id
	_increment_counter(playback_attempt_counts, asset_id)
	_verify_start_after_delay(player, asset_id, resource, kind, start_sequence)

func _invalidate_start_verification(player: AudioStreamPlayer) -> void:
	if player != null:
		start_token_by_player.erase(player.get_instance_id())

func _verify_start_after_delay(player: AudioStreamPlayer, asset_id: String, resource: AudioStream, kind: String, token: int) -> void:
	await get_tree().create_timer(START_VERIFY_DELAY_SECONDS, true).timeout
	if not is_instance_valid(player):
		return
	if int(start_token_by_player.get(player.get_instance_id(), -1)) != token:
		return
	start_token_by_player.erase(player.get_instance_id())
	var stream_matches := player.stream == resource
	if stream_matches and _player_has_active_playback(player):
		last_playback_id = asset_id
		_increment_counter(playback_counts, asset_id)
		if kind == "BGM":
			_note_bgm_success(asset_id)
		return
	last_failed_playback_id = asset_id
	_increment_counter(playback_failed_counts, asset_id)
	if kind == "BGM" and requested_bgm_id == asset_id:
		_note_bgm_failure(asset_id)
		_queue_bgm_recovery("verification")

func _player_has_active_playback(player: AudioStreamPlayer) -> bool:
	return player != null and (player.playing or player.has_stream_playback())

func _music_has_active_playback() -> bool:
	# Both players are intentional during a loop bridge. Treat either as active
	# so the recovery watchdog never restarts a valid BGM mid-crossfade.
	return _player_has_active_playback(music_player) or (bgm_crossfade_active and _player_has_active_playback(music_crossfade_player))

func _update_bgm_loop_crossfade() -> void:
	# Browser audio remains on one native-looped stream for the entire scene.
	# This prevents the repeated stop/start/crossfade recovery that presented as
	# music cutting out together with map and battle frame stalls.
	if OS.has_feature("web"):
		return
	if bgm_crossfade_active or not _can_play_now() or music_player == null or music_crossfade_player == null:
		return
	if not _player_has_active_playback(music_player) or current_bgm_id.is_empty():
		return
	var entry: Dictionary = entries_by_id.get(current_bgm_id, {})
	if not bool(entry.get("loop", false)):
		return
	var stream := music_player.stream
	if stream == null:
		return
	var length := stream.get_length()
	if length <= BGM_LOOP_CROSSFADE_SECONDS + 0.05:
		return
	if music_player.get_playback_position() < length - BGM_LOOP_CROSSFADE_SECONDS:
		return
	_begin_bgm_loop_crossfade(current_bgm_id, stream)

func _begin_bgm_loop_crossfade(asset_id: String, stream: AudioStream) -> void:
	if music_crossfade_player == null or stream == null:
		return
	bgm_crossfade_active = true
	bgm_crossfade_asset_id = asset_id
	music_crossfade_player.stop()
	music_crossfade_player.stream = stream
	music_crossfade_player.volume_db = BGM_CROSSFADE_SILENCE_DB
	music_crossfade_player.play()
	var outgoing := music_player
	var incoming := music_crossfade_player
	var bridge := create_tween()
	bridge.set_parallel(true)
	bridge.tween_property(outgoing, "volume_db", BGM_CROSSFADE_SILENCE_DB, BGM_LOOP_CROSSFADE_SECONDS)
	bridge.tween_property(incoming, "volume_db", music_target_volume_db, BGM_LOOP_CROSSFADE_SECONDS)
	bridge.chain().tween_callback(_complete_bgm_loop_crossfade.bind(outgoing, incoming, asset_id))

func _complete_bgm_loop_crossfade(outgoing: AudioStreamPlayer, incoming: AudioStreamPlayer, asset_id: String) -> void:
	# A scene/BGM change can invalidate a queued tween. Only the current bridge
	# may swap the active player.
	if not bgm_crossfade_active or asset_id != current_bgm_id or incoming != music_crossfade_player:
		return
	outgoing.stop()
	outgoing.volume_db = BGM_CROSSFADE_SILENCE_DB
	music_player = incoming
	music_crossfade_player = outgoing
	music_player.volume_db = music_target_volume_db
	bgm_crossfade_active = false
	bgm_crossfade_asset_id = ""

func _on_music_finished() -> void:
	# The outgoing stream ends at the same boundary as the incoming player takes
	# over. It is not a failed playback and must not enqueue a duplicate start.
	if bgm_crossfade_active:
		return
	if _can_play_now() and not requested_bgm_id.is_empty():
		_queue_bgm_recovery("finished")

func _queue_bgm_recovery(reason: String) -> void:
	if bgm_recovery_pending:
		return
	# Reject finished-signal floods before they enqueue deferred work. The hard
	# reservation in _start_bgm remains the authoritative second line of defense.
	if requested_bgm_id.is_empty() or not _bgm_attempt_is_eligible(requested_bgm_id, Time.get_ticks_msec()):
		return
	bgm_recovery_pending = true
	call_deferred("_recover_requested_bgm", reason)

func _recover_requested_bgm(reason: String) -> void:
	bgm_recovery_pending = false
	if not _can_play_now() or requested_bgm_id.is_empty() or music_player == null:
		return
	if _music_has_active_playback():
		return
	if _start_bgm(requested_bgm_id):
		_increment_counter(bgm_recovery_counts, reason)

func _play_sfx_asset(asset_id: String) -> void:
	if sfx_players.is_empty(): return
	var resource: AudioStream = _stream_for(asset_id)
	if resource == null:
		last_failed_playback_id = asset_id
		_increment_counter(playback_failed_counts, asset_id)
		return
	var player := sfx_players[sfx_cursor % sfx_players.size()]
	sfx_cursor = (sfx_cursor + 1) % sfx_players.size()
	var entry: Dictionary = entries_by_id.get(asset_id, {})
	sfx_asset_by_player[player.get_instance_id()] = asset_id
	_apply_mix()
	player.pitch_scale = clampf(float(entry.get("pitch_scale", 1.0)), 0.01, 4.0)
	player.stream = resource
	player.play()
	_record_attempt(player, asset_id, resource, "SFX")

func _event_asset(event_id: String) -> String:
	var choices: Array = entries_by_event.get(event_id, [])
	if choices.is_empty(): return ""
	# Stable round-robin keeps repeated auto attacks varied without consulting
	# wall-clock randomness or affecting BattleSimulation determinism.
	var index := int(last_event_at.get("__cursor_%s" % event_id, 0))
	last_event_at["__cursor_%s" % event_id] = (index + 1) % choices.size()
	return str(choices[index])

func play_event(event_id: String, minimum_interval := 0.04) -> void:
	if not _can_play_now(): return
	var now := Time.get_ticks_msec() / 1000.0
	var last := float(last_event_at.get(event_id, -1000.0))
	if now - last < minimum_interval: return
	last_event_at[event_id] = now
	var asset_id := _event_asset(event_id)
	if asset_id != "": _play_sfx_asset(asset_id)

func resolve_card_start_profile(profiles: Dictionary, card_id: String, fallback_event: String) -> Dictionary:
	# Pure resolution helper: tests can validate card selection and fallback
	# without creating an audio device or advancing wall-clock time.
	var raw_asset_ids = profiles.get(card_id, [])
	var asset_ids: Array = []
	if raw_asset_ids is Array:
		for asset_id_value in raw_asset_ids:
			var asset_id := str(asset_id_value).strip_edges()
			if not asset_id.is_empty():
				asset_ids.append(asset_id)
	return {
		"asset_ids": asset_ids,
		"fallback_event": fallback_event if asset_ids.is_empty() else "",
	}

func card_start_cooldown_ready(history: Dictionary, card_id: String, now_seconds: float, minimum_interval: float) -> bool:
	# Keep the decision deterministic and separately testable. Different cards
	# do not suppress each other even when they share the same fallback event.
	var last := float(history.get(card_id, -1000.0))
	return now_seconds - last >= maxf(0.0, minimum_interval)

func play_card_start(card_id: String, fallback_event: String, minimum_interval := 0.04) -> void:
	if not _can_play_now():
		return
	var normalized_card_id := card_id.strip_edges()
	if normalized_card_id.is_empty():
		play_event(fallback_event, minimum_interval)
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not card_start_cooldown_ready(last_card_start_at, normalized_card_id, now, minimum_interval):
		return
	last_card_start_at[normalized_card_id] = now
	var plan := resolve_card_start_profile(card_start_profiles, normalized_card_id, fallback_event)
	var asset_ids: Array = plan.get("asset_ids", [])
	if asset_ids.is_empty():
		play_event(str(plan.get("fallback_event", fallback_event)), minimum_interval)
		return
	# A card profile is a deterministic stack of authored layers, not a random
	# choice. Each layer keeps its own manifest gain and pitch settings.
	for asset_id_value in asset_ids:
		_play_sfx_asset(str(asset_id_value))

func play_bgm(asset_id: String) -> void:
	requested_bgm_id = asset_id
	if not _can_play_now(): return
	_start_bgm(asset_id)

func _start_bgm(asset_id: String) -> bool:
	if music_player == null: return false
	if current_bgm_id == asset_id and _music_has_active_playback(): return false
	if not _reserve_bgm_attempt(asset_id): return false
	var resource: AudioStream = _stream_for(asset_id)
	if resource == null:
		last_failed_playback_id = asset_id
		_increment_counter(playback_failed_counts, asset_id)
		_note_bgm_failure(asset_id)
		return false
	_apply_mix()
	var entry: Dictionary = entries_by_id.get(asset_id, {})
	_configure_music_loop(resource, bool(entry.get("loop", false)))
	if not OS.has_feature("web"):
		_prepare_music_crossfade(resource)
	bgm_crossfade_active = false
	bgm_crossfade_asset_id = ""
	if music_crossfade_player != null:
		_invalidate_start_verification(music_crossfade_player)
		music_crossfade_player.stop()
		music_crossfade_player.stream = null
	_invalidate_start_verification(music_player)
	music_player.stop()
	music_player.stream = resource
	music_player.volume_db = music_target_volume_db
	music_player.play()
	current_bgm_id = asset_id
	_record_attempt(music_player, asset_id, resource, "BGM")
	return true

func stop_bgm() -> void:
	if music_player != null:
		_invalidate_start_verification(music_player)
		music_player.stop()
	if music_crossfade_player != null:
		_invalidate_start_verification(music_crossfade_player)
		music_crossfade_player.stop()
		music_crossfade_player.stream = null
	bgm_crossfade_active = false
	bgm_crossfade_asset_id = ""
	current_bgm_id = ""
	requested_bgm_id = ""

func play_sfx(asset_id: String) -> void:
	if not _can_play_now(): return
	if entries_by_event.has(asset_id):
		play_event(asset_id)
	else:
		_play_sfx_asset(asset_id)

func play_voice(asset_or_path: String) -> void:
	if not _can_play_now() or voice_player == null: return
	var path := AssetRegistry.resolve(asset_or_path)
	if asset_or_path.begins_with("res://") or asset_or_path.begins_with("user://"): path = asset_or_path
	if path != "" and ResourceLoader.exists(path):
		var resource = load(path)
		if resource is AudioStream:
			_apply_mix()
			voice_player.stream = resource
			voice_player.play()
			_record_attempt(voice_player, asset_or_path, resource, "VOICE")

func voice_is_playing() -> bool:
	return _can_play_now() and voice_player != null and voice_player.playing

func runtime_status() -> Dictionary:
	var active_sfx_players := 0
	for player in sfx_players:
		if _player_has_active_playback(player):
			active_sfx_players += 1
	var music_active := _music_has_active_playback()
	var music_loop_mode := -1
	var music_loop_begin := -1
	var music_loop_end := -1
	if music_player != null and music_player.stream is AudioStreamWAV:
		var wav := music_player.stream as AudioStreamWAV
		music_loop_mode = int(wav.loop_mode)
		music_loop_begin = int(wav.loop_begin)
		music_loop_end = int(wav.loop_end)
	return {
		"audio_enabled": _audio_enabled(),
		"web_unlocked": browser_audio_unlocked,
		"players_created": music_player != null and music_crossfade_player != null and voice_player != null and sfx_players.size() == SFX_POOL_SIZE,
		"requested_bgm": requested_bgm_id,
		"current_bgm": current_bgm_id,
		"music_playing": music_player != null and music_player.playing,
		"music_has_stream_playback": music_player != null and music_player.has_stream_playback(),
		"music_active": music_active,
		"music_playback_position": music_player.get_playback_position() if music_active else 0.0,
		"music_stream_type": music_player.stream.get_class() if music_player != null and music_player.stream != null else "",
		"music_stream_length": music_player.stream.get_length() if music_player != null and music_player.stream != null else 0.0,
		"music_loop_mode": music_loop_mode,
		"music_loop_begin": music_loop_begin,
		"music_loop_end": music_loop_end,
		"music_crossfade_enabled": BGM_LOOP_CROSSFADE_SECONDS > 0.0 and not OS.has_feature("web"),
		"music_crossfade_active": bgm_crossfade_active,
		"music_crossfade_seconds": BGM_LOOP_CROSSFADE_SECONDS,
		"music_crossfade_asset": bgm_crossfade_asset_id,
		"active_sfx_players": active_sfx_players,
		"last_attempted_playback": last_attempted_playback_id,
		"last_playback": last_playback_id,
		"last_failed_playback": last_failed_playback_id,
		"playback_attempt_counts": playback_attempt_counts.duplicate(true),
		"playback_verified_counts": playback_counts.duplicate(true),
		"playback_failed_counts": playback_failed_counts.duplicate(true),
		"bgm_recovery_counts": bgm_recovery_counts.duplicate(true),
		"bgm_suppressed_attempt_counts": bgm_suppressed_attempt_counts.duplicate(true),
		"bgm_consecutive_failures": bgm_consecutive_failures_by_asset.duplicate(true),
		"bgm_circuit_open_until_msec": bgm_circuit_open_until_by_asset.duplicate(true),
		"bgm_attempt_min_interval_msec": BGM_ATTEMPT_MIN_INTERVAL_MSEC,
		# Compatibility key: now intentionally means verified starts, not calls.
		"playback_counts": playback_counts.duplicate(true),
	}
