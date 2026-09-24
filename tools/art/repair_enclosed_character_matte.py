"""Repair user-identified enclosed white matte, retaining the exact costume.

Hand-reviewed seed regions on the immutable 512px authority are the selection
authority. This is not a global white-colour key: skin, eyes, silver armour and
weapon highlights outside those connected regions are protected byte-for-byte.
All animation keys derive from the one repaired base, never independent edits.
"""
from __future__ import annotations
import argparse
from collections import deque
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter, ImageDraw
from build_full_density_runtime import ROOT, GODOT, module, read, sha, save_json

rig=module('existing_combat_rig',ROOT/'tools/local_art_pipeline/build_combat_animation_pack.py')
keyer=module('existing_character_keyer',ROOT/'tools/art/build_battle_signature_pack.py')

SEEDS={
    'CHR004':[(175,72),(154,116),(115,142),(90,178),(188,161)],
    'CHR002':[(182,229)],
}
ROOTS={
    'CHR004':GODOT/'assets/generated_import/characters/sd_chr004_eda_combat_r27_dev',
    'CHR002':GODOT/'assets/generated_import/characters/sd_chr002_roan_combat_r27_dev',
}

def enclosed_mask(image, seeds):
    pixels=np.asarray(image).astype(np.int16)
    rgb=pixels[:,:,:3]
    candidate=(rgb.min(axis=2)>=185)&((rgb.max(axis=2)-rgb.min(axis=2))<=65)&(pixels[:,:,3]>0)
    mask=np.zeros(candidate.shape,dtype=np.uint8)
    components=[]
    for sx,sy in seeds:
        if not candidate[sy,sx]: raise ValueError(f'SEED_IS_NOT_WHITE_MATTE:{sx},{sy}:{pixels[sy,sx]}')
        queue=deque([(sx,sy)])
        component=[]
        while queue:
            x,y=queue.popleft()
            if x<0 or y<0 or y>=mask.shape[0] or x>=mask.shape[1] or mask[y,x] or not candidate[y,x]: continue
            mask[y,x]=255; component.append((x,y))
            queue.extend(((x-1,y),(x+1,y),(x,y-1),(x,y+1)))
        if component: components.append({'seed':[sx,sy],'pixels':len(component),'bounds':[min(p[0] for p in component),min(p[1] for p in component),max(p[0] for p in component)+1,max(p[1] for p in component)+1]})
    if not components or any(c['pixels']>4500 for c in components): raise ValueError(f'MASK_REQUIRES_REVIEW:{components}')
    return Image.fromarray(mask),components

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--entity',choices=SEEDS,required=True)
    parser.add_argument('--revision',required=True)
    args=parser.parse_args()
    source=ROOTS[args.entity]
    out=ROOT/'work/enclosed_matte_repair'/args.revision/args.entity
    if out.exists(): raise ValueError('IMMUTABLE_CANDIDATE_EXISTS')
    out.mkdir(parents=True)
    base=Image.open(source/'combat_base_512.png').convert('RGBA')
    mask,components=enclosed_mask(base,SEEDS[args.entity])
    mask.save(out/'approved_region_mask.png')
    # A one-pixel feather replaces the white-mixed antialias boundary. Only
    # the reviewed component and its immediate rim can change alpha.
    halo=mask.filter(ImageFilter.MaxFilter(3))
    values=np.array(base)
    hard=np.asarray(mask)>0
    edge=(np.asarray(halo)>0)&~hard
    values[hard]=0
    old=np.asarray(base).astype(np.float32)
    for y,x in zip(*np.where(edge)):
        minimum=float(old[y,x,:3].min())
        if minimum<95: continue  # the authored dark ink contour is preserved
        retain=min(1.0,max(0.0,(255-minimum)/160.0))
        if retain>.995: continue
        values[y,x,3]=round(float(old[y,x,3])*retain)
        if retain>0.001: values[y,x,:3]=np.clip((old[y,x,:3]-255*(1-retain))/retain,0,255).astype(np.uint8)
        else: values[y,x]=0
    repaired=Image.fromarray(values)
    master=keyer.flat_chroma_master(repaired)
    master.save(out/'green_master.png')
    repaired,key_qc=keyer.key_chroma_master(master,repaired)
    repaired.save(out/'runtime_rgba.png')
    # Unambiguous single-background QA with a labelled hole overlay and a
    # separate actual-game-background composite, never an unlabeled cream tile.
    check=Image.new('RGBA',(1024,512),(25,47,62,255))
    check.alpha_composite(base,(0,0));check.alpha_composite(repaired,(512,0))
    d=ImageDraw.Draw(check);d.text((12,478),'BEFORE - REJECTED: white hair/arm holes',fill='white');d.text((524,478),'AFTER - alpha holes reveal same blue background',fill='white')
    check.save(out/'before_after_blue.png')
    bg=Image.open(GODOT/'assets/art/backgrounds/BG_BATTLE_GLASS_RAIL/bg_battle_glass_rail_1920x1080.png').convert('RGBA').resize((910,512))
    bg.alpha_composite(repaired,(199,0));bg.save(out/'actual_game_background.png')
    original_manifest=read(source/'animation_manifest.json')
    manifest={**original_manifest,'status':'LOCAL_QA_ONLY_ENCLOSED_MATTE_REPAIR','source':(out/'runtime_rgba.png').relative_to(ROOT).as_posix(),'source_sha256':sha(out/'runtime_rgba.png'),'animations':{}}
    for name,spec in original_manifest['animations'].items():
        frames=[]
        for index in range(len(spec['frame_paths'])):
            frame=rig.render_frame(repaired,name,index,len(spec['frame_paths']),original_manifest['role'],'PLAYER')
            path=out/name/f'{name}_{index:03}.png'
            path.parent.mkdir(parents=True,exist_ok=True);frame.save(path)
            frames.append(path.relative_to(out).as_posix())
        manifest['animations'][name]={**spec,'frame_paths':frames,'sheets':[]}
    save_json(out/'animation_manifest.json',manifest)
    save_json(out/'repair_manifest.json',{'status':'LOCAL_QA_ONLY_PENDING_VISUAL_REVIEW','entity':args.entity,'source':(source/'combat_base_512.png').relative_to(ROOT).as_posix(),'source_sha256':sha(source/'combat_base_512.png'),'mask_sha256':sha(out/'approved_region_mask.png'),'regions':components,'green_master_sha256':sha(out/'green_master.png'),'rgba_sha256':sha(out/'runtime_rgba.png'),'key_qc':key_qc,'no_model_used':True,'no_costume_change':True,'no_source_mutation':True})
    print(out)

if __name__=='__main__': main()
