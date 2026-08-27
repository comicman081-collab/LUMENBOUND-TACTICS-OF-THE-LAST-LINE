extends Node

var current_screen := "TITLE"
var history: Array[String] = []

static func screen_allowed(screen_id: String, developer_mode: bool) -> bool:
	return screen_id != "DEBUG" or developer_mode

func go(screen_id: String, payload: Dictionary = {}) -> void:
	var target_screen := screen_id if screen_allowed(screen_id, SettingsService.is_developer_mode()) else "HOME"
	var target_payload := payload if target_screen == screen_id else {}
	if current_screen != target_screen:
		history.append(current_screen)
	current_screen = target_screen
	AppState.route_payload = target_payload
	EventBus.screen_changed.emit(target_screen)

func back(fallback := "HOME") -> void:
	var next := fallback
	if not history.is_empty():
		next = history.pop_back()
	if not screen_allowed(next, SettingsService.is_developer_mode()):
		next = fallback if screen_allowed(fallback, SettingsService.is_developer_mode()) else "HOME"
	current_screen = next
	AppState.route_payload = {}
	EventBus.screen_changed.emit(next)
