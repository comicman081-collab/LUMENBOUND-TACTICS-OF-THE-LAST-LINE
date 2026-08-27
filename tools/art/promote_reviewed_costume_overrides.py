"""Promote only already-reviewed costume authorities into the dev runtime contract.

This command deliberately does not invent art, regenerate files, or erase the
prior authority.  It records the exact approved PNG, SHA-256, versioned
costume ID and review gate so the Web pack builder can consume it deterministically.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RENEWED = ROOT / "data_source" / "art_source" / "combat_hd_sources" / "renewed"
CONTRACT = ROOT / "data_source" / "art_source" / "expansion_static_sources" / "qa" / "COSTUME_CONTINUITY_CONTRACT.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def roster() -> dict[str, dict[str, str]]:
    with (ROOT / "data_source" / "characters.csv").open(encoding="utf-8-sig", newline="") as stream:
        return {str(row["id"]).upper(): row for row in csv.DictReader(stream)}


def parse_candidate(value: str) -> tuple[str, str]:
    entity_id, separator, version = value.upper().partition(":")
    if separator != ":" or not entity_id.startswith("CHR") or version not in {"B", "C", "D"}:
        raise argparse.ArgumentTypeError("use CHRnnn:B, CHRnnn:C, or CHRnnn:D")
    return entity_id, version


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "approved",
        nargs="+",
        type=parse_candidate,
        help="IDs that have already received an explicit COSTUME_CONTINUITY_PASS",
    )
    args = parser.parse_args()

    document = json.loads(CONTRACT.read_text(encoding="utf-8"))
    overrides = dict(document.get("developmentCostumeOverrides", {}))
    rows = roster()
    for entity_id, version in args.approved:
        row = rows.get(entity_id)
        if row is None:
            raise ValueError(f"unknown roster ID: {entity_id}")
        authority = RENEWED / f"{entity_id.lower()}_costume_{version.lower()}_authority.png"
        if not authority.is_file():
            raise FileNotFoundError(f"approved authority is missing: {authority}")
        overrides[entity_id] = {
            "costumeId": f"{entity_id}_COSTUME_{version}",
            "authorityImage": f"../../combat_hd_sources/renewed/{authority.name}",
            "authoritySha256": sha256(authority),
            "status": "CANDIDATE_GPT_COSTUME_CONTINUITY_PASS_DEV_RUNTIME",
            "review": {
                "verdict": "COSTUME_CONTINUITY_PASS",
                "surface": "existing_gpt_web_session",
                "checks": [
                    "adult_15_plus_sd_read",
                    "source_identity_hair_ornament_palette_role_weapon_preserved",
                    "distinct_face_body_pose_reviewed",
                    "transparent_cutout",
                    "complete_body_and_readable_hands_or_weapon",
                ],
            },
            "fingerprint": {
                "identityInvariant": f"adult {row.get('gender', 'female').lower()} {row.get('role', '').lower()}; original hair, screen-relative ornament, palette placement, role and weapon class retained",
                "silhouette": f"distinct {row.get('role', '').lower()} combat read reviewed against the active roster",
                "garmentModules": "premium high-resolution SD costume revision derived from the approved authority source",
                "coverage": "ADULT_NON_EXPLICIT_15_PLUS_COSTUME",
                "accessories": "source hair and screen-relative ornament placement locked",
                "weaponGrip": f"{row.get('weapon_class', 'SUPPORT_DEVICE')}_READABLE_GRIP_OR_SEPARATED_SUPPORT_DEVICE",
            },
        }
    document["schemaVersion"] = 2
    document["developmentCostumeOverrides"] = dict(sorted(overrides.items()))
    CONTRACT.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("promoted", ", ".join(f"{entity_id}:{version}" for entity_id, version in args.approved))


if __name__ == "__main__":
    main()
