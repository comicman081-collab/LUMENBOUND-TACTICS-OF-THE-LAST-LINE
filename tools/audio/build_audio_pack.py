"""Build the small runtime audio pack from the user's local Sound folder.

No network or remote generation is used. Long PCM BGM files are reduced to a
short, 22.05 kHz mono loop so the offline Web build remains practical. The
English title source is an MP3 stream stored with a .wav suffix; it is trimmed
at frame boundaries without invoking an external encoder.
Short effects are copied byte-for-byte and the original Sound folder is never
modified.
"""
from __future__ import annotations

import csv
import hashlib
import json
import shutil
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT.parent / "Sound"
MANIFEST_PATH = ROOT / "data_source" / "audio_manifest.json"
OUTPUT_ROOT = ROOT / "godot" / "assets" / "audio"
REPORT_ROOT = ROOT / "reports" / "audio"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def compact_bgm(source: Path, target: Path, max_seconds: float) -> None:
    with wave.open(str(source), "rb") as reader:
        channels = reader.getnchannels()
        sample_width = reader.getsampwidth()
        source_rate = reader.getframerate()
        frame_limit = min(reader.getnframes(), int(source_rate * max_seconds))
        raw = reader.readframes(frame_limit)
    if sample_width == 2:
        samples = np.frombuffer(raw, dtype="<i2")
    elif sample_width == 3:
        packed = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        samples = packed[:, 0] | (packed[:, 1] << 8) | (packed[:, 2] << 16)
        sign_bit = samples & 0x800000
        samples = samples - (sign_bit << 1)
        samples = samples.astype(np.float32) / 256.0
    else:
        raise ValueError(f"unsupported BGM sample width: {sample_width}")
    if channels > 1:
        samples = samples.reshape(-1, channels).astype(np.float32).mean(axis=1)
    else:
        samples = samples.astype(np.float32)
    target_rate = 22050
    output_frames = max(1, int(round(len(samples) * target_rate / source_rate)))
    source_axis = np.linspace(0.0, 1.0, num=len(samples), endpoint=False)
    target_axis = np.linspace(0.0, 1.0, num=output_frames, endpoint=False)
    resized = np.interp(target_axis, source_axis, samples)
    resized = np.clip(np.rint(resized), -32768, 32767).astype("<i2")
    target.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(target), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(target_rate)
        writer.writeframes(resized.tobytes())


def compact_mp3(source: Path, target: Path, max_seconds: float) -> None:
    """Keep an ID3 header and complete MP3 frames up to max_seconds.

    The supplied English title track is an MP3 with a legacy .wav filename.
    Keeping complete frames preserves decoder compatibility while avoiding any
    external codec or network dependency.
    """
    payload = source.read_bytes()
    start = 0
    if payload[:3] == b"ID3" and len(payload) >= 10:
        tag_size = (
            (payload[6] & 0x7F) << 21
            | (payload[7] & 0x7F) << 14
            | (payload[8] & 0x7F) << 7
            | (payload[9] & 0x7F)
        )
        start = 10 + tag_size + (10 if payload[5] & 0x10 else 0)
    frame_start = start
    while frame_start + 4 <= len(payload):
        if payload[frame_start] == 0xFF and (payload[frame_start + 1] & 0xE0) == 0xE0:
            break
        frame_start += 1
    if frame_start + 4 > len(payload):
        raise ValueError(f"no MP3 frame sync found: {source}")
    header = int.from_bytes(payload[frame_start:frame_start + 4], "big")
    version_id = (header >> 19) & 0x3
    layer = (header >> 17) & 0x3
    if layer != 1 or version_id == 1:
        raise ValueError(f"unsupported MP3 stream: {source}")
    bitrate_index = (header >> 12) & 0xF
    sample_index = (header >> 10) & 0x3
    padding = (header >> 9) & 0x1
    bitrate_tables = {
        3: [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
        2: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
        0: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
    }
    sample_tables = {
        3: [44100, 48000, 32000],
        2: [22050, 24000, 16000],
        0: [11025, 12000, 8000],
    }
    bitrates = bitrate_tables[version_id]
    sample_rates = sample_tables[version_id]
    if bitrate_index <= 0 or bitrate_index >= len(bitrates) or sample_index >= 3:
        raise ValueError(f"invalid MP3 header: {source}")
    bitrate_kbps = bitrates[bitrate_index]
    sample_rate = sample_rates[sample_index]
    samples_per_frame = 1152 if version_id == 3 else 576
    frame_scale = 144000 if version_id == 3 else 72000
    max_frames = max(1, int(max_seconds * sample_rate / samples_per_frame + 0.999))
    cursor = frame_start
    frames = []
    for _ in range(max_frames):
        if cursor + 4 > len(payload):
            break
        h = int.from_bytes(payload[cursor:cursor + 4], "big")
        if payload[cursor] != 0xFF or (payload[cursor + 1] & 0xE0) != 0xE0:
            break
        v = (h >> 19) & 0x3
        l = (h >> 17) & 0x3
        bi = (h >> 12) & 0xF
        si = (h >> 10) & 0x3
        pad = (h >> 9) & 0x1
        if v not in bitrate_tables or l != 1 or bi <= 0 or bi >= len(bitrate_tables[v]) or si >= 3:
            break
        length = int(frame_scale * bitrate_tables[v][bi] * 1000 / sample_tables[v][si]) + pad
        if length < 4 or cursor + length > len(payload):
            break
        frames.append(payload[cursor:cursor + length])
        cursor += length
    if not frames:
        raise ValueError(f"no complete MP3 frames found: {source}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(payload[:frame_start] + b"".join(frames))


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    entries = manifest.get("entries", [])
    ownership_declaration = manifest.get("ownership_declaration", {})
    if not entries:
        raise SystemExit("audio manifest has no entries")
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    REPORT_ROOT.mkdir(parents=True, exist_ok=True)
    resolved = []
    for entry in entries:
        source = SOURCE_ROOT / entry["source_path"]
        if not source.is_file():
            raise FileNotFoundError(source)
        runtime_rel = Path(entry["runtime_path"].removeprefix("res://assets/audio/"))
        target = OUTPUT_ROOT / runtime_rel
        if entry["format"] == "PCM_WAV_COMPACT":
            compact_bgm(source, target, float(entry.get("max_seconds", 30)))
        elif entry["format"] == "MP3_SOURCE_RELABELED":
            compact_mp3(source, target, float(entry.get("max_seconds", 30)))
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        item = dict(entry)
        item["source_sha256"] = sha256(source)
        item["source_bytes"] = source.stat().st_size
        item["runtime_sha256"] = sha256(target)
        item["runtime_bytes"] = target.stat().st_size
        # Rights are carried from the source-of-truth declaration rather than
        # reset by every sync.  This keeps a user-provided ownership statement
        # auditable while preserving the original Sound folder unchanged.
        item["ownership_status"] = str(entry.get("ownership_status", ownership_declaration.get("ownership_status", "LICENSE_UNRESOLVED")))
        item["commercial_use"] = bool(entry.get("commercial_use", ownership_declaration.get("commercial_use", False)))
        item["attribution_required"] = bool(entry.get("attribution_required", ownership_declaration.get("attribution_required", False)))
        item["rights_basis"] = str(entry.get("rights_basis", ownership_declaration.get("rights_basis", "")))
        item["runtime_path"] = entry["runtime_path"]
        resolved.append(item)
    output_manifest = {
        "schema_version": 1,
        "source_root": str(SOURCE_ROOT),
        "generated_by": "tools/audio/build_audio_pack.py",
        "ownership_declaration": ownership_declaration,
        "entries": resolved,
    }
    (OUTPUT_ROOT / "audio_manifest.json").write_text(
        json.dumps(output_manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    with (REPORT_ROOT / "AUDIO_LINEAGE_AUDIT.csv").open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=[
                "asset_id", "category", "event", "source_path", "runtime_path",
                "source_bytes", "runtime_bytes", "source_sha256", "runtime_sha256",
                "ownership_status", "commercial_use",
            ],
        )
        writer.writeheader()
        for entry in resolved:
            writer.writerow({field: entry.get(field, "") for field in writer.fieldnames})
    print(f"AUDIO_PACK_ENTRIES={len(resolved)}")
    print(f"AUDIO_PACK_BYTES={sum(int(item['runtime_bytes']) for item in resolved)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
