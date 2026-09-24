extends RefCounted

# One geometric authority for visible water and the navigation footprint.
const Hex := preload("res://chapter_map/model/hex_coord.gd")
const TILE_SIZE := 1.08
const HALF_WIDTH := 0.74
# Reserve the full hex footprint, not only its centre. Otherwise the yellow
# polygon and the pawn's turn could still extend over the visible water edge.
const BANK_CLEARANCE := TILE_SIZE

static func route_polyline(definition: Dictionary) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var start: Dictionary = definition.get("start_hex", {})
	var previous := Vector2i(int(start.get("q", 0)), int(start.get("r", 0)))
	points.append(previous)
	for stage in definition.get("normal_route", []):
		var target := previous
		for node in definition.get("nodes", []):
			if str(node.get("stage_id", "")) == str(stage):
				target = Vector2i(int(node.q), int(node.r))
				break
		while previous != target:
			var neighbors := Hex.neighbors(previous)
			neighbors.sort_custom(func(a: Vector2i, b: Vector2i):
				var da := Hex.distance(a, target)
				var db := Hex.distance(b, target)
				return da < db if da != db else (a.x < b.x or (a.x == b.x and a.y < b.y)))
			previous = neighbors[0]
			points.append(previous)
	return points

static func build(definition: Dictionary) -> Dictionary:
	var coords := route_polyline(definition)
	var route: Array[Vector3] = []
	for coord in coords:
		route.append(Hex.axial_to_world(coord, TILE_SIZE))
	var points: Array[Vector3] = []
	var sides: Array[Vector3] = []
	var previous_side := Vector3.ZERO
	for index in range(route.size()):
		var current := route[index]
		var incoming := route[index] - route[index - 1] if index > 0 else route[mini(1, route.size() - 1)] - current
		var outgoing := route[index + 1] - current if index < route.size() - 1 else incoming
		if incoming.is_zero_approx(): incoming = outgoing
		if outgoing.is_zero_approx(): outgoing = incoming
		incoming = incoming.normalized()
		outgoing = outgoing.normalized()
		var incoming_side := Vector3(-incoming.z, 0.0, incoming.x)
		var outgoing_side := Vector3(-outgoing.z, 0.0, outgoing.x)
		if previous_side != Vector3.ZERO:
			if incoming_side.dot(previous_side) < 0.0: incoming_side = -incoming_side
			if outgoing_side.dot(previous_side) < 0.0: outgoing_side = -outgoing_side
		var side := incoming_side + outgoing_side
		if side.is_zero_approx(): side = previous_side if previous_side != Vector3.ZERO else incoming_side
		side = side.normalized()
		if previous_side != Vector3.ZERO and side.dot(previous_side) < 0.0: side = -side
		previous_side = side
		var alignment := maxf(0.78, minf(absf(side.dot(incoming_side)), absf(side.dot(outgoing_side))))
		var meander := sin(float(index) * 0.41 + float(coords[index].x) * 0.071 - float(coords[index].y) * 0.113) * 0.26
		var lateral_offset := clampf((2.72 + meander) / alignment, 2.45, 3.35)
		points.append(current + side * lateral_offset)
		sides.append(side)
	var footprint: Dictionary = {}
	# Rasterize only nearby hexes, not every tile against every river segment.
	for index in range(points.size() - 1):
		var a := Vector2(points[index].x, points[index].z)
		var b := Vector2(points[index + 1].x, points[index + 1].z)
		var samples := maxi(1, ceili(a.distance_to(b) / (TILE_SIZE * 0.5)))
		for sample in range(samples + 1):
			var p := a.lerp(b, float(sample) / samples)
			var center := Hex.world_to_axial(Vector3(p.x, 0.0, p.y), TILE_SIZE)
			var candidates := Hex.neighbors(center)
			candidates.append(center)
			for coord in candidates:
				var world := Hex.axial_to_world(coord, TILE_SIZE)
				var position := Vector2(world.x, world.z)
				if Geometry2D.get_closest_point_to_segment(position, a, b).distance_to(position) <= HALF_WIDTH + BANK_CLEARANCE:
					footprint[Hex.key(coord)] = true
	return {"points": points, "sides": sides, "footprint": footprint}
