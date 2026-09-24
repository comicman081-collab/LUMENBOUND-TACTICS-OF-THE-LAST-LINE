extends RefCounted

const Integrity := preload("res://battle/view/runtime_texture_integrity.gd")

# Share verified backing textures across map/battle transitions. Weak entries
# also reuse pages still owned by a live scene; only the bounded LRU retains
# resources after that scene exits. A failed/hash-mismatched page is never kept.
const CACHE_BUDGET_BYTES := 64 * 1024 * 1024
const COMPACT_PAGE_BYTES := 4 * 1024 * 1024
# Web's main-thread HTTP client drains one chunk per poll. The default 64 KiB
# adds dozens of display-frame waits to a 3 MiB atlas even on localhost.
# Keep the three-request/12 MiB-body bounds and one decoded page per frame.
const HTTP_READ_CHUNK_BYTES := 1024 * 1024
static var _live_pages: Dictionary = {}
static var _retained_pages: Dictionary = {}
static var _retained_bytes := 0
static var _cache_hits := 0
static var _cache_misses := 0
static var _timing := {"batches": 0, "pages": 0, "response_wait_usec": 0, "hash_usec": 0, "decode_usec": 0, "upload_usec": 0, "batch_usec": 0}

static func cache_snapshot() -> Dictionary:
	return {"hits": _cache_hits, "misses": _cache_misses, "retained_bytes": _retained_bytes,
		"budget_bytes": CACHE_BUDGET_BYTES, "retained_pages": _retained_pages.size(), "timing": _timing.duplicate()}

static func clear_cache() -> void:
	_live_pages.clear()
	_retained_pages.clear()
	_retained_bytes = 0
	_cache_hits = 0
	_cache_misses = 0
	for key in _timing: _timing[key] = 0

static func _page_key(path: String, digest: String) -> String:
	var relative := path.trim_prefix("res://assets/runtime_web/")
	if relative == path or ".." in relative or digest.length() != 64: return ""
	if not _approved_family(relative): return ""
	if not digest.is_valid_hex_number(false): return ""
	return path + ":" + digest

static func _approved_family(relative: String) -> bool:
	return relative.begins_with("full_density/") or relative.begins_with("full_density_effects/") or relative.begins_with("map_density/") or relative.begins_with("action_frames/r1/")

static func can_stream_companion_pages() -> bool:
	# High-density pages live beside the Web export so the initial PCK stays
	# bounded.  They are a same-origin HTTP(S) optimization, never a requirement
	# for opening the local file handoff: file:// cannot make this request, so map
	# and battle take their already-packaged compact fallback immediately.
	if not OS.has_feature("web"):
		return false
	var protocol := str(JavaScriptBridge.eval("location.protocol", true))
	return protocol in ["http:", "https:"]

static func _cached_page(key: String) -> Texture2D:
	var reference: WeakRef = _live_pages.get(key)
	var texture: Texture2D = reference.get_ref() as Texture2D if reference != null else null
	if texture == null:
		_live_pages.erase(key)
		return null
	_remember_page(key, texture)
	return texture

static func _remember_page(key: String, texture: Texture2D) -> void:
	var bytes := int(texture.get_width()) * int(texture.get_height()) * 4
	if _retained_pages.has(key):
		_retained_bytes -= int(_retained_pages[key].bytes)
		_retained_pages.erase(key)
	_live_pages[key] = weakref(texture)
	if bytes > CACHE_BUDGET_BYTES: return
	# A battle scans more actor RGBA data than this retention budget. Plain LRU
	# lets that one-way scan evict every reusable effect before effects load,
	# causing zero hits on the next battle. Keep compact pages ahead of large
	# streaming atlases, with recency deciding within each class.
	var compact := bytes <= COMPACT_PAGE_BYTES
	while _retained_bytes + bytes > CACHE_BUDGET_BYTES and not _retained_pages.is_empty():
		var victim := ""
		for candidate: String in _retained_pages:
			if int(_retained_pages[candidate].bytes) > COMPACT_PAGE_BYTES:
				victim = candidate
				break
		if victim.is_empty():
			if not compact: return
			victim = str(_retained_pages.keys()[0])
		_retained_bytes -= int(_retained_pages[victim].bytes)
		_retained_pages.erase(victim)
	_retained_pages[key] = {"texture": texture, "bytes": bytes}
	_retained_bytes += bytes
	if _live_pages.size() > 2048:
		for candidate in _live_pages.keys():
			if _live_pages[candidate].get_ref() == null: _live_pages.erase(candidate)

static func load_pages(records: Array, owner_node: Node) -> Array[Texture2D]:
	if records.is_empty() or records.size() > 3: return []
	if not is_instance_valid(owner_node) or not owner_node.is_inside_tree(): return []
	var keys: Array[String] = []
	for record in records:
		var key := _page_key(str(record.get("path", "")), str(record.get("sha256", "")))
		if key.is_empty(): return []
		keys.append(key)
	var result: Array[Texture2D] = []
	result.resize(records.size())
	var missing: Array = []
	var slots: Array[int] = []
	for index in records.size():
		result[index] = _cached_page(keys[index])
		if result[index] == null:
			missing.append(records[index])
			slots.append(index)
			_cache_misses += 1
		else:
			_cache_hits += 1
	if not missing.is_empty():
		var loaded := await _load_pages_uncached(missing, owner_node)
		if loaded.size() != missing.size(): return []
		if not is_instance_valid(owner_node) or not owner_node.is_inside_tree(): return []
		for index in slots.size():
			result[slots[index]] = loaded[index]
			_remember_page(keys[slots[index]], loaded[index])
	return result

static func load_page(path: String, expected_sha256: String, owner_node: Node) -> Texture2D:
	var pages := await load_pages([{"path": path, "sha256": expected_sha256}], owner_node)
	return pages[0] if pages.size() == 1 else null

static func _load_pages_uncached(records: Array, owner_node: Node) -> Array[Texture2D]:
	# A bounded batch amortizes browser HTTP polling without downloading the
	# entire roster or decoding several large images in the same draw frame.
	var textures: Array[Texture2D] = []
	if records.is_empty() or records.size() > 3: return textures
	if not OS.has_feature("web"):
		for record in records:
			var texture := await _load_page_uncached(str(record.path), str(record.sha256), owner_node)
			if texture == null: return []
			textures.append(texture)
		return textures
	if not can_stream_companion_pages():
		return textures
	if not is_instance_valid(owner_node) or not owner_node.is_inside_tree(): return textures
	var requests: Array[HTTPRequest] = []
	var batch_started := Time.get_ticks_usec()
	var state := {"responses": {}}
	var relatives: Array[String] = []
	for index in records.size():
		var record: Dictionary = records[index]
		var relative := str(record.path).trim_prefix("res://assets/runtime_web/")
		if ".." in relative or not _approved_family(relative) or str(record.sha256).length()!=64:
			_cancel_requests(requests)
			return []
		relatives.append(relative)
		var request := HTTPRequest.new()
		request.timeout = 30.0
		request.body_size_limit = 12 * 1024 * 1024
		request.download_chunk_size = HTTP_READ_CHUNK_BYTES
		owner_node.add_child(request)
		requests.append(request)
		request.request_completed.connect(func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
			state.responses[index] = [result,code,headers,body,Time.get_ticks_usec()], CONNECT_ONE_SHOT)
		var url := str(JavaScriptBridge.eval("new URL('./_hd/' + " + JSON.stringify(relative) + ", location.href).href",true))
		if request.request(url) != OK:
			_cancel_requests(requests)
			return []
	textures.resize(records.size())
	var completed := 0
	while completed < records.size():
		if not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
			_cancel_requests(requests)
			return []
		for index in records.size():
			if textures[index] != null or not state.responses.has(index): continue
			var result: Array = state.responses[index]
			if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
				_cancel_requests(requests)
				return []
			var body: PackedByteArray = result[3]
			_timing.response_wait_usec += int(result[4]) - batch_started
			var hash_started := Time.get_ticks_usec()
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(body)
			var matches := hash.finish().hex_encode() == str(records[index].sha256)
			_timing.hash_usec += Time.get_ticks_usec() - hash_started
			if not matches:
				_cancel_requests(requests)
				return []
			var decoded := Image.new()
			var decode_started := Time.get_ticks_usec()
			var decode_error := decoded.load_png_from_buffer(body)
			_timing.decode_usec += Time.get_ticks_usec() - decode_started
			if decode_error != OK or decoded.get_width()>2048 or decoded.get_height()>2048:
				_cancel_requests(requests)
				return []
			var upload_started := Time.get_ticks_usec()
			textures[index] = ImageTexture.create_from_image(decoded)
			_timing.upload_usec += Time.get_ticks_usec() - upload_started
			_timing.pages += 1
			state.responses.erase(index)
			completed += 1
			if owner_node.has_method("_density_page_ready"): owner_node.call("_density_page_ready",relatives[index])
			break # one decoded/uploaded page per frame, even when all replies arrive
		await owner_node.get_tree().process_frame
	_cancel_requests(requests)
	_timing.batches += 1
	_timing.batch_usec += Time.get_ticks_usec() - batch_started
	return textures

static func _cancel_requests(requests: Array[HTTPRequest]) -> void:
	for request in requests:
		if is_instance_valid(request):
			request.cancel_request()
			request.queue_free()

static func _load_page_uncached(path: String, expected_sha256: String, owner_node: Node) -> Texture2D:
	if expected_sha256.length() != 64: return null
	if not OS.has_feature("web"):
		if not Integrity.matches(path, expected_sha256): return null
		if ResourceLoader.exists(path): return load(path) as Texture2D
		var local_image := Image.load_from_file(path)
		return ImageTexture.create_from_image(local_image) if local_image != null else null
	if not can_stream_companion_pages():
		return null
	# HD pages are separately fetched at the explicit battle loading boundary.
	# Shipping all 109 actors + 327 effects in the startup PCK adds 326 MiB and
	# defeats mobile memory/loading goals. Only current-stage pages are requested.
	var relative := path.trim_prefix("res://assets/runtime_web/")
	if relative == path or ".." in relative or not _approved_family(relative): return null
	if not is_instance_valid(owner_node) or not owner_node.is_inside_tree(): return null
	var url := str(JavaScriptBridge.eval("new URL('./_hd/' + " + JSON.stringify(relative) + ", location.href).href", true))
	var request := HTTPRequest.new()
	request.timeout = 30.0
	request.body_size_limit = 12 * 1024 * 1024
	request.download_chunk_size = HTTP_READ_CHUNK_BYTES
	owner_node.add_child(request)
	if request.request(url) != OK:
		request.queue_free()
		return null
	var result: Array = await request.request_completed
	request.queue_free()
	if result.size() != 4 or int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200: return null
	var body: PackedByteArray = result[3]
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(body)
	if hash.finish().hex_encode() != expected_sha256: return null
	var image := Image.new()
	if image.load_png_from_buffer(body) != OK or image.get_width() > 2048 or image.get_height() > 2048: return null
	var texture := ImageTexture.create_from_image(image)
	# A completed, hash-verified page is real progress. Whole-family labels can
	# otherwise remain unchanged for >12 seconds and trip the idle watchdog even
	# while the next actor's pages are steadily arriving.
	if is_instance_valid(owner_node) and owner_node.has_method("_density_page_ready"):
		owner_node.call("_density_page_ready", relative)
	return texture
