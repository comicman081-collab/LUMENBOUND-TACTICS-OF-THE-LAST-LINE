#!/usr/bin/env python3
"""Reframe an approved RGBA subject onto an exact-green safe-margin canvas."""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


GREEN = (0, 255, 0, 255)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_rgba", type=Path)
    parser.add_argument("destination_green", type=Path)
    parser.add_argument("--inset", type=int, default=72)
    args = parser.parse_args()
    source = Image.open(args.source_rgba).convert("RGBA")
    bbox = source.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError("source has no visible subject")
    subject = source.crop(bbox)
    subject.thumbnail((source.width - args.inset * 2, source.height - args.inset * 2), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", source.size, GREEN)
    canvas.alpha_composite(subject, ((source.width - subject.width) // 2, (source.height - subject.height) // 2))
    args.destination_green.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(args.destination_green, optimize=True)
    print(f"CARD_GREEN_SAFE_FRAME={args.destination_green}|subject={subject.size}|canvas={source.size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
