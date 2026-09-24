"""Record the delivered local player, art browser and final storage size."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import os
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT/'reports/existing_roster_spritegen_20260911'
BASE = 'http://127.0.0.1:8770'
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
with urllib.request.urlopen(BASE+'/__local_game_status') as response:
    health = json.load(response)
assert health['build'] == 'builds/web_roster21_damage_restart_20260911_release'
with urllib.request.urlopen(BASE+'/art-gallery') as response:
    page = response.read().decode('utf8')
assert page.count('<article data-group=') == 73
ids = []
for folder in ['enemy_replacements_20260911','roster_replacements_20260911']:
    ids.extend(row['entity_id'] for row in read(ROOT/'data_source/art_source'/folder/'manifest.json')['assets'])
def endpoint(url):
    with urllib.request.urlopen(urllib.request.Request(BASE+url,method='HEAD')) as response:
        assert response.status == 200 and response.headers['Content-Type'] == 'image/png'
        assert int(response.headers['Content-Length']) > 1000
    return url
with ThreadPoolExecutor(max_workers=6) as pool:
    endpoints = list(pool.map(endpoint,[url for entity in ids for url in [f'/art/{entity}.png',f'/art/{entity}/preview.png']]))
try:
    urllib.request.urlopen(BASE+'/art/CHR999.png')
    raise AssertionError('Unreviewed art must not be served')
except urllib.error.HTTPError as error:
    assert error.code == 404
totals = {}
for directory, dirs, names in os.walk(ROOT.parent,followlinks=False):
    dirs[:] = [d for d in dirs if not (Path(directory)/d).is_junction() and not (Path(directory)/d).is_symlink()]
    for name in names:
        p = Path(directory)/name
        if p.is_symlink(): continue
        rel = p.relative_to(ROOT.parent)
        totals[rel.parts[0]] = totals.get(rel.parts[0],0) + p.stat().st_size
result = {'status':'PASS','health':health,'art_count':len(ids),'art_http_endpoints':len(endpoints),
          'project_bytes':totals[ROOT.name],'workspace_bytes':sum(totals.values()),
          'workspace_by_top_level':totals,
          'storage_verification':read(REPORT/'verification_after_cleanup.json')['passed']}
assert result['storage_verification']
(REPORT/'delivery_verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(result,ensure_ascii=False),flush=True)
