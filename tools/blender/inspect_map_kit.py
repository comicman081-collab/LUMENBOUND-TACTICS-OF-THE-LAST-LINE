"""Read-only inspection of the project's existing Blender environment kit."""
import bpy
import json
import sys
from pathlib import Path

source, output = (Path(value).resolve() for value in sys.argv[sys.argv.index('--') + 1:])
output.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))
inventory = []
for obj in bpy.data.objects:
    if obj.type != 'MESH':
        continue
    inventory.append({'name': obj.name, 'vertices': len(obj.data.vertices),
                      'dimensions': list(obj.dimensions),
                      'materials': [slot.name for slot in obj.material_slots]})
(output / 'kit_inventory.json').write_text(json.dumps({'source': str(source), 'blender': bpy.app.version_string, 'meshes': inventory}, indent=2), encoding='utf-8')
print('READ_ONLY_MAP_KIT_INSPECTION', len(inventory), 'meshes', sum(item['vertices'] for item in inventory), 'vertices')
