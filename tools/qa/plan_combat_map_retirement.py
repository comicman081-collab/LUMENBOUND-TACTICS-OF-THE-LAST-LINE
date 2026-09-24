"""Retire only redundant non-media output after the September 13 local QA gates."""
from pathlib import Path
import hashlib,json,os
ROOT=Path(__file__).resolve().parents[2]
REPORT=ROOT/'reports/combat_map_upgrade_20260913'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def files(root):
    for parent,dirs,names in os.walk(root,followlinks=False):
        dirs[:]=[d for d in dirs if not (Path(parent)/d).is_junction() and not (Path(parent)/d).is_symlink()]
        for name in names:
            p=Path(parent)/name
            if not p.is_symlink():yield p
for name in ['model.json','browser_verified/acceptance.json','pursuit_verified/acceptance.json','boss_final/acceptance.json','release_final/acceptance.json']:
    checks=read(REPORT/name)['checks']
    assert checks and all(c.get('pass',c.get('ok',False)) for c in checks),name
for log,summary in [('regression_final.log','TEST_SUMMARY total=256 pass=256 fail=0'),('map_final.log','MAP_TEST_SUMMARY total=354 pass=354 fail=0'),('chapter_flow.log','CHAPTER_BOSS_FLOW checks=153 failures=0'),('model_final.log','ENCOUNTER_COMBAT_UPGRADE checks=143 failures=0')]:
    assert summary in (REPORT/log).read_text(encoding='utf-8-sig'),log
media={'.wav','.ogg','.oga','.mp3','.flac','.m4a','.aac','.opus','.mid','.midi','.mp4','.webm','.ogv','.avi','.mov','.mkv'}
protected=set()
for name,key,field in [('music_preservation.json','files','path'),('intro_preservation.json','protected_videos','path'),('audio_source_preservation.json','records','retained')]:
    protected.update((ROOT/r[field]).resolve() for r in read(ROOT/'reports/storage_cleanup_20260911'/name)[key])
roots=['builds/web_chapter_boss_flow_final_20260912_release','builds/web_combat_map_20260913_development','builds/web_combat_map_20260913_release','builds/web_combat_map_final_20260913_development','godot/.godot','godot/.runtime_profile']
rows=[];retained=[]
for rel in roots:
    root=ROOT/rel
    assert root.resolve().is_relative_to(ROOT) and not root.is_junction() and not root.is_symlink()
    if not root.exists():continue
    for p in files(root):
        assert p.resolve().is_relative_to(root.resolve())
        relative=p.relative_to(ROOT).as_posix()
        if p.suffix.lower() in media or p.resolve() in protected:retained.append(relative)
        else:rows.append({'path':relative,'bytes':p.stat().st_size,'sha256':sha(p)})
result={'status':'VERIFIED_REPLACEMENT_READY_FOR_REDUNDANT_OUTPUT_RETIREMENT','retained_build':'web_combat_map_final_20260913_release','roots':roots,'files':rows,'retirement_bytes':sum(r['bytes'] for r in rows),'protected_media_retained':retained,'project_bytes_before':sum(p.stat().st_size for p in files(ROOT))}
(REPORT/'retirement_manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('RETIREMENT_READY',len(rows),'files',result['retirement_bytes'],'bytes')
