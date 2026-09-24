extends Node

## Real-phone viewport regression for the two player-reported progression
## failures: the Chapter 1 N05 mid-boss story plate and the reward -> growth ->
## equipment path.  It deliberately renders the actual AppShell trees at
## 390×844 and proves both that the relevant controls are reachable and that a
## real ScrollContainer can move to them.  The representative reward is held
## only in this isolated QA process: no save, campaign state, source asset, or
## runtime registry is changed.

const BOOT_SCENE := preload("res://screens/boot/boot.tscn")
const GrowthAffordabilityAnalyzerScript := preload("res://progression/growth_affordability_analyzer.gd")
const VIEWPORT_SIZE := Vector2i(390, 844)

var shell: Control
var output_dir := ""
var captures: Array[Dictionary] = []
var checks: Dictionary = {}
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().root.size = VIEWPORT_SIZE
	output_dir = ProjectSettings.globalize_path("res://../reports/art_qa/%s" % _run_id())
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		_finish(2, "MOBILE_PROGRESSION_QA_OUTPUT_DIR_FAILED")
		return
	shell = BOOT_SCENE.instantiate()
	get_tree().root.add_child(shell)
	await _settle(.18)
	# The authored opening video is intentionally bypassed only for this local
	# offscreen diagnostic.  Otherwise it would cover valid N05/result pixels.
	shell.call("_finish_intro_video")
	await _settle(.24)
	await _capture_n05_story()
	await _capture_reward_growth_and_equipment()
	var report := {
		"kind": "MOBILE_N05_REWARD_GROWTH_REAL_VIEWPORT_QA",
		"approval_status": "LOCAL_QA_ONLY",
		"viewport": [VIEWPORT_SIZE.x, VIEWPORT_SIZE.y],
		"capture_mode": "OFFSCREEN_WINDOW_NO_FOREGROUND_AUTOMATION",
		"scenario_id": "SCN_CH01_MID_B",
		"reward_fixture": "In-memory CH01-N05 result delta only; SaveService is never called.",
		"checks": checks,
		"captures": captures,
		"failures": failures,
	}
	var report_path := output_dir.path_join("viewport_qa.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		_finish(3, "MOBILE_PROGRESSION_QA_REPORT_OPEN_FAILED")
		return
	report_file.store_string(JSON.stringify(report, "  ") + "\n")
	report_file.close()
	print("MOBILE_PROGRESSION_VIEWPORT_QA %s" % JSON.stringify(report))
	if not failures.is_empty():
		_finish(4, "MOBILE_PROGRESSION_QA_FAILED:%s" % "; ".join(failures))
		return
	await _finish(0, "")


func _capture_n05_story() -> void:
	AppState.active_scenario_id = "SCN_CH01_MID_B"
	AppState.profile.last_scenario_position.erase("SCN_CH01_MID_B")
	shell.call("_show_screen", "STORY")
	await _settle(.34)
	for page_index in range(3):
		var story_body := shell.get("scenario_text") as RichTextLabel
		if story_body != null and story_body.visible_ratio < 0.999:
			# Exercise the player-facing first-tap behavior rather than assigning the
			# property directly.  This is the exact path that must cancel the old
			# tween before showing a complete N05 line.
			var revealed := bool(shell.call("_request_story_text_box_advance", "qa:n05:reveal:%d" % page_index))
			_require(revealed, "N05 page %d completes its typewriter via the real touch path" % (page_index + 1), "reveal tap rejected")
		await _settle(.10)
		var page_label := "n05_story_page_%02d" % (page_index + 1)
		await _capture(page_label, "N05_STORY_PAGE_%d" % (page_index + 1))
		var dialogue := shell.get("story_dialogue_panel") as Control
		var auto_button := shell.get("story_auto_button") as Control
		var skip_button := shell.get("story_skip_button") as Control
		var body_height: float = story_body.get_content_height() if story_body != null else -1.0
		var body_visible_height: float = story_body.size.y if story_body != null else -1.0
		var page_check: Dictionary = {
			"body_text": story_body.get_parsed_text() if story_body != null else "",
			"body_content_height": body_height,
			"body_visible_height": body_visible_height,
			"dialogue_fully_visible": _fully_visible(dialogue),
			"body_fully_visible": _fully_visible(story_body),
			"auto_fully_visible": _fully_visible(auto_button),
			"skip_fully_visible": _fully_visible(skip_button),
		}
		checks[page_label] = page_check
		_require(body_height >= 0.0 and body_visible_height >= body_height - 1.0, "%s body text is not vertically clipped" % page_label, JSON.stringify(page_check))
		_require(bool(page_check.dialogue_fully_visible) and bool(page_check.body_fully_visible) and bool(page_check.auto_fully_visible) and bool(page_check.skip_fully_visible), "%s dialogue and fixed controls stay inside 390×844" % page_label, JSON.stringify(page_check))
		if page_index < 2:
			await get_tree().create_timer(.24, true, false, true).timeout
			var advanced := bool(shell.call("_request_story_advance", "qa:n05:%d" % page_index))
			_require(advanced, "%s advances through the real story interaction path" % page_label, "transition edge rejected")
			await _settle(.16)


func _capture_reward_growth_and_equipment() -> void:
	var pre_profile: Dictionary = AppState.profile.duplicate(true)
	var before_inventory: Dictionary = pre_profile.get("inventory", {}).duplicate(true)
	var rewards: Dictionary = {
		"CREDIT": 18000,
		"TRAINING_NOTE_L": 3,
		"WEAPON_CHIP_M": 4,
		"LANTERN_SHARD": 5,
	}
	var after_inventory: Dictionary = before_inventory.duplicate(true)
	for item_id_value in rewards:
		var item_id := str(item_id_value)
		after_inventory[item_id] = int(after_inventory.get(item_id, 0)) + int(rewards[item_id])
	var post_profile: Dictionary = pre_profile.duplicate(true)
	post_profile["inventory"] = after_inventory.duplicate(true)
	# The UI action enablement reads AppState directly.  This is an in-memory
	# equivalent of the committed reward transaction, never persisted by this QA.
	AppState.profile["inventory"] = after_inventory.duplicate(true)
	AppState.selected_character_id = "CHR001"
	var growth: Dictionary = GrowthAffordabilityAnalyzerScript.analyze(pre_profile, post_profile)
	shell.set("last_battle_result", {
		"victory": true,
		"time": 61.27,
		"survivors": 5,
		"seed": 9052026,
		"event_hash": "MOBILE_N05_QA_REWARD",
		"damage": {"CHR001": 18240},
		"healing": {"CHR003": 2240},
	})
	shell.set("last_rewards", rewards.duplicate(true))
	shell.set("last_reward_report", {
		"source_type": "BATTLE",
		"source_id": "CH01-N05",
		"rewards": rewards.duplicate(true),
		"pre_inventory": before_inventory.duplicate(true),
		"post_inventory": after_inventory.duplicate(true),
		"growth": growth.duplicate(true),
		"progress": {"first_clear": true},
	})
	shell.call("_show_screen", "RESULT")
	await _settle(.34)
	var result_scroll := _primary_scroll()
	# Growth moved to the lobby / map "메뉴"; the result rail keeps map and home.
	var result_home_button := _find_button("홈") if _find_button("홈") != null else _find_button("본부")
	_require(_find_button("권장 파티 성장") == null, "result offers no party growth action", "")
	var celebration := shell.find_child("RewardCelebrationQueue", true, false) as Control
	var celebration_next := shell.find_child("RewardCelebrationNext", true, false) as Control
	var celebration_skip := shell.find_child("RewardCelebrationSkip", true, false) as Control
	if celebration != null and celebration_next != null and celebration_skip != null:
		var card_rect := celebration.get_global_rect().grow(1.0)
		_require(card_rect.encloses(celebration_next.get_global_rect()) and card_rect.encloses(celebration_skip.get_global_rect()), "reward celebration touch buttons stay inside their container", JSON.stringify(_control_snapshot(celebration)))
		var ledger := celebration.get_parent().get_child(celebration.get_index() + 1) as Control
		_require(ledger.get_global_rect().position.y >= celebration.get_global_rect().end.y - 1.0, "reward celebration does not overlap the following ledger", JSON.stringify(_control_snapshot(ledger)))
	await _capture("reward_result_top", "RESULT_TOP")
	var result_top := _scroll_snapshot(result_scroll)
	_require(result_scroll != null and bool(result_top.get("scrollable", false)), "result ledger exposes a real vertical scroll range", JSON.stringify(result_top))
	_require(_fully_visible(result_home_button), "result action rail remains above the scrollable report", JSON.stringify(_control_snapshot(result_home_button)))
	if result_scroll != null:
		result_scroll.scroll_vertical = 1000000
		await _settle(.16)
	await _capture("reward_result_bottom", "RESULT_BOTTOM")
	var result_bottom := _scroll_snapshot(result_scroll)
	checks["reward_result"] = {
		"top": result_top,
		"bottom": result_bottom,
		"action_rail_fully_visible": _fully_visible(result_home_button),
	}
	_require(float(result_bottom.get("position", 0.0)) > float(result_top.get("position", 0.0)), "result report scroll reaches its lower content", JSON.stringify(checks["reward_result"]))

	# The growth screen the lobby / map menu opens is rendered immediately afterward.
	shell.call("_show_screen", "GROWTH")
	await _settle(.34)
	var growth_scroll := _primary_scroll()
	var quick_actions := shell.find_child("MobileGrowthQuickActions", true, false) as Control
	var equipment_choices := shell.find_child("MobileEquipmentChoices", true, false) as Control
	var level_button := _find_button("레벨업")
	var weapon_button := _find_button("무기 강화")
	await _capture("growth_top", "GROWTH_TOP")
	var growth_top := _scroll_snapshot(growth_scroll)
	var selector := shell.find_child("GrowthPartySelector", true, false) as GridContainer
	var hint := shell.find_child("GrowthSectionHint", true, false) as Label
	var one_row := selector != null and selector.columns == selector.get_child_count()
	if selector != null:
		for tab in selector.get_children():
			one_row = one_row and _fully_visible(tab) and absf(tab.position.y - selector.get_child(0).position.y) < 1.0
	_require(one_row, "all five character tabs fit one visible row", str(one_row))
	_require(hint != null and hint.get_line_count() == 1, "character section subtitle stays on one line", "hint")
	_require(_fully_visible(quick_actions) and _fully_visible(equipment_choices), "growth and equipment actions appear before the dossier without scrolling", "initial action positions")
	_require(growth_scroll != null and bool(growth_top.get("scrollable", false)), "growth dossier keeps an always-visible vertical scroll rail", JSON.stringify(growth_top))
	_require(quick_actions != null and equipment_choices != null, "growth creates immediate level/weapon and equipment action sections", "quick=%s equipment=%s" % [str(quick_actions != null), str(equipment_choices != null)])
	if growth_scroll != null and quick_actions != null:
		await _scroll_to_control(growth_scroll, quick_actions)
	await _capture("growth_quick_actions", "GROWTH_QUICK_ACTIONS")
	var growth_quick := _scroll_snapshot(growth_scroll)
	checks["growth_quick_actions"] = {
		"scroll": growth_quick,
		"section": _control_snapshot(quick_actions),
		"level_button": _control_snapshot(level_button),
		"weapon_button": _control_snapshot(weapon_button),
	}
	_require(_intersects_visible(quick_actions) and _intersects_visible(level_button) and _intersects_visible(weapon_button), "quick level and weapon actions are reachable in the viewport", JSON.stringify(checks["growth_quick_actions"]))
	if growth_scroll != null and equipment_choices != null:
		await _scroll_to_control(growth_scroll, equipment_choices)
	await _capture("growth_equipment_choices", "GROWTH_EQUIPMENT_CHOICES")
	var growth_equipment := _scroll_snapshot(growth_scroll)
	var equipment_buttons := _equipment_option_buttons(equipment_choices)
	var equipment_button_contract := not equipment_buttons.is_empty()
	var equipment_button_texts: Array[String] = []
	for equipment_button in equipment_buttons:
		equipment_button_texts.append(equipment_button.text)
		equipment_button_contract = equipment_button_contract and equipment_button.text.contains("\n") and not equipment_button.text.contains("WPN") and equipment_button.autowrap_mode != TextServer.AUTOWRAP_OFF and _fully_visible(equipment_button)
	checks["growth_equipment_choices"] = {
		"scroll": growth_equipment,
		"section": _control_snapshot(equipment_choices),
		"buttons": equipment_button_texts,
		"compact_touch_labels": equipment_button_contract,
	}
	_require(_intersects_visible(equipment_choices), "equipment selection is reachable by the same real growth scroll", JSON.stringify(checks["growth_equipment_choices"]))
	_require(equipment_button_contract, "equipment choices use readable no-WPN two-line labels inside fully visible touch targets", JSON.stringify(checks["growth_equipment_choices"]))
	growth_scroll.scroll_vertical = 0
	await _settle(.1)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = growth_scroll.get_global_rect().position + Vector2(100, 300)
	touch.pressed = true
	get_viewport().push_input(touch, true)
	await get_tree().process_frame
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = touch.position - Vector2(0, 220)
	drag.relative = Vector2(0, -220)
	get_viewport().push_input(drag, true)
	await get_tree().process_frame
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = drag.position
	release.pressed = false
	get_viewport().push_input(release, true)
	await _settle(.1)
	checks["growth_touch_scroll"] = _scroll_snapshot(growth_scroll)
	_require(growth_scroll.scroll_vertical > 0, "finger drag moves the real growth scroll past nested panels", JSON.stringify(checks["growth_touch_scroll"]))


func _primary_scroll() -> ScrollContainer:
	return shell.find_child("PrimaryContentScroll", true, false) as ScrollContainer


func _scroll_to_control(scroll: ScrollContainer, target: Control) -> void:
	if scroll == null or target == null:
		return
	var target_y := target.get_global_rect().position.y
	var scroll_y := scroll.get_global_rect().position.y
	scroll.scroll_vertical = maxi(0, roundi(float(scroll.scroll_vertical) + target_y - scroll_y - 8.0))
	await _settle(.16)


func _find_button(text_fragment: String) -> Button:
	for node_value in shell.find_children("*", "Button", true, false):
		var button := node_value as Button
		if button != null and button.text.contains(text_fragment):
			return button
	return null


func _equipment_option_buttons(section: Control) -> Array[Button]:
	var options: Array[Button] = []
	if section == null:
		return options
	for node_value in section.find_children("MobileEquipmentOption_*", "Button", true, false):
		var option := node_value as Button
		if option != null:
			options.append(option)
	return options


func _scroll_snapshot(scroll: ScrollContainer) -> Dictionary:
	if scroll == null:
		return {"present": false}
	var bar := scroll.get_v_scroll_bar()
	var max_position := 0.0
	var visible := false
	var minimum_width := 0.0
	if bar != null:
		max_position = maxf(0.0, bar.max_value - bar.page)
		visible = bar.visible
		minimum_width = bar.custom_minimum_size.x
	return {
		"present": true,
		"position": float(scroll.scroll_vertical),
		"max_position": max_position,
		"scrollable": max_position > 0.5,
		"bar_visible": visible,
		"bar_minimum_width": minimum_width,
		"rect": _rect_array(scroll.get_global_rect()),
	}


func _control_snapshot(control: Control) -> Dictionary:
	if control == null:
		return {"present": false}
	return {
		"present": true,
		"visible": control.visible,
		"fully_visible": _fully_visible(control),
		"intersects_visible": _intersects_visible(control),
		"rect": _rect_array(control.get_global_rect()),
	}


func _fully_visible(control: Control) -> bool:
	if control == null or not control.visible:
		return false
	var rect := control.get_global_rect()
	var viewport_rect := get_viewport().get_visible_rect()
	return rect.position.x >= viewport_rect.position.x - 1.0 and rect.position.y >= viewport_rect.position.y - 1.0 and rect.end.x <= viewport_rect.end.x + 1.0 and rect.end.y <= viewport_rect.end.y + 1.0


func _intersects_visible(control: Control) -> bool:
	if control == null or not control.visible:
		return false
	return control.get_global_rect().intersects(get_viewport().get_visible_rect())


func _rect_array(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _capture(label: String, stage: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_tree().root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("%s capture exists" % label, "empty image")
		return
	var path := output_dir.path_join("%s.png" % label)
	if image.save_png(path) != OK:
		_fail("%s capture writes" % label, path)
		return
	captures.append({
		"stage": stage,
		"file": path.get_file(),
		"width": image.get_width(),
		"height": image.get_height(),
		"sha256": FileAccess.get_sha256(path),
	})


func _settle(seconds: float) -> void:
	await get_tree().process_frame
	if seconds > 0.0:
		await get_tree().create_timer(seconds, true, false, true).timeout
	await get_tree().process_frame


func _require(condition: bool, label: String, detail := "") -> void:
	if not condition:
		_fail(label, detail)


func _fail(label: String, detail: String) -> void:
	failures.append("%s :: %s" % [label, detail])


func _run_id() -> String:
	return "mobile_n05_reward_growth_viewport_%s" % Time.get_datetime_string_from_system(true).replace(":", "-").replace(" ", "_")


func _finish(exit_code: int, reason: String) -> void:
	if not reason.is_empty():
		push_error(reason)
	if shell != null and is_instance_valid(shell):
		shell.queue_free()
		shell = null
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)
