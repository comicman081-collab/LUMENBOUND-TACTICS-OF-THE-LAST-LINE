"""Verify the Web intro against the preserved master before publishing it."""
from __future__ import annotations
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FFMPEG = "C:/AI_SHARED/common_tools/ffmpeg/bin/ffmpeg.exe"
FFPROBE = "C:/AI_SHARED/common_tools/ffmpeg/bin/ffprobe.exe"


def main() -> None:
    source = ROOT / "work/video/intro_1080p_50s_20260910/intro_1080p_50s_with_existing_bgm.mp4"
    web = ROOT / "intro/web_1080p_50s/intro.mp4"
    master_manifest = json.loads((ROOT / "intro/completed_1080p_50s/manifest.json").read_text(encoding="utf-8"))
    expected_master = master_manifest["outputs"]["intro_1080p_50s_with_existing_bgm.mp4"]["sha256"]
    if hashlib.sha256(source.read_bytes()).hexdigest() != expected_master:
        raise ValueError("Preserved master no longer matches the approved production hash")
    subprocess.run([FFMPEG, "-v", "error", "-xerror", "-i", str(web), "-f", "null", "-"], check=True)
    probe = json.loads(subprocess.check_output([FFPROBE, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(web)]))
    video = next(s for s in probe["streams"] if s["codec_type"] == "video")
    audio = next(s for s in probe["streams"] if s["codec_type"] == "audio")
    if (video["width"], video["height"], video["codec_name"], audio["codec_name"]) != (1920, 1080, "h264", "aac"):
        raise ValueError("Wrong Web intro format")
    if float(probe["format"]["duration"]) != 50.0 or int(video["nb_frames"]) != 1200 or video["avg_frame_rate"] != "24/1":
        raise ValueError("Intro duration or frame count changed")
    def audio_hash(path: Path) -> str:
        data = subprocess.check_output([FFMPEG, "-v", "error", "-i", str(path), "-map", "0:a:0", "-c", "copy", "-f", "adts", "-"])
        return hashlib.sha256(data).hexdigest()
    soundtrack = audio_hash(source)
    if soundtrack != audio_hash(web):
        raise ValueError("Original intro BGM stream changed")
    quality = subprocess.run([FFMPEG, "-hide_banner", "-nostdin", "-i", str(source), "-i", str(web),
                              "-lavfi", "[0:v][1:v]ssim", "-an", "-f", "null", "-"],
                             capture_output=True, text=True, encoding="utf-8", errors="replace", check=True)
    score = float(re.findall(r"All:([0-9.]+)", quality.stderr)[-1])
    if score < .96:
        raise ValueError(f"Web video quality below review gate: {score}")
    def file_record(path: Path) -> dict:
        return {"path": path.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "bytes": path.stat().st_size}
    manifest = {"schema": 1, "source": file_record(source),
                "web": {**file_record(web), "width": 1920, "height": 1080, "duration": 50.0, "frames": 1200,
                        "frame_rate": "24/1", "video_codec": "h264", "audio_codec": "aac"},
                "audio_stream_preserved": True, "audio_stream_sha256": soundtrack, "ssim": score,
                "encoding": {"video": "libx264 preset veryslow CRF23 maxrate2000k bufsize4000k", "audio": "stream copy", "faststart": True},
                "original_files_preserved": True}
    web.with_name("manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    report = ROOT / "reports/sites_r21_intro_fix_20261001/media-validation.json"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"duration": 50, "resolution": "1920x1080", "bytes": web.stat().st_size, "audio_stream_preserved": True, "ssim": score}))


if __name__ == "__main__":
    main()
