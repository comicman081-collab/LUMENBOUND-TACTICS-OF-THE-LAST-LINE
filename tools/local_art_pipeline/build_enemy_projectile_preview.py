#!/usr/bin/env python3
"""Build a review GIF from the exact enemy and projectile runtime frames."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "godot" / "assets" / "generated_import"
OUTPUT = ROOT / "reports" / "art_qa" / "enemy_projectile_r28_preview.gif"

ENEMIES = [
    ("ENM001", ASSETS / "enemies" / "sd_enm001_rush_drone_combat_r28_dev", ASSETS / "projectiles" / "proj_enm001_crystal_claw_r28", (255, 112, 55)),
    ("ENM002", ASSETS / "enemies" / "sd_enm002_arc_mote_combat_r28_dev", ASSETS / "projectiles" / "proj_enm002_arc_mote_r28", (79, 222, 255)),
]


def main() -> int:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    frames = []
    for tick in range(24):
        image = Image.new("RGBA", (960, 420), (12, 24, 49, 255))
        draw = ImageDraw.Draw(image)
        draw.rectangle((0, 325, 960, 420), fill=(38, 53, 75, 255))
        for row, (label, enemy_root, projectile_root, accent) in enumerate(ENEMIES):
            x, y = 750, 65 + row * 170
            phase = tick % 16
            animation = "basic_attack" if phase >= 8 else "move"
            count = 8 if animation == "basic_attack" else 12
            frame_index = (phase - 8) if animation == "basic_attack" else phase
            sprite = Image.open(enemy_root / animation / f"{animation}_{frame_index % count:03d}.png").convert("RGBA").resize((230, 230), Image.Resampling.LANCZOS)
            image.alpha_composite(sprite, (x - 115, y - 80))
            if phase >= 10:
                fx_index = min(7, phase - 10)
                fx = Image.open(projectile_root / f"frame_{fx_index:03d}.png").convert("RGBA").resize((92, 92), Image.Resampling.LANCZOS)
                travel = min(1.0, (phase - 10) / 5.0)
                px = round((x - 105) * (1.0 - travel) + 100 * travel)
                image.alpha_composite(fx, (px - 46, y + 11))
            draw.text((22, y + 25), f"{label}  {animation.upper()}", fill=accent + (255,))
            draw.line((20, y + 61, 930, y + 61), fill=accent + (80,), width=2)
        frames.append(image.convert("P", palette=Image.Palette.ADAPTIVE))
    frames[0].save(OUTPUT, save_all=True, append_images=frames[1:], duration=83, loop=0, disposal=2)
    print(OUTPUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
