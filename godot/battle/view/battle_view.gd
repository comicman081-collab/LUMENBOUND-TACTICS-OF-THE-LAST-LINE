class_name BattleView
extends Control

signal battle_finished(result: Dictionary)

var simulation: BattleSimulation
var accumulator := 0.0
var speed := 1
var paused := false
var emitted_finish := false
var consumed_events := 0
var floating_texts: Array = []
var projectiles: Array = []
var free_floating_texts: Array = []
var free_projectiles: Array = []
var unit_flash: Dictionary = {}
var sprite_library := BattleSpriteLibrary.new()
var sprite_pack_ready := false
var projectile_library := ProjectileSpriteLibrary.new()
var projectile_pack_ready := false
var animation_tracks: Dictionary = {}
var entry_tracks: Dictionary = {}
var vfx_presentations: Array = []
var free_vfx_presentations: Array = []
var skill_callouts: Array = []
var free_skill_callouts: Array = []
var vfx_frames: Dictionary = {}
var normal_background: Texture2D
var boss_background: Texture2D
const MAX_PRESENTATION_SPEED := 1.35

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite_pack_ready = sprite_library.load_pack()
	if not sprite_pack_ready and sprite_library.load_error != "MANIFEST_MISSING":
		push_warning("Battle sprite pack unavailable: %s" % sprite_library.load_error)
	projectile_pack_ready = projectile_library.load_pack()
	if not projectile_pack_ready:
		push_warning("Projectile sprite pack unavailable: %s" % projectile_library.load_error)
	normal_background = load("res://assets/art/backgrounds/BG_BATTLE_GLASS_RAIL/bg_battle_glass_rail_1920x1080.png")
	boss_background = load("res://assets/art/backgrounds/BG_BOSS_SIGNAL_CATHEDRAL/bg_boss_signal_cathedral_1920x1080.png")
	_load_pilot_vfx()
	set_process(true)

func setup(value: BattleSimulation) -> void:
	simulation = value
	accumulator = 0.0
	emitted_finish = false
	consumed_events = 0
	free_floating_texts.append_array(floating_texts)
	free_projectiles.append_array(projectiles)
	free_vfx_presentations.append_array(vfx_presentations)
	free_skill_callouts.append_array(skill_callouts)
	floating_texts.clear()
	projectiles.clear()
	vfx_presentations.clear()
	skill_callouts.clear()
	animation_tracks.clear()
	entry_tracks.clear()
	for unit in simulation.state.party + simulation.state.enemies:
		animation_tracks[unit.uid] = {"name": "move", "elapsed": 0.0}
		entry_tracks[unit.uid] = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if simulation == null: return
	if not paused and not simulation.state.ended:
		accumulator += delta * speed
		var safety := 0
		while accumulator >= BattleSimulation.TICK_DELTA and safety < 30:
			simulation.tick()
			accumulator -= BattleSimulation.TICK_DELTA
			safety += 1
	if not paused:
		# Simulation remains exact at the selected 1x/2x/3x speed.  Presentation
		# deliberately has a readable upper speed so NORMAL/ULT events never become
		# a one-frame flash at 3x.
		var presentation_delta := delta * minf(float(speed), MAX_PRESENTATION_SPEED)
		_advance_animations(presentation_delta)
		_advance_entries(presentation_delta)
	_consume_events()
	for text in floating_texts:
		text.age = float(text.age) + delta
	if not paused:
		for projectile in projectiles:
			projectile.age = float(projectile.age) + delta * minf(float(speed), 1.8)
		for presentation in vfx_presentations:
			presentation.age = float(presentation.age) + delta * minf(float(speed), MAX_PRESENTATION_SPEED)
		for callout in skill_callouts:
			callout.age = float(callout.age) + delta * minf(float(speed), MAX_PRESENTATION_SPEED)
	_recycle_expired_presentations()
	for uid in unit_flash.keys():
		unit_flash[uid] = float(unit_flash[uid]) - delta
		if float(unit_flash[uid]) <= 0: unit_flash.erase(uid)
	queue_redraw()
	if simulation.state.ended and not emitted_finish:
		emitted_finish = true
		battle_finished.emit(simulation.result_snapshot())

func _consume_events() -> void:
	while consumed_events < simulation.event_log.size():
		var event: Dictionary = simulation.event_log[consumed_events]
		consumed_events += 1
		if event.type == BattleEvent.DAMAGE:
			_spawn_floating_text({"target": event.target, "text": "MISS" if int(event.value) == 0 else ("CRIT %d" % event.value if event.extra.get("crit", false) else str(event.value)), "color": Color("ffd166") if event.extra.get("crit", false) else Color.WHITE, "age": 0.0})
			unit_flash[event.target] = .14
			var hit_unit := simulation.find_unit(str(event.target))
			if not hit_unit.is_empty():
				if str(hit_unit.team) == "PLAYER": AudioService.play_event("PLAYER_HIT", .06)
				elif str(hit_unit.get("rank", "NORMAL")) == "BOSS": AudioService.play_event("BOSS_HIT", .06)
				else: AudioService.play_event("ENEMY_HIT", .06)
			if int(event.value) > 0:
				var damage_source := str(event.extra.get("source", ""))
				if damage_source in ["NORMAL", "ULTIMATE"]:
					_spawn_projectile(str(event.source), str(event.target), damage_source)
					_spawn_vfx(str(event.source), str(event.target), "impact_%s" % damage_source.to_lower(), .18 if damage_source == "NORMAL" else .28)
				var damaged := simulation.find_unit(str(event.target))
				if not damaged.is_empty() and UnitState.alive(damaged): _play_animation(str(event.target), "hit")
		elif event.type == BattleEvent.HEAL:
			_spawn_floating_text({"target": event.target, "text": "+%d" % event.value, "color": Color("76e6a5"), "age": 0.0})
			_spawn_vfx(str(event.source), str(event.target), "heal")
		elif event.type == BattleEvent.SHIELD:
			_spawn_floating_text({"target": event.target, "text": "SHIELD %d" % event.value, "color": Color("72d5ff"), "age": 0.0})
			_spawn_vfx(str(event.source), str(event.target), "shield")
		elif event.type == BattleEvent.BASIC_ATTACK:
			var basic_source := simulation.find_unit(str(event.source))
			if str(basic_source.team) == "PLAYER": AudioService.play_event("PLAYER_BASIC_ATTACK", .05)
			elif str(basic_source.get("rank", "NORMAL")) == "BOSS": AudioService.play_event("BOSS_BASIC_ATTACK", .05)
			else: AudioService.play_event("ENEMY_BASIC_ATTACK", .05)
			_spawn_projectile(str(event.source), str(event.target), "BASIC")
			_spawn_vfx(str(event.source), str(event.target), "basic")
			_play_animation(str(event.source), "basic_attack")
		elif event.type == BattleEvent.NORMAL_SKILL:
			var skill_source := simulation.find_unit(str(event.source))
			if str(skill_source.team) == "PLAYER": AudioService.play_event("PLAYER_NORMAL_SKILL", .10)
			elif str(skill_source.get("rank", "NORMAL")) == "BOSS": AudioService.play_event("BOSS_SKILL", .10)
			else: AudioService.play_event("ENEMY_SKILL", .10)
			_spawn_skill_callout(str(event.source), "SKILL", Color("79e8ff"))
			_spawn_vfx(str(event.source), str(event.target), "normal")
			_play_animation(str(event.source), "normal_skill")
		elif event.type == BattleEvent.ULTIMATE:
			var ultimate_source := simulation.find_unit(str(event.source))
			if str(ultimate_source.team) == "PLAYER": AudioService.play_event("PLAYER_ULTIMATE", .12)
			elif str(ultimate_source.get("rank", "NORMAL")) == "BOSS": AudioService.play_event("BOSS_SKILL", .12)
			else: AudioService.play_event("ENEMY_SKILL", .12)
			_spawn_skill_callout(str(event.source), "ULT", Color("ffd36f"))
			_spawn_vfx(str(event.source), str(event.target), "ultimate")
			_play_animation(str(event.source), "ultimate")
		elif event.type == BattleEvent.DOWN:
			_play_animation(str(event.target), "down")
		elif event.type == BattleEvent.SPAWN:
			animation_tracks[event.source] = {"name": "move", "elapsed": 0.0}
			entry_tracks[event.source] = 0.0
		elif event.type == BattleEvent.BATTLE_END and int(event.value) == 1:
			for unit in simulation.state.party:
				if UnitState.alive(unit): _play_animation(str(unit.uid), "victory")

func _spawn_projectile(source_uid: String, target_uid: String, attack_kind: String) -> void:
	var source := simulation.find_unit(source_uid)
	if source.is_empty(): return
	var source_id := str(source.get("def_id", ""))
	var duration := projectile_library.duration(source_id) if projectile_pack_ready else .32
	# Asset projectile loops stay fast for basic fire, while skill shots remain
	# visible long enough to read their travel and endpoint impact.
	if attack_kind == "NORMAL": duration = maxf(duration, .28)
	elif attack_kind == "ULTIMATE": duration = maxf(duration, .42)
	var projectile: Dictionary = free_projectiles.pop_back() if not free_projectiles.is_empty() else {}
	projectile.clear()
	projectile.merge({
		"source": source_uid,
		"target": target_uid,
		"source_id": source_id,
		"attack_kind": attack_kind,
		"age": 0.0,
		"duration": maxf(.05, duration),
	})
	projectiles.append(projectile)

func _spawn_floating_text(data: Dictionary) -> void:
	var item: Dictionary = free_floating_texts.pop_back() if not free_floating_texts.is_empty() else {}
	item.clear()
	item.merge(data)
	floating_texts.append(item)

func _spawn_vfx(source_uid: String, target_uid: String, kind: String, delay := 0.0) -> void:
	var source := simulation.find_unit(source_uid)
	if source.is_empty(): return
	var key := "%s_%s" % [str(source.get("def_id", "")).to_lower(), kind]
	var presentation: Dictionary = free_vfx_presentations.pop_back() if not free_vfx_presentations.is_empty() else {}
	presentation.clear()
	var duration := 0.40
	if kind == "normal": duration = 0.72
	elif kind == "ultimate": duration = 1.00
	elif kind == "impact_normal": duration = .46
	elif kind == "impact_ultimate": duration = .68
	elif kind in ["heal", "shield"]: duration = .56
	presentation.merge({"source": source_uid, "target": target_uid, "kind": kind, "key": key, "textured": vfx_frames.has(key), "age": 0.0, "delay": delay, "duration": duration})
	vfx_presentations.append(presentation)

func _spawn_skill_callout(source_uid: String, label: String, color: Color) -> void:
	var item: Dictionary = free_skill_callouts.pop_back() if not free_skill_callouts.is_empty() else {}
	item.clear()
	item.merge({"source": source_uid, "label": label, "color": color, "age": 0.0, "duration": 0.78})
	skill_callouts.append(item)

func _recycle_expired_presentations() -> void:
	for index in range(floating_texts.size() - 1, -1, -1):
		if float(floating_texts[index].age) >= 1.0:
			free_floating_texts.append(floating_texts[index])
			floating_texts.remove_at(index)
	for index in range(projectiles.size() - 1, -1, -1):
		if float(projectiles[index].age) >= float(projectiles[index].get("duration", .4)):
			free_projectiles.append(projectiles[index])
			projectiles.remove_at(index)
	for index in range(vfx_presentations.size() - 1, -1, -1):
		if float(vfx_presentations[index].age) >= float(vfx_presentations[index].get("delay", 0.0)) + float(vfx_presentations[index].duration):
			free_vfx_presentations.append(vfx_presentations[index])
			vfx_presentations.remove_at(index)
	for index in range(skill_callouts.size() - 1, -1, -1):
		if float(skill_callouts[index].age) >= float(skill_callouts[index].duration):
			free_skill_callouts.append(skill_callouts[index])
			skill_callouts.remove_at(index)

func pool_diagnostics() -> Dictionary:
	return {"active_projectiles": projectiles.size(), "free_projectiles": free_projectiles.size(), "active_floating_texts": floating_texts.size(), "free_floating_texts": free_floating_texts.size(), "active_vfx": vfx_presentations.size(), "free_vfx": free_vfx_presentations.size(), "active_skill_callouts": skill_callouts.size(), "free_skill_callouts": free_skill_callouts.size()}

func _load_pilot_vfx() -> void:
	for character_id in ["chr001", "chr008"]:
		for kind in ["basic", "normal", "ultimate"]:
			var key := "%s_%s" % [character_id, kind]
			var folder := "vfx_%s" % key
			var textures: Array[Texture2D] = []
			for frame in range(12):
				var path := "res://assets/art/vfx/%s/%s_%02d.png" % [folder, folder, frame]
				var texture = load(path)
				if texture is Texture2D: textures.append(texture)
			if textures.size() == 12: vfx_frames[key] = textures

func _play_animation(uid: String, animation_name: String) -> void:
	animation_tracks[uid] = {"name": animation_name, "elapsed": 0.0}

func _advance_animations(delta: float) -> void:
	for uid in animation_tracks:
		var track: Dictionary = animation_tracks[uid]
		track.elapsed = float(track.get("elapsed", 0.0)) + delta
		var animation_name := str(track.get("name", "idle"))
		var unit := simulation.find_unit(str(uid))
		var character_id := str(unit.get("def_id", ""))
		if sprite_pack_ready and sprite_library.supports_character(character_id) and not sprite_library.is_looping(character_id, animation_name):
			var duration := sprite_library.duration(character_id, animation_name)
			if duration > 0.0 and float(track.elapsed) >= duration and animation_name not in ["down", "victory"]:
				track.name = "move" if float(entry_tracks.get(uid, 1.0)) < 1.0 else "idle"
				track.elapsed = 0.0
		animation_tracks[uid] = track

func _advance_entries(delta: float) -> void:
	for uid in entry_tracks:
		entry_tracks[uid] = minf(1.0, float(entry_tracks[uid]) + delta / 0.9)
		if float(entry_tracks[uid]) >= 1.0:
			var track: Dictionary = animation_tracks.get(uid, {})
			if str(track.get("name", "")) == "move": animation_tracks[uid] = {"name": "idle", "elapsed": 0.0}

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var background := boss_background if _boss_present() else normal_background
	if background != null: draw_texture_rect(background, rect, false)
	else: draw_rect(rect, Color("101b35"))
	draw_rect(rect, Color(0.02, 0.04, 0.09, 0.16))
	if simulation == null:
		return
	for unit in simulation.state.party + simulation.state.enemies:
		_draw_unit(unit)
	for projectile in projectiles:
		var source := simulation.find_unit(projectile.source)
		var target := simulation.find_unit(projectile.target)
		if source.is_empty() or target.is_empty(): continue
		var duration := float(projectile.get("duration", .4))
		var t := clampf(float(projectile.age) / maxf(.01, duration), 0, 1)
		var source_position := _projectile_origin(source)
		var target_position := _projectile_target(target)
		var position := source_position.lerp(target_position, t) + Vector2(0, -24.0 * sin(t * PI))
		var source_id := str(projectile.get("source_id", ""))
		var texture := projectile_library.texture_at(source_id, float(projectile.age)) if projectile_pack_ready else null
		var attack_kind := str(projectile.get("attack_kind", "BASIC"))
		if attack_kind in ["NORMAL", "ULTIMATE"]:
			var trail_color := _skill_color(source, "ultimate" if attack_kind == "ULTIMATE" else "normal")
			trail_color.a = .82
			draw_line(source_position, position, trail_color.darkened(.20), 8.0 if attack_kind == "ULTIMATE" else 5.0, true)
			draw_line(source_position, position, Color(0.92, 1.0, 1.0, .88), 2.0 if attack_kind == "ULTIMATE" else 1.2, true)
		if texture != null:
			var projectile_size := projectile_library.runtime_size(source_id)
			if attack_kind == "ULTIMATE": projectile_size *= 1.24
			elif attack_kind == "NORMAL": projectile_size *= 1.10
			draw_texture_rect(texture, Rect2(position - projectile_size * .5, projectile_size), false)
		else:
			draw_circle(position, 8, Color("fff3a6") if source.team == "PLAYER" else Color("ff8c8c"))
	for presentation in vfx_presentations:
		var source := simulation.find_unit(str(presentation.source))
		var target := simulation.find_unit(str(presentation.get("target", "")))
		if source.is_empty(): continue
		var textures: Array = vfx_frames.get(str(presentation.key), [])
		var delay := float(presentation.get("delay", 0.0))
		if float(presentation.age) < delay: continue
		var progress := clampf((float(presentation.age) - delay) / maxf(0.01, float(presentation.duration)), 0.0, 0.999)
		var kind := str(presentation.get("kind", "basic"))
		var anchor_unit := target if kind.begins_with("impact_") or kind in ["heal", "shield"] else (target if not target.is_empty() else source)
		var position := _unit_pos(anchor_unit) + _entry_offset(anchor_unit) + Vector2(0, -82)
		if not textures.is_empty():
			var frame := mini(textures.size() - 1, int(floor(progress * textures.size())))
			var vfx_size := Vector2(150, 150)
			if kind == "normal": vfx_size = Vector2(190, 190)
			elif kind == "ultimate": vfx_size = Vector2(270, 270)
			draw_texture_rect(textures[frame], Rect2(position - vfx_size * 0.5, vfx_size), false)
		else:
			# Explicit visual fallback for characters whose authored PNG VFX packs
			# are still pending.  It preserves a legible multi-stage skill read; it
			# is not reported as a replacement for authored character VFX.
			_draw_runtime_skill_vfx(position, source, kind, progress)
	for callout in skill_callouts:
		var caster := simulation.find_unit(str(callout.source))
		if caster.is_empty(): continue
		var alpha := clampf(1.0 - float(callout.age) / maxf(.01, float(callout.duration)), 0.0, 1.0)
		var callout_position := _unit_pos(caster) + _entry_offset(caster) + Vector2(-30, -168 - float(callout.age) * 24.0)
		var callout_color: Color = callout.color
		callout_color.a = alpha
		draw_rect(Rect2(callout_position, Vector2(62, 24)), Color(0.03, 0.08, 0.15, alpha * .88), true)
		draw_rect(Rect2(callout_position, Vector2(62, 24)), callout_color, false, 1.5)
		draw_string(ThemeDB.fallback_font, callout_position + Vector2(8, 18), str(callout.label), HORIZONTAL_ALIGNMENT_CENTER, 46, 16, callout_color)
	for text in floating_texts:
		var target := simulation.find_unit(text.target)
		if target.is_empty(): continue
		var position := _unit_pos(target) + Vector2(-34, -125 - float(text.age) * 40)
		draw_string(ThemeDB.fallback_font, position, text.text, HORIZONTAL_ALIGNMENT_CENTER, 72, 24, text.color)

func _draw_runtime_skill_vfx(position: Vector2, source: Dictionary, kind: String, progress: float) -> void:
	var color := _skill_color(source, kind)
	var impact := sin(progress * PI)
	var ultimate := kind in ["ultimate", "impact_ultimate"]
	var fade := 1.0 - progress * .38
	if kind.begins_with("impact_"):
		# Endpoint: shock disk, starburst debris and a crisp white core. This is
		# delayed to the visible projectile arrival instead of being a caster ring.
		var impact_radius := (56.0 if ultimate else 38.0) * (0.55 + impact * .65)
		draw_circle(position, impact_radius, Color(color.r, color.g, color.b, .22 * fade))
		draw_arc(position, impact_radius, -progress * 2.6, TAU - progress * 2.6, 32, Color(color.r, color.g, color.b, .92 * fade), 4.0 if ultimate else 2.8, true)
		draw_arc(position, impact_radius * .56, progress * 4.1, TAU + progress * 4.1, 24, Color(1.0, .98, .84, .86 * fade), 2.0, true)
		var shards := 12 if ultimate else 8
		for index in range(shards):
			var angle := TAU * float(index) / float(shards) + progress * .55
			var origin := position + Vector2(cos(angle), sin(angle)) * impact_radius * .18
			var tip := position + Vector2(cos(angle), sin(angle)) * impact_radius * (1.08 + progress * .38)
			draw_line(origin, tip, Color(color.r, color.g, color.b, .86 * fade), 3.0 if ultimate else 2.0, true)
		draw_circle(position, 9.0 + impact * 10.0, Color(1.0, 1.0, 1.0, .90 * fade))
		return
	if kind == "heal":
		var heal_radius := 30.0 + impact * 24.0
		draw_circle(position, heal_radius, Color(.32, 1.0, .72, .16 * fade))
		draw_arc(position, heal_radius, -progress * TAU, TAU - progress * TAU, 28, Color(.48, 1.0, .76, .92 * fade), 3.2, true)
		draw_line(position + Vector2(-heal_radius * .38, 0), position + Vector2(heal_radius * .38, 0), Color(1, 1, 1, .94 * fade), 4.0, true)
		draw_line(position + Vector2(0, -heal_radius * .38), position + Vector2(0, heal_radius * .38), Color(1, 1, 1, .94 * fade), 4.0, true)
		return
	if kind == "shield":
		var shield_radius := 38.0 + impact * 22.0
		var hex := PackedVector2Array()
		for index in range(6):
			var angle := TAU * float(index) / 6.0 - PI / 2.0
			hex.append(position + Vector2(cos(angle), sin(angle)) * shield_radius)
		draw_colored_polygon(hex, Color(.25, .78, 1.0, .16 * fade))
		draw_polyline(hex + PackedVector2Array([hex[0]]), Color(.50, .90, 1.0, .96 * fade), 3.4, true)
		return
	# Cast phase: a role-coloured ground seal, rotating glyph and energy spikes.
	var radius := 42.0 + 34.0 * impact + (44.0 if ultimate else 0.0)
	var glow := Color(color.r, color.g, color.b, (.26 if ultimate else .19) * fade)
	var core := Color(color.r, color.g, color.b, .92 * fade)
	draw_circle(position + Vector2(0, 18), radius * .84, glow)
	draw_arc(position, radius, 0.0, TAU, 32, core, 4.4 if ultimate else 3.0, true)
	draw_arc(position, radius * .60, -progress * TAU * 1.6, TAU - progress * TAU * 1.6, 20, Color(.94, 1.0, 1.0, .80 * fade), 1.8, true)
	var spokes := 12 if ultimate else 8
	for index in range(spokes):
		var angle := TAU * float(index) / float(spokes) + progress * 1.7
		var inner := position + Vector2(cos(angle), sin(angle)) * radius * .24
		var outer := position + Vector2(cos(angle), sin(angle)) * radius * (1.04 + .18 * impact)
		draw_line(inner, outer, Color(color.r, color.g, color.b, .84 * fade), 3.2 if ultimate else 2.0, true)
	var diamond := PackedVector2Array([
		position + Vector2(0, -radius * .24), position + Vector2(radius * .24, 0),
		position + Vector2(0, radius * .24), position + Vector2(-radius * .24, 0),
	])
	draw_colored_polygon(diamond, Color(1.0, 1.0, 1.0, .82 * fade))

func _skill_color(source: Dictionary, kind: String) -> Color:
	var role := str(source.get("role", ""))
	var base := Color("70e7ff")
	match role:
		"GUARDIAN": base = Color("64dfc0")
		"VANGUARD": base = Color("ffb36a")
		"ASSAULT": base = Color("ff7f9d")
		"ARTILLERY": base = Color("8e9dff")
		"SPECIALIST": base = Color("c785ff")
		"MEDIC": base = Color("75f4be")
	if kind == "ultimate": return base.lightened(.22)
	return base

func _boss_present() -> bool:
	if simulation == null: return false
	for enemy in simulation.state.enemies:
		if str(enemy.get("rank", "")) == "BOSS" and UnitState.alive(enemy): return true
	return false

func _draw_unit(unit: Dictionary) -> void:
	var p := _unit_pos(unit)
	var player: bool = str(unit.team) == "PLAYER"
	var alive := UnitState.alive(unit)
	var color := _character_color(unit.slot) if player else _enemy_color(unit.rank)
	if not alive: color = color.darkened(.65)
	if unit_flash.has(unit.uid): color = Color.WHITE
	p += _entry_offset(unit)
	var generated_sprite := sprite_pack_ready and sprite_library.supports_character(str(unit.def_id))
	var bob := sin(Time.get_ticks_msec() / 180.0 + int(unit.slot)) * 3.0 if alive and not generated_sprite else 0.0
	p.y += bob
	# Generated CHR001 frames contain their own motion. Every remaining
	# code-native DEV placeholder receives the same event-driven directional
	# pose offset so all five allies and all enemies visibly animate.
	if not generated_sprite:
		p += _placeholder_pose_offset(unit)
	_draw_ellipse_polygon(p + Vector2(0, 12), Vector2(42, 12), Color(0, 0, 0, .35))
	if _draw_combat_sprite(unit, p, alive):
		pass
	elif player:
		_draw_player_sd(p, color, str(unit.role), alive)
	elif unit.rank == "BOSS":
		# Bosses deploy on the right and visibly face screen-left. The forward
		# sensor, jaw, and attack core all sit on the left side of the chassis.
		draw_circle(p + Vector2(8, -48), 62, color)
		draw_rect(Rect2(p + Vector2(-40, -35), Vector2(96, 70)), color.darkened(.15))
		var boss_jaw := PackedVector2Array([p + Vector2(-62, -67), p + Vector2(-28, -81), p + Vector2(-30, -45), p + Vector2(-66, -48)])
		draw_colored_polygon(boss_jaw, color.lightened(.08))
		draw_circle(p + Vector2(-29, -65), 9, Color("ffdf6b"))
		draw_circle(p + Vector2(-49, -57), 5, Color("ff7a70"))
	else:
		_draw_nonhuman_enemy(p, color, str(unit.role), alive)
	var bar_width := 96.0 if unit.rank != "BOSS" else 150.0
	var hp_ratio := UnitState.hp_ratio(unit)
	var head_position := _head_position(unit, p)
	var bar_origin := head_position + Vector2(-bar_width / 2.0, -18)
	draw_rect(Rect2(bar_origin, Vector2(bar_width, 9)), Color("351e2b"))
	draw_rect(Rect2(bar_origin, Vector2(bar_width * hp_ratio, 9)), Color("62e49b") if player else Color("ff6868"))
	if int(unit.shield) > 0:
		var shield_ratio := minf(1.0, float(unit.shield) / maxf(1.0, float(unit.max_hp)))
		draw_rect(Rect2(bar_origin + Vector2(0, 12), Vector2(bar_width * shield_ratio, 5)), Color("6ecfff"))
	var label: String = str(unit.def_id)
	draw_string(ThemeDB.fallback_font, p + Vector2(-55, 46), label, HORIZONTAL_ALIGNMENT_CENTER, 110, 16, Color("dbe9ff"))

func _draw_combat_sprite(unit: Dictionary, p: Vector2, alive: bool) -> bool:
	if not sprite_pack_ready or not sprite_library.supports_character(str(unit.def_id)):
		return false
	var track: Dictionary = animation_tracks.get(unit.uid, {"name": "idle", "elapsed": 0.0})
	var animation_name := "down" if not alive else str(track.get("name", "idle"))
	var character_id := str(unit.def_id)
	var texture := sprite_library.texture_at(character_id, animation_name, float(track.get("elapsed", 0.0)))
	if texture == null:
		return false
	var scale := 0.44 if str(unit.team) == "PLAYER" else 0.42
	var destination_size := Vector2(512.0, 512.0) * scale
	var top_left := p - Vector2(256.0 * scale, 512.0 * .88 * scale)
	var modulate := Color(1.0, .72, .72, 1.0) if unit_flash.has(unit.uid) else Color.WHITE
	draw_texture_rect(texture, Rect2(top_left, destination_size), false, modulate)
	return true

func _draw_player_sd(p: Vector2, color: Color, role: String, alive: bool) -> void:
	# Code-native DEV_PLACEHOLDER. The player silhouette is explicitly an adult
	# woman: four-head proportions, long legs/hair, mature waist/hip line, bare
	# shoulders and midriff, with opaque chest/groin coverage.
	var skin := Color("f3c2ad") if alive else Color("806960")
	var hair := color.darkened(.38)
	var suit := color.darkened(.08)
	var trim := color.lightened(.34)
	# Long hair and ponytail behind the body.
	draw_circle(p + Vector2(11, -86), 29, hair)
	draw_line(p + Vector2(24, -82), p + Vector2(38, -18), hair, 18.0, true)
	draw_circle(p + Vector2(40, -14), 10, hair)
	# Long legs and opaque thigh boots.
	draw_line(p + Vector2(-13, -25), p + Vector2(-15, 15), skin, 13.0, true)
	draw_line(p + Vector2(13, -25), p + Vector2(15, 15), skin, 13.0, true)
	draw_rect(Rect2(p + Vector2(-24, -8), Vector2(16, 31)), suit)
	draw_rect(Rect2(p + Vector2(8, -8), Vector2(16, 31)), suit)
	# Opaque high-cut hip armor, narrow exposed waist, opaque chest panel.
	var hips := PackedVector2Array([p + Vector2(-27, -34), p + Vector2(27, -34), p + Vector2(18, -10), p + Vector2(-18, -10)])
	draw_colored_polygon(hips, suit)
	draw_rect(Rect2(p + Vector2(-14, -49), Vector2(28, 17)), skin)
	var torso := PackedVector2Array([p + Vector2(-25, -74), p + Vector2(25, -74), p + Vector2(15, -49), p + Vector2(-15, -49)])
	draw_colored_polygon(torso, suit)
	draw_line(p + Vector2(-22, -68), p + Vector2(-31, -40), skin, 9.0, true)
	draw_line(p + Vector2(22, -68), p + Vector2(31, -40), skin, 9.0, true)
	draw_line(p + Vector2(-20, -71), p + Vector2(0, -54), trim, 3.0, true)
	draw_line(p + Vector2(20, -71), p + Vector2(0, -54), trim, 3.0, true)
	# Player units deploy left and look toward lower-right in a readable 3/4
	# view: the near/right eye is larger and the nose/chin project rightward.
	draw_circle(p + Vector2(4, -101), 27, hair)
	draw_circle(p + Vector2(5, -96), 22, skin)
	draw_circle(p + Vector2(1, -99), 2.3, Color("17243b"))
	draw_circle(p + Vector2(14, -97), 3.7, Color("17243b"))
	draw_line(p + Vector2(21, -94), p + Vector2(25, -91), skin.darkened(.28), 2.0, true)
	draw_line(p + Vector2(9, -86), p + Vector2(18, -88), Color("a65b67"), 2.0, true)
	draw_line(p + Vector2(-17, -112), p + Vector2(23, -117), hair.lightened(.18), 7.0, true)
	# Readable role prop at combat scale.
	if role == "GUARDIAN":
		# The shield is forward/right toward the enemy and overlaps the hand;
		# no detached or independently floating prop is permitted.
		draw_line(p + Vector2(20, -66), p + Vector2(35, -54), skin, 10.0, true)
		var shield := PackedVector2Array([p + Vector2(28, -79), p + Vector2(51, -87), p + Vector2(67, -70), p + Vector2(64, -23), p + Vector2(45, -7), p + Vector2(25, -29)])
		draw_colored_polygon(shield, Color("246f79"))
		draw_polyline(shield + PackedVector2Array([shield[0]]), Color("8de4d5"), 4.0, true)
		draw_circle(p + Vector2(34, -55), 5.0, Color("f3c2ad"))
	elif role == "MEDIC":
		draw_arc(p + Vector2(37, -50), 18, 0, TAU, 24, Color("8ff5df"), 5.0, true)
	elif role == "ARTILLERY":
		draw_rect(Rect2(p + Vector2(26, -59), Vector2(42, 10)), Color("d9e7ee"))
	elif role == "VANGUARD":
		draw_line(p + Vector2(27, -50), p + Vector2(55, -82), Color("f4d27c"), 7.0, true)
	elif role == "SPECIALIST":
		draw_arc(p + Vector2(0, -114), 34, PI, TAU, 20, trim, 4.0, true)

func _draw_nonhuman_enemy(p: Vector2, color: Color, role: String, alive: bool) -> void:
	# Genderless nonhuman machine silhouette. Enemies deploy right and face
	# screen-left: the snout, visor focus, weapon, and leading arm all point left.
	var metal := color if alive else color.darkened(.6)
	var body := PackedVector2Array([p + Vector2(-37, -56), p + Vector2(25, -61), p + Vector2(31, 17), p + Vector2(-25, 20)])
	draw_colored_polygon(body, metal.darkened(.12))
	var head := PackedVector2Array([p + Vector2(-48, -83), p + Vector2(-22, -105), p + Vector2(20, -99), p + Vector2(30, -72), p + Vector2(12, -61), p + Vector2(-29, -65)])
	draw_colored_polygon(head, metal)
	draw_rect(Rect2(p + Vector2(-38, -87), Vector2(31, 8)), Color("ff666f"))
	draw_circle(p + Vector2(-40, -83), 4.0, Color("ffd166"))
	draw_line(p + Vector2(-27, -37), p + Vector2(-55, -2), metal.lightened(.15), 12.0, true)
	draw_line(p + Vector2(22, -35), p + Vector2(45, 8), metal.lightened(.15), 11.0, true)
	if role in ["RANGED", "AREA", "DEBUFFER"]:
		draw_rect(Rect2(p + Vector2(-82, -51), Vector2(54, 13)), Color("aebed1"))
		draw_rect(Rect2(p + Vector2(-88, -48), Vector2(8, 7)), Color("ffad66"))

func _placeholder_pose_offset(unit: Dictionary) -> Vector2:
	var track: Dictionary = animation_tracks.get(unit.uid, {"name": "idle", "elapsed": 0.0})
	var animation_name := str(track.get("name", "idle"))
	var elapsed := float(track.get("elapsed", 0.0))
	var direction := 1.0 if str(unit.team) == "PLAYER" else -1.0
	var duration := sprite_library.duration(str(unit.get("def_id", "")), animation_name) if sprite_pack_ready else 0.75
	var progress := clampf(elapsed / maxf(duration, 0.01), 0.0, 1.0)
	var pulse := sin(progress * PI)
	match animation_name:
		"basic_attack":
			return Vector2(direction * 18.0 * pulse, -4.0 * pulse)
		"normal_skill":
			return Vector2(direction * 11.0 * pulse, -12.0 * pulse)
		"ultimate":
			return Vector2(direction * 27.0 * pulse, -16.0 * pulse)
		"hit":
			return Vector2(-direction * 13.0 * pulse, 2.0 * pulse)
		"victory":
			return Vector2(0.0, -10.0 * absf(sin(elapsed * PI * 3.0)))
		_:
			return Vector2.ZERO

func _draw_ellipse_polygon(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(24):
		var angle := TAU * i / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)

func _unit_pos(unit: Dictionary) -> Vector2:
	var slot := int(unit.slot)
	if str(unit.team) == "PLAYER":
		var player_columns := [0.14, 0.255, 0.37, 0.485, 0.60]
		var player_lanes := [0.68, 0.745, 0.785, 0.70, 0.755]
		return Vector2(size.x * float(player_columns[slot % player_columns.size()]), size.y * float(player_lanes[slot % player_lanes.size()]))
	var enemy_columns := [0.79, 0.91, 0.84]
	var enemy_column := float(enemy_columns[slot % enemy_columns.size()])
	var enemy_lane := 0.69 + (slot % 3) * 0.055
	return Vector2(size.x * enemy_column, size.y * enemy_lane)

func _projectile_origin(unit: Dictionary) -> Vector2:
	var foot := _unit_pos(unit) + _entry_offset(unit)
	if str(unit.team) == "PLAYER": return foot + Vector2(46, -82)
	return foot + Vector2(-46, -72)

func _projectile_target(unit: Dictionary) -> Vector2:
	var foot := _unit_pos(unit) + _entry_offset(unit)
	return foot + Vector2(0, -72)

func _entry_offset(unit: Dictionary) -> Vector2:
	var progress := clampf(float(entry_tracks.get(unit.uid, 1.0)), 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	var direction := -1.0 if str(unit.team) == "PLAYER" else 1.0
	return Vector2(direction * 150.0 * (1.0 - eased), -8.0 * sin(progress * PI))

func _head_position(unit: Dictionary, foot_position: Vector2) -> Vector2:
	var character_id := str(unit.get("def_id", ""))
	if sprite_pack_ready and sprite_library.supports_character(character_id):
		var anchor := sprite_library.head_anchor(character_id)
		var scale := 0.44 if str(unit.team) == "PLAYER" else 0.42
		return foot_position + Vector2((anchor.x - 0.5) * 512.0 * scale, -(0.88 - anchor.y) * 512.0 * scale)
	if str(unit.get("rank", "")) == "BOSS": return foot_position + Vector2(0, -158)
	return foot_position + Vector2(0, -128)

func _character_color(slot: int) -> Color:
	return [Color("5ed6c0"), Color("ff9b73"), Color("75a7ff"), Color("e788ff"), Color("ffd166")][slot % 5]

func _enemy_color(rank: String) -> Color:
	if rank == "BOSS": return Color("b54d67")
	if rank == "ELITE": return Color("a46bd4")
	return Color("6f7f98")
