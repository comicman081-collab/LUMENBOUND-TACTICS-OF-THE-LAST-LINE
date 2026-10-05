extends RefCounted

## Procedural ornament for banners, title cards and battle callouts.
##
## The "compromise" tone keeps the teal signal theme and adds metal-rail
## frames: a gold double rail with a teal lumen line inside it, diamond studs
## and short scroll curls at the ends. Everything is drawn with CanvasItem
## primitives from inside a caller's `_draw()`, so no texture or AI art is
## loaded and nothing here touches game state.

const GOLD := Color("e8c476")
const GOLD_SHADOW := Color("4a3412")
const GOLD_LIGHT := Color("fff1c4")
const LUMEN := Color("62f0dc")
const INK := Color(.018, .040, .075)
const ALERT := Color("ff4d4d")
const ALERT_DEEP := Color("5a0c12")

# Metrics depend only on the font resource, text and pixel size. Keep the
# exact font results while the moving bands change position/color every frame.
const TEXT_METRICS_LIMIT := 512
static var _text_metrics: Dictionary = {}
static var _metric_fonts: Dictionary = {}

static func tint(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(alpha, 0.0, 1.0))

static func quad(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	ci.draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([ca, cb, cc, cd]), PackedVector2Array())

static func _flat_primitive(ci: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	if points.size() == 3 or points.size() == 4:
		var colors := PackedColorArray()
		colors.resize(points.size())
		colors.fill(color)
		ci.draw_primitive(points, colors, PackedVector2Array())
	else:
		ci.draw_colored_polygon(points, color)

## A rect whose fill fades to transparent over `fade` pixels at both ends.
static func faded_rect(ci: CanvasItem, rect: Rect2, color: Color, fade: float) -> void:
	var edge := minf(fade, rect.size.x * .5)
	var clear := tint(color, 0.0)
	var top := rect.position.y
	var bottom := rect.end.y
	var x0 := rect.position.x
	var x1 := x0 + edge
	var x2 := rect.end.x - edge
	var x3 := rect.end.x
	quad(ci, Vector2(x0, top), Vector2(x1, top), Vector2(x1, bottom), Vector2(x0, bottom), clear, color, color, clear)
	if x2 > x1:
		ci.draw_rect(Rect2(Vector2(x1, top), Vector2(x2 - x1, bottom - top)), color)
	quad(ci, Vector2(x2, top), Vector2(x3, top), Vector2(x3, bottom), Vector2(x2, bottom), color, clear, clear, color)

static func diamond(ci: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	_flat_primitive(ci, PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius, 0),
		center + Vector2(0, radius), center + Vector2(-radius, 0)]), color)

## Gold stud with a lumen core.
static func stud(ci: CanvasItem, center: Vector2, radius: float, alpha: float, accent := LUMEN) -> void:
	diamond(ci, center, radius * 1.35, tint(GOLD_SHADOW, alpha * .9))
	diamond(ci, center, radius, tint(GOLD, alpha))
	diamond(ci, center, radius * .45, tint(accent.lightened(.25), alpha))

## A short curl leaving `origin` toward `direction` (+1 right, -1 left).
static func curl(ci: CanvasItem, origin: Vector2, direction: float, size: float, color: Color, width: float) -> void:
	var center := origin + Vector2(direction * size * .5, -size * .28)
	var start := PI * .5 if direction > 0.0 else PI * .5
	var sweep := -PI * 1.35 if direction > 0.0 else PI * 1.35
	ci.draw_arc(center, size * .5, start, start + sweep, 14, color, width, true)
	var tip := center + Vector2(cos(start + sweep), sin(start + sweep)) * size * .5
	ci.draw_circle(tip, width * .9, color)

## Gold double rail with a teal lumen line. `lumen_phase` in 0..1 draws a
## travelling highlight; a negative phase leaves the rail at rest.
static func rail(ci: CanvasItem, from: Vector2, to: Vector2, alpha: float, scale := 1.0, accent := LUMEN, lumen_phase := -1.0, inner_side := 1.0) -> void:
	var direction := (to - from).normalized()
	var normal := Vector2(-direction.y, direction.x) * inner_side
	ci.draw_line(from, to, tint(GOLD_SHADOW, alpha * .85), 4.2 * scale, true)
	ci.draw_line(from, to, tint(GOLD, alpha), 2.0 * scale, true)
	var inner := normal * 4.5 * scale
	ci.draw_line(from + inner, to + inner, tint(accent, alpha * .72), 1.2 * scale, true)
	if lumen_phase >= 0.0:
		var length := from.distance_to(to)
		var head := from + direction * length * fposmod(lumen_phase, 1.0)
		var tail := head - direction * minf(length * .16, 180.0 * scale)
		ci.draw_line(tail + inner, head + inner, tint(Color.WHITE, alpha * .85), 2.2 * scale, true)
		ci.draw_circle(head + inner, 2.4 * scale, tint(accent.lightened(.5), alpha))

## End piece for a band: stud, two curls and a short tapered spike.
static func band_end(ci: CanvasItem, point: Vector2, outward: float, height: float, alpha: float, scale := 1.0, accent := LUMEN) -> void:
	var gold := tint(GOLD, alpha)
	var spike := PackedVector2Array([
		point + Vector2(0, -height * .18), point + Vector2(outward * height * .62, 0), point + Vector2(0, height * .18)])
	ci.draw_colored_polygon(spike, tint(GOLD_SHADOW, alpha * .85))
	ci.draw_polyline(PackedVector2Array([spike[0], spike[1], spike[2]]), gold, 1.6 * scale, true)
	curl(ci, point + Vector2(0, -height * .24), -outward, height * .30, gold, 1.5 * scale)
	var lower_curl := point + Vector2(0, height * .24)
	ci.draw_arc(lower_curl + Vector2(-outward * height * .15, height * .08), height * .15, 0.0, TAU * .7, 12, gold, 1.5 * scale, true)
	stud(ci, point, 5.0 * scale, alpha, accent)

## Full-width or centred banner band: ink fill, rails above and below and
## ornamented ends. `fill` may be tinted (the boss band uses deep red).
static func band(ci: CanvasItem, rect: Rect2, alpha: float, scale := 1.0, accent := LUMEN, lumen_phase := -1.0, fill := INK, fade := 0.0) -> void:
	if rect.size.x <= 1.0 or alpha <= 0.0:
		return
	var body := tint(fill, alpha * .90)
	if fade > 0.0:
		faded_rect(ci, rect, body, fade)
	else:
		ci.draw_rect(rect, body)
	# A soft inner glow keeps the band from reading as a flat slab.
	var glow := Rect2(rect.position + Vector2(0, rect.size.y * .18), Vector2(rect.size.x, rect.size.y * .64))
	faded_rect(ci, glow, tint(accent, alpha * .07), maxf(fade, rect.size.x * .25))
	var inset := fade * .55
	var left := rect.position.x + inset
	var right := rect.end.x - inset
	rail(ci, Vector2(left, rect.position.y), Vector2(right, rect.position.y), alpha, scale, accent, lumen_phase, 1.0)
	rail(ci, Vector2(right, rect.end.y), Vector2(left, rect.end.y), alpha, scale, accent, lumen_phase, 1.0)
	if fade <= 0.0:
		band_end(ci, Vector2(left, rect.get_center().y), -1.0, rect.size.y, alpha, scale, accent)
		band_end(ci, Vector2(right, rect.get_center().y), 1.0, rect.size.y, alpha, scale, accent)
	else:
		stud(ci, Vector2(left, rect.position.y), 4.0 * scale, alpha, accent)
		stud(ci, Vector2(right, rect.position.y), 4.0 * scale, alpha, accent)
		stud(ci, Vector2(left, rect.end.y), 4.0 * scale, alpha, accent)
		stud(ci, Vector2(right, rect.end.y), 4.0 * scale, alpha, accent)

## L-shaped corner bracket with a stud and a curl. `sx`/`sy` are +1 or -1 and
## point from the corner into the frame.
static func corner(ci: CanvasItem, point: Vector2, sx: float, sy: float, arm: float, alpha: float, scale := 1.0, accent := LUMEN) -> void:
	var gold := tint(GOLD, alpha)
	var shadow := tint(GOLD_SHADOW, alpha * .85)
	var a := point + Vector2(sx * arm, 0)
	var b := point + Vector2(0, sy * arm)
	for pass_index in range(2):
		var color := shadow if pass_index == 0 else gold
		var width := (4.0 if pass_index == 0 else 2.0) * scale
		ci.draw_line(point, a, color, width, true)
		ci.draw_line(point, b, color, width, true)
	var inner := Vector2(sx, sy) * 5.0 * scale
	ci.draw_line(point + inner, point + inner + Vector2(sx * arm * .62, 0), tint(accent, alpha * .75), 1.2 * scale, true)
	ci.draw_line(point + inner, point + inner + Vector2(0, sy * arm * .62), tint(accent, alpha * .75), 1.2 * scale, true)
	ci.draw_arc(a + Vector2(-sx * arm * .12, sy * arm * .12), arm * .12, 0.0, TAU * .75, 10, gold, 1.4 * scale, true)
	ci.draw_arc(b + Vector2(sx * arm * .12, -sy * arm * .12), arm * .12, 0.0, TAU * .75, 10, gold, 1.4 * scale, true)
	stud(ci, point, 5.5 * scale, alpha, accent)

## Ornate rectangular frame: gold outer rail, lumen inner line, corner brackets
## and centred studs on the long edges.
static func frame(ci: CanvasItem, rect: Rect2, alpha: float, scale := 1.0, accent := LUMEN, fill := INK, fill_alpha := .88) -> void:
	if alpha <= 0.0:
		return
	if fill_alpha > 0.0:
		ci.draw_rect(rect, tint(fill, alpha * fill_alpha))
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var br := rect.end
	var bl := Vector2(rect.position.x, rect.end.y)
	ci.draw_polyline(PackedVector2Array([tl, tr, br, bl, tl]), tint(GOLD_SHADOW, alpha * .8), 4.0 * scale, true)
	ci.draw_polyline(PackedVector2Array([tl, tr, br, bl, tl]), tint(GOLD, alpha * .92), 1.6 * scale, true)
	var inset := 7.0 * scale
	var inner := rect.grow(-inset)
	ci.draw_rect(inner, tint(accent, alpha * .55), false, 1.0 * scale)
	var arm := clampf(minf(rect.size.x, rect.size.y) * .22, 18.0 * scale, 64.0 * scale)
	corner(ci, tl, 1.0, 1.0, arm, alpha, scale, accent)
	corner(ci, tr, -1.0, 1.0, arm, alpha, scale, accent)
	corner(ci, br, -1.0, -1.0, arm, alpha, scale, accent)
	corner(ci, bl, 1.0, -1.0, arm, alpha, scale, accent)
	stud(ci, Vector2(rect.get_center().x, rect.position.y), 5.0 * scale, alpha, accent)
	stud(ci, Vector2(rect.get_center().x, rect.end.y), 5.0 * scale, alpha, accent)

## Horizontal speed streaks travelling toward -x inside `rect`. Deterministic
## from `time` and `seed`, so capture tools get stable frames.
static func speed_lines(ci: CanvasItem, rect: Rect2, time: float, color: Color, count := 22, seed := 0, speed := 1.0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	for index in range(count):
		var h := float((index * 7919 + seed * 104729) % 1000) / 1000.0
		var h2 := float((index * 3571 + seed * 7727 + 331) % 1000) / 1000.0
		var y := rect.position.y + rect.size.y * h
		var length := rect.size.x * (.10 + .26 * h2)
		var travel := fposmod(h2 + time * speed * (1.4 + h), 1.0)
		var x := rect.end.x - (rect.size.x + length) * travel
		var start := Vector2(maxf(rect.position.x, x), y)
		var finish := Vector2(minf(rect.end.x, x + length), y)
		if finish.x <= start.x:
			continue
		var width := 1.0 + 2.6 * h2
		ci.draw_line(start, finish, tint(color, .35 + .5 * h), width, true)

## Centred text with an outline; returns the drawn width.
static func text_metrics(font: Font, text: String, size: int) -> Dictionary:
	var font_id := font.get_instance_id()
	if not _metric_fonts.has(font_id) or (_metric_fonts[font_id] as WeakRef).get_ref() != font:
		_metric_fonts[font_id] = weakref(font)
		var invalidate := _invalidate_text_metrics.bind(font_id)
		if not font.changed.is_connected(invalidate):
			font.changed.connect(invalidate)
	var key := "%d:%d:%s" % [font_id, size, text]
	if not _text_metrics.has(key):
		if _text_metrics.size() >= TEXT_METRICS_LIMIT:
			_text_metrics.clear()
		_text_metrics[key] = {
			"width": font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x,
			"ascent": font.get_ascent(size),
			"descent": font.get_descent(size),
		}
	return _text_metrics[key]

static func _invalidate_text_metrics(font_id: int) -> void:
	var prefix := "%d:" % font_id
	for key in _text_metrics.keys():
		if (key as String).begins_with(prefix):
			_text_metrics.erase(key)

static func centered_text(ci: CanvasItem, font: Font, center: Vector2, text: String, size: int, color: Color, outline := 0, outline_color := Color(0, 0, 0, .8)) -> float:
	if font == null or text.is_empty():
		return 0.0
	var metrics := text_metrics(font, text, size)
	var width := float(metrics.width)
	var ascent := float(metrics.ascent)
	var descent := float(metrics.descent)
	var baseline := Vector2(center.x - width * .5, center.y + (ascent - descent) * .5)
	if outline > 0:
		ci.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_color)
	ci.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return width

## Diagonal hazard chevrons for the boss band.
static func hazard_stripes(ci: CanvasItem, rect: Rect2, time: float, color: Color, stripe := 22.0) -> void:
	var slant := rect.size.y
	var offset := fposmod(time * stripe * 2.0, stripe * 2.0)
	var x := rect.position.x - slant - stripe * 2.0 + offset
	while x < rect.end.x:
		var polygon := _hazard_stripe_polygon(rect, x, stripe)
		# Clipping at the band ends can leave a sliver with no area, which the
		# renderer cannot triangulate; those are invisible anyway.
		if polygon.size() >= 3 and absf(_polygon_area(polygon)) > .5:
			_flat_primitive(ci, polygon, color)
		x += stripe * 2.0

static func _hazard_stripe_polygon(rect: Rect2, x: float, stripe: float) -> PackedVector2Array:
	var right := x + stripe + rect.size.y
	if right <= rect.position.x or x >= rect.end.x:
		return PackedVector2Array()
	var polygon := PackedVector2Array([
		Vector2(x, rect.end.y), Vector2(x + stripe, rect.end.y),
		Vector2(right, rect.position.y), Vector2(x + rect.size.y, rect.position.y),
	])
	# All four vertices lie on/in the same rectangular band. Only the two
	# moving boundary stripes need the original polygon intersection routine.
	if x >= rect.position.x and right <= rect.end.x:
		return polygon
	var clipped := Geometry2D.intersect_polygons(polygon, PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
	]))
	return clipped[0] if not clipped.is_empty() else PackedVector2Array()

static func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index in polygon.size():
		area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	return area * .5
