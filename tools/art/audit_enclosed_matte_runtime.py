"""Verify actual packed frames keep repaired alpha, not just a preview image."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
GODOT=ROOT/'godot'
def read(path): return json.loads(path.read_text(encoding='utf-8'))
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
checks=[]
for entity,seeds in {'CHR002':[(182,229)],'CHR004':[(175,72),(154,116),(115,142),(90,178),(188,161)]}.items():
    source=GODOT/'assets/generated_import/enclosed_matte_repair/r1'/entity
    base=Image.open(source/'runtime_rgba.png').convert('RGBA')
    checks.append({'entity':entity,'check':'every user-reported enclosed matte seed is fully transparent','pass':all(base.getpixel(seed)[3]==0 for seed in seeds)})
    source_manifest=read(source/'animation_manifest.json')
    folder=GODOT/'assets/runtime_web/full_density/r2'/entity
    manifest=read(folder/'animation_manifest.json')
    pages=[Image.open(folder/page['atlas_path']).convert('RGBA') for page in manifest['atlas_pages']]
    max_error=0
    count=0
    for action,spec in manifest['animations'].items():
        for index,frame_index in enumerate(spec['frame_indices']):
            record=manifest['packed_frames'][frame_index]
            x,y,w,h=record['region']
            actual=Image.new('RGBA',(256,256))
            actual.paste(pages[record['page']].crop((x,y,x+w,y+h)),tuple(record['margin'][:2]))
            expected=Image.open(source/source_manifest['animations'][action]['frame_paths'][index]).convert('RGBA').resize((256,256),Image.Resampling.LANCZOS)
            error=int(np.abs(np.asarray(actual.getchannel('A')).astype(int)-np.asarray(expected.getchannel('A')).astype(int)).max())
            max_error=max(max_error,error);count+=1
    checks.append({'entity':entity,'check':'packed all-action runtime alpha equals repaired source alpha','frames':count,'maximum_alpha_difference':max_error,'pass':max_error==0})
    signature=read(GODOT/'assets/runtime_web/combat_signature/r16'/entity/'signature_manifest.json')
    provenance=read(ROOT/signature['chroma_key_provenance']['derivative_manifest'])
    valid=all(sha(ROOT/r['green_master_path'])==r['green_master_sha256'] and sha(ROOT/r['keyed_rgba_path'])==r['keyed_rgba_sha256'] for r in provenance['records'])
    checks.append({'entity':entity,'check':'every signature frame keeps hash-verified green master and keyed RGBA','frames':len(provenance['records']),'pass':valid})
data=read(GODOT/'data/compiled/game_data.json')
actors=read(GODOT/'assets/runtime_web/full_density/r2/index.json')['actors']
largest=sorted((id for id in actors if id.startswith('CHR')),key=lambda id:actors[id]['decoded_rgba_bytes'],reverse=True)[:5]
budgets=[{'stage':s['id'],'bytes':sum(actors[id]['decoded_rgba_bytes'] for id in set(largest+s['waves'][0]+sum(s['waves'][1:],[])))} for s in data['stages']]
checks.append({'check':'all 500 authored stages fit HD actor budget even with the five largest party assets','stages':len(budgets),'worst':max(budgets,key=lambda b:b['bytes']),'budget_bytes':144*1024*1024,'pass':all(b['bytes']<=144*1024*1024 for b in budgets)})
output=ROOT/'reports/gameplay_qa/20260907_ENCLOSED_MATTE_RUNTIME_AUDIT.json'
output.write_text(json.dumps({'checks':checks,'no_model_used':True,'no_deployment':True,'no_deletion':True},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(checks,ensure_ascii=True))
raise SystemExit(0 if all(c['pass'] for c in checks) else 1)
