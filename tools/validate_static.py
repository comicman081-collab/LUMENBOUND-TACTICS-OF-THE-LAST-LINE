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


def main() -> int:
    check("engine lock 4.7.1", 'required_engine_version="4.7.1-stable"' in (ROOT / "godot/project.godot").read_text(encoding="utf-8"))
    check("Compatibility renderer", 'rendering_method="gl_compatibility"' in (ROOT / "godot/project.godot").read_text(encoding="utf-8"))
    for collection in ("characters", "skills", "weapons", "enemies", "stages", "rewards", "items", "scenarios"):
        check(f"{collection} IDs unique", unique(collection))
    skills = {row["id"]: row for row in DATA["skills"]}
    check("character count 8", len(DATA["characters"]) == 8, len(DATA["characters"]))
    policy = json.loads((ROOT / "tools/policy/project_content_policy.json").read_text(encoding="utf-8"))
    check("project character policy FEMALE_ONLY", policy["character_policy"]["human_and_humanoid_characters"] == "FEMALE_ONLY" and policy["character_policy"]["male_character_creation"] == "PROHIBITED")
    check("all playable characters FEMALE", all(c.get("gender") == "FEMALE" for c in DATA["characters"]))
    check("all playable characters ADULT", all(c.get("age_category") == "ADULT" for c in DATA["characters"]))
    check("all playable attire policy maximum non-explicit", all(c.get("attire_policy") == "MAXIMUM_NON_EXPLICIT" for c in DATA["characters"]))
    check("all enemies genderless nonhuman", all(e.get("gender") == "GENDERLESS_NONHUMAN" for e in DATA["enemies"]))
    roles = {role: sum(c["role"] == role for c in DATA["characters"]) for role in ("GUARDIAN", "VANGUARD", "ASSAULT", "ARTILLERY", "SPECIALIST", "MEDIC")}
    check("role distribution 1/1/2/1/2/1", roles == {"GUARDIAN": 1, "VANGUARD": 1, "ASSAULT": 2, "ARTILLERY": 1, "SPECIALIST": 2, "MEDIC": 1}, roles)
    refs = all(c[key] in skills for c in DATA["characters"] for key in ("normal_skill_id", "passive_skill_id", "ultimate_skill_id"))
    check("all character skill references valid", refs)
    check("skill arrays 10/10/5", all(len(s["values"]) == (5 if s["type"] == "ULTIMATE_SKILL" else 10) for s in DATA["skills"]))
    check("exactly three skills per character", all(sum(s["owner_id"] == c["id"] for s in DATA["skills"]) == 3 for c in DATA["characters"]))
    enemy_counts = {rank: sum(e["rank"] == rank for e in DATA["enemies"]) for rank in ("NORMAL", "ELITE", "BOSS")}
    check("enemy counts 6/3/2", enemy_counts == {"NORMAL": 6, "ELITE": 3, "BOSS": 2}, enemy_counts)
    check("boss phases/patterns data-defined", all(e.get("phases") == ["PHASE_1", "PHASE_2", "ENRAGE", "DOWN"] and e.get("patterns") for e in DATA["enemies"] if e["rank"] == "BOSS"))
    normal = [s for s in DATA["stages"] if s["mode"] == "NORMAL"]
    hard = [s for s in DATA["stages"] if s["mode"] == "HARD"]
    check("Chapter 1 NORMAL exactly 10", len(normal) == 10)
    check("Chapter 1 HARD exactly 5", len(hard) == 5)
    check("N10 and H5 are bosses", normal[-1]["boss"] and hard[-1]["boss"] and normal[-1]["id"] == "CH01-N10" and hard[-1]["id"] == "CH01-H05")
    rewards = {r["id"]: r for r in DATA["rewards"]}
    check("all stages have rewards", all(s["reward_table_id"] in rewards and rewards[s["reward_table_id"]]["guaranteed"] for s in DATA["stages"]))
    check("rare rate 8% and pity 8", all(any(b.get("chance") == .08 and b.get("pity_after_failures") == 8 for b in rewards[s["reward_table_id"]]["bonus"]) for s in DATA["stages"]))
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
    check("scenario count 9", len(DATA["scenarios"]) == 9)
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
