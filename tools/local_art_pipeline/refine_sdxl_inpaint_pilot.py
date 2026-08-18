#!/usr/bin/env python3
"""Targeted offline pilot corrections with the approved local SDXL inpaint model.

Inputs are project-owned SDXL concept candidates. Model roots stay read-only;
only masks, corrected candidates, and a provenance manifest are written under
the project work tree. Outputs remain ART_QA_CANDIDATE.
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
from diffusers import AutoPipelineForInpainting, DPMSolverMultistepScheduler
from PIL import Image, ImageDraw, ImageFilter
from transformers import CLIPTokenizer


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODEL_POLICY_PATH = PROJECT_ROOT / "tools" / "local_art_pipeline" / "model_policy.json"
CONTENT_POLICY_PATH = PROJECT_ROOT / "tools" / "policy" / "project_content_policy.json"
APPROVED_MODEL_ID = "diffusers-sdxl-inpaint-0.1-local"
DEFAULT_OUTPUT = PROJECT_ROOT / "work" / "art_gen" / "sdxl_inpaint_pilot_r03"

NEGATIVE = (
    "male, man, boy, masculine, child, school uniform, halo, gun, logo, text, watermark, hood, hat, "
    "leaf shield, round shield, staff, static pose, fused fingers, extra fingers, extra limbs, bad hands, "
    "broken anatomy, cropped feet, blurry face, flat materials, low detail"
)

JOBS = {
    "CHR001_GUARDIAN_R03": {
        "input": PROJECT_ROOT / "tools" / "premium_asset_factory" / "concept_inputs" / "selected" / "CHR001_GUARDIAN_DIRECTION_R02.png",
        "expected_input_sha256": "347deb650b7c86294bb60612560d730c1b087366a1ec583aaa0f286b28c1dec8",
        "seed": 171031,
        "prompt": (
            "premium 3D anime RPG chibi adult woman rescue guardian, three-head body, layered chestnut bob, "
            "bare head, navy ivory utility coat, orange piping, clean hands gripping huge symmetrical octagonal "
            "rescue shield, straight eight-sided metal frame, teal glass core, polished cel shading, full body"
        ),
        "mask_boxes": [(0, 500, 255, 1024), (410, 0, 704, 360)],
        "qa_target": "replace leaf shield with octagonal rescue shield and remove hood",
    },
    "CHR008_MEDIC_R03": {
        "input": PROJECT_ROOT / "tools" / "premium_asset_factory" / "concept_inputs" / "selected" / "CHR008_MEDIC_FACE_COLOR_DIRECTION_R02.png",
        "expected_input_sha256": "11f75e6b4af853383512bf0c96305bb92d820d851c75c8d0aefea6d8a22db7d4",
        "seed": 178031,
        "prompt": (
            "premium 3D anime RPG chibi adult woman field medic, layered mint asymmetric bob, teal ivory rescue coat, "
            "active healing pose, clean hands operating large forearm diagnostic ring, split teal glass lens, coral "
            "piping, glass ampoules, detailed cloth glass metal, polished cel shading, full body"
        ),
        "mask_boxes": [(65, 530, 650, 875)],
        "qa_target": "add readable forearm diagnostic ring and active medic gesture",
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


def load_and_validate_policies() -> tuple[dict, Path]:
    model_policy = json.loads(MODEL_POLICY_PATH.read_text(encoding="utf-8"))
    content_policy = json.loads(CONTENT_POLICY_PATH.read_text(encoding="utf-8"))
    if content_policy["character_policy"]["human_and_humanoid_characters"] != "FEMALE_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID: FEMALE_ONLY is required")
    selected = {row["id"]: row for row in model_policy["selected"]}
    approved = selected.get(APPROVED_MODEL_ID)
    if approved is None:
        raise SystemExit(f"MODEL_BLOCKED: {APPROVED_MODEL_ID} is not selected")
    if approved["commercial_use"] != "ALLOWED_SUBJECT_TO_LICENSE_RESTRICTIONS":
        raise SystemExit("MODEL_BLOCKED: commercial-use policy state is invalid")
    model = Path(approved["path"]).resolve()
    if "krea" in str(model).lower() or not (model / "model_index.json").is_file():
        raise SystemExit(f"MODEL_BLOCKED: invalid local model path {model}")
    forbidden = content_policy["character_policy"]["forbidden_positive_prompt_terms"]
    for job_id, job in JOBS.items():
        lowered = job["prompt"].lower()
        if "adult woman" not in lowered:
            raise SystemExit(f"FEMALE_ONLY_POLICY_BLOCK: {job_id}")
        for term in forbidden:
            if re.search(rf"(?<![a-z]){re.escape(term.lower())}(?![a-z])", lowered):
                raise SystemExit(f"FEMALE_ONLY_POLICY_BLOCK: {job_id} contains {term}")
    return content_policy, model


def make_mask(size: tuple[int, int], boxes: list[tuple[int, int, int, int]]) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    for box in boxes:
        draw.rounded_rectangle(box, radius=28, fill=255)
    return mask.filter(ImageFilter.GaussianBlur(radius=10))


def main() -> int:
    raise SystemExit("PIPELINE_BLOCKED: R02 inputs failed the current FEMALE/ADULT/ATTIRE visual policy")
    args = parse_args()
    content_policy, model = load_and_validate_policies()
    tokenizer = CLIPTokenizer.from_pretrained(model / "tokenizer", local_files_only=True)
    tokenizer_2 = CLIPTokenizer.from_pretrained(model / "tokenizer_2", local_files_only=True)
    for prompt_name, prompt_value in {**{key: value["prompt"] for key, value in JOBS.items()}, "NEGATIVE": NEGATIVE}.items():
        lengths = [
            len(tokenizer(prompt_value, truncation=False).input_ids),
            len(tokenizer_2(prompt_value, truncation=False).input_ids),
        ]
        print(f"PROMPT_TOKENS {prompt_name} {lengths}")
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {prompt_name} {lengths}")
    if args.validate_only:
        print("INPAINT_POLICY_AND_PROMPT_VALIDATION_OK")
        return 0

    output = args.output.resolve()
    if PROJECT_ROOT.resolve() not in output.parents:
        raise SystemExit("OUTPUT_BLOCKED: output must stay inside project")
    output.mkdir(parents=True, exist_ok=True)

    pipe = AutoPipelineForInpainting.from_pretrained(
        model,
        torch_dtype=torch.float16,
        variant="fp16",
        use_safetensors=True,
        local_files_only=True,
    )
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(
        pipe.scheduler.config,
        algorithm_type="dpmsolver++",
        use_karras_sigmas=True,
    )
    pipe.vae.enable_slicing()
    pipe.vae.enable_tiling()
    pipe.enable_attention_slicing("auto")
    pipe.enable_model_cpu_offload(gpu_id=0)

    records = []
    for job_id, job in JOBS.items():
        input_path = job["input"].resolve()
        if sha256(input_path) != job["expected_input_sha256"]:
            raise SystemExit(f"INPUT_SHA256_MISMATCH: {job_id}")
        image = Image.open(input_path).convert("RGB")
        mask = make_mask(image.size, job["mask_boxes"])
        mask_path = output / f"{job_id.lower()}_mask.png"
        result_path = output / f"{job_id.lower()}_seed{job['seed']}.png"
        if mask_path.exists() or result_path.exists():
            raise SystemExit(f"REFUSE_OVERWRITE: {job_id}")
        mask.save(mask_path, format="PNG", optimize=True)
        generator = torch.Generator(device="cuda").manual_seed(job["seed"])
        result = pipe(
            prompt=job["prompt"],
            negative_prompt=NEGATIVE,
            image=image,
            mask_image=mask,
            width=image.width,
            height=image.height,
            strength=0.985,
            guidance_scale=7.0,
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
            "source_model": APPROVED_MODEL_ID,
            "source_model_path": str(model),
            "source_model_license": "CreativeML Open RAIL++-M",
            "model_original_preserved": True,
            "krea2_used": False,
            "input_path": str(input_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
            "input_sha256": job["expected_input_sha256"],
            "mask_path": str(mask_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
            "mask_sha256": sha256(mask_path),
            "output_path": str(result_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
            "output_sha256": sha256(result_path),
            "seed": job["seed"],
            "steps": args.steps,
            "prompt": job["prompt"],
            "negative_prompt": NEGATIVE,
            "qa_target": job["qa_target"],
            "qa_verdict": "UNREVIEWED",
        })

    manifest = {
        "kind": "LOCAL_SDXL_INPAINT_PREMIUM_PILOT_R03",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "offline": True,
        "content_policy_version": content_policy["policy_version"],
        "character_gender_policy": "FEMALE_ONLY",
        "source_model_mutated": False,
        "production_approved": False,
        "records": records,
    }
    manifest_path = output / "inpaint_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
