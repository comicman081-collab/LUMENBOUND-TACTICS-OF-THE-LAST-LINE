#!/usr/bin/env python3
"""Stage a verified Web release for GitHub Pages and prepare its git transport tree.

``stage`` turns a project release such as ``builds/web_visual_r22_release`` into
the exact tree GitHub Pages serves: public loading screen and service worker,
the opening movie, license notices and a VERSION.json that lists every file.
The optional HD pages (``_hd/``) stay out, as in the Sites deployment: the game
falls back to the compact textures packaged in the PCK when a page is missing.

``transport`` rebuilds that tree for git. The PCK becomes parts below 50 MB, so
no Git LFS quota is involved and no file nears GitHub's limits; every other
file is hard-linked. The deploy workflow joins the parts, verifies every byte
against VERSION.json and only then publishes.

Nothing here touches the source release or any existing output directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import finalize_public_web as public  # noqa: E402  (shares the public loader/service-worker contract)
import stage_audio_sidecars as audio  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
INTRO_DIR = ROOT / "intro" / "web_1080p_50s"
FONTS = ROOT / "godot" / "assets" / "fonts"
DEFAULT_GODOT_LICENSE = Path(r"D:\AI 종합 폴더\Godot\4.7.1-standard\LICENSE.txt")
PACK_MODE = "verified_prebuilt_web_export_without_optional_hd"
PART_LIMIT = 49_000_000  # GitHub warns above 50 MB per file
BASE_PATTERN = re.compile(r"r7_current_[0-9a-f]{12}")
EXCLUDED = {"README_HTML.md", "LICENSES.md", "VERSION.json", "density_sidecars.json", "DEPLOY_SHA.txt"}
TEXT_SUFFIXES = {".html", ".js", ".json", ".md", ".txt"}
LEAK = re.compile(r"(?i)(?<![A-Za-z0-9_])[A-Z]:[\\/]|source_blends?|render_command|blender_sources|\.blend\b")

# The packaged player asks for the absolute '/intro.mp4'. Below a repository path
# (GitHub Pages project sites) that would leave the site, so resolve it beside index.html.
INTRO_SHIM = b"""\t\t<script>
/* LUMENBOUND_PAGES_INTRO_PATH */
(function () {
\tvar descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
\tif (!descriptor || !descriptor.set) return;
\tObject.defineProperty(HTMLMediaElement.prototype, 'src', {
\t\tconfigurable: true, enumerable: descriptor.enumerable, get: descriptor.get,
\t\tset: function (value) {
\t\t\tdescriptor.set.call(this, value === '/intro.mp4' ? new URL('intro.mp4', document.baseURI).href : value);
\t\t}
\t});
}());
</script>
"""
BRAND = '<div id="status-brand"><div class="kicker">LANTERNLINE \u00b7 CHAPTER 01</div><h1>LUMEN<br>BOUND</h1></div>'


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def part_plan(size: int) -> list[tuple[str, int, int]]:
    count = -(-size // PART_LIMIT)
    each = -(-size // count)
    return [(f"{index:02d}", index * each, min(each, size - index * each)) for index in range(count)]


def verified_intro() -> Path:
    manifest = json.loads((INTRO_DIR / "manifest.json").read_text(encoding="utf-8"))["web"]
    movie = INTRO_DIR / "intro.mp4"
    if movie.stat().st_size != manifest["bytes"] or sha256(movie) != manifest["sha256"]:
        raise SystemExit("intro.mp4 does not match its verified manifest")
    return movie


def license_notices(godot_license: Path) -> str:
    sources = {
        "policy": ROOT / "docs" / "LICENSE_POLICY.md",
        "pako": ROOT / "tools" / "web" / "PAKO_LICENSES.txt",
        "noto": FONTS / "NotoSansKR-OFL.txt",
        "nunito": FONTS / "Nunito-OFL.txt",
        "godot": godot_license,
    }
    for source in sources.values():
        if not source.is_file() or source.stat().st_size <= 0:
            raise SystemExit(f"required license text is missing: {source}")
    text = {name: source.read_text(encoding="utf-8") for name, source in sources.items()}
    return (
        "# LUMENBOUND Web \u2014 License Notices\n\n## Project asset policy\n\n" + public.scrub_policy(text["policy"])
        + "\n\n## Godot Engine 4.7.1\n\n" + text["godot"]
        + "\n\n## pako and embedded zlib-derived code\n\n" + text["pako"]
        + "\n\n## Noto Sans KR (basis of Lantern Sans, a renamed static instance)\n\n" + text["noto"]
        + "\n\n## Nunito (basis of Lantern Rounded, a renamed static instance)\n\n" + text["nunito"] + "\n"
    )


def edit_loading_screen(html_path: Path) -> None:
    raw = html_path.read_bytes()
    brand = re.compile(rb'<div id="status-brand">.*?(?=\s*<img id="status-splash")', re.S)
    if len(brand.findall(raw)) != 1:
        raise SystemExit("expected exactly one status-brand block in index.html")
    raw = brand.sub(lambda _: BRAND.encode("utf-8"), raw, count=1)
    if raw.count(b"</head>") != 1:
        raise SystemExit("expected exactly one </head> in index.html")
    raw = raw.replace(b"</head>", INTRO_SHIM + b"\t</head>", 1)
    html_path.write_bytes(raw)
    raw.decode("utf-8")  # strict: the unreadable Korean sub-line must be gone


def stage(release: Path, out: Path, source_commit: str, godot_license: Path, source_note: str = "", reviewed_hd: bool = False) -> dict:
    release, out = release.resolve(), out.resolve()
    if not re.fullmatch(r"[0-9a-f]{40}", source_commit):
        raise SystemExit("--source-commit must be a full 40-character SHA")
    version = json.loads((release / "VERSION.json").read_text(encoding="utf-8-sig"))
    base = version["runtime_artifact_base"]
    if not BASE_PATTERN.fullmatch(base):
        raise SystemExit(f"unexpected runtime artifact base: {base}")
    pck, wasm = release / f"{base}.pck", release / f"{base}.wasm"
    pck_hash = sha256(pck)
    if pck_hash != version["pck_sha256"] or base != "r7_current_" + pck_hash[:12]:
        raise SystemExit("PCK hash does not match VERSION.json or its artifact name")
    if wasm.read_bytes()[:2] != b"\x1f\x8b":
        raise SystemExit("WASM is not the deterministic gzip payload")
    audio_manifest = audio.validate(release)
    movie = verified_intro()

    site = out / "site"
    if site.exists():
        raise SystemExit(f"refusing to reuse an existing staging directory: {site}")
    for source in sorted(release.rglob("*")):
        rel = source.relative_to(release).as_posix()
        superseded_boss = rel.startswith('_hd/full_density/r2/BOSS')
        if not source.is_file() or rel in EXCLUDED or (rel.startswith("_hd/") and (not reviewed_hd or superseded_boss)):
            continue
        target = site / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    shutil.copy2(movie, site / "intro.mp4")

    site_pck, site_wasm = site / pck.name, site / wasm.name
    edit_loading_screen(site / "index.html")
    public.finalize_html(site, site_pck, site_wasm)
    public.finalize_worker(site, site_pck, site_wasm)

    manifest_path = site / "index.manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("name") != public.PUBLIC_TITLE or manifest.get("orientation") != "landscape":
        raise SystemExit("PWA manifest must carry the public title and landscape orientation")
    (site / "LICENSES.md").write_text(license_notices(godot_license), encoding="utf-8", newline="\n")
    (site / "README_HTML.md").write_text(
        "# LUMENBOUND: TACTICS OF THE LAST LINE (Web)\n\n"
        "Godot 4.7.1 Compatibility Web export, build " + version["build_id"] + ". Serve this directory over HTTP(S).\n"
        "Music, sound effects and story voices are the sidecars in `_audio/`; the opening movie is `intro.mp4`.\n"
        "The optional high-density texture pages (`_hd/`) are not part of this deployment: the game then uses\n"
        "the compact textures packaged in the PCK.\n" if not reviewed_hd else
        "# LUMENBOUND R24 Web\n\nReviewed character, monster, effect and map HD pages are fetched only when required.\n",
        encoding="utf-8", newline="\n",
    )

    leaks = []
    for path in site.rglob("*"):
        if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES and not path.relative_to(site).as_posix().startswith("_audio/"):
            match = LEAK.search(path.read_text(encoding="utf-8", errors="replace"))
            if match:
                leaks.append(f"{path.relative_to(site).as_posix()}: {match.group(0)!r}")
    if leaks:
        raise SystemExit("public text leaks authoring lineage: " + "; ".join(leaks))

    files = {}
    for path in sorted(site.rglob("*")):
        rel = path.relative_to(site).as_posix()
        if path.is_file() and not rel.startswith("_audio/") and rel != "VERSION.json":
            files[rel] = {"bytes": path.stat().st_size, "sha256": sha256(path)}
    pck_size = site_pck.stat().st_size
    parts = []
    with site_pck.open("rb") as stream:
        for suffix, offset, length in part_plan(pck_size):
            stream.seek(offset)
            data = stream.read(length)
            parts.append({"name": f"{base}.pck.part{suffix}", "bytes": length, "sha256": hashlib.sha256(data).hexdigest()})
    public_version = {
        "build_id": version["build_id"], "engine": version["engine"], "renderer": version["renderer"],
        "target": "Web HTML Release (GitHub Pages)", "map_revision": version.get("map_revision"),
        "runtime_artifact_base": base, "release_pack_mode": 'verified_prebuilt_web_export_with_reviewed_hd' if reviewed_hd else PACK_MODE, "source_commit": source_commit,
        "verified_local_source_pck_sha256": version.get('verified_local_source_pck_sha256', pck_hash),
        "public_features": version.get('public_features', []),
        **({"source_note": source_note} if source_note else {}),
        "pck_sha256": pck_hash, "pck_size": pck_size, "pck_parts": parts,
        "wasm_sha256": files[wasm.name]["sha256"], "wasm_size": files[wasm.name]["bytes"],
        "intro": {"path": "intro.mp4", **files["intro.mp4"]},
        "audio_sidecars": {
            "files": sum(len(audio_manifest[key]) for key in ("tracks", "sfx", "voice")),
            "bytes": sum(record["bytes"] for key in ("tracks", "sfx", "voice") for record in audio_manifest[key].values()),
        },
        "files": files, "production_approved": bool(version.get("production_approved", False)),
        "created_utc": datetime.now(timezone.utc).isoformat(),
    }
    (site / "VERSION.json").write_text(json.dumps(public_version, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

    total = sum(path.stat().st_size for path in site.rglob("*") if path.is_file())
    count = sum(1 for path in site.rglob("*") if path.is_file())
    summary = {"site": str(site), "files": count, "bytes": total, "pck_parts": len(parts),
               "audio_files": public_version["audio_sidecars"]["files"], "source_commit": source_commit}
    (out / "stage_summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def transport(out: Path) -> dict:
    out = out.resolve()
    site = out / "site"
    version = json.loads((site / "VERSION.json").read_text(encoding="utf-8"))
    base = version["runtime_artifact_base"]
    pck = site / f"{base}.pck"
    target_root = out / "transport"
    if target_root.exists():
        raise SystemExit(f"refusing to reuse an existing transport directory: {target_root}")
    plan = part_plan(version["pck_size"])
    if [part["name"] for part in version["pck_parts"]] != [f"{base}.pck.part{suffix}" for suffix, _, _ in plan]:
        raise SystemExit("VERSION.json part list does not match the split plan")
    for source in sorted(site.rglob("*")):
        if not source.is_file() or source == pck:
            continue
        target = target_root / "site" / source.relative_to(site)
        target.parent.mkdir(parents=True, exist_ok=True)
        os.link(source, target)
    with pck.open("rb") as stream:
        for (suffix, offset, length), record in zip(plan, version["pck_parts"]):
            stream.seek(offset)
            data = stream.read(length)
            if hashlib.sha256(data).hexdigest() != record["sha256"] or length != record["bytes"]:
                raise SystemExit(f"part {suffix} does not match VERSION.json")
            (target_root / "site" / record["name"]).write_bytes(data)
    # Keep every byte exactly as verified: no line-ending or LFS filters in the payload branch.
    (target_root / ".gitattributes").write_text("* -text\n", encoding="utf-8", newline="\n")
    count = sum(1 for path in target_root.rglob("*") if path.is_file())
    return {"transport": str(target_root), "files": count, "parts": len(plan)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    stage_parser = commands.add_parser("stage")
    stage_parser.add_argument("release", type=Path)
    stage_parser.add_argument("out", type=Path)
    stage_parser.add_argument("--source-commit", required=True)
    stage_parser.add_argument("--godot-license", type=Path, default=DEFAULT_GODOT_LICENSE)
    stage_parser.add_argument("--source-note", default="")
    stage_parser.add_argument("--reviewed-hd", action='store_true')
    transport_parser = commands.add_parser("transport")
    transport_parser.add_argument("out", type=Path)
    args = parser.parse_args()
    if args.command == "stage":
        summary = stage(args.release, args.out, args.source_commit, args.godot_license, args.source_note, args.reviewed_hd)
        print("PAGES_STAGE=PASS " + json.dumps(summary))
    else:
        print("PAGES_TRANSPORT=PASS " + json.dumps(transport(args.out)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
