class_name HexPathfinder
extends RefCounted

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")

static func find_path(grid, start: Vector2i, goal: Vector2i, allowed: Dictionary = {}, blocked: Dictionary = {}) -> Array[Vector2i]:
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
			# A live hostile occupies real ground. It may be the requested terminal
			# goal (which triggers contact), but a route to some other destination
			# must detour instead of silently walking through that pawn.
			if (blocked.has(next_key) and next_coord != goal) or (not allowed.is_empty() and not allowed.has(next_key)) or not grid.can_step(current, next_coord):
				continue
			var new_cost: int = int(cost_so_far[HexCoordScript.key(current)]) + grid.movement_cost(next_coord)
			if not cost_so_far.has(next_key) or new_cost < int(cost_so_far[next_key]):
				cost_so_far[next_key] = new_cost
				came_from[next_key] = current
				if not open.has(next_coord): open.append(next_coord)
	return []

static func reachable_within(grid, start: Vector2i, max_steps: int, allowed: Dictionary = {}, stop_after: Dictionary = {}) -> Dictionary:
	# Breadth-first range authority for the per-pulse map overlay. Movement is
	# discrete one-hex-per-point in the runtime, so this uses the exact same
	# can_step contract as pathfinding (blocked water and two-level cliffs stay
	# outside the highlighted area). Values are the minimum required steps.
	var reachable: Dictionary = {}
	if max_steps < 0 or not grid.traversable(start):
		return reachable
	var start_key := HexCoordScript.key(start)
	if not allowed.is_empty() and not allowed.has(start_key):
		return reachable
	reachable[start_key] = 0
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		var current_key := HexCoordScript.key(current)
		var current_steps := int(reachable[current_key])
		# A hostile contact tile is reachable, but contact owns the transition and
		# movement can never continue through it during the same pulse.
		if current != start and stop_after.has(current_key):
			continue
		if current_steps >= max_steps:
			continue
		var next_coords := HexCoordScript.neighbors(current)
		next_coords.sort_custom(func(left: Vector2i, right: Vector2i) -> bool: return left.x < right.x or (left.x == right.x and left.y < right.y))
		for next_coord in next_coords:
			var next_key := HexCoordScript.key(next_coord)
			if reachable.has(next_key) or (not allowed.is_empty() and not allowed.has(next_key)) or not grid.can_step(current, next_coord):
				continue
			reachable[next_key] = current_steps + 1
			frontier.append(next_coord)
	return reachable

static func _reconstruct(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var current := goal
	while current != start:
		var key := HexCoordScript.key(current)
		if not came_from.has(key): return []
		current = came_from[key]
		path.push_front(current)
	return path
