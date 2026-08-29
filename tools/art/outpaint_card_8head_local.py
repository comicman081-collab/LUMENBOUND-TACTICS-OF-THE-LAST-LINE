#!/usr/bin/env python3
"""Local SDXL inpaint pilot: extend a high-quality torso card into a full body.

This is a candidate-only helper.  It neither writes runtime files nor marks a
continuity contract as approved.  Its only job is to test whether a mature
upper-body render can be extended to boots without reintroducing SD/chibi art.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
MODEL_ROOT = Path(r"C:\AI_MODELS\sdxl-inpaint")
SIZE = (768, 1152)
GREEN = (0, 255, 0)


def cutout(image: Image.Image) -> tuple[Image.Image, Image.Image]:
    """Get a conservative central subject mask for the upper-body source."""
    rgb = np.asarray(image.convert("RGB"))
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    height, width = bgr.shape[:2]
    mask = np.zeros((height, width), np.uint8)
    background_model = np.zeros((1, 65), np.float64)
    foreground_model = np.zeros((1, 65), np.float64)
    cv2.grabCut(bgr, mask, (8, 8, width - 16, height - 16), background_model, foreground_model, 6, cv2.GC_INIT_WITH_RECT)
    alpha = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype("uint8")
    alpha = cv2.morphologyEx(alpha, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8), iterations=1)
    result = Image.fromarray(rgb, "RGB").convert("RGBA")
    result.putalpha(Image.fromarray(alpha, "L"))
    return result, Image.fromarray(alpha, "L")


def seed_canvas(source: Path) -> tuple[Image.Image, Image.Image]:
    subject, _ = cutout(Image.open(source))
    subject.thumbnail((540, 690), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", SIZE, GREEN + (255,))
    canvas.alpha_composite(subject, ((SIZE[0] - subject.width) // 2, 42))
    # Preserve face/shoulders; request legs and boots from the waist down.
    mask = Image.new("L", SIZE, 255)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rectangle((0, 0, SIZE[0], 410), fill=0)
    # Keep only actual upper-body pixels in the protected area. Transparent
    # holes must be regenerated as exact-green background rather than frozen.
    upper_alpha = canvas.getchannel("A").crop((0, 0, SIZE[0], 410))
    mask.paste(Image.eval(upper_alpha, lambda value: 0 if value > 24 else 255), (0, 0))
    return canvas.convert("RGB"), mask


def green_matte(image: Image.Image) -> Image.Image:
    """Use a second conservative GrabCut pass to make an exact #00FF00 source."""
    subject, alpha = cutout(image)
    result = Image.new("RGB", SIZE, GREEN)
    result.paste(subject.convert("RGB"), (0, 0), alpha)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--steps", type=int, default=30)
    parser.add_argument("--seed", type=int, default=8181)
    args = parser.parse_args()
    if not args.source.is_file():
        raise FileNotFoundError(args.source)
    if not MODEL_ROOT.is_dir():
        raise FileNotFoundError(MODEL_ROOT)

    import torch
    from diffusers import EulerAncestralDiscreteScheduler, StableDiffusionXLInpaintPipeline

    pipe = StableDiffusionXLInpaintPipeline.from_pretrained(
        str(MODEL_ROOT), torch_dtype=torch.float16, use_safetensors=True, variant="fp16"
    )
    pipe.scheduler = EulerAncestralDiscreteScheduler.from_config(pipe.scheduler.config)
    pipe.enable_model_cpu_offload()
    pipe.vae.enable_slicing()
    pipe.set_progress_bar_config(disable=True)
    image, mask = seed_canvas(args.source)
    prompt = (
        "high-end anime tactical SRPG card, adult woman, full body, 8-head proportion, "
        "head to boots visible, flat chroma green backdrop, refined linework, crisp cel shading, "
        "navy cyan silver armored vanguard, elegant boots, blade, three-quarter standing pose"
    )
    negative = "chibi, SD, child, close-up, portrait, cropped, 3d render, toy, duplicate, extra legs, malformed hands, scenery, text"
    rendered = pipe(
        prompt=prompt,
        negative_prompt=negative,
        image=image,
        mask_image=mask,
        num_inference_steps=args.steps,
        guidance_scale=7.5,
        strength=0.97,
        generator=torch.Generator(device="cuda").manual_seed(args.seed),
        width=SIZE[0],
        height=SIZE[1],
    ).images[0]
    result = green_matte(rendered)
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    result.save(args.destination, optimize=True)
    print(f"CARD_8HEAD_OUTPAINT_CANDIDATE={args.destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
