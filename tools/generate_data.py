#!/usr/bin/env python3
"""Deterministically builds source balance tables and Godot runtime JSON.

Build-time only. The shipped game has no Python dependency.
"""
from __future__ import annotations

import csv
import json
import math
from pathlib import Path

from campaign20 import (
    CHAPTER_BLUEPRINTS,
    CHAPTER_STORY_ARCS,
    REGULAR_ENEMY_CODES,
    STORY_RECRUIT_IDS,
    boss_id_pairs,
    chapter_rows,
    regular_enemy_ids_for_chapter,
    story_recruit_set,
)

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
    # Iri joins immediately before the Chapter 2 normal-route boss.  Her
    # higher baseline keeps the late medic competitive with a roster that has
    # already been trained through two chapters without making her a tank or
    # primary damage dealer.
    ("CHR008", "IRI", "MEDIC", "BACK", "ENERGY", "BARRIER", "SUPPORT_DEVICE", 960, 105, 62, 125, 520, 92, 180, 8000, 760, 390, 1320),
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
            "initial_rarity": 3 if cid == "CHR008" else 2 + (index % 2),
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
            # Only twenty of the thirty-nine non-starters are story recruits in
            # the 20-chapter campaign.  RESERVED characters remain visible for
            # art/skill QA but cannot be silently granted without a future
            # acquisition system.
            "acquisition_source": "DEFAULT" if index <= 5 else ("EVENT_CONTACT" if cid in story_recruit_set() else "RESERVED"),
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

# Chapters 3-20 add exactly three region-specific combatants each: two normal
# bodies and one elite.  The rest of each formation reuses established foes,
# keeping the requested roughly one-third-new/two-thirds-reused ratio.
for chapter_number in range(3, 21):
    region_codes = REGULAR_ENEMY_CODES[(chapter_number - 3) // 2]
    region_ids = regular_enemy_ids_for_chapter(chapter_number)
    for offset, (enemy_id, code) in enumerate(zip(region_ids, region_codes)):
        if enemy_id in {row[0] for row in ENEMIES}:
            continue
        rank = "ELITE" if offset == 2 else "NORMAL"
        role = ("MELEE_RUSH", "RANGED", "DEFENDER")[offset]
        attack = ("PHYSICAL", "ENERGY", "ANOMALY")[(chapter_number + offset) % 3]
        defense = ("ARMOR", "BARRIER", "WARD")[(chapter_number + offset) % 3]
        scale = 1.0 + (chapter_number - 2) * 0.16
        ENEMIES.append((
            enemy_id, code, rank, role, attack, defense,
            round((660 if rank == "NORMAL" else 1850) * scale),
            round((92 if rank == "NORMAL" else 142) * scale),
            round((38 if rank == "NORMAL" else 94) * scale),
        ))

# Every chapter owns a unique Normal and Hard finale identity.  Existing boss
# IDs stay stable for save compatibility; later IDs are immutable additions.
_existing_enemy_ids = {row[0] for row in ENEMIES}
for chapter in chapter_rows():
    normal_boss_id, hard_boss_id = boss_id_pairs()[chapter["id"]]
    for hard_index, (boss_id, code) in enumerate(((normal_boss_id, chapter["normal_boss_code"]), (hard_boss_id, chapter["hard_boss_code"]))):
        if boss_id in _existing_enemy_ids:
            continue
        chapter_number = int(chapter["number"])
        scale = 1.0 + (chapter_number - 1) * 0.20 + hard_index * 0.12
        ENEMIES.append((
            boss_id, code, "BOSS", "BOSS_PATTERN",
            ("ENERGY", "ANOMALY", "PHYSICAL")[chapter_number % 3],
            ("ARMOR", "WARD", "BARRIER")[(chapter_number + hard_index) % 3],
            round(7600 * scale), round(182 * scale), round(132 * scale),
        ))
        _existing_enemy_ids.add(boss_id)


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
    # A chapter map is a full 30-contact expedition: twenty NORMAL nodes followed
    # by ten HARD nodes.  The original bosses remain unique, but their finales
    # now sit at the end of the longer route (N20/H10) instead of being repeated
    # as the map grows.  Extra contacts deliberately recombine established
    # normal/elite archetypes rather than inventing invisible placeholder art.
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
        [["ENM003", "ENM006"], ["ENM007", "ENM008"], ["ENM009"]],
        [["ENM010", "ENM005"], ["ENM011", "ENM006", "ENM002"]],
        [["ENM012", "ENM007"], ["ENM003", "ENM008"]],
        [["ENM004", "ENM010", "ENM001"], ["ENM009"]],
        [["ENM011", "ENM006"], ["ENM007", "ENM005"]],
        [["ENM003", "ENM012"], ["ENM008", "ENM002", "ENM010"]],
        [["ENM001", "ENM004"], ["ENM007", "ENM009"]],
        [["ENM005", "ENM011"], ["ENM008", "ENM012"]],
        [["ENM006", "ENM010", "ENM003"], ["ENM009", "ENM007"]],
        [["ENM002", "ENM011"], ["ENM008", "ENM004"], ["ENM009"]],
        [["ENM003", "ENM006"], ["ENM007", "ENM008"], ["BOSS001"]],
    ]
    hard = [
        [["ENM007", "ENM002"], ["ENM009"]],
        [["ENM008", "ENM006"], ["ENM007", "ENM008"]],
        [["ENM009"], ["ENM007", "ENM008"], ["BOSS003"]],
        [["ENM007", "ENM009"], ["ENM008", "ENM009"]],
        [["ENM007", "ENM008"], ["ENM009", "ENM009"], ["ENM012"]],
        [["ENM010", "ENM007"], ["ENM008", "ENM006", "ENM009"]],
        [["ENM011", "ENM009"], ["ENM007", "ENM012"]],
        [["ENM008", "ENM010"], ["ENM009", "ENM003"]],
        [["ENM007", "ENM011"], ["ENM008", "ENM012", "ENM009"]],
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
            }.get(sid, [])
            if not farmable:
                if mode == "NORMAL":
                    farmable = ["WEAPON_ORE_T2", "BLUEPRINT_T2"] if i <= 15 else ["SKILL_BOOK_T2", "SKILL_TOKEN_T2", "ULT_BOOK_T2"]
                else:
                    farmable = ["BREAK_CORE_T4", "ROLE_TOKEN_T4"] if i <= 8 else ["UNIVERSAL_CATALYST", "FACTION_SEAL_T3"]
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
        [["ENM013", "ENM015"], ["ENM014", "ENM008"], ["ENM009"]],
        [["ENM014", "ENM001"], ["ENM015", "ENM007", "ENM013"]],
        [["ENM013", "ENM008"], ["ENM014", "ENM009"]],
        [["ENM015", "ENM003"], ["ENM013", "ENM006", "ENM014"]],
        [["ENM014", "ENM007"], ["ENM015", "ENM008"]],
        [["ENM013", "ENM009"], ["ENM014", "ENM002", "ENM015"]],
        [["ENM015", "ENM006"], ["ENM013", "ENM007"]],
        [["ENM014", "ENM008"], ["ENM015", "ENM009"]],
        [["ENM013", "ENM014", "ENM007"], ["ENM015", "ENM008"]],
        [["ENM014", "ENM015"], ["ENM013", "ENM009", "ENM007"]],
        [["ENM015", "ENM008"], ["ENM014", "ENM013"], ["BOSS004"]],
    ]
    chapter_two_hard = [
        [["ENM013", "ENM007"], ["ENM015", "ENM009"]],
        [["ENM014", "ENM008"], ["ENM013", "ENM009"]],
        [["ENM015", "ENM007"], ["ENM014", "ENM008"]],
        [["ENM013", "ENM014"], ["ENM007", "ENM009"]],
        [["ENM015", "ENM008"], ["ENM013", "ENM014"], ["ENM009"]],
        [["ENM013", "ENM007"], ["ENM014", "ENM015", "ENM008"]],
        [["ENM014", "ENM009"], ["ENM013", "ENM006"]],
        [["ENM015", "ENM008"], ["ENM014", "ENM007"]],
        [["ENM013", "ENM014"], ["ENM015", "ENM009", "ENM008"]],
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
                "boss": any(str(enemy_id).startswith("BOSS") for wave in waves for enemy_id in wave),
                "daily_attempts": 0 if mode == "NORMAL" else 3,
            })
            tier = "T2" if i <= 5 else ("T3" if mode == "NORMAL" else "T4")
            guaranteed = [{"item_id": "CREDIT", "min": 1800 + i * 250, "max": 2200 + i * 350}, {"item_id": f"BREAK_CORE_{tier}", "min": 1, "max": 2}]
            if mode == "HARD":
                guaranteed.append({"item_id": f"SHARD_CHR{26 + i:03d}", "min": 1, "max": 1})
            rewards.append({"id": reward_id, "stage_id": sid, "guaranteed": guaranteed, "bonus": [{"item_id": "UNIVERSAL_CATALYST", "chance": .12, "quantity": 1, "pity_after_failures": 7}], "first_clear": [{"item_id": "CREDIT", "quantity": 6000 + i * 600}, {"item_id": "LANTERN_SHARD", "quantity": 15}]})
    return stages, rewards


def campaign_stage_data() -> tuple[list[dict], list[dict]]:
    """Build the audited 20 chapter x 25 battle campaign.

    Chapters 1-2 retain their existing Normal routes.  Their Hard routes are
    shortened to five operations and end in the already-authored unique boss.
    Chapters 3-20 use deterministic two-thirds legacy/one-third regional enemy
    formations and a unique boss for each Normal and Hard finale.
    """
    legacy_stages, legacy_rewards = stage_data()
    reward_by_stage = {str(row["stage_id"]): row for row in legacy_rewards}
    stages: list[dict] = []
    rewards: list[dict] = []
    boss_pairs = boss_id_pairs()

    for stage in legacy_stages:
        chapter_id = str(stage["chapter_id"])
        if chapter_id not in ("CH01", "CH02"):
            continue
        if str(stage["mode"]) == "HARD" and int(stage["stage_number"]) > 5:
            continue
        row = json.loads(json.dumps(stage))
        if str(row["mode"]) == "HARD":
            # Remove the former mid-route finale and put the chapter's unique
            # Hard boss at the new H05 endpoint.
            row["waves"] = [
                [enemy_id for enemy_id in wave if not str(enemy_id).startswith("BOSS")]
                for wave in row["waves"]
            ]
            row["waves"] = [wave for wave in row["waves"] if wave]
            if int(row["stage_number"]) == 5:
                row["waves"].append([boss_pairs[chapter_id][1]])
            row["boss"] = int(row["stage_number"]) == 5
        stages.append(row)
        rewards.append(json.loads(json.dumps(reward_by_stage[row["id"]])))

    for chapter in chapter_rows()[2:]:
        chapter_number = int(chapter["number"])
        chapter_id = str(chapter["id"])
        new_ids = list(regular_enemy_ids_for_chapter(chapter_number))
        previous_ids = list(regular_enemy_ids_for_chapter(chapter_number - 1))
        reusable = ["ENM001", "ENM002", "ENM003", "ENM004", "ENM005", "ENM006", "ENM007", "ENM008", "ENM009"] + previous_ids
        normal_boss_id, hard_boss_id = boss_pairs[chapter_id]
        for mode, count in (("NORMAL", 20), ("HARD", 5)):
            route_code = "N" if mode == "NORMAL" else "H"
            for number in range(1, count + 1):
                stage_id = f"{chapter_id}-{route_code}{number:02d}"
                regional = new_ids[(number + (1 if mode == "HARD" else 0)) % len(new_ids)]
                legacy_a = reusable[(chapter_number + number * 2) % len(reusable)]
                legacy_b = reusable[(chapter_number * 3 + number * 5) % len(reusable)]
                waves = [[legacy_a, regional], [legacy_b, new_ids[(number + 1) % 3]]]
                if number % 4 == 0:
                    waves.append(["ENM007" if number % 8 else "ENM009"])
                is_finale = number == count
                finale_id = normal_boss_id if mode == "NORMAL" else hard_boss_id
                is_boss = is_finale and str(finale_id).startswith("BOSS")
                if is_finale:
                    waves.append([finale_id])
                raw_level = 34 + (chapter_number - 2) * 12 + number * 2 + (8 if mode == "HARD" else 0)
                recommended_level = min(100, raw_level)
                post_cap_scale = 1.0 if raw_level <= 100 else round(1.0 + (raw_level - 100) * .012, 3)
                reward_id = f"REWARD_{stage_id}"
                stages.append({
                    "id": stage_id, "chapter_id": chapter_id, "mode": mode,
                    "stage_number": number, "name_key": f"STAGE_{stage_id.replace('-', '_')}",
                    "recommended_level": recommended_level, "post_cap_scale": post_cap_scale,
                    "stamina_cost": min(24, 10 + chapter_number // 2 + number // 4 + (4 if mode == "HARD" else 0)),
                    "time_limit": 100 + min(20, chapter_number), "target_time": 78 + min(16, chapter_number),
                    "waves": waves, "reward_table_id": reward_id, "boss": is_boss,
                    "daily_attempts": 0 if mode == "NORMAL" else 3,
                })
                tier = "T2" if chapter_number <= 4 else ("T3" if chapter_number <= 10 else "T4")
                guaranteed = [
                    {"item_id": "CREDIT", "min": 2800 + chapter_number * 420 + number * 180, "max": 3600 + chapter_number * 560 + number * 260},
                    {"item_id": f"BREAK_CORE_{tier}", "min": 1, "max": 2},
                ]
                if mode == "HARD":
                    shard_number = 6 + ((chapter_number * 3 + number) % 39)
                    guaranteed.append({"item_id": f"SHARD_CHR{shard_number:03d}", "min": 1, "max": 1})
                rewards.append({
                    "id": reward_id, "stage_id": stage_id, "guaranteed": guaranteed,
                    "bonus": [{"item_id": "UNIVERSAL_CATALYST", "chance": .12, "quantity": 1, "pity_after_failures": 7}],
                    "first_clear": [{"item_id": "CREDIT", "quantity": 7000 + chapter_number * 850 + number * 500}, {"item_id": "LANTERN_SHARD", "quantity": 15}],
                })
    stages.sort(key=lambda row: (int(str(row["chapter_id"])[2:]), 0 if row["mode"] == "NORMAL" else 1, int(row["stage_number"])))
    rewards.sort(key=lambda row: next(index for index, stage in enumerate(stages) if stage["id"] == row["stage_id"]))
    return stages, rewards


def relay_spec_data() -> list[dict]:
    """Small offline contracts which borrow authored battles without mutating chapter clear state."""
    return [
        {
            "id": "RELAY_CH01_A",
            "name": "삼중 노선 릴레이 · 제1구간",
            "subtitle": "서로 다른 15명을 세 개의 독립 편성으로 운용하십시오.",
            "stage_ids": ["CH01-N03", "CH01-N06", "CH01-N09"],
            "completion_rewards": {"CREDIT": 15000, "TRAINING_NOTE_L": 3, "SKILL_BOOK_T1": 6},
            "s_rank_time": 150.0,
            "a_rank_time": 195.0,
        }
    ]


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
    major = {"EXPEDITION_ROUTE_MODULE_A", "EXPEDITION_ROUTE_MODULE_B", "UNIVERSAL_CATALYST", "BLUEPRINT_T4", "WEAPON_ORE_T4", "BREAK_CORE_T4", "ROLE_TOKEN_T4", "SKILL_BOOK_T4", "SKILL_TOKEN_T4", "ULT_BOOK_T4"}
    rare = {"LANTERN_SHARD", "BLUEPRINT_T3", "WEAPON_ORE_T3", "BREAK_CORE_T3", "ROLE_TOKEN_T3", "FACTION_SEAL_T3", "SKILL_BOOK_T3", "SKILL_TOKEN_T3", "ULT_BOOK_T3"}
    return [{"id": item, "name_key": f"ITEM_{item}", "category": item.split("_")[0], "xp_value": xp.get(item, 0), "presentation_tier": ("MAJOR" if item in major else ("RARE" if item in rare else "STANDARD")), "icon_asset_id": ("item_lantern_shard_dev" if item.startswith("EXPEDITION_ROUTE_MODULE") else f"item_{item.lower()}_dev")} for item in ids]


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
        # N16-N18 are the authored three-operation approach.  Iri's contact at
        # N19 is therefore the last recruitment beat before the unique N20
        # Reverse Gatekeeper boss.
        ("N19", [("CHR008", "IMMEDIATE_ON_VICTORY", "")]),
        ("H01", [("CHR039", "IMMEDIATE_ON_VICTORY", "")]),
        ("H02", [("CHR040", "IMMEDIATE_ON_VICTORY", "")]),
        ("H03", [("CHR041", "IMMEDIATE_ON_VICTORY", "")]),
        ("H04", [("CHR042", "AFTER_STAGE_CLEAR", "CH02-H05"), ("CHR043", "IMMEDIATE_ON_VICTORY", "")]),
        ("H05", [("CHR044", "IMMEDIATE_ON_VICTORY", "")]),
    ],
}

# Campaign authority supersedes the former 39-recruit Chapter 1-2 pile-up.
# Each chapter now owns one readable companion arc and one acquisition result.
CONTACT_EVENT_SPECS = {
    str(chapter["id"]): [
        (str(chapter["recruit_stage"]), [(str(chapter["recruit_id"]), "IMMEDIATE_ON_VICTORY", "")])
    ]
    for chapter in chapter_rows()
}

for chapter in chapter_rows():
    for hard_index, boss_id in enumerate(boss_id_pairs()[chapter["id"]]):
        if boss_id in _BOSS_PATTERN_SETS:
            continue
        chapter_number = int(chapter["number"])
        _BOSS_PATTERN_SETS[boss_id] = [
            {"condition": "TIME", "value": 10 + (chapter_number % 7), "action": f"CH{chapter_number:02d}_SIGNATURE", "damage_multiplier": round(.54 + chapter_number * .018 + hard_index * .12, 3)},
            {"condition": "HP_BELOW", "value": round(.68 - (chapter_number % 4) * .04, 2), "action": "PHASE_2"},
            {"condition": "TIME_LEFT_BELOW", "value": 18 + (chapter_number % 5) * 3, "action": f"CH{chapter_number:02d}_FINALE", "damage_multiplier": round(.88 + chapter_number * .016 + hard_index * .10, 3)},
        ]


# Three non-recruitment contacts per chapter make the ! marker mean more than
# a companion acquisition.  These authored special-enemy incidents use the
# pre-battle dialogue contract but never grant a character, item, or completion
# flag before their actual battle has been won.
SPECIAL_ENEMY_EVENT_SPECS = {
    str(chapter["id"]): [
        ("N06", regular_enemy_ids_for_chapter(int(chapter["number"]))[0]),
        ("N13", regular_enemy_ids_for_chapter(int(chapter["number"]))[1]),
        ("H03", regular_enemy_ids_for_chapter(int(chapter["number"]))[2]),
    ]
    for chapter in chapter_rows()
}


# The long-route coordinates are deliberate authored anchors, not procedural
# encounters.  MacroWorldGenerator fills the legal terrain corridor between
# them, preserving the same one-hex movement and route-preview authority.
MAP_EXTENSION_COORDS = {
    "CH01": {
        "N": [(106, -15), (116, -20), (128, -18), (139, -23), (150, -21), (161, -26), (173, -24), (184, -29), (195, -27), (207, -32)],
        "H": [(201, -25), (193, -19), (183, -23), (174, -17), (166, -21), (156, -16), (148, -20), (138, -14), (130, -18), (119, -12)],
    },
    "CH02": {
        "N": [(115, -16), (127, -21), (139, -19), (150, -24), (162, -22), (173, -27), (185, -25), (196, -30), (208, -28), (220, -33)],
        "H": [(214, -26), (206, -20), (196, -24), (187, -18), (179, -22), (169, -17), (161, -21), (151, -15), (143, -19), (132, -13)],
    },
}


BOSS_PRESENTATIONS = {
    "CH01-N20": {"event_title_key": "MAP_BOSS_CH01_N20_TITLE", "boss_name_key": "ENEMY_HOLLOW_ENGINE", "boss_subtitle_key": "MAP_BOSS_CH01_N20_SUBTITLE"},
    "CH01-H03": {"event_title_key": "MAP_BOSS_CH01_H03_TITLE", "boss_name_key": "ENEMY_WHITE_DAWN_OBSERVER", "boss_subtitle_key": "MAP_BOSS_CH01_H03_SUBTITLE"},
    "CH01-H10": {"event_title_key": "MAP_BOSS_CH01_H10_TITLE", "boss_name_key": "ENEMY_NIGHT_BELL", "boss_subtitle_key": "MAP_BOSS_CH01_H10_SUBTITLE"},
    "CH02-N20": {"event_title_key": "MAP_BOSS_CH02_N20_TITLE", "boss_name_key": "ENEMY_REVERSE_GATEKEEPER", "boss_subtitle_key": "MAP_BOSS_CH02_N20_SUBTITLE"},
    "CH02-H10": {"event_title_key": "MAP_BOSS_CH02_H10_TITLE", "boss_name_key": "ENEMY_RETURN_FORMATION_CORE", "boss_subtitle_key": "MAP_BOSS_CH02_H10_SUBTITLE"},
}

for _chapter in chapter_rows():
    _chapter_id = str(_chapter["id"])
    _normal_boss_id, _hard_boss_id = boss_id_pairs()[_chapter_id]
    BOSS_PRESENTATIONS[f"{_chapter_id}-N20"] = {
        "event_title_key": f"MAP_BOSS_{_chapter_id}_N20_TITLE",
        "boss_name_key": f"ENEMY_{_chapter['normal_boss_code']}",
        "boss_subtitle_key": f"MAP_BOSS_{_chapter_id}_N20_SUBTITLE",
    }
    BOSS_PRESENTATIONS[f"{_chapter_id}-H05"] = {
        "event_title_key": f"MAP_BOSS_{_chapter_id}_H05_TITLE",
        "boss_name_key": f"ENEMY_{_chapter['hard_boss_code']}",
        "boss_subtitle_key": f"MAP_BOSS_{_chapter_id}_H05_SUBTITLE",
    }


def _dialogue_entry(speaker_kind: str, speaker_id: str, text_key: str) -> dict:
    return {"speaker_kind": speaker_kind, "speaker_id": speaker_id, "text_key": text_key}


def recruitment_battle_count(character_id: str) -> int:
    """Return the authored 1-5 victory route for a contact recruit.

    The contact battle itself is victory one.  Subsequent victories may be on
    any newly cleared route node, so a contact never requires grinding the same
    stage.  Iri is special: her three-operation prerequisite is N16-N18 and the
    N19 contact victory recruits her before N20.
    """
    # Reviewed Campaign-20 cadence: quick routes are common early, two-fight
    # arcs form the backbone, and only one late companion asks for five wins.
    route_counts = ([1] * 4) + ([2] * 9) + ([3] * 4) + ([4] * 2) + [5]
    return dict(zip(STORY_RECRUIT_IDS, route_counts)).get(character_id, 1)


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
        recruitment_rows = [
            {
                "character_id": character_id,
                "recruitment_timing": timing,
                "recruit_after_stage_id": after_stage,
                "battle_victories_required": recruitment_battle_count(character_id),
            }
            for character_id, timing, after_stage in recruits
        ]
        primary_battle_count = recruitment_battle_count(primary_id)
        events.append({
            "event_encounter_id": event_id, "node_id": node_id, "marker": "BANG", "entry_type": "EVENT_CONTACT", "event_kind": "COMPANION",
            "character_id": primary_id, "recruitment_timing": primary_timing, "recruit_after_stage_id": primary_after,
            "battle_victories_required": primary_battle_count,
            "title_key": title_key, "body_key": body_key, "contact_outcome_key": outcome_key,
            "recruitments": recruitment_rows,
            "pre_battle_dialogue": [
                _dialogue_entry("COMMAND", "", f"MAP_CONTACT_{suffix}_DIALOGUE_01"),
                _dialogue_entry("COMPANION", primary_id, f"MAP_CONTACT_{suffix}_DIALOGUE_02"),
                _dialogue_entry("COMMAND", "", f"MAP_CONTACT_{suffix}_DIALOGUE_03"),
            ],
            "stage_id": stage_id,
        })
    return events


def chapter_special_enemy_events(chapter_id: str) -> list[dict]:
    events: list[dict] = []
    for route_stage, enemy_id in SPECIAL_ENEMY_EVENT_SPECS[chapter_id]:
        suffix = f"{chapter_id}_{route_stage}"
        events.append({
            "event_encounter_id": f"EVENT_ANOMALY_{suffix}", "node_id": f"NODE_{route_stage}",
            "marker": "BANG", "entry_type": "EVENT_CONTACT", "event_kind": "SPECIAL_ENEMY", "enemy_id": enemy_id,
            "character_id": "", "recruitment_timing": "", "recruit_after_stage_id": "",
            "title_key": f"MAP_ANOMALY_{suffix}_TITLE", "body_key": f"MAP_ANOMALY_{suffix}_BODY",
            "contact_outcome_key": f"MAP_ANOMALY_{suffix}_OUTCOME", "recruitments": [],
            "pre_battle_dialogue": [
                _dialogue_entry("COMMAND", "", f"MAP_ANOMALY_{suffix}_DIALOGUE_01"),
                _dialogue_entry("ENEMY", enemy_id, f"MAP_ANOMALY_{suffix}_DIALOGUE_02"),
                _dialogue_entry("COMMAND", "", f"MAP_ANOMALY_{suffix}_DIALOGUE_03"),
            ],
            "stage_id": f"{chapter_id}-{route_stage}",
        })
    return events


def _is_boss_stage(stage: dict) -> bool:
    return any(str(enemy_id).startswith("BOSS") for wave in stage.get("waves", []) for enemy_id in wave)


def _node_type_for_stage(stage: dict) -> str:
    mode = str(stage["mode"])
    number = int(stage["stage_number"])
    if _is_boss_stage(stage):
        return f"{mode}_BOSS"
    # Keep a readable cadence across the expanded route: an elite every few
    # nodes, with the original authored elite beats retained where possible.
    elite_numbers = {"NORMAL": {4, 7, 10, 12, 15, 18}, "HARD": {3, 4, 5, 7, 9}}
    return f"{mode}_{'ELITE' if number in elite_numbers[mode] else 'BATTLE'}"


def _node_marker_asset(node_type: str) -> str:
    if node_type.endswith("BOSS"):
        return "map_marker_boss_r7"
    if node_type.endswith("ELITE"):
        return "map_marker_elite_r7"
    return "map_marker_hard_r7" if node_type.startswith("HARD") else "map_marker_normal_r7"


def expand_chapter_map_definition(definition: dict, chapter_id: str, stages: list[dict]) -> dict:
    """Build one authored 20N+5H route while keeping immutable stage IDs."""
    updated = json.loads(json.dumps(definition))
    by_id = {str(stage["id"]): stage for stage in stages if str(stage["chapter_id"]) == chapter_id}
    existing = {str(node.get("node_id", "")): node for node in updated.get("nodes", [])}
    start_nodes = [node for node in updated.get("nodes", []) if str(node.get("node_type", "")) == "START"]
    built_nodes = start_nodes[:1] or [{
        "node_id": "NODE_START", "node_type": "START", "q": 0, "r": 0,
        "stage_id": "", "scenario_id": "", "unlock_condition": "NONE",
        "reveal_condition": "ALWAYS", "marker_asset_id": "map_marker_start_r7",
        "repeatable": False, "fast_travel_allowed": True,
    }]
    chapter_number = int(chapter_id.removeprefix("CH"))
    for route_code, mode, count in (("N", "NORMAL", 20), ("H", "HARD", 5)):
        for number in range(1, count + 1):
            stage_id = f"{chapter_id}-{route_code}{number:02d}"
            node_id = f"NODE_{route_code}{number:02d}"
            stage = by_id[stage_id]
            node = dict(existing.get(node_id, {}))
            if route_code == "N":
                node["q"] = number * 10 + (chapter_number % 3) * 2
                node["r"] = -number - ((number + chapter_number) % 4) * 2
            else:
                node["q"] = 202 - number * 13 + (chapter_number % 4)
                node["r"] = -18 + number * 3 - (chapter_number % 3)
            node_type = _node_type_for_stage(stage)
            node.update({
                "node_id": node_id, "node_type": node_type, "stage_id": stage_id, "scenario_id": "",
                "unlock_condition": "STAGE_RULE", "reveal_condition": "ROUTE_PROGRESS",
                "marker_asset_id": _node_marker_asset(node_type), "repeatable": True, "fast_travel_allowed": True,
            })
            if _is_boss_stage(stage):
                presentation = dict(BOSS_PRESENTATIONS[stage_id])
                presentation["transition_style"] = "BOSS"
                node["presentation"] = presentation
            else:
                node.pop("presentation", None)
            built_nodes.append(node)
    updated["nodes"] = built_nodes
    updated["normal_route"] = [f"{chapter_id}-N{number:02d}" for number in range(1, 21)]
    updated["hard_route"] = [f"{chapter_id}-H{number:02d}" for number in range(1, 6)]
    macro = dict(updated.get("macro_world", {}))
    macro["linear_scale_viewports"] = 24
    macro["seed"] = 7022600 + chapter_number * 101
    macro["direction_policy"] = f"CHAPTER_{chapter_number:02d}_EXPEDITION_ROUTE"
    macro["bounds"] = {"min_q": -18, "max_q": 226, "min_r": -54, "max_r": 26}
    updated["macro_world"] = macro
    for patrol in updated.get("patrols", []):
        if str(patrol.get("encounter_id", "")) == "NODE_N10":
            patrol["entry_type"] = "ELITE_GUARD"
    return updated


def ensure_campaign_map_sources() -> None:
    """Create missing chapter map authorities without cloning event state."""
    map_root = SOURCE / "chapter_maps"
    map_root.mkdir(parents=True, exist_ok=True)
    for chapter in chapter_rows():
        chapter_id = str(chapter["id"])
        path = map_root / f"{chapter_id}_MAP.json"
        if path.exists() and chapter_id in ("CH01", "CH02"):
            continue
        definition = {
            "map_id": f"{chapter_id}_MAP", "chapter_id": chapter_id,
            "visual_set_id": f"{chapter_id}_{str(chapter['normal_boss_code'])}_R1",
            "start_hex": {"q": 0, "r": 0},
            "macro_world": {
                "seed": 7022600 + int(chapter["number"]) * 101,
                "linear_scale_viewports": 24, "corridor_radius": 4,
                "direction_policy": f"CHAPTER_{int(chapter['number']):02d}_EXPEDITION_ROUTE",
                "bounds": {"min_q": -18, "max_q": 226, "min_r": -54, "max_r": 26},
            },
            "normal_route": [], "hard_route": [],
            "map_simulation": {"seed": 140700 + int(chapter["number"]), "tick_seconds": .25, "wait_pulse_ticks": 4},
            "exploration_rules": {
                "base_move_points": 4, "max_move_points": 8,
                "account_level_milestones": [{"level": 35, "bonus": 1}, {"level": 60, "bonus": 1}, {"level": 85, "bonus": 1}],
                "mobility_items": [{"item_id": "EXPEDITION_ROUTE_MODULE_A", "bonus": 1}, {"item_id": "EXPEDITION_ROUTE_MODULE_B", "bonus": 1}],
            },
            "patrols": [], "relays": [], "map_events": [], "event_encounters": [],
            "nodes": [{
                "node_id": "NODE_START", "node_type": "START", "q": 0, "r": 0,
                "stage_id": "", "scenario_id": "", "unlock_condition": "NONE",
                "reveal_condition": "ALWAYS", "marker_asset_id": "map_marker_start_r7",
                "repeatable": False, "fast_travel_allowed": True,
            }],
        }
        write_json(path, definition)


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
            "background": "bg_ch01_glass_rail_story", "portrait": "portrait_chr006_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C1B_01", "SERIOUS"),
                ("dialogue", "CHAR_VERA_NAME", "STORY_C1B_02", "SERIOUS"),
                ("dialogue", "CHAR_VERA_NAME", "STORY_C1B_03", "BATTLE_FOCUS"),
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
            "background": "bg_ch01_glass_rail_story", "portrait": "portrait_chr008_dev",
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C2B_01", "SERIOUS"),
                ("dialogue", "SPEAKER_IRI", "STORY_C2B_02", "CONCERNED"),
                ("dialogue", "SPEAKER_IRI", "STORY_C2B_03", "BATTLE_FOCUS"),
            ],
        },
        {
            "id": "SCN_CH02_PREBOSS", "title": "SCENARIO_CH02_PREBOSS_TITLE", "chapter": "CH02",
            "background": "bg_ch01_signal_cathedral_story", "portrait": "portrait_chr008_dev",
            "extra_portraits": [
                {"command": "show_portrait", "slot": "LEFT", "asset_id": "portrait_chr005_dev", "expression": "ALERT"},
            ],
            "lines": [
                ("narration", "SPEAKER_ROUTEKEEPER", "STORY_C2P_01", "ALERT"),
                ("dialogue", "SPEAKER_IRI", "STORY_C2P_02", "SERIOUS"),
                ("dialogue", "SPEAKER_SOREN", "STORY_C2P_03", "SERIOUS"),
                ("dialogue", "SPEAKER_IRI", "STORY_C2P_04", "BATTLE_FOCUS"),
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


def campaign_scenario_sources() -> list[dict]:
    """Append staged Chapter 3-20 story and inter-chapter records.

    The current recruit is always shown as premium half-body art during her
    contact and pre-boss decision.  The immediately previous recruit remains
    opposite her so joining the party is dramatized as a relationship, not a
    text-only unlock notification.
    """
    result = scenario_sources()
    character_codes = {str(row[0]): str(row[1]) for row in CHARACTERS}
    for chapter in chapter_rows()[2:]:
        chapter_id = str(chapter["id"])
        chapter_number = int(chapter["number"])
        recruit_id = str(chapter["recruit_id"])
        recruit_speaker = f"CHAR_{character_codes[recruit_id]}_NAME"
        previous_recruit_id = str(chapter_rows()[chapter_number - 2]["recruit_id"])
        beats = (
            ("INTRO", "portrait_chr001_dev", "SPEAKER_MAERU", "SERIOUS"),
            ("MID_A", "portrait_chr003_dev", "SPEAKER_NARIN", "ALERT"),
            ("MID_B", f"portrait_{recruit_id.lower()}_dev", recruit_speaker, "CONCERNED"),
            ("PREBOSS", f"portrait_{recruit_id.lower()}_dev", recruit_speaker, "BATTLE_FOCUS"),
            ("OUTRO", "portrait_chr001_dev", "SPEAKER_MAERU", "SMILE"),
        )
        for beat, portrait, speaker_key, expression in beats:
            scenario_id = f"SCN_{chapter_id}_{beat}"
            text_prefix = f"STORY_{chapter_id}_{beat}"
            commands = [
                {"id": "start", "command": "set_background", "asset_id": "bg_lantern_tunnel_dev" if beat in ("INTRO", "OUTRO") else "bg_ch01_signal_cathedral_story"},
                {"command": "show_portrait", "slot": "LEFT" if beat in ("MID_B", "PREBOSS") else "RIGHT", "asset_id": portrait, "expression": expression},
            ]
            if beat in ("MID_B", "PREBOSS"):
                commands.append({"command": "show_portrait", "slot": "RIGHT", "asset_id": f"portrait_{previous_recruit_id.lower()}_dev", "expression": "SERIOUS"})
            elif beat == "OUTRO":
                commands.append({"command": "show_portrait", "slot": "LEFT", "asset_id": f"portrait_{recruit_id.lower()}_dev", "expression": "SMILE"})
            commands.extend([
                {"command": "fade_in", "duration": .24},
                {"command": "narration", "speaker_key": "SPEAKER_ROUTEKEEPER", "text_key": f"{text_prefix}_01"},
                {"command": "dialogue", "speaker_key": speaker_key, "text_key": f"{text_prefix}_02"},
                {"command": "set_expression", "slot": "LEFT" if beat in ("MID_B", "PREBOSS") else "RIGHT", "expression": "RESOLVED" if beat != "OUTRO" else "SMILE"},
                {"command": "dialogue", "speaker_key": speaker_key, "text_key": f"{text_prefix}_03"},
            ])
            if beat == "OUTRO":
                commands.append({"command": "narration", "speaker_key": "SPEAKER_ROUTEKEEPER", "text_key": f"{text_prefix}_INTERLUDE"})
            commands.extend([{"command": "grant_reward", "item_id": "LANTERN_SHARD", "quantity": 5}, {"command": "end_scenario"}])
            result.append({
                "id": scenario_id, "title_key": f"SCENARIO_{chapter_id}_{beat}_TITLE",
                "chapter_id": chapter_id, "commands": commands,
            })
    return result


def campaign_story_triggers() -> list[dict]:
    # The generated source file is intentionally rewritten on every build.
    # Retain only the hand-authored CH01/CH02 authority before regenerating
    # CH03-CH20 so repeated builds remain idempotent instead of duplicating
    # ninety campaign triggers each time.
    source_triggers = json.loads((SOURCE / "chapter_story_triggers.json").read_text(encoding="utf-8"))
    triggers = [
        row for row in source_triggers
        if str(row.get("id", "")).startswith("TRIG_CH01_")
        or str(row.get("id", "")).startswith("TRIG_CH02_")
    ]
    # Shortened Hard routes end at H05.
    for trigger in triggers:
        if str(trigger.get("stage_id", "")) == "CH01-H10":
            trigger["stage_id"] = "CH01-H05"
        elif str(trigger.get("stage_id", "")) == "CH02-H10":
            trigger["stage_id"] = "CH02-H05"
    priority = max(int(row.get("priority", 0)) for row in triggers) + 10
    for chapter in chapter_rows()[2:]:
        chapter_id = str(chapter["id"])
        for beat, event, stage_code in (
            ("INTRO", "MAP_ENTER", ""),
            ("MID_A", "STAGE_CLEAR", "N04"),
            ("MID_B", "STAGE_CLEAR", "N14"),
            ("PREBOSS", "STAGE_CLEAR", "N19"),
            ("OUTRO", "STAGE_CLEAR", "N20"),
        ):
            trigger_id = f"TRIG_{chapter_id}_{beat}"
            triggers.append({
                "id": trigger_id, "event": event,
                "stage_id": "" if not stage_code else f"{chapter_id}-{stage_code}",
                "scenario_id": f"SCN_{chapter_id}_{beat}",
                "completion_flag": f"story.trigger.{trigger_id}", "priority": priority,
            })
            priority += 10
    return triggers


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
	"RESULT_EVENT_TRACKING_BATTLES": ("신호 동행 · %s 합류까지 신규 작전 승리 %d회", "Signal Follow-up · %s joins after %d more new-operation victories"),
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
    loc.update({
        "CHAPTER_01": ("제1장 — 꺼진 노선의 신호", "Chapter 1 — Signal on the Dark Line"),
        "CHAPTER_02": ("제2장 — 되감기는 종착선", "Chapter 2 — The Returning Terminus"),
        "MAP_EVENT_COMMAND_NAME": ("등로단 통신", "Lamplighter Comms"),
        "MAP_EVENT_ENEMY_SIGNAL_NAME": ("위협 신호", "Threat Signal"),
        "MAP_EVENT_DIALOGUE_SKIP": ("대화 건너뛰기", "Skip dialogue"),
        "MAP_EVENT_DIALOGUE_NEXT": ("다음", "Next"),
        "MAP_EVENT_DIALOGUE_BATTLE": ("전투 개시", "Begin battle"),
        "MAP_EVENT_DIALOGUE_HINT": ("화면을 누르거나 다음을 선택해 사건을 진행합니다.", "Tap the panel or choose Next to continue the incident."),
    })
    for chapter in chapter_rows()[2:]:
        loc[f"CHAPTER_{int(chapter['number']):02d}"] = (
            f"제{int(chapter['number'])}장 — {chapter['title_ko']}",
            f"Chapter {int(chapter['number'])} — {chapter['title_en']}",
        )
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
            loc[f"MAP_CONTACT_{chapter_id}_{str(event['stage_id']).split('-')[-1]}_DIALOGUE_01"] = ("미확인 신호를 포착했습니다. 전투 구역에 진입하기 전에 응답 주체를 확인합니다.", "An unidentified signal is inside the combat zone. Confirm the responder before entering.")
            loc[f"MAP_CONTACT_{chapter_id}_{str(event['stage_id']).split('-')[-1]}_DIALOGUE_02"] = (f"{joined_ko}입니다. 신호가 적대 개체에 붙잡혀 있습니다. 길을 열면 합류하겠습니다.", f"This is {joined_en}. Hostiles have pinned the signal; clear a path and we will join you.")
            loc[f"MAP_CONTACT_{chapter_id}_{str(event['stage_id']).split('-')[-1]}_DIALOGUE_03"] = ("영입 여부와 보상은 전투 승리 뒤에만 확정됩니다. 편성을 정비하고 접촉을 개시합니다.", "Recruitment and rewards will be confirmed only after victory. Prepare the formation and initiate contact.")
            route_ko = [f"{korean_names[i]} {int(row['battle_victories_required'])}회" for i, row in enumerate(recruitments)]
            route_en = [f"{english_names[i]} {int(row['battle_victories_required'])} battle(s)" for i, row in enumerate(recruitments)]
            outcome_ko = "작전 승리 누적 후 합류 · " + " / ".join(route_ko)
            outcome_en = "Joins after operation victories · " + " / ".join(route_en)
            loc[outcome_key] = (outcome_ko, outcome_en)
    for chapter_id in SPECIAL_ENEMY_EVENT_SPECS:
        for event in chapter_special_enemy_events(chapter_id):
            suffix = str(event["stage_id"]).split("-")[-1]
            enemy_id = str(event["enemy_id"])
            enemy_ko = enemy_names.get(enemy_id, enemy_id)
            loc[str(event["title_key"])] = (f"특이 위협 신호 · {enemy_ko}", f"Anomalous Threat Signal: {enemy_id}")
            loc[str(event["body_key"])] = ("경로를 봉쇄하는 특이 반응이 감지되었습니다. 신호를 분석한 뒤 전투 구역으로 진입합니다.", "An anomalous reaction is blocking the route. Analyze the signal before entering the combat zone.")
            loc[str(event["contact_outcome_key"])] = ("승리 시 위협 신호 안정화 · 영입/보상은 없음", "Victory outcome: threat signal stabilized · no recruitment/reward")
            loc[f"MAP_ANOMALY_{chapter_id}_{suffix}_DIALOGUE_01"] = ("경로 앞의 반응은 일반 개체와 다릅니다. 가까이 가면 전투가 시작됩니다.", "The reaction ahead is unlike a normal unit. Combat will begin after the signal is assessed.")
            loc[f"MAP_ANOMALY_{chapter_id}_{suffix}_DIALOGUE_02"] = (f"{enemy_ko}: [왜곡된 적대 파장]", f"{enemy_id}: [distorted hostile waveform]")
            loc[f"MAP_ANOMALY_{chapter_id}_{suffix}_DIALOGUE_03"] = ("신호를 고정했습니다. 이 창을 닫으면 전투 개시이며, 승리 전에는 아무 상태도 확정되지 않습니다.", "The signal is locked. Closing this window begins combat; no state is committed before victory.")
    boss_copy = {
        "MAP_BOSS_CH01_N20": ("심층 중계 핵", "Deep Relay Core"), "MAP_BOSS_CH01_H03": ("백야 감시선", "White Dawn Watchline"),
        "MAP_BOSS_CH01_H10": ("심야 공명선", "Midnight Resonance Line"), "MAP_BOSS_CH02_N20": ("역행 개찰 심층", "Reverse Gate Depths"),
        "MAP_BOSS_CH02_H10": ("회송 편성 최심부", "Return Formation Depths"),
    }
    for chapter in chapter_rows():
        chapter_id = str(chapter["id"])
        boss_copy[f"MAP_BOSS_{chapter_id}_N20"] = (str(chapter["title_ko"]), str(chapter["title_en"]))
        boss_copy[f"MAP_BOSS_{chapter_id}_H05"] = (f"{chapter['title_ko']} · 심층", f"{chapter['title_en']} · Depths")
    for prefix, pair in boss_copy.items():
        loc[prefix + "_TITLE"] = pair
        loc[prefix + "_SUBTITLE"] = ("고유 보스 신호 · 경로 최종 방어선", "Unique boss signal · final route defense")
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
    beat_titles = {
        "INTRO": ("진입", "Arrival"), "MID_A": ("첫 단서", "First Trace"),
        "MID_B": ("뒤집힌 기록", "Reversed Record"), "PREBOSS": ("최종 방어선", "Final Defense"),
        "OUTRO": ("다음 노선", "The Next Line"),
    }
    for chapter in chapter_rows()[2:]:
        chapter_id = str(chapter["id"])
        for beat, (beat_ko, beat_en) in beat_titles.items():
            scenario_titles[f"SCN_{chapter_id}_{beat}"] = (
                f"제{int(chapter['number'])}장 · {chapter['title_ko']} — {beat_ko}",
                f"Chapter {int(chapter['number'])} · {chapter['title_en']} — {beat_en}",
            )
    for scn in scenarios:
        loc[scn["title_key"]] = scenario_titles[scn["id"]]
    story_ko = {
        "STORY_PRO_01": "대정전 뒤, 지하의 광맥 철로는 마지막 도시들을 잇는 유일한 길이 되었다.", "STORY_PRO_02": "새로 깨어난 기록 항해자는 끊긴 등불과 사람들의 기억을 복구해야 한다.", "STORY_PRO_03": "제7 승강장에서 첫 신호가 깜박이고 있어. 거기서 시작하자.", "STORY_PRO_04": "정찰로는 내가 연다. 신호가 살아나면 바로 따라와.",
        "STORY_C1I_01": "등로단은 잔광 폭풍 속에서도 움직이는 소규모 복구 조직이다.", "STORY_C1I_02": "지도에 없는 선로에서 구조 요청을 들었어. 아직 신호가 살아 있어.", "STORY_C1I_03": "진위를 확인하고 길을 복구하자. 모두 출발 준비.",
        "STORY_C1A_01": "첫 터널에는 기억을 흉내 내는 잔향체가 모여 있었다.", "STORY_C1A_02": "그것들은 사람의 목소리를 냈지만 질문에는 답하지 못했다.", "STORY_C1A_03": "전투 뒤 손상되지 않은 기록편 하나를 회수했어. 다음 구간을 열 수 있겠어.",
        "STORY_C1B_01": "기록편의 구조 신호가 공허기관 안에서 역방향으로 소모되고 있었다. 중계기 앞에는 신호를 추적하던 베라가 버티고 있었다.", "STORY_C1B_02": "공허기관이 삼키는 건 광맥 전력이 아니야. 구조 신호의 잔향을 연료로 바꾸고 있어.", "STORY_C1B_03": "내가 역추적 경로를 열게. 핵심부까지 함께 가자. 이 신호를 사람들에게 돌려줘야 해.",
        "STORY_C1C_01": "좌표는 폐쇄된 종탑형 중계기로 이어졌다. 구조 대상은 더 깊은 회송선에서 원격 신호만 보내고 있었다.", "STORY_C1C_02": "이리야. 아직 합류할 수는 없어. 생체 신호를 따라오면 종착선 앞에서 길을 열어 둘게.", "STORY_C1C_03": "잔향체 군집이 중계기를 포위했어. 신호를 잃지 않으려면 먼저 이 구간을 돌파해야 해.",
        "STORY_PRE_01": "거대한 공허기관이 선로의 빛을 삼키며 깨어났다.", "STORY_PRE_02": "각자 등불과 장비를 확인해. 여기서부터는 한 번의 실수도 허용되지 않아.", "STORY_PRE_03": "우리가 지키려는 것은 선로가 아니라, 그 끝에서 기다리는 사람들의 이야기야.",
        "STORY_OUT_01": "공허기관이 멈추자 지워졌던 행선지가 다시 나타났다.", "STORY_OUT_02": "마지막 열차는 사라진 도시가 아니라 이동 중인 피난처를 향하고 있었다.", "STORY_OUT_03": "첫 노선은 다시 이어졌어. 이제 다음 등불로 가자.",
        "STORY_REL_M_01": "출발 전에는 빈 좌석의 안전띠까지 확인해. 빠뜨리면 마음이 놓이지 않거든.", "STORY_REL_M_02": "돌아오지 못한 동료의 자리를 잊지 않기 위해 시작한 습관이야.", "STORY_REL_M_03": "오늘은 그 자리에 새 구조 장비를 놓았어. 빈자리가 다음 사람을 살리게 됐네.",
        "STORY_REL_I_01": "고장 난 안내 방송을 모아서 작은 합창곡을 만들었어.", "STORY_REL_I_02": "완벽한 음정보다 누군가 살아 있었다는 흔적이 더 중요하다고 생각해.", "STORY_REL_I_03": "다음 정거장에 도착하면 같이 틀어 보자. 혼자 듣는 것보다 좋을 거야.",
        "STORY_C2I_01": "세 개의 고유 보스 기록에는 같은 짧은 handshake 패턴이 남아 있었다.", "STORY_C2I_02": "신호는 진행 방향이 아니라 종착점에서 출발점 쪽으로 하나씩 켜지고 있어.", "STORY_C2I_03": "시간을 되돌리는 장치가 아니야. 망가진 회송 절차가 현재의 우리를 과거 기록에 끼워 맞추고 있어.",
        "STORY_C2A_01": "닫힌 승강장은 존재하지 않는 승객의 이름을 반복해서 불렀다.", "STORY_C2A_02": "구조 신호가 진짜인지 가짜인지가 아니라, 지금 누가 그 신호를 듣고 있는지가 중요해.", "STORY_C2A_03": "우리 이름을 과거 목록에서 지우고, 현재 좌표를 남기자.",
        "STORY_C2B_01": "전력은 거꾸로 흘렀고, 회송핵은 살아 있는 승객을 과거 명부의 빈 좌석으로 덮어쓰기 시작했다.", "STORY_C2B_02": "내 생체 기록으로 현재 명부를 고정하면 마지막 개찰까지 모두의 신원을 지킬 수 있어.", "STORY_C2B_03": "명부 고정이 끝날 때까지 동행할게. 끝나면 보호 대상이 아니라 원정대의 의료 담당으로 가겠어.",
        "STORY_C2P_01": "세 개의 방어 구간을 연속 돌파하자, 종탑형 중계기에서 추적하던 생체 신호가 중앙 개찰 바로 앞에서 모습을 드러냈다.", "STORY_C2P_02": "늦어서 미안해. 이리야. 회송선의 부상자를 지키느라 움직일 수 없었지만, 이제부터는 내가 너희의 후방을 맡을게.", "STORY_C2P_03": "합류 신호 확인. 다음은 역행 개찰의 고유 방어 개체야. 네 회복 장치가 버틸 수 있겠어?", "STORY_C2P_04": "세 구간 동안 출력은 충분히 맞춰 뒀어. 다친 사람 없이 저 문을 넘기자.",
        "STORY_C2H_01": "지하 회송실에는 빈 자리만 남은 편성표가 벽처럼 이어져 있었다.", "STORY_C2H_02": "이 핵은 사람을 찾는 게 아니라, 비어 있는 칸을 채우려는 거야.", "STORY_C2H_03": "우리가 멈추게 할 건 과거가 아니라, 현재를 지워 버리는 이 명령이야.",
        "STORY_C2O_01": "회송 편성핵이 멈추자, 뒤집혀 있던 신호등이 하나씩 정상 방향으로 돌아왔다.", "STORY_C2O_02": "모든 기록이 사라진 것은 아니지만, 더는 현재의 사람을 과거의 빈자리에 넣지 않았다.", "STORY_C2O_03": "남은 건 바깥을 향한 하나의 정상 신호야. 다음 길은 우리가 선택해서 이어 가자.",
    }
    story_en = {
        "STORY_PRO_01": "After the Great Blackout, the mineral railway beneath the earth became the last route connecting the surviving cities.", "STORY_PRO_02": "A newly awakened record navigator must restore broken lights and the memories carried between them.", "STORY_PRO_03": "The first signal is blinking at Platform Seven. We start there.", "STORY_PRO_04": "I will clear the reconnaissance route. Follow as soon as the signal comes alive.",
        "STORY_C1I_01": "The Lamplighters are a small restoration crew that keeps moving even through afterglow storms.", "STORY_C1I_02": "I heard a rescue call from a line that is not on the map. The signal is still alive.", "STORY_C1I_03": "We verify it and restore the route. Everyone, prepare to depart.",
        "STORY_C1A_01": "The first tunnel was crowded with echoforms that imitated human memories.", "STORY_C1A_02": "They spoke in human voices, but none could answer a question.", "STORY_C1A_03": "I recovered an intact record fragment after the battle. It should open the next section.",
        "STORY_C1B_01": "The fragment's rescue signal was being consumed backward inside the Hollow Engine. Vera was holding the relay while tracing it.", "STORY_C1B_02": "The Hollow Engine is not consuming ore-line power. It is turning the echoes of rescue calls into fuel.", "STORY_C1B_03": "I will open a reverse-trace route. Come with me to the core. We have to return these signals to their people.",
        "STORY_C1C_01": "The coordinates led to a sealed bell-tower relay. The survivor could only transmit remotely from deeper in the return line.", "STORY_C1C_02": "This is Iri. I cannot join you yet. Follow my biosignal and I will open the way near the terminus.", "STORY_C1C_03": "An echoform cluster has surrounded the relay. Break through this section before we lose the signal.",
        "STORY_PRE_01": "The massive Hollow Engine awoke, swallowing the light along the rails.", "STORY_PRE_02": "Check your lights and equipment. From here on, one mistake is too many.", "STORY_PRE_03": "We are not protecting the rails. We are protecting the stories of the people waiting at their end.",
        "STORY_OUT_01": "When the Hollow Engine stopped, the erased destination returned.", "STORY_OUT_02": "The final train had not been bound for a lost city, but for a refuge still in motion.", "STORY_OUT_03": "The first line is connected again. Let us head for the next light.",
        "STORY_REL_M_01": "Before departure, I even check the seatbelt on the empty seat. I cannot relax if I skip it.", "STORY_REL_M_02": "I began doing it so I would not forget the teammate who never returned.", "STORY_REL_M_03": "Today I placed new rescue gear there. An empty place can help save the next person now.",
        "STORY_REL_I_01": "I gathered broken station announcements and turned them into a little chorus.", "STORY_REL_I_02": "A trace that someone lived matters more to me than perfect pitch.", "STORY_REL_I_03": "Let us play it together at the next station. It will sound better than listening alone.",
        "STORY_C2I_01": "The three unique boss records retained the same short handshake pattern.", "STORY_C2I_02": "Signals are lighting one by one from the terminus back toward the origin, not in the direction of travel.", "STORY_C2I_03": "It is not time travel. A damaged return procedure is fitting us into a past record.",
        "STORY_C2A_01": "The sealed platform kept calling the names of passengers who no longer existed.", "STORY_C2A_02": "What matters is not whether a rescue signal is real, but who is hearing it now.", "STORY_C2A_03": "Erase our names from the old list and leave our current coordinates behind.",
        "STORY_C2B_01": "Power flowed backward as the return core began overwriting living passengers with empty seats from an old manifest.", "STORY_C2B_02": "If I anchor the current manifest to my biometric record, I can protect everyone's identity through the final gate.", "STORY_C2B_03": "I will stay until the manifest is fixed. After that, I join as the expedition's medic—not as someone you have to protect.",
        "STORY_C2P_01": "After three consecutive defense sectors, the biosignal tracked from the bell-tower relay finally appeared before the central gate.", "STORY_C2P_02": "Sorry I am late. I am Iri. I could not leave the wounded on the return line, but from now on I will hold your rear line.", "STORY_C2P_03": "Recruitment signal confirmed. The Reverse Gatekeeper is next. Can your recovery rig withstand it?", "STORY_C2P_04": "I tuned its output through all three sectors. We cross that gate without leaving anyone wounded behind.",
        "STORY_C2H_01": "The underground return chamber was lined like a wall with formation charts containing only vacant seats.", "STORY_C2H_02": "This core is not looking for people. It is trying to fill empty slots.", "STORY_C2H_03": "We will stop not the past, but the command that erases the present.",
        "STORY_C2O_01": "When the return formation core stopped, the inverted signal lights turned back toward their proper direction.", "STORY_C2O_02": "Not every record vanished, but none could place a present person into a past empty seat again.", "STORY_C2O_03": "One true beacon remains, facing outward. We choose how to connect the next route.",
    }
    for key, ko in story_ko.items():
        loc[key] = (ko, story_en[key])
    for chapter in chapter_rows()[2:]:
        chapter_id = str(chapter["id"])
        conflict_ko = str(chapter["conflict_ko"])
        conflict_en = str(chapter["conflict_en"])
        opening, truth, recruit_action, boss_reversal, resolution, next_hook = CHAPTER_STORY_ARCS[chapter_id]
        beat_lines = {
            "INTRO": (opening, (f"이 신호는 앞선 노선의 결과다. 이번 목표는 {conflict_ko}.", f"This signal is a consequence of the previous line. Our objective is to {conflict_en}."), ("원인을 남겨 둔 채 다음 길로 도망치지 않는다. 여기서 연결을 바로잡는다.", "We will not flee onward while leaving the cause behind. We repair the connection here.")),
            "MID_A": (truth, ("단순한 고장이 아니야. 누군가의 선택을 규칙으로 굳힌 장치야.", "This is no simple fault. A machine has hardened someone's choice into a rule."), ("그 규칙이 누구를 지우는지 확인했어. 다음 접촉에서 증거를 확보한다.", "We know who that rule erases. The next contact will secure the proof.")),
            "MID_B": (recruit_action, ("내가 이 구간의 틈을 붙들게. 당신들은 이 신호가 끝나는 곳까지 가 줘.", "I will hold the gap in this sector. Follow the signal to where it ends."), ("이번 전투만의 거래가 아니야. 이 길을 끝까지 확인하기 위해 함께 가겠다.", "This is more than a bargain for one fight. I will come with you to see this route through.")),
            "PREBOSS": (boss_reversal, ("내가 찾아낸 약점은 아직 유효해. 놈이 규칙을 바꾸기 전에 진입해야 해.", "The weakness I found still holds. We enter before it can rewrite the rule."), ("뒤는 내가 맡는다. 이 전투가 끝나야 내 합류도, 이 노선의 결과도 확정돼.", "I have the rear. My recruitment—and this route's outcome—become final only after victory.")),
            "OUTRO": (resolution, ("함께 싸운 이유를 이제 내 기록으로 남길게. 다음 노선에서도 이 선택을 지키겠다.", "I will record why we fought together and defend that choice on the next line."), ("한 장의 결말이 다음 장의 원인이 됐어. 남은 신호를 따라 출발한다.", "One chapter's ending has become the next one's cause. We follow the remaining signal.")),
        }
        for beat, lines in beat_lines.items():
            prefix = f"STORY_{chapter_id}_{beat}"
            loc[f"{prefix}_01"], loc[f"{prefix}_02"], loc[f"{prefix}_03"] = lines
            if beat == "OUTRO":
                loc[f"{prefix}_INTERLUDE"] = next_hook
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
    stages, rewards = campaign_stage_data()
    # Relay specs stay data-authored so the shell and saved run logic never embed
    # a CH01-only stage list. This first vertical slice intentionally reuses
    # existing non-boss battles and existing inventory resources.
    relay_specs = relay_spec_data()

    # Chapter definitions are consumed at runtime for map selection, route
    # progression, and additive save repair. Keep the exact ordered stage IDs
    # here instead of deriving them from a CH01-only string convention.
    chapters = [
        {
            "id": chapter_id, "number": number, "name_key": name_key, "map_id": map_id,
            "normal_stage_ids": [s["id"] for s in stages if s["chapter_id"] == chapter_id and s["mode"] == "NORMAL"],
            "hard_stage_ids": [s["id"] for s in stages if s["chapter_id"] == chapter_id and s["mode"] == "HARD"],
            "required_stage_ids": [f"{chapter_id}-N{stage_number:02d}" for stage_number in (1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 19, 20)],
            "optional_stage_ids": [f"{chapter_id}-N{stage_number:02d}" for stage_number in (3, 5, 7, 9, 11, 13, 15, 17)] + [f"{chapter_id}-H{stage_number:02d}" for stage_number in range(1, 6)],
        }
        for chapter_id, number, name_key, map_id in [
            (str(chapter["id"]), int(chapter["number"]), f"CHAPTER_{int(chapter['number']):02d}", f"{chapter['id']}_MAP")
            for chapter in chapter_rows()
        ]
    ]
    items = item_data()
    weapons = weapon_data()
    breakthrough, normal_costs, ultimate_costs = costs()
    scenarios = campaign_scenario_sources()
    char_levels, acct_levels, weapon_levels = level_rows(), account_rows(), weapon_level_rows()
    affinity_matrix = json.loads((SOURCE / "affinity_matrix.json").read_text(encoding="utf-8"))
    status_effects = json.loads((SOURCE / "status_effects.json").read_text(encoding="utf-8"))
    story_triggers = campaign_story_triggers()
    write_json(SOURCE / "chapter_story_triggers.json", story_triggers)

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
    write_json(SOURCE / "relay_specs.json", relay_specs)
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
    ensure_campaign_map_sources()
    chapter_map_source = SOURCE / "chapter_maps"
    for map_path in sorted(chapter_map_source.glob("*.json")):
        map_definition = json.loads(map_path.read_text(encoding="utf-8"))
        chapter_id = str(map_definition.get("chapter_id", ""))
        if chapter_id in CONTACT_EVENT_SPECS:
            map_definition = expand_chapter_map_definition(map_definition, chapter_id, stages)
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
            map_definition["event_encounters"] = chapter_contact_events(chapter_id) + chapter_special_enemy_events(chapter_id)
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
        "legacy_retired_stage_ids": [f"CH{chapter_number:02d}-H{stage_number:02d}" for chapter_number in (1, 2) for stage_number in range(6, 11)],
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
        "relay_specs": relay_specs,
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
