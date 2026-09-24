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

ROOT = Path(__file__).resolve().parents[2]
RELEASE = ROOT / "builds/web_sites_20260920_release"
SOURCE = ROOT / "work/sites_20260920"
if len(sys.argv) != 2:
    raise SystemExit("usage: prepare_sites_minimal.py SITE_CHECKOUT")
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
for source in sorted(RELEASE.rglob("*")):
    if not source.is_file():
        continue
    rel = source.relative_to(RELEASE).as_posix()
    if rel == "density_sidecars.json" or rel.startswith("_hd/"):
        continue
    raw = source.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    hashes[rel] = {"sha256": digest, "bytes": len(raw)}
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

server = (site / "dist/server/index.js").read_text(encoding="utf-8")
marker = server.index("export default")
server = "const FILES = " + json.dumps(files, separators=(",", ":")) + ";\n" + server[marker:]
(site / "dist/server/index.js").write_text(server, encoding="utf-8", newline="\n")

report = site / "reports/sites_update_20260920/staged_assets.json"
report.parent.mkdir(parents=True, exist_ok=True)
report.write_text(json.dumps({"files": hashes, "streamed_routes": files, "count": len(hashes)}, indent=2), encoding="utf-8")
(site / "dist/.openai").mkdir(parents=True, exist_ok=True)
shutil.copy2(site / ".openai/hosting.json", site / "dist/.openai/hosting.json")
largest = max(path.stat().st_size for path in client.rglob("*") if path.is_file())
if largest > 20_000_000:
    raise ValueError(f"physical Sites member too large: {largest}")
print(json.dumps({"files": len(hashes), "streamed": list(files), "largest_static_bytes": largest}))
