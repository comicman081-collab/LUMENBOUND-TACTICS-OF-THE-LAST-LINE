"""Measure candidate transparency and render review sheets; never approves art."""
from pathlib import Path
import hashlib
import json
import math
import argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
RUN=ROOT/'work/enemy_replacement_20260911'
OUT=ROOT/'reports/enemy_replacement_20260911'


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--run-name',default='enemy_replacement_20260911');args=parser.parse_args()
    run=(ROOT/'work'/args.run_name).resolve();out=(ROOT/'reports'/args.run_name).resolve()
    assert run.is_relative_to((ROOT/'work').resolve()) and out.is_relative_to((ROOT/'reports').resolve())
    out.mkdir(parents=True,exist_ok=True)
    rows=[]
    palette_path=run/'reviewed_material_colors.json'
    palettes=json.loads(palette_path.read_text(encoding='utf8')) if palette_path.exists() else {}
    font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',18)
    images=sorted((run/'normalized').glob('*/source.png'))
    for path in images:
        im=Image.open(path)
        a=np.asarray(im.convert('RGBA'))
        alpha=a[:,:,3]
        visible=alpha>16
        green=(a[:,:,1].astype(int)>np.maximum(a[:,:,0],a[:,:,2]).astype(int)+55)&(a[:,:,1]>120)&(alpha>160)
        bounds=im.convert('RGBA').getchannel('A').getbbox()
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        material=palettes.get(path.parent.name,{})
        reviewed_green=material.get('source_sha256')==digest and material.get('status')=='INTENDED_MATERIAL_COLOR_VISUAL_PASS'
        checks={
            'rgba':im.mode=='RGBA',
            'source_resolution':min(im.size)>=1024,
            'alpha_range':int(alpha.min())==0 and int(alpha.max())==255,
            'clean_transparent_rgb':not np.any(a[:,:,:3][alpha==0]),
            'fully_framed':bool(bounds and min(bounds[0],bounds[1],im.width-bounds[2],im.height-bounds[3])>=min(im.size)*.01),
            'subject_coverage':.025<float(visible.mean())<.85,
            'no_opaque_green_background':float(green.sum())/max(1,int(visible.sum()))<.015 or reviewed_green,
        }
        rows.append({'entity_id':path.parent.name,'path':path.relative_to(ROOT).as_posix(),'sha256':digest,'size':list(im.size),'bounds':bounds,'visible_percent':round(float(visible.mean())*100,3),'green_body_percent':round(float(green.sum())/max(1,int(visible.sum()))*100,4),'reviewed_material':material if reviewed_green else {},'checks':checks,'technical_status':'PASS' if all(checks.values()) else 'FAIL','visual_status':'REVIEW_REQUIRED'})
    sheets=[]
    for offset in range(0,len(rows),12):
        group=rows[offset:offset+12]
        sheet=Image.new('RGB',(4*320,math.ceil(len(group)/4)*340),'#14202d')
        draw=ImageDraw.Draw(sheet)
        for i,row in enumerate(group):
            x,y=i%4*320,i//4*340
            bg='#14202d' if i%2==0 else '#e9e4db'
            draw.rectangle((x,y,x+319,y+339),fill=bg)
            im=Image.open(ROOT/row['path']).convert('RGBA')
            im.thumbnail((296,290),Image.Resampling.LANCZOS)
            sheet.paste(im,(x+(320-im.width)//2,y+12+(290-im.height)//2),im)
            draw.text((x+12,y+308),row['entity_id']+' / '+row['technical_status'],font=font,fill='#6adbc8' if i%2==0 else '#14202d')
        target=out/f'candidate_sheet_{offset//12+1:02}.jpg'
        sheet.save(target,quality=94)
        sheets.append(target.relative_to(ROOT).as_posix())
    result={'status':'VISUAL_REVIEW_REQUIRED','count':len(rows),'technical_pass':sum(r['technical_status']=='PASS' for r in rows),'sheets':sheets,'assets':rows}
    (out/'candidate_technical_review.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({'count':len(rows),'technical_pass':result['technical_pass'],'failures':[r['entity_id'] for r in rows if r['technical_status']!='PASS'],'sheets':sheets}))


if __name__=='__main__':main()
