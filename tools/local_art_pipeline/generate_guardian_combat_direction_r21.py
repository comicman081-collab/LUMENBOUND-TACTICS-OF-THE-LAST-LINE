#!/usr/bin/env python3
"""R21: local SDXL depth/IP battle-view pilot facing lower-right by about 30 degrees."""
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


ROOT = Path(__file__).resolve().parents[2]
MODEL_POLICY = ROOT / "tools" / "local_art_pipeline" / "model_policy.json"
CONTENT_POLICY = ROOT / "tools" / "policy" / "project_content_policy.json"
APPEARANCE = ROOT / "work" / "art_gen" / "sdxl_chibi_guardian_r20" / "chr001_maeru_guardian_chibi_r20v01_seed171251.png"
OUTPUT = ROOT / "work" / "art_gen" / "sdxl_guardian_combat_direction_r21"
BASE_ID = "stabilityai-sdxl-base-1.0-local"
DEPTH_ID = "diffusers-controlnet-depth-sdxl-1.0-local"
IP_ID = "h94-ip-adapter-sdxl-local"
SIZE = 768

PROMPT = (
    "detailed 3D anime RPG adult woman, mature athletic 3-head chibi guardian, right-facing three-quarter view, gaze 30 degrees downward, "
    "short rounded limbs, revealing non-explicit minimal teal gold bikini armor, opaque coverage, bare abdomen hips thighs, "
    "one shield held forward by connected left gauntlet, glossy game render"
)
NEGATIVE = (
    "male, man, boy, child, teen, underage, juvenile, school uniform, front view, looking at camera, left-facing, back view, long legs, "
    "nude, nipples, genitals, explicit, transparent fabric, bodysuit, covered abdomen, floating shield, detached shield, second shield, extra limbs, text, watermark, blurry"
)


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def cli() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=4, choices=(1, 2, 3, 4))
    parser.add_argument("--steps", type=int, default=44)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def preflight() -> tuple[dict, dict, Path, Path, Path, Path]:
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
    if not APPEARANCE.is_file():
        raise SystemExit(f"SOURCE_MISSING: {APPEARANCE}")
    return content, selected, base, depth, ip_root, encoder


def depth_guide() -> Image.Image:
    depth = Image.new("L", (SIZE, SIZE), 15)
    draw = ImageDraw.Draw(depth)
    # Right-facing three-quarter head, with nose/chin volume on the right.
    draw.ellipse((288, 58, 500, 268), fill=214)
    draw.ellipse((458, 132, 522, 205), fill=222)
    draw.ellipse((210, 108, 338, 315), fill=169)  # ponytail trailing left
    # Compact torso angled toward lower-right with distinct chest and hips.
    draw.polygon([(318, 252), (480, 270), (514, 454), (458, 536), (342, 516), (292, 420)], fill=194)
    draw.ellipse((326, 438, 500, 582), fill=188)
    # Short legs; forward/right leg slightly larger to communicate 3/4 depth.
    draw.polygon([(356, 522), (414, 532), (400, 680), (332, 674)], fill=178)
    draw.polygon([(432, 520), (496, 530), (530, 680), (452, 688)], fill=190)
    draw.rounded_rectangle((318, 652, 410, 710), radius=20, fill=202)
    draw.rounded_rectangle((444, 658, 546, 716), radius=20, fill=211)
    # Rear arm trails left; shield arm reaches forward and overlaps its handle.
    draw.line((326, 316, 272, 438), fill=202, width=54)
    draw.ellipse((250, 417, 306, 474), fill=213)
    draw.line((468, 326, 536, 410), fill=212, width=58)
    draw.ellipse((516, 388, 578, 450), fill=226)
    # Shield occupies the forward/right side and visibly overlaps the hand.
    outer = [(530, 278), (610, 240), (686, 294), (674, 526), (612, 630), (534, 590), (504, 468)]
    inner = [(553, 302), (608, 276), (657, 312), (648, 502), (606, 578), (557, 552), (532, 458)]
    draw.polygon(outer, fill=234)
    draw.polygon(inner, fill=196)
    draw.rounded_rectangle((520, 386, 550, 468), radius=10, fill=226)  # hand/handle overlap
    draw.ellipse((572, 378, 640, 446), fill=219)
    return Image.merge("RGB", (depth, depth, depth)).filter(ImageFilter.GaussianBlur(5))


def main() -> int:
    cfg = cli()
    content, selected, base, depth_model, ip_root, encoder = preflight()
    tokenizers = [CLIPTokenizer.from_pretrained(base / part, local_files_only=True) for part in ("tokenizer", "tokenizer_2")]
    for label, value in (("PROMPT", PROMPT), ("NEGATIVE", NEGATIVE)):
        lengths = [len(tok(value, truncation=False).input_ids) for tok in tokenizers]
        print(f"PROMPT_TOKENS {label} {lengths}", flush=True)
        if max(lengths) > 77:
            raise SystemExit(f"PROMPT_TOO_LONG: {label} {lengths}")
    if cfg.validate_only:
        print("R21_COMBAT_DIRECTION_POLICY_VALIDATION_OK")
        return 0
    OUTPUT.mkdir(parents=True, exist_ok=True)
    guide = depth_guide()
    appearance = Image.open(APPEARANCE).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    guide_path = OUTPUT / "chr001_guardian_r21_lower_right_depth.png"
    appearance_path = OUTPUT / "chr001_guardian_r21_appearance.png"
    guide.save(guide_path, format="PNG", optimize=True); appearance.save(appearance_path, format="PNG", optimize=True)
    controlnet = ControlNetModel.from_pretrained(depth_model, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True)
    pipe = StableDiffusionXLControlNetPipeline.from_pretrained(base, controlnet=controlnet, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True)
    pipe.load_ip_adapter(str(ip_root), subfolder="sdxl_models", weight_name="ip-adapter_sdxl_vit-h.safetensors", image_encoder_folder=str(encoder), local_files_only=True)
    pipe.set_ip_adapter_scale(0.42)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True)
    pipe.vae.enable_slicing(); pipe.vae.enable_tiling(); pipe.enable_model_cpu_offload(gpu_id=0)
    records = []
    for revision in range(1, cfg.count + 1):
        seed = 171260 + revision
        result = pipe(prompt=PROMPT, negative_prompt=NEGATIVE, image=guide, ip_adapter_image=appearance, width=SIZE, height=SIZE,
                      num_inference_steps=cfg.steps, guidance_scale=6.6, controlnet_conditioning_scale=0.82,
                      control_guidance_start=0.0, control_guidance_end=0.88,
                      generator=torch.Generator(device="cuda").manual_seed(seed)).images[0]
        target = OUTPUT / f"chr001_maeru_guardian_combat_right30_r21v{revision:02d}_seed{seed}.png"
        result.save(target, format="PNG", optimize=True)
        records.append({"asset_id": f"concept_chr001_guardian_combat_right30_r21v{revision:02d}", "character_id": "CHR001", "character_gender": "FEMALE",
                        "age_category": "ADULT", "attire_policy": "MAXIMUM_NON_EXPLICIT", "status": "ART_QA_CANDIDATE", "production_approved": False,
                        "runtime_asset": False, "view": "THREE_QUARTER_RIGHT_DOWN_30", "team_usage": "PLAYER_LEFT_SIDE_FACING_RIGHT",
                        "facing_policy": "SEPARATE_LEFT_RIGHT", "models": [BASE_ID, DEPTH_ID, IP_ID],
                        "model_licenses": [selected[BASE_ID]["license"], selected[DEPTH_ID]["license"], selected[IP_ID]["license"]],
                        "model_originals_preserved": True, "krea2_used": False, "appearance_source": APPEARANCE.relative_to(ROOT).as_posix(),
                        "appearance_source_sha256": sha(APPEARANCE), "depth_guide": guide_path.relative_to(ROOT).as_posix(), "seed": seed,
                        "path": target.relative_to(ROOT).as_posix(), "bytes": target.stat().st_size, "sha256": sha(target),
                        "qa_verdict": "UNREVIEWED", "integration_allowed": False})
        print(f"R21_RENDERED {target}", flush=True)
    manifest = {"kind": "LOCAL_SDXL_COMBAT_DIRECTION_GUARDIAN_R21", "created_utc": datetime.now(timezone.utc).isoformat(), "offline": True,
                "content_policy_version": content["policy_version"], "source_models_mutated": False, "production_approved": False, "records": records}
    manifest_path = OUTPUT / "combat_direction_r21_manifest.json"; manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "records": len(records), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
