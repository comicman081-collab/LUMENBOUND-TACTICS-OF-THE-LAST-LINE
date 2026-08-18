#!/usr/bin/env python3
"""Generate original premium-pilot concept candidates with local SDXL only.

The source model and Python environment are read-only. This script writes only
to the project work/art_gen tree. Outputs are concept QA candidates, not final
runtime art and never receive production approval automatically.
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
from diffusers import DPMSolverMultistepScheduler, StableDiffusionXLPipeline
from transformers import CLIPTokenizer


PROJECT_ROOT = Path(__file__).resolve().parents[2]
APPROVED_MODEL = Path(r"C:\AI_MODELS\sdxl-base-1.0")
CONTENT_POLICY = PROJECT_ROOT / "tools" / "policy" / "project_content_policy.json"
DEFAULT_OUTPUT = PROJECT_ROOT / "work" / "art_gen" / "sdxl_policy_pilot_r05"

NEGATIVE = (
    "male, man, boy, masculine, androgynous, child, teen, underage, school uniform, short boyish hair, nude, nipples, "
    "areola, genitals, explicit, transparent clothing, logo, text, watermark, signature, halo, gun, hood, hat, staff, "
    "extra limbs, bad hands, cropped feet, blurry face, low detail"
)

CONCEPTS = {
    "CHR001_MAERU_GUARDIAN": (
        "3D anime RPG chibi adult woman, clearly feminine adult face, long chestnut ponytail, curvy adult proportions, "
        "rescue guardian, dynamic pose, huge octagonal teal shield, revealing non-explicit navy bodysuit, deep neckline, "
        "bare shoulders, exposed midriff, side cutouts, opaque coverage chest and groin, thigh-high boots, full body, cel shading"
    ),
    "CHR008_IRI_MEDIC": (
        "3D anime RPG chibi adult woman, clearly feminine adult face, long mint hair, curvy adult proportions, field "
        "medic, active healing pose, diagnostic ring, revealing non-explicit teal medical bodysuit, deep neckline, "
        "bare shoulders, exposed midriff, high-cut hips, opaque coverage chest and groin, thigh-high boots, full body, cel shading"
    ),
}

SEEDS = {
    "CHR001_MAERU_GUARDIAN": [171011, 171012, 171013],
    "CHR008_IRI_MEDIC": [178011, 178012, 178013],
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, default=APPROVED_MODEL)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--width", type=int, default=704)
    parser.add_argument("--height", type=int, default=1024)
    parser.add_argument("--steps", type=int, default=28)
    parser.add_argument("--count", type=int, default=3, choices=(1, 2, 3))
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def validate_content_policy() -> dict:
    policy = json.loads(CONTENT_POLICY.read_text(encoding="utf-8"))
    character_policy = policy["character_policy"]
    if character_policy["human_and_humanoid_characters"] != "FEMALE_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID: project must remain FEMALE_ONLY")
    if character_policy["male_character_creation"] != "PROHIBITED":
        raise SystemExit("CONTENT_POLICY_INVALID: male character creation must remain prohibited")
    required = tuple(term.lower() for term in character_policy["required_positive_prompt_terms"])
    required += tuple(term.lower() for term in policy["appearance_policy"]["required_positive_prompt_terms"])
    forbidden = tuple(term.lower() for term in character_policy["forbidden_positive_prompt_terms"])
    for prompt_name, prompt_value in CONCEPTS.items():
        lowered = prompt_value.lower()
        if not all(term in lowered for term in required):
            raise SystemExit(f"FEMALE_ONLY_POLICY_BLOCK: {prompt_name} missing required terms {required}")
        for term in forbidden:
            if re.search(rf"(?<![a-z]){re.escape(term)}(?![a-z])", lowered):
                raise SystemExit(f"FEMALE_ONLY_POLICY_BLOCK: {prompt_name} contains forbidden term {term}")
    return policy


def main() -> int:
    args = parse_args()
    content_policy = validate_content_policy()
    model = args.model.resolve()
    approved = APPROVED_MODEL.resolve()
    if model != approved:
        raise SystemExit(f"MODEL_BLOCKED: only {approved} is approved; got {model}")
    if "krea" in str(model).lower():
        raise SystemExit("MODEL_BLOCKED: Krea2 is NON_COMMERCIAL_EXCLUDED")
    license_path = model / "LICENSE.md"
    model_index = model / "model_index.json"
    if not license_path.is_file() or not model_index.is_file():
        raise SystemExit("MODEL_BLOCKED: local SDXL license/model_index missing")
    if args.width % 8 or args.height % 8:
        raise SystemExit("width and height must be divisible by 8")

    tokenizer = CLIPTokenizer.from_pretrained(model / "tokenizer", local_files_only=True)
    tokenizer_2 = CLIPTokenizer.from_pretrained(model / "tokenizer_2", local_files_only=True)
    for prompt_name, prompt_value in {**CONCEPTS, "NEGATIVE": NEGATIVE}.items():
        token_lengths = [
            len(tokenizer(prompt_value, truncation=False).input_ids),
            len(tokenizer_2(prompt_value, truncation=False).input_ids),
        ]
        print(f"PROMPT_TOKENS {prompt_name} {token_lengths}")
        if max(token_lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {prompt_name} token_lengths={token_lengths}")
    if args.validate_only:
        print("PROMPT_VALIDATION_OK")
        return 0

    output = args.output.resolve()
    project = PROJECT_ROOT.resolve()
    if project not in output.parents:
        raise SystemExit(f"OUTPUT_BLOCKED: output must stay under {project}")
    output.mkdir(parents=True, exist_ok=True)

    pipe = StableDiffusionXLPipeline.from_pretrained(
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

    # Keep the original weights read-only and move inactive modules to CPU. The
    # 12 GB target GPU otherwise leaves too little headroom for SDXL VAE decode.
    pipe.vae.enable_slicing()
    pipe.vae.enable_tiling()
    pipe.enable_attention_slicing("auto")
    pipe.enable_model_cpu_offload(gpu_id=0)

    records: list[dict] = []
    for concept_id, prompt in CONCEPTS.items():
        concept_dir = output / concept_id
        concept_dir.mkdir(parents=True, exist_ok=True)
        for revision, seed in enumerate(SEEDS[concept_id][: args.count], start=1):
            generator = torch.Generator(device="cuda").manual_seed(seed)
            result = pipe(
                prompt=prompt,
                negative_prompt=NEGATIVE,
                width=args.width,
                height=args.height,
                num_inference_steps=args.steps,
                guidance_scale=6.5,
                generator=generator,
            ).images[0]
            filename = f"{concept_id.lower()}_concept_r05v{revision:02d}_seed{seed}.png"
            target = concept_dir / filename
            if target.exists():
                raise SystemExit(f"REFUSE_OVERWRITE: {target}")
            result.save(target, format="PNG", optimize=True)
            records.append(
                {
                    "asset_id": f"concept_{concept_id.lower()}_r{revision:02d}",
                    "character_id": concept_id.split("_", 1)[0],
                    "character_gender": "FEMALE",
                    "age_category": "ADULT",
                    "attire_policy": "MAXIMUM_NON_EXPLICIT",
                    "status": "ART_QA_CANDIDATE",
                    "runtime_asset": False,
                    "model": "stabilityai-sdxl-base-1.0-local",
                    "model_path": str(model),
                    "model_license": "CreativeML Open RAIL++-M",
                    "model_original_preserved": True,
                    "krea2_used": False,
                    "seed": seed,
                    "width": args.width,
                    "height": args.height,
                    "steps": args.steps,
                    "guidance_scale": 6.5,
                    "prompt": prompt,
                    "negative_prompt": NEGATIVE,
                    "path": str(target.relative_to(project)).replace("\\", "/"),
                    "bytes": target.stat().st_size,
                    "sha256": sha256(target),
                    "qa_verdict": "UNREVIEWED",
                    "visual_qa_verdicts": [],
                    "integration_allowed": False,
                }
            )

    manifest = {
        "kind": "LOCAL_SDXL_POLICY_PREMIUM_PILOT_R05",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "offline": True,
        "content_policy_version": content_policy["policy_version"],
        "character_gender_policy": "FEMALE_ONLY",
        "age_policy": "ADULT_ONLY",
        "attire_policy": "MAXIMUM_NON_EXPLICIT",
        "source_model_mutated": False,
        "production_approved": False,
        "records": records,
    }
    manifest_path = output / "concept_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "count": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
