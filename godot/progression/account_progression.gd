class_name AccountProgression
extends RefCounted

static func grant_stage_xp(stamina_cost: int, first_clear_bonus := 0) -> void:
	var account: Dictionary = AppState.profile.account
	account.xp = int(account.xp) + stamina_cost * 5 + first_clear_bonus
	var curve: Array = DataRegistry.list_of("account_level_curve")
	while int(account.level) < 100:
		var needed := int(curve[int(account.level) - 1].xp_to_next)
		if int(account.xp) < needed: break
		account.xp = int(account.xp) - needed
		account.level = int(account.level) + 1

## The character level cap is min(account level, breakthrough cap), and stage
## EXP alone left the account about 40 levels under the operations'
## recommendations. A first clear lifts the account to the operation's
## recommended level plus a lead, so the next operation's recommended level is
## always reachable.
const FIRST_CLEAR_LEVEL_LEAD := 10

static func raise_for_first_clear(stage: Dictionary) -> void:
	var account: Dictionary = AppState.profile.account
	var floor_level := mini(100, int(stage.get("recommended_level", 1)) + FIRST_CLEAR_LEVEL_LEAD)
	if int(account.level) < floor_level:
		account.level = floor_level
		account.xp = 0

