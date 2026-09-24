extends RefCounted

## Shared cinematic layers for title, story and result screens: drifting
## backgrounds, light shafts, floating motes, low fog, Live2D-style idle motion
## for illustrations, title shine, pulsing button glow and entrance tweens.
## Everything is presentation-only and safe to build outside the SceneTree
## (tweens are skipped until the node is inside the tree).

const LIVE_PORTRAIT := preload("res://ui/shaders/live_portrait.gdshader")
const DRIFT := preload("res://ui/shaders/drift_background.gdshader")
const RAYS := preload("res://ui/shaders/light_rays.gdshader")
const MOTES := preload("res://ui/shaders/motes.gdshader")
const SHINE := preload("res://ui/shaders/text_shine.gdshader")
const FOG := preload("res://ui/shaders/fog_band.gdshader")

static func material(shader: Shader, params: Dictionary = {}) -> ShaderMaterial:
	var value := ShaderMaterial.new()
	value.shader = shader
	for key in params:
		value.set_shader_parameter(str(key), params[key])
	return value

static func _full_rect(node: Control) -> void:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func drift_background(parent: Node, texture: Texture2D, params: Dictionary = {}) -> TextureRect:
	var bg := TextureRect.new()
	bg.name = "CinematicBackground"
	bg.texture = texture
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_full_rect(bg)
	bg.material = material(DRIFT, params)
	parent.add_child(bg)
	return bg

static func _overlay(parent: Node, name_value: String, shader: Shader, params: Dictionary) -> ColorRect:
	var layer := ColorRect.new()
	layer.name = name_value
	layer.color = Color.WHITE
	_full_rect(layer)
	layer.material = material(shader, params)
	parent.add_child(layer)
	return layer

static func light_rays(parent: Node, params: Dictionary = {}) -> ColorRect:
	return _overlay(parent, "CinematicLightRays", RAYS, params)

static func motes(parent: Node, params: Dictionary = {}) -> ColorRect:
	return _overlay(parent, "CinematicMotes", MOTES, params)

static func fog(parent: Node, params: Dictionary = {}) -> ColorRect:
	return _overlay(parent, "CinematicFog", FOG, params)

## Stable per-character phase so two illustrations never breathe in unison.
static func seeded_phase(seed_text: String) -> float:
	return float(absi(hash(seed_text)) % 1000) / 1000.0 * TAU

static func live_portrait(target: CanvasItem, seed_text: String, params: Dictionary = {}) -> ShaderMaterial:
	var values := {"phase": seeded_phase(seed_text)}
	values.merge(params, true)
	var value := material(LIVE_PORTRAIT, values)
	target.material = value
	return value

static func shine(label: Label, params: Dictionary = {}) -> void:
	label.material = material(SHINE, params)

## Title-grade typography: warm outline and a deep drop shadow.
static func heroic_text(label: Label, outline := Color("1a0f05"), shadow := Color("000000aa")) -> void:
	label.add_theme_color_override("font_outline_color", outline)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_shadow_color", shadow)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 8)
	label.add_theme_constant_override("shadow_outline_size", 14)

## A soft glow halo behind a control that breathes in and out.
static func pulse_glow(target: Control, color: Color, spread := 18) -> Panel:
	var glow := Panel.new()
	glow.name = "PulseGlow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.show_behind_parent = true
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.0)
	style.shadow_color = Color(color.r, color.g, color.b, 0.55)
	style.shadow_size = spread
	style.set_corner_radius_all(10)
	glow.add_theme_stylebox_override("panel", style)
	target.add_child(glow)
	if glow.is_inside_tree():
		var tween := glow.create_tween().set_loops()
		tween.tween_property(glow, "modulate:a", 0.35, 1.1).set_trans(Tween.TRANS_SINE)
		tween.tween_property(glow, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)
	return glow

## Fade a control in after an optional delay; no-op outside the SceneTree.
## (Position is not animated: anchored controls have no final position until
## the first layout pass, and tweening from that zero would pin them top-left.)
static func entrance(target: CanvasItem, delay := 0.0, _offset := Vector2.ZERO, duration := 0.55) -> void:
	if not target.is_inside_tree():
		return
	target.modulate.a = 0.0
	var tween := target.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(target, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Cinematic letterbox bars that slide in from the top and bottom.
static func letterbox(parent: Control, ratio := 0.075) -> void:
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.name = "LetterboxTop" if top else "LetterboxBottom"
		bar.color = Color("020409")
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0 - ratio
		bar.anchor_bottom = ratio if top else 1.0
		parent.add_child(bar)
