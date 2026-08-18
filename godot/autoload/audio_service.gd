extends Node

const PHASE_AUDIO_ENABLED := true
const AUDIO_MANIFEST_PATH := "res://assets/audio/audio_manifest.json"
const SFX_POOL_SIZE := 8

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var voice_player: AudioStreamPlayer
var manifest: Dictionary = {}
var entries_by_id: Dictionary = {}
var entries_by_event: Dictionary = {}
var current_bgm_id := ""
var sfx_cursor := 0
var last_event_at: Dictionary = {}

func _ready() -> void:
	_load_manifest()
	if not _audio_enabled():
		return
	music_player = AudioStreamPlayer.new()
	voice_player = AudioStreamPlayer.new()
	add_child(music_player)
	add_child(voice_player)
	for index in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer%02d" % index
		add_child(player)
		sfx_players.append(player)

func _exit_tree() -> void:
	# Explicitly release browser/desktop playback resources so headless QA and
	# scene reloads do not report leaked AudioStreamPlayback objects.
	if music_player != null:
		music_player.stop()
		music_player.stream = null
	for player in sfx_players:
		player.stop()
		player.stream = null
	if voice_player != null:
		voice_player.stop()
		voice_player.stream = null

func _audio_enabled() -> bool:
	# Headless QA validates manifests and hooks without creating a playback
	# device; browser and interactive desktop builds keep the real audio path.
	var display_name := DisplayServer.get_name().to_lower()
	return PHASE_AUDIO_ENABLED and display_name not in ["headless", "dummy", "null"] and bool(SettingsService.values.get("audio_enabled", false))

func _load_manifest() -> void:
	manifest = {}
	entries_by_id.clear()
	entries_by_event.clear()
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

func _entry_path(asset_id: String) -> String:
	if not entries_by_id.has(asset_id): return ""
	return str(entries_by_id[asset_id].get("runtime_path", ""))

func _stream_for(asset_id: String):
	var path := _entry_path(asset_id)
	if path == "" or not ResourceLoader.exists(path): return null
	var resource = load(path)
	return resource if resource is AudioStream else null

func _configure_music_loop(resource) -> void:
	if resource is AudioStreamWAV:
		resource.loop_mode = AudioStreamWAV.LOOP_FORWARD

func _play_sfx_asset(asset_id: String) -> void:
	if sfx_players.is_empty(): return
	var resource = _stream_for(asset_id)
	if resource == null: return
	var player := sfx_players[sfx_cursor % sfx_players.size()]
	sfx_cursor = (sfx_cursor + 1) % sfx_players.size()
	player.stream = resource
	player.play()

func _event_asset(event_id: String) -> String:
	var choices: Array = entries_by_event.get(event_id, [])
	if choices.is_empty(): return ""
	# Stable round-robin keeps repeated auto attacks varied without consulting
	# wall-clock randomness or affecting BattleSimulation determinism.
	var index := int(last_event_at.get("__cursor_%s" % event_id, 0))
	last_event_at["__cursor_%s" % event_id] = (index + 1) % choices.size()
	return str(choices[index])

func play_event(event_id: String, minimum_interval := 0.04) -> void:
	if not _audio_enabled(): return
	var now := Time.get_ticks_msec() / 1000.0
	var last := float(last_event_at.get(event_id, -1000.0))
	if now - last < minimum_interval: return
	last_event_at[event_id] = now
	var asset_id := _event_asset(event_id)
	if asset_id != "": _play_sfx_asset(asset_id)

func play_bgm(asset_id: String) -> void:
	if not _audio_enabled(): return
	if music_player == null: return
	if current_bgm_id == asset_id and music_player.playing: return
	var resource = _stream_for(asset_id)
	if resource == null: return
	_configure_music_loop(resource)
	music_player.stream = resource
	music_player.play()
	current_bgm_id = asset_id

func stop_bgm() -> void:
	if music_player != null:
		music_player.stop()
	current_bgm_id = ""

func play_sfx(asset_id: String) -> void:
	if not _audio_enabled(): return
	if entries_by_event.has(asset_id):
		play_event(asset_id)
	else:
		_play_sfx_asset(asset_id)

func play_voice(asset_or_path: String) -> void:
	if not _audio_enabled(): return
	var path := AssetRegistry.resolve(asset_or_path)
	if asset_or_path.begins_with("res://") or asset_or_path.begins_with("user://"): path = asset_or_path
	if path != "" and ResourceLoader.exists(path):
		var resource = load(path)
		if resource is AudioStream:
			voice_player.stream = resource
			voice_player.play()

func voice_is_playing() -> bool:
	return _audio_enabled() and voice_player != null and voice_player.playing
