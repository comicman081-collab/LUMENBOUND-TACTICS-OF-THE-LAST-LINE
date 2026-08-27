#!/usr/bin/env python3
"""Composite a transparent source over the project's flat #00FF00 matte."""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    source = Image.open(args.source).convert("RGBA")
    matte = Image.new("RGBA", source.size, (0, 255, 0, 255))
    matte.alpha_composite(source)
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    matte.convert("RGB").save(args.destination, optimize=True)
    print(f"GREEN_MATTE={args.destination}|size={source.width}x{source.height}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
