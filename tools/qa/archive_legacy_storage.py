"""Losslessly consolidate old LFS build caches and quarantined art evidence.

Never removes inputs. Every member is hashed again from the finished archive
before a separate, bounded cleanup step can retire the redundant loose copies.
"""
from pathlib import Path
import hashlib
import json
import lzma
import tarfile
import argparse

ROOT=Path(__file__).resolve().parents[2]
REPORT=ROOT/'reports/storage_cleanup_20260911'
ARCHIVES=ROOT/'quarantine/retained_archive_20260911'
ART_ROOTS=[
    'work/gameplay_qa_quarantine_20260907/enclosed_white_matte/retained_failures',
    'quarantine/battle_signature_hd',
    'quarantine/incomplete_asset_candidates',
    'data_source/art_source/natural_environment_r1/quarantine',
] + [f'godot/assets/generated_import/chroma_key_derivatives/battle_signature_r{n}' for n in [7,10,11,12,13]]

def sha(p):
    with p.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def run(kind, verify_existing=False):
    ARCHIVES.mkdir(parents=True,exist_ok=True)
    if kind=='lfs':
        inputs=[p for p in (ROOT/'.git/lfs/objects').rglob('*') if p.is_file()]
        inputs.sort(key=lambda p:p.stat().st_size)
        roots=[]
    else:
        roots=[ROOT/p for p in ART_ROOTS if (ROOT/p).exists()]
        inputs=[p for folder in roots for p in folder.rglob('*') if p.is_file()]
    records=[]
    for p in inputs:
        if p.is_symlink() or p.is_junction() or not p.resolve().is_relative_to(ROOT):raise ValueError('Unsafe input')
        h=sha(p)
        if kind=='lfs' and h!=p.name:raise ValueError('LFS content does not match its OID')
        records.append({'path':str(p),'member':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':h})
    if kind=='art':records.sort(key=lambda r:(r['sha256'],r['member']))
    output=ARCHIVES/f'{kind}_retained.tar.xz'
    dictionary=(256 if kind=='lfs' else 32)*2**20
    if not verify_existing:
        if output.exists():raise FileExistsError('Retained archive already exists; use --verify-existing to audit it')
        with lzma.open(output,'wb',filters=[{'id':lzma.FILTER_LZMA2,'preset':1,'dict_size':dictionary}]) as compressed:
            with tarfile.open(fileobj=compressed,mode='w|',format=tarfile.PAX_FORMAT) as archive:
                for i,row in enumerate(records):
                    archive.add(row['path'],arcname=row['member'],recursive=False)
                    if kind=='lfs' or i%250==0:print('ARCHIVED',kind,i+1,'/',len(records),flush=True)
    expected={r['member']:r for r in records};seen=set()
    # Seekable tar reading avoids a stream/readinto inconsistency observed with
    # this Python runtime on a large PCK member. Hash explicit bounded reads.
    with tarfile.open(output,mode='r:xz') as archive:
        for member in archive:
            if not member.isfile():raise ValueError('Unexpected archive member')
            if member.name not in expected or member.name in seen:raise ValueError('Unexpected or duplicate member')
            stream=archive.extractfile(member)
            digest=hashlib.sha256()
            while chunk:=stream.read(1024*1024):digest.update(chunk)
            if member.size!=expected[member.name]['bytes'] or digest.hexdigest()!=expected[member.name]['sha256']:raise ValueError('Archive verification failed: '+member.name)
            seen.add(member.name)
            if kind=='lfs':print('VERIFIED',len(seen),'/',len(records),member.name,flush=True)
    if len(seen)!=len(records):raise ValueError('Incomplete archive')
    report={'status':'LOSSLESS_ARCHIVE_VERIFIED','archive':str(output),'archive_sha256':sha(output),
        'input_bytes':sum(r['bytes'] for r in records),'archive_bytes':output.stat().st_size,
        'root_directories':[str(p) for p in roots],'members':records,'kind':kind,
        'retention':'Content, green masters, manifests and review evidence preserved; no failed asset is disposed of.'}
    (REPORT/f'{kind}_archive.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print('ARCHIVE_VERIFIED',kind,'saved_MiB',(report['input_bytes']-report['archive_bytes'])/2**20,flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('kind',choices=['lfs','art'])
    parser.add_argument('--verify-existing',action='store_true')
    args=parser.parse_args();run(args.kind,args.verify_existing)
