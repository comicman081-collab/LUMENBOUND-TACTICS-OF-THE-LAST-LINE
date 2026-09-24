"""Read-only alpha analysis of actual runtime frames; no image/model edits."""
import hashlib
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'godot/assets/runtime_web'
OUT=ROOT/'godot/data/battle_contact_anchors_r1.json'
REPORT=ROOT/'reports/gameplay_qa/20260907_contact_anchor_analysis.json'

def read(p): return json.loads(p.read_text(encoding='utf8'))
def contacts(image,offset,canvas):
    alpha=np.asarray(image.getchannel('A'))
    ys,xs=np.where(alpha>=96)
    if not len(xs): raise ValueError('Empty contact silhouette')
    bottom=int(ys.max())
    result=[]
    # Lower-silhouette samples keep at least one opaque contact on the ground
    # after rotation. They are not a newly inferred skeleton or joint model.
    for low,high in zip(np.linspace(0,image.width,9)[:-1],np.linspace(0,image.width,9)[1:]):
        chosen=(xs>=low)&(xs<high)&(ys>=bottom-max(8,image.height*.18))
        if not chosen.any(): continue
        y=int(ys[chosen].max())
        x=float(np.median(xs[chosen&(ys>=y-1)]))
        result.append([round((x+offset[0]+.5)/canvas[0],7),round((y+offset[1]+1)/canvas[1],7)])
    return result

def main():
    global OUT,REPORT
    parser=argparse.ArgumentParser();parser.add_argument('--revision',default='r1');args=parser.parse_args()
    if not args.revision.replace('_','').isalnum(): raise ValueError('Invalid revision')
    if args.revision!='r1':
        OUT=ROOT/f'godot/data/battle_contact_anchors_{args.revision}.json'
        REPORT=ROOT/f'reports/existing_roster_spritegen_20260911/contact_anchors_{args.revision}.json'
    if OUT.exists() or REPORT.exists(): raise ValueError('Use a new revision; preserve old analysis')
    result={'schema':1,'alpha_threshold':96,'packs':{}}
    evidence=[];total=0
    for kind,folder in [('compact',ART/'combat'),('full',ART/'full_density/r2'),('signature',ART/'combat_signature/r16')]:
        result['packs'][kind]={}
        for source in sorted(folder.glob('*/'+('signature_manifest.json' if kind=='signature' else 'animation_manifest.json'))):
            manifest=read(source);entity=manifest['character_id'];animations={}
            evidence.append({'path':str(source.relative_to(ROOT)),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
            pages={}
            def page(name):
                if name not in pages: pages[name]=Image.open(source.parent/name).convert('RGBA')
                return pages[name]
            for action,definition in manifest['animations'].items():
                frames=[]
                if kind=='signature':
                    for frame in definition['frames']:
                        x,y,w,h=frame['region']
                        frames.append(contacts(page(definition['atlas_path']).crop((x,y,x+w,y+h)),frame['logical_rect'][:2],definition['logical_frame_size']))
                else:
                    for index in definition['frame_indices']:
                        canvas=manifest['frame_size']
                        if kind=='full':
                            frame=manifest['packed_frames'][index];x,y,w,h=frame['region']
                            name=manifest['atlas_pages'][frame['page']]['atlas_path'];offset=frame['margin'][:2]
                        else:
                            w,h=canvas;columns=manifest['atlas_columns']
                            x,y=index%columns*w,index//columns*h;name=manifest['atlas_path'];offset=[0,0]
                        frames.append(contacts(page(name).crop((x,y,x+w,y+h)),offset,canvas))
                total+=len(frames)
                animations[action]={'fps':definition['fps'],'loop':definition.get('loop',False),'frames':frames}
            result['packs'][kind][entity]=animations
    OUT.write_text(json.dumps(result,separators=(',',':'))+'\n',encoding='utf8')
    report={'status':'READ_ONLY_ALPHA_ANALYSIS','frames':total,'entities':{k:len(v) for k,v in result['packs'].items()},
            'output':str(OUT.relative_to(ROOT)),'sha256':hashlib.sha256(OUT.read_bytes()).hexdigest(),'sources':evidence,
            'image_edits':False,'model_used':False,'method':'Eight lower silhouette bins per frame; exact local atlas alpha, no skeleton inference.'}
    REPORT.write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
    print(json.dumps({k:v for k,v in report.items() if k!='sources'}))
if __name__=='__main__': main()
