"""Build the runtime audio pack from local, auditable source material.

The user's BGM remains in the adjacent Sound folder. Public SFX are checked into
``data_source/audio_source/public_cc0`` with source-page and CC0 lineage. The
96 kHz/24-bit firearm masters are transient-trimmed, peak-normalized and reduced
to 48 kHz/16-bit stereo for the offline Web build; the masters are never edited.
Already compact Ogg effects are copied byte-for-byte. No network access or
remote generation occurs while this builder runs.
"""
from __future__ import annotations

import csv
import hashlib
import json
import re
import shutil
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT.parent / "Sound"
MANIFEST_PATH = ROOT / "data_source" / "audio_manifest.json"
OUTPUT_ROOT = ROOT / "godot" / "assets" / "audio"
REPORT_ROOT = ROOT / "reports" / "audio"
SKILLS_PATH = ROOT / "data_source" / "skills.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _asset_fragment(value: str) -> str:
    """Return a stable lowercase manifest identifier fragment."""
    return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")


def _expand_public_sfx_collections(manifest: dict) -> list[dict]:
    """Expand compact, directory-based CC0 source declarations.

    Source collections keep the hand-authored manifest readable while every
    emitted runtime entry still carries its own creator, source URL, license,
    hash and commercial-use declaration in the lineage report.
    """
    event_by_asset: dict[str, str] = {}
    for event_id, asset_ids in manifest.get("event_assignments", {}).items():
        for asset_id in asset_ids:
            asset_id = str(asset_id)
            if asset_id in event_by_asset:
                raise ValueError(
                    f"public SFX asset assigned to multiple events: {asset_id}"
                )
            event_by_asset[asset_id] = str(event_id)

    expanded: list[dict] = []
    seen_ids: set[str] = set()
    for collection in manifest.get("public_sfx_collections", []):
        source_root_rel = Path(str(collection["source_root"]))
        source_root = ROOT / source_root_rel
        if not source_root.is_dir():
            raise FileNotFoundError(source_root)
        matches = sorted(
            path for path in source_root.glob(str(collection.get("glob", "*")))
            if path.is_file()
        )
        if not matches:
            raise ValueError(f"public SFX collection is empty: {source_root}")
        prefix = str(collection["asset_id_prefix"])
        runtime_root = str(collection["runtime_root"]).rstrip("/")
        overrides = collection.get("file_overrides", {})
        for source in matches:
            asset_id = f"{prefix}_{_asset_fragment(source.stem)}"
            if asset_id in seen_ids:
                raise ValueError(f"duplicate public SFX asset id: {asset_id}")
            seen_ids.add(asset_id)
            entry = {
                "asset_id": asset_id,
                "category": "SFX",
                "event": event_by_asset.get(asset_id, ""),
                "source_scope": "PROJECT",
                "source_path": source.relative_to(ROOT).as_posix(),
                "runtime_path": f"{runtime_root}/{source.name}",
                "format": str(collection["format"]),
                "max_seconds": float(collection.get("max_seconds", 0.0)),
                "target_sample_rate": int(collection.get("target_sample_rate", 48000)),
                "target_peak_db": float(collection.get("target_peak_db", -1.5)),
                "gain_db": float(collection.get("gain_db", 0.0)),
                "pitch_scale": float(collection.get("pitch_scale", 1.0)),
                "ownership_status": str(collection.get("ownership_status", "LICENSE_UNRESOLVED")),
                "commercial_use": bool(collection.get("commercial_use", False)),
                "attribution_required": bool(collection.get("attribution_required", True)),
                "rights_basis": str(collection.get("rights_basis", "")),
                "license_name": str(collection.get("license_name", "")),
                "license_url": str(collection.get("license_url", "")),
                "source_url": str(collection.get("source_url", "")),
                "creator": str(collection.get("creator", "")),
            }
            entry.update(overrides.get(source.name, {}))
            expanded.append(entry)

    unknown_assignments = sorted(set(event_by_asset) - seen_ids)
    if unknown_assignments:
        raise ValueError(
            "event assignments reference missing public assets: "
            + ", ".join(unknown_assignments)
        )
    return expanded


def _pcm_to_float(raw: bytes, sample_width: int) -> np.ndarray:
    if sample_width == 1:
        return (np.frombuffer(raw, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    if sample_width == 2:
        return np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    if sample_width == 3:
        packed = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        values = packed[:, 0] | (packed[:, 1] << 8) | (packed[:, 2] << 16)
        values = values - ((values & 0x800000) << 1)
        return values.astype(np.float32) / 8388608.0
    if sample_width == 4:
        return np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
    raise ValueError(f"unsupported PCM sample width: {sample_width}")


def compact_sfx(
    source: Path,
    target: Path,
    max_seconds: float,
    target_rate: int,
    target_peak_db: float,
) -> None:
    """Make a short Web-ready PCM effect without flattening its transient."""
    with wave.open(str(source), "rb") as reader:
        channels = reader.getnchannels()
        sample_width = reader.getsampwidth()
        source_rate = reader.getframerate()
        samples = _pcm_to_float(reader.readframes(reader.getnframes()), sample_width)
    if channels <= 0 or samples.size == 0:
        raise ValueError(f"empty SFX source: {source}")
    samples = samples.reshape(-1, channels)
    mono = np.max(np.abs(samples), axis=1)

    # Prepared firearm masters include pre-roll and a long field tail. Locate
    # the first intentional transient using a short moving envelope, retaining
    # 15 ms of attack lead so the muzzle crack never feels clipped.
    envelope_window = max(1, int(round(source_rate * 0.004)))
    kernel = np.ones(envelope_window, dtype=np.float32) / envelope_window
    envelope = np.convolve(mono, kernel, mode="same")
    peak = float(np.max(envelope))
    floor = float(np.percentile(envelope, 20.0))
    threshold = max(peak * 0.075, floor * 8.0, 1e-4)
    candidates = np.flatnonzero(envelope >= threshold)
    onset = int(candidates[0]) if candidates.size else 0
    start = max(0, onset - int(round(source_rate * 0.015)))
    frame_limit = samples.shape[0] - start
    if max_seconds > 0.0:
        frame_limit = min(frame_limit, max(1, int(round(source_rate * max_seconds))))
    samples = samples[start:start + frame_limit]

    if source_rate != target_rate:
        output_frames = max(1, int(round(samples.shape[0] * target_rate / source_rate)))
        source_axis = np.linspace(0.0, 1.0, num=samples.shape[0], endpoint=False)
        target_axis = np.linspace(0.0, 1.0, num=output_frames, endpoint=False)
        samples = np.column_stack([
            np.interp(target_axis, source_axis, samples[:, channel])
            for channel in range(samples.shape[1])
        ]).astype(np.float32)

    target_peak = pow(10.0, target_peak_db / 20.0)
    current_peak = float(np.max(np.abs(samples)))
    if current_peak > 1e-7:
        samples *= target_peak / current_peak
    fade_in_frames = min(samples.shape[0] // 4, max(1, int(target_rate * 0.002)))
    fade_out_frames = min(samples.shape[0] // 4, max(1, int(target_rate * 0.025)))
    samples[:fade_in_frames] *= np.linspace(0.0, 1.0, fade_in_frames)[:, None]
    samples[-fade_out_frames:] *= np.linspace(1.0, 0.0, fade_out_frames)[:, None]
    encoded = np.clip(np.rint(samples * 32767.0), -32768, 32767).astype("<i2")
    target.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(target), "wb") as writer:
        writer.setnchannels(channels)
        writer.setsampwidth(2)
        writer.setframerate(target_rate)
        writer.writeframes(encoded.tobytes())


def _build_card_start_profiles(manifest: dict, asset_ids: set[str]) -> tuple[dict, list[dict]]:
    """Assign a unique two-layer audible signature to every active card."""
    config = manifest.get("card_start_profile_config", {})
    damage_bases = [str(value) for value in config.get("damage_base_asset_ids", [])]
    support_bases = [str(value) for value in config.get("support_base_asset_ids", [])]
    accents = [str(value) for value in config.get("accent_asset_ids", [])]
    for asset_id in damage_bases + support_bases + accents:
        if asset_id not in asset_ids:
            raise ValueError(f"card audio profile references missing asset: {asset_id}")
    if not damage_bases or not support_bases or not accents:
        raise ValueError("card audio profile pools must not be empty")

    skills = json.loads(SKILLS_PATH.read_text(encoding="utf-8"))
    active_skills = sorted(
        (skill for skill in skills if str(skill.get("type", "")) in {"NORMAL_SKILL", "ULTIMATE_SKILL"}),
        key=lambda skill: str(skill["id"]),
    )
    damage_effects = {"DAMAGE", "AOE_DAMAGE", "SLOW", "DEBUFF"}
    grouped: dict[str, list[dict]] = {"DAMAGE": [], "SUPPORT": []}
    for skill in active_skills:
        group = "DAMAGE" if str(skill.get("effect", "")) in damage_effects else "SUPPORT"
        grouped[group].append(skill)
    for card_id in config.get("extra_damage_card_ids", []):
        grouped["DAMAGE"].append({"id": str(card_id), "effect": "BOSS_PATTERN"})
    for card_id in config.get("extra_support_card_ids", []):
        grouped["SUPPORT"].append({"id": str(card_id), "effect": "BOSS_PATTERN_SUPPORT"})

    profiles: dict[str, list[str]] = {}
    audit_rows: list[dict] = []
    used_pairs: set[tuple[str, str]] = set()
    for group, cards in grouped.items():
        bases = damage_bases if group == "DAMAGE" else support_bases
        pairs = [(base, accent) for accent in accents for base in bases if accent != base]
        if len(cards) > len(pairs):
            raise ValueError(f"not enough unique {group.lower()} card audio pairs")
        for index, card in enumerate(cards):
            pair = pairs[index]
            if pair in used_pairs:
                raise ValueError(f"duplicate card audio pair: {pair}")
            used_pairs.add(pair)
            card_id = str(card["id"])
            profiles[card_id] = [pair[0], pair[1]]
            audit_rows.append({
                "card_id": card_id,
                "profile_group": group,
                "effect": str(card.get("effect", "")),
                "base_asset_id": pair[0],
                "accent_asset_id": pair[1],
            })
    return profiles, audit_rows


def compact_bgm(
    source: Path,
    target: Path,
    max_seconds: float,
    loop_smoothing_ms: float,
    target_rate: int,
) -> None:
    with wave.open(str(source), "rb") as reader:
        channels = reader.getnchannels()
        sample_width = reader.getsampwidth()
        source_rate = reader.getframerate()
        frame_limit = reader.getnframes() if max_seconds <= 0.0 else min(
            reader.getnframes(), int(source_rate * max_seconds)
        )
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
    if target_rate <= 0:
        raise ValueError(f"target BGM sample rate must be positive: {target_rate}")
    output_frames = max(1, int(round(len(samples) * target_rate / source_rate)))
    source_axis = np.linspace(0.0, 1.0, num=len(samples), endpoint=False)
    target_axis = np.linspace(0.0, 1.0, num=output_frames, endpoint=False)
    resized = np.interp(target_axis, source_axis, samples)
    # Some authored tracks do not end on a zero crossing. Taper only the very
    # edge; AudioService supplies the audible two-player crossfade at playback
    # time without destructively shortening the user's original composition.
    smoothing_frames = min(
        len(resized) // 4,
        max(0, int(round(target_rate * loop_smoothing_ms / 1000.0))),
    )
    if smoothing_frames > 1:
        fade_in = np.linspace(0.0, 1.0, num=smoothing_frames, endpoint=True)
        resized[:smoothing_frames] *= fade_in
        resized[-smoothing_frames:] *= fade_in[::-1]
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
    if max_seconds <= 0.0:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        return
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
    entries = list(manifest.get("entries", []))
    entries.extend(_expand_public_sfx_collections(manifest))
    ownership_declaration = manifest.get("ownership_declaration", {})
    if not entries:
        raise SystemExit("audio manifest has no entries")
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    REPORT_ROOT.mkdir(parents=True, exist_ok=True)
    resolved = []
    for entry in entries:
        source = (
            ROOT / entry["source_path"]
            if str(entry.get("source_scope", "SOUND")) == "PROJECT"
            else SOURCE_ROOT / entry["source_path"]
        )
        if not source.is_file():
            raise FileNotFoundError(source)
        runtime_rel = Path(entry["runtime_path"].removeprefix("res://assets/audio/"))
        target = OUTPUT_ROOT / runtime_rel
        if entry["format"] == "PCM_WAV_COMPACT":
            compact_bgm(
                source,
                target,
                float(entry.get("max_seconds", 30)),
                float(entry.get("loop_smoothing_ms", 20)),
                int(entry.get("target_sample_rate", 22050)),
            )
        elif entry["format"] == "MP3_SOURCE_RELABELED":
            compact_mp3(source, target, float(entry.get("max_seconds", 30)))
        elif entry["format"] == "PCM_WAV_SFX_TRIMMED":
            compact_sfx(
                source,
                target,
                float(entry.get("max_seconds", 2.4)),
                int(entry.get("target_sample_rate", 48000)),
                float(entry.get("target_peak_db", -1.5)),
            )
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
        item["license_name"] = str(entry.get("license_name", ownership_declaration.get("license_name", "")))
        item["license_url"] = str(entry.get("license_url", ownership_declaration.get("license_url", "")))
        item["source_url"] = str(entry.get("source_url", ""))
        item["creator"] = str(entry.get("creator", ""))
        item["runtime_path"] = entry["runtime_path"]
        resolved.append(item)
    card_start_profiles, card_profile_rows = _build_card_start_profiles(
        manifest, {str(entry["asset_id"]) for entry in resolved}
    )
    # The browser only needs event-to-runtime mapping plus integrity/ownership.
    # Keep workstation paths and reference-oriented source filenames in the
    # private lineage CSV/data source, never in the Godot PCK.
    runtime_entries = []
    runtime_keys = (
        "asset_id", "category", "event", "runtime_path", "format", "loop",
        "max_seconds", "loop_smoothing_ms",
        "runtime_sha256", "runtime_bytes", "ownership_status",
        "commercial_use", "attribution_required", "gain_db", "pitch_scale",
    )
    for entry in resolved:
        runtime_entries.append({key: entry[key] for key in runtime_keys if key in entry})
    output_manifest = {
        "schema_version": 1,
        "generated_by": "tools/audio/build_audio_pack.py",
        "ownership_declaration": {
            "ownership_status": "PER_ENTRY_DECLARED",
            "commercial_use": all(bool(entry.get("commercial_use", False)) for entry in resolved),
            "attribution_required": any(bool(entry.get("attribution_required", False)) for entry in resolved),
        },
        "entries": runtime_entries,
        "card_start_profiles": card_start_profiles,
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
                "ownership_status", "commercial_use", "attribution_required",
                "license_name", "license_url", "source_url", "creator", "rights_basis",
            ],
        )
        writer.writeheader()
        for entry in resolved:
            writer.writerow({field: entry.get(field, "") for field in writer.fieldnames})
    with (REPORT_ROOT / "CARD_START_AUDIO_AUDIT.csv").open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=["card_id", "profile_group", "effect", "base_asset_id", "accent_asset_id"],
        )
        writer.writeheader()
        writer.writerows(card_profile_rows)
    print(f"AUDIO_PACK_ENTRIES={len(resolved)}")
    print(f"AUDIO_PACK_BYTES={sum(int(item['runtime_bytes']) for item in resolved)}")
    print(f"CARD_START_PROFILES={len(card_start_profiles)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
