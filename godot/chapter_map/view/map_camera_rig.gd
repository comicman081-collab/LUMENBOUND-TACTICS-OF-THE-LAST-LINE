extends RefCounted

## Phase 4 / A4 (2026-09-30): the chapter map's camera pose. The map used to be
## an orthographic isometric view; it is now a slightly tilted perspective view
## (about 48 degrees, 38 degree lens) that keeps the old framing: at the orbit
## target the picture has exactly the scale the orthographic camera had, so
## every screen-space estimate made at the target plane stays right, while
## nearer ground grows and farther ground shrinks. Zoom dollies the camera
## instead of changing the lens, so zooming in also deepens the perspective.
##
## "Moments" are short camera flourishes for map events (a revealed cache, a
## re-lit relay, a choice event): a push-in, a slight orbit and a little shake.
## Everything here is a pure function of time, so it is testable headless.

const BASE_OFFSET := Vector3(9.2, 14.2, 8.8)
const BASE_SIZE := 13.2
const FAR := 160.0
const NEAR := 0.1

## Moment presets: how long, how far it pushes in, the orbit swing (radians),
## shake amplitude (world units) and how strongly the view is pulled to the tile.
const MOMENTS := {
	"treasure": {"duration": 1.00, "zoom": 1.16, "orbit": 0.11, "shake": 0.0, "pull": 7.0},
	"relay": {"duration": 1.25, "zoom": 1.12, "orbit": -0.13, "shake": 0.05, "pull": 7.0},
	"event": {"duration": 0.85, "zoom": 1.09, "orbit": 0.07, "shake": 0.0, "pull": 6.0},
	"impact": {"duration": 0.60, "zoom": 1.05, "orbit": 0.0, "shake": 0.13, "pull": 0.0},
}

static func base_distance() -> float:
	return BASE_OFFSET.length()

## Vertical field of view, in degrees, that matches the old orthographic scale
## at the target plane when the camera sits `base_distance()` away.
static func fov_degrees() -> float:
	return rad_to_deg(2.0 * atan(BASE_SIZE * 0.5 / base_distance()))

## Height of the picture at the target plane for a zoom level.
static func view_size(zoom: float) -> float:
	return BASE_SIZE / maxf(zoom, 0.01)

## Camera distance that frames `size` world units at the target with the fixed lens.
static func distance_for_size(size: float) -> float:
	return size * 0.5 / tan(deg_to_rad(fov_degrees()) * 0.5)

## Camera position relative to the target. Orthographic keeps the fixed offset;
## perspective dollies along the same direction.
static func offset(size: float, yaw: float, perspective: bool) -> Vector3:
	var direction := BASE_OFFSET.normalized()
	var distance := distance_for_size(size) if perspective else base_distance()
	return Basis(Vector3.UP, yaw) * (direction * distance)

## Camera pitch below the horizon, in degrees.
static func pitch_degrees() -> float:
	return rad_to_deg(atan2(BASE_OFFSET.y, Vector2(BASE_OFFSET.x, BASE_OFFSET.z).length()))

static func is_moment(kind: String) -> bool:
	return MOMENTS.has(kind)

static func moment_duration(kind: String) -> float:
	return float(MOMENTS.get(kind, {}).get("duration", 0.0))

static func moment_pull(kind: String) -> float:
	return float(MOMENTS.get(kind, {}).get("pull", 0.0))

static func _smooth(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

## State of a moment `elapsed` seconds in: {active, zoom (multiplier), yaw
## (radians), shake (Vector3 world offset), progress}. Inactive past the end.
static func moment(kind: String, elapsed: float) -> Dictionary:
	var preset: Dictionary = MOMENTS.get(kind, {})
	var duration := float(preset.get("duration", 0.0))
	if preset.is_empty() or duration <= 0.0 or elapsed < 0.0 or elapsed >= duration:
		return {"active": false, "zoom": 1.0, "yaw": 0.0, "shake": Vector3.ZERO, "progress": 1.0}
	var t := elapsed / duration
	# Push in over the first 40%, hold a beat, ease back out; the orbit swings
	# out and back with one smooth arch.
	var push := _smooth(t / 0.4) if t < 0.4 else (1.0 if t < 0.6 else 1.0 - _smooth((t - 0.6) / 0.4))
	var arch := sin(t * PI)
	var decay := (1.0 - t) * (1.0 - t)
	var amplitude := float(preset.get("shake", 0.0)) * decay
	var shake := Vector3(sin(elapsed * 53.0), sin(elapsed * 71.0 + 1.3) * 0.6, cos(elapsed * 47.0)) * amplitude
	return {
		"active": true,
		"zoom": 1.0 + (float(preset.get("zoom", 1.0)) - 1.0) * push,
		"yaw": float(preset.get("orbit", 0.0)) * arch,
		"shake": shake,
		"progress": t,
	}
