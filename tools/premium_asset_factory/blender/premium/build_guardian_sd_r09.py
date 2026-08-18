from __future__ import annotations

import argparse
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from common import (
    assign,
    bevel,
    capsule,
    clear_scene,
    cone,
    cube,
    curve_line,
    front_prism,
    material,
    render,
    setup_render,
    sha256,
    smooth,
    torus,
    uv,
)


FACTORY_REVISION = "guardian-sd-r09-0.1.0"


def args_after_dash() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(values)


def lashes(name: str, x: float, z: float, dark) -> None:
    direction = -1.0 if x < 0 else 1.0
    curve_line(name, [
        (x - 0.18 * direction, -0.824, z + 0.01),
        (x, -0.848, z + 0.055),
        (x + 0.18 * direction, -0.818, z + 0.01),
    ], 0.032, dark)
    curve_line(name + "_tip", [
        (x + 0.17 * direction, -0.820, z + 0.015),
        (x + 0.25 * direction, -0.805, z + 0.095),
    ], 0.026, dark)


def hair_lock(name: str, points, radius: float, hair) -> None:
    curve_line(name, points, radius, hair)
    uv(name + "_tip", points[-1], (radius * 1.15, radius * 0.72, radius * 1.7), hair, 20, 10)


def build_character(root: Path) -> tuple[Path, Path, Path]:
    clear_scene()
    scene = setup_render(
        768,
        768,
        transparent=True,
        camera_location=(7.2, -14.5, 6.2),
        camera_target=(-0.05, 0.0, 3.15),
        ortho_scale=7.15,
        samples=64,
        world=(0.018, 0.028, 0.060),
    )
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = "RGBA"

    skin = material("r09_skin", (0.96, 0.58, 0.48, 1.0), roughness=0.62)
    skin_light = material("r09_skin_light", (1.0, 0.72, 0.62, 1.0), roughness=0.58)
    teal = material("r09_teal_armor", (0.015, 0.42, 0.43, 1.0), metallic=0.34, roughness=0.24)
    teal_dark = material("r09_teal_dark", (0.008, 0.09, 0.13, 1.0), metallic=0.24, roughness=0.34)
    teal_glow = material("r09_teal_glow", (0.02, 0.92, 0.82, 1.0), metallic=0.10, roughness=0.18, emission=2.4)
    gold = material("r09_gold", (0.92, 0.45, 0.06, 1.0), metallic=0.78, roughness=0.20)
    gold_light = material("r09_gold_light", (1.0, 0.73, 0.20, 1.0), metallic=0.64, roughness=0.18)
    navy = material("r09_navy_cloth", (0.018, 0.035, 0.090, 1.0), roughness=0.72)
    hair = material("r09_chestnut_hair", (0.20, 0.035, 0.018, 1.0), roughness=0.38)
    hair_light = material("r09_hair_highlight", (0.55, 0.12, 0.035, 1.0), roughness=0.32)
    eye_white = material("r09_eye_white", (0.98, 0.99, 1.0, 1.0), roughness=0.20)
    iris = material("r09_cyan_iris", (0.01, 0.70, 0.95, 1.0), roughness=0.15, emission=1.6)
    pupil = material("r09_pupil", (0.004, 0.008, 0.020, 1.0), roughness=0.28)
    mouth = material("r09_mouth", (0.42, 0.015, 0.035, 1.0), roughness=0.55)
    shield_brown = material("r09_shield_inlay", (0.18, 0.055, 0.025, 1.0), metallic=0.18, roughness=0.48)

    # Adult SD proportions: large head for combat readability with an adult armor silhouette.
    # Boots and legs.
    for side, x in (("L", -0.33), ("R", 0.43)):
        foot_y = -0.18 if side == "L" else -0.10
        cube(f"{side}_boot", (x, foot_y, 0.33), (0.30, 0.48, 0.29), teal_dark, bevel_width=0.11)
        capsule(f"{side}_calf", (x, 0.0, 0.55), (x + (0.03 if side == "R" else -0.02), 0.02, 1.34), 0.245, teal)
        front_prism(f"{side}_knee_gold", (x, -0.29, 1.28), 0.25, 0.27, 0.075, gold, vertices=5)
        capsule(f"{side}_thigh", (x, 0.02, 1.40), (x * 0.74, 0.02, 2.14), 0.315, skin_light)
        # High-cut opaque hip armor keeps the exposed thigh readable without nudity.
        front_prism(f"{side}_hip_plate", (x * 0.70, -0.19, 2.14), 0.33, 0.42, 0.095, teal, vertices=6,
                    rotation_z=(-0.12 if side == "L" else 0.12))

    cone("opaque_lower_bodysuit", (0.04, 0.04, 2.20), 0.57, 0.43, 0.72, navy, vertices=32)
    torus("hip_gold_ring", (0.04, -0.02, 2.34), 0.53, 0.055, gold, rotation=(0.0, 0.0, 0.0))
    # Narrow exposed waist and layered opaque bust armor establish a mature heroine read.
    cone("waist", (0.04, 0.02, 2.72), 0.36, 0.46, 0.72, skin, vertices=40)
    cone("torso_bodice", (0.04, 0.05, 3.20), 0.48, 0.62, 0.86, teal_dark, vertices=40)
    for side, x in (("L", -0.28), ("R", 0.36)):
        uv(f"{side}_bust_plate", (x, -0.38, 3.36), (0.38, 0.22, 0.34), teal, 36, 18)
        front_prism(f"{side}_bust_gold", (x, -0.57, 3.39), 0.25, 0.22, 0.055, gold_light, vertices=6,
                    rotation_z=(-0.14 if side == "L" else 0.14))
    front_prism("sternum_guard", (0.04, -0.57, 3.06), 0.26, 0.42, 0.06, gold, vertices=5)
    torus("collar", (0.04, -0.01, 3.70), 0.46, 0.055, gold, rotation=(0.0, 0.0, 0.0))

    # Open shoulders, asymmetric bracers, and grounded hands.
    shoulder_z = 3.58
    left_points = ((-0.51, 0.0, shoulder_z), (-0.83, -0.10, 3.03), (-1.07, -0.42, 2.53))
    right_points = ((0.58, 0.0, shoulder_z), (0.91, -0.12, 3.08), (0.73, -0.46, 2.48))
    for side, pts in (("L", left_points), ("R", right_points)):
        capsule(f"{side}_upper_arm", pts[0], pts[1], 0.22, skin_light)
        capsule(f"{side}_forearm", pts[1], pts[2], 0.205, teal_dark)
        uv(f"{side}_hand", pts[2], (0.23, 0.16, 0.27), skin_light, 28, 14)
        front_prism(f"{side}_shoulder", (pts[0][0], -0.13, shoulder_z + 0.02), 0.36, 0.28, 0.10, gold, vertices=6)
        torus(f"{side}_bracer_ring", pts[1], 0.225, 0.043, gold, rotation=(0.0, 0.0, 0.0))

    # Face, eyes, brows, lashes, nose and mouth.
    capsule("neck", (0.04, 0.0, 3.66), (0.04, 0.0, 3.99), 0.22, skin)
    uv("adult_sd_face", (0.04, -0.03, 4.58), (0.82, 0.70, 0.82), skin_light, 64, 32)
    for side, x in (("L", -0.27), ("R", 0.35)):
        uv(f"{side}_eye_white", (x, -0.695, 4.69), (0.245, 0.055, 0.155), eye_white, 32, 16)
        uv(f"{side}_iris", (x, -0.747, 4.68), (0.105, 0.029, 0.120), iris, 28, 14)
        uv(f"{side}_pupil", (x, -0.772, 4.68), (0.043, 0.016, 0.073), pupil, 20, 10)
        uv(f"{side}_catch", (x - 0.035, -0.790, 4.735), (0.025, 0.010, 0.032), eye_white, 16, 8)
        lashes(f"{side}_lashes", x, 4.69, pupil)
    curve_line("left_brow", [(-0.50, -0.714, 4.94), (-0.27, -0.748, 4.99), (-0.08, -0.724, 4.96)], 0.035, hair)
    curve_line("right_brow", [(0.16, -0.724, 4.96), (0.37, -0.748, 4.99), (0.57, -0.714, 4.94)], 0.035, hair)
    uv("nose", (0.04, -0.724, 4.49), (0.060, 0.050, 0.085), skin, 20, 10)
    curve_line("confident_smile", [(-0.12, -0.742, 4.33), (0.04, -0.765, 4.27), (0.20, -0.742, 4.33)], 0.032, mouth)

    # Layered hair cap, cheek framing, long back mass and high ponytail.
    uv("hair_back", (0.05, 0.18, 4.62), (0.91, 0.75, 0.96), hair, 56, 28)
    uv("hair_crown", (0.04, -0.00, 4.91), (0.86, 0.70, 0.61), hair, 56, 28)
    for index, x in enumerate((-0.58, -0.37, -0.16, 0.07, 0.30, 0.52)):
        end_x = x * 1.06 + (0.04 if x < 0 else -0.02)
        hair_lock(f"bang_{index}", [(x, -0.56, 5.24), (x * 0.94, -0.73, 4.98), (end_x, -0.70, 4.66)], 0.075, hair)
    hair_lock("left_face_lock", [(-0.66, -0.25, 5.05), (-0.76, -0.48, 4.48), (-0.61, -0.34, 3.92)], 0.105, hair)
    hair_lock("right_face_lock", [(0.72, -0.22, 5.05), (0.83, -0.44, 4.48), (0.69, -0.29, 3.86)], 0.105, hair)
    uv("ponytail_knot", (0.56, 0.55, 5.20), (0.28, 0.30, 0.30), gold, 28, 14)
    for index, offset in enumerate((-0.26, 0.0, 0.25)):
        hair_lock(f"ponytail_{index}", [(0.57 + offset * 0.2, 0.55, 5.18), (1.02 + offset, 0.43, 4.74),
                                         (1.18 + offset * 1.4, 0.18, 3.82 - abs(offset) * 0.35)], 0.145, hair)
    hair_lock("hair_highlight", [(-0.42, -0.60, 5.18), (-0.21, -0.72, 4.94), (-0.14, -0.70, 4.75)], 0.026, hair_light)

    # Guardian shield: independent silhouette with layered metal, inlay, core and handle cue.
    shield_x = -1.63
    front_prism("shield_outer", (shield_x, -0.10, 2.72), 0.92, 1.48, 0.18, gold, vertices=8, rotation_z=-0.03)
    front_prism("shield_body", (shield_x, -0.35, 2.72), 0.79, 1.30, 0.15, teal, vertices=8, rotation_z=-0.03)
    front_prism("shield_inlay", (shield_x, -0.51, 2.72), 0.55, 0.92, 0.055, shield_brown, vertices=8, rotation_z=-0.03)
    torus("shield_core_ring", (shield_x, -0.59, 2.75), 0.33, 0.085, gold_light)
    uv("shield_core", (shield_x, -0.66, 2.75), (0.22, 0.055, 0.28), teal_glow, 32, 16)
    for z in (1.68, 3.80):
        uv(f"shield_rivet_{z}", (shield_x, -0.61, z), (0.095, 0.045, 0.095), gold_light, 20, 10)

    # Rear split cape, readable beyond both legs.
    cone("cape_left", (-0.25, 0.34, 2.36), 0.45, 0.30, 2.05, teal_dark,
         rotation=(0.08, 0.12, 0.10), vertices=5)
    cone("cape_right", (0.43, 0.36, 2.32), 0.45, 0.30, 2.10, teal,
         rotation=(0.08, -0.12, -0.10), vertices=5)

    output = root / "work" / "art_gen" / "blender_guardian_sd_r09"
    output.mkdir(parents=True, exist_ok=True)
    transparent_path = output / "chr001_maeru_guardian_sd_r09_transparent.png"
    qa_path = output / "chr001_maeru_guardian_sd_r09_qa.png"
    blend_path = root / "tools" / "premium_asset_factory" / "blender_sources" / "premium" / "guardian_r09" / "chr001_maeru_guardian_sd_r09.blend"
    blend_path.parent.mkdir(parents=True, exist_ok=True)

    render(transparent_path)
    scene.render.film_transparent = False
    scene.world.color = (0.028, 0.038, 0.072)
    render(qa_path)

    datablocks = set(bpy.data.objects) | set(bpy.data.materials) | set(bpy.data.scenes) | set(bpy.data.worlds)
    bpy.data.libraries.write(str(blend_path), datablocks, path_remap="RELATIVE", fake_user=True, compress=True)
    return transparent_path, qa_path, blend_path


def main() -> int:
    options = args_after_dash()
    root = Path(options.project_root).resolve()
    if not (root / "godot" / "project.godot").is_file():
        raise SystemExit("project.godot missing")
    transparent_path, qa_path, blend_path = build_character(root)
    manifest_path = transparent_path.parent / "guardian_sd_r09_manifest.json"
    manifest = {
        "kind": "BLENDER_ORIGINAL_GUARDIAN_SD_PILOT_R09",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "factory_revision": FACTORY_REVISION,
        "blender_version": bpy.app.version_string,
        "character_id": "CHR001",
        "character_gender": "FEMALE",
        "age_category": "ADULT",
        "attire_policy": "MAXIMUM_NON_EXPLICIT",
        "facing_policy": "MIRROR_SAFE",
        "status": "ART_QA_CANDIDATE",
        "production_approved": False,
        "runtime_asset": False,
        "source_type": "PROJECT_AUTHORED_PROCEDURAL_BLENDER",
        "krea2_used": False,
        "external_model_weights_used": False,
        "foot_anchor": [0.5, 0.88],
        "files": [
            {"path": transparent_path.relative_to(root).as_posix(), "sha256": sha256(transparent_path), "bytes": transparent_path.stat().st_size},
            {"path": qa_path.relative_to(root).as_posix(), "sha256": sha256(qa_path), "bytes": qa_path.stat().st_size},
            {"path": blend_path.relative_to(root).as_posix(), "sha256": sha256(blend_path), "bytes": blend_path.stat().st_size},
        ],
        "qa_verdict": "UNREVIEWED",
        "integration_allowed": False,
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"manifest": str(manifest_path), "qa": str(qa_path), "blend": str(blend_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
