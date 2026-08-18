#!/usr/bin/env python3
"""R23 targeted face-turn and shield-grip correction for the R22 combat base."""
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
SOURCE = ROOT / "work" / "art_gen" / "sdxl_guardian_combat_direction_r22" / "chr001_maeru_guardian_combat_right30_r22v03_seed171273.png"
OUTPUT = ROOT / "work" / "art_gen" / "sdxl_guardian_combat_direction_r23"
MODEL_ID = "diffusers-sdxl-inpaint-0.1-local"
SIZE = 768
FACE_PROMPT = (
    "detailed 3D anime RPG adult woman, mature 3-head chibi guardian, head turned right three-quarter view, nose pointing right, chin lowered, "
    "cyan eyes looking 30 degrees lower-right, near eye larger and far eye smaller, chestnut ponytail, revealing non-explicit armor, opaque coverage, glossy game render"
)
FACE_NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, front view, looking at camera, left-facing, profile, closed eyes, crossed eyes, extra eyes, "
    "deformed face, duplicate face, text, watermark, blurry"
)
GRIP_PROMPT = (
    "detailed 3D anime RPG adult woman, mature 3-head chibi guardian, shield on right held by connected left gauntlet, hand wrapped around visible handle, "
    "wrist and forearm touching shield rim, one shield, revealing non-explicit minimal armor, opaque coverage, glossy game render"
)
GRIP_NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, floating shield, detached shield, gap, missing hand, extra arm, second shield, sword, gun, text, watermark, blurry"
)


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def cli() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=2, choices=(1, 2))
    parser.add_argument("--steps", type=int, default=44)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def preflight() -> tuple[dict, dict, Path]:
    content = json.loads(CONTENT_POLICY.read_text(encoding="utf-8"))
    policy = json.loads(MODEL_POLICY.read_text(encoding="utf-8"))
    cp, ap = content["character_policy"], content["appearance_policy"]
    if cp["human_and_humanoid_characters"] != "FEMALE_ONLY" or cp["age_category"] != "ADULT_ONLY" or ap["attire_exposure"] != "MAXIMUM_NON_EXPLICIT":
        raise SystemExit("CONTENT_POLICY_INVALID")
    required = tuple(cp["required_positive_prompt_terms"]) + tuple(ap["required_positive_prompt_terms"])
    for label, prompt in (("FACE", FACE_PROMPT), ("GRIP", GRIP_PROMPT)):
        lower = prompt.lower()
        if not all(term.lower() in lower for term in required):
            raise SystemExit(f"CONTENT_POLICY_BLOCK {label}: {required}")
        for term in cp["forbidden_positive_prompt_terms"]:
            if re.search(rf"(?<![a-z]){re.escape(term.lower())}(?![a-z])", lower):
                raise SystemExit(f"CONTENT_POLICY_BLOCK {label}: {term}")
    selected = {row["id"]: row for row in policy["selected"]}
    if MODEL_ID not in selected:
        raise SystemExit(f"MODEL_BLOCKED: {MODEL_ID}")
    model = Path(selected[MODEL_ID]["path"]).resolve()
    if "krea" in str(model).lower() or not (model / "model_index.json").is_file():
        raise SystemExit(f"MODEL_BLOCKED: {model}")
    if not SOURCE.is_file():
        raise SystemExit(f"SOURCE_MISSING: {SOURCE}")
    return content, selected, model


def mask(points: list[tuple[int, int]], blur: int) -> Image.Image:
    result = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(result).polygon(points, fill=255)
    return result.filter(ImageFilter.GaussianBlur(blur))


def clean_source() -> Image.Image:
    image = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    pixels = image.load()
    for y in range(SIZE):
        left_fill = pixels[74, y]
        right_fill = pixels[694, y]
        for x in range(72):
            if sum(pixels[x, y]) < 95: pixels[x, y] = left_fill
        for x in range(696, SIZE):
            if sum(pixels[x, y]) < 95: pixels[x, y] = right_fill
    return image


def main() -> int:
    cfg = cli()
    content, selected, model = preflight()
    tokenizers = [CLIPTokenizer.from_pretrained(model / part, local_files_only=True) for part in ("tokenizer", "tokenizer_2")]
    for label, value in (("FACE_PROMPT", FACE_PROMPT), ("FACE_NEGATIVE", FACE_NEGATIVE), ("GRIP_PROMPT", GRIP_PROMPT), ("GRIP_NEGATIVE", GRIP_NEGATIVE)):
        lengths = [len(tok(value, truncation=False).input_ids) for tok in tokenizers]
        print(f"PROMPT_TOKENS {label} {lengths}", flush=True)
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {label} {lengths}")
    if cfg.validate_only:
        print("R23_COMBAT_DIRECTION_INPAINT_POLICY_VALIDATION_OK")
        return 0
    OUTPUT.mkdir(parents=True, exist_ok=True)
    source = clean_source()
    face_mask = mask([(248, 54), (480, 52), (522, 150), (482, 290), (296, 305), (226, 186)], 9)
    grip_mask = mask([(420, 286), (555, 270), (592, 344), (564, 478), (444, 500), (395, 402)], 7)
    source_path, face_path, grip_path = OUTPUT / "chr001_guardian_r23_clean_source.png", OUTPUT / "chr001_guardian_r23_face_mask.png", OUTPUT / "chr001_guardian_r23_grip_mask.png"
    source.save(source_path, format="PNG", optimize=True); face_mask.save(face_path, format="PNG", optimize=True); grip_mask.save(grip_path, format="PNG", optimize=True)
    pipe = StableDiffusionXLInpaintPipeline.from_pretrained(model, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True)
    pipe.vae.enable_slicing(); pipe.vae.enable_tiling(); pipe.enable_model_cpu_offload(gpu_id=0)
    records = []
    for revision in range(1, cfg.count + 1):
        face_seed, grip_seed = 171280 + revision, 171290 + revision
        face = pipe(prompt=FACE_PROMPT, negative_prompt=FACE_NEGATIVE, image=source, mask_image=face_mask, width=SIZE, height=SIZE,
                    strength=0.82, guidance_scale=8.2, num_inference_steps=cfg.steps, generator=torch.Generator(device="cuda").manual_seed(face_seed)).images[0]
        face_file = OUTPUT / f"chr001_guardian_r23v{revision:02d}_face_seed{face_seed}.png"; face.save(face_file, format="PNG", optimize=True)
        final = pipe(prompt=GRIP_PROMPT, negative_prompt=GRIP_NEGATIVE, image=face, mask_image=grip_mask, width=SIZE, height=SIZE,
                     strength=0.62, guidance_scale=7.8, num_inference_steps=cfg.steps, generator=torch.Generator(device="cuda").manual_seed(grip_seed)).images[0]
        target = OUTPUT / f"chr001_maeru_guardian_combat_right30_r23v{revision:02d}_seed{grip_seed}.png"; final.save(target, format="PNG", optimize=True)
        records.append({"asset_id": f"concept_chr001_guardian_combat_right30_r23v{revision:02d}", "character_id": "CHR001", "character_gender": "FEMALE",
                        "age_category": "ADULT", "attire_policy": "MAXIMUM_NON_EXPLICIT", "status": "ART_QA_CANDIDATE", "production_approved": False,
                        "runtime_asset": False, "view": "THREE_QUARTER_RIGHT_DOWN_30", "team_usage": "PLAYER_LEFT_SIDE_FACING_RIGHT",
                        "facing_policy": "SEPARATE_LEFT_RIGHT", "model": MODEL_ID, "model_license": selected[MODEL_ID]["license"],
                        "model_original_preserved": True, "krea2_used": False, "source": SOURCE.relative_to(ROOT).as_posix(), "source_sha256": sha(SOURCE),
                        "face_seed": face_seed, "grip_seed": grip_seed, "face_mask": face_path.relative_to(ROOT).as_posix(), "grip_mask": grip_path.relative_to(ROOT).as_posix(),
                        "path": target.relative_to(ROOT).as_posix(), "bytes": target.stat().st_size, "sha256": sha(target),
                        "qa_verdict": "UNREVIEWED", "integration_allowed": False})
        print(f"R23_RENDERED {target}", flush=True)
    manifest = {"kind": "LOCAL_SDXL_COMBAT_DIRECTION_GUARDIAN_R23", "created_utc": datetime.now(timezone.utc).isoformat(), "offline": True,
                "content_policy_version": content["policy_version"], "source_models_mutated": False, "production_approved": False, "records": records}
    manifest_path = OUTPUT / "combat_direction_r23_manifest.json"; manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
