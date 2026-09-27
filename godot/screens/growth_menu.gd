extends RefCounted

## "메뉴" for the lobby and the chapter map (relay camp and field movement).
## Level-up and skill-up live here instead of on the battle result screen; each
## entry opens the growth screen on its own tab, on a party member who can use it.
## "권장 성장" raises the whole party to the next operation's recommended
## profile in one press and shows the result in the reopened menu.

const GameUI := preload("res://ui/game_ui_tokens.gd")
const CommandPresentation := preload("res://screens/command_presentation.gd")
const ENTRIES := [
	{"tab": "레벨업", "kind": "LEVEL", "node": "GrowthMenuLevelUp", "summary_key": "level_characters", "hint": "동료 레벨을 올립니다"},
	{"tab": "스킬업", "kind": "SKILL", "node": "GrowthMenuSkillUp", "summary_key": "skill_characters", "hint": "스킬 위력을 올립니다"},
]

static func button(s, minimum := Vector2(128, 56)) -> Button:
	var menu: Button = CommandPresentation.button(s, "메뉴", func(): open(s), false, minimum)
	menu.name = "GrowthMenuButton"
	return menu

static func is_open(s) -> bool:
	return is_instance_valid(s.growth_menu_layer)

static func open(s, result_message := "") -> void:
	close(s)
	var layer := CanvasLayer.new()
	layer.name = "GrowthMenuLayer"
	layer.layer = 370
	s.add_child(layer)
	s.growth_menu_layer = layer
	var surface := Control.new()
	surface.name = "GrowthMenuSurface"
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.theme = s.theme
	layer.add_child(surface)
	var dimmer := ColorRect.new()
	dimmer.name = "GrowthMenuDimmer"
	dimmer.color = Color("020710b8")
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed: close(s))
	surface.add_child(dimmer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(center)
	# Phones render the 1920x1080 canvas at about 0.4x; grow the panel so the
	# entries stay comfortable touch targets.
	var ui := clampf(float(s._responsive_control_scale()), 1.0, 1.6)
	var panel := PanelContainer.new()
	panel.name = "GrowthMenuPanel"
	panel.custom_minimum_size = Vector2(620, 0) * ui
	panel.add_theme_stylebox_override("panel", GameUI.panel_style(Color("081725f5"), Color("79e7d5c8"), 1, GameUI.RADIUS_MODAL, Vector4(36, 30, 36, 32) * ui, 18))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(16 * ui))
	panel.add_child(column)
	column.add_child(CommandPresentation.label(s, "메뉴", roundi(36 * ui), GameUI.OBJECTIVE))
	column.add_child(CommandPresentation.label(s, "파티 성장 · 크레딧 %s" % MathUtil.comma(AppState.inventory_count("CREDIT")), roundi(19 * ui), GameUI.TEXT_MUTED))
	if not result_message.is_empty():
		var result_label := CommandPresentation.label(s, result_message, roundi(19 * ui), GameUI.OBJECTIVE)
		result_label.name = "GrowthMenuResult"
		result_label.custom_minimum_size = Vector2(548, 0) * ui
		column.add_child(result_label)
	var plan: Dictionary = GrowthPlanBuilder.preview_to_recommended(AppState.get_party())
	var target: Dictionary = plan.get("target", {})
	var plan_ready: bool = not plan.get("actions", []).is_empty()
	var plan_status := ("지금 권장 수준까지" if bool(plan.get("reached", false)) else "가능한 만큼") if plan_ready else ("권장 수준입니다" if bool(plan.get("reached", false)) else "재료를 모으면 열립니다")
	var recommended: Button = CommandPresentation.button(s, "권장 성장   ·   Lv.%d · 스킬 · 무기   ·   %s" % [int(target.get("level", 1)), plan_status], func():
		var outcome: Dictionary = s._run_recommended_growth()
		open(s, str(outcome.message)), not plan_ready, Vector2(548, 88) * ui)
	recommended.name = "GrowthMenuRecommended"
	recommended.add_theme_font_size_override("font_size", roundi(24 * ui))
	if plan_ready: GameUI.apply_button(recommended, "primary")
	column.add_child(recommended)
	var summary := GrowthAffordabilityAnalyzer.summary(GrowthAffordabilityAnalyzer.candidates(AppState.profile))
	for entry in ENTRIES:
		var tab := str(entry.tab)
		var ready := int(summary.get(str(entry.summary_key), 0))
		var status := "지금 가능 %d명" % ready if ready > 0 else "재료를 모으면 열립니다"
		var item: Button = CommandPresentation.button(s, "%s   ·   %s   ·   %s" % [tab, str(entry.hint), status], func():
			close(s)
			s._open_growth_menu_tab(tab), false, Vector2(548, 88) * ui)
		item.name = str(entry.node)
		item.add_theme_font_size_override("font_size", roundi(24 * ui))
		if ready > 0: GameUI.apply_button(item, "primary")
		column.add_child(item)
	var close_button: Button = CommandPresentation.button(s, "닫기", func(): close(s), false, Vector2(548, 60) * ui)
	close_button.name = "GrowthMenuClose"
	close_button.add_theme_font_size_override("font_size", roundi(24 * ui))
	column.add_child(close_button)

static func close(s) -> void:
	if is_instance_valid(s.growth_menu_layer):
		s.growth_menu_layer.queue_free()
	s.growth_menu_layer = null

## Opening a tab starts on a party member who can use it right now, keeping the
## current member when they can.
static func member_for(tab: String) -> String:
	var kind := "LEVEL" if tab == "레벨업" else "SKILL"
	var party: Array = AppState.get_party()
	var ready: Array[String] = []
	for candidate in GrowthAffordabilityAnalyzer.candidates(AppState.profile):
		if str(candidate.get("kind", "")) == kind and party.has(str(candidate.get("character_id", ""))):
			ready.append(str(candidate.character_id))
	var current := str(AppState.selected_character_id)
	if ready.has(current): return current
	if not ready.is_empty(): return ready[0]
	if party.has(current): return current
	return str(party[0]) if not party.is_empty() else current
