#!/usr/bin/env python3
"""R24 deterministic shield-position repair for the accepted R23 face turn."""
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "work" / "art_gen" / "sdxl_guardian_combat_direction_r23" / "chr001_guardian_r23v01_face_seed171281.png"
OUTPUT = ROOT / "work" / "art_gen" / "guardian_combat_direction_r24"
SIZE = 768


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def cli() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shift-left", type=int, default=76)
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def main() -> int:
    cfg = cli()
    if not SOURCE.is_file():
        raise SystemExit(f"SOURCE_MISSING: {SOURCE}")
    if not 40 <= cfg.shift_left <= 120:
        raise SystemExit("SHIFT_OUT_OF_RANGE")
    if cfg.validate_only:
        print("R24_DIRECTION_COMPOSITE_VALIDATION_OK")
        return 0
    OUTPUT.mkdir(parents=True, exist_ok=True)
    image = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    array = np.asarray(image, dtype=np.int16)
    spread = array.max(axis=2) - array.min(axis=2)
    brightness = array.mean(axis=2)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    raw = (xx >= 470) & (xx <= 720) & (yy >= 170) & (yy <= 660) & (spread >= 44) & (brightness >= 55)
    shield_mask = Image.fromarray((raw * 255).astype(np.uint8), mode="L").filter(ImageFilter.MaxFilter(13)).filter(ImageFilter.GaussianBlur(2.0))
    if shield_mask.getbbox() is None:
        raise SystemExit("SHIELD_MASK_FAILED")
    rgba = image.convert("RGBA")
    shield = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shield.paste(rgba, (0, 0), shield_mask)
    repaired = image.copy()
    pixels = repaired.load()
    mask_array = np.asarray(shield_mask)
    for y in range(SIZE):
        sample = pixels[736, y]
        for x in range(455, 736):
            if mask_array[y, x] > 8:
                pixels[x, y] = sample
    repaired_rgba = repaired.convert("RGBA")
    repaired_rgba.alpha_composite(shield, (-cfg.shift_left, 0))
    # Clear the thin perspective-guide side bars with nearby neutral background.
    out_pixels = repaired_rgba.load()
    for y in range(SIZE):
        left = out_pixels[76, y]
        right = out_pixels[692, y]
        for x in range(64): out_pixels[x, y] = left
        for x in range(704, SIZE): out_pixels[x, y] = right
    target = OUTPUT / f"chr001_maeru_guardian_combat_right30_r24_shift{cfg.shift_left}.png"
    repaired_rgba.convert("RGB").save(target, format="PNG", optimize=True)
    manifest = {
        "kind": "PROJECT_AUTHORED_COMBAT_DIRECTION_COMPOSITE_R24",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "asset_id": "concept_chr001_guardian_combat_right30_r24",
        "character_id": "CHR001",
        "character_gender": "FEMALE",
        "age_category": "ADULT",
        "attire_policy": "MAXIMUM_NON_EXPLICIT",
        "status": "ART_QA_CANDIDATE",
        "production_approved": False,
        "runtime_asset": False,
        "view": "THREE_QUARTER_RIGHT_DOWN_30",
        "team_usage": "PLAYER_LEFT_SIDE_FACING_RIGHT",
        "facing_policy": "SEPARATE_LEFT_RIGHT",
        "source": SOURCE.relative_to(ROOT).as_posix(),
        "source_sha256": sha(SOURCE),
        "shield_shift_left_px": cfg.shift_left,
        "model_used": False,
        "krea2_used": False,
        "path": target.relative_to(ROOT).as_posix(),
        "bytes": target.stat().st_size,
        "sha256": sha(target),
        "qa_verdict": "UNREVIEWED",
        "integration_allowed": False
    }
    manifest_path = OUTPUT / "combat_direction_r24_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(target), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
