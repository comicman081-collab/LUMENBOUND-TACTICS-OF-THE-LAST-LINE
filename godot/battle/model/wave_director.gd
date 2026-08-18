class_name WaveDirector
extends RefCounted

var waves: Array = []
var current_index := -1

func setup(stage_waves: Array) -> void:
	waves = stage_waves.duplicate(true)
	current_index = -1

func has_next() -> bool:
	return current_index + 1 < waves.size()

func next_wave() -> Array:
	current_index += 1
	return waves[current_index] if current_index < waves.size() else []

