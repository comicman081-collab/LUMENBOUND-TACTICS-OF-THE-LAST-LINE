extends Node

var current_screen := "TITLE"
var history: Array[String] = []

func go(screen_id: String, payload: Dictionary = {}) -> void:
	if current_screen != screen_id:
		history.append(current_screen)
	current_screen = screen_id
	AppState.route_payload = payload
	EventBus.screen_changed.emit(screen_id)

func back(fallback := "HOME") -> void:
	var next := fallback
	if not history.is_empty():
		next = history.pop_back()
	current_screen = next
	AppState.route_payload = {}
	EventBus.screen_changed.emit(next)

