"""Project-local SDXL pose candidates; never writes installed models/runtimes."""
from pathlib import Path
import os, json, hashlib, argparse
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'work/down_pose_r1'
for name in ['tmp','cache/huggingface','cache/torch','cache/triton','candidates']:
    (OUT/name).mkdir(parents=True,exist_ok=True)
for key,value in {'TEMP':'tmp','TMP':'tmp','HF_HOME':'cache/huggingface','TORCH_HOME':'cache/torch','TRITON_CACHE_DIR':'cache/triton','XDG_CACHE_HOME':'cache'}.items():
    os.environ[key]=str(OUT/value)
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',PYTHONDONTWRITEBYTECODE='1')
MODEL=Path('C:/AI_MODELS/sdxl-base-1.0')
license_text=(MODEL/'LICENSE.md').read_text(encoding='utf-8')
assert 'royalty-free' in license_text and 'Licensor claims no rights in the Output' in license_text
manifest={'purpose':'Commercial original game character pose candidate, local review required',
 'status':'LOCAL_CANDIDATES_ONLY_UNTIL_VISUAL_REVIEW', 'models':[{
 'root':str(MODEL),'license':'CreativeML Open RAIL++-M (2023-07-26)',
 'evidence':str(MODEL/'LICENSE.md'),'evidence_sha256':hashlib.sha256(license_text.encode()).hexdigest(),
 'scope':'SDXL base bundled UNet, VAE, two text encoders and tokenizers',
 'permission':'Section II royalty-free copyright/patent grants; Section III output rights retained by user; intended adult fictional game art is outside prohibited uses.'}],
 'excluded':['OpenPose SDXL: bundled model card refers to commercially restricted OpenPose license','IP-Adapter: auxiliary vision-encoder license not locally established','Krea2: prohibited'],
 'immutable_inputs':True,'offline':True,'outputs_and_caches':str(OUT)}
(OUT/'model-license-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')

import torch
from diffusers import StableDiffusionXLImg2ImgPipeline, DPMSolverMultistepScheduler
from PIL import Image
import numpy as np

parser=argparse.ArgumentParser();parser.add_argument('--id',default='CHR001');args=parser.parse_args()
cid=args.id
root=ROOT/'godot/assets/runtime_web/full_density/r2'/cid
metadata=json.loads((root/'animation_manifest.json').read_text(encoding='utf-8'))
source_root=ROOT/'godot'/metadata['source_root']
source_path=next(iter(sorted((source_root/'idle').glob('*.png'))),ROOT/'godot/assets/runtime_web/combat'/cid/'preview.png')
source=Image.open(source_path).convert('RGBA')
source=source.crop(source.getchannel('A').getbbox())
# A temporary pose initializer from this character alone. The neural pass must
# redraw folded limbs and ground contact; this rotation is never a runtime asset.
guide=source.rotate(-90,expand=True,resample=Image.Resampling.BICUBIC)
guide.thumbnail((850,430),Image.Resampling.LANCZOS)
canvas=Image.new('RGB',(1024,1024),(0,255,0));canvas.paste(guide,((1024-guide.width)//2,610-guide.height//2),guide)
canvas.save(OUT/'candidates'/f'{cid}_pose_initializer.png')
traits={'CHR001':'long flowing turquoise hair, turquoise eyes, ornate teal white and gold armored dress, teal gold shield and lantern, Maeru guardian',
 'CHR002':'long red ponytail hair, red and black angular armor, crimson greatsword, Roan swordswoman',
 'CHR003':'long pale ice blue ponytail, blue black and silver tactical armor, long sniper rifle, Narin sniper',
 'CHR004':'deep purple high ponytail, purple eyes, black violet tactical armor, compact purple energy carbine, Eda assault',
 'CHR005':'long honey blonde ponytail, green eyes, black gold olive tactical armor, heavy gold rotary firearm, Soren heavy gunner',
 'CHR008':'short salmon pink hair, teal white medical jacket and combat shorts, white teal medical drone, Iri medic'}
prompt='A single adult woman anime tactical RPG battle sprite, '+traits.get(cid,'fantasy armored female soldier')+'. Fully collapsed unconscious lying FACE DOWN on her stomach, horizontal body resting on ground, cheek resting on folded forearms, eyes CLOSED, chest and hips down, knees bent slightly, legs extended behind, relaxed empty hands, her weapon lying flat beside her. Entire body fully visible, detailed mature anime face, 3.5 head proportions, crisp detailed painted game illustration, preserve the reference costume and colors, flat uniform bright green background, no environment, no shadow.'
negative='standing, upright, sitting, floating, flying, reclining on back, open eyes, ready to attack, aiming, duplicate person, extra arms, extra legs, child, baby, nude, nudity, lingerie, text, logo, scenery, ground texture, gradient, cast shadow, cropped body, monochrome, blur, photorealistic'
pipe=StableDiffusionXLImg2ImgPipeline.from_pretrained(str(MODEL),variant='fp16',torch_dtype=torch.float16,local_files_only=True,use_safetensors=True,add_watermarker=False)
pipe.scheduler=DPMSolverMultistepScheduler.from_config(pipe.scheduler.config,use_karras_sigmas=True)
pipe.enable_model_cpu_offload();pipe.enable_vae_slicing()
image=pipe(prompt=prompt,negative_prompt=negative,image=canvas,strength=.82,num_inference_steps=36,guidance_scale=7.0,generator=torch.Generator('cpu').manual_seed(2026091101)).images[0]
path=OUT/'candidates'/f'{cid}_prone_candidate.png';image.save(path)
(OUT/'candidates'/f'{cid}_provenance.json').write_text(json.dumps({'id':cid,'status':'REVIEW_REQUIRED','source':str(source_path),'source_sha256':hashlib.sha256(source_path.read_bytes()).hexdigest(),'prompt':prompt,'seed':2026091101,'candidate_sha256':hashlib.sha256(path.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
print('CANDIDATE_READY',path,flush=True)
