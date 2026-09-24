"""Prepare a bounded retirement inventory; deletion is a separate PowerShell step."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os

ROOT=Path(__file__).resolve().parents[2]
REPORT=ROOT/'reports/storage_cleanup_20260911'
KEEP_BUILD=ROOT/'builds/web_verified_local_20260911_release'

def sha(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def files_under(root):
    if root.is_file():yield root;return
    for base,dirs,files in os.walk(root,followlinks=False):
        for name in dirs+files:
            path=Path(base)/name
            if path.is_symlink() or path.is_junction():raise ValueError(f'Reparse point in deletion target: {path}')
        for name in files:yield Path(base)/name

def prepare():
    previous_plan=REPORT/'retirement_plan.json'
    if previous_plan.exists() and json.loads(previous_plan.read_text(encoding='utf8')).get('status')=='COMPLETE':
        raise RuntimeError('This one-off cleanup is complete. Use a new inventory for any future cleanup; preserve all remaining audio.')
    protected=json.loads((REPORT/'intro_preservation.json').read_text(encoding='utf8'))['protected_videos']
    for row in protected:
        path=ROOT/row['path']
        if sha(path)!=row['sha256']:raise ValueError(f'Intro changed: {path}')
    audio=json.loads((REPORT/'audio_source_preservation.json').read_text(encoding='utf8'))['records']
    for row in audio:
        if sha(ROOT/row['retained'])!=row['sha256']:raise ValueError('Required audio source is not retained')
    # September 11 user steering: unused BGM, title and ending songs stay.
    music_root=ROOT/'quarantine/asset_cleanup_20260904/audio_sources_retained'
    music_paths=[music_root/p for p in ['Sound/BGM','Sound/Title,ending','Sound/BLUE_ARCHIVE_like_title_songs.zip','work_site_overlay_audio/bgm']]
    music=[]
    for folder in music_paths:
        for p in files_under(folder):
            music.append({'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
    (REPORT/'music_preservation.json').write_text(json.dumps({'status':'VERIFIED','files':music},ensure_ascii=False,indent=2),encoding='utf8')
    version=json.loads((KEEP_BUILD/'VERSION.json').read_text(encoding='utf8'))
    pck=KEEP_BUILD/(version['runtime_artifact_base']+'.pck')
    if sha(pck)!=version['pck_sha256']:raise ValueError('Current build hash mismatch')
    targets={}
    for p in (ROOT/'builds').iterdir():
        if p!=KEEP_BUILD:targets[p]='superseded local build'
    # Isolated Chrome profiles are disposable cache, not the screenshots,
    # assertions and console logs retained alongside them.
    old=json.loads((REPORT/'inventory_before.json').read_text(encoding='utf8'))
    for row in old['files']:
        parts=Path(row['path']).parts[1:]
        if not parts or parts[0] not in ['reports','work','quarantine']:continue
        for index,part in enumerate(parts):
            if part.lower() in ['profile','profiles','browser_profile','chrome_profile','chromium_profile'] or part.lower().startswith('profile_'):
                path=ROOT.joinpath(*parts[:index+1])
                if path.exists():targets[path]='disposable browser profile'
                break
    # Old exports in quarantine have complete replacement runtime verification.
    # Source-art failures and their review evidence are deliberately kept.
    for area in ['work/gameplay_qa_quarantine_20260907','work/build_output_quarantine','quarantine/local_audit_20260910']:
        for p in (ROOT/area).rglob('*.pck'):
            if (p.parent/'index.html').exists():targets[p.parent]='replaced local export in quarantine'
    for path,reason in [
        ('godot/.runtime_profile/runs','isolated Godot test profiles and copied templates'),
        ('godot/.godot','rebuildable Godot import/export cache'),
        ('quarantine/asset_cleanup_20260904/audio_sources_retained/Sound/Characters','unused character sound collection'),
        ('quarantine/asset_cleanup_20260904/audio_sources_retained/Sound/Mobs','unused monster sound collection'),
        ('quarantine/asset_cleanup_20260904/audio_sources_retained/data_source_audio_source','duplicate of restored current CC0 source masters'),
        ('quarantine/asset_cleanup_20260904/audio_sources_retained/work_site_overlay_audio/sfx','obsolete overlay sound effects'),
        ('.git/objects/pack/tmp_pack_i6mA18','abandoned pack temporary file from September 5; no live Git writer'),
    ]:
        if (ROOT/path).exists():targets[ROOT/path]=reason
    for area in ['tools','work']:
        for p in (ROOT/area).rglob('__pycache__'):targets[p]='rebuildable Python bytecode cache'
    selected=[]
    for p in sorted(targets,key=lambda p:len(p.parts)):
        resolved=p.resolve(strict=True)
        if resolved!=p or not resolved.is_relative_to(ROOT) or resolved==ROOT:raise ValueError(f'Unsafe target: {p}')
        if any(p.is_relative_to(parent) for parent in selected):continue
        if p==KEEP_BUILD or KEEP_BUILD.is_relative_to(p):raise ValueError('Current build selected')
        if any((ROOT/row['path']).is_relative_to(p) for row in protected):raise ValueError('Intro selected')
        if any((ROOT/row['retained']).is_relative_to(p) for row in audio):raise ValueError('Source audio selected')
        if any(m==p or m.is_relative_to(p) for m in music_paths):raise ValueError('Protected music selected')
        selected.append(p)
    jobs=[];records=[]
    for p in selected:
        rows=list(files_under(p));size=sum(f.stat().st_size for f in rows)
        records.append({'path':str(p),'relative':p.relative_to(ROOT).as_posix(),'reason':targets[p],'files':len(rows),'bytes':size})
        jobs.extend((f,targets[p]) for f in rows)
    plan={'status':'PREPARED_NOT_DELETED','root':str(ROOT),'keep_build':str(KEEP_BUILD),'keep_pck_sha256':version['pck_sha256'],
        'targets':records,'files':len(jobs),'bytes':sum(r['bytes'] for r in records),'protected_intro_files':len(protected)}
    (REPORT/'retirement_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({k:v for k,v in plan.items() if k!='targets'},ensure_ascii=False),flush=True)
    def record(job):
        p,reason=job;stat=p.stat()
        return {'path':str(p),'bytes':stat.st_size,'mtime_ns':stat.st_mtime_ns,'sha256':sha(p),'reason':reason}
    with (REPORT/'retired_files.jsonl').open('w',encoding='utf8') as stream,ThreadPoolExecutor(max_workers=4) as pool:
        for index,row in enumerate(pool.map(record,jobs)):
            stream.write(json.dumps(row,ensure_ascii=False)+'\n')
            if index%20000==0:print('HASHED',index,'/',len(jobs),flush=True)
    plan['status']='HASHES_RECORDED_READY_FOR_DELETION'
    plan['inventory_sha256']=sha(REPORT/'retired_files.jsonl')
    (REPORT/'retirement_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')
    print('RETIREMENT_READY',round(plan['bytes']/2**30,3),'GiB',flush=True)

if __name__=='__main__':prepare()
