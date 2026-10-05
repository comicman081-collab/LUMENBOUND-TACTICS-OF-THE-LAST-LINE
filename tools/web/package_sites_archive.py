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
    if not (root / "dist/client/intro.mp4").is_file():
        raise SystemExit("missing browser intro sidecar dist/client/intro.mp4")
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, "w:gz", format=tarfile.PAX_FORMAT) as output:
        # Sites accepts build output, not the source tree or local QA reports.
        paths = [root / ".openai/hosting.json", *(root / "dist").rglob("*")]
        for path in sorted(paths):
            if path.is_file():
                info = output.gettarinfo(str(path), arcname=path.relative_to(root).as_posix())
                info.mtime = 0
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                with path.open("rb") as content:
                    output.addfile(info, content)
    print(archive)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
