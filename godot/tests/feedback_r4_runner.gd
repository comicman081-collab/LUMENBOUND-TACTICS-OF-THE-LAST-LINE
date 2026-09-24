extends Node

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	AppState.new_game()
	AppState.profile.account.level = 30
	for id in CharacterProgression.MATERIAL_XP: AppState.profile.inventory[id] = 0
	AppState.profile.inventory.CREDIT = 500000
	AppState.profile.inventory.TRAINING_NOTE_XL = 1
	var original := AppState.profile.duplicate(true)
	var plan := CharacterProgression.preview_target("CHR001",2)
	check(bool(plan.ok) and int(plan.materials.TRAINING_NOTE_XL) == 1,"one available large note auto selected")
	check(AppState.profile == original,"preview does not spend or alter state")
	var result := CharacterProgression.level_to("CHR001",2)
	check(result.ok and int(AppState.profile.roster.CHR001.level) == 2,"target stops at requested level")
	check(int(AppState.profile.roster.CHR001.training_xp_reserve) + int(plan.required_xp) == 10000,"unused training EXP conserved")
	check(AppState.inventory_count("TRAINING_NOTE_XL") == 0,"one note spent exactly once")
	var next := CharacterProgression.preview_target("CHR001",3)
	check(bool(next.ok) and next.materials.is_empty(),"surplus used before new notes")
	AppState.profile.inventory.CREDIT = 0
	original = AppState.profile.duplicate(true)
	check(not CharacterProgression.level_to("CHR001",3).ok and AppState.profile == original,"failed credit check spends nothing")
	AppState.profile.inventory.CREDIT = 500000
	AppState.profile.inventory.TRAINING_NOTE_S = 99
	var max_level := CharacterProgression.maximum_target("CHR001")
	check(max_level > 2 and max_level <= 20,"MAX respects material and breakthrough cap")
	check(not CharacterProgression.level_to("CHR001",21).ok,"no implicit breakthrough")
	AppState.profile.roster.CHR001.unlocked = false
	check(not CharacterProgression.level_to("CHR001",3).ok,"locked characters cannot consume materials")
	AppState.new_game()
	var map := ChapterMapLoader.load_map("CH01_MAP")
	check(ChapterMapLoader.validate(map).is_empty(),"expanded scout map validates")
	var scouts := 0
	var nearest := 10000
	for node in map.nodes:
		if bool(node.get("forward_patrol",false)):
			scouts += 1
			if str(node.stage_id) == "CH01-N01": nearest = mini(nearest,HexCoord.distance(Vector2i.ZERO,Vector2i(int(node.q),int(node.r))))
	check(scouts >= 20,"at least twenty additional forward patrols per chapter")
	check(nearest <= 5,"first hostile within initial sight and two movement turns")
	var screen := ChapterMapScreen.new()
	screen.definition = map
	screen.map_state = AppState.chapter_map_state("CH01_MAP")
	screen.moving = true
	check(not screen._start_patrol_contact("NODE_N19",Vector2i.ZERO),"locked patrol cannot claim a movement coroutine")
	check(screen.moving,"rejected contact leaves movement owner to finish its route")
	screen.free()
	# Divisible-denomination selector against brute-force inventories, including
	# denomination gaps; this checks minimization rather than copying its logic.
	for small in range(4):
		for medium in range(3):
			AppState.profile.inventory.TRAINING_NOTE_S = small
			AppState.profile.inventory.TRAINING_NOTE_M = medium
			AppState.profile.inventory.TRAINING_NOTE_L = 1
			AppState.profile.inventory.TRAINING_NOTE_XL = 0
			for needed in [140,420,680,1040,2510,3320]:
				var best := 999999
				for a in range(small+1):
					for b in range(medium+1):
						for c in range(2):
							var value := a*100+b*500+c*2500
							if value >= needed: best = mini(best,value)
				var pick := CharacterProgression._select_notes(needed)
				check((best == 999999 and not pick.ok) or (pick.ok and int(pick.xp) == best),"minimal material selection %d/%d/%d" % [small,medium,needed])
	print("FEEDBACK_R4_TESTS total=%d pass=%d fail=%d" % [checks,checks-failures,failures])
	get_tree().quit(0 if failures == 0 else 1)
