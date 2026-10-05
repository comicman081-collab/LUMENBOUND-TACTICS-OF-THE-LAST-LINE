"""Include the verified browser intro that lives outside Godot's Web export."""
from __future__ import annotations

import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INTRO = ROOT / "intro/web_1080p_50s/intro.mp4"
MANIFEST = INTRO.with_name("manifest.json")


def verified_intro() -> tuple[Path, dict]:
    if not INTRO.is_file() or not MANIFEST.is_file():
        raise ValueError("Missing verified 1080p intro; Web exports require the separate /intro.mp4 sidecar")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    source = ROOT / manifest["source"]["path"]
    for path, expected in [(source, manifest["source"]), (INTRO, manifest["web"])]:
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected["sha256"] or path.stat().st_size != expected["bytes"]:
            raise ValueError(f"Intro hash mismatch: {path}")
    web = manifest["web"]
    if (web["width"], web["height"], web["duration"], web["video_codec"], web["audio_codec"]) != (1920, 1080, 50.0, "h264", "aac"):
        raise ValueError("Browser intro must remain H.264/AAC, 1080p, 50 seconds")
    if not manifest["audio_stream_preserved"] or web["bytes"] >= 20_000_000:
        raise ValueError("Intro audio preservation or Sites file-size gate failed")
    return INTRO, manifest


def stage_intro(site: Path) -> None:
    source, manifest = verified_intro()
    client = site / "dist/client"
    report_path = site / "reports/sites_update_20260920/staged_assets.json"
    if not client.is_dir() or not report_path.is_file():
        raise ValueError("Prepare the Sites checkout before staging its intro")
    shutil.copy2(source, client / "intro.mp4")
    report = json.loads(report_path.read_text(encoding="utf-8"))
    report["files"]["intro.mp4"] = {key: manifest["web"][key] for key in ("sha256", "bytes")}
    report["count"] = len(report["files"])
    report["intro_contract"] = {"route": "/intro.mp4", "width": 1920, "height": 1080, "duration": 50.0,
                                "audio_stream_sha256": manifest["audio_stream_sha256"]}
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    provenance = site / "reports/sites_intro_20261001.json"
    provenance.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    verifier = site / "scripts/verify-prebuilt.mjs"
    code = verifier.read_text(encoding="utf-8")
    if "SITES_INTRO_SIDECAR_REQUIRED" not in code:
        code += """
// SITES_INTRO_SIDECAR_REQUIRED: the movie is external to the Godot PCK.
if(!report.files['intro.mp4'] || !report.intro_contract)
  throw Error('Missing browser intro sidecar contract');
const intro=fs.readFileSync('dist/client/intro.mp4');
if(intro.subarray(4,8).toString()!=='ftyp' || intro.indexOf(Buffer.from('moov'))<0
   || intro.indexOf(Buffer.from('moov'))>intro.indexOf(Buffer.from('mdat')))
  throw Error('Intro must be a fast-start MP4, not an HTML fallback');
console.log('Verified separate 1080p/50s browser intro and preserved BGM.');
"""
        verifier.write_text(code, encoding="utf-8", newline="\n")
    print(json.dumps({"intro": "/intro.mp4", "bytes": manifest["web"]["bytes"], "sha256": manifest["web"]["sha256"]}))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: stage_sites_intro.py SITE_CHECKOUT")
    site = Path(sys.argv[1]).resolve()
    if ROOT / "work" not in site.parents:
        raise SystemExit("Sites checkout must stay inside the project work folder")
    stage_intro(site)
