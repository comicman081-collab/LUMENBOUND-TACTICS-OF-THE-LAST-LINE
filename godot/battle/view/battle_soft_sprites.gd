extends RefCounted

## Cached procedural sprites for the battle view (r22).
##
## Contact shadows, footing glows, motes, bag outlines and unit rings are soft
## ellipses and thin rings. They were drawn as polygon and polyline commands,
## four or five per unit, so a busy battle recorded ~100 of them every frame.
## The Web (Compatibility) renderer builds and frees GPU buffers for each such
## command on every redraw; a textured rectangle is batched instead. Each
## texture here is filled once from simple coverage maths, as white pixels with
## an alpha edge, so callers tint it with `modulate`.

## Ellipse textures: 128x32 keeps a clean edge for the widest shadows (about
## 320 px); 64x16 serves the small ones (contact core, sandbags) without
## sampling a 3x minified edge; 32x32 is the disc for round markers.
const ELLIPSE_WIDTH := 128
const ELLIPSE_HEIGHT := 32
const SMALL_WIDTH := 64
const SMALL_HEIGHT := 16
const DISC_SIZE := 32
## Ellipses narrower than this many pixels use the small texture.
const SMALL_BELOW := 40.0
## Transparent border around a ring so its anti-aliased edge is never clipped.
const RING_MARGIN := 2.0

static var _cache: Dictionary = {}

## Filled ellipse inscribed in the texture. Draw it into any rectangle.
static func ellipse() -> Texture2D:
	if not _cache.has("ellipse"):
		_cache["ellipse"] = _texture(ELLIPSE_WIDTH, ELLIPSE_HEIGHT, 0.0, 0.0, 0.0)
	return _cache["ellipse"]

static func small_ellipse() -> Texture2D:
	if not _cache.has("small"):
		_cache["small"] = _texture(SMALL_WIDTH, SMALL_HEIGHT, 0.0, 0.0, 0.0)
	return _cache["small"]

static func disc() -> Texture2D:
	if not _cache.has("disc"):
		_cache["disc"] = _texture(DISC_SIZE, DISC_SIZE, 0.0, 0.0, 0.0)
	return _cache["disc"]

## Elliptical ring of constant pixel `width` around semi-axes rx, ry (pixels at
## zoom 1). The texture is centred on the ellipse; its pixel size is ring_size().
static func ring(rx: float, ry: float, width: float) -> Texture2D:
	var key := "ring|%.2f|%.2f|%.2f" % [rx, ry, width]
	if not _cache.has(key):
		var extent := ring_size(rx, ry, width)
		_cache[key] = _texture(int(extent.x), int(extent.y), rx, ry, width)
	return _cache[key]

static func ring_size(rx: float, ry: float, width: float) -> Vector2:
	return Vector2(ceilf(2.0 * (rx + width * .5 + RING_MARGIN)), ceilf(2.0 * (ry + width * .5 + RING_MARGIN)))

## Rectangle that places a ring texture on `center`, scaled by the camera zoom.
static func ring_rect(center: Vector2, rx: float, ry: float, width: float, zoom: float) -> Rect2:
	var extent := ring_size(rx, ry, width) * zoom
	return Rect2(center - extent * .5, extent)

## Draws a filled ellipse of the given radii (already in screen pixels).
static func draw_ellipse(canvas: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	var texture := ellipse() if radii.x >= SMALL_BELOW else small_ellipse()
	canvas.draw_texture_rect(texture, Rect2(center - radii, radii * 2.0), false, color)

## Draws a filled circle (radius in screen pixels).
static func draw_disc(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	canvas.draw_texture_rect(disc(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)

## ring_width == 0 renders the filled ellipse inscribed in the texture.
static func _texture(width: int, height: int, ring_rx: float, ring_ry: float, ring_width: float) -> Texture2D:
	var data := PackedByteArray()
	data.resize(width * height * 4)
	var half_x := float(width) * .5
	var half_y := float(height) * .5
	var rx := ring_rx if ring_width > 0.0 else half_x
	var ry := ring_ry if ring_width > 0.0 else half_y
	var half_stroke := ring_width * .5
	var offset := 0
	for y in range(height):
		var qy := float(y) + .5 - half_y
		for x in range(width):
			var qx := float(x) + .5 - half_x
			var nx := qx / rx
			var ny := qy / ry
			var radius := sqrt(nx * nx + ny * ny)
			var coverage := 0.0
			if radius > .0001:
				# First-order distance to the curve r == 1, in pixels: accurate
				# within a pixel or two of the edge, which is all that is seen.
				var gx := qx / (rx * rx)
				var gy := qy / (ry * ry)
				var slope := sqrt(gx * gx + gy * gy) / radius
				var distance := (radius - 1.0) / maxf(slope, .000001)
				if ring_width > 0.0:
					coverage = clampf(half_stroke + .5 - absf(distance), 0.0, 1.0)
				else:
					coverage = clampf(.5 - distance, 0.0, 1.0)
			elif ring_width <= 0.0:
				coverage = 1.0
			data[offset] = 255
			data[offset + 1] = 255
			data[offset + 2] = 255
			data[offset + 3] = int(roundf(coverage * 255.0))
			offset += 4
	return ImageTexture.create_from_image(Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data))
