#!/usr/bin/env python3
"""Build a review-only sheet for player SD proportion and enemy-facing QA."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
COMBAT_ROOT = ROOT / "godot" / "assets" / "runtime_web" / "combat"
OUTPUT = ROOT / "reports" / "r15" / "art_b" / "contact_sheets" / "PLAYER_SD_ORIENTATION_R1.png"
IDS = [f"CHR{index:03d}" for index in range(1, 45)]
COLS = 8
CELL_W, CELL_H = 260, 300


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/malgunbd.ttf" if bold else "C:/Windows/Fonts/malgun.ttf"),
        Path("C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def checker(canvas: Image.Image, box: tuple[int, int, int, int]) -> None:
    draw = ImageDraw.Draw(canvas)
    x0, y0, x1, y1 = box
    size = 14
    for y in range(y0, y1, size):
        for x in range(x0, x1, size):
            fill = (28, 39, 55, 255) if ((x - x0) // size + (y - y0) // size) % 2 == 0 else (42, 56, 74, 255)
            draw.rectangle((x, y, min(x + size - 1, x1), min(y + size - 1, y1)), fill=fill)


def main() -> None:
    rows = (len(IDS) + COLS - 1) // COLS
    sheet = Image.new("RGBA", (COLS * CELL_W, rows * CELL_H + 54), (8, 14, 24, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((18, 13), "Player runtime battle read — SD proportion + face-right contract", font=font(24, True), fill=(116, 238, 219, 255))
    label_font = font(18, True)
    note_font = font(12)
    for index, entity_id in enumerate(IDS):
        col, row = index % COLS, index // COLS
        x, y = col * CELL_W, 54 + row * CELL_H
        checker(sheet, (x + 1, y + 1, x + CELL_W - 2, y + CELL_H - 2))
        folder = COMBAT_ROOT / entity_id
        manifest = json.loads((folder / "animation_manifest.json").read_text(encoding="utf-8"))
        preview = Image.open(folder / manifest["preview_path"]).convert("RGBA")
        bbox = preview.getchannel("A").getbbox()
        if bbox is not None:
            art = preview.crop(bbox)
            art.thumbnail((CELL_W - 28, CELL_H - 68), Image.Resampling.LANCZOS)
            sheet.alpha_composite(art, (x + (CELL_W - art.width) // 2, y + 32 + (CELL_H - 68 - art.height) // 2))
        draw.rectangle((x, y, x + CELL_W - 1, y + CELL_H - 1), outline=(67, 91, 119, 255), width=2)
        draw.rectangle((x + 6, y + 6, x + 88, y + 31), fill=(11, 20, 34, 230))
        draw.text((x + 12, y + 8), entity_id, font=label_font, fill=(240, 247, 255, 255))
        lineage = "SD ATLAS" if str(manifest.get("status", "")).startswith("RUNTIME_WEB") else "STATIC SOURCE"
        draw.text((x + 96, y + 11), lineage, font=note_font, fill=(151, 185, 212, 255))
        draw.text((x + 8, y + CELL_H - 23), "target: adult SD 3.5–4H · faces →", font=note_font, fill=(191, 215, 232, 255))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUTPUT, optimize=True)
    print(OUTPUT)


if __name__ == "__main__":
    main()
