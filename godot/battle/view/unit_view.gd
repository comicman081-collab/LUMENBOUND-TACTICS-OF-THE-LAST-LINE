class_name UnitView
extends Node2D

enum AnimationState { IDLE, MOVE, BASIC_ATTACK, NORMAL_SKILL, ULTIMATE, HIT, STUN, DOWN, VICTORY }
var animation_state := AnimationState.IDLE
var facing_policy := "MIRROR_SAFE"

func present_event(event: Dictionary) -> void:
	if event.type == BattleEvent.BASIC_ATTACK: animation_state = AnimationState.BASIC_ATTACK
	elif event.type == BattleEvent.NORMAL_SKILL: animation_state = AnimationState.NORMAL_SKILL
	elif event.type == BattleEvent.ULTIMATE: animation_state = AnimationState.ULTIMATE
	elif event.type == BattleEvent.DAMAGE: animation_state = AnimationState.HIT
	elif event.type == BattleEvent.DOWN: animation_state = AnimationState.DOWN

