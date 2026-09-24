"""Offline, project-contained SDXL monster candidates; never promotes artwork."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'work/enemy_replacement_20260911'
MODEL = Path('C:/AI_MODELS/sdxl-base-1.0')
for name in ['tmp', 'cache/huggingface', 'cache/torch', 'cache/triton', 'cache/cuda', 'candidates', 'licenses']:
    (OUT/name).mkdir(parents=True, exist_ok=True)
for key, folder in {'TEMP':'tmp', 'TMP':'tmp', 'HF_HOME':'cache/huggingface', 'TORCH_HOME':'cache/torch', 'TRITON_CACHE_DIR':'cache/triton', 'TORCHINDUCTOR_CACHE_DIR':'cache/torch', 'CUDA_CACHE_PATH':'cache/cuda', 'XDG_CACHE_HOME':'cache', 'MPLCONFIGDIR':'cache'}.items():
    os.environ[key] = str(OUT/folder)
os.environ.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', DIFFUSERS_OFFLINE='1', PYTHONDONTWRITEBYTECODE='1', TOKENIZERS_PARALLELISM='false')

DESIGNS = {
 'ENM011':'floating crystalline beetle drone, cobalt glass wings, ivory segmented shell, red camera lens, thin antennae',
 'ENM012':'armored crustacean sentinel, silver interlocking shield plates, purple reactor, broad claw shields, low heavy body',
 'ENM013':'twin pronged electrical mantis drone, black ceramic armor, red magnetic coils, sharp articulated legs',
 'ENM014':'heavy artillery scorpion robot, bronze plated body, huge raised cannon tail, six steel legs, orange reactor',
 'ENM015':'floating mechanical jellyfish, purple cathedral bell shell, silver resonator tubes, curled metal tentacles',
 'ENM016':'predatory glass wolf automaton, translucent cobalt armor, ivory metal skeleton, serrated fangs, four clawed legs',
 'ENM017':'prism turret crab, sapphire crystal barrel, silver rounded armor, four stabilizer legs, purple lens',
 'ENM018':'colossal mirror tortoise, overlapping silver mirror shields, blue crystalline shell, heavy mechanical claws',
 'ENM019':'deep sea anglerfish machine, dark blue armored scales, orange lure, sharp steel teeth, fin thrusters',
 'ENM020':'amphibious mortar toad robot, corroded bronze shell, enormous dorsal mortar barrel, squat articulated limbs',
 'ENM021':'nautilus repair automaton, spiral ivory shell, red medical reactor, elegant metal tendrils, broad brass claws',
 'ENM022':'burning mechanical jackal, black segmented armor, ember orange seams, taloned feet, long bladed tail',
 'ENM023':'cinder hornet drone, black steel carapace, orange reactor abdomen, twin rifle mandibles, pointed metallic wings',
 'ENM024':'smoke furnace rhinoceros robot, massive black iron armor, red furnace core, bronze horns, heavy hooves',
 'ENM025':'lightning raptor machine, indigo feather blades, silver hooked beak, blue electrical coils, taloned legs',
 'ENM026':'thunder eye drone, circular gold gimbal, large sapphire lens, four white lightning fins, intricate cables',
 'ENM027':'bridge anchor guardian crab, giant steel anchor claws, navy armor, copper chains, squat armored legs',
 'ENM028':'snow lynx automaton, white ceramic armor, cobalt joints, blade ears, crystal claws, four stalking legs',
 'ENM029':'ice relay moth drone, six symmetrical sapphire crystal wings, white mechanical body, orange sensor eye',
 'ENM030':'arctic shield mammoth robot, ivory armor plates, curved steel tusks, blue core, broad mechanical feet',
 'ENM031':'quarry cutter mole machine, copper drill snout, dark iron shell, enormous excavator claws, orange lamps',
 'ENM032':'magma artillery salamander, obsidian armor, orange molten reactor, dorsal cannon, four heavy clawed feet',
 'ENM033':'ore bastion armadillo automaton, layered iron shell, ruby ore spikes, thick bronze limbs, glowing red seams',
 'ENM034':'dream prowler mechanical panther, midnight purple armor, crescent silver blades, violet eye, sleek stalking legs',
 'ENM035':'sleep needle wasp automaton, violet glass abdomen, elongated silver syringe stinger, delicate steel wings',
 'ENM036':'archive guard owl machine, bronze armor, booklike layered wings, ivory mask, purple clockwork eyes',
 'ENM037':'moon skirmisher silver fox automaton, crescent blade tail, navy body, blue crystal paws, long pointed ears',
 'ENM038':'tidal sniper mechanical seahorse, ivory spiral armor, long blue railgun snout, bronze fins, curled tail',
 'ENM039':'eclipse ward stag beetle robot, black and gold armored shell, giant crescent mandibles, purple core',
 'ENM040':'surge runner mechanical shark, navy steel body, red sensor eyes, blade fins, four articulated crawler legs',
 'ENM041':'brine cannon lobster machine, blue bronze segmented armor, oversized cannon claw, reinforced tail, six legs',
 'ENM042':'breakwater guardian turtle, white battleship shell, bronze wavebreaker spikes, blue reactor, massive clawed limbs',
 'BOSS004':'towering gatekeeper quadruped machine, two enormous black gold gate shields, purple reactor, broad bladed legs, menacing ornate silhouette',
 'BOSS005':'floating formation core leviathan, black bronze central reactor, six articulated blade arms, red orbital machinery, intricate armored shell',
 'BOSS006':'gigantic glass dragon automaton, sapphire crystal armor, white steel horns, broad mechanical wings, heavy four clawed legs',
 'BOSS007':'colossal tidal octopus engine, navy brass diving bell body, many armored tentacles, orange porthole reactor, enormous mechanical claws',
 'BOSS008':'ash citadel walking fortress beetle, black iron furnace shell, bronze battlements, red molten vents, six massive spiked legs',
 'BOSS009':'volt archon thunderbird automaton, gold silver armor, enormous cobalt blade wings, hooked beak, electrical reactor chest',
 'BOSS010':'frost cantor mechanical ice dragon, ivory armor, sapphire crystal horns, broad bladed wings, huge clawed feet',
 'BOSS011':'scarlet excavator colossal scorpion, black red mining armor, huge drill claws, crane cannon tail, heavy steel legs',
 'BOSS012':'dream bailiff mechanical sphinx beast, deep purple armor, bronze clockwork wings, ivory lion mask, four massive paws',
 'BOSS013':'lunar divider mechanical mantis, silver moon blade forearms, black armored abdomen, blue core, four towering support legs',
 'BOSS014':'tide reaper mechanical kraken, blue iron carapace, enormous curved silver claws, bronze tentacles, red beacon eye',
 'BOSS015':'nameless prelate cathedral spider machine, tall ivory bell shell, violet reactor windows, gold spikes, eight armored legs',
 'BOSS016':'dune stationmaster colossal sandworm machine, bronze segmented armor, circular drill maw, black steel fins, glowing orange eye',
 'BOSS017':'gravity auditor floating mechanical whale, black silver armor, purple singularity engine, heavy orbital fins, imposing broad silhouette',
 'BOSS018':'null gardener mechanical carnivorous flower, black ceramic petals, magenta crystal heart, silver thorn arms, thick rooted steel legs',
 'BOSS019':'crown lancer mechanical lion, gold crowned armored mane, crimson reactor, massive steel blade claws, broad muscular quadruped body',
 'BOSS020':'index predator mechanical centipede, navy ivory armored segments, orange sensor arrays, huge jaw blades, many steel claws',
 'BOSS021':'doom signaler mechanical raven, black bronze armor, red beacon crown, huge blade wings, powerful clawed landing legs',
 'BOSS022':'eternal ticket clockwork serpent, ivory gold locomotive head, violet reactor, coiled articulated black steel body, bladed fins',
 'BOSS023':'last line warden colossal mechanical dragon, black gold cathedral armor, crimson heart reactor, huge silver wings, four massive clawed legs',
}


def sha(path):
    with path.open('rb') as stream:
        digest=hashlib.sha256()
        while chunk:=stream.read(1024*1024):digest.update(chunk)
        return digest.hexdigest()


def license_gate():
    license_path = MODEL/'LICENSE.md'
    text = license_path.read_text(encoding='utf8')
    assert 'CreativeML Open RAIL++-M' in text and 'offer to sell, sell' in text
    assert 'Licensor claims no rights in the Output' in text
    (OUT/'licenses/SDXL_LICENSE.md').write_text(text, encoding='utf8')
    (OUT/'licenses/SDXL_MODEL_CARD.md').write_text((MODEL/'README.md').read_text(encoding='utf8'), encoding='utf8')
    runtime_license = Path('C:/AI_ENVS/SDXL_TRAINER/venv/Lib/site-packages/diffusers-0.32.1.dist-info/LICENSE')
    runtime_text = runtime_license.read_text(encoding='utf8')
    assert 'Apache License' in runtime_text and 'Grant of Copyright License' in runtime_text
    (OUT/'licenses/DIFFUSERS_LICENSE').write_text(runtime_text, encoding='utf8')
    weights = [MODEL/p for p in ['unet/diffusion_pytorch_model.fp16.safetensors', 'vae/diffusion_pytorch_model.fp16.safetensors', 'text_encoder/model.fp16.safetensors', 'text_encoder_2/model.fp16.safetensors']]
    records=[]
    for p in weights:
        metadata=MODEL/'.cache/huggingface/download'/(p.relative_to(MODEL).as_posix()+'.metadata')
        original=metadata.read_text(encoding='utf8').splitlines()[1]
        digest=sha(p)
        if digest!=original:
            digest=sha(p)
        if digest!=original:raise ValueError('Installed weight does not match its original download: '+str(p))
        records.append({'path':str(p),'sha256':digest,'original_download_sha256':original,'download_metadata':str(metadata),'bytes':p.stat().st_size,'mtime_ns':p.stat().st_mtime_ns})
    report = {'status':'LICENSE_GATE_PASS', 'model':'stabilityai/stable-diffusion-xl-base-1.0', 'license':'CreativeML Open RAIL++-M', 'evidence':str(license_path), 'evidence_sha256':sha(license_path), 'model_card':str(MODEL/'README.md'), 'commercial_use':'Permitted for original fictional nonhuman game creature illustrations; reviewed Sections II, III and Attachment A.', 'components':'Official bundled UNet, VAE, CLIP and OpenCLIP text encoders; no auxiliary model, LoRA, adapter or ControlNet.', 'runtime':'Installed Diffusers 0.32.1; Apache-2.0 license copied and reviewed.', 'immutable_inputs':True, 'offline':True, 'output_root':str(OUT), 'weights':records}
    (OUT/'model-license-manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    return records


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--ids',default='ENM011,ENM014,BOSS004'); parser.add_argument('--attempt',type=int,default=1); parser.add_argument('--steps',type=int,default=30)
    args=parser.parse_args(); ids=args.ids.split(',') if args.ids!='all' else list(DESIGNS)
    assert all(i in DESIGNS for i in ids)
    records=license_gate(); print('LICENSE_GATE_PASS',flush=True)
    import torch
    from diffusers import StableDiffusionXLPipeline, DPMSolverMultistepScheduler
    pipe=StableDiffusionXLPipeline.from_pretrained(str(MODEL),variant='fp16',torch_dtype=torch.float16,use_safetensors=True,local_files_only=True,add_watermarker=False)
    pipe.scheduler=DPMSolverMultistepScheduler.from_config(pipe.scheduler.config,use_karras_sigmas=True)
    pipe.enable_model_cpu_offload(); pipe.enable_vae_slicing(); pipe.set_progress_bar_config(disable=True)
    prefix='Bright green background, solid green background, isolated full body monster facing left, centered with margin. '
    suffix='. Painted anime RPG sprite, detailed layered armor, sharp silhouette. Plain bright green background, chroma key.'
    negative='gray background, white background, purple background, blue background, gradient background, scenery, floor, platform, ground shadow, human, person, humanoid, face portrait, cute, toy, lego, cube, pixel art, low poly, simple shapes, sketch, flat icon, text, letters, logo, watermark, border, multiple creatures, collage, cropped body, cut off legs, blurry, low resolution'
    for entity in ids:
        path=OUT/'candidates'/f'{entity}_r{args.attempt}.png'
        if path.exists():print('EXISTS',entity,flush=True);continue
        prompt=prefix+DESIGNS[entity]+suffix
        seed=2026091100+int(hashlib.sha256(entity.encode()).hexdigest()[:6],16)+args.attempt*1009
        started=time.monotonic()
        result=pipe(prompt=prompt,negative_prompt=negative,height=1024,width=1024,num_inference_steps=args.steps,guidance_scale=6.5,generator=torch.Generator('cpu').manual_seed(seed)).images[0]
        result.save(path)
        row={'status':'REVIEW_REQUIRED_NOT_RUNTIME','entity_id':entity,'prompt':prompt,'negative_prompt':negative,'seed':seed,'steps':args.steps,'model_license_manifest':'../model-license-manifest.json','path':str(path),'sha256':sha(path),'seconds':round(time.monotonic()-started,2)}
        path.with_suffix('.json').write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf8')
        print('CANDIDATE_READY',entity,row['seconds'],str(path),flush=True)
    for row in records:
        p=Path(row['path']);assert p.stat().st_mtime_ns==row['mtime_ns'] and sha(p)==row['sha256']
    print('IMMUTABLE_MODEL_INPUTS_PASS',flush=True)


if __name__=='__main__':main()
