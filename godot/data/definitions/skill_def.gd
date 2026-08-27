class_name SkillDef
extends Resource
@export var id := ""
@export var owner_id := ""
@export_enum("NORMAL_SKILL", "PASSIVE_SKILL", "ULTIMATE_SKILL") var type := "NORMAL_SKILL"
@export var name_key := ""
@export var icon_asset_id := ""
@export var max_level := 10
@export var values: Array[float] = []
@export var tactical_cost := 0.0
