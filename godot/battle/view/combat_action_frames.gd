extends RefCounted
const DensityLoader := preload("res://battle/view/density_texture_loader.gd")

## Reviewed, genuinely redrawn key poses. Only the current encounter is leased.
## Existing idle/down artwork remains authoritative outside these actions.
const ROOT := "res://assets/runtime_web/action_frames/r1"
const BUDGET := 32 * 1024 * 1024
var actors: Dictionary = {}
var decoded_bytes := 0
var error := ""

func clear() -> void:
	actors.clear()
	decoded_bytes = 0
	error = ""

func warm(ids: Array[String], owner: Node) -> bool:
	clear()
	if not FileAccess.file_exists(ROOT + "/index.json"): return false
	var index = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/index.json"))
	if not index is Dictionary or str(index.get("status", "")) != "VISUAL_MOTION_REVIEW_PASS": return false
	for id in ids:
		var entry: Dictionary = index.get("actors", {}).get(id, {})
		if entry.is_empty(): continue
		if decoded_bytes + int(entry.get("decoded_bytes", 0)) > BUDGET:
			error = "ACTION_MEMORY_BUDGET"
			return false
		var manifest_path := ROOT + "/" + id + "/manifest.json"
		if FileAccess.get_sha256(manifest_path) != str(entry.get("manifest_sha256", "")):
			error = "ACTION_MANIFEST_HASH:" + id
			return false
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not parsed is Dictionary:
			error = "ACTION_MANIFEST_PARSE:" + id
			return false
		var manifest: Dictionary = parsed
		var pages := await DensityLoader.load_pages([{"path": ROOT + "/" + id + "/atlas.png", "sha256": str(entry.get("atlas_sha256", ""))}], owner)
		if pages.is_empty():
			error = "ACTION_ATLAS:" + id
			return false
		var states: Dictionary = {}
		for action in manifest.get("states", {}):
			var sequence: Array = []
			for raw in manifest.states[action]:
				var rect: Array = raw.rect
				var texture := AtlasTexture.new()
				texture.atlas = pages[0]
				texture.region = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
				if not Rect2(Vector2.ZERO, pages[0].get_size()).encloses(texture.region):
					error = "ACTION_RECT:" + id
					return false
				sequence.append({"texture": texture, "contacts": raw.contacts, "head": raw.head, "logical_rect": raw.logical_rect})
			if sequence.size() != 6:
				error = "ACTION_FRAME_COUNT:" + id
				return false
			states[action] = sequence
		actors[id] = states
		decoded_bytes += int(entry.get("decoded_bytes", 0))
	return not actors.is_empty()

func has_action(id: String, action: String) -> bool:
	return actors.has(id) and actors[id].has(action)

static func duration(action: String) -> float:
	return 2.10 if action == "ultimate" else (.94 if action == "normal_skill" else .78)

static func frame_index(action: String, elapsed: float, melee: bool) -> int:
	# Pose three is release. For guns it meets muzzle launch; for melee it meets
	# target contact. These markers share BattleView's actual effect timebase.
	var times: Array = [0.0, .10, .25, .43, .53, .66] if melee else [0.0, .04, .09, .14, .27, .56]
	if action == "ultimate":
		times = [0.0, .26, .64, 1.10 if melee else .82, 1.23, 1.70]
	var result := 0
	for i in range(times.size()):
		if elapsed >= float(times[i]): result = i
	return result

func sample(id: String, action: String, elapsed: float, melee: bool) -> Dictionary:
	if not has_action(id, action): return {}
	var result: Dictionary = actors[id][action][frame_index(action, elapsed, melee)].duplicate()
	result.frame_index = frame_index(action, elapsed, melee)
	return result

func snapshot() -> Dictionary:
	return {"entities": actors.keys(), "decoded_bytes": decoded_bytes, "budget": BUDGET, "error": error}
