"""Enable reviewed art for public hosts without changing verified game resources.

The only PCK resource edit is the existing production HD capability in
project.binary. No developer feature, QA command or recording autoload is added.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/qa'))
from prepare_fps_probe_build import directory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    source, dest = args.source.resolve(), args.destination.resolve()
    assert source.is_relative_to(ROOT / 'builds') and dest.is_relative_to(ROOT / 'builds')
    assert source != dest and not dest.exists()
    checks = json.loads((ROOT / 'reports/startup_r24_20261005/completion.json').read_text(encoding='utf-8'))
    assert checks['status'] == 'LOCAL_VERIFIED_COMPLETE'
    pack, = source.glob('*.pck')
    data = pack.read_bytes()
    original_hash = hashlib.sha256(data).hexdigest()
    assert original_hash == checks['pck_sha256']
    version = json.loads((source / 'VERSION.json').read_text(encoding='utf-8-sig'))
    assert version['pck_sha256'] == original_hash
    base, offset, rows = directory(data)
    project, = [r for r in rows if r[0] == 'project.binary']
    old = data[project[1]:project[1] + project[2]]
    assert old[:4] == b'ECFG' and b'_custom_features' not in old
    feature = b'lanternline_reviewed_hd'
    variant = struct.pack('<II', 4, len(feature)) + feature
    variant += b'\0' * (-len(variant) % 4)
    key = b'_custom_features'
    prop = struct.pack('<I', len(key)) + key + struct.pack('<I', len(variant)) + variant
    patched = b'ECFG' + struct.pack('<I', struct.unpack_from('<I', old, 4)[0] + 1) + prop + old[8:]
    payload = bytearray(data[:offset])
    new_offset = len(payload)
    payload += patched
    payload += b'\0' * (-len(payload) % 16)
    new_directory_offset = len(payload)
    table = bytearray(data[offset:])
    relative = project[5] - offset
    struct.pack_into('<QQ', table, relative, new_offset - base, len(patched))
    table[relative + 16:relative + 32] = hashlib.md5(patched).digest()
    payload += table
    struct.pack_into('<Q', payload, 32, new_directory_offset)
    _, _, after = directory(payload)
    unchanged = []
    for before, current in zip(rows, after, strict=True):
        assert before[0] == current[0]
        if before[0] == 'project.binary':
            continue
        a = data[before[1]:before[1] + before[2]]
        b = payload[current[1]:current[1] + current[2]]
        assert a == b, before[0]
        unchanged.append({'path': before[0], 'sha256': hashlib.sha256(a).hexdigest(), 'bytes': len(a)})
    assert len(unchanged) == 4017
    public_hash = hashlib.sha256(payload).hexdigest()
    old_base, new_base = version['runtime_artifact_base'], 'r7_current_' + public_hash[:12]
    dest.mkdir()
    mutable = {'index.html', 'index.service.worker.js', 'VERSION.json', 'README_HTML.md'}
    for file in source.rglob('*'):
        if not file.is_file():
            continue
        name = file.relative_to(source).as_posix().replace(old_base, new_base)
        target = dest / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if file == pack:
            target.write_bytes(payload)
        elif file.name in mutable:
            text = file.read_text(encoding='utf-8-sig').replace(old_base, new_base)
            if file.name == 'index.html':
                text = text.replace('"' + new_base + '.pck":' + str(len(data)), '"' + new_base + '.pck":' + str(len(payload)))
            target.write_text(text, encoding='utf-8', newline='\n')
        else:
            os.link(file, target)
    version.update(runtime_artifact_base=new_base, pck_sha256=public_hash,
                   verified_local_source_pck_sha256=original_hash, production_approved=True,
                   public_features=['lanternline_reviewed_hd'], developer_features_enabled=False)
    (dest / 'VERSION.json').write_text(json.dumps(version, indent=2) + '\n', encoding='utf-8')
    evidence = {'source': str(source), 'destination': str(dest), 'source_pck_sha256': original_hash,
                'public_pck_sha256': public_hash, 'only_resource_change': 'project.binary: lanternline_reviewed_hd',
                'added_resources': [], 'developer_features_enabled': False,
                'identical_gameplay_and_asset_entries': unchanged}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(evidence, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in evidence.items() if k != 'identical_gameplay_and_asset_entries'}))


if __name__ == '__main__':
    main()
