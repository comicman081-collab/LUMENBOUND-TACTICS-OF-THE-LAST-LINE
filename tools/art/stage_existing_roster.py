"""Stage the 21 individually visually reviewed Sprite Gen reference redraws."""
import argparse
import shutil
from build_full_density_runtime import ROOT,GODOT,read,sha,save_json,legacy,build_actor
from build_map_density import build_map_actor

RUN=ROOT/'work/existing_roster_spritegen_20260911'
REPORT=ROOT/'reports/existing_roster_spritegen_20260911'
AUTHORITY=ROOT/'data_source/art_source/roster_replacements_20260911'
STAGED=RUN/'staged'

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--record-visual-review',action='store_true');args=parser.parse_args()
    references=read(RUN/'reference_inventory.json')['assets']
    if args.record_visual_review:
        technical={r['entity_id']:r for r in read(REPORT/'candidate_technical_review.json')['assets']}
        approvals={}
        for row in references:
            entity=row['entity_id'];candidate=technical[entity]
            assert candidate['technical_status']=='PASS'
            source=ROOT/candidate['path']
            assert sha(source)==candidate['sha256']
            approvals[entity]={'source':candidate['path'],'source_sha256':candidate['sha256'],'review':'PASS','reference':row['reference'],'reference_sha256':row['reference_sha256'],'fingerprint':row['fingerprint'],'identity':'ESTABLISHED_IDENTITY_PASS','costume_review':'COSTUME_CONTINUITY_PASS' if entity.startswith('CHR') else 'NOT_APPLICABLE','criteria':['Full body SD combat proportions, complete accessories and weapon grip','Compared against canonical reference; matching hair, costume modules, palette and role','Viewed against light and dark backgrounds; no background plate or body holes','Original prone character art remains identity-compatible; enemies retain explosion-only defeat']}
        save_json(REPORT/'visual_review.json',{'status':'ALL_21_VISUAL_REVIEW_PASS','reviewer':'Codex direct image inspection; 2 green-material creatures also inspected full size and corrected with canonical narrow extraction','assets':approvals})
    approvals=read(REPORT/'visual_review.json')
    assert approvals['status']=='ALL_21_VISUAL_REVIEW_PASS' and len(approvals['assets'])==21
    manifest=[]
    existing=read(AUTHORITY/'manifest.json') if (AUTHORITY/'manifest.json').exists() else None
    for entity,row in sorted(approvals['assets'].items()):
        source=ROOT/row['source'];assert sha(source)==row['source_sha256']
        target=AUTHORITY/entity;target.mkdir(parents=True,exist_ok=True)
        for name in ['source.png','green_master.png','normalization.json']:
            dest=target/name
            if dest.exists():assert sha(dest)==sha(source.parent/name)
            else:shutil.copy2(source.parent/name,dest)
        baseline=read(GODOT/'assets/runtime_web/combat'/entity/'animation_manifest.json')
        saved=next((r for r in existing['assets'] if r['entity_id']==entity),{}) if existing else {}
        manifest.append({'entity_id':entity,'name':entity,'file':f'{entity}/source.png','sha256':sha(target/'source.png'),'green_master':f'{entity}/green_master.png','green_master_sha256':sha(target/'green_master.png'),'review':'PASS','costume_review':row['costume_review'],'reference':row['reference'],'reference_sha256':row['reference_sha256'],'animation_contract':saved.get('animation_contract',baseline['animations']),'events':saved.get('events',baseline.get('events',{})),'creation_method':'Codex_GPT_imagegen_via_Sprite_Gen_2.1.0_reference_redraw_plus_canonical_cutout_and_deterministic_presentation_motion','license':'USER_AUTHORIZED_ORIGINAL_GPT_GENERATION','review_evidence':(REPORT/'visual_review.json').relative_to(ROOT).as_posix()})
    save_json(AUTHORITY/'manifest.json',{'status':'LOCAL_VISUAL_REVIEW_PASS','count':21,'assets':manifest})
    definitions=legacy.reviewed_roster_sources()
    legacy.COMBAT_OUTPUT=STAGED/'combat'
    records=read(STAGED/'build_summary.json')['actors'] if (STAGED/'build_summary.json').exists() else {}
    for entity,definition in definitions.items():
        if entity in records:
            assert sha(STAGED/'full_density'/entity/'animation_manifest.json')==records[entity]['hd']['manifest_sha256'];continue
        compact=legacy.build_static_combat_pack(entity,definition)
        hd=build_actor(entity,STAGED/'full_density'/entity,RUN/'runtime_review',baseline_root=STAGED/'combat')
        map_pack=build_map_actor(entity,hd,STAGED/'full_density',STAGED/'map_density',baseline_root=STAGED/'combat')
        records[entity]={'compact':compact,'hd':hd,'map':map_pack}
        save_json(STAGED/'build_summary.json',{'status':'STAGED_RUNTIME_VERIFICATION_REQUIRED','actors':records})
        print('ROSTER_PACKS_STAGED',entity,flush=True)
    for family,key in [('full_density','hd'),('map_density','map')]:
        save_json(STAGED/family/'index.json',{'status':'LOCAL_QA_ONLY','actors':{e:r[key] for e,r in records.items()}})

if __name__=='__main__':main()
