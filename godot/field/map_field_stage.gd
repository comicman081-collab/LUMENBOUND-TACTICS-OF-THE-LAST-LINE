extends "res://field/field_stage.gd"

## Contact scenes on the chapter map (2026-09-30, phase 3): two actors, the squad
## leader (`leader`, `ally`) and the encounter's pawn (`foe`, `boss`, `event`).
## Poses and camera go to the map screen's presentation-only field hooks; nothing
## here touches map state, the pending encounter or saves.

const FOCUS_WEIGHT := 0.65

var screen: Node
var overlay: Control
var node_id := ""
var names: Dictionary = {}
var portrait_source: Callable = Callable()


func _init(map_screen: Node, field_overlay: Control, encounter_node_id: String, actor_names := {}, portraits := Callable()) -> void:
	screen = map_screen
	overlay = field_overlay
	node_id = encounter_node_id
	names = actor_names
	portrait_source = portraits


func _live() -> bool:
	return screen != null and is_instance_valid(screen) and overlay != null and is_instance_valid(overlay)


func move_unit_px() -> float:
	return 1.0


func resolve(actor: String) -> String:
	match actor:
		"leader", "ally":
			return "leader"
		"foe", "boss", "event", "enemy":
			return "foe"
	return ""


func actor_name(actor: String) -> String:
	return str(names.get(actor, ""))


func actor_side(actor: String) -> String:
	return "foe" if actor == "foe" else "ally"


func opponent_of(actor: String) -> String:
	if actor == "leader":
		return "foe"
	if actor == "foe":
		return "leader"
	return ""


func _world(actor: String) -> Vector3:
	return screen.field_actor_world(actor, node_id) if _live() else Vector3.INF


func _head(actor: String) -> Vector2:
	if not _live():
		return Vector2.INF
	return screen.field_head_global(_world(actor))


func actor_anchor(actor: String) -> Vector2:
	var global_point := _head(actor)
	if global_point == Vector2.INF:
		return Vector2.INF
	return overlay.get_global_transform().affine_inverse() * global_point


func direction_between(actor: String, other: String) -> int:
	var from := _head(actor)
	var to := _head(other)
	if from == Vector2.INF or to == Vector2.INF or is_equal_approx(from.x, to.x):
		return 0
	return 1 if to.x > from.x else -1


func apply_actor_pose(actor: String, offset: Vector2, hop: float, flip: int) -> void:
	if not _live():
		return
	if actor == "leader":
		screen.field_set_pawn_pose(offset, hop, flip)
	elif actor == "foe":
		screen.field_set_enemy_pose(node_id, offset, hop)


func apply_camera(focus: String, zoom: float, shake: float) -> void:
	if not _live():
		return
	var focus_world := Vector3.INF
	if not focus.is_empty():
		var main := _world(focus)
		var other := _world(opponent_of(focus))
		if main != Vector3.INF:
			focus_world = main if other == Vector3.INF else other.lerp(main, FOCUS_WEIGHT)
	screen.field_set_camera(focus_world, zoom, shake)


func play_sfx(sfx_id: String) -> void:
	AudioService.play_sfx(sfx_id)


func line_started(text_key: String) -> void:
	AudioService.stop_voice()
	if not text_key.is_empty():
		AudioService.play_line_voice(text_key)


func portrait_for(asset_id: String) -> Texture2D:
	return portrait_source.call(asset_id) if portrait_source.is_valid() else null


func scene_finished() -> void:
	AudioService.stop_voice()
	if _live():
		screen.field_release()
