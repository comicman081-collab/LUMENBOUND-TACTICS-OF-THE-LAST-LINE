#!/usr/bin/env python3
"""Validate and normalize a generated 4x3 RGBA VFX atlas for Web runtime QA."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def alpha_occupancy(image: Image.Image, box: tuple[int, int, int, int], threshold: int = 32) -> float:
    values = list(image.getchannel("A").crop(box).getdata())
    return sum(value > threshold for value in values) / max(1, len(values))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--preview", type=Path)
    parser.add_argument("--masked-source-output", type=Path)
    parser.add_argument("--cell", type=int, default=112)
    parser.add_argument("--clear-center", action="store_true")
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGBA")
    width, height = source.size
    if width % 4 or height % 3 or width // 4 != height // 3:
        raise ValueError(f"expected 4x3 square-cell atlas, got {source.size}")
    if source.getchannel("A").getextrema()[0] != 0:
        raise ValueError("atlas has no transparent pixels")

    source_cell = width // 4
    atlas = Image.new("RGBA", (args.cell * 4, args.cell * 3), (0, 0, 0, 0))
    masked_source_atlas = Image.new("RGBA", source.size, (0, 0, 0, 0))
    frames = []
    for index in range(12):
        left = (index % 4) * source_cell
        top = (index // 4) * source_cell
        frame = source.crop((left, top, left + source_cell, top + source_cell))
        center_margin = int(round(source_cell * .275))
        center_box = (center_margin, center_margin, source_cell - center_margin, source_cell - center_margin)
        source_center_occupancy = alpha_occupancy(frame, center_box)
        if args.clear_center:
            mask = Image.new("L", (source_cell, source_cell), 255)
            mask_pixels = mask.load()
            center = (source_cell - 1) * .5
            inner = source_cell * .205
            outer = source_cell * .325
            for y in range(source_cell):
                for x in range(source_cell):
                    distance = ((x - center) ** 2 + (y - center) ** 2) ** .5
                    if distance <= inner:
                        mask_pixels[x, y] = 0
                    elif distance < outer:
                        mask_pixels[x, y] = round(255 * (distance - inner) / (outer - inner))
            frame.putalpha(ImageChops.multiply(frame.getchannel("A"), mask))
        center_occupancy = alpha_occupancy(frame, center_box)
        masked_source_atlas.alpha_composite(frame, (left, top))
        normalized = frame.resize((args.cell, args.cell), Image.Resampling.LANCZOS)
        atlas.alpha_composite(normalized, ((index % 4) * args.cell, (index // 4) * args.cell))
        frames.append({
            "frame": index,
            "source_center_alpha_occupancy": round(source_center_occupancy, 4),
            "runtime_center_alpha_occupancy": round(center_occupancy, 4),
        })

    args.output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(args.output, optimize=True)
    if args.masked_source_output:
        args.masked_source_output.parent.mkdir(parents=True, exist_ok=True)
        masked_source_atlas.save(args.masked_source_output, optimize=True)

    if args.preview:
        checker = Image.new("RGBA", atlas.size, (20, 27, 39, 255))
        draw = ImageDraw.Draw(checker)
        tile = 14
        for y in range(0, checker.height, tile):
            for x in range(0, checker.width, tile):
                if (x // tile + y // tile) % 2 == 0:
                    draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill=(42, 51, 66, 255))
        checker.alpha_composite(atlas)
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        checker.save(args.preview, optimize=True)

    report_path = args.report or args.output.with_suffix(".json")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "schema_version": 1,
        "source": str(args.input),
        "source_sha256": sha256(args.input),
        "source_size": [width, height],
        "source_cell": source_cell,
        "runtime_atlas": str(args.output),
        "runtime_sha256": sha256(args.output),
        "runtime_cell": args.cell,
        "center_clearance_applied": bool(args.clear_center),
        "masked_source": str(args.masked_source_output) if args.masked_source_output else "",
        "alpha_extrema": list(source.getchannel("A").getextrema()),
        "frames": frames,
        "central_clearance_policy": "visual review required; occupancy is diagnostic, not automatic acceptance",
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
