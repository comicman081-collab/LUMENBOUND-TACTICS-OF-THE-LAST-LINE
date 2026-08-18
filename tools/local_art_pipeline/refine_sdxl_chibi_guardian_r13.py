#!/usr/bin/env python3
"""R13 low-strength polish of the best project-owned R12 chibi Guardian."""
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
from diffusers import DPMSolverMultistepScheduler, StableDiffusionXLImg2ImgPipeline
from PIL import Image
from transformers import CLIPTokenizer


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MODEL_POLICY_PATH = PROJECT_ROOT / "tools" / "local_art_pipeline" / "model_policy.json"
CONTENT_POLICY_PATH = PROJECT_ROOT / "tools" / "policy" / "project_content_policy.json"
SOURCE = PROJECT_ROOT / "work" / "art_gen" / "sdxl_chibi_depth_guardian_r12" / "chr001_maeru_guardian_chibi_depth_r12v03_seed171123.png"
DEFAULT_OUTPUT = PROJECT_ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r13"
BASE_ID = "stabilityai-sdxl-base-1.0-local"
IP_ID = "h94-ip-adapter-sdxl-local"

PROMPT = (
    "premium 3D anime RPG adult woman, mature feminine 3-head chibi heroine, full body centered, large head short limbs, "
    "chestnut ponytail, cyan eyes, single octagonal teal shield left hand, teal split cape, ornate teal navy gold armor, "
    "revealing non-explicit bodysuit, bare shoulders waist thighs, opaque coverage, intricate metal leather cloth, polished game render"
)

NEGATIVE = (
    "male, man, boy, masculine, androgynous, child, teen, underage, juvenile, tall body, portrait, close-up, cropped feet, "
    "two shields, wing, wings, sword, nude, nipples, genitals, explicit, transparent clothing, text, "
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


def validate() -> tuple[dict, dict, Path, Path, Path]:
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
    for model_id in (BASE_ID, IP_ID):
        if model_id not in selected:
            raise SystemExit(f"MODEL_BLOCKED: {model_id}")
    base = Path(selected[BASE_ID]["path"]).resolve()
    ip_root = Path(selected[IP_ID]["path"]).resolve().parent
    encoder = Path(selected[IP_ID]["companion_image_encoder_path"]).resolve()
    for path in (base, ip_root, encoder):
        if "krea" in str(path).lower() or not path.exists():
            raise SystemExit(f"MODEL_BLOCKED: {path}")
    if not (base / "LICENSE.md").is_file() or not SOURCE.is_file():
        raise SystemExit("MODEL_BLOCKED_OR_SOURCE_MISSING")
    return content, selected, base, ip_root, encoder


def main() -> int:
    args = parse_args()
    content, selected, base, ip_root, encoder = validate()
    tokenizer = CLIPTokenizer.from_pretrained(base / "tokenizer", local_files_only=True)
    tokenizer_2 = CLIPTokenizer.from_pretrained(base / "tokenizer_2", local_files_only=True)
    for label, value in (("PROMPT", PROMPT), ("NEGATIVE", NEGATIVE)):
        lengths = [len(tokenizer(value, truncation=False).input_ids), len(tokenizer_2(value, truncation=False).input_ids)]
        print(f"PROMPT_TOKENS {label} {lengths}", flush=True)
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {label} {lengths}")
    if args.validate_only:
        print("R13_CHIBI_POLISH_POLICY_VALIDATION_OK")
        return 0

    output = args.output.resolve()
    if PROJECT_ROOT.resolve() not in output.parents:
        raise SystemExit("OUTPUT_BLOCKED: project output required")
    output.mkdir(parents=True, exist_ok=True)
    source_image = Image.open(SOURCE).convert("RGB").resize((768, 768), Image.Resampling.LANCZOS)

    pipe = StableDiffusionXLImg2ImgPipeline.from_pretrained(
        base, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True
    )
    pipe.load_ip_adapter(
        str(ip_root), subfolder="sdxl_models", weight_name="ip-adapter_sdxl_vit-h.safetensors",
        image_encoder_folder=str(encoder), local_files_only=True,
    )
    pipe.set_ip_adapter_scale(0.34)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(
        pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True
    )
    pipe.vae.enable_slicing()
    pipe.vae.enable_tiling()
    pipe.enable_model_cpu_offload(gpu_id=0)

    records = []
    for revision in range(1, args.count + 1):
        seed = 171130 + revision
        target = output / f"chr001_maeru_guardian_chibi_r13v{revision:02d}_seed{seed}.png"
        if target.exists():
            raise SystemExit(f"REFUSE_OVERWRITE: {target}")
        result = pipe(
            prompt=PROMPT,
            negative_prompt=NEGATIVE,
            image=source_image,
            ip_adapter_image=source_image,
            strength=0.30,
            guidance_scale=6.2,
            num_inference_steps=args.steps,
            generator=torch.Generator(device="cuda").manual_seed(seed),
        ).images[0]
        result.save(target, format="PNG", optimize=True)
        records.append({
            "asset_id": f"concept_chr001_guardian_chibi_r13v{revision:02d}",
            "character_id": "CHR001",
            "character_gender": "FEMALE",
            "age_category": "ADULT",
            "attire_policy": "MAXIMUM_NON_EXPLICIT",
            "status": "ART_QA_CANDIDATE",
            "production_approved": False,
            "runtime_asset": False,
            "source": SOURCE.relative_to(PROJECT_ROOT).as_posix(),
            "source_sha256": sha256(SOURCE),
            "models": [BASE_ID, IP_ID],
            "model_licenses": [selected[BASE_ID]["license"], selected[IP_ID]["license"]],
            "model_originals_preserved": True,
            "krea2_used": False,
            "seed": seed,
            "steps": args.steps,
            "strength": 0.30,
            "ip_adapter_scale": 0.34,
            "prompt": PROMPT,
            "negative_prompt": NEGATIVE,
            "path": target.relative_to(PROJECT_ROOT).as_posix(),
            "bytes": target.stat().st_size,
            "sha256": sha256(target),
            "qa_verdict": "UNREVIEWED",
            "integration_allowed": False,
        })
        print(f"R13_RENDERED {target}", flush=True)

    manifest = {
        "kind": "LOCAL_SDXL_IP_CHIBI_GUARDIAN_POLISH_R13",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "offline": True,
        "content_policy_version": content["policy_version"],
        "source_models_mutated": False,
        "production_approved": False,
        "records": records,
    }
    manifest_path = output / "chibi_guardian_r13_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
