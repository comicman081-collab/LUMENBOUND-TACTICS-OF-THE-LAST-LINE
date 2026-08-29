#!/usr/bin/env python3
"""Repair only Maeru's baked white hair-negative-space matte.

The R3 threshold pass was intentionally rejected: it reached into white armour
panels.  R4 uses four reviewed, hair-only regions in the original 1024×1536
authority.  Each region is flood-keyed from pale-neutral background pixels;
the face, armour, skirt, lantern and shield are outside every region.
"""

from __future__ import annotations

import hashlib
import json
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "godot" / "assets" / "art" / "characters" / "CHR001" / "portrait_1024x1536.png"
OUTPUT_ROOT = ROOT / "data_source" / "art_source" / "standing_green_matte_r4"
RGBA_OUTPUT = OUTPUT_ROOT / "chr001_standing_r4_rgba.png"
GREEN_OUTPUT = OUTPUT_ROOT / "chr001_standing_r4_green_matte.png"
REPORT_OUTPUT = OUTPUT_ROOT / "qa" / "CHR001_R4_HAIR_MATTE_REPAIR.json"

# (seed, bounding rectangle) values are specific to Maeru's ponytail and are
# stored so a reviewer can reproduce precisely what was removed.
HAIR_NEGATIVE_SPACES = (
    ((370, 220), (300, 180, 425, 305)),
    ((250, 360), (210, 305, 350, 420)),
    ((180, 500), (135, 370, 245, 555)),
    ((215, 535), (180, 500, 250, 600)),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def candidate(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    return alpha >= 150 and min(red, green, blue) >= 90 and max(red, green, blue) - min(red, green, blue) <= 88


def flood(image: Image.Image, seed: tuple[int, int], bounds: tuple[int, int, int, int]) -> list[tuple[int, int]]:
    pixels = image.load()
    if not candidate(pixels[seed[0], seed[1]]):
        raise ValueError(f"hair matte seed is not a pale background pixel: {seed}={pixels[seed[0], seed[1]]}")
    left, top, right, bottom = bounds
    queue: deque[tuple[int, int]] = deque([seed])
    seen: set[tuple[int, int]] = {seed}
    result: list[tuple[int, int]] = []
    while queue:
        x, y = queue.popleft()
        if not (left <= x < right and top <= y < bottom) or not candidate(pixels[x, y]):
            continue
        result.append((x, y))
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if left <= nx < right and top <= ny < bottom and (nx, ny) not in seen:
                seen.add((nx, ny))
                queue.append((nx, ny))
    return result


def main() -> int:
    source = Image.open(SOURCE).convert("RGBA")
    erase = Image.new("L", source.size, 0)
    records: list[dict] = []
    for seed, bounds in HAIR_NEGATIVE_SPACES:
        points = flood(source, seed, bounds)
        for x, y in points:
            erase.putpixel((x, y), 255)
        records.append({"seed": list(seed), "bounds": list(bounds), "pixels": len(points)})
    erase = erase.filter(ImageFilter.GaussianBlur(0.45))
    result = source.copy()
    alpha = result.getchannel("A")
    alpha_data = alpha.load()
    erase_data = erase.load()
    for y in range(result.height):
        for x in range(result.width):
            alpha_data[x, y] = min(alpha_data[x, y], 255 - erase_data[x, y])
    result.putalpha(alpha)
    if result.getchannel("A").getextrema() != (0, 255):
        raise RuntimeError("R4 result must retain true transparent RGBA")
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    REPORT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    result.save(RGBA_OUTPUT, optimize=True)
    green = Image.new("RGBA", result.size, (0, 255, 0, 255))
    green.alpha_composite(result)
    green.convert("RGB").save(GREEN_OUTPUT, optimize=True)
    payload = {
        "schemaVersion": 4,
        "characterId": "CHR001",
        "status": "CANDIDATE_PENDING_VISUAL_QA",
        "repair": "REVIEWED_HAIR_NEGATIVE_SPACE_ONLY",
        "source": SOURCE.relative_to(ROOT).as_posix(),
        "sourceSha256": sha256(SOURCE),
        "generationMatte": "#00FF00",
        "runtimeBackground": "RGBA_TRANSPARENT",
        "removedRegions": records,
        "removedPixels": sum(row["pixels"] for row in records),
        "rgba": RGBA_OUTPUT.relative_to(ROOT).as_posix(),
        "rgbaSha256": sha256(RGBA_OUTPUT),
        "greenMatte": GREEN_OUTPUT.relative_to(ROOT).as_posix(),
        "greenMatteSha256": sha256(GREEN_OUTPUT),
    }
    REPORT_OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
