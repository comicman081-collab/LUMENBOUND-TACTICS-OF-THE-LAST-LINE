"""Offline headquarters illustration using the already verified commercial SDXL stack."""
from pathlib import Path
import os,json,hashlib,shutil
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'work/headquarters_illustration_r1'
for name in ['tmp','cache/huggingface','cache/torch','cache/triton','candidates','licenses']:(OUT/name).mkdir(parents=True,exist_ok=True)
for key,value in {'TEMP':'tmp','TMP':'tmp','HF_HOME':'cache/huggingface','TORCH_HOME':'cache/torch','TRITON_CACHE_DIR':'cache/triton','XDG_CACHE_HOME':'cache'}.items():os.environ[key]=str(OUT/value)
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',PYTHONDONTWRITEBYTECODE='1')
PACK=Path('C:/AI_MODELS/FALSE_SUMMER_COMMERCIAL_SDXL_V3')
MODEL=PACK/'animagine-xl-4.0-opt/animagine-xl-4.0-opt.safetensors'
CONFIG=PACK/'hf_cache/models--cagliostrolab--animagine-xl-4.0/snapshots/2b7c1b397761bf5bd3cc42e5b39ec99314a75a96'
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
    return h.hexdigest()
evidence=[Path('C:/AI_MODELS/sdxl-base-1.0/LICENSE.md'),Path('D:/AI 종합 폴더/Games/비쥬얼 노벨/FALSE_SUMMER_GAME/docs/art/licenses/animagine-xl-4.0_README.md')]
manifest=json.loads((ROOT/'quarantine/down_pose_local_20260911/down_pose_r7/model-license-manifest.json').read_text(encoding='utf-8'))
records=[r for r in manifest['models'] if Path(r['local_path'])==MODEL]
assert len(records)==1 and sha(MODEL)==records[0]['verified_sha256']
for p in evidence:shutil.copy2(p,OUT/'licenses'/p.name)
(OUT/'model-license-manifest.json').write_text(json.dumps({'status':'REVIEW_REQUIRED','models':records,'evidence':[{'source':str(p),'sha256':sha(p)} for p in evidence],'license':'CreativeML Open RAIL++-M permits commercial use; bundled SDXL text encoders and VAE','purpose':'Original Lanternline headquarters background','immutable_inputs':True,'offline':True},indent=2),encoding='utf-8')
import torch
from diffusers import StableDiffusionXLPipeline,EulerAncestralDiscreteScheduler
pipe=StableDiffusionXLPipeline.from_single_file(str(MODEL),config=str(CONFIG),local_files_only=True,torch_dtype=torch.float16,add_watermarker=False)
pipe.scheduler=EulerAncestralDiscreteScheduler.from_config(pipe.scheduler.config)
pipe.enable_model_cpu_offload();pipe.enable_vae_slicing()
prompt='scenery, no humans, isometric view, aerial view, panoramic wide view of a complete beautiful fantasy military outpost, central monumental teal crystal beacon tower, white stone and dark teal metal buildings with gold brass trim, terraced platforms, small hangars and command buildings connected by stone walkways and railway bridges, lush green trees, distant mountains and clouds, waterfall flowing down cliff edge, warm afternoon sunlight, luminous turquoise crystal technology, brass lanterns, sophisticated anime tactical RPG headquarters environment illustration, clean readable building silhouettes, architectural concept art, rich detailed buildings, depth and atmospheric perspective, painterly anime background, masterpiece, best quality, very aesthetic, absurdres'
negative='text, letters, watermark, logo, UI, interface, people, characters, low poly, simple geometry, cubes, rough sketch, low detail, blurry, gloomy, oversaturated, clutter, cropped building, photorealistic, fisheye'
for i in range(2):
    target=OUT/'candidates'/f'headquarters_{i+1:02d}.png'
    if target.exists():raise RuntimeError('No overwrite of reviewed candidate')
    seed=2026091120+i
    image=pipe(prompt=prompt,negative_prompt=negative,width=1344,height=768,num_inference_steps=36,guidance_scale=6.5,generator=torch.Generator('cpu').manual_seed(seed)).images[0]
    image.save(target)
    target.with_suffix('.json').write_text(json.dumps({'status':'REVIEW_REQUIRED','prompt':prompt,'negative':negative,'seed':seed,'sha256':sha(target)},indent=2),encoding='utf-8')
    print('CANDIDATE_READY',str(target),flush=True)
assert sha(MODEL)==records[0]['verified_sha256']
print('IMMUTABLE_INPUT_GATE_PASS',flush=True)
