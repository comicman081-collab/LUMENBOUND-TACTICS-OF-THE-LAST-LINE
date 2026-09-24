#!/usr/bin/env python3
"""Build a bounded high-density effect candidate from shipped project art.

This is a deterministic Lanczos derivative of the project's compact Web
projectile and ultimate VFX atlases. It does not generate art, alter the source
atlases, or replace them. Every output is written to a fresh immutable
candidate directory and records source/output hashes for review. A failure
never deletes partial output: it must remain available for quarantine under the
global failed-asset policy.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "godot"
RUNTIME = GODOT / "assets" / "runtime_web"
OUTPUT_ROOT = RUNTIME / "effect_signature"
REPORT_ROOT = ROOT / "reports" / "art_qa"

# Every default-party member except the deliberately borrowed CHR002 profile
# has an authored projectile and ultimate source. CHR002 still intentionally
# borrows CHR001 at runtime, so it does not create a duplicate profile here.
ENTITIES = ("CHR001", "CHR003", "CHR004", "CHR005", "CHR008", "BOSS001", "ENM001")
PROJECTILE_SOURCE_FRAME = (96, 96)
ULTIMATE_SOURCE_FRAME = (112, 112)
MIN_SCALE = 1.1
MAX_SCALE = 2.0


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", default="R1", help="new immutable revision, e.g. R1")
    parser.add_argument(
        "--entities",
        default=",".join(ENTITIES),
        help="comma-separated VFX profiles; defaults to the current local-QA group",
    )
    parser.add_argument(
        "--scale",
        type=float,
        default=2.0,
        help="Lanczos scale per effect frame (1.1 through 2.0); choose a bounded value for mobile residency",
    )
    parser.add_argument("--validate-only", action="store_true")
    return parser.parse_args()


def exact_visible_green_pixels(image: Image.Image) -> int:
    return sum(
        1
        for red, green, blue, alpha in image.convert("RGBA").getdata()
        if alpha > 24 and green >= 245 and red <= 20 and blue <= 20
    )


def alpha_qc(image: Image.Image) -> dict:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    extrema = alpha.getextrema()
    bbox = alpha.point(lambda value: 255 if value > 18 else 0).getbbox()
    return {
        "alpha_extrema": [int(extrema[0]), int(extrema[1])],
        "alpha_bounds": list(bbox) if bbox else None,
        "visible_exact_green_pixels": exact_visible_green_pixels(rgba),
    }


def load_json(path: Path) -> dict:
    parsed = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(parsed, dict):
        raise RuntimeError(f"JSON_OBJECT_REQUIRED:{path}")
    return parsed


def source_definition(entity_id: str) -> tuple[Path, dict, Path, dict]:
    projectile_root = RUNTIME / "projectiles" / entity_id
    projectile_manifest_path = projectile_root / "projectile_manifest.json"
    projectile_manifest = load_json(projectile_manifest_path)
    if projectile_manifest.get("source_id") != entity_id:
        raise RuntimeError(f"PROJECTILE_SOURCE_ID_MISMATCH:{entity_id}")
    vfx_root = RUNTIME / "vfx" / f"vfx_{entity_id.lower()}_ultimate"
    vfx_manifest_path = vfx_root / "vfx_manifest.json"
    vfx_manifest = load_json(vfx_manifest_path)
    if vfx_manifest.get("entity_id") != entity_id or vfx_manifest.get("kind") != "ultimate":
        raise RuntimeError(f"ULTIMATE_VFX_ID_MISMATCH:{entity_id}")
    return projectile_root, projectile_manifest, vfx_root, vfx_manifest


def validate_source(entity_id: str) -> None:
    projectile_root, projectile_manifest, vfx_root, vfx_manifest = source_definition(entity_id)
    if tuple(projectile_manifest.get("frame_size", [])) != PROJECTILE_SOURCE_FRAME:
        raise RuntimeError(f"PROJECTILE_SOURCE_FRAME_INVALID:{entity_id}")
    if int(projectile_manifest.get("frames", 0)) != 8 or int(projectile_manifest.get("atlas_columns", 0)) != 8:
        raise RuntimeError(f"PROJECTILE_SOURCE_LAYOUT_INVALID:{entity_id}")
    if int(vfx_manifest.get("frames", 0)) != 12 or int(vfx_manifest.get("columns", 0)) != 4:
        raise RuntimeError(f"ULTIMATE_SOURCE_LAYOUT_INVALID:{entity_id}")
    projectile_atlas = projectile_root / str(projectile_manifest.get("atlas_path", ""))
    ultimate_atlas = vfx_root / "atlas.png"
    if not projectile_atlas.is_file() or not ultimate_atlas.is_file():
        raise RuntimeError(f"SOURCE_ATLAS_MISSING:{entity_id}")
    projectile_image = Image.open(projectile_atlas).convert("RGBA")
    ultimate_image = Image.open(ultimate_atlas).convert("RGBA")
    if projectile_image.size != (PROJECTILE_SOURCE_FRAME[0] * 8, PROJECTILE_SOURCE_FRAME[1]):
        raise RuntimeError(f"PROJECTILE_SOURCE_ATLAS_DIMENSIONS_INVALID:{entity_id}:{projectile_image.size}")
    if ultimate_image.size != (ULTIMATE_SOURCE_FRAME[0] * 4, ULTIMATE_SOURCE_FRAME[1] * 3):
        raise RuntimeError(f"ULTIMATE_SOURCE_ATLAS_DIMENSIONS_INVALID:{entity_id}:{ultimate_image.size}")
    for label, image in (("projectile", projectile_image), ("ultimate", ultimate_image)):
        if exact_visible_green_pixels(image):
            raise RuntimeError(f"SOURCE_VISIBLE_GREEN_MATTE:{entity_id}:{label}")


def runtime_frame_size(source_frame: tuple[int, int], scale: float) -> tuple[int, int]:
    return max(1, round(source_frame[0] * scale)), max(1, round(source_frame[1] * scale))


def upscale_atlas(source_path: Path, target_path: Path, expected_source_size: tuple[int, int], target_size: tuple[int, int]) -> dict:
    source = Image.open(source_path).convert("RGBA")
    if source.size != expected_source_size:
        raise RuntimeError(f"SOURCE_DIMENSIONS_CHANGED:{source_path}:{source.size}!={expected_source_size}")
    source_qc = alpha_qc(source)
    if source_qc["visible_exact_green_pixels"]:
        raise RuntimeError(f"SOURCE_VISIBLE_GREEN_MATTE:{source_path}")
    runtime = source.resize(target_size, Image.Resampling.LANCZOS)
    runtime_qc = alpha_qc(runtime)
    if runtime_qc["visible_exact_green_pixels"]:
        raise RuntimeError(f"RUNTIME_VISIBLE_GREEN_MATTE:{target_path}")
    runtime.save(target_path, format="PNG", optimize=True)
    return {
        "source_path": source_path.relative_to(ROOT).as_posix(),
        "source_sha256": sha256(source_path),
        "source_qc": source_qc,
        "atlas_path": target_path.name,
        "atlas_sha256": sha256(target_path),
        "atlas_size": [runtime.width, runtime.height],
        "runtime_qc": runtime_qc,
    }


def build_entity(entity_id: str, target_root: Path, scale: float) -> tuple[dict, Image.Image, Image.Image]:
    projectile_root, projectile_manifest, vfx_root, vfx_manifest = source_definition(entity_id)
    target = target_root / entity_id
    target.mkdir(parents=True, exist_ok=False)
    projectile_source = projectile_root / str(projectile_manifest["atlas_path"])
    ultimate_source = vfx_root / "atlas.png"
    projectile_frame = runtime_frame_size(PROJECTILE_SOURCE_FRAME, scale)
    ultimate_frame = runtime_frame_size(ULTIMATE_SOURCE_FRAME, scale)
    projectile = upscale_atlas(
        projectile_source,
        target / "projectile.png",
        (768, 96),
        (projectile_frame[0] * 8, projectile_frame[1]),
    )
    ultimate = upscale_atlas(
        ultimate_source,
        target / "ultimate.png",
        (448, 336),
        (ultimate_frame[0] * 4, ultimate_frame[1] * 3),
    )
    source_draw_size = projectile_manifest.get("runtime_size", [96, 96])
    draw_size = [round(int(source_draw_size[0]) * 1.16), round(int(source_draw_size[1]) * 1.16)]
    projectile.update({
        "frame_size": list(projectile_frame),
        "frames": 8,
        "atlas_columns": 8,
        "frame_indices": list(range(8)),
        "flight_duration": float(projectile_manifest.get("flight_duration", .12)),
        "draw_size": draw_size,
    })
    ultimate.update({
        "frame_size": list(ultimate_frame),
        "frames": 12,
        "atlas_columns": 4,
        "frame_indices": list(range(12)),
        "source_vfx_manifest": (vfx_root / "vfx_manifest.json").relative_to(ROOT).as_posix(),
        "source_vfx_manifest_sha256": sha256(vfx_root / "vfx_manifest.json"),
        "motion_shape": str(vfx_manifest.get("motion_shape", "")),
        "primary": str(vfx_manifest.get("primary", "")),
        "secondary": str(vfx_manifest.get("secondary", "")),
    })
    payload = {
        "schema_version": 1,
        "candidate_id": f"battle_effect_signature_{target_root.name}_{entity_id.lower()}",
        "status": "RUNTIME_EFFECT_SIGNATURE_CANDIDATE_PENDING_VISUAL_QA",
        "entity_id": entity_id,
        "projectile": projectile,
        "ultimate": ultimate,
        "generation": "deterministic_lanczos_upscale_only",
        "scale_factor": scale,
        "no_source_mutation": True,
        "failure_policy": "If review fails, retain this exact candidate and all provenance under quarantine; do not overwrite or delete it during the batch.",
    }
    manifest_path = target / "effect_signature_manifest.json"
    manifest_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (target / "effect_signature_manifest.sha256").write_text(
        f"{sha256(manifest_path)}  effect_signature_manifest.json\n", encoding="utf-8"
    )
    return payload, Image.open(target / "projectile.png").convert("RGBA"), Image.open(target / "ultimate.png").convert("RGBA")


def thumbnail(image: Image.Image, limit: tuple[int, int]) -> Image.Image:
    value = image.copy()
    value.thumbnail(limit, Image.Resampling.LANCZOS)
    return value


def contact_sheet(
    rows: list[tuple[str, Image.Image, Image.Image]],
    output_path: Path,
    scale: float,
    projectile_frame: tuple[int, int],
    ultimate_frame: tuple[int, int],
) -> None:
    sheet = Image.new("RGBA", (980, 106 + len(rows) * 136), (13, 24, 42, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((20, 16), "BATTLE EFFECT SIGNATURE — bounded Lanczos upscale (LOCAL QA candidate)", fill=(225, 243, 255, 255))
    draw.text(
        (20, 47),
        "Scale %.2fx | Projectile: 96px → %dpx    Ultimate VFX: 112px → %dpx" % (scale, projectile_frame[0], ultimate_frame[0]),
        fill=(147, 207, 237, 255),
    )
    for row_index, (entity_id, projectile, ultimate) in enumerate(rows):
        y = 86 + row_index * 136
        draw.rectangle((16, y, 964, y + 116), outline=(57, 103, 141, 255), width=1)
        draw.text((30, y + 16), entity_id, fill=(121, 230, 255, 255))
        projectile_preview = thumbnail(projectile, (330, 96))
        ultimate_preview = thumbnail(ultimate, (460, 108))
        sheet.alpha_composite(projectile_preview, (180, y + (116 - projectile_preview.height) // 2))
        sheet.alpha_composite(ultimate_preview, (490, y + (116 - ultimate_preview.height) // 2))
    sheet.convert("RGB").save(output_path, format="PNG", optimize=True)


def main() -> int:
    args = parse_args()
    revision = str(args.revision).strip().upper()
    if not revision or any(char not in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for char in revision):
        raise SystemExit("REVISION_INVALID")
    scale = float(args.scale)
    if not MIN_SCALE <= scale <= MAX_SCALE:
        raise SystemExit(f"SCALE_OUT_OF_RANGE:{scale}")
    selected_entities: list[str] = []
    for value in str(args.entities).split(","):
        entity_id = value.strip().upper()
        if not entity_id:
            continue
        if entity_id not in ENTITIES:
            raise SystemExit(f"ENTITY_NOT_CONFIGURED:{entity_id}")
        if entity_id not in selected_entities:
            selected_entities.append(entity_id)
    if not selected_entities:
        raise SystemExit("ENTITY_SELECTION_EMPTY")
    for entity_id in selected_entities:
        validate_source(entity_id)
    if args.validate_only:
        print("BATTLE_EFFECT_SIGNATURE_INPUT_VALIDATION_PASS")
        return 0
    target_root = OUTPUT_ROOT / revision.lower()
    if target_root.exists():
        raise SystemExit(f"OUTPUT_EXISTS_REFUSE_TO_OVERWRITE:{target_root}")
    target_root.mkdir(parents=True, exist_ok=False)
    built: list[dict] = []
    previews: list[tuple[str, Image.Image, Image.Image]] = []
    try:
        for entity_id in selected_entities:
            payload, projectile_preview, ultimate_preview = build_entity(entity_id, target_root, scale)
            built.append(payload)
            previews.append((entity_id, projectile_preview, ultimate_preview))
        manifest_hashes = {
            entry["entity_id"]: sha256(target_root / entry["entity_id"] / "effect_signature_manifest.json")
            for entry in built
        }
        full_preload_bytes = sum(
            int(effect["atlas_size"][0]) * int(effect["atlas_size"][1]) * 4
            for entry in built
            for effect in (entry["projectile"], entry["ultimate"])
        )
        core_resident_bytes = sum(
            int(entry["projectile"]["atlas_size"][0]) * int(entry["projectile"]["atlas_size"][1]) * 4
            for entry in built
        )
        ultimate_bytes_by_profile = {
            entry["entity_id"]: int(entry["ultimate"]["atlas_size"][0]) * int(entry["ultimate"]["atlas_size"][1]) * 4
            for entry in built
        }
        peak_transient_resident_bytes = core_resident_bytes + max(ultimate_bytes_by_profile.values(), default=0)
        approval = {
            "schema_version": 1,
            "effect_signature_revision": revision.lower(),
            "approval_status": "LOCAL_QA_ONLY",
            "manifest_sha256_by_entity": manifest_hashes,
            "technical_gate": {
                "runtime_memory_budget_mib": 12,
                "residency_model": "projectile_core_plus_one_caster_ultimate_transient",
                "estimated_core_resident_atlas_bytes_for_all_selected": core_resident_bytes,
                "ultimate_atlas_bytes_by_profile": ultimate_bytes_by_profile,
                "estimated_peak_transient_resident_atlas_bytes": peak_transient_resident_bytes,
                "estimated_full_preload_atlas_bytes_for_all_selected": full_preload_bytes,
                # Retain the legacy full inventory number for reports. It is
                # intentionally not the runtime preload contract.
                "estimated_resident_atlas_bytes_for_all_selected": full_preload_bytes,
                "selected_profiles": selected_entities,
                "scale_factor": scale,
                "projectile_runtime_frame": list(runtime_frame_size(PROJECTILE_SOURCE_FRAME, scale)),
                "ultimate_runtime_frame": list(runtime_frame_size(ULTIMATE_SOURCE_FRAME, scale)),
                "debug_only_candidate": True,
            },
            "review_gate": "Await real 390x844 viewport capture and the existing ChatGPT web planning-review reply before changing this candidate to APPROVED_FOR_RUNTIME.",
            "public_release_gate": "HOLD: no public export or deployment is authorized by this local QA record.",
        }
        (target_root / "promotion_approval.json").write_text(json.dumps(approval, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        REPORT_ROOT.mkdir(parents=True, exist_ok=True)
        sheet_path = REPORT_ROOT / f"BATTLE_EFFECT_SIGNATURE_{revision}_CONTACT_SHEET.png"
        contact_sheet(
            previews,
            sheet_path,
            scale,
            runtime_frame_size(PROJECTILE_SOURCE_FRAME, scale),
            runtime_frame_size(ULTIMATE_SOURCE_FRAME, scale),
        )
        report = {
            "batch_id": f"battle_effect_signature_{revision.lower()}",
            "status": "LOCAL_QA_ONLY",
            "runtime_root": target_root.relative_to(ROOT).as_posix(),
            "contact_sheet": sheet_path.relative_to(ROOT).as_posix(),
            "entities": built,
            "approval": approval,
            "why_bounded": "Projectile pages remain resident for the current high-density combat group, while one caster ultimate page is acquired transiently. The %.2fx scale is selected so that actual core-plus-one-page mobile residency remains inside 12MiB; compact atlases remain available as fallback." % scale,
            "failure_policy": "Do not delete this candidate if it fails review; quarantine it with its report, provenance and captures until a completed replacement passes every required gate.",
        }
        report_path = REPORT_ROOT / f"BATTLE_EFFECT_SIGNATURE_{revision}_REPORT.json"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except Exception:
        # Deliberately preserve partially built output for failure quarantine.
        raise
    print(json.dumps({
        "status": "BATTLE_EFFECT_SIGNATURE_CANDIDATE_BUILT",
        "runtime_root": str(target_root),
        "report": str(report_path),
        "contact_sheet": str(sheet_path),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
