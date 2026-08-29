#!/usr/bin/env python3
"""Create Maeru's versioned R3 standing source with the false white hair matte removed.

CHR001's legacy authority has true alpha at the outer canvas but contains several
opaque, pale-neutral islands *behind* her teal ponytail.  Those islands
are neither costume panels nor highlight strokes: they sit in the upper-left
hair negative space and read as an unkeyed white background in story/title
layouts.  This narrowly scoped repair preserves the face, costume, shield,
weapon, palette and silhouette while making only those residual islands
transparent.  It also records the mandated #00FF00 intermediate source.
"""

from __future__ import annotations

import hashlib
import json
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "godot" / "assets" / "art" / "characters" / "CHR001" / "portrait_1024x1536.png"
OUTPUT_ROOT = ROOT / "data_source" / "art_source" / "standing_green_matte_r3"
RGBA_OUTPUT = OUTPUT_ROOT / "chr001_standing_r3_rgba.png"
GREEN_OUTPUT = OUTPUT_ROOT / "chr001_standing_r3_green_matte.png"
REPORT_OUTPUT = OUTPUT_ROOT / "qa" / "CHR001_R3_WHITE_MATTE_REPAIR.json"

# This is intentionally a geometry-bounded repair, not a global "delete white"
# filter.  Maeru's white armour, skirt panels and lantern remain untouched.
ROI_X = (0.04, 0.50)
ROI_Y = (0.06, 0.46)
MIN_COMPONENT_PIXELS = 20


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _is_residual_white(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    return (
        # The residual matte is light gray as well as pure white after
        # antialiasing.  The ROI sits strictly in the left ponytail's negative
        # space, so this catches the pale islands without touching the white
        # costume, lantern, shield, face or the cyan hair rendering.
        alpha >= 180
        and red >= 130
        and green >= 130
        and blue >= 125
        and max(red, green, blue) - min(red, green, blue) <= 75
    )


def _components(image: Image.Image) -> list[list[tuple[int, int]]]:
    width, height = image.size
    pixels = image.load()
    left, right = int(width * ROI_X[0]), int(width * ROI_X[1])
    top, bottom = int(height * ROI_Y[0]), int(height * ROI_Y[1])
    candidates = {
        (x, y)
        for y in range(top, bottom)
        for x in range(left, right)
        if _is_residual_white(pixels[x, y])
    }
    seen: set[tuple[int, int]] = set()
    output: list[list[tuple[int, int]]] = []
    for seed in candidates:
        if seed in seen:
            continue
        pending: deque[tuple[int, int]] = deque([seed])
        seen.add(seed)
        component: list[tuple[int, int]] = []
        while pending:
            x, y = pending.popleft()
            component.append((x, y))
            for neighbor in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if neighbor in candidates and neighbor not in seen:
                    seen.add(neighbor)
                    pending.append(neighbor)
        if len(component) >= MIN_COMPONENT_PIXELS:
            output.append(component)
    return output


def _bounds(component: list[tuple[int, int]]) -> list[int]:
    xs = [point[0] for point in component]
    ys = [point[1] for point in component]
    return [min(xs), min(ys), max(xs) + 1, max(ys) + 1]


def _clean(image: Image.Image) -> tuple[Image.Image, list[dict[str, object]]]:
    rgba = image.convert("RGBA")
    components = _components(rgba)
    erase = Image.new("L", rgba.size, 0)
    erase_pixels = erase.load()
    records: list[dict[str, object]] = []
    for component in components:
        for x, y in component:
            erase_pixels[x, y] = 255
        records.append({"pixels": len(component), "bounds": _bounds(component)})
    # Feather only the removed islands' contour.  Existing opaque costume and
    # hair pixels retain their original alpha, while the repaired negative space
    # blends cleanly across both light and dark scene backdrops.
    erase = erase.filter(ImageFilter.GaussianBlur(0.55))
    output = rgba.copy()
    output_pixels = output.load()
    for y in range(output.height):
        for x in range(output.width):
            red, green, blue, alpha = output_pixels[x, y]
            repaired_alpha = min(alpha, 255 - erase.getpixel((x, y)))
            output_pixels[x, y] = (red, green, blue, repaired_alpha)
    if output.getchannel("A").getextrema() != (0, 255):
        raise RuntimeError("R3 repair must retain true RGBA extrema")
    return output, records


def main() -> int:
    if not SOURCE.is_file():
        raise FileNotFoundError(SOURCE)
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    REPORT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    cleaned, components = _clean(Image.open(SOURCE))
    cleaned.save(RGBA_OUTPUT, optimize=True)
    green = Image.new("RGBA", cleaned.size, (0, 255, 0, 255))
    green.alpha_composite(cleaned)
    green.convert("RGB").save(GREEN_OUTPUT, optimize=True)
    report = {
        "status": "COSTUME_CONTINUITY_PASS_PENDING_VISUAL_R3",
        "characterId": "CHR001",
        "repair": "UPPER_LEFT_HAIR_NEGATIVE_SPACE_WHITE_MATTE_ONLY",
        "source": str(SOURCE.relative_to(ROOT)).replace("\\", "/"),
        "sourceSha256": _sha256(SOURCE),
        "generationMatte": "#00FF00",
        "runtimeBackground": "RGBA_TRANSPARENT",
        "removedComponents": components,
        "removedPixels": sum(int(component["pixels"]) for component in components),
        "rgba": str(RGBA_OUTPUT.relative_to(ROOT)).replace("\\", "/"),
        "rgbaSha256": _sha256(RGBA_OUTPUT),
        "greenMatte": str(GREEN_OUTPUT.relative_to(ROOT)).replace("\\", "/"),
        "greenMatteSha256": _sha256(GREEN_OUTPUT),
        "alphaExtrema": list(cleaned.getchannel("A").getextrema()),
        "alphaBbox": list(cleaned.getchannel("A").getbbox() or ()),
    }
    REPORT_OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
