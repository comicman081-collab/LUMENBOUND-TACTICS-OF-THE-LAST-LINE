extends ScrollContainer

# Observe touch before nested panels/buttons consume GUI propagation. A tap
# stays on the normal Godot button path; only a deliberate vertical drag owns
# scrolling. The native scroll notification cancels a pressed child button.
var _finger := -1
var _origin := Vector2.ZERO
var _initial_scroll := 0
var _dragging := false
var last_gesture_was_drag := false

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_finger = -1
		_dragging = false
		return
	if event is InputEventScreenTouch:
		if event.pressed and _finger == -1 and get_global_rect().has_point(event.position):
			# Leave the actual scroll rail to the engine's own grabber handling.
			if get_v_scroll_bar().get_global_rect().has_point(event.position): return
			_finger = event.index
			_origin = event.position
			_initial_scroll = scroll_vertical
			_dragging = false
			last_gesture_was_drag = false
		elif not event.pressed and event.index == _finger:
			if _dragging:
				propagate_notification(Control.NOTIFICATION_SCROLL_END)
			_finger = -1
			_dragging = false
	elif event is InputEventScreenDrag and event.index == _finger:
		var distance: Vector2 = event.position - _origin
		if not _dragging and absf(distance.y) > maxf(float(scroll_deadzone), 1.0) and absf(distance.y) > absf(distance.x):
			_dragging = true
			last_gesture_was_drag = true
			propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
			var focused := get_viewport().gui_get_focus_owner()
			if focused != null and is_ancestor_of(focused): focused.release_focus()
		if _dragging:
			scroll_vertical = maxi(0, _initial_scroll - roundi(distance.y))
			get_viewport().set_input_as_handled()
