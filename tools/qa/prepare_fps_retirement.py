"""Record owned FPS probe/build hashes after the verified replacement exists.

This helper never deletes. Its exact, bounded directory plan is consumed by
native PowerShell Remove-Item; source art, media and deployed builds are kept.
"""
from collections import defaultdict
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys

from prepare_fps_probe_build import directory

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "reports/performance_r23_20261004"
BUILD = ROOT / "builds/web_visual_r23_release"
PROBES = ["web_visual_r22_fps_probe", "web_visual_r23_fps_probe",
          "web_visual_r23_verified_fps_probe", "web_visual_r23_complete_fps_probe",
          "web_visual_r23_map_fps_probe", "web_visual_r23_minimap_fps_probe",
          "web_visual_r23_wave_fps_probe", "web_visual_r23_wave_final_fps_probe"]
MEDIA = {".wav", ".ogg", ".mp3", ".flac", ".m4a", ".mp4", ".webm", ".ogv", ".zip"}
hashes = {}
physical = defaultdict(list)


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def normal(path):
    assert path.is_absolute() and path.resolve() == path
    assert path.is_dir() and not path.is_symlink()
    assert not (getattr(path.lstat(), "st_file_attributes", 0) & 0x400), path


def digest(path):
    st = path.stat()
    key = (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns)
    if key not in hashes:
        with path.open("rb") as stream:
            hashes[key] = hashlib.file_digest(stream, "sha256").hexdigest()
    return hashes[key]


def packed_assets(pack):
    data = pack.read_bytes()
    _, _, entries = directory(data)
    return {name: hashlib.sha256(data[pos:pos+length]).hexdigest()
            for name, pos, length, *_ in entries
            if name.startswith("assets/") or name.startswith(".godot/imported/")}


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    for name in ["r23_wave_final_a", "r23_wave_final_b"]:
        scored = read(REPORT / name / "fps_summary.json")
        assert scored["acceptance"]["pass"] and len(scored["acceptance"]["cases"]) == 11
        assert all(check["pass"] for check in scored["checks"])
    resolution = read(REPORT / "resolution_wave_final/resolution_summary.json")
    assert len(resolution["cases"]) == 7 and all(c["pass"] for c in resolution["checks"])
    assert '"pass": 71, "fail": 0' in (REPORT / "static_final_minimap.log").read_text(encoding="utf-8-sig")
    assert "total=358 pass=358 fail=0" in (REPORT / "map_full_final.log").read_text(encoding="utf-8-sig")
    assert "failures=0" in (REPORT / "map_minimap_cache.log").read_text(encoding="utf-8-sig")
    wave = ROOT / "reports/wave_transition_20261005"
    assert all(c["pass"] for c in read(wave / "web_flow_final/wave_flow_summary.json")["checks"])
    assert all(c["pass"] for c in read(REPORT / "minimap_flow_verified/minimap_flow_summary.json")["checks"])
    assert "total=2884 pass=2884 failures=0" in (wave / "battle_wave_transition_runner.log").read_text(encoding="utf-8-sig")
    identity = read(REPORT / "candidate_wave_final_resource_identity.json")
    assert len(identity["identical_gameplay_and_asset_entries"]) == 3993
    pack, = BUILD.glob("*.pck")
    candidate_hash = digest(pack)
    assert candidate_hash == identity["source_pck_sha256"] == read(BUILD / "VERSION.json")["pck_sha256"]
    normal(BUILD)

    identities = [read(p) for p in REPORT.glob("*resource_identity.json")]
    owned_versions = {j["source_pck_sha256"] for j in identities if Path(j["source"]) == BUILD}
    targets = []
    for name in PROBES:
        probe = ROOT / "builds" / name
        normal(probe)
        metadata = read(probe / "VERSION.json")
        proof, = [j for j in identities if Path(j["destination"]) == probe]
        assert proof["local_only"] is True and proof["never_publish"] is True
        pck, = probe.glob("*.pck")
        assert digest(pck) == proof["probe_pck_sha256"]
        if name == "web_visual_r23_fps_probe":
            # The first helper retained the source VERSION unchanged. Its
            # independently recorded pack/resource identity still proves ownership.
            assert metadata["pck_sha256"] == proof["source_pck_sha256"]
            assert metadata["production_approved"] is False
        else:
            assert metadata.get("never_publish") is True and metadata["build_id"].endswith("_LOCAL_FPS_PROBE")
            assert metadata["pck_sha256"] == proof["probe_pck_sha256"]
        targets.append(probe)

    candidate_assets = packed_assets(pack)
    asset_proofs = []
    quarantine = ROOT / "work/build_output_quarantine"
    for retired in sorted(quarantine.glob("web_visual_r23_release_*")):
        if not retired.is_dir():
            continue
        normal(retired)
        retention = read(retired.with_name(retired.name + ".retention.json"))
        metadata = read(retired / "VERSION.json")
        assert Path(retention["source"]) == BUILD and Path(retention["destination"]) == retired
        assert metadata["build_id"] == "LANTERNLINE_VISUAL_R23_WEB"
        assert metadata["pck_sha256"] in owned_versions and metadata["pck_sha256"] != candidate_hash
        old_pack, = retired.glob("*.pck")
        assert digest(old_pack) == metadata["pck_sha256"]
        previous_assets = packed_assets(old_pack)
        assert previous_assets == candidate_assets, "A superseded build contains distinct art/audio: " + str(retired)
        asset_proofs.append({"retired": str(retired), "retired_pck_sha256": metadata["pck_sha256"],
                             "identical_kept_asset_entries": len(previous_assets)})
        targets.append(retired)
    assert len(asset_proofs) == 6, "Unexpected retirement scope"

    # Only profiles from this batch's recorded commands, plus the two explicit
    # source-regression/final-export invocations. No general runtime-cache sweep.
    profile_names = {"7112-1791133781751", "38244-1791133812577", "41224-1791137101103",
                     "34656-1791137139922", "5804-1791137336623"}
    for log in [*REPORT.glob("*.log"), *wave.glob("*.log")]:
        text = log.read_text(encoding="utf-8-sig", errors="replace")
        profile_names.update(re.findall(r"\.runtime_profile[\\/]runs[\\/](\d+-\d{13})", text))
    for name in sorted(profile_names):
        profile = ROOT / "godot/.runtime_profile/runs" / name
        if profile.is_dir():
            normal(profile)
            targets.append(profile)

    media_kept = {}
    for item in BUILD.rglob("*"):
        if item.is_file() and item.suffix.lower() in MEDIA:
            media_kept.setdefault(digest(item), str(item))
    templates = Path.home() / "AppData/Roaming/Godot/export_templates/4.7.1.stable"
    for name in ["web_nothreads_debug.zip", "web_nothreads_release.zip"]:
        item = templates / name
        if item.is_file():
            media_kept.setdefault(digest(item), str(item))

    rows = []
    for target in targets:
        assert target.is_relative_to(ROOT) and target not in [ROOT, BUILD]
        for item in sorted(target.rglob("*")):
            assert item.resolve() == item and not item.is_symlink()
            assert not (getattr(item.lstat(), "st_file_attributes", 0) & 0x400), item
            if not item.is_file():
                continue
            st = item.stat()
            sha = digest(item)
            row = {"path": str(item), "bytes": st.st_size, "sha256": sha}
            if item.suffix.lower() in MEDIA:
                assert sha in media_kept, "Protected media has no verified kept copy: " + str(item)
                row["identical_media_kept_at"] = media_kept[sha]
            rows.append(row)
            physical[(st.st_dev, st.st_ino)].append((st.st_size, st.st_nlink))
    with gzip.open(REPORT / "retired_fps_files.jsonl.gz", "wt", encoding="utf-8") as stream:
        for row in rows:
            stream.write(json.dumps(row, ensure_ascii=False) + "\n")
    plan = {"status": "HASHED_READY_AFTER_REPLACEMENT_PASS", "created_utc": datetime.now(timezone.utc).isoformat(),
            "scope": "Owned local-only probes, six superseded FPS/wave code builds and recorded isolated test profiles",
            "candidate_pck": str(pack), "candidate_pck_sha256": candidate_hash,
            "gate": {"fps_repetitions_pass": 2, "scored_cases_each": 11, "runtime_checks_each": 28,
                     "resolution_profiles_pass": 7, "resolution_checks_pass": len(resolution["checks"]),
                     "static_checks_pass": 71, "map_checks_pass": 358, "map_geometry_regression_failures": 0,
                     "production_resource_identity_count": 3993, "visual_map_and_battle_screenshots_reviewed": True,
                     "wave_timeline_and_combat_boundary_checks": 2884, "wave_web_flow_checks_pass": True,
                     "generation_and_ponytail_asset_gates": "Not applicable: no art generation or source-art edits",
                     "active_runtime_references": "None: QA servers are stopped before disposal; production source/registries use the kept build",
                     "publishing": "No deployment, commit, push or Actions run"},
            "asset_identity_proofs": asset_proofs, "targets": [str(p) for p in targets],
            "file_count": len(rows), "logical_bytes": sum(r["bytes"] for r in rows),
            "estimated_reclaim_bytes": sum(values[0][0] for values in physical.values() if len(values) >= values[0][1]),
            "media_duplicates_with_verified_kept_copy": sum("identical_media_kept_at" in row for row in rows),
            "file_hash_manifest": str(REPORT / "retired_fps_files.jsonl.gz")}
    (REPORT / "storage_retirement_plan.json").write_text(json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: plan[k] for k in ["status", "file_count", "logical_bytes", "estimated_reclaim_bytes", "media_duplicates_with_verified_kept_copy"]}))
    print("Bounded directories:", len(targets))


if __name__ == "__main__":
    main()
