extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	if DataRegistry.load_error != "": failures.append(DataRegistry.load_error)
	_validate_unique("characters")
	_validate_unique("skills")
	_validate_unique("weapons")
	_validate_unique("stages")
	if DataRegistry.list_of("character_level_curve").size() != 100: failures.append("character curve rows")
	if DataRegistry.list_of("account_level_curve").size() != 100: failures.append("account curve rows")
	if DataRegistry.list_of("weapon_level_curve").size() != 60: failures.append("weapon curve rows")
	for skill in DataRegistry.list_of("skills"):
		var expected := 5 if skill.type == "ULTIMATE_SKILL" else 10
		if skill.values.size() != expected: failures.append("skill array: " + skill.id)
	for scenario in DataRegistry.list_of("scenarios"):
		failures.append_array(ScenarioParser.validate(scenario))
	print("VALIDATE_ALL failures=", failures.size())
	if not failures.is_empty(): printerr(JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

func _validate_unique(collection: String) -> void:
	var seen: Dictionary = {}
	for row in DataRegistry.list_of(collection):
		if seen.has(row.id): failures.append("duplicate %s:%s" % [collection, row.id])
		seen[row.id] = true

