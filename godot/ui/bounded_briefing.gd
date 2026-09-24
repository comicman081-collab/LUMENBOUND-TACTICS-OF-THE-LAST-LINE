extends PanelContainer

# Only the reading area may grow. Header and real button hit targets remain
# outside its scroll, including after rotating an already-open encounter.
var stack := VBoxContainer.new()
var header := HBoxContainer.new()
var body_scroll := preload("res://ui/touch_progression_scroll.gd").new()
var body := VBoxContainer.new()
var footer := HBoxContainer.new()
var font_targets: Dictionary = {}
var art_targets: Array[Control] = []
var runtime_size_reader: Callable
var preferred_height_css := 520.0
var _fit_queued := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(stack)
	stack.add_child(header)
	body_scroll.name = "BriefingBodyScroll"
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	stack.add_child(body_scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(body)
	stack.add_child(footer)
	footer.alignment = BoxContainer.ALIGNMENT_END

func _ready() -> void:
	get_viewport().size_changed.connect(reflow)
	body.minimum_size_changed.connect(_queue_fit)
	call_deferred("reflow")

func type_target(control: Control, css_size: float) -> void:
	font_targets[control] = css_size
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE if not control is Button else Control.MOUSE_FILTER_STOP
	if control is Button:
		control.set_meta("compact_reward_control", true)

static func frame_css(viewport_css: Vector2, preferred_height := 520.0) -> Rect2:
	var extent := Vector2(minf(680.0, viewport_css.x - 24.0), minf(preferred_height, viewport_css.y - 32.0))
	return Rect2((viewport_css - extent) * 0.5, extent)

func reflow() -> void:
	if not is_inside_tree() or not runtime_size_reader.is_valid(): return
	var viewport_css: Vector2 = runtime_size_reader.call()
	var scale_factor := maxf(minf(viewport_css.x / 1920.0, viewport_css.y / 1080.0), 0.001)
	var px := 1.0 / scale_factor
	var frame := frame_css(viewport_css, preferred_height_css)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = Vector2.ZERO
	var style := StyleBoxFlat.new()
	style.bg_color = Color("08121ffa")
	style.border_color = Color("54867f")
	style.set_border_width_all(maxi(1, roundi(px)))
	style.set_corner_radius_all(roundi(12.0 * px))
	style.content_margin_left = 14.0 * px
	style.content_margin_right = 14.0 * px
	style.content_margin_top = 12.0 * px
	style.content_margin_bottom = 12.0 * px
	add_theme_stylebox_override("panel", style)
	for box in [stack, header, body, footer]:
		box.add_theme_constant_override("separation", roundi(10.0 * px))
	for control in font_targets:
		if not is_instance_valid(control): continue
		control.add_theme_font_size_override("font_size", roundi(float(font_targets[control]) * px))
		if control is RichTextLabel:
			control.add_theme_font_size_override("normal_font_size", roundi(float(font_targets[control]) * px))
			control.add_theme_font_size_override("bold_font_size", roundi(float(font_targets[control]) * px))
			control.add_theme_constant_override("line_separation", roundi(4.0 * px))
		if control is Label:
			control.add_theme_constant_override("line_spacing", roundi(4.0 * px))
		if control is Button:
			control.custom_minimum_size = Vector2(112.0 * px, 52.0 * px)
			control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for art in art_targets:
		art.custom_minimum_size = Vector2(86.0, 110.0) * px
	body_scroll.custom_minimum_size.y = 32.0 * px
	body_scroll.scroll_deadzone = roundi(12.0 * px)
	body_scroll.get_v_scroll_bar().custom_minimum_size.x = 8.0 * px
	# Assign after reducing all children: a previous portrait minimum must not
	# clamp the new landscape frame before its scroll can absorb the content.
	position = frame.position * px
	size = frame.size * px
	_queue_fit()

func _queue_fit() -> void:
	if _fit_queued or not is_inside_tree(): return
	_fit_queued = true
	call_deferred("_fit_content")

func _fit_content() -> void:
	_fit_queued = false
	if not is_inside_tree() or not runtime_size_reader.is_valid(): return
	var viewport_css: Vector2 = runtime_size_reader.call()
	var scale_factor := maxf(minf(viewport_css.x / 1920.0, viewport_css.y / 1080.0), 0.001)
	var style := get_theme_stylebox("panel")
	var reading_height := body.get_combined_minimum_size().y
	var chrome_height := header.get_combined_minimum_size().y + footer.get_combined_minimum_size().y + style.get_minimum_size().y + 2.0 * stack.get_theme_constant("separation")
	var fitted_height := clampf((reading_height + chrome_height) * scale_factor + 2.0, 240.0, preferred_height_css)
	var frame := frame_css(viewport_css, fitted_height)
	position = frame.position / scale_factor
	size = frame.size / scale_factor

func rewind() -> void:
	body_scroll.set_deferred("scroll_vertical", 0)
