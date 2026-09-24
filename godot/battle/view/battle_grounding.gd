extends RefCounted

## Presentation-only contact registration; immutable bitmap alpha and original
## backdrop floor regions are the authorities. No combat/pathfinding mutation.
const ANCHORS_PATH := "res://data/battle_contact_anchors_r2_spritegen.json"
static var registry: Dictionary = {}

static func contacts(kind: String, entity: String, action: String, elapsed: float) -> Array:
	if registry.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ANCHORS_PATH))
		if parsed is Dictionary: registry = parsed
	var definition: Dictionary = registry.get("packs", {}).get(kind, {}).get(entity, {}).get(action, {})
	var frames: Array = definition.get("frames", [])
	if frames.is_empty(): return [[0.5, 0.88]]
	var index := maxi(0, int(floor(elapsed * float(definition.get("fps", 12)))))
	index = index % frames.size() if bool(definition.get("loop", false)) else mini(index, frames.size() - 1)
	return frames[index]

static func register_pose(pose: Dictionary, points: Array, body_scale: float, mirrored: bool) -> Dictionary:
	var draw_scale: Vector2 = pose.get("scale", Vector2.ONE)
	if mirrored: draw_scale.x *= -1.0
	var rotation := float(pose.get("rotation", 0.0))
	var bottom := -INF
	var contact_x := 0.0
	for raw in points:
		var local := (Vector2(float(raw[0]), float(raw[1])) - Vector2(.5, .88)) * 512.0 * body_scale
		var transformed := (local * draw_scale).rotated(rotation)
		if transformed.y > bottom:
			bottom = transformed.y
			contact_x = transformed.x
	var offset: Vector2 = pose.get("offset", Vector2.ZERO)
	# Ground actions transfer weight, never translate the whole cutout upward.
	# The per-frame correction also removes lift baked into the old source poses.
	offset.y = -bottom
	return {"offset": offset, "scale": draw_scale, "rotation": rotation, "contact_x": contact_x, "bottom_y": bottom + offset.y}

static func formation_point(view_size: Vector2, player: bool, slot: int, _boss_stage: bool) -> Vector2:
	# Both arenas share the same continuous foreground floor. Keeping the same
	# lane coordinates also prevents a formation jump when a boss wave arrives.
	var point: Vector2
	if player:
		# Slots are 전열 A/B, 중열 A/B, 후열. Enemies stand on the right, so the
		# front row takes the columns nearest them and the back row stays furthest
		# left; melee lunges no longer run through the whole party.
		var columns := [.412, .334, .256, .178, .10]
		var lanes := [.84, .725, .84, .725, .84]
		point = Vector2(float(columns[slot % 5]), float(lanes[slot % 5]))
	else:
		var columns := [.66, .85, .755]
		var lanes := [.745, .815, .87]
		point = Vector2(float(columns[slot % 3]), float(lanes[slot % 3]))
	return point * view_size
