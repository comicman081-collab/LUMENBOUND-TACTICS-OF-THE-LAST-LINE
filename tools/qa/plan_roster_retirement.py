"""Hash only verified redundant outputs; keep sources, all audio and all movies."""
from pathlib import Path
import hashlib
import json
import os

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / 'reports/existing_roster_spritegen_20260911'
PROTECTED = ROOT / 'reports/storage_cleanup_20260911'
KEEP_BUILD = 'web_roster21_damage_restart_20260911_release'
MEDIA = {'.wav','.ogg','.oga','.mp3','.flac','.m4a','.aac','.opus','.mid','.midi',
         '.mp4','.webm','.ogv','.avi','.mov','.mkv'}

def read(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))

def sha(p):
    with p.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def files(root):
    for directory, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = [d for d in dirs if not (Path(directory)/d).is_junction() and not (Path(directory)/d).is_symlink()]
        for name in names:
            p = Path(directory)/name
            if not p.is_symlink():
                yield p

def passed(p):
    doc = read(p)
    if 'checks' in doc:
        assert all(c.get('pass', c.get('ok', c.get('passed', False))) for c in doc['checks']), p
    else:
        assert doc.get('status') == 'PASS', p

for name in ['installed_runtime_verification.json','godot_asset_verification.json',
             'restart_tests.json','browser_v2/acceptance.json','defeat_browser/acceptance.json',
             'release_boot/acceptance.json','late_encounter_browser/acceptance.json']:
    passed(REPORT/name)

protected = set()
for name, key, field in [('music_preservation.json','files','path'),
                         ('intro_preservation.json','protected_videos','path'),
                         ('audio_source_preservation.json','records','retained')]:
    for row in read(PROTECTED/name)[key]:
        protected.add((ROOT/row[field]).resolve())

roots = [ROOT/'builds'/name for name in [
    'web_monster52_spritegen_20260911_development',
    'web_monster52_spritegen_20260911_release',
    'web_verified_local_20260911_release',
    'web_roster21_damage_restart_20260911_development']]
roots += [ROOT/p for p in [
    'godot/.godot','godot/.runtime_profile',
    'work/enemy_replacement_20260911/staged',
    'work/existing_roster_spritegen_20260911/staged',
    'reports/existing_roster_spritegen_20260911/browser/profile']]
rows, retained = [], []
for root in roots:
    assert root.resolve().is_relative_to(ROOT) and root != ROOT
    assert not root.is_junction() and not root.is_symlink()
    if not root.exists():
        continue
    for p in files(root):
        rel = p.relative_to(ROOT).as_posix()
        assert p.resolve().is_relative_to(root.resolve())
        if p.suffix.lower() in MEDIA or p.resolve() in protected:
            retained.append(rel)
            continue
        rows.append({'path': rel, 'bytes': p.stat().st_size, 'sha256': sha(p)})

total = sum(p.stat().st_size for p in files(ROOT))
result = {'status':'VERIFIED_REPLACEMENT_READY_FOR_REDUNDANT_OUTPUT_RETIREMENT',
          'retained_build':KEEP_BUILD,'project_bytes_before':total,
          'roots':[p.relative_to(ROOT).as_posix() for p in roots],
          'protected_media_retained':retained,'retirement_bytes':sum(r['bytes'] for r in rows),
          'files':rows,'scope':'Superseded export copies, rebuildable import cache, isolated QA profiles, duplicate installed pack staging. Source art, rejected masters, Git history and recovery archives are retained.'}
(REPORT/'retirement_manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in result.items() if k not in ['files','protected_media_retained']},ensure_ascii=False))
print('RETIREMENT_FILES',len(rows),'MEDIA_RETAINED',len(retained),flush=True)
