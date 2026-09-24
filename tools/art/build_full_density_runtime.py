"""Immutable local-QA all-action atlas bridge; never enlarges a compact atlas.

Retains all timing keys and identity from the current runtime's actual source.
Packed RGBA margins reconstruct the original canvas at draw time. Originals,
old candidates and installed models are never modified. No generative model.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / 'godot'
CELL = 256

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

legacy = module('compact_bridge', ROOT / 'tools/web/build_runtime_combat_packs.py')
packing = module('signature_bridge', ROOT / 'tools/art/build_battle_signature_pack.py')

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def source_path(raw):
    # The compact bridge records authoring roots in either project or res scope.
    result = (GODOT if raw.startswith('assets/') else ROOT) / raw
    result = result.resolve()
    if not result.is_relative_to(ROOT.resolve()): raise ValueError('SOURCE_OUTSIDE_PROJECT')
    return result

def build_actor(entity, destination, qa, baseline_root=None):
    current = read((baseline_root or GODOT / 'assets/runtime_web/combat') / entity / 'animation_manifest.json')
    source = source_path(current['source_root'])
    source_manifest = read(source / 'animation_manifest.json') if source.is_dir() else None
    base = None if source_manifest else legacy._static_base_canvas(source)
    animations, unique, digest_to_index, provenance = {}, [], {}, []
    preview = Image.new('RGB', (4*268, 2*294), '#182531')
    painter = ImageDraw.Draw(preview)
    for animation_index, (name, definition) in enumerate(current['animations'].items()):
        indices = []
        originals = source_manifest['animations'].get(name, {}).get('frame_paths', []) if source_manifest else []
        count = len(definition['frame_indices'])
        if source_manifest and len(originals) != count: raise ValueError(f'{entity}:{name}:TIMING_MISMATCH')
        for index in range(count):
            original_path = source / originals[index] if source_manifest else source
            original = Image.open(original_path).convert('RGBA') if source_manifest else legacy._static_frame(base, 'hit' if name == 'stun' else name, index, count)
            if min(original.size) < 512: raise ValueError(f'{entity}:SOURCE_DENSITY_TOO_LOW:{original.size}')
            if original.getchannel('A').getextrema() != (0,255): raise ValueError(f'{entity}:{name}:SOURCE_ALPHA_INVALID')
            item = {'path':original_path.relative_to(ROOT).as_posix(), 'sha256':sha(original_path)}
            # Reuse the established conservative fringe repair for every state,
            # not just the four high-impact states in the older signature slice.
            if entity in ('CHR002','CHR004','ENM001') and current.get('source_status') != 'SPRITEGEN_ROSTER_VISUAL_PASS':
                matte = packing.flat_chroma_master(original)
                original, key_qc = packing.key_chroma_master(matte, original)
                master_path = qa / entity / 'green_master' / name / f'{index:03}.png'
                keyed_path = qa / entity / 'keyed_rgba' / name / f'{index:03}.png'
                master_path.parent.mkdir(parents=True, exist_ok=True)
                keyed_path.parent.mkdir(parents=True, exist_ok=True)
                matte.save(master_path)
                original.save(keyed_path)
                item.update(green_master=master_path.relative_to(ROOT).as_posix(), green_master_sha256=sha(master_path), keyed_rgba=keyed_path.relative_to(ROOT).as_posix(), keyed_sha256=sha(keyed_path), key_qc=key_qc)
            frame = original.resize((CELL,CELL), Image.Resampling.LANCZOS)
            bounds = frame.getchannel('A').getbbox()
            if not bounds: raise ValueError(f'{entity}:{name}:EMPTY_FRAME')
            left,top,right,bottom = bounds
            left,top,right,bottom = max(0,left-3),max(0,top-3),min(CELL,right+3),min(CELL,bottom+3)
            digest = hashlib.sha256(frame.tobytes()).hexdigest()
            if digest not in digest_to_index:
                digest_to_index[digest] = len(unique)
                unique.append({'image':frame.crop((left,top,right,bottom)), 'logical_rect':[left,top,right-left,bottom-top]})
            indices.append(digest_to_index[digest])
            provenance.append({'animation':name,'frame':index,**item})
            if index == count//2 and animation_index < 8:
                x,y = (animation_index%4)*268,(animation_index//4)*294
                preview.paste('#eee9e0' if animation_index%2 else '#182531',(x,y,x+256,y+256))
                preview.paste(frame,(x,y),frame)
                painter.text((x+4,y+263),f'{entity} {name}',fill='#ffffff')
        animations[name] = {**definition,'frame_indices':indices}
    destination.mkdir(parents=True, exist_ok=False)
    records, pages = [None]*len(unique), []
    offset = 0
    while offset < len(unique):
        count = min(40,len(unique)-offset)
        while True:
            try:
                positions,size = packing._choose_packing(unique[offset:offset+count])
                break
            except RuntimeError:
                count -= 1
                if count < 1: raise
        atlas = Image.new('RGBA',size)
        for local_index, position in enumerate(positions):
            item = unique[offset+local_index]
            atlas.alpha_composite(item['image'],position)
            rect = item['logical_rect']
            records[offset+local_index] = {'page':len(pages),'region':[*position,*item['image'].size], 'margin':[rect[0],rect[1],CELL-rect[2],CELL-rect[3]]}
        path = destination / f'page_{len(pages):02}.png'
        atlas.save(path, compress_level=6)
        pages.append({'atlas_path':path.name,'atlas_sha256':sha(path),'size':list(size),'rgba_bytes':size[0]*size[1]*4})
        offset += count
    manifest = {**current,'status':'LOCAL_QA_ONLY_FULL_DENSITY','frame_size':[CELL,CELL], 'atlas_path':'','atlas_pages':pages,'packed_frames':records,'animations':animations,
        'source_manifest_sha256':sha(source/'animation_manifest.json') if source_manifest else sha(source),
        'density_provenance':'512px_or_larger_original_to_256px; compact_atlas_never_used',
        'identity_change':False,'costume_change':False,'decoded_rgba_bytes':sum(p['rgba_bytes'] for p in pages)}
    manifest_path = destination / 'animation_manifest.json'
    save_json(manifest_path,manifest)
    save_json(qa/entity/'source_provenance.json',{'no_source_mutation':True,'no_model_used':True,'records':provenance})
    preview.save(qa/entity/'actions_light_dark.png')
    return {'manifest_sha256':sha(manifest_path),'decoded_rgba_bytes':manifest['decoded_rgba_bytes'],'frames':sum(len(x['frame_indices']) for x in animations.values()),'unique_frames':len(unique),'source':current['source_root']}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--revision',required=True)
    parser.add_argument('--entities',default='')
    args=parser.parse_args()
    destination=GODOT/'assets/runtime_web/full_density'/args.revision
    qa=ROOT/'work/full_density'/args.revision
    if destination.exists() or qa.exists(): raise ValueError('IMMUTABLE_REVISION_ALREADY_EXISTS')
    qa.mkdir(parents=True)
    entities=args.entities.split(',') if args.entities else sorted(p.name for p in (GODOT/'assets/runtime_web/combat').iterdir() if p.is_dir())
    results={}
    for entity in entities:
        results[entity]=build_actor(entity,destination/entity,qa)
        print(json.dumps({'entity':entity,**results[entity]}),flush=True)
    save_json(destination/'index.json',{'status':'LOCAL_QA_ONLY','revision':args.revision,'no_source_mutation':True,'actors':results})
    save_json(qa/'build_summary.json',{'entities':len(results),'frames':sum(v['frames'] for v in results.values()),'actors':results})

if __name__=='__main__': main()
