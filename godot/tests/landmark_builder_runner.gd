extends Node

## Phase 4 / A2 (2026-09-30): procedural map landmarks. Every kind must build a
## valid, bounded, correctly wound mesh in every biome family, stay inside its
## triangle budget, and be shared through the cache.

const Landmarks := preload("res://chapter_map/view/landmark_builder.gd")

const SMALL_BUDGET := 420
const BOSS_BUDGET := 1500
const FAMILIES := ["FOREST", "FROST", "DUNE", "ASH", "TIDAL", "GLASS", "LUNAR", "RUINS"]

var checks := 0
var failures := 0

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("%s %s" % [label, detail])

func _ready() -> void:
	_tables()
	_builds()
	_winding()
	_cache()
	_palettes()
	print("LANDMARK_BUILDER_TESTS total=%d pass=%d fail=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _tables() -> void:
	check(Landmarks.BOSS_BY_CHAPTER.size() == 20, "every chapter has a boss landmark")
	var pairs := {}
	for chapter in range(1, 21):
		var spec := Landmarks.boss_spec(chapter)
		check(not spec.is_empty() and Landmarks.BOSS_KINDS.has(str(spec.kind)), "chapter %d names a known boss archetype" % chapter)
		pairs["%s|%d" % [spec.kind, spec.variant]] = true
	check(pairs.size() == 20, "no two chapters share an archetype and variant", str(pairs.size()))
	var used := {}
	for chapter in Landmarks.BOSS_BY_CHAPTER: used[str(Landmarks.BOSS_BY_CHAPTER[chapter][0])] = true
	check(used.size() == Landmarks.BOSS_KINDS.size(), "all thirteen boss archetypes are used", JSON.stringify(used.keys()))
	check(Landmarks.boss_spec(0).is_empty() and Landmarks.boss_spec(21).is_empty(), "unknown chapters have no boss landmark")
	check(Landmarks.all_kinds().size() == Landmarks.SMALL_KINDS.size() + 20, "all_kinds lists small kinds and every chapter boss")
	check(Landmarks.build("nonsense", "RUINS").is_empty(), "an unknown kind builds nothing")

func _builds() -> void:
	var worst_small := 0
	var worst_boss := 0
	for spec in Landmarks.all_kinds():
		var kind := str(spec.kind)
		var small := Landmarks.SMALL_KINDS.has(kind)
		for family in FAMILIES:
			var built := Landmarks.build(kind, family, int(spec.variant))
			var label := "%s/%d in %s" % [kind, int(spec.variant), family]
			if built.is_empty():
				check(false, "%s builds" % label)
				continue
			var body: ArrayMesh = built.body
			check(body != null and body.get_surface_count() == 1, "%s has one body surface" % label)
			var triangles := int(built.triangles)
			if small: worst_small = maxi(worst_small, triangles)
			else: worst_boss = maxi(worst_boss, triangles)
			check(triangles >= 24 and triangles <= (SMALL_BUDGET if small else BOSS_BUDGET), "%s stays inside its triangle budget" % label, str(triangles))
			var bounds: AABB = built.bounds
			var footprint := maxf(bounds.size.x, bounds.size.z)
			check(bounds.size.is_finite() and bounds.position.is_finite(), "%s has finite bounds" % label)
			check(bounds.position.y >= -.08, "%s sits on the ground" % label, str(bounds.position.y))
			if small:
				check(footprint <= 2.4 and bounds.size.y <= 2.4, "%s stays tile-sized" % label, str(bounds.size))
			else:
				check(footprint <= 5.2 and bounds.size.y >= 2.0 and bounds.size.y <= 6.2, "%s is large but bounded" % label, str(bounds.size))
			var arrays := body.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var finite := true
			for vertex in vertices:
				if not vertex.is_finite(): finite = false
			check(finite and colors.size() == vertices.size(), "%s has finite vertices and a colour per vertex" % label)
			var glow: ArrayMesh = built.glow
			if glow != null:
				check(glow.get_surface_count() == 1 and glow.get_aabb().size.is_finite(), "%s glow layer is valid" % label)
	check(worst_small <= SMALL_BUDGET and worst_boss <= BOSS_BUDGET, "heaviest landmarks: small %d, boss %d" % [worst_small, worst_boss])
	print("LANDMARK_BUDGET small=%d boss=%d" % [worst_small, worst_boss])

func _winding() -> void:
	## Every triangle of a closed-ish landmark must face away from the part it
	## belongs to. With Godot's clockwise front faces that means the geometric
	## normal of (a, c, b) equals the stored normal.
	var bad := 0
	var total := 0
	var upward := 0
	for spec in Landmarks.all_kinds():
		var built := Landmarks.build(str(spec.kind), "RUINS", int(spec.variant))
		var arrays: Array = (built.body as ArrayMesh).surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in range(0, indices.size(), 3):
			var a := vertices[indices[index]]
			var b := vertices[indices[index + 1]]
			var c := vertices[indices[index + 2]]
			# Godot front faces are clockwise from outside, so for the stored
			# index order the cross product points inward: -cross is outward.
			var face := (b - a).cross(c - a)
			if face.length_squared() < 1e-10: continue
			total += 1
			if (-face).normalized().dot(normals[indices[index]]) < .99: bad += 1
			if normals[indices[index]].y > .5: upward += 1
	check(total > 2000, "winding check inspected a real sample", str(total))
	check(bad == 0, "no triangle disagrees with its stored normal", str(bad))
	check(upward > 100, "roofs and tops face the sky", str(upward))

func _cache() -> void:
	Landmarks.clear_cache()
	var first := Landmarks.build("tent", "ASH")
	var second := Landmarks.build("tent", "ASH")
	check(first.body == second.body, "the same kind and family shares one mesh")
	check(Landmarks.build("tent", "FROST").body != first.body, "another biome gets its own colours")
	check(Landmarks.build("train", "FOREST", 0).body != Landmarks.build("train", "FOREST", 1).body, "variants differ")

func _palettes() -> void:
	for family in FAMILIES:
		var palette := Landmarks.palette(family)
		check(palette.has_all(["stone", "dark", "wood", "metal", "cloth", "glass", "hostile", "lamp", "cool"]), "%s palette is complete" % family)
	check(Landmarks.palette("NOPE").stone == Landmarks.palette("RUINS").stone, "an unknown family falls back to the ruins palette")
	var families := {}
	for family in FAMILIES: families[Landmarks.palette(family).cloth.to_html()] = true
	check(families.size() == 8, "each biome has its own cloth colour")
