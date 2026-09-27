extends Node

const Density := preload("res://battle/view/density_texture_loader.gd")
const Palette := preload("res://chapter_map/view/region_palette.gd")
const Shell := preload("res://screens/app_shell.gd")
var passed := 0
var failed := 0

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print(("PASS | " if ok else "FAIL | ") + label)

func _run() -> void:
	Density.clear_cache()
	var records: Array = []
	for id in ["CHR001", "CHR002"]:
		var root: String = "res://assets/runtime_web/map_density/r1/" + id + "/"
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root + "animation_manifest.json"))
		records.append({"path": root + "atlas.png", "sha256": manifest.atlas_sha256})
	var cold := await Density.load_pages(records, self)
	check(cold.size() == 2, "verified map textures load as a complete batch")
	var warm := await Density.load_pages([records[1], records[0]], self)
	check(warm.size() == 2 and warm[0] == cold[1] and warm[1] == cold[0], "warm texture reuse preserves caller order and object identity")
	check(Density.cache_snapshot().hits == 2 and Density.cache_snapshot().misses == 2, "repeat load performs no new page decoding")
	var bad: Dictionary = records[0].duplicate()
	bad.sha256 = "0".repeat(64)
	check((await Density.load_pages([bad], self)).is_empty(), "changed expected hash never receives the old cached page")
	check((await Density.load_pages(records, null)).is_empty(), "abandoned owner cannot obtain cached pages")
	var malicious: Dictionary = records[0].duplicate()
	malicious.path = "res://assets/runtime_web/map_density/../private.png"
	check((await Density.load_pages([malicious], self)).is_empty(), "cache refuses traversal paths")
	cold.clear()
	warm.clear()
	Density.clear_cache()
	# More than the budget in independent allocations must evict old entries,
	# while a texture still owned by a scene remains reusable through a weak ref.
	var active: Texture2D
	for index in range(6):
		var texture := ImageTexture.create_from_image(Image.create(2048, 2048, false, Image.FORMAT_RGBA8))
		if index == 0: active = texture
		Density._remember_page("fixture_%d" % index, texture)
	check(Density.cache_snapshot().retained_bytes <= Density.CACHE_BUDGET_BYTES and Density.cache_snapshot().retained_pages == 4, "retained RGBA texture memory stays within 64 MiB under eviction")
	check(Density._cached_page("fixture_0") == active, "evicted page still owned by a scene is reused without copying")
	active = null
	Density.clear_cache()
	var reusable := ImageTexture.create_from_image(Image.create(1024, 512, false, Image.FORMAT_RGBA8))
	var identity := reusable.get_instance_id()
	Density._remember_page("compact_effect", reusable)
	reusable = null
	for index in range(8):
		Density._remember_page("large_actor_%d" % index, ImageTexture.create_from_image(Image.create(2048, 2048, false, Image.FORMAT_RGBA8)))
	var retained := Density._cached_page("compact_effect")
	check(retained != null and retained.get_instance_id() == identity, "a large sequential actor scan cannot evict the reusable compact effect page")
	check(Density.cache_snapshot().retained_bytes <= Density.CACHE_BUDGET_BYTES, "scan-resistant admission preserves the memory cap")
	retained = null
	Density.clear_cache()
	AppState.new_game()
	var shell := Shell.new()
	check(shell.region_entry_stage("CH01") == "CH01-N01" and shell.region_entry_stage("CH02").is_empty(), "region selector respects fresh-save chapter locks")
	check(shell.region_entry_stage("CH99").is_empty(), "unknown region cannot be entered")
	var families: Dictionary = {}
	for number in range(1, 21):
		var chapter_id := "CH%02d" % number
		var chapter := DataRegistry.chapter(chapter_id)
		var definition := ChapterMapLoader.load_map(chapter_id + "_MAP")
		check(ChapterMapLoader.validate(definition).is_empty(), chapter_id + " canonical map and routes validate")
		check(ChapterMapScreen.region_status_title(definition, true) == "제%d장" % number and ChapterMapScreen.region_status_title(definition, false) == LocalizationService.tr_key(str(chapter.name_key)), chapter_id + " map status uses the current chapter identity")
		families[Palette.for_definition(definition).family] = true
		check(shell.region_entry_stage(chapter_id) == chapter_id + "-N01", chapter_id + " newly opened region starts at its first operation")
		check(AppState.queue_story_event("MAP_ENTER", "", chapter_id), chapter_id + " queues its introduction")
		var intro := AppState.next_pending_story_trigger(chapter_id)
		check(not intro.is_empty() and DataRegistry.by_id("scenarios", str(intro.get("scenario_id", ""))).get("chapter_id", "") == chapter_id, chapter_id + " introduction belongs to the selected region")
		AppState.complete_story_trigger_for_scenario(str(intro.get("scenario_id", "")))
		check(not AppState.queue_story_event("MAP_ENTER", "", chapter_id), chapter_id + " completed introduction does not repeat on return")
		for stage_id in chapter.normal_stage_ids:
			AppState.profile.first_clear[stage_id] = true
			AppState.profile.stage_stars[stage_id] = 3
		AppState.profile.chapter_progress[chapter_id].normal_highest = 20
		AppState.profile.chapter_progress[chapter_id].hard_unlocked = true
		check(shell.region_entry_stage(chapter_id) == chapter_id + "-H01", chapter_id + " resumes the first uncleared hard operation")
		for stage_id in chapter.hard_stage_ids:
			AppState.record_stage_clear(str(stage_id), 3)
		var outro: Dictionary = DataRegistry.by_id("chapter_story_triggers", "TRIG_" + chapter_id + "_OUTRO")
		AppState.queue_story_event(str(outro.get("event", "")), str(outro.get("stage_id", "")), chapter_id)
		var ending := AppState.next_pending_story_trigger(chapter_id)
		check(not ending.is_empty(), chapter_id + " final operation queues its chapter ending")
		AppState.complete_story_trigger_for_scenario(str(ending.get("scenario_id", "")))
		check(shell.region_entry_stage(chapter_id) == chapter_id + "-N01", chapter_id + " completed region remains revisitable")
	check(families.size() == 8, "all eight distinct environment palettes are represented")
	AppState.new_game()
	# The chapter ending plays on the final normal operation (N20).
	AppState.selected_stage_id = "CH01-N20"
	AppState.profile.chapter_progress.CH02.unlocked = true
	AppState.queue_story_event("STAGE_CLEAR", "CH01-N20", "CH01")
	shell._travel_to_region("CH02")
	check(SceneRouter.current_screen == "STORY" and AppState.active_scenario_id == "SCN_CH01_OUTRO" and AppState.selected_stage_id == "CH01-N20", "region travel plays the departing ending before changing chapters")
	check(AppState.route_payload.get("region_destination", "") == "CH02-N01", "requested region survives the ending route")
	AppState.complete_story_trigger_for_scenario("SCN_CH01_OUTRO")
	shell.current_screen = "STORY"
	shell.story_navigation_pending = true
	shell._commit_story_navigation("STAGE_SELECT")
	check(AppState.selected_stage_id == "CH02-N01" and SceneRouter.current_screen == "STAGE_SELECT", "completed ending transfers to the intended region")
	check(AppState.queue_story_event("MAP_ENTER", "", "CH02") and AppState.next_pending_story_trigger("CH02").scenario_id == "SCN_CH02_INTRO", "arrival then queues the next chapter introduction")
	shell.free()
	print("REGION_LOADING_SUMMARY total=%d pass=%d fail=%d" % [passed + failed, passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
