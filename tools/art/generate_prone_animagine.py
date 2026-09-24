"""Offline pose candidates from licensed immutable weights and current cast art."""
from pathlib import Path
import os, json, hashlib, argparse, shutil
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'work/down_pose_r6'
for name in ['tmp','cache/huggingface','cache/torch','cache/triton','candidates','licenses']:
    (OUT/name).mkdir(parents=True,exist_ok=True)
for key,value in {'TEMP':'tmp','TMP':'tmp','HF_HOME':'cache/huggingface','TORCH_HOME':'cache/torch','TRITON_CACHE_DIR':'cache/triton','XDG_CACHE_HOME':'cache'}.items():
    os.environ[key]=str(OUT/value)
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',PYTHONDONTWRITEBYTECODE='1')
PACK=Path('C:/AI_MODELS/FALSE_SUMMER_COMMERCIAL_SDXL_V3')
MODEL=PACK/'animagine-xl-4.0-opt/animagine-xl-4.0-opt.safetensors'
CONFIG=PACK/'hf_cache/models--cagliostrolab--animagine-xl-4.0/snapshots/2b7c1b397761bf5bd3cc42e5b39ec99314a75a96'
LICENSES=[Path('C:/AI_MODELS/sdxl-base-1.0/LICENSE.md'),Path('C:/AI_MODELS/_codex_setup/official_runtime_sources/IP-Adapter/LICENSE'),Path('D:/AI 종합 폴더/Games/비쥬얼 노벨/FALSE_SUMMER_GAME/docs/art/licenses/animagine-xl-4.0_README.md')]
for file in LICENSES: shutil.copy2(file,OUT/'licenses'/file.name)
def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for part in iter(lambda:f.read(8*1024*1024),b''): h.update(part)
    return h.hexdigest()
installed=json.loads((PACK/'manifests/installed_models.json').read_text(encoding='utf-8-sig'))
records=[]
for model in installed['models']:
    if model['role'] in ['image_encoder_config','ip_adapter_plus_sdxl']: continue
    file=Path(model['local_path']); digest=sha(file)
    assert digest==model['sha256'] and model['commercial_use'].startswith('permitted')
    records.append({**model,'verified_sha256':digest,'source_mtime_ns':file.stat().st_mtime_ns})
adapter=Path('C:/AI_MODELS/ip-adapter/sdxl_models/ip-adapter_sdxl.safetensors')
metadata_path=Path('C:/AI_MODELS/ip-adapter/.cache/huggingface/download/sdxl_models/ip-adapter_sdxl.safetensors.metadata')
metadata_lines=metadata_path.read_text().splitlines()
assert sha(adapter)==metadata_lines[1]
records.append({'role':'ip_adapter_sdxl_bigG','local_path':str(adapter),'verified_sha256':sha(adapter),'source_mtime_ns':adapter.stat().st_mtime_ns,'license':'Apache-2.0','evidence':str(LICENSES[1]),'source_repo':'h94/IP-Adapter','source_revision':metadata_lines[0],'source_path':'sdxl_models/ip-adapter_sdxl.safetensors','compatibility':'Original SDXL adapter uses licensed bundled bigG encoder (1664 hidden, 1280 projection), not Plus/ViT-H.'})
manifest={'status':'REVIEW_REQUIRED_NOT_RUNTIME','purpose':'Original adult tactical game cast prone battle poses','models':records,'evidence':[{'source':str(p),'sha256':sha(p)} for p in LICENSES],'scope':'Animagine bundled SDXL UNet/VAE/text encoders; h94 original IP-Adapter SDXL and its bundled bigG image encoder; SDXL config/tokenizers. RAIL++ permits commercial use; Apache-2.0 code/model grant. Excludes FaceID, OpenPose, Krea2.','immutable_inputs':True,'offline':True,'output_root':str(OUT)}
(OUT/'model-license-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('LICENSE_AND_HASH_GATE_PASS',flush=True)

import torch
from PIL import Image
from diffusers import StableDiffusionXLImg2ImgPipeline, EulerAncestralDiscreteScheduler
from transformers import CLIPImageProcessor, CLIPVisionModelWithProjection
parser=argparse.ArgumentParser();parser.add_argument('--id',default='CHR001');parser.add_argument('--count',type=int,default=2);args=parser.parse_args()
cid=args.id
metadata=json.loads((ROOT/f'godot/assets/runtime_web/full_density/r2/{cid}/animation_manifest.json').read_text(encoding='utf-8'))
source_path=next(iter(sorted((ROOT/'godot'/metadata['source_root']/'idle').glob('*.png'))))
source_path=ROOT/f'godot/assets/runtime_web/characters/{cid}_card_384x576.png'
source=Image.open(source_path).convert('RGBA');source=source.crop(source.getchannel('A').getbbox())
reference=Image.new('RGB',source.size,(0,255,0));reference.paste(source,(0,0),source)
reference.save(OUT/'candidates'/f'{cid}_reference.png')
traits={'CHR001':'turquoise hair, long hair, ponytail, gold tiara, teal white gold armor, armored dress, teal gold shield',
 'CHR002':'red hair, long ponytail, black crimson armor, red greatsword',
 'CHR003':'ice blue hair, long ponytail, black silver blue tactical armor, sniper rifle',
 'CHR004':'purple hair, high ponytail, black violet tactical armor, carbine',
 'CHR005':'blonde hair, long ponytail, black gold olive tactical armor, heavy machine gun',
 'CHR008':'pink short hair, white teal jacket, black combat shorts, white teal medical equipment'}
prompt='1girl, solo, adult woman, rating:general, full body, entire boots and hands visible, isolated on pure green, '+traits.get(cid,'fantasy armored soldier')+', mature face, small head, full body, lying, on stomach, prone, face down, closed eyes, exhausted, head resting on arms, legs extended, side view, horizontal composition, weapon on ground, flat green background, simple green background, finely painted tactical RPG illustration, intricate costume, thin lineart, soft shading, detailed armor, masterpiece, high score, great score, absurdres'
negative='white background, gray background, thick outlines, oversaturated, chibi, giant head, simplified costume, flat cel shading, lowres, worst quality, low quality, bad anatomy, standing, sitting, kneeling, on back, upright torso, open eyes, looking at viewer, holding weapon, attacking, flying, floating, extra limbs, missing legs, cropped, nude, naked, bikini, child, baby, toddler, loli, text, logo, watermark, multiple views, scenery, shadow, gradient'
pipe=StableDiffusionXLImg2ImgPipeline.from_single_file(str(MODEL),config=str(CONFIG),local_files_only=True,torch_dtype=torch.float16,add_watermarker=False)
pipe.scheduler=EulerAncestralDiscreteScheduler.from_config(pipe.scheduler.config)
encoder=CLIPVisionModelWithProjection.from_pretrained(str(PACK/'image_encoder'),local_files_only=True,torch_dtype=torch.float16)
pipe.register_modules(image_encoder=encoder,feature_extractor=CLIPImageProcessor())
pipe.load_ip_adapter(str(adapter.parent),subfolder='',weight_name=adapter.name,image_encoder_folder=None,local_files_only=True)
pipe.enable_model_cpu_offload();pipe.enable_vae_slicing()
import numpy as np
import cv2
pose=Image.open(ROOT/'work/down_pose_r4/candidates/CHR001_prone_02.png').convert('RGB')
a=np.array(pose);hsv=cv2.cvtColor(a,cv2.COLOR_RGB2HSV)
bg=((hsv[:,:,1]<55)&(hsv[:,:,2]>170)).astype('uint8')
_,components=cv2.connectedComponents(bg,connectivity=8)
edge_ids=np.unique(np.concatenate([components[0],components[-1],components[:,0],components[:,-1]]));edge_ids=edge_ids[edge_ids!=0]
alpha=(~np.isin(components,edge_ids)).astype('uint8')*255
rgba=Image.fromarray(np.dstack([a,alpha]));rgba=rgba.crop(rgba.getchannel('A').getbbox());rgba.thumbnail((1020,400),Image.Resampling.LANCZOS)
guide=Image.new('RGB',(1216,832),(0,255,0));guide.paste(rgba,((1216-rgba.width)//2,(832-rgba.height)//2),rgba);guide.save(OUT/'candidates'/f'{cid}_pose_guide.png')
for i in range(args.count):
    scale=[.55,.65][i%2];seed=2026091101+i
    pipe.set_ip_adapter_scale(scale)
    image=pipe(prompt=prompt,negative_prompt=negative,ip_adapter_image=reference,image=guide,strength=[.55,.70][i%2],num_inference_steps=32,guidance_scale=6.0,generator=torch.Generator('cpu').manual_seed(seed)).images[0]
    path=OUT/'candidates'/f'{cid}_prone_{i+1:02d}.png'
    if path.exists(): raise RuntimeError('Refusing to overwrite reviewed candidate')
    image.save(path)
    path.with_suffix('.json').write_text(json.dumps({'status':'REVIEW_REQUIRED','id':cid,'reference':str(source_path),'reference_sha256':sha(source_path),'prompt':prompt,'negative':negative,'ip_scale':scale,'seed':seed,'output_sha256':sha(path)},indent=2),encoding='utf-8')
    print('CANDIDATE_READY',str(path),flush=True)
for model in records:
    file=Path(model['local_path'])
    assert file.stat().st_mtime_ns==model['source_mtime_ns'] and sha(file)==model['verified_sha256']
print('IMMUTABLE_INPUT_GATE_PASS',flush=True)
