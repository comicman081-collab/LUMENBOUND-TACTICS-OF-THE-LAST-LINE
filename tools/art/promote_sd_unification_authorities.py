#!/usr/bin/env python3
"""Promote locally reviewed SD-unification cutouts into the dev contract.

Costume IDs stay immutable because this revision changes proportion and battle
pose only. The selected authority path/hash changes, and the review surface is
recorded honestly as local visual QA rather than external GPT approval.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "data_source/art_source/expansion_static_sources/qa/COSTUME_CONTINUITY_CONTRACT.json"
AUTHORITY_ROOT = ROOT / "data_source/art_source/combat_hd_sources/renewed"

FILES = {
    "CHR016": "chr016_costume_c_sd_r1_greenkey_authority.png",
    "CHR017": "chr017_costume_c_sd_r1_greenkey_authority.png",
    "CHR018": "chr018_costume_d_sd_r1_greenkey_authority.png",
    "CHR019": "chr019_costume_c_sd_r1_rgba_authority.png",
    "CHR020": "chr020_costume_c_sd_r1_rgba_authority.png",
    "CHR021": "chr021_costume_c_sd_r1_rgba_authority.png",
    "CHR022": "chr022_costume_c_sd_r1_rgba_authority.png",
    "CHR023": "chr023_costume_c_sd_r1_rgba_authority.png",
    "CHR024": "chr024_costume_c_sd_r1_rgba_authority.png",
    "CHR025": "chr025_costume_c_sd_r1_rgba_authority.png",
    "CHR027": "chr027_costume_d_sd_r1_rgba_authority.png",
    "CHR033": "chr033_costume_c_sd_r1_rgba_authority.png",
    "CHR039": "chr039_costume_c_sd_r1_rgba_authority.png",
    "CHR040": "chr040_costume_d_sd_r1_rgba_authority.png",
    "CHR041": "chr041_costume_c_sd_r1_rgba_authority.png",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    data = json.loads(CONTRACT.read_text(encoding="utf-8"))
    overrides = data["developmentCostumeOverrides"]
    for entity_id, filename in FILES.items():
        path = AUTHORITY_ROOT / filename
        if not path.is_file():
            raise FileNotFoundError(path)
        entry = overrides[entity_id]
        entry["authorityImage"] = f"../../combat_hd_sources/renewed/{filename}"
        entry["authoritySha256"] = sha256(path)
        entry["status"] = "CANDIDATE_LOCAL_SD_UNIFICATION_PASS_DEV_RUNTIME"
        entry["artRevision"] = "SD_UNIFICATION_R1"
        entry["generationMatte"] = {
            "color": "#00FF00",
            "role": "INTERMEDIATE_ONLY",
            "runtimeBackground": "TRANSPARENT_RGBA",
            "keying": "FULL_CANVAS_STRICT_HUE_GREEN_KEY_WITH_EDGE_DESPILL",
        }
        entry["review"] = {
            "verdict": "SD_IDENTITY_CONTINUITY_PASS",
            "surface": "codex_local_visual_review",
            "checks": [
                "adult_15_plus_3_5_to_4_head_sd_read",
                "source_identity_hair_ornament_palette_role_weapon_preserved",
                "distinct_face_and_silhouette_preserved",
                "player_screen_right_combat_intent",
                "green_matte_keyed_to_transparent_rgba",
                "complete_body_and_readable_hands_weapon_or_device",
            ],
        }
        print(f"SD_AUTHORITY={entity_id}|{filename}|{entry['authoritySha256']}")
    CONTRACT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
