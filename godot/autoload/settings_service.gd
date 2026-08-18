extends Node

var values := {
	"language": "ko",
	"audio_enabled": false,
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

func apply_saved(saved: Dictionary) -> void:
	for key in saved:
		if values.has(key):
			values[key] = saved[key]
	EventBus.settings_changed.emit()

func set_value(key: String, value) -> void:
	values[key] = value
	EventBus.settings_changed.emit()
