extends RefCounted

## Static 2D triangle meshes with vertex colours (r22).
##
## `draw_polyline` and `draw_colored_polygon` record a new GPU buffer for every
## call, every frame, on the Web renderer. A floor ornament of a hundred strokes
## or the eighteen cells of the tactical grid never change shape, so they are
## tessellated here once (anti-aliased strokes with mitred joins, ear-clipped
## fills) into one ArrayMesh and drawn with a single `draw_mesh` per frame.
## Shapes are appended in painter's order and keep their own colour and alpha,
## so one mesh composes exactly like the sequence of commands it replaces.

const FEATHER := 1.0
const MITER_LIMIT := 3.0

var vertices := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()

func is_empty() -> bool:
	return indices.is_empty()

## Filled polygon, hard edged like `draw_colored_polygon`.
func fill(points: PackedVector2Array, color: Color) -> void:
	var count := points.size()
	if count < 3: return
	if points[0].is_equal_approx(points[count - 1]) and count > 3:
		points = points.slice(0, count - 1)
		count -= 1
	var triangles := Geometry2D.triangulate_polygon(points)
	var base := vertices.size()
	vertices.append_array(points)
	for index in range(count): colors.append(color)
	if triangles.is_empty():
		# Self-touching outline: a fan is right for the convex shapes used here.
		for index in range(1, count - 1):
			indices.append(base)
			indices.append(base + index)
			indices.append(base + index + 1)
		return
	for index in triangles: indices.append(base + index)

## Anti-aliased stroke of constant pixel `width` through `points` with mitred
## joins. A closed outline may repeat its first point at the end.
func stroke(points: PackedVector2Array, width: float, color: Color, closed := false) -> void:
	var count := points.size()
	if closed and count > 2 and points[0].is_equal_approx(points[count - 1]): count -= 1
	if count < 2 or width <= 0.0: return
	var strength := minf(1.0, width)
	var half := maxf(width, 1.0) * .5
	var inner := maxf(half - FEATHER * .5, 0.0)
	var outer := half + FEATHER * .5
	var core := Color(color.r, color.g, color.b, color.a * strength)
	var clear := Color(color.r, color.g, color.b, 0.0)
	var base := vertices.size()
	for index in range(count):
		var current := points[index]
		var before := Vector2.ZERO
		var after := Vector2.ZERO
		if closed or index > 0:
			before = (current - points[(index - 1 + count) % count]).normalized()
		if closed or index < count - 1:
			after = (points[(index + 1) % count] - current).normalized()
		if before == Vector2.ZERO: before = after
		if after == Vector2.ZERO: after = before
		var normal_before := Vector2(-before.y, before.x)
		var normal_after := Vector2(-after.y, after.x)
		var miter := normal_before + normal_after
		var reach := 1.0
		if miter.length_squared() > .000001:
			miter = miter.normalized()
			reach = minf(MITER_LIMIT, 1.0 / maxf(miter.dot(normal_after), .0001))
		else:
			miter = normal_after
		vertices.append(current + miter * outer * reach)
		vertices.append(current + miter * inner * reach)
		vertices.append(current - miter * inner * reach)
		vertices.append(current - miter * outer * reach)
		colors.append(clear)
		colors.append(core)
		colors.append(core)
		colors.append(clear)
	var segments := count if closed else count - 1
	for index in range(segments):
		var a := base + index * 4
		var b := base + ((index + 1) % count) * 4
		for row in range(3):
			indices.append(a + row)
			indices.append(a + row + 1)
			indices.append(b + row)
			indices.append(a + row + 1)
			indices.append(b + row + 1)
			indices.append(b + row)

## Independent straight segments (a, b, a, b ...), each with butt ends.
func segments(points: PackedVector2Array, width: float, color: Color) -> void:
	for index in range(0, points.size() - 1, 2):
		stroke(PackedVector2Array([points[index], points[index + 1]]), width, color, false)

## The finished mesh, or null when nothing was added (or no renderer exists to
## hold it, which `draw_mesh` ignores anyway).
func build() -> ArrayMesh:
	if indices.is_empty(): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
