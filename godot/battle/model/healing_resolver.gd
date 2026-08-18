class_name HealingResolver
extends RefCounted

static func calculate(caster: Dictionary, coefficient: float, rng: DeterministicRng) -> int:
	var variance := rng.rangef(0.97, 1.03)
	return maxi(1, MathUtil.round_half_up(float(caster.stats.get("HEAL_POWER", 1)) * coefficient * variance * float(caster.get("healing_done_modifier", 1.0))))

