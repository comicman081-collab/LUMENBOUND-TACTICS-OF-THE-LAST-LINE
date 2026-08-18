class_name HexGrid
extends RefCounted

const HexCoordScript := preload("res://chapter_map/model/hex_coord.gd")

var tiles: Dictionary = {}

func load_tiles(source: Array) -> void:
	tiles.clear()
	for row in source:
		var coord := Vector2i(int(row.get("q", 0)), int(row.get("r", 0)))
		tiles[HexCoordScript.key(coord)] = row.duplicate(true)

func has(coord: Vector2i) -> bool:
	return tiles.has(HexCoordScript.key(coord))

func tile(coord: Vector2i) -> Dictionary:
	return tiles.get(HexCoordScript.key(coord), {})

func traversable(coord: Vector2i) -> bool:
	var definition := tile(coord)
	return not definition.is_empty() and not bool(definition.get("movement_blocked", false))

func can_step(from: Vector2i, to: Vector2i) -> bool:
	if not traversable(from) or not traversable(to) or HexCoordScript.distance(from, to) != 1:
		return false
	return absi(int(tile(from).get("elevation", 0)) - int(tile(to).get("elevation", 0))) <= 1

func movement_cost(coord: Vector2i) -> int:
	return maxi(1, int(tile(coord).get("movement_cost", 1)))
