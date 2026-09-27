extends Node

## Measures how much placement and reaction matter against growth.
##   godot --headless res://tools/tactical_balance_probe.tscn -- <stage_ids,...> [runs] [level_offset]
## For each stage prints win rate / time / downs for:
##   TACTICAL  counter-formation + dodging + focus, AUTO ultimates
##   DEFAULT   preferred-position formation, AUTO ultimates, no reaction
##   REVERSED  back-row roles in front, AUTO ultimates, no reaction
## at the recommended profile shifted by level_offset.

const PARTY_IDS := ["CHR001", "CHR002", "CHR003", "CHR005", "CHR008"]

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var ids := str(args[0]).split(",") if args.size() > 0 else PackedStringArray(["CH01-N01"])
	var runs := int(args[1]) if args.size() > 1 else 8
	var offset := int(args[2]) if args.size() > 2 else 0
	var multiplier := float(args[3]) if args.size() > 3 else 1.0
	for stage_id in ids:
		var stage := DataRegistry.stage(stage_id)
		if stage.is_empty(): continue
		var profile := GrowthAdvisor.recommended_profile(stage)
		profile.level = clampi(int(profile.level) + offset, 1, 100)
		profile.weapon_level = mini(60, int(profile.level))
		var party := party_at(profile)
		var tactical := TacticalPolicy.formation_for(party, stage, DataRegistry.data)
		var default := BattleGrid.default_formation(party)
		var reversed := reversed_formation(party)
		var line := "%s lv%+d x%.2f" % [stage_id, offset, multiplier]
		for mode in [["TACTICAL", tactical, true], ["DEFAULT", default, false], ["REVERSED", reversed, false]]:
			var wins := 0
			var time := 0.0
			var downs := 0
			var moves := 0
			for run in range(runs):
				var sim := BattleSimulation.new()
				sim.setup(party, stage, 7000 + run * 131, DataRegistry.data, {"retain_event_log": false, "formation": mode[1], "enemy_multiplier": multiplier})
				while not sim.state.ended:
					if bool(mode[2]): TacticalPolicy.react(sim)
					sim.tick()
				if sim.state.victory: wins += 1
				time += sim.state.time_elapsed
				moves += sim.move_commands
				for unit in sim.state.party:
					if not UnitState.alive(unit): downs += 1
			line += " | %s %d/%d %.0fs down%.1f mv%.0f" % [mode[0], wins, runs, time / runs, float(downs) / runs, float(moves) / runs]
		print(line)
	get_tree().quit()

static func party_at(profile: Dictionary) -> Array:
	var output: Array = []
	for character_id in PARTY_IDS:
		var definition := DataRegistry.character(character_id).duplicate(true)
		var weapon_id := ""
		for weapon in DataRegistry.list_of("weapons"):
			if str(weapon.weapon_class) == str(definition.weapon_class):
				weapon_id = str(weapon.id)
				break
		var level := int(profile.level)
		var breakthrough := 0
		for cap in [20, 40, 60, 80, 90]:
			if level > int(cap): breakthrough += 1
		definition.progress = {
			"level": level, "breakthrough": breakthrough,
			"skills": {"normal": int(profile.normal), "passive": int(profile.passive), "ultimate": int(profile.ultimate)},
			"equipped_weapon_id": weapon_id,
			"weapon_state": {"owned": true, "level": int(profile.weapon_level), "xp": 0, "tier": clampi(int(ceil(int(profile.weapon_level) / 10.0)), 1, 6)},
		}
		output.append(definition)
	return output

static func reversed_formation(party: Array) -> Dictionary:
	var output: Dictionary = {}
	var default := BattleGrid.default_formation(party)
	for def_id in default:
		var cell: Array = default[def_id]
		output[def_id] = [BattleGrid.PLAYER_FRONT - int(cell[0]), int(cell[1])]
	return output
