class_name CharacterDef
extends Resource

@export var id := ""
@export var name_key := ""
@export var description_key := ""
@export_enum("GUARDIAN", "VANGUARD", "ASSAULT", "ARTILLERY", "SPECIALIST", "MEDIC") var role := "ASSAULT"
@export_enum("FRONT", "MIDDLE", "BACK") var preferred_position := "MIDDLE"
@export var normal_skill_id := ""
@export var passive_skill_id := ""
@export var ultimate_skill_id := ""
@export var asset_id := ""
@export var stats_l1: Dictionary = {}
@export var stats_l100: Dictionary = {}

