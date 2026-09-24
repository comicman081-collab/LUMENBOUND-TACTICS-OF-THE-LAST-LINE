"""Retain green masters and use Sprite Gen's canonical imported-image cutout.

Run with the installed Sprite Gen interpreter. Some GPT outputs already carry
alpha despite a green request; those are explicitly composited onto green before
keying, instead of accidentally keying their invisible RGB as creature colours.
"""
from pathlib import Path
import hashlib
import json
import argparse
from PIL import Image
from sprite_gen.frames.cutout import cutout

ROOT=Path(__file__).resolve().parents[2]
RUN=ROOT/'work/enemy_replacement_20260911'


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--run-name',default='enemy_replacement_20260911');args=parser.parse_args()
    run=(ROOT/'work'/args.run_name).resolve()
    assert run.is_relative_to((ROOT/'work').resolve())
    for report in sorted((run/'gpt_candidates').glob('*.report.json')):
        entity=report.name.split('.')[0]
        target=run/'normalized'/entity
        if (target/'normalization.json').exists():continue
        raw=run/'gpt_candidates'/f'{entity}.png.raw.png'
        original=Image.open(raw)
        has_alpha='A' in original.getbands() and original.getchannel('A').getextrema()[0]<255
        target.mkdir(parents=True,exist_ok=True)
        master=Image.new('RGBA',(original.width+128,original.height+128),(0,255,0,255))
        if has_alpha:master.alpha_composite(original.convert('RGBA'),(64,64))
        else:master.paste(original.convert('RGBA'),(64,64))
        master.convert('RGB').save(target/'green_master.png')
        stats=cutout(target/'green_master.png',target/'source.png',key='green')
        record={'entity_id':entity,'raw':raw.relative_to(ROOT).as_posix(),'raw_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),'raw_had_generated_alpha':has_alpha,'green_master':'green_master.png','master_method':'Generated artwork composited without resizing onto uniform green with 64px safety border; raw preserved unchanged.','extractor':'sprite_gen.frames.cutout.cutout key=green; canonical Sprite Gen tool, no replacement extractor','stats':stats,'status':'VISUAL_REVIEW_REQUIRED'}
        (target/'normalization.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
        print(entity, 'native-alpha-to-green' if has_alpha else 'green-source',flush=True)


if __name__=='__main__':main()
