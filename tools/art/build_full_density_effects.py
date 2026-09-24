"""Render genuine high-density FX from pinned key art/original vectors, not thumbnails."""
import argparse
import math
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter,ImageChops
from build_full_density_runtime import ROOT,GODOT,read,sha,save_json,module,legacy
keyart=module('vfx_keyart',ROOT/'tools/art/build_vfx_keyart_atlas.py')
RUNTIME=GODOT/'assets/runtime_web'

def sheet_from_frames(frames,columns):
    cell=frames[0].width
    atlas=Image.new('RGBA',(cell*columns,cell*math.ceil(len(frames)/columns)))
    for i,frame in enumerate(frames): atlas.alpha_composite(frame,((i%columns)*cell,(i//columns)*cell))
    return atlas

def resize_sheet(source,cell):
    if source.width%4 or source.height%3 or source.width//4!=source.height//3: raise ValueError('NOT_AUTHORED_4X3')
    sc=source.width//4
    if sc<cell: raise ValueError('AUTHORITY_NOT_HIGH_DENSITY')
    return sheet_from_frames([source.crop(((i%4)*sc,(i//4)*sc,(i%4+1)*sc,(i//4+1)*sc)).resize((cell,cell),Image.Resampling.LANCZOS) for i in range(12)],4)

def vector_projectile(manifest,profile,cell=192):
    # Same project-authored 96-unit geometry, rendered at 3x then reduced to
    # 192px. This preserves its profile/timing without enlarging a raster.
    frames=[]; s=3; p=tuple(profile['primary']); sec=tuple(profile['secondary']); shape=profile['normal']
    for index in range(8):
        t=index/7;cx=(28+t*38)*s;cy=(49+math.sin(t*math.tau)*5)*s;r=(9+(index%3)*2)*s
        energy=Image.new('RGBA',(96*s,96*s));d=ImageDraw.Draw(energy)
        d.line((4*s,cy+6*s,cx+r*1.2,cy-4*s),fill=p+(120,),width=5*s)
        if shape in ('tracer','lightning','artillery'): d.polygon([(cx-r,cy+r*.5),(cx+r*1.7,cy),(cx-r,cy-r*.5)],fill=sec+(255,))
        elif shape in ('shield','heal','chorus'):
            d.ellipse((cx-r,cy-r,cx+r,cy+r),outline=sec+(255,),width=3*s)
            d.ellipse((cx-r*.42,cy-r*.42,cx+r*.42,cy+r*.42),fill=p+(230,))
        else: d.polygon(legacy._polygon_ring(cx,cy,r,5+index%3,t*math.tau),fill=p+(240,),outline=sec+(255,))
        frame=energy.filter(ImageFilter.GaussianBlur(5*s));frame.alpha_composite(energy)
        frames.append(frame.resize((cell,cell),Image.Resampling.LANCZOS))
    return sheet_from_frames(frames,8)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--revision',required=True);args=parser.parse_args()
    out=RUNTIME/'full_density_effects'/args.revision
    qa=ROOT/'work/full_density_effects'/args.revision
    if out.exists() or qa.exists(): raise ValueError('IMMUTABLE_REVISION_EXISTS')
    (out/'pages').mkdir(parents=True);qa.mkdir(parents=True)
    proven={}
    for directory in (ROOT/'reports/r15/vfx',ROOT/'reports/r15/art_b/qa'):
        for path in directory.glob('*.json'):
            report=read(path)
            atlas_hash=report.get('atlas_sha256',report.get('runtime_sha256',''))
            clean=report.get('clean_source',report.get('masked_source',''))
            if atlas_hash and clean:
                clean_path=ROOT/clean.replace('\\','/')
                if clean_path.is_file(): proven[atlas_hash]=(clean_path,report,path)
    index={'status':'LOCAL_QA_ONLY','revision':args.revision,'projectiles':{},'vfx':{},'issues':[]}
    profiles=legacy.complete_vfx_style_profiles()
    def store(atlas,meta):
        if atlas.getchannel('A').getextrema()[0]!=0: raise ValueError('OPAQUE_FX_MATTE')
        key=__import__('hashlib').sha256(atlas.tobytes()).hexdigest()
        file=out/'pages'/f'{key}.png'
        if not file.exists(): atlas.save(file,compress_level=6)
        return {**meta,'atlas_path':'pages/'+file.name,'atlas_sha256':sha(file),'size':list(atlas.size),'decoded_rgba_bytes':atlas.width*atlas.height*4}
    for path in sorted((RUNTIME/'projectiles').glob('*/projectile_manifest.json')):
        m=read(path);entity=m['source_id'];source=GODOT/'assets/generated_import/projectiles'/m.get('source_asset_id','')
        if (source/'projectile_manifest.json').is_file():
            original=read(source/'projectile_manifest.json');frames=[];records=[]
            for relative in original['frame_paths']:
                file=source/relative;frame=Image.open(file).convert('RGBA')
                if min(frame.size)<192: raise ValueError('PROJECTILE_SOURCE_TOO_SMALL')
                frames.append(frame.resize((192,192),Image.Resampling.LANCZOS));records.append({'source':file.relative_to(ROOT).as_posix(),'sha256':sha(file)})
            atlas=sheet_from_frames(frames,8);method='original_256px_frames_to_192px'
        else:
            atlas=vector_projectile(m,profiles[entity]);records=[];method='project_original_vector_geometry_rerender_288_to_192'
        index['projectiles'][entity]=store(atlas,{'frame_size':192,'columns':8,'frames':8,'source_method':method,'source_manifest':path.relative_to(ROOT).as_posix(),'source_manifest_sha256':sha(path),'source_records':records})
    for path in sorted((RUNTIME/'vfx').glob('*/vfx_manifest.json')):
        m=read(path);entity=m.get('entity_id','');kind=m.get('kind','');key=path.parent.name.removeprefix('vfx_')
        if not entity or kind not in ('basic','normal','ultimate'): continue
        cell=256 if kind=='ultimate' else 192
        expected=m.get('source_sha256',m.get('sha256',''))
        if expected in proven:
            clean,report,report_path=proven[expected]
            original=Image.open(clean).convert('RGBA')
            if report.get('clean_source'):
                baseline=keyart.build_atlas(original,112);atlas=keyart.build_atlas(original,cell);method='pinned_high_resolution_keyart_rerender'
                if sha(clean)!=report['clean_source_sha256']: raise ValueError(f'KEYART_HASH_MISMATCH:{clean}')
            else:
                baseline=resize_sheet(original,112);atlas=resize_sheet(original,cell);method='authored_high_resolution_frame_sheet_downsample'
            old=Image.open(path.parent/'atlas.png').convert('RGBA')
            if ImageChops.difference(baseline,old).getbbox(alpha_only=False): raise ValueError(f'VFX_SOURCE_REPRODUCTION_MISMATCH:{key}')
            records={'source':clean.relative_to(ROOT).as_posix(),'source_sha256':sha(clean),'report':report_path.relative_to(ROOT).as_posix(),'report_sha256':sha(report_path),'compact_reproduction_pixel_exact':True}
        elif not m.get('source'):
            p=tuple(bytes.fromhex(m['primary'].lstrip('#')));s=tuple(bytes.fromhex(m['secondary'].lstrip('#')))
            atlas=sheet_from_frames([legacy._vfx_cell(p,s,kind,i,m['motion_shape'],cell) for i in range(12)],4)
            method='existing_project_vector_motion_rerender_336px';records={'source_manifest_sha256':sha(path)}
        else:
            index['issues'].append({'key':key,'reason':'HIGH_RESOLUTION_AUTHORITY_PROVENANCE_NOT_RESOLVED','source':m.get('source')})
            continue
        index['vfx'][key]=store(atlas,{'frame_size':cell,'columns':4,'frames':12,'source_method':method,**records})
    save_json(out/'index.json',index);save_json(qa/'build_summary.json',{'projectiles':len(index['projectiles']),'vfx':len(index['vfx']),'unique_pages':len(list((out/'pages').glob('*.png'))),'issues':index['issues']})
    print(read(qa/'build_summary.json'))

if __name__=='__main__':main()
