#!/usr/bin/env python3
"""Convert one chroma-matte VFX key-art cutout into a 12-frame RGBA atlas.

The generator's matte is provenance only.  This utility removes a flat green
matte, preserves non-matte lime details, and derives a compact charge/impact/
fade animation without ever exporting the chroma colour to the runtime.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageFilter


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def remove_green_matte(image: Image.Image) -> Image.Image:
    """Key only strongly green-dominant pixels; retain yellow/lime effect art."""
    result = image.convert("RGBA")
    pixels = result.load()
    width, height = result.size
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            green_excess = green - max(red, blue)
            if green >= 160 and green_excess >= 120:
                # A #00ff00 matte is fully removed.  The soft shoulder avoids
                # a hard chroma outline while the 120 threshold protects the
                # intentional pale-lime ribbon and gem highlights.
                retention = max(0.0, min(1.0, (170 - green_excess) / 50.0))
                alpha = round(alpha * retention)
                if alpha == 0:
                    pixels[x, y] = (0, 0, 0, 0)
                else:
                    # Decontaminate only the matte transition edge; preserve
                    # the authored hue relationship in actual effect pixels.
                    green = min(green, max(red, blue) + 105)
                    pixels[x, y] = (red, green, blue, alpha)
    return result


def source_background_contract(image: Image.Image) -> str:
    """Record truthfully whether this source used the optional green matte."""
    rgba = image.convert("RGBA")
    pixels = rgba.getdata()
    chroma_pixels = sum(1 for red, green, blue, alpha in pixels if alpha > 0 and green >= 160 and green - max(red, blue) >= 120)
    return "#00ff00 intermediate only" if chroma_pixels >= (rgba.width * rgba.height) // 20 else "RGBA source; no chroma matte used"


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    box = image.getchannel("A").getbbox()
    if box is None:
        raise ValueError("matte removal produced an empty VFX cutout")
    left, top, right, bottom = box
    width, height = image.size
    padding = max(8, round(max(right - left, bottom - top) * 0.07))
    return max(0, left - padding), max(0, top - padding), min(width, right + padding), min(height, bottom + padding)


def compose_frame(source: Image.Image, scale: float, rotation: float, opacity: float, cell: int) -> Image.Image:
    extent = max(1, round(cell * scale))
    art = source.resize((extent, extent), Image.Resampling.LANCZOS).rotate(rotation, Image.Resampling.BICUBIC, expand=True)
    alpha = art.getchannel("A").point(lambda value: round(value * opacity))
    art.putalpha(alpha)
    frame = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    glow = Image.new("RGBA", art.size, (220, 249, 255, 0))
    glow.putalpha(alpha.filter(ImageFilter.GaussianBlur(max(1, round(cell * .035)))).point(lambda value: round(value * .42)))
    position = ((cell - art.width) // 2, (cell - art.height) // 2)
    frame.alpha_composite(glow, position)
    frame.alpha_composite(art, position)
    return frame


def build_atlas(keyart: Image.Image, cell: int) -> Image.Image:
    # Charge -> impact -> residual.  A light rotation and scale progression
    # makes one premium key-art source read as an authored tactical cast, not
    # as a static card pasted over the combatant.
    scales = (.38, .50, .64, .79, .95, 1.11, 1.25, 1.17, 1.06, .93, .77, .60)
    rotations = (-13, -9, -6, -3, 0, 3, 6, 8, 10, 12, 15, 18)
    opacities = (.20, .36, .55, .73, .90, 1.0, 1.0, .92, .79, .62, .43, .24)
    atlas = Image.new("RGBA", (cell * 4, cell * 3), (0, 0, 0, 0))
    for index, (scale, rotation, opacity) in enumerate(zip(scales, rotations, opacities)):
        frame = compose_frame(keyart, scale, rotation, opacity, cell)
        atlas.alpha_composite(frame, ((index % 4) * cell, (index // 4) * cell))
    return atlas


def checker_preview(atlas: Image.Image) -> Image.Image:
    preview = Image.new("RGBA", atlas.size, (17, 24, 36, 255))
    for y in range(0, atlas.height, 14):
        for x in range(0, atlas.width, 14):
            if (x // 14 + y // 14) % 2 == 0:
                preview.paste((36, 47, 65, 255), (x, y, min(x + 14, atlas.width), min(y + 14, atlas.height)))
    preview.alpha_composite(atlas)
    return preview


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("clean_output", type=Path)
    parser.add_argument("atlas_output", type=Path)
    parser.add_argument("--preview", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--cell", type=int, default=112)
    args = parser.parse_args()

    source_image = Image.open(args.input)
    source_contract = source_background_contract(source_image)
    keyed = remove_green_matte(source_image)
    box = alpha_bbox(keyed)
    crop = keyed.crop(box)
    square = Image.new("RGBA", (max(crop.width, crop.height), max(crop.width, crop.height)), (0, 0, 0, 0))
    square.alpha_composite(crop, ((square.width - crop.width) // 2, (square.height - crop.height) // 2))
    atlas = build_atlas(square, args.cell)

    for path in (args.clean_output, args.atlas_output):
        path.parent.mkdir(parents=True, exist_ok=True)
    square.save(args.clean_output, optimize=True)
    atlas.save(args.atlas_output, optimize=True)
    if args.preview:
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        checker_preview(atlas).save(args.preview, optimize=True)
    report = {
        "schema_version": 1,
        "source": str(args.input),
        "source_sha256": sha256(args.input),
        "matte": source_contract,
        "clean_source": str(args.clean_output),
        "clean_source_sha256": sha256(args.clean_output),
        "atlas": str(args.atlas_output),
        "atlas_sha256": sha256(args.atlas_output),
        "atlas_size": list(atlas.size),
        "alpha_extrema": list(atlas.getchannel("A").getextrema()),
        "source_crop": list(box),
    }
    report_path = args.report or args.atlas_output.with_suffix(".json")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
