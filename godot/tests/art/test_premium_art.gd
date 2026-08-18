extends SceneTree

var total := 0
var passed := 0
var failed := 0

const PACKS := {
	"CHR001": "res://assets/art/sd/CHR001",
	"CHR008": "res://assets/art/sd/CHR008",
	"ENM001": "res://assets/art/enemies/ENM001",
	"ENM007": "res://assets/art/enemies/ENM007",
	"BOSS001": "res://assets/art/bosses/BOSS001",
}
const STATE_COUNTS := {"idle": 8, "move": 12, "basic_attack": 8, "normal_skill": 12, "ultimate": 18, "hit": 4, "down": 8, "victory": 10}

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	total += 1
	if condition:
		passed += 1
		print("PASS | ", label)
	else:
		failed += 1
		printerr("FAIL | ", label)

func read_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	return JSON.parse_string(file.get_as_text())

func run() -> void:
	var all_packs_valid := true
	var all_frames_present := true
	var all_frames_512 := true
	var no_fallback := true
	for entity_id in PACKS:
		var root: String = PACKS[entity_id]
		var manifest = read_json(root + "/animation_manifest.json")
		if not manifest is Dictionary:
			all_packs_valid = false
			continue
		all_packs_valid = all_packs_valid and str(manifest.get("character_id", "")) == entity_id
		no_fallback = no_fallback and root.begins_with("res://assets/art/")
		for state in STATE_COUNTS:
			var definition: Dictionary = manifest.get("animations", {}).get(state, {})
			var paths: Array = definition.get("frame_paths", [])
			all_frames_present = all_frames_present and paths.size() == int(STATE_COUNTS[state])
			for relative_path in paths:
				var path := root + "/" + str(relative_path)
				all_frames_present = all_frames_present and ResourceLoader.exists(path)
				var texture = load(path)
				all_frames_512 = all_frames_512 and texture is Texture2D and texture.get_size() == Vector2(512, 512)
	check(all_packs_valid, "five premium pilot manifests parse with immutable entity IDs")
	check(no_fallback, "five premium pilot IDs use no generated_import fallback")
	check(all_frames_present, "five premium pilot packs expose exact 80-frame state contract")
	check(all_frames_512, "all 400 premium pilot SD frames import at 512x512")

	var vfx_valid := true
	for character_id in ["chr001", "chr008"]:
		for kind in ["basic", "normal", "ultimate"]:
			var folder := "vfx_%s_%s" % [character_id, kind]
			for frame in range(12):
				var path := "res://assets/art/vfx/%s/%s_%02d.png" % [folder, folder, frame]
				vfx_valid = vfx_valid and ResourceLoader.exists(path)
	check(vfx_valid, "six character-specific VFX packs expose all 72 frames")

	check(ResourceLoader.exists("res://assets/art/backgrounds/BG_STORY_RELAY/bg_story_relay_1920x1080.png"), "premium story background imports")
	check(ResourceLoader.exists("res://assets/art/backgrounds/BG_BATTLE_GLASS_RAIL/bg_battle_glass_rail_1920x1080.png"), "premium battle background imports")
	check(ResourceLoader.exists("res://assets/art/backgrounds/BG_BOSS_SIGNAL_CATHEDRAL/bg_boss_signal_cathedral_1920x1080.png"), "premium boss background imports")
	check(ResourceLoader.exists("res://assets/art/cg/CG_CH01_PILOT_TEAMWORK/cg_ch01_pilot_teamwork_1920x1080.png"), "premium event CG imports")
	check(ResourceLoader.exists("res://assets/art/characters/CHR001/fullbody_2048x3072.png") and ResourceLoader.exists("res://assets/art/characters/CHR008/fullbody_2048x3072.png"), "two master character illustrations import")
	check(ResourceLoader.exists("res://assets/art/characters/CHR001/expressions/neutral.png") and ResourceLoader.exists("res://assets/art/characters/CHR008/expressions/surprised.png"), "two six-expression sets import")

	var manifest = read_json("res://assets/art/asset_manifest.json")
	var story_path := ""
	var portrait_path := ""
	if manifest is Dictionary:
		for asset in manifest.get("assets", []):
			if asset.get("asset_id", "") == "bg_lantern_tunnel_dev": story_path = str(asset.get("godot_path", ""))
			if asset.get("asset_id", "") == "portrait_chr001_dev": portrait_path = str(asset.get("godot_path", ""))
	check(story_path.begins_with("res://assets/art/backgrounds/"), "legacy story ID migrates to premium background")
	check(portrait_path.begins_with("res://assets/art/characters/CHR001/"), "legacy CHR001 portrait ID migrates to premium portrait")

	var settings_source := FileAccess.get_file_as_string("res://autoload/settings_service.gd")
	check(settings_source.contains("\"audio_enabled\": false"), "project-stage audio flag is disabled")
	var battle_source := FileAccess.get_file_as_string("res://battle/view/battle_view.gd")
	check(battle_source.contains("BG_BATTLE_GLASS_RAIL") and battle_source.contains("vfx_presentations"), "battle view integrates premium background and pooled VFX")

	print("ART_TEST_SUMMARY total=%d pass=%d fail=%d" % [total, passed, failed])
	quit(0 if failed == 0 else 1)
