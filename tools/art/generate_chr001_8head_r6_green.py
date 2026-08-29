#!/usr/bin/env python3
"""Create from-scratch green-matte 8-head Maeru card candidates locally.

R1 and its R3–R5 repair variants are not used as image input.  This produces
new full-body candidates from the immutable written identity only, keeping the
source field flat #00FF00 so alpha extraction has no hidden white backing.
Candidates remain outside runtime until visual continuity QA selects one.
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
from diffusers import ControlNetModel, DPMSolverMultistepScheduler, StableDiffusionXLControlNetPipeline
from PIL import Image, ImageDraw
from transformers import CLIPTokenizer, Sam2Model, Sam2Processor


ROOT = Path(__file__).resolve().parents[2]
BASE = Path(r"C:\AI_MODELS\sdxl-base-1.0")
CONTROL = Path(r"C:\AI_MODELS\controlnet-sdxl\controlnet-canny-sdxl-1.0")
IP_ROOT = Path(r"C:\AI_MODELS\ip-adapter")
IP_ENCODER = Path(r"C:\AI_MODELS\clip-vit-h-14-laion2b\models\image_encoder")
SAM2 = Path(r"C:\AI_MODELS\SAM2\sam2.1-hiera-small")
SD_REFERENCE = ROOT / "godot" / "assets" / "runtime_web" / "combat" / "CHR001" / "preview.png"
OUTPUT = ROOT / "data_source" / "art_source" / "card_8head_green_matte_r2" / "CHR001"
GREEN = (0, 255, 0)
SIZE = (768, 1152)
SEEDS = (101201, 101202)
PROMPT = (
    "long turquoise teal high ponytail, gold crown, amber eyes, teal and gold guardian armour, huge teal gold kite shield, chained lantern mace, "
    "premium polished anime tactical SRPG card, adult woman guardian, elegant eight-head full body, head and boots visible, "
    "non-explicit isolated studio character art, flat solid chroma green background"
)
NEGATIVE = (
    "chibi, SD, child, teen, male, cropped, closeup, portrait, scenery, shadow, text, logo, multiple people, extra limbs, "
    "duplicate arms, missing shield, missing weapon, white background, black background, gray background"
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def full_body_guide() -> Image.Image:
    guide = Image.new("RGB", SIZE, (255, 255, 255))
    draw = ImageDraw.Draw(guide)
    ink = (0, 0, 0)
    cx = 388
    draw.ellipse((cx - 60, 60, cx + 60, 180), outline=ink, width=10)
    draw.line((cx, 180, cx, 490), fill=ink, width=12)
    draw.line((cx - 110, 275, cx + 105, 275), fill=ink, width=12)
    draw.line((cx - 95, 275, cx - 175, 500), fill=ink, width=12)
    draw.line((cx + 95, 275, cx + 160, 490), fill=ink, width=12)
    draw.polygon([(cx - 120, 350), (cx + 120, 350), (cx + 100, 605), (cx - 100, 605)], outline=ink, width=12)
    draw.line((cx - 58, 595, cx - 112, 1035), fill=ink, width=14)
    draw.line((cx + 58, 595, cx + 112, 1035), fill=ink, width=14)
    draw.line((cx - 172, 1035, cx - 72, 1035), fill=ink, width=18)
    draw.line((cx + 72, 1035, cx + 172, 1035), fill=ink, width=18)
    # The shield is deliberately a separate, unmistakable mass. The lantern
    # chain is a lightweight diagonal cue on the opposite side.
    draw.polygon([(520, 270), (695, 340), (704, 650), (614, 805), (522, 710)], outline=ink, width=18)
    draw.line((255, 470, 125, 900), fill=ink, width=14)
    return guide


def exact_green_source(raw: Image.Image, sam: Sam2Model, processor: Sam2Processor) -> Image.Image:
    """Use a fresh, full-body SAM2 mask then compose the *new* render over #00FF00.

    This does not reuse or repair any rejected R1--R5 art.  It deliberately
    avoids hue-only extraction: teal hair and shield materials are foreground,
    while every pixel outside the generated subject becomes exact authoring
    green.  The result is therefore a clean chroma source, not a screenshot
    with an unkeyed white/grey backing.
    """
    width, height = raw.size
    points = [[[
        [width // 2, int(height * 0.22)], [width // 2, int(height * 0.48)],
        [width // 2, int(height * 0.78)], [int(width * 0.73), int(height * 0.45)],
        [int(width * 0.23), int(height * 0.62)],
    ]]]
    labels = [[[1, 1, 1, 1, 1]]]
    boxes = [[[46, 34, width - 46, height - 34]]]
    inputs = processor(images=raw, input_points=points, input_labels=labels, input_boxes=boxes, return_tensors="pt")
    inputs = {key: value.to("cuda") if hasattr(value, "to") else value for key, value in inputs.items()}
    with torch.inference_mode():
        outputs = sam(**inputs, multimask_output=True)
    masks = processor.post_process_masks(outputs.pred_masks.cpu(), inputs["original_sizes"].cpu())[0]
    scores = outputs.iou_scores[0, 0].detach().cpu().tolist()
    index = max(range(len(scores)), key=lambda value: scores[value])
    mask = masks[0, index].detach().cpu().numpy().astype(np.uint8) * 255
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8), iterations=1)
    # Conservative one-pixel feather removes green sawteeth without admitting
    # any of the rejected source image's old pale backdrop (which is absent).
    mask = cv2.GaussianBlur(mask, (0, 0), 0.55)
    rgb = np.asarray(raw.convert("RGB"))
    green = np.zeros_like(rgb); green[:, :] = GREEN
    alpha = (mask.astype(np.float32) / 255.0)[..., None]
    return Image.fromarray(np.round(rgb * alpha + green * (1.0 - alpha)).astype(np.uint8), "RGB")


def key_green(source: Image.Image) -> Image.Image:
    rgb = source.convert("RGB")
    alpha = Image.new("L", rgb.size, 255)
    pixels = rgb.load()
    alpha_pixels = alpha.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            red, green, blue = pixels[x, y]
            if green >= 160 and green - red >= 72 and green - blue >= 72:
                alpha_pixels[x, y] = 0
    image = rgb.convert("RGBA")
    image.putalpha(alpha)
    if image.getchannel("A").getextrema() != (0, 255):
        raise RuntimeError("green source did not yield genuine RGBA")
    return image


def main() -> int:
    for path in (BASE / "model_index.json", CONTROL / "config.json", IP_ROOT / "sdxl_models" / "ip-adapter_sdxl_vit-h.safetensors", IP_ENCODER / "config.json", SAM2 / "config.json", SD_REFERENCE):
        if not path.is_file():
            raise FileNotFoundError(path)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    tokenizers = [CLIPTokenizer.from_pretrained(BASE / part, local_files_only=True) for part in ("tokenizer", "tokenizer_2")]
    if max(len(tokenizer(PROMPT, truncation=False).input_ids) for tokenizer in tokenizers) > 77:
        raise RuntimeError("prompt must remain within SDXL's 77-token limit")
    if max(len(tokenizer(NEGATIVE, truncation=False).input_ids) for tokenizer in tokenizers) > 77:
        raise RuntimeError("negative prompt must remain within SDXL's 77-token limit")
    sam = Sam2Model.from_pretrained(SAM2, local_files_only=True, torch_dtype=torch.float16).to("cuda").eval()
    processor = Sam2Processor.from_pretrained(SAM2, local_files_only=True)
    control = ControlNetModel.from_pretrained(CONTROL, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True)
    pipe = StableDiffusionXLControlNetPipeline.from_pretrained(BASE, controlnet=control, torch_dtype=torch.float16, variant="fp16", use_safetensors=True, local_files_only=True)
    pipe.load_ip_adapter(str(IP_ROOT), subfolder="sdxl_models", weight_name="ip-adapter_sdxl_vit-h.safetensors", image_encoder_folder=str(IP_ENCODER), local_files_only=True)
    pipe.set_ip_adapter_scale(0.48)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, algorithm_type="dpmsolver++", use_karras_sigmas=True)
    pipe.vae.enable_slicing(); pipe.vae.enable_tiling(); pipe.enable_model_cpu_offload(gpu_id=0)
    guide = full_body_guide()
    guide_path = OUTPUT / "chr001_8head_r6_fullbody_canny_guide.png"
    guide.save(guide_path, optimize=True)
    preview = Image.open(SD_REFERENCE).convert("RGBA")
    appearance = Image.new("RGBA", preview.size, GREEN + (255,))
    appearance.alpha_composite(preview)
    appearance = appearance.convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
    records = []
    for ordinal, seed in enumerate(SEEDS, start=1):
        raw = pipe(
            prompt=PROMPT, negative_prompt=NEGATIVE, image=guide, ip_adapter_image=appearance, width=SIZE[0], height=SIZE[1],
            num_inference_steps=40, guidance_scale=6.8, controlnet_conditioning_scale=0.76,
            generator=torch.Generator(device="cuda").manual_seed(seed),
        ).images[0].convert("RGB")
        raw_path = OUTPUT / f"chr001_8head_r6v{ordinal:02d}_seed{seed}_raw_fresh.png"
        raw.save(raw_path, optimize=True)
        green = exact_green_source(raw, sam, processor)
        green_path = OUTPUT / f"chr001_8head_r6v{ordinal:02d}_seed{seed}_green_matte.png"
        rgba_path = OUTPUT / f"chr001_8head_r6v{ordinal:02d}_seed{seed}_rgba.png"
        green.save(green_path, optimize=True)
        keyed = key_green(green)
        keyed.save(rgba_path, optimize=True)
        corners = [green.getpixel(point) for point in ((0, 0), (767, 0), (0, 1151), (767, 1151))]
        if any(pixel != GREEN for pixel in corners):
            raise RuntimeError(f"source field is not flat #00FF00: {corners}")
        records.append({
            "candidate": ordinal, "seed": seed,
            "rawFreshRender": raw_path.relative_to(ROOT).as_posix(), "rawFreshRenderSha256": sha256(raw_path),
            "greenMatte": green_path.relative_to(ROOT).as_posix(), "greenMatteSha256": sha256(green_path),
            "rgba": rgba_path.relative_to(ROOT).as_posix(), "rgbaSha256": sha256(rgba_path),
            "alphaExtrema": list(keyed.getchannel("A").getextrema()),
            "status": "CANDIDATE_PENDING_VISUAL_COSTUME_AND_IDENTITY_QA",
        })
        print(f"CHR001_R6_GREEN_CANDIDATE={green_path}")
    manifest = {
        "characterId": "CHR001", "status": "UNREVIEWED_FROM_SCRATCH_GREEN_MATTE_CANDIDATES",
        "generationMatte": "#00FF00", "runtimeBackground": "RGBA_TRANSPARENT",
        "model": "stabilityai-sdxl-base-1.0-local + controlnet-canny-sdxl-1.0-local + ip-adapter-sdxl-local + sam2.1-hiera-small-local",
        "guide": guide_path.relative_to(ROOT).as_posix(), "prompt": PROMPT, "negativePrompt": NEGATIVE,
        "identityRequirements": ["turquoise high ponytail", "gold crown ornament", "teal-gold guardian armour", "kite shield", "chained lantern"],
        "continuityReference": SD_REFERENCE.relative_to(ROOT).as_posix(),
        "candidates": records,
    }
    (OUTPUT / "chr001_8head_r6_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "CHR001_R6_CANDIDATES_READY", "count": len(records)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
