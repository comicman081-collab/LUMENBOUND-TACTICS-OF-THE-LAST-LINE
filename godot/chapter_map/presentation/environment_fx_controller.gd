class_name EnvironmentFXController
extends Control

# Presentation-only environment controller. It deliberately has no reference
# to AppState, SaveService, map simulation, reward services or RNG. Its input
# is an optional transient world coordinate and its output is render state.

const GradeShader := preload("res://chapter_map/shaders/environment_grade.gdshader")
const FogShader := preload("res://chapter_map/shaders/environment_fog.gdshader")
const RainShader := preload("res://chapter_map/shaders/environment_rain.gdshader")

const PRESETS := {
	"CLEAR_DAY": {
		"brightness": 0.87, "contrast": 1.15, "saturation": 0.94,
		"ambient_energy": 0.65, "ambient_color": Color("9d9d80"), "fog_color": Color("9da796"),
		"fog_density": 0.045, "fog_world_density": 0.0017, "fog_energy": 0.52,
		"world_tint": Color(0.04, 0.07, 0.04, 0.018), "vignette": 0.025,
		"rain": 0.0, "rain_speed": 0.85, "wind": 0.08, "wetness": 0.0, "water_ripple": 0.15,
	},
	"MIST_DAY": {
		"brightness": 0.83, "contrast": 1.08, "saturation": 0.90,
		"ambient_energy": 0.64, "ambient_color": Color("9b9b82"), "fog_color": Color("a6ac99"),
		"fog_density": 0.20, "fog_world_density": 0.0038, "fog_energy": 0.62,
		"world_tint": Color(0.20, 0.31, 0.26, 0.045), "vignette": 0.045,
		"rain": 0.0, "rain_speed": 0.92, "wind": 0.04, "wetness": 0.08, "water_ripple": 0.20,
	},
	"DUSK": {
		"brightness": 0.86, "contrast": 1.05, "saturation": 1.00,
		"ambient_energy": 0.71, "ambient_color": Color("d5ad83"), "fog_color": Color("ad836c"),
		"fog_density": 0.095, "fog_world_density": 0.0027, "fog_energy": 0.56,
		"world_tint": Color(0.28, 0.13, 0.05, 0.055), "vignette": 0.065,
		"rain": 0.0, "rain_speed": 0.92, "wind": 0.12, "wetness": 0.04, "water_ripple": 0.20,
	},
	"NIGHT": {
		"brightness": 0.77, "contrast": 1.04, "saturation": 0.91,
		"ambient_energy": 0.67, "ambient_color": Color("829890"), "fog_color": Color("708b87"),
		"fog_density": 0.12, "fog_world_density": 0.0030, "fog_energy": 0.56,
		"world_tint": Color(0.03, 0.10, 0.15, 0.08), "vignette": 0.085,
		"rain": 0.0, "rain_speed": 1.0, "wind": 0.10, "wetness": 0.05, "water_ripple": 0.23,
	},
	"NIGHT_RAIN": {
		"brightness": 0.77, "contrast": 1.00, "saturation": 0.93,
		"ambient_energy": 0.68, "ambient_color": Color("98a68d"), "fog_color": Color("7b9082"),
		"fog_density": 0.16, "fog_world_density": 0.0036, "fog_energy": 0.58,
		"world_tint": Color(0.03, 0.10, 0.12, 0.085), "vignette": 0.09,
		"rain": 0.42, "rain_speed": 1.10, "wind": 0.18, "wetness": 0.48, "water_ripple": 0.62,
	},
	"STORM": {
		"brightness": 0.67, "contrast": 1.02, "saturation": 0.84,
		"ambient_energy": 0.59, "ambient_color": Color("778b82"), "fog_color": Color("667c78"),
		"fog_density": 0.25, "fog_world_density": 0.0052, "fog_energy": 0.62,
		"world_tint": Color(0.02, 0.08, 0.12, 0.13), "vignette": 0.14,
		"rain": 0.68, "rain_speed": 1.42, "wind": 0.36, "wetness": 0.74, "water_ripple": 0.90,
	},
}

const NUMERIC_FIELDS := ["brightness", "contrast", "saturation", "ambient_energy", "fog_density", "fog_world_density", "fog_energy", "vignette", "rain", "rain_speed", "wind", "wetness", "water_ripple"]
const COLOR_FIELDS := ["ambient_color", "fog_color", "world_tint"]

var active_preset := "CLEAR_DAY"
var target_preset := "CLEAR_DAY"
var current_values: Dictionary = PRESETS["CLEAR_DAY"].duplicate(true)
var from_values: Dictionary = PRESETS["CLEAR_DAY"].duplicate(true)
var target_values: Dictionary = PRESETS["CLEAR_DAY"].duplicate(true)
var transition_elapsed := 0.0
var transition_duration := 0.0
var preferred_transition_duration := 0.9
var quality_tier := "HIGH"
var tuning_overrides := {}
# Development tuning may temporarily pin a visual preset for inspection.  It is
# deliberately transient: it is not saved, does not alter the map context, and
# is cleared by the reset action or a fresh scene load.
var development_preset_override := ""
var map_environment: Environment
var terrain_material: StandardMaterial3D
var water_material: ShaderMaterial
var sun_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var grade_rect: ColorRect
var far_fog_rect: ColorRect
var near_fog_rect: ColorRect
var rain_rects: Array[ColorRect] = []
var canvas_layer: Control
var dev_panel: PanelContainer
var camera_phase := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

static func preset_ids() -> Array[String]:
	return ["CLEAR_DAY", "MIST_DAY", "DUSK", "NIGHT", "NIGHT_RAIN", "STORM"]

static func preset_values(preset_id: String) -> Dictionary:
	var safe_id := preset_id if PRESETS.has(preset_id) else "CLEAR_DAY"
	return PRESETS[safe_id].duplicate(true)

func attach_canvas(layer: Control) -> void:
	if layer == null or grade_rect != null:
		return
	canvas_layer = Control.new()
	canvas_layer.name = "EnvironmentPresentationLayer"
	canvas_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# This controller node is positioned by ChapterMapScreen between the 3D
	# viewport and interaction overlay. Keeping all rects under it preserves that
	# ordering instead of appending visual fog above the HUD.
	add_child(canvas_layer)
	far_fog_rect = _make_rect(FogShader)
	near_fog_rect = _make_rect(FogShader)
	grade_rect = _make_rect(GradeShader)
	# Fog/rain stay above 3D world but below map interaction and HUD controls.
	canvas_layer.add_child(far_fog_rect)
	canvas_layer.add_child(near_fog_rect)
	for index in range(3):
		var rain_rect := _make_rect(RainShader)
		rain_rects.append(rain_rect)
		canvas_layer.add_child(rain_rect)
	canvas_layer.add_child(grade_rect)
	_apply_canvas()

func bind_world(environment: Environment, terrain: StandardMaterial3D, water: ShaderMaterial, sun: DirectionalLight3D, fill: DirectionalLight3D) -> void:
	map_environment = environment
	terrain_material = terrain
	water_material = water
	sun_light = sun
	fill_light = fill
	_apply_world()

func set_preset(preset_id: String, duration := 0.9) -> void:
	if not PRESETS.has(preset_id):
		return
	if target_preset == preset_id and transition_duration > 0.0:
		return
	target_preset = preset_id
	from_values = current_values.duplicate(true)
	target_values = _effective_values(preset_id)
	transition_elapsed = 0.0
	transition_duration = clampf(duration, 0.5, 2.0)
	if duration <= 0.0:
		transition_duration = 0.0
		current_values = target_values.duplicate(true)
		active_preset = preset_id
		_apply_all()

func set_quality_tier(tier: String) -> void:
	quality_tier = "LOW" if tier == "LOW" else "HIGH"
	_apply_canvas()

func set_preferred_transition_duration(duration: float) -> void:
	preferred_transition_duration = clampf(duration, 0.5, 2.0)

func toggle_development_panel(parent: Control) -> void:
	if parent == null:
		return
	if dev_panel != null:
		dev_panel.visible = not dev_panel.visible
		return
	dev_panel = PanelContainer.new()
	dev_panel.name = "EnvironmentFXDevelopmentPanel"
	var viewport_size := parent.get_viewport().get_visible_rect().size
	var portrait := viewport_size.y > viewport_size.x
	var panel_ui_scale := 1.0
	var panel_width := 342.0
	var panel_height := 582.0
	if portrait:
		# The map remains on the 1920-wide logical canvas in portrait Web views.
		# Derive offsets from the real viewport so this developer-only sheet is
		# fully visible instead of becoming a narrow, clipped right-hand strip.
		# The content itself must use the same inverse scale; otherwise a 320
		# logical-pixel VBox becomes only about 65 CSS pixels wide on a phone.
		var canvas_scale := viewport_size.x / maxf(parent.size.x, 1.0)
		# CanvasItems are uniformly fitted from the logical 16:9 canvas.  Deriving
		# height from the physical viewport's Y scale here collapsed the portrait
		# sheet to roughly two rows.  Use the canvas scale consistently for both
		# axes, then reserve the lower 30% for browser UI/safe-area comfort.
		panel_ui_scale = clampf(1.0 / maxf(canvas_scale, 0.001), 2.8, 4.9)
		panel_width = viewport_size.x * 0.91 / maxf(canvas_scale, 0.001)
		# `visible_rect` is the expanded logical canvas (1920×4159 at 390×844),
		# not CSS pixels.  Size the sheet from the actual map region instead of
		# applying a physical-pixel cap to logical coordinates.
		panel_height = parent.size.y * 0.85
		dev_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		dev_panel.offset_left = viewport_size.x * 0.045 / maxf(canvas_scale, 0.001)
		dev_panel.offset_right = viewport_size.x * 0.955 / maxf(canvas_scale, 0.001)
		var panel_top := parent.size.x * 0.045
		dev_panel.offset_top = panel_top
		dev_panel.offset_bottom = panel_top + panel_height
	else:
		dev_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		dev_panel.offset_left = -360.0
		dev_panel.offset_top = 92.0
		dev_panel.offset_right = -18.0
		dev_panel.offset_bottom = 674.0
	dev_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	dev_panel.size = Vector2(panel_width, panel_height)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("071b2cf2")
	panel_style.border_color = Color("4b8790")
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 12.0 * panel_ui_scale
	panel_style.content_margin_right = 12.0 * panel_ui_scale
	panel_style.content_margin_top = 10.0 * panel_ui_scale
	panel_style.content_margin_bottom = 10.0 * panel_ui_scale
	dev_panel.add_theme_stylebox_override("panel", panel_style)
	dev_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dev_panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(panel_width, panel_height)
	dev_panel.add_child(scroll)
	# Anchors must be resolved after the ScrollContainer has a parent.  Resolving
	# PRESET_FULL_RECT before add_child() leaves the portrait sheet at its
	# content-minimum height, so only the first two controls were visible.
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(maxf(320.0 * panel_ui_scale, panel_width), 0.0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	var heading := Label.new()
	heading.text = "환경 FX 조정 · 개발 전용"
	heading.add_theme_font_size_override("font_size", roundi(19.0 * panel_ui_scale))
	box.add_child(heading)
	var preset := OptionButton.new()
	for preset_id in preset_ids():
		preset.add_item(preset_id)
	preset.selected = preset_ids().find(target_preset)
	preset.item_selected.connect(func(index: int): set_development_preset(preset_ids()[index]))
	box.add_child(_field_row("프리셋", preset, panel_ui_scale))
	var time_of_day := OptionButton.new()
	for time_id in ["CLEAR_DAY", "DUSK", "NIGHT"]:
		time_of_day.add_item(time_id)
	time_of_day.item_selected.connect(func(index: int): set_development_preset(["CLEAR_DAY", "DUSK", "NIGHT"][index]))
	box.add_child(_field_row("시간대", time_of_day, panel_ui_scale))
	_add_tuning_slider(box, "밝기", "brightness", 0.30, 1.20, 0.01, panel_ui_scale)
	_add_tuning_slider(box, "채도", "saturation", 0.20, 1.20, 0.01, panel_ui_scale)
	_add_tuning_slider(box, "대비", "contrast", 0.70, 1.40, 0.01, panel_ui_scale)
	_add_tuning_slider(box, "안개 농도", "fog_density", 0.0, 0.70, 0.01, panel_ui_scale)
	var fog_tint := OptionButton.new()
	fog_tint.add_item("차가운 안개")
	fog_tint.add_item("중립 안개")
	fog_tint.add_item("따뜻한 안개")
	fog_tint.item_selected.connect(func(index: int):
		var colors := [Color("153d55"), Color("64848a"), Color("684b45")]
		set_tuning_override("fog_color", colors[index])
	)
	box.add_child(_field_row("안개 색", fog_tint, panel_ui_scale))
	_add_tuning_slider(box, "비네트", "vignette", 0.0, 0.45, 0.01, panel_ui_scale)
	_add_tuning_slider(box, "비 강도", "rain", 0.0, 1.0, 0.01, panel_ui_scale)
	_add_tuning_slider(box, "비 속도", "rain_speed", 0.2, 2.5, 0.01, panel_ui_scale)
	_add_tuning_slider(box, "바람", "wind", -0.65, 0.65, 0.01, panel_ui_scale)
	_add_tuning_slider(box, "젖음", "wetness", 0.0, 1.0, 0.01, panel_ui_scale)
	_add_tuning_slider(box, "물결", "water_ripple", 0.0, 1.0, 0.01, panel_ui_scale)
	var transition := HSlider.new()
	transition.min_value = 0.5
	transition.max_value = 2.0
	transition.step = 0.05
	transition.value = preferred_transition_duration
	transition.value_changed.connect(func(value: float): set_preferred_transition_duration(value))
	box.add_child(_field_row("전환 시간", transition, panel_ui_scale))
	var quality := OptionButton.new()
	quality.add_item("HIGH")
	quality.add_item("LOW")
	quality.item_selected.connect(func(index: int): set_quality_tier("HIGH" if index == 0 else "LOW"))
	box.add_child(_field_row("품질", quality, panel_ui_scale))
	var reset := Button.new()
	reset.text = "프리셋으로 초기화"
	reset.custom_minimum_size = Vector2(0.0, 48.0 * panel_ui_scale)
	reset.pressed.connect(func(): reset_to_preset())
	box.add_child(reset)

func _field_row(label_text: String, control: Control, ui_scale := 1.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(96.0 * ui_scale, 30.0 * ui_scale)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _add_tuning_slider(parent: Container, label_text: String, field: String, minimum: float, maximum: float, step: float, ui_scale := 1.0) -> void:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = clampf(float(current_values.get(field, minimum)), minimum, maximum)
	slider.value_changed.connect(func(value: float): set_tuning_override(field, value))
	parent.add_child(_field_row(label_text, slider, ui_scale))

func set_tuning_override(field: String, value) -> void:
	if not NUMERIC_FIELDS.has(field) and not COLOR_FIELDS.has(field):
		return
	tuning_overrides[field] = value
	current_values = _effective_values(active_preset)
	target_values = _effective_values(target_preset)
	_apply_all()

func reset_to_preset() -> void:
	tuning_overrides.clear()
	development_preset_override = ""
	preferred_transition_duration = 0.9
	quality_tier = "HIGH"
	current_values = preset_values(active_preset)
	target_values = preset_values(target_preset)
	_apply_all()

func set_transient_map_context(coord: Vector2i, hard_route: bool) -> void:
	# Region grading is derived only from the transient position. It is intentionally
	# not saved and cannot alter topology, pathfinding or any simulation state.
	var preset_id := "CLEAR_DAY"
	if coord.x >= 88:
		preset_id = "STORM"
	elif coord.x >= 76:
		preset_id = "NIGHT_RAIN"
	elif coord.x >= 62:
		preset_id = "NIGHT"
	elif coord.x >= 46:
		preset_id = "DUSK"
	elif coord.x >= 26:
		preset_id = "MIST_DAY"
	if hard_route and preset_id == "CLEAR_DAY":
		preset_id = "NIGHT_RAIN"
	if not development_preset_override.is_empty():
		return
	if preset_id != target_preset:
		set_preset(preset_id, 0.95)

func set_development_preset(preset_id: String) -> void:
	if not PRESETS.has(preset_id):
		return
	development_preset_override = preset_id
	set_preset(preset_id, preferred_transition_duration)

func set_camera_phase(world_position: Vector3) -> void:
	camera_phase = world_position.x * 0.11 + world_position.z * 0.07

func transition_progress() -> float:
	return 1.0 if transition_duration <= 0.0 else clampf(transition_elapsed / transition_duration, 0.0, 1.0)

func presentation_snapshot() -> Dictionary:
	return {"active": active_preset, "target": target_preset, "progress": transition_progress(), "quality": quality_tier, "values": current_values.duplicate(true)}

func _process(delta: float) -> void:
	if transition_duration > 0.0 and transition_elapsed < transition_duration:
		transition_elapsed = minf(transition_duration, transition_elapsed + delta)
		var weight := transition_progress()
		current_values = _interpolated_values(from_values, target_values, weight)
		if weight >= 1.0:
			active_preset = target_preset
		_apply_all()

func _effective_values(preset_id: String) -> Dictionary:
	var values := preset_values(preset_id)
	for field in tuning_overrides:
		values[field] = tuning_overrides[field]
	return values

func _interpolated_values(from: Dictionary, destination: Dictionary, weight: float) -> Dictionary:
	var result := {}
	for field in NUMERIC_FIELDS:
		result[field] = lerpf(float(from.get(field, 0.0)), float(destination.get(field, 0.0)), weight)
	for field in COLOR_FIELDS:
		var from_color: Color = from.get(field, Color.WHITE)
		var destination_color: Color = destination.get(field, Color.WHITE)
		result[field] = from_color.lerp(destination_color, weight)
	return result

func _apply_all() -> void:
	_apply_world()
	_apply_canvas()

func _apply_world() -> void:
	if map_environment != null:
		map_environment.ambient_light_color = current_values.get("ambient_color", Color.WHITE)
		map_environment.ambient_light_energy = float(current_values.get("ambient_energy", 0.66))
		map_environment.adjustment_brightness = float(current_values.get("brightness", 0.82))
		map_environment.adjustment_contrast = float(current_values.get("contrast", 1.0))
		map_environment.adjustment_saturation = float(current_values.get("saturation", 1.0))
		map_environment.fog_light_color = current_values.get("fog_color", Color("0a3145"))
		map_environment.fog_density = float(current_values.get("fog_world_density", 0.0022))
		map_environment.fog_light_energy = float(current_values.get("fog_energy", 0.46))
	if terrain_material != null:
		var wetness := float(current_values.get("wetness", 0.0))
		terrain_material.roughness = lerpf(0.92, 0.70, wetness)
		terrain_material.albedo_color = Color(1.0 - wetness * 0.10, 1.0 - wetness * 0.06, 1.0, 1.0)
	if water_material != null:
		water_material.set_shader_parameter("weather_tint", current_values.get("world_tint", Color.TRANSPARENT))
		water_material.set_shader_parameter("ripple_intensity", float(current_values.get("water_ripple", 0.15)))
		water_material.set_shader_parameter("wet_weather", float(current_values.get("wetness", 0.0)))
	if sun_light != null:
		sun_light.light_energy = lerpf(1.02, 0.76, float(current_values.get("wetness", 0.0)))
	if fill_light != null:
		fill_light.light_energy = lerpf(0.68, 0.56, float(current_values.get("wetness", 0.0)))

func _apply_canvas() -> void:
	if grade_rect == null:
		return
	var world_tint: Color = current_values.get("world_tint", Color.TRANSPARENT)
	var fog_color: Color = current_values.get("fog_color", Color("0a3145"))
	var fog_density := float(current_values.get("fog_density", 0.0))
	var rain := float(current_values.get("rain", 0.0))
	var rain_speed := float(current_values.get("rain_speed", 1.0))
	var wind := float(current_values.get("wind", 0.0))
	var vignette := float(current_values.get("vignette", 0.0))
	var grade_material := grade_rect.material as ShaderMaterial
	grade_material.set_shader_parameter("world_tint", world_tint)
	grade_material.set_shader_parameter("vignette_amount", vignette)
	_apply_fog(far_fog_rect, fog_color, fog_density * 0.58, 1.55, 0.006)
	_apply_fog(near_fog_rect, fog_color, fog_density * 0.34, 0.78, 0.012)
	var layer_settings := [
		{"scale": 0.66, "density": 0.68, "opacity": 0.38, "splash": 0.0},
		{"scale": 1.00, "density": 1.0, "opacity": 0.56, "splash": 0.0},
		{"scale": 1.45, "density": 1.22, "opacity": 0.72, "splash": 0.28},
	]
	for index in range(rain_rects.size()):
		var rect := rain_rects[index]
		var settings: Dictionary = layer_settings[index]
		var visible := rain > 0.01 and (quality_tier == "HIGH" or index < 2)
		rect.visible = visible
		if not visible:
			continue
		var material := rect.material as ShaderMaterial
		material.set_shader_parameter("rain_color", Color(0.66, 0.87, 1.0, float(settings.opacity)))
		material.set_shader_parameter("intensity", rain)
		material.set_shader_parameter("speed", rain_speed * (0.72 + float(index) * 0.25))
		material.set_shader_parameter("wind", wind * (0.70 + float(index) * 0.22))
		material.set_shader_parameter("density", float(settings.density) * (0.72 if quality_tier == "LOW" else 1.0))
		material.set_shader_parameter("layer_scale", float(settings.scale))
		material.set_shader_parameter("camera_phase", camera_phase * (0.20 + float(index) * 0.12))
		material.set_shader_parameter("splash_strength", float(settings.splash) if quality_tier == "HIGH" else 0.0)

func _apply_fog(rect: ColorRect, fog_color: Color, density: float, depth_weight: float, drift_speed: float) -> void:
	if rect == null:
		return
	rect.visible = density > 0.005
	var material := rect.material as ShaderMaterial
	material.set_shader_parameter("fog_tint", Color(fog_color.r, fog_color.g, fog_color.b, 1.0))
	material.set_shader_parameter("density", density * (0.72 if quality_tier == "LOW" else 1.0))
	material.set_shader_parameter("depth_weight", depth_weight)
	material.set_shader_parameter("drift_speed", drift_speed)
	material.set_shader_parameter("camera_phase", camera_phase)

func _make_rect(shader: Shader) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	return rect
