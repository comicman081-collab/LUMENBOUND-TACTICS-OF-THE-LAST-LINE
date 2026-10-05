extends Node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var index = JSON.parse_string(FileAccess.get_file_as_string(BattleSpriteLibrary.FULL_DENSITY_ROOT + "/index.json"))
	var checked := 0
	var failures: Array[String] = []
	for entity in index.actors:
		var ids: Array[String] = [str(entity)]
		var actors := BattleSpriteLibrary.new()
		actors.load_pack(ids)
		if not await actors.warm_full_density(ids, self):
			failures.append("%s actor=%s" % [entity,actors.full_density_error])
		for action in ["idle", "move", "basic_attack", "normal_skill", "ultimate", "hit", "down", "victory"]:
			var frame := actors.texture_at(entity, action, .2)
			var cell_size := 512 if str(entity).begins_with("BOSS") else 256
			if frame == null or frame.get_size() != Vector2(cell_size,cell_size): failures.append("%s:%s frame" % [entity,action])
		var effects = preload("res://battle/view/full_density_effects.gd").new()
		if not await effects.warm(ids, self): failures.append("%s FX=%s" % [entity,effects.error])
		if effects.projectile_at(entity, .2) == null or effects.ultimate_at(entity,.4) == null: failures.append("%s missing FX" % entity)
		var pending := {"actor_manifests": {}, "actor_atlases": {}, "map_idle_packs": {}}
		if not await StageAssetCache._load_map_density_task({"id":entity},pending):
			failures.append("%s map HD missing" % entity)
		else:
			StageAssetCache._finalize_map_bundle(pending)
			var pack: Dictionary = pending.map_idle_packs[entity]
			var baseline = JSON.parse_string(FileAccess.get_file_as_string("res://assets/runtime_web/combat/%s/animation_manifest.json" % entity))
			if pack.texture.get_width() != 192 or absf(float(pack.pixel_scale)*192-float(baseline.frame_size[1])) > .01:
				failures.append("%s map HD scale changed" % entity)
		pending.clear()
		checked += 1
		actors = null
		effects = null
		await get_tree().process_frame
	print("FULL_DENSITY_TEST actors=%d effects=%d map_actors=%d failures=%s" % [checked,checked*4,checked,JSON.stringify(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
