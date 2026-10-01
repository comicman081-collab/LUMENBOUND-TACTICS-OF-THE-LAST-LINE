extends RefCounted

## Phase 4 / A2 (2026-09-30): procedural map landmarks. Every landmark is one
## low-poly ArrayMesh (boxes, prisms, cones and beams with baked vertex colour
## and fake lighting) plus an optional emissive mesh for lamps and windows. The
## meshes are built once per (kind, biome family, variant) and shared by every
## node that uses them, so a map pays a few dozen triangles per landmark and no
## texture, GLB or download. Smoke puffs and flags are returned as descriptors;
## the map screen animates them lightly.
##
## Kinds:
##   small  - camp (forward camp at the start), barricade (enemy stronghold),
##            tent (elite stronghold), tower (relay signal tower), crate
##            (supply crate for treasure), arch (ruin arch landmark), beacon
##            (broken signal beacon landmark)
##   boss   - one archetype per chapter boss, see BOSS_BY_CHAPTER
## Winding: Godot front faces are clockwise, so triangles are emitted with the
## index order reversed from the counter-clockwise-from-outside input; the
## stored normals always point outward.

const LIGHT_DIRECTION := Vector3(.42, .80, .44)
## The map grades, fogs and rains on everything; baked colours are lifted so a
## landmark keeps its contrast against the ground instead of melting into it.
const BODY_GAIN := 1.38
const SHEET_GAP := .004
const HOSTILE_CLOTH := Color("a0413a")
const LAMP_WARM := Color("ffb45a")

const SMALL_KINDS := ["camp", "barricade", "tent", "tower", "crate", "arch", "beacon"]
const BOSS_KINDS := ["train", "gate", "spire", "lighthouse", "citadel", "coil", "cathedral", "crane", "clock", "flagship", "ring", "dome", "archive"]

## chapter -> [archetype, variant]. All twenty pairs are distinct.
const BOSS_BY_CHAPTER := {
	1: ["train", 0], 2: ["gate", 0], 3: ["spire", 0], 4: ["lighthouse", 0], 5: ["citadel", 0],
	6: ["coil", 0], 7: ["cathedral", 1], 8: ["crane", 0], 9: ["clock", 0], 10: ["spire", 1],
	11: ["flagship", 0], 12: ["cathedral", 0], 13: ["clock", 1], 14: ["ring", 0], 15: ["dome", 0],
	16: ["citadel", 1], 17: ["archive", 0], 18: ["coil", 1], 19: ["train", 1], 20: ["flagship", 1],
}

const PALETTES := {
	"FOREST": {"stone": "7b7d6a", "dark": "3a4a36", "wood": "6f5434", "metal": "58646a", "cloth": "4f9a66", "glass": "9fd6b8"},
	"FROST": {"stone": "9fb4be", "dark": "54707c", "wood": "7a6a58", "metal": "6e8494", "cloth": "8cc8e8", "glass": "cfeaf6"},
	"DUNE": {"stone": "b79f73", "dark": "6a5840", "wood": "7d5a36", "metal": "6c6258", "cloth": "d08a3c", "glass": "e6d2a4"},
	"ASH": {"stone": "70645f", "dark": "33302f", "wood": "5a4636", "metal": "4c4a4d", "cloth": "c4583a", "glass": "9a8f88"},
	"TIDAL": {"stone": "7a9a98", "dark": "34585a", "wood": "6b5a45", "metal": "587a84", "cloth": "3fa6a0", "glass": "a8e0da"},
	"GLASS": {"stone": "8aa4ad", "dark": "3a5560", "wood": "6f6350", "metal": "5f7a88", "cloth": "58c2d6", "glass": "b4e6f0"},
	"LUNAR": {"stone": "8f8aa8", "dark": "45446a", "wood": "6a5a66", "metal": "6c6f8c", "cloth": "9b8cf0", "glass": "d3c9fa"},
	"RUINS": {"stone": "a39a80", "dark": "54503f", "wood": "7a5d3c", "metal": "5e6268", "cloth": "c0a24e", "glass": "d8cfae"},
}

static var _cache: Dictionary = {}

# ---------------------------------------------------------------- mesher

class Layer extends RefCounted:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

class Mesher extends RefCounted:
	var layers: Dictionary = {}
	var layer := "body"
	var xf := Transform3D.IDENTITY
	var stack: Array = []
	var flags: Array = []
	var smoke: Array = []

	func _init() -> void:
		for name in ["body", "glow"]:
			layers[name] = Layer.new()

	func use(name: String) -> void:
		layer = name

	func push(transform: Transform3D) -> void:
		stack.append(xf)
		xf = xf * transform

	func pop() -> void:
		xf = stack.pop_back()

	## Counter-clockwise triangle seen from outside; `hint` is a direction the
	## face should point away from the part, used to fix the order if needed.
	func tri(a: Vector3, b: Vector3, c: Vector3, color: Color, hint := Vector3.ZERO) -> void:
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < 1e-10: return
		if hint != Vector3.ZERO and normal.dot(hint) < 0.0:
			var swap := b
			b = c
			c = swap
			normal = -normal
		normal = normal.normalized()
		var data: Layer = layers[layer]
		var world_normal := (xf.basis.inverse().transposed() * normal).normalized()
		var shade := 1.0
		if layer == "body":
			shade = (.56 + .44 * maxf(0.0, world_normal.dot(LIGHT_DIRECTION.normalized()))) * BODY_GAIN
		var shaded := Color(color.r * shade, color.g * shade, color.b * shade, 1.0)
		var base := data.v.size()
		data.v.append_array(PackedVector3Array([xf * a, xf * b, xf * c]))
		data.n.append_array(PackedVector3Array([world_normal, world_normal, world_normal]))
		data.c.append_array(PackedColorArray([shaded, shaded, shaded]))
		# Godot front faces are clockwise.
		data.i.append_array(PackedInt32Array([base, base + 2, base + 1]))

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, hint := Vector3.ZERO) -> void:
		var h := hint
		if h == Vector3.ZERO: h = (b - a).cross(c - a)
		tri(a, b, c, color, h)
		tri(a, c, d, color, h)

	## Two-sided sheet. The faces sit a hair apart so a material with culling
	## disabled (the web's warmed one) never z-fights a coplanar pair.
	func quad2(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
		var normal := (b - a).cross(c - a).normalized()
		var lift := normal * SHEET_GAP
		quad(a + lift, b + lift, c + lift, d + lift, color, normal)
		quad(a - lift, b - lift, c - lift, d - lift, color, -normal)

	func box(center: Vector3, size: Vector3, color: Color, yaw := 0.0) -> void:
		var rot := Basis(Vector3.UP, yaw)
		var h := size * .5
		var p := func(sx: float, sy: float, sz: float) -> Vector3: return center + rot * Vector3(sx * h.x, sy * h.y, sz * h.z)
		quad(p.call(-1, 1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(-1, 1, 1), color, rot * Vector3.UP)
		quad(p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1), color, rot * Vector3.DOWN)
		quad(p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(1, -1, 1), color, rot * Vector3.RIGHT)
		quad(p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(-1, 1, 1), p.call(-1, -1, 1), color, rot * Vector3.LEFT)
		quad(p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), color, rot * Vector3.BACK)
		quad(p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(-1, 1, -1), color, rot * Vector3.FORWARD)

	## Gable roof: footprint w (x) by d (z), ridge along x at the top.
	func wedge(center: Vector3, size: Vector3, color: Color, yaw := 0.0) -> void:
		var rot := Basis(Vector3.UP, yaw)
		var h := size * .5
		var p := func(sx: float, sy: float, sz: float) -> Vector3: return center + rot * Vector3(sx * h.x, sy * h.y, sz * h.z)
		var b0: Vector3 = p.call(-1, -1, -1)
		var b1: Vector3 = p.call(1, -1, -1)
		var b2: Vector3 = p.call(1, -1, 1)
		var b3: Vector3 = p.call(-1, -1, 1)
		var r0: Vector3 = p.call(-1, 1, 0)
		var r1: Vector3 = p.call(1, 1, 0)
		quad(b0, b1, r1, r0, color, rot * Vector3(0, .6, -1))
		quad(b3, b2, r1, r0, color, rot * Vector3(0, .6, 1))
		tri(b0, b3, r0, color, rot * Vector3.LEFT)
		tri(b1, b2, r1, color, rot * Vector3.RIGHT)

	func pyramid(base_center: Vector3, w: float, d: float, height: float, color: Color, yaw := 0.0) -> void:
		var rot := Basis(Vector3.UP, yaw)
		var apex := base_center + Vector3(0, height, 0)
		var corners: Array = []
		for sign in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			corners.append(base_center + rot * Vector3(float(sign[0]) * w * .5, 0.0, float(sign[1]) * d * .5))
		for index in range(4):
			var a: Vector3 = corners[index]
			var b: Vector3 = corners[(index + 1) % 4]
			tri(a, b, apex, color, ((a + b) * .5 - base_center).normalized() + Vector3.UP * .4)

	## Frustum between two points; `segments` sides, `phase` rotates the corners.
	func cyl_axis(a: Vector3, b: Vector3, r0: float, r1: float, segments: int, color: Color, phase := 0.0, caps := true) -> void:
		var axis := (b - a)
		if axis.length_squared() < 1e-8: return
		var direction := axis.normalized()
		var reference := Vector3.UP if absf(direction.y) < .95 else Vector3.RIGHT
		var u := direction.cross(reference).normalized()
		var v := direction.cross(u).normalized()
		for index in range(segments):
			var a0 := phase + TAU * float(index) / float(segments)
			var a1 := phase + TAU * float(index + 1) / float(segments)
			var d0 := u * cos(a0) + v * sin(a0)
			var d1 := u * cos(a1) + v * sin(a1)
			var hint := (d0 + d1).normalized()
			var p00 := a + d0 * r0
			var p10 := a + d1 * r0
			var p01 := b + d0 * r1
			var p11 := b + d1 * r1
			if r1 <= 0.0001:
				tri(p00, p10, b, color, hint)
			elif r0 <= 0.0001:
				tri(p01, p11, a, color, hint)
			else:
				quad(p00, p10, p11, p01, color, hint)
			if caps and r1 > 0.0001:
				tri(b, p01, p11, color, direction)
			if caps and r0 > 0.0001:
				tri(a, p10, p00, color, -direction)

	func cyl(base_center: Vector3, r0: float, r1: float, height: float, segments: int, color: Color, phase := 0.0) -> void:
		cyl_axis(base_center, base_center + Vector3(0, height, 0), r0, r1, segments, color, phase)

	func hcyl(center: Vector3, radius: float, length: float, segments: int, color: Color, yaw := 0.0) -> void:
		var half := Basis(Vector3.UP, yaw) * Vector3(length * .5, 0, 0)
		cyl_axis(center - half, center + half, radius, radius, segments, color)

	## Square-section beam of half thickness `t`.
	func beam(a: Vector3, b: Vector3, t: float, color: Color) -> void:
		cyl_axis(a, b, t * 1.4142, t * 1.4142, 4, color, PI * .25)

	## Horizontal triangular prism whose tip points along local +x.
	func bow(center: Vector3, length: float, width: float, height: float, color: Color) -> void:
		var back_l := center + Vector3(0, 0, -width * .5)
		var back_r := center + Vector3(0, 0, width * .5)
		var tip := center + Vector3(length, 0, 0)
		var up := Vector3(0, height * .5, 0)
		tri(back_l + up, back_r + up, tip + up, color, Vector3.UP)
		tri(back_l - up, back_r - up, tip - up, color, Vector3.DOWN)
		quad(back_l - up, tip - up, tip + up, back_l + up, color, Vector3(.5, 0, -1))
		quad(back_r - up, tip - up, tip + up, back_r + up, color, Vector3(.5, 0, 1))

	func add_flag(pole_top: Vector3, length: float, height: float, color: Color) -> void:
		flags.append({"pos": xf * pole_top, "size": Vector2(length, height), "color": color})

	func add_smoke(position: Vector3) -> void:
		smoke.append(xf * position)

	func build_mesh(name: String) -> ArrayMesh:
		var data: Layer = layers[name]
		if data.v.is_empty(): return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.v
		arrays[Mesh.ARRAY_NORMAL] = data.n
		arrays[Mesh.ARRAY_COLOR] = data.c
		arrays[Mesh.ARRAY_INDEX] = data.i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh

# ---------------------------------------------------------------- lookup

static func palette(family: String) -> Dictionary:
	var source: Dictionary = PALETTES.get(family, PALETTES.RUINS)
	var colors := {}
	for key in source: colors[key] = Color(str(source[key]))
	colors["hostile"] = HOSTILE_CLOTH
	colors["lamp"] = LAMP_WARM
	colors["cool"] = (colors.cloth as Color).lerp(Color.WHITE, .45)
	return colors

## {kind, variant} for a chapter's boss landmark, or {} for unknown chapters.
static func boss_spec(chapter: int) -> Dictionary:
	if not BOSS_BY_CHAPTER.has(chapter): return {}
	var entry: Array = BOSS_BY_CHAPTER[chapter]
	return {"kind": str(entry[0]), "variant": int(entry[1])}

static func all_kinds() -> Array:
	var kinds: Array = []
	for kind in SMALL_KINDS: kinds.append({"kind": kind, "variant": 0})
	for chapter in BOSS_BY_CHAPTER: kinds.append(boss_spec(int(chapter)))
	return kinds

## Cached build: {body: ArrayMesh, glow: ArrayMesh|null, flags: Array, smoke: Array,
## bounds: AABB, triangles: int, glow_color: Color, height: float}.
static func build(kind: String, family: String, variant := 0) -> Dictionary:
	var key := "%s|%s|%d" % [kind, family, variant]
	if _cache.has(key): return _cache[key]
	var m := Mesher.new()
	var p := palette(family)
	match kind:
		"camp": _camp(m, p)
		"barricade": _barricade(m, p)
		"tent": _tent(m, p)
		"tower": _tower(m, p)
		"crate": _crate(m, p)
		"arch": _arch(m, p)
		"beacon": _beacon(m, p)
		"train": _train(m, p, variant)
		"gate": _gate(m, p, variant)
		"spire": _spire(m, p, variant)
		"lighthouse": _lighthouse(m, p)
		"citadel": _citadel(m, p, variant)
		"coil": _coil(m, p, variant)
		"cathedral": _cathedral(m, p, variant)
		"crane": _crane(m, p)
		"clock": _clock(m, p, variant)
		"flagship": _flagship(m, p, variant)
		"ring": _ring(m, p)
		"dome": _dome(m, p)
		"archive": _archive(m, p)
		_: return {}
	var body := m.build_mesh("body")
	var glow := m.build_mesh("glow")
	var bounds := AABB()
	if body != null: bounds = body.get_aabb()
	if glow != null: bounds = bounds.merge(glow.get_aabb())
	var triangles: int = (m.layers.body as Layer).i.size() / 3 + (m.layers.glow as Layer).i.size() / 3
	var result := {"body": body, "glow": glow, "flags": m.flags, "smoke": m.smoke, "bounds": bounds, "triangles": triangles,
		"glow_color": glow_color_for(kind, family), "height": bounds.end.y}
	_cache[key] = result
	return result

## Lamp / window colour of a kind in a family. Needs no mesh, so a caller can pick
## its glow material before the (comparatively slow) mesh build has run.
static func glow_color_for(kind: String, family: String) -> Color:
	var p := palette(family)
	return (p.cool as Color) if kind in ["spire", "coil", "ring", "dome", "tower"] else (p.lamp as Color)

static func has_kind(kind: String) -> bool:
	return kind in SMALL_KINDS or kind in BOSS_KINDS

static func clear_cache() -> void:
	_cache.clear()
	_aux_cache.clear()

# ------------------------------------------------------------- instancing

const FLAG_WAVE_SPEED := 2.3
const FLAG_WAVE_SWING := .30
const PUFFS_PER_SMOKE := 3
const PUFF_PERIOD := 3.2
const PUFF_RISE := .95

static var _aux_cache: Dictionary = {}

static func _flag_mesh(size: Vector2, color: Color) -> ArrayMesh:
	var key := "flag|%.2f|%.2f|%s" % [size.x, size.y, color.to_html(false)]
	if _aux_cache.has(key): return _aux_cache[key]
	var m := Mesher.new()
	var dark := color.darkened(.12)
	# Hinged at the pole (x = 0); two tapered faces so it reads from both sides.
	var a := Vector3(0, size.y * .5, 0)
	var b := Vector3(size.x, size.y * .36, 0)
	var c := Vector3(size.x, -size.y * .36, 0)
	var d := Vector3(0, -size.y * .5, 0)
	var gap := Vector3(0, 0, SHEET_GAP)
	m.quad(a + gap, b + gap, c + gap, d + gap, color, Vector3.BACK)
	m.quad(a - gap, b - gap, c - gap, d - gap, dark, Vector3.FORWARD)
	var mesh := m.build_mesh("body")
	_aux_cache[key] = mesh
	return mesh

static func _puff_mesh() -> ArrayMesh:
	if _aux_cache.has("puff"): return _aux_cache["puff"]
	var m := Mesher.new()
	var smoke_color := Color("8d8a86")
	var top := Vector3(0, .5, 0)
	var bottom := Vector3(0, -.5, 0)
	var ring: Array = []
	for index in range(5):
		var angle := TAU * float(index) / 5.0
		ring.append(Vector3(cos(angle) * .5, .08, sin(angle) * .5))
	for index in range(5):
		var a: Vector3 = ring[index]
		var b: Vector3 = ring[(index + 1) % 5]
		m.tri(a, b, top, smoke_color, (a + b) * .5 + Vector3.UP * .3)
		m.tri(a, b, bottom, smoke_color, (a + b) * .5 + Vector3.DOWN * .3)
	var mesh := m.build_mesh("body")
	_aux_cache["puff"] = mesh
	return mesh

## An empty root that only knows what it will become. `populate` adds the meshes.
## Keeping the two apart lets the web map place every landmark during the stage
## entry and fill in the GDScript-built meshes afterwards, a few per frame.
static func create_root(kind: String, family: String, variant: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Landmark_%s" % kind
	root.set_meta("landmark_kind", kind)
	root.set_meta("landmark_family", family)
	root.set_meta("landmark_variant", variant)
	return root

## A ready-to-add Node3D: "Body" (body_material), "Glow" (glow_material),
## flags and smoke puffs, all sharing cached meshes. Returns null for an
## unknown kind. Animated parts are listed in the root's "animated" meta.
static func instantiate(kind: String, family: String, variant: int, body_material: Material, glow_material: Material) -> Node3D:
	var root := create_root(kind, family, variant)
	if not populate(root, body_material, glow_material):
		root.free()
		return null
	return root

## Fills a root from `create_root` with Body / Glow / flag / smoke nodes. False for
## an unknown kind or a root that is already filled.
static func populate(root: Node3D, body_material: Material, glow_material: Material) -> bool:
	if root == null or root.has_meta("animated"): return false
	var kind := str(root.get_meta("landmark_kind", ""))
	var family := str(root.get_meta("landmark_family", ""))
	var variant := int(root.get_meta("landmark_variant", 0))
	var built := build(kind, family, variant)
	if built.is_empty(): return false
	root.set_meta("landmark_height", float(built.height))
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = built.body
	body.material_override = body_material
	root.add_child(body)
	if built.glow != null:
		var glow := MeshInstance3D.new()
		glow.name = "Glow"
		glow.mesh = built.glow
		glow.material_override = glow_material
		root.add_child(glow)
	var animated: Array = []
	var palette_colors := palette(family)
	var flag_index := 0
	for flag in built.flags:
		var node := MeshInstance3D.new()
		node.name = "Flag%d" % flag_index
		node.mesh = _flag_mesh(flag.size, flag.color)
		node.material_override = body_material
		node.position = flag.pos
		root.add_child(node)
		animated.append({"node": node, "type": "flag", "phase": float(flag_index) * 1.7 + float(hash(kind) % 7)})
		flag_index += 1
	var smoke_index := 0
	for source in built.smoke:
		for puff_index in range(PUFFS_PER_SMOKE):
			var puff := MeshInstance3D.new()
			puff.name = "Smoke%d_%d" % [smoke_index, puff_index]
			puff.mesh = _puff_mesh()
			puff.material_override = body_material
			puff.position = source
			# animate() sizes the puffs; a landmark nobody animates (far from the camera, or not yet
			# visited this frame) must not show full-size grey diamonds sitting on its fire
			puff.scale = Vector3.ONE * .05
			root.add_child(puff)
			animated.append({"node": puff, "type": "smoke", "origin": source, "phase": float(puff_index) / float(PUFFS_PER_SMOKE) + float(smoke_index) * .37})
		smoke_index += 1
	root.set_meta("animated", animated)
	return true

## Lightly animates a root from `instantiate`: flags wave, smoke puffs rise and
## shrink (opaque, no blending needed on web).
static func animate(root: Node3D, clock: float) -> void:
	if root == null or not root.has_meta("animated"): return
	for entry in root.get_meta("animated"):
		var node: Node3D = entry.node
		if not is_instance_valid(node): continue
		if entry.type == "flag":
			var swing := sin(clock * FLAG_WAVE_SPEED + float(entry.phase))
			node.rotation = Vector3(0.0, swing * FLAG_WAVE_SWING, sin(clock * 1.6 + float(entry.phase) * 1.3) * .05)
		else:
			var t := fposmod(clock / PUFF_PERIOD + float(entry.phase), 1.0)
			var origin: Vector3 = entry.origin
			var grow := sin(t * PI)
			node.position = origin + Vector3(sin(t * 5.0 + float(entry.phase) * 6.0) * .10 * t, t * PUFF_RISE, cos(t * 4.0 + float(entry.phase) * 5.0) * .08 * t)
			node.scale = Vector3.ONE * (.05 + .34 * grow)
			node.rotation.y = t * 2.0

## Glow material flicker: a slow pulse plus a fast shimmer, in [0.8, 1.7].
static func flicker(clock: float, phase := 0.0) -> float:
	return 1.25 + .28 * sin(clock * 1.7 + phase) + .12 * sin(clock * 6.3 + phase * 2.0)

static func glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .8
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.4
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material

## Body material for previews and tests; the map reuses its terrain material.
static func body_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = .92
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material

# ---------------------------------------------------------------- helpers

static func _lerp_color(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, t)

static func _glow_box(m: Mesher, center: Vector3, size: Vector3, yaw := 0.0) -> void:
	m.use("glow")
	m.box(center, size, Color.WHITE, yaw)
	m.use("body")

static func _glow_cyl(m: Mesher, a: Vector3, b: Vector3, r0: float, r1: float, segments := 8) -> void:
	m.use("glow")
	m.cyl_axis(a, b, r0, r1, segments, Color.WHITE)
	m.use("body")

static func _ring_beams(m: Mesher, center: Vector3, radius: float, count: int, thickness: float, color: Color, tilt := Vector3.ZERO) -> void:
	var basis := Basis.from_euler(tilt)
	var points: Array = []
	for index in range(count + 1):
		var angle := TAU * float(index) / float(count)
		points.append(center + basis * Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	for index in range(count):
		m.beam(points[index], points[index + 1], thickness, color)

# ------------------------------------------------------------------ small

static func _barricade(m: Mesher, p: Dictionary) -> void:
	var sand: Color = (p.stone as Color).lerp(p.wood, .22)
	for row in range(2):
		var count := 3 - row
		for index in range(count):
			var x := (float(index) - float(count - 1) * .5) * .56
			m.box(Vector3(x, .10 + float(row) * .21, 0), Vector3(.52, .20, .34), sand.darkened(.04 * float(index % 2)), .08 * float(index - 1))
	for end_x in [-.92, .92]:
		var wood: Color = p.wood
		m.beam(Vector3(end_x - .14, 0, .12), Vector3(end_x + .14, .86, -.12), .04, wood)
		m.beam(Vector3(end_x + .14, 0, .12), Vector3(end_x - .14, .86, -.12), .04, wood)
		m.pyramid(Vector3(end_x + .14, .86, -.12), .10, .10, .14, (p.dark as Color))
		m.pyramid(Vector3(end_x - .14, .86, -.12), .10, .10, .14, (p.dark as Color))
	m.beam(Vector3(0, .0, -.22), Vector3(0, 1.45, -.22), .03, p.wood)
	m.add_flag(Vector3(0, 1.45, -.22), .58, .34, p.hostile)

static func _tent(m: Mesher, p: Dictionary) -> void:
	var canvas: Color = (p.dark as Color).lerp(p.hostile, .55)
	m.wedge(Vector3(-.12, .44, -.05), Vector3(1.55, .88, 1.15), canvas)
	m.box(Vector3(.0, .26, .56), Vector3(.40, .52, .05), (p.dark as Color).darkened(.35))
	m.box(Vector3(.78, .15, .52), Vector3(.34, .30, .34), p.wood, .2)
	m.box(Vector3(.80, .40, .50), Vector3(.26, .22, .26), (p.wood as Color).lightened(.12), -.15)
	for index in range(2):
		m.box(Vector3(-.75 + float(index) * .5, .10, .86), Vector3(.46, .20, .3), (p.stone as Color).lerp(p.wood, .22), .1)
	_glow_box(m, Vector3(.40, .56, .60), Vector3(.10, .15, .10))
	m.beam(Vector3(-.88, 0, -.45), Vector3(-.88, 1.6, -.45), .03, p.wood)
	m.add_flag(Vector3(-.88, 1.6, -.45), .62, .38, p.hostile)

static func _camp(m: Mesher, p: Dictionary) -> void:
	m.wedge(Vector3(-.40, .42, -.18), Vector3(1.45, .84, 1.1), p.cloth)
	m.box(Vector3(-.40, .25, .39), Vector3(.40, .50, .05), (p.dark as Color).darkened(.3))
	for index in range(3):
		var angle := float(index) * 1.05
		m.beam(Vector3(.75, .05, .55) + Vector3(cos(angle), 0, sin(angle)) * .22, Vector3(.75, .10, .55) - Vector3(cos(angle), 0, sin(angle)) * .22, .035, p.wood)
	_glow_cyl(m, Vector3(.75, .06, .55), Vector3(.75, .44, .55), .15, 0.0, 6)
	m.add_smoke(Vector3(.75, .5, .55))
	m.box(Vector3(.10, .14, .92), Vector3(.36, .28, .34), p.wood, .25)
	m.box(Vector3(.12, .38, .92), Vector3(.28, .22, .26), (p.wood as Color).lightened(.12), -.1)
	for index in range(3):
		m.box(Vector3(-.4 + float(index) * .56, .10, -.78), Vector3(.52, .20, .32), (p.stone as Color).lerp(p.wood, .22), .05 * float(index))
	m.beam(Vector3(-1.05, 0, .62), Vector3(-1.05, 1.75, .62), .03, p.wood)
	m.add_flag(Vector3(-1.05, 1.75, .62), .66, .40, p.cloth)

static func _tower(m: Mesher, p: Dictionary) -> void:
	m.box(Vector3(0, .07, 0), Vector3(.72, .14, .72), p.stone)
	var top_y := 1.56
	var metal: Color = p.metal
	for corner in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
		var sx := float(corner[0])
		var sz := float(corner[1])
		m.beam(Vector3(sx * .27, .14, sz * .27), Vector3(sx * .08, top_y, sz * .08), .035, metal)
	for level in [.55, 1.0]:
		var half := lerpf(.27, .08, (level - .14) / (top_y - .14))
		m.beam(Vector3(-half, level, -half), Vector3(half, level, -half), .02, metal)
		m.beam(Vector3(half, level, -half), Vector3(half, level, half), .02, metal)
		m.beam(Vector3(half, level, half), Vector3(-half, level, half), .02, metal)
		m.beam(Vector3(-half, level, half), Vector3(-half, level, -half), .02, metal)
	m.beam(Vector3(-.2, .3, .2), Vector3(.13, 1.0, .13), .015, metal)
	m.beam(Vector3(.2, .3, .2), Vector3(-.13, 1.0, .13), .015, metal)
	m.box(Vector3(0, top_y + .04, 0), Vector3(.30, .08, .30), metal)
	m.cyl(Vector3(0, top_y + .08, 0), .20, .04, .13, 8, (p.stone as Color).lightened(.1))
	m.beam(Vector3(0, top_y + .08, 0), Vector3(0, 2.05, 0), .02, metal)
	_glow_box(m, Vector3(0, 2.10, 0), Vector3(.09, .09, .09))

static func _crate(m: Mesher, p: Dictionary) -> void:
	var wood: Color = p.wood
	m.box(Vector3(-.12, .17, 0), Vector3(.56, .34, .44), wood, .12)
	m.box(Vector3(.32, .13, .20), Vector3(.42, .26, .36), wood.lightened(.10), -.2)
	m.box(Vector3(-.06, .47, -.02), Vector3(.40, .26, .34), wood.darkened(.06), .3)
	var strap: Color = (p.dark as Color).darkened(.2)
	m.box(Vector3(-.12, .17, 0), Vector3(.58, .36, .07), strap, .12)
	m.box(Vector3(.32, .13, .20), Vector3(.44, .28, .06), strap, -.2)
	m.box(Vector3(-.06, .47, -.02), Vector3(.42, .28, .06), strap, .3)
	_glow_box(m, Vector3(-.06, .62, -.02), Vector3(.20, .03, .20), .3)

static func _arch(m: Mesher, p: Dictionary) -> void:
	var stone: Color = p.stone
	m.box(Vector3(0, .07, 0), Vector3(1.9, .14, .8), (p.dark as Color).lightened(.05))
	for side in [-1.0, 1.0]:
		m.box(Vector3(side * .68, .78, 0), Vector3(.42, 1.28, .52), stone.darkened(.04 if side < 0 else 0.0))
		m.box(Vector3(side * .68, 1.46, 0), Vector3(.50, .14, .60), stone.lightened(.08))
	# Lintel: complete on one side, snapped off on the other.
	m.box(Vector3(-.36, 1.64, 0), Vector3(1.02, .30, .56), stone.lightened(.04))
	m.push(Transform3D(Basis.from_euler(Vector3(0, .35, .28)), Vector3(.55, 1.86, 0)))
	m.box(Vector3.ZERO, Vector3(.42, .24, .50), stone.lightened(.06))
	m.pop()
	m.box(Vector3(.22, .12, .58), Vector3(.40, .22, .34), stone.darkened(.1), .4)
	m.box(Vector3(-.92, .10, -.52), Vector3(.30, .18, .28), stone.darkened(.14), -.5)
	m.box(Vector3(.96, .09, -.3), Vector3(.24, .16, .24), stone.darkened(.08), .9)
	_glow_box(m, Vector3(-.34, 1.66, .29), Vector3(.46, .07, .03))
	m.beam(Vector3(-.68, 1.52, .3), Vector3(-.68, .6, .3), .02, p.cloth)
	m.add_flag(Vector3(-.68, 1.56, .3), .22, .5, p.cloth)

static func _beacon(m: Mesher, p: Dictionary) -> void:
	var metal: Color = p.metal
	m.cyl(Vector3(0, 0, 0), .52, .40, .22, 8, p.stone)
	m.cyl(Vector3(0, .22, 0), .18, .12, 1.30, 6, metal)
	m.cyl(Vector3(0, 1.50, 0), .20, .10, .18, 6, (p.dark as Color).lightened(.1))
	_glow_cyl(m, Vector3(0, 1.66, 0), Vector3(0, 1.92, 0), .14, .10, 6)
	m.cyl(Vector3(0, 1.92, 0), .18, 0.0, .18, 6, p.dark)
	# Broken ring: three arcs around the mast with a gap.
	var basis := Basis.from_euler(Vector3(.22, 0.0, -.12))
	var points: Array = []
	for index in range(9):
		var angle := .5 + TAU * float(index) / 12.0
		points.append(Vector3(0, 1.1, 0) + basis * Vector3(cos(angle) * .44, 0.0, sin(angle) * .44))
	for index in range(8):
		m.beam(points[index], points[index + 1], .035, (metal as Color).lightened(.1))
	m.beam(Vector3(.40, .22, .10), Vector3(.30, .05, .12), .012, p.dark)
	m.beam(Vector3(-.20, .42, -.12), Vector3(-.50, .05, -.30), .012, p.dark)

# ------------------------------------------------------------------- boss

static func _train(m: Mesher, p: Dictionary, variant: int) -> void:
	var metal: Color = p.metal
	var dark: Color = p.dark
	# Broken track: two rails, ties, a bent rail end.
	for z in [-.62, .62]:
		m.beam(Vector3(-2.5, .03, z), Vector3(1.9, .03, z), .035, metal)
	for index in range(9):
		m.box(Vector3(-2.3 + float(index) * .5, .012, 0), Vector3(.12, .04, 1.5), p.wood)
	m.beam(Vector3(1.9, .03, -.62), Vector3(2.45, .42, -.74), .035, metal)
	m.push(Transform3D(Basis.from_euler(Vector3(.36, .22, 0.0)), Vector3(-.15, .34, 0)))
	if variant == 0:
		m.box(Vector3(0, .42, 0), Vector3(2.7, .22, .9), dark)
		m.hcyl(Vector3(.3, .96, 0), .48, 1.7, 10, (metal as Color).lerp(p.cloth, .25))
		m.hcyl(Vector3(1.18, .96, 0), .50, .14, 10, dark)
		m.cyl(Vector3(.95, 1.36, 0), .13, .19, .5, 8, dark)
		m.add_smoke(Vector3(.95, 1.95, 0))
		m.cyl(Vector3(.15, 1.40, 0), .2, .1, .2, 8, (p.stone as Color).lerp(p.lamp, .4))
		m.box(Vector3(-.88, 1.12, 0), Vector3(.92, 1.2, 1.0), p.wood)
		m.box(Vector3(-.88, 1.76, 0), Vector3(1.06, .08, 1.16), dark)
		_glow_box(m, Vector3(-.88, 1.26, .51), Vector3(.40, .30, .04))
		_glow_box(m, Vector3(1.26, .96, 0), Vector3(.06, .22, .22))
		for x in [-.95, -.15, .7]:
			for z in [-.5, .5]:
				m.cyl_axis(Vector3(x, .42, z - .05), Vector3(x, .42, z + .05), .36, .36, 10, dark)
	else:
		m.box(Vector3(0, .42, 0), Vector3(2.8, .2, .9), dark)
		m.box(Vector3(0, 1.0, 0), Vector3(2.6, 1.1, .96), p.cloth)
		m.wedge(Vector3(0, 1.72, 0), Vector3(2.7, .42, 1.06), dark)
		for index in range(5):
			_glow_box(m, Vector3(-1.0 + float(index) * .5, 1.15, .49), Vector3(.30, .32, .04))
		for x in [-1.0, -.3, .4, 1.0]:
			for z in [-.5, .5]:
				m.cyl_axis(Vector3(x, .4, z - .05), Vector3(x, .4, z + .05), .3, .3, 10, dark)
	m.pop()
	# Loose tender / carriage thrown clear.
	m.push(Transform3D(Basis.from_euler(Vector3(.14, .55, .10)), Vector3(-1.75, .55, .95)))
	m.box(Vector3.ZERO, Vector3(1.3, .8, .9), p.wood if variant == 0 else p.cloth)
	if variant == 0:
		for index in range(4):
			m.box(Vector3(-.4 + float(index) * .27, .45, float(index % 2) * .1 - .05), Vector3(.24, .18, .24), dark.darkened(.3), float(index))
	else:
		m.box(Vector3(.0, .38, 0), Vector3(.9, .06, .7), dark)
	m.pop()
	if variant == 1:
		# A giant ticket stub stuck upright beside the track.
		m.push(Transform3D(Basis.from_euler(Vector3(0, .4, -.1)), Vector3(1.75, .95, .3)))
		m.box(Vector3.ZERO, Vector3(.12, 1.9, 1.05), (p.stone as Color).lightened(.2))
		for index in range(6):
			m.box(Vector3(0, .8 - float(index) * .32, .53), Vector3(.13, .14, .14), dark)
		m.pop()
		_glow_box(m, Vector3(1.75, 1.3, .8), Vector3(.05, .34, .30), .4)

static func _gate(m: Mesher, p: Dictionary, variant: int) -> void:
	var stone: Color = p.stone
	for side in [-1.0, 1.0]:
		m.box(Vector3(side * 1.25, .15, 0), Vector3(1.10, .30, 1.15), stone.darkened(.12))
		m.box(Vector3(side * 1.25, 1.65, 0), Vector3(.85, 3.0, .9), stone)
		m.pyramid(Vector3(side * 1.25, 3.15, 0), .95, .95, .55, stone.lightened(.1))
		_glow_box(m, Vector3(side * 1.25, 2.45, .47), Vector3(.14, .30, .06))
	m.box(Vector3(0, 3.22, 0), Vector3(3.6, .55, 1.0), stone.lightened(.05))
	m.box(Vector3(0, 3.72, 0), Vector3(.75, .5, .85), stone.lightened(.16))
	_glow_box(m, Vector3(0, 3.72, .44), Vector3(.34, .15, .05))
	for side in [-1.0, 1.0]:
		m.box(Vector3(side * .45, 1.3, 0), Vector3(.86, 2.6, .14), (p.metal as Color).darkened(.2), side * .32)
	if variant == 1:
		for index in range(5):
			var x := -1.4 + float(index) * .7
			m.pyramid(Vector3(x, 3.5, 0), .4, .4, .8 if index % 2 == 0 else .55, p.cloth)
		m.beam(Vector3(2.15, 0, .95), Vector3(1.6, 3.55, .55), .07, p.metal)
		m.pyramid(Vector3(1.6, 3.55, .55), .22, .22, .4, p.cloth.lightened(.2))

static func _spire(m: Mesher, p: Dictionary, variant: int) -> void:
	var glass: Color = p.glass
	var stone: Color = p.stone
	if variant == 0:
		m.cyl(Vector3(0, 0, 0), .72, .46, 2.6, 6, glass.lerp(stone, .3))
		m.cyl(Vector3(0, 2.6, 0), .46, 0.0, 1.3, 6, glass)
		for crystal in [[-1.15, -.55, 1.5], [1.1, -.6, 1.9], [-.95, .75, 1.2], [1.2, .65, 1.6], [.1, 1.05, 1.1]]:
			m.cyl(Vector3(float(crystal[0]), 0, float(crystal[1])), .3, .22, float(crystal[2]), 6, glass.lerp(stone, .45))
			m.cyl(Vector3(float(crystal[0]), float(crystal[2]), float(crystal[1])), .22, 0.0, .6, 6, glass)
		for index in range(4):
			var angle := float(index) * 1.5 + .3
			_glow_cyl(m, Vector3(cos(angle) * .58, .2, sin(angle) * .58), Vector3(cos(angle) * .42, 2.4, sin(angle) * .42), .035, .03, 4)
		_glow_cyl(m, Vector3(0, 3.0, 0), Vector3(0, 3.9, 0), .07, 0.0, 6)
	else:
		m.cyl(Vector3(0, 0, 0), 1.3, 1.05, .35, 8, stone.darkened(.1))
		for side in [-1.0, 1.0]:
			m.push(Transform3D(Basis.from_euler(Vector3(0, 0, -side * .10)), Vector3(side * .95, .3, 0)))
			m.box(Vector3(0, 1.45, 0), Vector3(.7, 2.9, .8), stone)
			m.pyramid(Vector3(0, 2.9, 0), .78, .88, .55, stone.lightened(.12))
			m.pop()
		_ring_beams(m, Vector3(0, 2.35, 0), 1.1, 14, .05, p.metal, Vector3(PI * .5, 0, 0))
		m.use("glow")
		m.cyl_axis(Vector3(0, 2.35, -.04), Vector3(0, 2.35, .04), .55, .55, 12, Color.WHITE)
		m.use("body")

static func _lighthouse(m: Mesher, p: Dictionary) -> void:
	var rock: Color = (p.dark as Color).lightened(.12)
	m.box(Vector3(0, .22, 0), Vector3(2.0, .44, 1.7), rock, .2)
	m.box(Vector3(.5, .18, .8), Vector3(1.0, .36, .8), rock.darkened(.06), -.3)
	m.box(Vector3(-.7, .2, -.5), Vector3(.9, .4, .9), rock.lightened(.05), .5)
	var white: Color = (p.stone as Color).lightened(.35)
	m.cyl(Vector3(0, .4, 0), .82, .58, 1.2, 10, white)
	m.cyl(Vector3(0, 1.6, 0), .58, .48, 1.1, 10, p.cloth)
	m.cyl(Vector3(0, 2.7, 0), .48, .42, 1.0, 10, white)
	m.cyl(Vector3(0, 3.7, 0), .62, .62, .1, 10, p.dark)
	_glow_cyl(m, Vector3(0, 3.8, 0), Vector3(0, 4.3, 0), .3, .3, 8)
	m.cyl(Vector3(0, 4.3, 0), .44, 0.0, .5, 10, p.dark)
	m.box(Vector3(1.55, .30, .3), Vector3(1.3, .08, .5), p.wood)
	for index in range(3):
		m.beam(Vector3(1.0 + float(index) * .45, 0, .1), Vector3(1.0 + float(index) * .45, .3, .1), .03, p.wood)
	m.add_flag(Vector3(0, 4.8, 0), .55, .3, p.cloth)
	m.beam(Vector3(0, 4.3, 0), Vector3(0, 4.8, 0), .02, p.metal)

static func _citadel(m: Mesher, p: Dictionary, variant: int) -> void:
	var stone: Color = (p.stone as Color).darkened(.22)
	m.box(Vector3(0, .95, 0), Vector3(2.3, 1.9, 1.8), stone)
	for index in range(6):
		m.box(Vector3(-1.0 + float(index) * .4, 2.0, .86), Vector3(.28, .22, .2), stone.lightened(.05))
	for corner in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
		var x := float(corner[0]) * 1.3
		var z := float(corner[1]) * .98
		m.cyl(Vector3(x, 0, z), .55, .5, 2.6, 8, stone.lightened(.06))
		if variant == 0:
			m.cyl(Vector3(x, 2.6, z), .66, 0.0, .9, 8, p.dark)
		else:
			for index in range(3):
				var angle := float(index) * TAU / 3.0
				m.pyramid(Vector3(x + cos(angle) * .2, 2.6, z + sin(angle) * .2), .2, .2, .75 + float(index) * .12, p.cloth)
		_glow_box(m, Vector3(x + float(corner[0]) * .1, 1.75, z + float(corner[1]) * .48), Vector3(.10, .26, .04))
	m.box(Vector3(0, .58, .92), Vector3(.76, 1.16, .08), (p.dark as Color).darkened(.35))
	_glow_box(m, Vector3(0, 1.3, .96), Vector3(.52, .10, .04))
	for x in [-.55, .55]:
		_glow_box(m, Vector3(x, 1.4, .92), Vector3(.12, .30, .03))
	if variant == 0:
		for x in [-.55, .35]:
			m.cyl(Vector3(x, 1.9, -.4), .17, .14, .75, 8, p.dark)
			m.add_smoke(Vector3(x, 2.75, -.4))
	m.beam(Vector3(0, 1.9, -.6), Vector3(0, 3.0, -.6), .03, p.metal)
	m.add_flag(Vector3(0, 3.0, -.6), .7, .42, p.hostile if variant == 0 else p.cloth)

static func _coil(m: Mesher, p: Dictionary, variant: int) -> void:
	var metal: Color = p.metal
	m.box(Vector3(0, .15, 0), Vector3(1.7, .3, 1.7), (p.stone as Color).darkened(.1))
	if variant == 0:
		for index in range(7):
			var radius := .58 - float(index) * .05
			m.cyl(Vector3(0, .3 + float(index) * .42, 0), radius + .03, radius, .30, 10, metal if index % 2 == 0 else (p.stone as Color))
			_glow_cyl(m, Vector3(0, .6 + float(index) * .42, 0), Vector3(0, .68 + float(index) * .42, 0), radius - .02, radius - .02, 10)
		_glow_cyl(m, Vector3(0, 3.3, 0), Vector3(0, 3.65, 0), .3, .22, 8)
		_glow_cyl(m, Vector3(0, 3.65, 0), Vector3(0, 4.2, 0), .22, 0.0, 8)
		for side in [[-1.25, -.55], [1.25, .55], [1.1, -.7]]:
			for index in range(3):
				m.cyl(Vector3(float(side[0]), float(index) * .36, float(side[1])), .3 - float(index) * .05, .27 - float(index) * .05, .3, 8, metal)
			_glow_cyl(m, Vector3(float(side[0]), 1.08, float(side[1])), Vector3(float(side[0]), 1.3, float(side[1])), .14, 0.0, 6)
	else:
		m.cyl(Vector3(0, .3, 0), .55, .32, 2.8, 8, metal)
		m.cyl(Vector3(0, 3.1, 0), .42, .42, .12, 8, p.dark)
		for index in range(4):
			var angle := float(index) * PI * .5 + PI * .25
			var dir := Vector3(cos(angle), 0, sin(angle))
			var root := Vector3(0, 3.25, 0) + dir * .3
			var mouth := Vector3(0, 3.45, 0) + dir * 1.0
			m.cyl_axis(root, mouth, .13, .42, 8, p.cloth)
			_glow_cyl(m, mouth - dir * .03, mouth + dir * .03, .30, .30, 8)
		m.beam(Vector3(0, 3.3, 0), Vector3(0, 4.0, 0), .03, metal)
		m.add_flag(Vector3(0, 4.0, 0), .5, .3, p.hostile)

static func _cathedral(m: Mesher, p: Dictionary, variant: int) -> void:
	var stone: Color = p.stone
	m.box(Vector3(0, .9, -.1), Vector3(1.8, 1.8, 2.8), stone)
	m.wedge(Vector3(0, 2.15, -.1), Vector3(1.9, .9, 2.95), p.dark, PI * .5)
	if variant == 0:
		for side in [-1.0, 1.0]:
			m.box(Vector3(side * .95, 1.7, 1.25), Vector3(.62, 3.4, .62), stone.lightened(.05))
			m.pyramid(Vector3(side * .95, 3.4, 1.25), .72, .72, 1.1, p.dark)
			_glow_box(m, Vector3(side * .95, 2.6, 1.58), Vector3(.14, .34, .04))
		m.use("glow")
		m.cyl_axis(Vector3(0, 1.75, 1.40), Vector3(0, 1.75, 1.46), .38, .38, 12, Color.WHITE)
		m.use("body")
		m.box(Vector3(0, .5, 1.36), Vector3(.52, 1.0, .08), (p.dark as Color).darkened(.35))
		for side in [-1.0, 1.0]:
			for z in [-.9, .3]:
				m.beam(Vector3(side * .85, 1.4, z), Vector3(side * 1.45, 0, z), .05, stone.darkened(.1))
	else:
		# Frost Cantor: a front row of organ pipes in place of twin towers.
		for index in range(9):
			var x := -1.3 + float(index) * .325
			var height := 1.3 + 1.1 * (1.0 - absf(float(index) - 4.0) / 4.0)
			m.cyl(Vector3(x, 0, 1.3), .12, .11, height, 8, (p.metal as Color).lerp(p.glass, .45))
			_glow_cyl(m, Vector3(x, height, 1.3), Vector3(x, height + .07, 1.3), .10, .10, 8)
		m.box(Vector3(0, .12, 1.3), Vector3(3.1, .24, .5), p.stone.darkened(.15))
		m.pyramid(Vector3(0, 1.75, -.1), 1.7, 2.7, 1.0, p.glass)
	m.beam(Vector3(0, 2.6, -1.3), Vector3(0, 3.5, -1.3), .03, p.metal)
	m.add_flag(Vector3(0, 3.5, -1.3), .6, .36, p.cloth)

static func _crane(m: Mesher, p: Dictionary) -> void:
	var dark: Color = p.dark
	for z in [-.62, .62]:
		m.box(Vector3(0, .24, z), Vector3(2.3, .48, .42), dark)
		for x in [-.8, -.27, .27, .8]:
			m.cyl_axis(Vector3(x, .24, z - .23), Vector3(x, .24, z + .23), .2, .2, 8, (p.metal as Color).lightened(.1))
	m.box(Vector3(-.2, .85, 0), Vector3(1.5, .7, 1.25), p.cloth)
	m.box(Vector3(.35, 1.42, .28), Vector3(.72, .62, .62), (p.cloth as Color).lightened(.08))
	_glow_box(m, Vector3(.72, 1.48, .28), Vector3(.04, .34, .42))
	m.box(Vector3(-1.0, 1.0, 0), Vector3(.52, .62, 1.15), dark)
	m.cyl(Vector3(-.4, 1.2, -.3), .14, .12, .7, 8, dark)
	m.add_smoke(Vector3(-.4, 1.95, -.3))
	m.beam(Vector3(.45, 1.15, -.1), Vector3(2.05, 2.85, -.1), .12, p.metal)
	m.beam(Vector3(.45, 1.15, .1), Vector3(2.05, 2.85, .1), .12, p.metal)
	m.beam(Vector3(2.05, 2.85, 0), Vector3(2.95, 1.45, 0), .10, (p.metal as Color).lightened(.05))
	m.beam(Vector3(.9, .95, .0), Vector3(1.6, 2.1, .0), .06, (p.metal as Color).lightened(.2))
	m.box(Vector3(3.05, 1.2, 0), Vector3(.62, .46, .86), p.metal)
	for index in range(3):
		m.pyramid(Vector3(3.3, 1.0, -.28 + float(index) * .28), .16, .16, -.22, (p.metal as Color).lightened(.25))
	m.add_smoke(Vector3(2.05, 3.0, 0))

static func _clock(m: Mesher, p: Dictionary, variant: int) -> void:
	var stone: Color = p.stone
	var cx := 0.0 if variant == 0 else 1.25
	if variant == 1:
		m.box(Vector3(0, .12, 0), Vector3(4.2, .24, 1.7), stone.darkened(.1))
		m.box(Vector3(-1.1, .85, -.3), Vector3(1.5, 1.2, .95), p.wood)
		m.wedge(Vector3(-1.1, 1.65, -.3), Vector3(1.65, .5, 1.1), p.dark)
		for z in [.85, 1.25]:
			m.beam(Vector3(-2.0, .28, z), Vector3(2.0, .28, z), .035, p.metal)
		m.box(Vector3(-1.1, .55, .2), Vector3(.4, .8, .06), (p.dark as Color).darkened(.3))
	var width := 1.1 if variant == 0 else .9
	var height := 3.2 if variant == 0 else 2.7
	m.box(Vector3(cx, height * .5 + .2, 0), Vector3(width, height, width), stone)
	m.box(Vector3(cx, .28, 0), Vector3(width + .2, .16, width + .2), stone.darkened(.1))
	var face_y := height - .45
	for face in [[0.0, 0.0, 1.0], [1.0, 0.0, 0.0]]:
		var offset := Vector3(float(face[0]), 0, float(face[2])) * (width * .5 + .02)
		m.use("glow")
		var centre := Vector3(cx, face_y, 0) + offset
		m.cyl_axis(centre - offset.normalized() * .02, centre + offset.normalized() * .02, .36, .36, 12, Color.WHITE)
		m.use("body")
		var hand := Vector3(cx, face_y, 0) + offset * 1.25
		m.beam(hand, hand + Vector3(0, .26, 0) + offset.normalized() * .02, .02, p.dark)
		m.beam(hand, hand + (Vector3(.0, .0, -.16) if face[2] > 0 else Vector3(0, 0, .16)) + offset.normalized() * .02, .02, p.dark)
	m.pyramid(Vector3(cx, height + .2, 0), width + .3, width + .3, 1.0, p.dark)
	if variant == 0:
		# Dream Bailiff: fragments of the room drift around the tower.
		for index in range(7):
			var angle := float(index) * 0.9
			m.push(Transform3D(Basis.from_euler(Vector3(float(index) * .7, float(index) * 1.1, float(index) * .4)), Vector3(cos(angle) * 1.5, 1.2 + float(index) * .42, sin(angle) * 1.3)))
			m.box(Vector3.ZERO, Vector3(.30, .16, .22), stone.lerp(p.glass, .4))
			m.pop()
	m.beam(Vector3(cx, height + 1.2, 0), Vector3(cx, height + 1.7, 0), .02, p.metal)
	m.add_flag(Vector3(cx, height + 1.7, 0), .5, .3, p.cloth)

static func _flagship(m: Mesher, p: Dictionary, variant: int) -> void:
	var hull: Color = (p.wood as Color) if variant == 0 else (p.metal as Color).darkened(.15)
	m.box(Vector3(-.1, .30, 0), Vector3(3.2, .6, 1.05), hull)
	m.box(Vector3(-.05, .72, 0), Vector3(3.4, .34, 1.25), hull.lightened(.06))
	m.bow(Vector3(1.6, .30, 0), 1.0, 1.05, .6, hull)
	m.bow(Vector3(1.6, .72, 0), 1.05, 1.25, .34, hull.lightened(.06))
	m.box(Vector3(-.05, .92, 0), Vector3(3.4, .06, 1.3), (p.dark as Color))
	if variant == 0:
		for mast in [[-.85, 3.4], [.25, 3.9], [1.15, 2.9]]:
			var x := float(mast[0])
			var top := float(mast[1])
			m.beam(Vector3(x, .9, 0), Vector3(x, top, 0), .05, p.wood)
			for row in range(2):
				var y := .95 + float(row) * (top - 1.05) * .48
				var sail_h := (top - 1.1) * .4
				m.quad2(Vector3(x, y, -.6), Vector3(x, y, .6), Vector3(x + .08, y + sail_h, .55), Vector3(x + .08, y + sail_h, -.55), (p.dark as Color).lerp(p.cloth, .3 + float(row) * .2))
			m.beam(Vector3(x, top, -.55), Vector3(x, top, .55), .03, p.wood)
		m.add_flag(Vector3(.25, 3.9, 0), .6, .34, p.hostile)
		m.box(Vector3(-1.35, 1.25, 0), Vector3(.85, .65, 1.0), p.wood)
		_glow_box(m, Vector3(-1.35, 1.3, .51), Vector3(.5, .18, .04))
		for index in range(3):
			_glow_box(m, Vector3(-.6 + float(index) * .7, .65, .64), Vector3(.12, .12, .05))
	else:
		m.box(Vector3(-.4, 1.5, 0), Vector3(1.0, 1.15, .9), (p.metal as Color))
		m.box(Vector3(-.4, 2.15, 0), Vector3(1.15, .18, 1.05), p.dark)
		_glow_box(m, Vector3(-.4, 1.75, .46), Vector3(.72, .18, .04))
		m.cyl(Vector3(-.75, 2.2, 0), .26, .22, .75, 8, p.dark)
		m.add_smoke(Vector3(-.75, 3.0, 0))
		m.cyl(Vector3(.95, .96, 0), .40, .36, .22, 10, p.metal)
		m.cyl_axis(Vector3(.95, 1.14, 0), Vector3(1.85, 1.30, 0), .075, .075, 6, p.dark)
		m.cyl(Vector3(-1.2, .96, 0), .34, .3, .2, 10, p.metal)
		m.cyl_axis(Vector3(-1.2, 1.1, 0), Vector3(-.4, 1.0, .7), .06, .06, 6, p.dark)
		m.beam(Vector3(-.4, 2.25, 0), Vector3(-.4, 3.2, 0), .03, p.metal)
		m.add_flag(Vector3(-.4, 3.2, 0), .6, .34, p.cloth)

static func _ring(m: Mesher, p: Dictionary) -> void:
	m.cyl(Vector3(0, 0, 0), .95, .72, .5, 10, p.stone)
	m.cyl(Vector3(0, .5, 0), .30, .26, 1.7, 8, p.metal)
	var tilt := Vector3(.38, 0.0, .18)
	_ring_beams(m, Vector3(0, 2.75, 0), 1.45, 18, .09, (p.metal as Color).lightened(.08), tilt)
	m.use("glow")
	var basis := Basis.from_euler(tilt)
	for index in range(18):
		var a0 := TAU * float(index) / 18.0
		var a1 := TAU * float(index + 1) / 18.0
		m.beam(Vector3(0, 2.75, 0) + basis * Vector3(cos(a0) * 1.22, 0, sin(a0) * 1.22), Vector3(0, 2.75, 0) + basis * Vector3(cos(a1) * 1.22, 0, sin(a1) * 1.22), .035, Color.WHITE)
	m.cyl(Vector3(0, 2.55, 0), .0, .30, .2, 8, Color.WHITE)
	m.cyl(Vector3(0, 2.75, 0), .30, .0, .2, 8, Color.WHITE)
	m.use("body")
	for index in range(3):
		var angle := float(index) * TAU / 3.0 + .5
		var at := Vector3(0, 2.75, 0) + basis * Vector3(cos(angle) * 1.45, 0, sin(angle) * 1.45)
		m.box(at, Vector3(.30, .22, .30), p.stone, angle)
	for index in range(3):
		var angle := float(index) * TAU / 3.0 + 1.6
		m.beam(Vector3(cos(angle) * .55, .5, sin(angle) * .55), Vector3(cos(angle) * .3, 1.4, sin(angle) * .3), .04, p.metal)

static func _dome(m: Mesher, p: Dictionary) -> void:
	var rib: Color = (p.stone as Color).lightened(.1)
	m.cyl(Vector3(0, 0, 0), 1.75, 1.6, .22, 12, p.stone.darkened(.12))
	var meridians := 8
	var steps := [0.0, .30, .58, .84, 1.12, 1.45]
	for index in range(meridians):
		var angle := TAU * float(index) / float(meridians)
		var previous := Vector3(cos(angle) * 1.5, .22, sin(angle) * 1.5)
		for step in range(1, steps.size()):
			var elevation := float(steps[step])
			var point := Vector3(cos(angle) * 1.5 * cos(elevation), .22 + 1.9 * sin(elevation), sin(angle) * 1.5 * cos(elevation))
			m.beam(previous, point, .035, rib)
			previous = point
	for elevation in [.30, .84]:
		_ring_beams(m, Vector3(0, .22 + 1.9 * sin(float(elevation)), 0), 1.5 * cos(float(elevation)), 16, .03, rib)
	_glow_cyl(m, Vector3(0, 1.95, 0), Vector3(0, 2.3, 0), .12, 0.0, 6)
	# A dead tree in the middle of the greenhouse, with a few pale buds.
	m.beam(Vector3(0, .22, 0), Vector3(.05, 1.3, 0), .08, p.dark)
	for branch in [[-.6, 1.6, .1], [.55, 1.75, -.15], [.1, 1.9, .5], [-.2, 1.5, -.55]]:
		m.beam(Vector3(.05, 1.0 + float(branch[1]) * .1, 0), Vector3(float(branch[0]), float(branch[1]), float(branch[2])), .035, p.dark)
		_glow_box(m, Vector3(float(branch[0]), float(branch[1]) + .05, float(branch[2])), Vector3(.10, .10, .10))
	for index in range(5):
		var angle := float(index) * 1.25
		m.box(Vector3(cos(angle) * 1.15, .34, sin(angle) * 1.15), Vector3(.34, .24, .34), p.wood, angle)

static func _archive(m: Mesher, p: Dictionary) -> void:
	var stone: Color = p.stone
	m.box(Vector3(0, .6, 0), Vector3(1.9, 1.2, 1.5), p.dark.lightened(.08))
	m.box(Vector3(0, 1.65, 0), Vector3(1.55, .95, 1.25), stone)
	m.box(Vector3(0, 2.5, 0), Vector3(1.2, .8, 1.0), stone.lightened(.06))
	m.pyramid(Vector3(0, 2.9, 0), 1.35, 1.15, 1.0, p.dark)
	for index in range(6):
		m.box(Vector3(0, .15 + float(index) * .46, .76), Vector3(1.75, .05, .03), (p.dark as Color).darkened(.3))
	for row in range(3):
		for column in range(3):
			_glow_box(m, Vector3(-.4 + float(column) * .4, .4 + float(row) * .78, .77), Vector3(.14, .10, .03))
	for index in range(6):
		var colour: Color = p.cloth if index % 2 == 0 else (p.stone as Color).lightened(.2)
		m.box(Vector3(1.0, .35 + float(index) * .34, .1 + float(index % 3) * .15), Vector3(.30, .12, .48), colour)
	for side in [-.12, .12]:
		m.beam(Vector3(-1.1, 0, .55 + side), Vector3(-.95, 2.3, .55 + side), .025, p.wood)
	for index in range(8):
		m.box(Vector3(-1.03 + float(index % 2) * .02, .25 + float(index) * .27, .55), Vector3(.03, .03, .28), p.wood)
	m.quad2(Vector3(-.5, 2.4, .62), Vector3(.5, 2.4, .62), Vector3(.45, 1.7, .64), Vector3(-.45, 1.7, .64), (p.cloth as Color).darkened(.1))
	m.add_flag(Vector3(0, 3.9, 0), .5, .3, p.cloth)
	m.beam(Vector3(0, 3.9, 0), Vector3(0, 3.5, 0), .02, p.metal)
