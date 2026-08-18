class_name HexPathfinder
extends RefCounted

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")

static func find_path(grid, start: Vector2i, goal: Vector2i, allowed: Dictionary = {}) -> Array[Vector2i]:
	if not grid.traversable(start) or not grid.traversable(goal):
		return []
	if not allowed.is_empty() and (not allowed.has(HexCoordScript.key(start)) or not allowed.has(HexCoordScript.key(goal))):
		return []
	var open: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var cost_so_far := {HexCoordScript.key(start): 0}
	while not open.is_empty():
		open.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
			var left_cost: int = int(cost_so_far[HexCoordScript.key(left)]) + HexCoordScript.distance(left, goal)
			var right_cost: int = int(cost_so_far[HexCoordScript.key(right)]) + HexCoordScript.distance(right, goal)
			if left_cost != right_cost: return left_cost < right_cost
			if left.x != right.x: return left.x < right.x
			return left.y < right.y)
		var current: Vector2i = open.pop_front()
		if current == goal:
			return _reconstruct(came_from, start, goal)
		var next_coords := HexCoordScript.neighbors(current)
		next_coords.sort_custom(func(left: Vector2i, right: Vector2i) -> bool: return left.x < right.x or (left.x == right.x and left.y < right.y))
		for next_coord in next_coords:
			var next_key := HexCoordScript.key(next_coord)
			if (not allowed.is_empty() and not allowed.has(next_key)) or not grid.can_step(current, next_coord):
				continue
			var new_cost: int = int(cost_so_far[HexCoordScript.key(current)]) + grid.movement_cost(next_coord)
			if not cost_so_far.has(next_key) or new_cost < int(cost_so_far[next_key]):
				cost_so_far[next_key] = new_cost
				came_from[next_key] = current
				if not open.has(next_coord): open.append(next_coord)
	return []

static func _reconstruct(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var current := goal
	while current != start:
		var key := HexCoordScript.key(current)
		if not came_from.has(key): return []
		current = came_from[key]
		path.push_front(current)
	return path
