"""Hash redundant exports/cache after the chapter/boss delivery gates pass."""
from pathlib import Path
import hashlib
import json
import os

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / 'reports/chapter_boss_flow_20260912'

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def files(root):
    for parent, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = [d for d in dirs if not (Path(parent)/d).is_junction() and not (Path(parent)/d).is_symlink()]
        for name in names:
            path = Path(parent)/name
            if not path.is_symlink():
                yield path

for name in ['model.json', 'browser_final/acceptance.json', 'browser_final_compact/acceptance.json', 'release_final/acceptance.json']:
    checks = read(REPORT/name)['checks']
    assert checks and all(c.get('pass', c.get('ok', False)) for c in checks), name
assert 'TEST_SUMMARY total=301 pass=301 fail=0' in (REPORT/'regression_final.log').read_text(encoding='utf-8-sig')
protected = set()
for name, key, field in [('music_preservation.json','files','path'), ('intro_preservation.json','protected_videos','path'), ('audio_source_preservation.json','records','retained')]:
    protected.update((ROOT/r[field]).resolve() for r in read(ROOT/'reports/storage_cleanup_20260911'/name)[key])
media = {'.wav','.ogg','.oga','.mp3','.flac','.m4a','.aac','.opus','.mid','.midi','.mp4','.webm','.ogv','.avi','.mov','.mkv'}
roots = ['builds/web_chapter_boss_flow_20260912_release', 'builds/web_chapter_boss_flow_final_20260912_development', 'godot/.godot', 'godot/.runtime_profile']
rows, retained = [], []
for rel in roots:
    root = ROOT/rel
    assert root.resolve().is_relative_to(ROOT) and not root.is_junction() and not root.is_symlink()
    if not root.exists(): continue
    for path in files(root):
        assert path.resolve().is_relative_to(root.resolve())
        relative = path.relative_to(ROOT).as_posix()
        if path.suffix.lower() in media or path.resolve() in protected:
            retained.append(relative)
        else:
            rows.append({'path': relative, 'bytes': path.stat().st_size, 'sha256': sha(path)})
result = {'status': 'VERIFIED_REPLACEMENT_READY_FOR_REDUNDANT_OUTPUT_RETIREMENT',
          'retained_build': 'web_chapter_boss_flow_final_20260912_release', 'roots': roots,
          'files': rows, 'retirement_bytes': sum(r['bytes'] for r in rows),
          'protected_media_retained': retained,
          'project_bytes_before': sum(path.stat().st_size for path in files(ROOT))}
(REPORT/'retirement_manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('RETIREMENT_READY', len(rows), 'files', result['retirement_bytes'], 'bytes', flush=True)
