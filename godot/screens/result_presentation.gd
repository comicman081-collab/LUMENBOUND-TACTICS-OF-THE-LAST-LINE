extends RefCounted

## Battle-result presentation. The layout answers, in reading order:
##   1. Did we win, how many stars, and which star conditions were missed?
##   2. Who carried the fight and who went down?
##   3. What did we get?
##   4. What should we grow next, and why? (GrowthAdvisor)
## Reward and progression data are read from the committed report only; the
## one-tap growth action goes through the normal progression services.

const GameUI := preload("res://ui/game_ui_tokens.gd")
const GrowthAdvisorScript := preload("res://progression/growth_advisor.gd")
const CinematicFx := preload("res://ui/cinematic_fx.gd")
const GOLD := Color("f1d77a")
const MUTED := Color("9fb4cc")
const GOOD := Color("7ee8a8")
const BAD := Color("ff8a8a")
const INK := Color("0b1a28f2")

static func is_battle_report(s) -> bool:
	return str(s.last_reward_report.get("source_type", "BATTLE")) == "BATTLE"

static func result_party(s) -> Array:
	return s.battle_party_ids if not s.battle_party_ids.is_empty() else AppState.get_party()

static func result_stage(s) -> Dictionary:
	return DataRegistry.stage(str(s.last_reward_report.get("source_id", AppState.selected_stage_id)))

## Same rule as the clear record: win, +1 if all five survive, +1 within target time.
static func star_conditions(s) -> Array:
	var result: Dictionary = s.last_battle_result
	var stage := result_stage(s)
	var victory := bool(result.get("victory", false))
	var survivors := int(result.get("survivors", 0))
	var elapsed := float(result.get("time", 0.0))
	var target_time := float(stage.get("target_time", 90))
	return [
		{"label": "작전 승리", "met": victory},
		{"label": "전원 생존 %d/5" % survivors, "met": victory and survivors >= 5},
		{"label": "목표 %d초 이내 · %.1f초" % [roundi(target_time), elapsed], "met": victory and elapsed <= target_time},
	]

static func star_count(s) -> int:
	var count := 0
	for condition in star_conditions(s):
		if bool(condition.met): count += 1
	return count

static func build_landscape(s) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "ResultReportScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.content.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)
	scroll.add_child(page)
	build_header(s, page, 1.0)
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	page.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = .92
	left.add_theme_constant_override("separation", 14)
	body.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.08
	right.add_theme_constant_override("separation", 12)
	body.add_child(right)
	if is_battle_report(s):
		build_mvp(s, left, 1.0)
		build_contribution(s, left, 1.0)
	build_growth_advice(s, left, 1.0)
	s._add_reward_celebration(right, 20)
	var rewards: VBoxContainer = s._panel_box(right)
	s._add_reward_clarity(rewards, 20)

static func build_portrait(s, parent: VBoxContainer, scale: float) -> void:
	build_header(s, parent, scale)
	if is_battle_report(s):
		build_mvp(s, parent, scale)
		build_contribution(s, parent, scale)
	build_growth_advice(s, parent, scale)

static func _card(parent: Node, border: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", GameUI.panel_style(INK, border, 1, GameUI.RADIUS_CONTROL, Vector4(20, 16, 20, 16), 6))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return box

static func build_header(s, parent: Node, scale: float) -> void:
	var result: Dictionary = s.last_battle_result
	var victory := bool(result.get("victory", false))
	var box := _card(parent, GOLD if victory else BAD)
	box.name = "ResultHeader"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	var outcome := VBoxContainer.new()
	outcome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(outcome)
	var outcome_label: Label = s._label("VICTORY" if victory else "DEFEAT", roundi(64 * scale), GOLD if victory else BAD)
	outcome_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	CinematicFx.heroic_text(outcome_label, Color("2a1606") if victory else Color("2a0608"), Color("000000b0"))
	if victory: CinematicFx.shine(outcome_label, {"shine_color": Color("fff2c4")})
	outcome.add_child(outcome_label)
	var stage := result_stage(s)
	var stage_name := LocalizationService.tr_key(str(stage.get("name_key", ""))) if not stage.is_empty() else ""
	if is_battle_report(s):
		outcome.add_child(s._label("%s  ·  %.1f초  ·  생존 %d/5" % [stage_name, float(result.get("time", 0.0)), int(result.get("survivors", 0))], roundi(20 * scale), MUTED))
	else:
		outcome.add_child(s._label("%s  ·  %s" % [stage_name, "소탕 완료" if str(s.last_reward_report.get("source_type", "")) == "SWEEP" else "보급 획득"], roundi(20 * scale), MUTED))
		return
	var stars := VBoxContainer.new()
	stars.add_theme_constant_override("separation", 2)
	stars.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(stars)
	var count := star_count(s)
	# Labels in this shrink column must not autowrap, or each wraps to one
	# character per line and the header grows to the full screen height.
	var star_label: Label = s._label("★".repeat(count) + "☆".repeat(3 - count), roundi(40 * scale), GOLD)
	star_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	stars.add_child(star_label)
	for condition in star_conditions(s):
		var condition_label: Label = s._label("● " + str(condition.label), roundi(16 * scale), GOOD if bool(condition.met) else Color("6f8196"))
		condition_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		stars.add_child(condition_label)
	if victory and count < 3:
		box.add_child(s._label("별 3개를 모으면 이 작전의 소탕이 열립니다. 빠진 조건: %s" % _missing_conditions(s), roundi(16 * scale), GOLD))
	elif not victory:
		box.add_child(s._label("패배해도 사용한 작전력 외의 손실은 없습니다. 아래 추천 성장으로 파티를 보강한 뒤 다시 도전하세요.", roundi(16 * scale), MUTED))

static func _missing_conditions(s) -> String:
	var missing: Array[String] = []
	for condition in star_conditions(s):
		if not bool(condition.met): missing.append(str(condition.label))
	return ", ".join(missing)

static func build_mvp(s, parent: Node, scale: float) -> void:
	var damage: Dictionary = s.last_battle_result.get("damage", {})
	if damage.is_empty():
		return
	var total := 0
	var best_id := ""
	for character_id in damage:
		total += int(damage[character_id])
		if best_id.is_empty() or int(damage[character_id]) > int(damage[best_id]): best_id = str(character_id)
	var definition := DataRegistry.character(best_id)
	if definition.is_empty():
		return
	var box := _card(parent, Color("9cb8ff"))
	box.name = "ResultMvp"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var art := TextureRect.new()
	art.texture = s._asset_texture(str(definition.get("portrait_asset_id", "")))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(96, 128) * scale
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CinematicFx.live_portrait(art, "MVP_" + best_id, {"rim_color": Color("ffe3a0"), "rim_strength": 0.6})
	row.add_child(art)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(copy)
	copy.add_child(s._label("MVP", roundi(18 * scale), GOLD))
	copy.add_child(s._label(s._display_character_name(best_id), roundi(30 * scale), Color.WHITE))
	copy.add_child(s._label("가한 피해 %s  ·  파티 피해의 %d%%" % [MathUtil.comma(int(damage[best_id])), roundi(100.0 * float(damage[best_id]) / maxf(1.0, float(total)))], roundi(17 * scale), MUTED))

static func build_contribution(s, parent: Node, scale: float) -> void:
	var result: Dictionary = s.last_battle_result
	var damage: Dictionary = result.get("damage", {})
	var healing: Dictionary = result.get("healing", {})
	var downed := GrowthAdvisorScript.downed_ids_from_result(result)
	var party := result_party(s)
	var top := 1
	for character_id in party:
		top = maxi(top, int(damage.get(str(character_id), 0)))
	var box := _card(parent, Color("3b566c"))
	box.name = "ResultContribution"
	box.add_child(s._label("파티 기여도", roundi(20 * scale), GOLD))
	var positions := ["전열", "전열", "중열", "중열", "후열"]
	for index in range(party.size()):
		var character_id := str(party[index])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var name_label: Label = s._label("%s  %s" % [positions[mini(index, 4)], s._display_character_name(character_id)], roundi(16 * scale), Color.WHITE)
		name_label.custom_minimum_size = Vector2(150 * scale, 0)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.clip_text = true
		row.add_child(name_label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = top
		bar.value = int(damage.get(character_id, 0))
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size = Vector2(0, 14 * scale)
		var background := StyleBoxFlat.new()
		background.bg_color = Color("1a2a3a")
		background.set_corner_radius_all(4)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("f1d77a") if int(damage.get(character_id, 0)) >= top else Color("7fa9c9")
		fill.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("background", background)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		var value_text := MathUtil.comma(int(damage.get(character_id, 0)))
		if int(healing.get(character_id, 0)) > 0:
			value_text += "  회복 %s" % MathUtil.comma(int(healing[character_id]))
		var value_label: Label = s._label(value_text, roundi(15 * scale), MUTED)
		value_label.custom_minimum_size = Vector2(130 * scale, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(value_label)
		var status: Label = s._label("쓰러짐" if downed.has(character_id) else "생존", roundi(15 * scale), BAD if downed.has(character_id) else GOOD)
		status.custom_minimum_size = Vector2(56 * scale, 0)
		status.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(status)
	if not downed.is_empty():
		box.add_child(s._label("적은 전열부터 노립니다. 쓰러진 동료는 아래 추천에서 우선 보강됩니다.", roundi(15 * scale), MUTED))

static func build_growth_advice(s, parent: Node, scale: float) -> void:
	var party := result_party(s)
	var downed := GrowthAdvisorScript.downed_ids_from_result(s.last_battle_result)
	var report := GrowthAdvisorScript.party_report(party, downed)
	var box := _card(parent, GOLD)
	box.name = "ResultGrowthAdvice"
	box.add_child(s._label("다음 성장 추천", roundi(22 * scale), GOLD))
	var stage := DataRegistry.stage(str(report.stage_id))
	var skill_requirement := GrowthAdvisorScript.skill_requirement_text(stage)
	box.add_child(s._label("목표 작전  %s  ·  권장 Lv.%d" % [LocalizationService.tr_key(str(stage.get("name_key", report.stage_id))), int(report.recommended_level)] + ("  ·  " + skill_requirement if not skill_requirement.is_empty() else ""), roundi(16 * scale), MUTED))
	add_readiness_bar(s, box, report, scale)
	var entries := GrowthAdvisorScript.recommendations(party, downed, 2)
	if entries.is_empty():
		box.add_child(s._label("지금 파티는 목표 작전의 권장 수준입니다. 작전을 진행하며 재료를 모으세요.", roundi(16 * scale), GOOD))
	for entry in entries:
		add_recommendation_row(s, box, entry, scale, "RESULT")
	var more: Button = s._button("성장 화면에서 자세히 보기", func():
		AppState.selected_character_id = str(entries[0].character_id) if not entries.is_empty() else str(party[0])
		s.growth_tab = "레벨업"
		s.growth_target_level = 0
		SceneRouter.go("GROWTH"), false, Vector2(0, 52 * scale))
	more.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(more)

static func add_readiness_bar(s, parent: Node, report: Dictionary, scale: float) -> void:
	var readiness := float(report.readiness)
	var color := GOOD if readiness >= .995 else (GOLD if readiness >= .85 else BAD)
	parent.add_child(s._label("파티 전투력  %s / 권장 %s  (%d%%)" % [MathUtil.comma(int(report.party_power)), MathUtil.comma(int(report.recommended_power)), roundi(readiness * 100.0)], roundi(17 * scale), Color.WHITE))
	var bar := ProgressBar.new()
	bar.name = "ReadinessBar"
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = clampf(readiness * 100.0, 0.0, 100.0)
	bar.custom_minimum_size = Vector2(0, 14 * scale)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("1a2a3a")
	background.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	parent.add_child(s._label(str(report.verdict), roundi(15 * scale), color))

## One recommendation: what, why, expected gain, and a direct apply button.
static func add_recommendation_row(s, parent: Node, entry: Dictionary, scale: float, return_screen: String) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", GameUI.panel_style(Color("12263a"), Color("3b566c"), 1, GameUI.RADIUS_CONTROL, Vector4(14, 10, 14, 10), 0))
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	row.add_child(copy)
	copy.add_child(s._label(str(entry.title), roundi(19 * scale), Color.WHITE))
	copy.add_child(s._label("이유 · " + str(entry.reason), roundi(15 * scale), MUTED))
	if not str(entry.get("gain", "")).is_empty():
		copy.add_child(s._label(str(entry.gain), roundi(15 * scale), GOOD))
	var actionable := not Dictionary(entry.get("action", {})).is_empty()
	var apply: Button = s._button("바로 적용" if actionable else "재료 필요", func():
		var outcome: GameResult = GrowthAdvisorScript.execute(entry)
		if outcome.ok:
			var saved := SaveService.save_game()
			s._notify("%s 완료%s" % [str(entry.title), "" if saved.ok else " · 저장하지 못했습니다"])
		else:
			s._notify("적용하지 못했습니다 · 재료와 조건을 확인하세요")
		s._show_screen(return_screen), not actionable, Vector2(150 * scale, 56 * scale))
	apply.name = "GrowthAdviceApply"
	if actionable: s._make_primary_button(apply)
	row.add_child(apply)
