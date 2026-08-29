#!/usr/bin/env python3
"""Build the authoritative 44-character presentation separation QA.

The prior R2 standing contact sheet paired a green-matte source and an RGBA
derivative, but it used SD combat authorities for much of CHR009–CHR044.  It
cannot establish the project's non-combat 8-head rule and is deliberately not
read here.  This builder reads only the current 8-head card contract for
non-combat art and the isolated combat preview path for SD art, then produces
small, inspectable pages plus a machine-readable contract.
"""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
CARD_CONTRACT = ROOT / "data_source" / "art_source" / "card_8head_green_matte_r1" / "qa" / "CARD_8HEAD_RGBA_R1_CONTRACT.json"
OUTPUT = ROOT / "builds" / "qa" / "character_presentation_r3"
CONTRACT_OUTPUT = OUTPUT / "CHARACTER_PRESENTATION_R3_CONTRACT.json"
LEGACY_R2 = ROOT / "builds" / "qa" / "standing_rgba_r2_continuity_contact_sheet.png"
GREEN = (0, 255, 0)
PAGE_SIZE = (1760, 2060)
PANEL_SIZE = (840, 490)
PAGES = ((1, 11), (12, 22), (23, 33), (34, 44))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/malgunbd.ttf" if bold else "C:/Windows/Fonts/malgun.ttf"),
        Path("C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            return ImageFont.truetype(candidate, size=size)
    return ImageFont.load_default()


def checkerboard(size: tuple[int, int], cell: int = 18) -> Image.Image:
    image = Image.new("RGB", size, (235, 238, 244))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(204, 211, 224))
    return image.convert("RGBA")


def fit(image: Image.Image, size: tuple[int, int], background: Image.Image) -> Image.Image:
    output = background.copy()
    subject = image.convert("RGBA").copy()
    subject.thumbnail(size, Image.Resampling.LANCZOS)
    x = (output.width - subject.width) // 2
    y = (output.height - subject.height) // 2
    output.alpha_composite(subject, (x, y))
    return output


def alpha_metrics(path: Path) -> dict:
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    extrema = list(alpha.getextrema())
    bbox = alpha.getbbox()
    if extrema != [0, 255] or bbox is None:
        raise ValueError(f"{relative(path)} lacks required true-alpha RGBA: {extrema}, {bbox}")
    return {"size": list(image.size), "alphaExtrema": extrema, "alphaBbox": list(bbox)}


def green_metrics(path: Path) -> dict:
    image = Image.open(path).convert("RGB")
    width, height = image.size
    probe = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
    values = [image.getpixel(point) for point in probe]
    if any(value != GREEN for value in values):
        raise ValueError(f"{relative(path)} is not a flat #00FF00 source matte at its canvas corners: {values}")
    return {"size": [width, height], "cornerPixels": [list(value) for value in values], "generationMatte": "#00FF00"}


def path_from_contract(value: str) -> Path:
    path = ROOT / value
    if not path.is_file():
        raise FileNotFoundError(path)
    return path


def create_page(rows: list[dict], page_number: int) -> Path:
    page = Image.new("RGBA", PAGE_SIZE, (12, 21, 37, 255))
    draw = ImageDraw.Draw(page)
    title = font(32, True)
    label = font(20, True)
    small = font(15)
    draw.text((40, 30), "CHARACTER PRESENTATION R3 — NONCOMBAT 8-HEAD / BATTLE SD", font=title, fill=(235, 243, 255))
    draw.text((40, 74), "Every panel: 8-head green source → 8-head transparent runtime → isolated SD combat runtime. R2 mixed sheet is invalid.", font=small, fill=(144, 211, 198))
    for index, row in enumerate(rows):
        column = index % 2
        line = index // 2
        left = 36 + column * 860
        top = 120 + line * 510
        draw.rounded_rectangle((left, top, left + PANEL_SIZE[0], top + PANEL_SIZE[1]), radius=14, fill=(20, 34, 57), outline=(72, 209, 188), width=2)
        draw.text((left + 16, top + 14), row["characterId"], font=label, fill=(255, 218, 132))
        draw.text((left + 132, top + 18), "NONCOMBAT: 8-HEAD", font=small, fill=(112, 245, 207))
        draw.text((left + 540, top + 18), "BATTLE/MAP: SD", font=small, fill=(142, 191, 255))
        slots = [
            (left + 16, "8-HEAD\nSOURCE #00FF00", row["greenSource"], Image.new("RGBA", (244, 382), GREEN + (255,))),
            (left + 298, "8-HEAD\nRUNTIME RGBA", row["runtimePortrait"], checkerboard((244, 382))),
            (left + 580, "SD COMBAT\nRUNTIME RGBA", row["combatPreview"], checkerboard((244, 382))),
        ]
        for x, caption, file_value, background in slots:
            draw.text((x, top + 52), caption, font=small, fill=(194, 216, 239), spacing=1)
            art = Image.open(ROOT / file_value).convert("RGBA")
            cell = fit(art, (244, 382), background)
            page.alpha_composite(cell, (x, top + 96))
            draw.rectangle((x, top + 96, x + 244, top + 478), outline=(105, 126, 161), width=1)
    target = OUTPUT / f"CHARACTER_PRESENTATION_R3_PAGE_{page_number:02d}.png"
    page.convert("RGB").save(target, optimize=True)
    return target


def main() -> int:
    if not CARD_CONTRACT.is_file():
        raise FileNotFoundError(CARD_CONTRACT)
    document = json.loads(CARD_CONTRACT.read_text(encoding="utf-8"))
    characters = dict(document.get("characters", {}))
    expected = {f"CHR{index:03d}" for index in range(1, 45)}
    if set(characters) != expected:
        raise ValueError(f"8-head card contract coverage mismatch: {len(characters)}")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    for index in range(1, 45):
        character_id = f"CHR{index:03d}"
        entry = dict(characters[character_id])
        green = path_from_contract(str(entry["greenMatte"]))
        portrait = path_from_contract(str(entry["runtimePortrait"]))
        combat = ROOT / "godot" / "assets" / "runtime_web" / "combat" / character_id / "preview.png"
        if not combat.is_file():
            raise FileNotFoundError(combat)
        if portrait == combat or portrait.parent.parent.name == "combat":
            raise ValueError(f"{character_id} presentation families are not separated")
        if sha256(portrait) != str(entry["runtimePortraitSha256"]):
            raise ValueError(f"{character_id} 8-head runtime portrait hash drift")
        green_record = green_metrics(green)
        portrait_record = alpha_metrics(portrait)
        combat_record = alpha_metrics(combat)
        rows.append({
            "characterId": character_id,
            "nonCombatRule": "8_HEAD_ONLY_CARD_GACHA_ROSTER_STORY_RECRUIT",
            "combatMapRule": "SD_ONLY",
            "greenSource": relative(green),
            "greenSourceSha256": sha256(green),
            "greenSourceQa": green_record,
            "runtimePortrait": relative(portrait),
            "runtimePortraitSha256": sha256(portrait),
            "runtimePortraitQa": portrait_record,
            "combatPreview": relative(combat),
            "combatPreviewSha256": sha256(combat),
            "combatPreviewQa": combat_record,
            "costumeId": str(entry["costumeId"]),
            "status": "PASS_SEPARATED_8HEAD_NONCOMBAT_AND_SD_COMBAT",
        })
    pages = []
    for page_number, (start, end) in enumerate(PAGES, start=1):
        page = create_page(rows[start - 1:end], page_number)
        pages.append(relative(page))
    r2_receipt = {
        "legacyPath": relative(LEGACY_R2) if LEGACY_R2.exists() else "builds/qa/standing_rgba_r2_continuity_contact_sheet.png",
        "status": "SUPERSEDED_INVALID_MIXED_PRESENTATION_QA",
        "reason": "R2 used SD combat authorities as standing/card evidence for part of the 44-character roster.",
        "replacement": "builds/qa/character_presentation_r3/CHARACTER_PRESENTATION_R3_CONTRACT.json",
    }
    payload = {
        "schemaVersion": 3,
        "generationMatte": "#00FF00",
        "runtimeBackground": "RGBA_TRANSPARENT",
        "coverage": "CHR001-CHR044",
        "nonCombatRule": "8_HEAD_ONLY_CARD_GACHA_ROSTER_STORY_RECRUIT",
        "combatMapRule": "SD_ONLY",
        "legacyR2": r2_receipt,
        "pages": pages,
        "characters": rows,
        "summary": {"total": len(rows), "passed": len(rows), "failed": 0},
    }
    CONTRACT_OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"CHARACTER_PRESENTATION_R3_QA=pass:{len(rows)}|pages={len(pages)}|contract={relative(CONTRACT_OUTPUT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
