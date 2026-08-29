#!/usr/bin/env python3
"""Make one local, green-matte Maeru standing candidate without damaging costume art.

This is candidate-only.  It repairs the specific baked-white regions behind
Maeru's ponytail with the locally approved SDXL inpaint model, then emits a
flat #00FF00 source and a separately keyed RGBA review derivative.  It never
writes a Godot runtime path; visual QA must promote it explicitly.
"""

from __future__ import annotations

import hashlib
import json
import os
from collections import deque
from pathlib import Path

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("DIFFUSERS_OFFLINE", "1")

import cv2
import numpy as np
import torch
from diffusers import DPMSolverMultistepScheduler, StableDiffusionXLInpaintPipeline
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "godot" / "assets" / "art" / "characters" / "CHR001" / "portrait_1024x1536.png"
MODEL = Path(r"C:\AI_MODELS\sdxl-inpaint")
OUTPUT = ROOT / "data_source" / "art_source" / "standing_green_matte_r5" / "CHR001"
GREEN = (0, 255, 0)
SIZE = (768, 1152)
SEED = 100137
PROMPT = (
    "high-end 2D anime tactical SRPG full-body adult woman guardian, preserve the existing turquoise teal ponytail, "
    "gold-trimmed teal armour, tower shield and chained lantern, elegant mature 8-head illustration, "
    "repair only the ponytail hair background with clean separated teal hair strands, flat chroma green background"
)
NEGATIVE = (
    "chibi, SD, child, baby face, male, cropped, white background, black background, scenery, shadow, text, logo, "
    "different costume, different weapon, extra limbs, damaged face, low detail"
)
REGIONS = ((292, 175, 430, 310), (198, 300, 365, 430), (120, 365, 260, 565))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resize_source() -> Image.Image:
    original = Image.open(SOURCE).convert("RGBA")
    background = Image.new("RGBA", original.size, GREEN + (255,))
    background.alpha_composite(original)
    return background.convert("RGB").resize(SIZE, Image.Resampling.LANCZOS)


def repair_mask(image: Image.Image) -> Image.Image:
    rgb = np.asarray(image.convert("RGB"))
    mask = np.zeros((SIZE[1], SIZE[0]), dtype=np.uint8)
    scale_x, scale_y = SIZE[0] / 1024.0, SIZE[1] / 1536.0
    for x0, y0, x1, y1 in REGIONS:
        left, top = round(x0 * scale_x), round(y0 * scale_y)
        right, bottom = round(x1 * scale_x), round(y1 * scale_y)
        crop = rgb[top:bottom, left:right]
        low = crop.min(axis=2)
        high = crop.max(axis=2)
        # Only baked neutral/white matter is masked. Hair, linework and armour
        # remain an immutable image condition for local inpainting.
        selected = (low >= 80) & ((high - low) <= 105)
        mask[top:bottom, left:right][selected] = 255
    # The tiny dilation covers the original white antialias seam but is much
    # smaller than a hair lock; source identity stays intact.
    mask = cv2.dilate(mask, np.ones((3, 3), np.uint8), iterations=1)
    return Image.fromarray(mask, "L").filter(ImageFilter.GaussianBlur(1.2))


def extract_green(source: Image.Image) -> Image.Image:
    array = np.asarray(source.convert("RGB"))
    red, green, blue = array[:, :, 0], array[:, :, 1], array[:, :, 2]
    keyed = (green >= 150) & (green - red >= 70) & (green - blue >= 70)
    alpha = np.where(keyed, 0, 255).astype(np.uint8)
    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.6)
    result = source.convert("RGBA")
    result.putalpha(Image.fromarray(alpha, "L"))
    return result


def normalize_green_background(source: Image.Image) -> Image.Image:
    """Restore an exact #00FF00 field after inpaint's slight green variation.

    Only green-dominant pixels connected to the canvas boundary are normalised.
    Teal hair, shield glass and costume panels are never boundary-connected to
    the background through the conservative hue test.
    """
    result = source.convert("RGB")
    pixels = result.load()
    width, height = result.size
    queue: deque[tuple[int, int]] = deque()
    seen: set[tuple[int, int]] = set()

    def is_background(x: int, y: int) -> bool:
        red, green, blue = pixels[x, y]
        return green >= 115 and green - red >= 70 and green - blue >= 70

    for x in range(width):
        queue.extend(((x, 0), (x, height - 1)))
    for y in range(1, height - 1):
        queue.extend(((0, y), (width - 1, y)))
    while queue:
        x, y = queue.popleft()
        if (x, y) in seen or not is_background(x, y):
            continue
        seen.add((x, y))
        pixels[x, y] = GREEN
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < width and 0 <= ny < height and (nx, ny) not in seen:
                queue.append((nx, ny))
    return result


def main() -> int:
    if not SOURCE.is_file() or not (MODEL / "model_index.json").is_file():
        raise FileNotFoundError("Maeru source or approved local SDXL inpaint model is missing")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    guide = resize_source()
    mask = repair_mask(guide)
    guide_path = OUTPUT / "chr001_8head_r5_green_guide.png"
    mask_path = OUTPUT / "chr001_8head_r5_hair_mask.png"
    green_path = OUTPUT / "chr001_8head_r5_green_matte.png"
    rgba_path = OUTPUT / "chr001_8head_r5_rgba.png"
    guide.save(guide_path, optimize=True)
    mask.save(mask_path, optimize=True)
    pipeline = StableDiffusionXLInpaintPipeline.from_pretrained(
        MODEL, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True
    )
    pipeline.scheduler = DPMSolverMultistepScheduler.from_config(
        pipeline.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True
    )
    pipeline.vae.enable_slicing()
    pipeline.vae.enable_tiling()
    pipeline.enable_model_cpu_offload(gpu_id=0)
    rendered = pipeline(
        prompt=PROMPT, negative_prompt=NEGATIVE, image=guide, mask_image=mask,
        width=SIZE[0], height=SIZE[1], strength=0.76, guidance_scale=7.2,
        num_inference_steps=30, generator=torch.Generator(device="cuda").manual_seed(SEED),
    ).images[0].convert("RGB")
    rendered = normalize_green_background(rendered)
    rendered.save(green_path, optimize=True)
    rgba = extract_green(rendered)
    rgba.save(rgba_path, optimize=True)
    report = {
        "characterId": "CHR001", "status": "CANDIDATE_PENDING_VISUAL_AND_COSTUME_CONTINUITY_QA",
        "generationMatte": "#00FF00", "runtimeBackground": "RGBA_TRANSPARENT",
        "source": SOURCE.relative_to(ROOT).as_posix(), "sourceSha256": sha256(SOURCE),
        "model": "diffusers-sdxl-inpaint-0.1-local", "modelPath": str(MODEL), "seed": SEED,
        "prompt": PROMPT, "negativePrompt": NEGATIVE,
        "guide": guide_path.relative_to(ROOT).as_posix(), "hairMask": mask_path.relative_to(ROOT).as_posix(),
        "greenMatte": green_path.relative_to(ROOT).as_posix(), "greenMatteSha256": sha256(green_path),
        "rgba": rgba_path.relative_to(ROOT).as_posix(), "rgbaSha256": sha256(rgba_path),
    }
    (OUTPUT / "chr001_8head_r5_manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
