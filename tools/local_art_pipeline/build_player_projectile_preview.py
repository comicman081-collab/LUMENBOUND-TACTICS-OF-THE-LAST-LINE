#!/usr/bin/env python3
"""Build a review GIF from all five active player projectile frame packs."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
PROJECTILES = ROOT / "godot" / "assets" / "generated_import" / "projectiles"
OUTPUT = ROOT / "reports" / "art_qa" / "player_projectiles_r28_preview.gif"
PACKS = [
    ("CHR001  TEAL GUARD WAVE  0.13s", "proj_chr001_teal_guard_wave_r28", (63, 255, 216), .13),
    ("CHR002  CORAL BLADE ARC  0.08s", "proj_chr002_coral_blade_arc_r28", (255, 95, 128), .08),
    ("CHR003  ICE RIFLE TRACER  0.06s", "proj_chr003_ice_rifle_tracer_r28", (99, 225, 255), .06),
    ("CHR004  MAGENTA ENERGY BOLT  0.09s", "proj_chr004_magenta_energy_bolt_r28", (255, 72, 226), .09),
    ("CHR005  EMERALD CANNON ORB  0.12s", "proj_chr005_emerald_cannon_orb_r28", (64, 255, 169), .12),
]


def main() -> int:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    frames = []
    frame_time = .02
    for tick in range(24):
        canvas = Image.new("RGBA", (960, 600), (12, 24, 49, 255))
        draw = ImageDraw.Draw(canvas)
        for row, (label, folder, accent, flight_duration) in enumerate(PACKS):
            top = 18 + row * 112
            draw.text((24, top + 43), label, fill=accent + (255,))
            draw.line((24, top + 79, 930, top + 79), fill=accent + (70,), width=2)
            local_tick = tick % 12
            flight_frames = max(3, round(flight_duration / frame_time))
            if local_tick < flight_frames:
                travel = local_tick / max(1, flight_frames - 1)
                frame_index = min(7, round(travel * 7))
                fx = Image.open(PROJECTILES / folder / f"frame_{frame_index:03d}.png").convert("RGBA")
                fx = fx.resize((118, 118), Image.Resampling.LANCZOS)
                x = round(385 + 430 * travel)
                canvas.alpha_composite(fx, (x - 59, top - 1))
        frames.append(canvas.convert("P", palette=Image.Palette.ADAPTIVE))
    frames[0].save(OUTPUT, save_all=True, append_images=frames[1:], duration=20, loop=0, disposal=2)
    print(OUTPUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
