from __future__ import annotations

import hashlib
import json
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "godot" / "assets" / "audio" / "audio_manifest.json"
SKILLS_PATH = ROOT / "data_source" / "skills.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
failures: list[str] = []
entries = manifest.get("entries", [])
entries_by_id = {str(entry.get("asset_id", "")): entry for entry in entries}

for entry in entries:
    asset_id = str(entry.get("asset_id", ""))
    rel = Path(str(entry["runtime_path"]).removeprefix("res://"))
    path = ROOT / "godot" / rel
    if not path.is_file():
        failures.append(f"missing:{asset_id}:{path}")
        continue
    suffix = path.suffix.lower()
    if suffix == ".wav":
        try:
            with wave.open(str(path), "rb") as reader:
                if reader.getnframes() <= 0 or reader.getframerate() <= 0:
                    failures.append(f"invalid_wav:{asset_id}")
                if entry.get("category") == "SFX" and reader.getframerate() < 32000:
                    failures.append(f"low_rate_sfx:{asset_id}:{reader.getframerate()}")
        except wave.Error as exc:
            failures.append(f"invalid_wav:{asset_id}:{exc}")
    elif suffix == ".ogg":
        if path.read_bytes()[:4] != b"OggS":
            failures.append(f"invalid_ogg:{asset_id}")
    if int(entry.get("runtime_bytes", 0)) != path.stat().st_size:
        failures.append(f"manifest_size_mismatch:{asset_id}")
    if str(entry.get("runtime_sha256", "")) != sha256(path):
        failures.append(f"manifest_hash_mismatch:{asset_id}")
    if not bool(entry.get("commercial_use", False)):
        failures.append(f"commercial_use_not_declared:{asset_id}")
    if str(entry.get("ownership_status", "LICENSE_UNRESOLVED")) == "LICENSE_UNRESOLVED":
        failures.append(f"license_unresolved:{asset_id}")

profiles = manifest.get("card_start_profiles", {})
skills = json.loads(SKILLS_PATH.read_text(encoding="utf-8"))
active_card_ids = {
    str(skill["id"])
    for skill in skills
    if str(skill.get("type", "")) in {"NORMAL_SKILL", "ULTIMATE_SKILL"}
}
missing_cards = sorted(active_card_ids - set(profiles))
if missing_cards:
    failures.append("missing_card_profiles:" + ",".join(missing_cards))

seen_profiles: dict[tuple[str, ...], str] = {}
for card_id, raw_layers in profiles.items():
    layers = tuple(str(asset_id) for asset_id in raw_layers)
    if len(layers) < 2:
        failures.append(f"card_profile_too_shallow:{card_id}")
    if layers in seen_profiles:
        failures.append(f"duplicate_card_profile:{card_id}:{seen_profiles[layers]}")
    seen_profiles[layers] = str(card_id)
    for asset_id in layers:
        if asset_id not in entries_by_id:
            failures.append(f"card_profile_missing_asset:{card_id}:{asset_id}")

required_events = {
    "PLAYER_BASIC_ATTACK", "PLAYER_NORMAL_SKILL", "PLAYER_ULTIMATE", "PLAYER_HIT",
    "ENEMY_BASIC_ATTACK", "ENEMY_SKILL", "ENEMY_HIT",
    "BOSS_BASIC_ATTACK", "BOSS_SKILL", "BOSS_HIT",
}
available_events = {str(entry.get("event", "")) for entry in entries}
for event_id in sorted(required_events - available_events):
    failures.append(f"missing_required_event:{event_id}")

public_sfx_count = sum(
    1 for entry in entries
    if entry.get("category") == "SFX" and entry.get("ownership_status") == "CC0-1.0"
)
if public_sfx_count < 40:
    failures.append(f"insufficient_public_cc0_sfx:{public_sfx_count}")

print(f"AUDIO_MANIFEST_ENTRIES={len(entries)}")
print(f"AUDIO_PUBLIC_CC0_SFX={public_sfx_count}")
print(f"AUDIO_CARD_PROFILES={len(profiles)}")
print(f"AUDIO_VALIDATION={'PASS' if not failures else 'FAIL'}")
if failures:
    print("\n".join(failures))
raise SystemExit(1 if failures else 0)
