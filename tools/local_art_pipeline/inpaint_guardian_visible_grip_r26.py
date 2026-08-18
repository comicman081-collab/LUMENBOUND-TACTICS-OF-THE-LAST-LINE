#!/usr/bin/env python3
"""R26: expose a readable hand/wrist/forearm chain on the shield rim."""
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
SOURCE = ROOT / "work" / "art_gen" / "sdxl_guardian_combat_grip_r25" / "chr001_maeru_guardian_combat_right30_r25v02_seed171302.png"
OUTPUT = ROOT / "work" / "art_gen" / "sdxl_guardian_visible_grip_r26"
MODEL_ID = "diffusers-sdxl-inpaint-0.1-local"
SIZE = 768
PROMPT = (
    "polished 3D anime RPG adult woman, mature chibi guardian looking lower-right, revealing non-explicit teal gold bikini armor, opaque coverage, "
    "bare abdomen hips thighs, clearly visible teal gauntlet hand clasping shield left rim, fingers wrapped over gold border, connected wrist and forearm from shoulder"
)
NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, nude, nipples, genitals, explicit, covered abdomen, bodysuit, "
    "floating shield, detached shield, hidden hand, missing hand, stump, gap, extra hand, extra arm, fused fingers, weapon, text, watermark, blurry"
)


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=4, choices=(1, 2, 3, 4))
    parser.add_argument("--steps", type=int, default=48)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def preflight() -> tuple[dict, dict, Path]:
    content = json.loads(CONTENT_POLICY.read_text(encoding="utf-8"))
    policy = json.loads(MODEL_POLICY.read_text(encoding="utf-8"))
    cp, ap = content["character_policy"], content["appearance_policy"]
    if cp["human_and_humanoid_characters"] != "FEMALE_ONLY" or cp["age_category"] != "ADULT_ONLY" or ap["attire_exposure"] != "MAXIMUM_NON_EXPLICIT":
        raise SystemExit("CONTENT_POLICY_INVALID")
    required = tuple(cp["required_positive_prompt_terms"]) + tuple(ap["required_positive_prompt_terms"])
    lower = PROMPT.lower()
    if not all(term.lower() in lower for term in required):
        raise SystemExit(f"CONTENT_POLICY_BLOCK: {required}")
    for term in cp["forbidden_positive_prompt_terms"]:
        if re.search(rf"(?<![a-z]){re.escape(term.lower())}(?![a-z])", lower):
            raise SystemExit(f"CONTENT_POLICY_BLOCK: {term}")
    selected = {row["id"]: row for row in policy["selected"]}
    model = Path(selected[MODEL_ID]["path"]).resolve()
    if "krea" in str(model).lower() or not (model / "model_index.json").is_file():
        raise SystemExit(f"MODEL_BLOCKED: {model}")
    if not SOURCE.is_file():
        raise SystemExit(f"SOURCE_MISSING: {SOURCE}")
    return content, selected, model


def mask() -> Image.Image:
    result = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(result)
    # Narrow diagonal seam: right shoulder to a visible grip around the
    # shield's gold left border at waist height.
    draw.polygon([(374, 259), (438, 252), (474, 326), (473, 445), (428, 474), (381, 421), (361, 324)], fill=255)
    return result.filter(ImageFilter.GaussianBlur(6))


def main() -> int:
    cfg = arguments()
    content, selected, model = preflight()
    tokenizers = [CLIPTokenizer.from_pretrained(model / part, local_files_only=True) for part in ("tokenizer", "tokenizer_2")]
    for label, value in (("PROMPT", PROMPT), ("NEGATIVE", NEGATIVE)):
        lengths = [len(tok(value, truncation=False).input_ids) for tok in tokenizers]
        print(f"PROMPT_TOKENS {label} {lengths}", flush=True)
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {label} {lengths}")
    if cfg.validate_only:
        print("R26_VISIBLE_GRIP_POLICY_VALIDATION_OK")
        return 0
    OUTPUT.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    grip_mask = mask()
    mask_path = OUTPUT / "chr001_guardian_r26_visible_grip_mask.png"
    grip_mask.save(mask_path, format="PNG", optimize=True)
    pipe = StableDiffusionXLInpaintPipeline.from_pretrained(model, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True)
    pipe.vae.enable_slicing(); pipe.vae.enable_tiling(); pipe.enable_model_cpu_offload(gpu_id=0)
    records = []
    for revision in range(1, cfg.count + 1):
        seed = 171310 + revision
        image = pipe(prompt=PROMPT, negative_prompt=NEGATIVE, image=source, mask_image=grip_mask,
                     width=SIZE, height=SIZE, strength=0.88, guidance_scale=9.2,
                     num_inference_steps=cfg.steps, generator=torch.Generator(device="cuda").manual_seed(seed)).images[0]
        target = OUTPUT / f"chr001_maeru_guardian_combat_right30_r26v{revision:02d}_seed{seed}.png"
        image.save(target, format="PNG", optimize=True)
        records.append({
            "asset_id": f"concept_chr001_guardian_combat_right30_r26v{revision:02d}", "character_id": "CHR001",
            "character_gender": "FEMALE", "age_category": "ADULT", "attire_policy": "MAXIMUM_NON_EXPLICIT",
            "status": "ART_QA_CANDIDATE", "production_approved": False, "runtime_asset": False,
            "view": "THREE_QUARTER_RIGHT_DOWN_30", "team_usage": "PLAYER_LEFT_SIDE_FACING_RIGHT",
            "facing_policy": "SEPARATE_LEFT_RIGHT", "model": MODEL_ID, "model_license": selected[MODEL_ID]["license"],
            "model_original_preserved": True, "krea2_used": False, "source": SOURCE.relative_to(ROOT).as_posix(),
            "source_sha256": sha(SOURCE), "mask": mask_path.relative_to(ROOT).as_posix(), "seed": seed,
            "path": target.relative_to(ROOT).as_posix(), "bytes": target.stat().st_size, "sha256": sha(target),
            "qa_verdict": "UNREVIEWED", "integration_allowed": False,
        })
        print(f"R26_RENDERED {target}", flush=True)
    manifest = {"kind": "LOCAL_SDXL_VISIBLE_GRIP_R26", "created_utc": datetime.now(timezone.utc).isoformat(), "offline": True,
                "content_policy_version": content["policy_version"], "source_models_mutated": False,
                "production_approved": False, "records": records}
    manifest_path = OUTPUT / "visible_grip_r26_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
