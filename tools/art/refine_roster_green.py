"""Use Sprite Gen's canonical extractor with a narrow key for green materials."""
from pathlib import Path
import json
from PIL import Image
from sprite_gen.frames.extract import remove_chroma_background

ROOT=Path(__file__).resolve().parents[2]
RUN=ROOT/'work/existing_roster_spritegen_20260911'
for entity in ['BOSS003','ENM004']:
    folder=RUN/'normalized'/entity
    image=Image.open(folder/'green_master.png')
    result=remove_chroma_background(image,(0,255,0),16,60,18,unmix_reach=1,spill_max_fraction=0)
    output=RUN/'green_material_refinement'/entity
    output.mkdir(parents=True,exist_ok=True)
    result.save(output/'source.png')
    for color,name in [('#192433','dark'),('#ece8df','light')]:
        plate=Image.new('RGBA',result.size,color)
        plate.alpha_composite(result)
        plate.thumbnail((1024,1024))
        plate.convert('RGB').save(output/(name+'.jpg'),quality=96)
    (output/'extraction.json').write_text(json.dumps({'extractor':'sprite_gen.frames.extract.remove_chroma_background','key':[0,255,0],'threshold':16,'fringe_threshold':60,'fringe_delta':18,'unmix_reach':1,'spill_max_fraction':0,'reason':'Preserve authored green energy/glass; broad default key removed interior material','review':'REQUIRED'},indent=2),encoding='utf8')
    print(entity,flush=True)
