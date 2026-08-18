#!/usr/bin/env python3
"""R17 local waist-silhouette and readable shield-finger correction."""
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
SOURCE = ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r16" / "chr001_maeru_guardian_chibi_r16v02_seed171192.png"
DEFAULT_OUTPUT = ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r17"
MODEL_ID = "diffusers-sdxl-inpaint-0.1-local"
SIZE = 768

BODY_PROMPT = (
    "premium polished 3D anime mobile RPG adult woman, mature athletic 3-head chibi guardian, revealing non-explicit minimal bikini armor, "
    "opaque coverage, separate armored bra and high-cut briefs, flat toned bare abdomen, very narrow waist, visible navel, bare side waist hips thighs, "
    "teal gold ornate detail, short rounded limbs, glossy cel shaded collectible game model"
)
BODY_NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, school uniform, pregnant, pregnancy, pot belly, round belly, obese, wide waist, bodysuit, leotard, "
    "torso armor, covered stomach, covered waist, nude, nipples, genitals, explicit, transparent fabric, text, watermark, malformed anatomy, blurry"
)
GRIP_PROMPT = (
    "premium polished 3D anime mobile RPG adult woman, mature 3-head chibi guardian, one shield held firmly, teal armored left glove on shield front, "
    "four visible gloved fingers curling around gold right rim, thumb behind rim, hand touching shield, connected wrist and forearm, revealing non-explicit, "
    "opaque coverage, glossy cel shaded game model"
)
GRIP_NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, floating shield, detached shield, gap, missing hand, missing fingers, extra fingers, extra arm, "
    "second shield, wing, wings, broken wrist, text, watermark, low detail, blurry"
)


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--count", type=int, default=2, choices=(1, 2))
    parser.add_argument("--steps", type=int, default=36)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def preflight() -> tuple[dict, dict, Path]:
    content = json.loads(CONTENT_POLICY.read_text(encoding="utf-8"))
    policy = json.loads(MODEL_POLICY.read_text(encoding="utf-8"))
    character = content["character_policy"]
    appearance = content["appearance_policy"]
    if character["human_and_humanoid_characters"] != "FEMALE_ONLY" or character["age_category"] != "ADULT_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID")
    if appearance["attire_exposure"] != "MAXIMUM_NON_EXPLICIT":
        raise SystemExit("ATTIRE_POLICY_INVALID")
    required = tuple(character["required_positive_prompt_terms"]) + tuple(appearance["required_positive_prompt_terms"])
    for label, prompt in (("BODY", BODY_PROMPT), ("GRIP", GRIP_PROMPT)):
        lower = prompt.lower()
        if not all(term.lower() in lower for term in required):
            raise SystemExit(f"CONTENT_POLICY_BLOCK {label}: {required}")
        for term in character["forbidden_positive_prompt_terms"]:
            if re.search(rf"(?<![a-z]){re.escape(term.lower())}(?![a-z])", lower):
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


def mask(points: list[tuple[int, int]], blur: int) -> Image.Image:
    result = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(result).polygon(points, fill=255)
    return result.filter(ImageFilter.GaussianBlur(blur))


def guide() -> Image.Image:
    image = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(image)
    for y in range(620, SIZE):
        draw.line((604, y, SIZE - 1, y), fill=image.getpixel((595, y)))
    skin, teal, gold, dark = (247, 188, 174), (13, 139, 148), (237, 175, 38), (33, 38, 47)
    # Narrow athletic hourglass, preserving the already successful exposed-skin topology.
    draw.polygon([(347, 306), (461, 306), (456, 354), (430, 418), (448, 474), (431, 505), (373, 505), (354, 474), (376, 418), (350, 354)], fill=skin)
    draw.ellipse((344, 307, 405, 365), fill=teal, outline=gold, width=6)
    draw.ellipse((402, 307, 463, 365), fill=teal, outline=gold, width=6)
    draw.polygon([(355, 466), (451, 466), (432, 510), (374, 510)], fill=dark, outline=gold)
    draw.ellipse((399, 408, 408, 419), fill=(203, 125, 103))
    # Readable front fingers: four teal bands cross the gold rim and join the existing forearm.
    for index in range(4):
        y0 = 391 + index * 11
        draw.rounded_rectangle((281, y0, 316, y0 + 8), radius=4, fill=teal, outline=gold, width=2)
    draw.rounded_rectangle((307, 381, 329, 442), radius=9, fill=teal, outline=gold, width=3)
    return image


def main() -> int:
    cfg = args()
    content, selected, model = preflight()
    tokenizers = [CLIPTokenizer.from_pretrained(model / name, local_files_only=True) for name in ("tokenizer", "tokenizer_2")]
    for label, text in (("BODY_PROMPT", BODY_PROMPT), ("BODY_NEGATIVE", BODY_NEGATIVE), ("GRIP_PROMPT", GRIP_PROMPT), ("GRIP_NEGATIVE", GRIP_NEGATIVE)):
        lengths = [len(tokenizer(text, truncation=False).input_ids) for tokenizer in tokenizers]
        print(f"PROMPT_TOKENS {label} {lengths}", flush=True)
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {label} {lengths}")
    if cfg.validate_only:
        print("R17_WAIST_GRIP_POLICY_VALIDATION_OK")
        return 0
    output = cfg.output.resolve()
    if ROOT.resolve() not in output.parents:
        raise SystemExit("OUTPUT_BLOCKED")
    output.mkdir(parents=True, exist_ok=True)
    source_guide = guide()
    body_mask = mask([(318, 286), (486, 286), (497, 368), (472, 510), (445, 529), (358, 529), (329, 508), (308, 370)], 9)
    grip_mask = mask([(274, 368), (334, 360), (348, 391), (343, 450), (303, 461), (274, 439)], 5)
    guide_path = output / "chr001_guardian_r17_structure_guide.png"
    body_mask_path = output / "chr001_guardian_r17_body_mask.png"
    grip_mask_path = output / "chr001_guardian_r17_grip_mask.png"
    source_guide.save(guide_path, format="PNG", optimize=True)
    body_mask.save(body_mask_path, format="PNG", optimize=True)
    grip_mask.save(grip_mask_path, format="PNG", optimize=True)
    pipe = StableDiffusionXLInpaintPipeline.from_pretrained(model, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True)
    pipe.vae.enable_slicing(); pipe.vae.enable_tiling(); pipe.enable_model_cpu_offload(gpu_id=0)
    records = []
    for revision in range(1, cfg.count + 1):
        body_seed, grip_seed = 171200 + revision, 171210 + revision
        body = pipe(prompt=BODY_PROMPT, negative_prompt=BODY_NEGATIVE, image=source_guide, mask_image=body_mask, width=SIZE, height=SIZE,
                    strength=0.58, guidance_scale=8.0, num_inference_steps=cfg.steps, generator=torch.Generator(device="cuda").manual_seed(body_seed)).images[0]
        body_path = output / f"chr001_guardian_r17v{revision:02d}_body_seed{body_seed}.png"
        body.save(body_path, format="PNG", optimize=True)
        final = pipe(prompt=GRIP_PROMPT, negative_prompt=GRIP_NEGATIVE, image=body, mask_image=grip_mask, width=SIZE, height=SIZE,
                     strength=0.28, guidance_scale=7.2, num_inference_steps=cfg.steps, generator=torch.Generator(device="cuda").manual_seed(grip_seed)).images[0]
        target = output / f"chr001_maeru_guardian_chibi_r17v{revision:02d}_seed{grip_seed}.png"
        final.save(target, format="PNG", optimize=True)
        records.append({"asset_id": f"concept_chr001_guardian_chibi_r17v{revision:02d}", "character_id": "CHR001", "character_gender": "FEMALE",
                        "age_category": "ADULT", "attire_policy": "MAXIMUM_NON_EXPLICIT", "status": "ART_QA_CANDIDATE",
                        "production_approved": False, "runtime_asset": False, "source": SOURCE.relative_to(ROOT).as_posix(),
                        "source_sha256": digest(SOURCE), "model": MODEL_ID, "model_license": selected[MODEL_ID]["license"],
                        "model_original_preserved": True, "krea2_used": False, "body_seed": body_seed, "grip_seed": grip_seed,
                        "structure_guide": guide_path.relative_to(ROOT).as_posix(), "body_mask": body_mask_path.relative_to(ROOT).as_posix(),
                        "grip_mask": grip_mask_path.relative_to(ROOT).as_posix(), "path": target.relative_to(ROOT).as_posix(),
                        "bytes": target.stat().st_size, "sha256": digest(target), "qa_verdict": "UNREVIEWED", "integration_allowed": False})
        print(f"R17_RENDERED {target}", flush=True)
    manifest = {"kind": "LOCAL_SDXL_WAIST_GRIP_CHIBI_GUARDIAN_INPAINT_R17", "created_utc": datetime.now(timezone.utc).isoformat(), "offline": True,
                "content_policy_version": content["policy_version"], "source_models_mutated": False, "production_approved": False, "records": records}
    manifest_path = output / "chibi_guardian_r17_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
