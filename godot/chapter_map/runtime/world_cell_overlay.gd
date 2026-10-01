extends Control

## One layer of world-space hex cells drawn through the map camera's projection on
## the GPU (see world_cell_overlay.gdshader). Owners feed it meshes made by
## `append_cell()` / `append_band()` / `build_mesh()` and call `apply_view()` whenever
## the camera projection or the overlay size changes; nothing is re-projected on the
## CPU.

const SHADER := preload("res://chapter_map/runtime/world_cell_overlay.gdshader")
## Triangles are positioned by the vertex shader, so the item's own bounds (which
## are made of world coordinates) must never be used to cull it.
const CULL_RECT := Rect2(Vector2(-32768.0, -32768.0), Vector2(65536.0, 65536.0))

var layer_material: ShaderMaterial
var meshes: Array[Mesh] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_material = ShaderMaterial.new()
	layer_material.shader = SHADER
	material = layer_material

func _ready() -> void:
	RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, CULL_RECT)

## `ribbon` layers hold `append_band()` geometry and paint only `line`; cell layers
## paint `fill` plus an outline of `line_half_width` canvas pixels on flagged edges.
func configure_style(fill: Color, line: Color, line_half_width: float, ribbon := false) -> void:
	layer_material.set_shader_parameter("fill_color", fill)
	layer_material.set_shader_parameter("line_color", line)
	layer_material.set_shader_parameter("line_half_width", line_half_width)
	layer_material.set_shader_parameter("ribbon", 1.0 if ribbon else 0.0)

func apply_view(world_to_clip: Projection, view_size: Vector2, physical_scale: float) -> void:
	layer_material.set_shader_parameter("world_to_clip", world_to_clip)
	layer_material.set_shader_parameter("target_size", view_size)
	layer_material.set_shader_parameter("px_scale", physical_scale)

func set_meshes(value: Array[Mesh]) -> void:
	meshes = value
	queue_redraw()

func clear_meshes() -> void:
	meshes = []
	queue_redraw()

func triangle_count() -> int:
	var total := 0
	for mesh in meshes:
		if mesh is ArrayMesh and mesh.get_surface_count() > 0:
			total += int(mesh.surface_get_array_len(0) / 3)
	return total

func _draw() -> void:
	for mesh in meshes:
		if mesh != null:
			draw_mesh(mesh, null)

## Appends the six triangles of one hex cell (centre + two corners each). Bit `i` of
## `line_mask` outlines the edge from corner i to corner i + 1; an edge whose bit is
## clear is filled but not outlined (its two corners get the centre's distance, so
## the distance field is flat there).
static func append_cell(vertices: PackedVector2Array, uvs: PackedVector2Array, corners: Array[Vector3], line_mask := 0x3F) -> void:
	var centre := (corners[0] + corners[3]) * 0.5
	for edge in range(6):
		var from := corners[edge]
		var to := corners[(edge + 1) % 6]
		var edge_distance := 0.0 if line_mask & (1 << edge) != 0 else 1.0
		vertices.append(Vector2(centre.x, centre.z))
		vertices.append(Vector2(from.x, from.z))
		vertices.append(Vector2(to.x, to.z))
		uvs.append(Vector2(centre.y, 1.0))
		uvs.append(Vector2(from.y, edge_distance))
		uvs.append(Vector2(to.y, edge_distance))

## Appends a world-width band centred on the edge `from` -> `to`: the sides sit at
## `centre -/+ offset` (a plan-view vector per end, so neighbouring bands can share
## mitred corners). Distance field: 0 on both sides, 1 on the middle line.
static func append_band(vertices: PackedVector2Array, uvs: PackedVector2Array, from: Vector3, to: Vector3, from_offset: Vector3, to_offset: Vector3) -> void:
	var inner_from := from - from_offset
	var inner_to := to - to_offset
	var outer_from := from + from_offset
	var outer_to := to + to_offset
	_append_triangle(vertices, uvs, inner_from, 0.0, inner_to, 0.0, to, 1.0)
	_append_triangle(vertices, uvs, inner_from, 0.0, to, 1.0, from, 1.0)
	_append_triangle(vertices, uvs, from, 1.0, to, 1.0, outer_to, 0.0)
	_append_triangle(vertices, uvs, from, 1.0, outer_to, 0.0, outer_from, 0.0)

static func _append_triangle(vertices: PackedVector2Array, uvs: PackedVector2Array, a: Vector3, a_distance: float, b: Vector3, b_distance: float, c: Vector3, c_distance: float) -> void:
	vertices.append(Vector2(a.x, a.z))
	vertices.append(Vector2(b.x, b.z))
	vertices.append(Vector2(c.x, c.z))
	uvs.append(Vector2(a.y, a_distance))
	uvs.append(Vector2(b.y, b_distance))
	uvs.append(Vector2(c.y, c_distance))

static func build_mesh(vertices: PackedVector2Array, uvs: PackedVector2Array) -> ArrayMesh:
	if vertices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## The exact formula the vertex shader applies, for tests and CPU-side lookups.
static func project(world_to_clip: Projection, world: Vector3, view_size: Vector2) -> Vector2:
	var clip := world_to_clip * Vector4(world.x, world.y, world.z, 1.0)
	var w := maxf(clip.w, 0.05)
	return Vector2(clip.x / w * 0.5 + 0.5, 0.5 - clip.y / w * 0.5) * view_size
