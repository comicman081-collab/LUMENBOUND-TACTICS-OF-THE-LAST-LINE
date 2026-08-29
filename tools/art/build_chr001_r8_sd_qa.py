#!/usr/bin/env python3
"""Build visual and pixel-level QA evidence for Maeru's R8 SD combat pack.

The generation source intentionally retains an exact #00FF00 matte.  Every
runtime frame is keyed to RGBA before promotion, so this script validates all
80 animation frames and produces a labelled contact sheet on both light and
dark in-game-style backgrounds.  It is a QA artefact only; it never mutates
authoring or runtime assets.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "data_source/art_source/combat_hd_sources/maeru_r8_sd_green_matte/chr001_sd_r8_exact_green_matte.png"
RUNTIME_SOURCE = ROOT / "data_source/art_source/combat_hd_sources/maeru_r8_sd_green_matte/chr001_sd_r8_runtime_rgba.png"
PACK_ROOT = ROOT / "godot/assets/art/sd/CHR001"
MANIFEST = PACK_ROOT / "animation_manifest.json"
WEB_PREVIEW = ROOT / "godot/assets/runtime_web/combat/CHR001/preview.png"
OUT_DIR = ROOT / "reports/art_qa"
SHEET = OUT_DIR / "CHR001_SD_R8_GREEN_TO_RGBA_CONTACT_SHEET.png"
REPORT = OUT_DIR / "CHR001_SD_R8_GREEN_TO_RGBA_REPORT.json"


def green_key(red: int, green: int, blue: int) -> bool:
    """Same conservative residue detector used by the runtime validation."""
    return green >= 178 and red <= 104 and blue <= 104 and green - red >= 92 and green - blue >= 92


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf"),
        Path("C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def contain(image: Image.Image, bounds: tuple[int, int, int, int], inset: int = 18) -> tuple[Image.Image, tuple[int, int]]:
    left, top, right, bottom = bounds
    width, height = right - left - inset * 2, bottom - top - inset * 2
    scale = min(width / image.width, height / image.height)
    resized = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.LANCZOS)
    return resized, (left + (right - left - resized.width) // 2, top + (bottom - top - resized.height) // 2)


def checker(draw: ImageDraw.ImageDraw, rect: tuple[int, int, int, int], cell: int = 20) -> None:
    left, top, right, bottom = rect
    for y in range(top, bottom, cell):
        for x in range(left, right, cell):
            parity = ((x - left) // cell + (y - top) // cell) % 2
            draw.rectangle((x, y, min(right, x + cell), min(bottom, y + cell)), fill="#e4e9f1" if parity else "#f7f9fc")


def panel(canvas: Image.Image, draw: ImageDraw.ImageDraw, image: Image.Image, rect: tuple[int, int, int, int], title: str, subtitle: str, fill: str, checkered: bool = False) -> None:
    left, top, right, bottom = rect
    draw.rounded_rectangle(rect, radius=18, fill=fill, outline="#36526b", width=3)
    content = (left + 10, top + 68, right - 10, bottom - 10)
    if checkered:
        checker(draw, content)
    title_font = font(27, True)
    body_font = font(18)
    draw.text((left + 18, top + 15), title, font=title_font, fill="#81f4d8")
    draw.text((left + 18, top + 46), subtitle, font=body_font, fill="#b5c7da")
    rendered, position = contain(image, content)
    canvas.alpha_composite(rendered, position)


def main() -> int:
    if not all(path.is_file() for path in (SOURCE, RUNTIME_SOURCE, MANIFEST, WEB_PREVIEW)):
        missing = [str(path) for path in (SOURCE, RUNTIME_SOURCE, MANIFEST, WEB_PREVIEW) if not path.is_file()]
        raise RuntimeError("missing QA input: " + "; ".join(missing))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    frame_paths = [PACK_ROOT / frame for animation in manifest["animations"].values() for frame in animation["frame_paths"]]
    if len(frame_paths) != 80 or len(set(frame_paths)) != 80:
        raise RuntimeError(f"expected 80 unique animation frames, got {len(frame_paths)} total / {len(set(frame_paths))} unique")

    failures: list[str] = []
    frame_checks: list[dict[str, object]] = []
    for path in frame_paths:
        if not path.is_file():
            failures.append(f"missing:{path.relative_to(PACK_ROOT)}")
            continue
        image = Image.open(path).convert("RGBA")
        alpha_channel = image.getchannel("A")
        alpha = alpha_channel.getextrema()
        bounds = alpha_channel.getbbox()
        residue = sum(1 for red, green, blue, opacity in image.get_flattened_data() if opacity > 16 and green_key(red, green, blue))
        relative_frame = str(path.relative_to(PACK_ROOT)).replace("\\", "/")
        frame_checks.append({"frame": relative_frame, "alpha": list(alpha), "bounds": list(bounds) if bounds else None, "visible_green_pixels": residue})
        if alpha != (0, 255):
            failures.append(f"alpha:{path.relative_to(PACK_ROOT)}:{alpha}")
        if residue:
            failures.append(f"green_residue:{path.relative_to(PACK_ROOT)}:{residue}")
        # DOWN must show the complete prone silhouette.  Other attack poses
        # may intentionally use an edge-adjacent flash, but a collapsed body
        # touching the source frame edge is always an unintended crop.
        if relative_frame.startswith("down/") and (bounds is None or bounds[0] < 4 or bounds[1] < 4 or bounds[2] > image.width - 4 or bounds[3] > image.height - 4):
            failures.append(f"down_crop:{relative_frame}:{bounds}")

    source = Image.open(SOURCE).convert("RGBA")
    runtime = Image.open(RUNTIME_SOURCE).convert("RGBA")
    preview = Image.open(WEB_PREVIEW).convert("RGBA")
    idle = Image.open(PACK_ROOT / "idle/idle_003.png").convert("RGBA")
    ultimate = Image.open(PACK_ROOT / "ultimate/ultimate_011.png").convert("RGBA")
    down = Image.open(PACK_ROOT / "down/down_007.png").convert("RGBA")

    canvas = Image.new("RGBA", (2100, 1560), "#07111d")
    draw = ImageDraw.Draw(canvas)
    draw.text((44, 30), "CHR001 · MAERU · R8 SD COMBAT QA", font=font(44, True), fill="#f6e4a4")
    draw.text((46, 87), "Exact #00FF00 generation matte → keyed transparent RGBA → 80-frame combat pack → Web runtime preview", font=font(22), fill="#b5c7da")
    panel(canvas, draw, source, (40, 140, 690, 810), "GENERATION SOURCE", "Exact #00FF00 matte (authoring only)", "#00ff00")
    panel(canvas, draw, runtime, (725, 140, 1375, 810), "KEYED RUNTIME SOURCE", "RGBA alpha; light QA backdrop", "#1b2634", True)
    panel(canvas, draw, preview, (1410, 140, 2060, 810), "WEB ATLAS PREVIEW", "Packaged 128 px combat runtime", "#0b1620")
    panel(canvas, draw, idle, (40, 850, 520, 1490), "IDLE FRAME 003", "transparent frame on battle dark", "#132632")
    panel(canvas, draw, ultimate, (560, 850, 1040, 1490), "ULTIMATE FRAME 011", "transparent frame on battle dark", "#132632")
    panel(canvas, draw, down, (1080, 850, 1560, 1490), "DOWN FRAME 007", "down is the only allowed prone state", "#132632")
    summary = "PASS · 80/80 RGBA frames · no visible chroma residue" if not failures else "FAIL · " + "; ".join(failures[:3])
    draw.rounded_rectangle((1600, 850, 2060, 1490), radius=18, fill="#102235", outline="#36526b", width=3)
    draw.multiline_text((1630, 900), "RUNTIME QA\n\n" + summary + "\n\nSource SHA\n" + sha256(SOURCE)[:16] + "…\n\nRuntime SHA\n" + sha256(RUNTIME_SOURCE)[:16] + "…\n\nAtlas preview\n" + sha256(WEB_PREVIEW)[:16] + "…", font=font(24, True), fill="#dbeaf8", spacing=20)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(SHEET, quality=95)
    report = {
        "character_id": "CHR001",
        "asset_id": manifest["asset_id"],
        "authoring_matte": "#00FF00",
        "runtime_background": "transparent RGBA",
        "source_sha256": sha256(SOURCE),
        "runtime_source_sha256": sha256(RUNTIME_SOURCE),
        "web_preview_sha256": sha256(WEB_PREVIEW),
        "frame_count": len(frame_paths),
        "frame_checks": frame_checks,
        "failures": failures,
        "status": "PASS" if not failures else "FAIL",
        "contact_sheet": str(SHEET.relative_to(ROOT)).replace("\\", "/"),
    }
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"CHR001_R8_SD_QA={'PASS' if not failures else 'FAIL'}|frames={len(frame_paths)}|sheet={SHEET}|report={REPORT}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
