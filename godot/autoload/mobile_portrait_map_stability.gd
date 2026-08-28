extends Node

# The portrait V2 pass intentionally runs late, but ChapterMapScreen can also
# re-apply its own responsive geometry after map refresh/resizes. On phones this
# made the top status strip and `next encounter` button alternate between two Y
# positions. Keep V2 authoritative while the map is open without re-running the
# whole layout every frame.

const REFRESH_INTERVAL := 0.10
const SIZE_EPSILON := 1.0

var _portrait_hotfix: Node
var _shell: Control
var _refresh_left := 0.0
var _map_mode := false
var _last_map_instance_id := 0
var _last_runtime_size := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# ChapterMapScreen uses the default priority and MobilePortraitHotfix V2 uses
	# 2000. This final presentation lock must run after both.
	process_priority = 3000
	print("LUMENBOUND_MOBILE_MAP_STABILITY_READY")
	call_deferred("_refresh_refs")

func _exit_tree() -> void:
	_release_v2_process()

func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_INTERVAL
		_refresh_refs()

	if _portrait_hotfix == null or not is_instance_valid(_portrait_hotfix):
		return
	if _shell == null or not is_instance_valid(_shell):
		return

	var runtime_value = _portrait_hotfix.call("_runtime_size")
	if not runtime_value is Vector2:
		_release_map_mode()
		return
	var runtime_size := runtime_value as Vector2
	var screen := str(_shell.get("current_screen"))
	var wants_map_lock := runtime_size.y > runtime_size.x and screen in ["STAGE_SELECT", "STAGE_DETAIL"]
	if not wants_map_lock:
		_release_map_mode()
		return

	var map_value = _shell.get("active_chapter_map_screen")
	if not map_value is Control or not is_instance_valid(map_value):
		return
	var map_screen := map_value as Control
	var instance_id := map_screen.get_instance_id()
	var size_changed := absf(runtime_size.x - _last_runtime_size.x) > SIZE_EPSILON or absf(runtime_size.y - _last_runtime_size.y) > SIZE_EPSILON
	var new_map := not _map_mode or instance_id != _last_map_instance_id

	# Stop V2's 10 Hz full-map probe while this screen is active. The stability
	# layer applies that same full layout once on entry/real viewport change, then
	# only locks the two top overlay controls after ChapterMapScreen each frame.
	if _portrait_hotfix.is_processing():
		_portrait_hotfix.set_process(false)
	if new_map or size_changed:
		_portrait_hotfix.call("_fix_map", runtime_size)
		_last_map_instance_id = instance_id
		_last_runtime_size = runtime_size
		if new_map:
			print("LUMENBOUND_MOBILE_MAP_STABILITY_LOCKED size=%sx%s" % [roundi(runtime_size.x), roundi(runtime_size.y)])

	_portrait_hotfix.call("_fix_map_overlay", map_screen, runtime_size)
	_map_mode = true

func _refresh_refs() -> void:
	if _portrait_hotfix == null or not is_instance_valid(_portrait_hotfix):
		_portrait_hotfix = get_node_or_null("/root/MobilePortraitHotfix")
	if _shell == null or not is_instance_valid(_shell):
		_shell = _find_shell(get_tree().root)

func _find_shell(node: Node) -> Control:
	if node is Control and node.has_method("responsive_ui_metrics_for_size") and node.has_method("_show_chapter_map"):
		return node as Control
	for child in node.get_children():
		if child is SubViewport:
			continue
		var found := _find_shell(child)
		if found != null:
			return found
	return null

func _release_map_mode() -> void:
	if not _map_mode:
		_release_v2_process()
		return
	_map_mode = false
	_last_map_instance_id = 0
	_last_runtime_size = Vector2.ZERO
	_release_v2_process()

func _release_v2_process() -> void:
	if _portrait_hotfix != null and is_instance_valid(_portrait_hotfix) and not _portrait_hotfix.is_processing():
		_portrait_hotfix.set_process(true)
