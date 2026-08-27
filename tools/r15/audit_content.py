#!/usr/bin/env python3
"""R15 content-gap audit against actual source and runtime files.

The audit intentionally distinguishes a connected runtime atlas from a
premium, independently sourced asset.  It is a reporting tool only: it never
copies, deletes, or rewrites authoring assets.
"""
from __future__ import annotations

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "godot"
RUNTIME = GODOT / "assets" / "runtime_web"
REPORT = ROOT / "reports" / "r15" / "R15_CONTENT_GAP_MATRIX.csv"
RUNTIME_ASSET_MANIFEST = RUNTIME / "runtime_asset_manifest.json"

FIELDS = [
    "entity_id", "type", "illustration", "portrait", "icon", "sd_pack",
    "animation", "vfx", "map_pawn", "battle_integration", "story_integration",
    "stage_integration", "fallback_used", "qa_status",
]
EXPECTED_ANIMATIONS = {"idle": 8, "move": 12, "basic_attack": 8, "normal_skill": 12, "ultimate": 18, "hit": 4, "down": 8, "victory": 10}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def asset_state(path: Path, premium: bool = False) -> str:
    if not path.is_file():
        return "MISSING"
    return "COMPLETE" if premium else "PARTIAL"


def godot_path(value: str) -> Path:
    """Resolve a manifest res:// path without guessing a fallback path."""
    if not value.startswith("res://"):
        return Path()
    return GODOT / value.removeprefix("res://")


def runtime_asset_paths() -> dict[str, Path]:
    """Return stable asset IDs from the real Web runtime manifest.

    The old audit looked only at the legacy runtime card PNG.  That made a
    connected transparent portrait appear as a missing static asset even after
    the stable asset ID had been migrated.  Runtime IDs, rather than a filename
    convention, are the authoritative linkage here.
    """
    if not RUNTIME_ASSET_MANIFEST.is_file():
        return {}
    manifest = read_json(RUNTIME_ASSET_MANIFEST)
    return {
        str(entry.get("asset_id", "")): godot_path(str(entry.get("godot_path", "")))
        for entry in manifest.get("assets", [])
        if str(entry.get("asset_id", ""))
    }


def static_art(entity_id: str) -> tuple[str, str, str, str]:
    """Audit source-backed static art separately from its runtime mapping.

    Returns illustration, portrait, icon and a compact QA label.  A file only
    becomes COMPLETE after its explicit static-art manifest reports technical,
    visual and reference-parity PASS.  Existing but unreviewed source art is
    PARTIAL rather than silently promoted to final art.
    """
    directory = GODOT / "assets" / "art" / "characters" / entity_id
    manifests = sorted(directory.glob("*_STATIC_ART_*.manifest.json"))
    if not manifests:
        return "MISSING", "MISSING", "MISSING", "STATIC_MANIFEST_MISSING"
    manifest = read_json(manifests[-1])
    outputs = manifest.get("outputs", [])
    files_by_role: dict[str, Path] = {}
    for output in outputs:
        asset_id = str(output.get("asset_id", ""))
        path = godot_path(str(output.get("runtime_path", "")))
        if path.is_file():
            files_by_role[asset_id] = path
    illustration = any("illustration_master" in key or "fullbody" in key for key in files_by_role)
    portrait = any(key.startswith("portrait_") and not key.endswith("_runtime") for key in files_by_role)
    icon = any(key.startswith("icon_") and not key.endswith("_runtime") for key in files_by_role)
    qa = manifest.get("qa", {})
    technical = str(qa.get("technical", ""))
    visual = str(qa.get("visual", ""))
    parity = str(qa.get("reference_parity", ""))
    review_complete = technical.startswith("PASS") and visual.startswith("PASS") and parity.startswith("PASS")
    state = "COMPLETE" if review_complete else "PARTIAL"
    qa_label = "STATIC_%s/%s/%s" % (technical or "PENDING", visual or "PENDING", parity or "PENDING")
    return (state if illustration else "MISSING", state if portrait else "MISSING", state if icon else "MISSING", qa_label)


def combat_state(entity_id: str) -> tuple[str, str, bool]:
    manifest_path = RUNTIME / "combat" / entity_id / "animation_manifest.json"
    if not manifest_path.is_file():
        return "MISSING", "MISSING", True
    manifest = read_json(manifest_path)
    animations = manifest.get("animations", {})
    correct = all(len(animations.get(name, {}).get("frame_indices", [])) == frames for name, frames in EXPECTED_ANIMATIONS.items())
    status = str(manifest.get("status", ""))
    fallback = status == "RUNTIME_CARD_STATIC_PRESENTATION"
    return ("COMPLETE" if correct and not fallback else "PARTIAL"), status or "PARTIAL", fallback


def vfx_state(entity_id: str) -> str:
    return "COMPLETE" if all((RUNTIME / "vfx" / f"vfx_{entity_id.lower()}_{kind}" / "atlas.png").is_file() for kind in ("basic", "normal", "ultimate")) else "MISSING"


def main() -> int:
    characters = read_csv(ROOT / "data_source" / "characters.csv")
    enemies = read_csv(ROOT / "data_source" / "enemies.csv")
    stages = read_csv(ROOT / "data_source" / "stages.csv")
    scenarios = sorted((ROOT / "data_source" / "scenarios").glob("*.json"))
    runtime_assets = runtime_asset_paths()
    rows: list[dict[str, str]] = []
    for item in characters:
        entity_id = item["id"]
        illustration, authored_portrait, authored_icon, static_qa = static_art(entity_id)
        runtime_portrait = runtime_assets.get(f"portrait_{entity_id.lower()}_dev", Path())
        runtime_icon = runtime_assets.get(f"icon_{entity_id.lower()}_dev", Path())
        runtime_portrait_valid = runtime_portrait.is_file()
        runtime_icon_valid = runtime_icon.is_file()
        # A legacy generated card is never accepted as a static-art fallback
        # once the stable portrait/icon IDs have migrated to authored art.
        static_fallback = not (runtime_portrait_valid and runtime_icon_valid)
        sd, qa, combat_fallback = combat_state(entity_id)
        rows.append({
            "entity_id": entity_id, "type": "PLAYER",
            "illustration": illustration,
            "portrait": authored_portrait if runtime_portrait_valid else "MISSING",
            "icon": authored_icon if runtime_icon_valid else "MISSING", "sd_pack": sd,
            "animation": sd, "vfx": vfx_state(entity_id), "map_pawn": sd,
            "battle_integration": "COMPLETE" if sd != "MISSING" else "MISSING",
            "story_integration": "COMPLETE" if runtime_portrait_valid else "MISSING",
            "stage_integration": "COMPLETE", "fallback_used": str(static_fallback or combat_fallback).upper(),
            "qa_status": "%s; %s" % (static_qa, qa),
        })
    for item in enemies:
        entity_id = item["id"]
        sd, qa, fallback = combat_state(entity_id)
        rows.append({
            "entity_id": entity_id, "type": "ENEMY_" + item["rank"],
            "illustration": "NOT_APPLICABLE", "portrait": "NOT_APPLICABLE", "icon": "PARTIAL",
            "sd_pack": sd, "animation": sd, "vfx": vfx_state(entity_id), "map_pawn": sd,
            "battle_integration": "COMPLETE" if sd != "MISSING" else "MISSING",
            "story_integration": "NOT_APPLICABLE", "stage_integration": "COMPLETE",
            "fallback_used": str(fallback).upper(), "qa_status": qa,
        })
    for item in stages:
        stage_id = item["id"]
        waves = json.loads(item["waves"])
        rows.append({
            "entity_id": stage_id, "type": "STAGE_" + item["mode"],
            "illustration": "NOT_APPLICABLE", "portrait": "NOT_APPLICABLE", "icon": "NOT_APPLICABLE",
            "sd_pack": "NOT_APPLICABLE", "animation": "NOT_APPLICABLE", "vfx": "NOT_APPLICABLE",
            "map_pawn": "COMPLETE", "battle_integration": "COMPLETE" if waves else "MISSING",
            "story_integration": "PARTIAL", "stage_integration": "COMPLETE", "fallback_used": "FALSE",
            "qa_status": f"WAVES_{len(waves)}",
        })
    for path in scenarios:
        scenario = read_json(path)
        rows.append({
            "entity_id": str(scenario.get("id", path.stem)), "type": "SCENARIO",
            "illustration": "PARTIAL", "portrait": "PARTIAL", "icon": "NOT_APPLICABLE",
            "sd_pack": "NOT_APPLICABLE", "animation": "NOT_APPLICABLE", "vfx": "NOT_APPLICABLE",
            "map_pawn": "NOT_APPLICABLE", "battle_integration": "NOT_APPLICABLE",
            "story_integration": "COMPLETE", "stage_integration": "PARTIAL", "fallback_used": "FALSE",
            "qa_status": "SCENARIO_JSON_VALID",
        })
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    with REPORT.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    counts = {"rows": len(rows), "players": len(characters), "enemies": len(enemies), "stages": len(stages), "scenarios": len(scenarios), "fallback_rows": sum(row["fallback_used"] == "TRUE" for row in rows)}
    print(json.dumps(counts, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
