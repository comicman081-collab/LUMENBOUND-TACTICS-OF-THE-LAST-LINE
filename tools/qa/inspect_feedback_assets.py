from pathlib import Path
import json, struct
root = Path(__file__).resolve().parents[2]
for name in ['R11/CH01_MAP_KIT_R11.glb','R19/environment_polish.glb','NaturalEnvR2/kit/environment.glb']:
    path = root / 'godot/assets/art/chapter_map' / name
    with path.open('rb') as f:
        f.read(12); length, kind = struct.unpack('<II', f.read(8)); data=json.loads(f.read(length))
    print(name, [n.get('name') for n in data.get('nodes',[])][:90])
