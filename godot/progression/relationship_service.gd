class_name RelationshipService
extends RefCounted

static func grant(character_id: String, amount: int) -> void:
	var state: Dictionary = AppState.profile.roster[character_id]
	state.relationship_xp = int(state.relationship_xp) + amount
	while int(state.relationship_level) < 20 and int(state.relationship_xp) >= int(state.relationship_level) * 100:
		state.relationship_xp -= int(state.relationship_level) * 100
		state.relationship_level += 1

