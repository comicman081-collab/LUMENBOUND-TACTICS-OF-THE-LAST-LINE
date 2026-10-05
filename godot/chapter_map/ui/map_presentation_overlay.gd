extends Control

## Phase 2 map presentation drawn over the 3D map (A6, B1, B2):
## - floating, pulsing markers: boss skull, elite star, event "!", treasure chest
## - the route preview as a glowing dotted line with an arrowhead and step count
## - a light that runs around the move-range rim
## - landing dust under the party token
## Pure presentation. The map screen hands in world anchors (or the label
## buttons they follow) plus a projector; nothing here reads or writes state.

const MARKER_COLORS := {"BOSS": Color("ff5a52"), "ELITE": Color("c78bff"), "EVENT": Color("ffd166"), "TREASURE": Color("ffcf6e")}
const DUST_DURATION := .55
const OUT_OF_REACH := Color("6d7c88")

## Projects a world point to overlay pixels.
var projector := Callable()
## Returns false for anchors behind the camera or off screen.
var visible_check := Callable()
var ui_scale := 1.0
var clock := 0.0
## {kind, button?: Button, world?: Vector3, phase}
var markers: Array = []
## Extra markers drawn with the synced ones (design preview and QA captures);
## the map never writes this list.
var extra_markers: Array = []
var route_world: Array = []
var route_reach := 0
var route_color := Color("4fd3c2")
var rim_world: Array = []
var rim_center := Vector3.ZERO
var dust: Array = []
var projection_serial := -1
var projection_dirty := true
var projected_scale := -1.0
var projected_route: Array[Vector2] = []
var projected_rim: Array[Vector2] = []
var projected_rim_center := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	clock += delta
	for index in range(dust.size() - 1, -1, -1):
		var puff: Dictionary = dust[index]
		puff.age = float(puff.age) + delta
		if float(puff.age) >= DUST_DURATION:
			dust.remove_at(index)
	if not markers.is_empty() or not extra_markers.is_empty() or route_world.size() >= 2 or not rim_world.is_empty() or not dust.is_empty():
		queue_redraw()

func set_route(points: Array, reach: int, color: Color) -> void:
	route_world = points
	route_reach = reach
	route_color = color
	projection_dirty = true
	queue_redraw()

func set_rim(segments: Array, center: Vector3) -> void:
	rim_world = segments
	rim_center = center
	projection_dirty = true
	queue_redraw()

## The map owns one exact projection serial shared by its world-space overlays.
## Pulsing/dotted presentation continues at the display rate; a stationary camera
## does not need Camera3D.unproject_position for every rim edge on every frame.
func apply_projection_serial(serial: int) -> void:
	if projection_serial == serial:
		return
	projection_serial = serial
	projection_dirty = true
	queue_redraw()

func _refresh_projected_geometry() -> void:
	if projection_serial >= 0 and not projection_dirty and is_equal_approx(projected_scale, ui_scale):
		return
	projected_route.clear()
	for world in route_world:
		projected_route.append(_project(world))
	projected_rim.clear()
	for segment in rim_world:
		projected_rim.append(_project(segment[0]))
		projected_rim.append(_project(segment[1]))
	projected_rim_center = _project(rim_center)
	projected_scale = ui_scale
	projection_dirty = false

func spawn_dust(world: Vector3, strength := 1.0) -> void:
	dust.append({"world": world, "age": 0.0, "strength": strength})

func snapshot() -> Dictionary:
	var kinds: Array = []
	for marker in markers: kinds.append(str(marker.kind))
	return {"markers": kinds, "route": route_world.size(), "reach": route_reach, "rim": rim_world.size(), "dust": dust.size()}

func _project(world: Vector3) -> Vector2:
	return projector.call(world) if projector.is_valid() else Vector2.ZERO

func _on_screen(world: Vector3) -> bool:
	return visible_check.call(world, Vector2(8, 8)) if visible_check.is_valid() else true

func _draw() -> void:
	_refresh_projected_geometry()
	_draw_rim()
	_draw_route()
	_draw_dust()
	for marker in markers:
		_draw_marker(marker)
	for marker in extra_markers:
		_draw_marker(marker)

# --- move range rim -------------------------------------------------------

func _draw_rim() -> void:
	if rim_world.is_empty(): return
	var center := projected_rim_center
	var sweep := fmod(clock * 1.25, TAU)
	var breathe := .5 + .5 * sin(clock * 2.2)
	for index in range(0, projected_rim.size(), 2):
		var a := projected_rim[index]
		var b := projected_rim[index + 1]
		var mid := (a + b) * .5
		var angle := atan2(mid.y - center.y, mid.x - center.x)
		var light := pow(maxf(0.0, cos(angle - sweep)), 8.0)
		draw_line(a, b, Color(1.0, .86, .48, .30 + .12 * breathe), 3.0 * ui_scale, true)
		if light > .02:
			draw_line(a, b, Color(1.0, .95, .72, .85 * light), 5.5 * ui_scale, true)

# --- route preview ----------------------------------------------------------

func _draw_route() -> void:
	if route_world.size() < 2: return
	var points := projected_route
	var spacing := 15.0 * ui_scale
	var offset := fmod(clock * 30.0 * ui_scale, spacing)
	var travelled := 0.0
	var reach_end := mini(route_reach, points.size() - 1)
	for index in range(points.size() - 1):
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		var length := a.distance_to(b)
		if length < 1.0: continue
		var reachable := index < route_reach
		var color := route_color.lightened(.15) if reachable else OUT_OF_REACH
		var d := spacing - fmod(travelled - offset + spacing * 100.0, spacing)
		while d < length:
			var p := a.lerp(b, d / length)
			if reachable:
				draw_circle(p, 7.0 * ui_scale, Color(color.r, color.g, color.b, .22))
			draw_circle(p, (3.4 if reachable else 2.6) * ui_scale, Color(color.r, color.g, color.b, .95 if reachable else .7))
			d += spacing
		travelled += length
	# Arrowhead at the last cell this turn can reach, then a step-count badge.
	var tip: Vector2 = points[reach_end] if reach_end > 0 else points[points.size() - 1]
	var from: Vector2 = points[maxi(0, (reach_end if reach_end > 0 else points.size() - 1) - 1)]
	var direction := (tip - from).normalized() if tip.distance_to(from) > .5 else Vector2.RIGHT
	var normal := Vector2(-direction.y, direction.x)
	var bob := sin(clock * 5.0) * 2.0 * ui_scale
	var head := tip + direction * bob
	var arrow := PackedVector2Array([head + direction * 12.0 * ui_scale, head - direction * 8.0 * ui_scale + normal * 10.0 * ui_scale, head - direction * 3.0 * ui_scale, head - direction * 8.0 * ui_scale - normal * 10.0 * ui_scale])
	var arrow_color := route_color.lightened(.2) if route_reach > 0 else OUT_OF_REACH
	draw_colored_polygon(arrow, Color(0.02, 0.05, 0.08, .55))
	var inner := PackedVector2Array()
	for point in arrow: inner.append(head + (point - head) * .78)
	draw_colored_polygon(inner, arrow_color)
	var steps := points.size() - 1
	var shown := mini(steps, route_reach) if route_reach > 0 else steps
	var label := "%d칸" % shown if shown >= steps else "%d칸 / %d" % [shown, steps]
	var font := get_theme_default_font()
	var font_size := roundi(17.0 * ui_scale)
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 16.0 * ui_scale
	var badge := Rect2(tip + Vector2(-width * .5, -38.0 * ui_scale), Vector2(width, font_size + 9.0 * ui_scale))
	draw_rect(badge, Color(0.02, 0.05, 0.08, .86))
	draw_rect(badge, arrow_color, false, 1.5 * ui_scale)
	draw_string(font, badge.position + Vector2(8.0 * ui_scale, font_size + 2.0 * ui_scale), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("fff4d6"))

# --- landing dust -------------------------------------------------------------

func _draw_dust() -> void:
	for puff in dust:
		var t := clampf(float(puff.age) / DUST_DURATION, 0.0, 1.0)
		var center := _project(puff.world)
		var strength := float(puff.get("strength", 1.0))
		for index in range(7):
			var angle := TAU * float(index) / 7.0 + float(index) * .4
			var spread := (10.0 + 30.0 * strength) * ui_scale * (1.0 - pow(1.0 - t, 2.0))
			var p := center + Vector2(cos(angle) * spread, sin(angle) * spread * .38 - 6.0 * ui_scale * t)
			draw_circle(p, (5.0 + 5.0 * t) * ui_scale * (.7 + .3 * strength), Color(.86, .80, .66, .42 * (1.0 - t)))

# --- floating markers ---------------------------------------------------------

func _marker_position(marker: Dictionary) -> Vector2:
	var button = marker.get("button", null)
	if button is Button and is_instance_valid(button):
		return (button as Button).position + Vector2((button as Button).size.x * .5, -30.0 * ui_scale)
	return _project(marker.get("world", Vector3.ZERO))

func _marker_visible(marker: Dictionary) -> bool:
	var button = marker.get("button", null)
	if button is Button:
		return is_instance_valid(button) and (button as Button).visible
	return _on_screen(marker.get("world", Vector3.ZERO))

func _draw_marker(marker: Dictionary) -> void:
	if not _marker_visible(marker): return
	var kind := str(marker.get("kind", "EVENT"))
	var phase := float(marker.get("phase", 0.0))
	var color: Color = MARKER_COLORS.get(kind, Color.WHITE)
	var float_y := sin(clock * 2.1 + phase) * 4.0 * ui_scale
	var center := _marker_position(marker) + Vector2(0, float_y)
	var radius := 20.0 * ui_scale
	var pulse := .5 + .5 * sin(clock * 3.2 + phase)
	# Ground tether and pulsing ring.
	draw_circle(center, radius * (1.35 + .25 * pulse), Color(color.r, color.g, color.b, .10 + .10 * pulse))
	draw_circle(center, radius + 2.5 * ui_scale, Color(0.02, 0.04, 0.07, .9))
	draw_arc(center, radius + 1.0 * ui_scale, 0.0, TAU, 32, Color(color.r, color.g, color.b, .75 + .25 * pulse), 2.4 * ui_scale, true)
	match kind:
		"BOSS": _draw_skull(center, radius * .72, color)
		"ELITE": _draw_star(center, radius * .7, color)
		"TREASURE": _draw_chest(center, radius * .7, color)
		_: _draw_exclaim(center, radius * .7, color)

func _draw_skull(c: Vector2, r: float, color: Color) -> void:
	var bone := Color("f4ece0")
	draw_circle(c + Vector2(0, -r * .18), r * .78, bone)
	draw_rect(Rect2(c + Vector2(-r * .46, r * .18), Vector2(r * .92, r * .52)), bone)
	var socket := Color(color.r * .35, color.g * .12, color.b * .12)
	draw_circle(c + Vector2(-r * .32, -r * .12), r * .22, socket)
	draw_circle(c + Vector2(r * .32, -r * .12), r * .22, socket)
	draw_circle(c + Vector2(-r * .32, -r * .12), r * .08, color)
	draw_circle(c + Vector2(r * .32, -r * .12), r * .08, color)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * .08), c + Vector2(-r * .09, r * .26), c + Vector2(r * .09, r * .26)]), socket)
	for tooth in range(3):
		var x := -r * .24 + float(tooth) * r * .24
		draw_line(c + Vector2(x + r * .12, r * .42), c + Vector2(x + r * .12, r * .70), socket, maxf(1.0, r * .07))

func _draw_star(c: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(8):
		var angle := -PI * .5 + TAU * float(index) / 8.0
		var reach := r if index % 2 == 0 else r * .42
		points.append(c + Vector2(cos(angle), sin(angle)) * reach)
	draw_colored_polygon(points, color)
	draw_circle(c, r * .2, Color("fff4ff"))

func _draw_chest(c: Vector2, r: float, color: Color) -> void:
	var body := Rect2(c + Vector2(-r * .82, -r * .12), Vector2(r * 1.64, r * .86))
	draw_rect(body, Color("8a5a2b"))
	draw_rect(Rect2(c + Vector2(-r * .82, -r * .62), Vector2(r * 1.64, r * .46)), Color("a86f35"))
	draw_rect(Rect2(c + Vector2(-r * .82, -r * .18), Vector2(r * 1.64, r * .12)), color)
	draw_rect(Rect2(c + Vector2(-r * .12, -r * .30), Vector2(r * .24, r * .34)), color)
	draw_rect(body.grow(0.5), Color("3a220e"), false, maxf(1.0, r * .08))

func _draw_exclaim(c: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * .20, -r * .82), c + Vector2(r * .20, -r * .82), c + Vector2(r * .11, r * .28), c + Vector2(-r * .11, r * .28)]), color)
	draw_circle(c + Vector2(0, r * .62), r * .16, color)
