#!/usr/bin/env python3
"""Validate alpha and chroma-key cleanup for SD-unified runtime sources."""
from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2] / "data_source/art_source/combat_hd_sources/renewed"
FILES = [
    "chr006_costume_authority_sd_r1_rgba.png",
    "chr007_costume_authority_sd_r1_rgba.png",
    "chr008_costume_authority_sd_r1_rgba.png",
    "chr016_costume_c_sd_r1_greenkey_authority.png",
    "chr017_costume_c_sd_r1_greenkey_authority.png",
    "chr018_costume_d_sd_r1_greenkey_authority.png",
    "chr019_costume_c_sd_r1_rgba_authority.png",
    "chr020_costume_c_sd_r1_rgba_authority.png",
    "chr021_costume_c_sd_r1_rgba_authority.png",
    "chr022_costume_c_sd_r1_rgba_authority.png",
    "chr023_costume_c_sd_r1_rgba_authority.png",
    "chr024_costume_c_sd_r1_rgba_authority.png",
    "chr025_costume_c_sd_r1_rgba_authority.png",
    "chr027_costume_d_sd_r1_rgba_authority.png",
    "chr033_costume_c_sd_r1_rgba_authority.png",
    "chr039_costume_c_sd_r1_rgba_authority.png",
    "chr040_costume_d_sd_r1_rgba_authority.png",
    "chr041_costume_c_sd_r1_rgba_authority.png",
]


def is_key_green(red: int, green: int, blue: int) -> bool:
    return green >= 178 and red <= 104 and blue <= 104 and green - red >= 92 and green - blue >= 92


def main() -> int:
    errors: list[str] = []
    for filename in FILES:
        path = ROOT / filename
        if not path.is_file():
            errors.append(f"MISSING:{filename}")
            continue
        image = Image.open(path).convert("RGBA")
        extrema = image.getchannel("A").getextrema()
        visible_key_green = sum(
            1 for red, green, blue, alpha in image.get_flattened_data()
            if alpha > 16 and is_key_green(red, green, blue)
        )
        print(f"SD_RGBA_QA={filename}|alpha={extrema}|visible_key_green={visible_key_green}")
        if extrema != (0, 255):
            errors.append(f"ALPHA:{filename}:{extrema}")
        if visible_key_green:
            errors.append(f"GREEN_SPILL:{filename}:{visible_key_green}")
    if errors:
        print("SD_RGBA_QA_FAIL=" + ";".join(errors))
        return 1
    print(f"SD_RGBA_QA_PASS={len(FILES)}/{len(FILES)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
