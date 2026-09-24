#!/usr/bin/env python3
"""Retain superseded battle-signature candidates in project quarantine.

This is deliberately a move-only, one-batch tool.  It never deletes source
files, never touches the promoted revision, and records a before/after
per-file SHA-256 inventory.  The retained batch is *not* eligible for
disposal; its manifest makes that explicit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
QUARANTINE_ROOT = ROOT / "quarantine" / "battle_signature_hd"
BATCH_ID = "r5_r6_superseded_after_r7_local_qa_20260904"
CURRENT_LIBRARY = ROOT / "godot" / "battle" / "view" / "battle_sprite_library.gd"

# These are exact, verified project-local candidates and QA evidence only.
# R7 and its source/evidence are intentionally not listed here.
CANDIDATES = (
    {
        "label": "runtime_signature_r5",
        "source": "godot/assets/runtime_web/combat_signature/r5",
        "destination": "retained_candidates/runtime_signature_r5",
        "reason": "Superseded by R7 after the CHR002 white-matte repair.",
    },
    {
        "label": "runtime_signature_r6",
        "source": "godot/assets/runtime_web/combat_signature/r6",
        "destination": "retained_candidates/runtime_signature_r6",
        "reason": "Interim non-promoted chroma-key candidate superseded by R7.",
    },
    {
        "label": "chroma_derivatives_r6",
        "source": "godot/assets/generated_import/chroma_key_derivatives/battle_signature_r6",
        "destination": "retained_candidates/chroma_derivatives_r6",
        "reason": "Source derivatives belonging exclusively to the retained R6 candidate.",
    },
    {
        "label": "r5_report",
        "source": "reports/art_qa/BATTLE_SIGNATURE_HD_R5_REPORT.json",
        "destination": "qa_evidence/BATTLE_SIGNATURE_HD_R5_REPORT.json",
        "reason": "R5 provenance and QA report retained with its candidate.",
    },
    {
        "label": "r5_contact_sheet",
        "source": "reports/art_qa/BATTLE_SIGNATURE_HD_R5_CONTACT_SHEET.png",
        "destination": "qa_evidence/BATTLE_SIGNATURE_HD_R5_CONTACT_SHEET.png",
        "reason": "R5 visual-QA evidence retained with its candidate.",
    },
    {
        "label": "r6_report",
        "source": "reports/art_qa/BATTLE_SIGNATURE_HD_R6_REPORT.json",
        "destination": "qa_evidence/BATTLE_SIGNATURE_HD_R6_REPORT.json",
        "reason": "R6 provenance and QA report retained with its candidate.",
    },
    {
        "label": "r6_contact_sheet",
        "source": "reports/art_qa/BATTLE_SIGNATURE_HD_R6_CONTACT_SHEET.png",
        "destination": "qa_evidence/BATTLE_SIGNATURE_HD_R6_CONTACT_SHEET.png",
        "reason": "R6 visual-QA evidence retained with its candidate.",
    },
    {
        "label": "r5_mobile_viewport_capture",
        "source": "reports/art_qa/battle_signature_hd_r5_viewport_2026-09-04T14-04-08",
        "destination": "qa_evidence/battle_signature_hd_r5_viewport_2026-09-04T14-04-08",
        "reason": "R5 mobile viewport capture retained with its candidate.",
    },
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def path_inside(container: Path, candidate: Path) -> bool:
    try:
        candidate.resolve().relative_to(container.resolve())
        return True
    except ValueError:
        return False


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inventory(path: Path) -> dict[str, Any]:
    """Return a deterministic, individually hashable inventory for a file/tree."""
    if path.is_file():
        files = [path]
        base = path.parent
    else:
        files = sorted(item for item in path.rglob("*") if item.is_file())
        base = path
    rows = [
        {
            "relative_path": item.relative_to(base).as_posix(),
            "bytes": item.stat().st_size,
            "sha256": sha256_file(item),
        }
        for item in files
    ]
    serialized = json.dumps(rows, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return {
        "file_count": len(rows),
        "total_bytes": sum(int(row["bytes"]) for row in rows),
        "inventory_sha256": hashlib.sha256(serialized.encode("utf-8")).hexdigest(),
        "files": rows,
    }


def current_signature_revision() -> str:
    text = CURRENT_LIBRARY.read_text(encoding="utf-8")
    match = re.search(r'SIGNATURE_REVISION\s*:=\s*"([^"]+)"', text)
    if not match:
        raise RuntimeError(f"Could not find SIGNATURE_REVISION in {CURRENT_LIBRARY}")
    return match.group(1).lower()


def resolve_candidate(spec: dict[str, str], batch_root: Path) -> tuple[Path, Path]:
    source = (ROOT / spec["source"]).resolve()
    destination = (batch_root / spec["destination"]).resolve()
    if not path_inside(ROOT, source):
        raise RuntimeError(f"Source is outside project root: {source}")
    if not path_inside(QUARANTINE_ROOT, destination):
        raise RuntimeError(f"Destination is outside quarantine: {destination}")
    if not source.exists():
        raise RuntimeError(f"Required candidate does not exist: {source}")
    if destination.exists():
        raise RuntimeError(f"Quarantine destination already exists: {destination}")
    return source, destination


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build_plan(batch_root: Path, revision: str) -> dict[str, Any]:
    records = []
    for spec in CANDIDATES:
        source, destination = resolve_candidate(spec, batch_root)
        records.append(
            {
                "label": spec["label"],
                "reason": spec["reason"],
                "original_project_relative_path": source.relative_to(ROOT).as_posix(),
                "quarantine_project_relative_path": destination.relative_to(ROOT).as_posix(),
                "pre_move_inventory": inventory(source),
            }
        )
    return {
        "schema_version": 1,
        "batch_id": BATCH_ID,
        "created_utc": utc_now(),
        "status": "IN_PROGRESS_MOVE_ONLY_RETAINED_NOT_FOR_DISPOSAL",
        "active_signature_revision_confirmed": revision,
        "replacement": {
            "runtime_root": "godot/assets/runtime_web/combat_signature/r7",
            "derivative_root": "godot/assets/generated_import/chroma_key_derivatives/battle_signature_r7/CHR002",
            "validation": {
                "headless_tests": "254 pass / 0 fail",
                "mobile_viewport": "390x844 captured and inspected",
                "chroma_key_qa": "38 CHR002 frames; visible exact green=0; exterior near-white rim 27817 -> 55",
                "external_review": "ChatGPT web Sol Pro approved R7 for LOCAL_QA_ONLY; public deployment remains held",
            },
        },
        "retention_policy": {
            "disposition": "QUARANTINED_RETAINED_NOT_FOR_DISPOSAL",
            "deletion_prohibited": True,
            "rule": "Do not dispose of this batch until a completed final replacement has passed all required visual, runtime, technical, promotion, and retirement-manifest gates, and no active registry references it.",
        },
        "records": records,
    }


def execute(plan: dict[str, Any], batch_root: Path) -> dict[str, Any]:
    transaction_path = batch_root / "QUARANTINE_TRANSACTION_PLAN.json"
    write_json(transaction_path, plan)
    for record in plan["records"]:
        source = (ROOT / record["original_project_relative_path"]).resolve()
        destination = (ROOT / record["quarantine_project_relative_path"]).resolve()
        # The source was already constrained/hashed while creating the plan;
        # revalidate before every move to keep a partial failure recoverable.
        if not source.exists() or destination.exists():
            raise RuntimeError(f"Unsafe transaction state for {record['label']}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source), str(destination))
        post_move = inventory(destination)
        if post_move != record["pre_move_inventory"]:
            raise RuntimeError(f"Hash/inventory mismatch after move: {record['label']}")
        record["post_move_inventory"] = post_move

    plan["completed_utc"] = utc_now()
    plan["status"] = "QUARANTINED_RETAINED_NOT_FOR_DISPOSAL"
    plan["move_operation"] = "shutil.move within the same project workspace; no delete operation was invoked"
    write_json(batch_root / "QUARANTINE_MANIFEST.json", plan)
    return plan


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true", help="perform the verified move-only quarantine")
    args = parser.parse_args()

    revision = current_signature_revision()
    if revision != "r7":
        raise RuntimeError(f"Quarantine blocked: expected active revision r7, found {revision!r}")
    batch_root = (QUARANTINE_ROOT / BATCH_ID).resolve()
    if batch_root.exists():
        raise RuntimeError(f"Quarantine batch already exists: {batch_root}")

    plan = build_plan(batch_root, revision)
    if not args.execute:
        summary = {
            "mode": "dry_run",
            "batch_id": BATCH_ID,
            "active_signature_revision_confirmed": revision,
            "records": [
                {
                    "label": record["label"],
                    "source": record["original_project_relative_path"],
                    "destination": record["quarantine_project_relative_path"],
                    "file_count": record["pre_move_inventory"]["file_count"],
                    "total_bytes": record["pre_move_inventory"]["total_bytes"],
                }
                for record in plan["records"]
            ],
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0

    batch_root.mkdir(parents=True, exist_ok=False)
    final_plan = execute(plan, batch_root)
    print(
        json.dumps(
            {
                "status": final_plan["status"],
                "batch_root": str(batch_root),
                "records": len(final_plan["records"]),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
