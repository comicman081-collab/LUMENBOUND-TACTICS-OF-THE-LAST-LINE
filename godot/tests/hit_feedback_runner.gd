extends Node

## Phase 4 / D6 (2026-09-30): hit feedback. Hit classification, damage-scaled
## camera impulse with the 55 ms hit-stop cap, shake presets, knockback slide,
## the 2-frame white flash and the four damage-number shapes. View-only.

const HitFeedback := preload("res://battle/view/combat_hit_feedback.gd")
const Director := preload("res://battle/view/battle_presentation_director.gd")
const Choreography := preload("res://battle/view/battle_actor_choreography.gd")
const Weapons := preload("res://battle/view/combat_weapon_effects.gd")

var checks := 0
var failures := 0
var draw_probe: Control

func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("%s %s" % [label, detail])

func _ready() -> void:
	AppState.new_game()
	_classification()
	_weight_and_strength()
	_director()
	_slide()
	_view_integration()
	await _draw_smoke()
	print("HIT_FEEDBACK_TESTS total=%d pass=%d fail=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _event(value: int, extra := {}, target := "P:1") -> Dictionary:
	return BattleEvent.make(1, BattleEvent.DAMAGE, "E:1", target, value, extra)

func _classification() -> void:
	check(HitFeedback.damage_style(_event(0)) == "miss", "zero damage is a miss")
	check(HitFeedback.damage_style(_event(10, {"crit": true})) == "crit", "a critical hit is crit")
	check(HitFeedback.damage_style(_event(10, {"affinity_factor": 1.25})) == "weak", "an affinity advantage is weak")
	check(HitFeedback.damage_style(_event(10, {"affinity_factor": .85})) == "resist", "an affinity disadvantage is resist")
	check(HitFeedback.damage_style(_event(10, {"affinity_factor": 1.0})) == "normal" and HitFeedback.damage_style(_event(10)) == "normal", "neutral affinity is normal")
	check(HitFeedback.damage_style(_event(10, {"crit": true, "affinity_factor": 1.25})) == "crit", "crit wins over weak")
	check(HitFeedback.damage_style(_event(10, {"source": "DAMAGE_OVER_TIME", "hp_damage": 10})) == "normal", "damage over time reads as a plain number")
	var shapes := {}
	for style in ["normal", "crit", "weak", "heal", "resist", "shield", "miss"]:
		var spec := HitFeedback.number_style(style)
		shapes[style] = "%s|%s|%s" % [spec.ink.to_html(), spec.tag, spec.size]
	var distinct := {}
	for value in shapes.values(): distinct[value] = true
	check(distinct.size() == shapes.size(), "each damage-number kind has its own ink, tag and size", JSON.stringify(shapes))
	check(HitFeedback.number_style("nonsense") == HitFeedback.NUMBER_STYLES.normal, "an unknown style falls back to the plain number")

func _weight_and_strength() -> void:
	var target := {"max_hp": 1000, "hp": 1000}
	check(is_zero_approx(HitFeedback.damage_weight(_event(0), target)), "a miss has no weight")
	var light := HitFeedback.damage_weight(_event(30, {"hp_damage": 30}), target)
	var heavy := HitFeedback.damage_weight(_event(200, {"hp_damage": 200}), target)
	var huge := HitFeedback.damage_weight(_event(900, {"hp_damage": 900}), target)
	check(light > 0.0 and light < heavy and is_equal_approx(huge, 1.0), "weight grows with the share of max HP and saturates at 1", "%f %f %f" % [light, heavy, huge])
	check(HitFeedback.damage_weight(_event(50), {}) >= 0.0 and HitFeedback.damage_weight(_event(50), {}) <= 1.0, "a target without HP data still yields a bounded weight")
	var normal_small := HitFeedback.impact_strength("normal", .1, "NORMAL", false)
	var normal_big := HitFeedback.impact_strength("normal", .9, "NORMAL", false)
	check(normal_small < normal_big, "a bigger hit shakes harder", "%f %f" % [normal_small, normal_big])
	check(HitFeedback.impact_strength("crit", .5, "NORMAL", false) > HitFeedback.impact_strength("normal", .5, "NORMAL", false), "a crit shakes harder than a plain hit")
	check(HitFeedback.impact_strength("resist", .5, "NORMAL", false) < HitFeedback.impact_strength("normal", .5, "NORMAL", false), "a resisted hit shakes less")
	check(HitFeedback.impact_strength("normal", 0.0, "ULTIMATE", false) >= .82, "an ultimate keeps its strong floor")
	check(HitFeedback.impact_strength("normal", 0.0, "NORMAL", true) >= .40, "a boss hit keeps a floor")
	var all_bounded := true
	for style in ["normal", "crit", "weak", "resist", "miss"]:
		for weight in [0.0, .3, 1.0]:
			for kind in ["NORMAL", "ULTIMATE"]:
				var value := HitFeedback.impact_strength(style, weight, kind, true)
				if value < .12 or value > 1.0: all_bounded = false
	check(all_bounded, "impact strength always stays inside 0.12..1.0")
	check(HitFeedback.shake_preset("normal", .1, "NORMAL") == "tap" and HitFeedback.shake_preset("normal", .8, "NORMAL") == "thud" and HitFeedback.shake_preset("crit", .1, "NORMAL") == "snap" and HitFeedback.shake_preset("normal", .1, "ULTIMATE") == "quake", "shake preset follows weight, crit and ultimate")
	check(HitFeedback.impact_accent("crit") == "crit" and HitFeedback.impact_accent("weak") == "weak" and HitFeedback.impact_accent("normal") == "", "only crit and weak hits add a burst accent")
	var light_span := HitFeedback.reaction_span("normal", .1)
	var heavy_span := HitFeedback.reaction_span("normal", 1.0)
	var crit_span := HitFeedback.reaction_span("crit", 1.0)
	check(float(light_span.power) < float(heavy_span.power) and float(heavy_span.power) < float(crit_span.power) and float(light_span.duration) < float(heavy_span.duration), "knockback distance and flash length grow with the hit")

func _director() -> void:
	var light = Director.new()
	light.request_combat_impact(.2, "tap")
	var heavy = Director.new()
	heavy.request_combat_impact(1.0, "quake")
	var light_stop := float(light.cinematic_snapshot().get("combat_hitstop_remaining", 0.0))
	var heavy_stop := float(heavy.cinematic_snapshot().get("combat_hitstop_remaining", 0.0))
	check(light_stop > 0.0 and light_stop < heavy_stop and heavy_stop <= .055001, "hit-stop grows with the hit and never passes 55 ms", "%f %f" % [light_stop, heavy_stop])
	var offsets := {}
	for preset in HitFeedback.SHAKE_PRESETS:
		var shaker = Director.new()
		shaker.request_combat_impact(.8, preset)
		shaker.advance(.031)
		offsets[preset] = shaker.battlefield_offset()
		check(str(shaker.cinematic_snapshot().combat_impulse_preset) == preset, "the %s preset is stored" % preset)
	var unique := {}
	for preset in offsets: unique[str(offsets[preset])] = true
	check(unique.size() == 4, "each shake preset moves the battlefield differently", JSON.stringify(offsets))
	check(absf(float(offsets.quake.y)) > absf(float(offsets.quake.x)) * .3 and absf(float(offsets.snap.x)) > absf(float(offsets.snap.y)) * .3, "quake is vertical-heavy and snap is horizontal-heavy")
	var owner = Director.new()
	owner.request_combat_impact(.9, "quake")
	owner.request_combat_impact(.3, "tap")
	check(str(owner.cinematic_snapshot().combat_impulse_preset) == "quake", "the strongest impulse keeps its shake shape")
	var bad = Director.new()
	bad.request_combat_impact(.5, "not-a-preset")
	check(str(bad.cinematic_snapshot().combat_impulse_preset) == "thud", "an unknown preset falls back to thud")
	var default_shape = Director.new()
	default_shape.request_combat_impact(.5)
	check(str(default_shape.cinematic_snapshot().combat_impulse_preset) == "thud", "no preset keeps the original shake")
	owner.advance(.4)
	check(str(owner.cinematic_snapshot().combat_impulse_preset) == "thud" and owner.battlefield_offset().length() == 0.0 and is_equal_approx(owner.battlefield_zoom(), 1.0), "an expired impulse leaves no shake and resets the preset")
	heavy.force_finish()
	check(str(heavy.cinematic_snapshot().combat_impulse_preset) == "thud" and heavy.battlefield_offset().length() == 0.0, "skip clears the shake preset")
	var sustained = Director.new()
	var moving := 0.0
	for _frame in range(100):
		sustained.request_combat_impact(1.0, "quake")
		moving += float(sustained.advance(.01).actor_delta)
	check(moving >= .70, "damage-scaled impacts still leave at least 70 percent moving time")

func _slide() -> void:
	var base := {"offset": Vector2.ZERO, "rotation": 0.0, "scale": Vector2.ONE}
	var plain: Dictionary = Choreography.add_hit_reaction(base.duplicate(true), "PLAYER", .07)
	var explicit: Dictionary = Choreography.add_hit_reaction(base.duplicate(true), "PLAYER", .07, .14, 1.0)
	check(plain.offset == explicit.offset and plain.rotation == explicit.rotation, "power 1 keeps the original recoil")
	var small: Dictionary = Choreography.add_hit_reaction(base.duplicate(true), "PLAYER", .06, .16, 1.0)
	var big: Dictionary = Choreography.add_hit_reaction(base.duplicate(true), "PLAYER", .06, .16, 2.0)
	check(absf(float(big.offset.x)) > absf(float(small.offset.x)) * 1.4, "a heavier hit slides further back")
	var enemy_big: Dictionary = Choreography.add_hit_reaction(base.duplicate(true), "ENEMY", .06, .16, 2.0)
	check(float(big.offset.x) < 0.0 and float(enemy_big.offset.x) > 0.0, "the slide goes away from the attacker for both teams")
	var start: Dictionary = Choreography.add_hit_reaction(base.duplicate(true), "PLAYER", .16, .16, 2.0)
	var finish: Dictionary = Choreography.add_hit_reaction(base.duplicate(true), "PLAYER", .001, .16, 2.0)
	check(absf(float(start.offset.x)) < 1.0 and absf(float(finish.offset.x)) < 4.0, "the slide starts and ends at rest")
	var early: Dictionary = Choreography.add_hit_reaction(base.duplicate(true), "PLAYER", .16 * .8, .16, 2.0)
	var late: Dictionary = Choreography.add_hit_reaction(base.duplicate(true), "PLAYER", .16 * .2, .16, 2.0)
	check(absf(float(early.offset.x)) > absf(float(late.offset.x)), "the slide leaves fast and returns slowly")
	check(Choreography.add_hit_reaction(base.duplicate(true), "PLAYER", 0.0, .16, 2.0).offset == Vector2.ZERO, "no remaining flash means no slide")

func _sim() -> BattleSimulation:
	var sim := BattleSimulation.new()
	sim.setup(AppState.create_party_snapshot(), DataRegistry.stage("CH01-N01"), 4401, DataRegistry.data)
	return sim

func _view_integration() -> void:
	var sim := _sim()
	var view := BattleView.new()
	view.size = Vector2(1600, 900)
	view.setup(sim)
	var victim: Dictionary = sim.state.enemies[0]
	var ally: Dictionary = sim.state.party[0]
	var uid := str(victim.uid)
	var attacker_uid := str(ally.uid)
	var max_hp := int(victim.max_hp)
	var plain := BattleEvent.make(sim.state.tick, BattleEvent.DAMAGE, attacker_uid, uid, int(max_hp * .05), {"hp_damage": int(max_hp * .05), "source": "BASIC", "affinity_factor": 1.0})
	view._present_regular_event(plain)
	check(int(view.hit_flash_frames.get(uid, 0)) == 2, "a landed hit starts a 2-frame white flash")
	check(view.unit_flash.has(uid) and view.unit_flash_span.has(uid), "a hit registers its flash and slide span")
	view._process(.016)
	check(int(view.hit_flash_frames.get(uid, 0)) == 1, "the white flash is still on for the second frame")
	view._process(.016)
	check(not view.hit_flash_frames.has(uid), "the white flash is over after two frames")
	check(view.unit_flash.has(uid), "the pink recoil tint outlasts the white flash")
	var light_power := float(view.unit_flash_span[uid].power)
	var heavy := BattleEvent.make(sim.state.tick, BattleEvent.DAMAGE, attacker_uid, uid, int(max_hp * .4), {"hp_damage": int(max_hp * .4), "source": "BASIC", "crit": true})
	view._present_regular_event(heavy)
	check(float(view.unit_flash_span[uid].power) > light_power, "a heavy crit slides further than a light hit")
	var miss_view := BattleView.new()
	miss_view.size = Vector2(1600, 900)
	miss_view.setup(_sim())
	miss_view._present_regular_event(BattleEvent.make(1, BattleEvent.DAMAGE, attacker_uid, uid, 0, {"miss": true}))
	check(miss_view.hit_flash_frames.is_empty(), "a miss never flashes white")
	miss_view.free()
	# Number kinds through the spawn path.
	view.floating_texts.clear()
	view._spawn_damage_text(_event(120, {"crit": true}, uid))
	view._spawn_damage_text(_event(80, {"affinity_factor": 1.25}, uid))
	view._spawn_damage_text(_event(60, {"affinity_factor": .85}, uid))
	view._spawn_damage_text(_event(50, {}, uid))
	view._spawn_damage_text(_event(0, {"miss": true}, uid))
	var styles: Array = []
	for text in view.floating_texts: styles.append(str(text.style))
	check(styles == ["crit", "weak", "resist", "normal", "miss"], "damage numbers carry their kind", JSON.stringify(styles))
	check(bool(view.floating_texts[0].crit) and not bool(view.floating_texts[3].crit), "the legacy crit flag still follows the crit kind")
	check(float(view.floating_texts[0].duration) > float(view.floating_texts[3].duration) and float(view.floating_texts[4].duration) > 0.0, "a crit number lingers longer than a plain one")
	var sizes: Array = []
	for text in view.floating_texts:
		text.age = .3
		sizes.append(int(view.damage_number_layout(text).font_size))
	check(sizes[0] > sizes[1] and sizes[1] > sizes[3] and sizes[3] > sizes[2] and sizes[2] > sizes[4], "number size runs crit > weak > normal > resist > miss", JSON.stringify(sizes))
	# Heal and shield go through the event handler.
	view.floating_texts.clear()
	view._present_regular_event(BattleEvent.make(1, BattleEvent.HEAL, attacker_uid, attacker_uid, 40))
	view._present_regular_event(BattleEvent.make(1, BattleEvent.SHIELD, attacker_uid, attacker_uid, 25))
	check(view.floating_texts.size() == 2 and str(view.floating_texts[0].style) == "heal" and str(view.floating_texts[1].style) == "shield", "heal and shield numbers have their own kinds")
	var heal_layout := view.damage_number_layout(view.floating_texts[0])
	check(str(heal_layout.style) == "heal" and not bool(heal_layout.crit), "the heal number lays out as a heal")
	# A legacy text dictionary with no style still lays out.
	var legacy := {"target": uid, "text": "77", "color": Color.WHITE, "age": 0.0, "duration": 1.15}
	check(str(view.damage_number_layout(legacy).style) == "normal" and str(view.damage_number_layout({"target": uid, "text": "MISS", "color": Color.WHITE, "age": 0.0}).style) == "miss", "a text without a style keeps the old reading")
	# Effects reach the pooled VFX with their accent, and cleanup empties everything.
	view.vfx_presentations.clear()
	view._present_regular_event(BattleEvent.make(sim.state.tick, BattleEvent.DAMAGE, attacker_uid, uid, int(max_hp * .1), {"hp_damage": int(max_hp * .1), "source": "NORMAL", "crit": true}))
	var accents: Array = []
	for vfx in view.vfx_presentations:
		if str(vfx.kind).begins_with("impact_"): accents.append(str(vfx.accent))
	check(accents.has("crit"), "a crit impact carries the crit burst accent", JSON.stringify(accents))
	view._present_regular_event(BattleEvent.make(sim.state.tick, BattleEvent.DAMAGE, attacker_uid, uid, int(max_hp * .1), {"hp_damage": int(max_hp * .1), "source": "NORMAL"}))
	check(str(view.vfx_presentations[view.vfx_presentations.size() - 1].accent) == "", "a plain impact carries no accent")
	view._clear_active_presentation_effects()
	check(view.hit_flash_frames.is_empty() and view.unit_flash_span.is_empty() and view.unit_flash.is_empty() and view.floating_texts.is_empty() and view.vfx_presentations.is_empty(), "clearing presentation effects clears flash frames, slide spans, numbers and VFX")
	check(int(view.presentation_residual_snapshot().active_effect_count) == 0, "no pooled effects remain after cleanup")
	view.free()
	# The ultimate batch path uses the same feedback.
	var batch_view := BattleView.new()
	batch_view.size = Vector2(1600, 900)
	batch_view.setup(_sim())
	batch_view._present_ultimate_batch_event(BattleEvent.make(1, BattleEvent.DAMAGE, attacker_uid, uid, int(max_hp * .3), {"hp_damage": int(max_hp * .3), "source": "ULTIMATE", "crit": true}))
	check(int(batch_view.hit_flash_frames.get(uid, 0)) == 2 and str(batch_view.floating_texts[0].style) == "crit", "an ultimate hit flashes white and shows a crit number")
	check(str(batch_view.presentation_director.cinematic_snapshot().combat_impulse_preset) == "quake", "an ultimate hit shakes with the quake preset")
	batch_view.free()

class DrawProbe extends Control:
	var frames := 0
	var t := 0.0
	func _draw() -> void:
		frames += 1
		var styles := ["blade", "claw", "rifle", "burst", "mortar", "siege", "shield", "prism", "seal", "heal"]
		for index in range(styles.size()):
			var origin := Vector2(60 + index * 70, 120)
			var target := origin + Vector2(0, 200)
			for action in ["basic_attack", "ultimate"]:
				Weapons.action(self, origin, target, styles[index], t, action, Color("7bdeed"), 1.0)
			Weapons.telegraph(self, target, styles[index], .3, .44, true, 1.0)
			for accent in ["", "crit", "weak"]:
				Weapons.impact(self, target, styles[index], t, Color("ff9464"), 1.0, accent)

func _draw_smoke() -> void:
	draw_probe = DrawProbe.new()
	draw_probe.size = Vector2(800, 400)
	add_child(draw_probe)
	# Sweep the timeline so every branch (before, during and after the effect) draws.
	var times := [0.0, .05, .1, .2, .3, .45, .7, 1.0, 1.2]
	for t in times:
		draw_probe.t = t
		draw_probe.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
	check(draw_probe.frames >= times.size(), "every weapon family draws its action and impact sets at every stage of the timeline", str(draw_probe.frames))
	draw_probe.queue_free()
