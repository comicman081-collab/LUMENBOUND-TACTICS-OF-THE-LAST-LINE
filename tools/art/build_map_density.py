"""Map-only 192px idle/move/victory sheets from verified 256px actor pages."""
import argparse
import math
from pathlib import Path
from PIL import Image
from build_full_density_runtime import GODOT, ROOT, read, sha, save_json

def build_map_actor(entity, approval, source, destination, baseline_root=None):
    """Build one new map pack; callers can stage reviewed replacements safely."""
    folder=source/entity
    manifest=read(folder/'animation_manifest.json')
    assert sha(folder/'animation_manifest.json')==approval['manifest_sha256']
    pages=[]
    for page in manifest['atlas_pages']:
        assert sha(folder/page['atlas_path'])==page['atlas_sha256']
        pages.append(Image.open(folder/page['atlas_path']).convert('RGBA'))
    frames=[];animations={}
    for action in ['idle','move','victory']:
        spec=manifest['animations'][action]
        indices=[]
        for index in spec['frame_indices']:
            record=manifest['packed_frames'][index]
            x,y,w,h=record['region']
            frame=Image.new('RGBA',(256,256))
            frame.paste(pages[record['page']].crop((x,y,x+w,y+h)),tuple(record['margin'][:2]))
            indices.append(len(frames));frames.append(frame.resize((192,192),Image.Resampling.LANCZOS))
        animations[action]={**spec,'frame_indices':indices}
    atlas=Image.new('RGBA',(8*192,math.ceil(len(frames)/8)*192))
    for index,frame in enumerate(frames): atlas.paste(frame,((index%8)*192,(index//8)*192))
    target=destination/entity;target.mkdir(parents=True)
    atlas.save(target/'atlas.png',compress_level=6)
    baseline=read((baseline_root or GODOT/'assets/runtime_web/combat')/entity/'animation_manifest.json')
    output={key:manifest[key] for key in ['character_id','source_asset_id','foot_anchor','head_anchor','view','facing_policy']}
    output.update(status='LOCAL_QA_ONLY_MAP_DENSITY',frame_size=[192,192],atlas_columns=8,atlas_path='atlas.png',atlas_sha256=sha(target/'atlas.png'),animations=animations,map_pixel_scale=baseline['frame_size'][1]/192,decoded_rgba_bytes=atlas.width*atlas.height*4,source_manifest_sha256=approval['manifest_sha256'])
    save_json(target/'animation_manifest.json',output)
    return {'manifest_sha256':sha(target/'animation_manifest.json'),'decoded_rgba_bytes':output['decoded_rgba_bytes'],'png_bytes':(target/'atlas.png').stat().st_size}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=GODOT/'assets/runtime_web/full_density/r2')
    parser.add_argument('--destination',type=Path,default=GODOT/'assets/runtime_web/map_density/r1')
    parser.add_argument('--entities',default='')
    args=parser.parse_args()
    source=args.source.resolve();destination=args.destination.resolve()
    if not source.is_relative_to(ROOT.resolve()) or not destination.is_relative_to(ROOT.resolve()):
        raise ValueError('MAP_DENSITY_PATH_OUTSIDE_PROJECT')
    if destination.exists():raise ValueError('IMMUTABLE_MAP_DENSITY_EXISTS')
    wanted=set(args.entities.split(',')) if args.entities else None
    actors=read(source/'index.json')['actors']
    if wanted is not None and not wanted.issubset(actors):raise ValueError('MAP_DENSITY_ENTITY_MISSING')
    records={entity:build_map_actor(entity,approval,source,destination) for entity,approval in actors.items() if wanted is None or entity in wanted}
    save_json(destination/'index.json',{'status':'LOCAL_QA_ONLY','actors':records})
    save_json(ROOT/'work/map_density'/destination.name/'build_summary.json',{'actors':len(records),'no_source_mutation':True,'no_model_used':True,'records':records})
    print('MAP_DENSITY_READY actors=%d PNG_MiB=%.2f'%(len(records),sum(v['png_bytes'] for v in records.values())/1048576))


if __name__=='__main__':main()
