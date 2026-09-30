extends Node

## Phase 4 / D1 (2026-09-30): regional battle floors. The chapter table must
## match the map's biome families, every ornament and prop set must be valid
## geometry inside its budget, and the layers must draw at both layouts.

const RegionFloor := preload("res://battle/view/battle_region_floor.gd")
const RegionPalette := preload("res://chapter_map/view/region_palette.gd")

var checks := 0
var failures := 0

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("%s %s" % [label, detail])

func _ready() -> void:
	AppState.new_game()
	_tables()
	_geometry()
	_themes()
	_motes()
	_view_integration()
	await _draw_smoke()
	print("BATTLE_REGION_FLOOR_TESTS total=%d pass=%d fail=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _tables() -> void:
	var mismatches: Array = []
	var loaded := 0
	for chapter in range(1, 21):
		var path := "res://data/compiled/chapter_maps/CH%02d_MAP.json" % chapter
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary): continue
		loaded += 1
		var family := str(RegionPalette.for_definition(parsed).family)
		if family != str(RegionFloor.FAMILY_BY_CHAPTER.get(chapter, "")):
			mismatches.append("CH%02d map=%s floor=%s" % [chapter, family, RegionFloor.FAMILY_BY_CHAPTER.get(chapter, "?")])
	check(loaded == 20, "all twenty compiled chapter maps are readable", str(loaded))
	check(mismatches.is_empty(), "every chapter's floor family matches the map's biome family", JSON.stringify(mismatches))
	check(RegionFloor.FAMILY_BY_CHAPTER.size() == 20 and RegionFloor.ORNAMENT_BY_CHAPTER.size() == 20, "both tables cover twenty chapters")
	var used := {}
	for chapter in RegionFloor.ORNAMENT_BY_CHAPTER:
		used[str(RegionFloor.ORNAMENT_BY_CHAPTER[chapter])] = true
		check(RegionFloor.ORNAMENT_KINDS.has(str(RegionFloor.ORNAMENT_BY_CHAPTER[chapter])), "chapter %d has a known ornament" % chapter)
	check(used.size() == RegionFloor.ORNAMENT_KINDS.size(), "all ten ornament kinds are used by some chapter", JSON.stringify(used.keys()))
	var families := {}
	for chapter in RegionFloor.FAMILY_BY_CHAPTER: families[str(RegionFloor.FAMILY_BY_CHAPTER[chapter])] = true
	check(families.size() == 8 and RegionFloor.THEMES.size() == 8, "eight biome families each have a theme")
	for family in RegionFloor.THEMES:
		check(RegionFloor.THEMES[family].has_all(["grade", "haze", "floor", "accent", "mote", "props", "vignette"]), "%s theme is complete" % family)

func _finite(point: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y)

func _geometry() -> void:
	var worst := 0
	for kind in RegionFloor.ORNAMENT_KINDS:
		var shapes: Array = RegionFloor.ornament(kind)
		check(shapes.size() >= 8 and shapes.size() <= 140, "%s ornament stays inside the draw budget" % kind, str(shapes.size()))
		worst = maxi(worst, shapes.size())
		var valid := true
		var inside := true
		for shape in shapes:
			var points: PackedVector2Array = shape.pts
			if points.size() < 2 or float(shape.a) < 0.0 or float(shape.a) > 1.0 or float(shape.w) < 0.0: valid = false
			for point in points:
				if not _finite(point): valid = false
				if point.length() > 1.12: inside = false
		check(valid, "%s ornament geometry is finite with sane alpha and width" % kind)
		check(inside, "%s ornament stays inside its unit disc" % kind)
		check(RegionFloor.ornament(kind) == shapes, "%s ornament is cached" % kind)
	check(worst <= 140, "the heaviest ornament is at most 140 shapes per frame", str(worst))
	for kind in ["fern", "ice", "rock", "pillar", "reed", "float", "column"]:
		var items: Array = RegionFloor.props(kind)
		check(items.size() >= 2, "%s props have silhouettes" % kind)
		var bounded := true
		for item in items:
			var points: PackedVector2Array = item.pts
			if points.size() < 3: bounded = false
			for point in points:
				if not _finite(point) or point.x < -.05 or point.x > .16 or point.y < .80 or point.y > 1.03: bounded = false
		check(bounded, "%s props sit in the bottom-left corner and stay clear of the lanes" % kind)
	check(RegionFloor.props("none").is_empty(), "the glass family keeps the painted crystals and adds no props")

func _themes() -> void:
	check(RegionFloor.chapter_number({"chapter_id": "CH07"}) == 7 and RegionFloor.chapter_number({"id": "CH12-N05"}) == 12 and RegionFloor.chapter_number({"id": "TRAINING"}) == 0, "chapters parse from chapter_id or stage id")
	check(RegionFloor.theme_for_stage({"id": "TUTORIAL"}).is_empty() and RegionFloor.theme_for_stage({}).is_empty(), "a stage without a chapter gets no regional dressing")
	var forest := RegionFloor.theme_for_stage({"chapter_id": "CH01"})
	check(str(forest.family) == "FOREST" and str(forest.ornament) == "leaf" and int(forest.chapter) == 1, "chapter 1 is the forest with the leaf ornament")
	check(RegionFloor.background_grade({}) == Color.WHITE and RegionFloor.background_grade(forest) == forest.grade, "the plate grade follows the theme and is neutral without one")
	var accents := {}
	for chapter in [2, 12, 14, 16, 17, 19, 20]:
		accents[RegionFloor.theme_for_stage({"chapter_id": "CH%02d" % chapter}).accent.to_html()] = true
	check(accents.size() >= 4, "ruins chapters get distinct accent hues", str(accents.size()))
	var grades := {}
	for family in RegionFloor.THEMES: grades[RegionFloor.THEMES[family].grade.to_html()] = true
	check(grades.size() == 8, "each family grades the plate differently")
	var within := true
	for family in RegionFloor.THEMES:
		var grade: Color = RegionFloor.THEMES[family].grade
		if grade.r < .7 or grade.r > 1.25 or grade.g < .7 or grade.g > 1.25 or grade.b < .7 or grade.b > 1.25: within = false
	check(within, "plate grades stay gentle (0.7 to 1.25 per channel)")

func _motes() -> void:
	var bounded := true
	for kind in ["pollen", "snow", "sand", "ember", "bubble", "spark", "star", "dust"]:
		var list: Array = RegionFloor.motes(kind)
		if list.size() != RegionFloor.MOTE_COUNT: bounded = false
		for seed in list:
			for clock in [0.0, 3.7, 41.2, 600.0]:
				var point: Vector2 = RegionFloor.mote_position(kind, seed, clock)
				if not _finite(point) or point.x < -.001 or point.x > 1.001 or point.y < .15 or point.y > .90: bounded = false
	check(bounded, "motes stay on screen above the floor for every kind and time")
	var moving := RegionFloor.mote_position("snow", RegionFloor.motes("snow")[0], 0.0) != RegionFloor.mote_position("snow", RegionFloor.motes("snow")[0], 5.0)
	check(moving and RegionFloor.motes("snow") == RegionFloor.motes("snow"), "motes drift over time from fixed seeds")

func _stage_sim(stage_id: String) -> BattleSimulation:
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage(stage_id), 4601, DataRegistry.data)
	return sim

func _view_integration() -> void:
	var view := BattleView.new()
	view.size = Vector2(1600, 900)
	view.setup(_stage_sim("CH07-N05"))
	var theme := view._region_theme()
	check(str(theme.get("family", "")) == "FROST" and str(theme.get("ornament", "")) == "snowflake", "a chapter 7 battle resolves the frost theme", JSON.stringify(theme.keys()))
	check(view._region_theme() == theme and view.region_theme_stage == "CH07-N05", "the theme is cached by stage id")
	view.region_dressing_enabled = false
	check(view._region_theme().is_empty(), "regional dressing can be switched off")
	view.region_dressing_enabled = true
	# The cached transform is the battlefield camera, exactly.
	view.field_offset = Vector2(6, -4)
	view.field_zoom = 1.12
	var xf := view._battlefield_transform()
	var agree := true
	for point in [Vector2(.1, .2), Vector2(.485, .745), Vector2(.9, .95), Vector2(0, 0), Vector2(1, 1)]:
		if (xf * point).distance_to(view._battlefield_point(point * view.size)) > .01: agree = false
	check(agree, "the floor transform equals the battlefield camera for every point")
	view.free()
	var stageless := BattleView.new()
	stageless.size = Vector2(800, 450)
	check(stageless._region_theme().is_empty(), "a view without a simulation has no theme")
	stageless.free()

class LayerProbe extends Control:
	const RegionFloor := preload("res://battle/view/battle_region_floor.gd")
	var region: Dictionary = {}
	var clock := 0.0
	var frames := 0
	var zoom := 1.0
	func _draw() -> void:
		frames += 1
		var xf := RegionFloor.battlefield_transform(size, zoom, Vector2(4, -3))
		RegionFloor.draw_far(self, region, size, clock)
		RegionFloor.draw_floor(self, region, xf, size, clock)
		RegionFloor.draw_front(self, region, xf, size)

func _draw_smoke() -> void:
	var probe := LayerProbe.new()
	add_child(probe)
	var frames_wanted := 0
	for layout in [Vector2(1600, 900), Vector2(390, 844)]:
		probe.size = layout
		for chapter in range(1, 21):
			probe.region = RegionFloor.theme_for_stage({"chapter_id": "CH%02d" % chapter})
			probe.clock = float(chapter) * 1.3
			probe.zoom = 1.0 + float(chapter % 3) * .05
			probe.queue_redraw()
			frames_wanted += 1
			await get_tree().process_frame
	await get_tree().process_frame
	check(probe.frames >= frames_wanted, "all twenty chapters draw all three layers at 1600x900 and 390x844", "%d/%d" % [probe.frames, frames_wanted])
	probe.region = {}
	probe.queue_redraw()
	await get_tree().process_frame
	check(probe.frames > frames_wanted, "an empty theme draws nothing and does not fail")
	probe.queue_free()
