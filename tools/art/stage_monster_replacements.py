"""Stage reviewed original monsters for all three game texture consumers.

--approve records an explicit visual review of the named, hash-bound candidates.
This tool stages packs only; runtime installation is a separate guarded step.
"""
from pathlib import Path
import argparse
import json
import shutil
from build_full_density_runtime import ROOT,GODOT,read,sha,save_json,legacy,build_actor
from build_map_density import build_map_actor

RUN=ROOT/'work/enemy_replacement_20260911'
REPORT=ROOT/'reports/enemy_replacement_20260911'
AUTHORITY=ROOT/'data_source/art_source/enemy_replacements_20260911'
STAGED=RUN/'staged'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--approve',default='')
    parser.add_argument('--build',action='store_true')
    args=parser.parse_args()
    approval_path=REPORT/'visual_review.json'
    approvals=read(approval_path) if approval_path.exists() else {'status':'PARTIAL_VISUAL_REVIEW','reviewer':'Codex visual inspection of actual generated creature images on alternating light/dark backgrounds','assets':{}}
    if args.approve:
        technical={r['entity_id']:r for r in read(REPORT/'candidate_technical_review.json')['assets']}
        for entity in args.approve.split(','):
            row=technical[entity]
            assert row['technical_status']=='PASS' and sha(ROOT/row['path'])==row['sha256']
            approvals['assets'][entity]={'source_sha256':row['sha256'],'source':row['path'],'review':'PASS','criteria':['Distinct detailed nonhuman SD creature; no polygon placeholder','Complete visible limbs, weapon tips and body','Readable at map/battle sprite size','Transparent exterior and enclosed openings; no visible background plate','No corpse; explosion-only runtime contract']}
        approvals['status']='ALL_52_VISUAL_REVIEW_PASS' if len(approvals['assets'])==52 else 'PARTIAL_VISUAL_REVIEW'
        save_json(approval_path,approvals)
        print('VISUALLY_REVIEWED',len(approvals['assets']),flush=True)
    if not args.build:return
    descriptions={r['id']:r for r in read(REPORT/'missing_monster_audit.json')['entities']}
    manifest=[]
    for entity,row in sorted(approvals['assets'].items()):
        source=ROOT/row['source']
        assert row['review']=='PASS' and sha(source)==row['source_sha256']
        target=AUTHORITY/entity
        target.mkdir(parents=True,exist_ok=True)
        for name in ['source.png','green_master.png','normalization.json']:
            before=source.parent/name;after=target/name
            if after.exists():assert sha(before)==sha(after)
            else:shutil.copy2(before,after)
        manifest.append({'entity_id':entity,'name':descriptions[entity]['name_key'],'file':f'{entity}/source.png','sha256':sha(target/'source.png'),'green_master':f'{entity}/green_master.png','green_master_sha256':sha(target/'green_master.png'),'review':'PASS','creation_method':'Codex_GPT_imagegen_via_Sprite_Gen_2.1.0_plus_canonical_green_cutout_and_existing_presentation_motion','license':'USER_AUTHORIZED_ORIGINAL_GPT_GENERATION','review_evidence':approval_path.relative_to(ROOT).as_posix()})
    save_json(AUTHORITY/'manifest.json',{'status':'LOCAL_VISUAL_REVIEW_PASS','count':len(manifest),'scope':'Individually reviewed replacement creature originals; runtime checks are separate','assets':manifest})
    definitions=legacy.reviewed_enemy_sources()
    legacy.COMBAT_OUTPUT=STAGED/'combat'
    records=read(STAGED/'build_summary.json')['actors'] if (STAGED/'build_summary.json').exists() else {}
    for entity,definition in definitions.items():
        if entity in records:
            assert sha(STAGED/'full_density'/entity/'animation_manifest.json')==records[entity]['hd']['manifest_sha256']
            continue
        compact=legacy.build_static_combat_pack(entity,definition)
        hd=build_actor(entity,STAGED/'full_density'/entity,RUN/'runtime_review',baseline_root=STAGED/'combat')
        map_pack=build_map_actor(entity,hd,STAGED/'full_density',STAGED/'map_density',baseline_root=STAGED/'combat')
        records[entity]={'compact':compact,'hd':hd,'map':map_pack}
        save_json(STAGED/'build_summary.json',{'status':'STAGED_RUNTIME_VERIFICATION_REQUIRED','actors':records})
        print('ALL_THREE_PACKS_STAGED',entity,hd['decoded_rgba_bytes'],flush=True)
    for family,index_key in [('full_density','hd'),('map_density','map')]:
        save_json(STAGED/family/'index.json',{'status':'LOCAL_QA_ONLY','actors':{entity:record[index_key] for entity,record in records.items()}})


if __name__=='__main__':main()
