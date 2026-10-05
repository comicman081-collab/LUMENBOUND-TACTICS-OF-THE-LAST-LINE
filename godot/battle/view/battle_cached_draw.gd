extends RefCounted

## Small reusable meshes for effects whose centre, direction, radius and tint
## animate but whose topology never changes. No clock or animation is sampled
## less often: the caller's current positions and sizes remain authoritative.
const CIRCLE_POINTS := 64

static var _disc: ArrayMesh = null

static func disc_mesh() -> ArrayMesh:
	if _disc == null:
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		for index in range(CIRCLE_POINTS + 1):
			var angle := TAU * float(index) / float(CIRCLE_POINTS)
			points.append(Vector2(cos(angle), sin(angle)))
			colors.append(Color.WHITE)
			if index < CIRCLE_POINTS:
				indices.append_array(PackedInt32Array([CIRCLE_POINTS + 1, index, index + 1]))
		points.append(Vector2.ZERO)
		colors.append(Color.WHITE)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		_disc = ArrayMesh.new()
		_disc.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _disc

static func disc(c: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0: return
	c.draw_mesh(disc_mesh(), null, Transform2D(Vector2(radius, 0), Vector2(0, radius), center), color)

## Three/four-vertex fills fit the canvas renderer's normal streamed batch;
## draw_colored_polygon takes the separate polygon-buffer path even for these.
static func fill(c: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	var colors := PackedColorArray()
	for _index in points.size(): colors.append(color)
	c.draw_primitive(points, colors, PackedVector2Array())
