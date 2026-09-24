extends Node

const DensityLoader := preload("res://battle/view/density_texture_loader.gd")
var checks: Array[Dictionary] = []

func check(ok: bool, label: String) -> void:
	checks.append({"pass":ok,"name":label})
	if not ok: push_error(label)

func _ready() -> void:
	var entities: Array[String] = []
	var roster := "--roster" in OS.get_cmdline_user_args()
	if roster:
		for number in range(1,9): entities.append("CHR%03d" % number)
		for number in range(1,11): entities.append("ENM%03d" % number)
		for number in range(1,4): entities.append("BOSS%03d" % number)
	else:
		for number in range(11,43): entities.append("ENM%03d" % number)
		for number in range(4,24): entities.append("BOSS%03d" % number)
	for id in entities:
		var library := BattleSpriteLibrary.new()
		var ids: Array[String] = [id]
		var loaded := library.load_pack(ids)
		check(loaded, id + " compact loads: " + library.load_error)
		if not loaded: continue
		check(await library.warm_full_density(ids,self), id + " HD loads through actual battle library")
		check(str(library.manifests[id].get("source_status","")) == ("SPRITEGEN_ROSTER_VISUAL_PASS" if roster else "ILLUSTRATED_MONSTER_VISUAL_PASS"), id + " selected illustration")
		for action in library.manifests[id].animations.keys():
			var texture := library.texture_at(id,action,.21)
			check(texture != null and texture.get_size() == Vector2(256,256),id + " " + action + " real texture")
		var pending := {"actor_manifests":{},"actor_atlases":{},"map_idle_packs":{}}
		check(await StageAssetCache._load_map_density_group([{"id":id}],pending),id + " map loads through actual map cache")
		StageAssetCache._finalize_map_bundle(pending)
		var map_texture: Texture2D = pending.map_idle_packs[id].texture
		check(map_texture.get_size() == Vector2(192,192),id + " real map texture size")
		check(pending.actor_manifests[id].source_asset_id == library.manifests[id].source_asset_id,id + " map and battle same creature")
		library.load_down_pose_pack(ids)
		check(library.has_down_pose(id) == id.begins_with("CHR"),id + " player prone / enemy explosion contract")
		if roster: check(not library.has_signature_animation(id,"idle"), id + " old signature cannot cover redraw")
		library = null
		pending.clear()
		DensityLoader.clear_cache()
		await get_tree().process_frame
	var failed := checks.filter(func(row): return not row.pass)
	var folder := "existing_roster_spritegen_20260911" if roster else "enemy_replacement_20260911"
	var output := FileAccess.open("res://../reports/"+folder+"/godot_asset_verification.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"status":"PASS" if failed.is_empty() else "FAIL","entities":entities.size(),"checks":checks},"\t"))
	output.close()
	print("MONSTER_ASSET_RUNTIME ", checks.size()-failed.size(), "/", checks.size(), " entities=",entities.size())
	get_tree().quit(0 if failed.is_empty() else 1)
