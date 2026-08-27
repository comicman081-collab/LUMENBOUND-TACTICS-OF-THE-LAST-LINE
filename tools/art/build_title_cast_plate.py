#!/usr/bin/env python3
"""Build the title-screen cast plate from immutable full-body authorities."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "godot"
OUTPUT = GODOT / "assets/art/title/title_cast_plate_r1.png"
PORTRAIT_OUTPUT = GODOT / "assets/art/title/title_cast_plate_portrait_r1.png"
LOGO_OUTPUT = GODOT / "assets/art/title/title_logo_r1.png"
LEDGER = ROOT / "data_source/art_source/title/qa/TITLE_CAST_CONTINUITY_R1.json"
BACKGROUND = GODOT / "assets/art/backgrounds/BG_STORY_RELAY/bg_story_relay_1920x1080.png"
SOURCES = [
    ("CHR002", GODOT / "assets/art/characters/CHR002/CHR002_ILLUSTRATION_MASTER_R1.png", 1010, (-170, 86), 0.78),
    ("CHR003", GODOT / "assets/art/characters/CHR003/CHR003_ILLUSTRATION_MASTER_R1.png", 900, (155, 155), 0.91),
    ("CHR008", GODOT / "assets/art/characters/CHR008/CHR008_ILLUSTRATION_MASTER_R1.png", 905, (1265, 150), 0.92),
    ("CHR001", GODOT / "assets/art/characters/CHR001/fullbody_2048x3072.png", 1070, (1540, 28), 0.82),
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fit_cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = max(size[0] / image.width, size[1] / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - size[0]) // 2
    top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1]))


def resize_height(image: Image.Image, height: int) -> Image.Image:
    return image.resize((round(image.width * height / image.height), height), Image.Resampling.LANCZOS)


def add_character(canvas: Image.Image, source: Path, height: int, position: tuple[int, int], opacity: float) -> None:
    character = resize_height(Image.open(source).convert("RGBA"), height)
    if opacity < 1.0:
        alpha = character.getchannel("A").point(lambda value: round(value * opacity))
        character.putalpha(alpha)
    shadow_alpha = character.getchannel("A").filter(ImageFilter.GaussianBlur(20)).point(lambda value: round(value * 0.72))
    shadow = Image.new("RGBA", character.size, (0, 0, 0, 0))
    shadow.putalpha(shadow_alpha)
    canvas.alpha_composite(shadow, (position[0] + 20, position[1] + 24))
    glow_alpha = character.getchannel("A").filter(ImageFilter.GaussianBlur(13)).point(lambda value: round(value * 0.26))
    glow = Image.new("RGBA", character.size, (78, 226, 214, 0))
    glow.putalpha(glow_alpha)
    canvas.alpha_composite(glow, position)
    canvas.alpha_composite(character, position)


def build_plate() -> None:
    background = fit_cover(Image.open(BACKGROUND).convert("RGB"), (1920, 1080))
    background = ImageEnhance.Brightness(background).enhance(0.69)
    background = ImageEnhance.Contrast(background).enhance(1.12).convert("RGBA")
    canvas = background.copy()
    grade = Image.new("RGBA", canvas.size, (5, 12, 25, 0))
    grade_alpha = Image.new("L", canvas.size)
    pixels = grade_alpha.load()
    for y in range(canvas.height):
        for x in range(canvas.width):
            edge = abs(x - 960) / 960
            vertical = abs(y - 500) / 580
            pixels[x, y] = round(82 + 78 * max(edge, vertical) + 34 * (y / 1080))
    grade.putalpha(grade_alpha)
    canvas.alpha_composite(grade)

    draw = ImageDraw.Draw(canvas, "RGBA")
    for index in range(12):
        x = 960 + (index - 5.5) * 88
        draw.line((960, 330, x, 1030), fill=(102, 235, 220, 10), width=18)
    center_glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(center_glow, "RGBA")
    glow_draw.ellipse((410, 120, 1510, 1040), fill=(3, 8, 20, 205), outline=(225, 180, 92, 42), width=3)
    center_glow = center_glow.filter(ImageFilter.GaussianBlur(52))
    canvas.alpha_composite(center_glow)

    for _character_id, source, height, position, opacity in SOURCES:
        add_character(canvas, source, height, position, opacity)

    draw = ImageDraw.Draw(canvas, "RGBA")
    draw.rectangle((0, 0, 1920, 1080), outline=(226, 188, 103, 75), width=3)
    draw.line((440, 784, 1480, 784), fill=(226, 188, 103, 70), width=2)
    for x, y, radius in [(520, 212, 3), (641, 126, 2), (1390, 220, 3), (1500, 350, 2), (460, 650, 2), (1440, 690, 3)]:
        draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill=(247, 219, 148, 190))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGBA").save(OUTPUT, optimize=True)


def build_portrait_plate() -> None:
    background = fit_cover(Image.open(BACKGROUND).convert("RGB"), (1080, 1920))
    background = ImageEnhance.Brightness(background).enhance(0.64)
    background = ImageEnhance.Contrast(background).enhance(1.10).convert("RGBA")
    canvas = background.copy()
    grade = Image.new("RGBA", canvas.size, (3, 9, 20, 108))
    canvas.alpha_composite(grade)
    # Keep the middle readable for the shared logo/CTA while the immutable cast
    # frames the lower mobile composition instead of disappearing in a crop.
    add_character(canvas, SOURCES[1][1], 1290, (-335, 640), 0.90)
    add_character(canvas, SOURCES[3][1], 1460, (560, 480), 0.86)
    center = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    center_draw = ImageDraw.Draw(center, "RGBA")
    center_draw.ellipse((-180, 100, 1260, 1430), fill=(2, 7, 18, 190), outline=(226, 188, 103, 44), width=3)
    canvas.alpha_composite(center.filter(ImageFilter.GaussianBlur(48)))
    draw = ImageDraw.Draw(canvas, "RGBA")
    draw.rectangle((0, 0, 1079, 1919), outline=(226, 188, 103, 75), width=3)
    PORTRAIT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(PORTRAIT_OUTPUT, optimize=True)


def build_logo() -> None:
    size = (1240, 330)
    logo = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(logo)
    latin_path = Path("C:/Windows/Fonts/bahnschrift.ttf")
    korean_path = GODOT / "assets/fonts/NotoSansKR-VF.ttf"
    latin_font = ImageFont.truetype(str(latin_path), 112)
    korean_font = ImageFont.truetype(str(korean_path), 36)
    small_font = ImageFont.truetype(str(latin_path), 21)
    network_font = ImageFont.truetype(str(latin_path), 18)

    network = "LANTERNLINE NETWORK"
    nb = draw.textbbox((0, 0), network, font=network_font)
    nx = (size[0] - (nb[2] - nb[0])) // 2
    draw.text((nx, 26), network, font=network_font, fill=(213, 177, 105, 230))
    draw.line((196, 38, nx - 28, 38), fill=(213, 177, 105, 125), width=2)
    draw.line((nx + (nb[2] - nb[0]) + 28, 38, 1044, 38), fill=(213, 177, 105, 125), width=2)

    title = "LUMENBOUND"
    title_box = draw.textbbox((0, 0), title, font=latin_font, stroke_width=0)
    title_width = title_box[2] - title_box[0]
    origin = ((size[0] - title_width) // 2, 58)
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.text(origin, title, font=latin_font, fill=(91, 232, 217, 220), stroke_width=9, stroke_fill=(5, 13, 26, 225))
    logo.alpha_composite(glow.filter(ImageFilter.GaussianBlur(12)))
    draw = ImageDraw.Draw(logo)
    draw.text(origin, title, font=latin_font, fill=(231, 242, 241, 255), stroke_width=4, stroke_fill=(14, 27, 42, 255))
    draw.text(origin, title, font=latin_font, fill=(112, 235, 221, 82), stroke_width=1, stroke_fill=(239, 244, 244, 120))
    draw.line((origin[0], 193, origin[0] + title_width, 193), fill=(218, 177, 91, 210), width=3)

    subtitle = "TACTICS OF THE LAST LINE"
    sb = draw.textbbox((0, 0), subtitle, font=small_font)
    sx = (size[0] - (sb[2] - sb[0])) // 2
    draw.text((sx, 220), subtitle, font=small_font, fill=(224, 239, 239, 245), stroke_width=1, stroke_fill=(12, 35, 45, 255))
    tagline = "BOUND BY LIGHT  ·  FORGED BY CHOICE"
    tb = draw.textbbox((0, 0), tagline, font=small_font)
    tx = (size[0] - (tb[2] - tb[0])) // 2
    draw.text((tx, 275), tagline, font=small_font, fill=(205, 178, 112, 235))
    draw.line((170, 290, tx - 30, 290), fill=(218, 177, 91, 130), width=2)
    draw.line((tx + (tb[2] - tb[0]) + 30, 290, 1070, 290), fill=(218, 177, 91, 130), width=2)
    LOGO_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    logo.save(LOGO_OUTPUT, optimize=True)


def write_ledger() -> None:
    records = []
    for character_id, source, height, position, opacity in SOURCES:
        records.append({
            "characterId": character_id,
            "authorityPath": source.relative_to(ROOT).as_posix(),
            "authoritySha256": sha256(source),
            "transformation": {"scaleToHeight": height, "position": list(position), "opacity": opacity},
            "costumeContinuity": "COSTUME_CONTINUITY_PASS",
            "identityMutation": False,
        })
    payload = {
        "artifact": OUTPUT.relative_to(ROOT).as_posix(),
        "portraitArtifact": PORTRAIT_OUTPUT.relative_to(ROOT).as_posix(),
        "logoArtifact": LOGO_OUTPUT.relative_to(ROOT).as_posix(),
        "revision": "TITLE_CAST_R3_LUMENBOUND",
        "sources": records,
        "review": "deterministic LUMENBOUND tactical title composition of immutable authority art; no regeneration or costume edits",
    }
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    LEDGER.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    for _character_id, path, _height, _position, _opacity in SOURCES:
        if not path.is_file():
            raise FileNotFoundError(path)
    build_plate()
    build_portrait_plate()
    build_logo()
    write_ledger()
    print(f"TITLE_CAST_PLATE={OUTPUT}|sha256={sha256(OUTPUT)}")
    print(f"TITLE_CAST_PORTRAIT={PORTRAIT_OUTPUT}|sha256={sha256(PORTRAIT_OUTPUT)}")
    print(f"TITLE_LOGO={LOGO_OUTPUT}|sha256={sha256(LOGO_OUTPUT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
