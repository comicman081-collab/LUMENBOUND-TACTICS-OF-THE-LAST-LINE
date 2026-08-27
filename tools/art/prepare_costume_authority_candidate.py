"""Prepare a transparent costume candidate and a labeled continuity sheet.

This is intentionally limited to removing a generated neutral checkerboard from
the *edge-connected* background.  It never alters enclosed costume pixels.
"""
from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def is_neutral_light(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    return alpha > 0 and min(red, green, blue) >= 232 and max(red, green, blue) - min(red, green, blue) <= 9


def clear_edge_connected_checker(image: Image.Image) -> Image.Image:
    result = image.convert("RGBA")
    pixels = result.load()
    width, height = result.size
    queue: deque[tuple[int, int]] = deque()
    seen: set[tuple[int, int]] = set()
    for x in range(width):
        queue.extend(((x, 0), (x, height - 1)))
    for y in range(1, height - 1):
        queue.extend(((0, y), (width - 1, y)))
    while queue:
        x, y = queue.popleft()
        if (x, y) in seen or not is_neutral_light(pixels[x, y]):
            continue
        seen.add((x, y))
        pixels[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < width and 0 <= ny < height:
                queue.append((nx, ny))
    return result


def checker(size: tuple[int, int]) -> Image.Image:
    canvas = Image.new("RGBA", size, (242, 245, 250, 255))
    draw = ImageDraw.Draw(canvas)
    step = 32
    for y in range(0, size[1], step):
        for x in range(0, size[0], step):
            if (x // step + y // step) % 2:
                draw.rectangle((x, y, x + step - 1, y + step - 1), fill=(228, 232, 240, 255))
    return canvas


def fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    result = image.copy()
    result.thumbnail(size, Image.Resampling.LANCZOS)
    return result


def build_sheet(authority: Image.Image, candidate: Image.Image, output: Path) -> None:
    panel = (700, 900)
    canvas = Image.new("RGBA", (panel[0] * 2, panel[1] + 76), (16, 22, 37, 255))
    font = ImageFont.load_default()
    draw = ImageDraw.Draw(canvas)
    for index, (label, source) in enumerate((("A · ORIGINAL AUTHORITY", authority), ("B · COSTUME ONLY CANDIDATE", candidate))):
        x = index * panel[0]
        draw.rectangle((x, 76, x + panel[0] - 1, canvas.height - 1), fill=(29, 39, 61, 255))
        draw.text((20 + x, 26), label, fill=(245, 248, 255, 255), font=font)
        field = checker((panel[0] - 48, panel[1] - 48))
        art = fit(source, (panel[0] - 90, panel[1] - 90))
        field.alpha_composite(art, ((field.width - art.width) // 2, (field.height - art.height) // 2))
        canvas.alpha_composite(field, (x + 24, 100))
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("authority", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("cleaned", type=Path)
    parser.add_argument("sheet", type=Path)
    args = parser.parse_args()
    authority = Image.open(args.authority).convert("RGBA")
    candidate = clear_edge_connected_checker(Image.open(args.candidate).convert("RGBA"))
    args.cleaned.parent.mkdir(parents=True, exist_ok=True)
    candidate.save(args.cleaned, optimize=True)
    build_sheet(authority, candidate, args.sheet)


if __name__ == "__main__":
    main()
