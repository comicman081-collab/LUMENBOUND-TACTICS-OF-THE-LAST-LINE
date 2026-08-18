#!/usr/bin/env python3
"""R25 local-only grip repair for the lower-right battle-view guardian.

This pass deliberately edits the shield/body seam as one connected structure.
The model sources stay read-only; only project-owned candidates are written.
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
from diffusers import DPMSolverMultistepScheduler, StableDiffusionXLInpaintPipeline
from PIL import Image, ImageDraw, ImageFilter
from transformers import CLIPTokenizer


ROOT = Path(__file__).resolve().parents[2]
MODEL_POLICY = ROOT / "tools" / "local_art_pipeline" / "model_policy.json"
CONTENT_POLICY = ROOT / "tools" / "policy" / "project_content_policy.json"
SOURCE = ROOT / "work" / "art_gen" / "guardian_combat_direction_r24" / "chr001_maeru_guardian_combat_right30_r24_shift45.png"
OUTPUT = ROOT / "work" / "art_gen" / "sdxl_guardian_combat_grip_r25"
MODEL_ID = "diffusers-sdxl-inpaint-0.1-local"
SIZE = 768
PROMPT = (
    "polished 3D anime RPG adult woman, mature athletic chibi guardian looking lower-right, revealing non-explicit teal gold bikini armor, opaque coverage, "
    "bare abdomen hips thighs, one large teal shield held close, visible left hand gripping handle behind rim, bent wrist and forearm physically connected, game render"
)
NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, nude, nipples, genitals, explicit, covered abdomen, bodysuit, "
    "floating shield, detached shield, gap, missing hand, extra hand, extra arm, fused fingers, second shield, weapon, text, watermark, blurry"
)


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def cli() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=4, choices=(1, 2, 3, 4))
    parser.add_argument("--steps", type=int, default=46)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def preflight() -> tuple[dict, dict, Path]:
    content = json.loads(CONTENT_POLICY.read_text(encoding="utf-8"))
    policy = json.loads(MODEL_POLICY.read_text(encoding="utf-8"))
    cp, ap = content["character_policy"], content["appearance_policy"]
    if cp["human_and_humanoid_characters"] != "FEMALE_ONLY" or cp["age_category"] != "ADULT_ONLY":
        raise SystemExit("CONTENT_POLICY_INVALID")
    if ap["attire_exposure"] != "MAXIMUM_NON_EXPLICIT":
        raise SystemExit("ATTIRE_POLICY_INVALID")
    required = tuple(cp["required_positive_prompt_terms"]) + tuple(ap["required_positive_prompt_terms"])
    lower = PROMPT.lower()
    if not all(term.lower() in lower for term in required):
        raise SystemExit(f"CONTENT_POLICY_BLOCK: {required}")
    for term in cp["forbidden_positive_prompt_terms"]:
        if re.search(rf"(?<![a-z]){re.escape(term.lower())}(?![a-z])", lower):
            raise SystemExit(f"CONTENT_POLICY_BLOCK: {term}")
    selected = {row["id"]: row for row in policy["selected"]}
    if MODEL_ID not in selected:
        raise SystemExit(f"MODEL_BLOCKED: {MODEL_ID}")
    model = Path(selected[MODEL_ID]["path"]).resolve()
    if "krea" in str(model).lower() or not (model / "model_index.json").is_file():
        raise SystemExit(f"MODEL_BLOCKED: {model}")
    if not SOURCE.is_file():
        raise SystemExit(f"SOURCE_MISSING: {SOURCE}")
    return content, selected, model


def build_mask() -> Image.Image:
    mask = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(mask)
    # Only the body/shield seam is regenerated. The face, attire, legs, and
    # outer shield silhouette remain invariant.
    draw.polygon(
        [(390, 245), (478, 232), (548, 282), (560, 420), (520, 515),
         (442, 514), (394, 438), (374, 330)],
        fill=255,
    )
    return mask.filter(ImageFilter.GaussianBlur(8))


def main() -> int:
    cfg = cli()
    content, selected, model = preflight()
    tokenizers = [CLIPTokenizer.from_pretrained(model / part, local_files_only=True) for part in ("tokenizer", "tokenizer_2")]
    for label, value in (("PROMPT", PROMPT), ("NEGATIVE", NEGATIVE)):
        lengths = [len(tok(value, truncation=False).input_ids) for tok in tokenizers]
        print(f"PROMPT_TOKENS {label} {lengths}", flush=True)
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {label} {lengths}")
    if cfg.validate_only:
        print("R25_COMBAT_GRIP_POLICY_VALIDATION_OK")
        return 0

    OUTPUT.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    grip_mask = build_mask()
    mask_path = OUTPUT / "chr001_guardian_r25_grip_connection_mask.png"
    grip_mask.save(mask_path, format="PNG", optimize=True)

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
    for revision in range(1, cfg.count + 1):
        seed = 171300 + revision
        result = pipe(
            prompt=PROMPT,
            negative_prompt=NEGATIVE,
            image=source,
            mask_image=grip_mask,
            width=SIZE,
            height=SIZE,
            strength=0.72,
            guidance_scale=8.4,
            num_inference_steps=cfg.steps,
            generator=torch.Generator(device="cuda").manual_seed(seed),
        ).images[0]
        target = OUTPUT / f"chr001_maeru_guardian_combat_right30_r25v{revision:02d}_seed{seed}.png"
        result.save(target, format="PNG", optimize=True)
        records.append({
            "asset_id": f"concept_chr001_guardian_combat_right30_r25v{revision:02d}",
            "character_id": "CHR001",
            "character_gender": "FEMALE",
            "age_category": "ADULT",
            "attire_policy": "MAXIMUM_NON_EXPLICIT",
            "status": "ART_QA_CANDIDATE",
            "production_approved": False,
            "runtime_asset": False,
            "view": "THREE_QUARTER_RIGHT_DOWN_30",
            "team_usage": "PLAYER_LEFT_SIDE_FACING_RIGHT",
            "facing_policy": "SEPARATE_LEFT_RIGHT",
            "model": MODEL_ID,
            "model_license": selected[MODEL_ID]["license"],
            "model_original_preserved": True,
            "krea2_used": False,
            "source": SOURCE.relative_to(ROOT).as_posix(),
            "source_sha256": sha(SOURCE),
            "mask": mask_path.relative_to(ROOT).as_posix(),
            "seed": seed,
            "path": target.relative_to(ROOT).as_posix(),
            "bytes": target.stat().st_size,
            "sha256": sha(target),
            "qa_verdict": "UNREVIEWED",
            "integration_allowed": False,
        })
        print(f"R25_RENDERED {target}", flush=True)

    manifest = {
        "kind": "LOCAL_SDXL_COMBAT_GRIP_R25",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "offline": True,
        "content_policy_version": content["policy_version"],
        "source_models_mutated": False,
        "production_approved": False,
        "records": records,
    }
    manifest_path = OUTPUT / "combat_grip_r25_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
