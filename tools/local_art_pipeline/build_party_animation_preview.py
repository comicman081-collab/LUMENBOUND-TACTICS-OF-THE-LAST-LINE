#!/usr/bin/env python3
"""Build an animated QA preview from the exact frames consumed by Godot."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
PACKS = [
    ("CHR001", ROOT / "godot/assets/generated_import/characters/sd_chr001_maeru_combat_r27_dev"),
    ("CHR002", ROOT / "godot/assets/generated_import/characters/sd_chr002_roan_combat_r27_dev"),
    ("CHR003", ROOT / "godot/assets/generated_import/characters/sd_chr003_narin_combat_r27_dev"),
    ("CHR004", ROOT / "godot/assets/generated_import/characters/sd_chr004_eda_combat_r27_dev"),
    ("CHR005", ROOT / "godot/assets/generated_import/characters/sd_chr005_soren_combat_r27_dev"),
]
SEQUENCE = [
    ("idle", range(8)),
    ("move", range(12)),
    ("basic_attack", range(8)),
    ("hit", range(4)),
    ("victory", range(10)),
]


def main() -> int:
    output = ROOT / "reports/art_qa/party_r27_animation_preview.gif"
    output.parent.mkdir(parents=True, exist_ok=True)
    timeline = [(name, index) for name, indices in SEQUENCE for index in indices]
    frames: list[Image.Image] = []
    for animation, index in timeline:
        canvas = Image.new("RGBA", (1280, 360), (12, 25, 50, 255))
        draw = ImageDraw.Draw(canvas)
        draw.text((20, 16), f"R27 RUNTIME FRAMES  |  {animation.upper()}  {index + 1}", fill=(218, 236, 255, 255))
        draw.line((20, 314, 1260, 314), fill=(70, 105, 135, 255), width=2)
        for slot, (character_id, pack) in enumerate(PACKS):
            source = pack / animation / f"{animation}_{index:03d}.png"
            sprite = Image.open(source).convert("RGBA").resize((256, 256), Image.Resampling.LANCZOS)
            x = slot * 250 + 12
            canvas.alpha_composite(sprite, (x, 62))
            draw.rounded_rectangle((x + 72, 52, x + 184, 60), radius=4, fill=(29, 50, 63, 255))
            draw.rounded_rectangle((x + 72, 52, x + 184, 60), radius=4, fill=(86, 226, 157, 255))
            draw.text((x + 100, 326), character_id, fill=(215, 230, 248, 255))
        frames.append(canvas.convert("P", palette=Image.Palette.ADAPTIVE, colors=255))
    frames[0].save(output, save_all=True, append_images=frames[1:], duration=83, loop=0, disposal=2, optimize=False)
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
