extends RefCounted

const GameUI := preload("res://ui/game_ui_tokens.gd")
const GrowthAdvisorScript := preload("res://progression/growth_advisor.gd")
const CinematicFx := preload("res://ui/cinematic_fx.gd")
const ResultPresentation := preload("res://screens/result_presentation.gd")

const INK := Color("081421")
const GOLD := Color("edcc81")
const SIGNAL := Color("84e4da")
const ROLE := {"GUARDIAN":"수호", "STRIKER":"돌격", "VANGUARD":"돌격", "ASSAULT":"강습", "ARTILLERY":"화력", "SPECIALIST":"특수", "SNIPER":"저격", "SUPPORT":"지원", "MEDIC":"치유"}

static func label(s, text_value: String, font_size := 24, color := Color.WHITE) -> Label:
	var item := Label.new()
	item.text = text_value
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var factor := clampf(1280.0 / maxf(1.0, s._runtime_layout_size().x), 1.0, 1.45) if font_size < 48 else 1.0
	item.add_theme_font_size_override("font_size", roundi(float(font_size)*factor))
	item.add_theme_color_override("font_color",color)
	var face := GameUI.weighted_font(s.interface_font,850.0 if font_size >= 48 else 580.0,0.0)
	if face != null: item.add_theme_font_override("font",face)
	return item

static func button(s, text_value: String, callback: Callable, disabled := false, minimum := Vector2(190,64)) -> Button:
	var item: Button = s._button(text_value,callback,disabled,minimum)
	item.set_meta("composed_control", true)
	item.custom_minimum_size = minimum
	item.autowrap_mode = TextServer.AUTOWRAP_OFF
	item.add_theme_font_size_override("font_size",roundi(24.0*clampf(1280.0/maxf(1.0,s._runtime_layout_size().x),1.0,1.3)))
	var face := GameUI.weighted_font(s.interface_font,650.0,0.0)
	if face != null: item.add_theme_font_override("font",face)
	return item

static func area(parent: Node, rect: Rect2, name_value := "") -> Control:
	var control := Control.new()
	if not name_value.is_empty(): control.name = name_value
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	control.anchor_left = rect.position.x
	control.anchor_top = rect.position.y
	control.anchor_right = rect.end.x
	control.anchor_bottom = rect.end.y
	return control

static func shade(parent: Node, from: Color, to: Color, horizontal := true) -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([from, to])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2.RIGHT if horizontal else Vector2.DOWN
	var surface := TextureRect.new()
	surface.texture = texture
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(surface)

static func art(s, parent: Node, cid: String, rect: Rect2) -> TextureRect:
	var box = area(parent, rect)
	var definition := DataRegistry.character(cid)
	var image := TextureRect.new()
	image.texture = s._asset_texture(str(definition.portrait_asset_id))
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.name = "FullBody_" + cid
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(image)
	return image

static func scene_surface(s, name_value: String) -> Control:
	var stage := Control.new()
	stage.name = name_value
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	s.content.add_child(stage)
	return stage

## Layered title stage: drifting cathedral, light shafts behind the heroine,
## a breathing (Live2D-style) full-body cast, rising lantern motes and low fog.
static func title_backdrop(s, parent: Node) -> void:
	CinematicFx.drift_background(parent, load("res://assets/art/backgrounds/BG_BOSS_SIGNAL_CATHEDRAL/bg_boss_signal_cathedral_1920x1080.png"), {"zoom_base": 1.08, "tint": Color("b8d4ff"), "tint_strength": 0.12, "vignette": 0.32, "brightness": 1.3})
	# Keep the left side dark enough for the logo, but let the set read on the right.
	shade(parent, Color("050d18d0"), Color("0c243800"))
	CinematicFx.light_rays(parent, {"origin": Vector2(0.70, -0.10), "ray_color": Color("ffd98a"), "intensity": 0.5})
	var hero := art(s, parent, "CHR001", Rect2(.43, -.015, .56, 1.10))
	CinematicFx.live_portrait(hero, "TITLE_CHR001", {"breath_amount": 0.010, "sway_amount": 0.006, "rim_color": Color("ffe3a0"), "rim_strength": 0.55})
	CinematicFx.fog(parent, {"fog_color": Color("7fa3c4"), "intensity": 0.30, "top": 0.62})
	CinematicFx.motes(parent, {"intensity": 0.85})
	shade(parent, Color("030a1600"), Color("030a1699"), false)

static func title(s) -> void:
	# The title follows the intro (a trusted gesture already happened), so the
	# title theme can play instead of leaving the key art in silence.
	AudioService.play_bgm("audio_bgm_title_en")
	var stage := scene_surface(s, "TitleHeroStage")
	title_backdrop(s, stage)
	var identity = area(stage, Rect2(.055, .24, .45, .56))
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 14)
	identity.add_child(column)
	var eyebrow_row := HBoxContainer.new()
	eyebrow_row.add_theme_constant_override("separation", 14)
	column.add_child(eyebrow_row)
	var rule := ColorRect.new()
	rule.color = GOLD
	rule.custom_minimum_size = Vector2(64, 2)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eyebrow_row.add_child(rule)
	var eyebrow := label(s, "L A N T E R N L I N E   ·   C H A P T E R   0 1", 19, GOLD)
	eyebrow.autowrap_mode = TextServer.AUTOWRAP_OFF
	eyebrow_row.add_child(eyebrow)
	var logo := label(s, "LUMEN\nBOUND", 128, Color("fff6dd"))
	logo.name = "TitleLogo"
	CinematicFx.heroic_text(logo, Color("2a1606"), Color("000000c0"))
	CinematicFx.shine(logo, {"shine_color": Color("fff2c4")})
	column.add_child(logo)
	var tagline := label(s, "꺼진 노선 위에서, 다시 빛을 잇다.", 27, Color("e3eef4"))
	CinematicFx.heroic_text(tagline, Color("06121c"), Color("000000a0"))
	tagline.add_theme_constant_override("outline_size", 6)
	column.add_child(tagline)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	column.add_child(spacer)
	var start = button(s, "기록 이어가기  ›" if not AppState.profile.get("stage_stars", {}).is_empty() else "기록 시작  ›", s._start_title_flow, false, Vector2(410, 78))
	start.name = "TitleStartButton"
	GameUI.apply_button(start, "objective")
	start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var starts := HBoxContainer.new()
	starts.add_theme_constant_override("separation",18)
	column.add_child(starts)
	starts.add_child(start)
	CinematicFx.pulse_glow(start, Color("ffd27a"), 22)
	var fresh := button(s,"새 게임",s._request_new_game,false,Vector2(230,78))
	fresh.name = "TitleNewGameButton"
	starts.add_child(fresh)
	CinematicFx.entrance(identity, 0.15, Vector2(-36, 0), 0.9)
	var utility = area(stage, Rect2(.055, .89, .40, .065))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	utility.add_child(row)
	row.add_child(button(s, "설정", func(): SceneRouter.go("SETTINGS"), false, Vector2(130, 48)))
	row.add_child(button(s, "인트로 다시 보기", s._show_intro_video, false, Vector2(220, 48)))

static func home(s) -> void:
	s.home_first_operation_navigation_pending = false
	AudioService.play_bgm("audio_bgm_lobby")
	AppState.refresh_stamina()
	var stage := scene_surface(s, "RelayHeadquarters")
	var world := TextureRect.new()
	world.name = "HeadquartersIllustration"
	world.texture = preload("res://assets/art/backgrounds/BG_LANTERNLINE_HEADQUARTERS/headquarters_1344x768.png")
	world.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(world)
	shade(stage, Color("061322a8"), Color("06132200"), false)
	var top = area(stage, Rect2(.025, .025, .95, .10))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 25)
	top.add_child(row)
	var brand = label(s, "랜턴라인 본부", 37, Color("f3f9fa"))
	brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(brand)
	var resources = label(s, "Lv.%d    ◇ %s    작전력 %d/%d" % [int(AppState.profile.account.level), MathUtil.comma(AppState.inventory_count("CREDIT")), int(AppState.profile.account.stamina), AppState.account_max_stamina()], 24, GOLD)
	resources.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(resources)
	var menu: Button = s._growth_menu_button(Vector2(112, 50))
	menu.size_flags_horizontal = Control.SIZE_FILL
	GameUI.apply_button(menu, "objective")
	row.add_child(menu)
	var settings := button(s, "설정", func(): SceneRouter.go("SETTINGS"), false, Vector2(112, 50))
	settings.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(settings)
	var next_stage := "CH01-N01"
	for entry in DataRegistry.list_of("stages"):
		if str(entry.get("mode", "")) == "NORMAL" and AppState.is_stage_unlocked(str(entry.id)) and int(AppState.profile.stage_stars.get(str(entry.id), 0)) == 0:
			next_stage = str(entry.id)
			break
	var mission = area(stage, Rect2(.71, .19, .265, .34))
	var mission_panel := PanelContainer.new()
	mission_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mission_panel.add_theme_stylebox_override("panel", GameUI.panel_style(Color("071c2bea"), Color("4b7e88"), 1, 5, Vector4(26,24,26,24), 0))
	mission.add_child(mission_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	mission_panel.add_child(column)
	column.add_child(label(s, "다음 작전", 20, SIGNAL))
	column.add_child(label(s, next_stage.replace("CH", "제").replace("-N", "장 · 작전 "), 30, Color.WHITE))
	column.add_child(label(s, "탐색 중인 노선에서 여정을 이어갑니다.", 20, Color("bed0db")))
	var launch = button(s, "작전 출동  ›", s._launch_first_operation, false, Vector2(1, 68))
	launch.name = "HomeFirstOperationButton"
	GameUI.apply_button(launch, "primary")
	column.add_child(launch)
	s.home_menu_buttons["STAGE"] = launch
	for item in [["통신 관제", "STORY", .20,.33],["작전 사령부", "FORMATION", .43,.42],["보급 창고", "INVENTORY", .33,.70],["기록 보관소", "ARCHIVE", .62,.73]]:
		var hotspot = area(stage, Rect2(float(item[2])-.07,float(item[3]),.15,.06))
		var route := str(item[1])
		var callback: Callable = func(): SceneRouter.go(route)
		if route == "STORY": callback = func(): AppState.active_scenario_id = "SCN_PROLOGUE"; SceneRouter.go("STORY", {"after":"HOME"})
		var button = button(s, str(item[0]), callback, false, Vector2(185, 48))
		button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hotspot.add_child(button)
	var dock = area(stage, Rect2(.025,.86,.95,.11))
	var dock_row := HBoxContainer.new()
	dock_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock_row.add_theme_constant_override("separation", 12)
	dock.add_child(dock_row)
	for item in [["동료", "ROSTER"],["파티 편성", "FORMATION"],["릴레이 작전", "RELAY"],["인벤토리", "INVENTORY"],["스토리 기록", "ARCHIVE"]]:
		var route := str(item[1])
		var button = button(s, str(item[0]), func(): SceneRouter.go(route), false, Vector2(190, 82))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dock_row.add_child(button)
	var save = button(s, "저장", func(): s._report_result(SaveService.save_game()), false, Vector2(115, 82))
	dock_row.add_child(save)
	if s._home_tutorial_active(): s.call_deferred("_start_home_tutorial")

static func roster(s) -> void:
	s._title("동료", "함께 노선을 지키는 사람들")
	var scroll = s._scroll_box()
	var grid := GridContainer.new()
	grid.columns = 3 if s._is_portrait_layout() else 6
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for definition in DataRegistry.list_of("characters"):
		var cid := str(definition.id)
		var state: Dictionary = AppState.profile.roster[cid]
		var card = character_card(s, cid, "동료" if bool(state.unlocked) else "미합류", func():
			AppState.selected_character_id = cid
			s.growth_target_level = 0
			SceneRouter.go("CHARACTER_DETAIL"), false, Vector2(250,360))
		grid.add_child(card)
		if not bool(state.unlocked): card.modulate = Color(.6,.66,.72,1)

static func character_card(s, cid: String, badge: String, callback: Callable, selected := false, minimum := Vector2(260,320)) -> Button:
	var definition := DataRegistry.character(cid)
	var state: Dictionary = AppState.profile.roster[cid]
	var card := button(s, "", callback, false, minimum)
	card.name = "CharacterCard_" + cid
	card.clip_contents = true
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if selected: GameUI.apply_button(card, "selected")
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_" + side,12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	var badge_label := label(s, badge, 18, INK if selected else GOLD)
	badge_label.name = "CardBadge"
	badge_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(badge_label)
	var source: Texture2D = s._asset_texture(str(definition.portrait_asset_id))
	var portrait := TextureRect.new()
	portrait.name = "Portrait_" + cid
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if source != null:
		# Portrait masters contain the whole body. A deliberate upper-body window
		# keeps faces legible in cards without changing the source illustration.
		var crop := AtlasTexture.new()
		crop.atlas = source
		var window := Rect2(.20,.13,.58,.24) if cid == "CHR001" else Rect2(.16,.025,.68,.37)
		crop.region = Rect2(Vector2(source.get_width()*window.position.x,source.get_height()*window.position.y),Vector2(source.get_width()*window.size.x,source.get_height()*window.size.y))
		portrait.texture = crop
	column.add_child(portrait)
	var name_label := label(s, s._display_character_name(cid), 26, INK if selected else Color.WHITE)
	name_label.name = "CardName"
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	var detail := label(s, "%s · Lv.%d" % [ROLE.get(str(definition.role),"지원"),int(state.level)],18,INK if selected else Color("bed3df"))
	detail.name = "CardDetail"
	detail.autowrap_mode = TextServer.AUTOWRAP_OFF
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(detail)
	for child in column.get_children(): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card

static func formation(s) -> void:
	s._title("파티 편성", "배치할 자리를 고른 뒤 동료를 선택하세요")
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 12)
	s.content.add_child(presets)
	for i in range(5):
		presets.add_child(button(s, "편성 %d" % (i+1),func(index := i): AppState.profile.active_party=index; s._show_screen("FORMATION"),i==int(AppState.profile.active_party),Vector2(200,68)))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 14)
	s.content.add_child(slots)
	var positions := ["전열 A","전열 B","중열 A","중열 B","후열"]
	for i in range(5):
		var cid := str(AppState.get_party()[i])
		var card := character_card(s,cid,positions[i],func(index := i): s.formation_slot=index; s._show_screen("FORMATION"),s.formation_slot==i,Vector2(320,340))
		card.name = "FormationSlot_%d" % i
		slots.add_child(card)
	var roster_box = s._scroll_box()
	roster_box.add_child(label(s,"동료 선택 · %s에 배치" % positions[s.formation_slot],22,GOLD))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",14)
	grid.add_theme_constant_override("v_separation",14)
	roster_box.add_child(grid)
	for definition in DataRegistry.list_of("characters"):
		var cid := str(definition.id)
		if not bool(AppState.profile.roster[cid].unlocked): continue
		var card := character_card(s,cid,"편성 중" if AppState.get_party().has(cid) else "대기",func(id := cid):
			AppState.set_party_slot(s.formation_slot,id)
			SaveService.save_game()
			s._show_screen("FORMATION"),false,Vector2(250,250))
		grid.add_child(card)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",14)
	s.content.add_child(actions)
	var destination := str(AppState.route_payload.get("after","STAGE_SELECT"))
	if destination not in ["STAGE_DETAIL","STAGE_SELECT"]: destination="STAGE_SELECT"
	actions.add_child(button(s,"작전으로",func(): SceneRouter.go(destination),false,Vector2(300,80)))
	var save := button(s,"편성 저장",func(): s._report_result(SaveService.save_game()),false,Vector2(300,80))
	GameUI.apply_button(save,"primary")
	actions.add_child(save)

static func growth(s) -> void:
	var cid := str(AppState.selected_character_id)
	var definition := DataRegistry.character(cid)
	var state: Dictionary = AppState.profile.roster[cid]
	var advice := GrowthAdvisorScript.party_report(AppState.get_party())
	var target_stage := DataRegistry.stage(str(advice.stage_id))
	var skill_requirement := GrowthAdvisorScript.skill_requirement_text(target_stage)
	s._title(str(s.growth_tab), "크레딧 %s  ·  목표 %s 권장 Lv.%d" % [MathUtil.comma(AppState.inventory_count("CREDIT")), LocalizationService.tr_key(str(target_stage.get("name_key", advice.stage_id))), int(advice.recommended_level)] + ("  ·  " + skill_requirement if not skill_requirement.is_empty() else ""))
	var stage := scene_surface(s, "CharacterPresentation")
	shade(stage, Color("153d50"), Color("06101e"))
	CinematicFx.light_rays(stage, {"origin": Vector2(0.28, -0.1), "ray_color": Color("bfe8ff"), "intensity": 0.22})
	CinematicFx.live_portrait(art(s, stage, cid, Rect2(.03,.025,.51,.97)), "GROWTH_" + cid, {"rim_strength": 0.5})
	CinematicFx.motes(stage, {"intensity": 0.45, "density": 0.6})
	var identity = area(stage, Rect2(.025,.035,.28,.20))
	var identity_col := VBoxContainer.new()
	identity_col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	identity.add_child(identity_col)
	identity_col.add_child(label(s, ROLE.get(str(definition.role), str(definition.role)), 23, GOLD))
	identity_col.add_child(label(s, s._display_character_name(cid), 56, Color.WHITE))
	identity_col.add_child(label(s, "Lv.%d / %d" % [int(state.level), CharacterProgression.level_cap(state)], 28, SIGNAL))
	var panel_area = area(stage, Rect2(.54,.025,.44,.95))
	var scroll := ScrollContainer.new()
	scroll.set_script(preload("res://ui/touch_progression_scroll.gd"))
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_area.add_child(scroll)
	if str(s.growth_tab) == "레벨업" and bool(state.unlocked):
		scroll.offset_bottom = -90
		var sticky := Control.new()
		sticky.name = "GrowthStickyAction"
		sticky.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		sticky.offset_top = -78
		panel_area.add_child(sticky)
	var body := VBoxContainer.new()
	body.name = "GrowthContent"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	scroll.add_child(body)
	var selectors := HBoxContainer.new()
	selectors.name = "GrowthPartySelector"
	body.add_child(selectors)
	# Each tab shows the member's level; members below the next operation's
	# recommended level are tinted so the weak link is visible at a glance.
	for member_id in AppState.get_party():
		var id := str(member_id)
		var member_level := int(AppState.profile.roster[id].level)
		var button = button(s, "%s Lv.%d" % [s._display_character_name(id), member_level], func(): AppState.selected_character_id = id; s.growth_target_level = 0; s._show_screen("GROWTH"), id == cid, Vector2(1,46))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18)
		if member_level < int(advice.recommended_level):
			button.add_theme_color_override("font_color", Color("ff9a8a"))
			button.tooltip_text = "권장 Lv.%d보다 낮습니다" % int(advice.recommended_level)
		selectors.add_child(button)
	if bool(state.unlocked):
		_growth_guide(s, body, advice)
	var stats := CharacterProgression.final_stats(cid)
	var stat_box = s._panel_box(body)
	var member_report: Dictionary = {}
	for member_value in advice.members:
		if str(member_value.character_id) == cid: member_report = member_value
	stat_box.add_child(label(s, "전투 능력", 23, SIGNAL))
	if not member_report.is_empty():
		var below: bool = int(member_report.combat_power) < int(member_report.recommended_power)
		stat_box.add_child(label(s, "전투력 %s  /  권장 %s" % [MathUtil.comma(int(member_report.combat_power)), MathUtil.comma(int(member_report.recommended_power))], 26, Color("ff9a8a") if below else Color("7ee8a8")))
	stat_box.add_child(label(s, "체력 %s     공격력 %s     방어력 %s" % [MathUtil.comma(stats.HP),MathUtil.comma(stats.ATK),MathUtil.comma(stats.DEF)], 23, Color.WHITE))
	if not bool(state.unlocked):
		stat_box.add_child(label(s, "스토리에서 합류하면 성장할 수 있습니다.", 22))
		return
	if not s.growth_feedback.is_empty(): body.add_child(label(s, s.growth_feedback, 20, GOLD))
	if s.growth_save_pending: body.add_child(button(s, "저장 다시 시도", s._retry_growth_save, false, Vector2(1,50)))
	var tabs := HBoxContainer.new()
	tabs.name = "GrowthTabs"
	body.add_child(tabs)
	for title_value in ["레벨업", "스킬업", "장비·돌파", "캐릭터 정보"]:
		var tab := str(title_value)
		var button = button(s, tab, func(): s.growth_tab = tab; s._show_screen("GROWTH"), s.growth_tab == tab, Vector2(1,48))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(button)
	match str(s.growth_tab):
		"레벨업": level(s, body, cid)
		"스킬업": s._build_growth_skills(body,cid)
		"장비·돌파": s._build_growth_equipment(body,cid)
		_: body.add_child(label(s, "돌파 %d · 관계 %d\n선호 위치: %s" % [int(state.breakthrough),int(state.relationship_level),{"FRONT":"전열","MIDDLE":"중열","BACK":"후열","REAR":"후열"}.get(str(definition.preferred_position),str(definition.preferred_position))],23))

## Party-wide "권장 성장" card: the target operation's recommended profile,
## readiness, and what one press changes (per member, cost, what is still
## missing), computed by the same plan the button executes.
static func _growth_guide(s, parent: Node, advice: Dictionary) -> void:
	var box = s._panel_box(parent)
	box.name = "GrowthGuide"
	box.add_child(label(s, "권장 성장", 22, GOLD))
	var profile: Dictionary = advice.get("profile", {})
	box.add_child(label(s, "목표 · Lv.%d · 스킬 Lv.%d · 궁극기 Lv.%d · 무기 Lv.%d" % [int(profile.get("level", advice.recommended_level)), int(profile.get("normal", 1)), int(profile.get("ultimate", 1)), int(profile.get("weapon_level", 1))], 18, Color.WHITE))
	ResultPresentation.add_readiness_bar(s, box, advice, 1.0)
	var preview: Dictionary = GrowthPlanBuilder.preview_to_recommended(AppState.get_party())
	var summary := recommended_growth_summary(s, preview)
	var actions: Array = preview.get("actions", [])
	if actions.is_empty() and bool(preview.get("reached", false)):
		box.add_child(label(s, "파티가 목표 작전의 권장 수준입니다. 작전을 진행하세요.", 18, Color("7ee8a8")))
		return
	for line in summary.changes:
		box.add_child(label(s, str(line), 17, Color("d7e3ee")))
	if not str(summary.cost).is_empty():
		box.add_child(label(s, "소모 · " + str(summary.cost), 16, Color("b8cbd8")))
	if not str(summary.shortage).is_empty():
		box.add_child(label(s, ("적용 후에도 부족 · " if not actions.is_empty() else "부족 · ") + str(summary.shortage), 16, Color("ff9a8a")))
		box.add_child(label(s, "작전 첫 클리어와 반복 출격 보상으로 채울 수 있습니다.", 15, Color("8e9aaf")))
	var reached := bool(preview.get("reached", false))
	var apply := button(s, ("권장 수준까지 성장" if reached else "가능한 만큼 권장 성장") if not actions.is_empty() else "재료 부족", s._apply_recommended_growth, actions.is_empty() or s.growth_save_pending, Vector2(1, 58))
	apply.name = "GrowthRecommendedApply"
	if not actions.is_empty(): s._make_primary_button(apply)
	box.add_child(apply)

## Player-facing text for a GrowthPlanBuilder recommended-growth report:
## headline, one line per member that changes, the cost and what is missing.
static func recommended_growth_summary(s, report: Dictionary) -> Dictionary:
	var changes: Array[String] = []
	var raised := 0
	for member in report.get("members", []):
		var before: Dictionary = member.get("before", {})
		var after: Dictionary = member.get("after", {})
		var parts: Array[String] = []
		if int(after.get("level", 1)) > int(before.get("level", 1)):
			parts.append("Lv.%d→%d" % [int(before.get("level", 1)), int(after.get("level", 1))])
		var skill_before: Dictionary = before.get("skills", {})
		var skill_after: Dictionary = after.get("skills", {})
		for slot in [["normal", "스킬"], ["passive", "패시브"], ["ultimate", "궁극기"]]:
			if int(skill_after.get(slot[0], 1)) > int(skill_before.get(slot[0], 1)):
				parts.append("%s %d→%d" % [slot[1], int(skill_before.get(slot[0], 1)), int(skill_after.get(slot[0], 1))])
		var weapon_before: Dictionary = before.get("weapon", {})
		var weapon_after: Dictionary = after.get("weapon", {})
		if int(weapon_after.get("level", 0)) > int(weapon_before.get("level", 0)):
			parts.append("무기 %d→%d" % [int(weapon_before.get("level", 0)), int(weapon_after.get("level", 0))])
		if parts.is_empty(): continue
		raised += 1
		changes.append("%s  %s%s" % [s._display_character_name(str(member.character_id)), " · ".join(parts), "  ✓" if bool(member.get("reached", false)) else ""])
	var spent: Array[String] = []
	var accounting: Dictionary = report.get("accounting", {})
	var deltas: Dictionary = accounting.get("inventory_delta", {})
	var spent_ids: Array = deltas.keys()
	spent_ids.sort()
	for item_id in spent_ids:
		if int(deltas[item_id]) < 0:
			spent.append("%s %s" % [s._display_item_name(str(item_id)), MathUtil.comma(-int(deltas[item_id]))])
	var missing: Array[String] = []
	var shortages: Dictionary = report.get("shortages", {})
	var missing_ids: Array = shortages.keys()
	missing_ids.sort()
	for item_id in missing_ids:
		var item_name: String = "훈련 노트 경험치" if str(item_id) == "TRAINING_XP" else ("무기 칩 경험치" if str(item_id) == "WEAPON_XP" else s._display_item_name(str(item_id)))
		missing.append("%s %s" % [item_name, MathUtil.comma(int(shortages[item_id]))])
	var actions: int = report.get("actions", []).size()
	var headline := "%d명 · %d단계 성장" % [raised, actions] if actions > 0 else "변경 없음"
	return {"headline": headline, "changes": changes, "cost": ", ".join(spent), "shortage": ", ".join(missing)}

static func level(s, parent: Node, cid: String) -> void:
	var state: Dictionary = AppState.profile.roster[cid]
	var current := int(state.level)
	var cap := CharacterProgression.level_cap(state)
	var target := clampi(int(s.growth_target_level) if int(s.growth_target_level) > 0 else current + 1, mini(current+1,cap),cap)
	s.growth_target_level = target
	var preview := CharacterProgression.preview_target(cid,target)
	var box = s._panel_box(parent)
	box.name = "GrowthLevelCard"
	box.add_child(label(s, "Lv.%d  →  Lv.%d" % [current,target], 38, Color.WHITE))
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation",10)
	box.add_child(controls)
	# "권장" jumps straight to the next operation's recommended level (or as
	# close as current materials allow) instead of making the player guess.
	var recommended := mini(int(DataRegistry.stage(GrowthAdvisorScript.target_stage_id()).get("recommended_level", current + 1)), CharacterProgression.maximum_target(cid))
	for option in [["MIN",current+1],["−",target-1],["+",target+1],["권장",maxi(recommended, current + 1)],["MAX",CharacterProgression.maximum_target(cid)]]:
		var value := int(option[1])
		var button = button(s, str(option[0]), func(): s.growth_target_level = clampi(value,mini(current+1,cap),cap); s._show_screen("GROWTH"), current >= cap or s.growth_save_pending, Vector2(1,50))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.add_child(button)
	var target_state := state.duplicate(true)
	target_state.level = target
	var before := CharacterProgression.final_stats(cid)
	var after := CharacterProgression.final_stats(cid,target_state)
	var changes: Array[String] = []
	for stat in ["HP","ATK","DEF"]:
		changes.append("%s    %s   →   %s  (+%s)" % [{"HP":"체력","ATK":"공격력","DEF":"방어력"}[stat], MathUtil.comma(int(before[stat])),MathUtil.comma(int(after[stat])),MathUtil.comma(int(after[stat])-int(before[stat]))])
	box.add_child(label(s, "\n".join(changes),22, SIGNAL))
	box.add_child(label(s, "자동 선택 재료 · 필요 / 보유",22, GOLD))
	var cost: Dictionary = preview.get("materials",{}).duplicate()
	cost.CREDIT = int(preview.get("credit_cost",0))
	for item_id in cost:
		var need := int(cost[item_id])
		if need <= 0: continue
		var owned := AppState.inventory_count(str(item_id))
		var item_name: String = s._display_item_name(str(item_id))
		box.add_child(label(s, "%s   %s / %s" % [item_name, MathUtil.comma(need), MathUtil.comma(owned)], 23, Color.WHITE if owned >= need else GameUI.DANGER))
	if int(preview.get("reserve_xp",0)) > 0 or int(state.get("training_xp_reserve",0)) > 0:
		box.add_child(label(s, "보관 경험치 %s → %s\n남은 경험치는 다음 레벨업에 우선 사용됩니다." % [MathUtil.comma(int(state.get("training_xp_reserve",0))),MathUtil.comma(maxi(0,int(preview.get("reserve_xp",0))))],18,Color("b8cbd8")))
	var errors := {"LEVEL_CAP":"현재 성장 상한에 도달했습니다. 계정 레벨과 돌파를 확인하세요.","INSUFFICIENT_MATERIALS":"훈련 노트가 부족합니다.","INSUFFICIENT_CREDIT":"크레딧이 부족합니다."}
	if not bool(preview.get("ok",false)): box.add_child(label(s, errors.get(str(preview.get("error","")),"성장 가능한 목표 레벨을 선택하세요."),20,GOLD))
	var action = button(s, "Lv.%d까지 레벨업" % target, func():
		var result := CharacterProgression.level_to(cid,target)
		s.growth_target_level = 0
		s._finish_growth_action(result,"Lv.%d 성장 완료 · 재료 자동 사용" % target), not bool(preview.get("ok",false)) or s.growth_save_pending, Vector2(1,64))
	action.name = "GrowthLevelApply"
	GameUI.apply_button(action,"primary")
	var sticky := parent.get_node_or_null("../../GrowthStickyAction") if parent.is_inside_tree() else null
	if sticky != null:
		action.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sticky.add_child(action)
	else:
		box.add_child(action)
