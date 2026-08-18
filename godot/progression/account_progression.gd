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

