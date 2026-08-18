class_name StatusEffectRuntime
extends RefCounted

static func apply(unit: Dictionary, status_id: String, duration: float, source_id: String, strength := 0.0) -> void:
	if status_id == "CLEANSE":
		cleanse(unit)
		return
	if status_id == "DISPEL":
		dispel(unit)
		return
	var definition := _definition(status_id)
	if definition.is_empty():
		return
	if duration <= 0.0:
		duration = float(definition.get("duration", 0.0))
	if unit.get("rank", "") == "BOSS":
		duration *= 1.0 - clampf(float(definition.get("boss_resistance", 0.0)), 0.0, 0.95)
	if duration <= 0.0:
		return
	var tick_interval := float(definition.get("tick_interval", 0.0))
	var max_stacks := maxi(1, int(definition.get("max_stacks", 1)))
	var stack_policy := str(definition.get("stack_policy", "REFRESH"))
	var current: Dictionary = unit.statuses.get(status_id, {})
	if current.is_empty():
		unit.statuses[status_id] = {"remaining": duration, "source": source_id, "strength": strength, "tick_left": tick_interval, "tick_interval": tick_interval, "stacks": 1, "dispellable": bool(definition.get("dispellable", true))}
	else:
		if stack_policy == "STACK":
			current.stacks = mini(max_stacks, int(current.get("stacks", 1)) + 1)
		elif stack_policy == "SOURCE_REFRESH" and str(current.get("source", "")) != source_id:
			current.stacks = mini(max_stacks, int(current.get("stacks", 1)) + 1)
		_refresh_duration(current, duration, str(definition.get("refresh_policy", "RESET_DURATION")))
		current.source = source_id
		current.strength = maxf(float(current.get("strength", 0)), strength)
		current.tick_interval = tick_interval
		if tick_interval > 0.0 and float(current.get("tick_left", 0.0)) <= 0.0:
			current.tick_left = tick_interval

static func remove(unit: Dictionary, status_id: String) -> void:
	unit.statuses.erase(status_id)

static func cleanse(unit: Dictionary) -> void:
	for status_id in unit.statuses.keys():
		var definition := _definition(str(status_id))
		if not definition.is_empty() and bool(definition.get("dispellable", true)) and _is_harmful(str(status_id)):
			unit.statuses.erase(status_id)

static func dispel(unit: Dictionary) -> void:
	for status_id in unit.statuses.keys():
		var definition := _definition(str(status_id))
		if not definition.is_empty() and bool(definition.get("dispellable", true)) and not _is_harmful(str(status_id)):
			unit.statuses.erase(status_id)

static func update(unit: Dictionary, delta: float) -> Array:
	var ticked: Array = []
	var expired: Array = []
	for status_id in unit.statuses:
		var status: Dictionary = unit.statuses[status_id]
		status.remaining = float(status.remaining) - delta
		if status_id in ["DAMAGE_OVER_TIME", "HEAL_OVER_TIME"]:
			status.tick_left = float(status.tick_left) - delta
			if float(status.tick_left) <= 0:
				var interval := maxf(0.01, float(status.get("tick_interval", 1.0)))
				status.tick_left = interval
				ticked.append({"id": status_id, "strength": float(status.strength) * int(status.get("stacks", 1)), "source": status.source})
		if float(status.remaining) <= 0:
			expired.append(status_id)
	for status_id in expired:
		unit.statuses.erase(status_id)
	return ticked

static func _definition(status_id: String) -> Dictionary:
	for definition in DataRegistry.list_of("status_effects"):
		if str(definition.get("id", "")) == status_id:
			return definition
	return {}

static func _refresh_duration(current: Dictionary, duration: float, policy: String) -> void:
	match policy:
		"KEEP_LONGER": current.remaining = maxf(float(current.get("remaining", 0.0)), duration)
		"EXTEND_TO_MAX": current.remaining = minf(duration, float(current.get("remaining", 0.0)) + duration)
		"NONE": pass
		_: current.remaining = duration

static func _is_harmful(status_id: String) -> bool:
	return status_id in ["STUN", "SILENCE", "SLOW", "TAUNT", "DEF_DOWN", "ATK_DOWN", "DAMAGE_OVER_TIME"]
