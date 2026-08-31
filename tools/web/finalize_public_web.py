#!/usr/bin/env python3
"""Finalize one freshly exported Godot Web directory for public hosting.

This script deliberately operates only on the supplied staging directory. It
never uses the checked-in ``builds/web_release`` donor from older deployments,
so HTML, loader, WASM and PCK always come from the same Godot export.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path


PUBLIC_TITLE = "LUMENBOUND: TACTICS OF THE LAST LINE"
PUBLIC_CACHE_PREFIX = "LUMENBOUND-TACTICS-sw-cache-"
REQUIRED_EXPORT_FILES = (
    "index.html", "index.js", "index.service.worker.js", "index.manifest.json",
    "index.offline.html", "index.png", "index.icon.png", "index.apple-touch-icon.png",
    "index.144x144.png", "index.180x180.png", "index.512x512.png",
    "index.audio.worklet.js", "index.audio.position.worklet.js",
)


def replace_exact(text: str, needle: str, replacement: str, label: str) -> str:
    count = text.count(needle)
    if count != 1:
        raise SystemExit(f"expected exactly one {label}, found {count}")
    return text.replace(needle, replacement, 1)


def one_file(root: Path, suffix: str) -> Path:
    matches = sorted(root.glob(f"*{suffix}"))
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one {suffix} file in {root}, found {len(matches)}")
    if matches[0].stat().st_size <= 0:
        raise SystemExit(f"empty exported file: {matches[0]}")
    return matches[0]


def synchronize_file_size(html: str, filename: str, size: int) -> str:
    pattern = rf'("{re.escape(filename)}"\s*:\s*)\d+'
    html, count = re.subn(pattern, lambda match: match.group(1) + str(size), html, count=1)
    if count != 1:
        raise SystemExit(f"file size entry for {filename} is missing from index.html")
    return html


def finalize_html(root: Path, pck: Path, wasm: Path) -> None:
    html_path = root / "index.html"
    html = html_path.read_text(encoding="utf-8")
    html, count = re.subn(
        r"<title>.*?</title>", f"<title>{PUBLIC_TITLE}</title>", html,
        count=1, flags=re.DOTALL,
    )
    if count != 1:
        raise SystemExit("public browser title is missing from index.html")

    progress_css = """

/* LUMENBOUND_PUBLIC_PROGRESS */
#status {
\tbackground:
\t\tradial-gradient(circle at 50% 36%, rgba(36, 116, 123, .22), transparent 32%),
\t\tlinear-gradient(180deg, #06101a 0%, #02070d 100%);
}
#status-progress {
\tbottom: 13%;
\twidth: min(56%, 680px);
\theight: 10px;
\taccent-color: #77e3cf;
}
#status-copy {
\tposition: absolute;
\tleft: 5%;
\tright: 5%;
\tbottom: 17%;
\ttext-align: center;
\tfont: 600 clamp(14px, 1.7vw, 22px)/1.5 "Segoe UI", "Noto Sans KR", sans-serif;
\tletter-spacing: .08em;
\tcolor: #d9f7ee;
\ttext-shadow: 0 2px 12px #000;
}
#status-percent { color: #f1cf7a; }
""".rstrip()
    if "LUMENBOUND_PUBLIC_PROGRESS" not in html:
        html = replace_exact(html, "</style>", progress_css + "\n\t</style>", "style closing tag")

    if 'id="status-copy"' not in html:
        html, count = re.subn(
            r'(<img id="status-splash"[^>]*>)',
            r'\1\n\t\t\t<div id="status-copy">LOADING LUMENBOUND TACTICAL DATA · '
            r'<span id="status-percent">0%</span></div>',
            html, count=1,
        )
        if count != 1:
            raise SystemExit("status splash image is missing from index.html")

    progress_declaration = "const statusProgress = document.getElementById('status-progress');"
    if "const statusPercent = document.getElementById('status-percent');" not in html:
        html = replace_exact(
            html, progress_declaration,
            progress_declaration + "\n\tconst statusPercent = document.getElementById('status-percent');",
            "status progress declaration",
        )
    progress_max = "statusProgress.max = total;"
    if "statusPercent.textContent" not in html:
        html = replace_exact(
            html, progress_max,
            progress_max + "\n\t\t\t\t\tstatusPercent.textContent = "
            + "Math.max(1, Math.min(100, Math.round(current / total * 100))) + '%';",
            "status progress update",
        )

    html = synchronize_file_size(html, pck.name, pck.stat().st_size)
    html = synchronize_file_size(html, wasm.name, wasm.stat().st_size)
    html_path.write_text(html, encoding="utf-8", newline="\n")


def finalize_worker(root: Path, pck: Path, wasm: Path) -> None:
    worker_path = root / "index.service.worker.js"
    worker = worker_path.read_text(encoding="utf-8")
    worker, prefix_count = re.subn(
        r"const CACHE_PREFIX = '[^']+';",
        f"const CACHE_PREFIX = '{PUBLIC_CACHE_PREFIX}';",
        worker, count=1,
    )
    if prefix_count != 1:
        raise SystemExit("could not set the public service-worker cache prefix")

    install_needle = "event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)));"
    install_replacement = (
        "event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES))"
        ".then(() => self.skipWaiting()));"
    )
    worker = replace_exact(worker, install_needle, install_replacement, "service-worker install block")

    activate_needle = (
        "return ('navigationPreload' in self.registration) ? "
        "self.registration.navigationPreload.enable() : Promise.resolve();"
    )
    activate_replacement = (
        "return (('navigationPreload' in self.registration) ? "
        "self.registration.navigationPreload.enable() : Promise.resolve())"
        ".then(() => self.clients.claim());"
    )
    worker = replace_exact(worker, activate_needle, activate_replacement, "service-worker activate block")

    navigation_pattern = re.compile(
        r"\t\t\t\tif \(isNavigate\) \{.*?\n\t\t\t\t\}\n\t\t\t\tlet cached",
        re.DOTALL,
    )
    navigation_replacement = """\t\t\t\tif (isNavigate) {
\t\t\t\t\t// Fetch the current shell first so a stable Pages URL cannot pin an old build.
\t\t\t\t\ttry {
\t\t\t\t\t\treturn await fetchAndCache(event, cache, true);
\t\t\t\t\t} catch (e) {
\t\t\t\t\t\tconsole.warn('Navigation network error; using cached LUMENBOUND shell.', e); // eslint-disable-line no-console
\t\t\t\t\t\treturn (await cache.match(event.request))
\t\t\t\t\t\t\t|| (await cache.match(CACHED_FILES[0]))
\t\t\t\t\t\t\t|| (await caches.match(OFFLINE_URL));
\t\t\t\t\t}
\t\t\t\t}
\t\t\t\tlet cached"""
    worker, navigation_count = navigation_pattern.subn(navigation_replacement, worker, count=1)
    if navigation_count != 1:
        raise SystemExit("could not install network-first navigation in service worker")

    hash_inputs = (pck, wasm, root / "index.js", root / "index.html")
    cache_digest = hashlib.sha256(
        "|".join(hashlib.sha256(path.read_bytes()).hexdigest() for path in hash_inputs).encode("utf-8")
    ).hexdigest()
    worker, version_count = re.subn(
        r"const CACHE_VERSION = '[^']+';",
        f"const CACHE_VERSION = 'r7_{cache_digest[:16]}';",
        worker, count=1,
    )
    if version_count != 1:
        raise SystemExit("could not rotate the service-worker cache version")
    for contract in (
        "self.skipWaiting()", "self.clients.claim()",
        "Navigation network error; using cached LUMENBOUND shell.",
    ):
        if contract not in worker:
            raise SystemExit(f"service-worker update contract missing: {contract}")
    worker_path.write_text(worker, encoding="utf-8", newline="\n")


def scrub_policy(text: str) -> str:
    text = text.replace("`tools/local_art_pipeline/model_policy.json`", "빌드 시점 로컬 모델 허용 목록")
    return re.sub(r"`(?i:[A-Z]:\\[^`]+)`", "로컬 제작 모델 저장소", text)


def write_companion_files(
    root: Path, project_root: Path, godot_license: Path, source_commit: str,
    pck: Path, wasm: Path,
) -> None:
    manifest_path = root / "index.manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["name"] = PUBLIC_TITLE
    if manifest.get("orientation") != "any":
        raise SystemExit(f"PWA orientation must support desktop and mobile, got {manifest.get('orientation')!r}")
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8", newline="\n",
    )

    pck_hash = hashlib.sha256(pck.read_bytes()).hexdigest()
    wasm_hash = hashlib.sha256(wasm.read_bytes()).hexdigest()
    version = {
        "build_id": "LUMENBOUND_R7_WEB_MVP", "engine": "Godot 4.7.1-stable",
        "renderer": "Compatibility", "target": "Web HTML Release", "revision": "R7",
        "source_commit": source_commit, "release_pack_mode": "fresh_full_web_export",
        "pck_sha256": pck_hash, "pck_size": pck.stat().st_size,
        "wasm_sha256": wasm_hash, "wasm_size": wasm.stat().st_size,
        "mobile_orientation": "landscape_and_portrait",
        "created_utc": datetime.now(timezone.utc).isoformat(),
    }
    (root / "VERSION.json").write_text(
        json.dumps(version, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8", newline="\n",
    )
    (root / "DEPLOY_SHA.txt").write_text(
        f"source_commit={source_commit}\npck_sha256={pck_hash}\npck_size={pck.stat().st_size}\n"
        f"wasm_sha256={wasm_hash}\nwasm_size={wasm.stat().st_size}\n"
        "release_pack_mode=fresh_full_web_export\n",
        encoding="utf-8", newline="\n",
    )
    (root / "README_HTML.md").write_text(
        "# LUMENBOUND R7 Web MVP\n\nFresh Godot 4.7.1 Compatibility Web export. "
        "Serve this directory over HTTP.\nDesktop, mobile landscape and mobile portrait "
        "layouts are supported.\n",
        encoding="utf-8", newline="\n",
    )

    policy_path = project_root / "docs" / "LICENSE_POLICY.md"
    font_license = project_root / "godot" / "assets" / "fonts" / "NotoSansKR-OFL.txt"
    pako_licenses = project_root / "tools" / "web" / "PAKO_LICENSES.txt"
    for source in (policy_path, font_license, pako_licenses, godot_license):
        if not source.is_file() or source.stat().st_size <= 0:
            raise SystemExit(f"required license text is missing: {source}")
    notices = (
        "# LUMENBOUND R7 Web — License Notices\n\n## Project asset policy\n\n"
        + scrub_policy(policy_path.read_text(encoding="utf-8"))
        + "\n\n## Godot Engine 4.7.1\n\n" + godot_license.read_text(encoding="utf-8")
        + "\n\n## pako and embedded zlib-derived code\n\n"
        + pako_licenses.read_text(encoding="utf-8")
        + "\n\n## Noto Sans KR\n\n" + font_license.read_text(encoding="utf-8")
    )
    (root / "LICENSES.md").write_text(notices, encoding="utf-8", newline="\n")


def validate(root: Path, pck: Path, wasm: Path) -> None:
    required = REQUIRED_EXPORT_FILES + (
        pck.name, wasm.name, "README_HTML.md", "VERSION.json", "DEPLOY_SHA.txt", "LICENSES.md",
    )
    missing = [name for name in required if not (root / name).is_file() or (root / name).stat().st_size <= 0]
    if missing:
        raise SystemExit(f"public Web staging is incomplete: {', '.join(missing)}")
    if pck.stat().st_size >= 180_000_000:
        raise SystemExit(f"Web PCK exceeds the 180 MB release budget: {pck.stat().st_size}")
    if wasm.stat().st_size >= 26_214_400:
        raise SystemExit(f"compressed Web WASM exceeds the 25 MiB host budget: {wasm.stat().st_size}")
    if wasm.read_bytes()[:2] != b"\x1f\x8b":
        raise SystemExit("Web WASM staging file is not the expected deterministic gzip payload")

    public_text = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in root.iterdir()
        if path.is_file() and path.suffix.lower() in {".html", ".js", ".json", ".md", ".txt"}
    )
    leak = re.search(
        r"(?i)(?<![A-Za-z0-9_])[A-Z]:[\\/]|source_blends?|render_command|blender_sources|\.blend\b",
        public_text,
    )
    if leak:
        raise SystemExit(f"public Web companion files leak authoring lineage: {leak.group(0)!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("staging", type=Path)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--godot-license", type=Path, required=True)
    parser.add_argument("--source-commit", required=True)
    args = parser.parse_args()

    root = args.staging.resolve()
    if not root.is_dir():
        raise SystemExit(f"Web staging directory is missing: {root}")
    pck = one_file(root, ".pck")
    wasm = one_file(root, ".wasm")
    finalize_html(root, pck, wasm)
    finalize_worker(root, pck, wasm)
    write_companion_files(
        root, args.project_root.resolve(), args.godot_license.resolve(),
        args.source_commit, pck, wasm,
    )
    validate(root, pck, wasm)
    print(f"PUBLIC_WEB_STAGE={root}")
    print(f"PUBLIC_WEB_PCK_BYTES={pck.stat().st_size}")
    print(f"PUBLIC_WEB_WASM_GZIP_BYTES={wasm.stat().st_size}")
    print("PUBLIC_WEB_FINALIZE=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
