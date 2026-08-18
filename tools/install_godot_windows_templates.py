#!/usr/bin/env python3
"""Install only Windows binaries from the official Godot export TPZ.

The official all-platform archive is about 1.3 GB. This range reader fetches
the ZIP directory and the two Windows entries only, verifies ZIP CRC/size, and
writes atomically. It never downloads or installs Android templates.
"""
from __future__ import annotations

import argparse
import binascii
import hashlib
import json
import os
import struct
import urllib.request
import zlib
from pathlib import Path


DEFAULT_URL = (
    "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/"
    "Godot_v4.7.1-stable_export_templates.tpz"
)
TARGET_BASENAMES = {"windows_debug_x86_64.exe", "windows_release_x86_64.exe"}


def range_read(url: str, start: int, end: int | None = None, suffix: bool = False) -> tuple[bytes, str]:
    value = f"bytes=-{start}" if suffix else f"bytes={start}-{'' if end is None else end}"
    request = urllib.request.Request(url, headers={"Range": value, "User-Agent": "Lanternline-Godot-Template-Installer/1"})
    with urllib.request.urlopen(request, timeout=120) as response:
        if response.status != 206:
            raise RuntimeError(f"server did not honor Range {value}: HTTP {response.status}")
        content_range = response.headers.get("Content-Range", "")
        data = response.read()
    return data, content_range


def remote_size(url: str) -> int:
    request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "Lanternline-Godot-Template-Installer/1"})
    with urllib.request.urlopen(request, timeout=120) as response:
        value = response.headers.get("Content-Length")
    if value is None:
        raise RuntimeError("official archive Content-Length missing")
    return int(value)


def archive_size_from_range(content_range: str) -> int:
    if "/" not in content_range:
        raise RuntimeError(f"invalid Content-Range: {content_range}")
    return int(content_range.rsplit("/", 1)[1])


def central_entries(data: bytes) -> list[dict]:
    entries: list[dict] = []
    cursor = 0
    while cursor + 46 <= len(data):
        if data[cursor : cursor + 4] != b"PK\x01\x02":
            break
        fields = struct.unpack_from("<4s6H3L5H2L", data, cursor)
        compression = fields[4]
        crc32 = fields[7]
        compressed_size = fields[8]
        uncompressed_size = fields[9]
        name_len, extra_len, comment_len = fields[10], fields[11], fields[12]
        local_offset = fields[16]
        name_start = cursor + 46
        name = data[name_start : name_start + name_len].decode("utf-8")
        entries.append(
            {
                "name": name,
                "compression": compression,
                "crc32": crc32,
                "compressed_size": compressed_size,
                "uncompressed_size": uncompressed_size,
                "local_offset": local_offset,
            }
        )
        cursor = name_start + name_len + extra_len + comment_len
    return entries


def extract_entry(url: str, entry: dict) -> bytes:
    offset = int(entry["local_offset"])
    header, _ = range_read(url, offset, offset + 29)
    fields = struct.unpack("<4s5H3L2H", header)
    if fields[0] != b"PK\x03\x04":
        raise RuntimeError(f"bad local header: {entry['name']}")
    name_len, extra_len = fields[9], fields[10]
    data_start = offset + 30 + name_len + extra_len
    compressed_size = int(entry["compressed_size"])
    compressed, _ = range_read(url, data_start, data_start + compressed_size - 1)
    if len(compressed) != compressed_size:
        raise RuntimeError(f"short range for {entry['name']}: {len(compressed)} != {compressed_size}")
    method = int(entry["compression"])
    if method == 0:
        output = compressed
    elif method == 8:
        output = zlib.decompress(compressed, -zlib.MAX_WBITS)
    else:
        raise RuntimeError(f"unsupported ZIP compression {method}: {entry['name']}")
    if len(output) != int(entry["uncompressed_size"]):
        raise RuntimeError(f"size mismatch: {entry['name']}")
    if (binascii.crc32(output) & 0xFFFFFFFF) != int(entry["crc32"]):
        raise RuntimeError(f"CRC mismatch: {entry['name']}")
    return output


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    if temporary.exists():
        temporary.unlink()
    temporary.write_bytes(data)
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()

    archive_size = remote_size(args.url)
    tail_start = max(0, archive_size - 131072)
    tail, content_range = range_read(args.url, tail_start, archive_size - 1)
    if archive_size_from_range(content_range) != archive_size:
        raise RuntimeError("archive size changed during range install")
    eocd_at = tail.rfind(b"PK\x05\x06")
    if eocd_at < 0:
        raise RuntimeError("ZIP EOCD not found")
    eocd = struct.unpack_from("<4s4H2LH", tail, eocd_at)
    central_size, central_offset = eocd[5], eocd[6]
    if central_size == 0xFFFFFFFF or central_offset == 0xFFFFFFFF:
        raise RuntimeError("ZIP64 central directory is not supported by this minimal installer")
    central, _ = range_read(args.url, central_offset, central_offset + central_size - 1)
    candidates = [entry for entry in central_entries(central) if Path(entry["name"]).name in TARGET_BASENAMES]
    found = {Path(entry["name"]).name for entry in candidates}
    if found != TARGET_BASENAMES:
        raise RuntimeError(f"required Windows templates missing: expected {TARGET_BASENAMES}, found {found}")

    records = []
    for entry in sorted(candidates, key=lambda value: value["name"]):
        basename = Path(entry["name"]).name
        target = args.destination / basename
        data = extract_entry(args.url, entry)
        atomic_write(target, data)
        records.append({"file": basename, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        print(f"INSTALLED {target} bytes={len(data)} sha256={records[-1]['sha256']}")

    manifest = {
        "kind": "GODOT_4_7_1_OFFICIAL_WINDOWS_EXPORT_TEMPLATES",
        "source": args.url,
        "archive_bytes": archive_size,
        "range_install": True,
        "android_templates_installed": False,
        "records": records,
    }
    atomic_write(args.manifest, (json.dumps(manifest, indent=2) + "\n").encode("utf-8"))
    print(f"TEMPLATE_INSTALL_SUMMARY files={len(records)} manifest={args.manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
