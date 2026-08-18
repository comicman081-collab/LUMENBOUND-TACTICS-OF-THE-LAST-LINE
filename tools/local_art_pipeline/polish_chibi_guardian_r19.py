#!/usr/bin/env python3
"""R19 low-denoise Canny-locked polish of the R18 direction source."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("DIFFUSERS_OFFLINE", "1")
os.environ.setdefault("PYTHONDONTWRITEBYTECODE", "1")

import torch
from diffusers import ControlNetModel, DPMSolverMultistepScheduler, StableDiffusionXLControlNetImg2ImgPipeline
from PIL import Image, ImageFilter, ImageOps
from transformers import CLIPTokenizer


ROOT = Path(__file__).resolve().parents[2]
MODEL_POLICY = ROOT / "tools" / "local_art_pipeline" / "model_policy.json"
CONTENT_POLICY = ROOT / "tools" / "policy" / "project_content_policy.json"
SOURCE = ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r18" / "chr001_maeru_guardian_chibi_r18v02_seed171232.png"
OUTPUT = ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r19"
BASE_ID = "stabilityai-sdxl-base-1.0-local"
CANNY_ID = "diffusers-controlnet-canny-sdxl-1.0-local"
SIZE = 768

PROMPT = (
    "detailed 3D anime RPG adult woman, mature athletic 3-head chibi guardian, short rounded limbs, "
    "chestnut ponytail cyan eyes, minimal teal gold bikini armor, revealing non-explicit, opaque coverage, bare shoulders flat abdomen narrow waist hips thighs, "
    "one shield held by visible left glove gripping rim, polished metal, clean fingers, glossy cel shaded collectible game render"
)
NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, school uniform, tall body, long legs, nude, nipples, genitals, explicit, transparent fabric, bodysuit, "
    "covered abdomen, floating shield, detached shield, second shield, bars, rods, mechanical fingers, extra limbs, bad hands, text, watermark, blurry"
)


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def cli() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=2, choices=(1, 2))
    parser.add_argument("--steps", type=int, default=42)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def preflight() -> tuple[dict, dict, Path, Path]:
    content = json.loads(CONTENT_POLICY.read_text(encoding="utf-8"))
    policy = json.loads(MODEL_POLICY.read_text(encoding="utf-8"))
    cp, ap = content["character_policy"], content["appearance_policy"]
    if cp["human_and_humanoid_characters"] != "FEMALE_ONLY" or cp["age_category"] != "ADULT_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID")
    if ap["attire_exposure"] != "MAXIMUM_NON_EXPLICIT":
        raise SystemExit("ATTIRE_POLICY_INVALID")
    required = tuple(cp["required_positive_prompt_terms"]) + tuple(ap["required_positive_prompt_terms"])
    lower = PROMPT.lower()
    if not all(term.lower() in lower for term in required):
        raise SystemExit(f"CONTENT_POLICY_BLOCK: {required}")
    for term in cp["forbidden_positive_prompt_terms"]:
        if re.search(rf"(?<![a-z]){re.escape(term.lower())}(?![a-z])", lower):
            raise SystemExit(f"CONTENT_POLICY_BLOCK: {term}")
    selected = {row["id"]: row for row in policy["selected"]}
    for model_id in (BASE_ID, CANNY_ID):
        if model_id not in selected:
            raise SystemExit(f"MODEL_BLOCKED: {model_id}")
    base, canny = Path(selected[BASE_ID]["path"]).resolve(), Path(selected[CANNY_ID]["path"]).resolve()
    if "krea" in str(base).lower() or "krea" in str(canny).lower() or not (base / "model_index.json").is_file() or not (canny / "config.json").is_file():
        raise SystemExit("MODEL_BLOCKED: missing approved local model evidence")
    if not SOURCE.is_file():
        raise SystemExit(f"SOURCE_MISSING: {SOURCE}")
    return content, selected, base, canny


def edge_guide(image: Image.Image) -> Image.Image:
    gray = ImageOps.grayscale(image.filter(ImageFilter.GaussianBlur(1.1)))
    edges = ImageOps.autocontrast(gray.filter(ImageFilter.FIND_EDGES))
    edges = edges.point(lambda value: 255 if value >= 38 else 0)
    return Image.merge("RGB", (edges, edges, edges))


def main() -> int:
    cfg = cli()
    content, selected, base, canny = preflight()
    tokenizers = [CLIPTokenizer.from_pretrained(base / part, local_files_only=True) for part in ("tokenizer", "tokenizer_2")]
    for label, value in (("PROMPT", PROMPT), ("NEGATIVE", NEGATIVE)):
        lengths = [len(tok(value, truncation=False).input_ids) for tok in tokenizers]
        print(f"PROMPT_TOKENS {label} {lengths}", flush=True)
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {label} {lengths}")
    if cfg.validate_only:
        print("R19_CANNY_POLISH_POLICY_VALIDATION_OK")
        return 0
    OUTPUT.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    edges = edge_guide(source)
    edge_path = OUTPUT / "chr001_guardian_r19_canny_guide.png"
    edges.save(edge_path, format="PNG", optimize=True)
    controlnet = ControlNetModel.from_pretrained(canny, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True)
    pipe = StableDiffusionXLControlNetImg2ImgPipeline.from_pretrained(base, controlnet=controlnet, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True)
    pipe.vae.enable_slicing(); pipe.vae.enable_tiling(); pipe.enable_model_cpu_offload(gpu_id=0)
    records = []
    for revision in range(1, cfg.count + 1):
        seed = 171240 + revision
        result = pipe(prompt=PROMPT, negative_prompt=NEGATIVE, image=source, control_image=edges, width=SIZE, height=SIZE,
                      strength=0.30, guidance_scale=7.0, num_inference_steps=cfg.steps, controlnet_conditioning_scale=0.62,
                      control_guidance_start=0.0, control_guidance_end=0.85,
                      generator=torch.Generator(device="cuda").manual_seed(seed)).images[0]
        target = OUTPUT / f"chr001_maeru_guardian_chibi_r19v{revision:02d}_seed{seed}.png"
        result.save(target, format="PNG", optimize=True)
        records.append({"asset_id": f"concept_chr001_guardian_chibi_r19v{revision:02d}", "character_id": "CHR001", "character_gender": "FEMALE",
                        "age_category": "ADULT", "attire_policy": "MAXIMUM_NON_EXPLICIT", "status": "ART_QA_CANDIDATE", "production_approved": False,
                        "runtime_asset": False, "source": SOURCE.relative_to(ROOT).as_posix(), "source_sha256": sha(SOURCE),
                        "models": [BASE_ID, CANNY_ID], "model_licenses": [selected[BASE_ID]["license"], selected[CANNY_ID]["license"]],
                        "model_originals_preserved": True, "krea2_used": False, "seed": seed, "strength": 0.30,
                        "canny_guide": edge_path.relative_to(ROOT).as_posix(), "path": target.relative_to(ROOT).as_posix(),
                        "bytes": target.stat().st_size, "sha256": sha(target), "qa_verdict": "UNREVIEWED", "integration_allowed": False})
        print(f"R19_RENDERED {target}", flush=True)
    manifest = {"kind": "LOCAL_SDXL_CANNY_POLISH_CHIBI_GUARDIAN_R19", "created_utc": datetime.now(timezone.utc).isoformat(), "offline": True,
                "content_policy_version": content["policy_version"], "source_models_mutated": False, "production_approved": False, "records": records}
    manifest_path = OUTPUT / "chibi_guardian_r19_manifest.json"; manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
