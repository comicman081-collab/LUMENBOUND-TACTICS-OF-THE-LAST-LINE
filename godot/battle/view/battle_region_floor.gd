extends RefCounted

## Phase 4 / D1 (2026-09-30): the battle floor gets a regional identity. Every
## chapter belongs to one of the map's eight biome families and one of ten floor
## ornaments. The painted battle plate (one normal, one boss) stays as the far
## layer and is colour-graded; on top of it the view draws three light layers:
##   far   - horizon haze and a few drifting motes (pollen, snow, sand, embers ...)
##   floor - a family-tinted floor plate and the chapter's ornament (signal emblem,
##           rail turntable, rose window ...), projected with the grid transform
##   front - dark prop silhouettes in both bottom corners and an edge vignette
## Everything is generated from cached unit geometry: no downloaded art and
## nothing the simulation or the grid cells depend on. The strokes are built once
## per chapter and view size into meshes (see the drawing section below).

## Same table the map uses (chapter -> visual_set_id -> RegionPalette family).
## tests/battle_region_floor_runner.gd checks it against the compiled chapter maps.
const FAMILY_BY_CHAPTER := {
	1: "FOREST", 2: "RUINS", 3: "GLASS", 4: "TIDAL", 5: "ASH", 6: "GLASS", 7: "FROST", 8: "DUNE", 9: "LUNAR", 10: "LUNAR",
	11: "TIDAL", 12: "RUINS", 13: "DUNE", 14: "RUINS", 15: "LUNAR", 16: "RUINS", 17: "RUINS", 18: "ASH", 19: "RUINS", 20: "RUINS",
}
const ORNAMENT_BY_CHAPTER := {
	1: "leaf", 2: "turntable", 3: "signal", 4: "wave", 5: "crack", 6: "signal", 7: "snowflake", 8: "sun", 9: "moon", 10: "moon",
	11: "wave", 12: "rose", 13: "turntable", 14: "gauge", 15: "moon", 16: "rose", 17: "gauge", 18: "crack", 19: "turntable", 20: "signal",
}
const ORNAMENT_KINDS := ["signal", "turntable", "rose", "leaf", "snowflake", "sun", "crack", "wave", "moon", "gauge"]

const THEMES := {
	"FOREST": {"grade": Color(.93, 1.04, .93), "haze": Color("b9d8a0"), "floor": Color("3e5a2c"), "accent": Color("b4e48c"), "mote": "pollen", "props": "fern", "vignette": Color(.01, .05, .02)},
	"FROST": {"grade": Color(.90, 1.0, 1.12), "haze": Color("e6f2ff"), "floor": Color("8fb4c4"), "accent": Color("dff3ff"), "mote": "snow", "props": "ice", "vignette": Color(.02, .05, .10)},
	"DUNE": {"grade": Color(1.10, .98, .80), "haze": Color("e6cc9a"), "floor": Color("a58a59"), "accent": Color("ffd98a"), "mote": "sand", "props": "rock", "vignette": Color(.08, .05, .01)},
	"ASH": {"grade": Color(1.02, .84, .80), "haze": Color("a39890"), "floor": Color("4a4440"), "accent": Color("ffb27a"), "mote": "ember", "props": "pillar", "vignette": Color(.06, .02, .01)},
	"TIDAL": {"grade": Color(.86, 1.03, 1.0), "haze": Color("a3d4cf"), "floor": Color("3f6f6a"), "accent": Color("9ef0e0"), "mote": "bubble", "props": "reed", "vignette": Color(.01, .05, .06)},
	"GLASS": {"grade": Color(1.0, 1.0, 1.0), "haze": Color("b4d6dc"), "floor": Color("405961"), "accent": Color("8ff2ff"), "mote": "spark", "props": "none", "vignette": Color(.01, .04, .07)},
	"LUNAR": {"grade": Color(.93, .90, 1.12), "haze": Color("b9b4e0"), "floor": Color("4b4c65"), "accent": Color("d9cfff"), "mote": "star", "props": "float", "vignette": Color(.03, .02, .08)},
	"RUINS": {"grade": Color(1.04, .98, .88), "haze": Color("cdbd9c"), "floor": Color("6f6a55"), "accent": Color("ffe3a0"), "mote": "dust", "props": "column", "vignette": Color(.05, .04, .02)},
}

## Ornament footprint on the floor, in normalized battlefield space (the same
## space as BattleGrounding cells).
const ORNAMENT_CENTER := Vector2(.485, .745)
const ORNAMENT_RADIUS := Vector2(.305, .105)
const FLOOR_LINE_ALPHA := .66
const MOTE_COUNT := 18

static var _ornaments: Dictionary = {}
static var _props: Dictionary = {}
static var _motes: Dictionary = {}

# ------------------------------------------------------------------ theme

static func chapter_number(stage: Dictionary) -> int:
	var id := str(stage.get("chapter_id", ""))
	if id.is_empty(): id = str(stage.get("id", "")).left(4)
	if id.length() >= 4 and id.begins_with("CH") and id.substr(2, 2).is_valid_int(): return int(id.substr(2, 2))
	return 0

## Empty when the stage has no chapter (tests, tutorials): the view then keeps
## the plain painted battle plate.
static func theme_for_stage(stage: Dictionary) -> Dictionary:
	var chapter := chapter_number(stage)
	if not FAMILY_BY_CHAPTER.has(chapter): return {}
	var family := str(FAMILY_BY_CHAPTER[chapter])
	var theme: Dictionary = (THEMES[family] as Dictionary).duplicate()
	# A small per-chapter hue shift separates chapters that share a family.
	var shift := (float((chapter * 37) % 50) - 25.0) / 25.0 * .035
	var accent: Color = theme.accent
	accent.h = fposmod(accent.h + shift, 1.0)
	theme["accent"] = accent
	theme["family"] = family
	theme["chapter"] = chapter
	theme["ornament"] = str(ORNAMENT_BY_CHAPTER[chapter])
	return theme

static func background_grade(theme: Dictionary) -> Color:
	if theme.is_empty(): return Color.WHITE
	return theme.grade

## Normalized-view -> screen transform for the battlefield camera. Identical to
## BattleView._battlefield_point(p * size) for every p.
static func battlefield_transform(size: Vector2, zoom: float, offset: Vector2) -> Transform2D:
	var centre := size * .5
	return Transform2D(Vector2(size.x * zoom, 0.0), Vector2(0.0, size.y * zoom), centre * (1.0 - zoom) + offset)

# --------------------------------------------------------------- geometry

static func _shape(points: PackedVector2Array, width: float, alpha: float, fill := false, hot := false, spin := 0.0) -> Dictionary:
	return {"pts": points, "w": width, "a": alpha, "fill": fill, "hot": hot, "spin": spin}

static func _polar(radius: float, angle: float) -> Vector2:
	return Vector2(cos(angle), sin(angle)) * radius

static func _arc(radius: float, from_angle: float, to_angle: float) -> PackedVector2Array:
	var steps := maxi(6, int(absf(to_angle - from_angle) / TAU * 64.0))
	var points := PackedVector2Array()
	for index in range(steps + 1):
		points.append(_polar(radius, lerpf(from_angle, to_angle, float(index) / float(steps))))
	return points

static func _ring(radius: float) -> PackedVector2Array:
	return _arc(radius, 0.0, TAU)

static func _seg(a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, b])

## A pointed lens (petal or leaf) from radius r0 to r1 around `angle`.
static func _lens(r0: float, r1: float, angle: float, half_angle: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for step in range(9):
		var t := float(step) / 8.0
		var radius := lerpf(r0, r1, t)
		var spread := half_angle * sin(PI * t) * (1.0 - .25 * t)
		left.append(_polar(radius, angle - spread))
		right.append(_polar(radius, angle + spread))
	right.reverse()
	left.append_array(right)
	return left

static func ornament(kind: String) -> Array:
	if _ornaments.has(kind): return _ornaments[kind]
	var shapes: Array = []
	match kind:
		"signal":
			shapes.append(_shape(_ring(1.0), 2.4, .95))
			shapes.append(_shape(_ring(.92), 1.0, .40))
			shapes.append(_shape(_ring(.62), 1.6, .70))
			for index in range(48):
				var angle := TAU * float(index) / 48.0
				shapes.append(_shape(_seg(_polar(.68 if index % 4 == 0 else .74, angle), _polar(.86, angle)), 1.1, .55))
			for side in [0.0, PI]:
				for radius in [.30, .40, .50]:
					shapes.append(_shape(_arc(radius, side - .70, side + .70), 1.7, .75))
			shapes.append(_shape(PackedVector2Array([Vector2(0, -.26), Vector2(-.10, .14), Vector2(.10, .14), Vector2(0, -.26)]), 1.8, .95, true))
		"turntable":
			shapes.append(_shape(_ring(1.0), 2.6, .95))
			shapes.append(_shape(_ring(.94), 1.0, .40))
			shapes.append(_shape(_ring(.80), 1.6, .70))
			for axis in [0.0, PI * .5]:
				for side in [-.05, .05]:
					var perp := _polar(side, axis + PI * .5)
					shapes.append(_shape(_seg(_polar(-.80, axis) + perp, _polar(.80, axis) + perp), 1.8, .85, false, false, .10))
				for step in range(-6, 7):
					var at := _polar(float(step) * .12, axis)
					shapes.append(_shape(_seg(at + _polar(.08, axis + PI * .5), at - _polar(.08, axis + PI * .5)), 1.1, .45, false, false, .10))
			for diagonal in [PI * .25, PI * .75, PI * 1.25, PI * 1.75]:
				shapes.append(_shape(_seg(_polar(.22, diagonal), _polar(.80, diagonal)), 1.0, .30, false, false, .10))
			shapes.append(_shape(_ring(.16), 1.8, .90, true))
			for index in range(24):
				var angle := TAU * float(index) / 24.0
				shapes.append(_shape(_seg(_polar(.94, angle), _polar(1.0, angle)), 1.0, .5))
		"rose":
			shapes.append(_shape(_ring(1.0), 2.4, .95))
			shapes.append(_shape(_ring(.93), 1.0, .40))
			shapes.append(_shape(_ring(.36), 1.5, .75))
			shapes.append(_shape(_ring(.16), 1.3, .65, true))
			for index in range(12):
				var angle := TAU * float(index) / 12.0
				shapes.append(_shape(_lens(.36, .88, angle, .23), 1.5, .80, false, false, .05))
				shapes.append(_shape(_seg(_polar(.16, angle), _polar(.36, angle)), 1.0, .45, false, false, .05))
				shapes.append(_shape(_arc(.96, angle - .10, angle + .10), 1.2, .55))
		"leaf":
			shapes.append(_shape(_ring(1.0), 2.2, .85))
			shapes.append(_shape(_ring(.92), 1.0, .40))
			shapes.append(_shape(_ring(.20), 1.6, .80, true))
			for index in range(8):
				var angle := TAU * float(index) / 8.0
				shapes.append(_shape(_lens(.30, .86, angle, .30), 1.6, .85, true, false, .04))
				shapes.append(_shape(_seg(_polar(.30, angle), _polar(.80, angle)), 1.0, .55, false, false, .04))
				var between := angle + TAU / 16.0
				shapes.append(_shape(_lens(.55, .82, between, .14), 1.1, .55, false, false, .04))
		"snowflake":
			shapes.append(_shape(_ring(1.0), 1.8, .65))
			shapes.append(_shape(_arc(.94, 0.0, TAU), 1.0, .35))
			var hex := PackedVector2Array()
			for index in range(7): hex.append(_polar(.36, TAU * float(index) / 6.0 + PI / 6.0))
			shapes.append(_shape(hex, 1.6, .70, true))
			for index in range(6):
				var angle := TAU * float(index) / 6.0
				shapes.append(_shape(_seg(_polar(.14, angle), _polar(.96, angle)), 2.2, .95, false, false, .035))
				for branch in [[.50, .24], [.72, .18]]:
					var base := _polar(float(branch[0]), angle)
					for turn in [-1.0, 1.0]:
						shapes.append(_shape(_seg(base, base + _polar(float(branch[1]), angle + turn * PI / 3.0)), 1.5, .80, false, false, .035))
		"sun":
			shapes.append(_shape(_ring(1.0), 2.4, .90))
			shapes.append(_shape(_ring(.86), 1.0, .40))
			shapes.append(_shape(_ring(.34), 2.0, .90, true))
			for index in range(16):
				var angle := TAU * float(index) / 16.0
				var long_ray := index % 2 == 0
				shapes.append(_shape(_seg(_polar(.44, angle), _polar(.80 if long_ray else .66, angle)), 2.4 if long_ray else 1.4, .85 if long_ray else .60, false, false, .05))
			for radius in [.62, .74, .86]:
				shapes.append(_shape(_arc(radius, .35, PI - .35), 1.2, .40))
		"crack":
			for arc_range in [[.17, 1.22], [1.66, 2.62], [3.23, 4.62], [5.06, 6.03]]:
				shapes.append(_shape(_arc(1.0, float(arc_range[0]), float(arc_range[1])), 2.6, .90))
			for arc_range in [[0.0, 1.75], [2.27, 4.01], [4.36, 5.93]]:
				shapes.append(_shape(_arc(.72, float(arc_range[0]), float(arc_range[1])), 1.7, .65))
			for index in range(6):
				var base_angle := TAU * float(index) / 6.0 + .21
				var inner := PackedVector2Array()
				var outer := PackedVector2Array()
				for step in range(6):
					var radius := .14 + float(step) * .17
					var jitter := sin(float(index * 7 + step * 5) * 1.7) * .13
					var point := _polar(radius, base_angle + jitter)
					if step <= 3: inner.append(point)
					if step >= 3: outer.append(point)
				shapes.append(_shape(inner, 1.9, .95, false, true))
				shapes.append(_shape(outer, 1.5, .65))
			shapes.append(_shape(_ring(.13), 1.5, .95, true, true))
		"wave":
			for index in range(4):
				var radius := .30 + float(index) * .22
				var offset := float(index) * .40
				for piece in range(3):
					var start := offset + float(piece) * TAU / 3.0 + .18
					shapes.append(_shape(_arc(radius, start, start + TAU / 3.0 - .36), 2.3 - float(index) * .35, .90 - float(index) * .10, false, false, .03 * (1.0 if index % 2 == 0 else -1.0)))
			shapes.append(_shape(PackedVector2Array([Vector2(0, -.36), Vector2(.06, -.06), Vector2(.36, 0), Vector2(.06, .06), Vector2(0, .36), Vector2(-.06, .06), Vector2(-.36, 0), Vector2(-.06, -.06), Vector2(0, -.36)]), 1.4, .85, true, false, .0))
			shapes.append(_shape(_ring(1.0), 1.2, .40))
		"moon":
			shapes.append(_shape(_ring(1.0), 2.4, .90))
			shapes.append(_shape(_ring(.92), 1.0, .40))
			shapes.append(_shape(_ring(.36), 1.6, .75))
			shapes.append(_shape(_ring(.28), 1.0, .40))
			for index in range(8):
				var centre := _polar(.70, TAU * float(index) / 8.0 - PI * .5)
				var disc := PackedVector2Array()
				for step in range(25): disc.append(centre + _polar(.115, TAU * float(step) / 24.0))
				shapes.append(_shape(disc, 1.3, .75))
				var phase := TAU * float(index) / 8.0
				var lit := PackedVector2Array()
				for step in range(13):
					var phi := lerpf(-PI * .5, PI * .5, float(step) / 12.0)
					lit.append(centre + Vector2(cos(phi), sin(phi)) * .115)
				for step in range(13):
					var phi := lerpf(PI * .5, -PI * .5, float(step) / 12.0)
					lit.append(centre + Vector2(.115 * cos(phase) * cos(phi), .115 * sin(phi)))
				if index > 0: shapes.append(_shape(lit, 0.0, .85, true)) # new moon: nothing lit
			shapes.append(_shape(PackedVector2Array([Vector2(0, -.22), Vector2(.05, -.05), Vector2(.22, 0), Vector2(.05, .05), Vector2(0, .22), Vector2(-.05, .05), Vector2(-.22, 0), Vector2(-.05, -.05), Vector2(0, -.22)]), 1.2, .80, true, false, .05))
		"gauge":
			shapes.append(_shape(_ring(1.0), 2.6, .95))
			shapes.append(_shape(_ring(.94), 1.0, .40))
			shapes.append(_shape(_ring(.58), 1.5, .65))
			for index in range(60):
				var angle := TAU * float(index) / 60.0
				var major := index % 5 == 0
				shapes.append(_shape(_seg(_polar(.80 if major else .86, angle), _polar(.94, angle)), 1.6 if major else 1.0, .80 if major else .50))
			shapes.append(_shape(_arc(.70, PI * .75, PI * 2.25), 1.7, .70))
			for index in range(11):
				var angle := PI * .75 + float(index) / 10.0 * PI * 1.5
				shapes.append(_shape(_seg(_polar(.62, angle), _polar(.70, angle)), 1.2, .65))
			shapes.append(_shape(_seg(_polar(-.18, -.70), _polar(.66, -.70)), 2.4, .95, false, true, .18))
			shapes.append(_shape(_ring(.09), 1.5, .95, true))
	_ornaments[kind] = shapes
	return shapes

# ------------------------------------------------------------------ props

static func _blade(base: Vector2, tip: Vector2, half_width: float) -> PackedVector2Array:
	var direction := (tip - base).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var mid := base.lerp(tip, .55) + normal * half_width * .6
	return PackedVector2Array([base - normal * half_width, mid - normal * half_width * .5, tip, mid + normal * half_width, base + normal * half_width])

## Corner silhouettes for the LEFT corner, in normalized view space; the right
## corner mirrors them. Each entry is {pts, shade}; shade 0 is darkest.
static func props(kind: String) -> Array:
	if _props.has(kind): return _props[kind]
	var items: Array = []
	match kind:
		"fern":
			for blade in [[.030, .93, .012], [.050, .90, .010], [.068, .95, .009], [.020, .86, .010], [.082, .98, .007]]:
				items.append({"pts": _blade(Vector2(.028, 1.01), Vector2(float(blade[0]) + .03, float(blade[1])), float(blade[2])), "shade": .25})
			items.append({"pts": _blade(Vector2(.05, 1.01), Vector2(.012, .895), .010), "shade": .10})
		"ice":
			for spike in [[.02, .82, .028], [.055, .91, .024], [.085, .96, .018]]:
				var x := float(spike[0])
				items.append({"pts": PackedVector2Array([Vector2(x - float(spike[2]), 1.01), Vector2(x + .004, float(spike[1])), Vector2(x + float(spike[2]), 1.01)]), "shade": .35})
				items.append({"pts": PackedVector2Array([Vector2(x + .004, float(spike[1])), Vector2(x + float(spike[2]), 1.01), Vector2(x + .004, 1.01)]), "shade": .12})
		"rock":
			items.append({"pts": PackedVector2Array([Vector2(-.01, 1.01), Vector2(-.01, .90), Vector2(.03, .87), Vector2(.065, .905), Vector2(.085, .96), Vector2(.10, 1.01)]), "shade": .20})
			items.append({"pts": PackedVector2Array([Vector2(.05, 1.01), Vector2(.06, .955), Vector2(.09, .935), Vector2(.118, .975), Vector2(.12, 1.01)]), "shade": .32})
		"pillar":
			items.append({"pts": PackedVector2Array([Vector2(.012, 1.01), Vector2(.012, .84), Vector2(.03, .86), Vector2(.042, .825), Vector2(.058, .87), Vector2(.058, 1.01)]), "shade": .22})
			items.append({"pts": PackedVector2Array([Vector2(.070, 1.01), Vector2(.074, .945), Vector2(.10, .93), Vector2(.112, 1.01)]), "shade": .30})
		"reed":
			for index in range(8):
				var x := .012 + float(index) * .010
				var height := .86 + float((index * 5) % 7) * .022
				items.append({"pts": _blade(Vector2(x, 1.01), Vector2(x + .012 + float(index % 3) * .006, height), .004), "shade": .18 + float(index % 3) * .06})
		"float":
			items.append({"pts": PackedVector2Array([Vector2(.012, .88), Vector2(.058, .865), Vector2(.075, .895), Vector2(.03, .915)]), "shade": .28})
			items.append({"pts": PackedVector2Array([Vector2(.050, .945), Vector2(.092, .935), Vector2(.100, .962), Vector2(.064, .972)]), "shade": .22})
			items.append({"pts": PackedVector2Array([Vector2(.008, .965), Vector2(.03, .958), Vector2(.034, .985), Vector2(.012, .99)]), "shade": .18})
		"column":
			items.append({"pts": PackedVector2Array([Vector2(.008, 1.01), Vector2(.008, .875), Vector2(.03, .895), Vector2(.05, .86), Vector2(.052, 1.01)]), "shade": .24})
			items.append({"pts": PackedVector2Array([Vector2(.066, 1.01), Vector2(.070, .965), Vector2(.112, .955), Vector2(.116, 1.01)]), "shade": .32})
			items.append({"pts": PackedVector2Array([Vector2(.002, .875), Vector2(.058, .86), Vector2(.058, .888), Vector2(.002, .902)]), "shade": .36})
	_props[kind] = items
	return items

# ------------------------------------------------------------------ motes

## Deterministic per-mote seeds: {x, y, speed, phase, size}.
static func motes(kind: String) -> Array:
	if _motes.has(kind): return _motes[kind]
	var list: Array = []
	for index in range(MOTE_COUNT):
		var a := fposmod(sin(float(index) * 12.9898 + float(kind.hash() % 97)) * 43758.5453, 1.0)
		var b := fposmod(sin(float(index) * 78.233 + 1.7) * 24634.6345, 1.0)
		var c := fposmod(sin(float(index) * 37.719 + 4.1) * 9575.3351, 1.0)
		list.append({"x": a, "y": b, "speed": .4 + c * .9, "phase": c * TAU, "size": 1.0 + b * 1.6})
	_motes[kind] = list
	return list

## Screen position of one mote at `clock`, in normalized view space.
static func mote_position(kind: String, seed: Dictionary, clock: float) -> Vector2:
	var x := float(seed.x)
	var y := float(seed.y)
	var speed := float(seed.speed)
	var phase := float(seed.phase)
	var top := .20
	var span := .64
	match kind:
		"snow":
			return Vector2(fposmod(x + sin(clock * .5 * speed + phase) * .02, 1.0), top + fposmod(y + clock * .035 * speed, 1.0) * span)
		"sand":
			return Vector2(fposmod(x + clock * .085 * speed, 1.0), top + .30 + y * (span - .30) + sin(clock * speed + phase) * .006)
		"ember":
			return Vector2(fposmod(x + sin(clock * .7 * speed + phase) * .025, 1.0), top + span - fposmod(y + clock * .05 * speed, 1.0) * span)
		"bubble":
			return Vector2(fposmod(x + sin(clock * .6 * speed + phase) * .018, 1.0), top + span - fposmod(y + clock * .04 * speed, 1.0) * span)
	return Vector2(fposmod(x + sin(clock * .23 * speed + phase) * .03, 1.0), top + y * span + cos(clock * .31 * speed + phase) * .02)

# ---------------------------------------------------------------- drawing
#
# r22: nothing here records a polygon or polyline command per shape any more.
# The Web renderer builds fresh GPU buffers for each such command every frame,
# and the ornaments alone were up to ~200 of them. Static strokes and fills are
# tessellated once per chapter and view size into a few meshes (drawn with the
# camera transform), gradients are single quads, ellipses and motes are textured
# rectangles. Only the slowly turning parts of an ornament are still stroked
# live, merged into one multiline per style.

const MeshKit := preload("res://battle/view/battle_mesh_kit.gd")
const SoftSprites := preload("res://battle/view/battle_soft_sprites.gd")

static var _no_uvs := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

## chapter|width|height -> pixel-space layers (see _build_layers). A battle only
## ever needs the current chapter, so the cache stays tiny.
static var _layers: Dictionary = {}

static func _scaled_width(base: float, size: Vector2) -> float:
	return maxf(1.2, base * 1.55 * clampf(size.x / 1600.0, .7, 1.5))

static func _quad(c: CanvasItem, points: PackedVector2Array, colors: PackedColorArray) -> void:
	c.draw_primitive(points, colors, _no_uvs)

## Ornament-local unit space -> pixel space at camera zoom 1.
static func _ornament_to_pixels(size: Vector2) -> Transform2D:
	return Transform2D(Vector2(size.x * ORNAMENT_RADIUS.x, 0.0), Vector2(0.0, size.y * ORNAMENT_RADIUS.y), Vector2(size.x * ORNAMENT_CENTER.x, size.y * ORNAMENT_CENTER.y))

## Pixel space at zoom 1 -> screen, for a normalized->screen camera transform.
static func _pixel_camera(xf: Transform2D, size: Vector2) -> Transform2D:
	return xf * Transform2D(Vector2(1.0 / size.x, 0.0), Vector2(0.0, 1.0 / size.y), Vector2.ZERO)

static func _segment_pairs(points: PackedVector2Array) -> PackedVector2Array:
	var pairs := PackedVector2Array()
	for index in range(points.size() - 1):
		pairs.append(points[index])
		pairs.append(points[index + 1])
	return pairs

## Everything that does not move, tessellated for one chapter at one view size:
##   floor      - static ornament strokes and fills (alpha as in the design)
##   hot        - ember shapes that pulse, drawn with the pulse as modulate
##   spin       - [{spin, fill, fill_hot, batches}] for parts that turn slowly;
##                strokes stay live, fills are meshes in ornament-local space
##   props      - corner silhouettes of both sides, one mesh
static func _build_layers(theme: Dictionary, size: Vector2) -> Dictionary:
	var accent: Color = theme.accent
	var ember := Color(1.0, .55, .24)
	var to_pixels := _ornament_to_pixels(size)
	var floor_kit := MeshKit.new()
	var hot_kit := MeshKit.new()
	var groups: Dictionary = {}
	for shape in ornament(str(theme.ornament)):
		var spin := float(shape.spin)
		var hot := bool(shape.hot)
		var tone: Color = ember if hot else accent
		var alpha := float(shape.a) * FLOOR_LINE_ALPHA
		var width := float(shape.w)
		var points: PackedVector2Array = shape.pts
		var filled := bool(shape.fill) and points.size() >= 3
		var fill_color := Color(tone.r, tone.g, tone.b, alpha * .55)
		if is_zero_approx(spin):
			var kit := hot_kit if hot else floor_kit
			var projected: PackedVector2Array = to_pixels * points
			if filled: kit.fill(projected, fill_color)
			if width > 0.0:
				var px := _scaled_width(width, size)
				# A dark underlay keeps the line readable on bright floor paint.
				if width >= 1.5: kit.stroke(projected, px + 2.4, Color(0, 0, 0, minf(.55, alpha * .6)))
				kit.stroke(projected, px, Color(tone.r, tone.g, tone.b, minf(1.0, alpha)))
			continue
		var group: Dictionary = groups.get(spin, {})
		if group.is_empty():
			group = {"spin": spin, "fill": MeshKit.new(), "fill_hot": MeshKit.new(), "batches": {}}
			groups[spin] = group
		if filled: (group.fill_hot if hot else group.fill).fill(points, fill_color)
		if width > 0.0:
			var batches: Dictionary = group.batches
			var key := "%.2f|%.2f|%s" % [width, float(shape.a), str(hot)]
			if not batches.has(key):
				batches[key] = {"pairs": PackedVector2Array(), "px": _scaled_width(width, size), "alpha": alpha, "tone": tone, "hot": hot, "under": width >= 1.5}
			var batch: Dictionary = batches[key]
			var pairs: PackedVector2Array = batch.pairs
			pairs.append_array(_segment_pairs(points))
			batch["pairs"] = pairs
	var spin_groups: Array = []
	for spin in groups:
		var group: Dictionary = groups[spin]
		spin_groups.append({"spin": float(spin), "fill": (group.fill as MeshKit).build(), "fill_hot": (group.fill_hot as MeshKit).build(), "batches": (group.batches as Dictionary).values()})
	# Corner silhouettes: the left corner as authored, the right one mirrored.
	var props_kit := MeshKit.new()
	var dark: Color = (theme.floor as Color).darkened(.72)
	for item in props(str(theme.props)):
		var color := dark.lerp(theme.floor, float(item.shade))
		color.a = .94
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for point in (item.pts as PackedVector2Array):
			left.append(Vector2(point.x * size.x, point.y * size.y))
			right.append(Vector2((1.0 - point.x) * size.x, point.y * size.y))
		props_kit.fill(left, color)
		props_kit.fill(right, color)
	return {"floor": floor_kit.build(), "hot": hot_kit.build(), "spin": spin_groups, "props": props_kit.build()}

static func _layers_for(theme: Dictionary, size: Vector2) -> Dictionary:
	var key := "%d|%d|%d" % [int(theme.chapter), roundi(size.x), roundi(size.y)]
	if not _layers.has(key):
		if _layers.size() >= 3: _layers.clear()
		_layers[key] = _build_layers(theme, size)
	return _layers[key]

## Number of live (per-frame) strokes the ornament still needs: a proxy the
## tests use to keep the Web cost bounded.
static func live_stroke_count(theme: Dictionary, size: Vector2) -> int:
	var total := 0
	for group in (_layers_for(theme, size).spin as Array):
		for batch in (group.batches as Array):
			total += 2 if bool(batch.under) else 1
	return total

## Layer 1 (far): horizon haze and drifting motes. Screen-locked, so it sits
## still behind the camera shake.
static func draw_far(c: CanvasItem, theme: Dictionary, size: Vector2, clock: float, strength := 1.0) -> void:
	if theme.is_empty() or strength <= 0.0: return
	var haze: Color = theme.haze
	var rows := [.44, .585, .665]
	var alphas := [0.0, .17, 0.0]
	for index in range(2):
		var top := float(rows[index]) * size.y
		var bottom := float(rows[index + 1]) * size.y
		var top_color := Color(haze.r, haze.g, haze.b, float(alphas[index]) * strength)
		var bottom_color := Color(haze.r, haze.g, haze.b, float(alphas[index + 1]) * strength)
		_quad(c, PackedVector2Array([Vector2(0, top), Vector2(size.x, top), Vector2(size.x, bottom), Vector2(0, bottom)]), PackedColorArray([top_color, top_color, bottom_color, bottom_color]))
	var kind := str(theme.mote)
	var accent: Color = theme.accent
	var scale := clampf(size.x / 1600.0, .7, 1.4)
	var disc := SoftSprites.disc()
	for seed in motes(kind):
		var point: Vector2 = mote_position(kind, seed, clock) * size
		var twinkle := .5 + .5 * sin(clock * 1.6 * float(seed.speed) + float(seed.phase))
		var radius := float(seed.size) * scale
		match kind:
			"sand":
				c.draw_line(point, point + Vector2(18.0 * scale, 0), Color(accent.r, accent.g, accent.b, .16 * strength), 1.2 * scale, true)
			"bubble":
				# A thin ring that scales with the bubble (reference ring: radius 4, 1 px).
				var reach := radius * 2.4
				var extent := SoftSprites.ring_size(4.0, 4.0, 1.0) * (reach / 4.0)
				c.draw_texture_rect(SoftSprites.ring(4.0, 4.0, 1.0), Rect2(point - extent * .5, extent), false, Color(accent.r, accent.g, accent.b, .28 * strength))
			"ember":
				c.draw_texture_rect(disc, Rect2(point - Vector2(radius, radius) * .9, Vector2(radius, radius) * 1.8), false, Color(1.0, .55, .22, (.28 + .4 * twinkle) * strength))
			"snow":
				c.draw_texture_rect(disc, Rect2(point - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, Color(1, 1, 1, (.30 + .25 * twinkle) * strength))
			_:
				c.draw_texture_rect(disc, Rect2(point - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, Color(accent.r, accent.g, accent.b, (.16 + .34 * twinkle) * strength))

## Layer 2 (floor): the tinted floor plate and the chapter ornament, projected
## through the grid's transform so it lies in the same plane as the cells.
static func draw_floor(c: CanvasItem, theme: Dictionary, xf: Transform2D, size: Vector2, clock: float, strength := 1.0) -> void:
	if theme.is_empty() or strength <= 0.0: return
	var floor_color: Color = theme.floor
	var clear := Color(floor_color.r, floor_color.g, floor_color.b, 0.0)
	var tinted := Color(floor_color.r, floor_color.g, floor_color.b, .24 * strength)
	_quad(c, PackedVector2Array([xf * Vector2(.02, .612), xf * Vector2(.98, .612), xf * Vector2(1.05, .91), xf * Vector2(-.05, .91)]), PackedColorArray([clear, clear, tinted, tinted]))
	var accent: Color = theme.accent
	var centre := xf * ORNAMENT_CENTER
	var radii := Vector2(xf.x.x * ORNAMENT_RADIUS.x, xf.y.y * ORNAMENT_RADIUS.y)
	# Soft pool of light under the emblem.
	SoftSprites.draw_ellipse(c, centre, radii * .98, Color(accent.r, accent.g, accent.b, .15 * strength))
	SoftSprites.draw_ellipse(c, centre, radii * .55, Color(accent.r, accent.g, accent.b, .10 * strength))
	var layers := _layers_for(theme, size)
	var camera := _pixel_camera(xf, size)
	var pulse := .86 + .14 * sin(clock * 1.3)
	if layers.floor != null: c.draw_mesh(layers.floor, null, camera, Color(1, 1, 1, strength))
	if layers.hot != null: c.draw_mesh(layers.hot, null, camera, Color(1, 1, 1, strength * pulse))
	var base := camera * _ornament_to_pixels(size)
	for group in (layers.spin as Array):
		var turned: Transform2D = base * Transform2D(clock * float(group.spin), Vector2.ZERO)
		if group.fill != null: c.draw_mesh(group.fill, null, turned, Color(1, 1, 1, strength))
		if group.fill_hot != null: c.draw_mesh(group.fill_hot, null, turned, Color(1, 1, 1, strength * pulse))
		for batch in (group.batches as Array):
			var hot := bool(batch.hot)
			var tone: Color = batch.tone
			var alpha := float(batch.alpha) * strength * (pulse if hot else 1.0)
			var points: PackedVector2Array = turned * (batch.pairs as PackedVector2Array)
			var px := float(batch.px)
			if bool(batch.under): c.draw_multiline(points, Color(0, 0, 0, minf(.55, alpha * .6)), px + 2.4, true)
			c.draw_multiline(points, Color(tone.r, tone.g, tone.b, minf(1.0, alpha)), px, true)

## Layer 3 (front): dark corner props and an edge vignette.
static func draw_front(c: CanvasItem, theme: Dictionary, xf: Transform2D, size: Vector2, strength := 1.0) -> void:
	if theme.is_empty() or strength <= 0.0: return
	var layers := _layers_for(theme, size)
	if layers.props != null: c.draw_mesh(layers.props, null, _pixel_camera(xf, size), Color(1, 1, 1, strength))
	var edge: Color = theme.vignette
	var strong := Color(edge.r, edge.g, edge.b, .34 * strength)
	var none := Color(edge.r, edge.g, edge.b, 0.0)
	var depth_x := size.x * .13
	var depth_y := size.y * .15
	_quad(c, PackedVector2Array([Vector2(0, 0), Vector2(depth_x, 0), Vector2(depth_x, size.y), Vector2(0, size.y)]), PackedColorArray([strong, none, none, strong]))
	_quad(c, PackedVector2Array([Vector2(size.x - depth_x, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(size.x - depth_x, size.y)]), PackedColorArray([none, strong, strong, none]))
	_quad(c, PackedVector2Array([Vector2(0, size.y - depth_y), Vector2(size.x, size.y - depth_y), Vector2(size.x, size.y), Vector2(0, size.y)]), PackedColorArray([none, none, strong, strong]))
