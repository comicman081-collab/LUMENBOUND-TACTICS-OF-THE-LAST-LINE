"""Build compact, in-PCK character cards for the R7 Web runtime.

The original high-resolution illustration and animation sources remain where
they are.  This produces one small 384x576 RGBA card per playable character
for roster, formation, detail fallback, and the chapter-map squad pawn.  It is
deliberately separate from the production-art tree so the Web release can keep
all eight character identities visible without exceeding the hosting file cap.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "godot" / "assets" / "runtime_web" / "characters"
SOURCES = {
    "CHR001": ROOT / "godot" / "assets" / "art" / "characters" / "CHR001" / "portrait_1024x1536.png",
    "CHR002": ROOT / "godot" / "assets" / "generated_import" / "characters" / "sd_chr002_roan_combat_r27_dev" / "combat_base_512.png",
    "CHR003": ROOT / "godot" / "assets" / "generated_import" / "characters" / "sd_chr003_narin_combat_r27_dev" / "combat_base_512.png",
    "CHR004": ROOT / "godot" / "assets" / "generated_import" / "characters" / "sd_chr004_eda_combat_r27_dev" / "combat_base_512.png",
    "CHR005": ROOT / "godot" / "assets" / "generated_import" / "characters" / "sd_chr005_soren_combat_r27_dev" / "combat_base_512.png",
    "CHR006": ROOT / "data_source" / "art_source" / "runtime_cards" / "CHR006_vera_icon_r7.png",
    "CHR007": ROOT / "data_source" / "art_source" / "runtime_cards" / "CHR007_toa_icon_r7.png",
    "CHR008": ROOT / "godot" / "assets" / "art" / "characters" / "CHR008" / "portrait_1024x1536.png",
}


def render_card(character_id: str, source: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(f"missing runtime card source for {character_id}: {source}")
    image = Image.open(source).convert("RGBA")
    card = Image.new("RGBA", (384, 576), (0, 0, 0, 0))
    if character_id in {"CHR002", "CHR003", "CHR004", "CHR005"}:
        # SD combat anchors are square.  Keep their full silhouette but give
        # them portrait-card breathing room so they do not become tiny heads.
        image.thumbnail((360, 430), Image.Resampling.LANCZOS)
        offset = ((384 - image.width) // 2, 80 + (430 - image.height) // 2)
    elif character_id in {"CHR006", "CHR007"}:
        # Runtime card is intentionally an upper-body composition: readable in
        # a 220px formation cell and still useful as a Sprite3D map-pawn face.
        crop_height = min(image.height, image.width)
        crop = image.crop((0, 0, image.width, crop_height))
        crop.thumbnail((384, 512), Image.Resampling.LANCZOS)
        image = crop
        offset = ((384 - image.width) // 2, 22 + (512 - image.height) // 2)
    else:
        image.thumbnail((384, 576), Image.Resampling.LANCZOS)
        offset = ((384 - image.width) // 2, (576 - image.height) // 2)
    card.alpha_composite(image, offset)
    target = OUTPUT / f"{character_id}_card_384x576.png"
    card.save(target, optimize=True)
    print(f"RUNTIME_CARD={character_id}|{target.name}|{target.stat().st_size}")


def main() -> int:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for character_id, source in SOURCES.items():
        render_card(character_id, source)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
