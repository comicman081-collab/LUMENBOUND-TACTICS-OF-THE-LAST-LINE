extends Node

var checks: Array[Dictionary] = []
func check(ok: bool, label: String) -> void:
	checks.append({"pass":ok,"name":label})
	if not ok: push_error(label)

func _ready() -> void:
	AppState.profile.stage_stars["CH01-N01"] = 3
	AppState.profile.first_clear["CH01-N01"] = true
	AppState.profile.story_flags.PROLOGUE_READ = true
	AppState.profile.roster.CHR001.level = 15
	AppState.selected_stage_id = "CH02-N01"
	AppState.pending_battle_token = "previous-run"
	check(SaveService.save_game().ok,"save prior progress")
	check(SaveService.start_new_game().ok,"new game saves successfully")
	check(AppState.profile.stage_stars.is_empty() and AppState.profile.first_clear.is_empty(),"new game clears clears/rewards")
	check(AppState.profile.story_flags.is_empty() and AppState.profile.last_scenario_position.is_empty(),"new game clears scenario progress")
	check(int(AppState.profile.roster.CHR001.level)==1,"new game resets character growth")
	check(AppState.selected_stage_id=="CH01-N01" and AppState.pending_battle_token.is_empty(),"new game resets battle and map selection")
	var previous := SaveService._read_valid(SaveService.BACKUP_PATH)
	check(previous.ok and int(previous.value.roster.CHR001.level)==15,"old save retained as atomic backup")
	AppState.profile.roster.CHR001.level = 99
	check(SaveService.load_game().ok and int(AppState.profile.roster.CHR001.level)==1,"fresh save survives reload")
	# Deliberately fail directory preparation inside this isolated QA profile.
	SaveService.soak_sandbox_enabled = true
	SaveService.soak_sandbox_session = "blocked-new-game"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://r15_soak_sandbox"))
	var blocker := FileAccess.open("user://r15_soak_sandbox/blocked-new-game",FileAccess.WRITE)
	blocker.store_string("test-only directory blocker")
	blocker.close()
	AppState.profile.roster.CHR001.level = 7
	AppState.selected_stage_id = "CH03-N01"
	check(not SaveService.start_new_game().ok,"failed save does not report a successful restart")
	check(int(AppState.profile.roster.CHR001.level)==7 and AppState.selected_stage_id=="CH03-N01","failed restart restores prior profile and context")
	SaveService.soak_sandbox_enabled = false
	var font := BattleView.DAMAGE_FONT
	check(font != null and font.has_char(48) and font.has_char(57),"rounded font contains damage digits")
	# The flank / cover / area prefixes are Hangul; the rounded face has none and the web has no system
	# font, so the battle font must stand behind it (BattleView binds it as soon as the font loads).
	check(not font.has_char(0xCE21),"rounded font alone has no Hangul (the reason for the fallback)")
	var prefix_view := BattleView.new()
	prefix_view.battle_font = load("res://assets/fonts/LanternSans-Medium.ttf") as Font
	prefix_view._bind_damage_font_fallback()
	var prefix_ok := true
	for glyph in "측면엄폐직격":
		prefix_ok = prefix_ok and font.has_char(glyph.unicode_at(0))
	check(prefix_ok,"damage prefixes (측면 / 엄폐 / 직격) resolve through the battle font fallback")
	prefix_view.free()
	var failures := checks.filter(func(row):return not row.pass)
	var output := FileAccess.open("res://../reports/existing_roster_spritegen_20260911/restart_tests.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"status":"PASS" if failures.is_empty() else "FAIL"},"\t"))
	output.close()
	print("RESTART_TESTS ",checks.size()-failures.size(),"/",checks.size())
	get_tree().quit(0 if failures.is_empty() else 1)
