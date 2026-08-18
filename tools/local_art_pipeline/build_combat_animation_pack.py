#!/usr/bin/env python3
"""Build a 512px cutout-rig battle animation pack from an approved character.

The feet remain locked to the shared anchor while the upper body, weapon, and
whole-body silhouette receive role-specific anticipation, recoil, lunge, hit,
and recovery motion.  This is a real runtime animation asset, while still being
labelled DEV until an artist performs final frame-by-frame cleanup.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
FRAME_SIZE = 512
FOOT_ANCHOR = (0.50, 0.88)
FOOT_PIXEL = (256, round(FRAME_SIZE * FOOT_ANCHOR[1]))
ANIMATIONS = {
    "idle": {"fps": 12, "loop": True, "frames": 8, "event": {}},
    "move": {"fps": 12, "loop": True, "frames": 12, "event": {}},
    "basic_attack": {"fps": 12, "loop": False, "frames": 8, "event": {4: ["DAMAGE_FRAME"]}},
    "normal_skill": {"fps": 12, "loop": False, "frames": 12, "event": {7: ["VFX_FRAME", "DAMAGE_FRAME"]}},
    "ultimate": {"fps": 12, "loop": False, "frames": 18, "event": {5: ["VFX_FRAME"], 11: ["DAMAGE_FRAME", "SFX_FRAME"]}},
    "hit": {"fps": 12, "loop": False, "frames": 4, "event": {}},
    "down": {"fps": 12, "loop": False, "frames": 8, "event": {}},
    "victory": {"fps": 12, "loop": False, "frames": 10, "event": {9: ["ANIMATION_END"]}},
}


def cli() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "work" / "art_gen" / "combat_animation_pack")
    parser.add_argument("--asset-id", default="sd_chr001_maeru_combat_r21_dev")
    parser.add_argument("--character-id", default="CHR001")
    parser.add_argument("--role", default="GUARDIAN", choices=("GUARDIAN", "VANGUARD", "ASSAULT", "ARTILLERY", "SPECIALIST", "MEDIC", "MELEE_RUSH", "RANGED"))
    parser.add_argument("--team", default="PLAYER", choices=("PLAYER", "ENEMY"))
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def transparent_subject(source: Image.Image) -> Image.Image:
    if source.mode == "RGBA" and source.getchannel("A").getextrema()[0] < 255:
        return source.copy()
    rgb = np.asarray(source.convert("RGB"), dtype=np.int16)
    spread = rgb.max(axis=2) - rgb.min(axis=2)
    brightness = rgb.mean(axis=2)
    # Image generation may return a baked light checkerboard rather than real
    # alpha. Only neutral, bright pixels connected to the canvas edge are
    # removed, so enclosed white costume panels remain intact.
    candidate = ((spread < 22) & (brightness > 218)) | (brightness < 24)
    height, width = candidate.shape
    background = np.zeros((height, width), dtype=np.uint8)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        if candidate[0, x]: queue.append((0, x))
        if candidate[height - 1, x]: queue.append((height - 1, x))
    for y in range(height):
        if candidate[y, 0]: queue.append((y, 0))
        if candidate[y, width - 1]: queue.append((y, width - 1))
    while queue:
        y, x = queue.popleft()
        if background[y, x] or not candidate[y, x]:
            continue
        background[y, x] = 255
        if y > 0: queue.append((y - 1, x))
        if y + 1 < height: queue.append((y + 1, x))
        if x > 0: queue.append((y, x - 1))
        if x + 1 < width: queue.append((y, x + 1))
    alpha = Image.fromarray(255 - background, mode="L").filter(ImageFilter.GaussianBlur(0.75))
    rgba = source.convert("RGBA")
    rgba.putalpha(alpha)
    return rgba


def normalize_canvas(subject: Image.Image) -> Image.Image:
    alpha = subject.getchannel("A")
    bbox = alpha.point(lambda p: 255 if p > 18 else 0).getbbox()
    if bbox is None:
        raise SystemExit("ALPHA_EXTRACTION_FAILED")
    cropped = subject.crop(bbox)
    # Leave room for a muzzle flash and the head-anchored HP bar.
    max_width, max_height = 430, 418
    scale = min(max_width / cropped.width, max_height / cropped.height)
    resized = cropped.resize((max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    x = FOOT_PIXEL[0] - resized.width // 2
    y = FOOT_PIXEL[1] - resized.height
    canvas.alpha_composite(resized, (x, y))
    return canvas


def transform(base: Image.Image, angle: float = 0.0, tx: int = 0, ty: int = 0, sx: float = 1.0, sy: float = 1.0) -> Image.Image:
    width, height = max(1, round(FRAME_SIZE * sx)), max(1, round(FRAME_SIZE * sy))
    scaled = base.resize((width, height), Image.Resampling.BICUBIC)
    anchor = (round(FOOT_PIXEL[0] * sx), round(FOOT_PIXEL[1] * sy))
    rotated = scaled.rotate(angle, resample=Image.Resampling.BICUBIC, center=anchor, expand=False)
    canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    paste_x = FOOT_PIXEL[0] - anchor[0] + tx
    paste_y = FOOT_PIXEL[1] - anchor[1] + ty
    canvas.alpha_composite(rotated, (paste_x, paste_y))
    return canvas


def upper_body_motion(base: Image.Image, angle: float, tx: int, ty: int) -> Image.Image:
    """Move the upper body/weapon around the hips while the legs stay planted."""
    if abs(angle) < 0.001 and tx == 0 and ty == 0:
        return base
    alpha = np.asarray(base.getchannel("A"), dtype=np.float32)
    rows = np.arange(FRAME_SIZE, dtype=np.float32)[:, None]
    upper_weight = np.clip((340.0 - rows) / 48.0, 0.0, 1.0)
    upper_alpha = Image.fromarray(np.uint8(alpha * upper_weight), mode="L")
    lower_alpha = Image.fromarray(np.uint8(alpha * (1.0 - upper_weight)), mode="L")
    upper = base.copy(); upper.putalpha(upper_alpha)
    lower = base.copy(); lower.putalpha(lower_alpha)
    moved = upper.rotate(angle, resample=Image.Resampling.BICUBIC, center=(256, 324), expand=False)
    shifted = Image.new("RGBA", base.size, (0, 0, 0, 0))
    shifted.alpha_composite(moved, (tx, ty))
    lower.alpha_composite(shifted)
    return lower


def add_muzzle_flash(frame: Image.Image, base: Image.Image, strength: float, team: str) -> Image.Image:
    if strength <= 0.0:
        return frame
    bbox = base.getchannel("A").point(lambda p: 255 if p > 24 else 0).getbbox()
    if bbox is None:
        return frame
    alpha = np.asarray(base.getchannel("A"))
    if team == "PLAYER":
        edge_band = alpha[:, max(0, bbox[2] - 12):bbox[2]]
    else:
        edge_band = alpha[:, bbox[0]:min(FRAME_SIZE, bbox[0] + 12)]
    ys = np.where(edge_band > 32)[0]
    muzzle_y = int(np.median(ys)) if ys.size else (bbox[1] + bbox[3]) // 2
    muzzle_x = min(496, bbox[2] + 5) if team == "PLAYER" else max(16, bbox[0] - 5)
    glow = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    radius = round(16 + 13 * strength)
    draw.ellipse((muzzle_x - radius, muzzle_y - radius, muzzle_x + radius, muzzle_y + radius), fill=(255, 205, 88, round(105 * strength)))
    direction = 1 if team == "PLAYER" else -1
    draw.polygon([
        (muzzle_x - 5 * direction, muzzle_y),
        (max(0, min(511, muzzle_x + 34 * direction)), muzzle_y - 12),
        (max(0, min(511, muzzle_x + 23 * direction)), muzzle_y),
        (max(0, min(511, muzzle_x + 34 * direction)), muzzle_y + 12),
    ], fill=(255, 246, 174, round(245 * strength)))
    glow = glow.filter(ImageFilter.GaussianBlur(1.2))
    result = frame.copy(); result.alpha_composite(glow)
    return result


def motion(animation: str, index: int, count: int, role: str, team: str) -> dict:
    t = index / max(1, count - 1)
    wave = np.sin(t * np.pi * 2.0)
    direction = 1 if team == "PLAYER" else -1
    if animation == "idle":
        return {"ty": round(-2 - 2 * wave), "sx": 1.0 + 0.006 * wave, "sy": 1.0 - 0.004 * wave}
    if animation == "move":
        step = np.sin(t * np.pi * 4.0)
        return {"angle": direction * (-3.5 + 1.8 * step), "tx": round(direction * 5 * step), "ty": round(-7 * abs(step)), "sx": 1.015, "sy": 0.985, "upper_angle": direction * -1.5 * step}
    if animation == "basic_attack":
        if role in ("VANGUARD", "MELEE_RUSH"):
            lunge = [0, -8, -15, -7, 30, 21, 9, 0][index]
            return {"angle": direction * [-2, -6, -10, -5, 10, 7, 3, 0][index], "tx": direction * lunge, "ty": -abs(lunge) // 6, "upper_angle": direction * [0, -3, -5, -2, 5, 3, 1, 0][index]}
        if role == "GUARDIAN":
            lunge = [0, -5, -10, -4, 22, 14, 6, 0][index]
            return {"angle": direction * [-1, -3, -5, -2, 6, 4, 2, 0][index], "tx": direction * lunge, "ty": -abs(lunge) // 6, "upper_angle": direction * [-1, -2, -3, 0, 3, 2, 1, 0][index]}
        recoil = [0, 0, 2, 1, -10, -6, -2, 0][index]
        return {"angle": direction * [0, -1, -2, -1, 3, 2, 1, 0][index], "tx": round(direction * recoil * .35), "upper_tx": direction * recoil, "upper_angle": direction * [0, 0, -1, 0, -5, -3, -1, 0][index], "flash": 1.0 if index == 4 else (0.35 if index == 5 else 0.0)}
    if animation == "normal_skill":
        pulse = np.sin(t * np.pi)
        return {"angle": direction * (-4 + 8 * t), "tx": round(direction * 11 * pulse), "ty": round(-12 * pulse), "sx": 1.0 + 0.045 * pulse, "sy": 1.0 + 0.035 * pulse, "upper_angle": direction * (-5 + 10 * t), "flash": 1.0 if role not in ("GUARDIAN", "VANGUARD", "MELEE_RUSH") and index == 7 else 0.0}
    if animation == "ultimate":
        anticipation = -min(index, 5) * 2 if index <= 5 else min(24, (index - 5) * 4)
        if index > 11: anticipation = max(0, 24 - (index - 11) * 4)
        pulse = np.sin(t * np.pi)
        return {"angle": direction * (-6 + 13 * t), "tx": direction * anticipation, "ty": round(-16 * pulse), "sx": 1.0 + 0.065 * pulse, "sy": 1.0 + 0.035 * pulse, "upper_angle": direction * (-7 + 14 * t), "flash": 1.0 if role not in ("GUARDIAN", "VANGUARD", "MELEE_RUSH") and index == 11 else 0.0}
    if animation == "hit":
        return {"angle": direction * [0, -8, 5, 0][index], "tx": direction * [0, -14, -7, 0][index], "ty": [0, 2, 1, 0][index]}
    if animation == "down":
        return {"angle": direction * 68 * t, "tx": round(direction * 38 * t), "ty": round(20 * t), "sx": 1.0 - 0.13 * t, "sy": 1.0 - 0.13 * t}
    if animation == "victory":
        pulse = np.sin(t * np.pi * 2.0)
        return {"angle": direction * 4 * pulse, "tx": round(direction * 3 * pulse), "ty": round(-8 * abs(pulse)), "sx": 1.0 + 0.025 * abs(pulse), "sy": 1.0 + 0.025 * abs(pulse)}
    return {}


def render_frame(base: Image.Image, animation: str, index: int, count: int, role: str, team: str) -> Image.Image:
    spec = motion(animation, index, count, role, team)
    upper = upper_body_motion(base, float(spec.pop("upper_angle", 0.0)), int(spec.pop("upper_tx", 0)), int(spec.pop("upper_ty", 0)))
    flash = float(spec.pop("flash", 0.0))
    rendered = transform(upper, **spec)
    if role in ("ASSAULT", "ARTILLERY", "SPECIALIST", "MEDIC", "RANGED"):
        rendered = add_muzzle_flash(rendered, upper, flash, team)
    return rendered


def pack_sheets(frames: list[Path], output_dir: Path, animation: str) -> list[dict]:
    sheets = []
    for part, start in enumerate(range(0, len(frames), 16)):
        subset = frames[start:start + 16]
        sheet = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0))
        cells = []
        for local_index, path in enumerate(subset):
            frame = Image.open(path).convert("RGBA")
            col, row = local_index % 4, local_index // 4
            sheet.alpha_composite(frame, (col * FRAME_SIZE, row * FRAME_SIZE))
            cells.append({"frame": start + local_index, "region": [col * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE]})
        path = output_dir / f"{animation}_sheet_{part + 1:02d}.png"
        sheet.save(path, format="PNG", optimize=True)
        sheets.append({"path": path.name, "size": [2048, 2048], "cells": cells})
    return sheets


def main() -> int:
    cfg = cli()
    source = cfg.source.resolve()
    output = cfg.output.resolve()
    if not source.is_file():
        raise SystemExit(f"SOURCE_MISSING: {source}")
    if ROOT.resolve() not in output.parents:
        raise SystemExit("OUTPUT_BLOCKED: project output required")
    if cfg.validate_only:
        total = sum(int(row["frames"]) for row in ANIMATIONS.values())
        if total != 80:
            raise SystemExit(f"FRAME_CONTRACT_INVALID: {total}")
        print("COMBAT_ANIMATION_PACK_VALIDATION_OK")
        return 0
    output.mkdir(parents=True, exist_ok=True)
    source_image = Image.open(source)
    normalized = normalize_canvas(transparent_subject(source_image))
    normalized_path = output / "combat_base_512.png"
    normalized.save(normalized_path, format="PNG", optimize=True)
    metadata = {}
    total_frames = 0
    for animation, spec in ANIMATIONS.items():
        animation_dir = output / animation
        animation_dir.mkdir(parents=True, exist_ok=True)
        frame_paths = []
        events = []
        count = int(spec["frames"])
        for index in range(count):
            frame = render_frame(normalized, animation, index, count, cfg.role, cfg.team)
            frame_path = animation_dir / f"{animation}_{index:03d}.png"
            frame.save(frame_path, format="PNG", optimize=True)
            frame_paths.append(frame_path)
            for event_name in spec["event"].get(index, []):
                events.append({"frame": index, "event": event_name})
        metadata[animation] = {
            "fps": int(spec["fps"]), "loop": bool(spec["loop"]), "frames": count,
            "frame_paths": [path.relative_to(output).as_posix() for path in frame_paths],
            "sheets": pack_sheets(frame_paths, output, animation), "events": events,
        }
        total_frames += count
    manifest = {
        "schema_version": 1,
        "asset_id": cfg.asset_id,
        "character_id": cfg.character_id,
        "role": cfg.role,
        "team": cfg.team,
        "status": "DEV_CUTOUT_RIG_ANIMATION",
        "production_approved": False,
        "source": source.relative_to(ROOT).as_posix(),
        "source_sha256": sha256(source),
        "frame_size": [FRAME_SIZE, FRAME_SIZE],
        "foot_anchor": list(FOOT_ANCHOR),
        "head_anchor": [0.5, max(0.02, normalized.getchannel("A").getbbox()[1] / FRAME_SIZE)],
        "default_fps": 12,
        "view": "THREE_QUARTER_RIGHT_DOWN_30" if cfg.team == "PLAYER" else "THREE_QUARTER_LEFT_DOWN_30",
        "team_usage": "PLAYER_LEFT_SIDE_FACING_RIGHT" if cfg.team == "PLAYER" else "ENEMY_RIGHT_SIDE_FACING_LEFT",
        "facing_policy": "SEPARATE_LEFT_RIGHT",
        "runtime_dependencies": [],
        "total_frames": total_frames,
        "animations": metadata,
        "created_utc": datetime.now(timezone.utc).isoformat(),
    }
    manifest_path = output / "animation_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "manifest": str(manifest_path), "total_frames": total_frames}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
