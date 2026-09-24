"""Stage the verified release in the existing Sites checkout, retaining range streaming."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
release = ROOT / 'builds/web_sites_20260920_release'
site = Path(sys.argv[1]).resolve()
assert json.loads((site / '.openai/hosting.json').read_text('utf-8'))['project_id'] == 'appgprj_6a8470621e60819190718ccb72b10c1d'
assert not (site / 'dist/client').exists(), 'Retire previous generated client explicitly first'
client = site / 'dist/client'
client.mkdir(parents=True)
server = site / 'dist/server/index.js'
body = server.read_text('utf-8').split('export default', 1)[1]
files = {}
hashes = {}
for source in sorted(release.rglob('*')):
    if not source.is_file(): continue
    relative = source.relative_to(release).as_posix()
    raw = source.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    hashes[relative] = {'sha256': digest, 'bytes': len(raw)}
    if len(raw) <= 20_000_000:
        target = client / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        continue
    chunk_size = 4 * 1024 * 1024
    parts = []
    for n, start in enumerate(range(0, len(raw), chunk_size)):
        part = f'asset-parts/{digest}/{n:03}.bin'
        target = client / part
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw[start:start + chunk_size])
        parts.append('/' + part)
    assert hashlib.sha256(b''.join((client / p.lstrip('/')).read_bytes() for p in parts)).hexdigest() == digest
    files['/' + relative] = {'size': len(raw), 'hash': digest, 'chunkSize': chunk_size,
                             'parts': parts, 'type': {'.mp4':'video/mp4', '.wasm':'application/wasm'}.get(source.suffix, 'application/octet-stream')}
server.write_text('const FILES = ' + json.dumps(files, separators=(',', ':')) + ';\nexport default' + body, 'utf-8')
# Keep the actual source for this release with the existing Site history.
for source in (ROOT / 'godot').rglob('*'):
    relative = source.relative_to(ROOT)
    if any(p.startswith('.') for p in relative.parts) or not source.is_file(): continue
    if source.suffix not in {'.gd', '.tscn', '.tres', '.cfg', '.godot', '.json', '.js', '.html'}: continue
    target = site / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
report = ROOT / 'reports/sites_update_20260920/staged_assets.json'
report.write_text(json.dumps({'files': hashes, 'streamed_routes':files, 'count':len(hashes)}, indent=2), 'utf-8')
target = site / 'reports/sites_update_20260920'
target.mkdir(parents=True, exist_ok=True)
shutil.copy2(report, target / report.name)
for name in ['delivery.json', 'artifact_verification.json']:
    shutil.copy2(ROOT / 'reports/combat_motion_20260913' / name, target / name)
for name in ['prepare_sites_update.py']:
    (site / 'tools/web').mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path(__file__).parent / name, site / 'tools/web' / name)
assert max(p.stat().st_size for p in client.rglob('*') if p.is_file()) <= 20_000_000
print(json.dumps({'files':len(hashes), 'streamed':list(files), 'largest_static_bytes':max(p.stat().st_size for p in client.rglob('*') if p.is_file())}))
