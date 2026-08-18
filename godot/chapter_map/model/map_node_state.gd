class_name MapNodeState
extends RefCounted

enum State { HIDDEN, REVEALED_LOCKED, REACHABLE, VISITED, CLEARED, THREE_STAR }

static func from_stage(stage_id: String, revealed: bool) -> State:
	if not revealed: return State.HIDDEN
	if not AppState.is_stage_unlocked(stage_id): return State.REVEALED_LOCKED
	var stars := int(AppState.profile.stage_stars.get(stage_id, 0))
	if stars == 3: return State.THREE_STAR
	if stars > 0: return State.CLEARED
	return State.REACHABLE
