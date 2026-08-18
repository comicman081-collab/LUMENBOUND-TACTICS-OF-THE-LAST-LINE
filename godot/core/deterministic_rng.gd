class_name DeterministicRng
extends RefCounted

var _state: int

func _init(seed_value: int = 1) -> void:
	_state = seed_value & 0x7fffffff
	if _state == 0:
		_state = 1

func next_u32() -> int:
	# Park-Miller LCG avoids platform-dependent RandomNumberGenerator details.
	_state = int((_state * 48271) % 2147483647)
	return _state

func randf() -> float:
	return float(next_u32()) / 2147483647.0

func rangef(minimum: float, maximum: float) -> float:
	# Qualify the call: an unqualified randf() resolves to Godot's global RNG.
	return minimum + (maximum - minimum) * self.randf()

func randi_range(minimum: int, maximum: int) -> int:
	return minimum + int(next_u32() % (maximum - minimum + 1))

func snapshot() -> int:
	return _state
