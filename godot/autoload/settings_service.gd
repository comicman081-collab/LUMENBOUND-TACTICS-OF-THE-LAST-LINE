extends Node

var values := {
	"language": "ko",
	"audio_enabled": true,
	"master_volume": 0.8,
	"bgm_volume": 0.7,
	"sfx_volume": 0.8,
	"text_speed": 0.03,
	"auto_delay": 1.2,
	"developer_mode": false,
	"battle_auto": true,
	"battle_speed": 1,
	"map_camera_follow_strength": 0.72,
	"map_reduced_transition": false,
	"map_instant_focus": false
}

func _ready() -> void:
	_apply_developer_build_policy()

static func developer_mode_for_build(debug_build: bool) -> bool:
	# Developer tooling is a build capability, never a user-save preference.
	# A release export must remain unable to opt in through a modified save.
	return debug_build

static func developer_mode_for_capabilities(debug_build: bool, qa_feature: bool) -> bool:
	# The Web Development package uses the stable release Web template plus an
	# explicit compile-time feature.  This avoids depending on the much larger
	# debug Web template while keeping the public Release preset incapable of
	# enabling developer authority through save data or URL parameters.
	return developer_mode_for_build(debug_build) or qa_feature

func _build_has_developer_authority() -> bool:
	return developer_mode_for_capabilities(OS.is_debug_build(), OS.has_feature("lanternline_dev_tools"))

func is_developer_mode() -> bool:
	# Keep the build gate on every privileged read as defence in depth. Direct
	# Dictionary writes are convenient in headless tests, but cannot enable the
	# tools or progression bypass in a release binary.
	return _build_has_developer_authority() and bool(values.get("developer_mode", false))

func persisted_values() -> Dictionary:
	# Preserve the settings schema while keeping build-only authority out of the
	# normal save. Debug builds re-derive the effective value on startup/load.
	var persisted := values.duplicate(true)
	persisted["developer_mode"] = false
	return persisted

func apply_saved(saved: Dictionary) -> void:
	for key in saved:
		if key != "developer_mode" and values.has(key):
			values[key] = saved[key]
	_apply_developer_build_policy()
	EventBus.settings_changed.emit()

func set_value(key: String, value) -> void:
	if key == "developer_mode":
		values[key] = _build_has_developer_authority() and bool(value)
	else:
		values[key] = value
	EventBus.settings_changed.emit()

func _apply_developer_build_policy() -> void:
	values["developer_mode"] = _build_has_developer_authority()
