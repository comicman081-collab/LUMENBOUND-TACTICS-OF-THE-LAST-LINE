#!/usr/bin/env python3
"""Generate R06 role-first concepts with local SDXL and ControlNet Canny.

The Canny controls are original line guides drawn by this project. Local model
roots are read-only. Generated files remain unapproved QA candidates until the
manual female/adult/attire and role-silhouette gates are recorded.
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
from PIL import Image, ImageDraw
from transformers import CLIPTokenizer


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODEL_POLICY_PATH = PROJECT_ROOT / "tools" / "local_art_pipeline" / "model_policy.json"
CONTENT_POLICY_PATH = PROJECT_ROOT / "tools" / "policy" / "project_content_policy.json"
DEFAULT_OUTPUT = PROJECT_ROOT / "work" / "art_gen" / "sdxl_controlnet_role_pilot_r06"
BASE_ID = "stabilityai-sdxl-base-1.0-local"
CONTROL_ID = "diffusers-controlnet-canny-sdxl-1.0-local"
WIDTH = 704
HEIGHT = 1024

NEGATIVE = (
    "male, man, boy, masculine, androgynous, child, teen, underage, school uniform, juvenile body, nude, nipples, "
    "areola, genitals, explicit, transparent clothing, logo, text, watermark, signature, halo, gun, hood, hat, staff, "
    "extra limbs, bad hands, cropped feet, blurry face, low detail"
)

JOBS = {
    "CHR001_MAERU_GUARDIAN": {
        "seed": 171061,
        "guide_kind": "GUARDIAN_OCTAGON",
        "prompt": (
            "premium 3D anime RPG SD adult woman, mature feminine face, long chestnut ponytail, four-head curvy adult "
            "proportions, dynamic guardian stance, enormous octagonal teal tower shield, revealing non-explicit navy "
            "combat bodysuit, bare shoulders, exposed waist, opaque coverage chest and groin, thigh boots, full body, cel shading"
        ),
    },
    "CHR008_IRI_MEDIC": {
        "seed": 178061,
        "guide_kind": "MEDIC_DIAGNOSTIC_RING",
        "prompt": (
            "premium 3D anime RPG SD adult woman, mature feminine face, long mint ponytail, four-head curvy adult "
            "proportions, active field medic pose, large glowing diagnostic ring around forearm, revealing non-explicit "
            "teal medical bodysuit, bare shoulders, exposed waist, opaque coverage chest and groin, thigh boots, full body, cel shading"
        ),
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
    parser.add_argument("--count", type=int, default=1, choices=(1, 2))
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def validate_policies() -> tuple[dict, dict, Path, Path]:
    model_policy = json.loads(MODEL_POLICY_PATH.read_text(encoding="utf-8"))
    content_policy = json.loads(CONTENT_POLICY_PATH.read_text(encoding="utf-8"))
    character = content_policy["character_policy"]
    appearance = content_policy["appearance_policy"]
    if character["human_and_humanoid_characters"] != "FEMALE_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID: FEMALE_ONLY required")
    if character["age_category"] != "ADULT_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID: ADULT_ONLY required")
    if appearance["attire_exposure"] != "MAXIMUM_NON_EXPLICIT":
        raise SystemExit("CONTENT_POLICY_INVALID: MAXIMUM_NON_EXPLICIT required")

    selected = {row["id"]: row for row in model_policy["selected"]}
    base = selected.get(BASE_ID)
    control = selected.get(CONTROL_ID)
    if base is None or control is None:
        raise SystemExit("MODEL_BLOCKED: approved base/control model missing")
    base_path = Path(base["path"]).resolve()
    control_path = Path(control["path"]).resolve()
    for model_path in (base_path, control_path):
        if "krea" in str(model_path).lower() or not model_path.is_dir():
            raise SystemExit(f"MODEL_BLOCKED: {model_path}")
    if not (base_path / "LICENSE.md").is_file() or not (control_path / "config.json").is_file():
        raise SystemExit("MODEL_BLOCKED: local license/config evidence missing")

    required = tuple(term.lower() for term in character["required_positive_prompt_terms"])
    required += tuple(term.lower() for term in appearance["required_positive_prompt_terms"])
    forbidden = tuple(term.lower() for term in character["forbidden_positive_prompt_terms"])
    for job_id, job in JOBS.items():
        lowered = job["prompt"].lower()
        if not all(term in lowered for term in required):
            raise SystemExit(f"CONTENT_POLICY_BLOCK: {job_id} missing {required}")
        for term in forbidden:
            if re.search(rf"(?<![a-z]){re.escape(term)}(?![a-z])", lowered):
                raise SystemExit(f"CONTENT_POLICY_BLOCK: {job_id} contains {term}")
    return content_policy, selected, base_path, control_path


def line(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], width: int = 7) -> None:
    draw.line(points, fill=(255, 255, 255), width=width, joint="curve")


def ellipse(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], width: int = 7) -> None:
    draw.ellipse(box, outline=(255, 255, 255), width=width)


def polygon(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], width: int = 8) -> None:
    line(draw, points + [points[0]], width)


def draw_adult_woman_base(draw: ImageDraw.ImageDraw, center_x: int, pose: str) -> None:
    # Four-head stylization, tapered waist, adult hip/shoulder read, full feet.
    ellipse(draw, (center_x - 82, 90, center_x + 82, 260), 8)
    line(draw, [(center_x - 70, 145), (center_x - 108, 205), (center_x - 74, 312)], 9)
    line(draw, [(center_x + 70, 145), (center_x + 118, 225), (center_x + 70, 330)], 9)
    line(draw, [(center_x - 72, 286), (center_x - 105, 385), (center_x - 70, 515)], 8)
    line(draw, [(center_x + 72, 286), (center_x + 105, 385), (center_x + 70, 515)], 8)
    line(draw, [(center_x - 70, 515), (center_x - 108, 630), (center_x - 88, 730)], 8)
    line(draw, [(center_x + 70, 515), (center_x + 108, 630), (center_x + 88, 730)], 8)
    line(draw, [(center_x - 88, 730), (center_x - 92, 900), (center_x - 142, 952), (center_x - 58, 958)], 9)
    line(draw, [(center_x + 88, 730), (center_x + 92, 900), (center_x + 142, 952), (center_x + 58, 958)], 9)
    line(draw, [(center_x - 72, 312), (center_x, 345), (center_x + 72, 312)], 5)
    line(draw, [(center_x - 82, 600), (center_x, 636), (center_x + 82, 600)], 5)
    if pose == "GUARDIAN":
        line(draw, [(center_x - 78, 332), (center_x - 156, 470), (center_x - 210, 550)], 10)
        line(draw, [(center_x + 78, 332), (center_x + 18, 470), (center_x - 85, 560)], 10)
    else:
        line(draw, [(center_x - 78, 332), (center_x - 160, 452), (center_x - 94, 585)], 10)
        line(draw, [(center_x + 78, 332), (center_x + 170, 440), (center_x + 118, 580)], 10)


def build_guide(guide_kind: str) -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0))
    draw = ImageDraw.Draw(image)
    if guide_kind == "GUARDIAN_OCTAGON":
        draw_adult_woman_base(draw, 420, "GUARDIAN")
        outer = [(22, 365), (92, 285), (230, 258), (332, 330), (350, 645), (282, 820), (138, 920), (32, 825)]
        inner = [(54, 385), (112, 322), (220, 302), (298, 354), (312, 630), (250, 782), (145, 858), (68, 790)]
        polygon(draw, outer, 12)
        polygon(draw, inner, 7)
        line(draw, [(220, 302), (218, 858)], 6)
        line(draw, [(54, 385), (312, 630)], 5)
        line(draw, [(298, 354), (68, 790)], 5)
    elif guide_kind == "MEDIC_DIAGNOSTIC_RING":
        draw_adult_woman_base(draw, 350, "MEDIC")
        ellipse(draw, (70, 430, 365, 725), 13)
        ellipse(draw, (112, 472, 323, 683), 8)
        line(draw, [(217, 430), (217, 725)], 6)
        line(draw, [(70, 578), (365, 578)], 6)
        ellipse(draw, (92, 452, 343, 704), 4)
    else:
        raise ValueError(f"unknown guide: {guide_kind}")
    return image


def main() -> int:
    args = parse_args()
    content_policy, selected, base_path, control_path = validate_policies()
    tokenizer = CLIPTokenizer.from_pretrained(base_path / "tokenizer", local_files_only=True)
    tokenizer_2 = CLIPTokenizer.from_pretrained(base_path / "tokenizer_2", local_files_only=True)
    for prompt_id, prompt in {**{key: value["prompt"] for key, value in JOBS.items()}, "NEGATIVE": NEGATIVE}.items():
        lengths = [len(tokenizer(prompt, truncation=False).input_ids), len(tokenizer_2(prompt, truncation=False).input_ids)]
        print(f"PROMPT_TOKENS {prompt_id} {lengths}")
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {prompt_id} {lengths}")
    if args.validate_only:
        print("R06_CONTROLNET_POLICY_PROMPT_VALIDATION_OK")
        return 0

    output = args.output.resolve()
    if PROJECT_ROOT.resolve() not in output.parents:
        raise SystemExit("OUTPUT_BLOCKED: output must stay under project")
    output.mkdir(parents=True, exist_ok=True)

    controlnet = ControlNetModel.from_pretrained(
        control_path, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True
    )
    pipe = StableDiffusionXLControlNetPipeline.from_pretrained(
        base_path,
        controlnet=controlnet,
        torch_dtype=torch.float16,
        variant="fp16",
        use_safetensors=True,
        local_files_only=True,
    )
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(
        pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True
    )
    pipe.vae.enable_slicing()
    pipe.vae.enable_tiling()
    pipe.enable_attention_slicing("auto")
    pipe.enable_model_cpu_offload(gpu_id=0)

    records: list[dict] = []
    for job_id, job in JOBS.items():
        concept_dir = output / job_id
        concept_dir.mkdir(parents=True, exist_ok=True)
        guide = build_guide(job["guide_kind"])
        guide_path = concept_dir / f"{job_id.lower()}_project_guide.png"
        if guide_path.exists():
            raise SystemExit(f"REFUSE_OVERWRITE: {guide_path}")
        guide.save(guide_path, format="PNG", optimize=True)
        for revision in range(1, args.count + 1):
            seed = job["seed"] + revision - 1
            result_path = concept_dir / f"{job_id.lower()}_concept_r06v{revision:02d}_seed{seed}.png"
            if result_path.exists():
                raise SystemExit(f"REFUSE_OVERWRITE: {result_path}")
            generator = torch.Generator(device="cuda").manual_seed(seed)
            result = pipe(
                prompt=job["prompt"],
                negative_prompt=NEGATIVE,
                image=guide,
                width=WIDTH,
                height=HEIGHT,
                num_inference_steps=args.steps,
                guidance_scale=6.5,
                controlnet_conditioning_scale=0.82,
                control_guidance_start=0.0,
                control_guidance_end=0.82,
                generator=generator,
            ).images[0]
            result.save(result_path, format="PNG", optimize=True)
            records.append({
                "asset_id": f"concept_{job_id.lower()}_r{revision:02d}",
                "character_id": job_id.split("_", 1)[0],
                "character_gender": "FEMALE",
                "age_category": "ADULT",
                "attire_policy": "MAXIMUM_NON_EXPLICIT",
                "status": "ART_QA_CANDIDATE",
                "runtime_asset": False,
                "base_model": BASE_ID,
                "control_model": CONTROL_ID,
                "model_paths": [str(base_path), str(control_path)],
                "model_licenses": [selected[BASE_ID]["license"], selected[CONTROL_ID]["license"]],
                "model_originals_preserved": True,
                "krea2_used": False,
                "guide_kind": job["guide_kind"],
                "guide_source": "PROJECT_AUTHORED_VECTOR_LINES",
                "guide_path": str(guide_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
                "guide_sha256": sha256(guide_path),
                "seed": seed,
                "width": WIDTH,
                "height": HEIGHT,
                "steps": args.steps,
                "guidance_scale": 6.5,
                "controlnet_conditioning_scale": 0.82,
                "prompt": job["prompt"],
                "negative_prompt": NEGATIVE,
                "path": str(result_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
                "bytes": result_path.stat().st_size,
                "sha256": sha256(result_path),
                "qa_verdict": "UNREVIEWED",
                "visual_qa_verdicts": [],
                "integration_allowed": False,
            })

    manifest = {
        "kind": "LOCAL_SDXL_CONTROLNET_ROLE_PILOT_R06",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "offline": True,
        "content_policy_version": content_policy["policy_version"],
        "character_gender_policy": "FEMALE_ONLY",
        "age_policy": "ADULT_ONLY",
        "attire_policy": "MAXIMUM_NON_EXPLICIT",
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
