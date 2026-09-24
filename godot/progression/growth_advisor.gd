class_name GrowthAdvisor
extends RefCounted

## Explainable growth guidance for the result and growth screens.
##
## The advisor compares the party with the next operation the player is heading
## to and ranks concrete upgrades with a reason the player can read:
##   1. a member at their level cap who can break through,
##   2. members below the operation's recommended level (members who went down
##      in the last battle, and the front row that absorbs attacks, come first),
##   3. skill upgrades, then weapon enhancement once levels are on target.
## It never mutates the profile; `execute` goes through the same progression
## services as the manual controls.

const FRONT_ROW_SLOTS := 2

static func target_stage_id() -> String:
	var selected := DataRegistry.stage(str(AppState.selected_stage_id))
	var chapter_id := str(selected.get("chapter_id", ""))
	var chapter := DataRegistry.chapter(chapter_id)
	var route: Array = chapter.get("required_stage_ids", []) + chapter.get("hard_stage_ids", [])
	for stage_id_value in route:
		var stage_id := str(stage_id_value)
		if AppState.is_stage_unlocked(stage_id) and not bool(AppState.profile.get("first_clear", {}).get(stage_id, false)):
			return stage_id
	return str(AppState.selected_stage_id)

## Skill levels the campaign balance assumes for a stage (the same curve
## tools/campaign_balance_calibrator tunes enemies against). Up to chapter 4 the
## recommended level is the requirement; after the level cap, skills are the only
## growth and climb to their maximum by chapter 20.
static func expected_skill_levels(stage: Dictionary) -> Dictionary:
	var post_cap := clampi(int(str(stage.get("chapter_id", "CH01")).substr(2)) - 4, 0, 16)
	if post_cap <= 0:
		return {}
	return {"normal": 2 + roundi(post_cap * .5), "passive": 2 + roundi(post_cap * .5), "ultimate": 1 + roundi(post_cap * .25)}

## Short requirement line for stage / growth headers ("" up to chapter 4).
static func skill_requirement_text(stage: Dictionary) -> String:
	var skills := expected_skill_levels(stage)
	if skills.is_empty():
		return ""
	return "권장 스킬 Lv.%d · 궁극기 Lv.%d" % [int(skills.normal), int(skills.ultimate)]

## One number for "how strong": weighted HP / ATK / DEF plus skill levels.
static func combat_power(character_id: String, state_override: Dictionary = {}) -> int:
	if not AppState.profile.get("roster", {}).has(character_id):
		return 0
	var state: Dictionary = state_override if not state_override.is_empty() else AppState.profile.roster[character_id]
	var stats := CharacterProgression.final_stats(character_id, state)
	var skills: Dictionary = state.get("skills", {})
	var skill_points := int(skills.get("normal", 1)) + int(skills.get("passive", 1)) + int(skills.get("ultimate", 1)) * 2 - 4
	return roundi(float(stats.get("HP", 0)) * .25 + float(stats.get("ATK", 0)) * 2.0 + float(stats.get("DEF", 0)) * 1.5) + skill_points * 30

static func downed_ids_from_result(result: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for death_value in result.get("deaths", []):
		var unit_id := str(death_value.get("unit_id", ""))
		if unit_id.begins_with("P:") and not output.has(unit_id.substr(2)):
			output.append(unit_id.substr(2))
	return output

static func party_report(party_ids: Array, downed_ids: Array = [], stage_id := "") -> Dictionary:
	var target := stage_id if not stage_id.is_empty() else target_stage_id()
	var stage := DataRegistry.stage(target)
	var recommended_level := maxi(1, int(stage.get("recommended_level", 1)))
	var expected_skills := expected_skill_levels(stage)
	var members: Array = []
	var party_cp := 0
	var recommended_cp := 0
	for slot in range(party_ids.size()):
		var character_id := str(party_ids[slot])
		var state: Dictionary = AppState.profile.get("roster", {}).get(character_id, {})
		if state.is_empty():
			continue
		var level := int(state.get("level", 1))
		var at_recommended: Dictionary = state.duplicate(true)
		at_recommended.level = clampi(maxi(level, recommended_level), 1, 100)
		var skills: Dictionary = state.get("skills", {})
		var skill_gaps := {}
		if not expected_skills.is_empty():
			var raised: Dictionary = skills.duplicate(true)
			for skill_slot in expected_skills:
				var current := int(skills.get(skill_slot, 1))
				raised[skill_slot] = maxi(current, int(expected_skills[skill_slot]))
				if current < int(expected_skills[skill_slot]): skill_gaps[skill_slot] = int(expected_skills[skill_slot])
			at_recommended.skills = raised
		var cp := combat_power(character_id)
		var target_cp := maxi(cp, combat_power(character_id, at_recommended))
		party_cp += cp
		recommended_cp += target_cp
		members.append({
			"character_id": character_id,
			"slot": slot,
			"level": level,
			"cap": CharacterProgression.level_cap(state),
			"recommended_level": recommended_level,
			"level_gap": maxi(0, recommended_level - level),
			"combat_power": cp,
			"recommended_power": target_cp,
			"skill_gaps": skill_gaps,
			"downed": downed_ids.has(character_id),
		})
	var readiness := float(party_cp) / maxf(1.0, float(recommended_cp))
	return {
		"stage_id": target,
		"recommended_level": recommended_level,
		"expected_skills": expected_skills,
		"members": members,
		"party_power": party_cp,
		"recommended_power": recommended_cp,
		"readiness": readiness,
		"verdict": verdict_text(readiness),
	}

static func verdict_text(readiness: float) -> String:
	if readiness >= .995:
		return "권장 전투력을 충족했습니다"
	if readiness >= .85:
		return "조금 부족합니다 · 추천 성장 몇 개면 충분합니다"
	return "부족합니다 · 아래 추천 성장을 먼저 진행하세요"

## Best action per member, ranked. Each entry: kind, character_id, action
## (executable, or {} when blocked), title, reason, gain, score.
static func recommendations(party_ids: Array, downed_ids: Array = [], limit := 3, stage_id := "") -> Array:
	var report := party_report(party_ids, downed_ids, stage_id)
	var ranked: Array = []
	for member_value in report.members:
		var entry := _best_for_member(member_value)
		if not entry.is_empty():
			ranked.append(entry)
	ranked.sort_custom(func(left, right):
		if int(left.score) != int(right.score): return int(left.score) > int(right.score)
		return int(left.slot) < int(right.slot))
	return ranked.slice(0, limit)

static func execute(entry: Dictionary) -> GameResult:
	var action: Dictionary = entry.get("action", {})
	if action.is_empty():
		return GameResult.failure(str(entry.get("reason", "NO_ACTION")))
	if str(action.get("kind", "")) == "LEVEL_TO":
		return CharacterProgression.level_to(str(action.character_id), int(action.target))
	return GrowthPlanBuilder.execute(action)

static func _name(character_id: String) -> String:
	return LocalizationService.tr_key(str(DataRegistry.character(character_id).get("name_key", character_id))).replace(" (DEV)", "")

static func _best_for_member(member: Dictionary) -> Dictionary:
	var character_id := str(member.character_id)
	var state: Dictionary = AppState.profile.roster[character_id]
	var name := _name(character_id)
	var level := int(member.level)
	var cap := int(member.cap)
	var gap := int(member.level_gap)
	var front := int(member.slot) < FRONT_ROW_SLOTS
	var reasons: Array[String] = []
	if bool(member.downed):
		reasons.append("지난 전투에서 쓰러졌습니다")
	var base := {"character_id": character_id, "slot": int(member.slot), "name": name}
	# 1. At the cap: breakthrough unlocks the next 20 levels.
	if level >= cap and GrowthPlanBuilder._can_breakthrough(character_id):
		var next_cap: int = [20, 40, 60, 80, 90, 100][clampi(int(state.get("breakthrough", 0)) + 1, 0, 5)]
		reasons.push_front("레벨 상한 Lv.%d 도달 · 돌파하면 Lv.%d까지 성장합니다" % [cap, mini(next_cap, int(AppState.profile.account.level))])
		return _entry(base, "BREAKTHROUGH", {"kind": "BREAKTHROUGH", "character_id": character_id}, "%s 돌파" % name, reasons, "능력치 배율 상승", 120 + gap * 10)
	# 2. Below the operation's recommended level.
	if gap > 0:
		reasons.push_front("권장 Lv.%d보다 %d레벨 낮습니다" % [int(member.recommended_level), gap])
		if front and not bool(member.downed):
			reasons.append("전열은 적의 공격을 먼저 받습니다")
		var score := 60 + gap * 10 + (30 if bool(member.downed) else 0) + (6 if front else 0)
		if level >= cap:
			reasons.append("계정 레벨 Lv.%d가 상한입니다 · 작전을 진행해 계정 레벨을 올리세요" % int(AppState.profile.account.level) if cap >= int(AppState.profile.account.level) else "돌파 재료가 필요합니다")
			return _entry(base, "BLOCKED", {}, "%s 성장 대기" % name, reasons, "", score - 40)
		var target := mini(int(member.recommended_level), CharacterProgression.maximum_target(character_id))
		if target <= level:
			reasons.append("훈련 노트나 크레딧이 부족합니다 · 작전과 소탕으로 모으세요")
			return _entry(base, "BLOCKED", {}, "%s 레벨업 재료 부족" % name, reasons, "", score - 40)
		var after: Dictionary = state.duplicate(true)
		after.level = target
		return _entry(base, "LEVEL_TO", {"kind": "LEVEL_TO", "character_id": character_id, "target": target}, "%s Lv.%d → Lv.%d" % [name, level, target], reasons, _gain_text(character_id, state, after), score)
	# 3. Levels on target: skills, then weapon.
	var definition := DataRegistry.character(character_id)
	var slots := ["passive", "ultimate", "normal"] if str(definition.get("role", "")) in ["GUARDIAN", "MEDIC"] else ["ultimate", "normal", "passive"]
	for slot in slots:
		var cost := SkillUpgradeService.next_cost(character_id, slot)
		if cost.is_empty() or not AppState.can_pay(cost):
			continue
		var comparison := SkillUpgradeService.comparison(character_id, slot)
		var slot_name: String = {"normal": "일반 스킬", "passive": "패시브", "ultimate": "궁극기"}[slot]
		var skill_gaps: Dictionary = member.get("skill_gaps", {})
		var score := 25 + (10 if bool(member.downed) else 0)
		if skill_gaps.has(slot):
			# After the level cap, the operation is tuned against these skill levels.
			reasons.push_front("이 작전은 %s Lv.%d 기준으로 조정되어 있습니다" % [slot_name, int(skill_gaps[slot])])
			score += 30 + (int(skill_gaps[slot]) - int(state.skills[slot])) * 5
		else:
			reasons.push_front("레벨은 권장 수준입니다 · %s 위력을 올립니다" % slot_name)
		var gain := "계수 %.2f → %.2f" % [float(comparison.current), float(comparison.next)] if comparison.next != null else ""
		return _entry(base, "SKILL", {"kind": "SKILL", "character_id": character_id, "slot": slot}, "%s %s Lv.%d → Lv.%d" % [name, slot_name, int(state.skills[slot]), int(state.skills[slot]) + 1], reasons, gain, score)
	var weapon_id := str(state.get("equipped_weapon_id", ""))
	var material := GrowthPlanBuilder.weapon_material_that_fits(weapon_id)
	if not weapon_id.is_empty() and not material.is_empty():
		reasons.push_front("레벨과 스킬은 준비됐습니다 · 무기로 공격력을 보강합니다")
		return _entry(base, "WEAPON_LEVEL", {"kind": "WEAPON_LEVEL", "weapon_id": weapon_id, "material_id": material}, "%s 무기 강화" % name, reasons, "공격력 상승", 12)
	return {}

static func _entry(base: Dictionary, kind: String, action: Dictionary, title: String, reasons: Array[String], gain: String, score: int) -> Dictionary:
	var entry := base.duplicate(true)
	entry.merge({"kind": kind, "action": action, "title": title, "reason": " · ".join(reasons), "gain": gain, "score": score})
	return entry

static func _gain_text(character_id: String, before_state: Dictionary, after_state: Dictionary) -> String:
	var before := CharacterProgression.final_stats(character_id, before_state)
	var after := CharacterProgression.final_stats(character_id, after_state)
	return "전투력 +%s · 체력 +%s · 공격력 +%s · 방어력 +%s" % [
		MathUtil.comma(combat_power(character_id, after_state) - combat_power(character_id, before_state)),
		MathUtil.comma(int(after.get("HP", 0)) - int(before.get("HP", 0))),
		MathUtil.comma(int(after.get("ATK", 0)) - int(before.get("ATK", 0))),
		MathUtil.comma(int(after.get("DEF", 0)) - int(before.get("DEF", 0))),
	]
