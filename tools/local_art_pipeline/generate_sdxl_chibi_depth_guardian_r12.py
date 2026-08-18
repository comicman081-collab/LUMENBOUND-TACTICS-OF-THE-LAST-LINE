#!/usr/bin/env python3
"""R12: lock a 3.2-head chibi Guardian with local SDXL depth + IP-Adapter."""
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
APPEARANCE_SOURCE = PROJECT_ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r11" / "chr001_maeru_guardian_chibi_r11v04_seed171114.png"
DEFAULT_OUTPUT = PROJECT_ROOT / "work" / "art_gen" / "sdxl_chibi_depth_guardian_r12"
BASE_ID = "stabilityai-sdxl-base-1.0-local"
DEPTH_ID = "diffusers-controlnet-depth-sdxl-1.0-local"
IP_ID = "h94-ip-adapter-sdxl-local"
SIZE = 768

PROMPT = (
    "premium 3D anime mobile RPG adult woman, mature feminine 3-head chibi heroine, full body centered, large head short limbs, "
    "chestnut ponytail, cyan eyes, giant octagonal teal shield left hand, guardian combat stance, ornate teal navy gold armor, "
    "revealing non-explicit bodysuit, bare shoulders waist thighs, opaque coverage, detailed metal leather cloth, polished game render"
)

NEGATIVE = (
    "male, man, boy, masculine, androgynous, child, teen, underage, juvenile, tall body, long legs, "
    "portrait, close-up, cropped feet, two shields, sword, nude, nipples, genitals, explicit, transparent clothing, text, watermark, "
    "extra limbs, extra fingers, fused hands, broken anatomy, low detail, blurry"
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
    parser.add_argument("--count", type=int, default=4, choices=(1, 2, 3, 4))
    parser.add_argument("--steps", type=int, default=44)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def validate() -> tuple[dict, dict, Path, Path, Path, Path]:
    content = json.loads(CONTENT_POLICY_PATH.read_text(encoding="utf-8"))
    models = json.loads(MODEL_POLICY_PATH.read_text(encoding="utf-8"))
    character = content["character_policy"]
    appearance = content["appearance_policy"]
    if character["human_and_humanoid_characters"] != "FEMALE_ONLY" or character["age_category"] != "ADULT_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID: adult FEMALE_ONLY required")
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
            raise SystemExit(f"MODEL_BLOCKED: {model_id}")
    base = Path(selected[BASE_ID]["path"]).resolve()
    depth = Path(selected[DEPTH_ID]["path"]).resolve()
    ip_root = Path(selected[IP_ID]["path"]).resolve().parent
    encoder = Path(selected[IP_ID]["companion_image_encoder_path"]).resolve()
    for path in (base, depth, ip_root, encoder):
        if "krea" in str(path).lower() or not path.exists():
            raise SystemExit(f"MODEL_BLOCKED: {path}")
    if not (base / "LICENSE.md").is_file() or not (depth / "config.json").is_file():
        raise SystemExit("MODEL_BLOCKED: local license/config evidence missing")
    if not APPEARANCE_SOURCE.is_file():
        raise SystemExit(f"PROJECT_SOURCE_MISSING: {APPEARANCE_SOURCE}")
    return content, selected, base, depth, ip_root, encoder


def build_depth() -> Image.Image:
    depth = Image.new("L", (SIZE, SIZE), 16)
    draw = ImageDraw.Draw(depth)
    # 3.2-head body: 214 px head over a compact 520 px full silhouette.
    draw.ellipse((300, 60, 514, 274), fill=212)
    # Ponytail stays behind the head and never changes the body count.
    draw.ellipse((462, 118, 566, 310), fill=174)
    # Compact torso/hips.
    draw.polygon([(322, 260), (492, 254), (530, 468), (464, 544), (342, 534), (292, 456)], fill=192)
    draw.ellipse((330, 456, 494, 584), fill=186)
    # Short thick legs and boots.
    draw.polygon([(344, 532), (407, 532), (397, 680), (326, 680)], fill=178)
    draw.polygon([(424, 530), (482, 526), (510, 680), (438, 680)], fill=181)
    draw.rounded_rectangle((312, 655, 402, 712), radius=20, fill=204)
    draw.rounded_rectangle((430, 655, 526, 712), radius=20, fill=205)
    # Arms angled to shield and hip.
    draw.line((320, 316, 260, 460), fill=208, width=62)
    draw.ellipse((228, 430, 292, 498), fill=220)
    draw.line((490, 318, 548, 466), fill=205, width=62)
    draw.ellipse((520, 438, 584, 505), fill=218)
    # Independent left shield, smaller than R08 and clear of face.
    outer = [(62, 250), (132, 188), (245, 196), (304, 262), (296, 530), (226, 642), (112, 602), (56, 510)]
    inner = [(91, 270), (148, 222), (226, 228), (269, 278), (264, 507), (207, 596), (132, 568), (87, 492)]
    draw.polygon(outer, fill=235)
    draw.polygon(inner, fill=198)
    draw.ellipse((145, 350, 240, 445), fill=222)
    return Image.merge("RGB", (depth, depth, depth)).filter(ImageFilter.GaussianBlur(radius=6))


def appearance() -> Image.Image:
    image = Image.open(APPEARANCE_SOURCE).convert("RGB")
    return image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


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
        print("R12_CHIBI_DEPTH_POLICY_VALIDATION_OK")
        return 0

    output = args.output.resolve()
    if PROJECT_ROOT.resolve() not in output.parents:
        raise SystemExit("OUTPUT_BLOCKED: project output required")
    output.mkdir(parents=True, exist_ok=True)
    depth = build_depth()
    appearance_image = appearance()
    depth_path = output / "chr001_guardian_r12_project_depth.png"
    appearance_path = output / "chr001_guardian_r12_project_appearance.png"
    depth.save(depth_path, format="PNG", optimize=True)
    appearance_image.save(appearance_path, format="PNG", optimize=True)

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
    pipe.set_ip_adapter_scale(0.44)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(
        pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True
    )
    pipe.vae.enable_slicing()
    pipe.vae.enable_tiling()
    pipe.enable_model_cpu_offload(gpu_id=0)

    records = []
    for revision in range(1, args.count + 1):
        seed = 171120 + revision
        target = output / f"chr001_maeru_guardian_chibi_depth_r12v{revision:02d}_seed{seed}.png"
        if target.exists():
            raise SystemExit(f"REFUSE_OVERWRITE: {target}")
        result = pipe(
            prompt=PROMPT,
            negative_prompt=NEGATIVE,
            image=depth,
            ip_adapter_image=appearance_image,
            width=SIZE,
            height=SIZE,
            num_inference_steps=args.steps,
            guidance_scale=6.2,
            controlnet_conditioning_scale=0.74,
            control_guidance_start=0.0,
            control_guidance_end=0.82,
            generator=torch.Generator(device="cuda").manual_seed(seed),
        ).images[0]
        result.save(target, format="PNG", optimize=True)
        records.append({
            "asset_id": f"concept_chr001_guardian_chibi_depth_r12v{revision:02d}",
            "character_id": "CHR001",
            "character_gender": "FEMALE",
            "age_category": "ADULT",
            "attire_policy": "MAXIMUM_NON_EXPLICIT",
            "status": "ART_QA_CANDIDATE",
            "production_approved": False,
            "runtime_asset": False,
            "models": [BASE_ID, DEPTH_ID, IP_ID],
            "model_licenses": [selected[BASE_ID]["license"], selected[DEPTH_ID]["license"], selected[IP_ID]["license"]],
            "model_originals_preserved": True,
            "krea2_used": False,
            "appearance_source": APPEARANCE_SOURCE.relative_to(PROJECT_ROOT).as_posix(),
            "appearance_source_sha256": sha256(APPEARANCE_SOURCE),
            "depth_guide": depth_path.relative_to(PROJECT_ROOT).as_posix(),
            "seed": seed,
            "steps": args.steps,
            "ip_adapter_scale": 0.44,
            "controlnet_conditioning_scale": 0.74,
            "control_guidance_end": 0.82,
            "prompt": PROMPT,
            "negative_prompt": NEGATIVE,
            "path": target.relative_to(PROJECT_ROOT).as_posix(),
            "bytes": target.stat().st_size,
            "sha256": sha256(target),
            "qa_verdict": "UNREVIEWED",
            "integration_allowed": False,
        })
        print(f"R12_RENDERED {target}", flush=True)

    manifest = {
        "kind": "LOCAL_SDXL_DEPTH_IP_CHIBI_GUARDIAN_PILOT_R12",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "offline": True,
        "content_policy_version": content["policy_version"],
        "source_models_mutated": False,
        "production_approved": False,
        "records": records,
    }
    manifest_path = output / "chibi_depth_guardian_r12_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
