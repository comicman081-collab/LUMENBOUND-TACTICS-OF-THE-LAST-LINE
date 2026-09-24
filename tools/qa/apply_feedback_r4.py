from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def rewrite(relative, old, new, count=1):
    path = ROOT / relative
    source = path.read_text(encoding='utf-8-sig')
    assert source.count(old) >= count, (relative, old[:100])
    path.write_text(source.replace(old, new, count), encoding='utf-8')

mapfile = 'godot/chapter_map/runtime/chapter_map_screen.gd'
rewrite(mapfile, 'func _start_patrol_contact(node_id: String, return_coord: Vector2i, movement_refilled := false) -> void:', 'func _start_patrol_contact(node_id: String, return_coord: Vector2i, movement_refilled := false) -> bool:')
p = ROOT / mapfile
s = p.read_text(encoding='utf-8')
a, b = s.index('func _start_patrol_contact('), s.index('\nfunc _emit_battle_request_after_map_callback')
block = s[a:b].replace(': return\n', ': return false\n').replace('\n\t\t\treturn\n', '\n\t\t\treturn false\n')
block += '\n\t\treturn true\n\treturn false\n'
s = s[:a]+block+s[b:]
s = s.replace('if not contacts.is_empty():\n\t\t\t_start_patrol_contact(str(contacts[0]), prior_coord)\n\t\t\treturn', 'for contact_id in contacts:\n\t\t\tif _start_patrol_contact(str(contact_id), prior_coord):\n\t\t\t\treturn')
s = s.replace('if not update.get("contacts", []).is_empty():\n\t\tturn_transitioning = false\n\t\t_start_patrol_contact(str(update.contacts[0]), party_coord, true)\n\t\treturn', 'for contact_id in update.get("contacts", []):\n\t\tturn_transitioning = false\n\t\tif _start_patrol_contact(str(contact_id), party_coord, true):\n\t\t\treturn')
s = s.replace('_start_patrol_contact(node_id, return_coord)\n\treturn "TRANSITION"', 'return "TRANSITION" if _start_patrol_contact(node_id, return_coord) else "STAY"')
# Visible enemy bodies must not inherit screen label visibility or remain visible
# when a label's early-continue skipped the corresponding root update.
s = s.replace('\t\tif not button.visible: continue\n', '\t\tvar visible_enemy: Node3D = enemy_pawns.get(node_id)\n\t\tif is_instance_valid(visible_enemy):\n\t\t\tvisible_enemy.visible = button.visible and not _node_encounter_cleared(node)\n\t\tif not button.visible: continue\n', 1)
# The cached map can return from battle with newly unlocked stages. Reconcile
# missing roots even when terrain preload was completed on its original visit.
s = s.replace('not OS.has_feature("web") or web_stage_entry_preload_complete or web_enemy_stream_active', 'not OS.has_feature("web") or web_enemy_stream_active')
p.write_text(s, encoding='utf-8')

rewrite('godot/chapter_map/model/macro_world_generator.gd', '\texpanded["patrols"] = _complete_mobile_patrols', '\t_add_forward_patrols(expanded)\n\texpanded["patrols"] = _complete_mobile_patrols')
