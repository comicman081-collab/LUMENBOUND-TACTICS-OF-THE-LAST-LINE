class_name RewardService
extends RefCounted

static func resolve(stage_id: String, count: int, seed: int, include_first_clear: bool) -> Dictionary:
	var stage := DataRegistry.stage(stage_id)
	var table: Dictionary = {}
	for row in DataRegistry.list_of("rewards"):
		if row.id == stage.reward_table_id:
			table = row
			break
	var rng := DeterministicRng.new(seed)
	var total: Dictionary = {}
	for run in range(count):
		for guaranteed in table.get("guaranteed", []):
			var quantity := rng.randi_range(int(guaranteed.get("min", 1)), int(guaranteed.get("max", 1)))
			total[guaranteed.item_id] = int(total.get(guaranteed.item_id, 0)) + quantity
		for bonus in table.get("bonus", []):
			var pity_key := "%s:%s" % [stage_id, bonus.item_id]
			var failures := int(AppState.profile.reward_pity_counters.get(pity_key, 0))
			var guaranteed_by_pity := int(bonus.get("pity_after_failures", 0)) > 0 and failures >= int(bonus.pity_after_failures)
			if guaranteed_by_pity or rng.randf() < float(bonus.chance):
				total[bonus.item_id] = int(total.get(bonus.item_id, 0)) + int(bonus.quantity)
				AppState.profile.reward_pity_counters[pity_key] = 0
			else:
				AppState.profile.reward_pity_counters[pity_key] = failures + 1
	if include_first_clear:
		for item in table.get("first_clear", []):
			total[item.item_id] = int(total.get(item.item_id, 0)) + int(item.quantity)
	InventoryService.grant(total)
	return total

static func sweep(stage_id: String, count: int, seed: int) -> GameResult:
	if count not in [1, 5, 10]: return GameResult.failure("INVALID_SWEEP_COUNT")
	if int(AppState.profile.stage_stars.get(stage_id, 0)) < 3: return GameResult.failure("REQUIRES_THREE_STARS")
	var stage := DataRegistry.stage(stage_id)
	if not AppState.consume_stage_entries(stage_id, count): return GameResult.failure("INSUFFICIENT_STAGE_ENTRIES")
	var rewards := resolve(stage_id, count, seed, false)
	AccountProgression.grant_stage_xp(int(stage.stamina_cost) * count)
	return GameResult.success(rewards)
