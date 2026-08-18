from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from common import BLENDER_VERSION, FACTORY_VERSION, build_character, clear_scene, material, render, save_json, setup_render


def args_after_dash() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--stage", choices=("silhouettes", "full"), default="silhouettes")
    parser.add_argument("--seed", type=int, default=471001)
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(values)


def build_silhouettes(root: Path, seed: int) -> None:
    output = root / "godot" / "assets" / "art" / "qa" / "silhouettes"
    rows = []
    for character in ("CHR001", "CHR008"):
        for variant in (1, 2, 3):
            clear_scene()
            scene = setup_render(512, 768, transparent=False, camera_location=(7.4, -13.8, 5.2),
                                 camera_target=(0.0, 0.0, 3.05), ortho_scale=7.4, samples=16,
                                 world=(0.88, 0.88, 0.84))
            black = material("qa_silhouette", (0.001, 0.001, 0.001, 1.0), roughness=1.0)
            role_pose = ({"arm_raise_l": 0.15 + 0.05 * variant,
                          "arm_raise_r": 0.28 + 0.06 * variant,
                          "hand_out_l": 0.22,
                          "hand_out_r": 0.02}
                         if character == "CHR001" else
                         {"arm_raise_l": 0.02,
                          "arm_raise_r": 0.42 + 0.05 * variant,
                          "hand_out_l": 0.08,
                          "hand_out_r": -0.08})
            role_pose.update({"leg_spread": 0.06 * (variant - 2),
                              "stride": 0.18 * (variant - 2)})
            build_character(character, variant=variant, silhouette=True, pose=role_pose)
            scene.view_layers[0].material_override = black
            path = output / f"{character.lower()}_silhouette_v{variant}.png"
            render(path)
            rows.append({"character_id": character, "variant": variant, "path": path.relative_to(root).as_posix(),
                         "seed": seed + variant, "status": "PREMIUM_PILOT"})
    source_dir = root / "tools" / "premium_asset_factory" / "blender_sources" / "premium" / "silhouettes"
    source_dir.mkdir(parents=True, exist_ok=True)
    save_json(output / "silhouette_manifest.json", {
        "schema_version": 1,
        "generator_version": FACTORY_VERSION,
        "blender_version": BLENDER_VERSION,
        "seed": seed,
        "status": "PREMIUM_PILOT",
        "variants": rows,
    })
    # Library write avoids Blender's temporary `.blend@` path, which can be
    # denied by managed Windows workspaces even when the final path is writable.
    datablocks = set(bpy.data.objects) | set(bpy.data.materials) | set(bpy.data.scenes)
    bpy.data.libraries.write(str(source_dir / "pilot_silhouettes.blend"), datablocks,
                             path_remap="RELATIVE", fake_user=True, compress=True)


def main() -> int:
    options = args_after_dash()
    root = Path(options.project_root).resolve()
    if not (root / "godot" / "project.godot").is_file():
        print("project.godot missing", file=sys.stderr)
        return 2
    if options.stage == "silhouettes":
        build_silhouettes(root, options.seed)
    else:
        print("Full pilot stage is implemented by the specialized batch entry points.", file=sys.stderr)
        return 3
    print(f"PREMIUM_PILOT_STAGE={options.stage} BLENDER={BLENDER_VERSION} FACTORY={FACTORY_VERSION}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
