class_name MathUtil
extends RefCounted

static func round_half_up(value: float) -> int:
	return int(floor(value + 0.5))

static func round_to_step(value: float, step: int) -> int:
	return int(floor(value / float(step) + 0.5)) * step

static func abbreviated(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (value / 1000.0)
	return str(value)

static func comma(value: int) -> String:
	var raw := str(value)
	var out := ""
	while raw.length() > 3:
		out = "," + raw.right(3) + out
		raw = raw.left(raw.length() - 3)
	return raw + out

