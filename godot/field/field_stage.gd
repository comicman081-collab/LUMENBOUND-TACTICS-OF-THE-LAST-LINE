extends RefCounted

## What a field scene needs from the screen it plays on (2026-09-30, phase 3).
##
## `FieldScene` decides who says, moves, jumps and where the camera looks; the host
## (chapter map, battle view, or a test) owns the actors and the camera. Every method
## has a harmless default, so a host only overrides what it can show.
##
## Actor ids in a script are roles or ids: `leader`, `ally`, `foe`, `boss`, `event`,
## or a concrete id such as `CHR003`. `resolve()` maps a script id to the host's own
## actor key, and returns "" when the actor is not on screen.

## Unit of a `move` offset in host pixels (a cell width on the battle floor, a hex on the map).
func move_unit_px() -> float:
	return 100.0


func resolve(_actor: String) -> String:
	return ""


## Head point, in the overlay's pixel space, where bubbles and emotes attach.
## `Vector2.INF` means "not visible".
func actor_anchor(_actor: String) -> Vector2:
	return Vector2.INF


func actor_name(_actor: String) -> String:
	return ""


## "ally" for the player side, "foe" for the enemy side.
func actor_side(_actor: String) -> String:
	return "ally"


## The actor this one faces by default (`ally` -> `foe` and back); "" when unknown.
func opponent_of(_actor: String) -> String:
	return ""


## Screen x direction (-1 left, +1 right) from `actor` towards `other`; 0 when unknown.
func direction_between(_actor: String, _other: String) -> int:
	return 0


## Called for every actor a scene has touched, on each advance. `offset` is in
## `move_unit_px()` units, `hop` is a 0..1 jump height, `flip` is 0 (keep), -1 or +1.
func apply_actor_pose(_actor: String, _offset: Vector2, _hop: float, _flip: int) -> void:
	pass


## Camera request: look at `focus` (or the whole scene when ""), `zoom` >= 1 pushes in,
## `shake` is a pixel amplitude that decays on the host's side.
func apply_camera(_focus: String, _zoom: float, _shake: float) -> void:
	pass


func play_sfx(_sfx_id: String) -> void:
	pass


## A speech line starts; hosts play its recorded voice (keyed by localization key).
func line_started(_text_key: String) -> void:
	pass


func portrait_for(_asset_id: String) -> Texture2D:
	return null


## The scene has released the actors; the host restores every pose and the camera.
func scene_finished() -> void:
	pass
