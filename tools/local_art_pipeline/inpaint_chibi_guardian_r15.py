#!/usr/bin/env python3
"""R15 narrow local inpaint: expose abdomen and physically join hand to shield."""
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


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODEL_POLICY_PATH = PROJECT_ROOT / "tools" / "local_art_pipeline" / "model_policy.json"
CONTENT_POLICY_PATH = PROJECT_ROOT / "tools" / "policy" / "project_content_policy.json"
SOURCE = PROJECT_ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r14" / "chr001_maeru_guardian_chibi_r14v01_seed171151.png"
DEFAULT_OUTPUT = PROJECT_ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r15"
MODEL_ID = "diffusers-sdxl-inpaint-0.1-local"
SIZE = 768

BODY_PROMPT = (
    "premium polished 3D anime mobile RPG adult woman, mature curvy 3-head chibi body, revealing non-explicit fantasy bikini armor, "
    "opaque coverage, armored bikini top, bare skin abdomen, visible navel, fully exposed midriff and side waist, high-cut opaque bikini bottoms, "
    "wide hips, teal gold metal trim, detailed cel shaded collectible game model"
)

BODY_NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, school uniform, nude, nipples, genitals, explicit, transparent fabric, fabric on stomach, "
    "bodysuit, torso armor, corset, breastplate, covered belly, covered waist, dress, skirt, text, watermark, malformed anatomy, low detail, blurry"
)

GRIP_PROMPT = (
    "premium polished 3D anime mobile RPG adult woman, mature 3-head chibi guardian, single teal gold shield held in left hand, "
    "left hand visibly wrapped around a vertical leather handle mounted on shield right rim, shield touching hand, connected forearm and wrist, "
    "correct five fingers, short rounded arm, revealing non-explicit armor, opaque coverage, detailed cel shaded game model"
)

GRIP_NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, floating shield, detached shield, gap between hand and shield, no handle, second shield, "
    "two shields, wing, wings, extra arm, extra arms, missing hand, fused fingers, extra fingers, broken wrist, text, watermark, low detail, blurry"
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--count", type=int, default=2, choices=(1, 2))
    parser.add_argument("--steps", type=int, default=42)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def validate() -> tuple[dict, dict, Path]:
    content = json.loads(CONTENT_POLICY_PATH.read_text(encoding="utf-8"))
    models = json.loads(MODEL_POLICY_PATH.read_text(encoding="utf-8"))
    character = content["character_policy"]
    appearance = content["appearance_policy"]
    if character["human_and_humanoid_characters"] != "FEMALE_ONLY" or character["age_category"] != "ADULT_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID: adult FEMALE_ONLY required")
    if appearance["attire_exposure"] != "MAXIMUM_NON_EXPLICIT":
        raise SystemExit("CONTENT_POLICY_INVALID: MAXIMUM_NON_EXPLICIT required")
    required = tuple(character["required_positive_prompt_terms"]) + tuple(appearance["required_positive_prompt_terms"])
    for label, prompt in (("BODY", BODY_PROMPT), ("GRIP", GRIP_PROMPT)):
        lowered = prompt.lower()
        if not all(term.lower() in lowered for term in required):
            raise SystemExit(f"CONTENT_POLICY_BLOCK {label}: missing required terms {required}")
        for term in character["forbidden_positive_prompt_terms"]:
            if re.search(rf"(?<![a-z]){re.escape(term.lower())}(?![a-z])", lowered):
                raise SystemExit(f"CONTENT_POLICY_BLOCK {label}: forbidden positive term {term}")
    selected = {item["id"]: item for item in models["selected"]}
    if MODEL_ID not in selected:
        raise SystemExit(f"MODEL_BLOCKED: {MODEL_ID}")
    model = Path(selected[MODEL_ID]["path"]).resolve()
    if "krea" in str(model).lower() or not (model / "model_index.json").is_file():
        raise SystemExit(f"MODEL_BLOCKED: {model}")
    if not SOURCE.is_file():
        raise SystemExit(f"PROJECT_SOURCE_MISSING: {SOURCE}")
    return content, selected, model


def feather_polygon(points: list[tuple[int, int]], radius: int) -> Image.Image:
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask.filter(ImageFilter.GaussianBlur(radius=radius))


def make_clean_guide() -> Image.Image:
    image = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    # Repair the old watermark-cover rectangle using the background color from each row.
    draw = ImageDraw.Draw(image)
    for y in range(620, SIZE):
        draw.line((604, y, SIZE - 1, y), fill=image.getpixel((595, y)))
    # Explicit construction guide: a rim-mounted handle and palm at the existing arm endpoint.
    draw.rounded_rectangle((286, 376, 304, 448), radius=8, fill=(74, 47, 31), outline=(232, 178, 42), width=4)
    draw.ellipse((296, 400, 326, 434), fill=(30, 132, 142), outline=(238, 190, 51), width=4)
    return image


def main() -> int:
    args = parse_args()
    content, selected, model = validate()
    tokenizer = CLIPTokenizer.from_pretrained(model / "tokenizer", local_files_only=True)
    tokenizer_2 = CLIPTokenizer.from_pretrained(model / "tokenizer_2", local_files_only=True)
    for label, value in (
        ("BODY_PROMPT", BODY_PROMPT),
        ("BODY_NEGATIVE", BODY_NEGATIVE),
        ("GRIP_PROMPT", GRIP_PROMPT),
        ("GRIP_NEGATIVE", GRIP_NEGATIVE),
    ):
        lengths = [len(tokenizer(value, truncation=False).input_ids), len(tokenizer_2(value, truncation=False).input_ids)]
        print(f"PROMPT_TOKENS {label} {lengths}", flush=True)
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {label} {lengths}")
    if args.validate_only:
        print("R15_NARROW_INPAINT_POLICY_VALIDATION_OK")
        return 0

    output = args.output.resolve()
    if PROJECT_ROOT.resolve() not in output.parents:
        raise SystemExit("OUTPUT_BLOCKED: project output required")
    output.mkdir(parents=True, exist_ok=True)
    guide = make_clean_guide()
    # Preserve breasts and bottoms; replace only the covered abdomen/side-waist panel.
    body_mask = feather_polygon([(335, 355), (473, 355), (490, 402), (474, 477), (444, 493), (356, 488), (325, 442)], 9)
    # Repair only the shield-rim/hand/forearm junction, not the whole shield or body.
    grip_mask = feather_polygon([(278, 354), (337, 348), (355, 392), (345, 452), (305, 466), (278, 440)], 7)
    guide_path = output / "chr001_guardian_r15_connection_guide.png"
    body_mask_path = output / "chr001_guardian_r15_body_mask.png"
    grip_mask_path = output / "chr001_guardian_r15_grip_mask.png"
    guide.save(guide_path, format="PNG", optimize=True)
    body_mask.save(body_mask_path, format="PNG", optimize=True)
    grip_mask.save(grip_mask_path, format="PNG", optimize=True)

    pipe = StableDiffusionXLInpaintPipeline.from_pretrained(
        model, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True
    )
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(
        pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True
    )
    pipe.vae.enable_slicing()
    pipe.vae.enable_tiling()
    pipe.enable_model_cpu_offload(gpu_id=0)

    records = []
    for revision in range(1, args.count + 1):
        body_seed = 171160 + revision
        grip_seed = 171170 + revision
        body_stage = pipe(
            prompt=BODY_PROMPT,
            negative_prompt=BODY_NEGATIVE,
            image=guide,
            mask_image=body_mask,
            width=SIZE,
            height=SIZE,
            strength=0.92,
            guidance_scale=7.5,
            num_inference_steps=args.steps,
            generator=torch.Generator(device="cuda").manual_seed(body_seed),
        ).images[0]
        body_path = output / f"chr001_guardian_r15v{revision:02d}_body_seed{body_seed}.png"
        body_stage.save(body_path, format="PNG", optimize=True)
        final = pipe(
            prompt=GRIP_PROMPT,
            negative_prompt=GRIP_NEGATIVE,
            image=body_stage,
            mask_image=grip_mask,
            width=SIZE,
            height=SIZE,
            strength=0.72,
            guidance_scale=7.8,
            num_inference_steps=args.steps,
            generator=torch.Generator(device="cuda").manual_seed(grip_seed),
        ).images[0]
        target = output / f"chr001_maeru_guardian_chibi_r15v{revision:02d}_seed{grip_seed}.png"
        final.save(target, format="PNG", optimize=True)
        records.append({
            "asset_id": f"concept_chr001_guardian_chibi_r15v{revision:02d}",
            "character_id": "CHR001",
            "character_gender": "FEMALE",
            "age_category": "ADULT",
            "attire_policy": "MAXIMUM_NON_EXPLICIT",
            "status": "ART_QA_CANDIDATE",
            "production_approved": False,
            "runtime_asset": False,
            "source": SOURCE.relative_to(PROJECT_ROOT).as_posix(),
            "source_sha256": sha256(SOURCE),
            "model": MODEL_ID,
            "model_license": selected[MODEL_ID]["license"],
            "model_original_preserved": True,
            "krea2_used": False,
            "body_seed": body_seed,
            "grip_seed": grip_seed,
            "body_mask": body_mask_path.relative_to(PROJECT_ROOT).as_posix(),
            "grip_mask": grip_mask_path.relative_to(PROJECT_ROOT).as_posix(),
            "path": target.relative_to(PROJECT_ROOT).as_posix(),
            "bytes": target.stat().st_size,
            "sha256": sha256(target),
            "qa_verdict": "UNREVIEWED",
            "integration_allowed": False,
        })
        print(f"R15_RENDERED {target}", flush=True)

    manifest = {
        "kind": "LOCAL_SDXL_NARROW_CHIBI_GUARDIAN_INPAINT_R15",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "offline": True,
        "content_policy_version": content["policy_version"],
        "source_models_mutated": False,
        "production_approved": False,
        "records": records,
    }
    manifest_path = output / "chibi_guardian_r15_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
