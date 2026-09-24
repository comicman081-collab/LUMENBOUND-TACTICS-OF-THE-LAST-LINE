class_name BattleUltimateOrb
extends Button

## A compact, touch-safe tactical ultimate control.  The ordinary rectangular
## button was information-dense but looked like a text command rather than a
## combat resource.  This control keeps the actual Button hit target while
## drawing a portrait disc, a continuously readable outer charge ring, and a
## small READY badge at the top once the skill can be fired.

const PORTRAIT_SHADER := preload("res://battle/view/battle_ultimate_orb_portrait.gdshader")

var portrait_texture: Texture2D
var character_name := ""
var tactical_cost := 0
var accent := Color("70e7ff")
var charge_ratio := 0.0
var is_ready := false
## The combat source cells include a whole posed body.  The tactical control is
## intentionally a face portrait, so it owns an explicit crop rather than
## shrinking a complete sprite until the face disappears.
var portrait_focus := Vector2(.50, .50)
var portrait_zoom := 1.0

var portrait_rect: TextureRect
var portrait_material: ShaderMaterial
var ready_backdrop: Panel
var ready_badge: Label


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Ultimate"
	_clear_rectangular_button_theme()
	_build_layers()
	resized.connect(_layout_layers)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	_layout_layers()
	queue_redraw()


func configure(texture: Texture2D, display_name: String, cost: int, accent_color: Color, face_focus := Vector2(.50, .50), face_zoom := 1.0) -> void:
	portrait_texture = texture
	character_name = display_name
	tactical_cost = maxi(1, cost)
	accent = accent_color
	portrait_focus = face_focus.clamp(Vector2(.06, .06), Vector2(.94, .94))
	portrait_zoom = maxf(1.0, face_zoom)
	tooltip_text = "%s · ULTIMATE · TACTICAL %d" % [character_name, tactical_cost]
	if portrait_rect != null:
		portrait_rect.texture = portrait_texture
	_apply_portrait_crop()
	_layout_layers()
	queue_redraw()


func set_charge(tactical_gauge: float, maximum_gauge: float, ready: bool) -> void:
	# `maximum_gauge` is the individual skill cost, not a global ten-point cap.
	# That makes a five-cost ultimate visibly become ready halfway through the
	# shared tactical resource, while a ten-cost ultimate correctly needs a full
	# ring.  It is presentation-only and does not alter SkillRuntime authority.
	var safe_maximum := maxf(0.01, maximum_gauge)
	charge_ratio = clampf(tactical_gauge / safe_maximum, 0.0, 1.0)
	is_ready = ready
	if ready_badge != null:
		ready_badge.visible = is_ready
		# The badge bobs gently so a ready ultimate catches the eye.
		ready_badge.position.y = ready_backdrop.position.y + sin(Time.get_ticks_msec() * .006) * 2.5 if is_ready and ready_backdrop != null else ready_badge.position.y
	if ready_backdrop != null:
		ready_backdrop.visible = is_ready
	if portrait_material != null:
		portrait_material.set_shader_parameter("saturation", 1.0 if is_ready else .15 + .45 * charge_ratio)
		portrait_material.set_shader_parameter("brightness", 1.08 if is_ready else .55 + .3 * charge_ratio)
	queue_redraw()


func _clear_rectangular_button_theme() -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_theme_color_override("font_color", Color.TRANSPARENT)
	add_theme_color_override("font_disabled_color", Color.TRANSPARENT)
	add_theme_constant_override("outline_size", 0)


func _build_layers() -> void:
	portrait_rect = TextureRect.new()
	portrait_rect.name = "PortraitDisc"
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_rect.texture = portrait_texture
	portrait_material = ShaderMaterial.new()
	portrait_material.shader = PORTRAIT_SHADER
	portrait_rect.material = portrait_material
	add_child(portrait_rect)
	_apply_portrait_crop()

	ready_backdrop = Panel.new()
	ready_backdrop.name = "ReadyBackdrop"
	ready_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ready_backdrop.visible = is_ready
	add_child(ready_backdrop)

	ready_badge = Label.new()
	ready_badge.name = "ReadyBadge"
	ready_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ready_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ready_badge.text = "READY"
	ready_badge.visible = is_ready
	ready_badge.add_theme_color_override("font_color", Color("f7fff9"))
	ready_badge.add_theme_color_override("font_outline_color", Color("071018"))
	ready_badge.add_theme_constant_override("outline_size", 3)
	add_child(ready_badge)

func _layout_layers() -> void:
	if portrait_rect == null:
		return
	var diameter := minf(size.x, size.y)
	if diameter <= 1.0:
		return
	# Keep the energy ring readable without turning its hit target into a large
	# opaque disc. The face receives the visual priority, not the chrome.
	var inset := maxf(6.0, diameter * .082)
	var disc_size := maxf(1.0, diameter - inset * 2.0)
	var disc_origin := Vector2((size.x - disc_size) * .5, (size.y - disc_size) * .5)
	portrait_rect.position = disc_origin
	portrait_rect.size = Vector2(disc_size, disc_size)
	var badge_height := maxf(18.0, diameter * .17)
	var badge_width := diameter * .70
	var badge_position := Vector2((size.x - badge_width) * .5, diameter * .004)
	ready_backdrop.position = badge_position
	ready_backdrop.size = Vector2(badge_width, badge_height)
	var ready_style := StyleBoxFlat.new()
	ready_style.bg_color = Color(.012, .035, .070, .86)
	ready_style.border_color = Color(accent.r, accent.g, accent.b, .78)
	ready_style.set_border_width_all(maxi(1, roundi(diameter * .012)))
	ready_style.set_corner_radius_all(roundi(badge_height * .5))
	ready_backdrop.add_theme_stylebox_override("panel", ready_style)
	ready_badge.position = badge_position
	ready_badge.size = Vector2(badge_width, badge_height)
	ready_badge.add_theme_font_size_override("font_size", roundi(maxf(12.0, diameter * .155)))
	ready_badge.add_theme_constant_override("outline_size", maxi(3, roundi(diameter * .018)))
	queue_redraw()


func _apply_portrait_crop() -> void:
	if portrait_material == null:
		return
	portrait_material.set_shader_parameter("portrait_focus", portrait_focus)
	portrait_material.set_shader_parameter("portrait_zoom", portrait_zoom)


func _draw() -> void:
	var diameter := minf(size.x, size.y)
	if diameter <= 1.0:
		return
	var center := Vector2(size.x * .5, size.y * .5)
	var outer_radius := diameter * .485
	var ring_radius := diameter * .444
	var ring_width := maxf(3.0, diameter * .050)
	var alpha_scale := .44 if disabled else 1.0
	var core_tint := Color(.018, .045, .09, .92 * alpha_scale)
	draw_circle(center, outer_radius, core_tint)
	draw_circle(center, outer_radius, Color(accent.r, accent.g, accent.b, (.18 if is_ready else .10) * alpha_scale), false, maxf(1.5, diameter * .014), true)
	# Twelve thin notches make an empty ring still read as a charge instrument,
	# not a static portrait frame.
	for notch in range(12):
		var notch_angle := -PI * .5 + TAU * float(notch) / 12.0
		var inner := center + Vector2(cos(notch_angle), sin(notch_angle)) * (ring_radius - ring_width * .60)
		var outer := center + Vector2(cos(notch_angle), sin(notch_angle)) * (ring_radius + ring_width * .48)
		draw_line(inner, outer, Color(.64, .76, .88, .24 * alpha_scale), maxf(1.0, ring_width * .18), true)
	draw_arc(center, ring_radius, -PI * .5, TAU - PI * .5, 64, Color(.15, .23, .34, .92 * alpha_scale), ring_width, true)
	var charge_color := accent.lerp(Color("f7fff9"), .20)
	charge_color.a = (1.0 if is_ready else .94) * alpha_scale
	if charge_ratio > 0.002:
		draw_arc(center, ring_radius, -PI * .5, -PI * .5 + TAU * charge_ratio, 64, charge_color, ring_width, true)
	if is_ready:
		var now := Time.get_ticks_msec() * .001
		var pulse := .72 + .28 * (sin(now * 8.0) * .5 + .5)
		# Double halo plus a bright spark orbiting the ring.
		draw_circle(center, outer_radius + ring_width * 1.1, Color(accent.r, accent.g, accent.b, .16 * pulse * alpha_scale))
		draw_arc(center, outer_radius + ring_width * .18, -PI * .5, TAU - PI * .5, 64, Color(accent.r, accent.g, accent.b, .80 * pulse * alpha_scale), maxf(2.0, ring_width * .34), true)
		draw_arc(center, outer_radius + ring_width * .75, -PI * .5, TAU - PI * .5, 64, Color(accent.r, accent.g, accent.b, .35 * pulse * alpha_scale), maxf(1.5, ring_width * .20), true)
		var spark_angle := now * 3.2
		var spark := center + Vector2(cos(spark_angle), sin(spark_angle)) * ring_radius
		draw_circle(spark, ring_width * .85, Color(1.0, 1.0, 1.0, .9 * alpha_scale))
		draw_circle(spark, ring_width * 1.6, Color(accent.r, accent.g, accent.b, .35 * alpha_scale))
	# Gauge cost chip at the bottom of the disc.
	var chip_radius := diameter * .13
	var chip_center := center + Vector2(0.0, outer_radius - chip_radius * .55)
	draw_circle(chip_center, chip_radius, Color(.02, .05, .10, .95 * alpha_scale))
	draw_arc(chip_center, chip_radius, 0.0, TAU, 32, Color(accent.r, accent.g, accent.b, .9 * alpha_scale), maxf(1.5, diameter * .012), true)
	var chip_font := get_theme_default_font()
	var chip_size := roundi(maxf(11.0, diameter * .15))
	var chip_text := str(tactical_cost)
	var chip_width := chip_font.get_string_size(chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size).x
	draw_string(chip_font, chip_center + Vector2(-chip_width * .5, chip_size * .36), chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size, Color(1.0, .95, .75, alpha_scale))
	if is_hovered() and not disabled:
		draw_circle(center, outer_radius, Color(1.0, 1.0, 1.0, .075), false, maxf(1.5, ring_width * .24), true)
	if has_focus():
		draw_arc(center, outer_radius + ring_width * .80, 0.0, TAU, 48, Color("fff3b0"), maxf(2.0, ring_width * .28), true)
