extends Control

var cell_polygons: Array[PackedVector2Array] = []
var grid_segments := PackedVector2Array()
var boundary_segments := PackedVector2Array()

const FILL_COLOR := Color("edcb772b")
const GRID_COLOR := Color("e8d19a70")
const BOUNDARY_COLOR := Color("ffe4a3d9")

func set_geometry(cells: Array[PackedVector2Array], grid: PackedVector2Array, boundary: PackedVector2Array) -> void:
	cell_polygons = cells
	grid_segments = grid
	boundary_segments = boundary
	visible = not cell_polygons.is_empty()
	queue_redraw()

func clear_geometry() -> void:
	cell_polygons.clear()
	grid_segments.clear()
	boundary_segments.clear()
	visible = false
	queue_redraw()

func _draw() -> void:
	for polygon in cell_polygons:
		if polygon.size() >= 3:
			draw_colored_polygon(polygon, FILL_COLOR)
	for index in range(0, grid_segments.size() - 1, 2):
		draw_line(grid_segments[index], grid_segments[index + 1], GRID_COLOR, 1.5, false)
	for index in range(0, boundary_segments.size() - 1, 2):
		draw_line(boundary_segments[index], boundary_segments[index + 1], BOUNDARY_COLOR, 3.5, false)
