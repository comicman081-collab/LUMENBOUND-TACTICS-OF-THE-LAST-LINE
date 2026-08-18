#!/usr/bin/env python3
"""Generate R07 full-body role concepts with local SDXL depth guidance.

Unlike the rejected R06 edge mesh, these project-authored controls contain
broad depth masses only. They constrain framing and role props while leaving
the diffusion model room to render faces, hands, clothing, and materials.
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
DEFAULT_OUTPUT = PROJECT_ROOT / "work" / "art_gen" / "sdxl_depth_role_pilot_r07"
BASE_ID = "stabilityai-sdxl-base-1.0-local"
CONTROL_ID = "diffusers-controlnet-depth-sdxl-1.0-local"
WIDTH = 704
HEIGHT = 1024

NEGATIVE = (
    "male, man, boy, masculine, androgynous, child, teen, underage, school uniform, juvenile body, portrait, close-up, "
    "nude, nipples, areola, genitals, explicit, transparent clothing, featureless face, mask, text, watermark, "
    "extra limbs, bad hands, cropped feet, blurry face, low detail"
)

JOBS = {
    "CHR001_MAERU_GUARDIAN": {
        "seed": 171071,
        "guide_kind": "GUARDIAN_DEPTH",
        "prompt": (
            "full-length premium 3D anime RPG SD adult woman, mature feminine face, long chestnut ponytail, four-head "
            "adult proportions, boots visible, dynamic guardian stance, enormous octagonal teal tower shield, revealing "
            "non-explicit navy combat bodysuit, bare shoulders and waist, opaque coverage chest and groin, polished cel shading"
        ),
    },
    "CHR008_IRI_MEDIC": {
        "seed": 178071,
        "guide_kind": "MEDIC_DEPTH",
        "prompt": (
            "full-length premium 3D anime RPG SD adult woman, mature feminine face, long mint ponytail, four-head adult "
            "proportions, boots visible, active field medic pose, large glowing diagnostic ring around forearm, revealing "
            "non-explicit teal medical bodysuit, bare shoulders and waist, opaque coverage chest and groin, polished cel shading"
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
    parser.add_argument("--steps", type=int, default=32)
    parser.add_argument("--count", type=int, default=1, choices=(1, 2))
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def validate_policies() -> tuple[dict, dict, Path, Path]:
    model_policy = json.loads(MODEL_POLICY_PATH.read_text(encoding="utf-8"))
    content_policy = json.loads(CONTENT_POLICY_PATH.read_text(encoding="utf-8"))
    character = content_policy["character_policy"]
    appearance = content_policy["appearance_policy"]
    if character["human_and_humanoid_characters"] != "FEMALE_ONLY" or character["age_category"] != "ADULT_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID: FEMALE_ONLY and ADULT_ONLY required")
    if appearance["attire_exposure"] != "MAXIMUM_NON_EXPLICIT":
        raise SystemExit("CONTENT_POLICY_INVALID: MAXIMUM_NON_EXPLICIT required")
    selected = {row["id"]: row for row in model_policy["selected"]}
    base = selected.get(BASE_ID)
    control = selected.get(CONTROL_ID)
    if base is None or control is None:
        raise SystemExit("MODEL_BLOCKED: approved base/depth model missing")
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


def adult_body_depth(draw: ImageDraw.ImageDraw, cx: int, arm_pose: str) -> None:
    # Far-to-near grayscale masses with a four-head full-body framing.
    draw.ellipse((cx - 94, 82, cx + 94, 276), fill=188)
    draw.polygon([(cx - 82, 245), (cx + 82, 245), (cx + 68, 540), (cx, 612), (cx - 68, 540)], fill=174)
    draw.ellipse((cx - 92, 500, cx + 92, 680), fill=182)
    draw.polygon([(cx - 82, 615), (cx - 16, 615), (cx - 42, 946), (cx - 116, 946)], fill=168)
    draw.polygon([(cx + 16, 615), (cx + 82, 615), (cx + 116, 946), (cx + 42, 946)], fill=168)
    if arm_pose == "GUARDIAN":
        draw.line((cx - 64, 300, cx - 188, 570), fill=198, width=58)
        draw.line((cx + 64, 300, cx - 18, 565), fill=196, width=58)
    else:
        draw.line((cx - 64, 300, cx - 172, 555), fill=196, width=58)
        draw.line((cx + 64, 300, cx + 172, 540), fill=196, width=58)


def build_depth(guide_kind: str) -> Image.Image:
    depth = Image.new("L", (WIDTH, HEIGHT), 30)
    draw = ImageDraw.Draw(depth)
    if guide_kind == "GUARDIAN_DEPTH":
        adult_body_depth(draw, 432, "GUARDIAN")
        shield = [(18, 355), (88, 270), (226, 250), (332, 330), (346, 650), (278, 824), (136, 922), (28, 825)]
        draw.polygon(shield, fill=222)
        inner = [(58, 382), (112, 318), (216, 300), (294, 358), (306, 630), (248, 780), (144, 854), (70, 786)]
        draw.polygon(inner, fill=202)
    elif guide_kind == "MEDIC_DEPTH":
        adult_body_depth(draw, 365, "MEDIC")
        draw.ellipse((70, 410, 376, 716), outline=232, width=38)
        draw.ellipse((111, 451, 335, 675), outline=210, width=12)
    else:
        raise ValueError(f"unknown guide: {guide_kind}")
    depth = depth.filter(ImageFilter.GaussianBlur(radius=7))
    return Image.merge("RGB", (depth, depth, depth))


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
        print("R07_DEPTH_POLICY_PROMPT_VALIDATION_OK")
        return 0

    output = args.output.resolve()
    if PROJECT_ROOT.resolve() not in output.parents:
        raise SystemExit("OUTPUT_BLOCKED: output must stay under project")
    output.mkdir(parents=True, exist_ok=True)
    controlnet = ControlNetModel.from_pretrained(
        control_path, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True
    )
    pipe = StableDiffusionXLControlNetPipeline.from_pretrained(
        base_path, controlnet=controlnet, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True
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
        guide = build_depth(job["guide_kind"])
        guide_path = concept_dir / f"{job_id.lower()}_project_depth.png"
        if guide_path.exists():
            raise SystemExit(f"REFUSE_OVERWRITE: {guide_path}")
        guide.save(guide_path, format="PNG", optimize=True)
        for revision in range(1, args.count + 1):
            seed = job["seed"] + revision - 1
            result_path = concept_dir / f"{job_id.lower()}_concept_r07v{revision:02d}_seed{seed}.png"
            if result_path.exists():
                raise SystemExit(f"REFUSE_OVERWRITE: {result_path}")
            generator = torch.Generator(device="cuda").manual_seed(seed)
            result = pipe(
                prompt=job["prompt"], negative_prompt=NEGATIVE, image=guide, width=WIDTH, height=HEIGHT,
                num_inference_steps=args.steps, guidance_scale=6.5, controlnet_conditioning_scale=0.58,
                control_guidance_start=0.0, control_guidance_end=0.68, generator=generator,
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
                "guide_source": "PROJECT_AUTHORED_DEPTH_MASSES",
                "guide_path": str(guide_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
                "guide_sha256": sha256(guide_path),
                "seed": seed,
                "width": WIDTH,
                "height": HEIGHT,
                "steps": args.steps,
                "guidance_scale": 6.5,
                "controlnet_conditioning_scale": 0.58,
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
        "kind": "LOCAL_SDXL_DEPTH_ROLE_PILOT_R07",
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
    manifest_path = output / "depth_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
