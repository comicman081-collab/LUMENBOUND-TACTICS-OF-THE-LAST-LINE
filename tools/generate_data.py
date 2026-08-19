#!/usr/bin/env python3
"""Deterministically builds source balance tables and Godot runtime JSON.

Build-time only. The shipped game has no Python dependency.
"""
from __future__ import annotations

import csv
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data_source"
COMPILED = ROOT / "godot" / "data" / "compiled"
LOCALE = ROOT / "godot" / "localization"
REPORTS = ROOT / "reports"


def round_step(value: float, step: int) -> int:
    return math.floor(value / step + 0.5) * step


def write_csv(path: Path, rows: list[dict], fields: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fields = fields or list(rows[0])
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def level_rows() -> list[dict]:
    rows = []
    for level in range(1, 101):
        x = (level - 1) / 99.0
        curve = 0.25 * x + 0.75 * pow(x, 1.55)
        xp = 0 if level == 100 else round_step(100 + 35 * level + 2.2 * level * level, 10)
        credits = 0 if level == 100 else round_step(50 + 0.45 * xp, 50)
        rows.append({"level": level, "curve": f"{curve:.6f}", "xp_to_next": xp, "credit_cost": credits})
    return rows


def account_rows() -> list[dict]:
    return [
        {
            "level": level,
            "xp_to_next": 0 if level == 100 else round_step(20 + 8 * level + 0.45 * level * level, 10),
            "max_stamina": 120 + (level // 10) * 2,
        }
        for level in range(1, 101)
    ]


def weapon_level_rows() -> list[dict]:
    return [
        {
            "level": level,
            "xp_to_next": 0 if level == 60 else round_step(60 + 24 * level + 1.4 * level * level, 10),
        }
        for level in range(1, 61)
    ]


CHARACTERS = [
    ("CHR001", "MAERU", "GUARDIAN", "FRONT", "ENERGY", "BARRIER", "HEAVY", 1280, 102, 88, 108, 520, 92, 84, 10800, 710, 540, 490),
    ("CHR002", "ROAN", "VANGUARD", "FRONT", "PHYSICAL", "ARMOR", "BLADE", 980, 126, 66, 112, 500, 88, 70, 8200, 920, 390, 360),
    ("CHR003", "NARIN", "ASSAULT", "MIDDLE", "PHYSICAL", "ARMOR", "RIFLE", 760, 146, 44, 128, 540, 74, 58, 6100, 1080, 280, 300),
    ("CHR004", "EDA", "ASSAULT", "MIDDLE", "ENERGY", "BARRIER", "COMPACT", 720, 151, 42, 132, 550, 76, 60, 5800, 1110, 270, 315),
    ("CHR005", "SOREN", "ARTILLERY", "BACK", "ANOMALY", "WARD", "HEAVY", 690, 158, 38, 118, 480, 82, 55, 5600, 1160, 250, 330),
    ("CHR006", "VERA", "SPECIALIST", "MIDDLE", "ENERGY", "WARD", "FOCUS", 740, 112, 46, 124, 510, 80, 64, 6000, 820, 295, 380),
    ("CHR007", "TOA", "SPECIALIST", "BACK", "ANOMALY", "BARRIER", "SUPPORT_DEVICE", 790, 105, 49, 121, 505, 78, 66, 6400, 770, 305, 400),
    ("CHR008", "IRI", "MEDIC", "BACK", "ENERGY", "BARRIER", "SUPPORT_DEVICE", 810, 82, 51, 116, 490, 72, 138, 6600, 610, 320, 890),
]


def character_data() -> list[dict]:
    result = []
    for index, c in enumerate(CHARACTERS, 1):
        cid, code, role, pos, attack, defense, weapon, hp1, atk1, def1, acc, eva, crit, heal, hp100, atk100, def100, heal100 = c
        base = f"SK_{cid}"
        result.append({
            "id": cid,
            "name_key": f"CHAR_{code}_NAME",
            "description_key": f"CHAR_{code}_DESC",
            "gender": "FEMALE",
            "age_category": "ADULT",
            "attire_policy": "MAXIMUM_NON_EXPLICIT",
            "role": role,
            "preferred_position": pos,
            "attack_type": attack,
            "defense_type": defense,
            "weapon_class": weapon,
            "initial_rarity": 2 + (index % 2),
            "level": 1,
            "breakthrough": 0,
            "normal_skill_id": f"{base}_NORMAL",
            "passive_skill_id": f"{base}_PASSIVE",
            "ultimate_skill_id": f"{base}_ULTIMATE",
            "asset_id": f"sd_{cid.lower()}_dev",
            "portrait_asset_id": f"portrait_{cid.lower()}_dev",
            "icon_asset_id": f"icon_{cid.lower()}_dev",
            "attack_interval": round(1.05 + index * 0.045, 3),
            "attack_range": {"FRONT": 1.8, "MIDDLE": 5.2, "BACK": 7.0}[pos],
            "move_speed": round(2.8 + (index % 3) * 0.2, 2),
            "threat_modifier": 1.8 if role == "GUARDIAN" else (1.25 if role == "VANGUARD" else 1.0),
            "stats_l1": {"HP": hp1, "ATK": atk1, "DEF": def1, "ACC": acc, "EVA": eva, "CRIT": crit, "CRIT_RES": 50, "HEAL_POWER": heal, "HASTE": 0, "DAMAGE_REDUCTION": 0, "STATUS_RESIST": 0},
            "stats_l100": {"HP": hp100, "ATK": atk100, "DEF": def100, "ACC": acc + 190, "EVA": eva + 90, "CRIT": crit + 180, "CRIT_RES": 180, "HEAL_POWER": heal100, "HASTE": 12, "DAMAGE_REDUCTION": 6 if role == "GUARDIAN" else 2, "STATUS_RESIST": 15},
            "tags": ["DEV_NAME", "LANTERNLINE", role],
            "acquisition_source": "DEFAULT" if index <= 5 else ("STORY" if index <= 7 else "HARD_SHARD"),
        })
    return result


def values(start: float, end: float, count: int, curve: float = 1.0) -> list[float]:
    return [round(start + (end - start) * pow(i / (count - 1), curve), 3) for i in range(count)]


def skill_data() -> list[dict]:
    result = []
    ultimate_types = ["SHIELD", "DAMAGE", "DAMAGE", "DAMAGE", "AOE_DAMAGE", "DEBUFF", "BUFF", "HEAL"]
    normal_types = ["TAUNT", "DAMAGE", "DAMAGE", "DAMAGE", "AOE_DAMAGE", "SLOW", "SHIELD", "HEAL"]
    for index, c in enumerate(CHARACTERS, 1):
        cid, code, role = c[0], c[1], c[2]
        base = f"SK_{cid}"
        result.extend([
            {"id": f"{base}_NORMAL", "owner_id": cid, "type": "NORMAL_SKILL", "name_key": f"SKILL_{code}_NORMAL", "max_level": 10, "values": values(1.00 + index * .035, 2.02 + index * .04, 10, 1.08), "cooldown": 7.0 + index % 4, "effect": normal_types[index - 1], "target": "SELF" if index == 1 else ("LOWEST_ALLY" if index in (7, 8) else "ENEMY"), "tactical_cost": 0},
            {"id": f"{base}_PASSIVE", "owner_id": cid, "type": "PASSIVE_SKILL", "name_key": f"SKILL_{code}_PASSIVE", "max_level": 10, "values": values(.045 + index * .003, .205 + index * .004, 10), "cooldown": 0, "effect": "STAT_UP", "target": "SELF", "tactical_cost": 0},
            {"id": f"{base}_ULTIMATE", "owner_id": cid, "type": "ULTIMATE_SKILL", "name_key": f"SKILL_{code}_ULTIMATE", "max_level": 5, "values": values(2.15 + index * .07, 4.35 + index * .08, 5, 1.05), "cooldown": 0, "effect": ultimate_types[index - 1], "target": "LOWEST_ALLY" if index in (1, 8) else "ENEMY", "tactical_cost": 2 + (index % 5)},
        ])
    return result


ENEMIES = [
    ("ENM001", "RUSH_WISP", "NORMAL", "MELEE_RUSH", "PHYSICAL", "ARMOR", 520, 70, 28),
    ("ENM002", "ARC_MOTE", "NORMAL", "RANGED", "ENERGY", "BARRIER", 440, 82, 22),
    ("ENM003", "SHELL_RELAY", "NORMAL", "DEFENDER", "PHYSICAL", "ARMOR", 760, 55, 62),
    ("ENM004", "MEND_ECHO", "NORMAL", "HEALER", "ENERGY", "WARD", 470, 48, 30),
    ("ENM005", "CHORUS_BIT", "NORMAL", "BUFFER", "ANOMALY", "WARD", 500, 58, 34),
    ("ENM006", "DUST_LENS", "NORMAL", "DEBUFFER", "ANOMALY", "BARRIER", 480, 64, 27),
    ("ENM007", "WARDEN_FRAME", "ELITE", "SUMMONER", "ENERGY", "ARMOR", 1700, 118, 88),
    ("ENM008", "BROADCASTER", "ELITE", "AREA", "ANOMALY", "WARD", 1500, 134, 64),
    ("ENM009", "IRON_CANTOR", "ELITE", "DEFENDER", "PHYSICAL", "BARRIER", 2100, 105, 112),
    ("BOSS001", "HOLLOW_ENGINE", "BOSS", "BOSS_PATTERN", "ENERGY", "ARMOR", 7200, 175, 126),
    ("BOSS002", "NIGHT_BELL", "BOSS", "BOSS_PATTERN", "ANOMALY", "WARD", 8600, 194, 138),
]


def enemy_data() -> list[dict]:
    out = []
    for eid, code, rank, role, attack, defense, hp, atk, deff in ENEMIES:
        item = {"id": eid, "name_key": f"ENEMY_{code}", "gender": "GENDERLESS_NONHUMAN", "rank": rank, "role": role, "attack_type": attack, "defense_type": defense, "level": 1, "stats": {"HP": hp, "ATK": atk, "DEF": deff, "ACC": 105, "EVA": 70, "CRIT": 65, "CRIT_RES": 45, "HEAL_POWER": 80}, "attack_interval": 1.45, "asset_id": f"enemy_{eid.lower()}_dev"}
        if rank == "BOSS":
            item["phases"] = ["PHASE_1", "PHASE_2", "ENRAGE", "DOWN"]
            item["patterns"] = [{"condition": "TIME", "value": 20, "action": "AOE"}, {"condition": "HP_BELOW", "value": .5, "action": "PHASE_2"}, {"condition": "TIME_LEFT_BELOW", "value": 20, "action": "ENRAGE"}]
        out.append(item)
    return out


def stage_data() -> tuple[list[dict], list[dict]]:
    stages, rewards = [], []
    override_path = SOURCE / "stage_balance_overrides.json"
    balance_overrides = json.loads(override_path.read_text(encoding="utf-8")) if override_path.exists() else {}
    normals = [
        [["ENM001", "ENM002"], ["ENM001", "ENM003"]],
        [["ENM001", "ENM002", "ENM002"], ["ENM003", "ENM004"]],
        [["ENM005", "ENM001"], ["ENM002", "ENM006", "ENM001"]],
        [["ENM003", "ENM004"], ["ENM001", "ENM005", "ENM006"]],
        [["ENM002", "ENM006"], ["ENM007"]],
        [["ENM001", "ENM003"], ["ENM002", "ENM004"], ["ENM007"]],
        [["ENM005", "ENM006"], ["ENM008"]],
        [["ENM003", "ENM004"], ["ENM008", "ENM001"]],
        [["ENM007"], ["ENM008"], ["ENM009"]],
        [["ENM003", "ENM006"], ["ENM007", "ENM008"], ["BOSS001"]],
    ]
    hard = [
        [["ENM007", "ENM002"], ["ENM009"]],
        [["ENM008", "ENM006"], ["ENM007", "ENM008"]],
        [["ENM009"], ["ENM007", "ENM008"], ["BOSS001"]],
        [["ENM007", "ENM009"], ["ENM008", "ENM009"]],
        [["ENM007", "ENM008"], ["ENM009", "ENM009"], ["BOSS002"]],
    ]
    for mode, wave_sets in (("NORMAL", normals), ("HARD", hard)):
        for i, waves in enumerate(wave_sets, 1):
            sid = f"CH01-{'N' if mode == 'NORMAL' else 'H'}{i:02d}"
            normal_cost = min(18, 6 + ((1 - 1) // 2) + ((i - 1) // 3))
            stamina = normal_cost if mode == "NORMAL" else min(24, normal_cost + 6)
            recommended = i if mode == "NORMAL" else 10 + i * 2
            reward_id = f"REWARD_{sid}"
            stage_override = balance_overrides.get(sid, {})
            stages.append({"id": sid, "chapter_id": "CH01", "mode": mode, "stage_number": i, "name_key": f"STAGE_{sid.replace('-', '_')}", "recommended_level": recommended, "post_cap_scale": float(stage_override.get("post_cap_scale", 1.0)), "stamina_cost": stamina, "time_limit": int(stage_override.get("time_limit", 90)), "target_time": int(stage_override.get("target_time", 70)), "waves": waves, "reward_table_id": reward_id, "boss": (mode == "NORMAL" and i == 10) or (mode == "HARD" and i == 5), "daily_attempts": 0 if mode == "NORMAL" else 3})
            primary = "TRAINING_NOTE_M" if i <= 3 else ("CREDIT" if i <= 5 else ("WEAPON_CHIP_M" if i <= 7 else "SKILL_BOOK_T1"))
            if mode == "HARD":
                primary = f"SHARD_CHR00{min(8, i + 3)}"
            farmable = {
                "CH01-N01": ["TRAINING_NOTE_S", "TRAINING_NOTE_M"],
                "CH01-N02": ["TRAINING_NOTE_L"],
                "CH01-N03": ["TRAINING_NOTE_XL"],
                "CH01-N04": ["BREAK_CORE_T1"],
                "CH01-N05": ["ROLE_TOKEN_T1", "FACTION_SEAL_T1"],
                "CH01-N06": ["WEAPON_CHIP_S", "WEAPON_CHIP_M", "WEAPON_ORE_T1"],
                "CH01-N07": ["WEAPON_CHIP_L", "WEAPON_CHIP_XL", "BLUEPRINT_T1"],
                "CH01-N08": ["SKILL_BOOK_T1", "SKILL_TOKEN_T1", "ULT_BOOK_T1"],
                "CH01-N09": ["SKILL_BOOK_T2", "SKILL_TOKEN_T2", "ULT_BOOK_T2"],
                "CH01-N10": ["BREAK_CORE_T2", "ROLE_TOKEN_T2", "FACTION_SEAL_T2", "WEAPON_ORE_T2", "BLUEPRINT_T2"],
                "CH01-H01": ["BREAK_CORE_T3", "ROLE_TOKEN_T3", "SKILL_BOOK_T3", "SKILL_TOKEN_T3", "ULT_BOOK_T3"],
                "CH01-H02": ["BREAK_CORE_T4", "ROLE_TOKEN_T4", "SKILL_BOOK_T4", "SKILL_TOKEN_T4", "ULT_BOOK_T4"],
                "CH01-H03": ["FACTION_SEAL_T3", "WEAPON_ORE_T3", "BLUEPRINT_T3"],
                "CH01-H04": ["WEAPON_ORE_T4", "BLUEPRINT_T4"],
                "CH01-H05": ["UNIVERSAL_CATALYST"],
            }[sid]
            guaranteed = [{"item_id": primary, "min": 1 if primary != "CREDIT" else 1200, "max": 2 if primary != "CREDIT" else 1800}]
            for farm_item in farmable:
                if farm_item != primary:
                    guaranteed.append({"item_id": farm_item, "min": 1, "max": 1})
            rewards.append({"id": reward_id, "stage_id": sid, "guaranteed": guaranteed, "bonus": [{"item_id": "BREAK_CORE_T1", "chance": .35, "quantity": 1}, {"item_id": "UNIVERSAL_CATALYST", "chance": .08, "quantity": 1, "pity_after_failures": 8}], "first_clear": [{"item_id": "CREDIT", "quantity": 2500 + i * 500}, {"item_id": "LANTERN_SHARD", "quantity": 10}]})
    return stages, rewards


def item_data() -> list[dict]:
    ids = [
        "CREDIT", "LANTERN_SHARD", "TRAINING_NOTE_S", "TRAINING_NOTE_M", "TRAINING_NOTE_L", "TRAINING_NOTE_XL",
        "BREAK_CORE_T1", "BREAK_CORE_T2", "BREAK_CORE_T3", "BREAK_CORE_T4",
        "ROLE_TOKEN_T1", "ROLE_TOKEN_T2", "ROLE_TOKEN_T3", "ROLE_TOKEN_T4",
        "FACTION_SEAL_T1", "FACTION_SEAL_T2", "FACTION_SEAL_T3",
        "SKILL_BOOK_T1", "SKILL_BOOK_T2", "SKILL_BOOK_T3", "SKILL_BOOK_T4",
        "SKILL_TOKEN_T1", "SKILL_TOKEN_T2", "SKILL_TOKEN_T3", "SKILL_TOKEN_T4",
        "ULT_BOOK_T1", "ULT_BOOK_T2", "ULT_BOOK_T3", "ULT_BOOK_T4",
        "WEAPON_CHIP_S", "WEAPON_CHIP_M", "WEAPON_CHIP_L", "WEAPON_CHIP_XL",
        "WEAPON_ORE_T1", "WEAPON_ORE_T2", "WEAPON_ORE_T3", "WEAPON_ORE_T4",
        "BLUEPRINT_T1", "BLUEPRINT_T2", "BLUEPRINT_T3", "BLUEPRINT_T4", "UNIVERSAL_CATALYST",
    ] + [f"SHARD_CHR{i:03d}" for i in range(1, 9)]
    xp = {"TRAINING_NOTE_S": 100, "TRAINING_NOTE_M": 500, "TRAINING_NOTE_L": 2500, "TRAINING_NOTE_XL": 10000, "WEAPON_CHIP_S": 100, "WEAPON_CHIP_M": 500, "WEAPON_CHIP_L": 2500, "WEAPON_CHIP_XL": 10000}
    return [{"id": item, "name_key": f"ITEM_{item}", "category": item.split("_")[0], "xp_value": xp.get(item, 0), "icon_asset_id": f"item_{item.lower()}_dev"} for item in ids]


def weapon_data() -> list[dict]:
    rows = []
    classes = ["BLADE", "COMPACT", "RIFLE", "HEAVY", "FOCUS", "SUPPORT_DEVICE"]
    for variant in range(2):
        for i, cls in enumerate(classes, 1):
            index = variant * 6 + i
            rows.append({"id": f"WPN{index:03d}", "name_key": f"WEAPON_{cls}_V{variant + 1}", "weapon_class": cls, "level": 1, "tier": 1, "max_level": 60, "primary_stat": "HEAL_POWER" if cls == "SUPPORT_DEVICE" else "ATK", "primary_l1": 18 + i * 3 + variant * 2, "primary_l60": 190 + i * 15 + variant * 12, "secondary_stat": ("EVA" if variant else ("ACC" if i % 2 else "CRIT")), "secondary_t3": 12 + i + variant * 3, "secondary_t5": 28 + i * 2 + variant * 4, "exclusive_owner_id": ""})
    return rows


def costs() -> tuple[list[dict], list[dict], list[dict]]:
    breakthrough = [
        {"target": 1, "level_cap": 40, "multiplier": 1.02, "cost": {"BREAK_CORE_T1": 10, "ROLE_TOKEN_T1": 5, "CREDIT": 10000}},
        {"target": 2, "level_cap": 60, "multiplier": 1.04, "cost": {"BREAK_CORE_T1": 20, "ROLE_TOKEN_T1": 10, "CREDIT": 25000}},
        {"target": 3, "level_cap": 80, "multiplier": 1.07, "cost": {"BREAK_CORE_T2": 20, "ROLE_TOKEN_T2": 12, "FACTION_SEAL_T1": 8, "CREDIT": 60000}},
        {"target": 4, "level_cap": 90, "multiplier": 1.10, "cost": {"BREAK_CORE_T3": 24, "ROLE_TOKEN_T3": 15, "FACTION_SEAL_T2": 10, "CREDIT": 120000}},
        {"target": 5, "level_cap": 100, "multiplier": 1.14, "cost": {"BREAK_CORE_T4": 30, "ROLE_TOKEN_T4": 20, "FACTION_SEAL_T3": 12, "UNIVERSAL_CATALYST": 2, "CREDIT": 250000}},
    ]
    normal_raw = [
        {"SKILL_BOOK_T1": 3, "CREDIT": 500},
        {"SKILL_BOOK_T1": 6, "SKILL_TOKEN_T1": 2, "CREDIT": 1000},
        {"SKILL_BOOK_T1": 9, "SKILL_TOKEN_T1": 4, "CREDIT": 2000},
        {"SKILL_BOOK_T2": 6, "SKILL_TOKEN_T1": 8, "CREDIT": 4000},
        {"SKILL_BOOK_T2": 10, "SKILL_TOKEN_T2": 5, "CREDIT": 8000},
        {"SKILL_BOOK_T3": 6, "SKILL_TOKEN_T2": 10, "CREDIT": 16000},
        {"SKILL_BOOK_T3": 10, "SKILL_TOKEN_T3": 6, "CREDIT": 30000},
        {"SKILL_BOOK_T4": 6, "SKILL_TOKEN_T3": 12, "CREDIT": 55000},
        {"SKILL_BOOK_T4": 10, "SKILL_TOKEN_T4": 8, "UNIVERSAL_CATALYST": 1, "CREDIT": 100000},
    ]
    normal = [{"skill_type": "NORMAL_OR_PASSIVE", "target_level": target, "cost": normal_raw[target - 2]} for target in range(2, 11)]
    ultimate_raw = [
        {"ULT_BOOK_T1": 8, "SKILL_TOKEN_T1": 4, "CREDIT": 5000},
        {"ULT_BOOK_T2": 12, "SKILL_TOKEN_T2": 8, "CREDIT": 20000},
        {"ULT_BOOK_T3": 16, "SKILL_TOKEN_T3": 12, "UNIVERSAL_CATALYST": 1, "CREDIT": 60000},
        {"ULT_BOOK_T4": 20, "SKILL_TOKEN_T4": 16, "UNIVERSAL_CATALYST": 3, "CREDIT": 150000},
    ]
    ultimate = [{"skill_type": "ULTIMATE", "target_level": target, "cost": ultimate_raw[target - 2]} for target in range(2, 6)]
    return breakthrough, normal, ultimate


def scenario_sources() -> list[dict]:
    specs = [
        ("SCN_PROLOGUE", "SCENARIO_PROLOGUE_TITLE", ["STORY_PRO_01", "STORY_PRO_02", "STORY_PRO_03"]),
        ("SCN_CH01_INTRO", "SCENARIO_CH01_INTRO_TITLE", ["STORY_C1I_01", "STORY_C1I_02", "STORY_C1I_03"]),
        ("SCN_CH01_MID_A", "SCENARIO_CH01_MID_A_TITLE", ["STORY_C1A_01", "STORY_C1A_02", "STORY_C1A_03"]),
        ("SCN_CH01_MID_B", "SCENARIO_CH01_MID_B_TITLE", ["STORY_C1B_01", "STORY_C1B_02", "STORY_C1B_03"]),
        ("SCN_CH01_MID_C", "SCENARIO_CH01_MID_C_TITLE", ["STORY_C1C_01", "STORY_C1C_02", "STORY_C1C_03"]),
        ("SCN_CH01_PREBOSS", "SCENARIO_CH01_PREBOSS_TITLE", ["STORY_PRE_01", "STORY_PRE_02", "STORY_PRE_03"]),
        ("SCN_CH01_OUTRO", "SCENARIO_CH01_OUTRO_TITLE", ["STORY_OUT_01", "STORY_OUT_02", "STORY_OUT_03"]),
        ("SCN_REL_MAERU", "SCENARIO_REL_MAERU_TITLE", ["STORY_REL_M_01", "STORY_REL_M_02", "STORY_REL_M_03"]),
        ("SCN_REL_IRI", "SCENARIO_REL_IRI_TITLE", ["STORY_REL_I_01", "STORY_REL_I_02", "STORY_REL_I_03"]),
    ]
    result = []
    for sid, title, lines in specs:
        commands = [{"id": "start", "command": "set_background", "asset_id": "bg_lantern_tunnel_dev"}, {"command": "show_portrait", "slot": "RIGHT", "asset_id": "portrait_chr001_dev", "expression": "DEFAULT"}, {"command": "fade_in", "duration": .35}]
        for i, line in enumerate(lines):
            commands.append({"command": "dialogue" if i != 1 else "narration", "speaker_key": "SPEAKER_ROUTEKEEPER" if i == 0 else "SPEAKER_MAERU", "text_key": line})
        if sid == "SCN_PROLOGUE":
            commands.extend([{"command": "choice", "choices": [{"text_key": "CHOICE_LIGHT", "set_flag": "CHOSE_LIGHT"}, {"text_key": "CHOICE_RECORD", "set_flag": "CHOSE_RECORD"}]}, {"command": "set_flag", "flag": "PROLOGUE_READ", "value": True}])
        if sid == "SCN_CH01_PREBOSS":
            commands.append({"command": "start_battle", "stage_id": "CH01-N10"})
        commands.extend([{"command": "grant_reward", "item_id": "LANTERN_SHARD", "quantity": 5}, {"command": "end_scenario"}])
        result.append({"id": sid, "title_key": title, "chapter_id": "REL" if "REL_" in sid else ("PROLOGUE" if sid == "SCN_PROLOGUE" else "CH01"), "commands": commands})
    return result


LOCALIZED = {
    "GAME_TITLE": ("랜턴라인: 잔광기록", "Lanternline: Afterglow Records"),
    "GAME_SUBTITLE": ("빛이 끊긴 세계에서 이야기를 잇는 사람들", "People reconnecting stories in a lightless world"),
    "SPEAKER_ROUTEKEEPER": ("길잡이", "Routekeeper"), "SPEAKER_MAERU": ("마에루", "Maeru"),
    "CHOICE_LIGHT": ("먼저 불빛을 확인한다", "Check the light first"), "CHOICE_RECORD": ("기록 장치를 확보한다", "Secure the recorder"),
}


def localization(characters, enemies, stages, skills, weapons, items, scenarios) -> dict[str, tuple[str, str]]:
    loc = dict(LOCALIZED)
    ko_names = {"MAERU": "마에루", "ROAN": "로안", "NARIN": "나린", "EDA": "에다", "SOREN": "소렌", "VERA": "베라", "TOA": "토아", "IRI": "이리"}
    skill_names = {
        "MAERU": {"NORMAL": "결속 방패", "PASSIVE": "수호자의 맹세", "ULTIMATE": "성벽의 등불"},
        "ROAN": {"NORMAL": "선로 돌진", "PASSIVE": "돌파 호흡", "ULTIMATE": "철편 난무"},
        "NARIN": {"NORMAL": "정밀 사격", "PASSIVE": "관측 보정", "ULTIMATE": "유성 연사"},
        "EDA": {"NORMAL": "전류 도약", "PASSIVE": "과충전 회로", "ULTIMATE": "청뢰 낙하"},
        "SOREN": {"NORMAL": "공명 포격", "PASSIVE": "포구 안정화", "ULTIMATE": "별가루 포화"},
        "VERA": {"NORMAL": "교란 잔상", "PASSIVE": "변조 필드", "ULTIMATE": "침묵의 파장"},
        "TOA": {"NORMAL": "보호 신호", "PASSIVE": "중계 증폭", "ULTIMATE": "안전지대 전개"},
        "IRI": {"NORMAL": "회복 파동", "PASSIVE": "온기 기록", "ULTIMATE": "새벽의 합창"},
    }
    enemy_names = {
        "ENM001": "화염 송곳짐승", "ENM002": "전류 부유체", "ENM003": "장갑 중계기",
        "ENM004": "수복 잔향", "ENM005": "합창 파편", "ENM006": "먼지 렌즈",
        "ENM007": "감시자 골격", "ENM008": "왜곡 방송국", "ENM009": "철의 선창자",
        "BOSS001": "공허 기관", "BOSS002": "심야의 종",
    }
    item_names = {
        "BLUEPRINT_T1": "설계도 T1", "BLUEPRINT_T2": "설계도 T2", "BLUEPRINT_T3": "설계도 T3", "BLUEPRINT_T4": "설계도 T4",
        "BREAK_CORE_T1": "돌파 코어 T1", "BREAK_CORE_T2": "돌파 코어 T2", "BREAK_CORE_T3": "돌파 코어 T3", "BREAK_CORE_T4": "돌파 코어 T4",
        "CREDIT": "크레딧", "FACTION_SEAL_T1": "조직 인장 T1", "FACTION_SEAL_T2": "조직 인장 T2", "FACTION_SEAL_T3": "조직 인장 T3",
        "LANTERN_SHARD": "등불 파편", "ROLE_TOKEN_T1": "역할 토큰 T1", "ROLE_TOKEN_T2": "역할 토큰 T2", "ROLE_TOKEN_T3": "역할 토큰 T3", "ROLE_TOKEN_T4": "역할 토큰 T4",
        "SKILL_BOOK_T1": "기술 교본 T1", "SKILL_BOOK_T2": "기술 교본 T2", "SKILL_BOOK_T3": "기술 교본 T3", "SKILL_BOOK_T4": "기술 교본 T4",
        "SKILL_TOKEN_T1": "기술 토큰 T1", "SKILL_TOKEN_T2": "기술 토큰 T2", "SKILL_TOKEN_T3": "기술 토큰 T3", "SKILL_TOKEN_T4": "기술 토큰 T4",
        "TRAINING_NOTE_S": "훈련 노트 S", "TRAINING_NOTE_M": "훈련 노트 M", "TRAINING_NOTE_L": "훈련 노트 L", "TRAINING_NOTE_XL": "훈련 노트 XL",
        "ULT_BOOK_T1": "궁극 교본 T1", "ULT_BOOK_T2": "궁극 교본 T2", "ULT_BOOK_T3": "궁극 교본 T3", "ULT_BOOK_T4": "궁극 교본 T4",
        "UNIVERSAL_CATALYST": "범용 촉매", "WEAPON_CHIP_S": "무기 칩 S", "WEAPON_CHIP_M": "무기 칩 M", "WEAPON_CHIP_L": "무기 칩 L", "WEAPON_CHIP_XL": "무기 칩 XL",
        "WEAPON_ORE_T1": "무기 광석 T1", "WEAPON_ORE_T2": "무기 광석 T2", "WEAPON_ORE_T3": "무기 광석 T3", "WEAPON_ORE_T4": "무기 광석 T4",
    }
    for c in characters:
        code = c["name_key"].split("_")[1]
        loc[c["name_key"]] = (ko_names[code], code.title())
        loc[c["description_key"]] = ("등로단의 %s 역할을 맡은 탐사대원." % c["role"], "A Lamplighter serving as %s of the expedition." % c["role"])
    for s in skills:
        suffix = s["type"].replace("_SKILL", "")
        code = next(c["name_key"].split("_")[1] for c in characters if c["id"] == s["owner_id"])
        loc[s["name_key"]] = (skill_names[code][suffix], f"{code.title()} {suffix.title()} Skill")
    for e in enemies:
        loc[e["name_key"]] = (enemy_names[e["id"]], f"Echoform {e['id']}")
    for s in stages:
        loc[s["name_key"]] = (f"제1장 {s['mode']} {s['stage_number']}", f"Chapter 1 {s['mode']} {s['stage_number']}")
    for w in weapons:
        loc[w["name_key"]] = (f"공용 {w['weapon_class']} 장비 {w['id']}", f"Common {w['weapon_class']} Gear {w['id']}")
    for item in items:
        if item["id"].startswith("SHARD_"):
            character_code = item["id"].replace("SHARD_", "")
            character = next(c for c in characters if c["id"] == character_code)
            loc[item["name_key"]] = (ko_names[character["name_key"].split("_")[1]] + " 조각", item["id"])
        else:
            loc[item["name_key"]] = (item_names[item["id"]], item["id"])
    for scn in scenarios:
        loc[scn["title_key"]] = (scn["id"].replace("SCN_", "").replace("_", " "), scn["id"].replace("SCN_", "").replace("_", " "))
    story_ko = {
        "STORY_PRO_01": "대정전 뒤, 지하의 광맥 철로는 마지막 도시들을 잇는 유일한 길이 되었다.", "STORY_PRO_02": "새로 깨어난 기록 항해자는 끊긴 등불과 사람들의 기억을 복구해야 한다.", "STORY_PRO_03": "첫 신호는 폐쇄된 제7 승강장에서 깜박이고 있었다.",
        "STORY_C1I_01": "등로단은 잔광 폭풍 속에서도 움직이는 소규모 복구 조직이다.", "STORY_C1I_02": "마에루는 지도에 없는 선로에서 구조 요청을 들었다고 말했다.", "STORY_C1I_03": "우리는 신호의 진위를 확인하기 위해 출발했다.",
        "STORY_C1A_01": "첫 터널에는 기억을 흉내 내는 잔향체가 모여 있었다.", "STORY_C1A_02": "그것들은 사람의 목소리를 냈지만 질문에는 답하지 못했다.", "STORY_C1A_03": "전투 뒤 손상되지 않은 기록편 하나를 회수했다.",
        "STORY_C1B_01": "기록편에는 오래전 정거장의 대피 순서가 남아 있었다.", "STORY_C1B_02": "누군가 마지막 열차의 행선지를 고의로 지웠다.", "STORY_C1B_03": "나린은 지워진 층 아래에서 새로운 좌표를 찾아냈다.",
        "STORY_C1C_01": "좌표는 폐쇄된 종탑형 중계기로 이어졌다.", "STORY_C1C_02": "이리는 신호 속에 생체 맥박과 비슷한 주기가 있다고 분석했다.", "STORY_C1C_03": "잔향체의 군집이 우리보다 먼저 중계기를 포위했다.",
        "STORY_PRE_01": "거대한 공허기관이 선로의 빛을 삼키며 깨어났다.", "STORY_PRE_02": "마에루는 모두에게 각자의 등불을 확인하라고 명령했다.", "STORY_PRE_03": "우리가 지키려는 것은 선로가 아니라, 그 끝에서 기다리는 사람들의 이야기다.",
        "STORY_OUT_01": "공허기관이 멈추자 지워졌던 행선지가 다시 나타났다.", "STORY_OUT_02": "마지막 열차는 사라진 도시가 아니라 이동 중인 피난처를 향하고 있었다.", "STORY_OUT_03": "등로단은 다음 등불을 향해 제1 정거장을 떠났다.",
        "STORY_REL_M_01": "마에루는 매일 출발 전에 빈 좌석의 안전띠까지 확인했다.", "STORY_REL_M_02": "돌아오지 못한 동료의 자리를 기억하기 위한 습관이라고 했다.", "STORY_REL_M_03": "오늘은 그 자리에 새 구조 장비를 놓고 함께 웃었다.",
        "STORY_REL_I_01": "이리는 고장 난 안내 방송을 모아 작은 합창곡을 만들었다.", "STORY_REL_I_02": "완벽한 음정보다 누군가 살아 있었다는 흔적이 중요하다고 말했다.", "STORY_REL_I_03": "우리는 다음 정거장에서 그 곡을 틀기로 약속했다.",
    }
    for key, ko in story_ko.items():
        loc[key] = (ko, f"[DEV EN] {key}")
    return loc


def main() -> None:
    characters = character_data()
    skills = skill_data()
    enemies = enemy_data()
    stages, rewards = stage_data()
    items = item_data()
    weapons = weapon_data()
    breakthrough, normal_costs, ultimate_costs = costs()
    scenarios = scenario_sources()
    char_levels, acct_levels, weapon_levels = level_rows(), account_rows(), weapon_level_rows()
    affinity_matrix = json.loads((SOURCE / "affinity_matrix.json").read_text(encoding="utf-8"))
    status_effects = json.loads((SOURCE / "status_effects.json").read_text(encoding="utf-8"))

    write_csv(SOURCE / "characters.csv", [{**c, "stats_l1": json.dumps(c["stats_l1"], separators=(",", ":")), "stats_l100": json.dumps(c["stats_l100"], separators=(",", ":")), "tags": "|".join(c["tags"])} for c in characters])
    write_csv(SOURCE / "character_archetypes.csv", [{"id": role, "description": role, "default_position": "FRONT" if role in ("GUARDIAN", "VANGUARD") else ("BACK" if role in ("ARTILLERY", "MEDIC") else "MIDDLE")} for role in ["GUARDIAN", "VANGUARD", "ASSAULT", "ARTILLERY", "SPECIALIST", "MEDIC"]])
    write_csv(SOURCE / "character_level_curve.csv", char_levels)
    write_csv(SOURCE / "account_level_curve.csv", acct_levels)
    write_csv(SOURCE / "weapon_level_curve.csv", weapon_levels)
    write_csv(SOURCE / "breakthroughs.csv", [{**b, "cost": json.dumps(b["cost"], separators=(",", ":"))} for b in breakthrough])
    write_json(SOURCE / "skills.json", skills)
    write_csv(SOURCE / "skill_upgrade_costs.csv", [{**x, "cost": json.dumps(x["cost"], separators=(",", ":"))} for x in normal_costs + ultimate_costs])
    write_csv(SOURCE / "weapons.csv", weapons)
    write_csv(SOURCE / "weapon_tier_costs.csv", [
        {"from_tier": 1, "target_tier": 2, "required_level": 10, "cost": '{"WEAPON_ORE_T1":10,"BLUEPRINT_T1":3,"CREDIT":5000}'},
        {"from_tier": 2, "target_tier": 3, "required_level": 20, "cost": '{"WEAPON_ORE_T1":20,"BLUEPRINT_T1":8,"CREDIT":15000}'},
        {"from_tier": 3, "target_tier": 4, "required_level": 30, "cost": '{"WEAPON_ORE_T2":20,"BLUEPRINT_T2":10,"UNIVERSAL_CATALYST":1,"CREDIT":40000}'},
        {"from_tier": 4, "target_tier": 5, "required_level": 40, "cost": '{"WEAPON_ORE_T3":24,"BLUEPRINT_T3":12,"UNIVERSAL_CATALYST":2,"CREDIT":90000}'},
        {"from_tier": 5, "target_tier": 6, "required_level": 50, "cost": '{"WEAPON_ORE_T4":30,"BLUEPRINT_T4":15,"UNIVERSAL_CATALYST":4,"CREDIT":180000}'},
    ])
    write_csv(SOURCE / "enemies.csv", [{**e, "stats": json.dumps(e["stats"], separators=(",", ":")), "patterns": json.dumps(e.get("patterns", []), separators=(",", ":"))} for e in enemies])
    write_csv(SOURCE / "stages.csv", [{**s, "waves": json.dumps(s["waves"], separators=(",", ":"))} for s in stages])
    write_json(SOURCE / "stage_rewards.json", rewards)
    write_csv(SOURCE / "reward_items.csv", items)
    write_json(SOURCE / "chapters.json", [{"id": "CH01", "number": 1, "name_key": "CHAPTER_01", "normal_stage_ids": [s["id"] for s in stages if s["mode"] == "NORMAL"], "hard_stage_ids": [s["id"] for s in stages if s["mode"] == "HARD"]}])
    for scn in scenarios:
        write_json(SOURCE / "scenarios" / f"{scn['id'].lower()}.json", scn)

    loc = localization(characters, enemies, stages, skills, weapons, items, scenarios)
    compiled_localization = {"ko": {}, "en": {}}
    for index, locale in enumerate(("ko", "en")):
        rows = [{"key": key, "text": pair[index]} for key, pair in sorted(loc.items())]
        compiled_localization[locale] = {
            key: pair[index].replace("\\n", "\n") for key, pair in sorted(loc.items())
        }
        write_csv(LOCALE / f"{locale}.csv", rows, ["key", "text"])
        write_csv(SOURCE / "localization" / f"{locale}.csv", rows, ["key", "text"])
    write_json(COMPILED / "localization.json", compiled_localization)

    # Chapter-map JSON remains a separate content authority because it contains
    # geometry/patrol/relay data rather than battle balance rows.  Compile it
    # through the same deterministic tool so source and Web runtime cannot
    # silently diverge after an exploration update.
    chapter_map_source = SOURCE / "chapter_maps"
    for map_path in sorted(chapter_map_source.glob("*.json")):
        write_json(COMPILED / "chapter_maps" / map_path.name, json.loads(map_path.read_text(encoding="utf-8")))

    compiled = {
        "data_version": "0.1.0-dev.2",
        "content_policy_version": 1,
        "required_engine": "4.7.1-stable",
        "characters": characters,
        "skills": skills,
        "enemies": enemies,
        "stages": stages,
        "rewards": rewards,
        "items": items,
        "weapons": weapons,
        "chapters": [{"id": "CH01", "number": 1, "name_key": "CHAPTER_01"}],
        "scenarios": scenarios,
        "character_level_curve": char_levels,
        "account_level_curve": acct_levels,
        "weapon_level_curve": weapon_levels,
        "breakthroughs": [{"stage": 0, "level_cap": 20, "multiplier": 1.0, "cost": {}}] + breakthrough,
        "skill_upgrade_costs": normal_costs + ultimate_costs,
        "weapon_tier_costs": [
            {"from_tier": 1, "target_tier": 2, "required_level": 10, "cost": {"WEAPON_ORE_T1": 10, "BLUEPRINT_T1": 3, "CREDIT": 5000}},
            {"from_tier": 2, "target_tier": 3, "required_level": 20, "cost": {"WEAPON_ORE_T1": 20, "BLUEPRINT_T1": 8, "CREDIT": 15000}},
            {"from_tier": 3, "target_tier": 4, "required_level": 30, "cost": {"WEAPON_ORE_T2": 20, "BLUEPRINT_T2": 10, "UNIVERSAL_CATALYST": 1, "CREDIT": 40000}},
            {"from_tier": 4, "target_tier": 5, "required_level": 40, "cost": {"WEAPON_ORE_T3": 24, "BLUEPRINT_T3": 12, "UNIVERSAL_CATALYST": 2, "CREDIT": 90000}},
            {"from_tier": 5, "target_tier": 6, "required_level": 50, "cost": {"WEAPON_ORE_T4": 30, "BLUEPRINT_T4": 15, "UNIVERSAL_CATALYST": 4, "CREDIT": 180000}},
        ],
        "weapon_tier_caps": {"1": 10, "2": 20, "3": 30, "4": 40, "5": 50, "6": 60},
        "affinity_matrix": affinity_matrix,
        "status_effects": status_effects,
    }
    write_json(COMPILED / "game_data.json", compiled)

    total_char_xp = sum(r["xp_to_next"] for r in char_levels)
    total_char_credits = sum(r["credit_cost"] for r in char_levels)
    total_weapon_xp = sum(r["xp_to_next"] for r in weapon_levels)
    REPORTS.mkdir(parents=True, exist_ok=True)
    growth_lines = ["# Character Growth Table", "", f"Regression: EXP `{total_char_xp:,}` / credits `{total_char_credits:,}`", "", "| Level | Curve | XP next | Credits |", "|---:|---:|---:|---:|"]
    growth_lines += [f"| {r['level']} | {r['curve']} | {r['xp_to_next']:,} | {r['credit_cost']:,} |" for r in char_levels]
    (REPORTS / "CHARACTER_GROWTH_TABLE.md").write_text("\n".join(growth_lines) + "\n", encoding="utf-8")
    print(json.dumps({"characters": len(characters), "skills": len(skills), "enemies": len(enemies), "stages": len(stages), "scenarios": len(scenarios), "character_xp_total": total_char_xp, "character_credit_total": total_char_credits, "weapon_xp_total": total_weapon_xp}, ensure_ascii=False))


if __name__ == "__main__":
    main()
