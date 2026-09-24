"""Record superseded non-audio exports after the encounter fix passes its gates."""
from pathlib import Path
import hashlib
import json
import os
ROOT=Path(__file__).resolve().parents[2]
REPORT=ROOT/'reports/encounter_contact_fix_20260911'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):
    with p.open('rb') as s:return hashlib.file_digest(s,'sha256').hexdigest()
def files(root):
    for parent,dirs,names in os.walk(root,followlinks=False):
        dirs[:]=[d for d in dirs if not (Path(parent)/d).is_junction() and not (Path(parent)/d).is_symlink()]
        for n in names:
            p=Path(parent)/n
            if not p.is_symlink():yield p
for name in ['encounter_matrix.json','browser_v2/acceptance.json','release_boot/acceptance.json']:
    data=read(REPORT/name)
    assert all(c.get('pass',c.get('ok',False)) for c in data['checks']),name
assert 'TEST_SUMMARY total=301 pass=301 fail=0' in (REPORT/'regression.log').read_text(encoding='utf-8-sig')
assert not read(REPORT/'rejection_after.json')['stranded']
protected=set()
for name,key,field in [('music_preservation.json','files','path'),('intro_preservation.json','protected_videos','path'),('audio_source_preservation.json','records','retained')]:
    protected.update((ROOT/r[field]).resolve() for r in read(ROOT/'reports/storage_cleanup_20260911'/name)[key])
media={'.wav','.ogg','.oga','.mp3','.flac','.m4a','.aac','.opus','.mid','.midi','.mp4','.webm','.ogv','.avi','.mov','.mkv'}
roots=['builds/web_roster21_damage_restart_20260911_release',
       'builds/web_contact_repro_20260911_development','builds/web_contact_repro_20260911_release',
       'builds/web_encounter_recovery_20260911_development','godot/.godot','godot/.runtime_profile']
rows=[];retained=[]
for rel in roots:
    root=ROOT/rel
    assert root.resolve().is_relative_to(ROOT) and not root.is_junction() and not root.is_symlink()
    if not root.exists():continue
    for p in files(root):
        assert p.resolve().is_relative_to(root.resolve())
        if p.suffix.lower() in media or p.resolve() in protected:
            retained.append(p.relative_to(ROOT).as_posix());continue
        rows.append({'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
result={'status':'VERIFIED_REPLACEMENT_READY_FOR_REDUNDANT_OUTPUT_RETIREMENT',
        'retained_build':'web_encounter_recovery_20260911_release','roots':roots,
        'retirement_bytes':sum(r['bytes'] for r in rows),'files':rows,'protected_media_retained':retained,
        'project_bytes_before':sum(p.stat().st_size for p in files(ROOT))}
(REPORT/'retirement_manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
print('RETIREMENT_READY',len(rows),'files',result['retirement_bytes'],'bytes',flush=True)
