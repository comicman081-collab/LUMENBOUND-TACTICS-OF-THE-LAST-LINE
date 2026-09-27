"""Stage browser-owned BGM, combat SFX and story voice sidecars with verified source hashes."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = "audio_sidecars.json"
BGM_ROOT = ROOT / "godot/assets/audio/bgm"
SFX_ROOT = ROOT / "godot/assets/audio/sfx/public"
VOICE_ROOT = ROOT / "godot/assets/audio/voice/ja"
VOICE_PREFIX = "res://assets/audio/voice/ja/"
# Schema 2 builds predate story voices; they stay valid without a voice set.
SCHEMA = 3


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def sources(root=ROOT):
    data = json.loads((root / "godot/assets/audio/audio_manifest.json").read_text(encoding="utf-8"))
    bgm, sfx = {}, {}
    for item in data["entries"]:
        category = item.get("category")
        if category not in {"BGM", "SFX"}:
            continue
        source = root / "godot" / item["runtime_path"].removeprefix("res://")
        if category == "BGM":
            if not source.resolve().is_relative_to(BGM_ROOT.resolve()):
                raise ValueError("Unsafe BGM source")
            destination = "_audio/bgm/" + source.name
            collection = bgm
        else:
            if not source.resolve().is_relative_to(SFX_ROOT.resolve()):
                raise ValueError("Unsafe SFX source")
            destination = "_audio/sfx/" + source.resolve().relative_to(SFX_ROOT.resolve()).as_posix()
            collection = sfx
        record = {"asset_id": item["asset_id"], "sha256": sha256(source), "bytes": source.stat().st_size}
        prior = collection.get(destination)
        if prior and prior != (source, record):
            raise ValueError("Conflicting sidecar record: " + destination)
        collection[destination] = (source, record)
    if len(bgm) != 5:
        raise ValueError("Expected the five existing BGM tracks")
    if not sfx:
        raise ValueError("Expected combat SFX sidecars")
    voice = {}
    voice_manifest = json.loads((root / "godot/assets/audio/voice/ja/voice_manifest.json").read_text(encoding="utf-8"))
    for runtime_path in sorted(set(voice_manifest["by_text_key"].values())):
        if not runtime_path.startswith(VOICE_PREFIX):
            raise ValueError("Unsafe voice source")
        source = root / "godot" / runtime_path.removeprefix("res://")
        if not source.resolve().is_relative_to(VOICE_ROOT.resolve()):
            raise ValueError("Unsafe voice source")
        record = {"voice_id": source.stem, "sha256": sha256(source), "bytes": source.stat().st_size}
        voice["_audio/voice/ja/" + source.name] = (source, record)
    if not voice:
        raise ValueError("Expected story voice sidecars")
    return {"tracks": bgm, "sfx": sfx, "voice": voice}


def validate(export, root=ROOT):
    manifest = json.loads((export / MANIFEST).read_text(encoding="utf-8"))
    expected = sources(root)
    schema = int(manifest.get("schema_version", 0))
    if schema not in (2, SCHEMA):
        raise ValueError("Audio sidecar manifest schema mismatch")
    if schema == 2:
        expected.pop("voice")
    for key, expected_records in expected.items():
        records = manifest.get(key, {})
        if set(records) != set(expected_records):
            raise ValueError("Audio sidecar set mismatch: " + key)
        for name, (source, expected_record) in expected_records.items():
            target = export / name
            record = records[name]
            if target.is_symlink() or not target.resolve().is_relative_to(export.resolve()):
                raise ValueError("Unsafe audio sidecar")
            if record != expected_record or sha256(target) != record["sha256"]:
                raise ValueError("Audio sidecar hash mismatch: " + name)
            if target.stat().st_size != record["bytes"]:
                raise ValueError("Audio sidecar size mismatch")
    return manifest


def stage(export, root=ROOT):
    export = export.resolve()
    if not export.is_relative_to((root / "builds").resolve()) or not (export / "index.html").is_file():
        raise ValueError("Expected a project-local Web export")
    if (export / MANIFEST).exists() or (export / "_audio").exists():
        raise ValueError("Audio destination already exists")
    records = {"tracks": {}, "sfx": {}, "voice": {}}
    for key, collection in sources(root).items():
        for name, (source, record) in collection.items():
            target = export / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            records[key][name] = record
    manifest = {"schema_version": SCHEMA, **records}
    (export / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return validate(export, root)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    manifest = validate(args.export) if args.validate_only else stage(args.export)
    print("LOCAL_AUDIO_SIDECARS_VERIFIED tracks=%d sfx=%d voice=%d" % (len(manifest["tracks"]), len(manifest["sfx"]), len(manifest.get("voice", {}))))
