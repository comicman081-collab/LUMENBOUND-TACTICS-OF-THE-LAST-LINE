"""List the largest packed Godot resources without extracting the release."""
from __future__ import annotations

import argparse
import re
import struct
from collections import defaultdict
from pathlib import Path


def read(fmt: str, file):
    size = struct.calcsize(fmt)
    data = file.read(size)
    if len(data) != size:
        raise ValueError("truncated PCK directory")
    return struct.unpack(fmt, data)


def audit(path: Path) -> None:
    with path.open("rb") as file:
        magic, version, *_ = read("<6I", file)
        if magic != 0x43504447 or version != 4:
            raise ValueError("expected a Godot 4 PCK v4")
        file_base, directory_offset = read("<2Q", file)
        file.seek(directory_offset)
        (count,) = read("<I", file)
        entries = []
        for _ in range(count):
            (path_bytes,) = read("<I", file)
            name = file.read(path_bytes).rstrip(b"\x00").decode("utf-8")
            offset, size = read("<2Q", file)
            file.seek(16, 1)  # MD5
            (flags,) = read("<I", file)
            entries.append((size, name, flags, offset))

        imported_sources = {}
        for size, name, _, offset in entries:
            if not name.endswith(".import") or size > 65536:
                continue
            file.seek(file_base + offset)
            source = file.read(size).decode("utf-8", errors="replace")
            for imported in re.findall(r'res://(\.godot/imported/[^"\s]+)', source):
                imported_sources[imported] = name.removesuffix(".import")

    groups = defaultdict(lambda: [0, 0])
    types = defaultdict(lambda: [0, 0])
    source_groups = defaultdict(lambda: [0, 0])
    for size, name, _, _ in entries:
        stem = name.removeprefix("res://")
        if stem.startswith(".godot/imported/"):
            imported_name = stem.split("/")[-1]
            group = "imported/" + imported_name.rsplit(".", 1)[-1]
        else:
            group = "/".join(stem.split("/")[:3])
        groups[group][0] += size
        groups[group][1] += 1
        resolved = imported_sources.get(stem, stem)
        source_group = "/".join(resolved.split("/")[:4])
        source_groups[source_group][0] += size
        source_groups[source_group][1] += 1
        suffix = stem.rsplit(".", 1)[-1]
        types[suffix][0] += size
        types[suffix][1] += 1
    print(f"PCK={path.stat().st_size:,} entries={count} file_base={file_base:,}")
    print("Largest entries:")
    for size, name, flags, _ in sorted(entries, reverse=True)[:35]:
        print(f"{size / 1048576:8.2f} MiB flags={flags} {name}")
    print("Largest groups:")
    for group, (size, quantity) in sorted(groups.items(), key=lambda item: item[1][0], reverse=True)[:25]:
        print(f"{size / 1048576:8.2f} MiB {quantity:5d} {group}")
    print("Largest source groups:")
    for group, (size, quantity) in sorted(source_groups.items(), key=lambda item: item[1][0], reverse=True)[:40]:
        print(f"{size / 1048576:8.2f} MiB {quantity:5d} {group}")
    print("Largest types:")
    for suffix, (size, quantity) in sorted(types.items(), key=lambda item: item[1][0], reverse=True)[:20]:
        print(f"{size / 1048576:8.2f} MiB {quantity:5d} .{suffix}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("pck", type=Path)
    audit(parser.parse_args().pck)
