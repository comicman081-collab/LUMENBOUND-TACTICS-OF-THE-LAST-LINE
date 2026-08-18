# Visual QA Captures

Godot 4.7.1 Compatibility rendered these images at 1920×1080 using an offscreen Windows position, without foreground UI automation.

- `title.png`: PASS
- `home.png`: PASS
- `story.png`: PASS after wrap/layout correction
- `formation.png`: PASS
- `character_detail.png`: PASS, combined growth screen
- `skill_upgrade.png`: PASS, combined growth screen
- `weapon_upgrade.png`: PASS, combined growth screen
- `stage_select.png`: PASS
- `battle.png`: PASS, actual live simulation with female-only code-native DEV SD and nonhuman enemies
- `result.png`: PASS, actual deterministic battle result

Exact dimensions, byte sizes, and SHA-256 values are in `capture_manifest.json`.

This is source-project Windows visual QA. It does not upgrade DEV placeholders to final art, and it does not count as packaged-EXE or Android visual QA.
