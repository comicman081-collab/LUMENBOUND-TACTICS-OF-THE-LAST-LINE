"""Create compact WebAudio speech derivatives only inside a Sites checkout.

The verified Godot release and all original BGM/SFX/voice files stay read-only.
Keep the existing voice paths and line IDs; update deployment hash manifests.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FFMPEG = Path(r"C:\AI_SHARED\common_tools\ffmpeg\bin\ffmpeg.exe")
FFPROBE = FFMPEG.with_name("ffprobe.exe")


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def probe(path):
    data = json.loads(subprocess.check_output([
        str(FFPROBE), "-v", "error", "-show_entries",
        "stream=codec_name,channels:format=duration", "-of", "json", str(path)
    ], creationflags=subprocess.CREATE_NO_WINDOW))
    return float(data["format"]["duration"]), data["streams"][0]


def decode_pcm(path):
    return subprocess.check_output([
        str(FFMPEG), "-v", "error", "-i", str(path), "-ac", "1", "-ar", "24000", "-f", "s16le", "-"
    ], creationflags=subprocess.CREATE_NO_WINDOW)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path)
    parser.add_argument("--bitrate", choices=["32k", "24k"], default="32k")
    args = parser.parse_args()
    site = args.checkout.resolve()
    if not site.is_relative_to(ROOT / "work") or not (site / ".openai/hosting.json").is_file():
        raise ValueError("Expected project-local Sites checkout")
    client = site / "dist/client"
    audio_path = client / "audio_sidecars.json"
    stage_path = site / "reports/sites_update_20260920/staged_assets.json"
    report_path = site / ("reports/sites_voice_compaction_20261001.json" if args.bitrate == "32k"
                          else "reports/sites_voice_compaction_24k_20261001.json")
    if report_path.exists():
        raise ValueError("Speech compaction already completed; do not encode a derivative again")
    audio = json.loads(audio_path.read_text(encoding="utf-8"))
    original_audio = json.loads((ROOT / "builds/web_visual_r21_release/audio_sidecars.json").read_text(encoding="utf-8"))
    stage = json.loads(stage_path.read_text(encoding="utf-8"))
    for tool in (FFMPEG, FFPROBE):
        if not tool.is_file():
            raise ValueError(f"Missing installed audio tool: {tool}")

    def encode(item):
        name, record = item
        target = client / name
        source = ROOT / "builds/web_visual_r21_release" / name
        if not name.startswith("_audio/voice/ja/") or target.is_symlink() or not target.resolve().is_relative_to(client):
            raise ValueError("Unsafe voice derivative path")
        original_hash = sha256(source)
        original_bytes = source.stat().st_size
        if original_hash != original_audio["voice"][name]["sha256"] or original_hash != stage["files"][name]["sha256"]:
            raise ValueError("Input voice does not match verified R21 source: " + name)
        original_duration, source_stream = probe(source)
        if source_stream["codec_name"] != "vorbis" or source_stream["channels"] != 1:
            raise ValueError("Unexpected source voice format: " + name)
        pcm = decode_pcm(source)
        if not pcm or len(pcm) % 2:
            raise ValueError("Invalid decoded voice samples: " + name)
        candidate = target.with_suffix(".web" + args.bitrate.removesuffix("k") + ".tmp")
        subprocess.run([
            str(FFMPEG), "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
            "-f", "s16le", "-ar", "24000", "-ac", "1", "-i", "pipe:0",
            "-map", "0:a:0", "-ac", "1", "-ar", "24000", "-c:a", "libopus", "-b:a", args.bitrate,
            "-vbr", "on", "-application", "voip", "-threads", "1", "-map_metadata", "-1", "-f", "ogg", str(candidate)
        ], input=pcm, check=True, creationflags=subprocess.CREATE_NO_WINDOW)
        duration, stream = probe(candidate)
        decoded = decode_pcm(candidate)
        if stream["codec_name"] != "opus" or stream["channels"] != 1 or len(decoded) != len(pcm):
            raise ValueError("Voice content duration/format changed: " + name)
        derivative = {"sha256": sha256(candidate), "bytes": candidate.stat().st_size}
        if derivative["bytes"] <= 0:
            raise ValueError("Empty speech derivative")
        os.replace(candidate, target)
        return name, {
            "source_sha256": original_hash, "source_bytes": original_bytes,
            "source_duration": original_duration, "duration": duration,
            "decoded_samples": len(pcm) // 2, "decoded_duration": len(pcm) / 48000, **derivative
        }

    records = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for index, (name, item) in enumerate(pool.map(encode, sorted(audio["voice"].items())), 1):
            records[name] = item
            audio["voice"][name].update({"sha256": item["sha256"], "bytes": item["bytes"]})
            stage["staged_rewrites"][name] = {"sha256": item["sha256"], "bytes": item["bytes"]}
            if index % 250 == 0:
                print(f"WEB_VOICE_COMPACT_VERIFIED {index}/{len(audio['voice'])}", flush=True)
    audio_path.write_text(json.dumps(audio, indent=2) + "\n", encoding="utf-8", newline="\n")
    stage["staged_rewrites"]["audio_sidecars.json"] = {"sha256": sha256(audio_path), "bytes": audio_path.stat().st_size}
    stage_path.write_text(json.dumps(stage, indent=2) + "\n", encoding="utf-8", newline="\n")
    report = {"schema_version": 1, "codec": "opus", "container": "ogg", "bitrate": args.bitrate,
              "application": "voip", "source_release": "builds/web_visual_r21_release", "files": records,
              "original_bytes": sum(item["source_bytes"] for item in records.values()),
              "web_bytes": sum(item["bytes"] for item in records.values())}
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({key: value for key, value in report.items() if key != "files"}), flush=True)


if __name__ == "__main__":
    main()
