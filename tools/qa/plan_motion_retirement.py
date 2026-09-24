"""Inventory redundant output; keep media, source art and quarantine intact."""
from pathlib import Path
import hashlib,json,os,re,zipfile
ROOT=Path(__file__).resolve().parents[2]
REPORT=ROOT/'reports/combat_motion_20260913'
KEEP=ROOT/'builds/web_combat_motion_scout_final_20260913_release'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def files(root):
    for parent,dirs,names in os.walk(root,followlinks=False):
        dirs[:]=[d for d in dirs if not (Path(parent)/d).is_junction() and not (Path(parent)/d).is_symlink()]
        for name in names:
            p=Path(parent)/name
            if not p.is_symlink():yield p
for name in ['scout_identity.json','scout_browser_final/acceptance.json','release_scout/acceptance.json','chapter_scout/acceptance.json','frames_verified/acceptance.json','live_final/acceptance.json','small_verified/acceptance.json']:
    checks=read(REPORT/name)['checks']
    assert checks and all(c.get('pass',c.get('ok',False)) for c in checks),name
for log,summary in [('map_regression_final.log','MAP_TEST_SUMMARY total=357 pass=357 fail=0'),('regression_verified.log','TEST_SUMMARY total=301 pass=301 fail=0')]:
    text=(REPORT/log).read_text(encoding='utf-8-sig')
    assert summary in text and 'SCRIPT ERROR:' not in text,log
version=read(KEEP/'VERSION.json')
assert sha(KEEP/(version['runtime_artifact_base']+'.pck'))==version['pck_sha256']
media={'.wav','.ogg','.oga','.mp3','.flac','.m4a','.aac','.opus','.mid','.midi','.mp4','.webm','.ogv','.avi','.mov','.mkv'}
protected=set()
for name,key,field in [('music_preservation.json','files','path'),('intro_preservation.json','protected_videos','path'),('audio_source_preservation.json','records','retained')]:
    protected.update((ROOT/r[field]).resolve() for r in read(ROOT/'reports/storage_cleanup_20260911'/name)[key])
roots=['builds/web_combat_map_final_20260913_release','godot/.godot','godot/.runtime_profile']
roots += [p.relative_to(ROOT).as_posix() for p in (ROOT/'builds').glob('web_combat_motion_*') if p.is_dir() and p!=KEEP]
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
# High-frequency QA state dumps are retained losslessly in one verified archive.
archive=REPORT/'qa_poll_records.zip'
assert not archive.exists(),'Never overwrite an evidence archive'
polls=[p for p in files(ROOT/'reports') if p.suffix=='.json' and (re.fullmatch(r'state_\d+\.json',p.name) or p.name=='gameplay_report.json')]
poll_rows=[]
with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=8) as z:
    for p in sorted(polls):
        payload=p.read_bytes();relative=p.relative_to(ROOT).as_posix()
        row={'path':relative,'bytes':len(payload),'sha256':hashlib.sha256(payload).hexdigest()}
        poll_rows.append(row);z.writestr(relative,payload)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for row in poll_rows:assert hashlib.sha256(z.read(row['path'])).hexdigest()==row['sha256']
index={'archive':archive.relative_to(ROOT).as_posix(),'sha256':sha(archive),'files':poll_rows,'restoration':'Extract entries under the project root. Original polling JSON is losslessly preserved; screenshots, acceptance and video remain loose.'}
(REPORT/'qa_poll_archive.json').write_text(json.dumps(index,ensure_ascii=False,indent=2),encoding='utf-8')
rows+=poll_rows;roots.append('reports')
result={'status':'VERIFIED_REPLACEMENT_READY_FOR_REDUNDANT_OUTPUT_RETIREMENT','retained_build':KEEP.relative_to(ROOT).as_posix(),'pck_sha256':version['pck_sha256'],'roots':roots,'files':rows,'retirement_bytes':sum(r['bytes'] for r in rows),'protected_media_retained':retained,'qa_archive':index['archive'],'project_bytes_before':sum(p.stat().st_size for p in files(ROOT))}
(REPORT/'retirement_manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('RETIREMENT_READY',len(rows),'files',result['retirement_bytes'],'bytes; projected',result['project_bytes_before']-result['retirement_bytes'])
