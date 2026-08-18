#!/usr/bin/env python3
"""Offline R04 structure-lock pilot using local SDXL + ControlNet Canny.

The conditioning images combine edges from project-owned concepts with
project-authored prop geometry. All model roots remain read-only and every
output stays an unapproved ART_QA_CANDIDATE until visual inspection.
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

import cv2
import numpy as np
import torch
from diffusers import ControlNetModel, DPMSolverMultistepScheduler, StableDiffusionXLControlNetImg2ImgPipeline
from PIL import Image, ImageDraw
from transformers import CLIPTokenizer


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODEL_POLICY_PATH = PROJECT_ROOT / "tools" / "local_art_pipeline" / "model_policy.json"
CONTENT_POLICY_PATH = PROJECT_ROOT / "tools" / "policy" / "project_content_policy.json"
DEFAULT_OUTPUT = PROJECT_ROOT / "work" / "art_gen" / "sdxl_controlnet_pilot_r04"
BASE_ID = "stabilityai-sdxl-base-1.0-local"
CONTROL_ID = "diffusers-controlnet-canny-sdxl-1.0-local"

NEGATIVE = (
    "male, man, boy, masculine, child, school uniform, halo, gun, logo, text, watermark, signature, "
    "hood, hat, leaf shield, round shield, staff, static pose, fused fingers, extra fingers, extra limbs, "
    "bad hands, broken anatomy, cropped feet, blurry face, flat materials, low detail"
)

JOBS = {
    "CHR001_GUARDIAN_R04": {
        "input": PROJECT_ROOT / "tools" / "premium_asset_factory" / "concept_inputs" / "selected" / "CHR001_GUARDIAN_DIRECTION_R02.png",
        "input_sha256": "347deb650b7c86294bb60612560d730c1b087366a1ec583aaa0f286b28c1dec8",
        "seed": 171041,
        "prompt": (
            "premium 3D anime RPG chibi adult woman rescue guardian, three-head body, layered chestnut bob, "
            "navy ivory utility coat, orange piping, clean hands gripping huge symmetrical octagonal rescue "
            "shield, straight eight-sided brass frame, teal glass core, detailed cloth leather metal, polished cel shading"
        ),
        "guide_kind": "OCTAGONAL_SHIELD",
        "strength": 0.48,
        "control_scale": 0.95,
    },
    "CHR008_MEDIC_R04": {
        "input": PROJECT_ROOT / "tools" / "premium_asset_factory" / "concept_inputs" / "selected" / "CHR008_MEDIC_FACE_COLOR_DIRECTION_R02.png",
        "input_sha256": "11f75e6b4af853383512bf0c96305bb92d820d851c75c8d0aefea6d8a22db7d4",
        "seed": 178041,
        "prompt": (
            "premium 3D anime RPG chibi adult woman field medic, layered mint asymmetric bob, teal ivory utility "
            "coat, active healing gesture, both clean hands operating large forearm diagnostic ring, split teal "
            "glass lens, coral piping, glass ampoules, detailed cloth glass metal, polished cel shading"
        ),
        "guide_kind": "DIAGNOSTIC_RING",
        "strength": 0.44,
        "control_scale": 0.90,
    },
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--steps", type=int, default=30)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def validate_policies() -> tuple[dict, Path, Path]:
    model_policy = json.loads(MODEL_POLICY_PATH.read_text(encoding="utf-8"))
    content_policy = json.loads(CONTENT_POLICY_PATH.read_text(encoding="utf-8"))
    if content_policy["character_policy"]["human_and_humanoid_characters"] != "FEMALE_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID: FEMALE_ONLY required")
    selected = {row["id"]: row for row in model_policy["selected"]}
    base = selected.get(BASE_ID)
    control = selected.get(CONTROL_ID)
    if base is None or control is None:
        raise SystemExit("MODEL_BLOCKED: selected base/control model missing")
    base_path = Path(base["path"]).resolve()
    control_path = Path(control["path"]).resolve()
    for model_path in (base_path, control_path):
        if "krea" in str(model_path).lower() or not model_path.is_dir():
            raise SystemExit(f"MODEL_BLOCKED: {model_path}")
    if not (base_path / "LICENSE.md").is_file() or not (control_path / "config.json").is_file():
        raise SystemExit("MODEL_BLOCKED: local evidence/config missing")
    forbidden = content_policy["character_policy"]["forbidden_positive_prompt_terms"]
    for job_id, job in JOBS.items():
        lowered = job["prompt"].lower()
        if "adult woman" not in lowered:
            raise SystemExit(f"FEMALE_ONLY_POLICY_BLOCK: {job_id}")
        for term in forbidden:
            if re.search(rf"(?<![a-z]){re.escape(term.lower())}(?![a-z])", lowered):
                raise SystemExit(f"FEMALE_ONLY_POLICY_BLOCK: {job_id} contains {term}")
    return content_policy, base_path, control_path


def base_canny(image: Image.Image) -> Image.Image:
    array = np.array(image.convert("RGB"))
    edges = cv2.Canny(array, 100, 200)
    return Image.fromarray(np.repeat(edges[:, :, None], 3, axis=2))


def draw_double_polyline(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], width: int = 8) -> None:
    loop = points + [points[0]]
    draw.line(loop, fill=(255, 255, 255), width=width, joint="curve")


def build_control(image: Image.Image, guide_kind: str) -> Image.Image:
    control = base_canny(image)
    draw = ImageDraw.Draw(control)
    if guide_kind == "OCTAGONAL_SHIELD":
        draw.rectangle((0, 500, 274, 1023), fill=(0, 0, 0))
        outer = [(18, 665), (70, 575), (170, 535), (252, 605), (268, 790), (215, 935), (105, 1005), (22, 910)]
        inner = [(43, 680), (87, 610), (162, 578), (224, 630), (238, 784), (194, 910), (111, 963), (49, 888)]
        draw_double_polyline(draw, outer, 10)
        draw_double_polyline(draw, inner, 7)
        draw.line((172, 535, 170, 958), fill=(255, 255, 255), width=5)
        draw.line((43, 680, 238, 784), fill=(255, 255, 255), width=4)
    elif guide_kind == "DIAGNOSTIC_RING":
        draw.rectangle((55, 520, 660, 880), fill=(0, 0, 0))
        draw.ellipse((100, 585, 355, 825), outline=(255, 255, 255), width=10)
        draw.ellipse((132, 618, 323, 792), outline=(255, 255, 255), width=7)
        draw.line((225, 585, 225, 825), fill=(255, 255, 255), width=6)
        draw.line((100, 705, 355, 705), fill=(255, 255, 255), width=5)
        draw.line((355, 705, 510, 660), fill=(255, 255, 255), width=8)
        draw.ellipse((485, 625, 555, 695), outline=(255, 255, 255), width=7)
    else:
        raise ValueError(f"unknown guide kind: {guide_kind}")
    return control


def main() -> int:
    raise SystemExit("PIPELINE_BLOCKED: R02 inputs failed the current FEMALE/ADULT/ATTIRE visual policy")
    args = parse_args()
    content_policy, base_path, control_path = validate_policies()
    tokenizer = CLIPTokenizer.from_pretrained(base_path / "tokenizer", local_files_only=True)
    tokenizer_2 = CLIPTokenizer.from_pretrained(base_path / "tokenizer_2", local_files_only=True)
    for prompt_id, prompt in {**{key: value["prompt"] for key, value in JOBS.items()}, "NEGATIVE": NEGATIVE}.items():
        lengths = [len(tokenizer(prompt, truncation=False).input_ids), len(tokenizer_2(prompt, truncation=False).input_ids)]
        print(f"PROMPT_TOKENS {prompt_id} {lengths}")
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {prompt_id} {lengths}")
    for job_id, job in JOBS.items():
        if sha256(job["input"]) != job["input_sha256"]:
            raise SystemExit(f"INPUT_SHA256_MISMATCH: {job_id}")
    if args.validate_only:
        print("CONTROLNET_POLICY_PROMPT_INPUT_VALIDATION_OK")
        return 0

    output = args.output.resolve()
    if PROJECT_ROOT.resolve() not in output.parents:
        raise SystemExit("OUTPUT_BLOCKED: output must stay under project")
    output.mkdir(parents=True, exist_ok=True)

    controlnet = ControlNetModel.from_pretrained(
        control_path,
        torch_dtype=torch.float16,
        variant="fp16",
        use_safetensors=True,
        local_files_only=True,
    )
    pipe = StableDiffusionXLControlNetImg2ImgPipeline.from_pretrained(
        base_path,
        controlnet=controlnet,
        torch_dtype=torch.float16,
        variant="fp16",
        use_safetensors=True,
        local_files_only=True,
    )
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True)
    pipe.vae.enable_slicing()
    pipe.vae.enable_tiling()
    pipe.enable_attention_slicing("auto")
    pipe.enable_model_cpu_offload(gpu_id=0)

    records = []
    for job_id, job in JOBS.items():
        source = Image.open(job["input"]).convert("RGB")
        control = build_control(source, job["guide_kind"])
        control_path_out = output / f"{job_id.lower()}_control.png"
        result_path = output / f"{job_id.lower()}_seed{job['seed']}.png"
        if control_path_out.exists() or result_path.exists():
            raise SystemExit(f"REFUSE_OVERWRITE: {job_id}")
        control.save(control_path_out, format="PNG", optimize=True)
        generator = torch.Generator(device="cuda").manual_seed(job["seed"])
        result = pipe(
            prompt=job["prompt"],
            negative_prompt=NEGATIVE,
            image=source,
            control_image=control,
            strength=job["strength"],
            controlnet_conditioning_scale=job["control_scale"],
            guidance_scale=6.5,
            num_inference_steps=args.steps,
            generator=generator,
        ).images[0]
        result.save(result_path, format="PNG", optimize=True)
        records.append({
            "job_id": job_id,
            "character_id": job_id.split("_", 1)[0],
            "character_gender": "FEMALE",
            "status": "ART_QA_CANDIDATE",
            "production_approved": False,
            "base_model": BASE_ID,
            "control_model": CONTROL_ID,
            "model_licenses": ["CreativeML Open RAIL++-M"],
            "model_originals_preserved": True,
            "krea2_used": False,
            "input_path": str(job["input"].relative_to(PROJECT_ROOT)).replace("\\", "/"),
            "input_sha256": job["input_sha256"],
            "control_path": str(control_path_out.relative_to(PROJECT_ROOT)).replace("\\", "/"),
            "control_sha256": sha256(control_path_out),
            "output_path": str(result_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
            "output_sha256": sha256(result_path),
            "guide_kind": job["guide_kind"],
            "seed": job["seed"],
            "steps": args.steps,
            "strength": job["strength"],
            "control_scale": job["control_scale"],
            "prompt": job["prompt"],
            "negative_prompt": NEGATIVE,
            "qa_verdict": "UNREVIEWED",
        })

    manifest = {
        "kind": "LOCAL_SDXL_CONTROLNET_PREMIUM_PILOT_R04",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "offline": True,
        "content_policy_version": content_policy["policy_version"],
        "character_gender_policy": "FEMALE_ONLY",
        "source_models_mutated": False,
        "production_approved": False,
        "records": records,
    }
    manifest_path = output / "controlnet_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
