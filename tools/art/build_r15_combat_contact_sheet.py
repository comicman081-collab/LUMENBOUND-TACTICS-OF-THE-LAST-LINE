#!/usr/bin/env python3
"""Build a review-only keyframe sheet from the shipped R15 combat atlases.

This intentionally reads the runtime animation manifests rather than assuming
fixed atlas positions.  It is a QA artifact: it never changes source art,
atlas files, or gameplay data.
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
COMBAT_ROOT = ROOT / "godot" / "assets" / "runtime_web" / "combat"
OUTPUT = ROOT / "reports" / "r15" / "art_b" / "contact_sheets" / "R15_COMBAT_KEYFRAMES_R1.png"
ENTITY_ORDER = [
    "CHR001", "CHR002", "CHR003", "CHR004", "CHR005", "CHR006", "CHR007", "CHR008",
    "ENM001", "ENM002", "ENM003", "ENM004", "ENM005", "ENM006", "ENM007", "ENM008", "ENM009",
    "BOSS001", "BOSS002",
]
SAMPLES = [("IDLE", "idle", 0), ("BASIC", "basic_attack", 0.55), ("NORMAL", "normal_skill", 0.55), ("ULT", "ultimate", 0.55), ("DOWN", "down", 0.9)]
CELL_W, CELL_H = 168, 184
HEADER_H, ROW_H = 60, 28
COLUMNS = len(SAMPLES)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/malgunbd.ttf" if bold else "C:/Windows/Fonts/malgun.ttf"),
        Path("C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def load_manifest(entity_id: str) -> tuple[dict, Image.Image]:
    folder = COMBAT_ROOT / entity_id
    manifest = json.loads((folder / "animation_manifest.json").read_text(encoding="utf-8"))
    atlas = Image.open(folder / manifest["atlas_path"]).convert("RGBA")
    return manifest, atlas


def frame(manifest: dict, atlas: Image.Image, animation: str, fraction: float) -> Image.Image:
    indices = manifest["animations"][animation]["frame_indices"]
    index = indices[min(len(indices) - 1, round((len(indices) - 1) * fraction))]
    frame_w, frame_h = manifest["frame_size"]
    columns = int(manifest["atlas_columns"])
    x = (index % columns) * frame_w
    y = (index // columns) * frame_h
    return atlas.crop((x, y, x + frame_w, y + frame_h))


def checker(canvas: Image.Image, box: tuple[int, int, int, int]) -> None:
    draw = ImageDraw.Draw(canvas)
    x0, y0, x1, y1 = box
    size = 12
    for y in range(y0, y1, size):
        for x in range(x0, x1, size):
            even = ((x - x0) // size + (y - y0) // size) % 2 == 0
            draw.rectangle((x, y, min(x + size - 1, x1), min(y + size - 1, y1)), fill=(30, 42, 58) if even else (42, 58, 77))


def main() -> None:
    width = COLUMNS * CELL_W
    height = HEADER_H + len(ENTITY_ORDER) * (CELL_H + ROW_H)
    sheet = Image.new("RGBA", (width, height), (8, 14, 25, 255))
    draw = ImageDraw.Draw(sheet)
    heading = font(22, True)
    label = font(14, True)
    small = font(12)
    draw.text((16, 16), "R15 Combat Keyframes — shipped Web atlases", font=heading, fill=(119, 241, 220, 255))
    for col, (caption, _, _) in enumerate(SAMPLES):
        x = col * CELL_W
        draw.text((x + 12, 43), caption, font=label, fill=(179, 204, 226, 255))

    for row, entity_id in enumerate(ENTITY_ORDER):
        y = HEADER_H + row * (CELL_H + ROW_H)
        manifest, atlas = load_manifest(entity_id)
        status = str(manifest.get("status", "UNKNOWN"))
        color = (112, 226, 188, 255) if entity_id.startswith("CHR") else (255, 182, 107, 255)
        draw.rectangle((0, y, width - 1, y + ROW_H - 1), fill=(15, 30, 48, 255))
        draw.text((8, y + 5), entity_id, font=label, fill=color)
        draw.text((78, y + 7), "IMAGEGEN" if status.startswith("IMAGEGEN") else "BLENDER/ATLAS", font=small, fill=(137, 161, 184, 255))
        for col, (_, animation, fraction) in enumerate(SAMPLES):
            x = col * CELL_W
            top = y + ROW_H
            checker(sheet, (x + 1, top + 1, x + CELL_W - 2, top + CELL_H - 2))
            sample = frame(manifest, atlas, animation, fraction)
            scale = min((CELL_W - 18) / sample.width, (CELL_H - 18) / sample.height)
            resized = sample.resize((max(1, round(sample.width * scale)), max(1, round(sample.height * scale))), Image.Resampling.NEAREST)
            px = x + (CELL_W - resized.width) // 2
            py = top + (CELL_H - resized.height) // 2
            sheet.alpha_composite(resized, (px, py))
            draw.rectangle((x, top, x + CELL_W - 1, top + CELL_H - 1), outline=(59, 88, 115, 255), width=1)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
