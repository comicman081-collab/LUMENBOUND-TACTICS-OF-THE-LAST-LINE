"""Retain every distinct intro video before retiring old local Godot exports."""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / 'reports/storage_cleanup_20260911'
VIDEO_EXT = {'.ogv', '.mp4', '.webm', '.mov', '.mkv'}

def digest(path, name='sha256'):
    h=hashlib.new(name)
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(2**20),b''):h.update(chunk)
    return h.hexdigest()

def entries(path):
    with path.open('rb') as stream:
        header=stream.read(40)
        if header[:4]!=b'GDPC' or struct.unpack_from('<I',header,4)[0]!=4:
            raise ValueError(f'Unverified pack format: {path}')
        flags=struct.unpack_from('<I',header,20)[0]
        if flags & 1: raise ValueError(f'Encrypted pack: {path}')
        base,directory=struct.unpack_from('<QQ',header,24)
        stream.seek(directory)
        count=struct.unpack('<I',stream.read(4))[0]
        if not 0<count<100000: raise ValueError('Invalid entry count')
        for _ in range(count):
            length=struct.unpack('<I',stream.read(4))[0]
            if length>4096:raise ValueError('Invalid entry length')
            name=stream.read(length).rstrip(b'\0').decode('utf8')
            offset,size=struct.unpack('<QQ',stream.read(16))
            md5=stream.read(16).hex()
            item_flags=struct.unpack('<I',stream.read(4))[0]
            yield name,base+offset,size,md5,item_flags

def main():
    known={};protected=[]
    for base in ['intro','data_source/video','godot/assets/video','work/video']:
        for path in (ROOT/base).rglob('*'):
            if path.is_file() and path.suffix.lower() in VIDEO_EXT:
                row={'path':path.relative_to(ROOT).as_posix(),'bytes':path.stat().st_size,'sha256':digest(path),'md5':digest(path,'md5')}
                known[row['md5']]=row;protected.append(row)
    packs=[];archive=ROOT/'intro/archived_from_builds'
    for base in ['builds','work','quarantine']:
        for pack in (ROOT/base).rglob('*.pck'):
            for name,offset,size,md5,flags in entries(pack):
                if Path(name).suffix.lower() not in VIDEO_EXT: continue
                if flags: raise ValueError(f'Unsupported video entry flags: {pack}: {name}')
                if md5 not in known:
                    with pack.open('rb') as stream:
                        stream.seek(offset);data=stream.read(size)
                    if len(data)!=size or hashlib.md5(data).hexdigest()!=md5: raise ValueError('Video entry hash mismatch')
                    archive.mkdir(parents=True,exist_ok=True)
                    dest=archive/(md5[:16]+'_'+Path(name).name)
                    if dest.exists() and digest(dest,'md5')!=md5: raise ValueError('Archive collision')
                    dest.write_bytes(data)
                    row={'path':dest.relative_to(ROOT).as_posix(),'bytes':size,'sha256':digest(dest),'md5':md5}
                    known[md5]=row;protected.append(row)
                packs.append({'pack':pack.relative_to(ROOT).as_posix(),'entry':name,'md5':md5,'retained':known[md5]['path']})
    report={'status':'VERIFIED','protected_videos':protected,'pack_video_entries':packs}
    (REPORT/'intro_preservation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({'protected_files':len(protected),'distinct_versions':len(known),'pack_video_entries':len(packs)},ensure_ascii=False))

if __name__=='__main__':main()
