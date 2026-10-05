"""Losslessly gzip PCK transport chunks; preserve every Godot resource byte."""
import gzip
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
site = Path(sys.argv[1]).resolve()
if not site.is_relative_to(ROOT / 'work'):
    raise ValueError('Expected project-local Sites checkout')
client = site / 'dist/client'
manifest_path, = client.glob('*.pck.chunks.json')
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
report_path = site / 'reports/sites_update_20260920/staged_assets.json'
report = json.loads(report_path.read_text(encoding='utf-8'))
html_path, loader_path, sw_path = (client / name for name in ['index.html', 'index.js', 'index.service.worker.js'])
html, loader, sw = (p.read_text(encoding='utf-8') for p in [html_path, loader_path, sw_path])
needle = 'chunkReader = response.body.getReader();'
if loader.count(needle) != 1 or any(c.get('encoding') for c in manifest['chunks']):
    raise ValueError('Unexpected or already compressed PCK transport')
old_files = []
digest = hashlib.sha256()
for chunk in manifest['chunks']:
    source = client / chunk['file']
    raw = source.read_bytes()
    if len(raw) != chunk['size'] or hashlib.sha256(raw).hexdigest() != chunk['sha256']:
        raise ValueError('Source PCK chunk integrity mismatch')
    encoded = gzip.compress(raw, compresslevel=9, mtime=0)
    if gzip.decompress(encoded) != raw:
        raise ValueError('Lossless PCK verification failed')
    target = source.with_name(source.name + '.gz')
    if target.exists():
        raise ValueError('Unexpected PCK gzip target')
    target.write_bytes(encoded)
    digest.update(gzip.decompress(target.read_bytes()))
    chunk.update({'encoding': 'gzip', 'encoded_size': len(encoded),
                  'encoded_sha256': hashlib.sha256(encoded).hexdigest(), 'source_file': chunk['file']})
    chunk['file'] = target.name
    html = html.replace('"file":"' + source.name + '"', '"file":"' + target.name + '","encoding":"gzip"')
    sw = sw.replace('"' + source.name + '"', '"' + target.name + '"')
    old_files.append(source)
if digest.hexdigest() != manifest['original']['sha256']:
    raise ValueError('Reconstructed R21 PCK does not match its original SHA-256')
loader = loader.replace(needle,
    "chunkReader = (chunk.encoding === 'gzip' ? response.body.pipeThrough(new DecompressionStream('gzip')) : response.body).getReader();")
html_path.write_text(html, encoding='utf-8', newline='\n')
loader_path.write_text(loader, encoding='utf-8', newline='\n')
sw_path.write_text(sw, encoding='utf-8', newline='\n')
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8', newline='\n')
for path in [html_path, loader_path, sw_path]:
    report['staged_rewrites'][path.name] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size}
report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
verifier = site / 'scripts/verify-prebuilt.mjs'
code = verifier.read_text(encoding='utf-8')
code = "import {gunzipSync} from 'node:zlib';\n" + code
code = code.replace('const content=fs.readFileSync(file);digest.update(content);bytes+=content.length;',
    "let content=fs.readFileSync(file);if(part.includes('.pck.chunk-')&&part.endsWith('.gz'))content=gunzipSync(content);digest.update(content);bytes+=content.length;")
verifier.write_text(code, encoding='utf-8', newline='\n')
transport = {'original_sha256': manifest['original']['sha256'], 'original_bytes': manifest['original']['size'],
             'encoded_bytes': sum(c['encoded_size'] for c in manifest['chunks']), 'chunks': manifest['chunks']}
(site / 'reports/sites_pck_transport_20261001.json').write_text(json.dumps(transport, indent=2) + '\n', encoding='utf-8', newline='\n')
# Every encoded chunk and the complete reconstructed PCK have passed checks.
# The original verified release PCK remains read-only in builds/.
for source in old_files:
    source.unlink()
print(json.dumps({key: value for key, value in transport.items() if key != 'chunks'}))
