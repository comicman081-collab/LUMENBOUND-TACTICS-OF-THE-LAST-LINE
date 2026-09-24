"""Verify monster identity, every atlas frame, and all authored encounter budgets."""
from pathlib import Path
import argparse
from PIL import Image
from build_full_density_runtime import ROOT,GODOT,read,sha,save_json

REPORT=ROOT/'reports/enemy_replacement_20260911'
RUNTIME=GODOT/'assets/runtime_web'


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--installed',action='store_true');parser.add_argument('--run-name',default='enemy_replacement_20260911');args=parser.parse_args()
    report=(ROOT/'reports'/args.run_name).resolve()
    assert report.is_relative_to((ROOT/'reports').resolve())
    scope='installed' if args.installed else 'staged'
    staging=ROOT/'work'/args.run_name/'staged'
    roots={'combat':RUNTIME/'combat','hd':RUNTIME/'full_density/r2','map':RUNTIME/'map_density/r1'} if args.installed else {'combat':staging/'combat','hd':staging/'full_density','map':staging/'map_density'}
    review=read(report/'visual_review.json')
    roster=args.run_name=='existing_roster_spritegen_20260911'
    assert review['status']==('ALL_21_VISUAL_REVIEW_PASS' if roster else 'ALL_52_VISUAL_REVIEW_PASS')
    expected={row['entity_id'] for row in read(ROOT/'work'/args.run_name/'reference_inventory.json')['assets']} if roster else {row['id'] for row in read(report/'missing_monster_audit.json')['entities']}
    original_contracts={r['entity_id']:r for r in read(ROOT/'data_source/art_source/roster_replacements_20260911/manifest.json')['assets']} if roster else {}
    assert set(review['assets'])==expected
    indices={kind:read(roots[kind]/'index.json')['actors'] for kind in ['hd','map']}
    checks=[]
    def check(ok,name):
        checks.append({'pass':bool(ok),'name':name})
        if not ok:raise ValueError(name)
    for entity in sorted(expected):
        compact=read(roots['combat']/entity/'animation_manifest.json')
        hd=read(roots['hd']/entity/'animation_manifest.json')
        map_pack=read(roots['map']/entity/'animation_manifest.json')
        check(compact['source_status']==('SPRITEGEN_ROSTER_VISUAL_PASS' if roster else 'ILLUSTRATED_MONSTER_VISUAL_PASS'),entity+' reviewed illustration selected')
        if roster:
            for action,spec in original_contracts[entity]['animation_contract'].items():
                check(len(spec['frame_indices'])==len(compact['animations'][action]['frame_indices']) and spec['fps']==compact['animations'][action]['fps'] and spec['loop']==compact['animations'][action]['loop'],entity+' original '+action+' timing retained')
        check(sha(ROOT/compact['source_root'])==review['assets'][entity]['source_sha256'],entity+' original identity hash')
        check(compact['source_asset_id']==hd['source_asset_id']==map_pack['source_asset_id'],entity+' identical source in all three consumers')
        for kind,manifest in [('hd',hd),('map',map_pack)]:
            check(sha(roots[kind]/entity/'animation_manifest.json')==indices[kind][entity]['manifest_sha256'],entity+' '+kind+' manifest binding')
        check(sha(roots['combat']/entity/'atlas.png')==compact['sha256'],entity+' compact hash')
        check(sha(roots['map']/entity/'atlas.png')==map_pack['atlas_sha256'],entity+' map hash')
        pages=[]
        for page in hd['atlas_pages']:
            path=roots['hd']/entity/page['atlas_path']
            check(sha(path)==page['atlas_sha256'],entity+' HD page hash '+page['atlas_path'])
            image=Image.open(path).convert('RGBA')
            check(list(image.size)==page['size'],entity+' HD page dimensions')
            pages.append(image)
        for record in hd['packed_frames']:
            p=pages[record['page']];x,y,w,h=record['region'];mx,my,mw,mh=record['margin']
            check(0<=x<x+w<=p.width and 0<=y<y+h<=p.height and w+mw==256 and h+mh==256 and 0<=mx<=mw and 0<=my<=mh,entity+' packed frame geometry')
            check(p.crop((x,y,x+w,y+h)).getchannel('A').getbbox() is not None,entity+' nonempty frame')
        for action, spec in compact['animations'].items():
            other=hd['animations'][action]
            check(len(spec['frame_indices'])==len(other['frame_indices']) and spec['fps']==other['fps'],entity+' '+action+' timing')
            check(all(0<=i<len(hd['packed_frames']) for i in other['frame_indices']),entity+' '+action+' indices')
        check(map_pack['frame_size']==[192,192] and hd['frame_size']==[256,256],entity+' map and battle density')
    all_actors=read(RUNTIME/'full_density/r2/index.json')['actors']
    all_actors.update(indices['hd'])
    data=read(GODOT/'data/compiled/game_data.json')
    party=sum(all_actors[f'CHR{i:03}']['decoded_rgba_bytes'] for i in range(1,6))
    largest_five=sum(sorted((v['decoded_rgba_bytes'] for k,v in all_actors.items() if k.startswith('CHR')),reverse=True)[:5])
    stages=[]
    for stage in data['stages']:
        enemies={e for wave in stage['waves'] for e in wave}
        size=sum(all_actors[e]['decoded_rgba_bytes'] for e in enemies)
        stages.append({'stage':stage['id'],'default_party_bytes':party+size,'largest_five_party_bytes':largest_five+size})
    check(all(s['largest_five_party_bytes']<=144*1024*1024 for s in stages),'all authored encounters including largest five characters fit 144MiB')
    worst=max(stages,key=lambda s:s['default_party_bytes'])
    save_json(report/f'{scope}_runtime_verification.json',{'status':'PASS','entities':len(expected),'checks_passed':len(checks),'stage_count':len(stages),'worst_default_party':worst,'largest_five_party_peak_bytes':max(s['largest_five_party_bytes'] for s in stages),'checks':checks})
    print(scope,'PASS',len(checks),'checks',len(stages),'stages',worst)


if __name__=='__main__':main()
