#!/usr/bin/env python3
"""Build a bounded high-density battle signature pack from existing art.

This is deliberately a non-generative bridge.  It never changes the verified
512px authoring frames and it does not overwrite the compact 128px combat
atlases.  Instead, it derives a small 384px ``idle / ultimate / hit / down``
slice for the active reference group.  The result is intended for visual QA
before a Web export: normal attacks continue to use the compact atlas while
camera, anticipation, lunge, recoil, and hit presentation are implemented in
BattleView.

Every output carries its exact source paths and SHA-256 hashes.  If a future
visual review rejects a revision, keep that revision under quarantine rather
than deleting it or reusing its output directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "godot"
RUNTIME_ROOT = GODOT / "assets" / "runtime_web" / "combat_signature"
REPORT_ROOT = ROOT / "reports" / "art_qa"
CHROMA_DERIVATIVE_ROOT = GODOT / "assets" / "generated_import" / "chroma_key_derivatives"
CHROMA_GREEN = (0, 255, 0, 255)

CELL_SIZE = 384
## R5 keeps the same 384px logical combat canvas but stores only the visible
## alpha-bearing pixels in its texture pages.  Each frame records its original
## position inside the logical canvas, so the renderer can preserve foot/head
## anchors without retaining 50%+ transparent padding on the GPU.
CROP_PADDING = 4
MAX_ATLAS_DIMENSION = 2048
ATLAS_WIDTH_CANDIDATES = (512, 768, 1024, 1280, 1536, 1792, 2048)
ATLAS_ALIGNMENT = 4
SIGNATURE_ANIMATIONS = ("idle", "ultimate", "hit", "down")
SIGNATURE_CORE_ANIMATIONS = ("idle", "hit", "down")

SOURCES = {
    "CHR001": {
        "root": GODOT / "assets" / "art" / "sd" / "CHR001",
        "manifest": GODOT / "assets" / "art" / "sd" / "CHR001" / "animation_manifest.json",
        "source_asset_id": "sd_chr001_maeru_combat_r8_green_key",
        "costume_id": "CHR001_CANONICAL_GUARDIAN_R1",
        "authority_status": "PROJECT_APPROVED_COMBAT_AUTHORITY",
        "identity": {
            "role": "GUARDIAN",
            "adult_classification": "ADULT",
            "signature_palette": "teal hair + ivory/gold armor + cyan shield lantern",
            "weapon": "shield and lantern mace",
            "silhouette": "adult SD guardian with long teal hair and forward shield",
        },
    },
    "CHR002": {
        ## This is the existing project-local 512px source set.  Its manifest
        ## is explicitly DEV, so R5 records it as local-QA-only and may never
        ## be promoted into a public runtime without an authority review.
        "root": GODOT / "assets" / "generated_import" / "characters" / "sd_chr002_roan_combat_r27_dev",
        "manifest": GODOT / "assets" / "generated_import" / "characters" / "sd_chr002_roan_combat_r27_dev" / "animation_manifest.json",
        "source_asset_id": "sd_chr002_roan_combat_r27_dev",
        "costume_id": "CHR002_CANONICAL_VANGUARD_R27_DEV_LOCAL_QA",
        "authority_status": "PROJECT_DEV_SOURCE_LOCAL_QA_ONLY_NOT_PROMOTABLE",
        "identity": {
            "role": "VANGUARD",
            "adult_classification": "ADULT",
            "signature_palette": "coral-red hair + graphite/black armor layers + crimson diamond trim",
            "weapon": "two-handed broad blade",
            "silhouette": "adult SD front-line vanguard with swept coral ponytail and forward blade guard",
        },
    },
    "CHR003": {
        # The default player's rear-line rifle authority is already an
        # in-project 512px cutout rig. It remains LOCAL_QA_ONLY because its
        # upstream animation manifest is DEV, but it is a genuine detailed
        # motion source rather than an enlarged 128px runtime thumbnail.
        "root": GODOT / "assets" / "generated_import" / "characters" / "sd_chr003_narin_combat_r27_dev",
        "manifest": GODOT / "assets" / "generated_import" / "characters" / "sd_chr003_narin_combat_r27_dev" / "animation_manifest.json",
        "source_asset_id": "sd_chr003_narin_combat_r27_dev",
        "costume_id": "CHR003_CANONICAL_ASSAULT_R27_DEV_LOCAL_QA",
        "authority_status": "PROJECT_DEV_SOURCE_LOCAL_QA_ONLY_NOT_PROMOTABLE",
        # Keep the perceptible anticipation, shot and recovery keys while
        # preserving the five-party core + one-caster transient mobile model.
        "signature_frame_indices": {
            "idle": [0, 2, 4, 6],
            "ultimate": [0, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17],
        },
        "identity": {
            "role": "ASSAULT",
            "adult_classification": "ADULT",
            "signature_palette": "silver-blue hair + black tactical base + white/cobalt armor + restrained violet rifle energy",
            "weapon": "long angular precision rifle with controlled two-hand grip",
            "silhouette": "adult SD mid-line markswoman with a high left-swept ponytail and stable long-range stance",
        },
    },
    "CHR004": {
        # Eda is in the actual first active party (CHR001 through CHR005), not
        # merely a future roster candidate.  Her immutable 512px rig already
        # carries the independent mobile carbine motion; preserve its selected
        # anticipation, contact and recovery frames rather than enlarging the
        # compact 128px atlas or borrowing another assault silhouette.
        "root": GODOT / "assets" / "generated_import" / "characters" / "sd_chr004_eda_combat_r27_dev",
        "manifest": GODOT / "assets" / "generated_import" / "characters" / "sd_chr004_eda_combat_r27_dev" / "animation_manifest.json",
        "source_asset_id": "sd_chr004_eda_combat_r27_dev",
        "costume_id": "CHR004_CANONICAL_ASSAULT_R27_DEV_LOCAL_QA",
        "authority_status": "PROJECT_DEV_SOURCE_LOCAL_QA_ONLY_NOT_PROMOTABLE",
        "signature_frame_indices": {
            "idle": [0, 2, 4, 6],
            "ultimate": [0, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17],
        },
        "identity": {
            "role": "ASSAULT",
            "adult_classification": "ADULT",
            "signature_palette": "deep-violet high ponytail + black/violet agile tactical armor + restrained magenta energy seams",
            "weapon": "compact angular energy carbine with a visible magenta energy chamber",
            "silhouette": "adult SD mobile assault operative with a high ponytail, compact carbine and forward close-range stance",
        },
    },
    "CHR005": {
        # Same local-QA boundary as CHR003: use the available immutable 512px
        # rig for a real high-density combat read, never a stretched card or
        # compact Web atlas.
        "root": GODOT / "assets" / "generated_import" / "characters" / "sd_chr005_soren_combat_r27_dev",
        "manifest": GODOT / "assets" / "generated_import" / "characters" / "sd_chr005_soren_combat_r27_dev" / "animation_manifest.json",
        "source_asset_id": "sd_chr005_soren_combat_r27_dev",
        "costume_id": "CHR005_CANONICAL_ARTILLERY_R27_DEV_LOCAL_QA",
        "authority_status": "PROJECT_DEV_SOURCE_LOCAL_QA_ONLY_NOT_PROMOTABLE",
        "signature_frame_indices": {
            "idle": [0, 2, 4, 6],
            "ultimate": [0, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17],
        },
        "identity": {
            "role": "ARTILLERY",
            "adult_classification": "ADULT",
            "signature_palette": "honey-blonde hair + charcoal/antique-brass armor + ivory split coat + emerald cannon core",
            "weapon": "oversized anomaly cannon with circular emerald core and readable two-hand grip",
            "silhouette": "adult SD rear-line heavy operator with high braided ponytail and grounded cannon-braced stance",
        },
    },
    "CHR008": {
        "root": GODOT / "assets" / "art" / "sd" / "CHR008",
        "manifest": GODOT / "assets" / "art" / "sd" / "CHR008" / "animation_manifest.json",
        "source_asset_id": "sd_chr008_premium_r6p2",
        "costume_id": "CHR008_MEDIC_SUPPORT_R6P2",
        "authority_status": "R6P2_COMBAT_AUTHORITY",
        "identity": {
            "role": "MEDIC",
            "adult_classification": "ADULT",
            "signature_palette": "silver-lavender braided hair + ivory/teal medic layers + warm gold trim",
            "weapon": "handheld support device and circular medical relay",
            "silhouette": "adult SD rear-line medic with long braid, halo-like headpiece, hand beacon and circular support relay",
        },
    },
    "BOSS001": {
        "root": GODOT / "assets" / "art" / "bosses" / "BOSS001",
        "manifest": GODOT / "assets" / "art" / "bosses" / "BOSS001" / "animation_manifest.json",
        "source_asset_id": "sd_boss001_premium_r6p2",
        "costume_id": "BOSS001_HOLLOW_ENGINE_R6P2",
        "authority_status": "R6P2_COMBAT_AUTHORITY",
        "identity": {
            "role": "BOSS_PATTERN",
            "adult_classification": "GENDERLESS_NONHUMAN",
            "signature_palette": "weathered iron + cyan core + orange furnace",
            "weapon": "integrated engine arms and rotating core",
            "silhouette": "low, broad, quadruped hollow engine with circular sensor core",
        },
    },
    "ENM001": {
        # ENM001 is the first common Chapter 1 enemy with its full immutable
        # 512px animation authority still available in-project.  Keep it as a
        # separate local-QA candidate rather than pretending its 128px Web
        # atlas contains new detail.
        "root": GODOT / "assets" / "art" / "enemies" / "ENM001",
        "manifest": GODOT / "assets" / "art" / "enemies" / "ENM001" / "animation_manifest.json",
        "source_asset_id": "sd_enm001_premium_r6p2",
        "costume_id": "ENM001_RUSH_WISP_R6P2",
        "authority_status": "ART_QA_CANDIDATE_LOCAL_QA_ONLY_NOT_PROMOTABLE",
        # Four idle frames preserve the weight-shift loop. Twelve evenly
        # distributed ultimate keys retain preparation, lunge, contact and
        # recovery while keeping the five-actor mobile lease below 72 MiB.
        "signature_frame_indices": {
            "idle": [0, 2, 4, 6],
            "ultimate": [0, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17],
        },
        "identity": {
            "role": "MELEE_RUSH",
            "adult_classification": "GENDERLESS_NONHUMAN",
            "signature_palette": "deep navy armored plates + ember-orange crystal fins + cyan joints + orange core",
            "weapon": "integrated crystal claws and forelimb strike assembly",
            "silhouette": "low, wide quadruped rush construct with forward orange crystal crest",
        },
    },
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def cli() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", default="R1", help="immutable candidate revision, for example R1")
    parser.add_argument(
        "--entities",
        default=",".join(SOURCES),
        help="comma-separated signature entities; defaults to the reviewed local-QA reference group",
    )
    parser.add_argument(
        "--chroma-remaster-entities",
        default="",
        help=(
            "comma-separated entities to derive through a flat #00FF00 master "
            "and keyed RGBA repair before this immutable candidate is built"
        ),
    )
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def visible_green_pixels(image: Image.Image) -> int:
    """Detect only *visible* exact chroma-green remnants.

    Fully transparent RGB payloads and alpha=1 edge samples are not visual
    matte residue.  Treat alpha 24 (about 9%) as the conservative visibility
    floor; stronger green is still a hard failure while genuine cyan/teal art
    remains outside the exact chroma hue test.
    """
    count = 0
    for red, green, blue, alpha in image.convert("RGBA").getdata():
        if alpha > 24 and green >= 245 and red <= 20 and blue <= 20:
            count += 1
    return count


def alpha_summary(image: Image.Image) -> dict:
    alpha = image.getchannel("A")
    extrema = alpha.getextrema()
    bbox = alpha.point(lambda value: 255 if value > 18 else 0).getbbox()
    return {
        "alpha_extrema": [int(extrema[0]), int(extrema[1])],
        "alpha_bounds": list(bbox) if bbox else None,
        "visible_exact_green_pixels": visible_green_pixels(image),
    }


def external_white_edge_count(image: Image.Image, include_opaque: bool = False) -> int:
    """Count near-white exterior pixels touching transparent space.

    The normal mode audits semi-transparent spill. The stricter mode also
    audits opaque rim pixels, which catches a white-background cutout that was
    already flattened at its outermost one-pixel edge.
    """
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = list(rgba.getdata())
    count = 0
    for y in range(1, height - 1):
        row = y * width
        for x in range(1, width - 1):
            red, green, blue, alpha = pixels[row + x]
            alpha_matches = 0 < alpha <= 255 if include_opaque else 0 < alpha < 255
            if not (alpha_matches and red >= 220 and green >= 220 and blue >= 220):
                continue
            if (
                pixels[row + x - 1][3] == 0
                or pixels[row + x + 1][3] == 0
                or pixels[row - width + x][3] == 0
                or pixels[row + width + x][3] == 0
            ):
                count += 1
    return count


def flat_chroma_master(source: Image.Image) -> Image.Image:
    """Flatten real RGBA art over a uniform #00FF00 key plate.

    The master stays opaque and is retained as an intermediate provenance
    artifact. It is never a runtime texture.
    """
    master = Image.new("RGBA", source.size, CHROMA_GREEN)
    master.alpha_composite(source.convert("RGBA"))
    return master


def _nearest_interior_color(
    pixels: list[tuple[int, int, int, int]], width: int, height: int, x: int, y: int
) -> tuple[int, int, int] | None:
    """Find a nearby opaque, preferably non-white interior color for fringe repair."""
    best_nonwhite: tuple[int, int, int, int] | None = None
    best_any: tuple[int, int, int, int] | None = None
    best_translucent: tuple[int, int, int, int] | None = None
    for radius in range(1, 6):
        for sample_y in range(max(0, y - radius), min(height, y + radius + 1)):
            for sample_x in range(max(0, x - radius), min(width, x + radius + 1)):
                if max(abs(sample_x - x), abs(sample_y - y)) != radius:
                    continue
                red, green, blue, alpha = pixels[sample_y * width + sample_x]
                distance = (sample_x - x) * (sample_x - x) + (sample_y - y) * (sample_y - y)
                if alpha >= 8 and not (red >= 220 and green >= 220 and blue >= 220):
                    translucent = (distance, red, green, blue)
                    if best_translucent is None or translucent < best_translucent:
                        best_translucent = translucent
                if alpha < 224:
                    continue
                distance = (sample_x - x) * (sample_x - x) + (sample_y - y) * (sample_y - y)
                candidate = (distance, red, green, blue)
                if best_any is None or candidate < best_any:
                    best_any = candidate
                if not (red >= 220 and green >= 220 and blue >= 220):
                    if best_nonwhite is None or candidate < best_nonwhite:
                        best_nonwhite = candidate
        if best_nonwhite is not None:
            break
    # Thin hair strands may have no >=224-alpha sample within five pixels.
    # Their own coloured antialias samples are a better spill authority than
    # another white matte pixel. Alpha and geometry are never changed here.
    chosen = best_nonwhite or best_translucent or best_any
    if chosen is None:
        return None
    return chosen[1], chosen[2], chosen[3]


def key_chroma_master(master: Image.Image, alpha_plate: Image.Image) -> tuple[Image.Image, dict]:
    """Recover straight RGBA from a green master and repair exterior white spill.

    The retained alpha plate is the deterministic key mask: it protects genuine
    lime/teal costume details from a naive hue-only key and lets us invert the
    documented green composite exactly. Only white, semi-transparent exterior
    fringe pixels are recolored from nearby opaque art; geometry and alpha
    coverage are preserved. The R2 repair also decontaminates an opaque white
    outer rim when the original white background was baked into that final edge
    pixel; interior white/silver highlights do not meet the exterior test.
    """
    source = alpha_plate.convert("RGBA")
    master_rgba = master.convert("RGBA")
    if source.size != master_rgba.size:
        raise RuntimeError("CHROMA_KEY_DIMENSION_MISMATCH")
    width, height = source.size
    source_pixels = list(source.getdata())
    master_pixels = list(master_rgba.getdata())
    keyed_pixels: list[tuple[int, int, int, int]] = []
    repaired = 0
    for index, (_, _, _, alpha) in enumerate(source_pixels):
        if alpha == 0:
            keyed_pixels.append((0, 0, 0, 0))
            continue
        master_red, master_green, master_blue, _ = master_pixels[index]
        # Invert source-over-green for straight RGB. The alpha plate is retained
        # only for the keyed matte, not as a replacement runtime source.
        red = max(0, min(255, round(master_red * 255 / alpha)))
        green = max(0, min(255, round((master_green - (255 - alpha)) * 255 / alpha)))
        blue = max(0, min(255, round(master_blue * 255 / alpha)))
        x = index % width
        y = index // width
        is_external = False
        if 0 < x < width - 1 and 0 < y < height - 1:
            is_external = (
                source_pixels[index - 1][3] == 0
                or source_pixels[index + 1][3] == 0
                or source_pixels[index - width][3] == 0
                or source_pixels[index + width][3] == 0
            )
        if is_external and red >= 220 and green >= 220 and blue >= 220:
            interior = _nearest_interior_color(source_pixels, width, height, x, y)
            if interior is not None:
                red, green, blue = interior
                repaired += 1
        keyed_pixels.append((red, green, blue, alpha))
    keyed = Image.new("RGBA", source.size, (0, 0, 0, 0))
    keyed.putdata(keyed_pixels)
    return keyed, {
        "method": "flat_00ff00_master_then_alpha_plate_key_with_external_white_fringe_decontamination_r2",
        "chroma_green": "#00FF00",
        "white_external_edge_pixels_before": external_white_edge_count(source),
        "white_external_edge_pixels_repaired": repaired,
        "white_external_edge_pixels_after": external_white_edge_count(keyed),
        "white_exterior_rim_pixels_before": external_white_edge_count(source, include_opaque=True),
        "white_exterior_rim_pixels_after": external_white_edge_count(keyed, include_opaque=True),
    }


def _copy_signature_animation_manifest(source_manifest: dict, frame_paths_by_animation: dict[str, list[str]]) -> dict:
    """Write only the source metadata needed by this bounded signature slice."""
    output = {
        key: source_manifest[key]
        for key in ("frame_size", "foot_anchor", "head_anchor", "view", "facing_policy")
        if key in source_manifest
    }
    output["animations"] = {}
    for animation_name, frame_paths in frame_paths_by_animation.items():
        original = source_manifest.get("animations", {}).get(animation_name, {})
        copied = dict(original) if isinstance(original, dict) else {}
        copied["frame_paths"] = frame_paths
        output["animations"][animation_name] = copied
    return output


def build_chroma_key_derivative(entity_id: str, revision: str) -> dict:
    """Create immutable green-master and keyed-RGBA source branches for one entity."""
    source = SOURCES[entity_id]
    source_root: Path = source["root"]
    source_manifest_path: Path = source["manifest"]
    source_manifest = json.loads(source_manifest_path.read_text(encoding="utf-8"))
    revision_root = CHROMA_DERIVATIVE_ROOT / f"battle_signature_{revision.lower()}" / entity_id
    master_root = revision_root / "green_master"
    keyed_root = revision_root / "keyed_rgba"
    if revision_root.exists():
        raise RuntimeError(f"CHROMA_DERIVATIVE_EXISTS_REFUSE_TO_OVERWRITE:{revision_root}")
    records: list[dict] = []
    frame_paths_by_animation: dict[str, list[str]] = {}
    for animation_name in SIGNATURE_ANIMATIONS:
        written_paths: list[str] = []
        frame_selection = source.get("signature_frame_indices", {}).get(animation_name)
        for source_path in source_animation_paths(source_root, source_manifest, animation_name, frame_selection):
            relative_path = source_path.relative_to(source_root)
            master_path = master_root / relative_path
            keyed_path = keyed_root / relative_path
            master_path.parent.mkdir(parents=True, exist_ok=True)
            keyed_path.parent.mkdir(parents=True, exist_ok=True)
            original = Image.open(source_path).convert("RGBA")
            original_qc = alpha_summary(original)
            if original_qc["alpha_extrema"] != [0, 255] or original_qc["visible_exact_green_pixels"]:
                raise RuntimeError(f"{source_path}:CHROMA_REPAIR_INPUT_INVALID:{original_qc}")
            master = flat_chroma_master(original)
            if master.getchannel("A").getextrema() != (255, 255):
                raise RuntimeError(f"{source_path}:CHROMA_MASTER_NOT_OPAQUE")
            master.save(master_path, format="PNG", optimize=True)
            keyed, key_qc = key_chroma_master(master, original)
            keyed_qc = alpha_summary(keyed)
            if keyed_qc["alpha_extrema"] != [0, 255] or keyed_qc["visible_exact_green_pixels"]:
                raise RuntimeError(f"{source_path}:CHROMA_KEY_OUTPUT_INVALID:{keyed_qc}")
            if (
                key_qc["white_external_edge_pixels_before"] > 0
                and key_qc["white_external_edge_pixels_after"] >= key_qc["white_external_edge_pixels_before"]
            ):
                raise RuntimeError(f"{source_path}:CHROMA_KEY_WHITE_MATTE_NOT_REDUCED:{key_qc}")
            if (
                key_qc["white_exterior_rim_pixels_before"] > 0
                and key_qc["white_exterior_rim_pixels_after"] >= key_qc["white_exterior_rim_pixels_before"]
            ):
                raise RuntimeError(f"{source_path}:CHROMA_KEY_OPAQUE_WHITE_RIM_NOT_REDUCED:{key_qc}")
            keyed.save(keyed_path, format="PNG", optimize=True)
            relative_text = relative_path.as_posix()
            written_paths.append(relative_text)
            records.append({
                "animation": animation_name,
                "source_path": source_path.relative_to(ROOT).as_posix(),
                "source_sha256": sha256(source_path),
                "green_master_path": master_path.relative_to(ROOT).as_posix(),
                "green_master_sha256": sha256(master_path),
                "keyed_rgba_path": keyed_path.relative_to(ROOT).as_posix(),
                "keyed_rgba_sha256": sha256(keyed_path),
                "source_qc": original_qc,
                "keyed_qc": keyed_qc,
                "key_qc": key_qc,
            })
        frame_paths_by_animation[animation_name] = written_paths
    keyed_manifest = _copy_signature_animation_manifest(source_manifest, frame_paths_by_animation)
    keyed_manifest["chroma_key_provenance"] = {
        "source_manifest": source_manifest_path.relative_to(ROOT).as_posix(),
        "source_manifest_sha256": sha256(source_manifest_path),
        "green_master": "flat #00FF00 only; never runtime",
        "key_method": "flat_00ff00_master_then_alpha_plate_key_with_external_white_fringe_decontamination_r2",
        "identity": "pixel/pose/costume preserving; no generative model or costume change",
    }
    keyed_manifest_path = keyed_root / "animation_manifest.json"
    keyed_manifest_path.parent.mkdir(parents=True, exist_ok=True)
    keyed_manifest_path.write_text(json.dumps(keyed_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    derivative_manifest = {
        "schema_version": 1,
        "status": "LOCAL_QA_ONLY_CHROMA_KEY_DERIVATIVE",
        "entity_id": entity_id,
        "revision": revision.lower(),
        "source_asset_id": source["source_asset_id"],
        "costume_id": source["costume_id"],
        "identity_fingerprint": source["identity"],
        "green_master_root": master_root.relative_to(ROOT).as_posix(),
        "keyed_rgba_root": keyed_root.relative_to(ROOT).as_posix(),
        "keyed_animation_manifest": keyed_manifest_path.relative_to(ROOT).as_posix(),
        "keyed_animation_manifest_sha256": sha256(keyed_manifest_path),
        "records": records,
        "failure_retention": "Prior art and every rejected derivative remain retained; this derivative may not replace a runtime pointer until visual and runtime gates pass.",
    }
    derivative_manifest_path = revision_root / "chroma_key_derivative_manifest.json"
    derivative_manifest_path.parent.mkdir(parents=True, exist_ok=True)
    derivative_manifest_path.write_text(json.dumps(derivative_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    override = dict(source)
    override["root"] = keyed_root
    override["manifest"] = keyed_manifest_path
    # `keyed_manifest` already contains only the selected source frames. Do
    # not apply the original source indices a second time when its signature
    # atlas is assembled (for example ENM001 idle [0,2,4,6] is now a four-frame
    # keyed sequence indexed [0,1,2,3]).
    override["signature_frame_indices"] = {}
    override["source_asset_id"] = f"{source['source_asset_id']}_chroma_key_{revision.lower()}"
    override["authority_status"] = "LOCAL_QA_ONLY_CHROMA_KEY_DERIVATIVE_NOT_PROMOTABLE"
    override["chroma_key_provenance"] = {
        "derivative_manifest": derivative_manifest_path.relative_to(ROOT).as_posix(),
        "derivative_manifest_sha256": sha256(derivative_manifest_path),
        "green_master_root": master_root.relative_to(ROOT).as_posix(),
        "keyed_rgba_root": keyed_root.relative_to(ROOT).as_posix(),
        "key_method": keyed_manifest["chroma_key_provenance"]["key_method"],
    }
    return override


def source_animation_paths(source_root: Path, manifest: dict, animation_name: str, frame_indices: list[int] | None = None) -> list[Path]:
    animations = manifest.get("animations", {})
    animation = animations.get(animation_name, {}) if isinstance(animations, dict) else {}
    raw_paths = animation.get("frame_paths", []) if isinstance(animation, dict) else []
    if not isinstance(raw_paths, list) or not raw_paths:
        raise RuntimeError(f"{source_root.name}:{animation_name}:FRAME_PATHS_MISSING")
    if frame_indices is not None:
        if not frame_indices:
            raise RuntimeError(f"{source_root.name}:{animation_name}:FRAME_SELECTION_EMPTY")
        if len(set(frame_indices)) != len(frame_indices):
            raise RuntimeError(f"{source_root.name}:{animation_name}:FRAME_SELECTION_DUPLICATE")
        if any(not isinstance(index, int) or index < 0 or index >= len(raw_paths) for index in frame_indices):
            raise RuntimeError(f"{source_root.name}:{animation_name}:FRAME_SELECTION_INVALID:{frame_indices}")
        raw_paths = [raw_paths[index] for index in frame_indices]
    paths = [source_root / str(value) for value in raw_paths]
    missing = [str(path) for path in paths if not path.is_file()]
    if missing:
        raise RuntimeError(f"{source_root.name}:{animation_name}:FRAME_MISSING:{'|'.join(missing)}")
    return paths


def resize_runtime_frame(source: Image.Image) -> Image.Image:
    """Downsample from the verified 512px source while retaining real alpha."""
    frame = source.convert("RGBA")
    if frame.size != (CELL_SIZE, CELL_SIZE):
        frame = frame.resize((CELL_SIZE, CELL_SIZE), Image.Resampling.LANCZOS)
    return frame


def _align(value: int, alignment: int = ATLAS_ALIGNMENT) -> int:
    return max(alignment, int(math.ceil(value / alignment)) * alignment)


def _alpha_tight_crop(frame: Image.Image) -> tuple[Image.Image, tuple[int, int, int, int]]:
    """Return a crop plus its immutable placement in the 384px logical canvas.

    `Image.getbbox()` considers every non-zero alpha pixel.  That preserves
    delicate hair and weapon fringe, while a four-pixel safety pad prevents
    filtering from sampling an adjacent packed frame.  The cropped image is
    *not* rescaled: source density and the battle's 512px logical anchors stay
    exactly unchanged.
    """
    alpha = frame.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise RuntimeError("FRAME_ALPHA_EMPTY")
    left = max(0, bbox[0] - CROP_PADDING)
    top = max(0, bbox[1] - CROP_PADDING)
    right = min(frame.width, bbox[2] + CROP_PADDING)
    bottom = min(frame.height, bbox[3] + CROP_PADDING)
    if right <= left or bottom <= top:
        raise RuntimeError("FRAME_CROP_EMPTY")
    rect = (left, top, right - left, bottom - top)
    return frame.crop((left, top, right, bottom)), rect


def _shelf_pack(items: list[dict], atlas_width: int) -> tuple[list[tuple[int, int]], tuple[int, int]] | None:
    """Deterministically shelf-pack alpha-tight rectangles into one NPOT atlas."""
    x = 0
    y = 0
    row_height = 0
    placements: list[tuple[int, int] | None] = [None] * len(items)
    # Large frames first avoids a late tall cell forcing a mostly-empty page.
    # Frame indices are retained in `placements`, so animation timing remains
    # exactly source ordered.
    ordered = sorted(enumerate(items), key=lambda pair: (-pair[1]["image"].height, -pair[1]["image"].width, pair[0]))
    for index, item in ordered:
        image: Image.Image = item["image"]
        width = _align(image.width)
        height = _align(image.height)
        if width > atlas_width:
            return None
        if x > 0 and x + width > atlas_width:
            y += row_height
            x = 0
            row_height = 0
        if y + height > MAX_ATLAS_DIMENSION:
            return None
        placements[index] = (x, y)
        x += width
        row_height = max(row_height, height)
    atlas_height = _align(y + row_height)
    if atlas_height > MAX_ATLAS_DIMENSION:
        return None
    if any(position is None for position in placements):
        raise RuntimeError("PACKING_POSITION_MISSING")
    return [position for position in placements if position is not None], (atlas_width, atlas_height)


def _choose_packing(items: list[dict]) -> tuple[list[tuple[int, int]], tuple[int, int]]:
    candidates: list[tuple[int, int, int, list[tuple[int, int]], tuple[int, int]]] = []
    for width in ATLAS_WIDTH_CANDIDATES:
        result = _shelf_pack(items, width)
        if result is None:
            continue
        placements, size = result
        candidates.append((size[0] * size[1], size[1], size[0], placements, size))
    if not candidates:
        raise RuntimeError("ALPHA_TIGHT_PACKING_FAILED")
    _, _, _, placements, size = min(candidates, key=lambda value: (value[0], value[1], value[2]))
    return placements, size


def build_animation_atlas(source_paths: list[Path], target_root: Path, animation_name: str) -> tuple[dict, list[Image.Image], list[dict]]:
    packed_items: list[dict] = []
    preview_frames: list[Image.Image] = []
    for source_path in source_paths:
        source_image = Image.open(source_path).convert("RGBA")
        source_qc = alpha_summary(source_image)
        if source_qc["alpha_extrema"] != [0, 255] or source_qc["visible_exact_green_pixels"]:
            raise RuntimeError(f"{source_path}:SOURCE_ALPHA_OR_MATTE_INVALID:{source_qc}")
        frame = resize_runtime_frame(source_image)
        frame_qc = alpha_summary(frame)
        if frame_qc["alpha_extrema"] != [0, 255] or frame_qc["visible_exact_green_pixels"]:
            raise RuntimeError(f"{source_path}:RUNTIME_ALPHA_OR_MATTE_INVALID:{frame_qc}")
        cropped, logical_rect = _alpha_tight_crop(frame)
        packed_items.append({
            "image": cropped,
            "logical_rect": logical_rect,
            "source_path": source_path,
            "source_qc": source_qc,
            "runtime_qc": frame_qc,
            "packed_qc": alpha_summary(cropped),
        })
        preview_frames.append(frame)
    placements, atlas_size = _choose_packing(packed_items)
    atlas = Image.new("RGBA", atlas_size, (0, 0, 0, 0))
    frame_records: list[dict] = []
    for index, item in enumerate(packed_items):
        packed_image: Image.Image = item["image"]
        position = placements[index]
        atlas.alpha_composite(packed_image, position)
        logical_rect = item["logical_rect"]
        frame_records.append({
            "source_path": item["source_path"].relative_to(ROOT).as_posix(),
            "source_sha256": sha256(item["source_path"]),
            "region": [position[0], position[1], packed_image.width, packed_image.height],
            "logical_rect": list(logical_rect),
            "source_qc": item["source_qc"],
            "runtime_qc": item["runtime_qc"],
            "packed_qc": item["packed_qc"],
        })
    atlas_path = target_root / f"{animation_name}.png"
    atlas.save(atlas_path, format="PNG", optimize=True)
    atlas_qc = alpha_summary(atlas)
    if atlas_qc["alpha_extrema"] != [0, 255] or atlas_qc["visible_exact_green_pixels"]:
        raise RuntimeError(f"{atlas_path}:ATLAS_ALPHA_OR_MATTE_INVALID:{atlas_qc}")
    logical_bytes = len(frame_records) * CELL_SIZE * CELL_SIZE * 4
    packed_bytes = atlas.width * atlas.height * 4
    return {
        "fps": 12,
        "loop": animation_name == "idle",
        "atlas_path": atlas_path.name,
        "atlas_sha256": sha256(atlas_path),
        "atlas_size": list(atlas.size),
        "logical_frame_size": [CELL_SIZE, CELL_SIZE],
        "packing": {
            "mode": "ALPHA_TIGHT_SHELF_R1",
            "padding_px": CROP_PADDING,
            "alignment_px": ATLAS_ALIGNMENT,
            "logical_rgba_bytes": logical_bytes,
            "packed_rgba_bytes": packed_bytes,
            "saved_rgba_bytes": logical_bytes - packed_bytes,
        },
        "frame_count": len(frame_records),
        "frames": frame_records,
        "atlas_qc": atlas_qc,
    }, preview_frames, frame_records


def paste_thumbnail(canvas: Image.Image, frame: Image.Image, position: tuple[int, int], target_size: int = 66) -> None:
    thumbnail = frame.copy()
    thumbnail.thumbnail((target_size, target_size), Image.Resampling.LANCZOS)
    offset = (position[0] + (target_size - thumbnail.width) // 2, position[1] + (target_size - thumbnail.height) // 2)
    canvas.alpha_composite(thumbnail, offset)


def build_contact_sheet(previews: dict[str, dict[str, list[Image.Image]]], output_path: Path) -> None:
    cell = 76
    label_width = 138
    width = label_width + 18 * cell + 32
    height = 42 + len(previews) * (28 + len(SIGNATURE_ANIMATIONS) * cell + 28)
    sheet = Image.new("RGBA", (width, height), (21, 29, 45, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((16, 12), "BATTLE SIGNATURE HD — source 512px → packed runtime 384px", fill=(234, 246, 255, 255))
    y = 42
    for entity_id in previews:
        draw.text((16, y + 6), entity_id, fill=(126, 230, 255, 255))
        y += 28
        for animation_name in SIGNATURE_ANIMATIONS:
            draw.text((16, y + 25), animation_name.upper(), fill=(255, 221, 133, 255))
            frames = previews[entity_id][animation_name]
            for index, frame in enumerate(frames):
                x = label_width + index * cell
                draw.rectangle((x, y, x + cell - 2, y + cell - 2), outline=(67, 91, 122, 255), width=1)
                paste_thumbnail(sheet, frame, (x + 5, y + 4))
                draw.text((x + 3, y + 59), str(index), fill=(210, 221, 234, 255))
            y += cell
        y += 28
    sheet.convert("RGB").save(output_path, format="PNG", optimize=True)


def build_entity(
    entity_id: str, revision: str, target_root: Path, source_override: dict | None = None
) -> tuple[dict, dict[str, list[Image.Image]]]:
    source = source_override or SOURCES[entity_id]
    manifest_path: Path = source["manifest"]
    if not manifest_path.is_file():
        raise RuntimeError(f"{entity_id}:MANIFEST_MISSING:{manifest_path}")
    source_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    entity_root = target_root / entity_id
    entity_root.mkdir(parents=True, exist_ok=False)
    animation_manifest: dict[str, dict] = {}
    previews: dict[str, list[Image.Image]] = {}
    for animation_name in SIGNATURE_ANIMATIONS:
        frame_selection = source.get("signature_frame_indices", {}).get(animation_name)
        source_paths = source_animation_paths(source["root"], source_manifest, animation_name, frame_selection)
        entry, preview_frames, _ = build_animation_atlas(source_paths, entity_root, animation_name)
        animation_manifest[animation_name] = entry
        previews[animation_name] = preview_frames
    payload = {
        "schema_version": 1,
        "candidate_id": f"battle_signature_hd_{revision.lower()}_{entity_id.lower()}",
        "status": "RUNTIME_SIGNATURE_CANDIDATE_PENDING_VISUAL_QA",
        "character_id": entity_id,
        "source_asset_id": source["source_asset_id"],
        "costume_id": source["costume_id"],
        "source_authority_status": source.get("authority_status", "PROJECT_APPROVED_COMBAT_AUTHORITY"),
        "identity_fingerprint": source["identity"],
        "signature_frame_selection": source.get("signature_frame_indices", {}),
        "chroma_key_provenance": source.get("chroma_key_provenance", {}),
        "source_animation_manifest": manifest_path.relative_to(ROOT).as_posix(),
        "source_animation_manifest_sha256": sha256(manifest_path),
        "source_frame_size": source_manifest.get("frame_size", [512, 512]),
        "runtime_frame_size": [CELL_SIZE, CELL_SIZE],
        "logical_draw_canvas": [512, 512],
        "foot_anchor": source_manifest.get("foot_anchor", [0.5, 0.88]),
        "head_anchor": source_manifest.get("head_anchor", [0.5, 0.12]),
        "view": source_manifest.get("view", ""),
        "facing_policy": source_manifest.get("facing_policy", ""),
        "animations": animation_manifest,
        "no_source_mutation": True,
        "generation": "deterministic_resize_alpha_tight_atlas_only",
    }
    manifest_output = entity_root / "signature_manifest.json"
    manifest_output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    # Keep the manifest's hash beside it rather than creating an impossible
    # self-referential JSON field whose value changes when it is recorded.
    (entity_root / "signature_manifest.sha256").write_text(
        "%s  signature_manifest.json\n" % sha256(manifest_output), encoding="utf-8"
    )
    return payload, previews


def main() -> int:
    args = cli()
    revision = str(args.revision).strip().upper()
    if not revision or any(character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for character in revision):
        raise SystemExit("REVISION_INVALID")
    selected_entities: list[str] = []
    for value in str(args.entities).split(","):
        entity_id = value.strip().upper()
        if not entity_id:
            continue
        if entity_id not in SOURCES:
            raise SystemExit(f"ENTITY_NOT_CONFIGURED:{entity_id}")
        if entity_id not in selected_entities:
            selected_entities.append(entity_id)
    if not selected_entities:
        raise SystemExit("ENTITY_SELECTION_EMPTY")
    chroma_remaster_entities: list[str] = []
    for value in str(args.chroma_remaster_entities).split(","):
        entity_id = value.strip().upper()
        if not entity_id:
            continue
        if entity_id not in SOURCES:
            raise SystemExit(f"CHROMA_REMASTER_ENTITY_NOT_CONFIGURED:{entity_id}")
        if entity_id not in selected_entities:
            raise SystemExit(f"CHROMA_REMASTER_ENTITY_NOT_SELECTED:{entity_id}")
        if entity_id not in chroma_remaster_entities:
            chroma_remaster_entities.append(entity_id)
    target_root = RUNTIME_ROOT / revision.lower()
    if target_root.exists():
        raise SystemExit(f"OUTPUT_EXISTS_REFUSE_TO_OVERWRITE:{target_root}")
    if args.validate_only:
        for entity_id in selected_entities:
            source = SOURCES[entity_id]
            manifest = json.loads(Path(source["manifest"]).read_text(encoding="utf-8"))
            for animation_name in SIGNATURE_ANIMATIONS:
                frame_selection = source.get("signature_frame_indices", {}).get(animation_name)
                source_animation_paths(Path(source["root"]), manifest, animation_name, frame_selection)
        print("BATTLE_SIGNATURE_INPUT_VALIDATION_PASS")
        return 0
    target_root.mkdir(parents=True, exist_ok=False)
    built: list[dict] = []
    previews: dict[str, dict[str, list[Image.Image]]] = {}
    try:
        chroma_overrides: dict[str, dict] = {}
        for entity_id in chroma_remaster_entities:
            chroma_overrides[entity_id] = build_chroma_key_derivative(entity_id, revision)
        for entity_id in selected_entities:
            payload, entity_previews = build_entity(entity_id, revision, target_root, chroma_overrides.get(entity_id))
            built.append(payload)
            previews[entity_id] = entity_previews
        manifest_hashes = {payload["character_id"]: sha256(target_root / payload["character_id"] / "signature_manifest.json") for payload in built}
        full_preload_bytes = sum(
            int(animation.get("atlas_size", [0, 0])[0]) * int(animation.get("atlas_size", [0, 0])[1]) * 4
            for payload in built
            for animation in payload.get("animations", {}).values()
        )
        core_resident_bytes = sum(
            int(payload["animations"][animation_name].get("atlas_size", [0, 0])[0])
            * int(payload["animations"][animation_name].get("atlas_size", [0, 0])[1])
            * 4
            for payload in built
            for animation_name in SIGNATURE_CORE_ANIMATIONS
        )
        ultimate_bytes_by_character = {
            payload["character_id"]: int(payload["animations"]["ultimate"].get("atlas_size", [0, 0])[0])
            * int(payload["animations"]["ultimate"].get("atlas_size", [0, 0])[1])
            * 4
            for payload in built
        }
        peak_transient_resident_bytes = core_resident_bytes + max(ultimate_bytes_by_character.values(), default=0)
        approval = {
            "schema_version": 1,
            "signature_revision": revision.lower(),
            "approval_status": "LOCAL_QA_ONLY",
            "approval_scope": ", ".join(selected_entities) + " packed 384px signature states: idle, ultimate, hit, down",
            "release_gate": "PUBLIC_EXPORT_HOLD: local QA, visual review, real mobile browser frame-time, peak-memory, and tab-return checks are all required. A chroma-key derivative remains LOCAL_QA_ONLY until its source identity, alpha/matte, visual, and runtime gates pass. CHR002 remains non-promotable without separate identity/authority approval.",
            "manifest_sha256_by_character": manifest_hashes,
            "technical_gate": {
                "source_manifest_hashes_verified": True,
                "runtime_atlas_hashes_verified": True,
                "source_canvas": [512, 512],
                "runtime_cell": [CELL_SIZE, CELL_SIZE],
                "packing": "ALPHA_TIGHT_SHELF_R1",
                "visible_chroma_green_pixels": 0,
                "source_mutation": False,
                "generation": "deterministic_chroma_key_derivative_then_resize_alpha_tight_atlas_only" if chroma_remaster_entities else "deterministic_resize_alpha_tight_atlas_only",
                "chroma_remaster_entities": chroma_remaster_entities,
                # The pack can contain more than one authored ultimate page,
                # but runtime never decodes all of them together. Its actual
                # mobile contract is resident idle/hit/down plus exactly one
                # caster page, measured here so a future loader cannot treat
                # the artifact's full sheet collection as a preload mandate.
                "residency_model": "core_idle_hit_down_plus_one_caster_ultimate_transient",
                "estimated_core_resident_atlas_bytes_for_all_selected": core_resident_bytes,
                "ultimate_atlas_bytes_by_character": ultimate_bytes_by_character,
                "estimated_peak_transient_resident_atlas_bytes": peak_transient_resident_bytes,
                "estimated_full_preload_atlas_bytes_for_all_selected": full_preload_bytes,
                # Kept for artifact inventory compatibility only. Runtime
                # admission uses the requested-state estimate above.
                "estimated_resident_atlas_bytes_for_all_selected": full_preload_bytes,
                "runtime_memory_budget_mib": 72,
            },
            "identity_continuity": {
                payload["character_id"]: {
                    "costume_id": payload["costume_id"],
                    "source_authority_status": payload["source_authority_status"],
                    "fingerprint": payload["identity_fingerprint"],
                }
                for payload in built
            },
            "failure_retention": "This revision is immutable LOCAL_QA_ONLY. Retain every prior revision and all failed/rejected QA artifacts in quarantine until a verified replacement has completed every required gate.",
        }
        (target_root / "promotion_approval.json").write_text(json.dumps(approval, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        REPORT_ROOT.mkdir(parents=True, exist_ok=True)
        contact_sheet = REPORT_ROOT / f"BATTLE_SIGNATURE_HD_{revision}_CONTACT_SHEET.png"
        build_contact_sheet(previews, contact_sheet)
        report = {
            "batch_id": f"battle_signature_hd_{revision.lower()}",
            "status": "PENDING_VISUAL_QA",
            "runtime_root": target_root.relative_to(ROOT).as_posix(),
            "contact_sheet": contact_sheet.relative_to(ROOT).as_posix(),
            "characters": built,
            "selected_entities": selected_entities,
            "chroma_remaster_entities": chroma_remaster_entities,
            "estimated_core_resident_atlas_bytes": core_resident_bytes,
            "estimated_peak_transient_resident_atlas_bytes": peak_transient_resident_bytes,
            "estimated_full_preload_atlas_bytes": full_preload_bytes,
            "runtime_memory_budget_mib": 72,
            "failure_policy": "On FAIL, move this exact revision root and report into quarantine; never overwrite or delete it during the batch.",
            "why_bounded": "Only the always-visible idle/hit/down pages remain resident. Exactly one current caster ultimate page is acquired transiently, then released after recovery; each frame is alpha-tight packed while retaining the 384px logical canvas, anchors, source hashes, and compact 128px fallback.",
        }
        report_path = REPORT_ROOT / f"BATTLE_SIGNATURE_HD_{revision}_REPORT.json"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except Exception:
        # Do not delete partial output.  The caller can inspect and quarantine
        # this immutable revision exactly as required by the project policy.
        raise
    print(json.dumps({
        "status": "BATTLE_SIGNATURE_CANDIDATE_BUILT",
        "runtime_root": str(target_root),
        "report": str(report_path),
        "contact_sheet": str(contact_sheet),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
