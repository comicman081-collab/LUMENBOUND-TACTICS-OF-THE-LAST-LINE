#!/usr/bin/env python3
"""Convert an ImageGen white/checker preview matte into real RGBA.

Only bright, low-chroma pixels connected to the canvas boundary are removed.
That preserves white costume modules enclosed by the character outline while
clearing both solid-white and baked neutral checker backgrounds.
"""
from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


def is_neutral_matte(pixel: tuple[int, int, int]) -> bool:
    lo = min(pixel)
    hi = max(pixel)
    return lo >= 178 and hi - lo <= 24


def extract(source: Path, destination: Path) -> None:
    rgb = Image.open(source).convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    background = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    def seed(x: int, y: int) -> None:
        index = y * width + x
        if not background[index] and is_neutral_matte(pixels[x, y]):
            background[index] = 1
            queue.append((x, y))

    for x in range(width):
        seed(x, 0)
        seed(x, height - 1)
    for y in range(height):
        seed(0, y)
        seed(width - 1, y)

    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if nx < 0 or ny < 0 or nx >= width or ny >= height:
                continue
            index = ny * width + nx
            if not background[index] and is_neutral_matte(pixels[nx, ny]):
                background[index] = 1
                queue.append((nx, ny))

    matte = Image.frombytes("L", (width, height), bytes(255 if value else 0 for value in background))
    # A very small feather removes the baked preview fringe without softening
    # the authored line work at combat scale.
    matte = matte.filter(ImageFilter.GaussianBlur(0.55))
    alpha = Image.eval(matte, lambda value: 255 - value)
    rgba = rgb.convert("RGBA")
    rgba.putalpha(alpha)
    destination.parent.mkdir(parents=True, exist_ok=True)
    rgba.save(destination, optimize=True)

    alpha_extrema = rgba.getchannel("A").getextrema()
    bbox = rgba.getchannel("A").getbbox()
    if alpha_extrema != (0, 255) or bbox is None:
        raise RuntimeError(f"alpha extraction failed: extrema={alpha_extrema}, bbox={bbox}")
    print(f"RGBA_EXTRACTED={destination}|size={width}x{height}|bbox={bbox}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    extract(args.source, args.destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
