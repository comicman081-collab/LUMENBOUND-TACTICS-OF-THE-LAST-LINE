#!/usr/bin/env python3
"""Incrementally syncs validated local asset-factory exports into Godot.

No network access. PNG inspection uses the standard library only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import struct
from pathlib import Path


HERE = Path(__file__).resolve().parent


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def png_info(path: Path) -> dict:
    with path.open("rb") as stream:
        header = stream.read(33)
    if len(header) < 33 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError("invalid PNG signature/IHDR")
    width, height, bit_depth, color_type = struct.unpack(">IIBB", header[16:26])
    return {"width": width, "height": height, "bit_depth": bit_depth, "color_type": color_type, "has_alpha": color_type in (4, 6)}


def version_key(asset_id: str) -> tuple[str, int]:
    match = re.match(r"^(.*)\.v(\d+)$", asset_id)
    return (match.group(1), int(match.group(2))) if match else (asset_id, 0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    config = json.loads((HERE / "asset_bridge_config.json").read_text(encoding="utf-8"))
    source_text = os.environ.get(config["source_root_env"], config["source_root"])
    source = Path(source_text)
    destination = (HERE / config["destination_root"]).resolve()
    if not source.is_dir():
        print(json.dumps({"ok": False, "error": "source root missing", "path": str(source)}, ensure_ascii=False))
        return 2
    manifest_files = sorted((source / "manifests").rglob("*.manifest.json"))
    required = set(config["required_manifest_fields"])
    parsed = []
    errors = []
    for path in manifest_files:
        try:
            manifest = json.loads(path.read_text(encoding="utf-8"))
            missing = sorted(required - set(manifest))
            if missing:
                errors.append(f"{path}: missing {missing}")
                continue
            if manifest["category"] in config["categories"]:
                parsed.append((path, manifest))
        except Exception as exc:
            errors.append(f"{path}: {exc}")
    if errors:
        print(json.dumps({"ok": False, "manifest_errors": errors[:50], "count": len(errors)}, ensure_ascii=False, indent=2))
        return 3

    if config.get("latest_version_only", True):
        latest = {}
        for path, manifest in parsed:
            family, version = version_key(manifest["assetId"])
            if family not in latest or version > latest[family][0]:
                latest[family] = (version, path, manifest)
        parsed = [(row[1], row[2]) for row in latest.values()]

    assets = []
    licenses = []
    copied = skipped = 0
    for manifest_path, manifest in sorted(parsed, key=lambda row: row[1]["assetId"]):
        for relative in manifest["exportPaths"]:
            if not any(relative.endswith(ext) for ext in config["allowed_extensions"]):
                continue
            source_file = source / relative
            if not source_file.is_file():
                errors.append(f"{manifest['assetId']}: missing export {relative}")
                continue
            actual_hash = sha256(source_file)
            expected_hash = manifest.get("outputSha256", {}).get(relative, "")
            if expected_hash and expected_hash != actual_hash:
                errors.append(f"{manifest['assetId']}: SHA mismatch {relative}")
                continue
            plural = {"enemy": "enemies"}.get(manifest["category"], manifest["category"] + "s")
            target_relative = Path("factory_sync") / Path(plural) / Path(relative).name
            target = destination / target_relative
            metadata = {}
            if source_file.suffix.lower() == ".png":
                try:
                    metadata = png_info(source_file)
                    if metadata["width"] <= 0 or metadata["height"] <= 0:
                        raise ValueError("invalid dimensions")
                except Exception as exc:
                    errors.append(f"{manifest['assetId']}: {relative}: {exc}")
                    continue
            same = target.is_file() and sha256(target) == actual_hash
            if same:
                skipped += 1
            else:
                copied += 1
                if not args.dry_run:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source_file, target)
            godot_path = config.get("godot_path_prefix", "res://assets/generated_import/") + target_relative.as_posix()
            asset_key = manifest["assetId"] + ":" + Path(relative).stem
            assets.append({
                "asset_id": asset_key,
                "source_asset_id": manifest["assetId"],
                "category": manifest["category"],
                "subtype": manifest["subtype"],
                "generator_version": manifest["generatorVersion"],
                "source_preset": manifest["sourcePreset"],
                "source_manifest": str(manifest_path.relative_to(source)).replace("\\", "/"),
                "source_export": relative,
                "godot_path": godot_path,
                "sha256": actual_hash,
                "status": config["mark_as"],
                "image": metadata,
            })
            licenses.append({
                "asset_id": asset_key,
                "source": f"local asset_share/{relative}",
                "author": "Asset Share Procedural Factory (local project)",
                "license": "MANIFEST_NOT_DECLARED",
                "modification": "incremental copy; no visual modification",
                "commercial_use": False,
                "attribution_required": True,
                "file_sha256": actual_hash,
                "note": "Factory code is MIT, but output asset rights require project-owner confirmation before commercial release.",
            })

    result = {
        "schema_version": 1,
        "factory": {"name": "asset-share-procedural-factory", "version": "0.1.0", "generator_versions": sorted({m["generatorVersion"] for _, m in parsed})},
        "status": "SYNCED_WITH_ERRORS" if errors else "SYNCED",
        "assets": assets,
        "stats": {"manifests_scanned": len(manifest_files), "latest_selected": len(parsed), "files": len(assets), "copied": copied, "unchanged": skipped, "errors": len(errors)},
        "errors": errors,
    }
    if not args.dry_run:
        destination.mkdir(parents=True, exist_ok=True)

        # Merge project-generated runtime packs into the license ledger without
        # pretending that DEV assets have production/commercial approval.
        local_patterns = (
            "characters/*/animation_manifest.json",
            "enemies/*/animation_manifest.json",
            "projectiles/*/projectile_manifest.json",
        )
        for pattern in local_patterns:
            for local_manifest in sorted(destination.glob(pattern)):
                try:
                    local_data = json.loads(local_manifest.read_text(encoding="utf-8"))
                except Exception as exc:
                    errors.append(f"{local_manifest}: {exc}")
                    continue
                licenses.append({
                    "asset_id": local_data.get("asset_id", local_manifest.parent.name),
                    "source": local_data.get("source", "project-local deterministic build pipeline"),
                    "author": "SD Story RPG local asset pipeline",
                    "license": "PROJECT_GENERATED_DEV_REVIEW_REQUIRED",
                    "modification": "cutout-rig animation derivation or locally rendered projectile frames",
                    "commercial_use": False,
                    "attribution_required": False,
                    "file_sha256": sha256(local_manifest),
                    "source_sha256": local_data.get("source_sha256", ""),
                    "note": "DEV asset bundle; production art and legal approval are not claimed.",
                })

        font_path = destination.parent / "fonts" / "NotoSansKR-VF.ttf"
        if font_path.is_file():
            licenses.append({
                "asset_id": "font_noto_sans_kr_vf",
                "source": "Google Noto Fonts project",
                "author": "Noto project authors",
                "license": "SIL_OPEN_FONT_LICENSE_1_1",
                "modification": "unmodified bundled font file",
                "commercial_use": True,
                "attribution_required": True,
                "file_sha256": sha256(font_path),
                "note": "See res://assets/fonts/LICENSE_OFL.txt.",
            })

        (destination / "import_manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (destination / "licenses.json").write_text(json.dumps({"schema_version": 1, "assets": licenses}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        attribution = ["# Attribution (DEV)", "", "All synchronized images are marked DEV_PLACEHOLDER.", "", "| Asset | Source | License status | SHA-256 |", "|---|---|---|---|"]
        attribution += [f"| {x['asset_id']} | {x['source']} | {x['license']} | `{x['file_sha256']}` |" for x in licenses]
        (destination / "attribution.md").write_text("\n".join(attribution) + "\n", encoding="utf-8")
    print(json.dumps(result["stats"] | {"ok": not errors, "dry_run": args.dry_run}, ensure_ascii=False))
    return 4 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
