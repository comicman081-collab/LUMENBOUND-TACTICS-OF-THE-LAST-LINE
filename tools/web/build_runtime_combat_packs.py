"""Build the small, Web-safe combat runtime packs from preserved source art.

The files in assets/art and assets/generated_import are authoring/source packs.
They remain untouched and are deliberately excluded from the Web PCK.  This
bridge makes a compact atlas for the seven currently playable combat IDs and
the projectile/VFX packs used by the R7 battle view.  It is deterministic and
can overwrite only its own runtime_web output.
"""
from __future__ import annotations

import hashlib
import json
import math
import shutil
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "godot"
OUTPUT = GODOT / "assets" / "runtime_web"
COMBAT_OUTPUT = OUTPUT / "combat"
PROJECTILE_OUTPUT = OUTPUT / "projectiles"
VFX_OUTPUT = OUTPUT / "vfx"
# 104px preserves full pose timing while keeping every connected player and
# enemy pack inside the single-file Web hosting ceiling.  BattleView continues
# to render at its authored world size, so this only affects texture density
# rather than unit placement or simulation state.
CELL = 104
# Single-render bridge assets are deliberately lower density than the authored
# multi-frame sources. They are used on the enemy half of a 1920px battlefield
# and need to keep all eleven enemy IDs Web-deliverable until the corresponding
# Blender animation packs are complete.
STATIC_CELL = 68
PROJECTILE_CELL = 96
# VFX is rendered briefly at a much smaller on-screen area than its source
# canvas.  A 112px atlas keeps the full, authored VFX sequence in the Web PCK
# without forcing the browser delivery artifact over its per-file ceiling.
VFX_CELL = 112
ATLAS_COLUMNS = 10

COMBAT_SOURCES = {
    "CHR001": GODOT / "assets" / "art" / "sd" / "CHR001",
    "CHR002": GODOT / "assets" / "generated_import" / "characters" / "sd_chr002_roan_combat_r27_dev",
    "CHR003": GODOT / "assets" / "generated_import" / "characters" / "sd_chr003_narin_combat_r27_dev",
    "CHR004": GODOT / "assets" / "generated_import" / "characters" / "sd_chr004_eda_combat_r27_dev",
    "CHR005": GODOT / "assets" / "generated_import" / "characters" / "sd_chr005_soren_combat_r27_dev",
    "ENM001": GODOT / "assets" / "art" / "enemies" / "ENM001",
    "ENM002": GODOT / "assets" / "generated_import" / "enemies" / "sd_enm002_arc_mote_combat_r28_dev",
    "ENM007": GODOT / "assets" / "art" / "enemies" / "ENM007",
    "BOSS001": GODOT / "assets" / "art" / "bosses" / "BOSS001",
}

# These are deliberately kept separate from COMBAT_SOURCES: the authoring
# roots above already contain authored multi-frame animation packs, while the
# following enemy originals are single-frame transparent renders.  The bridge
# derives a small, deterministic presentation pack from each original so the
# Web runtime never falls back to the old code-drawn placeholder.  They are
# not represented as hand-authored premium animation; the manifest makes that
# provenance explicit for later Blender replacement work.
STATIC_COMBAT_SOURCES = {
    "ENM003": {
        "source": ROOT / "data_source" / "art_source" / "imagegen_enemy_sources" / "ENM003_shell_relay_source.png",
        "asset_id": "imggen_enm003_shell_relay_r7",
        "name": "Shell Relay",
        "view": "THREE_QUARTER_LEFT_DOWN_30",
        "facing": "MIRROR_SAFE",
        "foot_anchor": [0.5, 0.88],
        "head_anchor": [0.5, 0.15],
    },
    "ENM004": {
        "source": ROOT / "data_source" / "art_source" / "imagegen_enemy_sources" / "ENM004_mend_echo_source.png",
        "asset_id": "imggen_enm004_mend_echo_r7",
        "name": "Mend Echo",
        "view": "THREE_QUARTER_LEFT_DOWN_30",
        "facing": "MIRROR_SAFE",
        "foot_anchor": [0.5, 0.88],
        "head_anchor": [0.5, 0.18],
    },
    "ENM005": {
        "source": ROOT / "data_source" / "art_source" / "imagegen_enemy_sources" / "ENM005_signal_jammer_source.png",
        "asset_id": "imggen_enm005_signal_jammer_r7",
        "name": "Signal Jammer",
        "view": "THREE_QUARTER_LEFT_DOWN_30",
        "facing": "MIRROR_SAFE",
        "foot_anchor": [0.5, 0.88],
        "head_anchor": [0.5, 0.16],
    },
    "ENM006": {
        "source": ROOT / "data_source" / "art_source" / "imagegen_enemy_sources" / "ENM006_dust_lens_source.png",
        "asset_id": "imggen_enm006_dust_lens_r7",
        "name": "Dust Lens",
        "view": "THREE_QUARTER_LEFT_DOWN_30",
        "facing": "MIRROR_SAFE",
        "foot_anchor": [0.5, 0.88],
        "head_anchor": [0.5, 0.2],
    },
    "ENM008": {
        "source": ROOT / "data_source" / "art_source" / "imagegen_enemy_sources" / "ENM008_broadcast_pylon_source.png",
        "asset_id": "imggen_enm008_broadcast_pylon_r7",
        "name": "Broadcast Pylon",
        "view": "THREE_QUARTER_LEFT_DOWN_30",
        "facing": "MIRROR_SAFE",
        "foot_anchor": [0.5, 0.88],
        "head_anchor": [0.5, 0.12],
    },
    "ENM009": {
        "source": ROOT / "data_source" / "art_source" / "imagegen_enemy_sources" / "ENM009_fortress_turtle_source.png",
        "asset_id": "imggen_enm009_fortress_turtle_r7",
        "name": "Fortress Turtle",
        "view": "THREE_QUARTER_LEFT_DOWN_30",
        "facing": "MIRROR_SAFE",
        "foot_anchor": [0.5, 0.88],
        "head_anchor": [0.5, 0.2],
    },
    "BOSS002": {
        "source": ROOT / "data_source" / "art_source" / "imagegen_enemy_sources" / "BOSS002_night_bell_engine_source.png",
        "asset_id": "imggen_boss002_night_bell_engine_r7",
        "name": "Night Bell Engine",
        "view": "THREE_QUARTER_LEFT_DOWN_30",
        "facing": "MIRROR_SAFE",
        "foot_anchor": [0.5, 0.88],
        "head_anchor": [0.5, 0.11],
    },
}

PROJECTILE_SOURCES = {
    "CHR001": GODOT / "assets" / "generated_import" / "projectiles" / "proj_chr001_teal_guard_wave_r28",
    "CHR002": GODOT / "assets" / "generated_import" / "projectiles" / "proj_chr002_coral_blade_arc_r28",
    "CHR003": GODOT / "assets" / "generated_import" / "projectiles" / "proj_chr003_ice_rifle_tracer_r28",
    "CHR004": GODOT / "assets" / "generated_import" / "projectiles" / "proj_chr004_magenta_energy_bolt_r28",
    "CHR005": GODOT / "assets" / "generated_import" / "projectiles" / "proj_chr005_emerald_cannon_orb_r28",
    "ENM001": GODOT / "assets" / "generated_import" / "projectiles" / "proj_enm001_crystal_claw_r28",
    "ENM002": GODOT / "assets" / "generated_import" / "projectiles" / "proj_enm002_arc_mote_r28",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def prepare_output(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def image_cell(source: Path, size: int) -> Image.Image:
    image = Image.open(source).convert("RGBA")
    if image.size != (size, size):
        image = image.resize((size, size), Image.Resampling.LANCZOS)
    return image


def _static_base_canvas(source: Path) -> Image.Image:
    """Fit a transparent generated source into a stable 512px battle canvas."""
    image = Image.open(source).convert("RGBA")
    alpha_bbox = image.getchannel("A").getbbox()
    if alpha_bbox is None:
        raise ValueError(f"Static combat source has no visible pixels: {source}")
    # Keep any glow that sits just outside the opaque body, but avoid allowing
    # the generator's large transparent canvas to make the unit unreadably
    # small in battle.
    padding = max(12, int(max(image.size) * 0.03))
    left = max(0, alpha_bbox[0] - padding)
    top = max(0, alpha_bbox[1] - padding)
    right = min(image.width, alpha_bbox[2] + padding)
    bottom = min(image.height, alpha_bbox[3] + padding)
    cropped = image.crop((left, top, right, bottom))
    cropped.thumbnail((448, 432), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    x = (512 - cropped.width) // 2
    y = 451 - cropped.height
    canvas.alpha_composite(cropped, (x, max(8, y)))
    return canvas


def _static_frame(base: Image.Image, animation: str, frame: int, count: int) -> Image.Image:
    """Create restrained presentation motion without changing simulation timing.

    The battle simulation remains the authority for attacks/hits.  These
    transforms exist only to prevent a static original render from looking
    frozen while its authored replacement is pending.
    """
    phase = (float(frame) / max(1, count)) * math.tau
    bob = int(round(math.sin(phase) * (3 if animation in ("idle", "move") else 1)))
    stride = int(round(math.sin(phase) * (5 if animation == "move" else 0)))
    angle = 0.0
    lunge = 0
    if animation == "basic_attack":
        progress = frame / max(1, count - 1)
        lunge = int(round(math.sin(progress * math.pi) * 18))
        angle = -5.0 * math.sin(progress * math.pi)
    elif animation == "normal_skill":
        progress = frame / max(1, count - 1)
        lunge = int(round(math.sin(progress * math.pi) * 12))
        angle = -8.0 * math.sin(progress * math.pi)
    elif animation == "ultimate":
        progress = frame / max(1, count - 1)
        lunge = int(round(math.sin(progress * math.pi) * 22))
        angle = -10.0 * math.sin(progress * math.pi)
    elif animation == "hit":
        progress = frame / max(1, count - 1)
        lunge = -int(round(math.sin(progress * math.pi) * 12))
        angle = 6.0 * math.sin(progress * math.pi)
    elif animation == "down":
        progress = frame / max(1, count - 1)
        angle = 70.0 * progress
        bob = int(round(38 * progress))
    elif animation == "victory":
        bob = int(round(abs(math.sin(phase)) * -9))
        angle = -3.5 * math.sin(phase)
    transformed = base.rotate(angle, resample=Image.Resampling.BICUBIC, center=(256, 451), fillcolor=(0, 0, 0, 0))
    output = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    output.alpha_composite(transformed, (stride + lunge, bob))
    return output


def build_static_combat_pack(entity_id: str, definition: dict) -> dict:
    source: Path = definition["source"]
    if not source.is_file():
        raise FileNotFoundError(f"{entity_id} static combat source missing: {source}")
    target_root = COMBAT_OUTPUT / entity_id
    prepare_output(target_root)
    base = _static_base_canvas(source)
    layout = {
        "idle": (8, True), "move": (12, True), "basic_attack": (8, False),
        "normal_skill": (12, False), "ultimate": (18, False), "hit": (4, False),
        "down": (8, False), "victory": (10, False), "stun": (4, True),
    }
    all_frames: list[Image.Image] = []
    animations: dict = {}
    for animation, (count, loop) in layout.items():
        motion_name = "hit" if animation == "stun" else animation
        indices = list(range(len(all_frames), len(all_frames) + count))
        all_frames.extend(_static_frame(base, motion_name, frame, count) for frame in range(count))
        animations[animation] = {"fps": 12, "loop": loop, "frame_indices": indices}
    rows = (len(all_frames) + ATLAS_COLUMNS - 1) // ATLAS_COLUMNS
    atlas = Image.new("RGBA", (ATLAS_COLUMNS * STATIC_CELL, rows * STATIC_CELL), (0, 0, 0, 0))
    for index, frame_image in enumerate(all_frames):
        frame_image.thumbnail((STATIC_CELL, STATIC_CELL), Image.Resampling.LANCZOS)
        atlas.alpha_composite(frame_image, ((index % ATLAS_COLUMNS) * STATIC_CELL, (index // ATLAS_COLUMNS) * STATIC_CELL))
    atlas_path = target_root / "atlas.png"
    atlas.save(atlas_path, optimize=True)
    manifest = {
        "schema_version": 1,
        "asset_id": f"runtime_web_combat_{entity_id.lower()}",
        "character_id": entity_id,
        "display_name": definition["name"],
        "status": "IMAGEGEN_STATIC_ANIMATED_SOURCE",
        "source_status": "ORIGINAL_INTERNAL_GENERATED",
        "source_root": str(source.relative_to(ROOT)).replace("\\", "/"),
        "source_asset_id": definition["asset_id"],
        "creation_method": "imagegen_original_render_plus_deterministic_presentation_motion",
        "ownership_status": "ORIGINAL_INTERNAL",
        "license": "USER_AUTHORIZED_INTERNAL_GENERATION",
        "frame_size": [STATIC_CELL, STATIC_CELL],
        "foot_anchor": definition["foot_anchor"],
        "head_anchor": definition["head_anchor"],
        "view": definition["view"],
        "facing_policy": definition["facing"],
        "atlas_path": "atlas.png",
        "atlas_columns": ATLAS_COLUMNS,
        "total_frames": len(all_frames),
        "animations": animations,
        "events": {
            "basic_attack": {"projectile_spawn_frame": 3, "damage_frame": 4},
            "normal_skill": {"vfx_frame": 5, "damage_frame": 6},
            "ultimate": {"vfx_frame": 8, "damage_frame": 10},
        },
        "sha256": sha256(atlas_path),
    }
    (target_root / "animation_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"RUNTIME_COMBAT_STATIC={entity_id}|frames={len(all_frames)}|bytes={atlas_path.stat().st_size}")
    return {"entity_id": entity_id, "path": f"combat/{entity_id}/atlas.png", "frames": len(all_frames), "sha256": manifest["sha256"], "status": manifest["status"]}


def build_combat_pack(entity_id: str, source_root: Path) -> dict:
    source_manifest = load_json(source_root / "animation_manifest.json")
    target_root = COMBAT_OUTPUT / entity_id
    prepare_output(target_root)
    ordered_frames: list[Path] = []
    animations: dict = {}
    for name, definition in source_manifest["animations"].items():
        indices: list[int] = []
        for relative in definition.get("frame_paths", []):
            path = source_root / relative
            if not path.is_file():
                raise FileNotFoundError(f"{entity_id} frame missing: {path}")
            indices.append(len(ordered_frames))
            ordered_frames.append(path)
        animations[name] = {
            "fps": definition.get("fps", source_manifest.get("default_fps", 12)),
            "loop": bool(definition.get("loop", False)),
            "frame_indices": indices,
            "events": definition.get("events", []),
        }
    if len(ordered_frames) > ATLAS_COLUMNS * 9:
        raise ValueError(f"{entity_id} has {len(ordered_frames)} frames; atlas capacity is 90")
    rows = max(1, (len(ordered_frames) + ATLAS_COLUMNS - 1) // ATLAS_COLUMNS)
    atlas = Image.new("RGBA", (ATLAS_COLUMNS * CELL, rows * CELL), (0, 0, 0, 0))
    for index, source in enumerate(ordered_frames):
        atlas.alpha_composite(image_cell(source, CELL), ((index % ATLAS_COLUMNS) * CELL, (index // ATLAS_COLUMNS) * CELL))
    atlas_path = target_root / "atlas.png"
    atlas.save(atlas_path, optimize=True)
    manifest = {
        "schema_version": 1,
        "asset_id": f"runtime_web_combat_{entity_id.lower()}",
        "character_id": entity_id,
        "status": "RUNTIME_WEB_COMBAT_ATLAS",
        "source_status": source_manifest.get("status", "ORIGINAL_INTERNAL"),
        "source_root": str(source_root.relative_to(GODOT)).replace("\\", "/"),
        "source_asset_id": source_manifest.get("asset_id", ""),
        "source_blend": source_manifest.get("source_blend", ""),
        "ownership_status": source_manifest.get("ownership_status", "PROJECT_DEV_GENERATED"),
        "frame_size": [CELL, CELL],
        "foot_anchor": source_manifest.get("foot_anchor", [0.5, 0.88]),
        "head_anchor": source_manifest.get("head_anchor", [0.5, 0.12]),
        "view": source_manifest.get("view", "THREE_QUARTER_RIGHT_DOWN_30"),
        "facing_policy": source_manifest.get("facing_policy", "SEPARATE_LEFT_RIGHT"),
        "atlas_path": "atlas.png",
        "atlas_columns": ATLAS_COLUMNS,
        "total_frames": len(ordered_frames),
        "animations": animations,
        "sha256": sha256(atlas_path),
    }
    (target_root / "animation_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"RUNTIME_COMBAT={entity_id}|frames={len(ordered_frames)}|bytes={atlas_path.stat().st_size}")
    return {"entity_id": entity_id, "path": f"combat/{entity_id}/atlas.png", "frames": len(ordered_frames), "sha256": manifest["sha256"]}


def build_projectile_pack(source_id: str, source_root: Path) -> dict:
    source_manifest = load_json(source_root / "projectile_manifest.json")
    target_root = PROJECTILE_OUTPUT / source_id
    prepare_output(target_root)
    frame_paths = [source_root / item for item in source_manifest.get("frame_paths", [])]
    if len(frame_paths) != 8 or any(not item.is_file() for item in frame_paths):
        raise ValueError(f"{source_id} projectile frames are incomplete")
    atlas = Image.new("RGBA", (PROJECTILE_CELL * len(frame_paths), PROJECTILE_CELL), (0, 0, 0, 0))
    for index, source in enumerate(frame_paths):
        atlas.alpha_composite(image_cell(source, PROJECTILE_CELL), (index * PROJECTILE_CELL, 0))
    atlas_path = target_root / "atlas.png"
    atlas.save(atlas_path, optimize=True)
    manifest = {
        "schema_version": 1,
        "asset_id": f"runtime_web_projectile_{source_id.lower()}",
        "source_id": source_id,
        "status": "RUNTIME_WEB_PROJECTILE_ATLAS",
        "source_asset_id": source_manifest.get("asset_id", ""),
        "frame_size": [PROJECTILE_CELL, PROJECTILE_CELL],
        "frames": 8,
        "atlas_path": "atlas.png",
        "atlas_columns": 8,
        "frame_indices": list(range(8)),
        "runtime_size": source_manifest.get("runtime_size", [80, 64]),
        "flight_duration": source_manifest.get("flight_duration", 0.13),
        "ownership_status": "PROJECT_DEV_GENERATED",
        "sha256": sha256(atlas_path),
    }
    (target_root / "projectile_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"RUNTIME_PROJECTILE={source_id}|bytes={atlas_path.stat().st_size}")
    return {"source_id": source_id, "path": f"projectiles/{source_id}/atlas.png", "sha256": manifest["sha256"]}


def build_vfx_pack(folder: Path) -> dict:
    frames = sorted(folder.glob("*.png"))
    if len(frames) != 12:
        raise ValueError(f"{folder.name} must contain 12 VFX frames, found {len(frames)}")
    target_root = VFX_OUTPUT / folder.name
    prepare_output(target_root)
    columns = 4
    atlas = Image.new("RGBA", (VFX_CELL * columns, VFX_CELL * 3), (0, 0, 0, 0))
    for index, source in enumerate(frames):
        atlas.alpha_composite(image_cell(source, VFX_CELL), ((index % columns) * VFX_CELL, (index // columns) * VFX_CELL))
    atlas_path = target_root / "atlas.png"
    atlas.save(atlas_path, optimize=True)
    print(f"RUNTIME_VFX={folder.name}|bytes={atlas_path.stat().st_size}")
    return {"folder": folder.name, "path": f"vfx/{folder.name}/atlas.png", "frames": 12, "columns": columns, "sha256": sha256(atlas_path)}


def main() -> int:
    COMBAT_OUTPUT.mkdir(parents=True, exist_ok=True)
    PROJECTILE_OUTPUT.mkdir(parents=True, exist_ok=True)
    VFX_OUTPUT.mkdir(parents=True, exist_ok=True)
    combat = [build_combat_pack(entity_id, path) for entity_id, path in COMBAT_SOURCES.items()]
    combat.extend(build_static_combat_pack(entity_id, definition) for entity_id, definition in STATIC_COMBAT_SOURCES.items())
    projectiles = [build_projectile_pack(source_id, path) for source_id, path in PROJECTILE_SOURCES.items()]
    vfx = [build_vfx_pack(path) for path in sorted((GODOT / "assets" / "art" / "vfx").iterdir()) if path.is_dir()]
    manifest = {"schema_version": 1, "combat": combat, "projectiles": projectiles, "vfx": vfx}
    (OUTPUT / "runtime_combat_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"RUNTIME_COMBAT_MANIFEST={OUTPUT / 'runtime_combat_manifest.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
