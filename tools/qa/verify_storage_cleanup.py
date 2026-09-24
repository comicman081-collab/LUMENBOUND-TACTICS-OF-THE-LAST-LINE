"""Read-only integrity audit after the September 11 local storage cleanup."""
from pathlib import Path
import ast
import argparse
import gzip
import hashlib
import json
import socket
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / 'reports/storage_cleanup_20260911'
parser = argparse.ArgumentParser()
parser.add_argument('--build', default='builds/web_verified_local_20260911_release')
parser.add_argument('--output', default='reports/storage_cleanup_20260911/verification_after_cleanup.json')
parser.add_argument('--retained-media-builds', action='store_true')
args = parser.parse_args()
BUILD = (ROOT / args.build).resolve()
assert BUILD.is_relative_to((ROOT/'builds').resolve())
checks = []


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def check(name, passed, details=None):
    checks.append({'name': name, 'passed': bool(passed), 'details': details})
    print('PASS' if passed else 'FAIL', name, flush=True)


def preserved(name, rows, key):
    failed = [r[key] for r in rows if not (ROOT/r[key]).is_file() or sha(ROOT/r[key]) != r['sha256']]
    check(name, not failed, {'files': len(rows), 'failures': failed})


preserved('Unused BGM, title and ending collections unchanged', read_json(REPORT/'music_preservation.json')['files'], 'path')
preserved('All previous intro videos unchanged', read_json(REPORT/'intro_preservation.json')['protected_videos'], 'path')
preserved('Required audio source masters unchanged', read_json(REPORT/'audio_source_preservation.json')['records'], 'retained')
second = read_json(REPORT/'inventory_second_pass.json')
audio_ext = {'.wav', '.ogg', '.oga', '.mp3', '.flac', '.m4a', '.aac', '.opus', '.mid', '.midi'}
audio = [r for r in second['files'] if Path(r['path']).suffix.lower() in audio_ext]
missing = [r['path'] for r in audio if not (ROOT/r['path']).is_file() or (ROOT/r['path']).stat().st_size != r['bytes']]
check('Additional cleanup preserves every remaining audio file', not missing, {'files': len(audio), 'failures': missing})

for kind in ['art', 'lfs']:
    archive = read_json(REPORT/f'{kind}_archive.json')
    check(f'{kind} recovery archive unchanged after loose-copy retirement', sha(Path(archive['archive'])) == archive['archive_sha256'], {'members': len(archive['members']), 'bytes': archive['archive_bytes']})
    check(f'{kind} archived loose copies removed', all(not Path(r['path']).exists() for r in archive['members']))

compressed = read_json(REPORT/'compressed_reports.json')
failed = []
for row in compressed:
    with gzip.open(row['gzip'], 'rb') as stream:
        digest = hashlib.sha256()
        while chunk := stream.read(1024*1024):
            digest.update(chunk)
    if digest.hexdigest() != row['sha256'] or Path(row['source']).exists():
        failed.append(row['source'])
check('Compressed QA reports reproduce original bytes', not failed, {'reports': len(compressed), 'failures': failed})

version = read_json(BUILD/'VERSION.json')
base = version['runtime_artifact_base']
check('Current release PCK unchanged', sha(BUILD/(base+'.pck')) == version['pck_sha256'], version['pck_sha256'])
for manifest_name, key in [('density_sidecars.json', 'pages'), ('audio_sidecars.json', 'tracks')]:
    manifest = read_json(BUILD/manifest_name)
    records = manifest[key]
    failures = []
    for name, row in records.items():
        path = BUILD / row.get('path', name)
        if not path.is_file() or sha(path) != row['sha256']:
            failures.append(str(path))
    check(f'{manifest_name} contents unchanged', not failures, {'entries': len(records), 'failures': failures})

base_url = 'http://127.0.0.1:8770'
with urllib.request.urlopen(base_url+'/__local_game_status', timeout=10) as response:
    health = json.load(response)
check('Local player serves the retained build', health['service'] == 'lumenbound-local-player-v2' and health['build'] == BUILD.relative_to(ROOT).as_posix() and version['pck_sha256'][:12] in health['play_path'], health)
for name in ['index.html', 'index.js', base+'.pck', base+'.wasm', 'density_sidecars.json', 'audio_sidecars.json']:
    request = urllib.request.Request(base_url+health['play_path']+name, method='HEAD')
    with urllib.request.urlopen(request, timeout=10) as response:
        check('HTTP '+name, response.status == 200, {'bytes': response.headers.get('Content-Length')})
request = urllib.request.Request(base_url+'/intro.mp4', headers={'Range': 'bytes=0-1023'})
with urllib.request.urlopen(request, timeout=10) as response:
    check('Intro supports browser range playback', response.status == 206 and len(response.read()) == 1024)
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    try:
        sock.bind(('127.0.0.1', 8770))
        exclusive = False
    except OSError:
        exclusive = True
check('A second server cannot claim the current player port', exclusive)

old_refs = (REPORT/'git_refs_before_gc.txt').read_text(encoding='utf-8-sig').splitlines()
live_refs = subprocess.check_output(['git', 'for-each-ref', '--format=%(objectname) %(refname)'], cwd=ROOT, text=True).splitlines()
check('All Git refs preserved', sorted(old_refs) == sorted(live_refs), {'refs': len(live_refs)})
old_objects = (REPORT/'git_objects_before_gc.txt').read_text(encoding='utf-8-sig').splitlines()
live_objects = subprocess.check_output(['git', 'cat-file', '--batch-all-objects', '--batch-check=%(objectname) %(objecttype) %(objectsize)'], cwd=ROOT, text=True).splitlines()
check('All Git objects preserved', sorted(old_objects) == sorted(live_objects), {'objects': len(live_objects)})
if args.retained_media_builds:
    media_ext = audio_ext | {'.mp4','.webm','.ogv','.avi','.mov','.mkv'}
    leftovers = [str(p.relative_to(ROOT)) for folder in (ROOT/'builds').iterdir() if folder != BUILD
                 for p in folder.rglob('*') if p.is_file() and p.suffix.lower() not in media_ext]
    check('Only current player plus protected media remain in builds', not leftovers, leftovers)
else:
    check('Only the current verified player build remains', [p.name for p in (ROOT/'builds').iterdir()] == [BUILD.name])
check('Disposable import cache is absent', not (ROOT/'godot/.godot').exists())
check('Old deployment staging is absent', not (ROOT/'dist/client').exists())
for name in ['archive_legacy_storage.py', 'restore_legacy_storage.py', 'verify_storage_cleanup.py']:
    ast.parse((ROOT/'tools/qa'/name).read_text(encoding='utf8'))
check('Cleanup and recovery Python helpers parse', True)

result = {'passed': all(r['passed'] for r in checks), 'checks': checks, 'player_url': base_url+health['play_path']}
(ROOT/args.output).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf8')
print('CLEANUP_VERIFICATION', sum(r['passed'] for r in checks), '/', len(checks), flush=True)
raise SystemExit(0 if result['passed'] else 1)
