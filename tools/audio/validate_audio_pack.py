from __future__ import annotations

import json
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
manifest = json.loads((ROOT / "godot/assets/audio/audio_manifest.json").read_text(encoding="utf-8"))
failures: list[str] = []
for entry in manifest.get("entries", []):
    rel = Path(entry["runtime_path"].removeprefix("res://"))
    path = ROOT / "godot" / rel
    if not path.is_file():
        failures.append(f"missing:{entry['asset_id']}:{path}")
        continue
    if path.suffix.lower() == ".wav":
        try:
            with wave.open(str(path), "rb") as reader:
                if reader.getnframes() <= 0 or reader.getframerate() <= 0:
                    failures.append(f"invalid_wav:{entry['asset_id']}")
        except wave.Error as exc:
            failures.append(f"invalid_wav:{entry['asset_id']}:{exc}")
    if int(entry.get("runtime_bytes", 0)) != path.stat().st_size:
        failures.append(f"manifest_size_mismatch:{entry['asset_id']}")
print(f"AUDIO_MANIFEST_ENTRIES={len(manifest.get('entries', []))}")
print(f"AUDIO_VALIDATION={'PASS' if not failures else 'FAIL'}")
if failures:
    print("\n".join(failures))
raise SystemExit(1 if failures else 0)
