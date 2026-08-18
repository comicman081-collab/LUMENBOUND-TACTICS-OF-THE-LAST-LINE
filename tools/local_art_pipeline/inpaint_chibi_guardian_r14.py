#!/usr/bin/env python3
"""R14 targeted costume-exposure and shield-grip repair with local SDXL inpaint."""
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
SOURCE = PROJECT_ROOT / "work" / "art_gen" / "sdxl_chibi_depth_guardian_r12" / "chr001_maeru_guardian_chibi_depth_r12v04_seed171124.png"
DEFAULT_OUTPUT = PROJECT_ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r14"
MODEL_ID = "diffusers-sdxl-inpaint-0.1-local"
SIZE = 768

COSTUME_PROMPT = (
    "premium 3D anime RPG adult woman, mature 3-head chibi body, minimal fantasy bikini armor, teal gold armored bra with opaque coverage, "
    "deep cleavage, bare shoulders, completely bare midriff and side waist, high-cut opaque bottoms, bare hips and upper thighs, "
    "revealing non-explicit, detailed metal leather, polished cel shaded game model"
)

COSTUME_NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, school uniform, nude, nipples, genitals, explicit, transparent fabric, dress, skirt, "
    "full torso armor, covered waist, long coat, text, watermark, extra limbs, malformed body, low detail, blurry"
)

GRIP_PROMPT = (
    "premium 3D anime RPG adult woman, mature 3-head chibi guardian, single teal gold shield, left forearm strapped behind shield, "
    "left hand visibly gripping thick shield handle, connected wrist, correct five fingers, short rounded arm, polished detailed game model, "
    "revealing non-explicit armor, opaque coverage"
)

GRIP_NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, floating shield, detached shield, no handle, second shield, two shields, wing, wings, "
    "extra arms, missing hand, fused fingers, extra fingers, broken wrist, text, watermark, low detail, blurry"
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
    parser.add_argument("--steps", type=int, default=44)
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
    for label, prompt in (("COSTUME", COSTUME_PROMPT), ("GRIP", GRIP_PROMPT)):
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


def feather_polygon(points: list[tuple[int, int]], radius: int = 14) -> Image.Image:
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask.filter(ImageFilter.GaussianBlur(radius=radius))


def clean_source() -> Image.Image:
    image = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(image)
    # Remove the generator mark from empty background before any inpainting.
    fill = image.getpixel((700, 620))
    draw.rectangle((610, 650, 767, 767), fill=fill)
    return image


def main() -> int:
    args = parse_args()
    content, selected, model = validate()
    tokenizer = CLIPTokenizer.from_pretrained(model / "tokenizer", local_files_only=True)
    tokenizer_2 = CLIPTokenizer.from_pretrained(model / "tokenizer_2", local_files_only=True)
    for label, value in (
        ("COSTUME_PROMPT", COSTUME_PROMPT),
        ("COSTUME_NEGATIVE", COSTUME_NEGATIVE),
        ("GRIP_PROMPT", GRIP_PROMPT),
        ("GRIP_NEGATIVE", GRIP_NEGATIVE),
    ):
        lengths = [len(tokenizer(value, truncation=False).input_ids), len(tokenizer_2(value, truncation=False).input_ids)]
        print(f"PROMPT_TOKENS {label} {lengths}", flush=True)
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {label} {lengths}")
    if args.validate_only:
        print("R14_TARGETED_INPAINT_POLICY_VALIDATION_OK")
        return 0

    output = args.output.resolve()
    if PROJECT_ROOT.resolve() not in output.parents:
        raise SystemExit("OUTPUT_BLOCKED: project output required")
    output.mkdir(parents=True, exist_ok=True)
    base = clean_source()
    costume_mask = feather_polygon([(292, 248), (520, 248), (565, 366), (548, 548), (486, 623), (326, 610), (268, 460)])
    grip_mask = feather_polygon([(218, 286), (350, 264), (392, 372), (375, 532), (294, 570), (224, 500)], radius=11)
    base_path = output / "chr001_guardian_r14_clean_base.png"
    costume_mask_path = output / "chr001_guardian_r14_costume_mask.png"
    grip_mask_path = output / "chr001_guardian_r14_grip_mask.png"
    base.save(base_path, format="PNG", optimize=True)
    costume_mask.save(costume_mask_path, format="PNG", optimize=True)
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
        costume_seed = 171140 + revision
        grip_seed = 171150 + revision
        costume_stage = pipe(
            prompt=COSTUME_PROMPT,
            negative_prompt=COSTUME_NEGATIVE,
            image=base,
            mask_image=costume_mask,
            width=SIZE,
            height=SIZE,
            strength=0.88,
            guidance_scale=7.0,
            num_inference_steps=args.steps,
            generator=torch.Generator(device="cuda").manual_seed(costume_seed),
        ).images[0]
        costume_path = output / f"chr001_guardian_r14v{revision:02d}_costume_seed{costume_seed}.png"
        costume_stage.save(costume_path, format="PNG", optimize=True)
        final = pipe(
            prompt=GRIP_PROMPT,
            negative_prompt=GRIP_NEGATIVE,
            image=costume_stage,
            mask_image=grip_mask,
            width=SIZE,
            height=SIZE,
            strength=0.82,
            guidance_scale=7.2,
            num_inference_steps=args.steps,
            generator=torch.Generator(device="cuda").manual_seed(grip_seed),
        ).images[0]
        target = output / f"chr001_maeru_guardian_chibi_r14v{revision:02d}_seed{grip_seed}.png"
        final.save(target, format="PNG", optimize=True)
        records.append({
            "asset_id": f"concept_chr001_guardian_chibi_r14v{revision:02d}",
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
            "costume_seed": costume_seed,
            "grip_seed": grip_seed,
            "costume_mask": costume_mask_path.relative_to(PROJECT_ROOT).as_posix(),
            "grip_mask": grip_mask_path.relative_to(PROJECT_ROOT).as_posix(),
            "path": target.relative_to(PROJECT_ROOT).as_posix(),
            "bytes": target.stat().st_size,
            "sha256": sha256(target),
            "qa_verdict": "UNREVIEWED",
            "integration_allowed": False,
        })
        print(f"R14_RENDERED {target}", flush=True)

    manifest = {
        "kind": "LOCAL_SDXL_TARGETED_CHIBI_GUARDIAN_INPAINT_R14",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "offline": True,
        "content_policy_version": content["policy_version"],
        "source_models_mutated": False,
        "production_approved": False,
        "records": records,
    }
    manifest_path = output / "chibi_guardian_r14_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
