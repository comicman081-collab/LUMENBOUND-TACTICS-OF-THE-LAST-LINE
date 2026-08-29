#!/usr/bin/env python3
"""Build the reviewed contract for CHR009-CHR044 8-head card art.

The generated green-matte/RGBA pairs are bound to each character's existing
authority image and objective alpha/key-green QA.  Runtime promotion is allowed
only because the exact four comparison sheets were approved in the existing
in-app ChatGPT continuity-review session on 2026-08-29.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
CARD_ROOT = ROOT / "data_source" / "art_source" / "card_8head_green_matte_r1"
STANDING_CONTRACT = (
    ROOT
    / "data_source"
    / "art_source"
    / "standing_green_matte_r2"
    / "qa"
    / "STANDING_RGBA_R2_CONTRACT.json"
)
OUTPUT = CARD_ROOT / "qa" / "CARD_8HEAD_CANDIDATE_CONTRACT.json"
REVIEW_SESSION_URL = "https://chatgpt.com/c/6a8c3496-05b0-83e9-b69f-c29b70a61300"
REVIEWED_AT = "2026-08-29"
APPROVED_STATUS = "CONTINUITY_APPROVED_PENDING_RUNTIME_PROMOTION"

NAMES_AND_ROLES = {
    9: ("LIV", "VANGUARD"), 10: ("SEON", "MEDIC"),
    11: ("ADELINE", "ARTILLERY"), 12: ("KIR", "SPECIALIST"),
    13: ("REMA", "GUARDIAN"), 14: ("VEON", "ASSAULT"),
    15: ("HART", "ARTILLERY"), 16: ("ORSA", "GUARDIAN"),
    17: ("TIEL", "MEDIC"), 18: ("RIAS", "ASSAULT"),
    19: ("PERIN", "SPECIALIST"), 20: ("KARN", "VANGUARD"),
    21: ("NOAR", "MEDIC"), 22: ("SEB", "VANGUARD"),
    23: ("YURIEN", "ARTILLERY"), 24: ("MOEN", "SPECIALIST"),
    25: ("LAVENT", "GUARDIAN"), 26: ("KAIREN", "ASSAULT"),
    27: ("INOA", "SPECIALIST"), 28: ("DRAN", "VANGUARD"),
    29: ("MERIN", "MEDIC"), 30: ("CIEL", "ARTILLERY"),
    31: ("ROME", "GUARDIAN"), 32: ("KIAN", "ASSAULT"),
    33: ("DAEL", "SPECIALIST"), 34: ("ORBIN", "GUARDIAN"),
    35: ("HERAON", "ARTILLERY"), 36: ("MIRE", "MEDIC"),
    37: ("RAEN", "VANGUARD"), 38: ("ZERN", "ASSAULT"),
    39: ("SOA", "SPECIALIST"), 40: ("BAEL", "MEDIC"),
    41: ("TERAN", "VANGUARD"), 42: ("YUNAK", "ARTILLERY"),
    43: ("ARINT", "GUARDIAN"), 44: ("VELK", "ASSAULT"),
}

# Explicit side-by-side SD-authority review rejected the first CHR009-013 and
# CHR016 candidates. Their listed revisions are individual reference-locked
# replacements; CHR031/034 use their second composition passes.
REVISIONS = {9: 6, 10: 2, 11: 2, 12: 2, 13: 2, 16: 2, 31: 2, 34: 2}


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def alpha_metrics(path: Path) -> dict:
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError(f"No visible pixels in {path}")
    width, height = image.size
    left, top, right, bottom = bbox
    visible_key_green = sum(
        1
        for red, green, blue, opacity in image.getdata()
        if opacity > 0 and red <= 12 and green >= 243 and blue <= 12
    )
    return {
        "size": [width, height],
        "alphaExtrema": list(alpha.getextrema()),
        "alphaBbox": [left, top, right, bottom],
        "safeInsets": [left, top, width - right, height - bottom],
        "visibleKeyGreenPixels": visible_key_green,
    }


def main() -> None:
    standing = json.loads(STANDING_CONTRACT.read_text(encoding="utf-8"))["characters"]
    candidates = {}
    for index in range(9, 45):
        entity_id = f"CHR{index:03d}"
        revision = REVISIONS.get(index, 1)
        stem = f"chr{index:03d}_8head_card_r{revision}_imagegen_safe"
        green = CARD_ROOT / entity_id / f"{stem}_green_matte.png"
        rgba = CARD_ROOT / entity_id / f"{stem}_rgba.png"
        qa = (
            ROOT
            / "builds"
            / "qa"
            / f"card_8head_chr{index:03d}_r{revision}_alpha_contact.png"
        )
        for required in (green, rgba, qa):
            if not required.is_file():
                raise FileNotFoundError(required)

        authority = ROOT / standing[entity_id]["authorityImage"]
        if not authority.is_file():
            raise FileNotFoundError(authority)
        authority_hash = sha256(authority)
        if authority_hash != standing[entity_id]["authoritySha256"]:
            raise ValueError(f"{entity_id} authority hash drift")

        metrics = alpha_metrics(rgba)
        if metrics["alphaExtrema"] != [0, 255]:
            raise ValueError(f"{entity_id} requires real transparent RGBA")
        if metrics["visibleKeyGreenPixels"] != 0:
            raise ValueError(f"{entity_id} retains visible key green")
        if min(metrics["safeInsets"]) < 72:
            raise ValueError(f"{entity_id} safe inset is below 72px: {metrics['safeInsets']}")

        name, role = NAMES_AND_ROLES[index]
        candidates[entity_id] = {
            "characterName": name,
            "combatRole": role,
            "cardFamily": "PREMIUM_8_HEAD_FULL_BODY_CARD",
            "identityReference": relative(authority),
            "identityReferenceSha256": authority_hash,
            "costumeId": standing[entity_id]["costumeId"],
            "identityLock": {
                "faceHairSilhouette": "must match identity reference",
                "costumeAndWeapon": "must match identity reference",
                "allowedChange": "adult 8-head proportion and premium card rendering only",
            },
            "generationMatte": "#00FF00",
            "greenMatteCandidate": relative(green),
            "greenMatteCandidateSha256": sha256(green),
            "rgbaCandidate": relative(rgba),
            "rgbaCandidateSha256": sha256(rgba),
            "alphaQaSheet": relative(qa),
            "alphaQa": metrics,
            "generation": "OPENAI_IMAGEGEN_INDIVIDUAL_AUTHORITY_REFERENCE_GREEN_MATTE",
            "continuityReview": {
                "reviewer": "IN_APP_CHATGPT_EXISTING_SESSION",
                "sessionUrl": REVIEW_SESSION_URL,
                "reviewedAt": REVIEWED_AT,
                "result": "COSTUME_CONTINUITY_PASS",
            },
            "status": APPROVED_STATUS,
        }

    document = {
        "schemaVersion": 2,
        "generationMatte": "#00FF00",
        "runtimeBackground": "RGBA_TRANSPARENT_REQUIRED",
        "coverage": "CHR009-CHR044",
        "reviewPolicy": "NO_RUNTIME_PROMOTION_BEFORE_IN_APP_GPT_CONTINUITY_APPROVAL",
        "batchReview": {
            "reviewer": "IN_APP_CHATGPT_EXISTING_SESSION",
            "sessionUrl": REVIEW_SESSION_URL,
            "reviewedAt": REVIEWED_AT,
            "comparisonSheets": [
                "builds/qa/card_8head_identity_review/CARD_8HEAD_SD_AUTHORITY_COMPARE_CHR009_CHR017.jpg",
                "builds/qa/card_8head_identity_review/CARD_8HEAD_SD_AUTHORITY_COMPARE_CHR018_CHR026.jpg",
                "builds/qa/card_8head_identity_review/CARD_8HEAD_SD_AUTHORITY_COMPARE_CHR027_CHR035.jpg",
                "builds/qa/card_8head_identity_review/CARD_8HEAD_SD_AUTHORITY_COMPARE_CHR036_CHR044.jpg",
            ],
            "characterContinuity": "PASS_36_OF_36",
            "batchDistinctness": "PASS",
            "greenKeyPipeline": "PASS",
        },
        "candidates": candidates,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"CARD_8HEAD_APPROVED_CONTRACT={relative(OUTPUT)}|count={len(candidates)}")


if __name__ == "__main__":
    main()
