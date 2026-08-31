#!/usr/bin/env python3
"""Pin browser-only runtime textures to a compact, high-quality WebP import."""

from __future__ import annotations

import re
from pathlib import Path


LOSSY_QUALITY = 0.85


def main() -> int:
    project_root = Path(__file__).resolve().parents[2]
    runtime_root = project_root / "godot" / "assets" / "runtime_web"
    imports = sorted(runtime_root.rglob("*.png.import"))
    if not imports:
        raise RuntimeError(f"no runtime Web texture imports found below {runtime_root}")

    changed = 0
    for path in imports:
        text = path.read_text(encoding="utf-8")
        updated, mode_count = re.subn(r"(?m)^compress/mode=\d+$", "compress/mode=1", text, count=1)
        updated, quality_count = re.subn(
            r"(?m)^compress/lossy_quality=[0-9.]+$",
            f"compress/lossy_quality={LOSSY_QUALITY}",
            updated,
            count=1,
        )
        if mode_count != 1 or quality_count != 1:
            raise RuntimeError(f"unexpected Godot texture import contract: {path}")
        if updated != text:
            path.write_text(updated, encoding="utf-8", newline="\n")
            changed += 1

    print(
        "RUNTIME_WEB_IMPORTS",
        f"files={len(imports)}",
        f"changed={changed}",
        "mode=lossy_webp",
        f"quality={LOSSY_QUALITY:.2f}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
