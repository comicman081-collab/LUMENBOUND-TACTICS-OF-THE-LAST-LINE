extends Node

const PHASE_AUDIO_ENABLED := false

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer

func _ready() -> void:
	# R7 Web is a visual-only phase.  Do not instantiate Web audio players when
	# audio is disabled: Godot otherwise initializes browser worklets even though
	# every playback hook is a no-op.
	if not _audio_enabled():
		return
	music_player = AudioStreamPlayer.new()
	sfx_player = AudioStreamPlayer.new()
	voice_player = AudioStreamPlayer.new()
	add_child(music_player)
	add_child(sfx_player)
	add_child(voice_player)

func _audio_enabled() -> bool:
	return PHASE_AUDIO_ENABLED and bool(SettingsService.values.get("audio_enabled", false))

func play_bgm(asset_id: String) -> void:
	if not _audio_enabled(): return
	var path := AssetRegistry.resolve(asset_id)
	if path != "" and ResourceLoader.exists(path):
		var resource = load(path)
		if resource is AudioStream:
			music_player.stream = resource
			music_player.play()

func stop_bgm() -> void:
	if music_player != null: music_player.stop()

func play_sfx(asset_id: String) -> void:
	if not _audio_enabled(): return
	var path := AssetRegistry.resolve(asset_id)
	if path != "" and ResourceLoader.exists(path):
		var resource = load(path)
		if resource is AudioStream:
			sfx_player.stream = resource
			sfx_player.play()

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
