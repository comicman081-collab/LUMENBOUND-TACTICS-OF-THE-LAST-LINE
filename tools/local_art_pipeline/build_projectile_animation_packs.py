#!/usr/bin/env python3
"""Generate original transparent 8-frame combat projectile/VFX packs.

The output is deterministic and deliberately code-rendered so runtime assets
never depend on Python, Pillow, or a network connection.
"""
from __future__ import annotations

import json
import math
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "godot" / "assets" / "generated_import" / "projectiles"
SIZE = 256
SCALE = 3
FPS = 20
FRAMES = 8

PACKS = {
    "CHR001": {"asset_id": "proj_chr001_teal_guard_wave_r28", "kind": "guard_wave", "colors": ((65, 255, 218), (255, 211, 82)), "orientation": "RIGHT", "size": [112, 92], "flight_duration": 0.13},
    "CHR002": {"asset_id": "proj_chr002_coral_blade_arc_r28", "kind": "blade_arc", "colors": ((255, 91, 123), (255, 238, 204)), "orientation": "RIGHT", "size": [126, 116], "flight_duration": 0.08},
    "CHR003": {"asset_id": "proj_chr003_ice_rifle_tracer_r28", "kind": "tracer", "colors": ((106, 228, 255), (177, 132, 255)), "orientation": "RIGHT", "size": [84, 48], "flight_duration": 0.06},
    "CHR004": {"asset_id": "proj_chr004_magenta_energy_bolt_r28", "kind": "energy_bolt", "colors": ((255, 66, 224), (102, 55, 255)), "orientation": "RIGHT", "size": [86, 64], "flight_duration": 0.09},
    "CHR005": {"asset_id": "proj_chr005_emerald_cannon_orb_r28", "kind": "cannon_orb", "colors": ((60, 255, 168), (255, 208, 64)), "orientation": "RIGHT", "size": [116, 108], "flight_duration": 0.12},
    "ENM001": {"asset_id": "proj_enm001_crystal_claw_r28", "kind": "enemy_claw", "colors": ((255, 80, 38), (255, 191, 37)), "orientation": "LEFT", "size": [118, 106], "flight_duration": 0.08},
    "ENM002": {"asset_id": "proj_enm002_arc_mote_r28", "kind": "enemy_bolt", "colors": ((255, 44, 121), (45, 224, 255)), "orientation": "LEFT", "size": [82, 64], "flight_duration": 0.09},
}


def sc(value: float) -> int:
    return round(value * SCALE)


def layer() -> Image.Image:
    return Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), (0, 0, 0, 0))


def glow_composite(base: Image.Image, shape: Image.Image, radius: float, alpha: float = 1.0) -> None:
    glow = shape.copy()
    if alpha < 1.0:
        glow.putalpha(glow.getchannel("A").point(lambda p: round(p * alpha)))
    base.alpha_composite(glow.filter(ImageFilter.GaussianBlur(sc(radius))))
    base.alpha_composite(shape)


def guard_wave(frame: int, colors: tuple) -> Image.Image:
    img, shape = layer(), layer(); d = ImageDraw.Draw(shape)
    phase = frame / FRAMES * math.tau
    width = 20 + 5 * math.sin(phase)
    box = (sc(61), sc(50 - width / 2), sc(194), sc(206 + width / 2))
    d.arc(box, 278, 82, fill=colors[0] + (255,), width=sc(10))
    d.arc((sc(70), sc(62), sc(184), sc(194)), 286, 74, fill=colors[1] + (235,), width=sc(4))
    d.polygon([(sc(182), sc(85)), (sc(230), sc(128)), (sc(182), sc(171)), (sc(197), sc(128))], fill=colors[0] + (220,))
    glow_composite(img, shape, 7, .72); return img


def blade_arc(frame: int, colors: tuple, mirrored: bool = False) -> Image.Image:
    img, shape = layer(), layer(); d = ImageDraw.Draw(shape)
    shift = 5 * math.sin(frame / FRAMES * math.tau)
    d.arc((sc(36 + shift), sc(34), sc(220 + shift), sc(222)), 294, 72, fill=colors[0] + (250,), width=sc(18))
    d.arc((sc(47 + shift), sc(47), sc(211 + shift), sc(210)), 300, 66, fill=colors[1] + (255,), width=sc(6))
    d.polygon([(sc(195 + shift), sc(67)), (sc(239), sc(128)), (sc(195 + shift), sc(184)), (sc(211), sc(128))], fill=colors[0] + (210,))
    glow_composite(img, shape, 6, .8)
    return img.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if mirrored else img


def tracer(frame: int, colors: tuple, mirrored: bool = False) -> Image.Image:
    img, shape = layer(), layer(); d = ImageDraw.Draw(shape)
    pulse = 1.0 + .16 * math.sin(frame / FRAMES * math.tau)
    d.polygon([(sc(32), sc(128)), (sc(194), sc(112)), (sc(235), sc(128)), (sc(194), sc(144))], fill=colors[0] + (220,))
    d.line((sc(48), sc(128), sc(229), sc(128)), fill=colors[1] + (255,), width=sc(5 * pulse))
    for x in (66, 106, 146):
        d.line((sc(x), sc(116), sc(x - 25), sc(102)), fill=colors[0] + (120,), width=sc(3))
    glow_composite(img, shape, 4.5, .78)
    return img.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if mirrored else img


def energy_bolt(frame: int, colors: tuple, mirrored: bool = False) -> Image.Image:
    img, shape = layer(), layer(); d = ImageDraw.Draw(shape)
    phase = frame / FRAMES * math.tau; y = 8 * math.sin(phase)
    d.ellipse((sc(82), sc(96 + y), sc(194), sc(160 + y)), fill=colors[0] + (225,))
    d.ellipse((sc(112), sc(108 + y), sc(181), sc(148 + y)), fill=(255, 244, 255, 245))
    d.polygon([(sc(25), sc(128)), (sc(118), sc(100 + y)), (sc(106), sc(128)), (sc(118), sc(156 + y))], fill=colors[1] + (185,))
    d.arc((sc(76), sc(72), sc(210), sc(184)), 20 + frame * 22, 175 + frame * 22, fill=colors[1] + (245,), width=sc(5))
    glow_composite(img, shape, 7, .75)
    return img.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if mirrored else img


def cannon_orb(frame: int, colors: tuple) -> Image.Image:
    img, shape = layer(), layer(); d = ImageDraw.Draw(shape)
    phase = frame / FRAMES * math.tau; radius = 42 + 5 * math.sin(phase)
    cx, cy = 148, 128
    d.ellipse((sc(cx-radius), sc(cy-radius), sc(cx+radius), sc(cy+radius)), fill=colors[0] + (235,))
    d.ellipse((sc(cx-radius*.58), sc(cy-radius*.58), sc(cx+radius*.58), sc(cy+radius*.58)), fill=(246, 255, 222, 245))
    d.arc((sc(73), sc(78), sc(222), sc(178)), frame * 26, 190 + frame * 26, fill=colors[1] + (245,), width=sc(6))
    d.arc((sc(91), sc(58), sc(205), sc(198)), 180 - frame * 23, 350 - frame * 23, fill=colors[0] + (220,), width=sc(4))
    d.polygon([(sc(22), sc(128)), (sc(117), sc(101)), (sc(101), sc(128)), (sc(117), sc(155))], fill=colors[1] + (175,))
    glow_composite(img, shape, 8, .72); return img


def render(kind: str, frame: int, colors: tuple) -> Image.Image:
    if kind == "guard_wave": return guard_wave(frame, colors)
    if kind == "blade_arc": return blade_arc(frame, colors)
    if kind == "enemy_claw": return blade_arc(frame, colors, True)
    if kind == "tracer": return tracer(frame, colors)
    if kind == "energy_bolt": return energy_bolt(frame, colors)
    if kind == "cannon_orb": return cannon_orb(frame, colors)
    if kind == "enemy_bolt": return energy_bolt(frame, colors, True)
    raise ValueError(kind)


def main() -> int:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    summary = []
    for source_id, spec in PACKS.items():
        pack = OUTPUT / spec["asset_id"]
        pack.mkdir(parents=True, exist_ok=True)
        paths = []
        for index in range(FRAMES):
            image = render(spec["kind"], index, spec["colors"])
            image = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
            path = pack / f"frame_{index:03d}.png"
            image.save(path, "PNG", optimize=True)
            paths.append(path.name)
        manifest = {
            "schema_version": 1, "asset_id": spec["asset_id"], "source_id": source_id,
            "status": "DEV_CODE_RENDERED_VFX", "production_approved": False,
            "frame_size": [SIZE, SIZE], "fps": FPS, "loop": False, "frames": FRAMES,
            "orientation": spec["orientation"], "runtime_size": spec["size"],
            "flight_duration": spec["flight_duration"],
            "frame_paths": paths, "created_utc": datetime.now(timezone.utc).isoformat(),
        }
        (pack / "projectile_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        summary.append({"source_id": source_id, "asset_id": spec["asset_id"], "frames": FRAMES})
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
