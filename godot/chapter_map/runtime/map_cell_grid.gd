extends Control

# Persistent orientation grid, independent of movement points and selection.
#
# The cells stay in world space and are projected by the GPU (world_cell_overlay),
# so the grid is exact for every camera: a pan, zoom, perspective change or camera
# moment is one uniform upload. The earlier version slid one Canvas item by the
# screen shift of the world origin, which is only right for an orthographic camera;
# under perspective the lines swam across cliffs and plateaus by up to ~40px.
#
# Cells are grouped into chunks. Only chunks that are safely in front of the camera
# (a vertex behind the camera plane cannot be projected sensibly) and within reach
# of the view are drawn, and a chunk's mesh is built the first time it is wanted,
# a couple per frame, nearest first.
const Layer := preload("res://chapter_map/runtime/world_cell_overlay.gd")

const OPEN_COLOR := Color("d9dfcb42")
const BLOCKED_COLOR := Color("abb9ae18")
## Each cell paints half of a shared edge, in canvas pixels.
const LINE_HALF_WIDTH := 0.6
const CHUNK_SPAN := 6
const BUILDS_PER_FRAME := 2
## Chunks farther than this many camera distances from the look-at point are skipped.
const FAR_FACTOR := 3.2
## A chunk corner must stay at least this far in front of the camera plane.
const DEPTH_MARGIN := 1.5
const RESELECT_DISTANCE := 1.0

var cells: Array[Dictionary] = []
var chunks: Dictionary = {}
var drawn_cells := 0
var open_layer: Control
var blocked_layer: Control

var _applied_serial := -1
var _selected_keys: Array[Vector2i] = []
var _selection_target := Vector3(1.0e20, 0.0, 0.0)
var _selection_distance := -1.0
var _selection_forward := Vector3.ZERO
var _build_queue: Array[Vector2i] = []
var _drawn_signature := ""

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	open_layer = Layer.new()
	open_layer.name = "OpenCells"
	open_layer.configure_style(Color(0.0, 0.0, 0.0, 0.0), OPEN_COLOR, LINE_HALF_WIDTH)
	add_child(open_layer)
	blocked_layer = Layer.new()
	blocked_layer.name = "BlockedCells"
	blocked_layer.configure_style(Color(0.0, 0.0, 0.0, 0.0), BLOCKED_COLOR, LINE_HALF_WIDTH)
	add_child(blocked_layer)

func configure(screen: Control) -> void:
	cells.clear()
	chunks.clear()
	_build_queue.clear()
	_selected_keys.clear()
	_selection_distance = -1.0
	_drawn_signature = ""
	drawn_cells = 0
	for tile in screen.definition.get("tiles", []):
		var coord := Vector2i(int(tile.q), int(tile.r))
		var height: float = float(tile.get("elevation", 0)) * screen.ELEVATION_STEP + .105
		var corners: Array[Vector3] = screen._movement_hex_corners(coord, height)
		var index := cells.size()
		cells.append({"corners": corners, "center": (corners[0] + corners[3]) * .5, "open": screen.grid.traversable(coord), "q": coord.x, "r": coord.y})
		var key := _chunk_key(coord)
		if not chunks.has(key):
			chunks[key] = {"cells": [], "open": null, "blocked": null, "built": false, "lo": Vector3(1.0e9, 1.0e9, 1.0e9), "hi": Vector3(-1.0e9, -1.0e9, -1.0e9)}
		var chunk: Dictionary = chunks[key]
		(chunk.cells as Array).append(index)
		for corner in corners:
			chunk.lo = Vector3(minf(chunk.lo.x, corner.x), minf(chunk.lo.y, corner.y), minf(chunk.lo.z, corner.z))
			chunk.hi = Vector3(maxf(chunk.hi.x, corner.x), maxf(chunk.hi.y, corner.y), maxf(chunk.hi.z, corner.z))
	open_layer.clear_meshes()
	blocked_layer.clear_meshes()
	_applied_serial = -1

static func _chunk_key(coord: Vector2i) -> Vector2i:
	return Vector2i(floori(float(coord.x) / float(CHUNK_SPAN)), floori(float(coord.y) / float(CHUNK_SPAN)))

func update_projection(screen: Control) -> void:
	if cells.is_empty() or screen.overlay == null or screen.camera == null:
		return
	if screen.overlay_view_serial <= 0:
		return
	var view_changed: bool = screen.overlay_view_serial != _applied_serial
	if view_changed:
		_applied_serial = screen.overlay_view_serial
		open_layer.apply_view(screen.overlay_view_to_clip, screen.overlay_view_size, screen.overlay_view_scale)
		blocked_layer.apply_view(screen.overlay_view_to_clip, screen.overlay_view_size, screen.overlay_view_scale)
		if _selection_needs_refresh(screen):
			_select_chunks(screen)
	var built := 0
	while built < BUILDS_PER_FRAME and not _build_queue.is_empty():
		var key: Vector2i = _build_queue.pop_front()
		if _build_chunk(key):
			built += 1
	if built > 0 or view_changed:
		_refresh_drawn()

func _selection_needs_refresh(screen: Control) -> bool:
	if _selection_distance < 0.0:
		return true
	var target: Vector3 = screen.overlay_view_target
	var forward: Vector3 = screen.overlay_view_forward
	return target.distance_squared_to(_selection_target) > RESELECT_DISTANCE * RESELECT_DISTANCE \
		or absf(float(screen.overlay_view_distance) - _selection_distance) > 0.6 \
		or forward.dot(_selection_forward) < 0.9995

## Chooses the chunks that are entirely in front of the camera and near enough to
## matter, and queues the ones that still need a mesh (nearest first).
func _select_chunks(screen: Control) -> void:
	var origin: Vector3 = screen.overlay_view_origin
	var forward: Vector3 = screen.overlay_view_forward
	var target: Vector3 = screen.overlay_view_target
	var reach: float = maxf(float(screen.overlay_view_distance) * FAR_FACTOR, 24.0)
	_selection_target = target
	_selection_distance = float(screen.overlay_view_distance)
	_selection_forward = screen.overlay_view_forward
	var candidates: Array = []
	for key in chunks.keys():
		var chunk: Dictionary = chunks[key]
		var low: Vector3 = chunk.lo
		var high: Vector3 = chunk.hi
		var centre := (low + high) * 0.5
		var nearest_x := clampf(target.x, low.x, high.x)
		var nearest_z := clampf(target.z, low.z, high.z)
		var gap := Vector2(nearest_x - target.x, nearest_z - target.z).length()
		if gap > reach:
			continue
		var in_front := true
		for corner_index in range(8):
			var corner := Vector3(high.x if corner_index & 1 else low.x, high.y if corner_index & 2 else low.y, high.z if corner_index & 4 else low.z)
			# Depth along the view axis: the clip-space w of a perspective camera, but
			# also meaningful for the orthographic one (whose w is always 1).
			if (corner - origin).dot(forward) < DEPTH_MARGIN:
				in_front = false
				break
		if in_front:
			candidates.append({"key": key, "gap": Vector2(centre.x - target.x, centre.z - target.z).length()})
	candidates.sort_custom(func(a, b): return float(a.gap) < float(b.gap))
	_selected_keys.clear()
	_build_queue.clear()
	for candidate in candidates:
		var key: Vector2i = candidate.key
		_selected_keys.append(key)
		if not bool((chunks[key] as Dictionary).built):
			_build_queue.append(key)

func _build_chunk(key: Vector2i) -> bool:
	var chunk: Dictionary = chunks.get(key, {})
	if chunk.is_empty() or bool(chunk.built):
		return false
	var open_vertices := PackedVector2Array()
	var open_uvs := PackedVector2Array()
	var blocked_vertices := PackedVector2Array()
	var blocked_uvs := PackedVector2Array()
	for index in chunk.cells:
		var cell: Dictionary = cells[int(index)]
		if bool(cell.open):
			Layer.append_cell(open_vertices, open_uvs, cell.corners)
		else:
			Layer.append_cell(blocked_vertices, blocked_uvs, cell.corners)
	chunk.open = Layer.build_mesh(open_vertices, open_uvs)
	chunk.blocked = Layer.build_mesh(blocked_vertices, blocked_uvs)
	chunk.built = true
	return true

func _refresh_drawn() -> void:
	var open_meshes: Array[Mesh] = []
	var blocked_meshes: Array[Mesh] = []
	var total := 0
	var signature := PackedStringArray()
	for key in _selected_keys:
		var chunk: Dictionary = chunks[key]
		if not bool(chunk.built):
			continue
		total += (chunk.cells as Array).size()
		signature.append("%d,%d" % [key.x, key.y])
		if chunk.open != null:
			open_meshes.append(chunk.open)
		if chunk.blocked != null:
			blocked_meshes.append(chunk.blocked)
	drawn_cells = total
	var joined := ";".join(signature)
	if joined == _drawn_signature:
		return
	_drawn_signature = joined
	open_layer.set_meshes(open_meshes)
	blocked_layer.set_meshes(blocked_meshes)
