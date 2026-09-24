"""Restore selected archived review sources or historical LFS build caches."""
from pathlib import Path
import argparse
import hashlib
import json
import tarfile

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('kind',choices=['art','lfs'])
parser.add_argument('--prefix',default='',help='Optional original project-relative path prefix')
parser.add_argument('--verify-only',action='store_true',help='Read and verify recoverable contents without restoring loose files')
args=parser.parse_args()
report=json.loads((ROOT/f'reports/storage_cleanup_20260911/{args.kind}_archive.json').read_text(encoding='utf8'))
archive=Path(report['archive'])
with archive.open('rb') as f:
    if hashlib.file_digest(f,'sha256').hexdigest()!=report['archive_sha256']:raise ValueError('Archive hash mismatch')
expected={r['member']:r for r in report['members']}
with tarfile.open(archive,'r:xz') as stream:
    for member in stream:
        if not member.isfile() or member.name not in expected:raise ValueError('Unexpected archive member')
        if not member.name.startswith(args.prefix.replace('\\','/')):continue
        dest=(ROOT/member.name).resolve()
        if not dest.is_relative_to(ROOT) or '..' in Path(member.name).parts:raise ValueError('Unsafe restore path')
        row=expected[member.name]
        if dest.exists() and not args.verify_only:
            with dest.open('rb') as f:
                if hashlib.file_digest(f,'sha256').hexdigest()!=row['sha256']:raise ValueError(f'Refusing to overwrite changed file: {dest}')
            continue
        data=stream.extractfile(member).read()
        if hashlib.sha256(data).hexdigest()!=row['sha256']:raise ValueError('Member hash mismatch')
        if args.verify_only:
            print('RECOVERY_VERIFIED',member.name,flush=True)
            continue
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(data)
        print('RESTORED',member.name)
