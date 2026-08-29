#!/usr/bin/env python3
"""Normalize only edge-connected green matte to exact #00FF00.

This is deliberately not a generic alpha repair.  It preserves the newly
generated character pixels and replaces only the continuous chroma field that
reaches the canvas edge.  That gives source art a deterministic #00FF00 field
before standard runtime RGBA keying, while preventing pale backing remnants
from being promoted.
"""
from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image


KEY = (0, 255, 0)


def is_chroma_field(pixel: tuple[int, int, int]) -> bool:
    red, green, blue = pixel
    # The ChatGPT-generation PNG retains a green antialias/compression range
    # around the requested #00FF00, but costume teal always carries material
    # blue or nontrivial red and does not match this high-dominance matte test.
    return green >= 170 and green - red >= 80 and green - blue >= 80


def normalize(source: Path, destination: Path) -> None:
    image = Image.open(source).convert("RGB")
    width, height = image.size
    pixels = image.load()
    pending: deque[tuple[int, int]] = deque()
    seen = bytearray(width * height)
    for x in range(width):
        pending.append((x, 0)); pending.append((x, height - 1))
    for y in range(1, height - 1):
        pending.append((0, y)); pending.append((width - 1, y))
    field_pixels = 0
    while pending:
        x, y = pending.popleft()
        offset = y * width + x
        if seen[offset]:
            continue
        seen[offset] = 1
        if not is_chroma_field(pixels[x, y]):
            continue
        pixels[x, y] = KEY
        field_pixels += 1
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < width and 0 <= ny < height and not seen[ny * width + nx]:
                pending.append((nx, ny))
    corners = (pixels[0, 0], pixels[width - 1, 0], pixels[0, height - 1], pixels[width - 1, height - 1])
    if any(pixel != KEY for pixel in corners):
        raise RuntimeError(f"matte did not reach every corner: {corners}")
    if field_pixels < width * height // 3:
        raise RuntimeError(f"unexpectedly small edge-connected green field: {field_pixels}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, optimize=True)
    print(f"EXACT_GREEN_MATTE={destination}|size={width}x{height}|fieldPixels={field_pixels}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    normalize(args.source, args.destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
