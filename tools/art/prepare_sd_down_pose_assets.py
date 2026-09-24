#!/usr/bin/env python3
"""Key green-screen SD defeat masters into fixed logical combat canvases.

The green masters are kept untouched under work/down_pose_sd_20260911/masters.
This script only writes the keyed runtime derivatives and provenance manifests.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image


CANVAS = 512
MAX_WIDTH = 492
MAX_HEIGHT = 360
BOTTOM_Y = 450


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def key_green(source: Image.Image) -> Image.Image:
    """Return an RGBA image with the uniform green screen keyed out."""

    rgba = source.convert("RGBA")
    values = np.asarray(rgba, dtype=np.int16)
    rgb = values[:, :, :3].astype(np.float32)
    # Generated masters use #00ff00. Distance based feathering preserves a
    # clean anti-aliased outline while avoiding removal of the characters'
    # darker teal/green costume highlights.
    distance = np.sqrt(
        rgb[:, :, 0] ** 2
        + (rgb[:, :, 1] - 255) ** 2
        + rgb[:, :, 2] ** 2
    )
    keyed_alpha = np.clip((distance - 42.0) * (255.0 / 54.0), 0.0, 255.0)
    # Only apply the key to pixels that are actually green-screen coloured.
    # This guard keeps saturated cyan/teal costume pixels opaque.
    green_screen = (
        (rgb[:, :, 1] > 170)
        & ((rgb[:, :, 1] - np.maximum(rgb[:, :, 0], rgb[:, :, 2])) > 62)
        & (rgb[:, :, 0] < 150)
        & (rgb[:, :, 2] < 150)
    )
    alpha = values[:, :, 3].astype(np.float32)
    alpha[green_screen] = np.minimum(alpha[green_screen], keyed_alpha[green_screen])
    result = np.array(rgba, copy=True)
    result[:, :, 3] = np.clip(alpha, 0, 255).astype(np.uint8)
    return Image.fromarray(result, "RGBA")


def normalize_pose(source: Image.Image) -> tuple[Image.Image, dict]:
    keyed = key_green(source)
    alpha = np.asarray(keyed.getchannel("A"), dtype=np.uint8)
    ys, xs = np.where(alpha > 8)
    if len(xs) == 0:
        raise ValueError("green-screen key removed the complete source")
    left, top, right, bottom = int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)
    crop = keyed.crop((left, top, right, bottom))
    width, height = crop.size
    scale = min(MAX_WIDTH / width, MAX_HEIGHT / height)
    target_size = (max(1, round(width * scale)), max(1, round(height * scale)))
    crop = crop.resize(target_size, Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    x = (CANVAS - crop.width) // 2
    y = BOTTOM_Y - crop.height
    canvas.alpha_composite(crop, (x, y))
    final_alpha = np.asarray(canvas.getchannel("A"), dtype=np.uint8)
    final_y, final_x = np.where(final_alpha > 8)
    bounds = [
        int(final_x.min()),
        int(final_y.min()),
        int(final_x.max() + 1),
        int(final_y.max() + 1),
    ]
    metadata = {
        "logical_canvas_size": [CANVAS, CANVAS],
        "alpha_bounds": bounds,
        "placement": {
            "center_x": CANVAS // 2,
            "bottom_y": BOTTOM_Y,
            "max_width": MAX_WIDTH,
            "max_height": MAX_HEIGHT,
        },
        "source_bbox": [left, top, right, bottom],
        "source_size": list(source.size),
        "normalized_size": list(crop.size),
        "state": "down",
        "style": "sd-combat",
        "background_key": "#00ff00",
    }
    return canvas, metadata


def process(root: Path) -> dict:
    masters = root / "masters"
    runtime_root = root.parent.parent / "godot" / "assets" / "runtime_web" / "combat_down_pose"
    runtime_root.mkdir(parents=True, exist_ok=True)
    entries: dict[str, dict] = {}
    for master in sorted(masters.glob("*_down_pose_sd_green.png")):
        character_id = master.name.split("_", 1)[0]
        image = Image.open(master)
        keyed, metadata = normalize_pose(image)
        destination_dir = runtime_root / character_id
        destination_dir.mkdir(parents=True, exist_ok=True)
        destination = destination_dir / "down_pose.png"
        keyed.save(destination, format="PNG", optimize=True)
        metadata.update(
            {
                "asset_id": character_id,
                "source_master": str(master.relative_to(root.parent.parent)).replace("\\", "/"),
                "source_sha256": sha256(master),
                "runtime_asset": f"res://assets/runtime_web/combat_down_pose/{character_id}/down_pose.png",
                "runtime_sha256": sha256(destination),
                "generated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        (destination_dir / "down_pose.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        entries[character_id] = metadata

    manifest = {
        "schema": "lumenbound.sd_down_pose.v1",
        "state": "down",
        "style": "sd-combat",
        "logical_canvas_size": [CANVAS, CANVAS],
        "assets": entries,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
    (runtime_root / "down_pose_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (root / "manifests" / "down_pose_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path("work/down_pose_sd_20260911"),
        help="project-relative down-pose work directory",
    )
    args = parser.parse_args()
    manifest = process(args.root)
    print(json.dumps({"assets": sorted(manifest["assets"]), "count": len(manifest["assets"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
