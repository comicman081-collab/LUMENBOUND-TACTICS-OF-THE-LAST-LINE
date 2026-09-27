extends Node

## Calibrates per-stage enemy factors (post_cap_scale) against the recommended
## growth profile played with careful tactics, or verifies the compiled data.
##
##   -- calibrate <first_chapter> <last_chapter> <all|finales|normal|hard>
##   -- verify    <first_chapter> <last_chapter> <all|finales|normal|hard>
##   -- matrix    <first_chapter> <last_chapter> <all|finales|normal|hard>
##
## The filter may also be a comma-separated list of stage IDs (CH07-N07,CH13-H05).
##
## Battles are positional (BattleGrid): the calibrated player reacts like
## TacticalPolicy (stepping out of telegraphed cells, focus calls, AUTO
## ultimates) from the better of two placements, the policy's counter-formation
## or the preferred-row default, as a careful player would try both. `matrix` also reports the default
## formation without reactions and the same tactics ten levels over the
## recommendation, which shows the placement/growth split the stage demands.
## Output lines are merged into data_source/stage_balance_overrides.json and
## compiled by tools/generate_data.py. Calibration and verification use
## different seed sets.

const PARTY_IDS := ["CHR001", "CHR002", "CHR003", "CHR005", "CHR008"]
const CALIBRATION_RUNS := 12
const VERIFY_RUNS := 16
const BISECTION_STEPS := 7

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := str(args[0]) if args.size() > 0 else "verify"
	var first := int(args[1]) if args.size() > 1 else 1
	var last := int(args[2]) if args.size() > 2 else 20
	var filter := str(args[3]) if args.size() > 3 else "all"
	var ids := filter.split(",") if filter.begins_with("CH") else PackedStringArray()
	for stage in DataRegistry.list_of("stages"):
		var chapter := int(str(stage.chapter_id).substr(2))
		if chapter < first or chapter > last: continue
		if not ids.is_empty() and not ids.has(str(stage.id)): continue
		if filter == "finales" and not is_finale(stage): continue
		if filter == "normal" and str(stage.mode) != "NORMAL": continue
		if filter == "hard" and str(stage.mode) != "HARD": continue
		match mode:
			"calibrate": _calibrate(stage)
			"matrix": _matrix(stage)
			_: _verify(stage)
	print("CALIBRATOR_DONE %s %d-%d %s" % [mode, first, last, filter])
	get_tree().quit()

static func is_finale(stage: Dictionary) -> bool:
	return int(stage.stage_number) == (20 if str(stage.mode) == "NORMAL" else 5)

## Win rate of the tactical player at the recommended profile. Normal routes
## ease from 95% to 88% and end in an 85% finale; Hard routes run 88% to 80%
## and end in a 75% finale. The first three stages stay near certain.
static func target_win_rate(stage: Dictionary) -> float:
	var number := int(stage.stage_number)
	if str(stage.mode) == "NORMAL":
		if number <= 3: return .98
		return .85 if number == 20 else .95 - .07 * float(number - 4) / 15.0
	return .75 if number == 5 else .88 - .08 * float(number - 1) / 3.0

## Upper bound of the enemy factor change. Onboarding stages are only made
## easier; later stages may be made harder so placement always matters.
static func multiplier_cap(stage: Dictionary) -> float:
	if str(stage.mode) == "NORMAL" and int(stage.stage_number) <= 3 and str(stage.chapter_id) == "CH01": return 1.0
	return 4.0

## The recommended profile the growth screen shows and "권장 성장" raises the
## party to (GrowthAdvisor.recommended_profile), so balance and growth agree.
static func expected_profile(stage: Dictionary) -> Dictionary:
	return GrowthAdvisor.recommended_profile(stage)

func _calibrate(stage: Dictionary) -> void:
	var party := _party(expected_profile(stage))
	var formation := best_formation(party, stage)
	var target := target_win_rate(stage)
	var high := multiplier_cap(stage)
	var result := high
	var rate := _win_rate(party, stage, formation, high, CALIBRATION_RUNS, 500000)
	if rate < target:
		# Bracket from 1.0 first: most stages land within a factor of two.
		var low := 1.0 / 32.0
		if high > 1.0:
			if _win_rate(party, stage, formation, 1.0, CALIBRATION_RUNS, 500000) >= target: low = 1.0
			else: high = 1.0
		if low < 1.0:
			var probe := high / 4.0
			while probe > 1.0 / 32.0 and _win_rate(party, stage, formation, probe, CALIBRATION_RUNS, 500000) < target:
				high = probe
				probe /= 4.0
			low = maxf(probe, 1.0 / 32.0)
		for step in range(BISECTION_STEPS):
			var mid := sqrt(low * high)
			if _win_rate(party, stage, formation, mid, CALIBRATION_RUNS, 500000) >= target: low = mid
			else: high = mid
		result = low
		rate = _win_rate(party, stage, formation, result, CALIBRATION_RUNS, 500000)
	var scale := snappedf(float(stage.post_cap_scale) * result, .001)
	print("CALIBRATED %s %.3f mult=%.3f target=%.2f rate=%.2f" % [stage.id, scale, result, target, rate])

func _verify(stage: Dictionary) -> void:
	var party := _party(expected_profile(stage))
	var formation := best_formation(party, stage)
	var summary := _summary(party, stage, formation, true, VERIFY_RUNS, 9000)
	print("VERIFY %s scale=%.3f target=%.2f win=%d/%d time=%.1f deaths=%.2f" % [stage.id, float(stage.post_cap_scale), target_win_rate(stage), int(summary.wins), VERIFY_RUNS, float(summary.time), float(summary.deaths)])

## TACTICAL vs DEFAULT (no reactions) at the recommendation, and TACTICAL /
## DEFAULT ten levels above it.
func _matrix(stage: Dictionary) -> void:
	var profile := expected_profile(stage)
	var party := _party(profile)
	var over_profile := profile.duplicate(true)
	over_profile.level = mini(100, int(profile.level) + 10)
	over_profile.weapon_level = mini(60, int(profile.weapon_level) + 10)
	var over := _party(over_profile)
	var tactical := best_formation(party, stage)
	var default := BattleGrid.default_formation(party)
	var rows := [
		_summary(party, stage, tactical, true, VERIFY_RUNS, 9000),
		_summary(party, stage, default, false, VERIFY_RUNS, 9000),
		_summary(over, stage, tactical, true, VERIFY_RUNS, 9000),
		_summary(over, stage, default, false, VERIFY_RUNS, 9000),
	]
	print("MATRIX %s scale=%.3f target=%.2f tactical=%d default=%d tactical_over=%d default_over=%d runs=%d time=%.1f deaths=%.2f" % [stage.id, float(stage.post_cap_scale), target_win_rate(stage), int(rows[0].wins), int(rows[1].wins), int(rows[2].wins), int(rows[3].wins), VERIFY_RUNS, float(rows[0].time), float(rows[0].deaths)])

## The better of the counter-formation and the default placement, judged by a
## short reacting trial (wins, then fewer downs, then speed).
func best_formation(party: Array, stage: Dictionary) -> Dictionary:
	var candidates := [TacticalPolicy.formation_for(party, stage, DataRegistry.data), BattleGrid.default_formation(party)]
	var best: Dictionary = candidates[0]
	var best_score := -INF
	for formation in candidates:
		var trial := _summary(party, stage, formation, true, 4, 30000)
		var score := float(trial.wins) * 100.0 - float(trial.deaths) * 10.0 - float(trial.time) * .1
		if score > best_score:
			best_score = score
			best = formation
	return best

func _summary(party: Array, stage: Dictionary, formation: Dictionary, react: bool, runs: int, seed_base: int) -> Dictionary:
	var wins := 0
	var time_total := 0.0
	var deaths := 0
	for run_index in range(runs):
		var sim := _simulate(party, stage, formation, react, 1.0, seed_base + run_index * 37)
		if sim.state.victory: wins += 1
		time_total += sim.state.time_elapsed
		for unit in sim.state.party:
			if not UnitState.alive(unit): deaths += 1
	return {"wins": wins, "time": time_total / runs, "deaths": float(deaths) / runs}

func _win_rate(party: Array, stage: Dictionary, formation: Dictionary, multiplier: float, runs: int, seed_base: int) -> float:
	var wins := 0
	for run_index in range(runs):
		if _simulate(party, stage, formation, true, multiplier, seed_base + run_index * 101).state.victory: wins += 1
	return float(wins) / runs

func _simulate(party: Array, stage: Dictionary, formation: Dictionary, react: bool, multiplier: float, seed: int) -> BattleSimulation:
	var sim := BattleSimulation.new()
	sim.setup(party, stage, seed, DataRegistry.data, {"retain_event_log": false, "enemy_multiplier": multiplier, "formation": formation})
	while not sim.state.ended and sim.state.tick < int(float(stage.time_limit) * 30.0) + 5:
		if react: TacticalPolicy.react(sim)
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
