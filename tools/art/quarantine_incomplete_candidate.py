#!/usr/bin/env python3
"""Move an interrupted asset candidate into project quarantine without disposal.

The tool accepts exact project-relative paths only. It writes an in-progress
transaction inventory before moving anything, verifies per-file SHA-256 after
the move, and never deletes input or destination content.
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
QUARANTINE_ROOT = ROOT / "quarantine" / "incomplete_asset_candidates"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def within(parent: Path, child: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inventory(path: Path) -> dict[str, Any]:
    base = path.parent if path.is_file() else path
    files = [path] if path.is_file() else sorted(item for item in path.rglob("*") if item.is_file())
    rows = [
        {
            "relative_path": item.relative_to(base).as_posix(),
            "bytes": item.stat().st_size,
            "sha256": sha256(item),
        }
        for item in files
    ]
    encoded = json.dumps(rows, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return {
        "file_count": len(rows),
        "total_bytes": sum(int(row["bytes"]) for row in rows),
        "inventory_sha256": hashlib.sha256(encoded.encode("utf-8")).hexdigest(),
        "files": rows,
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch-id", required=True)
    parser.add_argument("--reason", required=True)
    parser.add_argument("--source", action="append", required=True, help="exact project-relative source, repeatable")
    parser.add_argument("--execute", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    batch_id = str(args.batch_id).strip().lower()
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", batch_id):
        raise SystemExit("BATCH_ID_INVALID")
    batch_root = (QUARANTINE_ROOT / batch_id).resolve()
    if batch_root.exists():
        raise SystemExit(f"QUARANTINE_BATCH_EXISTS:{batch_root}")

    records = []
    for raw_source in args.source:
        source = (ROOT / raw_source).resolve()
        if not within(ROOT, source) or not source.exists():
            raise SystemExit(f"SOURCE_INVALID:{raw_source}")
        destination = (batch_root / "retained_payload" / Path(raw_source)).resolve()
        if not within(QUARANTINE_ROOT, destination):
            raise SystemExit(f"DESTINATION_INVALID:{destination}")
        records.append(
            {
                "original_project_relative_path": source.relative_to(ROOT).as_posix(),
                "quarantine_project_relative_path": destination.relative_to(ROOT).as_posix(),
                "pre_move_inventory": inventory(source),
            }
        )

    plan = {
        "schema_version": 1,
        "batch_id": batch_id,
        "created_utc": utc_now(),
        "status": "INCOMPLETE_CANDIDATE_RETAINED_NOT_FOR_DISPOSAL",
        "reason": str(args.reason),
        "retention_policy": "Do not delete or promote this interrupted candidate. Retain its partial runtime files, masters, keyed derivatives, logs, and provenance until a completed replacement has passed all required gates and retirement is separately recorded.",
        "records": records,
    }
    if not args.execute:
        print(json.dumps({"mode": "dry_run", "batch_id": batch_id, "records": records}, ensure_ascii=False, indent=2))
        return 0

    batch_root.mkdir(parents=True, exist_ok=False)
    write_json(batch_root / "QUARANTINE_TRANSACTION_PLAN.json", plan)
    for record in records:
        source = (ROOT / record["original_project_relative_path"]).resolve()
        destination = (ROOT / record["quarantine_project_relative_path"]).resolve()
        if not source.exists() or destination.exists():
            raise RuntimeError(f"UNSAFE_TRANSACTION_STATE:{source}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source), str(destination))
        post_move = inventory(destination)
        if post_move != record["pre_move_inventory"]:
            raise RuntimeError(f"INVENTORY_MISMATCH:{record['original_project_relative_path']}")
        record["post_move_inventory"] = post_move
    plan["completed_utc"] = utc_now()
    plan["move_operation"] = "shutil.move within this project only; no delete operation invoked"
    write_json(batch_root / "FAILURE_MANIFEST.json", plan)
    print(json.dumps({"status": plan["status"], "batch_root": str(batch_root)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
