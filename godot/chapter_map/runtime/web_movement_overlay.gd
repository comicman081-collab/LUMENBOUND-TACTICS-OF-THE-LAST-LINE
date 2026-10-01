extends Control

## The yellow movement range on browsers, where dynamic 3D meshes stall the frame.
## Cells are kept in world space and projected by the GPU (world_cell_overlay), so
## they stay glued to the terrain top of every elevation while the camera pans,
## zooms or plays a moment. Two layers: the cell fills with a thin seam on every
## edge shared with another range cell, and a world-width band along the edges on
## the range border (the same bold outline the 3D range draws on desktop).

const Layer := preload("res://chapter_map/runtime/world_cell_overlay.gd")

const FILL_COLOR := Color("edcb772b")
const GRID_COLOR := Color("e8d19a70")
const BOUNDARY_COLOR := Color("ffe4a3d9")
## Each cell paints half of a shared seam, so this is a half width in pixels.
const GRID_HALF_WIDTH := 0.9
## Half width of the border band in world units (the 3D ribbons use 0.070).
const BORDER_HALF_WIDTH := 0.070

var seam_layer: Control
var border_layer: Control
var cell_count := 0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	seam_layer = Layer.new()
	seam_layer.name = "RangeCells"
	seam_layer.configure_style(FILL_COLOR, GRID_COLOR, GRID_HALF_WIDTH)
	add_child(seam_layer)
	border_layer = Layer.new()
	border_layer.name = "RangeBorder"
	border_layer.configure_style(Color(0.0, 0.0, 0.0, 0.0), BOUNDARY_COLOR, 0.0, true)
	add_child(border_layer)

## `cells`: one Dictionary per cell, {"corners": Array[Vector3] x6 at the cell's
## own surface height, "boundary": bit i set when the edge from corner i to corner
## i + 1 faces outside the range}.
func set_world_cells(cells: Array) -> void:
	var cell_vertices := PackedVector2Array()
	var cell_uvs := PackedVector2Array()
	var border_edges: Array = []
	var corner_normals: Dictionary = {}
	for cell in cells:
		var corners: Array[Vector3] = cell.corners
		var boundary := int(cell.boundary) & 0x3F
		# Seams only on the edges that touch another range cell.
		Layer.append_cell(cell_vertices, cell_uvs, corners, ~boundary & 0x3F)
		if boundary == 0:
			continue
		var centre := (corners[0] + corners[3]) * 0.5
		for edge in range(6):
			if boundary & (1 << edge) == 0:
				continue
			var from := corners[edge]
			var to := corners[(edge + 1) % 6]
			var outward := Vector2((from.x + to.x) * 0.5 - centre.x, (from.z + to.z) * 0.5 - centre.z).normalized()
			border_edges.append({"from": from, "to": to, "normal": outward})
			for end in [from, to]:
				var key := _corner_key(end)
				corner_normals[key] = (corner_normals.get(key, Vector2.ZERO) as Vector2) + outward
	var border_vertices := PackedVector2Array()
	var border_uvs := PackedVector2Array()
	for edge in border_edges:
		var from: Vector3 = edge.from
		var to: Vector3 = edge.to
		var normal: Vector2 = edge.normal
		Layer.append_band(border_vertices, border_uvs, from, to, _mitre_offset(corner_normals[_corner_key(from)], normal), _mitre_offset(corner_normals[_corner_key(to)], normal))
	var cell_meshes: Array[Mesh] = []
	var border_meshes: Array[Mesh] = []
	var cell_mesh := Layer.build_mesh(cell_vertices, cell_uvs)
	var border_mesh := Layer.build_mesh(border_vertices, border_uvs)
	if cell_mesh != null:
		cell_meshes.append(cell_mesh)
	if border_mesh != null:
		border_meshes.append(border_mesh)
	seam_layer.set_meshes(cell_meshes)
	border_layer.set_meshes(border_meshes)
	cell_count = cells.size()
	visible = cell_count > 0

func clear_geometry() -> void:
	seam_layer.clear_meshes()
	border_layer.clear_meshes()
	cell_count = 0
	visible = false

func apply_view(world_to_clip: Projection, view_size: Vector2, physical_scale: float) -> void:
	seam_layer.apply_view(world_to_clip, view_size, physical_scale)
	border_layer.apply_view(world_to_clip, view_size, physical_scale)

## Two border edges meet at every corner of the range; the band's sides there are the
## corner pushed along the bisector of their outward normals, far enough that each
## side stays BORDER_HALF_WIDTH from its own edge (a mitred join, convex or concave).
static func _mitre_offset(corner_normal: Vector2, edge_normal: Vector2) -> Vector3:
	if corner_normal.length_squared() < 1.0e-8:
		return Vector3(edge_normal.x, 0.0, edge_normal.y) * BORDER_HALF_WIDTH
	var bisector := corner_normal.normalized()
	var reach := BORDER_HALF_WIDTH / maxf(bisector.dot(edge_normal), 0.35)
	return Vector3(bisector.x, 0.0, bisector.y) * reach

## Corners of different cells coincide in plan view; millimetre keys join them.
static func _corner_key(corner: Vector3) -> Vector2i:
	return Vector2i(roundi(corner.x * 1000.0), roundi(corner.z * 1000.0))
