"""Hash this batch's disposable outputs after the R24 runtime gates pass.

Does not delete. Sound/art/video originals and deployed R21/R22 are outside scope.
The replaced local R23 export is included only after the R24 replacement gates.
"""
from collections import defaultdict
from datetime import datetime, timezone
import gzip
import json
from pathlib import Path
import sys

from prepare_fps_retirement import digest, normal, packed_assets, MEDIA

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "reports/startup_r24_20261005"
BUILD = ROOT / "builds/web_visual_r24_release"
TARGETS = [ROOT / "builds" / name for name in [
    "web_visual_r24_fps_probe", "web_visual_r24_verified_fps_probe",
    "web_visual_r24_final_fps_probe", "web_visual_r24_boss_fps_probe"]]
TARGETS += [ROOT / "work/build_output_quarantine" / name for name in [
    "web_visual_r24_release_e300756cb8f54b7c9d1d4eb3c8f4370f",
    "web_visual_r24_release_ea32e1bebb704c3888f77a9ea34a71d9"]]
TARGETS += [ROOT / "builds/web_visual_r23_release"]
TARGETS += [ROOT / "godot/.runtime_profile/runs" / name for name in [
    "7176-1791168622652", "17292-1791169477951", "27768-1791169058843",
    "24868-1791170958480", "37248-1791171042159"]]


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    starts = [read(REPORT / name / "startup_summary.json") for name in ["boss_final_a", "boss_final_b", "boss_final_c"]]
    assert all(s["passed"] and s["timing"]["totalMs"] < 10000 for s in starts)
    intro = read(REPORT / "intro_boss_final/acceptance.json")
    assert intro["passed"] and all(c["ok"] for c in intro["checks"])
    fps = read(REPORT / "fps_boss_final/fps_summary.json")
    assert fps["acceptance"]["pass"] and len(fps["acceptance"]["cases"]) == 11
    assert len(fps["checks"]) == 30 and all(c["pass"] for c in fps["checks"])
    assert read(REPORT / "visual_review.json")["passed"] is True
    assert read(REPORT / "boss_after/boss_quality_summary.json")["passed"] is True
    assert "actors=109 effects=436 map_actors=109 failures=[]" in (REPORT / "full_density_boss_runner.log").read_text(encoding="utf-8-sig")
    for name, expected in [
        ("loading_pacing_runner", "total=34 pass=34 fail=0"),
        ("battle_wave_transition_runner", "total=2884 pass=2884 failures=0"),
        ("chapter_boss_flow_runner", "checks=153 failures=0")]:
        assert expected in (REPORT / (name + ".log")).read_text(encoding="utf-8-sig")
    identity = read(REPORT / "resource_identity_boss_final.json")
    assert len(identity["identical_gameplay_and_asset_entries"]) == 4017
    pack, = BUILD.glob("*.pck")
    candidate_hash = digest(pack)
    assert candidate_hash == identity["source_pck_sha256"] == read(BUILD / "VERSION.json")["pck_sha256"]
    normal(BUILD)
    candidate_assets = packed_assets(pack)
    proofs = [read(REPORT / name) for name in [
        "resource_identity.json", "resource_identity_final.json", "resource_identity_verified.json", "resource_identity_boss_final.json"]]
    asset_proofs = []
    for target in TARGETS[:7]:
        normal(target)
        old_pack, = target.glob("*.pck")
        old_hash = digest(old_pack)
        if target.name.endswith("_fps_probe"):
            proof, = [p for p in proofs if Path(p["destination"]) == target]
            assert proof["local_only"] and proof["never_publish"]
            assert proof["probe_pck_sha256"] == old_hash
        elif target.parent.name == "build_output_quarantine":
            retention = read(target.with_name(target.name + ".retention.json"))
            assert Path(retention["source"]) == BUILD and Path(retention["destination"]) == target
            assert read(target / "VERSION.json")["pck_sha256"] == old_hash
        else:
            assert target == ROOT / "builds/web_visual_r23_release"
            assert old_hash == "2f7a9abb8ee5e2dad1aa8d883f72a00457efd3a4df435c9420433d68208bd63d"
        old_assets = packed_assets(old_pack)
        assert all(candidate_assets.get(name) == sha for name, sha in old_assets.items()), "Distinct retired art/audio: " + str(target)
        asset_proofs.append({"path": str(target), "pck_sha256": old_hash,
                             "identical_kept_asset_entries": len(old_assets)})
    media_kept = {}
    for item in BUILD.rglob("*"):
        if item.is_file() and item.suffix.lower() in MEDIA:
            media_kept.setdefault(digest(item), str(item))
    templates = Path.home() / "AppData/Roaming/Godot/export_templates/4.7.1.stable"
    for name in ["web_nothreads_debug.zip", "web_nothreads_release.zip"]:
        item = templates / name
        if item.is_file():
            media_kept.setdefault(digest(item), str(item))
    rows, physical = [], defaultdict(list)
    for target in TARGETS:
        normal(target)
        assert target.is_relative_to(ROOT) and target not in [ROOT, BUILD]
        for item in sorted(target.rglob("*")):
            assert item.resolve() == item and not item.is_symlink()
            assert not (getattr(item.lstat(), "st_file_attributes", 0) & 0x400)
            if not item.is_file():
                continue
            st, sha = item.stat(), digest(item)
            row = {"path": str(item), "bytes": st.st_size, "sha256": sha}
            if item.suffix.lower() in MEDIA:
                assert sha in media_kept, "No identical preserved media: " + str(item)
                row["identical_media_kept_at"] = media_kept[sha]
            rows.append(row)
            physical[(st.st_dev, st.st_ino)].append((st.st_size, st.st_nlink))
    manifest = REPORT / "retired_startup_files.jsonl.gz"
    with gzip.open(manifest, "wt", encoding="utf-8") as stream:
        for row in rows:
            stream.write(json.dumps(row, ensure_ascii=False) + "\n")
    plan = {"status": "HASHED_READY_AFTER_REPLACEMENT_PASS", "created_utc": datetime.now(timezone.utc).isoformat(),
            "candidate_pck": str(pack), "candidate_pck_sha256": candidate_hash,
            "gate": {"startup_under_10s_repetitions": 3, "fps_scored_cases": 11, "runtime_checks": 30,
                     "full_intro_pass": True, "settled_visual_review_pass": True,
                     "bosses_source_density_pass": 23, "native_asset_loading_pass": 109,
                     "art_generation_and_ponytail": "No new illustration: 512px boss derivatives retain verified source identities and timing; native/runtime/visual checks passed",
                     "active_references": "Local-only probe server stopped before disposal",
                     "publishing": "No external deployment, commit, push or Actions"},
            "asset_identity_proofs": asset_proofs, "targets": [str(t) for t in TARGETS],
            "file_count": len(rows), "logical_bytes": sum(r["bytes"] for r in rows),
            "estimated_reclaim_bytes": sum(v[0][0] for v in physical.values() if len(v) >= v[0][1]),
            "media_duplicates_with_verified_kept_copy": sum("identical_media_kept_at" in r for r in rows),
            "file_hash_manifest": str(manifest)}
    (REPORT / "storage_retirement_plan.json").write_text(json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: plan[k] for k in ["status", "file_count", "logical_bytes", "estimated_reclaim_bytes"]}))


if __name__ == "__main__":
    main()
