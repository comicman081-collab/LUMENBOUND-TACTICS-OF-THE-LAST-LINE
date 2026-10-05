"""Build a size-safe Sites checkout from the verified Web release.

The public build uses the compact assets in the PCK. Optional HD companion
pages remain in the project release and local QA, but are omitted here because
the Sites worker source limit is lower than the full companion-page bundle.
"""
from __future__ import annotations
import hashlib
import json
import shutil
import sys
from pathlib import Path

from split_web_pck_for_sites import split_export
from stage_sites_intro import stage_intro, verified_intro

ROOT = Path(__file__).resolve().parents[2]
RELEASE = Path(sys.argv[2]).resolve() if len(sys.argv) == 3 else ROOT / "builds/web_title_pop_r10_release"
SOURCE = ROOT / "tools/web/sites_template"
if len(sys.argv) not in (2, 3):
    raise SystemExit("usage: prepare_sites_minimal.py SITE_CHECKOUT [WEB_RELEASE]")
if not RELEASE.is_dir() or ROOT / "builds" not in RELEASE.parents:
    raise SystemExit(f"release must be an existing directory under {ROOT / 'builds'}: {RELEASE}")
# /intro.mp4 is served separately by the local player and is not exported by
# Godot. Fail before writing a checkout if that required browser asset is absent.
verified_intro()
site = Path(sys.argv[1]).resolve()
site.mkdir(parents=True, exist_ok=True)
client = site / "dist/client"
client.mkdir(parents=True, exist_ok=True)
(site / ".openai").mkdir(parents=True, exist_ok=True)
(site / "dist/server").mkdir(parents=True, exist_ok=True)
shutil.copy2(SOURCE / ".openai/hosting.json", site / ".openai/hosting.json")
shutil.copy2(SOURCE / "dist/server/index.js", site / "dist/server/index.js")
for name in ("package.json", "package-lock.json"):
    shutil.copy2(SOURCE / name, site / name)
(site / "scripts").mkdir(parents=True, exist_ok=True)
shutil.copy2(SOURCE / "scripts/verify-prebuilt.mjs", site / "scripts/verify-prebuilt.mjs")

files = {}
hashes = {}
pck_source = None
for source in sorted(RELEASE.rglob("*")):
    if not source.is_file():
        continue
    rel = source.relative_to(RELEASE).as_posix()
    if rel == "density_sidecars.json" or rel.startswith("_hd/"):
        continue
    raw = source.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    hashes[rel] = {"sha256": digest, "bytes": len(raw)}
    if source.suffix == ".pck":
        if pck_source is not None:
            raise ValueError("expected one Web PCK")
        pck_source = source
        target = client / rel
        target.write_bytes(raw)
        continue
    if len(raw) <= 20_000_000:
        target = client / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        continue
    chunk_size = 4 * 1024 * 1024
    parts = []
    for index, start in enumerate(range(0, len(raw), chunk_size)):
        part = f"asset-parts/{digest}/{index:03}.bin"
        target = client / part
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw[start:start + chunk_size])
        parts.append("/" + part)
    files["/" + rel] = {
        "size": len(raw), "hash": digest, "chunkSize": chunk_size,
        "parts": parts,
        "type": {".mp4": "video/mp4", ".wasm": "application/wasm"}.get(
            source.suffix, "application/octet-stream"
        ),
    }

if pck_source is None:
    raise ValueError("missing Web PCK")
# Godot used to wait for one worker to fetch 42 asset parts in sequence. Patch
# its own preloader to fetch the physical parts directly with bounded overlap.
# The original file is removed only after the split and loader checks pass.
pck_manifest = split_export(client, 4 * 1024 * 1024)
if pck_manifest["original"]["sha256"] != hashes[pck_source.name]["sha256"]:
    raise ValueError("split PCK does not match the release")
staged_rewrites = {}
for name in ("index.html", "index.js", "index.service.worker.js"):
    raw = (client / name).read_bytes()
    staged_rewrites[name] = {"sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)}

server = (site / "dist/server/index.js").read_text(encoding="utf-8")
marker = server.index("export default")
server = "const FILES = " + json.dumps(files, separators=(",", ":")) + ";\n" + server[marker:]
(site / "dist/server/index.js").write_text(server, encoding="utf-8", newline="\n")

report = site / "reports/sites_update_20260920/staged_assets.json"
report.parent.mkdir(parents=True, exist_ok=True)
report.write_text(json.dumps({"files": hashes, "staged_rewrites": staged_rewrites, "streamed_routes": files, "count": len(hashes)}, indent=2), encoding="utf-8")
stage_intro(site)
(site / "dist/.openai").mkdir(parents=True, exist_ok=True)
shutil.copy2(site / ".openai/hosting.json", site / "dist/.openai/hosting.json")
largest = max(path.stat().st_size for path in client.rglob("*") if path.is_file())
if largest > 20_000_000:
    raise ValueError(f"physical Sites member too large: {largest}")
print(json.dumps({"files": len(hashes) + 1, "intro": "/intro.mp4", "streamed": list(files), "largest_static_bytes": largest}))
