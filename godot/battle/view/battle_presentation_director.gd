## View-only timeline controller for cinematic battle presentation.
##
## BattleSimulation remains authoritative: this class only schedules visual
## markers and never writes to a simulation, RNG, event log, or Engine time.
extends RefCounted

const ULTIMATE_DURATION := 2.10
const CUTIN_START := 0.12
const CUTIN_PEAK := 0.22
const BATTLEFIELD_PREP := 0.58
const IMPACT_COMMIT := 1.12
const HITSTOP_DURATION := 0.08
const RECOVERY_START := 1.20
const COMBAT_IMPULSE_DURATION := 0.18
## A short directional pan makes an attack read as a shared camera move rather
## than a static sprite lunge.  It remains deliberately smaller than the
## presentation-safe mobile edge margin, and never changes simulation time.
const COMBAT_FOCUS_MIN_DURATION := 0.20
const COMBAT_FOCUS_MAX_OFFSET_X := 22.0

var active_batch: Dictionary = {}
var elapsed := 0.0
var impact_committed := false
var prep_fired := false
var finished := false
var hitstop_remaining := 0.0
var presentation_clock := 0.0
var combat_impulse_remaining := 0.0
var combat_impulse_strength := 0.0
var combat_focus_direction := 0.0
var combat_focus_strength := 0.0
var combat_focus_elapsed := 0.0
var combat_focus_duration := 0.0

func begin_ultimate(batch: Dictionary) -> bool:
	if is_active() or batch.is_empty():
		return false
	active_batch = batch.duplicate(true)
	elapsed = 0.0
	impact_committed = false
	prep_fired = false
	finished = false
	hitstop_remaining = 0.0
	return true

func is_active() -> bool:
	return not active_batch.is_empty() and not finished

func is_impact_committed() -> bool:
	return impact_committed

func request_combat_impact(strength := 0.5) -> void:
	## Normal attacks and ordinary hit reactions may move the camera, but never
	## through Engine time scale or the simulation clock. The strongest impulse
	## wins so a multi-hit frame remains readable instead of accumulating shake.
	var safe_strength := clampf(float(strength), 0.0, 1.0)
	if safe_strength <= 0.0:
		return
	combat_impulse_strength = maxf(combat_impulse_strength, safe_strength)
	combat_impulse_remaining = maxf(combat_impulse_remaining, COMBAT_IMPULSE_DURATION * (.72 + safe_strength * .28))


func request_combat_focus(world_direction: float, strength := 0.5, duration := 0.42) -> void:
	## `world_direction` is source→target along the battlefield X axis.  A
	## positive attack therefore shifts the world left to settle the target toward
	## center; the inverse applies to an enemy attacking left.  This owns no
	## Camera2D and remains deterministic presentation-only state.
	if is_zero_approx(world_direction):
		return
	var safe_strength := clampf(float(strength), 0.0, 1.0)
	if safe_strength <= 0.0:
		return
	var safe_duration := maxf(COMBAT_FOCUS_MIN_DURATION, float(duration))
	var remaining := maxf(0.0, combat_focus_duration - combat_focus_elapsed)
	# A weak trailing basic shot must not reverse an active ultimate focus.  Once
	# the old move is almost complete, a new stronger impact may take over.
	if remaining > 0.0 and safe_strength * safe_duration < combat_focus_strength * remaining:
		return
	combat_focus_direction = -1.0 if world_direction < 0.0 else 1.0
	combat_focus_strength = safe_strength
	combat_focus_elapsed = 0.0
	combat_focus_duration = safe_duration

func advance(delta: float) -> Dictionary:
	var safe_delta := maxf(0.0, delta)
	presentation_clock += safe_delta
	if combat_impulse_remaining > 0.0:
		combat_impulse_remaining = maxf(0.0, combat_impulse_remaining - safe_delta)
		if combat_impulse_remaining <= 0.0:
			combat_impulse_strength = 0.0
	if combat_focus_duration > 0.0:
		combat_focus_elapsed = minf(combat_focus_duration, combat_focus_elapsed + safe_delta)
		if combat_focus_elapsed >= combat_focus_duration:
			_clear_combat_focus()
	var result := {
		"active": is_active(),
		"actor_delta": safe_delta,
		"battlefield_prep": false,
		"impact_commit": false,
		"finished": false,
		"batch": active_batch.duplicate(true),
	}
	if not is_active():
		return result
	elapsed = minf(ULTIMATE_DURATION, elapsed + safe_delta)
	if not prep_fired and elapsed >= BATTLEFIELD_PREP:
		prep_fired = true
		result.battlefield_prep = true
	if not impact_committed and elapsed >= IMPACT_COMMIT:
		impact_committed = true
		hitstop_remaining = HITSTOP_DURATION
		result.impact_commit = true
	if hitstop_remaining > 0.0:
		hitstop_remaining = maxf(0.0, hitstop_remaining - safe_delta)
		result.actor_delta = 0.0
	if elapsed >= ULTIMATE_DURATION:
		finished = true
		result.finished = true
		result.active = false
	return result

func force_finish() -> Dictionary:
	var result := {
		"had_active_batch": is_active(),
		"needs_impact_commit": is_active() and not impact_committed,
		"batch": active_batch.duplicate(true),
	}
	impact_committed = true
	finished = true
	hitstop_remaining = 0.0
	combat_impulse_remaining = 0.0
	combat_impulse_strength = 0.0
	_clear_combat_focus()
	return result

func reset() -> void:
	active_batch.clear()
	elapsed = 0.0
	impact_committed = false
	prep_fired = false
	finished = false
	hitstop_remaining = 0.0
	presentation_clock = 0.0
	combat_impulse_remaining = 0.0
	combat_impulse_strength = 0.0
	_clear_combat_focus()

func batch_snapshot() -> Dictionary:
	return active_batch.duplicate(true)

func cinematic_snapshot() -> Dictionary:
	var progress := clampf(elapsed / ULTIMATE_DURATION, 0.0, 1.0)
	var cutin_in := clampf((elapsed - CUTIN_START) / maxf(0.01, CUTIN_PEAK - CUTIN_START), 0.0, 1.0)
	var cutin_out := clampf((0.95 - elapsed) / 0.20, 0.0, 1.0)
	return {
		"active": is_active(),
		"elapsed": elapsed,
		"progress": progress,
		"cutin_visibility": sin(cutin_in * PI * .5) * sin(cutin_out * PI * .5),
		"impact_committed": impact_committed,
		"combat_impulse": _combat_impulse(),
		"combat_focus": _combat_focus(),
		"combat_focus_direction": combat_focus_direction,
		"recovery": clampf((elapsed - RECOVERY_START) / maxf(0.01, ULTIMATE_DURATION - RECOVERY_START), 0.0, 1.0),
		"batch": active_batch.duplicate(true),
	}

func battlefield_zoom() -> float:
	var zoom := 1.0
	if is_active():
		var impact_pulse := clampf(1.0 - absf(elapsed - IMPACT_COMMIT) / 0.46, 0.0, 1.0)
		zoom += 0.062 * sin(impact_pulse * PI * .5)
	zoom += 0.018 * _combat_impulse()
	zoom += 0.026 * _combat_focus()
	return zoom

func battlefield_offset() -> Vector2:
	var offset := Vector2.ZERO
	if is_active() and elapsed >= 0.94:
		var shake := clampf(1.0 - (elapsed - 0.94) / 0.52, 0.0, 1.0)
		offset += Vector2(sin(elapsed * 91.0) * 8.0 * shake, cos(elapsed * 73.0) * 4.0 * shake)
	var impulse := _combat_impulse()
	if impulse > 0.0:
		offset += Vector2(sin(presentation_clock * 143.0) * 7.0 * impulse, cos(presentation_clock * 109.0) * 3.5 * impulse)
	var focus := _combat_focus()
	if focus > 0.0:
		offset += Vector2(-combat_focus_direction * COMBAT_FOCUS_MAX_OFFSET_X * focus, -2.0 * focus)
	return offset

func _combat_impulse() -> float:
	if combat_impulse_remaining <= 0.0 or combat_impulse_strength <= 0.0:
		return 0.0
	var progress := clampf(combat_impulse_remaining / COMBAT_IMPULSE_DURATION, 0.0, 1.0)
	return combat_impulse_strength * sin(progress * PI * .5)


func _combat_focus() -> float:
	if combat_focus_duration <= 0.0 or combat_focus_strength <= 0.0:
		return 0.0
	var progress := clampf(combat_focus_elapsed / combat_focus_duration, 0.0, 1.0)
	var enter := clampf(progress / .18, 0.0, 1.0)
	var exit := clampf((1.0 - progress) / .30, 0.0, 1.0)
	return combat_focus_strength * sin(enter * PI * .5) * sin(exit * PI * .5)


func _clear_combat_focus() -> void:
	combat_focus_direction = 0.0
	combat_focus_strength = 0.0
	combat_focus_elapsed = 0.0
	combat_focus_duration = 0.0
