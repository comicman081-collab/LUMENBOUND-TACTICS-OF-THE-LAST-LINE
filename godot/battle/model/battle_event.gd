class_name BattleEvent
extends RefCounted

const SPAWN := "SPAWN"
const MOVE := "MOVE"
const BASIC_ATTACK := "BASIC_ATTACK"
const NORMAL_SKILL := "NORMAL_SKILL"
const ULTIMATE := "ULTIMATE"
const DAMAGE := "DAMAGE"
const HEAL := "HEAL"
const SHIELD := "SHIELD"
const STATUS := "STATUS"
const DOWN := "DOWN"
const WAVE := "WAVE"
const BATTLE_END := "BATTLE_END"

static func make(tick: int, type: String, source := "", target := "", value := 0, extra: Dictionary = {}) -> Dictionary:
	return {"tick": tick, "type": type, "source": source, "target": target, "value": value, "extra": extra}

