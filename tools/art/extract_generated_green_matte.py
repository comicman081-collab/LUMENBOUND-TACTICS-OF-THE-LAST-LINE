#!/usr/bin/env python3
"""Key the project's exact #00FF00 generation matte to transparent RGBA."""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageFilter


def is_key_green(pixel: tuple[int, int, int]) -> bool:
    red, green, blue = pixel
    # The authoring matte is exact #00FF00. A strict hue/dominance window also
    # catches its antialiased fringe without erasing lime hair, teal VFX, or
    # shaded green costume materials whose red/blue channels are substantial.
    return green >= 178 and red <= 104 and blue <= 104 and green - red >= 92 and green - blue >= 92


def extract(source: Path, destination: Path) -> None:
    rgb = Image.open(source).convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    # Key across the full canvas rather than flood-filling from its boundary.
    # Hair loops, shield handles and circular VFX often enclose isolated matte
    # islands that a boundary-only fill incorrectly leaves bright green.
    background = bytearray(
        1 if is_key_green(pixels[x, y]) else 0
        for y in range(height)
        for x in range(width)
    )

    matte = Image.frombytes("L", (width, height), bytes(255 if value else 0 for value in background))
    matte = matte.filter(ImageFilter.GaussianBlur(0.6))
    alpha = Image.eval(matte, lambda value: 255 - value)
    rgba = rgb.convert("RGBA")
    output = rgba.load()
    alpha_pixels = alpha.load()
    # Suppress chroma spill only along semi-transparent keyed edges. Fully
    # opaque intentional green costume and VFX regions are never recoloured.
    for y in range(height):
        for x in range(width):
            edge_alpha = alpha_pixels[x, y]
            if 0 < edge_alpha < 250:
                red, green, blue, _ = output[x, y]
                output[x, y] = (red, min(green, max(red, blue) + 24), blue, edge_alpha)
            else:
                red, green, blue, _ = output[x, y]
                output[x, y] = (red, green, blue, edge_alpha)
    destination.parent.mkdir(parents=True, exist_ok=True)
    rgba.save(destination, optimize=True)

    extrema = rgba.getchannel("A").getextrema()
    bbox = rgba.getchannel("A").getbbox()
    if extrema != (0, 255) or bbox is None:
        raise RuntimeError(f"green key failed: extrema={extrema}, bbox={bbox}")
    print(f"GREEN_KEY_RGBA={destination}|size={width}x{height}|bbox={bbox}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    extract(args.source, args.destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
