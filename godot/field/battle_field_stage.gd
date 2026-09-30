extends "res://field/field_stage.gd"

## Aftermath scenes on the battle floor (2026-09-30, phase 3). `leader` and `ally`
## are two surviving party members, `foe` and `boss` the defeated boss's last spot
## (its sprite is already gone, only its voice and the bubble remain). Poses and
## the camera go to the battle view's presentation-only field hooks.

const FOCUS_WEIGHT := 0.65

var view: Control
var overlay: Control
var names: Dictionary = {}
var portrait_source: Callable = Callable()


func _init(battle_view: Control, field_overlay: Control, actor_names := {}, portraits := Callable()) -> void:
	view = battle_view
	overlay = field_overlay
	names = actor_names
	portrait_source = portraits


func _live() -> bool:
	return view != null and is_instance_valid(view) and overlay != null and is_instance_valid(overlay)


func move_unit_px() -> float:
	return view.field_move_unit_px() if _live() else 100.0


func resolve(actor: String) -> String:
	match actor:
		"leader", "ally", "foe", "boss":
			return "boss" if actor == "foe" else actor
	return ""


func actor_name(actor: String) -> String:
	if names.has(actor):
		return str(names[actor])
	return str(view.field_actor_name(actor)) if _live() else ""


func actor_side(actor: String) -> String:
	return "foe" if actor == "boss" else "ally"


func opponent_of(actor: String) -> String:
	return "leader" if actor == "boss" else "boss"


func actor_anchor(actor: String) -> Vector2:
	if not _live():
		return Vector2.INF
	return view.field_head_point(actor)


func direction_between(actor: String, other: String) -> int:
	if not _live():
		return 0
	var from: Vector2 = view.field_layout_point(actor)
	var to: Vector2 = view.field_layout_point(other)
	if from == Vector2.INF or to == Vector2.INF or is_equal_approx(from.x, to.x):
		return 0
	return 1 if to.x > from.x else -1


func apply_actor_pose(actor: String, offset: Vector2, hop: float, _flip: int) -> void:
	if _live():
		view.field_set_pose(actor, offset, hop)


func apply_camera(focus: String, zoom: float, shake: float) -> void:
	if not _live():
		return
	var focus_point := Vector2.INF
	if not focus.is_empty():
		var main: Vector2 = view.field_layout_point(focus)
		var other: Vector2 = view.field_layout_point(opponent_of(focus))
		if main != Vector2.INF:
			focus_point = main if other == Vector2.INF else other.lerp(main, FOCUS_WEIGHT)
	view.field_set_camera(focus_point, zoom, shake)


func play_sfx(sfx_id: String) -> void:
	AudioService.play_sfx(sfx_id)


func line_started(text_key: String) -> void:
	AudioService.stop_voice()
	if not text_key.is_empty():
		AudioService.play_line_voice(text_key)


## `@boss`, `@leader` and `@ally` stand for the role's own portrait art.
func portrait_for(asset_id: String) -> Texture2D:
	if not portrait_source.is_valid():
		return null
	if asset_id.begins_with("@"):
		asset_id = view.field_portrait_id(asset_id.substr(1)) if _live() else ""
	return portrait_source.call(asset_id) if not asset_id.is_empty() else null


func scene_finished() -> void:
	AudioService.stop_voice()
	if _live():
		view.field_release()
