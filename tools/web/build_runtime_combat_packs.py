"""Build the small, Web-safe combat runtime packs from preserved source art.

The files in assets/art and assets/generated_import are authoring/source packs.
They remain untouched and are deliberately excluded from the Web PCK.  This
bridge makes a compact atlas for all nineteen Chapter 1 combat IDs and
the projectile/VFX packs used by the R7 battle view.  It is deterministic and
can overwrite only its own runtime_web output.
"""
from __future__ import annotations

import hashlib
import json
import math
import shutil
import colorsys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "godot"
OUTPUT = GODOT / "assets" / "runtime_web"
COMBAT_OUTPUT = OUTPUT / "combat"
PROJECTILE_OUTPUT = OUTPUT / "projectiles"
VFX_OUTPUT = OUTPUT / "vfx"
STORY_OUTPUT = OUTPUT / "story"
EXPANSION_SOURCE_ROOT = ROOT / "data_source" / "art_source" / "expansion_static_sources"
# Every non-combat card/standing image is authored against a flat chroma-green
# intermediate.  The matte is retained as a non-runtime audit source; the
# shipped image always keeps its genuine RGBA alpha channel and is never green
# in-game.  This is intentionally separate from the SD battle/map authorities.
CARD_MATTE_ROOT = ROOT / "data_source" / "art_source" / "card_8head_green_matte_r1"
CARD_MATTE_RGB = (0, 255, 0)
# Battle sprites are viewed well beyond a profile-icon scale.  These density
# targets retain linework and material separation in the 1920px battle view
# while leaving the atlas topology and simulation timing unchanged.
CELL = 128
# Static authority renders are no longer downsampled to icon density.  This
# keeps companion candidates, enemies, and bosses visually comparable to the
# authored multi-frame roster until their bespoke motion packs arrive.
STATIC_CELL = 112
PROJECTILE_CELL = 96
# VFX is rendered briefly at a much smaller on-screen area than its source
# canvas.  A 112px atlas keeps the full, authored VFX sequence in the Web PCK
# without forcing the browser delivery artifact over its per-file ceiling.
VFX_CELL = 112
# AssetRegistry consumers need a normal standalone texture rather than an
# atlas cell.  This preview is a deterministic derivative of the first idle
# frame and is deliberately labelled as a runtime preview, never as approved
# production illustration lineage.
PREVIEW_CELL = 256
ATLAS_COLUMNS = 10

# Story source plates intentionally stay outside the Web PCK.  These compact,
# deterministic derivatives preserve the actual authored CG in the browser
# without accidentally shipping the authoring-size source tree.
STORY_PLATES = {
    "cg_ch01_pilot_teamwork": {
        "source": GODOT / "assets" / "art" / "cg" / "CG_CH01_PILOT_TEAMWORK" / "cg_ch01_pilot_teamwork_1920x1080.png",
        "filename": "cg_ch01_pilot_teamwork_1280x720.png",
        "size": (1280, 720),
        "ownership_status": "ORIGINAL_INTERNAL",
        "license": "ORIGINAL_INTERNAL",
    },
}

COMBAT_SOURCES = {
    "CHR001": GODOT / "assets" / "art" / "sd" / "CHR001",
    "CHR002": GODOT / "assets" / "generated_import" / "characters" / "sd_chr002_roan_combat_r27_dev",
    "CHR003": GODOT / "assets" / "generated_import" / "characters" / "sd_chr003_narin_combat_r27_dev",
    "CHR004": GODOT / "assets" / "generated_import" / "characters" / "sd_chr004_eda_combat_r27_dev",
    "CHR005": GODOT / "assets" / "generated_import" / "characters" / "sd_chr005_soren_combat_r27_dev",
    # R15 replaces the former in-memory profile-card presentation for these
    # roster members.  Their deterministic 80-frame cutout-rig packs are
    # authored from project-owned transparent source art and preserved in
    # generated_import before this Web-only atlas bridge runs.
    "CHR006": GODOT / "assets" / "generated_import" / "characters" / "sd_chr006_vera_combat_r15",
    "CHR007": GODOT / "assets" / "generated_import" / "characters" / "sd_chr007_toa_combat_r15",
    "CHR008": GODOT / "assets" / "generated_import" / "characters" / "sd_chr008_iri_combat_r15",
    "ENM001": GODOT / "assets" / "art" / "enemies" / "ENM001",
    "ENM002": GODOT / "assets" / "generated_import" / "enemies" / "sd_enm002_arc_mote_combat_r28_dev",
    "ENM007": GODOT / "assets" / "art" / "enemies" / "ENM007",
    "BOSS001": GODOT / "assets" / "art" / "bosses" / "BOSS001",
}

# These eight are the immutable premium 8-head authorities for the original
# companions.  They feed every card, recruit, roster, profile and story
# surface.  Do not point these IDs at an SD frame: SD is battle/map-only.
PRIMARY_CARD_SOURCES = {
    # R5 is a green-matte source generated locally from the established Maeru
    # authority.  It repairs the baked white hair backing before chroma keying;
    # R3/R4 threshold attempts remain archived as rejected QA candidates.
    "CHR001": {"source": ROOT / "data_source" / "art_source" / "card_8head_green_matte_r2" / "CHR001" / "chr001_8head_r7_chatgpt_fresh_exact_green_matte.png", "costume_id": "CHR001_CANONICAL_8HEAD_CARD_R7", "source_status": "CHATGPT_FRESH_8HEAD_R7_GREEN_MATTE_VISUAL_QA_PASS", "presentation": "PREMIUM_8_HEAD_FULL_BODY_CARD", "input_mode": "KEY_GREEN_MATTE"},
    "CHR002": {"source": GODOT / "assets" / "art" / "characters" / "CHR002" / "CHR002_PORTRAIT_R1.png", "costume_id": "CHR002_CANONICAL_8HEAD_CARD_R1", "source_status": "ORIGINAL_INTERNAL_RGBA_8HEAD_AUTHORITY", "presentation": "PREMIUM_8_HEAD_FULL_BODY_CARD", "input_mode": "RGBA_AUTHORITY"},
    "CHR003": {"source": GODOT / "assets" / "art" / "characters" / "CHR003" / "CHR003_PORTRAIT_R1.png", "costume_id": "CHR003_CANONICAL_8HEAD_CARD_R1", "source_status": "ORIGINAL_INTERNAL_RGBA_8HEAD_AUTHORITY", "presentation": "PREMIUM_8_HEAD_FULL_BODY_CARD", "input_mode": "RGBA_AUTHORITY"},
    "CHR004": {"source": GODOT / "assets" / "art" / "characters" / "CHR004" / "CHR004_PORTRAIT_R1.png", "costume_id": "CHR004_CANONICAL_8HEAD_CARD_R1", "source_status": "ORIGINAL_INTERNAL_RGBA_8HEAD_AUTHORITY", "presentation": "PREMIUM_8_HEAD_FULL_BODY_CARD", "input_mode": "RGBA_AUTHORITY"},
    "CHR005": {"source": GODOT / "assets" / "art" / "characters" / "CHR005" / "CHR005_PORTRAIT_R1.png", "costume_id": "CHR005_CANONICAL_8HEAD_CARD_R1", "source_status": "ORIGINAL_INTERNAL_RGBA_8HEAD_AUTHORITY", "presentation": "PREMIUM_8_HEAD_FULL_BODY_CARD", "input_mode": "RGBA_AUTHORITY"},
    "CHR006": {"source": GODOT / "assets" / "art" / "characters" / "CHR006" / "CHR006_PORTRAIT_R1.png", "costume_id": "CHR006_CANONICAL_8HEAD_CARD_R1", "source_status": "ORIGINAL_INTERNAL_RGBA_8HEAD_AUTHORITY", "presentation": "PREMIUM_8_HEAD_FULL_BODY_CARD", "input_mode": "RGBA_AUTHORITY"},
    "CHR007": {"source": GODOT / "assets" / "art" / "characters" / "CHR007" / "CHR007_PORTRAIT_R1.png", "costume_id": "CHR007_CANONICAL_8HEAD_CARD_R1", "source_status": "ORIGINAL_INTERNAL_RGBA_8HEAD_AUTHORITY", "presentation": "PREMIUM_8_HEAD_FULL_BODY_CARD", "input_mode": "RGBA_AUTHORITY"},
    "CHR008": {"source": GODOT / "assets" / "art" / "characters" / "CHR008" / "CHR008_PORTRAIT_R1.png", "costume_id": "CHR008_CANONICAL_8HEAD_CARD_R1", "source_status": "ORIGINAL_INTERNAL_RGBA_8HEAD_AUTHORITY", "presentation": "PREMIUM_8_HEAD_FULL_BODY_CARD", "input_mode": "RGBA_AUTHORITY"},
}


def player_sd_static_overrides() -> dict[str, dict]:
    """Runtime-select SD authorities for the three tall R15 cutout rigs.

    Their original multi-frame packs remain preserved under generated_import.
    Only the Web/runtime selection changes, so later bespoke SD animation work
    can replace these presentation packs without destroying authored sources.
    """
    definitions = {
        "CHR006": ("chr006_costume_authority_sd_r1_rgba.png", "Vera"),
        "CHR007": ("chr007_costume_authority_sd_r1_rgba.png", "Toa"),
        "CHR008": ("chr008_costume_authority_sd_r1_rgba.png", "Iri"),
    }
    source_root = ROOT / "data_source" / "art_source" / "combat_hd_sources" / "renewed"
    result: dict[str, dict] = {}
    for entity_id, (filename, name) in definitions.items():
        source = source_root / filename
        if not source.is_file():
            raise FileNotFoundError(f"{entity_id} SD runtime authority missing: {source}")
        result[entity_id] = {
            "source": source,
            "asset_id": f"{entity_id.lower()}_sd_unification_r1_{sha256(source)[:16]}",
            "name": name,
            "view": "THREE_QUARTER_RIGHT_DOWN_30",
            "facing": "SEPARATE_LEFT_RIGHT",
            "foot_anchor": [0.5, 0.88],
            "head_anchor": [0.5, 0.12],
            "status": "SD_UNIFICATION_R1_STATIC_PRESENTATION_PACK",
            "source_status": "LOCAL_IDENTITY_CONTINUITY_REVIEWED_GREEN_KEY_RGBA",
            "creation_method": "imagegen_identity_preserving_sd_edit_green_matte_plus_deterministic_presentation_motion",
        }
    return result

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
    "CHR006": GODOT / "assets" / "generated_import" / "projectiles" / "proj_chr006_sapphire_focus_lance_r15",
    "CHR007": GODOT / "assets" / "generated_import" / "projectiles" / "proj_chr007_violet_signal_orb_r15",
    "CHR008": GODOT / "assets" / "generated_import" / "projectiles" / "proj_chr008_mint_medic_orb_r15",
    "ENM001": GODOT / "assets" / "generated_import" / "projectiles" / "proj_enm001_crystal_claw_r28",
    "ENM002": GODOT / "assets" / "generated_import" / "projectiles" / "proj_enm002_arc_mote_r28",
    "ENM003": GODOT / "assets" / "generated_import" / "projectiles" / "proj_enm003_shell_pulse_r15",
    "ENM004": GODOT / "assets" / "generated_import" / "projectiles" / "proj_enm004_mend_ray_r15",
    "ENM005": GODOT / "assets" / "generated_import" / "projectiles" / "proj_enm005_jammer_arc_r15",
    "ENM006": GODOT / "assets" / "generated_import" / "projectiles" / "proj_enm006_dust_lance_r15",
    "ENM007": GODOT / "assets" / "generated_import" / "projectiles" / "proj_enm007_warden_burst_r15",
    "ENM008": GODOT / "assets" / "generated_import" / "projectiles" / "proj_enm008_broadcast_wave_r15",
    "ENM009": GODOT / "assets" / "generated_import" / "projectiles" / "proj_enm009_fortress_arc_r15",
    "BOSS001": GODOT / "assets" / "generated_import" / "projectiles" / "proj_boss001_hollow_sun_r15",
    "BOSS002": GODOT / "assets" / "generated_import" / "projectiles" / "proj_boss002_bell_void_r15",
}

# The player-approved VFX style bible is deliberately data-first: every roster
# unit gets a different colour language *and* motion language.  The source of
# truth was reviewed in the existing in-app ChatGPT conversation before any
# renderer work began.  These runtime signature atlases sit over the authored
# Signal Breaker ultimate base and a lightweight procedural accent, keeping a
# cast at two textures plus one draw-time accent at most.
VFX_STYLE_PROFILES = {
    "CHR001": {"primary": (121, 231, 255), "secondary": (255, 211, 106), "normal": "shield", "ultimate": "shield"},
    "CHR002": {"primary": (184, 199, 217), "secondary": (255, 155, 84), "normal": "rush", "ultimate": "rush"},
    "CHR003": {"primary": (127, 216, 255), "secondary": (255, 110, 168), "normal": "tracer", "ultimate": "artillery"},
    "CHR004": {"primary": (67, 215, 255), "secondary": (255, 241, 106), "normal": "lightning", "ultimate": "lightning"},
    "CHR005": {"primary": (165, 140, 255), "secondary": (255, 211, 106), "normal": "artillery", "ultimate": "artillery"},
    "CHR006": {"primary": (214, 244, 255), "secondary": (109, 123, 255), "normal": "distort", "ultimate": "distort"},
    "CHR007": {"primary": (140, 255, 240), "secondary": (123, 179, 255), "normal": "shield", "ultimate": "shield"},
    "CHR008": {"primary": (185, 255, 207), "secondary": (255, 217, 138), "normal": "heal", "ultimate": "heal"},
    "ENM001": {"primary": (255, 106, 42), "secondary": (255, 208, 90), "normal": "flame", "ultimate": "flame_split"},
    "ENM002": {"primary": (91, 229, 255), "secondary": (140, 121, 255), "normal": "tracer", "ultimate": "lightning"},
    "ENM003": {"primary": (126, 138, 152), "secondary": (255, 211, 106), "normal": "heavy", "ultimate": "plate_rupture"},
    "ENM004": {"primary": (131, 255, 199), "secondary": (114, 199, 255), "normal": "heal", "ultimate": "barrier_mend"},
    "ENM005": {"primary": (255, 211, 106), "secondary": (255, 143, 210), "normal": "chorus", "ultimate": "harmonic_bars"},
    "ENM006": {"primary": (185, 164, 122), "secondary": (124, 140, 90), "normal": "dust", "ultimate": "dust_shear"},
    "ENM007": {"primary": (229, 224, 214), "secondary": (138, 108, 255), "normal": "summon", "ultimate": "ward_gate"},
    "ENM008": {"primary": (255, 87, 209), "secondary": (72, 231, 255), "normal": "broadcast_glitch", "ultimate": "broadcast_tear"},
    "ENM009": {"primary": (170, 183, 200), "secondary": (255, 211, 106), "normal": "iron_vibration", "ultimate": "slab_resonance"},
    "BOSS001": {"primary": (53, 224, 255), "secondary": (122, 43, 255), "normal": "void", "ultimate": "implode"},
    "BOSS002": {"primary": (167, 184, 255), "secondary": (255, 211, 106), "normal": "chorus", "ultimate": "resonance"},
    "ENM010": {"primary": (56, 229, 255), "secondary": (68, 124, 255), "normal": "rush_cut", "ultimate": "rush_cut"},
    "ENM011": {"primary": (169, 247, 255), "secondary": (110, 145, 255), "normal": "glass_tracer", "ultimate": "glass_tracer"},
    "ENM012": {"primary": (255, 164, 110), "secondary": (186, 110, 255), "normal": "barrier_fracture", "ultimate": "barrier_fracture"},
    "BOSS003": {"primary": (233, 251, 255), "secondary": (121, 223, 255), "normal": "orbital_scan", "ultimate": "lockon"},
    "ENM013": {"primary": (255, 89, 207), "secondary": (91, 231, 255), "normal": "reverse_arc", "ultimate": "reverse_arc"},
    "ENM014": {"primary": (255, 181, 67), "secondary": (84, 226, 255), "normal": "artillery", "ultimate": "battery_barrage"},
    "ENM015": {"primary": (206, 124, 255), "secondary": (101, 245, 221), "normal": "chorus", "ultimate": "chorus_collapse"},
    "BOSS004": {"primary": (114, 231, 255), "secondary": (255, 187, 99), "normal": "heavy", "ultimate": "gate_reverse"},
    "BOSS005": {"primary": (98, 241, 221), "secondary": (246, 198, 93), "normal": "summon", "ultimate": "network"},
}

# Invalidate generated atlases when the motion grammar changes.  Colour-only
# cache keys previously kept stale low-detail spirals after renderer upgrades.
VFX_STYLE_REVISION = "enemy_boss_motion_blockout_r2"
VFX_ATLAS_OVERRIDES = {
    # R3 player authorities use a chroma-matte generation source only during
    # extraction; the promoted atlas below is verified transparent RGBA.
    ("CHR014", "basic"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "chr014_basic_gpt_r3_atlas_448x336.png",
    ("CHR014", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "chr014_normal_gpt_r3_atlas_448x336.png",
    ("CHR014", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "chr014_ultimate_gpt_r3_atlas_448x336.png",
    ("BOSS001", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "boss001_ultimate_gpt_r2_atlas_448x336.png",
    ("BOSS002", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "boss002_ultimate_gpt_r2_atlas_448x336.png",
    ("BOSS003", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "boss003_ultimate_gpt_r2_atlas_448x336.png",
    ("BOSS004", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "boss004_ultimate_gpt_r2_atlas_448x336.png",
    ("BOSS005", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "boss005_ultimate_gpt_r2_atlas_448x336.png",
    ("BOSS001", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "boss001_normal_gpt_r2_atlas_448x336.png",
    ("BOSS002", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "boss002_normal_gpt_r2_atlas_448x336.png",
    ("BOSS003", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "boss003_normal_gpt_r2_atlas_448x336.png",
    ("BOSS004", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "boss004_normal_gpt_r2_atlas_448x336.png",
    ("BOSS005", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "boss005_normal_gpt_r2_atlas_448x336.png",
    ("ENM001", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm001_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM002", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm002_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM003", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm003_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM004", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm004_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM005", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm005_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM006", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm006_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM007", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm007_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM008", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm008_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM009", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm009_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM010", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm010_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM011", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm011_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM012", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm012_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM013", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm013_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM014", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm014_ultimate_gpt_r2_atlas_448x336.png",
    ("ENM015", "ultimate"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enm015_ultimate_gpt_r2_atlas_448x336.png",
    # Normal skills intentionally share seven role-family authorities across
    # ordinary mobs. Bosses never use these shared atlases.
    ("ENM001", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f1_gpt_r2_atlas_448x336.png",
    ("ENM002", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f2_gpt_r2_atlas_448x336.png",
    ("ENM010", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f2_gpt_r2_atlas_448x336.png",
    ("ENM011", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f2_gpt_r2_atlas_448x336.png",
    ("ENM013", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f2_gpt_r2_atlas_448x336.png",
    ("ENM003", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f3_gpt_r2_atlas_448x336.png",
    ("ENM009", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f3_gpt_r2_atlas_448x336.png",
    ("ENM012", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f3_gpt_r2_atlas_448x336.png",
    ("ENM004", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f4_gpt_r2_atlas_448x336.png",
    ("ENM005", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f4_gpt_r2_atlas_448x336.png",
    ("ENM015", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f4_gpt_r2_atlas_448x336.png",
    ("ENM006", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f5_gpt_r2_atlas_448x336.png",
    ("ENM014", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f5_gpt_r2_atlas_448x336.png",
    ("ENM007", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f6_gpt_r2_atlas_448x336.png",
    ("ENM008", "normal"): ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "enemy_normal_family_f7_gpt_r2_atlas_448x336.png",
}

# Player role authorities are shared only while the R3 source pass is in
# progress.  The individual unit profile still supplies its own movement,
# colour accents and timing; this replaces the code-only burst with verified
# high-density RGBA key art without inventing a second costume or character.
# Individual mappings above always win and are promoted first.
PLAYER_ROLE_VFX_AUTHORITIES = {
    "ASSAULT": {
        "basic": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_assault_basic_gpt_r3_atlas_448x336.png",
        "normal": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_assault_normal_gpt_r3_atlas_448x336.png",
        "ultimate": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_assault_ultimate_gpt_r3_atlas_448x336.png",
    },
    "GUARDIAN": {
        "basic": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_guardian_basic_gpt_r3_atlas_448x336.png",
        "normal": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_guardian_normal_gpt_r3_atlas_448x336.png",
        "ultimate": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_guardian_ultimate_gpt_r3_atlas_448x336.png",
    },
    "VANGUARD": {
        "basic": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_vanguard_basic_gpt_r3_atlas_448x336.png",
        "normal": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_vanguard_normal_gpt_r3_atlas_448x336.png",
        "ultimate": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_vanguard_ultimate_gpt_r3_atlas_448x336.png",
    },
    "ARTILLERY": {
        "basic": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_artillery_basic_gpt_r3_atlas_448x336.png",
        "normal": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_artillery_normal_gpt_r3_atlas_448x336.png",
        "ultimate": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_artillery_ultimate_gpt_r3_atlas_448x336.png",
    },
    "SPECIALIST": {
        "basic": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_specialist_basic_gpt_r3_atlas_448x336.png",
        "normal": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_specialist_normal_gpt_r3_atlas_448x336.png",
        "ultimate": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_specialist_ultimate_gpt_r3_atlas_448x336.png",
    },
    "MEDIC": {
        "basic": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_medic_basic_gpt_r3_atlas_448x336.png",
        "normal": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_medic_normal_gpt_r3_atlas_448x336.png",
        "ultimate": ROOT / "data_source" / "art_source" / "vfx_hd_sources" / "runtime_candidates" / "role_medic_ultimate_gpt_r3_atlas_448x336.png",
    },
}


def apply_player_role_vfx_authorities() -> None:
    """Promote available R3 role VFX for every matching player without overwriting an individual authority."""
    data = load_json(GODOT / "data" / "compiled" / "game_data.json")
    for row in data.get("characters", []):
        entity_id = str(row.get("id", ""))
        role_authorities = PLAYER_ROLE_VFX_AUTHORITIES.get(str(row.get("role", "")), {})
        for kind, atlas in role_authorities.items():
            VFX_ATLAS_OVERRIDES.setdefault((entity_id, kind), atlas)


def _stable_colour(entity_id: str, salt: int, value: float = .92) -> tuple[int, int, int]:
    digest = hashlib.sha256(f"{entity_id}:{salt}".encode("utf-8")).digest()
    hue = (int.from_bytes(digest[:2], "big") % 360) / 360.0
    saturation = .48 + (digest[2] % 34) / 100.0
    red, green, blue = colorsys.hsv_to_rgb(hue, min(.92, saturation), value)
    return int(red * 255), int(green * 255), int(blue * 255)


def _tint(colour: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, int(channel + (255 - channel) * amount))) for channel in colour)


def _draw_expansion_character_source(image: Image.Image, entity_id: str, row: dict) -> dict:
    """Create a unique, source-owned SD authority candidate from immutable data.

    This remains a clearly marked procedural candidate until the matching
    GPT-reviewed costume contract is promoted. Every runtime animation derives
    from this one texture; no pose gets a second outfit by accident.
    """
    draw = ImageDraw.Draw(image)
    seed = int.from_bytes(hashlib.sha256(entity_id.encode("utf-8")).digest()[:4], "big")
    primary = _stable_colour(entity_id, 1)
    secondary = _stable_colour(entity_id, 2, .82)
    trim = _tint(primary, .46)
    dark = tuple(max(15, int(channel * .28)) for channel in primary)
    skin = [(255, 213, 181), (235, 183, 150), (205, 138, 110), (247, 196, 155)][seed % 4]
    role = str(row.get("role", "ASSAULT"))
    cx, head_y = 512, 270
    # Shadow, boots and lower garment are deliberately separated in the source
    # silhouette so a combat rig candidate has readable non-fused joints.
    draw.ellipse((325, 814, 699, 878), fill=(8, 17, 33, 92))
    boot_y = 742
    for x in (414, 553):
        draw.rounded_rectangle((x, boot_y, x + 72, 842), radius=25, fill=dark + (255,), outline=trim + (255,), width=10)
    lower_shape = (390, 590, 635, 770)
    if role in ("GUARDIAN", "VANGUARD"):
        draw.polygon([(382, 590), (642, 590), (676, 742), (346, 742)], fill=secondary + (255,), outline=trim + (255,))
        draw.rectangle((360, 683, 664, 716), fill=dark + (255,))
    elif role == "MEDIC":
        draw.rounded_rectangle(lower_shape, radius=46, fill=secondary + (255,), outline=trim + (255,), width=12)
        draw.line((512, 602, 512, 756), fill=trim + (255,), width=12)
    else:
        draw.polygon([(396, 584), (628, 584), (650, 752), (548, 752), (512, 690), (474, 752), (374, 752)], fill=secondary + (255,), outline=trim + (255,))
    # Distinct coat/armor silhouettes by role; all coverage remains commercial
    # game appropriate and never relies on exposed-skin design.
    torso = (348, 440, 676, 652)
    draw.rounded_rectangle(torso, radius=58, fill=primary + (255,), outline=trim + (255,), width=14)
    if role == "GUARDIAN":
        draw.polygon([(324, 462), (368, 442), (396, 616), (334, 652)], fill=dark + (255,), outline=trim + (255,))
        draw.polygon([(700, 462), (656, 442), (628, 616), (690, 652)], fill=dark + (255,), outline=trim + (255,))
    elif role == "ARTILLERY":
        draw.polygon([(372, 478), (420, 440), (460, 628), (350, 680)], fill=secondary + (255,), outline=trim + (255,))
        draw.polygon([(652, 478), (604, 440), (564, 628), (674, 680)], fill=secondary + (255,), outline=trim + (255,))
    elif role == "SPECIALIST":
        draw.arc((365, 430, 660, 682), 15, 165, fill=trim + (255,), width=14)
        draw.line((384, 530, 641, 530), fill=dark + (255,), width=12)
    elif role == "MEDIC":
        draw.rectangle((452, 440, 572, 652), fill=trim + (255,))
        draw.rectangle((492, 474, 532, 574), fill=(242, 248, 255, 255))
        draw.rectangle((462, 504, 562, 544), fill=(242, 248, 255, 255))
    else:
        draw.line((372, 594, 652, 594), fill=trim + (255,), width=13)
    belt_y = 628
    draw.rounded_rectangle((370, belt_y, 654, belt_y + 35), radius=12, fill=dark + (255,), outline=trim + (255,), width=6)
    draw.ellipse((489, belt_y + 2, 535, belt_y + 33), fill=trim + (255,))
    # Hands and weapon are disconnected enough to preserve grip-zone checks.
    draw.ellipse((300, 542, 371, 620), fill=skin + (255,), outline=dark + (255,), width=7)
    draw.ellipse((651, 542, 722, 620), fill=skin + (255,), outline=dark + (255,), width=7)
    if role in ("GUARDIAN", "VANGUARD"):
        draw.rounded_rectangle((694, 386, 752, 690), radius=24, fill=dark + (255,), outline=trim + (255,), width=10)
        draw.polygon([(676, 404), (790, 360), (806, 422), (696, 466)], fill=secondary + (255,), outline=trim + (255,))
    elif role in ("ASSAULT", "ARTILLERY"):
        draw.rounded_rectangle((648, 470, 856, 524), radius=18, fill=dark + (255,), outline=trim + (255,), width=9)
        draw.polygon([(816, 465), (910, 490), (824, 534)], fill=secondary + (255,), outline=trim + (255,))
        draw.rectangle((700, 516, 748, 610), fill=dark + (255,))
    elif role == "MEDIC":
        draw.ellipse((706, 447, 826, 567), fill=secondary + (255,), outline=trim + (255,), width=12)
        draw.line((766, 472, 766, 542), fill=(245, 253, 255, 255), width=14)
        draw.line((731, 507, 801, 507), fill=(245, 253, 255, 255), width=14)
    else:
        draw.polygon([(712, 444), (816, 514), (758, 630), (666, 558)], fill=dark + (255,), outline=trim + (255,))
        draw.ellipse((719, 496, 791, 568), fill=secondary + (255,), outline=_tint(secondary, .55) + (255,), width=9)
    # Face and hair establish individual silhouette without hiding the head or
    # weapon grips. Seeded fringe/side-lock variants are stable per ID.
    draw.ellipse((342, 128, 682, 460), fill=dark + (255,))
    hair_variant = seed % 6
    hair = _tint(primary, -.30)
    draw.ellipse((360, 142, 664, 422), fill=hair + (255,), outline=trim + (255,), width=12)
    draw.ellipse((392, 215, 632, 432), fill=skin + (255,), outline=dark + (255,), width=8)
    if hair_variant in (0, 2):
        draw.polygon([(374, 248), (438, 148), (484, 284), (532, 145), (580, 280), (645, 198), (644, 272), (380, 290)], fill=hair + (255,))
    elif hair_variant in (1, 3):
        draw.polygon([(366, 224), (426, 122), (492, 266), (554, 126), (666, 242), (642, 308), (380, 304)], fill=hair + (255,))
        draw.ellipse((324, 294, 410, 472), fill=hair + (255,), outline=trim + (255,), width=8)
    else:
        draw.arc((344, 120, 680, 440), 185, 350, fill=trim + (255,), width=32)
        draw.polygon([(603, 256), (711, 330), (640, 430), (588, 370)], fill=hair + (255,), outline=trim + (255,))
    eye = (22, 47, 74, 255)
    draw.ellipse((442, 308, 478, 344), fill=eye)
    draw.ellipse((548, 308, 584, 344), fill=eye)
    draw.arc((480, 333, 544, 385), 10, 170, fill=dark + (255,), width=8)
    accessory_x = 388 + (seed % 4) * 55
    draw.polygon([(accessory_x, 206), (accessory_x + 42, 181), (accessory_x + 67, 222), (accessory_x + 24, 250)], fill=secondary + (255,), outline=trim + (255,))
    return {"costume_id": f"{entity_id}_COSTUME_A", "palette": {"primary": primary, "secondary": secondary, "trim": trim}, "role": role}


def _draw_expansion_enemy_source(image: Image.Image, entity_id: str, row: dict) -> dict:
    draw = ImageDraw.Draw(image)
    seed = int.from_bytes(hashlib.sha256(entity_id.encode("utf-8")).digest()[:4], "big")
    primary = _stable_colour(entity_id, 5, .78)
    secondary = _stable_colour(entity_id, 6, .96)
    dark = tuple(max(12, int(channel * .22)) for channel in primary)
    rank = str(row.get("rank", "NORMAL"))
    cx, cy = 512, 508
    scale = 1.40 if rank == "BOSS" else 1.0
    radius = int(178 * scale)
    for layer in range(3):
        local = radius - layer * int(36 * scale)
        points = _polygon_ring(cx, cy, local, 6 + (seed + layer) % 3, -math.pi / 2 + layer * .18)
        draw.polygon(points, fill=(primary if layer != 1 else dark) + (255,), outline=secondary + (255,))
    eye_radius = int(37 * scale)
    for x in (cx - int(64 * scale), cx + int(64 * scale)):
        draw.ellipse((x-eye_radius, cy-eye_radius, x+eye_radius, cy+eye_radius), fill=(8, 16, 36, 255), outline=secondary + (255,), width=10)
        draw.ellipse((x-eye_radius//3, cy-eye_radius//3, x+eye_radius//3, cy+eye_radius//3), fill=secondary + (255,))
    for index in range(5 if rank == "BOSS" else 3):
        angle = -2.5 + index * .9
        start = _point(cx, cy, radius*.78, angle)
        end = _point(cx, cy, radius*1.45, angle + .12)
        draw.line((start, end), fill=dark + (255,), width=int(34 * scale))
        draw.line((start, end), fill=secondary + (255,), width=int(9 * scale))
    if rank == "BOSS":
        for index in range(3):
            ring = radius * (1.06 + index * .18)
            draw.arc((cx-ring, cy-ring, cx+ring, cy+ring), 20 + index * 70, 190 + index * 65, fill=secondary + (205,), width=11)
    return {"costume_id": f"{entity_id}_SILHOUETTE_A", "palette": {"primary": primary, "secondary": secondary}, "role": str(row.get("role", ""))}


def expansion_static_sources() -> dict[str, dict]:
    """Return isolated source definitions for every new immutable entity ID."""
    data = load_json(GODOT / "data" / "compiled" / "game_data.json")
    known = set(COMBAT_SOURCES) | set(STATIC_COMBAT_SOURCES)
    entries = list(data.get("characters", [])) + list(data.get("enemies", []))
    definitions: dict[str, dict] = {}
    contract_path = EXPANSION_SOURCE_ROOT / "qa" / "COSTUME_CONTINUITY_CONTRACT.json"
    existing_contract_document = load_json(contract_path) if contract_path.is_file() else {"schemaVersion": 1, "candidates": {}}
    existing_contracts = dict(existing_contract_document.get("candidates", {}))
    development_overrides = dict(existing_contract_document.get("developmentCostumeOverrides", {}))
    contracts: dict[str, dict] = {}
    EXPANSION_SOURCE_ROOT.mkdir(parents=True, exist_ok=True)
    for row in entries:
        entity_id = str(row.get("id", ""))
        if not entity_id or entity_id in known:
            continue
        authority_path = EXPANSION_SOURCE_ROOT / f"{entity_id.lower()}_authority.png"
        override = development_overrides.get(entity_id)
        if override:
            path = (contract_path.parent / str(override.get("authorityImage", ""))).resolve()
            if not path.is_file():
                raise FileNotFoundError(f"{entity_id} approved development costume authority missing: {path}")
            if sha256(path) != str(override.get("authoritySha256", "")):
                raise ValueError(f"{entity_id} development costume authority hash does not match its continuity contract")
        else:
            path = authority_path
        if not path.is_file():
            image = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
            fingerprint = _draw_expansion_character_source(image, entity_id, row) if entity_id.startswith("CHR") else _draw_expansion_enemy_source(image, entity_id, row)
            image.save(path, optimize=True)
        else:
            fingerprint = {"costume_id": f"{entity_id}_{'COSTUME' if entity_id.startswith('CHR') else 'SILHOUETTE'}_A", "role": str(row.get("role", "")), "palette": {}}
        contracts[entity_id] = existing_contracts.get(entity_id, {
            "costumeId": fingerprint["costume_id"], "authorityImage": path.name, "authoritySha256": sha256(path),
            "status": "CANDIDATE_PENDING_GPT_COSTUME_CONTINUITY_REVIEW",
            "fingerprint": {"role": fingerprint["role"], "palette": fingerprint["palette"], "coverage": "NON_EXPLICIT_FULL_BODY", "weaponGrip": "SEPARATED_READABLE_GRIP_ZONES"},
        })
        costume_id = str(override.get("costumeId")) if override else str(contracts[entity_id]["costumeId"])
        definitions[entity_id] = {
            "source": path, "asset_id": f"{costume_id.lower()}_{sha256(path)[:16]}_sc{STATIC_CELL}", "name": entity_id,
            "view": "THREE_QUARTER_RIGHT_DOWN_30" if entity_id.startswith("CHR") else "THREE_QUARTER_LEFT_DOWN_30",
            "facing": "SEPARATE_LEFT_RIGHT" if entity_id.startswith("CHR") else "MIRROR_SAFE",
            "foot_anchor": [0.5, 0.88], "head_anchor": [0.5, 0.14],
            "status": "HIGH_RES_COSTUME_CANDIDATE" if override else "ORIGINAL_INTERNAL_PROCEDURAL_CANDIDATE",
            "source_status": str(override.get("status")) if override else "COSTUME_CONTRACT_PENDING_GPT_REVIEW",
            "creation_method": "costume_only_high_resolution_authority_candidate" if override else "deterministic_unique_sd_authority_candidate",
        }
    qa_root = EXPANSION_SOURCE_ROOT / "qa"
    qa_root.mkdir(parents=True, exist_ok=True)
    preserved_document = {key: value for key, value in existing_contract_document.items() if key not in {"schemaVersion", "candidates"}}
    (qa_root / "COSTUME_CONTINUITY_CONTRACT.json").write_text(json.dumps({"schemaVersion": 2, **preserved_document, "candidates": contracts}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return definitions


def card_8head_sources() -> dict[str, dict]:
    """Return the strict 44-character non-combat card authorities.

    The SD combat/map source directories are deliberately not consulted here.
    Expansion cards are allowed into the runtime only after their individual
    green-matte candidate has been explicitly continuity-approved.
    """
    sources = dict(PRIMARY_CARD_SOURCES)
    contract_path = CARD_MATTE_ROOT / "qa" / "CARD_8HEAD_CANDIDATE_CONTRACT.json"
    document = load_json(contract_path) if contract_path.is_file() else {"candidates": {}}
    candidates = dict(document.get("candidates", {}))
    for index in range(9, 45):
        entity_id = f"CHR{index:03d}"
        candidate = dict(candidates.get(entity_id, {}))
        # The reviewed RGBA candidate has already passed the project's strict
        # key removal and edge-despill pass.  Re-keying the green authoring
        # matte here can reintroduce a thin green fringe after thumbnailing, so
        # runtime cards are packed directly from the approved transparent file.
        relative_path = str(candidate.get("rgbaCandidate", ""))
        source = ROOT / relative_path
        if not relative_path or not source.is_file():
            raise FileNotFoundError(f"{entity_id} 8-head card authority is missing: {source}")
        if sha256(source) != str(candidate.get("rgbaCandidateSha256", "")):
            raise ValueError(f"{entity_id} 8-head card authority hash does not match its candidate contract")
        if str(candidate.get("status", "")) != "CONTINUITY_APPROVED_PENDING_RUNTIME_PROMOTION":
            raise ValueError(f"{entity_id} 8-head card authority is not approved for runtime promotion")
        sources[entity_id] = {
            "source": source,
            "costume_id": f"{entity_id}_CANONICAL_8HEAD_CARD_R1",
            "source_status": "OPENAI_IMAGEGEN_GREEN_MATTE_8HEAD_CONTINUITY_APPROVED",
            "presentation": "PREMIUM_8_HEAD_FULL_BODY_CARD",
            "input_mode": "RGBA_AUTHORITY",
        }
    if set(sources) != {f"CHR{index:03d}" for index in range(1, 45)}:
        raise ValueError("8-head card coverage must be exactly CHR001–CHR044")
    return sources


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def prepare_output(path: Path) -> None:
    """Clear bridge outputs without deleting Godot's tracked import metadata.

    The atlas and manifest are regenerated deterministically, but `*.import`
    files are project metadata that point at Godot's imported cache. Removing
    those files during every Web build can leave a headless validation process
    with an invalid texture record even though the raw PNG exists.
    """
    if not path.exists():
        path.mkdir(parents=True, exist_ok=True)
        return
    for child in path.iterdir():
        if child.name.endswith(".import"):
            continue
        if child.is_dir():
            shutil.rmtree(child)
        else:
            child.unlink()


def image_cell(source: Path, size: int) -> Image.Image:
    image = Image.open(source).convert("RGBA")
    if image.size != (size, size):
        image = image.resize((size, size), Image.Resampling.LANCZOS)
    return image


def _is_card_key_green(pixel: tuple[int, int, int]) -> bool:
    red, green, blue = pixel
    # Preserve intentional lime costume materials while removing the exact
    # #00FF00 source field and its antialiased fringe.
    return green >= 178 and red <= 104 and blue <= 104 and green - red >= 92 and green - blue >= 92


def _key_card_green_matte(source: Path) -> Image.Image:
    """Convert a #00FF00 card source to actual RGBA before runtime resize."""
    rgb = Image.open(source).convert("RGB")
    pixels = rgb.load()
    alpha = Image.new("L", rgb.size, 255)
    alpha_pixels = alpha.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            if _is_card_key_green(pixels[x, y]):
                alpha_pixels[x, y] = 0
    # Soften only the chroma boundary; do not retain a keyed green fringe.
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.6))
    image = rgb.convert("RGBA")
    image.putalpha(alpha)
    _decontaminate_card_rgba(image)
    if image.getchannel("A").getextrema() != (0, 255):
        raise ValueError(f"card green key did not produce true RGBA extrema: {source}")
    return image


def _decontaminate_card_rgba(image: Image.Image) -> None:
    """Clear keyed green RGB before and after thumbnail resampling.

    PNG stores RGB even where alpha is zero.  Leaving #00FF00 in those fully
    transparent pixels lets a subsequent Lanczos resize blend a green outline
    back into hair and shield edges.  Only transparent/key-fringe samples are
    touched; opaque teal armour remains untouched.
    """
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                pixels[x, y] = (0, 0, 0, 0)
            elif alpha < 255 and green >= 120 and green - red >= 30 and green - blue >= 30:
                pixels[x, y] = (red, min(green, max(red, blue) + 12), blue, alpha)


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
    # Re-running the Web bridge after a data-only change must not spend minutes
    # re-rotating an unchanged 80-frame candidate pack. The source asset ID and
    # output hashes still guard against accidentally sharing a different entity's
    # pack.
    cached_manifest_path = target_root / "animation_manifest.json"
    if cached_manifest_path.is_file():
        cached = load_json(cached_manifest_path)
        preview_path = target_root / str(cached.get("preview_path", "preview.png"))
        atlas_path = target_root / str(cached.get("atlas_path", "atlas.png"))
        if str(cached.get("source_asset_id", "")) == str(definition["asset_id"]) and preview_path.is_file() and atlas_path.is_file() and sha256(preview_path) == str(cached.get("preview_sha256", "")) and sha256(atlas_path) == str(cached.get("sha256", "")):
            return {"entity_id": entity_id, "path": f"combat/{entity_id}/atlas.png", "preview_path": f"combat/{entity_id}/preview.png", "frames": int(cached.get("total_frames", 0)), "sha256": str(cached["sha256"]), "preview_sha256": str(cached["preview_sha256"]), "status": str(cached.get("status", "")), "source_status": str(cached.get("source_status", "")), "source_asset_id": str(cached.get("source_asset_id", "")), "ownership_status": str(cached.get("ownership_status", "ORIGINAL_INTERNAL")), "license": str(cached.get("license", "USER_AUTHORIZED_INTERNAL_GENERATION"))}
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
    preview_path = target_root / "preview.png"
    all_frames[0].resize((PREVIEW_CELL, PREVIEW_CELL), Image.Resampling.LANCZOS).save(preview_path, optimize=True)
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
        "status": definition.get("status", "IMAGEGEN_STATIC_ANIMATED_SOURCE"),
        "source_status": definition.get("source_status", "ORIGINAL_INTERNAL_GENERATED"),
        "source_root": str(source.relative_to(ROOT)).replace("\\", "/"),
        "source_asset_id": definition["asset_id"],
        "creation_method": definition.get("creation_method", "imagegen_original_render_plus_deterministic_presentation_motion"),
        "ownership_status": "ORIGINAL_INTERNAL",
        "license": "USER_AUTHORIZED_INTERNAL_GENERATION",
        "frame_size": [STATIC_CELL, STATIC_CELL],
        "foot_anchor": definition["foot_anchor"],
        "head_anchor": definition["head_anchor"],
        "view": definition["view"],
        "facing_policy": definition["facing"],
        "atlas_path": "atlas.png",
        "preview_path": "preview.png",
        "preview_sha256": sha256(preview_path),
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
    return {
        "entity_id": entity_id,
        "path": f"combat/{entity_id}/atlas.png",
        "preview_path": f"combat/{entity_id}/preview.png",
        "frames": len(all_frames),
        "sha256": manifest["sha256"],
        "preview_sha256": manifest["preview_sha256"],
        "status": manifest["status"],
        "source_status": manifest["source_status"],
        "source_asset_id": manifest["source_asset_id"],
        "ownership_status": manifest["ownership_status"],
        "license": manifest["license"],
    }


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
    if not ordered_frames:
        raise ValueError(f"{entity_id} has no authored runtime frames")
    if len(ordered_frames) > ATLAS_COLUMNS * 9:
        raise ValueError(f"{entity_id} has {len(ordered_frames)} frames; atlas capacity is 90")
    preview_path = target_root / "preview.png"
    image_cell(ordered_frames[0], PREVIEW_CELL).save(preview_path, optimize=True)
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
        # Runtime manifests carry only stable logical lineage. Absolute Blender
        # source paths remain in internal review manifests and must never leak
        # into a browser PCK.
        "ownership_status": source_manifest.get("ownership_status", "PROJECT_DEV_GENERATED"),
        "frame_size": [CELL, CELL],
        "foot_anchor": source_manifest.get("foot_anchor", [0.5, 0.88]),
        "head_anchor": source_manifest.get("head_anchor", [0.5, 0.12]),
        "view": source_manifest.get("view", "THREE_QUARTER_RIGHT_DOWN_30"),
        "facing_policy": source_manifest.get("facing_policy", "SEPARATE_LEFT_RIGHT"),
        "atlas_path": "atlas.png",
        "preview_path": "preview.png",
        "preview_sha256": sha256(preview_path),
        "atlas_columns": ATLAS_COLUMNS,
        "total_frames": len(ordered_frames),
        "animations": animations,
        "sha256": sha256(atlas_path),
    }
    (target_root / "animation_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"RUNTIME_COMBAT={entity_id}|frames={len(ordered_frames)}|bytes={atlas_path.stat().st_size}")
    return {
        "entity_id": entity_id,
        "path": f"combat/{entity_id}/atlas.png",
        "preview_path": f"combat/{entity_id}/preview.png",
        "frames": len(ordered_frames),
        "sha256": manifest["sha256"],
        "preview_sha256": manifest["preview_sha256"],
        "status": manifest["status"],
        "source_status": manifest["source_status"],
        "source_asset_id": manifest["source_asset_id"],
        "ownership_status": manifest["ownership_status"] or "PROJECT_DEV_GENERATED",
        "license": source_manifest.get("license", "PROJECT_INTERNAL_REVIEW_REQUIRED"),
    }


def _write_card_green_matte(entity_id: str, source_image: Image.Image) -> Path:
    """Record the exact flat #00FF00 card authoring matte without shipping it."""
    provenance_root = CARD_MATTE_ROOT / "provenance"
    provenance_root.mkdir(parents=True, exist_ok=True)
    matte = Image.new("RGBA", source_image.size, CARD_MATTE_RGB + (255,))
    matte.alpha_composite(source_image)
    path = provenance_root / f"{entity_id.lower()}_8head_card_r1_green_matte.png"
    matte.convert("RGB").save(path, optimize=True)
    return path


def _card_alpha_record(image: Image.Image) -> dict:
    alpha = image.getchannel("A")
    extrema = alpha.getextrema()
    bbox = alpha.getbbox()
    if extrema != (0, 255) or bbox is None:
        raise ValueError(f"8-head card RGBA validation failed: extrema={extrema}, bbox={bbox}")
    left, top, right, bottom = bbox
    margins = [left, top, image.width - right, image.height - bottom]
    if min(margins) < 16:
        raise ValueError(f"8-head card safe inset failed: margins={margins}")
    return {"alphaExtrema": list(extrema), "alphaBbox": [left, top, right, bottom], "safeInsets": margins}


def build_character_8head_card_art(sources: dict[str, dict]) -> list[dict]:
    """Build the 44-character non-combat 8-head card family.

    This function is deliberately forbidden from reading the SD combat/map
    authorities.  Each output is a true-alpha derivative of either an approved
    transparent 8-head authority or an approved #00FF00 8-head matte source.
    """
    entries: list[dict] = []
    contracts: dict[str, dict] = {}
    for entity_id, definition in sources.items():
        if not entity_id.startswith("CHR"):
            continue
        source = Path(definition["source"])
        if not source.is_file():
            raise FileNotFoundError(f"{entity_id} character authority source missing: {source}")
        target_root = OUTPUT / "characters" / entity_id
        target_root.mkdir(parents=True, exist_ok=True)
        input_mode = str(definition.get("input_mode", ""))
        if input_mode == "KEY_GREEN_MATTE":
            source_image = _key_card_green_matte(source)
            green_matte_path = source
        elif input_mode == "RGBA_AUTHORITY":
            source_image = Image.open(source).convert("RGBA")
            green_matte_path = _write_card_green_matte(entity_id, source_image)
        else:
            raise ValueError(f"{entity_id} card authority has unknown input mode: {input_mode}")
        # Re-run the strict edge decontamination for *every* authority. Some
        # historical approved RGBA cards were derived from green sources before
        # this final pass existed; their authored pixels stay intact, while a
        # handful of translucent key-green edge samples cannot reach Web UI.
        _decontaminate_card_rgba(source_image)
        portrait = Image.new("RGBA", (512, 768), (0, 0, 0, 0))
        portrait_subject = source_image.copy()
        # A 22px side / 30px bottom target inset prevents any face, weapon,
        # hand or boot from being clipped by a story, roster or mobile frame.
        portrait_subject.thumbnail((468, 698), Image.Resampling.LANCZOS)
        _decontaminate_card_rgba(portrait_subject)
        portrait.alpha_composite(portrait_subject, ((512 - portrait_subject.width) // 2, 768 - portrait_subject.height - 30))
        _decontaminate_card_rgba(portrait)
        portrait_path = target_root / "portrait.png"
        portrait.save(portrait_path, optimize=True)
        portrait_record = _card_alpha_record(portrait)
        icon = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        icon_subject = source_image.copy()
        icon_subject.thumbnail((224, 224), Image.Resampling.LANCZOS)
        _decontaminate_card_rgba(icon_subject)
        icon.alpha_composite(icon_subject, ((256 - icon_subject.width) // 2, 256 - icon_subject.height - 16))
        _decontaminate_card_rgba(icon)
        icon_path = target_root / "icon.png"
        icon.save(icon_path, optimize=True)
        icon_record = _card_alpha_record(icon)
        costume_id = str(definition.get("costume_id", definition.get("asset_id", f"{entity_id}_CANONICAL_R1")))
        contracts[entity_id] = {
            "costumeId": costume_id,
            "authorityImage": str(source.relative_to(ROOT)).replace("\\", "/"),
            "authoritySha256": sha256(source),
            "greenMatte": str(green_matte_path.relative_to(ROOT)).replace("\\", "/"),
            "greenMatteSha256": sha256(green_matte_path),
            "runtimePortrait": str(portrait_path.relative_to(ROOT)).replace("\\", "/"),
            "runtimePortraitSha256": sha256(portrait_path),
            "runtimeIcon": str(icon_path.relative_to(ROOT)).replace("\\", "/"),
            "runtimeIconSha256": sha256(icon_path),
            "fingerprint": {"identity": "authority-preserved", "costume": "unchanged", "presentation": str(definition.get("presentation", "PREMIUM_8_HEAD_FULL_BODY_CARD")), "weaponGrip": "authority-preserved", "background": "#00FF00 intermediate → RGBA runtime"},
            "portrait": portrait_record,
            "icon": icon_record,
            "status": "COSTUME_CONTINUITY_PASS",
        }
        common = {
            "status": "RUNTIME_WEB_GREEN_MATTE_RGBA",
            "category": "character_8head_card_art",
            "entity_id": entity_id,
            "source": f"green_matte_8head_card_derivative:{entity_id}",
            "source_asset_id": costume_id,
            "source_status": str(definition.get("source_status", "COSTUME_CONTINUITY_PASS")),
            "ownership_status": "ORIGINAL_INTERNAL",
            "license": "USER_AUTHORIZED_INTERNAL_GENERATION",
            "qa_status": "8HEAD_CARD_CONTINUITY_PASS_RGBA_SEPARATION_VALIDATED",
            "production_approved": False,
        }
        entries.extend([
            {**common, "asset_id": f"portrait_{entity_id.lower()}_dev", "godot_path": f"res://assets/runtime_web/characters/{entity_id}/portrait.png", "sha256": sha256(portrait_path), "width": 512, "height": 768},
            {**common, "asset_id": f"icon_{entity_id.lower()}_dev", "godot_path": f"res://assets/runtime_web/characters/{entity_id}/icon.png", "sha256": sha256(icon_path), "width": 256, "height": 256},
        ])
        print(f"RUNTIME_8HEAD_CARD_ART={entity_id}|portrait={portrait_path.stat().st_size}|icon={icon_path.stat().st_size}")
    contract_payload = {
        "schemaVersion": 1,
        "generationMatte": "#00FF00",
        "runtimeBackground": "RGBA_TRANSPARENT",
        "characters": contracts,
    }
    contract_text = json.dumps(contract_payload, ensure_ascii=False, indent=2) + "\n"
    contract_path = CARD_MATTE_ROOT / "qa" / "CARD_8HEAD_RGBA_R1_CONTRACT.json"
    contract_path.parent.mkdir(parents=True, exist_ok=True)
    contract_path.write_text(contract_text, encoding="utf-8")
    # Keep the same compact contract beside the PCK-ready portraits so release
    # regression tests verify what the player build actually references.
    runtime_contract_path = OUTPUT / "characters" / "CARD_8HEAD_RGBA_R1_CONTRACT.json"
    runtime_contract_path.write_text(contract_text, encoding="utf-8")
    print(f"CARD_8HEAD_RGBA_R1={len(contracts)}|contract={contract_path}|runtime_contract={runtime_contract_path}")
    return entries


def update_runtime_asset_manifest(combat: list[dict], character_art: list[dict]) -> None:
    """Map immutable CharacterDef/EnemyDef asset IDs to connected previews.

    Existing portrait and icon entries are preserved at the object level.
    Stale preview rows are removed before rebuilding so repeated runs remain
    idempotent. Only stable project-relative runtime paths and logical source
    IDs are emitted; authoring workstation paths stay out of the browser
    manifest.
    """
    game_data = load_json(GODOT / "data" / "compiled" / "game_data.json")
    data_rows = list(game_data.get("characters", [])) + list(game_data.get("enemies", []))
    expected_by_entity = {str(row.get("id", "")): str(row.get("asset_id", "")) for row in data_rows}
    if "" in expected_by_entity or "" in expected_by_entity.values():
        raise ValueError(f"Invalid immutable combat asset IDs, found {len(expected_by_entity)} entities")
    combat_by_entity = {str(row["entity_id"]): row for row in combat}
    if set(combat_by_entity) != set(expected_by_entity):
        missing = sorted(set(expected_by_entity) - set(combat_by_entity))
        extra = sorted(set(combat_by_entity) - set(expected_by_entity))
        raise ValueError(f"Combat preview coverage mismatch; missing={missing} extra={extra}")

    manifest_path = OUTPUT / "runtime_asset_manifest.json"
    current = load_json(manifest_path) if manifest_path.is_file() else {"schema_version": 1, "assets": []}
    expected_asset_ids = set(expected_by_entity.values())
    character_art_ids = {str(entry["asset_id"]) for entry in character_art}
    preserved = [
        entry for entry in current.get("assets", [])
        if str(entry.get("asset_id", "")) not in expected_asset_ids
        and str(entry.get("asset_id", "")) not in character_art_ids
        and str(entry.get("category", "")) != "combat_preview"
        and str(entry.get("status", "")) != "RUNTIME_WEB_COMBAT_PREVIEW"
    ]
    previews: list[dict] = []
    for row in data_rows:
        entity_id = str(row["id"])
        pack = combat_by_entity[entity_id]
        relative_preview = str(pack["preview_path"])
        preview_file = OUTPUT / relative_preview
        if not preview_file.is_file() or sha256(preview_file) != str(pack["preview_sha256"]):
            raise ValueError(f"Combat preview integrity failed: {entity_id}")
        previews.append({
            "asset_id": str(row["asset_id"]),
            "godot_path": f"res://assets/runtime_web/{relative_preview}",
            "status": "RUNTIME_WEB_COMBAT_PREVIEW",
            "category": "combat_preview",
            "entity_id": entity_id,
            "source": f"runtime_combat_pack:{entity_id}",
            "source_asset_id": str(pack.get("source_asset_id", "")),
            "source_status": str(pack.get("source_status", "UNVERIFIED_SOURCE_STATUS")),
            "ownership_status": str(pack.get("ownership_status", "PROJECT_DEV_GENERATED")),
            "license": str(pack.get("license", "PROJECT_INTERNAL_REVIEW_REQUIRED")),
            "qa_status": "RUNTIME_CONNECTED_NOT_PRODUCTION_APPROVED",
            "production_approved": False,
            "sha256": str(pack["preview_sha256"]),
        })
    output_manifest = {
        "schema_version": max(1, int(current.get("schema_version", 1))),
        "assets": preserved + previews + character_art,
    }
    manifest_path.write_text(json.dumps(output_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"RUNTIME_ASSET_PREVIEWS={len(previews)}|character_art={len(character_art)}|preserved={len(preserved)}|manifest={manifest_path}")


def build_story_plates() -> list[dict]:
    """Build compact immutable CG derivatives for the browser story runtime."""
    prepare_output(STORY_OUTPUT)
    plates: list[dict] = []
    for asset_id, definition in STORY_PLATES.items():
        source: Path = definition["source"]
        if not source.is_file():
            raise FileNotFoundError(f"Story plate source missing: {source}")
        output_path = STORY_OUTPUT / str(definition["filename"])
        image = Image.open(source).convert("RGBA")
        if image.size != tuple(definition["size"]):
            image = image.resize(tuple(definition["size"]), Image.Resampling.LANCZOS)
        image.save(output_path, optimize=True)
        plates.append({
            "asset_id": asset_id,
            "godot_path": f"res://assets/runtime_web/story/{output_path.name}",
            "status": "RUNTIME_WEB_STORY_PLATE",
            "category": "story_plate",
            "source": "offline compact derivative of the authored Chapter 1 CG",
            "source_asset_id": asset_id,
            "ownership_status": definition["ownership_status"],
            "license": definition["license"],
            "sha256": sha256(output_path),
            "width": image.width,
            "height": image.height,
        })
        print(f"RUNTIME_STORY={asset_id}|bytes={output_path.stat().st_size}")
    return plates


def update_runtime_story_manifest(plates: list[dict]) -> None:
    """Override only the immutable story IDs that have runtime derivatives."""
    manifest_path = OUTPUT / "runtime_asset_manifest.json"
    current = load_json(manifest_path) if manifest_path.is_file() else {"schema_version": 1, "assets": []}
    plate_ids = {str(plate["asset_id"]) for plate in plates}
    preserved = [
        entry for entry in current.get("assets", [])
        if str(entry.get("asset_id", "")) not in plate_ids
    ]
    manifest_path.write_text(
        json.dumps({"schema_version": 1, "assets": preserved + plates}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"RUNTIME_STORY_MANIFEST={len(plates)}|manifest={manifest_path}")


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


def _point(cx: float, cy: float, radius: float, angle: float) -> tuple[float, float]:
    return cx + math.cos(angle) * radius, cy + math.sin(angle) * radius


def _polygon_ring(cx: float, cy: float, radius: float, count: int, rotation: float = 0.0) -> list[tuple[float, float]]:
    return [_point(cx, cy, radius, rotation + math.tau * index / count) for index in range(count)]


def _vfx_cell(primary: tuple[int, int, int], secondary: tuple[int, int, int], kind: str, frame: int, shape: str) -> Image.Image:
    """Build a Web-sized signature layer with a concrete motion language.

    This is not a generic colour swap: each unit profile selects a distinct
    physical read (shield, rush, tracer, lightning, artillery, distortion,
    healing, etc.) while preserving the shared 12-frame charge/peak/fade
    rhythm.  The result remains a small transparent PNG and therefore works in
    a Compatibility Web build without shaders or a persistent particle node.
    """
    scale = 3
    size = VFX_CELL * scale
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    energy = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(energy)
    p = primary
    s = secondary
    white = (255, 255, 255)
    t = frame / 11.0
    phase = min(1.0, t * 1.72)
    peak = math.sin(min(1.0, t * 1.24) * math.pi)
    fade = 1.0 if frame <= 8 else max(0.18, 1.0 - (frame - 8) * 0.20)
    cx = cy = size * 0.5
    magnitude = (25 if kind == "basic" else 43 if kind == "normal" else 62) * scale
    radius = magnitude * (0.32 + 0.68 * peak)
    primary_alpha = int(236 * fade)
    secondary_alpha = int(248 * fade)

    # Charge energy stays on the outer third so the actor/weapon remains the
    # focal point.  Basic attacks keep a compact arc; skills use offset edge
    # rails instead of the old universal concentric-ring grammar.
    if kind == "basic":
        ring = radius * (0.55 + phase * 0.55)
        draw.arc((cx-ring, cy-ring, cx+ring, cy+ring), int(t * 410), int(t * 410 + 148), fill=p + (int(154 * fade),), width=2 * scale)
    else:
        edge = radius * (1.02 + .16 * phase)
        for start in (22 + int(t * 170), 202 + int(t * 170)):
            draw.arc((cx-edge, cy-edge, cx+edge, cy+edge), start, start + 54, fill=p + (int(138 * fade),), width=2 * scale)
    if frame <= 2:
        draw.ellipse((cx-radius*.18, cy-radius*.18, cx+radius*.18, cy+radius*.18), fill=s + (int(126 * fade),))

    if shape == "shield":
        hexagon = _polygon_ring(cx, cy, radius * 0.92, 6, -math.pi / 2 + t * .55)
        draw.line(hexagon + [hexagon[0]], fill=p + (primary_alpha,), width=3 * scale, joint="curve")
        inner = _polygon_ring(cx, cy, radius * 0.54, 6, math.pi / 6 - t * .95)
        draw.line(inner + [inner[0]], fill=s + (secondary_alpha,), width=2 * scale, joint="curve")
        for index, point in enumerate(hexagon):
            panel = radius * (.10 + .04 * math.sin(t * math.tau + index))
            draw.ellipse((point[0]-panel, point[1]-panel, point[0]+panel, point[1]+panel), fill=s + (int(210 * fade),))
    elif shape in ("rush", "flame", "flame_split"):
        angle = -0.52
        for index in range(5 if kind == "ultimate" else 3):
            lateral = (index - 2) * 8 * scale
            start = (cx - radius * 1.34 + lateral * .2, cy + radius * .76 + lateral)
            end = (cx + radius * 1.26 + lateral * .1, cy - radius * .70 + lateral)
            draw.line((start, end), fill=p + (int((220 - index * 20) * fade),), width=max(scale, (5 - index) * scale), joint="curve")
        if shape in ("flame", "flame_split"):
            for index in range(7):
                angle = -math.pi * .72 + index * math.pi / 6.0
                tip = _point(cx, cy, radius * (1.0 + .18 * math.sin(t * 8 + index)), angle)
                base_a = _point(cx, cy, radius * .22, angle - .18)
                base_b = _point(cx, cy, radius * .22, angle + .18)
                draw.polygon([base_a, tip, base_b], fill=(255, 101 + index * 9, 38) + (int(204 * fade),))
        draw.polygon([_point(cx, cy, radius * .78, angle), _point(cx, cy, radius * .22, angle + 1.25), _point(cx, cy, radius * .22, angle - 1.25)], fill=s + (secondary_alpha,))
        if shape == "flame_split":
            draw.polygon([_point(cx, cy, radius * .94, angle-.22), _point(cx, cy, radius * .34, angle+.78), _point(cx, cy, radius * .28, angle-.95)], fill=p + (int(185*fade),))
            draw.polygon([_point(cx, cy, radius * .94, angle+.22), _point(cx, cy, radius * .28, angle+.95), _point(cx, cy, radius * .34, angle-.78)], fill=s + (int(165*fade),))
    elif shape == "tracer":
        reticle = radius * .46
        draw.ellipse((cx-reticle, cy-reticle, cx+reticle, cy+reticle), outline=s + (secondary_alpha,), width=2 * scale)
        for offset in (-.23, 0.0, .23):
            y = cy + radius * offset
            draw.line((cx-radius*1.35, y, cx+radius*1.5, y-radius*.14), fill=p + (int((220 - abs(offset)*80) * fade),), width=2 * scale)
        draw.ellipse((cx-radius*.12, cy-radius*.12, cx+radius*.12, cy+radius*.12), fill=white + (int(235 * fade),))
    elif shape == "lightning":
        branches = 5 if kind == "ultimate" else 3
        for branch in range(branches):
            angle = -math.pi / 2 + (branch - (branches - 1) * .5) * .47
            points = [(cx, cy)]
            for step in range(1, 6):
                local_angle = angle + math.sin((frame + branch * 3 + step) * 1.7) * .22
                points.append(_point(cx, cy, radius * step / 5.0, local_angle))
            draw.line(points, fill=p + (primary_alpha,), width=3 * scale, joint="curve")
            draw.line(points, fill=white + (int(185 * fade),), width=scale, joint="curve")
        draw.ellipse((cx-radius*.18, cy-radius*.18, cx+radius*.18, cy+radius*.18), fill=s + (int(210 * fade),))
    elif shape == "artillery":
        volleys = 7 if kind == "ultimate" else 4
        for index in range(volleys):
            angle = -2.35 + index * 4.7 / max(1, volleys - 1)
            start = _point(cx, cy + radius*.22, radius*.16, angle)
            end = _point(cx, cy - radius*.12, radius*(.72 + .24*math.sin(t*math.pi)), angle)
            control = ((start[0]+end[0])*.5, min(start[1], end[1]) - radius*.48)
            trail = [start, ((start[0]+control[0])*.5, (start[1]+control[1])*.5), control, ((control[0]+end[0])*.5, (control[1]+end[1])*.5), end]
            draw.line(trail, fill=p + (int(210 * fade),), width=2 * scale, joint="curve")
            orb = radius * .095
            draw.ellipse((end[0]-orb, end[1]-orb, end[0]+orb, end[1]+orb), fill=s + (secondary_alpha,))
        draw.ellipse((cx-radius*.22, cy-radius*.22, cx+radius*.22, cy+radius*.22), fill=white + (int(180 * fade),))
    elif shape in ("lockon", "orbital_scan"):
        # BOSS003: offset orbital nodes and four segmented lock brackets.  The
        # central lens/core stays clear even at overload peak.
        bracket = radius * (.62 + .10 * math.sin(t * math.pi))
        arm = radius * .24
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            corner_x, corner_y = cx + sx * bracket, cy + sy * bracket
            draw.line((corner_x, corner_y, corner_x - sx * arm, corner_y), fill=s + (secondary_alpha,), width=3 * scale)
            draw.line((corner_x, corner_y, corner_x, corner_y - sy * arm), fill=p + (primary_alpha,), width=3 * scale)
        nodes = 6 if kind == "ultimate" else 4
        for index in range(nodes):
            angle = -t * 4.8 + index * math.tau / nodes
            orbit_radius = radius * (.88 + .10 * math.sin(index * 1.9 + t * 5.0))
            point = _point(cx, cy, orbit_radius, angle)
            node = radius * (.055 if kind == "ultimate" else .045)
            draw.ellipse((point[0]-node, point[1]-node, point[0]+node, point[1]+node), fill=white + (int(225 * fade),), outline=s + (secondary_alpha,), width=scale)
        if shape == "lockon" and frame >= 5:
            for angle in (0.0, math.pi / 2, math.pi, math.pi * 1.5):
                a = _point(cx, cy, radius * .34, angle)
                b = _point(cx, cy, radius * 1.20, angle)
                draw.line((a, b), fill=s + (int(190 * fade),), width=2 * scale)
    elif shape in ("implode", "resonance", "network", "gate_reverse"):
        if shape == "implode":
            for index in range(12):
                angle = index * math.tau / 12.0 + t * .45
                outer = _point(cx, cy, radius * (1.18 + .10 * math.sin(index)), angle)
                inner = _point(cx, cy, radius * (.46 + .06 * peak), angle + .10)
                draw.line((outer, inner), fill=(p if index % 2 else s) + (int((178 + index % 3 * 22) * fade),), width=(2 + index % 2) * scale)
        elif shape == "resonance":
            for index in range(9):
                angle = index * math.tau / 9.0 - t * 1.5
                point = _point(cx, cy, radius * (.72 + .18 * (index % 2)), angle)
                shard = radius * (.10 + .03 * (index % 3))
                tangent = angle + math.pi / 2
                draw.polygon([_point(point[0], point[1], shard, angle), _point(point[0], point[1], shard * .52, tangent), _point(point[0], point[1], shard, angle + math.pi), _point(point[0], point[1], shard * .52, tangent + math.pi)], fill=(p if index % 2 else s) + (int(205 * fade),))
            for offset in (-.18, .18):
                y = cy + radius * offset
                draw.arc((cx-radius*1.02, y-radius*.26, cx+radius*1.02, y+radius*.26), 195, 345, fill=white + (int(145 * fade),), width=2 * scale)
        elif shape == "gate_reverse":
            for side in (-1, 1):
                gx = cx + side * radius * .72
                half_h = radius * (.82 + .08 * peak)
                half_w = radius * .23
                color = p if side < 0 else s
                draw.line((gx-side*half_w, cy-half_h, gx+side*half_w, cy-half_h*.78, gx+side*half_w, cy+half_h*.78, gx-side*half_w, cy+half_h), fill=color + (int(225 * fade),), width=4 * scale, joint="curve")
                for index in range(4):
                    y = cy - half_h * .65 + index * half_h * .44
                    draw.line((gx, y, gx - side * radius * (.36 + index * .05), y + side * radius * .10), fill=white + (int(155 * fade),), width=scale)
        else:  # network
            points = [_point(cx, cy, radius * (.78 + .12 * (index % 2)), index * math.tau / 7.0 - t) for index in range(7)]
            for index, point in enumerate(points):
                next_point = points[(index + 2) % len(points)]
                draw.line((point, next_point), fill=(p if index % 2 else s) + (int(154 * fade),), width=2 * scale)
                node = radius * .065
                draw.ellipse((point[0]-node, point[1]-node, point[0]+node, point[1]+node), fill=white + (int(225 * fade),))
    elif shape in ("rush_cut", "glass_tracer", "barrier_fracture", "reverse_arc", "battery_barrage", "chorus_collapse"):
        if shape == "rush_cut":
            for index in range(4):
                y = cy + (index - 1.5) * radius * .26
                start = (cx + radius * 1.18, y - radius * .42)
                end = (cx - radius * 1.08, y + radius * .32)
                draw.line((start, end), fill=(p if index % 2 else s) + (int((224-index*22)*fade),), width=(4-index//2)*scale)
        elif shape == "glass_tracer":
            for offset in (-.36, -.12, .12, .36):
                y = cy + radius * offset
                draw.line((cx+radius*1.24, y-radius*.12, cx+radius*.32, y, cx-radius*1.18, y+radius*.16), fill=(p if offset < 0 else s) + (int(210*fade),), width=2*scale)
                shard = radius * .10
                draw.polygon([(cx-radius*.72, y-shard), (cx-radius*.48, y), (cx-radius*.72, y+shard)], fill=white + (int(155*fade),))
        elif shape == "barrier_fracture":
            panels = _polygon_ring(cx, cy, radius * .86, 6, -math.pi/2+t*.20)
            for index, point in enumerate(panels):
                next_point = panels[(index+1)%6]
                mid = ((point[0]+next_point[0])*.5, (point[1]+next_point[1])*.5)
                gap = radius * .08
                draw.line((point, _point(mid[0], mid[1], gap, math.atan2(point[1]-mid[1], point[0]-mid[0]))), fill=(p if index%2 else s)+(int(220*fade),), width=3*scale)
                draw.line((next_point, _point(mid[0], mid[1], gap, math.atan2(next_point[1]-mid[1], next_point[0]-mid[0]))), fill=(p if index%2 else s)+(int(220*fade),), width=3*scale)
        elif shape == "reverse_arc":
            for index in range(5):
                local = radius * (.54 + index * .13)
                start = int(205 - t*150 + index*22)
                draw.arc((cx-local, cy-local*.62, cx+local, cy+local*.62), start, start+105, fill=(p if index%2 else s)+(int((220-index*20)*fade),), width=(3 if index<2 else 2)*scale)
        elif shape == "battery_barrage":
            for index in range(8):
                angle = -2.70 + index * .78
                outer = _point(cx, cy, radius * 1.18, angle)
                inner = _point(cx, cy, radius * (.48 + .05*(index%3)), angle+.18)
                draw.line((outer, inner), fill=(p if index%2 else s)+(int(220*fade),), width=(4 if index%3==0 else 2)*scale)
                spark = radius*.055
                draw.ellipse((inner[0]-spark, inner[1]-spark, inner[0]+spark, inner[1]+spark), fill=white+(int(215*fade),))
        else:  # chorus_collapse
            for index in range(10):
                x = cx + (index-4.5)*radius*.18
                height = radius*(.50+.28*math.sin(index*1.7+t*6))
                draw.line((x, cy-height, x-radius*.08, cy-radius*.40), fill=(p if index%2 else s)+(int(205*fade),), width=2*scale)
                draw.line((x-radius*.08, cy-radius*.40, x+radius*.06, cy+height), fill=white+(int(120*fade),), width=scale)
    elif shape in ("plate_rupture", "barrier_mend", "harmonic_bars", "dust_shear", "ward_gate", "broadcast_glitch", "broadcast_tear", "iron_vibration", "slab_resonance"):
        if shape == "plate_rupture":
            # Three offset armor slabs split away from a clear central lane.
            for index, angle in enumerate((-.72, .04, .78)):
                point = _point(cx, cy, radius * .72, angle + t * .12)
                w, h = radius * .24, radius * .40
                draw.polygon([(point[0]-w, point[1]-h), (point[0]+w*.82, point[1]-h*.72), (point[0]+w, point[1]+h), (point[0]-w*.72, point[1]+h*.62)], fill=(p if index%2 else s)+(int(188*fade),), outline=white+(int(135*fade),))
                draw.line((point, _point(cx, cy, radius*1.08, angle)), fill=white+(int(170*fade),), width=scale)
        elif shape == "barrier_mend":
            # Three curved bands rise from different perimeter anchors.
            for index in range(3):
                local = radius * (.56 + index*.18)
                y = cy + radius*.32 - index*radius*.22 - t*radius*.18
                draw.arc((cx-local, y-local*.46, cx+local, y+local*.46), 202+index*18, 338+index*18, fill=(p if index%2==0 else s)+(int((215-index*28)*fade),), width=(4-index)*scale)
                anchor = _point(cx, cy, radius*.84, -2.5+index*2.4)
                draw.ellipse((anchor[0]-3*scale,anchor[1]-3*scale,anchor[0]+3*scale,anchor[1]+3*scale),fill=white+(int(210*fade),))
        elif shape == "harmonic_bars":
            for index in range(9):
                x = cx + (index-4)*radius*.20
                h = radius*(.28+.52*(.5+.5*math.sin(index*1.7+t*7.0)))
                draw.line((x,cy-h,x-radius*.06,cy-radius*.34),fill=(p if index%2 else s)+(int(218*fade),),width=(3 if index in (2,5,7) else 2)*scale)
                draw.line((x-radius*.06,cy-radius*.34,x+radius*.08,cy+h),fill=white+(int(118*fade),),width=scale)
        elif shape == "dust_shear":
            for index, angle in enumerate((-.66,-.08,.52)):
                nx, ny = math.cos(angle), math.sin(angle)
                tx, ty = -ny, nx
                center_x = cx + tx * (index - 1) * radius * .22
                center_y = cy + ty * (index - 1) * radius * .22
                draw.line((center_x-nx*radius*1.16, center_y-ny*radius*1.16, center_x+nx*radius*1.16, center_y+ny*radius*1.16),fill=(p if index!=1 else s)+(int((184-index*18)*fade),),width=(5-index)*scale)
                for mote_index in range(4):
                    pct = -.7 + mote_index * .43
                    jitter = radius * .10 * math.sin(frame + mote_index)
                    mote_x = center_x + nx * radius * pct + tx * jitter
                    mote_y = center_y + ny * radius * pct + ty * jitter
                    draw.ellipse((mote_x-2*scale,mote_y-2*scale,mote_x+2*scale,mote_y+2*scale),fill=p+(int(105*fade),))
        elif shape == "ward_gate":
            for index, angle in enumerate((-2.5,-.55,1.48)):
                point=_point(cx,cy,radius*.78,angle+t*.28)
                shard=radius*(.18+.03*index)
                draw.polygon([_point(point[0],point[1],shard,angle),_point(point[0],point[1],shard*.72,angle+2.05),_point(point[0],point[1],shard*.58,angle-2.05)],fill=(p if index%2 else s)+(int(220*fade),))
                draw.line((point,_point(cx,cy,radius*.42,angle)),fill=white+(int(150*fade),),width=scale)
        elif shape in ("broadcast_glitch", "broadcast_tear"):
            planes = 6 if shape == "broadcast_tear" else 3
            for index in range(planes):
                y=cy+(index-(planes-1)*.5)*radius*(.28 if planes>3 else .38)
                shift=radius*.15*math.sin(frame*1.9+index)
                left=cx-radius*(1.08-.06*(index%2))+shift
                right=cx+radius*(1.02-.08*((index+1)%2))+shift
                height=radius*(.09+.025*(index%3))
                draw.polygon([(left,y-height),(right,y-height*.36),(right-radius*.18,y+height),(left+radius*.12,y+height*.44)],fill=(p if index%2 else s)+(int((194-index*9)*fade),))
                draw.line((left,y,right,y),fill=white+(int(126*fade),),width=scale)
        elif shape == "iron_vibration":
            for index in range(7):
                x=cx+(index-3)*radius*.22
                h=radius*(.44+.16*math.sin(t*9+index))
                draw.line((x,cy-h,x,cy+h),fill=(p if index%2 else s)+(int(190*fade),),width=(2+index%2)*scale)
        else:  # slab_resonance
            for index, xoff in enumerate((-.62,0.0,.62)):
                x=cx+radius*xoff
                w=radius*.24
                h=radius*(.68+.12*math.sin(t*7+index))
                draw.polygon([(x-w,cy-h),(x+w*.72,cy-h*.88),(x+w,cy+h),(x-w*.78,cy+h*.82)],fill=(p if index%2 else s)+(int(182*fade),),outline=white+(int(145*fade),))
                for crack in (-.22,.18):
                    draw.line((x,cy-h*.70,x+radius*crack,cy+h*.62),fill=white+(int(155*fade),),width=scale)
    elif shape in ("distort", "dust", "void"):
        turns = 2.3 if shape == "void" else 1.5
        for index in range(5 if kind == "ultimate" else 3):
            points = []
            for step in range(18):
                pct = step / 17.0
                local_radius = radius * (0.16 + pct * (0.95 - index * .09))
                angle = t * 8.0 + index * math.tau / 5.0 + pct * math.tau * turns
                points.append(_point(cx, cy, local_radius, angle))
            color = p if index % 2 == 0 else s
            draw.line(points, fill=color + (int((210 - index * 24) * fade),), width=(3 if index == 0 else 2) * scale, joint="curve")
        if shape == "dust":
            for index in range(12):
                angle = t * 4 + index * math.tau / 12.0
                point = _point(cx, cy, radius*(.38 + .48*((index%3)/2)), angle)
                mote = (2 + index % 3) * scale
                draw.ellipse((point[0]-mote, point[1]-mote, point[0]+mote, point[1]+mote), fill=p + (int(112 * fade),))
        if shape == "void":
            draw.ellipse((cx-radius*.28, cy-radius*.28, cx+radius*.28, cy+radius*.28), fill=(12, 18, 44, int(218 * fade)))
            draw.ellipse((cx-radius*.12, cy-radius*.12, cx+radius*.12, cy+radius*.12), fill=white + (int(165 * fade),))
    elif shape == "heal":
        for index in range(3):
            local_radius = radius * (.42 + index * .23)
            y = cy + radius*.30 - index * radius*.23 - t * radius*.24
            draw.arc((cx-local_radius, y-local_radius*.45, cx+local_radius, y+local_radius*.45), int(190+t*150), int(350+t*150), fill=p + (int((218-index*30)*fade),), width=3*scale)
        for index in range(8):
            angle = t * 4 + index * math.tau / 8.0
            point = _point(cx, cy-radius*.10, radius*.62, angle)
            petal = radius*.10
            draw.ellipse((point[0]-petal, point[1]-petal*.55, point[0]+petal, point[1]+petal*.55), fill=s + (int(200*fade),))
        draw.ellipse((cx-radius*.18, cy-radius*.18, cx+radius*.18, cy+radius*.18), fill=white + (int(215*fade),))
    elif shape == "heavy":
        for index in range(6):
            angle = t*.7 + index*math.tau/6.0
            point = _point(cx, cy, radius*.70, angle)
            width = radius*.22
            draw.rounded_rectangle((point[0]-width, point[1]-width*.44, point[0]+width, point[1]+width*.44), radius=3*scale, fill=p + (int((174+index*8)*fade),), outline=s + (secondary_alpha,), width=scale)
        draw.line((cx-radius*1.12, cy, cx+radius*1.12, cy), fill=s + (secondary_alpha,), width=4*scale)
        draw.ellipse((cx-radius*.20, cy-radius*.20, cx+radius*.20, cy+radius*.20), fill=white + (int(178*fade),))
    elif shape == "chorus":
        rings = 4 if kind == "ultimate" else 3
        for index in range(rings):
            local_radius = radius*(.34+index*.23)
            draw.arc((cx-local_radius, cy-local_radius, cx+local_radius, cy+local_radius), int(t*360+index*70), int(t*360+index*70+210), fill=(p if index%2==0 else s) + (int((224-index*22)*fade),), width=(3 if index==0 else 2)*scale)
        for index in range(10):
            point = _point(cx, cy, radius*.88, t*2+index*math.tau/10)
            shard = radius*.09
            draw.polygon([_point(point[0], point[1], shard, -math.pi/2), _point(point[0], point[1], shard*.55, .35), _point(point[0], point[1], shard*.55, math.pi-.35)], fill=s + (int(190*fade),))
    elif shape == "summon":
        gate = _polygon_ring(cx, cy, radius*.82, 5, -math.pi/2+t*.42)
        draw.line(gate+[gate[0]], fill=s + (secondary_alpha,), width=3*scale, joint="curve")
        for index in range(7):
            angle = -math.pi + index*math.pi/6.0
            base = _point(cx, cy+radius*.12, radius*.26, angle)
            tip = _point(cx, cy-radius*.12, radius*(.74+.16*math.sin(t*5+index)), angle)
            draw.line((base, tip), fill=p + (primary_alpha,), width=3*scale)
        draw.ellipse((cx-radius*.14, cy-radius*.14, cx+radius*.14, cy+radius*.14), fill=white + (int(214*fade),))
    else:
        for index in range(10):
            angle = -math.pi/2 + index*math.tau/10.0 + t*.38
            inner = _point(cx, cy, radius*.18, angle)
            outer = _point(cx, cy, radius*(.86+.18*peak), angle)
            draw.line((inner, outer), fill=p + (primary_alpha,), width=2*scale)
        draw.ellipse((cx-radius*.20, cy-radius*.20, cx+radius*.20, cy+radius*.20), fill=s + (secondary_alpha,))

    # White-hot peak remains an outer corona.  Never paint an opaque disc over
    # the actor/weapon or a boss's defining core silhouette.
    if 6 <= frame <= 8:
        for index in range(10):
            angle = index * math.tau / 10.0 + t
            draw.line((_point(cx, cy, radius*.58, angle), _point(cx, cy, radius*(1.05+.12*(index%2)), angle)), fill=(white if index%3==0 else s) + (int(180*fade),), width=(2 if index%3==0 else 1)*scale)
    glow = energy.filter(ImageFilter.GaussianBlur(7 * scale))
    near_glow = energy.filter(ImageFilter.GaussianBlur(2 * scale))
    image.alpha_composite(glow)
    image.alpha_composite(near_glow)
    image.alpha_composite(energy)
    return image.resize((VFX_CELL, VFX_CELL), Image.Resampling.LANCZOS)


def build_generated_vfx_pack(entity_id: str, profile: dict, kind: str) -> dict:
    folder = f"vfx_{entity_id.lower()}_{kind}"
    target_root = VFX_OUTPUT / folder
    manifest_path = target_root / "vfx_manifest.json"
    override_source = VFX_ATLAS_OVERRIDES.get((entity_id, kind))
    if override_source is not None:
        if not override_source.is_file():
            raise FileNotFoundError(f"approved VFX override missing: {override_source}")
        override = Image.open(override_source).convert("RGBA")
        if override.size != (VFX_CELL * 4, VFX_CELL * 3):
            raise ValueError(f"approved VFX override has wrong size: {override_source} {override.size}")
        prepare_output(target_root)
        atlas_path = target_root / "atlas.png"
        shutil.copy2(override_source, atlas_path)
        manifest = {
            "schema_version": 1,
            "style_revision": VFX_STYLE_REVISION,
            "asset_id": f"runtime_web_vfx_{entity_id.lower()}_{kind}",
            "entity_id": entity_id,
            "kind": kind,
            "status": "GPT_VFX_ATLAS_PASS_RUNTIME_AUTHORITY",
            "ownership_status": "ORIGINAL_INTERNAL",
            "creation_method": "imagegen_high_resolution_authority_alpha_clear_normalization",
            # Basic attacks intentionally inherit the unit's normal-skill
            # motion grammar; there is no separate `basic` profile key.
            "motion_shape": str(profile["normal"] if kind == "basic" else profile[kind]),
            "primary": "#%02x%02x%02x" % profile["primary"],
            "secondary": "#%02x%02x%02x" % profile["secondary"],
            # The premium authored atlas replaces the pixels, not the runtime
            # rendering tier: every per-unit ultimate remains a SIGNATURE
            # layer so the combat renderer and regression contract can treat
            # generated and art-authority effects uniformly.
            "layer": "SIGNATURE",
            "source": str(override_source.relative_to(ROOT)).replace("\\", "/"),
            "source_sha256": sha256(override_source),
            "frames": 12,
            "columns": 4,
            "sha256": sha256(atlas_path),
        }
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"RUNTIME_VFX_AUTHORITY={folder}|bytes={atlas_path.stat().st_size}")
        return {"folder": folder, "path": f"vfx/{folder}/atlas.png", "frames": 12, "columns": 4, "sha256": manifest["sha256"], "status": manifest["status"]}
    if manifest_path.is_file() and (target_root / "atlas.png").is_file():
        cached = load_json(manifest_path)
        if str(cached.get("style_revision", "")) == VFX_STYLE_REVISION and str(cached.get("entity_id", "")) == entity_id and str(cached.get("kind", "")) == kind and str(cached.get("primary", "")) == "#%02x%02x%02x" % profile["primary"] and str(cached.get("secondary", "")) == "#%02x%02x%02x" % profile["secondary"] and sha256(target_root / "atlas.png") == str(cached.get("sha256", "")):
            return {"folder": folder, "path": f"vfx/{folder}/atlas.png", "frames": 12, "columns": 4, "sha256": str(cached["sha256"]), "status": str(cached.get("status", ""))}
    prepare_output(target_root)
    atlas = Image.new("RGBA", (VFX_CELL * 4, VFX_CELL * 3), (0, 0, 0, 0))
    shape = str(profile["normal"] if kind == "basic" else profile[kind])
    for index in range(12):
        atlas.alpha_composite(_vfx_cell(profile["primary"], profile["secondary"], kind, index, shape), ((index % 4) * VFX_CELL, (index // 4) * VFX_CELL))
    atlas_path = target_root / "atlas.png"
    atlas.save(atlas_path, optimize=True)
    manifest = {
        "schema_version": 1,
        "style_revision": VFX_STYLE_REVISION,
        "asset_id": f"runtime_web_vfx_{entity_id.lower()}_{kind}",
        "entity_id": entity_id,
        "kind": kind,
        "status": "DRAFT_MOTION_BLOCKOUT_PENDING_ART_AUTHORITY",
        "ownership_status": "ORIGINAL_INTERNAL",
        "creation_method": "deterministic_motion_blockout_builder",
        "motion_shape": shape,
        "primary": "#%02x%02x%02x" % profile["primary"],
        "secondary": "#%02x%02x%02x" % profile["secondary"],
        "layer": "SIGNATURE",
        "frames": 12,
        "columns": 4,
        "sha256": sha256(atlas_path),
    }
    (target_root / "vfx_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"RUNTIME_VFX_GENERATED={folder}|bytes={atlas_path.stat().st_size}")
    return {"folder": folder, "path": f"vfx/{folder}/atlas.png", "frames": 12, "columns": 4, "sha256": manifest["sha256"], "status": manifest["status"]}


def main() -> int:
    COMBAT_OUTPUT.mkdir(parents=True, exist_ok=True)
    PROJECTILE_OUTPUT.mkdir(parents=True, exist_ok=True)
    VFX_OUTPUT.mkdir(parents=True, exist_ok=True)
    STORY_OUTPUT.mkdir(parents=True, exist_ok=True)
    apply_player_role_vfx_authorities()
    expansion_sources = expansion_static_sources()
    player_sd_overrides = player_sd_static_overrides()
    static_sources = {**STATIC_COMBAT_SOURCES, **player_sd_overrides, **expansion_sources}
    card_sources = card_8head_sources()
    combat = [build_combat_pack(entity_id, path) for entity_id, path in COMBAT_SOURCES.items() if entity_id not in player_sd_overrides]
    combat.extend(build_static_combat_pack(entity_id, definition) for entity_id, definition in static_sources.items())
    update_runtime_asset_manifest(combat, build_character_8head_card_art(card_sources))
    update_runtime_story_manifest(build_story_plates())
    profiles = complete_vfx_style_profiles()
    projectiles = [build_projectile_pack(source_id, path) for source_id, path in PROJECTILE_SOURCES.items()]
    for entity_id, profile in profiles.items():
        if entity_id not in PROJECTILE_SOURCES:
            projectiles.append(build_generated_projectile_pack(entity_id, profile))
    signature_folders = {f"vfx_{entity_id.lower()}_{kind}" for entity_id in profiles for kind in ("basic", "normal", "ultimate")}
    vfx = [build_vfx_pack(path) for path in sorted((GODOT / "assets" / "art" / "vfx").iterdir()) if path.is_dir() and path.name not in signature_folders]
    for entity_id, profile in profiles.items():
        for kind in ("basic", "normal", "ultimate"):
            vfx.append(build_generated_vfx_pack(entity_id, profile, kind))
    manifest = {"schema_version": 1, "combat": combat, "projectiles": projectiles, "vfx": vfx}
    (OUTPUT / "runtime_combat_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"RUNTIME_COMBAT_MANIFEST={OUTPUT / 'runtime_combat_manifest.json'}")
    return 0


def complete_vfx_style_profiles() -> dict[str, dict]:
    """Preserve reviewed profiles and derive a distinct signature for new IDs."""
    profiles = dict(VFX_STYLE_PROFILES)
    data = load_json(GODOT / "data" / "compiled" / "game_data.json")
    role_shapes = {"GUARDIAN": "shield", "VANGUARD": "rush", "ASSAULT": "tracer", "ARTILLERY": "artillery", "SPECIALIST": "distort", "MEDIC": "heal", "MELEE_RUSH": "flame", "RANGED": "tracer", "DEFENDER": "heavy", "HEALER": "heal", "BUFFER": "chorus", "DEBUFFER": "dust", "SUMMONER": "summon", "AREA": "lightning"}
    alternates = ["shield", "rush", "tracer", "lightning", "artillery", "distort", "heal", "chorus", "summon", "void", "heavy", "flame"]
    for row in list(data.get("characters", [])) + list(data.get("enemies", [])):
        entity_id = str(row.get("id", ""))
        if not entity_id or entity_id in profiles:
            continue
        seed = int.from_bytes(hashlib.sha256(entity_id.encode("utf-8")).digest()[:2], "big")
        primary = _stable_colour(entity_id, 31)
        secondary = _stable_colour(entity_id, 37, .98)
        normal_shape = role_shapes.get(str(row.get("role", "")), alternates[seed % len(alternates)])
        ultimate_shape = "void" if str(row.get("rank", "")) == "BOSS" else alternates[(seed // 7 + 3) % len(alternates)]
        profiles[entity_id] = {"primary": primary, "secondary": secondary, "normal": normal_shape, "ultimate": ultimate_shape}
    return profiles


def build_generated_projectile_pack(entity_id: str, profile: dict) -> dict:
    """Build an ID-specific eight-frame projectile without borrowing a pack."""
    target_root = PROJECTILE_OUTPUT / entity_id
    prepare_output(target_root)
    atlas = Image.new("RGBA", (PROJECTILE_CELL * 8, PROJECTILE_CELL), (0, 0, 0, 0))
    primary = tuple(profile["primary"])
    secondary = tuple(profile["secondary"])
    shape = str(profile["normal"])
    for frame in range(8):
        cell = Image.new("RGBA", (PROJECTILE_CELL, PROJECTILE_CELL), (0, 0, 0, 0))
        energy = Image.new("RGBA", cell.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(energy)
        progress = frame / 7.0
        cx = 28 + progress * 38
        cy = 49 + math.sin(progress * math.tau) * 5
        radius = 9 + (frame % 3) * 2
        draw.line((4, cy + 6, cx + radius * 1.2, cy - 4), fill=primary + (120,), width=5)
        if shape in ("tracer", "lightning", "artillery"):
            draw.polygon([(cx-radius, cy+radius*.5), (cx+radius*1.7, cy), (cx-radius, cy-radius*.5)], fill=secondary + (255,))
        elif shape in ("shield", "heal", "chorus"):
            draw.ellipse((cx-radius, cy-radius, cx+radius, cy+radius), outline=secondary + (255,), width=3)
            draw.ellipse((cx-radius*.42, cy-radius*.42, cx+radius*.42, cy+radius*.42), fill=primary + (230,))
        else:
            draw.polygon(_polygon_ring(cx, cy, radius, 5 + frame % 3, progress * math.tau), fill=primary + (240,), outline=secondary + (255,))
        cell.alpha_composite(energy.filter(ImageFilter.GaussianBlur(5)))
        cell.alpha_composite(energy)
        atlas.alpha_composite(cell, (frame * PROJECTILE_CELL, 0))
    atlas_path = target_root / "atlas.png"
    atlas.save(atlas_path, optimize=True)
    manifest = {
        "schema_version": 1, "asset_id": f"runtime_web_projectile_{entity_id.lower()}", "source_id": entity_id,
        "status": "ORIGINAL_INTERNAL_PROFILED_PROJECTILE", "source_asset_id": f"projectile_signature_{entity_id.lower()}",
        "frame_size": [PROJECTILE_CELL, PROJECTILE_CELL], "frames": 8, "atlas_path": "atlas.png", "atlas_columns": 8,
        "frame_indices": list(range(8)), "runtime_size": [82, 66], "flight_duration": .11 + (int.from_bytes(hashlib.sha256(entity_id.encode()).digest()[:1], "big") % 4) * .01,
        "ownership_status": "ORIGINAL_INTERNAL", "sha256": sha256(atlas_path),
    }
    (target_root / "projectile_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"RUNTIME_PROJECTILE_GENERATED={entity_id}|bytes={atlas_path.stat().st_size}")
    return {"source_id": entity_id, "path": f"projectiles/{entity_id}/atlas.png", "sha256": manifest["sha256"]}


if __name__ == "__main__":
    raise SystemExit(main())
