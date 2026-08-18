class_name BreakthroughService
extends RefCounted

static func next_cost(character_id: String) -> Dictionary:
	var current := int(AppState.profile.roster[character_id].breakthrough)
	if current >= 5:
		return {}
	return DataRegistry.list_of("breakthroughs")[current + 1].cost

static func upgrade(character_id: String) -> GameResult:
	var state: Dictionary = AppState.profile.roster[character_id]
	var current := int(state.breakthrough)
	if current >= 5:
		return GameResult.failure("MAX_BREAKTHROUGH")
	var target: Dictionary = DataRegistry.list_of("breakthroughs")[current + 1]
	var current_cap: int = int([20, 40, 60, 80, 90, 100][current])
	if int(state.level) < current_cap:
		return GameResult.failure("REQUIRES_LEVEL_%d" % current_cap)
	if not AppState.pay(target.cost):
		return GameResult.failure("INSUFFICIENT_MATERIALS")
	state.breakthrough = current + 1
	if int(state.breakthrough) >= 3 and not state.profile_unlocks.has("EXTRA_PROFILE"):
		state.profile_unlocks.append("EXTRA_PROFILE")
	if int(state.breakthrough) >= 5 and not state.profile_unlocks.has("VICTORY_FRAME"):
		state.profile_unlocks.append("VICTORY_FRAME")
	return GameResult.success(state.breakthrough)
