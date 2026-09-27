extends Node

## Calibrates per-stage enemy factors (post_cap_scale) against an expected
## player growth curve, or verifies the compiled data against the same targets.
##
##   -- calibrate <first_chapter> <last_chapter> <all|finales>
##   -- verify    <first_chapter> <last_chapter> <all|finales>
##
## Player level caps at 100 around chapter 5; after that the only growth is skill
## levels (worth roughly +8-20% enemy tolerance at max).  The original post-cap
## formula kept raising enemy stats on top of rising regional base stats, which
## left chapters 5-20 unwinnable.  Output lines are merged into
## data_source/stage_balance_overrides.json and compiled by tools/generate_data.py.
## Calibration and verification use different seed sets.

const PARTY_IDS := ["CHR001", "CHR002", "CHR003", "CHR005", "CHR008"]
const CALIBRATION_RUNS := 16
const VERIFY_RUNS := 24
const BISECTION_STEPS := 8

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := str(args[0]) if args.size() > 0 else "verify"
	var first := int(args[1]) if args.size() > 1 else 1
	var last := int(args[2]) if args.size() > 2 else 20
	var only_finales := args.size() > 3 and str(args[3]) == "finales"
	for stage in DataRegistry.list_of("stages"):
		var chapter := int(str(stage.chapter_id).substr(2))
		if chapter < first or chapter > last: continue
		if only_finales and not is_finale(stage): continue
		if mode == "calibrate":
			_calibrate(stage)
		else:
			_verify(stage)
	get_tree().quit()

static func is_finale(stage: Dictionary) -> bool:
	return int(stage.stage_number) == (20 if str(stage.mode) == "NORMAL" else 5)

## Normal routes ease from 95% to 85% and end in a 75% finale; Hard routes run
## 70% to 55% and end in a 40% finale (the chapter 1 hardening targets).
static func target_win_rate(stage: Dictionary) -> float:
	var number := int(stage.stage_number)
	if str(stage.mode) == "NORMAL":
		return .75 if number == 20 else .95 - .10 * float(number - 1) / 18.0
	return .40 if number == 5 else .70 - .05 * float(number - 1)

## Regular stages are only ever made easier; finales may also get harder so the
## boss stays a step up from the route before it.
static func multiplier_cap(stage: Dictionary) -> float:
	return 1.25 if is_finale(stage) else 1.0

## The recommended profile the growth screen shows and "권장 성장" raises the
## party to (GrowthAdvisor.recommended_profile), so balance and growth agree.
static func expected_profile(stage: Dictionary) -> Dictionary:
	return GrowthAdvisor.recommended_profile(stage)

func _calibrate(stage: Dictionary) -> void:
	var party := _party(expected_profile(stage))
	var target := target_win_rate(stage)
	var high := multiplier_cap(stage)
	var result := high
	var rate := _win_rate(party, stage, high, CALIBRATION_RUNS, 500000)
	if rate < target:
		var low := high / 8.0
		if _win_rate(party, stage, low, CALIBRATION_RUNS, 500000) < target: low = high / 32.0
		for step in range(BISECTION_STEPS):
			var mid := sqrt(low * high)
			if _win_rate(party, stage, mid, CALIBRATION_RUNS, 500000) >= target: low = mid
			else: high = mid
		result = low
		rate = _win_rate(party, stage, result, CALIBRATION_RUNS, 500000)
	var scale := snappedf(float(stage.post_cap_scale) * result, .001)
	print("CALIBRATED %s %.3f mult=%.3f target=%.2f rate=%.2f" % [stage.id, scale, result, target, rate])

func _verify(stage: Dictionary) -> void:
	var party := _party(expected_profile(stage))
	var wins := 0
	var time_total := 0.0
	var deaths := 0
	for run_index in range(VERIFY_RUNS):
		var sim := _simulate(party, stage, 1.0, 9000 + run_index * 37)
		if sim.state.victory: wins += 1
		time_total += sim.state.time_elapsed
		for unit in sim.state.party:
			if not UnitState.alive(unit): deaths += 1
	print("VERIFY %s scale=%.3f target=%.2f win=%d/%d time=%.1f deaths=%.2f" % [stage.id, float(stage.post_cap_scale), target_win_rate(stage), wins, VERIFY_RUNS, time_total / VERIFY_RUNS, float(deaths) / VERIFY_RUNS])

func _win_rate(party: Array, stage: Dictionary, multiplier: float, runs: int, seed_base: int) -> float:
	var wins := 0
	for run_index in range(runs):
		if _simulate(party, stage, multiplier, seed_base + run_index * 101).state.victory: wins += 1
	return float(wins) / runs

func _simulate(party: Array, stage: Dictionary, multiplier: float, seed: int) -> BattleSimulation:
	var sim := BattleSimulation.new()
	sim.setup(party, stage, seed, DataRegistry.data, {"retain_event_log": false, "enemy_multiplier": multiplier})
	while not sim.state.ended and sim.state.tick < int(float(stage.time_limit) * 30.0) + 5:
		sim.tick()
	return sim

func _party(profile: Dictionary) -> Array:
	var output: Array = []
	for character_id in PARTY_IDS:
		var definition := DataRegistry.character(character_id).duplicate(true)
		var weapon_id := ""
		for weapon in DataRegistry.list_of("weapons"):
			if str(weapon.weapon_class) == str(definition.weapon_class):
				weapon_id = str(weapon.id)
				break
		var level := int(profile.level)
		var weapon_level := int(profile.weapon_level)
		definition.progress = {
			"level": level,
			"breakthrough": 0 if level <= 20 else (1 if level <= 40 else (2 if level <= 60 else (3 if level <= 80 else (4 if level <= 90 else 5)))),
			"skills": {"normal": int(profile.normal), "passive": int(profile.passive), "ultimate": int(profile.ultimate)},
			"equipped_weapon_id": weapon_id,
			"weapon_state": {"owned": true, "level": weapon_level, "xp": 0, "tier": clampi(int(ceil(weapon_level / 10.0)), 1, 6)},
		}
		output.append(definition)
	return output
