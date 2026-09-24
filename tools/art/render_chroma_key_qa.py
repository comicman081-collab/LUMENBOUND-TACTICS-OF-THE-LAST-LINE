#!/usr/bin/env python3
"""Render a retained chroma-master / keyed-RGBA visual QA sheet.

This is a read-only renderer for an already-built local-QA derivative. It does
not promote, alter, or delete a combat candidate. The generated evidence shows
the original cutout, its flat #00FF00 master, and the keyed result over both
dark and light backgrounds so exterior matte is visible during review.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
REPORT_ROOT = ROOT / "reports" / "art_qa"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def cli() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--entity", default="CHR002")
    return parser.parse_args()


def thumbnail(image: Image.Image, background: tuple[int, int, int, int] | None) -> Image.Image:
    target = Image.new("RGBA", (228, 228), background or (0, 0, 0, 0))
    subject = image.convert("RGBA").copy()
    subject.thumbnail((214, 214), Image.Resampling.LANCZOS)
    position = ((target.width - subject.width) // 2, (target.height - subject.height) // 2)
    target.alpha_composite(subject, position)
    return target


def main() -> int:
    args = cli()
    revision = str(args.revision).strip().lower()
    entity = str(args.entity).strip().upper()
    derivative_manifest_path = (
        ROOT
        / "godot"
        / "assets"
        / "generated_import"
        / "chroma_key_derivatives"
        / f"battle_signature_{revision}"
        / entity
        / "chroma_key_derivative_manifest.json"
    )
    if not derivative_manifest_path.is_file():
        raise SystemExit(f"DERIVATIVE_MANIFEST_MISSING:{derivative_manifest_path}")
    manifest = json.loads(derivative_manifest_path.read_text(encoding="utf-8"))
    records = manifest.get("records", [])
    if not isinstance(records, list) or not records:
        raise SystemExit("DERIVATIVE_RECORDS_MISSING")
    selected: list[dict] = []
    for animation in ("idle", "ultimate", "hit", "down"):
        match = next((record for record in records if str(record.get("animation", "")) == animation), None)
        if not isinstance(match, dict):
            raise SystemExit(f"DERIVATIVE_ANIMATION_MISSING:{animation}")
        selected.append(match)

    columns = ["ORIGINAL · DARK", "#00FF00 MASTER", "KEYED RGBA · DARK", "KEYED RGBA · LIGHT"]
    width = 32 + len(columns) * 248
    height = 64 + len(selected) * 266
    sheet = Image.new("RGBA", (width, height), (16, 24, 37, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((16, 16), f"{entity} {revision.upper()} · CHROMA MASTER → KEYED RGBA · LOCAL QA ONLY", fill=(233, 245, 255, 255))
    for column, label in enumerate(columns):
        draw.text((32 + column * 248, 43), label, fill=(143, 216, 255, 255))

    dark = (10, 17, 25, 255)
    light = (239, 242, 246, 255)
    for row, record in enumerate(selected):
        y = 64 + row * 266
        draw.text((6, y + 104), str(record.get("animation", "")).upper(), fill=(255, 216, 130, 255))
        original = Image.open(ROOT / str(record["source_path"]))
        master = Image.open(ROOT / str(record["green_master_path"]))
        keyed = Image.open(ROOT / str(record["keyed_rgba_path"]))
        panels = [
            thumbnail(original, dark),
            thumbnail(master, None),
            thumbnail(keyed, dark),
            thumbnail(keyed, light),
        ]
        for column, panel in enumerate(panels):
            x = 32 + column * 248
            sheet.alpha_composite(panel, (x, y))
            draw.rectangle((x, y, x + 227, y + 227), outline=(76, 101, 132, 255), width=1)

    REPORT_ROOT.mkdir(parents=True, exist_ok=True)
    output_png = REPORT_ROOT / f"BATTLE_SIGNATURE_HD_{revision.upper()}_{entity}_CHROMA_KEY_QA.png"
    output_json = REPORT_ROOT / f"BATTLE_SIGNATURE_HD_{revision.upper()}_{entity}_CHROMA_KEY_QA.json"
    if output_png.exists() or output_json.exists():
        raise SystemExit(f"QA_OUTPUT_EXISTS_REFUSE_TO_OVERWRITE:{output_png}")
    sheet.convert("RGB").save(output_png, format="PNG", optimize=True)
    white_before = sum(int(record.get("key_qc", {}).get("white_exterior_rim_pixels_before", 0)) for record in records)
    white_after = sum(int(record.get("key_qc", {}).get("white_exterior_rim_pixels_after", 0)) for record in records)
    output_json.write_text(json.dumps({
        "kind": "BATTLE_SIGNATURE_CHROMA_KEY_DUAL_BACKDROP_QA",
        "approval_status": "LOCAL_QA_ONLY",
        "revision": revision,
        "entity": entity,
        "derivative_manifest": derivative_manifest_path.relative_to(ROOT).as_posix(),
        "derivative_manifest_sha256": sha256(derivative_manifest_path),
        "source_frames_checked": len(records),
        "white_exterior_rim_pixels_before": white_before,
        "white_exterior_rim_pixels_after": white_after,
        "qa_sheet": output_png.relative_to(ROOT).as_posix(),
        "qa_sheet_sha256": sha256(output_png),
        "review_rule": "Green master is evidence only. The only runtime candidate is the keyed RGBA branch, and public export remains held.",
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"qa_sheet": str(output_png), "report": str(output_json)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
