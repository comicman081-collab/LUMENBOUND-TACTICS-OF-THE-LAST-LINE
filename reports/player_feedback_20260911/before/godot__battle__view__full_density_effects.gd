extends RefCounted

const Loader := preload("res://battle/view/density_texture_loader.gd")
const ROOT := "res://assets/runtime_web/full_density_effects/r1"
const BUDGET := 80 * 1024 * 1024
var projectiles: Dictionary = {}
var effects: Dictionary = {}
var resident_bytes := 0
var error := ""

func snapshot() -> Dictionary:
	return {"projectile_ids": projectiles.keys(), "effect_keys": effects.keys(), "decoded_rgba_bytes": resident_bytes, "budget_bytes": BUDGET, "error": error}

func warm(ids: Array[String], owner_node: Node) -> bool:
	if not (OS.is_debug_build() or OS.has_feature("lanternline_dev_tools")): return false
	var path := ROOT + "/index.json"
	if not FileAccess.file_exists(path): return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or str(parsed.get("status", "")) != "LOCAL_QA_ONLY": return false
	var tasks: Array = []
	var staged_projectiles: Dictionary = {}
	var staged_effects: Dictionary = {}
	var unique: Dictionary = {}
	var total := 0
	for id in ids:
		var projectile: Dictionary = parsed.get("projectiles", {}).get(id, {})
		if projectile.is_empty(): error = "HD_PROJECTILE_MISSING:%s" % id; return false
		tasks.append({"kind":"projectile", "key":id, "record":projectile})
		for kind in ["basic", "normal", "ultimate"]:
			var key := "%s_%s" % [id.to_lower(),kind]
			var record: Dictionary = parsed.get("vfx", {}).get(key, {})
			if record.is_empty(): error = "HD_EFFECT_MISSING:%s" % key; return false
			tasks.append({"kind":"vfx", "key":key, "record":record})
	for task in tasks:
		var filename := str(task.record.get("atlas_path", ""))
		if not unique.has(filename):
			total += int(task.record.get("decoded_rgba_bytes", 0))
			unique[filename] = true
	if total <= 0 or total > BUDGET: error = "HD_EFFECT_MEMORY:%d" % total; return false
	unique.clear()
	var page_requests: Array = []
	var seen_pages: Dictionary = {}
	for task in tasks:
		var filename := str(task.record.atlas_path)
		if seen_pages.has(filename): continue
		if not filename.begins_with("pages/") or ".." in filename: error="HD_EFFECT_UNSAFE_PATH"; return false
		seen_pages[filename] = true
		page_requests.append({"path":ROOT+"/"+filename,"sha256":str(task.record.atlas_sha256),"filename":filename})
	for offset in range(0,page_requests.size(),3):
		var group := page_requests.slice(offset,mini(offset+3,page_requests.size()))
		var pages := await Loader.load_pages(group,owner_node)
		if pages.size()!=group.size(): error="HD_EFFECT_BATCH"; return false
		for index in pages.size(): unique[group[index].filename] = pages[index]
	var slice_started := Time.get_ticks_usec()
	for task in tasks:
		if not is_instance_valid(owner_node) or not owner_node.is_inside_tree(): return false
		var record: Dictionary = task.record
		var filename := str(record.get("atlas_path", ""))
		if not filename.begins_with("pages/") or ".." in filename: error = "HD_EFFECT_UNSAFE_PATH"; return false
		var atlas: Texture2D = unique.get(filename)
		if atlas == null:
			atlas = await Loader.load_page(ROOT + "/" + filename, str(record.get("atlas_sha256", "")), owner_node)
			if atlas == null: error = "HD_EFFECT_PAGE:%s" % filename; return false
			unique[filename] = atlas
		var frames: Array[Texture2D] = []
		var cell := int(record.get("frame_size", 0))
		var columns := int(record.get("columns", 0))
		if cell not in [192,256] or columns not in [4,8]: error="HD_EFFECT_LAYOUT"; return false
		if int(record.get("frames", 0)) not in [8,12]: error="HD_EFFECT_COUNT"; return false
		for index in int(record.get("frames", 0)):
			var frame := AtlasTexture.new()
			frame.atlas = atlas
			frame.region = Rect2(float(index % columns * cell),float(index / columns * cell),cell,cell)
			if not Rect2(Vector2.ZERO, atlas.get_size()).encloses(frame.region): error="HD_EFFECT_BOUNDS"; return false
			frames.append(frame)
		if task.kind == "projectile": staged_projectiles[task.key] = frames
		else: staged_effects[task.key] = frames
		# Frame views do not decode/upload pixels. Yield by measured work instead
		# of adding 4 display frames per actor to every cached battle entry.
		if Time.get_ticks_usec() - slice_started >= 4000:
			await owner_node.get_tree().process_frame
			slice_started = Time.get_ticks_usec()
	projectiles = staged_projectiles
	effects = staged_effects
	resident_bytes = total
	error = ""
	return true

func projectile_at(id: String, progress: float) -> Texture2D:
	var frames: Array = projectiles.get(id, [])
	return frames[mini(frames.size()-1,int(clampf(progress,0,.999)*frames.size()))] if not frames.is_empty() else null

func ultimate_at(id: String, progress: float) -> Texture2D:
	var frames: Array = effects.get(id.to_lower()+"_ultimate", [])
	return frames[mini(frames.size()-1,int(clampf(progress,0,.999)*frames.size()))] if not frames.is_empty() else null
