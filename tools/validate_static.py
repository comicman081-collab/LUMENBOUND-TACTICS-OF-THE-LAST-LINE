#!/usr/bin/env python3
"""Engine-independent source/data audit. Does not claim Godot runtime PASS."""
from __future__ import annotations

import csv
import hashlib
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = json.loads((ROOT / "godot/data/compiled/game_data.json").read_text(encoding="utf-8"))
checks: list[dict] = []


def check(name: str, condition: bool, details="") -> None:
    checks.append({"name": name, "pass": bool(condition), "details": str(details)})
    print(("PASS" if condition else "FAIL") + " | " + name + (" | " + str(details) if details else ""))


def unique(collection: str) -> bool:
    ids = [row["id"] for row in DATA[collection]]
    return len(ids) == len(set(ids))


def csv_rows(path: Path) -> list[dict]:
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_contract(path: Path) -> tuple[int, int, bool]:
    """Return width, height and alpha support from the PNG IHDR only."""
    if not path.is_file():
        return 0, 0, False
    header = path.read_bytes()[:26]
    if len(header) < 26 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        return 0, 0, False
    width = int.from_bytes(header[16:20], "big")
    height = int.from_bytes(header[20:24], "big")
    color_type = header[25]
    return width, height, color_type in (4, 6)


def main() -> int:
    check("engine lock 4.7.1", 'required_engine_version="4.7.1-stable"' in (ROOT / "godot/project.godot").read_text(encoding="utf-8"))
    check("Compatibility renderer", 'rendering_method="gl_compatibility"' in (ROOT / "godot/project.godot").read_text(encoding="utf-8"))
    for collection in ("characters", "skills", "weapons", "enemies", "stages", "rewards", "items", "scenarios"):
        check(f"{collection} IDs unique", unique(collection))
    skills = {row["id"]: row for row in DATA["skills"]}
    check("character count 44", len(DATA["characters"]) == 44, len(DATA["characters"]))
    policy = json.loads((ROOT / "tools/policy/project_content_policy.json").read_text(encoding="utf-8"))
    check("project character policy FEMALE_ONLY", policy["character_policy"]["human_and_humanoid_characters"] == "FEMALE_ONLY" and policy["character_policy"]["male_character_creation"] == "PROHIBITED")
    check("all playable characters FEMALE", all(c.get("gender") == "FEMALE" for c in DATA["characters"]))
    check("all playable characters ADULT", all(c.get("age_category") == "ADULT" for c in DATA["characters"]))
    check("all playable attire policy maximum non-explicit", all(c.get("attire_policy") == "MAXIMUM_NON_EXPLICIT" for c in DATA["characters"]))
    check("all enemies genderless nonhuman", all(e.get("gender") == "GENDERLESS_NONHUMAN" for e in DATA["enemies"]))
    roles = {role: sum(c["role"] == role for c in DATA["characters"]) for role in ("GUARDIAN", "VANGUARD", "ASSAULT", "ARTILLERY", "SPECIALIST", "MEDIC")}
    check("role distribution 7/7/8/7/8/7", roles == {"GUARDIAN": 7, "VANGUARD": 7, "ASSAULT": 8, "ARTILLERY": 7, "SPECIALIST": 8, "MEDIC": 7}, roles)
    refs = all(c[key] in skills for c in DATA["characters"] for key in ("normal_skill_id", "passive_skill_id", "ultimate_skill_id"))
    check("all character skill references valid", refs)
    check("skill arrays 10/10/5", all(len(s["values"]) == (5 if s["type"] == "ULTIMATE_SKILL" else 10) for s in DATA["skills"]))
    check("exactly three skills per character", all(sum(s["owner_id"] == c["id"] for s in DATA["skills"]) == 3 for c in DATA["characters"]))
    skill_icon_ids = [str(s.get("icon_asset_id", "")) for s in DATA["skills"]]
    check("132 immutable unique SkillDef icon references", len(skill_icon_ids) == 132 and "" not in skill_icon_ids and len(set(skill_icon_ids)) == 132, len(set(skill_icon_ids)))
    skill_icon_manifest = json.loads((ROOT / "godot/assets/art/icons/skills/skill_icon_manifest.json").read_text(encoding="utf-8"))
    skill_icon_assets = {str(row.get("asset_id", "")): row for row in skill_icon_manifest.get("assets", [])}
    check("skill icon manifest covers all SkillDefs", set(skill_icon_ids) == set(skill_icon_assets), len(skill_icon_assets))
    icon_variants_valid = True
    unique_variant_hashes = {256: set(), 128: set(), 64: set()}
    for asset_id in skill_icon_ids:
        entry = skill_icon_assets.get(asset_id, {})
        for resolution in (256, 128, 64):
            variant = str(entry.get("variants", {}).get(str(resolution), ""))
            local = ROOT / "godot" / variant.removeprefix("res://")
            width, height, alpha = png_contract(local)
            actual_hash = sha(local) if local.is_file() else ""
            icon_variants_valid &= width == resolution and height == resolution and alpha and actual_hash == str(entry.get("variant_sha256", {}).get(str(resolution), ""))
            if actual_hash:
                unique_variant_hashes[resolution].add(actual_hash)
    check("skill icons have SHA-verified RGBA 256/128/64 variants", icon_variants_valid)
    check("skill icon variants are all visually distinct files", all(len(unique_variant_hashes[size]) == 132 for size in unique_variant_hashes), {size: len(values) for size, values in unique_variant_hashes.items()})
    skill_icon_licenses = json.loads((ROOT / "godot/assets/art/icons/skills/skill_icon_licenses.json").read_text(encoding="utf-8")).get("assets", [])
    skill_icon_license_ids = {str(row.get("asset_id", "")) for row in skill_icon_licenses}
    check("skill icon ownership ledger complete", len(skill_icon_licenses) == 132 and skill_icon_license_ids == set(skill_icon_ids) and all(row.get("ownership_status") == "ORIGINAL_INTERNAL" and row.get("commercial_use") is True and len(str(row.get("file_sha256", ""))) == 64 for row in skill_icon_licenses), len(skill_icon_licenses))
    enemy_counts = {rank: sum(e["rank"] == rank for e in DATA["enemies"]) for rank in ("NORMAL", "ELITE", "BOSS")}
    check("enemy counts 30/12/23", enemy_counts == {"NORMAL": 30, "ELITE": 12, "BOSS": 23}, enemy_counts)
    check("boss phases/patterns data-defined", all(e.get("phases") == ["PHASE_1", "PHASE_2", "ENRAGE", "DOWN"] and e.get("patterns") for e in DATA["enemies"] if e["rank"] == "BOSS"))
    chapter_ids = tuple(f"CH{number:02d}" for number in range(1, 21))
    normal_by_chapter = {chapter_id: [s for s in DATA["stages"] if s["chapter_id"] == chapter_id and s["mode"] == "NORMAL"] for chapter_id in chapter_ids}
    hard_by_chapter = {chapter_id: [s for s in DATA["stages"] if s["chapter_id"] == chapter_id and s["mode"] == "HARD"] for chapter_id in chapter_ids}
    # Campaign 20 exposes 25 authored battles per chapter: twenty story-route
    # operations and five optional Hard operations.
    check("all 20 chapters have exactly 20 NORMAL operations", all(len(normal_by_chapter[chapter_id]) == 20 for chapter_id in chapter_ids))
    check("all 20 chapters have exactly 5 HARD operations", all(len(hard_by_chapter[chapter_id]) == 5 for chapter_id in chapter_ids))
    stages_by_id = {str(stage["id"]): stage for stage in DATA["stages"]}
    normal_boss_ids = [
        next(
            (str(enemy_id) for wave in stages_by_id[f"{chapter_id}-N20"].get("waves", []) for enemy_id in wave if str(enemy_id).startswith("BOSS")),
            "",
        )
        for chapter_id in chapter_ids
    ]
    check("each chapter N20 is a non-reused boss", all(bool(stages_by_id.get(f"{chapter_id}-N20", {}).get("boss", False)) for chapter_id in chapter_ids) and len(normal_boss_ids) == len(set(normal_boss_ids)))
    check("legacy H06-H10 IDs are retired from active stage data", all(f"{chapter_id}-H{stage_number:02d}" not in stages_by_id for chapter_id in ("CH01", "CH02") for stage_number in range(6, 11)))
    rewards = {r["id"]: r for r in DATA["rewards"]}
    check("all stages have rewards", all(s["reward_table_id"] in rewards and rewards[s["reward_table_id"]]["guaranteed"] for s in DATA["stages"]))
    rare_profiles = {chapter_id: ((.08, 8) if chapter_id == "CH01" else (.12, 7)) for chapter_id in chapter_ids}
    rare_profile_valid = all(
        stage["chapter_id"] in rare_profiles
        and any(
            math.isclose(float(bucket.get("chance", -1.0)), rare_profiles[stage["chapter_id"]][0])
            and int(bucket.get("pity_after_failures", -1)) == rare_profiles[stage["chapter_id"]][1]
            for bucket in rewards[stage["reward_table_id"]]["bonus"]
        )
        for stage in DATA["stages"]
    )
    check("chapter rare rates and pity thresholds match authored balance", rare_profile_valid)
    repeatable_items = {
        entry["item_id"]
        for reward in DATA["rewards"]
        for bucket in ("guaranteed", "bonus")
        for entry in reward.get(bucket, [])
    }
    required_growth_items = {
        item_id
        for row in DATA["breakthroughs"] + DATA["skill_upgrade_costs"] + DATA["weapon_tier_costs"]
        for item_id in row.get("cost", {})
        if item_id != "CREDIT"
    }
    check("all breakthrough skill and weapon materials are repeatable", not (required_growth_items - repeatable_items), sorted(required_growth_items - repeatable_items))
    check("character curve rows 100", len(DATA["character_level_curve"]) == 100)
    check("account curve rows 100", len(DATA["account_level_curve"]) == 100)
    check("weapon curve rows 60", len(DATA["weapon_level_curve"]) == 60)
    check("character XP regression 905,520", sum(r["xp_to_next"] for r in DATA["character_level_curve"]) == 905_520)
    check("character credits regression 412,400", sum(r["credit_cost"] for r in DATA["character_level_curve"]) == 412_400)
    check("weapon XP regression 144,330", sum(r["xp_to_next"] for r in DATA["weapon_level_curve"]) == 144_330)
    check("no negative growth values", all(r["xp_to_next"] >= 0 and r["credit_cost"] >= 0 for r in DATA["character_level_curve"]) and all(r["xp_to_next"] >= 0 for r in DATA["weapon_level_curve"]))
    check("stats monotonic endpoints", all(c["stats_l100"][k] >= c["stats_l1"][k] for c in DATA["characters"] for k in c["stats_l1"]))
    affinity = DATA["affinity_matrix"]
    check("affinity matrix exact", affinity == {"PHYSICAL": {"ARMOR": 1.25, "BARRIER": .85, "WARD": 1.0}, "ENERGY": {"ARMOR": 1.0, "BARRIER": 1.25, "WARD": .85}, "ANOMALY": {"ARMOR": .85, "BARRIER": 1.0, "WARD": 1.25}}, affinity)
    check("B0-B5 definitions", [x["level_cap"] for x in DATA["breakthroughs"]] == [20, 40, 60, 80, 90, 100])
    check("weapon T1-T6 caps", DATA["weapon_tier_caps"] == {str(i): i * 10 for i in range(1, 7)})
    check("no exclusive weapons", all(not w["exclusive_owner_id"] for w in DATA["weapons"]))
    check("all thirteen status IDs", len(DATA["status_effects"]) == 13)
    runtime_asset_manifest = json.loads((ROOT / "godot/assets/runtime_web/runtime_asset_manifest.json").read_text(encoding="utf-8"))
    runtime_asset_by_id = {str(row.get("asset_id", "")): row for row in runtime_asset_manifest.get("assets", [])}
    combat_data_rows = list(DATA["characters"]) + list(DATA["enemies"])
    combat_preview_contract = True
    combat_preview_lineage_honest = True
    for row in combat_data_rows:
        entry = runtime_asset_by_id.get(str(row.get("asset_id", "")), {})
        relative = str(entry.get("godot_path", "")).removeprefix("res://")
        local = ROOT / "godot" / relative
        width, height, alpha = png_contract(local)
        combat_preview_contract &= (
            str(entry.get("status", "")) == "RUNTIME_WEB_COMBAT_PREVIEW"
            and str(entry.get("category", "")) == "combat_preview"
            and str(entry.get("entity_id", "")) == str(row.get("id", ""))
            and width == 256 and height == 256 and alpha
            and local.is_file() and sha(local) == str(entry.get("sha256", ""))
        )
        logical_lineage = "|".join(str(entry.get(key, "")) for key in (
            "source", "source_asset_id", "source_status", "ownership_status", "license"
        ))
        combat_preview_lineage_honest &= (
            str(entry.get("source_status", "")) != ""
            and str(entry.get("qa_status", "")) == "RUNTIME_CONNECTED_NOT_PRODUCTION_APPROVED"
            and entry.get("production_approved") is False
            and re.search(r"[A-Za-z]:[\\/]", logical_lineage) is None
        )
    check("all 109 immutable combat asset IDs map to SHA-verified RGBA runtime previews", len(combat_data_rows) == 109 and combat_preview_contract, len(combat_data_rows))
    check("combat preview registry preserves honest non-production lineage without workstation paths", combat_preview_lineage_honest)
    check("scenario count 105", len(DATA["scenarios"]) == 105)
    scenario_cg_ids = {
        str(command.get("asset_id", ""))
        for scenario in DATA["scenarios"]
        for command in scenario.get("commands", [])
        if str(command.get("command", "")) == "set_cg" and str(command.get("asset_id", "")) != ""
    }
    story_runtime_contract = True
    for asset_id in scenario_cg_ids:
        entry = runtime_asset_by_id.get(asset_id, {})
        relative = str(entry.get("godot_path", "")).removeprefix("res://")
        local = ROOT / "godot" / relative
        width, height, alpha = png_contract(local)
        story_runtime_contract &= (
            str(entry.get("status", "")) == "RUNTIME_WEB_STORY_PLATE"
            and str(entry.get("category", "")) == "story_plate"
            and str(entry.get("source_asset_id", "")) == asset_id
            and relative.startswith("assets/runtime_web/story/")
            and local.is_file() and sha(local) == str(entry.get("sha256", ""))
            and width == 1280 and height == 720 and alpha
        )
    check("all authored scenario CG IDs resolve to SHA-verified Web runtime story plates", bool(scenario_cg_ids) and story_runtime_contract, sorted(scenario_cg_ids))
    supported = {"set_background", "set_cg", "show_portrait", "hide_portrait", "set_expression", "dialogue", "narration", "choice", "set_flag", "check_flag", "jump", "play_bgm", "stop_bgm", "play_sfx", "play_voice", "fade_in", "fade_out", "wait", "start_battle", "grant_reward", "end_scenario"}
    scenario_ok = True
    used_commands = set()
    for scenario in DATA["scenarios"]:
        labels = {c["id"] for c in scenario["commands"] if "id" in c}
        for command in scenario["commands"]:
            used_commands.add(command["command"])
            scenario_ok &= command["command"] in supported
            if command["command"] in ("jump", "check_flag") and "target" in command:
                scenario_ok &= command["target"] in labels
    check("scenario commands and jumps valid", scenario_ok)
    check("ScenarioRunner implements full command contract", all(f'"{cmd}"' in (ROOT / "godot/story/scenario_parser.gd").read_text(encoding="utf-8") for cmd in supported))
    locales = {}
    for locale in ("ko", "en"):
        locales[locale] = {row["key"] for row in csv_rows(ROOT / f"godot/localization/{locale}.csv")}
    referenced_keys = set()
    for c in DATA["characters"]: referenced_keys |= {c["name_key"], c["description_key"]}
    for s in DATA["skills"]: referenced_keys.add(s["name_key"])
    for e in DATA["enemies"]: referenced_keys.add(e["name_key"])
    for s in DATA["stages"]: referenced_keys.add(s["name_key"])
    for s in DATA["scenarios"]:
        referenced_keys.add(s["title_key"])
        for c in s["commands"]:
            referenced_keys |= {c[k] for k in ("text_key", "speaker_key") if k in c}
            for choice in c.get("choices", []):
                if "text_key" in choice: referenced_keys.add(choice["text_key"])
    check("all KO localization keys exist", not (referenced_keys - locales["ko"]), sorted(referenced_keys - locales["ko"]))
    check("all EN localization keys exist", not (referenced_keys - locales["en"]), sorted(referenced_keys - locales["en"]))
    manifest_path = ROOT / "godot/assets/generated_import/import_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    asset_files_ok = True
    hashes_ok = True
    for asset in manifest["assets"]:
        local = ROOT / "godot" / asset["godot_path"].removeprefix("res://")
        asset_files_ok &= local.is_file()
        hashes_ok &= local.is_file() and sha(local) == asset["sha256"]
    check("legacy asset bridge status SYNCED", manifest["status"] == "SYNCED", manifest["status"])
    check("legacy asset bridge 93 files resolve", len(manifest["assets"]) == 93 and asset_files_ok, len(manifest["assets"]))
    check("all legacy SHA-256 values match", hashes_ok)
    check("all legacy assets DEV_PLACEHOLDER", all(a["status"] == "DEV_PLACEHOLDER" for a in manifest["assets"]))
    runtime_import_files = list((ROOT / "godot/assets/runtime_web").rglob("*.import"))
    invalid_runtime_imports = [
        str(path.relative_to(ROOT))
        for path in runtime_import_files
        if "valid=false" in path.read_text(encoding="utf-8", errors="ignore").replace(" ", "").lower()
    ]
    check("runtime Web import metadata is valid", not invalid_runtime_imports, invalid_runtime_imports)
    licenses = json.loads((ROOT / "godot/assets/generated_import/licenses.json").read_text(encoding="utf-8"))["assets"]
    license_by_id = {row["asset_id"]: row for row in licenses}
    bridge_license_ids = {row["asset_id"] for row in manifest["assets"]}
    check("license entry per synchronized file", bridge_license_ids <= set(license_by_id), len(licenses))
    factory_licenses = [license_by_id[asset_id] for asset_id in bridge_license_ids]
    check("unconfirmed output rights not claimed commercial", all(not row["commercial_use"] and row["license"] == "MANIFEST_NOT_DECLARED" for row in factory_licenses))
    local_dev_licenses = [row for row in licenses if row["license"] == "PROJECT_GENERATED_DEV_REVIEW_REQUIRED"]
    check("project-generated combat bundles are in license ledger", len(local_dev_licenses) == 15, len(local_dev_licenses))
    check("every license record has SHA-256", all(len(row.get("file_sha256", "")) == 64 for row in licenses), len(licenses))
    required_paths = [
        "godot/autoload/app_state.gd", "godot/autoload/save_service.gd", "godot/battle/model/battle_simulation.gd",
        "godot/battle/view/battle_view.gd", "godot/story/scenario_runner.gd", "godot/screens/app_shell.gd",
        "godot/tests/test_runner.gd", "tools/asset_bridge/sync_assets.py", "data_source/characters.csv",
    ]
    check("foundation implementation files present", all((ROOT / p).is_file() for p in required_paths))
    web_build_script = (ROOT / "tools/powershell/BUILD_WEB_RELEASE.ps1").read_text(encoding="utf-8")
    stable_url_cache_policy = all(token in web_build_script for token in (
        "index.pck', 'index.wasm', 'index.js', 'index.html",
        "Navigation network error; using cached LUMENBOUND shell.",
        "self.skipWaiting()",
        "self.clients.claim()",
        "Unexpected Godot service-worker navigation block",
    ))
    check("Web stable-URL cache update keeps offline fallback", stable_url_cache_policy)
    all_text = "\n".join(p.read_text(encoding="utf-8", errors="ignore") for p in (ROOT / "godot").rglob("*.gd"))
    check("GDScript only / no C#", not list(ROOT.rglob("*.cs")) and not list(ROOT.rglob("*.csproj")))
    check("no HTTP runtime code", not re.search(r"HTTPRequest|https?://", all_text))
    model_policy = json.loads((ROOT / "tools/local_art_pipeline/model_policy.json").read_text(encoding="utf-8"))
    excluded = {row["id"]: row for row in model_policy["excluded"]}
    check("Krea2 permanently excluded", excluded.get("krea2-local", {}).get("must_never_be_used") is True)
    check("approved local models are build-time only", all(not row["runtime_dependency"] for row in model_policy["selected"]))
    concept_bridge = json.loads((ROOT / "tools/premium_asset_factory/concept_inputs/concept_bridge_manifest.json").read_text(encoding="utf-8"))
    required_art_verdicts = {"FEMALE_CONFIRMED", "ADULT_CONFIRMED", "ATTIRE_POLICY_CONFIRMED"}
    check("active art guides meet global visual policy", all(row.get("character_gender") == "FEMALE" and required_art_verdicts.issubset(set(row.get("visual_qa_verdicts", []))) for row in concept_bridge["guides"]))

    result = {"kind": "STATIC_DATA_SOURCE_AUDIT", "total": len(checks), "pass": sum(x["pass"] for x in checks), "fail": sum(not x["pass"] for x in checks), "checks": checks}
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    (reports / "static_validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: result[k] for k in ("kind", "total", "pass", "fail")}, ensure_ascii=False))
    return 0 if result["fail"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
