#!/usr/bin/env python3
"""R18 local micro-inpaint for symmetric briefs and organic shield grip."""
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
SOURCE = ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r17" / "chr001_maeru_guardian_chibi_r17v02_seed171212.png"
OUTPUT = ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r18"
MODEL_ID = "diffusers-sdxl-inpaint-0.1-local"
SIZE = 768

BOTTOM_PROMPT = (
    "premium polished 3D anime mobile RPG adult woman, mature athletic 3-head chibi guardian, revealing non-explicit minimal bikini armor, "
    "opaque coverage, symmetric high-cut teal bikini briefs with thin gold trim, bare hips upper thighs and side waist, flat abdomen, "
    "short rounded legs, ornate glossy cel shaded collectible game model"
)
BOTTOM_NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, school uniform, nude, nipples, genitals, explicit, transparent fabric, shorts, pants, skirt, "
    "apron, loincloth, hanging panel, black rectangle, asymmetry, bodysuit, covered hips, text, watermark, malformed anatomy, blurry"
)
GRIP_PROMPT = (
    "premium polished 3D anime mobile RPG adult woman, mature 3-head chibi guardian, one shield held firmly, natural teal armored left glove, "
    "four rounded gloved fingers curling over gold shield rim, thumb behind rim, palm and wrist connected to forearm, hand touching shield, "
    "revealing non-explicit, opaque coverage, glossy cel shaded game model"
)
GRIP_NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, floating shield, detached shield, gap, bars, rods, mechanical fingers, missing hand, "
    "extra fingers, extra arm, second shield, wing, wings, broken wrist, text, watermark, low detail, blurry"
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
    parser.add_argument("--steps", type=int, default=38)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def validate() -> tuple[dict, dict, Path]:
    content = json.loads(CONTENT_POLICY.read_text(encoding="utf-8"))
    policy = json.loads(MODEL_POLICY.read_text(encoding="utf-8"))
    cp, ap = content["character_policy"], content["appearance_policy"]
    if cp["human_and_humanoid_characters"] != "FEMALE_ONLY" or cp["age_category"] != "ADULT_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID")
    if ap["attire_exposure"] != "MAXIMUM_NON_EXPLICIT":
        raise SystemExit("ATTIRE_POLICY_INVALID")
    required = tuple(cp["required_positive_prompt_terms"]) + tuple(ap["required_positive_prompt_terms"])
    for label, prompt in (("BOTTOM", BOTTOM_PROMPT), ("GRIP", GRIP_PROMPT)):
        low = prompt.lower()
        if not all(term.lower() in low for term in required):
            raise SystemExit(f"CONTENT_POLICY_BLOCK {label}: {required}")
        for term in cp["forbidden_positive_prompt_terms"]:
            if re.search(rf"(?<![a-z]){re.escape(term.lower())}(?![a-z])", low):
                raise SystemExit(f"CONTENT_POLICY_BLOCK {label}: {term}")
    selected = {row["id"]: row for row in policy["selected"]}
    if MODEL_ID not in selected:
        raise SystemExit(f"MODEL_BLOCKED: {MODEL_ID}")
    model = Path(selected[MODEL_ID]["path"]).resolve()
    if "krea" in str(model).lower() or not (model / "model_index.json").is_file():
        raise SystemExit(f"MODEL_BLOCKED: {model}")
    if not SOURCE.is_file():
        raise SystemExit(f"SOURCE_MISSING: {SOURCE}")
    return content, selected, model


def polygon_mask(points: list[tuple[int, int]], blur: int) -> Image.Image:
    result = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(result).polygon(points, fill=255)
    return result.filter(ImageFilter.GaussianBlur(blur))


def make_guide() -> Image.Image:
    image = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(image)
    teal, gold, skin = (15, 143, 151), (237, 177, 40), (247, 188, 174)
    # Remove skirt/short topology from the guide, then author a compact high-cut brief.
    draw.polygon([(343, 428), (463, 428), (468, 487), (440, 520), (368, 520), (339, 487)], fill=skin)
    draw.polygon([(357, 456), (450, 456), (434, 512), (374, 512)], fill=teal, outline=gold)
    # Organic finger guide: rounded overlapping digits cross the shield rim.
    for index, width in enumerate((31, 34, 33, 29)):
        y0 = 386 + index * 12
        draw.ellipse((280, y0, 280 + width, y0 + 13), fill=teal, outline=gold, width=2)
    draw.rounded_rectangle((305, 378, 331, 444), radius=12, fill=teal, outline=gold, width=3)
    return image


def main() -> int:
    cfg = cli()
    content, selected, model = validate()
    tokenizers = [CLIPTokenizer.from_pretrained(model / part, local_files_only=True) for part in ("tokenizer", "tokenizer_2")]
    for label, prompt in (("BOTTOM_PROMPT", BOTTOM_PROMPT), ("BOTTOM_NEGATIVE", BOTTOM_NEGATIVE), ("GRIP_PROMPT", GRIP_PROMPT), ("GRIP_NEGATIVE", GRIP_NEGATIVE)):
        lengths = [len(tok(prompt, truncation=False).input_ids) for tok in tokenizers]
        print(f"PROMPT_TOKENS {label} {lengths}", flush=True)
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {label} {lengths}")
    if cfg.validate_only:
        print("R18_MICRO_INPAINT_POLICY_VALIDATION_OK")
        return 0
    OUTPUT.mkdir(parents=True, exist_ok=True)
    guide = make_guide()
    bottom_mask = polygon_mask([(329, 410), (476, 410), (484, 493), (446, 530), (363, 530), (325, 493)], 7)
    grip_mask = polygon_mask([(272, 368), (338, 360), (348, 392), (343, 452), (302, 463), (271, 438)], 5)
    guide_path, bottom_path, grip_path = OUTPUT / "chr001_guardian_r18_guide.png", OUTPUT / "chr001_guardian_r18_bottom_mask.png", OUTPUT / "chr001_guardian_r18_grip_mask.png"
    guide.save(guide_path, format="PNG", optimize=True); bottom_mask.save(bottom_path, format="PNG", optimize=True); grip_mask.save(grip_path, format="PNG", optimize=True)
    pipe = StableDiffusionXLInpaintPipeline.from_pretrained(model, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True)
    pipe.vae.enable_slicing(); pipe.vae.enable_tiling(); pipe.enable_model_cpu_offload(gpu_id=0)
    records = []
    for revision in range(1, cfg.count + 1):
        bottom_seed, grip_seed = 171220 + revision, 171230 + revision
        bottom = pipe(prompt=BOTTOM_PROMPT, negative_prompt=BOTTOM_NEGATIVE, image=guide, mask_image=bottom_mask, width=SIZE, height=SIZE,
                      strength=0.68, guidance_scale=8.0, num_inference_steps=cfg.steps, generator=torch.Generator(device="cuda").manual_seed(bottom_seed)).images[0]
        bottom_file = OUTPUT / f"chr001_guardian_r18v{revision:02d}_bottom_seed{bottom_seed}.png"; bottom.save(bottom_file, format="PNG", optimize=True)
        final = pipe(prompt=GRIP_PROMPT, negative_prompt=GRIP_NEGATIVE, image=bottom, mask_image=grip_mask, width=SIZE, height=SIZE,
                     strength=0.42, guidance_scale=7.5, num_inference_steps=cfg.steps, generator=torch.Generator(device="cuda").manual_seed(grip_seed)).images[0]
        target = OUTPUT / f"chr001_maeru_guardian_chibi_r18v{revision:02d}_seed{grip_seed}.png"; final.save(target, format="PNG", optimize=True)
        records.append({"asset_id": f"concept_chr001_guardian_chibi_r18v{revision:02d}", "character_id": "CHR001", "character_gender": "FEMALE",
                        "age_category": "ADULT", "attire_policy": "MAXIMUM_NON_EXPLICIT", "status": "ART_QA_CANDIDATE", "production_approved": False,
                        "runtime_asset": False, "source": SOURCE.relative_to(ROOT).as_posix(), "source_sha256": sha(SOURCE), "model": MODEL_ID,
                        "model_license": selected[MODEL_ID]["license"], "model_original_preserved": True, "krea2_used": False,
                        "bottom_seed": bottom_seed, "grip_seed": grip_seed, "guide": guide_path.relative_to(ROOT).as_posix(),
                        "bottom_mask": bottom_path.relative_to(ROOT).as_posix(), "grip_mask": grip_path.relative_to(ROOT).as_posix(),
                        "path": target.relative_to(ROOT).as_posix(), "bytes": target.stat().st_size, "sha256": sha(target),
                        "qa_verdict": "UNREVIEWED", "integration_allowed": False})
        print(f"R18_RENDERED {target}", flush=True)
    manifest = {"kind": "LOCAL_SDXL_MICRO_CHIBI_GUARDIAN_INPAINT_R18", "created_utc": datetime.now(timezone.utc).isoformat(), "offline": True,
                "content_policy_version": content["policy_version"], "source_models_mutated": False, "production_approved": False, "records": records}
    manifest_path = OUTPUT / "chibi_guardian_r18_manifest.json"; manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
