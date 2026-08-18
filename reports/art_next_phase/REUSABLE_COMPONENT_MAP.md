# Reusable Component Map

| Component | Reuse |
|---|---|
| AssetPathResolver / manifest IDs | Legacy discovery and immutable runtime mapping |
| `premium_pipeline.py` | Character, SD, enemy, boss, background, CG and icon orchestration |
| `render_animation_frames.py` | Immutable 80-frame state output |
| `build_vfx.py` | Six 12-frame character VFX packs |
| `validate_render.py` | Canvas, alpha, crop, anchor and matte checks |
| `build_contact_sheet.py` | Pilot review sheets |
| `SYNC_ART_TO_GODOT.ps1` | Incremental SHA-sensitive runtime copy and manifest conversion |
| Existing bridge | 93 DEV files kept intact for non-pilot fallbacks |
