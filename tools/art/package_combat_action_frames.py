"""Pack reviewed canonical curated PNGs, preserving a shared anatomical scale.

Raw component bounds are read using Sprite Gen's own extractor only to invert
its per-cell fit. Pixels are sourced exclusively from canonical curated exports.
No model output is cut into equal cells and no missing artwork is reconstructed.
"""
from pathlib import Path
import json, hashlib, argparse
import numpy as np
from PIL import Image, ImageDraw
from sprite_gen.frames.extract import remove_chroma_background_ycbcr, extract_component_images
from build_battle_contact_anchors import contacts

ROOT=Path(__file__).resolve().parents[2]
RUN=ROOT/'work/combat_motion_20260913/r2'
OUT=ROOT/'work/combat_motion_20260913/packed_candidate'

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf8'))

def bounds(image):
    a=np.asarray(image.getchannel('A'));ys,xs=np.where(a>=96)
    if not len(xs):raise ValueError('empty alpha')
    return int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--ids',default='');args=ap.parse_args()
    inventory=read(RUN/'inventory.json');records={x['id']:x for x in inventory['entities']}
    ids=args.ids.split(',') if args.ids else list(records)
    OUT.mkdir(parents=True,exist_ok=True)
    approvals=read(OUT/'index.json') if (OUT/'index.json').exists() else {'status':'CANDIDATE_REVIEW_REQUIRED','actors':{}}
    for entity in ids:
        folder=RUN/entity
        revised=RUN.parent/'r3'/entity
        if (revised/'curated').exists():folder=revised
        fm=read(folder/'frames/frames-manifest.json')
        assert fm['ok'],entity
        rows={x['state']:x for x in fm['rows']};poses={};raw_sizes={}
        for state,row in rows.items():
            raw=Image.open(folder/'raw'/f'{state}.png').convert('RGBA')
            keyed=remove_chroma_background_ycbcr(raw,(0,255,0))
            if isinstance(keyed,tuple):keyed=keyed[0]
            components=extract_component_images(keyed,3)
            assert components and len(components)==3
            curated=sorted((folder/'curated').glob(state+'-*.png'))
            assert len(curated)==3,(entity,state,curated)
            poses[state]=[Image.open(p).convert('RGBA') for p in curated]
            raw_sizes[state]=[bounds(im) for im in components]
        base=poses['basic_attack_prepare'][0]
        # Keep the current actor's ready-pose silhouette scale. The extended
        # sword/cannon may occupy extra logical canvas space without shrinking
        # its owner's head and torso in that individual frame.
        old=read(ROOT/f'godot/assets/runtime_web/combat/{entity}/animation_manifest.json')
        oldimage=Image.open(ROOT/f'godot/assets/runtime_web/combat/{entity}/atlas.png').convert('RGBA')
        cell=old['frame_size'][0];oldimage=oldimage.crop((0,0,cell,cell));ob=bounds(oldimage)
        ready_height=(ob[3]-ob[1])*256/cell
        packed=[];states={}
        for action in ['basic_attack','normal_skill','ultimate']:
            if action+'_prepare' not in poses:continue
            states[action]=[]
            for phase in ['prepare','release']:
                key=action+'_'+phase
                anchor_index=0 if phase=='prepare' else 2
                raw_anchor=raw_sizes[key][anchor_index]
                factor=ready_height/(raw_anchor[3]-raw_anchor[1])
                for n,source in enumerate(poses[key]):
                    box=bounds(source);rawbox=raw_sizes[key][n]
                    target_height=max(1,round((rawbox[3]-rawbox[1])*factor))
                    art=source.crop(box)
                    target_width=max(1,round(art.width*target_height/art.height))
                    art=art.resize((target_width,target_height),Image.Resampling.LANCZOS)
                    alpha=np.asarray(art.getchannel('A'));ys,xs=np.where(alpha>=96);bottom=int(ys.max())
                    foot_x=float(np.median(xs[ys>=bottom-3]));left=128-foot_x;top=225-(bottom+1)
                    # Quantile ignores a raised thin weapon when locating the head.
                    head_y=float(np.quantile(ys,.12));head_x=float(np.median(xs[ys<=head_y]))
                    meta={'logical_rect':[round(left,4),round(top,4),art.width,art.height], 'contacts':contacts(art,[left,top],[256,256]), 'head':[(left+head_x)/256,(top+head_y)/256], 'source':str((folder/'curated').relative_to(ROOT)), 'frame':n}
                    states[action].append(meta);packed.append((art,meta))
        width=1024;x=y=rowh=0
        for art,meta in packed:
            assert art.width<width-4
            if x+art.width+4>width:x=0;y+=rowh+4;rowh=0
            meta['rect']=[x,y,art.width,art.height];x+=art.width+4;rowh=max(rowh,art.height)
        height=y+rowh+2;page=Image.new('RGBA',(width,height))
        for art,meta in packed:page.alpha_composite(art,tuple(meta['rect'][:2]))
        dest=OUT/entity;dest.mkdir(exist_ok=True);page.save(dest/'atlas.png')
        manifest={'id':entity,'source_sha256':records[entity]['sha256'],'method':'Sprite Gen GPT split action rows → canonical component extraction → curated export → uniform pose-scale atlas','states':states}
        (dest/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
        approvals['actors'][entity]={'manifest_sha256':digest(dest/'manifest.json'),'atlas_sha256':digest(dest/'atlas.png'),'decoded_bytes':width*height*4}
        # This preview uses the actual logical sizes and grounded placement that
        # BattleView will draw, with room for overhead weapons.
        for action,sequence in states.items():
            sheet=Image.new('RGB',(512*6,430),'#12232f');draw=ImageDraw.Draw(sheet)
            frames=[]
            for n,meta in enumerate(sequence):
                xx,yy,w,h=meta['rect'];art=page.crop((xx,yy,xx+w,yy+h));lr=meta['logical_rect']
                pane=Image.new('RGBA',(512,430),(18,35,47,255));pane.alpha_composite(art,(round(128+lr[0]),round(140+lr[1])))
                sheet.paste(pane.convert('RGB'),(n*512,0));draw.text((n*512+8,8),f'{entity} {action} {n}',fill='white');frames.append(pane)
            sheet.save(dest/f'{action}_review.jpg')
            frames[0].save(dest/f'{action}.gif',save_all=True,append_images=frames[1:],duration=125,loop=0,disposal=2)
        print(entity,len(packed),width*height*4,flush=True)
    (OUT/'index.json').write_text(json.dumps(approvals,indent=2),encoding='utf8')

if __name__=='__main__':main()
