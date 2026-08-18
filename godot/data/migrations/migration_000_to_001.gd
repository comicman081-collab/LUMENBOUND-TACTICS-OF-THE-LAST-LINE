extends RefCounted

static func apply(data: Dictionary) -> Dictionary:
	data["save_schema_version"] = 1
	return data
