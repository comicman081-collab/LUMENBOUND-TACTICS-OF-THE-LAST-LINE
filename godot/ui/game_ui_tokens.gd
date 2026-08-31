class_name GameUITokens
extends RefCounted

## Shared visual authority for the playable Godot UI.
##
## The game previously assembled every surface with unrelated inline colours,
## radii and margins.  Keeping the tokens in one code-native authority lets the
## fixed 1920x1080 canvas scale to desktop and mobile without design drift.

const BG_DEEPEST := Color("050a11")
const BG_CANVAS := Color("08111b")
const SURFACE := Color("0d1a28f5")
const SURFACE_RAISED := Color("172b3df8")
const SURFACE_HOVER := Color("20445d")
const SURFACE_PRESSED := Color("0a1420")

const BORDER := Color("66849fc4")
const BORDER_STRONG := Color("91abc1e0")
const TEXT := Color("fffdf7")
const TEXT_MUTED := Color("cad7e3")
const TEXT_FAINT := Color("9eb2c4")
const SIGNAL := Color("6ce6d0")
const SIGNAL_SOFT := Color("a9f2e5")
const OBJECTIVE := Color("e7bf68")
const OBJECTIVE_SOFT := Color("f5dda2")
const DANGER := Color("ef7b78")
const INK := Color("071018")

const RADIUS_CONTROL := 8
const RADIUS_PANEL := 14
const RADIUS_MODAL := 18

static func weighted_font(base_font: Font, weight: float, embolden := 0.0) -> Font:
	if base_font == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base_font
	variation.variation_opentype = {"wght": weight}
	variation.variation_embolden = embolden
	return variation

static func panel_style(
		fill: Color = SURFACE,
		border: Color = BORDER,
		border_width := 1,
		radius := RADIUS_PANEL,
		margins := Vector4(20.0, 16.0, 20.0, 16.0),
		shadow_size := 8
	) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margins.x
	style.content_margin_top = margins.y
	style.content_margin_right = margins.z
	style.content_margin_bottom = margins.w
	if shadow_size > 0:
		style.shadow_color = Color("00000073")
		style.shadow_size = shadow_size
		style.shadow_offset = Vector2(0.0, 4.0)
	return style

static func _button_palette(role: String, state: String) -> Dictionary:
	match role:
		"primary":
			return {
				"fill": SIGNAL_SOFT if state == "hover" else (Color("52cdb7") if state == "pressed" else SIGNAL),
				"border": Color("d5fff7"),
				"text": INK,
			}
		"objective":
			return {
				"fill": OBJECTIVE_SOFT if state == "hover" else (Color("c99f4e") if state == "pressed" else OBJECTIVE),
				"border": Color("fff3cf"),
				"text": INK,
			}
		"danger":
			return {
				"fill": Color("3d2025") if state != "hover" else Color("54282e"),
				"border": DANGER,
				"text": Color("ffd9d6"),
			}
		_:
			return {
				"fill": SURFACE_HOVER if state == "hover" else (SURFACE_PRESSED if state == "pressed" else SURFACE_RAISED),
				"border": SIGNAL if state in ["hover", "focus"] else BORDER,
				"text": TEXT,
			}

static func button_style(role := "secondary", state := "normal", margins := Vector4(18.0, 11.0, 18.0, 11.0)) -> StyleBoxFlat:
	var palette := _button_palette(role, state)
	var width := 2 if state == "focus" else 1
	if state == "disabled":
		return panel_style(Color("0a121c"), Color("2d3b49"), 1, RADIUS_CONTROL, margins, 0)
	var style := panel_style(palette.fill, palette.border, width, RADIUS_CONTROL, margins, 0)
	if state == "pressed":
		style.content_margin_top += 1.0
		style.content_margin_bottom -= 1.0
	return style

static func apply_button(button: Button, role := "secondary") -> void:
	button.add_theme_stylebox_override("normal", button_style(role, "normal"))
	button.add_theme_stylebox_override("hover", button_style(role, "hover"))
	button.add_theme_stylebox_override("pressed", button_style(role, "pressed"))
	button.add_theme_stylebox_override("focus", button_style(role, "focus"))
	button.add_theme_stylebox_override("disabled", button_style(role, "disabled"))
	var normal_palette := _button_palette(role, "normal")
	var hover_palette := _button_palette(role, "hover")
	button.add_theme_color_override("font_color", normal_palette.text)
	button.add_theme_color_override("font_hover_color", hover_palette.text)
	button.add_theme_color_override("font_pressed_color", normal_palette.text)
	button.add_theme_color_override("font_focus_color", normal_palette.text)
	button.add_theme_color_override("font_disabled_color", TEXT_FAINT)
	button.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	button.add_theme_constant_override("outline_size", 0)

static func build_theme(font: Font, ui_scale := 1.0) -> Theme:
	var value := Theme.new()
	var body_font := weighted_font(font, 520.0, 0.02)
	var button_font := weighted_font(font, 620.0, 0.035)
	var strong_font := weighted_font(font, 720.0, 0.05)
	if font != null:
		value.default_font = body_font
		value.set_font("font", "Label", body_font)
		value.set_font("font", "Button", button_font)
		value.set_font("normal_font", "RichTextLabel", body_font)
		value.set_font("bold_font", "RichTextLabel", strong_font)
	value.default_font_size = roundi(22.0 * ui_scale)
	value.set_font_size("font_size", "Label", roundi(22.0 * ui_scale))
	value.set_font_size("font_size", "Button", roundi(20.0 * ui_scale))
	value.set_font_size("normal_font_size", "RichTextLabel", roundi(21.0 * ui_scale))
	value.set_font_size("bold_font_size", "RichTextLabel", roundi(21.0 * ui_scale))
	value.set_color("font_color", "Label", TEXT)
	value.set_color("default_color", "RichTextLabel", TEXT)
	value.set_color("font_color", "Button", TEXT)
	value.set_color("font_hover_color", "Button", TEXT)
	value.set_color("font_pressed_color", "Button", TEXT)
	value.set_color("font_focus_color", "Button", TEXT)
	value.set_color("font_disabled_color", "Button", TEXT_FAINT)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		value.set_stylebox(state, "Button", button_style("secondary", state))
	value.set_stylebox("panel", "PanelContainer", panel_style())
	var separator := StyleBoxLine.new()
	separator.color = Color("6c84994d")
	separator.thickness = 1
	separator.grow_begin = 4.0
	separator.grow_end = 4.0
	value.set_stylebox("separator", "HSeparator", separator)
	return value
