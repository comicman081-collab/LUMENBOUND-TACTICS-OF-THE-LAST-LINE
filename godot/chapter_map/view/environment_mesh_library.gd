extends RefCounted

const KIT_PATH := "res://assets/art/chapter_map/NaturalEnvR2/kit/environment.glb"
static var meshes: Dictionary = {}

static func load_once() -> Dictionary:
	if not meshes.is_empty(): return meshes
	var path := KIT_PATH
	if not ResourceLoader.exists(path): return {}
	var packed := load(path) as PackedScene
	if packed == null: return {}
	var root := packed.instantiate()
	_collect(root)
	root.free()
	return meshes

static func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		var names := {"POLISH_CANOPY": "canopy", "POLISH_CANOPY_ALT": "canopy_alt", "POLISH_BOULDER": "boulder", "POLISH_BOULDER_ALT": "boulder_alt", "POLISH_TRUNK": "trunk"}
		if names.has(str(node.name)):
			meshes[names[str(node.name)]] = node.mesh
	for child in node.get_children(): _collect(child)
