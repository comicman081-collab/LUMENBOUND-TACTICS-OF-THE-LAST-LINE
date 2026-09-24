extends Node
const Actions := preload("res://battle/view/combat_action_frames.gd")
const Weapons := preload("res://battle/view/combat_weapon_effects.gd")
var checks: Array = []
func check(ok: bool, label: String) -> void:
	checks.append({"pass":ok,"name":label})
	print("PASS | " if ok else "FAIL | ", label)

func _ready() -> void:
	var library := Actions.new()
	var ids: Array[String] = ["CHR001","CHR002","CHR003","CHR004","CHR005"]
	check(await library.warm(ids,self),"starting party leases reviewed motion")
	for id in ids:
		for action in ["basic_attack","normal_skill","ultimate"]:
			check(library.has_action(id,action),id+" "+action+" exists")
			var samples: Dictionary = {}
			for step in range(211):
				var sample := library.sample(id,action,float(step)*.01,id in ["CHR001","CHR002"])
				samples[int(sample.frame_index)]=true
			check(samples.size()==6,id+" "+action+" has six actual poses")
			var sample := library.sample(id,action,.44,id in ["CHR001","CHR002"])
			check(sample.texture is Texture2D and (sample.texture as Texture2D).get_width()>16,id+" "+action+" has drawable contact art")
	check(library.decoded_bytes<=Actions.BUDGET,"encounter motion respects bounded memory")
	check(Actions.frame_index("basic_attack",.13,false)==2 and Actions.frame_index("basic_attack",.14,false)==3,"firearm pose release matches muzzle launch")
	check(Actions.frame_index("basic_attack",.42,true)==2 and Actions.frame_index("basic_attack",.44,true)==3,"melee pose release matches target contact")
	check(Actions.frame_index("ultimate",.81,false)==2 and Actions.frame_index("ultimate",.82,false)==3,"ultimate gun pose matches prep plus launch")
	check(Actions.frame_index("ultimate",1.12,true)==3,"ultimate melee pose matches committed impact")
	check(Weapons.family("CHR002","VANGUARD")!=Weapons.family("CHR003","ASSAULT"),"sword and rifle have different effects")
	check(Weapons.family("CHR003","ASSAULT")!=Weapons.family("CHR004","ASSAULT"),"rifle and energy burst have different effects")
	check(Weapons.family("CHR006","SPECIALIST")!=Weapons.family("CHR007","SPECIALIST"),"focus and tome have different effects")
	check(Weapons.family("BOSS001","AREA")=="siege","boss uses siege blast")
	ids=["CHR006","CHR007","CHR008","ENM001","ENM002","ENM003","BOSS001"]
	check(await library.warm(ids,self),"alternate party and creatures lease motion")
	check(not library.has_action("CHR001","basic_attack"),"new encounter releases previous actor poses")
	for id in ids:
		check(library.has_action(id,"basic_attack") and library.has_action(id,"normal_skill"),id+" attack and skill present")
	library.clear()
	check(library.actors.is_empty() and library.decoded_bytes==0,"lease clears on exit")
	var failures := checks.filter(func(c):return not c.pass).size()
	var out:=FileAccess.open("res://../reports/combat_motion_20260913/action_tests.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"));out.close()
	print("ACTION_FRAMES checks=%d failures=%d"%[checks.size(),failures])
	get_tree().quit(0 if failures==0 else 1)
