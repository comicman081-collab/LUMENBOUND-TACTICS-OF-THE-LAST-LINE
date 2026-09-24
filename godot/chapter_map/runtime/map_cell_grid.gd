extends Control

# Persistent orientation grid, independent of movement points and selection.
# Cache world polygons once; camera translation moves one Canvas item until
# its padded coverage needs refreshing. No meshes are uploaded while walking.
const OPEN_COLOR := Color("d9dfcb42")
const BLOCKED_COLOR := Color("abb9ae18")
var cells: Array[Dictionary] = []
var open_segments := PackedVector2Array()
var blocked_segments := PackedVector2Array()
var projection_size := Vector2(-1, -1)
var projection_zoom := -1.0
var projection_origin := Vector2.ZERO
var drawn_cells := 0

func configure(screen: Control) -> void:
	cells.clear()
	for tile in screen.definition.get("tiles", []):
		var coord := Vector2i(int(tile.q), int(tile.r))
		var height: float = float(tile.get("elevation", 0)) * screen.ELEVATION_STEP + .105
		var corners: Array[Vector3] = screen._movement_hex_corners(coord, height)
		cells.append({"corners": corners, "center": (corners[0] + corners[3]) * .5, "open": screen.grid.traversable(coord)})
	projection_size = Vector2(-1, -1)

func update_projection(screen: Control) -> void:
	if cells.is_empty() or screen.overlay == null or screen.camera == null:
		return
	var origin: Vector2 = screen._overlay_position_from_world(Vector3.ZERO)
	var same_scale: bool = projection_size.is_equal_approx(screen.overlay.size) and is_equal_approx(projection_zoom, screen.camera.size)
	var shift := origin - projection_origin
	if same_scale and shift.length_squared() < 9216.0:
		position = shift
		return
	position = Vector2.ZERO
	open_segments.clear()
	blocked_segments.clear()
	drawn_cells = 0
	var bounds := Rect2(Vector2.ZERO, screen.overlay.size).grow(192.0)
	for cell in cells:
		if not bounds.has_point(screen._overlay_position_from_world(cell.center)):
			continue
		var polygon := PackedVector2Array()
		for corner in cell.corners:
			polygon.append(screen._overlay_position_from_world(corner))
		for edge in range(6):
			if cell.open:
				open_segments.append(polygon[edge])
				open_segments.append(polygon[(edge + 1) % 6])
			else:
				blocked_segments.append(polygon[edge])
				blocked_segments.append(polygon[(edge + 1) % 6])
		drawn_cells += 1
	projection_size = screen.overlay.size
	projection_zoom = screen.camera.size
	projection_origin = origin
	queue_redraw()

func _draw() -> void:
	# Negative width keeps a thin pixel line under portrait/landscape scaling.
	if not blocked_segments.is_empty():
		draw_multiline(blocked_segments, BLOCKED_COLOR, -1.0)
	if not open_segments.is_empty():
		draw_multiline(open_segments, OPEN_COLOR, -1.0)
