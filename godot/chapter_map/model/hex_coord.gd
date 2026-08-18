class_name HexCoord
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]

static func key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]

static func from_key(value: String) -> Vector2i:
	var parts := value.split(",")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i.ZERO

static func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in DIRECTIONS:
		result.append(coord + direction)
	return result

static func distance(left: Vector2i, right: Vector2i) -> int:
	var dq := left.x - right.x
	var dr := left.y - right.y
	return maxi(absi(dq), maxi(absi(dr), absi(dq + dr)))

static func axial_to_world(coord: Vector2i, size: float = 1.0, elevation: float = 0.0) -> Vector3:
	var x := size * sqrt(3.0) * (float(coord.x) + float(coord.y) * 0.5)
	var z := size * 1.5 * float(coord.y)
	return Vector3(x, elevation, z)

static func world_to_axial(position: Vector3, size: float = 1.0) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * position.x - position.z / 3.0) / size
	var r := (2.0 / 3.0 * position.z) / size
	return _cube_round(q, r)

static func _cube_round(q: float, r: float) -> Vector2i:
	var x := q
	var z := r
	var y := -x - z
	var rx := roundi(x)
	var ry := roundi(y)
	var rz := roundi(z)
	var x_diff := absf(float(rx) - x)
	var y_diff := absf(float(ry) - y)
	var z_diff := absf(float(rz) - z)
	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(rx, rz)
