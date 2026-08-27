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

# The expansion cast is data, not a bank of per-character booleans in save
# code. Every row has its own immutable ID and visual asset IDs downstream;
# numeric baselines are derived deterministically by role so existing CHR001–8
# balance stays byte-for-byte unchanged.
EXPANSION_CHARACTERS = [
    ("CHR009", "LIV", "VANGUARD"), ("CHR010", "SEON", "MEDIC"), ("CHR011", "ADELINE", "ARTILLERY"), ("CHR012", "KIR", "SPECIALIST"),
    ("CHR013", "REMA", "GUARDIAN"), ("CHR014", "VEON", "ASSAULT"), ("CHR015", "HART", "ARTILLERY"), ("CHR016", "ORSA", "GUARDIAN"),
    ("CHR017", "TIEL", "MEDIC"), ("CHR018", "RIAS", "ASSAULT"), ("CHR019", "PERIN", "SPECIALIST"), ("CHR020", "KARN", "VANGUARD"),
    ("CHR021", "NOAR", "MEDIC"), ("CHR022", "SEB", "VANGUARD"), ("CHR023", "YURIEN", "ARTILLERY"), ("CHR024", "MOEN", "SPECIALIST"),
    ("CHR025", "LAVENT", "GUARDIAN"), ("CHR026", "KAIREN", "ASSAULT"),
    ("CHR027", "INOA", "SPECIALIST"), ("CHR028", "DRAN", "VANGUARD"), ("CHR029", "MERIN", "MEDIC"), ("CHR030", "CIEL", "ARTILLERY"),
    ("CHR031", "ROME", "GUARDIAN"), ("CHR032", "KIAN", "ASSAULT"), ("CHR033", "DAEL", "SPECIALIST"), ("CHR034", "ORBIN", "GUARDIAN"),
    ("CHR035", "HERAON", "ARTILLERY"), ("CHR036", "MIRE", "MEDIC"), ("CHR037", "RAEN", "VANGUARD"), ("CHR038", "ZERN", "ASSAULT"),
    ("CHR039", "SOA", "SPECIALIST"), ("CHR040", "BAEL", "MEDIC"), ("CHR041", "TERAN", "VANGUARD"), ("CHR042", "YUNAK", "ARTILLERY"),
    ("CHR043", "ARINT", "GUARDIAN"), ("CHR044", "VELK", "ASSAULT"),
]


def _expansion_character_tuple(index: int, character_id: str, code: str, role: str) -> tuple:
    position = {"GUARDIAN": "FRONT", "VANGUARD": "FRONT", "ASSAULT": "MIDDLE", "ARTILLERY": "BACK", "SPECIALIST": "MIDDLE", "MEDIC": "BACK"}[role]
    weapon = {"GUARDIAN": "HEAVY", "VANGUARD": "BLADE", "ASSAULT": "RIFLE", "ARTILLERY": "HEAVY", "SPECIALIST": "FOCUS", "MEDIC": "SUPPORT_DEVICE"}[role]
    attack = "PHYSICAL" if role in ("VANGUARD", "ASSAULT") else ("ANOMALY" if role in ("ARTILLERY", "SPECIALIST") else "ENERGY")
    defense = "ARMOR" if role in ("GUARDIAN", "VANGUARD") else ("WARD" if role in ("ARTILLERY", "SPECIALIST") else "BARRIER")
    base_by_role = {
        "GUARDIAN": (1240, 106, 86, 104, 472, 88),
        "VANGUARD": (970, 132, 62, 113, 500, 72),
        "ASSAULT": (755, 150, 43, 127, 535, 80),
        "ARTILLERY": (695, 162, 37, 118, 476, 86),
        "SPECIALIST": (745, 116, 47, 123, 505, 90),
        "MEDIC": (815, 84, 52, 116, 490, 146),
    }
    hp, atk, deff, acc, eva, heal = base_by_role[role]
    variant = index % 6
    hp += variant * 18
    atk += variant * 3
    deff += variant
    acc += variant
    eva += variant * 2
    heal += variant * 3
    crit = 76 + (index * 7) % 32
    return (character_id, code, role, position, attack, defense, weapon, hp, atk, deff, acc, eva, crit, heal, hp * 8 + 320, atk * 7 + 90, deff * 6 + 36, heal * 7 + 80)


for expansion_index, expansion in enumerate(EXPANSION_CHARACTERS, 9):
    CHARACTERS.append(_expansion_character_tuple(expansion_index, *expansion))


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
            # CHR009 onward are authored for the map's ! contact transaction.
            # Keeping this aligned with CONTACT_EVENT_SPECS prevents the roster
            # catalogue from falsely presenting a shard-only acquisition path.
            "acquisition_source": "DEFAULT" if index <= 5 else ("STORY" if index <= 8 else "EVENT_CONTACT"),
        })
    return result


def values(start: float, end: float, count: int, curve: float = 1.0) -> list[float]:
    return [round(start + (end - start) * pow(i / (count - 1), curve), 3) for i in range(count)]


def skill_data() -> list[dict]:
    result = []
    ultimate_types = ["SHIELD", "DAMAGE", "DAMAGE", "DAMAGE", "AOE_DAMAGE", "DEBUFF", "BUFF", "HEAL"]
    normal_types = ["TAUNT", "DAMAGE", "DAMAGE", "DAMAGE", "AOE_DAMAGE", "SLOW", "SHIELD", "HEAL"]
    role_normal = {"GUARDIAN": "TAUNT", "VANGUARD": "DAMAGE", "ASSAULT": "DAMAGE", "ARTILLERY": "AOE_DAMAGE", "SPECIALIST": "DEBUFF", "MEDIC": "HEAL"}
    role_ultimate = {"GUARDIAN": "SHIELD", "VANGUARD": "DAMAGE", "ASSAULT": "DAMAGE", "ARTILLERY": "AOE_DAMAGE", "SPECIALIST": "BUFF", "MEDIC": "HEAL"}
    for index, c in enumerate(CHARACTERS, 1):
        cid, code, role = c[0], c[1], c[2]
        base = f"SK_{cid}"
        normal_effect = normal_types[index - 1] if index <= len(normal_types) else role_normal[role]
        ultimate_effect = ultimate_types[index - 1] if index <= len(ultimate_types) else role_ultimate[role]
        support_target = "LOWEST_ALLY" if role == "MEDIC" else ("SELF" if role == "GUARDIAN" else "ENEMY")
        normal_target = ("SELF" if index == 1 else ("LOWEST_ALLY" if index in (7, 8) else "ENEMY")) if index <= 8 else support_target
        ultimate_target = ("LOWEST_ALLY" if index in (1, 8) else "ENEMY") if index <= 8 else support_target
        result.extend([
            {"id": f"{base}_NORMAL", "owner_id": cid, "type": "NORMAL_SKILL", "name_key": f"SKILL_{code}_NORMAL", "icon_asset_id": f"skill_icon_{cid.lower()}_normal", "max_level": 10, "values": values(1.00 + index * .035, 2.02 + index * .04, 10, 1.08), "cooldown": 7.0 + index % 4, "effect": normal_effect, "target": normal_target, "tactical_cost": 0},
            {"id": f"{base}_PASSIVE", "owner_id": cid, "type": "PASSIVE_SKILL", "name_key": f"SKILL_{code}_PASSIVE", "icon_asset_id": f"skill_icon_{cid.lower()}_passive", "max_level": 10, "values": values(.045 + index * .003, .205 + index * .004, 10), "cooldown": 0, "effect": "STAT_UP", "target": "SELF", "tactical_cost": 0},
            {"id": f"{base}_ULTIMATE", "owner_id": cid, "type": "ULTIMATE_SKILL", "name_key": f"SKILL_{code}_ULTIMATE", "icon_asset_id": f"skill_icon_{cid.lower()}_ultimate", "max_level": 5, "values": values(2.15 + index * .07, 4.35 + index * .08, 5, 1.05), "cooldown": 0, "effect": ultimate_effect, "target": ultimate_target, "tactical_cost": 2 + (index % 5)},
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
    ("ENM010", "BROKENLINE_TRACKER", "NORMAL", "MELEE_RUSH", "PHYSICAL", "ARMOR", 590, 86, 34),
    ("ENM011", "GLASS_TRANSMITTER", "NORMAL", "RANGED", "ENERGY", "BARRIER", 510, 96, 28),
    ("ENM012", "AFTERGLOW_SCREEN", "NORMAL", "DEFENDER", "ANOMALY", "WARD", 820, 66, 74),
    ("BOSS003", "WHITE_DAWN_OBSERVER", "BOSS", "BOSS_PATTERN", "ENERGY", "BARRIER", 9200, 212, 146),
    ("ENM013", "REVERSE_ELECTRODE", "NORMAL", "RANGED", "ANOMALY", "BARRIER", 640, 108, 35),
    ("ENM014", "FALLEN_BATTERY", "NORMAL", "ARTILLERY", "ENERGY", "WARD", 600, 122, 31),
    ("ENM015", "VACANT_CHORUS", "NORMAL", "BUFFER", "ANOMALY", "WARD", 690, 78, 48),
    ("BOSS004", "REVERSE_GATEKEEPER", "BOSS", "BOSS_PATTERN", "ENERGY", "ARMOR", 10800, 232, 162),
    ("BOSS005", "RETURN_FORMATION_CORE", "BOSS", "BOSS_PATTERN", "ANOMALY", "BARRIER", 12400, 254, 176),
]


_BOSS_PATTERN_SETS = {
    # These are gameplay patterns, not merely the draw-time VFX labels.  Each
    # finale therefore has an independently auditable cadence and payoff.
    "BOSS001": [
        {"condition": "TIME", "value": 18, "action": "IMPLODE", "damage_multiplier": .78},
        {"condition": "HP_BELOW", "value": .62, "action": "PHASE_2"},
        {"condition": "TIME_LEFT_BELOW", "value": 20, "action": "RUPTURE", "damage_multiplier": 1.04},
    ],
    "BOSS002": [
        {"condition": "TIME", "value": 14, "action": "RESONANCE", "damage_multiplier": .52},
        {"condition": "TIME", "value": 28, "action": "RESONANCE", "damage_multiplier": .88},
        {"condition": "HP_BELOW", "value": .48, "action": "ENRAGE", "outgoing_multiplier": 1.42},
    ],
    "BOSS003": [
        {"condition": "TIME", "value": 12, "action": "LOCK_ON", "damage_multiplier": 1.18},
        {"condition": "HP_BELOW", "value": .60, "action": "PHASE_2"},
        {"condition": "TIME_LEFT_BELOW", "value": 32, "action": "OVERLOAD", "damage_multiplier": .92},
    ],
    "BOSS004": [
        {"condition": "TIME", "value": 16, "action": "GATE_CLOSE", "shield_multiplier": .64},
        {"condition": "HP_BELOW", "value": .55, "action": "PHASE_2"},
        {"condition": "TIME_LEFT_BELOW", "value": 24, "action": "GATE_REVERSE", "damage_multiplier": .86},
    ],
    "BOSS005": [
        {"condition": "TIME", "value": 10, "action": "NETWORK_FORM", "heal_multiplier": .18},
        {"condition": "HP_BELOW", "value": .58, "action": "PHASE_2"},
        {"condition": "TIME_LEFT_BELOW", "value": 18, "action": "NETWORK_COLLAPSE", "damage_multiplier": 1.10},
    ],
}


def enemy_data() -> list[dict]:
    out = []
    for eid, code, rank, role, attack, defense, hp, atk, deff in ENEMIES:
        item = {"id": eid, "name_key": f"ENEMY_{code}", "gender": "GENDERLESS_NONHUMAN", "rank": rank, "role": role, "attack_type": attack, "defense_type": defense, "level": 1, "stats": {"HP": hp, "ATK": atk, "DEF": deff, "ACC": 105, "EVA": 70, "CRIT": 65, "CRIT_RES": 45, "HEAL_POWER": 80}, "attack_interval": 1.45, "asset_id": f"enemy_{eid.lower()}_dev"}
        if rank == "BOSS":
            item["phases"] = ["PHASE_1", "PHASE_2", "ENRAGE", "DOWN"]
            item["patterns"] = _BOSS_PATTERN_SETS[eid]
        out.append(item)
    return out


def stage_data() -> tuple[list[dict], list[dict]]:
    stages, rewards = [], []
    override_path = SOURCE / "stage_balance_overrides.json"
    balance_overrides = json.loads(override_path.read_text(encoding="utf-8")) if override_path.exists() else {}
    normals = [
        [["ENM001", "ENM002"], ["ENM001", "ENM003"]],
        [["ENM001", "ENM002", "ENM002"], ["ENM003", "ENM004"]],
        [["ENM005", "ENM010"], ["ENM002", "ENM006", "ENM001"]],
        [["ENM003", "ENM004"], ["ENM001", "ENM005", "ENM006"]],
        [["ENM002", "ENM011"], ["ENM007"]],
        [["ENM001", "ENM003"], ["ENM002", "ENM004"], ["ENM007"]],
        [["ENM012", "ENM006"], ["ENM008"]],
        [["ENM003", "ENM004"], ["ENM008", "ENM001"]],
        [["ENM007"], ["ENM008"], ["ENM009"]],
        [["ENM003", "ENM006"], ["ENM007", "ENM008"], ["BOSS001"]],
    ]
    hard = [
        [["ENM007", "ENM002"], ["ENM009"]],
        [["ENM008", "ENM006"], ["ENM007", "ENM008"]],
        [["ENM009"], ["ENM007", "ENM008"], ["BOSS003"]],
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
            stages.append({"id": sid, "chapter_id": "CH01", "mode": mode, "stage_number": i, "name_key": f"STAGE_{sid.replace('-', '_')}", "recommended_level": recommended, "post_cap_scale": float(stage_override.get("post_cap_scale", 1.0)), "stamina_cost": stamina, "time_limit": int(stage_override.get("time_limit", 90)), "target_time": int(stage_override.get("target_time", 70)), "waves": waves, "reward_table_id": reward_id, "boss": any(str(enemy_id).startswith("BOSS") for wave in waves for enemy_id in wave), "daily_attempts": 0 if mode == "NORMAL" else 3})
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

    # Chapter 2 deliberately reuses the three established elite archetypes,
    # while adding only three new NORMAL enemies. Its two bosses are unique
    # entities and never tinted/relabelled copies of a prior boss.
    chapter_two_normals = [
        [["ENM013", "ENM001"], ["ENM014", "ENM002"]],
        [["ENM013", "ENM003"], ["ENM015", "ENM007"]],
        [["ENM014", "ENM015"], ["ENM013", "ENM006"]],
        [["ENM014", "ENM002"], ["ENM013", "ENM008"]],
        [["ENM015", "ENM003"], ["ENM014", "ENM007"]],
        [["ENM013", "ENM015"], ["ENM014", "ENM009"]],
        [["ENM014", "ENM003"], ["ENM013", "ENM007"]],
        [["ENM015", "ENM006"], ["ENM014", "ENM008"]],
        [["ENM013", "ENM014"], ["ENM015", "ENM007", "ENM009"]],
        [["ENM013", "ENM015"], ["ENM014", "ENM008"], ["BOSS004"]],
    ]
    chapter_two_hard = [
        [["ENM013", "ENM007"], ["ENM015", "ENM009"]],
        [["ENM014", "ENM008"], ["ENM013", "ENM009"]],
        [["ENM015", "ENM007"], ["ENM014", "ENM008"]],
        [["ENM013", "ENM014"], ["ENM007", "ENM009"]],
        [["ENM015", "ENM008"], ["ENM013", "ENM014"], ["BOSS005"]],
    ]
    for mode, wave_sets in (("NORMAL", chapter_two_normals), ("HARD", chapter_two_hard)):
        for i, waves in enumerate(wave_sets, 1):
            sid = f"CH02-{'N' if mode == 'NORMAL' else 'H'}{i:02d}"
            reward_id = f"REWARD_{sid}"
            stage_override = balance_overrides.get(sid, {})
            stamina = min(24, 10 + (i - 1) // 2 + (6 if mode == "HARD" else 0))
            stages.append({
                "id": sid, "chapter_id": "CH02", "mode": mode, "stage_number": i,
                "name_key": f"STAGE_{sid.replace('-', '_')}", "recommended_level": 20 + i * 2 + (10 if mode == "HARD" else 0),
                "post_cap_scale": float(stage_override.get("post_cap_scale", 1.0)), "stamina_cost": stamina,
                "time_limit": int(stage_override.get("time_limit", 95)), "target_time": int(stage_override.get("target_time", 74)),
                "waves": waves, "reward_table_id": reward_id,
                "boss": (mode == "NORMAL" and i == 10) or (mode == "HARD" and i == 5),
                "daily_attempts": 0 if mode == "NORMAL" else 3,
            })
            tier = "T2" if i <= 5 else ("T3" if mode == "NORMAL" else "T4")
            guaranteed = [{"item_id": "CREDIT", "min": 1800 + i * 250, "max": 2200 + i * 350}, {"item_id": f"BREAK_CORE_{tier}", "min": 1, "max": 2}]
            if mode == "HARD":
                guaranteed.append({"item_id": f"SHARD_CHR{26 + i:03d}", "min": 1, "max": 1})
            rewards.append({"id": reward_id, "stage_id": sid, "guaranteed": guaranteed, "bonus": [{"item_id": "UNIVERSAL_CATALYST", "chance": .12, "quantity": 1, "pity_after_failures": 7}], "first_clear": [{"item_id": "CREDIT", "quantity": 6000 + i * 600}, {"item_id": "LANTERN_SHARD", "quantity": 15}]})
    return stages, rewards


def item_data() -> list[dict]:
    ids = [
        "CREDIT", "LANTERN_SHARD", "EXPEDITION_ROUTE_MODULE_A", "EXPEDITION_ROUTE_MODULE_B", "TRAINING_NOTE_S", "TRAINING_NOTE_M", "TRAINING_NOTE_L", "TRAINING_NOTE_XL",
        "BREAK_CORE_T1", "BREAK_CORE_T2", "BREAK_CORE_T3", "BREAK_CORE_T4",
        "ROLE_TOKEN_T1", "ROLE_TOKEN_T2", "ROLE_TOKEN_T3", "ROLE_TOKEN_T4",
        "FACTION_SEAL_T1", "FACTION_SEAL_T2", "FACTION_SEAL_T3",
        "SKILL_BOOK_T1", "SKILL_BOOK_T2", "SKILL_BOOK_T3", "SKILL_BOOK_T4",
        "SKILL_TOKEN_T1", "SKILL_TOKEN_T2", "SKILL_TOKEN_T3", "SKILL_TOKEN_T4",
        "ULT_BOOK_T1", "ULT_BOOK_T2", "ULT_BOOK_T3", "ULT_BOOK_T4",
        "WEAPON_CHIP_S", "WEAPON_CHIP_M", "WEAPON_CHIP_L", "WEAPON_CHIP_XL",
        "WEAPON_ORE_T1", "WEAPON_ORE_T2", "WEAPON_ORE_T3", "WEAPON_ORE_T4",
        "BLUEPRINT_T1", "BLUEPRINT_T2", "BLUEPRINT_T3", "BLUEPRINT_T4", "UNIVERSAL_CATALYST",
    ] + [f"SHARD_CHR{i:03d}" for i in range(1, 45)]
    xp = {"TRAINING_NOTE_S": 100, "TRAINING_NOTE_M": 500, "TRAINING_NOTE_L": 2500, "TRAINING_NOTE_XL": 10000, "WEAPON_CHIP_S": 100, "WEAPON_CHIP_M": 500, "WEAPON_CHIP_L": 2500, "WEAPON_CHIP_XL": 10000}
    return [{"id": item, "name_key": f"ITEM_{item}", "category": item.split("_")[0], "xp_value": xp.get(item, 0), "icon_asset_id": ("item_lantern_shard_dev" if item.startswith("EXPEDITION_ROUTE_MODULE") else f"item_{item.lower()}_dev")} for item in ids]


# Each operation owns exactly one contact record and one real-time battle
# transaction. A contact can list one or two recruitments so the map never
# overlays a generic enemy asset on a companion-event stage.
CONTACT_EVENT_SPECS = {
    "CH01": [
        ("N01", [("CHR009", "IMMEDIATE_ON_VICTORY", "")]),
        ("N02", [("CHR010", "IMMEDIATE_ON_VICTORY", "")]),
        ("N03", [("CHR011", "IMMEDIATE_ON_VICTORY", ""), ("CHR012", "AFTER_STAGE_CLEAR", "CH01-N04")]),
        ("N04", [("CHR006", "IMMEDIATE_ON_VICTORY", ""), ("CHR013", "IMMEDIATE_ON_VICTORY", "")]),
        ("N05", [("CHR014", "IMMEDIATE_ON_VICTORY", "")]),
        ("N06", [("CHR015", "AFTER_STAGE_CLEAR", "CH01-N07")]),
        ("N07", [("CHR016", "IMMEDIATE_ON_VICTORY", ""), ("CHR017", "IMMEDIATE_ON_VICTORY", "")]),
        ("N08", [("CHR007", "AFTER_STAGE_CLEAR", "CH01-N09"), ("CHR018", "AFTER_STAGE_CLEAR", "CH01-N09")]),
        ("N09", [("CHR019", "IMMEDIATE_ON_VICTORY", "")]),
        ("N10", [("CHR020", "IMMEDIATE_ON_VICTORY", "")]),
        ("H01", [("CHR021", "IMMEDIATE_ON_VICTORY", "")]),
        ("H02", [("CHR022", "IMMEDIATE_ON_VICTORY", "")]),
        ("H03", [("CHR023", "AFTER_STAGE_CLEAR", "CH01-H03"), ("CHR024", "IMMEDIATE_ON_VICTORY", "")]),
        ("H04", [("CHR025", "IMMEDIATE_ON_VICTORY", "")]),
        ("H05", [("CHR026", "IMMEDIATE_ON_VICTORY", "")]),
    ],
    "CH02": [
        ("N01", [("CHR027", "IMMEDIATE_ON_VICTORY", "")]),
        ("N02", [("CHR028", "IMMEDIATE_ON_VICTORY", "")]),
        ("N03", [("CHR029", "AFTER_STAGE_CLEAR", "CH02-N04")]),
        ("N04", [("CHR030", "IMMEDIATE_ON_VICTORY", "")]),
        ("N05", [("CHR031", "IMMEDIATE_ON_VICTORY", ""), ("CHR032", "AFTER_STAGE_CLEAR", "CH02-N06")]),
        ("N06", [("CHR033", "IMMEDIATE_ON_VICTORY", "")]),
        ("N07", [("CHR034", "IMMEDIATE_ON_VICTORY", "")]),
        ("N08", [("CHR035", "IMMEDIATE_ON_VICTORY", "")]),
        ("N09", [("CHR036", "AFTER_STAGE_CLEAR", "CH02-N10")]),
        ("N10", [("CHR037", "IMMEDIATE_ON_VICTORY", ""), ("CHR038", "IMMEDIATE_ON_VICTORY", "")]),
        ("H01", [("CHR039", "IMMEDIATE_ON_VICTORY", "")]),
        ("H02", [("CHR040", "IMMEDIATE_ON_VICTORY", "")]),
        ("H03", [("CHR041", "IMMEDIATE_ON_VICTORY", "")]),
        ("H04", [("CHR042", "AFTER_STAGE_CLEAR", "CH02-H05"), ("CHR043", "IMMEDIATE_ON_VICTORY", "")]),
        ("H05", [("CHR044", "IMMEDIATE_ON_VICTORY", "")]),
    ],
}


def chapter_contact_events(chapter_id: str) -> list[dict]:
    events: list[dict] = []
    for route_stage, recruits in CONTACT_EVENT_SPECS[chapter_id]:
        stage_id = f"{chapter_id}-{route_stage}"
        node_id = f"NODE_{route_stage}"
        primary_id, primary_timing, primary_after = recruits[0]
        suffix = f"{chapter_id}_{route_stage}"
        event_id = f"EVENT_{suffix}"
        title_key = f"MAP_CONTACT_{suffix}_TITLE"
        body_key = f"MAP_CONTACT_{suffix}_BODY"
        outcome_key = f"MAP_CONTACT_{suffix}_OUTCOME"
        events.append({
            "event_encounter_id": event_id, "node_id": node_id, "marker": "BANG", "entry_type": "EVENT_CONTACT",
            "character_id": primary_id, "recruitment_timing": primary_timing, "recruit_after_stage_id": primary_after,
            "title_key": title_key, "body_key": body_key, "contact_outcome_key": outcome_key,
            "recruitments": [{"character_id": character_id, "recruitment_timing": timing, "recruit_after_stage_id": after_stage} for character_id, timing, after_stage in recruits],
            "stage_id": stage_id,
        })
    return events


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
    # Scenario presentation is authored here instead of applying one generic
    # CHR001 template. This is the deterministic source used to regenerate the
    # JSON files and the compiled runtime data, so portrait/background fixes
    # cannot silently regress on the next data build.
    specs = [
        {
            "id": "SCN_PROLOGUE", "title": "SCENARIO_PROLOGUE_TITLE", "chapter": "PROLOGUE",
            "background": "bg_lantern_tunnel_dev", "portrait": "portrait_chr001_dev",
            "extra_portraits": [
                {"command": "show_portrait", "slot": "LEFT", "asset_id": "portrait_chr002_dev", "expression": "SERIOUS"},
            ],
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_PRO_01", "SERIOUS"),
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_PRO_02", "SERIOUS"),
                ("dialogue", "SPEAKER_MAERU", "STORY_PRO_03", "BATTLE_FOCUS"),
                ("dialogue", "SPEAKER_ROAN", "STORY_PRO_04", "BATTLE_FOCUS"),
            ],
        },
        {
            "id": "SCN_CH01_INTRO", "title": "SCENARIO_CH01_INTRO_TITLE", "chapter": "CH01",
            "background": "bg_lantern_tunnel_dev", "portrait": "portrait_chr001_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C1I_01", "NEUTRAL"),
                ("dialogue", "SPEAKER_MAERU", "STORY_C1I_02", "SERIOUS"),
                ("dialogue", "SPEAKER_MAERU", "STORY_C1I_03", "BATTLE_FOCUS"),
            ],
        },
        {
            "id": "SCN_CH01_MID_A", "title": "SCENARIO_CH01_MID_A_TITLE", "chapter": "CH01",
            "background": "bg_ch01_glass_rail_story", "portrait": "portrait_chr002_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C1A_01", "ALERT"),
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C1A_02", "ALERT"),
                ("dialogue", "SPEAKER_ROAN", "STORY_C1A_03", "RELIEVED"),
            ],
        },
        {
            "id": "SCN_CH01_MID_B", "title": "SCENARIO_CH01_MID_B_TITLE", "chapter": "CH01",
            "background": "bg_ch01_glass_rail_story", "portrait": "portrait_chr003_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C1B_01", "SERIOUS"),
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C1B_02", "SERIOUS"),
                ("dialogue", "SPEAKER_NARIN", "STORY_C1B_03", "CONFIDENT"),
            ],
        },
        {
            "id": "SCN_CH01_MID_C", "title": "SCENARIO_CH01_MID_C_TITLE", "chapter": "CH01",
            "background": "bg_ch01_signal_cathedral_story", "portrait": "portrait_chr008_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C1C_01", "SERIOUS"),
                ("dialogue", "SPEAKER_IRI", "STORY_C1C_02", "CONCERNED"),
                ("dialogue", "SPEAKER_IRI", "STORY_C1C_03", "BATTLE_FOCUS"),
            ],
        },
        {
            "id": "SCN_CH01_PREBOSS", "title": "SCENARIO_CH01_PREBOSS_TITLE", "chapter": "CH01",
            "background": "bg_ch01_signal_cathedral_story", "portrait": "portrait_chr001_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_PRE_01", "ALERT"),
                ("dialogue", "SPEAKER_MAERU", "STORY_PRE_02", "SERIOUS"),
                ("dialogue", "SPEAKER_MAERU", "STORY_PRE_03", "BATTLE_FOCUS"),
            ],
        },
        {
            "id": "SCN_CH01_OUTRO", "title": "SCENARIO_CH01_OUTRO_TITLE", "chapter": "CH01",
            "background": "bg_lantern_tunnel_dev", "cg": "cg_ch01_pilot_teamwork",
            "portrait": "portrait_chr001_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_OUT_01", "RELIEVED"),
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_OUT_02", "RELIEVED"),
                ("dialogue", "SPEAKER_MAERU", "STORY_OUT_03", "SMILE"),
            ],
        },
        {
            "id": "SCN_CH02_INTRO", "title": "SCENARIO_CH02_INTRO_TITLE", "chapter": "CH02",
            "background": "bg_lantern_tunnel_dev", "portrait": "portrait_chr001_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C2I_01", "SERIOUS"),
                ("dialogue", "SPEAKER_MAERU", "STORY_C2I_02", "ALERT"),
                ("dialogue", "SPEAKER_MAERU", "STORY_C2I_03", "BATTLE_FOCUS"),
            ],
        },
        {
            "id": "SCN_CH02_MID_A", "title": "SCENARIO_CH02_MID_A_TITLE", "chapter": "CH02",
            "background": "bg_ch01_glass_rail_story", "portrait": "portrait_chr002_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C2A_01", "ALERT"),
                ("dialogue", "SPEAKER_ROAN", "STORY_C2A_02", "SERIOUS"),
                ("dialogue", "SPEAKER_ROAN", "STORY_C2A_03", "CONFIDENT"),
            ],
        },
        {
            "id": "SCN_CH02_MID_B", "title": "SCENARIO_CH02_MID_B_TITLE", "chapter": "CH02",
            "background": "bg_ch01_glass_rail_story", "portrait": "portrait_chr003_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C2B_01", "SERIOUS"),
                ("dialogue", "SPEAKER_NARIN", "STORY_C2B_02", "CONCERNED"),
                ("dialogue", "SPEAKER_NARIN", "STORY_C2B_03", "BATTLE_FOCUS"),
            ],
        },
        {
            "id": "SCN_CH02_PREBOSS", "title": "SCENARIO_CH02_PREBOSS_TITLE", "chapter": "CH02",
            "background": "bg_ch01_signal_cathedral_story", "portrait": "portrait_chr005_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C2P_01", "ALERT"),
                ("dialogue", "SPEAKER_SOREN", "STORY_C2P_02", "SERIOUS"),
                ("dialogue", "SPEAKER_SOREN", "STORY_C2P_03", "BATTLE_FOCUS"),
            ],
        },
        {
            "id": "SCN_CH02_HARD_INTRO", "title": "SCENARIO_CH02_HARD_INTRO_TITLE", "chapter": "CH02",
            "background": "bg_ch01_signal_cathedral_story", "portrait": "portrait_chr008_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C2H_01", "SERIOUS"),
                ("dialogue", "SPEAKER_IRI", "STORY_C2H_02", "CONCERNED"),
                ("dialogue", "SPEAKER_IRI", "STORY_C2H_03", "BATTLE_FOCUS"),
            ],
        },
        {
            "id": "SCN_CH02_OUTRO", "title": "SCENARIO_CH02_OUTRO_TITLE", "chapter": "CH02",
            "background": "bg_lantern_tunnel_dev", "portrait": "portrait_chr001_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C2O_01", "RELIEVED"),
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C2O_02", "RELIEVED"),
                ("dialogue", "SPEAKER_MAERU", "STORY_C2O_03", "SMILE"),
            ],
        },
        {
            "id": "SCN_REL_MAERU", "title": "SCENARIO_REL_MAERU_TITLE", "chapter": "REL",
            "background": "bg_lantern_tunnel_dev", "portrait": "portrait_chr001_dev",
            "lines": [
                ("dialogue", "SPEAKER_MAERU", "STORY_REL_M_01", "NEUTRAL"),
                ("dialogue", "SPEAKER_MAERU", "STORY_REL_M_02", "SAD"),
                ("dialogue", "SPEAKER_MAERU", "STORY_REL_M_03", "SMILE"),
            ],
        },
        {
            "id": "SCN_REL_IRI", "title": "SCENARIO_REL_IRI_TITLE", "chapter": "REL",
            "background": "bg_lantern_tunnel_dev", "portrait": "portrait_chr008_dev",
            "lines": [
                ("dialogue", "SPEAKER_IRI", "STORY_REL_I_01", "SMILE"),
                ("dialogue", "SPEAKER_IRI", "STORY_REL_I_02", "SERIOUS"),
                ("dialogue", "SPEAKER_IRI", "STORY_REL_I_03", "SMILE"),
            ],
        },
    ]
    result = []
    for spec in specs:
        first_expression = spec["lines"][0][3]
        commands = [
            {"id": "start", "command": "set_background", "asset_id": spec["background"]},
        ]
        if spec.get("cg"):
            commands.append({"command": "set_cg", "asset_id": spec["cg"]})
        commands.extend(spec.get("extra_portraits", []))
        commands.extend([
            {"command": "show_portrait", "slot": "RIGHT", "asset_id": spec["portrait"], "expression": first_expression},
            {"command": "fade_in", "duration": .35},
        ])
        active_expression = first_expression
        for command_type, speaker_key, text_key, expression in spec["lines"]:
            if expression != active_expression:
                commands.append({"command": "set_expression", "slot": "RIGHT", "expression": expression})
                active_expression = expression
            commands.append({"command": command_type, "speaker_key": speaker_key, "text_key": text_key})
        sid = spec["id"]
        if sid == "SCN_PROLOGUE":
            commands.extend([{"command": "choice", "choices": [{"text_key": "CHOICE_LIGHT", "set_flag": "CHOSE_LIGHT"}, {"text_key": "CHOICE_RECORD", "set_flag": "CHOSE_RECORD"}]}, {"command": "set_flag", "flag": "PROLOGUE_READ", "value": True}])
        # The chapter-map encounter is authoritative.  The pre-boss scenario
        # returns to the N10 map pawn; only physical map contact may open the
        # existing real-time battle transaction.
        commands.extend([{"command": "grant_reward", "item_id": "LANTERN_SHARD", "quantity": 5}, {"command": "end_scenario"}])
        result.append({"id": sid, "title_key": spec["title"], "chapter_id": spec["chapter"], "commands": commands})
    return result


LOCALIZED = {
    "GAME_TITLE": ("LUMENBOUND: TACTICS OF THE LAST LINE", "LUMENBOUND: TACTICS OF THE LAST LINE"),
    "GAME_SUBTITLE": ("빛이 끊긴 세계에서 이야기를 잇는 사람들", "People reconnecting stories in a lightless world"),
    "UI_STORY_TITLE": ("이야기", "Story"),
    "SPEAKER_ROUTEKEEPER": ("길잡이", "Routekeeper"), "SPEAKER_MAERU": ("마에루", "Maeru"),
    "SPEAKER_ROAN": ("로안", "Roan"), "SPEAKER_NARIN": ("나린", "Narin"), "SPEAKER_IRI": ("이리", "Iri"),
    "SPEAKER_SOREN": ("소렌", "Soren"),
    "CHOICE_LIGHT": ("먼저 불빛을 확인한다", "Check the light first"), "CHOICE_RECORD": ("기록 장치를 확보한다", "Secure the recorder"),
    "MAP_EVENT_DEFAULT_TITLE": ("탐색 기록", "Exploration Record"),
    "MAP_EVENT_DEFAULT_BODY": ("주변의 작은 변화가 탐색을 유도합니다.", "A subtle change in the surroundings invites a closer look."),
    "MAP_EVENT_DEFAULT_CHOICE_PRIMARY": ("조사한다", "Investigate"),
    "MAP_EVENT_DEFAULT_CHOICE_SECONDARY": ("지나간다", "Move on"),
    "MAP_EVENT_MOVE_TO": ("탐색 지점으로 이동", "Move to the site"),
    "MAP_EVENT_CRYSTAL_TRACE_TITLE": ("잔광 수정의 흔적", "Trace of Afterglow Crystal"),
    "MAP_EVENT_CRYSTAL_TRACE_BODY": ("수정 군락의 미세한 진동이 북쪽 샛길을 가리킨다.", "A faint vibration in the crystal cluster points toward a northern side path."),
    "MAP_EVENT_CRYSTAL_TRACE_INVESTIGATE": ("조사한다", "Investigate"),
    "MAP_EVENT_CRYSTAL_TRACE_PASS": ("지나간다", "Move on"),
    "MAP_EVENT_BROKEN_SWITCH_TITLE": ("끊긴 분기 스위치", "Severed Junction Switch"),
    "MAP_EVENT_BROKEN_SWITCH_BODY": ("손상된 분기 장치가 짧은 우회로와 연결되어 있다.", "The damaged junction device is connected to a short detour."),
    "MAP_EVENT_BROKEN_SWITCH_RESTORE": ("신호를 복구한다", "Restore the signal"),
    "MAP_EVENT_BROKEN_SWITCH_SALVAGE": ("부품을 회수한다", "Salvage the parts"),
    "MAP_EVENT_COAST_LOG_TITLE": ("해안 관측 기록", "Coastal Observation Log"),
    "MAP_EVENT_COAST_LOG_BODY": ("파도 아래의 빛이 다음 복구 지점을 잠시 비춘다.", "Light beneath the waves briefly reveals the next restoration site."),
    "MAP_EVENT_COAST_LOG_SYNC": ("기록을 동기화한다", "Synchronize the log"),
    "MAP_EVENT_COAST_LOG_LEAVE": ("지나간다", "Move on"),
    "MAP_EVENT_RESCUE_VERA_TITLE": ("구조 신호 · 베라", "Rescue Signal: Vera"),
    "MAP_EVENT_RESCUE_VERA_BODY": ("흐트러진 신호를 붙드는 탐사대원이 길목을 지키고 있다. 가까이 다가가면 기존 조우가 시작된다.", "An expedition scout is holding a fractured signal at the route choke point. Reach her to begin the existing encounter."),
    "MAP_EVENT_RESCUE_VERA_OUTCOME": ("승리 시 즉시 편성에 합류", "Victory outcome: joins formation immediately"),
    "MAP_EVENT_RELAY_TOA_TITLE": ("단절된 중계선 · 토아", "Severed Relay Line: Toa"),
    "MAP_EVENT_RELAY_TOA_BODY": ("중계선을 혼자 복구하던 탐사대원이 응답한다. 조우를 마치면 다음 신호를 함께 추적한다.", "An expedition specialist answers from a broken relay. Finish the encounter to follow the next signal together."),
	"MAP_EVENT_RELAY_TOA_OUTCOME": ("승리 후 신호 동행 · NORMAL 9 완료 뒤 편성 합류", "Victory outcome: signal follow-up; joins formation after NORMAL 9"),
	"MAP_EVENT_CONTACT_SIGNAL": ("특별 신호 조우", "Special Signal Contact"),
	"MAP_BOSS_CONTACT_CAPTION": ("위협 신호 · 특이 개체 감지", "Threat Signal · Anomalous Entity Detected"),
	"MAP_BOSS_N10_EVENT_TITLE": ("심층 신호 차단", "Deep Signal Interdiction"),
	"MAP_BOSS_N10_SUBTITLE": ("중계 구역 최심부 · 접근 통제 개체", "Relay Depths · Access-Control Entity"),
	"MAP_BOSS_UNKNOWN_NAME": ("미확인 위협", "Unidentified Threat"),
	"MAP_BOSS_UNKNOWN_SUBTITLE": ("신호 판독 중", "Signal Scan In Progress"),
	"RESULT_EVENT_RECRUITED": ("동료 합류 · %s가 편성에 참여합니다.", "Companion Joined · %s is now available for formation."),
	"RESULT_EVENT_TRACKING": ("신호 동행 · %s의 합류 신호를 %s 이후에 다시 추적합니다.", "Signal Follow-up · %s will join after the signal at %s is restored."),
	"MAP_TREASURE_CH01_VT01_NAME": ("부서진 릴레이 보급 상자", "Broken Relay Supply Case"),
	"MAP_TREASURE_CH01_VT02_NAME": ("해안 보급 상자", "Coastline Supply Case"),
	"MAP_TREASURE_CH01_VT03_NAME": ("폐허 신호 보관함", "Ruined Signal Crate"),
	"MAP_TREASURE_CH01_VT04_NAME": ("수정 조사 보물상자", "Crystal Survey Chest"),
	"MAP_TREASURE_CH01_VT05_NAME": ("선로 무장 보관함", "Railside Armament Case"),
	"MAP_TREASURE_CH01_VT06_NAME": ("등대 신호 금고", "Beacon Signal Vault"),
	"MAP_TREASURE_CH01_HT01_NAME": ("비정상 수정 군락", "Anomalous Crystal Cluster"),
	"MAP_TREASURE_CH01_HT02_NAME": ("붕괴한 아치 통로", "Collapsed Archway"),
	"MAP_TREASURE_CH01_HT03_NAME": ("끊긴 인프라 끝", "Broken Infrastructure End"),
	"MAP_TREASURE_CH01_HT04_NAME": ("열린 해안 공터", "Open Coastal Clearing"),
	"MAP_TREASURE_DETAIL_TITLE": ("탐색 보급품", "Exploration Cache"),
	"MAP_TREASURE_DETAIL_BODY": ("%s\n경로 길이: %d\n위험도: %s", "%s\nRoute length: %d\nRisk: %s"),
	"MAP_TREASURE_MOVE": ("보물로 이동", "Move to treasure"),
}


def localization(characters, enemies, stages, skills, weapons, items, scenarios) -> dict[str, tuple[str, str]]:
    loc = dict(LOCALIZED)
    ko_names = {"MAERU": "마에루", "ROAN": "로안", "NARIN": "나린", "EDA": "에다", "SOREN": "소렌", "VERA": "베라", "TOA": "토아", "IRI": "이리"}
    ko_names.update({
        "LIV": "리브", "SEON": "세온", "ADELINE": "아델린", "KIR": "키르", "REMA": "레마", "VEON": "베온", "HART": "하르트", "ORSA": "오르사", "TIEL": "티엘", "RIAS": "리아스", "PERIN": "페린", "KARN": "카른", "NOAR": "노아르", "SEB": "세브", "YURIEN": "유리엔", "MOEN": "모엔", "LAVENT": "라벤트", "KAIREN": "카이렌",
        "INOA": "이노아", "DRAN": "드란", "MERIN": "메린", "CIEL": "시엘", "ROME": "로메", "KIAN": "키안", "DAEL": "다엘", "ORBIN": "오르빈", "HERAON": "헤라온", "MIRE": "미레", "RAEN": "라엔", "ZERN": "제른", "SOA": "소아", "BAEL": "바엘", "TERAN": "테란", "YUNAK": "유나크", "ARINT": "아린트", "VELK": "벨크",
    })
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
    role_skill_names = {
        "GUARDIAN": ("방벽 전개", "수호 신호", "성채 공명"),
        "VANGUARD": ("선두 돌파", "개척 호흡", "돌입 섬광"),
        "ASSAULT": ("연속 사격", "전술 보정", "집중 난사"),
        "ARTILLERY": ("좌표 포격", "포구 안정", "성운 포화"),
        "SPECIALIST": ("교란 표식", "신호 해석", "역전 파장"),
        "MEDIC": ("회복 전송", "구호 기록", "새벽 구조"),
    }
    enemy_names = {
        "ENM001": "화염 송곳짐승", "ENM002": "전류 부유체", "ENM003": "장갑 중계기",
        "ENM004": "수복 잔향", "ENM005": "합창 파편", "ENM006": "먼지 렌즈",
        "ENM007": "감시자 골격", "ENM008": "왜곡 방송국", "ENM009": "철의 선창자",
        "BOSS001": "공허 기관", "BOSS002": "심야의 종", "ENM010": "단선 추적자", "ENM011": "유리 송신체", "ENM012": "잔광 차폐기", "BOSS003": "백야 관측체",
        "ENM013": "역송 전극체", "ENM014": "낙선 포대", "ENM015": "빈자리 합창체", "BOSS004": "역행의 개찰자", "BOSS005": "회송 편성핵",
    }
    item_names = {
        "BLUEPRINT_T1": "설계도 T1", "BLUEPRINT_T2": "설계도 T2", "BLUEPRINT_T3": "설계도 T3", "BLUEPRINT_T4": "설계도 T4",
        "BREAK_CORE_T1": "돌파 코어 T1", "BREAK_CORE_T2": "돌파 코어 T2", "BREAK_CORE_T3": "돌파 코어 T3", "BREAK_CORE_T4": "돌파 코어 T4",
        "CREDIT": "크레딧", "FACTION_SEAL_T1": "조직 인장 T1", "FACTION_SEAL_T2": "조직 인장 T2", "FACTION_SEAL_T3": "조직 인장 T3",
        "LANTERN_SHARD": "등불 파편", "EXPEDITION_ROUTE_MODULE_A": "노선 확장 모듈 α", "EXPEDITION_ROUTE_MODULE_B": "노선 확장 모듈 β", "ROLE_TOKEN_T1": "역할 토큰 T1", "ROLE_TOKEN_T2": "역할 토큰 T2", "ROLE_TOKEN_T3": "역할 토큰 T3", "ROLE_TOKEN_T4": "역할 토큰 T4",
        "SKILL_BOOK_T1": "기술 교본 T1", "SKILL_BOOK_T2": "기술 교본 T2", "SKILL_BOOK_T3": "기술 교본 T3", "SKILL_BOOK_T4": "기술 교본 T4",
        "SKILL_TOKEN_T1": "기술 토큰 T1", "SKILL_TOKEN_T2": "기술 토큰 T2", "SKILL_TOKEN_T3": "기술 토큰 T3", "SKILL_TOKEN_T4": "기술 토큰 T4",
        "TRAINING_NOTE_S": "훈련 노트 S", "TRAINING_NOTE_M": "훈련 노트 M", "TRAINING_NOTE_L": "훈련 노트 L", "TRAINING_NOTE_XL": "훈련 노트 XL",
        "ULT_BOOK_T1": "궁극 교본 T1", "ULT_BOOK_T2": "궁극 교본 T2", "ULT_BOOK_T3": "궁극 교본 T3", "ULT_BOOK_T4": "궁극 교본 T4",
        "UNIVERSAL_CATALYST": "범용 촉매", "WEAPON_CHIP_S": "무기 칩 S", "WEAPON_CHIP_M": "무기 칩 M", "WEAPON_CHIP_L": "무기 칩 L", "WEAPON_CHIP_XL": "무기 칩 XL",
        "WEAPON_ORE_T1": "무기 광석 T1", "WEAPON_ORE_T2": "무기 광석 T2", "WEAPON_ORE_T3": "무기 광석 T3", "WEAPON_ORE_T4": "무기 광석 T4",
    }
    loc.update({"CHAPTER_01": ("제1장 — 꺼진 노선의 신호", "Chapter 1 — Signal on the Dark Line"), "CHAPTER_02": ("제2장 — 되감기는 종착선", "Chapter 2 — The Returning Terminus")})
    for c in characters:
        code = c["name_key"].split("_")[1]
        loc[c["name_key"]] = (ko_names.get(code, code.title()), code.title())
        loc[c["description_key"]] = ("등로단의 %s 역할을 맡은 탐사대원." % c["role"], "A Lamplighter serving as %s of the expedition." % c["role"])
    for s in skills:
        suffix = s["type"].replace("_SKILL", "")
        owner = next(c for c in characters if c["id"] == s["owner_id"])
        code = owner["name_key"].split("_")[1]
        fallback_names = dict(zip(("NORMAL", "PASSIVE", "ULTIMATE"), role_skill_names[str(owner["role"])]))
        loc[s["name_key"]] = (skill_names.get(code, fallback_names)[suffix], f"{code.title()} {suffix.title()} Skill")
    for e in enemies:
        loc[e["name_key"]] = (enemy_names.get(e["id"], e["id"]), f"Echoform {e['id']}")
    for s in stages:
        chapter_number = int(str(s["chapter_id"]).replace("CH", ""))
        loc[s["name_key"]] = (f"제{chapter_number}장 {s['mode']} {s['stage_number']}", f"Chapter {chapter_number} {s['mode']} {s['stage_number']}")
    characters_by_id = {str(character["id"]): character for character in characters}
    for chapter_id in CONTACT_EVENT_SPECS:
        for event in chapter_contact_events(chapter_id):
            recruitments = event["recruitments"]
            korean_names = [ko_names[str(characters_by_id[row["character_id"]]["name_key"]).split("_")[1]] for row in recruitments]
            english_names = [str(characters_by_id[row["character_id"]]["name_key"]).split("_")[1].title() for row in recruitments]
            joined_ko = " · ".join(korean_names)
            joined_en = " / ".join(english_names)
            title_key = str(event["title_key"])
            body_key = str(event["body_key"])
            outcome_key = str(event["contact_outcome_key"])
            loc[title_key] = (f"특별 신호 · {joined_ko}", f"Special Signal: {joined_en}")
            loc[body_key] = ("왜곡된 회송 신호 속에서 동료의 구조 좌표가 겹쳐진다. 접촉을 마치면 이 조우의 진짜 응답을 확인할 수 있다.", "Rescue coordinates overlap inside a distorted return signal. Complete the contact to verify who answers it.")
            immediate_ko = [korean_names[i] for i, row in enumerate(recruitments) if row["recruitment_timing"] == "IMMEDIATE_ON_VICTORY"]
            delayed_ko = [korean_names[i] for i, row in enumerate(recruitments) if row["recruitment_timing"] == "AFTER_STAGE_CLEAR"]
            immediate_en = [english_names[i] for i, row in enumerate(recruitments) if row["recruitment_timing"] == "IMMEDIATE_ON_VICTORY"]
            delayed_en = [english_names[i] for i, row in enumerate(recruitments) if row["recruitment_timing"] == "AFTER_STAGE_CLEAR"]
            outcome_ko = ("승리 시 즉시 합류 · " + " · ".join(immediate_ko)) if immediate_ko else "승리 후 신호 동행"
            outcome_en = ("Victory outcome: joins immediately · " + " / ".join(immediate_en)) if immediate_en else "Victory outcome: signal follow-up"
            if delayed_ko:
                outcome_ko += " / 후속 합류 · " + " · ".join(delayed_ko)
                outcome_en += " / follow-up join · " + " / ".join(delayed_en)
            loc[outcome_key] = (outcome_ko, outcome_en)
    for w in weapons:
        loc[w["name_key"]] = (f"공용 {w['weapon_class']} 장비 {w['id']}", f"Common {w['weapon_class']} Gear {w['id']}")
    for item in items:
        if item["id"].startswith("SHARD_"):
            character_code = item["id"].replace("SHARD_", "")
            character = next(c for c in characters if c["id"] == character_code)
            loc[item["name_key"]] = (ko_names[character["name_key"].split("_")[1]] + " 조각", item["id"])
        else:
            loc[item["name_key"]] = (item_names[item["id"]], item["id"])
    scenario_titles = {
        "SCN_PROLOGUE": ("프롤로그 — 끊긴 등불", "Prologue — The Broken Light"),
        "SCN_CH01_INTRO": ("제1장 — 꺼진 노선의 신호", "Chapter 1 — Signal on the Dark Line"),
        "SCN_CH01_MID_A": ("잔향이 남은 터널", "The Echoing Tunnel"),
        "SCN_CH01_MID_B": ("지워진 행선지", "The Erased Destination"),
        "SCN_CH01_MID_C": ("종탑형 중계기", "The Bell-Tower Relay"),
        "SCN_CH01_PREBOSS": ("공허기관 앞에서", "Before the Hollow Engine"),
        "SCN_CH01_OUTRO": ("다음 등불", "The Next Light"),
        "SCN_CH02_INTRO": ("제2장 — 되감기는 종착선", "Chapter 2 — The Returning Terminus"),
        "SCN_CH02_MID_A": ("빈자리의 호명", "Calling the Vacant Seats"),
        "SCN_CH02_MID_B": ("역송 구간", "The Reverse-Current Section"),
        "SCN_CH02_PREBOSS": ("중앙 역행 개찰", "The Central Reverse Gate"),
        "SCN_CH02_HARD_INTRO": ("지하 회송실", "The Return Chamber"),
        "SCN_CH02_OUTRO": ("한 개의 정상 신호", "One True Beacon"),
        "SCN_REL_MAERU": ("빈 좌석의 안전띠", "The Empty Seatbelt"),
        "SCN_REL_IRI": ("고장 난 안내 방송", "The Broken Announcement"),
    }
    for scn in scenarios:
        loc[scn["title_key"]] = scenario_titles[scn["id"]]
    story_ko = {
        "STORY_PRO_01": "대정전 뒤, 지하의 광맥 철로는 마지막 도시들을 잇는 유일한 길이 되었다.", "STORY_PRO_02": "새로 깨어난 기록 항해자는 끊긴 등불과 사람들의 기억을 복구해야 한다.", "STORY_PRO_03": "제7 승강장에서 첫 신호가 깜박이고 있어. 거기서 시작하자.", "STORY_PRO_04": "정찰로는 내가 연다. 신호가 살아나면 바로 따라와.",
        "STORY_C1I_01": "등로단은 잔광 폭풍 속에서도 움직이는 소규모 복구 조직이다.", "STORY_C1I_02": "지도에 없는 선로에서 구조 요청을 들었어. 아직 신호가 살아 있어.", "STORY_C1I_03": "진위를 확인하고 길을 복구하자. 모두 출발 준비.",
        "STORY_C1A_01": "첫 터널에는 기억을 흉내 내는 잔향체가 모여 있었다.", "STORY_C1A_02": "그것들은 사람의 목소리를 냈지만 질문에는 답하지 못했다.", "STORY_C1A_03": "전투 뒤 손상되지 않은 기록편 하나를 회수했어. 다음 구간을 열 수 있겠어.",
        "STORY_C1B_01": "기록편에는 오래전 정거장의 대피 순서가 남아 있었다.", "STORY_C1B_02": "누군가 마지막 열차의 행선지를 고의로 지운 흔적이 보였다.", "STORY_C1B_03": "지워진 층 아래에서 새 좌표를 찾았어. 폐쇄 구간 안쪽이야.",
        "STORY_C1C_01": "좌표는 폐쇄된 종탑형 중계기로 이어졌다.", "STORY_C1C_02": "신호 안에서 생체 맥박과 비슷한 주기가 느껴져. 구조 대상일 수도 있어.", "STORY_C1C_03": "하지만 잔향체 군집이 먼저 중계기를 포위했어. 서둘러야 해.",
        "STORY_PRE_01": "거대한 공허기관이 선로의 빛을 삼키며 깨어났다.", "STORY_PRE_02": "각자 등불과 장비를 확인해. 여기서부터는 한 번의 실수도 허용되지 않아.", "STORY_PRE_03": "우리가 지키려는 것은 선로가 아니라, 그 끝에서 기다리는 사람들의 이야기야.",
        "STORY_OUT_01": "공허기관이 멈추자 지워졌던 행선지가 다시 나타났다.", "STORY_OUT_02": "마지막 열차는 사라진 도시가 아니라 이동 중인 피난처를 향하고 있었다.", "STORY_OUT_03": "첫 노선은 다시 이어졌어. 이제 다음 등불로 가자.",
        "STORY_REL_M_01": "출발 전에는 빈 좌석의 안전띠까지 확인해. 빠뜨리면 마음이 놓이지 않거든.", "STORY_REL_M_02": "돌아오지 못한 동료의 자리를 잊지 않기 위해 시작한 습관이야.", "STORY_REL_M_03": "오늘은 그 자리에 새 구조 장비를 놓았어. 빈자리가 다음 사람을 살리게 됐네.",
        "STORY_REL_I_01": "고장 난 안내 방송을 모아서 작은 합창곡을 만들었어.", "STORY_REL_I_02": "완벽한 음정보다 누군가 살아 있었다는 흔적이 더 중요하다고 생각해.", "STORY_REL_I_03": "다음 정거장에 도착하면 같이 틀어 보자. 혼자 듣는 것보다 좋을 거야.",
        "STORY_C2I_01": "세 개의 고유 보스 기록에는 같은 짧은 handshake 패턴이 남아 있었다.", "STORY_C2I_02": "신호는 진행 방향이 아니라 종착점에서 출발점 쪽으로 하나씩 켜지고 있어.", "STORY_C2I_03": "시간을 되돌리는 장치가 아니야. 망가진 회송 절차가 현재의 우리를 과거 기록에 끼워 맞추고 있어.",
        "STORY_C2A_01": "닫힌 승강장은 존재하지 않는 승객의 이름을 반복해서 불렀다.", "STORY_C2A_02": "구조 신호가 진짜인지 가짜인지가 아니라, 지금 누가 그 신호를 듣고 있는지가 중요해.", "STORY_C2A_03": "우리 이름을 과거 목록에서 지우고, 현재 좌표를 남기자.",
        "STORY_C2B_01": "전력은 거꾸로 흘렀고, 이미 지나온 플랫폼은 다시 미완료 표지를 켰다.", "STORY_C2B_02": "노선이 악의를 가진 건 아니야. 오래전에 멈췄어야 할 자동 절차가 계속 실행될 뿐이야.", "STORY_C2B_03": "중앙 개찰을 멈추면, 적어도 이 구간의 잘못된 호명은 끝낼 수 있어.",
        "STORY_C2P_01": "중앙 분기장의 개찰 패널은 탐사대를 오래전의 적 편성으로 분류했다.", "STORY_C2P_02": "패널을 부수는 게 목표가 아니야. 회송 명령을 종료시킬 틈을 만들어야 해.", "STORY_C2P_03": "문이 열리면 바로 지나간다. 돌아가는 기록에 남을 사람이 한 명도 없게.",
        "STORY_C2H_01": "지하 회송실에는 빈 자리만 남은 편성표가 벽처럼 이어져 있었다.", "STORY_C2H_02": "이 핵은 사람을 찾는 게 아니라, 비어 있는 칸을 채우려는 거야.", "STORY_C2H_03": "우리가 멈추게 할 건 과거가 아니라, 현재를 지워 버리는 이 명령이야.",
        "STORY_C2O_01": "회송 편성핵이 멈추자, 뒤집혀 있던 신호등이 하나씩 정상 방향으로 돌아왔다.", "STORY_C2O_02": "모든 기록이 사라진 것은 아니지만, 더는 현재의 사람을 과거의 빈자리에 넣지 않았다.", "STORY_C2O_03": "남은 건 바깥을 향한 하나의 정상 신호야. 다음 길은 우리가 선택해서 이어 가자.",
    }
    story_en = {
        "STORY_PRO_01": "After the Great Blackout, the mineral railway beneath the earth became the last route connecting the surviving cities.", "STORY_PRO_02": "A newly awakened record navigator must restore broken lights and the memories carried between them.", "STORY_PRO_03": "The first signal is blinking at Platform Seven. We start there.", "STORY_PRO_04": "I will clear the reconnaissance route. Follow as soon as the signal comes alive.",
        "STORY_C1I_01": "The Lamplighters are a small restoration crew that keeps moving even through afterglow storms.", "STORY_C1I_02": "I heard a rescue call from a line that is not on the map. The signal is still alive.", "STORY_C1I_03": "We verify it and restore the route. Everyone, prepare to depart.",
        "STORY_C1A_01": "The first tunnel was crowded with echoforms that imitated human memories.", "STORY_C1A_02": "They spoke in human voices, but none could answer a question.", "STORY_C1A_03": "I recovered an intact record fragment after the battle. It should open the next section.",
        "STORY_C1B_01": "The fragment preserved an evacuation order from the old station.", "STORY_C1B_02": "Someone had deliberately erased the destination of the final train.", "STORY_C1B_03": "I found new coordinates beneath the erased layer. They lead inside the sealed sector.",
        "STORY_C1C_01": "The coordinates led to a sealed bell-tower relay.", "STORY_C1C_02": "There is a rhythm like a living pulse inside the signal. It may be a survivor.", "STORY_C1C_03": "But an echoform cluster has already surrounded the relay. We need to hurry.",
        "STORY_PRE_01": "The massive Hollow Engine awoke, swallowing the light along the rails.", "STORY_PRE_02": "Check your lights and equipment. From here on, one mistake is too many.", "STORY_PRE_03": "We are not protecting the rails. We are protecting the stories of the people waiting at their end.",
        "STORY_OUT_01": "When the Hollow Engine stopped, the erased destination returned.", "STORY_OUT_02": "The final train had not been bound for a lost city, but for a refuge still in motion.", "STORY_OUT_03": "The first line is connected again. Let us head for the next light.",
        "STORY_REL_M_01": "Before departure, I even check the seatbelt on the empty seat. I cannot relax if I skip it.", "STORY_REL_M_02": "I began doing it so I would not forget the teammate who never returned.", "STORY_REL_M_03": "Today I placed new rescue gear there. An empty place can help save the next person now.",
        "STORY_REL_I_01": "I gathered broken station announcements and turned them into a little chorus.", "STORY_REL_I_02": "A trace that someone lived matters more to me than perfect pitch.", "STORY_REL_I_03": "Let us play it together at the next station. It will sound better than listening alone.",
        "STORY_C2I_01": "The three unique boss records retained the same short handshake pattern.", "STORY_C2I_02": "Signals are lighting one by one from the terminus back toward the origin, not in the direction of travel.", "STORY_C2I_03": "It is not time travel. A damaged return procedure is fitting us into a past record.",
        "STORY_C2A_01": "The sealed platform kept calling the names of passengers who no longer existed.", "STORY_C2A_02": "What matters is not whether a rescue signal is real, but who is hearing it now.", "STORY_C2A_03": "Erase our names from the old list and leave our current coordinates behind.",
        "STORY_C2B_01": "Power flowed backward, and platforms we had already crossed lit their incomplete signs again.", "STORY_C2B_02": "The line is not malicious. It is only an automated procedure running long after it should have stopped.", "STORY_C2B_03": "If we stop the central gate, at least this section's false calls can end.",
        "STORY_C2P_01": "The central junction panels classified the expedition as an enemy formation from long ago.", "STORY_C2P_02": "We do not need to smash the panels. We need a gap to terminate the return directive.", "STORY_C2P_03": "When the gate opens, we cross at once. No one is staying behind in a returning record.",
        "STORY_C2H_01": "The underground return chamber was lined like a wall with formation charts containing only vacant seats.", "STORY_C2H_02": "This core is not looking for people. It is trying to fill empty slots.", "STORY_C2H_03": "We will stop not the past, but the command that erases the present.",
        "STORY_C2O_01": "When the return formation core stopped, the inverted signal lights turned back toward their proper direction.", "STORY_C2O_02": "Not every record vanished, but none could place a present person into a past empty seat again.", "STORY_C2O_03": "One true beacon remains, facing outward. We choose how to connect the next route.",
    }
    for key, ko in story_ko.items():
        loc[key] = (ko, story_en[key])
    loc.update({
        "BATTLE_BOSS_PHASE_1_HUD": ("1단계", "Phase 1"),
        "BATTLE_BOSS_PHASE_2_HUD": ("2단계", "Phase 2"),
        "BATTLE_BOSS_ENRAGE_HUD": ("폭주", "Enraged"),
        "BATTLE_BOSS_PHASE_2_TITLE": ("제2단계 돌입", "Phase Two"),
        "BATTLE_BOSS_PHASE_2_SUBTITLE": ("공허기관의 핵이 재배열됩니다.", "The Hollow Engine core is rearranging."),
        "BATTLE_BOSS_ENRAGE_TITLE": ("보스 폭주", "Boss Enraged"),
        "BATTLE_BOSS_ENRAGE_SUBTITLE": ("위험 출력이 한계를 넘어섰습니다.", "Danger output has exceeded its limit."),
        "MAP_BOSS_CH02_N10_TITLE": ("중앙 역행 개찰", "Central Reverse Gate"),
        "MAP_BOSS_CH02_N10_SUBTITLE": ("회송선 중앙 분기장 · 역방향 절차 관리자", "Return Line Junction · Reverse Procedure Gatekeeper"),
        "MAP_BOSS_CH02_H05_TITLE": ("회송 편성핵 정지", "Return Formation Core Shutdown"),
        "MAP_BOSS_CH02_H05_SUBTITLE": ("지하 회송실 최심부 · 빈자리 편성 명령", "Return Chamber Depths · Vacant-Seat Formation Directive"),
    })
    return loc


def main() -> None:
    characters = character_data()
    skills = skill_data()
    enemies = enemy_data()
    stages, rewards = stage_data()

    # Chapter definitions are consumed at runtime for map selection, route
    # progression, and additive save repair. Keep the exact ordered stage IDs
    # here instead of deriving them from a CH01-only string convention.
    chapters = [
        {
            "id": chapter_id, "number": number, "name_key": name_key, "map_id": map_id,
            "normal_stage_ids": [s["id"] for s in stages if s["chapter_id"] == chapter_id and s["mode"] == "NORMAL"],
            "hard_stage_ids": [s["id"] for s in stages if s["chapter_id"] == chapter_id and s["mode"] == "HARD"],
        }
        for chapter_id, number, name_key, map_id in [("CH01", 1, "CHAPTER_01", "CH01_MAP"), ("CH02", 2, "CHAPTER_02", "CH02_MAP")]
    ]
    items = item_data()
    weapons = weapon_data()
    breakthrough, normal_costs, ultimate_costs = costs()
    scenarios = scenario_sources()
    char_levels, acct_levels, weapon_levels = level_rows(), account_rows(), weapon_level_rows()
    affinity_matrix = json.loads((SOURCE / "affinity_matrix.json").read_text(encoding="utf-8"))
    status_effects = json.loads((SOURCE / "status_effects.json").read_text(encoding="utf-8"))
    story_triggers = json.loads((SOURCE / "chapter_story_triggers.json").read_text(encoding="utf-8"))

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
    write_json(SOURCE / "chapters.json", chapters)
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
        map_definition = json.loads(map_path.read_text(encoding="utf-8"))
        chapter_id = str(map_definition.get("chapter_id", ""))
        # The trigger table is the runtime authority; mirror its scenario IDs onto
        # authored map nodes as an audit index.  This makes the intended moment of
        # every chapter scenario visible in the map data without creating a second
        # queue or changing the exactly-once trigger transaction.
        map_enter_scenario_id = ""
        stage_scenario_ids: dict[str, str] = {}
        for trigger in story_triggers:
            if str(trigger.get("id", "")).startswith("TRIG_%s_" % chapter_id):
                if str(trigger.get("event", "")) == "MAP_ENTER":
                    map_enter_scenario_id = str(trigger.get("scenario_id", ""))
                elif str(trigger.get("event", "")) == "STAGE_CLEAR":
                    stage_scenario_ids[str(trigger.get("stage_id", ""))] = str(trigger.get("scenario_id", ""))
        for node in map_definition.get("nodes", []):
            if str(node.get("node_type", "")) == "START":
                node["scenario_id"] = map_enter_scenario_id
            else:
                node["scenario_id"] = stage_scenario_ids.get(str(node.get("stage_id", "")), "")
        if chapter_id in CONTACT_EVENT_SPECS:
            map_definition["event_encounters"] = chapter_contact_events(chapter_id)
            # The generated contact catalog is part of the data source of
            # truth, not a compiled-only patch. Persisting it lets map review
            # and Web builds read the exact same 1–2 companion contract.
            write_json(map_path, map_definition)
        write_json(COMPILED / "chapter_maps" / map_path.name, map_definition)

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
        "chapters": chapters,
        "scenarios": scenarios,
        "chapter_story_triggers": story_triggers,
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
