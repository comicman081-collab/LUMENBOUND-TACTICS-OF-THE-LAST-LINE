#!/usr/bin/env python3
"""Build light/dark alpha QA evidence for one 8-head card candidate."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    image = Image.open(args.source).convert("RGBA")
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    extrema = alpha.getextrema()
    if bbox is None:
        raise RuntimeError("candidate has no visible subject")
    insets = [bbox[0], bbox[1], image.width - bbox[2], image.height - bbox[3]]
    visible_green = 0
    for red, green, blue, opacity in image.getdata():
        if opacity >= 32 and green >= 178 and red <= 104 and blue <= 104 and green - red >= 92 and green - blue >= 92:
            visible_green += 1
    label_height = 58
    sheet = Image.new("RGB", (image.width * 2, image.height + label_height), (16, 20, 28))
    left = Image.new("RGBA", image.size, (238, 241, 246, 255))
    right = Image.new("RGBA", image.size, (20, 24, 34, 255))
    left.alpha_composite(image)
    right.alpha_composite(image)
    sheet.paste(left.convert("RGB"), (0, label_height))
    sheet.paste(right.convert("RGB"), (image.width, label_height))
    draw = ImageDraw.Draw(sheet)
    draw.text((18, 18), f"LIGHT QA | alpha={extrema} inset={insets}", fill=(238, 241, 246))
    draw.text((image.width + 18, 18), f"DARK QA | visible-key-green={visible_green}", fill=(238, 241, 246))
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.destination, optimize=True)
    print(json.dumps({"alphaExtrema": list(extrema), "alphaBbox": list(bbox), "safeInsets": insets, "visibleKeyGreenPixels": visible_green, "qaSheet": str(args.destination)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
