"""Attach selected local-SDXL concepts to a Blender reference collection.

This does not render the images as final art. It creates a reproducible modeling
guide .blend whose objects are explicitly marked REFERENCE_ONLY.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy


def parse_args() -> argparse.Namespace:
    raw = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args(raw)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    args = parse_args()
    manifest_path = args.manifest.resolve()
    output_path = args.output.resolve()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("source_model", {}).get("krea2_used"):
        raise RuntimeError("Krea2 guide is NON_COMMERCIAL_EXCLUDED")
    if manifest.get("status") != "MODELING_REFERENCE_ONLY":
        raise RuntimeError("concept bridge manifest must remain reference-only")
    if not manifest.get("guides"):
        raise RuntimeError("no active concept guide passed the global visual policy")
    if manifest.get("content_policy", {}).get("character_gender") != "FEMALE_ONLY":
        raise RuntimeError("project-wide character policy must remain FEMALE_ONLY")
    if manifest.get("content_policy", {}).get("age_category") != "ADULT_ONLY":
        raise RuntimeError("project-wide character policy must remain ADULT_ONLY")
    if manifest.get("content_policy", {}).get("attire_policy") != "MAXIMUM_NON_EXPLICIT":
        raise RuntimeError("project-wide attire policy mismatch")
    if any(guide.get("character_gender") != "FEMALE" for guide in manifest.get("guides", [])):
        raise RuntimeError("FEMALE_ONLY policy violation in concept guide")
    required_verdicts = {"FEMALE_CONFIRMED", "ADULT_CONFIRMED", "ATTIRE_POLICY_CONFIRMED"}
    if any(not required_verdicts.issubset(set(guide.get("visual_qa_verdicts", []))) for guide in manifest.get("guides", [])):
        raise RuntimeError("concept guide blocked: all visual policy verdicts are required")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = "PILOT_CONCEPT_GUIDES_REFERENCE_ONLY"
    scene["LANTERNLINE_ASSET_STATUS"] = "MODELING_REFERENCE_ONLY"
    scene["RUNTIME_ASSET"] = False
    scene["RENDER_AS_FINAL"] = False
    scene["SOURCE_MODEL"] = manifest["source_model"]["id"]
    scene["SOURCE_MODEL_LICENSE"] = manifest["source_model"]["license"]
    scene["KREA2_USED"] = False
    scene["CHARACTER_GENDER_POLICY"] = "FEMALE_ONLY"
    scene["CHARACTER_AGE_POLICY"] = "ADULT_ONLY"
    scene["ATTIRE_POLICY"] = "MAXIMUM_NON_EXPLICIT"

    collection = bpy.data.collections.new("SDXL_CONCEPT_GUIDES_REFERENCE_ONLY")
    scene.collection.children.link(collection)
    base = manifest_path.parent
    for index, guide in enumerate(manifest["guides"]):
        image_path = (base / guide["path"]).resolve()
        if not image_path.is_file():
            raise RuntimeError(f"missing concept guide: {image_path}")
        actual_hash = sha256(image_path)
        if actual_hash != guide["sha256"]:
            raise RuntimeError(f"concept SHA-256 mismatch: {guide['guide_id']}")
        image = bpy.data.images.load(str(image_path), check_existing=False)
        image.name = guide["guide_id"] + "_IMAGE"
        image.filepath = bpy.path.relpath(str(image_path))
        empty = bpy.data.objects.new(guide["guide_id"] + "_REFERENCE_ONLY", None)
        empty.empty_display_type = "IMAGE"
        empty.data = image
        empty.empty_display_size = 5.0
        empty.color[3] = 1.0
        empty.location = (index * 6.0, 0.0, 0.0)
        empty["ASSET_STATUS"] = "MODELING_REFERENCE_ONLY"
        empty["CHARACTER_ID"] = guide["character_id"]
        empty["CHARACTER_GENDER"] = "FEMALE"
        empty["QA_VERDICT"] = guide["qa_verdict"]
        empty["RUNTIME_ASSET"] = False
        empty["RENDER_AS_FINAL"] = False
        empty["REQUIRED_CHANGES"] = json.dumps(guide["required_changes"], ensure_ascii=False)
        collection.objects.link(empty)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output_path))
    print(
        json.dumps(
            {
                "status": "MODELING_REFERENCE_ONLY",
                "guides": len(manifest["guides"]),
                "output": str(output_path),
                "krea2_used": False,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
