#!/usr/bin/env python3
"""R20 final local micro-inpaint for an organic shield gauntlet."""
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
from diffusers import DPMSolverMultistepScheduler, StableDiffusionXLInpaintPipeline
from PIL import Image, ImageDraw, ImageFilter
from transformers import CLIPTokenizer


ROOT = Path(__file__).resolve().parents[2]
MODEL_POLICY = ROOT / "tools" / "local_art_pipeline" / "model_policy.json"
CONTENT_POLICY = ROOT / "tools" / "policy" / "project_content_policy.json"
SOURCE = ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r19" / "chr001_maeru_guardian_chibi_r19v02_seed171242.png"
OUTPUT = ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r20"
MODEL_ID = "diffusers-sdxl-inpaint-0.1-local"
SIZE = 768
PROMPT = (
    "premium polished 3D anime RPG adult woman, mature 3-head chibi guardian, natural compact teal armored left gauntlet clasping gold shield rim, "
    "palm overlapping rim, fingers curled behind shield, one visible thumb on front, connected wrist and forearm, one held shield, "
    "revealing non-explicit minimal bikini armor, opaque coverage, glossy cel shaded collectible game model"
)
NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, floating shield, detached shield, gap, bars, rods, mechanical fingers, finger ladder, "
    "missing hand, extra fingers, extra arm, second shield, wing, wings, broken wrist, text, watermark, blurry"
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
    parser.add_argument("--steps", type=int, default=40)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def preflight() -> tuple[dict, dict, Path]:
    content = json.loads(CONTENT_POLICY.read_text(encoding="utf-8"))
    policy = json.loads(MODEL_POLICY.read_text(encoding="utf-8"))
    cp, ap = content["character_policy"], content["appearance_policy"]
    if cp["human_and_humanoid_characters"] != "FEMALE_ONLY" or cp["age_category"] != "ADULT_ONLY" or ap["attire_exposure"] != "MAXIMUM_NON_EXPLICIT":
        raise SystemExit("CONTENT_POLICY_INVALID")
    required = tuple(cp["required_positive_prompt_terms"]) + tuple(ap["required_positive_prompt_terms"])
    lower = PROMPT.lower()
    if not all(term.lower() in lower for term in required):
        raise SystemExit(f"CONTENT_POLICY_BLOCK: {required}")
    for term in cp["forbidden_positive_prompt_terms"]:
        if re.search(rf"(?<![a-z]){re.escape(term.lower())}(?![a-z])", lower):
            raise SystemExit(f"CONTENT_POLICY_BLOCK: {term}")
    selected = {row["id"]: row for row in policy["selected"]}
    if MODEL_ID not in selected:
        raise SystemExit(f"MODEL_BLOCKED: {MODEL_ID}")
    model = Path(selected[MODEL_ID]["path"]).resolve()
    if "krea" in str(model).lower() or not (model / "model_index.json").is_file():
        raise SystemExit(f"MODEL_BLOCKED: {model}")
    if not SOURCE.is_file():
        raise SystemExit(f"SOURCE_MISSING: {SOURCE}")
    return content, selected, model


def main() -> int:
    cfg = cli()
    content, selected, model = preflight()
    tokenizers = [CLIPTokenizer.from_pretrained(model / part, local_files_only=True) for part in ("tokenizer", "tokenizer_2")]
    for label, value in (("PROMPT", PROMPT), ("NEGATIVE", NEGATIVE)):
        lengths = [len(tok(value, truncation=False).input_ids) for tok in tokenizers]
        print(f"PROMPT_TOKENS {label} {lengths}", flush=True)
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {label} {lengths}")
    if cfg.validate_only:
        print("R20_GAUNTLET_POLICY_VALIDATION_OK")
        return 0
    OUTPUT.mkdir(parents=True, exist_ok=True)
    guide = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(guide)
    teal, gold = (15, 142, 150), (237, 176, 39)
    draw.rounded_rectangle((289, 382, 322, 444), radius=14, fill=teal, outline=gold, width=4)
    draw.ellipse((278, 396, 306, 430), fill=teal, outline=gold, width=3)
    draw.rounded_rectangle((313, 374, 336, 425), radius=10, fill=teal, outline=gold, width=3)
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).polygon([(270, 358), (342, 350), (354, 390), (346, 454), (301, 468), (269, 439)], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(5))
    guide_path, mask_path = OUTPUT / "chr001_guardian_r20_gauntlet_guide.png", OUTPUT / "chr001_guardian_r20_gauntlet_mask.png"
    guide.save(guide_path, format="PNG", optimize=True); mask.save(mask_path, format="PNG", optimize=True)
    pipe = StableDiffusionXLInpaintPipeline.from_pretrained(model, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True)
    pipe.vae.enable_slicing(); pipe.vae.enable_tiling(); pipe.enable_model_cpu_offload(gpu_id=0)
    records = []
    for revision in range(1, cfg.count + 1):
        seed = 171250 + revision
        final = pipe(prompt=PROMPT, negative_prompt=NEGATIVE, image=guide, mask_image=mask, width=SIZE, height=SIZE, strength=0.52,
                     guidance_scale=7.8, num_inference_steps=cfg.steps, generator=torch.Generator(device="cuda").manual_seed(seed)).images[0]
        target = OUTPUT / f"chr001_maeru_guardian_chibi_r20v{revision:02d}_seed{seed}.png"; final.save(target, format="PNG", optimize=True)
        records.append({"asset_id": f"concept_chr001_guardian_chibi_r20v{revision:02d}", "character_id": "CHR001", "character_gender": "FEMALE",
                        "age_category": "ADULT", "attire_policy": "MAXIMUM_NON_EXPLICIT", "status": "ART_QA_CANDIDATE", "production_approved": False,
                        "runtime_asset": False, "source": SOURCE.relative_to(ROOT).as_posix(), "source_sha256": sha(SOURCE), "model": MODEL_ID,
                        "model_license": selected[MODEL_ID]["license"], "model_original_preserved": True, "krea2_used": False, "seed": seed,
                        "guide": guide_path.relative_to(ROOT).as_posix(), "mask": mask_path.relative_to(ROOT).as_posix(), "path": target.relative_to(ROOT).as_posix(),
                        "bytes": target.stat().st_size, "sha256": sha(target), "qa_verdict": "UNREVIEWED", "integration_allowed": False})
        print(f"R20_RENDERED {target}", flush=True)
    manifest = {"kind": "LOCAL_SDXL_GAUNTLET_CHIBI_GUARDIAN_INPAINT_R20", "created_utc": datetime.now(timezone.utc).isoformat(), "offline": True,
                "content_policy_version": content["policy_version"], "source_models_mutated": False, "production_approved": False, "records": records}
    manifest_path = OUTPUT / "chibi_guardian_r20_manifest.json"; manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
