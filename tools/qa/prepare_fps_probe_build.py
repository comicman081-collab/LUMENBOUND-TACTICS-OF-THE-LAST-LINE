"""Local-only measurement derivative; retain every release resource byte.

Adds the existing development capability to project.binary, without recompiling
scripts or changing gameplay/assets. The immutable source build is never edited.
All unchanged files are hard links; never modify them in the derivative.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[2]


def directory(data):
    assert data[:4] == b"GDPC" and struct.unpack_from("<I", data, 4)[0] == 4
    base, offset = struct.unpack_from("<QQ", data, 24)
    count = struct.unpack_from("<I", data, offset)[0]
    cursor = offset + 4
    rows = []
    for _ in range(count):
        start = cursor
        length = struct.unpack_from("<I", data, cursor)[0]
        cursor += 4
        name = data[cursor:cursor + length].rstrip(b"\0").decode()
        cursor += length
        position = cursor
        file_offset, size = struct.unpack_from("<QQ", data, cursor)
        cursor += 36
        rows.append((name, base + file_offset, size, start, cursor, position))
    assert cursor == len(data), "Unexpected trailing pack data"
    return base, offset, rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("--refresh-probe", action="store_true")
    args = parser.parse_args()
    source, dest = args.source.resolve(), args.destination.resolve()
    assert source.is_relative_to(ROOT / "builds") and dest.is_relative_to(ROOT / "builds")
    assert dest.name.endswith("_fps_probe"), "Local QA output required"
    assert not dest.exists() or args.refresh_probe, "Fresh output or explicit QA refresh required"
    args.report.resolve().parent.mkdir(parents=True, exist_ok=True)
    pack, = source.glob("*.pck")
    version_path = source / "VERSION.json"
    assert version_path.is_file(), "Wait for the complete release export before preparing QA"
    version = json.loads(version_path.read_text(encoding="utf-8-sig"))
    assert version.get("pck_sha256") == hashlib.sha256(pack.read_bytes()).hexdigest(), "Release PCK differs from completed export metadata"
    assert source != dest and not dest.is_symlink()
    if dest.exists():
        assert (dest / pack.name).is_file() and (dest / 'index.html').is_file()
    data = pack.read_bytes()
    base, offset, rows = directory(data)
    project, = [r for r in rows if r[0] == "project.binary"]
    old = data[project[1]:project[1] + project[2]]
    assert old[:4] == b"ECFG" and b"_custom_features" not in old
    feature = b"lanternline_dev_tools"
    variant = struct.pack("<II", 4, len(feature)) + feature
    variant += b"\0" * (-len(variant) % 4)
    key = b"_custom_features"
    prop = struct.pack("<I", len(key)) + key + struct.pack("<I", len(variant)) + variant
    script = (ROOT / "tools/web_qa/fps_local_recorder.gd").read_bytes()
    autoload_key = b"autoload/FPSLocalRecorder"
    autoload_value = b"*res://qa/fps_local_recorder.gd"
    autoload_variant = struct.pack("<II", 4, len(autoload_value)) + autoload_value
    autoload_variant += b"\0" * (-len(autoload_variant) % 4)
    autoload_prop = struct.pack("<I", len(autoload_key)) + autoload_key + struct.pack("<I", len(autoload_variant)) + autoload_variant
    patched = b"ECFG" + struct.pack("<I", struct.unpack_from("<I", old, 4)[0] + 2) + prop + old[8:] + autoload_prop
    payload = bytearray(data[:offset])
    new_project_offset = len(payload)
    payload += patched
    payload += b"\0" * (-len(payload) % 16)
    recorder_offset = len(payload)
    payload += script
    payload += b"\0" * (-len(payload) % 16)
    new_directory_offset = len(payload)
    new_directory = bytearray(data[offset:])
    relative = project[5] - offset
    struct.pack_into("<QQ", new_directory, relative, new_project_offset - base, len(patched))
    new_directory[relative + 16:relative + 32] = hashlib.md5(patched).digest()
    struct.pack_into("<I", new_directory, 0, len(rows) + 1)
    recorder_name = b"qa/fps_local_recorder.gd"
    recorder_name += b"\0" * (-len(recorder_name) % 4)
    new_directory += (struct.pack("<I", len(recorder_name)) + recorder_name +
                      struct.pack("<QQ", recorder_offset - base, len(script)) +
                      hashlib.md5(script).digest() + struct.pack("<I", 0))
    payload += new_directory
    struct.pack_into("<Q", payload, 32, new_directory_offset)
    _, _, after = directory(payload)
    unchanged = []
    assert after[-1][0] == "qa/fps_local_recorder.gd" and len(after) == len(rows) + 1
    for before, current in zip(rows, after[:-1], strict=True):
        assert before[0] == current[0]
        if before[0] == "project.binary":
            continue
        a = data[before[1]:before[1] + before[2]]
        b = payload[current[1]:current[1] + current[2]]
        assert a == b, before[0]
        unchanged.append({"path": before[0], "bytes": len(a), "sha256": hashlib.sha256(a).hexdigest()})
    dest.mkdir(exist_ok=args.refresh_probe)
    for file in source.rglob("*"):
        if not file.is_file():
            continue
        target = dest / file.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        if file == pack:
            target.write_bytes(payload)
        elif file.name in ["index.html", "index.service.worker.js", "VERSION.json"]:
            target.write_bytes(file.read_bytes())
        else:
            if not target.exists():
                os.link(file, target)
    html = (dest / "index.html").read_text(encoding="utf-8-sig")
    html = re.sub(r'("' + re.escape(pack.name) + r'":)\d+', lambda m: m[1] + str(len(payload)), html)
    (dest / "index.html").write_text(html, encoding="utf-8")
    worker = dest / "index.service.worker.js"
    if worker.exists():
        text = worker.read_text(encoding="utf-8-sig")
        text = re.sub(r"const CACHE_VERSION = '[^']+';", "const CACHE_VERSION = 'fps-probe-" + hashlib.sha256(payload).hexdigest()[:12] + "';", text)
        worker.write_text(text, encoding="utf-8")
    version = dest / "VERSION.json"
    if version.exists():
        metadata = json.loads(version.read_text(encoding="utf-8-sig"))
        metadata.update(build_id=metadata["build_id"] + "_LOCAL_FPS_PROBE", never_publish=True,
                        source_pck_sha256=hashlib.sha256(data).hexdigest(), pck_sha256=hashlib.sha256(payload).hexdigest())
        version.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    report = {"local_only": True, "never_publish": True, "source": str(source), "destination": str(dest),
              "source_pck_sha256": hashlib.sha256(data).hexdigest(), "probe_pck_sha256": hashlib.sha256(payload).hexdigest(),
              "only_resource_change": "project.binary: existing localhost QA capability plus measurement autoload",
              "only_added_resource": "qa/fps_local_recorder.gd",
              "recorder_sha256": hashlib.sha256(script).hexdigest(),
              "identical_gameplay_and_asset_entries": unchanged}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "identical_gameplay_and_asset_entries"}, ensure_ascii=False))
    print(f"Verified {len(unchanged)} resource entries byte-for-byte identical.")


if __name__ == "__main__":
    main()
