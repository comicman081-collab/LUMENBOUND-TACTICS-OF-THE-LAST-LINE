extends Node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var runs := 100
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): runs = clampi(int(args[0]), 1, 1000)
	var wins := 0
	var times: Array[float] = []
	var survivors := 0
	var seeds: Array[int] = []
	var damage: Dictionary = {}
	var healing: Dictionary = {}
	var ultimate_uses := 0
	var ultimate_by_character: Dictionary = {}
	var death_causes: Dictionary = {}
	var end_reasons: Dictionary = {}
	var run_results: Array = []
	var party_snapshot := AppState.create_party_snapshot()
	for character in party_snapshot: character.progress.level = 10
	for i in range(runs):
		var seed := 700000 + i
		var sim := BattleSimulation.new()
		sim.setup(party_snapshot, DataRegistry.stage("CH01-N10"), seed, DataRegistry.data)
		while not sim.state.ended and sim.state.tick < 3000: sim.tick()
		var result := sim.result_snapshot()
		if result.victory: wins += 1
		times.append(float(result.time))
		survivors += int(result.survivors)
		ultimate_uses += int(result.ultimate_uses)
		end_reasons[result.reason] = int(end_reasons.get(result.reason, 0)) + 1
		seeds.append(seed)
		for id in result.damage: damage[id] = int(damage.get(id, 0)) + int(result.damage[id])
		for id in result.healing: healing[id] = int(healing.get(id, 0)) + int(result.healing[id])
		for id in result.ultimate_uses_by_character: ultimate_by_character[id] = int(ultimate_by_character.get(id, 0)) + int(result.ultimate_uses_by_character[id])
		for death in result.deaths: death_causes[death.source] = int(death_causes.get(death.source, 0)) + 1
		run_results.append({"seed": seed, "victory": result.victory, "reason": result.reason, "time": result.time, "survivors": result.survivors})
	var mean: float = float(times.reduce(func(total, value): return total + value, 0.0)) / runs
	var variance: float = float(times.reduce(func(total, value): return total + pow(value - mean, 2), 0.0)) / runs
	var sorted_times := times.duplicate()
	sorted_times.sort()
	var report := {"runs": runs, "stage_id": "CH01-N10", "party_level": 10, "win_rate": float(wins) / runs, "mean_clear_or_end_time": mean, "time_variance": variance, "min_time": sorted_times[0], "median_time": sorted_times[int((runs - 1) * .5)], "p90_time": sorted_times[int((runs - 1) * .9)], "max_time": sorted_times[-1], "mean_survivors": float(survivors) / runs, "damage_totals": damage, "healing_totals": healing, "mean_ultimate_uses": float(ultimate_uses) / runs, "ultimate_uses_by_character": ultimate_by_character, "death_causes": death_causes, "end_reasons": end_reasons, "seeds": seeds, "run_results": run_results}
	var report_path := ProjectSettings.globalize_path("res://").path_join("../reports/balance_simulation.json").simplify_path()
	var output := FileAccess.open(report_path, FileAccess.WRITE)
	if output == null:
		printerr("could not write ", report_path)
		get_tree().quit(2)
		return
	output.store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	get_tree().quit(0)
