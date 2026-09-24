"""Compress verified QA polling records losslessly; add originals to retirement plan."""
from pathlib import Path
import hashlib,json,re,zipfile,os,sys
ROOT=Path(__file__).resolve().parents[2]
REPORT=ROOT/'reports/combat_map_upgrade_20260913'
manifest_path=REPORT/'retirement_manifest.json'
manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
assert manifest['status']=='VERIFIED_REPLACEMENT_READY_FOR_REDUNDANT_OUTPUT_RETIREMENT'
sources=[REPORT,ROOT/'reports/chapter_boss_flow_20260912']
additional_roster='--additional-roster' in sys.argv
if additional_roster:sources=[ROOT/'reports/existing_roster_spritegen_20260911']
additional_encounters='--additional-encounters' in sys.argv
if additional_encounters:
    sources=[ROOT/'reports/encounter_contact_fix_20260911',ROOT/'reports/enemy_replacement_20260911']
    manifest['files']=[];manifest['roots']=[];manifest['qa_archives']=[]
    manifest_path=REPORT/'final_size_cleanup/retirement_manifest.json'
    manifest_path.parent.mkdir(exist_ok=True)
records=[]
for source in sources:
    assert source.resolve().is_relative_to(ROOT/'reports') and not source.is_junction()
    for p in source.rglob('*.json'):
        if p.is_symlink() or p.parent==source:continue
        if re.fullmatch(r'state_\d+\.json',p.name) or p.name=='gameplay_report.json':
            records.append(p)
archive=REPORT/('roster_qa_poll_records.zip' if additional_roster else 'qa_poll_records.zip')
if additional_encounters:archive=REPORT/'encounter_qa_poll_records.zip'
assert not archive.exists(),'Never overwrite an evidence archive'
rows=[]
with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=8) as z:
    for p in sorted(records):
        payload=p.read_bytes();relative=p.relative_to(ROOT).as_posix()
        row={'path':relative,'bytes':len(payload),'sha256':hashlib.sha256(payload).hexdigest()}
        rows.append(row);z.writestr(relative,payload)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for row in rows:assert hashlib.sha256(z.read(row['path'])).hexdigest()==row['sha256']
archive_index={'archive':archive.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'files':rows,'preservation':'Lossless original JSON records; screenshots and acceptance results remain loose. Extract archive entries under the project root to restore.'}
index_name='encounter_qa_poll_archive.json' if additional_encounters else ('roster_qa_poll_archive.json' if additional_roster else 'qa_poll_archive.json')
(REPORT/index_name).write_text(json.dumps(archive_index,ensure_ascii=False,indent=2),encoding='utf-8')
manifest['files'].extend(rows)
manifest['roots'].extend(p.relative_to(ROOT).as_posix() for p in sources)
manifest['retirement_bytes']=sum(r['bytes'] for r in manifest['files'])
manifest.setdefault('qa_archives',[]).append(archive_index['archive'])
manifest['project_bytes_before']=sum(p.stat().st_size for p in ROOT.rglob('*') if p.is_file() and not p.is_symlink())
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('ARCHIVE_VERIFIED',len(rows),'records',sum(r['bytes'] for r in rows),'source bytes',archive.stat().st_size,'archive bytes')
print('PROJECTED_AFTER',manifest['project_bytes_before']-manifest['retirement_bytes'])
