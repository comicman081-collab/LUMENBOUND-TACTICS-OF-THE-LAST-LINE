class_name DamageResolver
extends RefCounted

static func calculate(attacker: Dictionary, defender: Dictionary, coefficient: float, affinity_matrix: Dictionary, rng: DeterministicRng) -> Dictionary:
	var attacker_stats: Dictionary = attacker.stats
	var defender_stats: Dictionary = defender.stats
	var hit_chance := clampf(0.80 + (float(attacker_stats.get("ACC", 0)) - float(defender_stats.get("EVA", 0))) / 1000.0, 0.20, 0.99)
	if rng.randf() > hit_chance:
		return {"hit": false, "crit": false, "amount": 0, "hit_chance": hit_chance}
	var defense_factor := 700.0 / (700.0 + maxf(0.0, float(defender_stats.get("DEF", 0))))
	if UnitState.has_status(defender, "DEF_DOWN"):
		defense_factor = 700.0 / (700.0 + maxf(0.0, float(defender_stats.get("DEF", 0)) * 0.75))
	var level_factor := clampf(1.0 + 0.0125 * (int(attacker.level) - int(defender.level)), 0.70, 1.30)
	var crit_chance := clampf(0.05 + (float(attacker_stats.get("CRIT", 0)) - float(defender_stats.get("CRIT_RES", 0))) / 1200.0, 0.05, 0.60)
	var critical := rng.randf() < crit_chance
	var critical_factor := 1.5 if critical else 1.0
	var affinity := float(affinity_matrix.get(attacker.attack_type, {}).get(defender.defense_type, 1.0))
	var variance := rng.rangef(0.97, 1.03)
	var outgoing := float(attacker.get("outgoing_modifier", 1.0))
	var incoming := float(defender.get("incoming_modifier", 1.0))
	if UnitState.has_status(attacker, "ATK_DOWN"):
		outgoing *= 0.78
	var amount := maxi(1, MathUtil.round_half_up(float(attacker_stats.get("ATK", 1)) * coefficient * defense_factor * level_factor * affinity * critical_factor * variance * outgoing * incoming))
	return {"hit": true, "crit": critical, "amount": amount, "hit_chance": hit_chance, "crit_chance": crit_chance, "defense_factor": defense_factor, "level_factor": level_factor, "affinity_factor": affinity, "random_variance": variance}

