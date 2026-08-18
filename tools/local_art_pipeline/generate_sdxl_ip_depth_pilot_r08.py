#!/usr/bin/env python3
"""R08 premium pilot using only approved local, read-only model weights.

The project-owned R05 portrait supplies face, hair, palette, and material cues
through IP-Adapter. A new project-authored depth mass supplies full-body
framing and the Guardian shield. Outputs stay ART_QA_CANDIDATE until reviewed.
"""
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
from diffusers import ControlNetModel, DPMSolverMultistepScheduler, StableDiffusionXLControlNetPipeline
from PIL import Image, ImageDraw, ImageFilter
from transformers import CLIPTokenizer


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODEL_POLICY_PATH = PROJECT_ROOT / "tools" / "local_art_pipeline" / "model_policy.json"
CONTENT_POLICY_PATH = PROJECT_ROOT / "tools" / "policy" / "project_content_policy.json"
DEFAULT_OUTPUT = PROJECT_ROOT / "work" / "art_gen" / "sdxl_ip_depth_pilot_r08"
APPEARANCE_SOURCE = (
    PROJECT_ROOT
    / "work"
    / "art_gen"
    / "sdxl_policy_pilot_r05"
    / "CHR001_MAERU_GUARDIAN"
    / "chr001_maeru_guardian_concept_r05v01_seed171011.png"
)

BASE_ID = "stabilityai-sdxl-base-1.0-local"
DEPTH_ID = "diffusers-controlnet-depth-sdxl-1.0-local"
IP_ID = "h94-ip-adapter-sdxl-local"
WIDTH = 832
HEIGHT = 1216

PROMPT = (
    "premium 3D anime RPG adult woman, mature feminine face, chestnut high ponytail, four-head SD body, rescue guardian, "
    "dynamic full-body stance, giant octagonal teal shield, detailed navy gold armor, revealing non-explicit bodysuit, "
    "bare shoulders and waist, opaque coverage chest and groin, metal leather cloth, amber eyes, rim light, "
    "crisp cel shading"
)

NEGATIVE = (
    "male, man, boy, masculine, androgynous, child, teen, underage, school uniform, juvenile body, portrait, close-up, "
    "cropped feet, nude, nipples, genitals, explicit, transparent clothing, text, watermark, signature, "
    "extra limbs, extra fingers, fused hands, broken anatomy, doll joints, blurry, low detail"
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
    parser.add_argument("--steps", type=int, default=38)
    parser.add_argument("--count", type=int, default=2, choices=(1, 2, 3))
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def validate() -> tuple[dict, dict, Path, Path, Path, Path]:
    content = json.loads(CONTENT_POLICY_PATH.read_text(encoding="utf-8"))
    models = json.loads(MODEL_POLICY_PATH.read_text(encoding="utf-8"))
    character = content["character_policy"]
    appearance = content["appearance_policy"]
    if character["human_and_humanoid_characters"] != "FEMALE_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID: FEMALE_ONLY required")
    if character["age_category"] != "ADULT_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID: ADULT_ONLY required")
    if appearance["attire_exposure"] != "MAXIMUM_NON_EXPLICIT":
        raise SystemExit("CONTENT_POLICY_INVALID: MAXIMUM_NON_EXPLICIT required")
    required = tuple(character["required_positive_prompt_terms"]) + tuple(appearance["required_positive_prompt_terms"])
    lowered = PROMPT.lower()
    if not all(term.lower() in lowered for term in required):
        raise SystemExit(f"CONTENT_POLICY_BLOCK: missing required terms {required}")
    for term in character["forbidden_positive_prompt_terms"]:
        if re.search(rf"(?<![a-z]){re.escape(term.lower())}(?![a-z])", lowered):
            raise SystemExit(f"CONTENT_POLICY_BLOCK: forbidden positive term {term}")

    selected = {item["id"]: item for item in models["selected"]}
    for model_id in (BASE_ID, DEPTH_ID, IP_ID):
        if model_id not in selected:
            raise SystemExit(f"MODEL_BLOCKED: selected model missing: {model_id}")
    base = Path(selected[BASE_ID]["path"]).resolve()
    depth = Path(selected[DEPTH_ID]["path"]).resolve()
    ip_root = Path(selected[IP_ID]["path"]).resolve().parent
    encoder = Path(selected[IP_ID]["companion_image_encoder_path"]).resolve()
    for path in (base, depth, ip_root, encoder):
        if "krea" in str(path).lower() or not path.exists():
            raise SystemExit(f"MODEL_BLOCKED: {path}")
    if not (base / "LICENSE.md").is_file() or not (depth / "config.json").is_file():
        raise SystemExit("MODEL_BLOCKED: license/config evidence missing")
    if not (ip_root / "sdxl_models" / "ip-adapter_sdxl_vit-h.safetensors").is_file():
        raise SystemExit("MODEL_BLOCKED: IP-Adapter weight missing")
    if not (encoder / "model.safetensors").is_file():
        raise SystemExit("MODEL_BLOCKED: IP-Adapter image encoder missing")
    if not APPEARANCE_SOURCE.is_file():
        raise SystemExit(f"PROJECT_SOURCE_MISSING: {APPEARANCE_SOURCE}")
    return content, selected, base, depth, ip_root, encoder


def build_guardian_depth() -> Image.Image:
    depth = Image.new("L", (WIDTH, HEIGHT), 18)
    draw = ImageDraw.Draw(depth)
    # Four-head adult SD proportions in a mild three-quarter action pose.
    draw.ellipse((474, 78, 682, 286), fill=196)
    draw.polygon([(496, 250), (655, 238), (700, 550), (617, 700), (489, 622)], fill=180)
    draw.ellipse((500, 582, 686, 760), fill=188)
    draw.polygon([(512, 690), (590, 685), (548, 1090), (442, 1090)], fill=171)
    draw.polygon([(603, 690), (680, 676), (750, 1058), (648, 1084)], fill=178)
    draw.line((512, 320, 392, 610), fill=205, width=74)
    draw.line((654, 310, 716, 604), fill=202, width=70)
    # Large independent octagonal rescue shield, forward and readable.
    outer = [(40, 338), (138, 238), (328, 220), (430, 310), (454, 716), (348, 934), (160, 1020), (46, 900)]
    inner = [(82, 370), (160, 292), (309, 278), (384, 344), (404, 690), (316, 870), (176, 942), (94, 858)]
    draw.polygon(outer, fill=232)
    draw.polygon(inner, fill=207)
    draw.line((153, 617, 350, 615), fill=220, width=24)
    return Image.merge("RGB", (depth, depth, depth)).filter(ImageFilter.GaussianBlur(radius=8))


def appearance_crop() -> Image.Image:
    image = Image.open(APPEARANCE_SOURCE).convert("RGB")
    side = min(image.width, image.height)
    left = max(0, (image.width - side) // 2)
    return image.crop((left, 0, left + side, side)).resize((768, 768), Image.Resampling.LANCZOS)


def main() -> int:
    args = parse_args()
    content, selected, base, depth_model, ip_root, encoder = validate()
    tokenizer = CLIPTokenizer.from_pretrained(base / "tokenizer", local_files_only=True)
    tokenizer_2 = CLIPTokenizer.from_pretrained(base / "tokenizer_2", local_files_only=True)
    for label, value in (("PROMPT", PROMPT), ("NEGATIVE", NEGATIVE)):
        lengths = [len(tokenizer(value, truncation=False).input_ids), len(tokenizer_2(value, truncation=False).input_ids)]
        print(f"PROMPT_TOKENS {label} {lengths}", flush=True)
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {label} {lengths}")
    if args.validate_only:
        print("R08_IP_DEPTH_POLICY_VALIDATION_OK")
        return 0

    output = args.output.resolve()
    if PROJECT_ROOT.resolve() not in output.parents:
        raise SystemExit("OUTPUT_BLOCKED: output must stay under project")
    output.mkdir(parents=True, exist_ok=True)
    concept_dir = output / "CHR001_MAERU_GUARDIAN"
    concept_dir.mkdir(parents=True, exist_ok=True)
    depth = build_guardian_depth()
    appearance = appearance_crop()
    depth_path = concept_dir / "chr001_guardian_r08_project_depth.png"
    appearance_path = concept_dir / "chr001_guardian_r08_project_appearance.png"
    for target, image in ((depth_path, depth), (appearance_path, appearance)):
        if target.exists():
            raise SystemExit(f"REFUSE_OVERWRITE: {target}")
        image.save(target, format="PNG", optimize=True)

    controlnet = ControlNetModel.from_pretrained(
        depth_model, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True
    )
    pipe = StableDiffusionXLControlNetPipeline.from_pretrained(
        base, controlnet=controlnet, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True
    )
    pipe.load_ip_adapter(
        str(ip_root), subfolder="sdxl_models", weight_name="ip-adapter_sdxl_vit-h.safetensors",
        image_encoder_folder=str(encoder), local_files_only=True,
    )
    pipe.set_ip_adapter_scale(0.42)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(
        pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True
    )
    pipe.vae.enable_slicing()
    pipe.vae.enable_tiling()
    # Do not call enable_attention_slicing after loading IP-Adapter. It replaces
    # the tuple-aware IP attention processors with SlicedAttnProcessor.
    pipe.enable_model_cpu_offload(gpu_id=0)

    records: list[dict] = []
    for revision in range(1, args.count + 1):
        seed = 171080 + revision
        target = concept_dir / f"chr001_maeru_guardian_concept_r08v{revision:02d}_seed{seed}.png"
        if target.exists():
            raise SystemExit(f"REFUSE_OVERWRITE: {target}")
        generator = torch.Generator(device="cuda").manual_seed(seed)
        result = pipe(
            prompt=PROMPT,
            negative_prompt=NEGATIVE,
            image=depth,
            ip_adapter_image=appearance,
            width=WIDTH,
            height=HEIGHT,
            num_inference_steps=args.steps,
            guidance_scale=6.0,
            controlnet_conditioning_scale=0.46,
            control_guidance_start=0.0,
            control_guidance_end=0.58,
            generator=generator,
        ).images[0]
        result.save(target, format="PNG", optimize=True)
        records.append({
            "asset_id": f"concept_chr001_guardian_r08v{revision:02d}",
            "character_id": "CHR001",
            "character_gender": "FEMALE",
            "age_category": "ADULT",
            "attire_policy": "MAXIMUM_NON_EXPLICIT",
            "status": "ART_QA_CANDIDATE",
            "runtime_asset": False,
            "models": [BASE_ID, DEPTH_ID, IP_ID],
            "model_licenses": [selected[BASE_ID]["license"], selected[DEPTH_ID]["license"], selected[IP_ID]["license"]],
            "model_originals_preserved": True,
            "krea2_used": False,
            "appearance_source": str(APPEARANCE_SOURCE.relative_to(PROJECT_ROOT)).replace("\\", "/"),
            "appearance_source_sha256": sha256(APPEARANCE_SOURCE),
            "depth_guide": str(depth_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
            "seed": seed,
            "width": WIDTH,
            "height": HEIGHT,
            "steps": args.steps,
            "ip_adapter_scale": 0.42,
            "controlnet_conditioning_scale": 0.46,
            "prompt": PROMPT,
            "negative_prompt": NEGATIVE,
            "path": str(target.relative_to(PROJECT_ROOT)).replace("\\", "/"),
            "bytes": target.stat().st_size,
            "sha256": sha256(target),
            "qa_verdict": "UNREVIEWED",
            "integration_allowed": False,
        })
        print(f"R08_RENDERED {target}", flush=True)

    manifest = {
        "kind": "LOCAL_SDXL_IP_ADAPTER_DEPTH_PREMIUM_PILOT_R08",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "offline": True,
        "content_policy_version": content["policy_version"],
        "character_gender_policy": "FEMALE_ONLY",
        "age_policy": "ADULT_ONLY",
        "attire_policy": "MAXIMUM_NON_EXPLICIT",
        "source_models_mutated": False,
        "production_approved": False,
        "records": records,
    }
    manifest_path = output / "ip_depth_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
