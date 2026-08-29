#!/usr/bin/env python3
"""Build SD-authority versus 8-head-candidate continuity review sheets."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
CONTRACT = (
    ROOT
    / "data_source"
    / "art_source"
    / "card_8head_green_matte_r1"
    / "qa"
    / "CARD_8HEAD_CANDIDATE_CONTRACT.json"
)
OUTPUT_DIR = ROOT / "builds" / "qa" / "card_8head_identity_review"
CELL_W, CELL_H = 640, 640
COLS, ROWS = 3, 3


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    name = "arialbd.ttf" if bold else "arial.ttf"
    path = Path("C:/Windows/Fonts") / name
    return ImageFont.truetype(str(path), size) if path.is_file() else ImageFont.load_default()


def contain(image: Image.Image, box: tuple[int, int]) -> Image.Image:
    result = image.convert("RGBA")
    result.thumbnail(box, Image.Resampling.LANCZOS)
    return result


def checker(size: tuple[int, int], block: int = 24) -> Image.Image:
    width, height = size
    result = Image.new("RGB", size, "#E8EDF5")
    draw = ImageDraw.Draw(result)
    for y in range(0, height, block):
        for x in range(0, width, block):
            if (x // block + y // block) % 2:
                draw.rectangle((x, y, x + block - 1, y + block - 1), fill="#CBD4E2")
    return result


def paste_center(canvas: Image.Image, image: Image.Image, box: tuple[int, int, int, int]) -> None:
    left, top, right, bottom = box
    fitted = contain(image, (right - left, bottom - top))
    x = left + (right - left - fitted.width) // 2
    y = top + (bottom - top - fitted.height) // 2
    canvas.paste(fitted, (x, y), fitted)


def make_cell(entity_id: str, candidate: dict) -> Image.Image:
    cell = Image.new("RGB", (CELL_W, CELL_H), "#111827")
    draw = ImageDraw.Draw(cell)
    draw.rounded_rectangle((8, 8, CELL_W - 8, CELL_H - 8), 18, fill="#162033", outline="#5EEAD4", width=2)
    title = f"{entity_id}  {candidate['characterName']} · {candidate['combatRole']}"
    draw.text((24, 20), title, font=font(24, True), fill="#F8FAFC")
    draw.text((34, 58), "A · EXISTING SD AUTHORITY", font=font(14, True), fill="#FBBF24")
    draw.text((338, 58), "B · 8-HEAD CARD CANDIDATE", font=font(14, True), fill="#67E8F9")

    left_panel = checker((282, 480))
    right_panel = checker((282, 480))
    authority = Image.open(ROOT / candidate["identityReference"]).convert("RGBA")
    card = Image.open(ROOT / candidate["rgbaCandidate"]).convert("RGBA")
    paste_center(left_panel, authority, (8, 8, 274, 472))
    paste_center(right_panel, card, (8, 8, 274, 472))
    cell.paste(left_panel, (28, 86))
    cell.paste(right_panel, (330, 86))
    draw.rectangle((28, 86, 309, 565), outline="#64748B", width=2)
    draw.rectangle((330, 86, 611, 565), outline="#64748B", width=2)
    draw.text((28, 578), "CHECK: face/hair · costume · weapon · role silhouette", font=font(15), fill="#D5E4F7")
    draw.text((28, 605), "MATTE #00FF00 → RGBA / status: PENDING GPT REVIEW", font=font(14), fill="#86EFAC")
    return cell


def main() -> None:
    document = json.loads(CONTRACT.read_text(encoding="utf-8"))
    items = list(document["candidates"].items())
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    outputs = []
    for page_index in range(0, len(items), COLS * ROWS):
        page_items = items[page_index : page_index + COLS * ROWS]
        sheet = Image.new("RGB", (CELL_W * COLS, CELL_H * ROWS), "#070B14")
        for cell_index, (entity_id, candidate) in enumerate(page_items):
            x = (cell_index % COLS) * CELL_W
            y = (cell_index // COLS) * CELL_H
            sheet.paste(make_cell(entity_id, candidate), (x, y))
        first = page_items[0][0]
        last = page_items[-1][0]
        output = OUTPUT_DIR / f"CARD_8HEAD_SD_AUTHORITY_COMPARE_{first}_{last}.jpg"
        sheet.save(output, quality=94, subsampling=0)
        outputs.append(output.relative_to(ROOT).as_posix())
    print(json.dumps({"reviewSheets": outputs, "count": len(items)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
