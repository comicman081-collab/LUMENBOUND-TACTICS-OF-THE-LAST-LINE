#!/usr/bin/env python3
"""Create local-only 8-head card/gacha art candidates from the character bible.

This is intentionally separate from the battle/mapping SD pipeline.  It uses
the installed local SDXL checkpoint only; no network or hosted image service is
contacted.  Outputs stay in the green-matte candidate area until a visual
continuity review explicitly promotes them to the card runtime.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "godot"
MODEL_ROOT = Path(r"C:\AI_MODELS\sdxl-base-1.0")
OUTPUT_ROOT = ROOT / "data_source" / "art_source" / "card_8head_green_matte_r1"
SIZE = (768, 1152)
GREEN = (0, 255, 0)
REVISION = "R2_TEXT2IMG_CHARACTER_BIBLE"
CONTROLNET_CANNY_ROOT = Path(r"C:\AI_MODELS\controlnet-sdxl\controlnet-canny-sdxl-1.0")

ROLE_CUES = {
    "GUARDIAN": "guardian, shield, guard stance",
    "VANGUARD": "vanguard, melee stance",
    "ASSAULT": "assault, tactical firearm",
    "ARTILLERY": "artillery, heavy weapon",
    "SPECIALIST": "signal specialist, focus device",
    "MEDIC": "field medic, medical device",
}

# The old expansion records contain only simplified SD dev icons, not a
# usable full-body art authority.  This deliberately varied character bible
# establishes the first real 8-head card family without copying the SD shape.
# Role, weapon class and canonical character name remain immutable game data.
HAIR_CUES = (
    "long ash-silver hair in a low side ponytail", "short crimson textured bob",
    "deep teal braided undercut", "long midnight-blue wavy hair", "warm auburn high ponytail",
    "black asymmetrical pixie cut", "ice-blonde twin braids", "violet layered wolf cut",
    "chestnut curly shoulder-length hair", "rose-gold sleek bob", "emerald long loose braid",
    "white cropped hair with an indigo underlayer",
)
FACE_CUES = (
    "cool oval face and steel-grey eyes", "heart-shaped face and amber eyes",
    "angular face and vivid green eyes", "soft round face and violet eyes",
    "strong cheekbones and brown eyes", "freckled face and blue eyes",
)
PALETTE_CUES = (
    "navy and cyan armor", "crimson and black armor", "ivory and gold armor",
    "charcoal and lime armor", "violet and silver armor", "white and cobalt armor",
    "burgundy and bronze armor", "teal and white armor", "black and magenta armor",
    "forest green and copper armor", "slate and orange armor", "plum and pearl armor",
)
SILHOUETTE_CUES = (
    "light tactical jacket with layered hip guards", "fitted armored combat coat",
    "asymmetrical reinforced field skirt and greaves", "short mantle over segmented armor",
    "utility harness with articulated shoulder plates", "long split-tail coat with armored boots",
    "cropped tactical jacket over a reinforced bodysuit", "mobile relay cape with knee guards",
    "formal expedition uniform with a plated corset", "storm jacket with hard-shell gauntlets",
    "high-collar armored dress coat", "field hoodie under polished plate armor",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def character_rows() -> dict[str, dict]:
    data = json.loads((GODOT / "data" / "compiled" / "game_data.json").read_text(encoding="utf-8"))
    return {str(row["id"]): row for row in data.get("characters", [])}


def reference_path(character_id: str) -> Path:
    # Kept as provenance only.  The expansion sources are small SD development
    # icons, not an acceptable visual source for an 8-head premium card.
    if int(character_id[3:]) <= 8:
        raise ValueError(f"{character_id} already has an approved 8-head card authority; do not regenerate it")
    path = ROOT / "data_source" / "art_source" / "expansion_static_sources" / f"{character_id.lower()}_authority.png"
    if not path.is_file():
        raise FileNotFoundError(f"SD identity authority missing: {path}")
    return path


def prompt_for(character_id: str, row: dict) -> tuple[str, str, str]:
    role = str(row.get("role", "SPECIALIST"))
    role_cue = ROLE_CUES.get(role, ROLE_CUES["SPECIALIST"])
    index = int(character_id[3:]) - 9
    hair = HAIR_CUES[index % len(HAIR_CUES)]
    face = FACE_CUES[(index * 5) % len(FACE_CUES)]
    palette = PALETTE_CUES[(index * 7) % len(PALETTE_CUES)]
    silhouette = SILHOUETTE_CUES[(index * 11) % len(SILHOUETTE_CUES)]
    weapon = str(row.get("weapon_class", "FOCUS")).replace("_", " ").lower()
    identity = f"{hair}; {face}; {palette}; {silhouette}; {weapon}"
    # Keep the positive prompt inside SDXL's 77-token encoder window.  The
    # background and full-body requirements are deliberately early, never in
    # the truncation tail.
    prompt = (
        "high-end anime tactical SRPG card, adult woman, full body, elegant 8-head proportion, "
        "head and boots visible, flat chroma green backdrop, refined lines, crisp cel shading; "
        f"{identity}; {role_cue}; centered three-quarter pose"
    )
    negative = (
        "chibi, SD, child, baby face, toy, 3d render, pixel art, cropped, duplicate, "
        "extra limbs, malformed hands, white background, black background, scenery, shadow, text, logo"
    )
    return prompt, negative, identity


def full_body_pose_guide() -> Image.Image:
    """A simple, neutral 8-head standing guide for the local SDXL Canny control."""
    from PIL import ImageDraw

    guide = Image.new("RGB", SIZE, (255, 255, 255))
    draw = ImageDraw.Draw(guide)
    black = (0, 0, 0)
    cx = SIZE[0] // 2
    # Head through boots: the figure intentionally occupies the whole canvas.
    draw.ellipse((cx - 62, 56, cx + 62, 180), outline=black, width=10)
    draw.line((cx, 180, cx, 480), fill=black, width=12)
    draw.line((cx - 112, 262, cx + 112, 262), fill=black, width=12)
    draw.line((cx - 102, 266, cx - 226, 494), fill=black, width=12)
    draw.line((cx + 102, 266, cx + 226, 494), fill=black, width=12)
    draw.polygon([(cx - 150, 340), (cx + 150, 340), (cx + 118, 588), (cx - 118, 588)], outline=black, width=12)
    draw.line((cx - 68, 585, cx - 120, 1028), fill=black, width=14)
    draw.line((cx + 68, 585, cx + 120, 1028), fill=black, width=14)
    draw.line((cx - 170, 1030, cx - 78, 1030), fill=black, width=18)
    draw.line((cx + 78, 1030, cx + 170, 1030), fill=black, width=18)
    # A diagonal long-weapon line gives sword/rifle/heavy silhouettes a clear
    # non-portrait framing cue without dictating the final prop design.
    draw.line((cx + 208, 178, cx - 264, 856), fill=black, width=18)
    return guide


def composite_foreground_to_green(image: Image.Image) -> Image.Image:
    """Create an exact green source field from a center-framed card candidate."""
    bgr = cv2.cvtColor(np.asarray(image.convert("RGB")), cv2.COLOR_RGB2BGR)
    height, width = bgr.shape[:2]
    mask = np.zeros((height, width), np.uint8)
    background_model = np.zeros((1, 65), np.float64)
    foreground_model = np.zeros((1, 65), np.float64)
    cv2.grabCut(bgr, mask, (18, 12, width - 36, height - 24), background_model, foreground_model, 5, cv2.GC_INIT_WITH_RECT)
    subject = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype("uint8")
    subject = cv2.morphologyEx(subject, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8), iterations=1)
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    output = np.full_like(rgb, GREEN)
    output[subject > 0] = rgb[subject > 0]
    return Image.fromarray(output, "RGB")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ids", nargs="+", default=["CHR009"], help="Character IDs; CHR009–CHR044 only")
    parser.add_argument("--steps", type=int, default=30)
    parser.add_argument("--strength", type=float, default=0.84)
    parser.add_argument("--seed-offset", type=int, default=0)
    parser.add_argument("--controlnet", action="store_true", help="Use the installed local SDXL Canny model to lock full-body framing")
    args = parser.parse_args()

    if not MODEL_ROOT.is_dir():
        raise FileNotFoundError(f"Installed local SDXL authority is missing: {MODEL_ROOT}")
    import torch
    from diffusers import StableDiffusionXLPipeline, EulerAncestralDiscreteScheduler

    rows = character_rows()
    if args.controlnet:
        if not CONTROLNET_CANNY_ROOT.is_dir():
            raise FileNotFoundError(f"Installed local ControlNet authority is missing: {CONTROLNET_CANNY_ROOT}")
        from diffusers import ControlNetModel, StableDiffusionXLControlNetPipeline

        controlnet = ControlNetModel.from_pretrained(str(CONTROLNET_CANNY_ROOT), torch_dtype=torch.float16, use_safetensors=True, variant="fp16")
        pipe = StableDiffusionXLControlNetPipeline.from_pretrained(
            str(MODEL_ROOT), controlnet=controlnet, torch_dtype=torch.float16, use_safetensors=True, variant="fp16"
        )
    else:
        pipe = StableDiffusionXLPipeline.from_pretrained(
            str(MODEL_ROOT), torch_dtype=torch.float16, use_safetensors=True, variant="fp16"
        )
    pipe.scheduler = EulerAncestralDiscreteScheduler.from_config(pipe.scheduler.config)
    if args.controlnet:
        pipe.enable_model_cpu_offload()
    else:
        pipe.to("cuda")
    pipe.vae.enable_slicing()
    pipe.set_progress_bar_config(disable=True)

    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    contract_path = OUTPUT_ROOT / "qa" / "CARD_8HEAD_CANDIDATE_CONTRACT.json"
    existing = json.loads(contract_path.read_text(encoding="utf-8")) if contract_path.is_file() else {"schemaVersion": 1, "candidates": {}}
    candidates = dict(existing.get("candidates", {}))
    for character_id in args.ids:
        row = rows.get(character_id)
        if row is None:
            raise ValueError(f"Unknown character: {character_id}")
        source_path = reference_path(character_id)
        prompt, negative, identity = prompt_for(character_id, row)
        seed = int.from_bytes(hashlib.sha256((character_id + str(args.seed_offset)).encode("utf-8")).digest()[:8], "big") % (2**31)
        inference = {
            "prompt": prompt,
            "negative_prompt": negative,
            "num_inference_steps": args.steps,
            "guidance_scale": 7.0,
            "generator": torch.Generator(device="cuda").manual_seed(seed),
            "width": SIZE[0],
            "height": SIZE[1],
        }
        if args.controlnet:
            inference["image"] = full_body_pose_guide()
            inference["controlnet_conditioning_scale"] = 0.92
        image = pipe(**inference).images[0].convert("RGB")
        image = composite_foreground_to_green(image)
        target = OUTPUT_ROOT / character_id / f"{character_id.lower()}_8head_card_r3_green_matte.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target, optimize=True)
        candidates[character_id] = {
            "cardFamily": "8_HEAD_GACHA_CARD_R1",
            "identityReference": str(source_path.relative_to(ROOT)).replace("\\", "/"),
            "identityReferenceSha256": sha256(source_path),
            "identityDesign": identity,
            "greenMatteCandidate": str(target.relative_to(ROOT)).replace("\\", "/"),
            "greenMatteCandidateSha256": sha256(target),
            "prompt": prompt,
            "negativePrompt": negative,
            "seed": seed,
            "generation": f"LOCAL_SDXL_TEXT2IMG_{REVISION}{'_CONTROLNET_FULLBODY' if args.controlnet else ''}_GRABCUT_GREEN_MATTE",
            "status": "CANDIDATE_PENDING_CONTINUITY_AND_ALPHA_REVIEW",
        }
        print(f"CARD_8HEAD_CANDIDATE={character_id}|{target}")
    contract_path.parent.mkdir(parents=True, exist_ok=True)
    contract_path.write_text(json.dumps({"schemaVersion": 1, "generationMatte": "#00FF00", "runtimeBackground": "RGBA_TRANSPARENT_REQUIRED", "candidates": candidates}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
