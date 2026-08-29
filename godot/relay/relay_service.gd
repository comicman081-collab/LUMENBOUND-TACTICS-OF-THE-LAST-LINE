class_name RelayService
extends RefCounted

## The relay is deliberately a small, fully offline contract layer.  It never
## rewrites the canonical chapter-clear ledger: a relay segment borrows an
## existing battle definition, while its own run state owns squad locks,
## retries, completion and the exactly-once contract reward.

const SQUAD_COUNT := 3
const SQUAD_SIZE := 5

static func default_profile() -> Dictionary:
	return {
		"active_run": {},
		"completed_contracts": {},
		# Keep the new-profile schema already normalized.  Querying whether a
		# relay is active must be read-only; otherwise a stale result callback
		# could make an unrelated relay-only write while it is correctly refusing
		# to commit the battle transaction.
		"draft_squads": [["", "", "", "", ""], ["", "", "", "", ""], ["", "", "", "", ""]],
	}

static func ensure_profile(profile: Dictionary) -> void:
	if not profile.has("relay") or not (profile.get("relay") is Dictionary):
		profile["relay"] = default_profile()
	var relay: Dictionary = profile.relay
	if not relay.has("active_run") or not (relay.get("active_run") is Dictionary): relay["active_run"] = {}
	if not relay.has("completed_contracts") or not (relay.get("completed_contracts") is Dictionary): relay["completed_contracts"] = {}
	if not relay.has("draft_squads") or not (relay.get("draft_squads") is Array): relay["draft_squads"] = [[], [], []]
	while relay.draft_squads.size() < SQUAD_COUNT:
		relay.draft_squads.append([])
	if relay.draft_squads.size() > SQUAD_COUNT:
		relay.draft_squads = relay.draft_squads.slice(0, SQUAD_COUNT)
	for squad_index in range(SQUAD_COUNT):
		if not (relay.draft_squads[squad_index] is Array): relay.draft_squads[squad_index] = []
		relay.draft_squads[squad_index] = _normalized_squad(relay.draft_squads[squad_index])
	var active: Dictionary = relay.active_run
	if not active.is_empty():
		_normalize_active_run(active)

static func specs() -> Array:
	return DataRegistry.list_of("relay_specs")

static func spec(relay_id: String) -> Dictionary:
	for value in specs():
		var candidate: Dictionary = value
		if str(candidate.get("id", "")) == relay_id:
			return candidate.duplicate(true)
	return {}

static func first_spec() -> Dictionary:
	var all_specs := specs()
	return (all_specs[0] as Dictionary).duplicate(true) if not all_specs.is_empty() else {}

static func validate_specification(specification: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if str(specification.get("id", "")).is_empty(): errors.append("MISSING_ID")
	var stage_ids: Array = specification.get("stage_ids", [])
	if stage_ids.size() != SQUAD_COUNT:
		errors.append("REQUIRES_THREE_SEGMENTS")
	var seen: Dictionary = {}
	for stage_id_value in stage_ids:
		var stage_id := str(stage_id_value)
		if stage_id.is_empty() or DataRegistry.stage(stage_id).is_empty():
			errors.append("INVALID_STAGE:%s" % stage_id)
		elif seen.has(stage_id):
			errors.append("DUPLICATE_STAGE:%s" % stage_id)
		seen[stage_id] = true
	if not (specification.get("completion_rewards", {}) is Dictionary) or (specification.get("completion_rewards", {}) as Dictionary).is_empty():
		errors.append("MISSING_COMPLETION_REWARD")
	return errors

static func draft_squads(profile: Dictionary) -> Array:
	ensure_profile(profile)
	return profile.relay.draft_squads.duplicate(true)

static func set_draft_member(profile: Dictionary, squad_index: int, slot_index: int, character_id: String) -> bool:
	ensure_profile(profile)
	if squad_index < 0 or squad_index >= SQUAD_COUNT or slot_index < 0 or slot_index >= SQUAD_SIZE:
		return false
	if not _is_unlocked(profile, character_id):
		return false
	var squads: Array = profile.relay.draft_squads
	for index in range(SQUAD_COUNT):
		var squad: Array = _normalized_squad(squads[index])
		for member_index in range(squad.size()):
			if str(squad[member_index]) == character_id:
				squad[member_index] = ""
		squads[index] = squad
	var target: Array = _normalized_squad(squads[squad_index])
	target[slot_index] = character_id
	squads[squad_index] = target
	return true

static func autofill_draft(profile: Dictionary) -> bool:
	ensure_profile(profile)
	var unlocked := unlocked_character_ids(profile)
	if unlocked.size() < SQUAD_COUNT * SQUAD_SIZE:
		return false
	var squads: Array = [[], [], []]
	for squad_index in range(SQUAD_COUNT):
		for slot_index in range(SQUAD_SIZE):
			squads[squad_index].append(unlocked[squad_index * SQUAD_SIZE + slot_index])
	profile.relay.draft_squads = squads
	return true

static func unlocked_character_ids(profile: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for character_value in DataRegistry.list_of("characters"):
		var character: Dictionary = character_value
		var character_id := str(character.get("id", ""))
		if _is_unlocked(profile, character_id):
			result.append(character_id)
	return result

static func validate_squads(profile: Dictionary, squads_value: Array) -> Array[String]:
	var errors: Array[String] = []
	if squads_value.size() != SQUAD_COUNT:
		return ["REQUIRES_THREE_SQUADS"]
	var seen: Dictionary = {}
	for squad_index in range(SQUAD_COUNT):
		var squad: Array = squads_value[squad_index] if squads_value[squad_index] is Array else []
		if squad.size() != SQUAD_SIZE:
			errors.append("SQUAD_%d_REQUIRES_FIVE" % (squad_index + 1))
			continue
		for member_value in squad:
			var character_id := str(member_value)
			if not _is_unlocked(profile, character_id):
				errors.append("LOCKED_OR_EMPTY:%d" % (squad_index + 1))
			elif seen.has(character_id):
				errors.append("DUPLICATE_MEMBER:%s" % character_id)
			seen[character_id] = true
	return errors

static func active_run(profile: Dictionary) -> Dictionary:
	ensure_profile(profile)
	return (profile.relay.active_run as Dictionary).duplicate(true)

static func is_active(profile: Dictionary) -> bool:
	return not active_run(profile).is_empty()

static func start(profile: Dictionary, relay_id: String, seed_value: int) -> Dictionary:
	ensure_profile(profile)
	if not (profile.relay.active_run as Dictionary).is_empty():
		return {"ok": false, "error": "RUN_ALREADY_ACTIVE"}
	var specification := spec(relay_id)
	var spec_errors := validate_specification(specification)
	if not spec_errors.is_empty():
		return {"ok": false, "error": spec_errors[0]}
	var squads := draft_squads(profile)
	var squad_errors := validate_squads(profile, squads)
	if not squad_errors.is_empty():
		return {"ok": false, "error": squad_errors[0], "errors": squad_errors}
	profile.relay.active_run = {
		"relay_id": relay_id,
		"seed": seed_value,
		"squads": squads,
		"segment_index": 0,
		"segment_results": [],
		"started_at": int(Time.get_unix_time_from_system()),
	}
	return {"ok": true, "run": active_run(profile)}

static func cancel(profile: Dictionary) -> bool:
	ensure_profile(profile)
	if (profile.relay.active_run as Dictionary).is_empty():
		return false
	profile.relay.active_run = {}
	return true

static func current_stage_id(profile: Dictionary) -> String:
	var run := active_run(profile)
	if run.is_empty(): return ""
	var specification := spec(str(run.get("relay_id", "")))
	var stage_ids: Array = specification.get("stage_ids", [])
	var index := int(run.get("segment_index", 0))
	return str(stage_ids[index]) if index >= 0 and index < stage_ids.size() else ""

static func current_squad(profile: Dictionary) -> Array[String]:
	var run := active_run(profile)
	if run.is_empty(): return []
	var squads: Array = run.get("squads", [])
	var index := int(run.get("segment_index", 0))
	if index < 0 or index >= squads.size() or not (squads[index] is Array): return []
	var result: Array[String] = []
	for member_value in squads[index]: result.append(str(member_value))
	return result

static func record_segment_result(profile: Dictionary, result: Dictionary) -> Dictionary:
	ensure_profile(profile)
	var run: Dictionary = profile.relay.active_run
	if run.is_empty(): return {"ok": false, "error": "NO_ACTIVE_RUN"}
	_normalize_active_run(run)
	var stage_id := current_stage_id(profile)
	if stage_id.is_empty(): return {"ok": false, "error": "INVALID_ACTIVE_STAGE"}
	if not bool(result.get("victory", false)):
		return {"ok": true, "victory": false, "retry": true, "segment_index": int(run.segment_index)}
	var segment_result := {
		"stage_id": stage_id,
		"victory": true,
		"time": float(result.get("time", 0.0)),
		"survivors": int(result.get("survivors", 0)),
		"ticks": int(result.get("ticks", 0)),
		"event_hash": str(result.get("event_hash", "")),
	}
	run.segment_results.append(segment_result)
	var next_index := int(run.segment_index) + 1
	var specification := spec(str(run.relay_id))
	var stage_ids: Array = specification.get("stage_ids", [])
	if next_index < stage_ids.size():
		run.segment_index = next_index
		return {"ok": true, "victory": true, "advanced": true, "completed": false, "segment_index": next_index, "segment_result": segment_result}
	var grade := _grade_for(run.segment_results, specification)
	var relay_id := str(run.relay_id)
	var completed: Dictionary = profile.relay.completed_contracts
	var first_completion := not completed.has(relay_id)
	var rewards: Dictionary = {}
	if first_completion:
		rewards = RewardService.resolve_direct(specification.get("completion_rewards", {}))
	completed[relay_id] = {
		"best_grade": _better_grade(str(completed.get(relay_id, {}).get("best_grade", "")), grade),
		"completed_at": int(Time.get_unix_time_from_system()),
		"runs_completed": int(completed.get(relay_id, {}).get("runs_completed", 0)) + 1,
		"first_completion_claimed": true,
	}
	profile.relay.active_run = {}
	return {"ok": true, "victory": true, "advanced": false, "completed": true, "first_completion": first_completion, "grade": grade, "rewards": rewards, "segment_result": segment_result}

static func completion_summary(profile: Dictionary, relay_id: String) -> Dictionary:
	ensure_profile(profile)
	var value: Variant = profile.relay.completed_contracts.get(relay_id, {})
	return value.duplicate(true) if value is Dictionary else {}

static func _grade_for(results: Array, specification: Dictionary) -> String:
	var total_time := 0.0
	var total_survivors := 0
	for result_value in results:
		var result: Dictionary = result_value
		total_time += float(result.get("time", 0.0))
		total_survivors += int(result.get("survivors", 0))
	var s_time := float(specification.get("s_rank_time", 150.0))
	var a_time := float(specification.get("a_rank_time", 195.0))
	if total_survivors >= 13 and total_time <= s_time: return "S"
	if total_survivors >= 9 and total_time <= a_time: return "A"
	return "B"

static func _better_grade(previous: String, candidate: String) -> String:
	var weights := {"S": 3, "A": 2, "B": 1, "": 0}
	return candidate if int(weights.get(candidate, 0)) >= int(weights.get(previous, 0)) else previous

static func _normalized_squad(value: Variant) -> Array:
	var source: Array = value if value is Array else []
	var result: Array = []
	for index in range(SQUAD_SIZE):
		result.append(str(source[index]) if index < source.size() else "")
	return result

static func _is_unlocked(profile: Dictionary, character_id: String) -> bool:
	return not character_id.is_empty() and profile.get("roster", {}).has(character_id) and bool(profile.roster[character_id].get("unlocked", false))

static func _normalize_active_run(run: Dictionary) -> void:
	if not run.has("segment_index"): run["segment_index"] = 0
	if not run.has("segment_results") or not (run.get("segment_results") is Array): run["segment_results"] = []
	if not run.has("squads") or not (run.get("squads") is Array): run["squads"] = [[], [], []]
	while run.squads.size() < SQUAD_COUNT: run.squads.append([])
	if run.squads.size() > SQUAD_COUNT: run.squads = run.squads.slice(0, SQUAD_COUNT)
	for squad_index in range(SQUAD_COUNT): run.squads[squad_index] = _normalized_squad(run.squads[squad_index])
