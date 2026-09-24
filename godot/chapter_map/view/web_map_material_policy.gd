extends RefCounted

static var surface_shaders: Dictionary = {}

## The Web map is matte soil, wood and stone, lit by the authored map lights.
## Avoid compiling the expensive GGX/Burley branches for those materials.
## This does not turn off lighting, flatten normals, or change native rendering.
static func apply(material: StandardMaterial3D) -> void:
	if not OS.has_feature("web"):
		return
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX

static func surface_shader(source: Shader) -> Shader:
	if not OS.has_feature("web"):
		return source
	var key := source.resource_path
	if surface_shaders.has(key): return surface_shaders[key]
	# Preserve the authored per-fragment soil/foliage detail. Only matte light
	# evaluation moves to the vertices; these meshes already have flat normals.
	var code := source.code
	if code.contains("render_mode "):
		code = code.replace("render_mode ", "render_mode vertex_lighting, diffuse_lambert, specular_disabled, ")
	else:
		code = code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode vertex_lighting, diffuse_lambert, specular_disabled;")
	var shader := Shader.new()
	shader.code = code
	surface_shaders[key] = shader
	return shader
