#!/usr/bin/env python3
"""Install only official Godot 4.7.1 Web templates via HTTP ranges."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import install_godot_windows_templates as archive


TARGET_BASENAMES = {
    "web_nothreads_debug.zip",
    "web_nothreads_release.zip",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=archive.DEFAULT_URL)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()

    archive_size = archive.remote_size(args.url)
    tail_start = max(0, archive_size - 131072)
    tail, content_range = archive.range_read(args.url, tail_start, archive_size - 1)
    if archive.archive_size_from_range(content_range) != archive_size:
        raise RuntimeError("archive size changed during range install")
    eocd_at = tail.rfind(bytes.fromhex("504b0506"))
    if eocd_at < 0:
        raise RuntimeError("ZIP EOCD not found")

    import struct

    eocd = struct.unpack_from("<4s4H2LH", tail, eocd_at)
    central_size, central_offset = eocd[5], eocd[6]
    central, _ = archive.range_read(args.url, central_offset, central_offset + central_size - 1)
    candidates = [entry for entry in archive.central_entries(central) if Path(entry["name"]).name in TARGET_BASENAMES]
    found = {Path(entry["name"]).name for entry in candidates}
    if found != TARGET_BASENAMES:
        raise RuntimeError(f"required Web templates missing: expected {TARGET_BASENAMES}, found {found}")

    records = []
    for entry in sorted(candidates, key=lambda item: item["name"]):
        basename = Path(entry["name"]).name
        target = args.destination / basename
        data = archive.extract_entry(args.url, entry)
        archive.atomic_write(target, data)
        record = {"file": basename, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        records.append(record)
        print(f"INSTALLED {target} bytes={record['bytes']} sha256={record['sha256']}")

    manifest = {
        "kind": "GODOT_4_7_1_OFFICIAL_WEB_EXPORT_TEMPLATES",
        "source": args.url,
        "archive_bytes": archive_size,
        "range_install": True,
        "thread_support": False,
        "extensions_support": False,
        "native_game_templates_installed_by_this_script": False,
        "records": records,
    }
    archive.atomic_write(args.manifest, (json.dumps(manifest, indent=2) + "\n").encode("utf-8"))
    print(f"WEB_TEMPLATE_INSTALL_SUMMARY files={len(records)} manifest={args.manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
