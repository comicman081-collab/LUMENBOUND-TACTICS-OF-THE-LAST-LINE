"""Build identity reference sheets and split reviewed 4x2 SD renewal batches.

The grid order is immutable: row-major, four columns by two rows.  Each source
identity remains traceable through the emitted JSON report and SHA-256 hashes.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
import numpy as np
from scipy import ndimage


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "data_source" / "art_source" / "expansion_static_sources"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def character_rows() -> dict[str, dict[str, str]]:
    with (ROOT / "data_source" / "characters.csv").open(encoding="utf-8-sig", newline="") as stream:
        return {row["id"]: row for row in csv.DictReader(stream)}


def clear_edge_connected_background(image: Image.Image) -> Image.Image:
    """Remove a baked white/checker/dark stage background from one atlas cell.

    The generated review batches are RGB previews, so their apparent backdrop
    is not real transparency.  We classify the backdrop from the cell perimeter
    and only flood pixels that remain connected to that perimeter.  This keeps
    enclosed costume highlights while removing the matte around the silhouette.
    """
    result = image.convert("RGBA")
    pixels = result.load()
    width, height = result.size
    perimeter = []
    # The caller clears a four-pixel grid divider first; sample just inside it.
    inset = 4
    for x in range(inset, width - inset):
        perimeter.extend((pixels[x, inset][:3], pixels[x, height - 1 - inset][:3]))
    for y in range(inset + 1, height - 1 - inset):
        perimeter.extend((pixels[inset, y][:3], pixels[width - 1 - inset, y][:3]))
    perimeter_array = np.asarray(perimeter, dtype=np.int16)
    perimeter_colour = np.median(perimeter_array, axis=0)
    perimeter_luma = float(np.median(perimeter_array.mean(axis=1)))
    light_backdrop = perimeter_luma >= 145

    if not light_backdrop:
        # The navy stage is nearly uniform, while the inked silhouette is often
        # even darker than the backdrop.  Brightness-keying would erase those
        # black outlines, so key by RGB distance to the measured stage colour.
        rgba = np.asarray(result).copy()
        distance = np.linalg.norm(rgba[:, :, :3].astype(np.float32) - perimeter_colour, axis=2)
        mask = distance > 12.0
        labels, count = ndimage.label(mask)
        if count:
            sizes = np.bincount(labels.ravel())
            keep = sizes >= 24
            keep[0] = False
            mask = keep[labels]
        rgba[~mask] = (0, 0, 0, 0)
        return Image.fromarray(rgba, "RGBA")

    def is_background(red: int, green: int, blue: int, alpha: int) -> bool:
        if alpha == 0:
            return True
        low = min(red, green, blue)
        high = max(red, green, blue)
        chroma = high - low
        if light_backdrop:
            # White and baked checkerboard previews are neutral but may be
            # darkened around the generated subject by a soft contact shadow.
            return low >= 145 and chroma <= 48
        return False

    queue: deque[tuple[int, int]] = deque()
    seen: set[tuple[int, int]] = set()
    for x in range(width):
        queue.extend(((x, 0), (x, height - 1)))
    for y in range(1, height - 1):
        queue.extend(((0, y), (width - 1, y)))
    while queue:
        x, y = queue.popleft()
        if (x, y) in seen:
            continue
        seen.add((x, y))
        red, green, blue, alpha = pixels[x, y]
        if is_background(red, green, blue, alpha):
            pixels[x, y] = (0, 0, 0, 0)
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < width and 0 <= ny < height:
                    queue.append((nx, ny))
    # Eliminate disconnected compression/checker specks while retaining every
    # meaningful detached prop.  At source-cell resolution 24 pixels is much
    # smaller than a hand, muzzle, badge, or floating support device.
    rgba = np.asarray(result).copy()
    mask = rgba[:, :, 3] > 0
    labels, count = ndimage.label(mask)
    if count:
        sizes = np.bincount(labels.ravel())
        keep = sizes >= 24
        keep[0] = False
        cleaned = keep[labels]
        rgba[~cleaned] = (0, 0, 0, 0)
    return Image.fromarray(rgba, "RGBA")


def checkerboard(size: tuple[int, int], tile: int = 24) -> Image.Image:
    width, height = size
    board = Image.new("RGBA", size, (228, 232, 240, 255))
    draw = ImageDraw.Draw(board)
    for y in range(0, height, tile):
        for x in range(0, width, tile):
            if (x // tile + y // tile) % 2:
                draw.rectangle((x, y, min(x + tile - 1, width - 1), min(y + tile - 1, height - 1)), fill=(184, 192, 207, 255))
    return board


def make_qa(ids: list[str], authority_root: Path, output: Path) -> None:
    """Compose reviewed RGBA authorities over an explicit checkerboard."""
    sheet = Image.new("RGBA", (1536, 1024), (16, 23, 37, 255))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=20)
    for index, entity_id in enumerate(ids):
        col, row = index % 4, index // 4
        left, top = col * 384, row * 512
        panel = checkerboard((384, 512), 24)
        # Prefer the latest explicitly versioned authority.  Older rejected
        # batch candidates remain on disk for auditability but must not leak
        # back into a reviewer-facing comparison sheet.
        costume_d = authority_root / f"{entity_id.lower()}_costume_d_authority.png"
        costume_c = authority_root / f"{entity_id.lower()}_costume_c_authority.png"
        costume_b = authority_root / f"{entity_id.lower()}_costume_b_authority.png"
        selected = costume_d if costume_d.exists() else costume_c if costume_c.exists() else costume_b
        authority = Image.open(selected).convert("RGBA")
        authority.thumbnail((360, 470), Image.Resampling.LANCZOS)
        panel.alpha_composite(authority, ((384 - authority.width) // 2, 34 + (470 - authority.height) // 2))
        sheet.alpha_composite(panel, (left, top))
        draw.rectangle((left, top, left + 383, top + 511), outline=(54, 73, 104, 255), width=2)
        draw.rectangle((left + 8, top + 7, left + 108, top + 35), fill=(10, 17, 29, 220))
        draw.text((left + 16, top + 10), entity_id, font=font, fill=(248, 250, 255, 255))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(output, quality=94, optimize=True)


def clean_single(source_path: Path, output: Path) -> None:
    """Normalize one generated full-body candidate into a square RGBA authority."""
    candidate = Image.open(source_path).convert("RGBA")
    original_alpha = np.asarray(candidate.getchannel("A"))
    # Some ImageGen candidates do carry a real alpha channel.  Keep that
    # authority instead of keying its dark outlines as though they were a
    # baked backdrop; discard only imperceptible perimeter residue.
    if float((original_alpha < 8).mean()) >= 0.20:
        rgba = np.asarray(candidate).copy()
        rgba[rgba[:, :, 3] < 8] = (0, 0, 0, 0)
        candidate = Image.fromarray(rgba, "RGBA")
    else:
        candidate = clear_edge_connected_background(candidate)
    alpha_bbox = candidate.getchannel("A").getbbox()
    if alpha_bbox is None:
        raise ValueError(f"{source_path.name} became fully transparent")
    cutout = candidate.crop(alpha_bbox)
    scale = min(900 / cutout.width, 944 / cutout.height)
    cutout = cutout.resize(
        (max(1, round(cutout.width * scale)), max(1, round(cutout.height * scale))),
        Image.Resampling.LANCZOS,
    )
    authority = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    authority.alpha_composite(cutout, ((1024 - cutout.width) // 2, 40 + (944 - cutout.height) // 2))
    output.parent.mkdir(parents=True, exist_ok=True)
    authority.save(output, optimize=True)


def make_reference(ids: list[str], output: Path) -> None:
    if not 1 <= len(ids) <= 8:
        raise ValueError("a renewal batch must contain 1..8 characters")
    rows = character_rows()
    sheet = Image.new("RGBA", (1536, 1024), (14, 20, 33, 255))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=20)
    small = ImageFont.load_default(size=14)
    for index, entity_id in enumerate(ids):
        row = rows[entity_id]
        col, grid_row = index % 4, index // 4
        left, top = col * 384, grid_row * 512
        source_path = SOURCE_ROOT / f"{entity_id.lower()}_authority.png"
        source = Image.open(source_path).convert("RGBA")
        bbox = source.getbbox() or (0, 0, source.width, source.height)
        cutout = source.crop(bbox)
        cutout.thumbnail((330, 420), Image.Resampling.LANCZOS)
        x = left + (384 - cutout.width) // 2
        y = top + 62 + (420 - cutout.height) // 2
        sheet.alpha_composite(cutout, (x, y))
        draw.rectangle((left, top, left + 383, top + 511), outline=(77, 99, 135, 255), width=2)
        draw.text((left + 12, top + 9), entity_id, font=font, fill=(245, 248, 255, 255))
        meta = f"{row['role']} | {row['weapon_class']} | {row['attack_type']}"
        draw.text((left + 12, top + 36), meta, font=small, fill=(168, 194, 230, 255))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, optimize=True)


def split_batch(ids: list[str], source_path: Path, output_root: Path, report_path: Path) -> None:
    image = Image.open(source_path).convert("RGBA")
    if image.width % 4 or image.height % 2:
        raise ValueError(f"expected divisible 4x2 atlas, got {image.size}")
    cell_w, cell_h = image.width // 4, image.height // 2
    output_root.mkdir(parents=True, exist_ok=True)
    records = []
    for index, entity_id in enumerate(ids):
        col, row = index % 4, index // 4
        cell = image.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h))
        # Remove divider pixels baked into some generated batch sheets before
        # flood segmentation. They are layout residue, never character art.
        edge = ImageDraw.Draw(cell)
        edge.rectangle((0, 0, cell.width - 1, cell.height - 1), outline=(0, 0, 0, 0), width=4)
        cell = clear_edge_connected_background(cell)
        alpha_bbox = cell.getchannel("A").getbbox()
        if alpha_bbox is None:
            raise ValueError(f"{entity_id} cell is fully transparent")
        cutout = cell.crop(alpha_bbox)
        scale = min(880 / cutout.width, 940 / cutout.height)
        cutout = cutout.resize((max(1, round(cutout.width * scale)), max(1, round(cutout.height * scale))), Image.Resampling.LANCZOS)
        authority = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        authority.alpha_composite(cutout, ((1024 - cutout.width) // 2, 44 + (940 - cutout.height) // 2))
        output = output_root / f"{entity_id.lower()}_costume_b_authority.png"
        authority.save(output, optimize=True)
        records.append({
            "id": entity_id,
            "authority": str(output.relative_to(ROOT)).replace("\\", "/"),
            "sha256": sha256(output),
            "sourceCell": [col, row],
            "alphaExtrema": list(authority.getchannel("A").getextrema()),
            "status": "CANDIDATE_PENDING_GPT_COSTUME_CONTINUITY_REVIEW",
        })
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps({
        "schemaVersion": 1,
        "batchSource": str(source_path.relative_to(ROOT)).replace("\\", "/"),
        "batchSourceSha256": sha256(source_path),
        "grid": [4, 2],
        "characters": records,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    make = sub.add_parser("make-reference")
    make.add_argument("output", type=Path)
    make.add_argument("ids", nargs="+")
    split = sub.add_parser("split")
    split.add_argument("source", type=Path)
    split.add_argument("output_root", type=Path)
    split.add_argument("report", type=Path)
    split.add_argument("ids", nargs="+")
    qa = sub.add_parser("make-qa")
    qa.add_argument("authority_root", type=Path)
    qa.add_argument("output", type=Path)
    qa.add_argument("ids", nargs="+")
    clean = sub.add_parser("clean-single")
    clean.add_argument("source", type=Path)
    clean.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.command == "make-reference":
        ids = [value.upper() for value in args.ids]
        make_reference(ids, args.output.resolve())
    elif args.command == "split":
        ids = [value.upper() for value in args.ids]
        split_batch(ids, args.source.resolve(), args.output_root.resolve(), args.report.resolve())
    elif args.command == "make-qa":
        ids = [value.upper() for value in args.ids]
        make_qa(ids, args.authority_root.resolve(), args.output.resolve())
    else:
        clean_single(args.source.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()
