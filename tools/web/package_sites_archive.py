#!/usr/bin/env python3
"""Create a deterministic Sites archive from the validated static checkout."""
from __future__ import annotations

import sys
import tarfile
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: package_sites_archive.py SITE_CHECKOUT ARCHIVE")
    root = Path(sys.argv[1]).resolve()
    archive = Path(sys.argv[2]).resolve()
    if not (root / ".openai/hosting.json").is_file():
        raise SystemExit("missing .openai/hosting.json")
    if not (root / "dist/client/index.html").is_file():
        raise SystemExit("missing dist/client/index.html")
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, "w:gz", format=tarfile.PAX_FORMAT) as output:
        for path in sorted(root.rglob("*")):
            if ".git" in path.relative_to(root).parts:
                continue
            if path.is_file():
                output.add(path, arcname=path.relative_to(root).as_posix(), recursive=False)
    print(archive)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
