#!/usr/bin/env python3
"""Bind pinned signature PNG sources to the exact Godot-exported imports.

Run after Godot --editor --import. No approval status is changed. A missing,
stale or mismatched source/import fails closed before an export is produced.
"""
from __future__ import annotations
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "godot"
OUTPUT = ROOT / "data" / "runtime_texture_integrity.json"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def records(value):
    if isinstance(value, dict):
        if "atlas_path" in value and "atlas_sha256" in value:
            yield value
        for child in value.values():
            yield from records(child)
    elif isinstance(value, list):
        for child in value:
            yield from records(child)


def main():
    entries = {}
    for family, revision, manifest_name in [
        ("combat_signature", "r16", "signature_manifest.json"),
        ("effect_signature", "r4", "effect_signature_manifest.json"),
        ("full_density", "r2", "animation_manifest.json"),
    ]:
        folder = ROOT / "assets" / "runtime_web" / family / revision
        for manifest in sorted(folder.glob(f"*/{manifest_name}")):
            for record in records(json.loads(manifest.read_text(encoding="utf-8"))):
                source = (manifest.parent / record["atlas_path"]).resolve()
                if source.parent != manifest.parent.resolve():
                    raise ValueError(f"Non-local atlas path: {source}")
                expected = record["atlas_sha256"]
                if sha(source) != expected:
                    raise ValueError(f"Pinned source mismatch: {source}")
                descriptor = Path(str(source) + ".import")
                remap = re.search(r'^path="(res://\.godot/imported/[^"\r\n]+\.ctex)"$', descriptor.read_text(encoding="utf-8"), re.M)
                if not remap:
                    raise ValueError(f"Missing single imported texture: {descriptor}")
                imported_path = remap[1]
                imported = ROOT / imported_path.removeprefix("res://")
                md5 = imported.with_suffix(".md5").read_text(encoding="utf-8")
                # Godot's import record proves this ctex was made from this PNG.
                source_md5 = hashlib.md5(source.read_bytes()).hexdigest()
                if f'source_md5="{source_md5}"' not in md5:
                    raise ValueError(f"Stale import; reimport before export: {source}")
                entries["res://" + source.relative_to(ROOT).as_posix()] = {
                    "source_sha256": expected,
                    "imported_path": imported_path,
                    "imported_sha256": sha(imported),
                }
    if not entries:
        raise ValueError("No pinned signature atlases found")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps({"schema_version": 1, "textures": entries}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"TEXTURE_INTEGRITY_PASS atlases={len(entries)} output={OUTPUT}")


if __name__ == "__main__":
    main()
