from pathlib import Path
root = Path(__file__).resolve().parents[2]
p = root / 'godot/battle/view/battle_view.gd'
s = p.read_text(encoding='utf-8')
s = s.replace('func _ready() -> void:', '''# Damage and defeat commit on contact, using the same clock as the projectile.
const CONTACT_DELAY := .44
var contact_events: Array[Dictionary] = []
var engagement_positions: Dictionary = {}
var engagement_targets: Dictionary = {}
var opening_elapsed := 0.0
var combat_readout := ""
var combat_readout_left := 0.0
var contact_commits := 0

func _ready() -> void:''',1)
s = s.replace('simulation = value\n', 'simulation = value\n\tcontact_events.clear()\n\tengagement_positions.clear()\n\tengagement_targets.clear()\n\topening_elapsed = 0.0\n\tcontact_commits = 0\n\tcombat_readout = ""\n',1)
s = s.replace('func skip_to_result() -> bool:\n', 'func skip_to_result() -> bool:\n\tcontact_events.clear()\n',1)
s = s.replace('if not paused and not simulation.state.ended:\n', 'if not paused and not simulation.state.ended and opening_elapsed >= .85 and not presentation_director.is_active() and not _waiting_for_boss_contact():\n',1)
s = s.replace('\t\t\tsimulation.tick()\n', '\t\t\tsimulation.tick()\n\t\t\t_consume_events()\n',1)
s = s.replace('\t\t\t\treturn\n\tvar presentation_delta', '\t\t\t\treturn\n\t\t\tif presentation_director.is_active():\n\t\t\t\taccumulator = 0.0\n\t\t\t\tbreak\n\tvar presentation_delta',1)
s = s.replace('\t\t_advance_entries(actor_delta)\n', '\t\t_advance_entries(actor_delta)\n\t\topening_elapsed += actor_delta\n\t\t_advance_engagement(actor_delta)\n\t\t_advance_contacts(actor_delta)\n\t\tcombat_readout_left = maxf(0.0, combat_readout_left - presentation_delta)\n',1)
s = s.replace('if simulation.state.ended and not emitted_finish and not presentation_director.is_active()', 'if simulation.state.ended and contact_events.is_empty() and not emitted_finish and not presentation_director.is_active()',1)
s = s.replace('func _detect_boss_entrance() -> bool:\n', 'func _detect_boss_entrance() -> bool:\n\tif not contact_events.is_empty(): return false\n',1)
# Keep action dispatch, but delay its effects in a shared ordered contact queue.
start = s.index('\t\tif event.type == BattleEvent.DAMAGE:', s.index('func _consume_events()'))
end = s.index('\nfunc _supports_cinematic_ultimate', start)
dispatch = s[start:end]
dispatch = '\n'.join(line[1:] if line.startswith('\t') else line for line in dispatch.split('\n'))
dispatch = dispatch.replace('\t\t\tcontinue', '\t\t\treturn')
old = s.index('\t\t_apply_display_event(event)', s.index('func _consume_events()'))
s = s[:old] + '''\t\tpresented_cursor = consumed_events
\t\tprocessed_this_frame += 1
\t\tif event.type in [BattleEvent.DAMAGE, BattleEvent.HEAL, BattleEvent.SHIELD, BattleEvent.DOWN]:
\t\t\tcontact_events.append({"event": event.duplicate(true), "remaining": CONTACT_DELAY})
\t\t\tif event.type == BattleEvent.DAMAGE and str(event.get("extra", {}).get("source", "")) == "NORMAL":
\t\t\t\t_spawn_projectile(str(event.source), str(event.target), "NORMAL")
\t\telse:
\t\t\t_present_regular_event(event)

func _present_regular_event(event: Dictionary) -> void:
\t_apply_display_event(event)
''' + dispatch + s[end:]
s=s.replace('\t\tif event.type == BattleEvent.ULTIMATE and _supports_cinematic_ultimate(event):', '\t\tif event.type in [BattleEvent.ULTIMATE, BattleEvent.BATTLE_END] and not contact_events.is_empty(): break\n\t\tif event.type == BattleEvent.ULTIMATE and _supports_cinematic_ultimate(event):',1)
# The skill projectile is launched at the cue; contact effects never launch a second one.
a=s.index('\t\t\tvar damage_source :=', s.index('func _present_regular_event'))
b=s.index('\t\t\tvar damaged :=',a)
s=s[:a]+'''\t\t\t_spawn_vfx(str(event.source), str(event.target), "impact_basic")
'''+s[b:]
s=s.replace('\t\t_spawn_skill_callout(str(event.source), "SKILL",', '\t\t_spawn_skill_callout(str(event.source), _action_label(event),',1)
s=s.replace('\t\t_play_animation(str(event.target), "down")\n', '''\t\t_play_animation(str(event.target), "down")
\t\tcombat_readout = "%s → %s %s" % [unit_display_name(_actor_model(str(event.source))), unit_display_name(_actor_model(str(event.target))), "전투불능" if str(_actor_model(str(event.target)).get("team", "")) == "PLAYER" else "격파"]
\t\tcombat_readout_left = 2.2
''',1)
# Visual records outlive a simulation wave until their final impact has played.
s=s.replace('simulation.find_unit(', '_actor_model(')
s=s.replace('var duration := projectile_library.duration(source_id) if projectile_pack_ready else .32', 'if str(source.get("role", "")) in ActorChoreography.MELEE_ROLES: return\n\tvar duration := .30',1)
a=s.index('\t# Asset projectile loops stay fast',s.index('func _spawn_projectile'))
b=s.index('\tvar projectile: Dictionary',a)
s=s[:a]+'\tvar launch_delay := .14\n'+s[b:]
s=s.replace('\tfor unit in simulation.state.party + simulation.state.enemies:\n\t\tvisible_units.append(_presentation_unit(unit))', '''\tvar current_ids: Dictionary = {}
\tfor unit in simulation.state.party + simulation.state.enemies:
\t\tvisible_units.append(_presentation_unit(unit))
\t\tcurrent_ids[str(unit.uid)] = true
\tfor uid in presentation_actor_records:
\t\tif not current_ids.has(uid):
\t\t\tvar old_unit := _presentation_unit(presentation_actor_records[uid])
\t\t\tif UnitState.alive(old_unit): visible_units.append(old_unit)''',1)
s=s.replace('func _unit_pos(unit: Dictionary) -> Vector2:\n', 'func _unit_pos(unit: Dictionary) -> Vector2:\n\tvar uid := str(unit.get("uid", ""))\n\tif engagement_positions.has(uid): return _battlefield_point((engagement_positions[uid] as Vector2) * size)\n',1)
s=s.replace('\tanimation_tracks[uid] = {"name": animation_name', '\tif not target_uid.is_empty(): engagement_targets[uid] = target_uid\n\tanimation_tracks[uid] = {"name": animation_name',1)
# Draw a compact cause-of-defeat report away from head damage and bottom controls.
s=s.replace('\tvar arena_mix := _boss_background_mix()', '\tvar arena_mix := _boss_background_mix()',1)
s=s.replace('\tfor unit in visible_units: _draw_unit(unit)', '\tfor unit in visible_units: _draw_unit(unit)\n\t_draw_combat_readout()',1)
# Shift to battle contact positions before the first attack, then follow actual targets.
s += '''
func _actor_model(uid: String) -> Dictionary:
\tif simulation == null: return {}
\tvar live := simulation.find_unit(uid)
\treturn live if not live.is_empty() else presentation_actor_records.get(uid, {})

func _waiting_for_boss_contact() -> bool:
\treturn not contact_events.is_empty() and simulation.state.wave != boss_entry_wave and simulation.has_boss()

func _advance_contacts(delta: float) -> void:
\tfor item in contact_events: item.remaining = float(item.remaining) - delta
\twhile not contact_events.is_empty() and float(contact_events[0].remaining) <= 0.0:
\t\tvar item: Dictionary = contact_events.pop_front()
\t\t_present_regular_event(item.event)
\t\tcontact_commits += 1

func _action_label(event: Dictionary) -> String:
\tvar skill_id := str(event.get("extra", {}).get("skill_id", ""))
\tfor skill in simulation.data.get("skills", []):
\t\tif str(skill.get("id", "")) == skill_id:
\t\t\tvar key := str(skill.get("name_key", ""))
\t\t\tif not key.is_empty(): return Loc.t(key)
\treturn "집중 공격"

func _advance_engagement(delta: float) -> void:
\tif simulation == null: return
\tfor model in simulation.state.party + simulation.state.enemies:
\t\tvar unit := _presentation_unit(model)
\t\tvar uid := str(unit.uid)
\t\tvar player := str(unit.team) == "PLAYER"
\t\tvar base := Grounding.formation_point(Vector2.ONE, player, int(unit.slot), _boss_present())
\t\tif str(unit.get("rank", "")) == "BOSS": base = Vector2(.785, .83)
\t\tif not engagement_positions.has(uid): engagement_positions[uid] = base
\t\tif not UnitState.alive(unit): continue
\t\tvar goal := base
\t\tvar melee := str(unit.get("role", "")) in ActorChoreography.MELEE_ROLES
\t\tif player:
\t\t\tgoal.x = (.48 + float(int(unit.slot) % 2) * .055) if melee else (.22 + float(int(unit.slot) % 3) * .085)
\t\telif str(unit.get("rank", "")) != "BOSS":
\t\t\tgoal.x = (.64 + float(int(unit.slot) % 2) * .075) if melee else (.78 + float(int(unit.slot) % 2) * .095)
\t\tvar target := presentation_unit_for_uid(str(engagement_targets.get(uid, "")))
\t\tif melee and not target.is_empty() and UnitState.alive(target) and str(target.team) != str(unit.team):
\t\t\tvar target_position: Vector2 = engagement_positions.get(str(target.uid), Grounding.formation_point(Vector2.ONE, not player, int(target.slot), false))
\t\t\tgoal.x = clampf(target_position.x + (-.13 if player else .13), .40 if player else .59, .60 if player else .82)
\t\t\tgoal.y = clampf(target_position.y + (-.045 if int(unit.slot) % 2 else .025), .72, .86)
\t\tvar current: Vector2 = engagement_positions[uid]
\t\tvar moving := current.distance_to(goal) > .012
\t\tengagement_positions[uid] = current.move_toward(goal, delta * (.46 if melee else .24))
\t\tvar track: Dictionary = animation_tracks.get(uid, {})
\t\tif str(track.get("name", "idle")) in ["idle", "move"]:
\t\t\ttrack.name = "move" if moving else "idle"
\t\t\tanimation_tracks[uid] = track

func _draw_combat_readout() -> void:
\tif combat_readout_left <= 0.0 or combat_readout.is_empty() or scene_transition_active(): return
\tvar font := battle_font if battle_font != null else ThemeDB.fallback_font
\tvar box := Rect2(Vector2(size.x * .28, size.y * .135), Vector2(size.x * .44, 36))
\tdraw_style_box(_combat_readout_style(), box)
\tdraw_string(font, box.position + Vector2(10, 25), combat_readout, HORIZONTAL_ALIGNMENT_CENTER, box.size.x - 20, 20, Color("f6e5bd"))

func _combat_readout_style() -> StyleBoxFlat:
\tvar style := StyleBoxFlat.new()
\tstyle.bg_color = Color(.025, .055, .085, .9)
\tstyle.set_corner_radius_all(8)
\treturn style
'''
p.write_text(s,encoding='utf-8')
print('Patched contact timing and engagement movement')
